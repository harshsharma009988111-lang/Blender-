# Blender Android Port — Backend Spec (derived from the `origin/ios` branch)

Status: research notes. This maps how the iOS backend implements GHOST's contract
and specifies what the Android equivalents must implement. Scope here is the
**GHOST backend + runtime model** only — toolchain and dependency builds are
tracked separately.

---

## 1. The single most important thing: the event loop is inverted

On desktop, **Blender owns the loop**:

```
while (!quit) {
    GHOST_System::processEvents(waitForEvent);   // pumps OS events -> GHOST queue
    WM_main_loop_body(C);                         // Blender consumes queue, redraws
}
```

On iOS the model is **flipped** — the platform drives each frame and calls into
Blender once per frame:

- Entry is `UIApplicationMain(...)` with an `IOSAppDelegate`
  (`GHOST_SystemIOS.mm:47-74, 150-158`). There is no Blender-owned `while` loop.
- An `MTKView` display-link callback, `drawInMTKView:`
  (`GHOST_SystemIOS.mm:95-134`), runs every frame and calls
  `blender::WM_main_loop_body(blender::C)` exactly once per frame.
- `GHOST_SystemIOS::processEvents()` is a **no-op returning true**
  (`GHOST_SystemIOS.mm:628-636`). Input events are pushed **asynchronously** from
  UIKit callbacks straight into the GHOST queue via `system->pushEvent(...)`.
- `blender::C` (the `bContext*`) is handed to GHOST after Blender init via
  `GHOST_iosfinalize(bContext*)` (`GHOST_SystemIOS.mm:160-163`).

### Android equivalent
- **Entry**: `android_main(struct android_app*)` via `android_native_app_glue`
  (NativeActivity), or GameActivity. No Blender-owned loop.
- **Per-frame drive**: register a Choreographer frame callback (or the
  `android_app` command/input pump) and call `WM_main_loop_body(C)` once per
  vsync — the direct analog of `drawInMTKView:`.
- **Input**: translate `AInputEvent` (via glue's input queue, or GameActivity's
  motion/key buffers) into GHOST events and `pushEvent(...)` them, same
  asynchronous pattern. `processEvents()` stays a near no-op.
- Keep an equivalent of `current_active_window_` / `next_active_window_` state on
  the system object (`GHOST_SystemIOS.hh:310-312`).

---

## 2. Graphics context: Android is *easier* than iOS here

iOS wrote a **native Metal** context, `GHOST_ContextIOS` (`.hh`/`.mm`), wrapping a
`CAMetalLayer`/`MTKView`, a shared `MTLCommandQueue`, a 3-image swapchain, and a
present callback. ~640 lines of Metal-specific code.

Android does **not** need a new-from-scratch context. `GHOST_ContextVK` already
exists on `main` and already abstracts Vulkan across Win32 / Metal(MoltenVK) /
X11 / Wayland / headless (`GHOST_ContextVK.hh:58-126`). It just has **no Android
surface case yet**.

### Android work on the context
- Add `GHOST_kVulkanPlatformAndroid` to the platform enum
  (`GHOST_ContextVK.hh:58`).
- Add a constructor/surface path taking an `ANativeWindow*`, creating the surface
  via `VK_KHR_android_surface` (`vkCreateAndroidSurfaceKHR`) — parallel to the
  existing Metal/X11/Wayland branches.
- Enable the `VK_KHR_android_surface` instance extension in the Android build.
- This is a **small, well-scoped addition to an existing file**, not a new backend.
  (GLES via `GHOST_ContextEGL` also exists as a fallback, but Vulkan is the right
  target — Blender's GPU backend is moving off GL.)

---

## 3. Input model: reuse the macOS trackpad vocabulary

The iOS insight worth copying wholesale: **do not invent new GHOST event types
for touch**. iOS maps gestures onto GHOST's *existing* desktop event vocabulary
that Blender already understands (originally from macOS trackpads). See
`generateUserInputEvents:` (`GHOST_WindowIOS.mm:446-527`):

| Gesture (iOS)                | GHOST event pushed                                   |
|------------------------------|------------------------------------------------------|
| single-finger pan            | `GHOST_EventTrackpad` `kTrackpadEventScroll` (1 finger) |
| two-finger pan               | `GHOST_EventTrackpad` `kTrackpadEventScroll` (2 finger) |
| pinch                        | `GHOST_EventTrackpad` `kTrackpadEventMagnify`        |
| tap / touch down-up          | `GHOST_EventButton` down/up `kButtonMaskLeft`        |
| cursor move                  | `GHOST_EventCursor` `kEventCursorMove`               |
| pencil/stylus + tablet data  | `GHOST_TabletData` attached to cursor/button events  |
| pencil double-tap            | `GHOST_EventButton` `kButtonMaskRight` (simulated RMB) |

Events are **batched and `@synchronized`** so simultaneous gestures don't
interleave (`GHOST_WindowIOS.mm:446-449`), and only pan+zoom are allowed to fire
simultaneously (`gestureRecognizer:shouldRecognizeSimultaneously...`,
`:530-545`).

### Android equivalent
- Use Android `GestureDetector` / `ScaleGestureDetector` (Java side, over JNI) OR
  interpret raw `AMotionEvent` pointer streams natively. The Java gesture
  detectors are closer to iOS's `UIPanGestureRecognizer`/`UIPinchGestureRecognizer`
  and less error-prone.
- Map to the **same GHOST events** as the table above — this makes Blender behave
  identically to the iOS port with zero changes to Blender's window manager.
- Stylus: Android `MotionEvent` exposes `TOOL_TYPE_STYLUS`, pressure and tilt →
  fill `GHOST_TabletData`, mirroring the Apple Pencil path.

---

## 4. New GHOST interface surface added by iOS (Android must implement too)

iOS added on-screen-keyboard + security-scoped-file methods to the system:
- `popupOnScreenKeyboard(window, KeyboardProperties)` (`GHOST_SystemIOS.hh:232`)
- `hideOnScreenKeyboard(window)` (`:242`)
- `getKeyboardInput(window)` (`:244`)
- `startSecurityScopedFileAccess` / `stopSecurityScopedFileAccess` (`:246-247`)

Android needs equivalents:
- On-screen keyboard via `InputMethodManager.showSoftInput/hideSoftInputFromWindow`
  over JNI; feed committed text back as `GHOST_EventKey`s.
- Scoped storage / SAF (Storage Access Framework) instead of iOS
  security-scoped bookmarks — for opening/saving `.blend` outside the app sandbox.

---

## 5. Files to create (mirroring the iOS set)

iOS backend files (`intern/ghost/intern/`):
- `GHOST_SystemIOS.{hh,mm}`  — 354 / 1014 lines
- `GHOST_WindowIOS.{hh,mm}`  — 391 / 1956 lines (the big one: gestures/keyboard/view)
- `GHOST_ContextIOS.{hh,mm}` — 196 / 443 lines (Metal)

Android backend files to add:
- `GHOST_SystemAndroid.{hh,cpp}` — app lifecycle, event pump, JNI bridge, display info
- `GHOST_WindowAndroid.{hh,cpp}` — wraps `ANativeWindow`, gesture→GHOST translation, soft keyboard
- **No** `GHOST_ContextAndroid` — extend `GHOST_ContextVK` instead (see §2)
- A Java/Kotlin `Activity` (or pure `NativeActivity` manifest) + JNI glue
- `AndroidManifest.xml`, gradle packaging → APK/AAB (analog of iOS `.app` bundle)

---

## 6. Build-system wiring

iOS gates everything behind `WITH_APPLE_CROSSPLATFORM` and selects the backend in
`intern/ghost/CMakeLists.txt` (a nested `if(APPLE_TARGET_IOS)` block that swaps in
the `GHOST_*IOS` sources).

Android plan:
- Add a `WITH_GHOST_ANDROID` (or platform-detected `ANDROID`) branch in
  `intern/ghost/CMakeLists.txt` that compiles the `GHOST_*Android` sources and
  defines the Android Vulkan platform.
- Cross-compile via the **NDK toolchain** (`-DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-XX`).
- **Dependencies are the real mountain** (tracked separately): no prebuilt
  `lib/android_arm64` exists. iOS needed ~14 per-library patches
  (`build_files/build_environment/patches/*_ios.diff`) — expect a comparable or
  larger effort against the NDK (Python, LLVM, OpenImageIO, TBB, USD, embree,
  OpenColorIO, ffmpeg are the hard ones).

---

## 7. Suggested first milestone

Prove the runtime model before touching the dependency mountain:
1. NDK toolchain + `WITH_GHOST_ANDROID` skeleton that compiles empty
   `GHOST_SystemAndroid`/`GHOST_WindowAndroid` stubs.
2. Add the `GHOST_ContextVK` Android surface case; clear the screen from a
   `NativeActivity` — proves toolchain + Vulkan surface + `ANativeWindow`.
3. Wire the inverted loop: Choreographer → `WM_main_loop_body`.
4. Wire touch → GHOST trackpad/button events.
5. Only then grind through dependencies to link the full `blender` target.
