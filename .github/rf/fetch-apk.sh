#!/usr/bin/env bash
mkdir -p emu
gh release download "$RF_SRC_TAG" --repo "$GITHUB_REPOSITORY" --pattern 'input.apk.part*' --dir emu 2>/dev/null || true
if ls emu/input.apk.part* >/dev/null 2>&1; then
  cat $(ls emu/input.apk.part* | sort -V) > emu/app.apk
  echo "Joined $(ls emu/input.apk.part* | wc -l) parts into app.apk ($(du -h emu/app.apk | cut -f1))"
  exit 0
fi
gh release download "$RF_SRC_TAG" --repo "$GITHUB_REPOSITORY" --pattern '*.apk' --dir emu
APK="$(ls emu/*.apk | grep -i debug | head -1)"
[ -n "$APK" ] || APK="$(ls emu/*.apk | head -1)"
[ -n "$APK" ] || { echo "No APK found in release $RF_SRC_TAG"; exit 1; }
cp "$APK" emu/app.apk
echo "Testing $APK"
