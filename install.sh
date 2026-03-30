#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/dist/AutoTile.app"
TARGET_PATH="/Applications/AutoTile.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "未找到构建产物，请先运行: bash build.sh"
  exit 1
fi

echo "正在安装到 $TARGET_PATH"
rm -rf "$TARGET_PATH"
cp -R "$APP_PATH" "$TARGET_PATH"

echo
echo "安装完成。"
echo "下一步："
echo "1. 打开 /Applications/AutoTile.app"
echo "2. 在 系统设置 -> 隐私与安全性 -> 辅助功能 中允许 AutoTile"
