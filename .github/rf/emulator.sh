#!/usr/bin/env bash
BT="$ANDROID_HOME/build-tools/$(ls "$ANDROID_HOME/build-tools" | sort -V | tail -1)"
PKG="$("$BT/aapt2" dump packagename emu/app.apk)"
mkdir -p preview
echo "package=$PKG" > preview/device.txt
adb shell getprop ro.product.model >> preview/device.txt
adb shell getprop ro.build.version.release >> preview/device.txt
wait_app() {
  for i in $(seq 1 25); do
    if adb shell dumpsys window 2>/dev/null | grep -E "mCurrentFocus|mFocusedApp" | grep -qE "$PKG|permissioncontroller|packageinstaller"; then sleep "$1"; return; fi
    sleep 1
  done
}
W="$PWD"
repair_apk() {
  # repack: drop old signatures, store resources.arsc uncompressed (Android 11+ rule), align, sign with a debug key
  R="$RUNNER_TEMP/rp"; rm -rf "$R" emu/re.apk emu/aligned.apk; mkdir -p "$R"
  (cd "$R" && unzip -q -o "$W/emu/app.apk" && rm -f META-INF/*.SF META-INF/*.RSA META-INF/*.DSA META-INF/*.EC META-INF/MANIFEST.MF     && zip -q -r -X "$W/emu/re.apk" . -x resources.arsc && if [ -f resources.arsc ]; then zip -q -0 -X "$W/emu/re.apk" resources.arsc; fi)
  keytool -genkeypair -keystore "$RUNNER_TEMP/emu.jks" -storepass android -keypass android -alias emu -keyalg RSA -keysize 2048 -validity 1000 -dname "CN=RepoForge Emulator" >/dev/null 2>&1
  "$BT/zipalign" -f -p 4 emu/re.apk emu/aligned.apk
  "$BT/apksigner" sign --ks "$RUNNER_TEMP/emu.jks" --ks-pass pass:android --key-pass pass:android --ks-key-alias emu --out emu/app.apk emu/aligned.apk
}
if ! adb install -r emu/app.apk > preview/install.txt 2>&1; then
  if grep -qE "NO_CERTIFICATES|INVALID_APK|signatures do not match|not signed|resources.arsc|-124" preview/install.txt; then
    echo "The APK was unsigned, had a broken signature or a compressed resources.arsc. RepoForge repacked and re-signed it with a temporary debug key for this preview (your file is unchanged)." > preview/signed-note.txt
    repair_apk
    if ! adb install -r emu/app.apk > preview/install.txt 2>&1; then echo "INSTALL FAILED"; cat preview/install.txt; exit 0; fi
  else
    echo "INSTALL FAILED"; cat preview/install.txt; exit 0
  fi
fi
if [ "$RF_FAST" = "true" ]; then
  # fast mode: grant every runtime permission, launch once, one screenshot
  adb shell dumpsys package "$PKG" | grep -E "android.permission.[A-Z_]+: granted=(true|false)" | sort -u > preview/permissions-before.txt
  for p in $(adb shell dumpsys package "$PKG" | grep -oE "android.permission.[A-Z_]+: granted=false" | cut -d: -f1 | sort -u); do adb shell pm grant "$PKG" "$p" >/dev/null 2>&1; done
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  wait_app 5
  adb exec-out screencap -p > preview/screen-1-granted.png
  adb shell dumpsys package "$PKG" | grep -E "android.permission.[A-Z_]+: granted=(true|false)" | sort -u > preview/permissions-after.txt
  adb logcat -d -b crash > preview/crash.txt 2>/dev/null
  ls -la preview
  exit 0
fi
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
wait_app 6
adb exec-out screencap -p > preview/screen-1-launch.png
adb shell dumpsys package "$PKG" | grep -E "android.permission.[A-Z_]+: granted=(true|false)" | sort -u > preview/permissions-before.txt
for p in $(adb shell dumpsys package "$PKG" | grep -oE "android.permission.[A-Z_]+: granted=false" | cut -d: -f1 | sort -u); do adb shell pm grant "$PKG" "$p" >/dev/null 2>&1; done
adb shell am force-stop "$PKG"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
wait_app 7
adb exec-out screencap -p > preview/screen-2-granted.png
adb shell dumpsys package "$PKG" | grep -E "android.permission.[A-Z_]+: granted=(true|false)" | sort -u > preview/permissions-after.txt
adb logcat -d -b crash > preview/crash.txt 2>/dev/null
ls -la preview
