/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

/** \file
 * \ingroup GHOST
 *
 * NativeActivity entry point. Android owns the frame loop, so we invert
 * Blender's main loop: run init once, then WM_main_loop_body per frame.
 */

#include "GHOST_ISystem.hh"
#include "GHOST_SystemAndroid.hh"

#include <android/log.h>
#include <android_native_app_glue.h>
#include <cstdio>
#include <jni.h>
#include <pthread.h>
#include <unistd.h>

/* Route Blender's stdout/stderr to logcat (tag "blender") so init/errors are
 * visible; NativeActivity otherwise discards them. */
static int g_stdio_pipe[2];
static void *ghost_android_stdio_thread(void * /*arg*/)
{
  char line[1024];
  ssize_t count;
  while ((count = read(g_stdio_pipe[0], line, sizeof(line) - 1)) > 0) {
    if (line[count - 1] == '\n') {
      count--;
    }
    line[count] = '\0';
    __android_log_write(ANDROID_LOG_INFO, "blender", line);
  }
  return nullptr;
}
static void ghost_android_redirect_stdio()
{
  setvbuf(stdout, nullptr, _IONBF, 0);
  setvbuf(stderr, nullptr, _IONBF, 0);
  if (pipe(g_stdio_pipe) != 0) {
    return;
  }
  dup2(g_stdio_pipe[1], STDOUT_FILENO);
  dup2(g_stdio_pipe[1], STDERR_FILENO);
  pthread_t thread;
  if (pthread_create(&thread, nullptr, ghost_android_stdio_thread, nullptr) == 0) {
    pthread_detach(thread);
  }
}

namespace blender {
struct bContext;
/* Implemented in creator: runs Blender init + WM_main_entry, hands C back. */
int GHOST_android_launch(int argc, const char **argv);
void WM_main_loop_body(bContext *C);
}  // namespace blender

static blender::bContext *g_context = nullptr;
static bool g_blender_launched = false;

namespace blender {
/* Called by the creator once init finished, to hand the context to the loop. */
void GHOST_androidfinalize(bContext *C)
{
  g_context = C;
}
}  // namespace blender

static GHOST_SystemAndroid *android_system()
{
  return static_cast<GHOST_SystemAndroid *>(GHOST_ISystem::getSystem());
}

static void on_app_cmd(android_app *app, int32_t cmd)
{
  switch (cmd) {
    case APP_CMD_INIT_WINDOW:
      if (!g_blender_launched) {
        const char *argv[] = {"blender"};
        blender::GHOST_android_launch(1, argv);
        g_blender_launched = true;
      }
      else if (GHOST_ISystem::getSystem()) {
        android_system()->handleNativeWindowInit(app);
      }
      break;
    case APP_CMD_TERM_WINDOW:
      if (GHOST_ISystem::getSystem()) {
        android_system()->handleNativeWindowTerm();
      }
      break;
    default:
      break;
  }
}

static int32_t on_input_event(android_app * /*app*/, AInputEvent *event)
{
  if (!GHOST_ISystem::getSystem()) {
    return 0;
  }
  return android_system()->handleInputEvent(event);
}

static GHOST_SystemAndroid *android_system_if_ready()
{
  return GHOST_ISystem::getSystem() ? android_system() : nullptr;
}

/* Soft-keyboard text/keys from the Java InputConnection (BlenderActivity). */
extern "C" JNIEXPORT void JNICALL Java_org_blender_blender_BlenderActivity_nativeOnCommitText(
    JNIEnv *env, jobject /*thiz*/, jstring text)
{
  GHOST_SystemAndroid *system = android_system_if_ready();
  if (!system || !text) {
    return;
  }
  const char *utf = env->GetStringUTFChars(text, nullptr);
  system->handleTextInput(utf);
  env->ReleaseStringUTFChars(text, utf);
}

extern "C" JNIEXPORT void JNICALL Java_org_blender_blender_BlenderActivity_nativeOnKey(
    JNIEnv * /*env*/, jobject /*thiz*/, jint keycode, jint action, jint meta_state)
{
  if (GHOST_SystemAndroid *system = android_system_if_ready()) {
    system->handleJavaKeyEvent(keycode, action, meta_state);
  }
}

extern "C" void android_main(struct android_app *app)
{
  ghost_android_redirect_stdio();
  GHOST_SystemAndroid::setAndroidApp(app);
  app->onAppCmd = on_app_cmd;
  app->onInputEvent = on_input_event;

  while (!app->destroyRequested) {
    int events;
    android_poll_source *source;
    /* Block until the window exists (and Blender is launched); afterwards never
     * block, so we fall through to render every frame. `GHOST_android_launch`
     * runs the whole init inside `source->process` and sets `g_context`
     * mid-drain, so the timeout must be re-evaluated after each event rather
     * than captured once — otherwise the loop blocks forever and never renders. */
    int timeout = g_context ? 0 : -1;
    while (ALooper_pollOnce(timeout, nullptr, &events, (void **)&source) >= 0) {
      if (source) {
        source->process(app, source);
      }
      if (app->destroyRequested) {
        return;
      }
      if (g_context) {
        timeout = 0;
      }
    }

    if (g_context) {
      blender::WM_main_loop_body(g_context);
    }
  }
}
