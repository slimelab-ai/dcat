#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_DIR/build-release"
BIN_DIR="$HOME/.local/bin"

echo "[dizzcat] Installing system dependencies (needs sudo)..."
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config meson ninja-build \
  libvulkan-dev libassimp-dev libcglm-dev libvips-dev libsixel-dev \
  glslang-tools

echo "[dizzcat] Configuring build..."
meson setup "$BUILD_DIR" "$REPO_DIR" --buildtype=release --reconfigure
meson compile -C "$BUILD_DIR"

mkdir -p "$BIN_DIR" "$BIN_DIR/shaders"
cp "$BUILD_DIR/dcat" "$BIN_DIR/dizzcat-bin"
cp "$BUILD_DIR"/*.spv "$BIN_DIR/shaders/"
cat > "$BIN_DIR/dizzcat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BIN="$HOME/.local/bin/dizzcat-bin"
exec "$BIN" "$@"
EOF
chmod +x "$BIN_DIR/dizzcat" "$BIN_DIR/dizzcat-bin"

echo "[dizzcat] Installed as: $BIN_DIR/dizzcat"
echo "[dizzcat] Run with: dizzcat /path/to/model.glb"
