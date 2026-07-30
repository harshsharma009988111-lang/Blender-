/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 * Declaration of GHOST_SystemAndroid class.
 */

#pragma once

#include "GHOST_System.hh"

struct android_app;
struct AInputEvent;
class GHOST_WindowAndroid;

class GHOST_SystemAndroid : public GHOST_System {
 public:
  GHOST_SystemAndroid();
  ~GHOST_SystemAndroid() override;

  /* Set by the NativeActivity glue before GHOST is created. */
  static void setAndroidApp(android_app *app);

  bool processEvents(bool waitForEvent) override;

  bool setConsoleWindowState(GHOST_TConsoleWindowState /*action*/) override
  {
    return false;
  }

  GHOST_TSuccess getModifierKeys(GHOST_ModifierKeys &keys) const override;
  GHOST_TSuccess getButtons(GHOST_Buttons &buttons) const override;
  GHOST_TCapabilityFlag getCapabilities() const override;

  char *getClipboard(bool selection) const override;
  void putClipboard(const char *buffer, bool selection) const override;

  uint64_t getMilliSeconds() const override;

  uint8_t getNumDisplays() const override;
  void getMainDisplayDimensions(uint32_t &width, uint32_t &height) const override;
  void getAllDisplayDimensions(uint32_t &width, uint32_t &height) const override;

  GHOST_TSuccess getCursorPosition(int32_t &x, int32_t &y) const override;
  GHOST_TSuccess setCursorPosition(int32_t x, int32_t y) override;

  GHOST_IContext *createOffscreenContext(GHOST_GPUSettings gpu_settings) override;
  GHOST_TSuccess disposeContext(GHOST_IContext *context) override;

  uint16_t getDPIHint();

  /* Called by the glue when Android (re)creates or destroys the surface. */
  void handleNativeWindowInit(android_app *app);
  void handleNativeWindowTerm();

  /* Translate a native input event into GHOST events. Return 1 if handled. */
  int32_t handleInputEvent(AInputEvent *event);

 private:
  GHOST_TSuccess init() override;

  GHOST_IWindow *createWindow(const char *title,
                              int32_t left,
                              int32_t top,
                              uint32_t width,
                              uint32_t height,
                              GHOST_TWindowState state,
                              GHOST_GPUSettings gpu_settings,
                              const bool exclusive = false,
                              const bool is_dialog = false,
                              const GHOST_IWindow *parent_window = nullptr) override;

  android_app *app_;
  GHOST_WindowAndroid *window_;
  uint64_t start_time_;
};
