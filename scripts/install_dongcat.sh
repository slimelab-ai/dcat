#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_DIR/build"
BIN_DIR="$HOME/.local/bin"

echo "[dongcat] Installing system dependencies (needs sudo)..."
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config meson ninja-build \
  libvulkan-dev libassimp-dev libcglm-dev libvips-dev libsixel-dev \
  glslang-tools

echo "[dongcat] Configuring build..."
meson setup "$BUILD_DIR" "$REPO_DIR" --reconfigure
meson compile -C "$BUILD_DIR"

mkdir -p "$BIN_DIR"
cp "$BUILD_DIR/dcat" "$BIN_DIR/dongcat"
chmod +x "$BIN_DIR/dongcat"

echo "[dongcat] Installed as: $BIN_DIR/dongcat"
echo "[dongcat] Run with: dongcat /path/to/model.glb"
