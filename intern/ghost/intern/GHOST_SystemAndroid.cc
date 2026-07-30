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
#include "GHOST_WindowManager.hh"

#include <android/input.h>
#include <android/native_window.h>
#include <android_native_app_glue.h>

#include <ctime>

static android_app *g_android_app = nullptr;

GHOST_SystemAndroid::GHOST_SystemAndroid()
    : app_(g_android_app), window_(nullptr)
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

int32_t GHOST_SystemAndroid::handleInputEvent(AInputEvent *event)
{
  if (!window_ || AInputEvent_getType(event) != AINPUT_EVENT_TYPE_MOTION) {
    return 0;
  }

  const int32_t action = AMotionEvent_getAction(event) & AMOTION_EVENT_ACTION_MASK;
  const int32_t x = int32_t(AMotionEvent_getX(event, 0));
  const int32_t y = int32_t(AMotionEvent_getY(event, 0));

  /* Stylus barrel button maps to right mouse (S Pen side button). */
  const int32_t buttons = AMotionEvent_getButtonState(event);
  const bool secondary = (buttons & AMOTION_EVENT_BUTTON_STYLUS_PRIMARY) != 0;
  const GHOST_TButton button = secondary ? GHOST_kButtonMaskRight : GHOST_kButtonMaskLeft;

  pushEvent(std::make_unique<GHOST_EventCursor>(
      getMilliSeconds(), GHOST_kEventCursorMove, window_, x, y, GHOST_TABLET_DATA_NONE));

  switch (action) {
    case AMOTION_EVENT_ACTION_DOWN:
      pushEvent(std::make_unique<GHOST_EventButton>(
          getMilliSeconds(), GHOST_kEventButtonDown, window_, button, GHOST_TABLET_DATA_NONE));
      return 1;
    case AMOTION_EVENT_ACTION_UP:
      pushEvent(std::make_unique<GHOST_EventButton>(
          getMilliSeconds(), GHOST_kEventButtonUp, window_, button, GHOST_TABLET_DATA_NONE));
      return 1;
    default:
      return 1;
  }
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
