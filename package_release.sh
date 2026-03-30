#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
APP_PATH="$ROOT_DIR/dist/AutoTile.app"
ZIP_PATH="$RELEASE_DIR/AutoTile-macOS.zip"

bash "$ROOT_DIR/build.sh"

mkdir -p "$RELEASE_DIR"
rm -f "$ZIP_PATH"

cd "$ROOT_DIR/dist"
ditto -c -k --sequesterRsrc --keepParent "AutoTile.app" "$ZIP_PATH"

echo "已生成发布包: $ZIP_PATH"
