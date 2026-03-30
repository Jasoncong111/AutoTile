#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AutoTile"
BUNDLE_ID="${APP_BUNDLE_ID:-io.github.autotile.app}"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
MODULE_CACHE_DIR="$ROOT_DIR/.build/module-cache"
SDK_PATH="${SDK_PATH:-$(xcrun --show-sdk-path)}"

mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR"

swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework ApplicationServices \
  "$ROOT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR"

echo "Built: $APP_DIR"
