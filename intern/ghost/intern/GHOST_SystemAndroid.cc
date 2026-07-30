/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 */

#include "GHOST_SystemAndroid.hh"
#include "GHOST_WindowAndroid.hh"

#include "GHOST_Event.hh"
#include "GHOST_EventButton.hh"
#include "GHOST_EventCursor.hh"
#include "GHOST_EventKey.hh"
#include "GHOST_EventTrackpad.hh"
#include "GHOST_WindowManager.hh"

#include <android/input.h>
#include <android/keycodes.h>
#include <android/native_activity.h>
#include <android/native_window.h>
#include <android_native_app_glue.h>

#include <cmath>
#include <ctime>

static android_app *g_android_app = nullptr;

GHOST_SystemAndroid::GHOST_SystemAndroid()
    : app_(g_android_app),
      window_(nullptr),
      gesture_active_(false),
      gesture_prev_x_(0.0f),
      gesture_prev_y_(0.0f),
      gesture_prev_dist_(0.0f)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  start_time_ = uint64_t(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

GHOST_SystemAndroid::~GHOST_SystemAndroid() = default;

void GHOST_SystemAndroid::setAndroidApp(android_app *app)
{
  g_android_app = app;
}

GHOST_TSuccess GHOST_SystemAndroid::init()
{
  return GHOST_System::init();
}

uint64_t GHOST_SystemAndroid::getMilliSeconds() const
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  const uint64_t now = uint64_t(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
  return now - start_time_;
}

bool GHOST_SystemAndroid::processEvents(bool /*waitForEvent*/)
{
  /* Input arrives asynchronously via the glue calling handleInputEvent(). */
  return false;
}

uint8_t GHOST_SystemAndroid::getNumDisplays() const
{
  return 1;
}

void GHOST_SystemAndroid::getMainDisplayDimensions(uint32_t &width, uint32_t &height) const
{
  if (app_ && app_->window) {
    width = ANativeWindow_getWidth(app_->window);
    height = ANativeWindow_getHeight(app_->window);
  }
  else {
    width = height = 0;
  }
}

void GHOST_SystemAndroid::getAllDisplayDimensions(uint32_t &width, uint32_t &height) const
{
  getMainDisplayDimensions(width, height);
}

GHOST_IWindow *GHOST_SystemAndroid::createWindow(const char *title,
                                                 int32_t /*left*/,
                                                 int32_t /*top*/,
                                                 uint32_t width,
                                                 uint32_t height,
                                                 GHOST_TWindowState state,
                                                 GHOST_GPUSettings gpu_settings,
                                                 const bool /*exclusive*/,
                                                 const bool /*is_dialog*/,
                                                 const GHOST_IWindow * /*parent_window*/)
{
  if (!app_ || !app_->window) {
    return nullptr;
  }

  const GHOST_ContextParams context_params = GHOST_CONTEXT_PARAMS_FROM_GPU_SETTINGS(gpu_settings);

  GHOST_WindowAndroid *window = new GHOST_WindowAndroid(
      this, app_->window, title, width, height, state, gpu_settings.context_type, context_params);

  if (window->getValid()) {
    window_manager_->addWindow(window);
    window_manager_->setActiveWindow(window);
    window_ = window;
    pushEvent(std::make_unique<GHOST_Event>(getMilliSeconds(), GHOST_kEventWindowSize, window));
  }
  else {
    delete window;
    window = nullptr;
  }
  return window;
}

GHOST_IContext *GHOST_SystemAndroid::createOffscreenContext(GHOST_GPUSettings /*gpu_settings*/)
{
  return nullptr;
}

GHOST_TSuccess GHOST_SystemAndroid::disposeContext(GHOST_IContext *context)
{
  delete context;
  return GHOST_kSuccess;
}

void GHOST_SystemAndroid::handleNativeWindowInit(android_app *app)
{
  app_ = app;
  if (window_ && app->window) {
    window_->setNativeWindow(app->window);
  }
}

void GHOST_SystemAndroid::handleNativeWindowTerm()
{
  if (window_) {
    window_->setNativeWindow(nullptr);
  }
}

static GHOST_TabletData tablet_from_event(AInputEvent *event)
{
  GHOST_TabletData tablet = GHOST_TABLET_DATA_NONE;
  switch (AMotionEvent_getToolType(event, 0)) {
    case AMOTION_EVENT_TOOL_TYPE_STYLUS:
      tablet.Active = GHOST_kTabletModeStylus;
      break;
    case AMOTION_EVENT_TOOL_TYPE_ERASER:
      tablet.Active = GHOST_kTabletModeEraser;
      break;
    default:
      return tablet;
  }
  tablet.Pressure = AMotionEvent_getPressure(event, 0);
  const float tilt = AMotionEvent_getAxisValue(event, AMOTION_EVENT_AXIS_TILT, 0);
  const float orient = AMotionEvent_getAxisValue(event, AMOTION_EVENT_AXIS_ORIENTATION, 0);
  tablet.Xtilt = std::sin(orient) * (tilt / float(M_PI_2));
  tablet.Ytilt = -std::cos(orient) * (tilt / float(M_PI_2));
  return tablet;
}

int32_t GHOST_SystemAndroid::handleInputEvent(AInputEvent *event)
{
  if (!window_) {
    return 0;
  }
  switch (AInputEvent_getType(event)) {
    case AINPUT_EVENT_TYPE_KEY:
      return handleKeyEvent(event);
    case AINPUT_EVENT_TYPE_MOTION:
      return handleMotionEvent(event);
    default:
      return 0;
  }
}

int32_t GHOST_SystemAndroid::handleMotionEvent(AInputEvent *event)
{
  const int32_t action = AMotionEvent_getAction(event) & AMOTION_EVENT_ACTION_MASK;
  const size_t count = AMotionEvent_getPointerCount(event);

  /* Two fingers: pan -> scroll, distance change -> magnify. */
  if (count >= 2) {
    const float x0 = AMotionEvent_getX(event, 0), y0 = AMotionEvent_getY(event, 0);
    const float x1 = AMotionEvent_getX(event, 1), y1 = AMotionEvent_getY(event, 1);
    const float cx = (x0 + x1) * 0.5f, cy = (y0 + y1) * 0.5f;
    const float dist = std::hypot(x1 - x0, y1 - y0);

    if (gesture_active_) {
      pushEvent(std::make_unique<GHOST_EventTrackpad>(getMilliSeconds(),
                                                      window_,
                                                      GHOST_kTrackpadEventScroll,
                                                      int32_t(cx),
                                                      int32_t(cy),
                                                      int32_t(cx - gesture_prev_x_),
                                                      int32_t(cy - gesture_prev_y_),
                                                      false));
      pushEvent(std::make_unique<GHOST_EventTrackpad>(getMilliSeconds(),
                                                      window_,
                                                      GHOST_kTrackpadEventMagnify,
                                                      int32_t(cx),
                                                      int32_t(cy),
                                                      int32_t(dist - gesture_prev_dist_),
                                                      0,
                                                      false));
    }
    gesture_prev_x_ = cx;
    gesture_prev_y_ = cy;
    gesture_prev_dist_ = dist;
    gesture_active_ = true;
    return 1;
  }

  gesture_active_ = false;

  const GHOST_TabletData tablet = tablet_from_event(event);
  const int32_t x = int32_t(AMotionEvent_getX(event, 0));
  const int32_t y = int32_t(AMotionEvent_getY(event, 0));

  /* Stylus barrel button maps to right mouse (S Pen side button). */
  const bool secondary = (AMotionEvent_getButtonState(event) &
                          AMOTION_EVENT_BUTTON_STYLUS_PRIMARY) != 0;
  const GHOST_TButton button = secondary ? GHOST_kButtonMaskRight : GHOST_kButtonMaskLeft;

  pushEvent(std::make_unique<GHOST_EventCursor>(
      getMilliSeconds(), GHOST_kEventCursorMove, window_, x, y, tablet));

  switch (action) {
    case AMOTION_EVENT_ACTION_DOWN:
      pushEvent(std::make_unique<GHOST_EventButton>(
          getMilliSeconds(), GHOST_kEventButtonDown, window_, button, tablet));
      return 1;
    case AMOTION_EVENT_ACTION_UP:
    case AMOTION_EVENT_ACTION_CANCEL:
      pushEvent(std::make_unique<GHOST_EventButton>(
          getMilliSeconds(), GHOST_kEventButtonUp, window_, button, tablet));
      return 1;
    default:
      return 1;
  }
}

static GHOST_TKey convertAndroidKey(int32_t keycode)
{
  if (keycode >= AKEYCODE_A && keycode <= AKEYCODE_Z) {
    return GHOST_TKey(GHOST_kKeyA + (keycode - AKEYCODE_A));
  }
  if (keycode >= AKEYCODE_0 && keycode <= AKEYCODE_9) {
    return GHOST_TKey(GHOST_kKey0 + (keycode - AKEYCODE_0));
  }
  switch (keycode) {
    case AKEYCODE_SPACE:
      return GHOST_kKeySpace;
    case AKEYCODE_ENTER:
      return GHOST_kKeyEnter;
    case AKEYCODE_DEL:
      return GHOST_kKeyBackSpace;
    case AKEYCODE_FORWARD_DEL:
      return GHOST_kKeyDelete;
    case AKEYCODE_TAB:
      return GHOST_kKeyTab;
    case AKEYCODE_ESCAPE:
    case AKEYCODE_BACK:
      return GHOST_kKeyEsc;
    case AKEYCODE_DPAD_LEFT:
      return GHOST_kKeyLeftArrow;
    case AKEYCODE_DPAD_RIGHT:
      return GHOST_kKeyRightArrow;
    case AKEYCODE_DPAD_UP:
      return GHOST_kKeyUpArrow;
    case AKEYCODE_DPAD_DOWN:
      return GHOST_kKeyDownArrow;
    default:
      return GHOST_kKeyUnknown;
  }
}

int32_t GHOST_SystemAndroid::handleKeyEvent(AInputEvent *event)
{
  const GHOST_TKey key = convertAndroidKey(AKeyEvent_getKeyCode(event));
  if (key == GHOST_kKeyUnknown) {
    return 0;
  }
  const bool down = AKeyEvent_getAction(event) == AKEY_EVENT_ACTION_DOWN;
  const bool repeat = AKeyEvent_getRepeatCount(event) > 0;
  pushEvent(std::make_unique<GHOST_EventKey>(
      getMilliSeconds(), down ? GHOST_kEventKeyDown : GHOST_kEventKeyUp, window_, key, repeat));
  return 1;
}

GHOST_TSuccess GHOST_SystemAndroid::getModifierKeys(GHOST_ModifierKeys & /*keys*/) const
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemAndroid::getButtons(GHOST_Buttons & /*buttons*/) const
{
  return GHOST_kSuccess;
}

GHOST_TCapabilityFlag GHOST_SystemAndroid::getCapabilities() const
{
  return GHOST_TCapabilityFlag(GHOST_CAPABILITY_FLAG_ALL &
                               ~(GHOST_kCapabilityCursorWarp | GHOST_kCapabilityWindowPosition |
                                 GHOST_kCapabilityCursorRGBA | GHOST_kCapabilityClipboardImage));
}

char *GHOST_SystemAndroid::getClipboard(bool /*selection*/) const
{
  return nullptr;
}

void GHOST_SystemAndroid::putClipboard(const char * /*buffer*/, bool /*selection*/) const {}

GHOST_TSuccess GHOST_SystemAndroid::getCursorPosition(int32_t & /*x*/, int32_t & /*y*/) const
{
  return GHOST_kFailure;
}

GHOST_TSuccess GHOST_SystemAndroid::setCursorPosition(int32_t /*x*/, int32_t /*y*/)
{
  return GHOST_kFailure;
}

uint16_t GHOST_SystemAndroid::getDPIHint()
{
  /* TODO: query AConfiguration_getDensity via the glue's config. */
  return 288;
}

void GHOST_SystemAndroid::showSoftKeyboard()
{
  if (app_ && app_->activity) {
    ANativeActivity_showSoftInput(app_->activity, ANATIVEACTIVITY_SHOW_SOFT_INPUT_IMPLICIT);
  }
}

void GHOST_SystemAndroid::hideSoftKeyboard()
{
  if (app_ && app_->activity) {
    ANativeActivity_hideSoftInput(app_->activity, ANATIVEACTIVITY_HIDE_SOFT_INPUT_IMPLICIT_ONLY);
  }
}
