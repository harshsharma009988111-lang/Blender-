/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 */

#include "GHOST_SystemAndroid.hh"
#include "GHOST_WindowAndroid.hh"

#include "GHOST_AndroidMemoryTier.hh"

#include "GHOST_ContextVK.hh"
#include "GHOST_Event.hh"
#include "GHOST_EventButton.hh"
#include "GHOST_EventCursor.hh"
#include "GHOST_EventKey.hh"
#include "GHOST_EventTrackpad.hh"
#include "GHOST_ModifierKeys.hh"
#include "GHOST_WindowManager.hh"

#include <android/configuration.h>
#include <android/log.h>
#include <android/input.h>
#include <jni.h>
#include <android/keycodes.h>
#include <android/native_activity.h>
#include <android/native_window.h>
#include <android_native_app_glue.h>

#include <cmath>
#include <cstring>
#include <ctime>

static android_app *g_android_app = nullptr;

/* Hold a finger this long without moving to get a right-click. */
static constexpr uint64_t TOUCH_LONG_PRESS_MS = 500;
/* Movement past this (in pixels) makes the press a left-button drag. Sized for a
 * fingertip on a dense tablet panel, so resting jitter does not cancel a hold. */
static constexpr int32_t TOUCH_SLOP_PX = 48;

GHOST_SystemAndroid::GHOST_SystemAndroid()
    : app_(g_android_app),
      window_(nullptr),
      meta_state_(0),
      cursor_x_(0),
      cursor_y_(0),
      stylus_button_down_(false),
      gesture_active_(false),
      gesture_prev_x_(0.0f),
      gesture_prev_y_(0.0f),
      gesture_prev_dist_(0.0f),
      touch_pending_(false),
      touch_button_down_(false),
      touch_button_(GHOST_kButtonMaskLeft),
      touch_down_time_(0),
      touch_down_x_(0),
      touch_down_y_(0)
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

android_app *GHOST_SystemAndroid::getAndroidApp()
{
  return g_android_app;
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
  /* Soft-keyboard input arrives on the Android UI thread; dispatch it here. */
  drainJavaInput();

  /* A finger held still emits no events, so the long-press is timed here. */
  touchLongPressCheck();

  /* Input arrives asynchronously via the glue calling handleInputEvent(), which
   * queues GHOST events. Report whether any are pending so the window manager
   * actually dispatches them (it only calls dispatchEvents() when this is true). */
  return getEventManager()->getNumEvents() != 0;
}

uint8_t GHOST_SystemAndroid::getNumDisplays() const
{
  return 1;
}

void GHOST_SystemAndroid::getMainDisplayDimensions(uint32_t &width, uint32_t &height) const
{
  if (app_ && app_->window) {
    /* Report the size Blender renders at, which the render scale may have reduced. */
    const uint32_t divisor = GHOST_android_render_scale_divisor();
    width = uint32_t(ANativeWindow_getWidth(app_->window)) / divisor;
    height = uint32_t(ANativeWindow_getHeight(app_->window)) / divisor;
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
  /* Only one window exists on Android; its surface is exclusive to the native
   * window, so report failure rather than hand back a window that cannot draw. */
  if (window_ != nullptr) {
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

GHOST_IContext *GHOST_SystemAndroid::createOffscreenContext(GHOST_GPUSettings gpu_settings)
{
#ifdef WITH_VULKAN_BACKEND
  const GHOST_ContextParams context_params = GHOST_CONTEXT_PARAMS_FROM_GPU_SETTINGS(gpu_settings);
  GHOST_Context *context = new GHOST_ContextVK(
      context_params, nullptr, 1, 2, GHOST_GPUDevice{});
  if (context->initializeDrawingContext() == GHOST_kSuccess) {
    return context;
  }
  delete context;
#else
  (void)gpu_settings;
#endif
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
  __android_log_print(ANDROID_LOG_INFO,
                      "blender-surface",
                      "INIT_WINDOW window=%p ghost_window=%p",
                      (void *)app->window,
                      (void *)window_);
  if (window_ && app->window) {
    window_->setNativeWindow(app->window);
    pushEvent(std::make_unique<GHOST_Event>(getMilliSeconds(), GHOST_kEventWindowSize, window_));
    /* The window dimensions are unchanged across a background/foreground cycle, so
     * a size event alone schedules no redraw. Force an update so the reborn surface
     * is actually painted (else the window stays black after app switch). */
    pushEvent(std::make_unique<GHOST_Event>(getMilliSeconds(), GHOST_kEventWindowUpdate, window_));
  }
}

void GHOST_SystemAndroid::handleNativeWindowTerm()
{
  __android_log_print(
      ANDROID_LOG_INFO, "blender-surface", "TERM_WINDOW ghost_window=%p", (void *)window_);
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

  /* Two fingers: pan -> scroll, distance change -> magnify. A gesture is never a
   * click, so drop any press still waiting to be classified. */
  if (count >= 2) {
    touchCancelPending();
    const float x0 = ghost_android_scale_input(AMotionEvent_getX(event, 0)),
                y0 = ghost_android_scale_input(AMotionEvent_getY(event, 0));
    const float x1 = ghost_android_scale_input(AMotionEvent_getX(event, 1)),
                y1 = ghost_android_scale_input(AMotionEvent_getY(event, 1));
    const float cx = (x0 + x1) * 0.5f, cy = (y0 + y1) * 0.5f;
    const float dist = std::hypot(x1 - x0, y1 - y0);

    if (gesture_active_) {
      pushEvent(std::make_unique<GHOST_EventTrackpad>(getMilliSeconds(),
                                                      window_,
                                                      GHOST_kTrackpadEventScroll,
                                                      int32_t(cx),
                                                      int32_t(cy),
                                                      /* Negated so the view follows the
                                                       * fingers rather than opposing them. */
                                                      int32_t(gesture_prev_x_ - cx),
                                                      int32_t(gesture_prev_y_ - cy),
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

  /* On proximity exit the stylus leaves range; report no tablet. */
  const bool hover_exit = action == AMOTION_EVENT_ACTION_HOVER_EXIT;
  const GHOST_TabletData tablet = hover_exit ? GHOST_TABLET_DATA_NONE :
                                              tablet_from_event(event);
  const int32_t x = int32_t(ghost_android_scale_input(AMotionEvent_getX(event, 0)));
  const int32_t y = int32_t(ghost_android_scale_input(AMotionEvent_getY(event, 0)));
  meta_state_ = AMotionEvent_getMetaState(event);
  cursor_x_ = x;
  cursor_y_ = y;

  /* Cursor tracks the tip whether touching or hovering (S Pen proximity). */
  pushEvent(std::make_unique<GHOST_EventCursor>(
      getMilliSeconds(), GHOST_kEventCursorMove, window_, x, y, tablet));

  /* S Pen side button: independent right-click, in hover or contact. */
  const bool side = (AMotionEvent_getButtonState(event) &
                     AMOTION_EVENT_BUTTON_STYLUS_PRIMARY) != 0;
  if (side != stylus_button_down_) {
    stylus_button_down_ = side;
    buttons_.set(GHOST_kButtonMaskRight, side);
    pushEvent(std::make_unique<GHOST_EventButton>(
        getMilliSeconds(),
        side ? GHOST_kEventButtonDown : GHOST_kEventButtonUp,
        window_,
        GHOST_kButtonMaskRight,
        tablet));
  }

  /* A stylus has its own buttons, so its tip maps straight to the left button.
   * A finger cannot express a right-click, so the button is chosen from how long
   * the press is held (see touchLongPressCheck). */
  const bool is_stylus = tablet.Active != GHOST_kTabletModeNone;

  switch (action) {
    case AMOTION_EVENT_ACTION_DOWN:
      if (is_stylus) {
        touchSendButton(GHOST_kButtonMaskLeft, GHOST_kEventButtonDown);
      }
      else {
        touch_pending_ = true;
        touch_down_time_ = getMilliSeconds();
        touch_down_x_ = x;
        touch_down_y_ = y;
      }
      return 1;

    case AMOTION_EVENT_ACTION_MOVE:
      /* Moving past the slop means a drag, which is always the left button. */
      if (touch_pending_ && (abs(x - touch_down_x_) > TOUCH_SLOP_PX ||
                             abs(y - touch_down_y_) > TOUCH_SLOP_PX))
      {
        touch_pending_ = false;
        touchSendButton(GHOST_kButtonMaskLeft, GHOST_kEventButtonDown);
      }
      return 1;

    case AMOTION_EVENT_ACTION_UP:
    case AMOTION_EVENT_ACTION_CANCEL:
      /* Released before the long-press elapsed: a plain tap, press and release. */
      if (touch_pending_) {
        touch_pending_ = false;
        touchSendButton(GHOST_kButtonMaskLeft, GHOST_kEventButtonDown);
      }
      if (touch_button_down_) {
        touchSendButton(touch_button_, GHOST_kEventButtonUp);
      }
      return 1;

    default:
      return 1;
  }
}

void GHOST_SystemAndroid::touchSendButton(GHOST_TButton mask, GHOST_TEventType type)
{
  const bool down = type == GHOST_kEventButtonDown;
  buttons_.set(mask, down);
  touch_button_ = mask;
  touch_button_down_ = down;
  pushEvent(std::make_unique<GHOST_EventButton>(
      getMilliSeconds(), type, window_, mask, GHOST_TABLET_DATA_NONE));
}

void GHOST_SystemAndroid::touchLongPressCheck()
{
  if (!touch_pending_ || getMilliSeconds() - touch_down_time_ < TOUCH_LONG_PRESS_MS) {
    return;
  }
  /* Held in place long enough: emit a right-click instead. */
  touch_pending_ = false;
  touchSendButton(GHOST_kButtonMaskRight, GHOST_kEventButtonDown);
}

void GHOST_SystemAndroid::touchCancelPending()
{
  touch_pending_ = false;
  if (touch_button_down_) {
    touchSendButton(touch_button_, GHOST_kEventButtonUp);
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
  meta_state_ = AKeyEvent_getMetaState(event);
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

/* Byte length of the UTF-8 character starting at a lead byte. */
static int utf8_char_len(unsigned char lead)
{
  if (lead < 0x80) {
    return 1;
  }
  if ((lead >> 5) == 0x6) {
    return 2;
  }
  if ((lead >> 4) == 0xE) {
    return 3;
  }
  if ((lead >> 3) == 0x1E) {
    return 4;
  }
  return 1;
}

void GHOST_SystemAndroid::handleTextInput(const char *utf8_string)
{
  if (!utf8_string) {
    return;
  }
  std::scoped_lock lock(java_input_mutex_);
  java_text_.push_back(utf8_string);
}

void GHOST_SystemAndroid::handleJavaKeyEvent(int32_t keycode, int32_t action, int32_t meta_state)
{
  std::scoped_lock lock(java_input_mutex_);
  java_keys_.push_back({keycode, action, meta_state});
}

void GHOST_SystemAndroid::drainJavaInput()
{
  std::vector<std::string> text;
  std::vector<JavaKeyEvent> keys;
  {
    std::scoped_lock lock(java_input_mutex_);
    if (java_text_.empty() && java_keys_.empty()) {
      return;
    }
    text.swap(java_text_);
    keys.swap(java_keys_);
  }
  for (const std::string &string : text) {
    dispatchTextInput(string.c_str());
  }
  for (const JavaKeyEvent &key : keys) {
    dispatchJavaKeyEvent(key.keycode, key.action, key.meta_state);
  }
}

void GHOST_SystemAndroid::dispatchTextInput(const char *utf8_string)
{
  if (!window_ || !utf8_string) {
    return;
  }
  for (const char *p = utf8_string; *p;) {
    const int len = utf8_char_len((unsigned char)*p);
    char buf[6] = {0};
    for (int i = 0; i < len && p[i]; i++) {
      buf[i] = p[i];
    }
    /* utf8_buf drives insertion; key only needs a valid keyboard type. */
    const unsigned char c = (unsigned char)buf[0];
    GHOST_TKey key = GHOST_kKeyA;
    if (c == '\n' || c == '\r') {
      key = GHOST_kKeyEnter;
    }
    else if (c >= 'a' && c <= 'z') {
      key = GHOST_TKey(GHOST_kKeyA + (c - 'a'));
    }
    else if (c >= 'A' && c <= 'Z') {
      key = GHOST_TKey(GHOST_kKeyA + (c - 'A'));
    }
    else if (c >= '0' && c <= '9') {
      key = GHOST_TKey(GHOST_kKey0 + (c - '0'));
    }
    pushEvent(std::make_unique<GHOST_EventKey>(
        getMilliSeconds(), GHOST_kEventKeyDown, window_, key, false, buf));
    pushEvent(std::make_unique<GHOST_EventKey>(
        getMilliSeconds(), GHOST_kEventKeyUp, window_, key, false));
    p += len;
  }
}

void GHOST_SystemAndroid::dispatchJavaKeyEvent(int32_t keycode, int32_t action, int32_t meta_state)
{
  if (!window_) {
    return;
  }
  meta_state_ = meta_state;
  const GHOST_TKey key = convertAndroidKey(keycode);
  if (key == GHOST_kKeyUnknown) {
    return;
  }
  const bool down = action == AKEY_EVENT_ACTION_DOWN;
  pushEvent(std::make_unique<GHOST_EventKey>(
      getMilliSeconds(), down ? GHOST_kEventKeyDown : GHOST_kEventKeyUp, window_, key, false));
}

GHOST_TSuccess GHOST_SystemAndroid::getModifierKeys(GHOST_ModifierKeys &keys) const
{
  const bool shift = (meta_state_ & AMETA_SHIFT_ON) != 0;
  const bool ctrl = (meta_state_ & AMETA_CTRL_ON) != 0;
  const bool alt = (meta_state_ & AMETA_ALT_ON) != 0;
  const bool os = (meta_state_ & AMETA_META_ON) != 0;
  keys.set(GHOST_kModifierKeyLeftShift, shift);
  keys.set(GHOST_kModifierKeyRightShift, shift);
  keys.set(GHOST_kModifierKeyLeftControl, ctrl);
  keys.set(GHOST_kModifierKeyRightControl, ctrl);
  keys.set(GHOST_kModifierKeyLeftAlt, alt);
  keys.set(GHOST_kModifierKeyRightAlt, alt);
  keys.set(GHOST_kModifierKeyLeftOS, os);
  keys.set(GHOST_kModifierKeyRightOS, os);
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemAndroid::getButtons(GHOST_Buttons &buttons) const
{
  buttons = buttons_;
  return GHOST_kSuccess;
}

GHOST_TCapabilityFlag GHOST_SystemAndroid::getCapabilities() const
{
  return GHOST_TCapabilityFlag(GHOST_CAPABILITY_FLAG_ALL &
                               ~(GHOST_kCapabilityCursorWarp | GHOST_kCapabilityWindowPosition |
                                 GHOST_kCapabilityCursorRGBA | GHOST_kCapabilityClipboardImage));
}

/* Attach the glue thread to the JVM once and return its env. */
static JNIEnv *android_jni_env(android_app *app)
{
  if (!app || !app->activity || !app->activity->vm) {
    return nullptr;
  }
  JavaVM *vm = app->activity->vm;
  JNIEnv *env = nullptr;
  if (vm->GetEnv((void **)&env, JNI_VERSION_1_6) == JNI_OK) {
    return env;
  }
  return vm->AttachCurrentThread(&env, nullptr) == JNI_OK ? env : nullptr;
}

/* Fetch the ClipboardManager for the activity, or null. */
static jobject android_clipboard_manager(JNIEnv *env, jobject activity)
{
  jclass activity_class = env->GetObjectClass(activity);
  jmethodID get_service = env->GetMethodID(
      activity_class, "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;");
  jstring name = env->NewStringUTF("clipboard");
  jobject manager = env->CallObjectMethod(activity, get_service, name);
  env->DeleteLocalRef(name);
  return manager;
}

char *GHOST_SystemAndroid::getClipboard(bool /*selection*/) const
{
  JNIEnv *env = android_jni_env(app_);
  if (!env) {
    return nullptr;
  }
  jobject activity = app_->activity->clazz;
  jobject manager = android_clipboard_manager(env, activity);
  if (!manager) {
    return nullptr;
  }
  jclass manager_class = env->GetObjectClass(manager);
  jmethodID get_clip = env->GetMethodID(
      manager_class, "getPrimaryClip", "()Landroid/content/ClipData;");
  jobject clip = env->CallObjectMethod(manager, get_clip);
  if (!clip) {
    return nullptr;
  }
  jclass clip_class = env->GetObjectClass(clip);
  jmethodID get_item = env->GetMethodID(
      clip_class, "getItemAt", "(I)Landroid/content/ClipData$Item;");
  jobject item = env->CallObjectMethod(clip, get_item, 0);
  if (!item) {
    return nullptr;
  }
  jclass item_class = env->GetObjectClass(item);
  jmethodID coerce = env->GetMethodID(
      item_class, "coerceToText", "(Landroid/content/Context;)Ljava/lang/CharSequence;");
  jobject text = env->CallObjectMethod(item, coerce, activity);
  if (!text) {
    return nullptr;
  }
  jmethodID to_string = env->GetMethodID(
      env->GetObjectClass(text), "toString", "()Ljava/lang/String;");
  jstring str = (jstring)env->CallObjectMethod(text, to_string);
  const char *utf = env->GetStringUTFChars(str, nullptr);
  char *result = strdup(utf);
  env->ReleaseStringUTFChars(str, utf);
  return result;
}

void GHOST_SystemAndroid::putClipboard(const char *buffer, bool /*selection*/) const
{
  JNIEnv *env = android_jni_env(app_);
  if (!env || !buffer) {
    return;
  }
  jobject manager = android_clipboard_manager(env, app_->activity->clazz);
  if (!manager) {
    return;
  }
  jclass clip_data_class = env->FindClass("android/content/ClipData");
  jmethodID new_plain = env->GetStaticMethodID(
      clip_data_class,
      "newPlainText",
      "(Ljava/lang/CharSequence;Ljava/lang/CharSequence;)Landroid/content/ClipData;");
  jstring label = env->NewStringUTF("blender");
  jstring text = env->NewStringUTF(buffer);
  jobject clip = env->CallStaticObjectMethod(clip_data_class, new_plain, label, text);
  jmethodID set_clip = env->GetMethodID(
      env->GetObjectClass(manager), "setPrimaryClip", "(Landroid/content/ClipData;)V");
  env->CallVoidMethod(manager, set_clip, clip);
  env->DeleteLocalRef(label);
  env->DeleteLocalRef(text);
}

GHOST_TSuccess GHOST_SystemAndroid::getCursorPosition(int32_t &x, int32_t &y) const
{
  x = cursor_x_;
  y = cursor_y_;
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemAndroid::setCursorPosition(int32_t /*x*/, int32_t /*y*/)
{
  /* Touch input has no warpable cursor. */
  return GHOST_kFailure;
}

uint16_t GHOST_SystemAndroid::getDPIHint()
{
  /* Fewer pixels for the same physical screen means a proportionally lower density, else the
   * UI would be drawn at twice its intended physical size. */
  const uint32_t divisor = GHOST_android_render_scale_divisor();
  if (app_ && app_->config) {
    const int32_t density = AConfiguration_getDensity(app_->config);
    if (density > 0 && density != ACONFIGURATION_DENSITY_NONE &&
        density != ACONFIGURATION_DENSITY_ANY)
    {
      return uint16_t(uint32_t(density) / divisor);
    }
  }
  return uint16_t(160 / divisor);
}

/* Call a no-arg void method on the BlenderActivity instance. */
static GHOST_TSuccess android_call_activity_void(android_app *app, const char *method)
{
  if (!app || !app->activity || !app->activity->clazz) {
    return GHOST_kFailure;
  }
  JNIEnv *env = android_jni_env(app);
  if (!env) {
    return GHOST_kFailure;
  }
  jobject activity = app->activity->clazz;
  jmethodID mid = env->GetMethodID(env->GetObjectClass(activity), method, "()V");
  if (!mid) {
    env->ExceptionClear();
    return GHOST_kFailure;
  }
  env->CallVoidMethod(activity, mid);
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemAndroid::popupOnScreenKeyboard(GHOST_IWindow * /*window*/)
{
  return android_call_activity_void(app_, "showKeyboard");
}

GHOST_TSuccess GHOST_SystemAndroid::hideOnScreenKeyboard(GHOST_IWindow * /*window*/)
{
  return android_call_activity_void(app_, "hideKeyboard");
}
