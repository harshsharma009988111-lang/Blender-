/* SPDX-FileCopyrightText: 2026 Blender Authors
 *
 * SPDX-License-Identifier: GPL-2.0-or-later */

package org.blender.blender;

import android.app.NativeActivity;
import android.content.Context;
import android.content.pm.ActivityInfo;
import android.content.res.AssetManager;
import android.os.Bundle;
import android.text.InputType;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * NativeActivity subclass for Blender. Extracts the bundled runtime
 * (Python + scripts + datafiles) on first launch, then loads libblender.so
 * and bridges soft-keyboard IME text to native. Landscape only.
 */
public class BlenderActivity extends NativeActivity {

  /* Must match GHOST_SystemPathsAndroid: <filesDir>/blender/<version>. */
  private static final String VERSION = "5.3";
  private static final String RUNTIME_ZIP = "blender_runtime.zip";

  private InputView inputView;

  private native void nativeOnCommitText(String text);
  private native void nativeOnKey(int keycode, int action, int metaState);

  @Override
  protected void onCreate(Bundle state) {
    /* Runtime files must exist before native Blender init reads them. */
    extractRuntimeIfNeeded();
    super.onCreate(state);
    setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);

    inputView = new InputView(this);
    addContentView(inputView, new ViewGroup.LayoutParams(1, 1));
  }

  private void extractRuntimeIfNeeded() {
    File root = new File(getFilesDir(), "blender/" + VERSION);
    File marker = new File(root, ".installed-" + VERSION);
    if (marker.exists()) {
      return;
    }
    root.mkdirs();
    try (InputStream is = getAssets().open(RUNTIME_ZIP, AssetManager.ACCESS_STREAMING);
         ZipInputStream zis = new ZipInputStream(is)) {
      ZipEntry e;
      byte[] buf = new byte[65536];
      while ((e = zis.getNextEntry()) != null) {
        File out = new File(root, e.getName());
        if (e.isDirectory()) {
          out.mkdirs();
          continue;
        }
        File parent = out.getParentFile();
        if (parent != null) {
          parent.mkdirs();
        }
        try (OutputStream os = new FileOutputStream(out)) {
          int n;
          while ((n = zis.read(buf)) > 0) {
            os.write(buf, 0, n);
          }
        }
      }
      marker.createNewFile();
    }
    catch (Exception ex) {
      throw new RuntimeException("Failed to extract Blender runtime", ex);
    }
  }

  /* Called from native (popupOnScreenKeyboard). */
  public void showKeyboard() {
    runOnUiThread(() -> {
      inputView.setFocusableInTouchMode(true);
      inputView.requestFocus();
      InputMethodManager imm = (InputMethodManager)getSystemService(Context.INPUT_METHOD_SERVICE);
      imm.showSoftInput(inputView, InputMethodManager.SHOW_IMPLICIT);
    });
  }

  /* Called from native (hideOnScreenKeyboard). */
  public void hideKeyboard() {
    runOnUiThread(() -> {
      InputMethodManager imm = (InputMethodManager)getSystemService(Context.INPUT_METHOD_SERVICE);
      imm.hideSoftInputFromWindow(inputView.getWindowToken(), 0);
    });
  }

  /** Invisible view whose InputConnection captures IME text. */
  private class InputView extends View {
    InputView(Context context) {
      super(context);
      setFocusable(true);
      setFocusableInTouchMode(true);
    }

    @Override
    public boolean onCheckIsTextEditor() {
      return true;
    }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo outAttrs) {
      outAttrs.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
      outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;

      return new BaseInputConnection(this, false) {
        @Override
        public boolean commitText(CharSequence text, int newCursorPosition) {
          nativeOnCommitText(text.toString());
          return true;
        }

        @Override
        public boolean sendKeyEvent(KeyEvent event) {
          nativeOnKey(event.getKeyCode(), event.getAction(), event.getMetaState());
          return true;
        }

        @Override
        public boolean deleteSurroundingText(int beforeLength, int afterLength) {
          for (int i = 0; i < beforeLength; i++) {
            nativeOnKey(KeyEvent.KEYCODE_DEL, KeyEvent.ACTION_DOWN, 0);
            nativeOnKey(KeyEvent.KEYCODE_DEL, KeyEvent.ACTION_UP, 0);
          }
          return true;
        }
      };
    }
  }
}
