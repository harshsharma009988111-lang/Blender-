/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 */

#include "GHOST_WindowAndroid.hh"
#include "GHOST_SystemAndroid.hh"

#ifdef WITH_VULKAN_BACKEND
#  include "GHOST_ContextVK.hh"
#endif

#include <android/native_window.h>

GHOST_WindowAndroid::GHOST_WindowAndroid(GHOST_SystemAndroid *system,
                                         ANativeWindow *native_window,
                                         const char *title,
                                         uint32_t width,
                                         uint32_t height,
                                         GHOST_TWindowState state,
                                         GHOST_TDrawingContextType type,
                                         const GHOST_ContextParams &context_params)
    : GHOST_Window(width, height, state, context_params, false),
      system_(system),
      native_window_(native_window),
      title_(title ? title : "")
{
  if (native_window_) {
    ANativeWindow_acquire(native_window_);
  }
  setDrawingContextType(type);
}

GHOST_WindowAndroid::~GHOST_WindowAndroid()
{
  releaseNativeHandles();
  if (native_window_) {
    ANativeWindow_release(native_window_);
    native_window_ = nullptr;
  }
}

bool GHOST_WindowAndroid::getValid() const
{
  return GHOST_Window::getValid() && native_window_ != nullptr;
}

void GHOST_WindowAndroid::setNativeWindow(ANativeWindow *native_window)
{
  if (native_window_) {
    ANativeWindow_release(native_window_);
  }
  native_window_ = native_window;
  if (native_window_) {
    ANativeWindow_acquire(native_window_);
  }
}

GHOST_Context *GHOST_WindowAndroid::newDrawingContext(GHOST_TDrawingContextType type)
{
#ifdef WITH_VULKAN_BACKEND
  if (type == GHOST_kDrawingContextTypeVulkan) {
    GHOST_Context *context = new GHOST_ContextVK(
        want_context_params_, native_window_, 1, 2, GHOST_GPUDevice{});
    if (context->initializeDrawingContext() == GHOST_kSuccess) {
      return context;
    }
    delete context;
  }
#else
  (void)type;
#endif
  return nullptr;
}

void GHOST_WindowAndroid::getWindowBounds(GHOST_Rect &bounds) const
{
  getClientBounds(bounds);
}

void GHOST_WindowAndroid::getClientBounds(GHOST_Rect &bounds) const
{
  const int32_t w = native_window_ ? ANativeWindow_getWidth(native_window_) : 0;
  const int32_t h = native_window_ ? ANativeWindow_getHeight(native_window_) : 0;
  bounds.set(0, 0, w, h);
}

GHOST_TSuccess GHOST_WindowAndroid::setClientWidth(uint32_t /*width*/)
{
  return GHOST_kFailure;
}

GHOST_TSuccess GHOST_WindowAndroid::setClientHeight(uint32_t /*height*/)
{
  return GHOST_kFailure;
}

GHOST_TSuccess GHOST_WindowAndroid::setClientSize(uint32_t /*width*/, uint32_t /*height*/)
{
  return GHOST_kFailure;
}

void GHOST_WindowAndroid::screenToClient(
    int32_t inX, int32_t inY, int32_t &outX, int32_t &outY) const
{
  outX = inX;
  outY = inY;
}

void GHOST_WindowAndroid::clientToScreen(
    int32_t inX, int32_t inY, int32_t &outX, int32_t &outY) const
{
  outX = inX;
  outY = inY;
}

void GHOST_WindowAndroid::setTitle(const char *title)
{
  title_ = title ? title : "";
}

std::string GHOST_WindowAndroid::getTitle() const
{
  return title_;
}

GHOST_TSuccess GHOST_WindowAndroid::setState(GHOST_TWindowState /*state*/)
{
  return GHOST_kSuccess;
}

GHOST_TWindowState GHOST_WindowAndroid::getState() const
{
  return GHOST_kWindowStateFullScreen;
}

GHOST_TSuccess GHOST_WindowAndroid::invalidate()
{
  return GHOST_kSuccess;
}

uint16_t GHOST_WindowAndroid::getDPIHint()
{
  return system_ ? system_->getDPIHint() : 96;
}
