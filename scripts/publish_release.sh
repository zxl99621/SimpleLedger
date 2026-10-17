#!/usr/bin/env bash
# 在 GitHub 和 Gitee 创建 Release，并上传 APK + 源码包。
#
# 前置条件：
#   GitHub: gh auth login（或设置 GH_TOKEN）
#   Gitee:  在 https://gitee.com/profile/personal_access_tokens 创建带 projects
#           权限的 token，设置 GITEE_TOKEN，或写入 D:/AndroidDevCache/gitee_token.txt
#
# 用法：
#   scripts/publish_release.sh [版本号]   # 默认取 pubspec.yaml 的版本
set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON="${PYTHON:-python}"
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python3

VERSION="${1:-$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)}"
TAG="v$VERSION"
DIST_DIR="${DIST_DIR:-/f/SimpleLedger-dist}"
APK="$DIST_DIR/SimpleLedger-$VERSION-release.apk"
SRC="$DIST_DIR/SimpleLedger-$VERSION-source.zip"
NOTES="docs/releases/v$VERSION.md"
GH_REPO="${GH_REPO:-zxl99621/SimpleLedger}"
GITEE_REPO="${GITEE_REPO:-zxl996/simple-ledger}"

[ -f "$APK" ] || { echo "APK not found: $APK" >&2; exit 1; }
[ -f "$SRC" ] || { echo "Source zip not found: $SRC" >&2; exit 1; }
[ -f "$NOTES" ] || { echo "Release notes not found: $NOTES" >&2; exit 1; }

echo "Publishing SimpleLedger $VERSION ($TAG)"
echo "  APK:    $APK"
echo "  Source: $SRC"
echo "  Notes:  $NOTES"

# ---------- GitHub ----------
if gh auth status >/dev/null 2>&1; then
  if gh release view "$TAG" -R "$GH_REPO" >/dev/null 2>&1; then
    echo "GitHub release $TAG already exists; uploading assets..."
    gh release upload "$TAG" "$APK" "$SRC" -R "$GH_REPO" --clobber
  else
    echo "Creating GitHub release $TAG..."
    gh release create "$TAG" "$APK" "$SRC" \
      -R "$GH_REPO" \
      --title "SimpleLedger $VERSION" \
      --notes-file "$NOTES"
  fi
else
  echo "GitHub: gh is not authenticated; skipping. Run 'gh auth login' first." >&2
fi

# ---------- Gitee ----------
TOKEN="${GITEE_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "D:/AndroidDevCache/gitee_token.txt" ]; then
  TOKEN="$(tr -d '\r\n' < "D:/AndroidDevCache/gitee_token.txt")"
fi
if [ -z "$TOKEN" ]; then
  echo "Gitee: GITEE_TOKEN is not set; skipping. Save a token to D:/AndroidDevCache/gitee_token.txt or export GITEE_TOKEN." >&2
  exit 0
fi

api="https://gitee.com/api/v5/repos/$GITEE_REPO/releases"
existing="$(curl -s "$api/tags/$TAG" | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))' 2>/dev/null || true)"
if [ -z "$existing" ]; then
  echo "Creating Gitee release $TAG..."
  existing="$(curl -s -X POST "$api" \
    --data-urlencode "access_token=$TOKEN" \
    --data-urlencode "tag_name=$TAG" \
    --data-urlencode "name=SimpleLedger $VERSION" \
    --data-urlencode "body@$NOTES" \
    --data-urlencode "target_commitish=main" \
    --data-urlencode "prerelease=false" \
    | "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id",""))')"
fi
[ -n "$existing" ] || { echo "Failed to create/find Gitee release" >&2; exit 1; }

echo "Uploading assets to Gitee release id=$existing..."
for file in "$APK" "$SRC"; do
  curl -s -X POST "$api/$existing/attach_files" \
    -F "access_token=$TOKEN" \
    -F "file=@$file" >/dev/null
  echo "  uploaded $(basename "$file")"
done

echo "Done."
