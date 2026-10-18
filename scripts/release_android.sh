#!/usr/bin/env bash
# 构建 arm64 release APK，剥离其它 ABI 的 native 资产，重新对齐并签名。
#
# 用法：
#   scripts/release_android.sh              # 构建 + 剥离 + 签名 + 复制到 dist
#   SKIP_BUILD=1 scripts/release_android.sh # 复用已有 build 产物
#   DIST_DIR=/path scripts/release_android.sh
#
# CI 可通过环境变量覆盖签名信息：
#   KEYSTORE / STORE_PASS / KEY_ALIAS / KEY_PASS
#
# Windows 本地构建：Vulkan 的 host shader 生成器需要 MSVC，请在
# "x64 Native Tools Command Prompt for VS 2022" 中运行，或先执行
#   call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
# 否则构建会在 vulkan-shaders-gen 阶段失败。
set -euo pipefail

cd "$(dirname "$0")/.."

ABI="${ABI:-arm64-v8a}"
FLAVOR="${FLAVOR:-prod}"
SKIP_BUILD="${SKIP_BUILD:-0}"
DIST_DIR="${DIST_DIR:-/f/SimpleLedger-dist}"

ANDROID_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/f/Android/Sdk}}"
BUILD_TOOLS="$(find "$ANDROID_SDK/build-tools" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1)"
if [ -f "$BUILD_TOOLS/zipalign.exe" ]; then
  ZIPALIGN="$BUILD_TOOLS/zipalign.exe"
else
  ZIPALIGN="$BUILD_TOOLS/zipalign"
fi
if [ -f "$BUILD_TOOLS/apksigner.bat" ]; then
  APKSIGNER="$BUILD_TOOLS/apksigner.bat"
else
  APKSIGNER="$BUILD_TOOLS/apksigner"
fi
if [ ! -f "$ZIPALIGN" ]; then
  echo "zipalign not found under $BUILD_TOOLS" >&2
  exit 1
fi

case "$ABI" in
  arm64-v8a) TARGET_PLATFORM="android-arm64" ;;
  armeabi-v7a) TARGET_PLATFORM="android-arm" ;;
  x86_64) TARGET_PLATFORM="android-x64" ;;
  *) TARGET_PLATFORM="android-$ABI" ;;
esac

if [ "$SKIP_BUILD" != "1" ]; then
  flutter build apk --release --flavor "$FLAVOR" --target-platform "$TARGET_PLATFORM"
fi

if [ "$ABI" = "arm64-v8a" ]; then
  INPUT="build/app/outputs/flutter-apk/app-${FLAVOR}-release.apk"
else
  INPUT="build/app/outputs/flutter-apk/app-${ABI}-${FLAVOR}-release.apk"
fi
[ -f "$INPUT" ] || { echo "APK not found: $INPUT" >&2; exit 1; }

read_prop() {
  local key="$1"
  [ -f android/key.properties ] || return 0
  grep "^${key}=" android/key.properties | head -1 | cut -d= -f2- || true
}

KEYSTORE="${KEYSTORE:-$(read_prop storeFile)}"
STORE_PASS="${STORE_PASS:-$(read_prop storePassword)}"
KEY_ALIAS="${KEY_ALIAS:-$(read_prop keyAlias)}"
KEY_PASS="${KEY_PASS:-$(read_prop keyPassword)}"
if [ -z "$KEYSTORE" ] || [ -z "$STORE_PASS" ] || [ -z "$KEY_ALIAS" ] || [ -z "$KEY_PASS" ]; then
  echo "Release signing is not configured (android/key.properties or env vars)." >&2
  exit 1
fi

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$INPUT" "$TMP/stripped.apk"

echo "Removing non-$ABI native libraries..."
PYTHON="${PYTHON:-python}"
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python3
"$PYTHON" - "$TMP/stripped.apk" "$ABI" <<'PY'
import os
import sys
import zipfile

apk, target = sys.argv[1], sys.argv[2]
tmp = apk + '.new'
removed = set()
with zipfile.ZipFile(apk, 'r') as zin, zipfile.ZipFile(tmp, 'w') as zout:
    for item in zin.infolist():
        parts = item.filename.split('/')
        if len(parts) > 2 and parts[0] == 'lib' and parts[1] != target:
            removed.add(parts[1])
            continue
        data = zin.read(item.filename)
        info = zipfile.ZipInfo(item.filename, date_time=item.date_time)
        info.compress_type = item.compress_type
        info.external_attr = item.external_attr
        info.internal_attr = item.internal_attr
        info.create_system = item.create_system
        zout.writestr(info, data)
os.replace(tmp, apk)
for abi in sorted(removed):
    print(f'  removed lib/{abi}')
PY

echo "Aligning..."
"$ZIPALIGN" -P 16 -f 4 "$TMP/stripped.apk" "$TMP/aligned.apk"

mkdir -p "$DIST_DIR"
if [ "$ABI" = "arm64-v8a" ]; then
  OUT="$DIST_DIR/SimpleLedger-${VERSION}-release.apk"
else
  OUT="$DIST_DIR/SimpleLedger-${VERSION}-${ABI}.apk"
fi
echo "Signing..."
"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:$STORE_PASS" \
  --key-pass "pass:$KEY_PASS" \
  --out "$OUT" \
  "$TMP/aligned.apk"

echo "Verifying..."
"$APKSIGNER" verify --print-certs "$OUT" | head -4
ls -lh "$OUT"
sha256sum "$OUT"
