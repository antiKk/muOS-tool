#!/bin/sh

# shellcheck source=/dev/null

# ==== About ====
# ScummVM build script for MustardOS
# Created specifically for MustardOS 2508.0 Goose
# This assumes you have a Cross Compilation environment setup with appropriate toolchains.

# ===== Usage =====
usage() {
    echo "Usage: $(basename "$0") <device> [tag]"
    echo ""
    echo "  device   Target device. Supported: h700, a133p, rk3326, rk3576"
    echo "  tag      Git tag to build (default: master)"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") h700"
    echo "  $(basename "$0") h700 2.9.0"
    exit 1
}

[ -z "$1" ] && usage

# Stop if any command fails
set -e

# ===== Args =====
# Usage: ./build_scummvm.sh <device> [tag]
# If no tag is supplied, master is used.
DEVICE="$1"
TAG="${2:-}"

# ===== Device Info =====
# Set the appropriate toolchain script based on device selected
# Adjust paths to suit
case "$DEVICE" in
    h700)
        TOOLCHAIN_SCRIPT="$HOME/x-tools/h700-muos-cc.sh"
        SVM_BIN="scummvm-rg"
        ;;
    a133p)
        TOOLCHAIN_SCRIPT="$HOME/x-tools/a133p-muos-cc.sh"
        SVM_BIN="scummvm-tui"
        ;;
    rk3326)
        TOOLCHAIN_SCRIPT="$HOME/x-tools/rk3326-muos-cc.sh"
        SVM_BIN="scummvm-rk"
        ;;
    rk3576)
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/rk3576-muos-cc.sh"
        SVM_BIN="scummvm-vita"
        ;;
    *)
        echo "Error: Unknown device '$DEVICE'. Supported: h700, a133p, rk3326, rk3576"
        exit 1
        ;;
esac

# Check if the toolchain script exists
if [ ! -f "$TOOLCHAIN_SCRIPT" ]; then
    echo "Error: Toolchain script not found at: $TOOLCHAIN_SCRIPT"
    echo "Please update the path in $(basename "$0")"
    exit 1
fi

echo "Device:    $DEVICE"
echo "Tag:       ${TAG:-master (latest)}"
echo "Toolchain: $TOOLCHAIN_SCRIPT"

# ===== Settings =====
REPO_URL="https://github.com/scummvm/scummvm.git"
REPO_DIR="scummvm"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/scummvm/output"
# Patch naming convention:
#   scummvm-patch-NNN-description.patch        — applied to all devices
#   scummvm-patch-NNN-description_device.patch — applied to matching device only
PATCH_DIR="$SCRIPT_DIR/scummvm-patches"

# ===== Clone or Update =====
echo "[Step 01] Cloning or Updating ScummVM Repository..."

if [ -d "$REPO_DIR/.git" ]; then
    echo "Updating existing ScummVM clone..."
    cd "$REPO_DIR"

    # Clean any previously applied patches or local changes before switching
    git reset --hard
    git clean -fd

    git fetch --tags origin

    if [ -n "$TAG" ]; then
        echo "Checking out tag: $TAG"
        git checkout "tags/$TAG"
    else
        echo "Updating master to latest..."
        git checkout master
        git pull origin master
    fi

    git submodule update --init --recursive
else
    if [ -n "$TAG" ]; then
        echo "Cloning ScummVM at tag $TAG..."
        git clone --recurse-submodules --branch "$TAG" "$REPO_URL" "$REPO_DIR"
    else
        echo "Cloning ScummVM (master)..."
        git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"
    fi
    cd "$REPO_DIR"
fi

# ===== Apply Patches =====
echo "[Step 02] Applying patches..."
if [ -d "$PATCH_DIR" ]; then
    for PATCH_FILE in "$PATCH_DIR"/*.patch; do
        [ -f "$PATCH_FILE" ] || continue

        PATCH_NAME="$(basename "$PATCH_FILE" .patch)"

        # Check if patch has a device suffix (e.g. _rk3576)
        PATCH_DEVICE="${PATCH_NAME##*_}"
        if [ "$PATCH_DEVICE" != "$PATCH_NAME" ]; then
            # Has a device suffix — skip if it doesn't match current device
            if [ "$PATCH_DEVICE" != "$DEVICE" ]; then
                echo "Skipping $(basename "$PATCH_FILE") (not $DEVICE)"
                continue
            fi
        fi

        echo "Applying patch: $(basename "$PATCH_FILE")"
        patch -p1 < "$PATCH_FILE"
    done
else
    echo "Patch directory not found: $PATCH_DIR"
fi

# ===== Init Toolchain =====
echo "[Step 03] Loading toolchain environment..."
. "$TOOLCHAIN_SCRIPT"

# We need to explicitly point at Freetype2
export CFLAGS="$CFLAGS -I$SYSROOT/usr/include/freetype2"
export CXXFLAGS="$CXXFLAGS -I$SYSROOT/usr/include/freetype2"
export LDFLAGS="$LDFLAGS -L$SYSROOT/usr/lib"

# ===== Configure =====
echo "[Step 04] Configuring ScummVM..."

# Device-specific configure flags
DEVICE_CONFIGURE_FLAGS=""
case "$DEVICE" in
    rk3576)
        DEVICE_CONFIGURE_FLAGS="--enable-sdl-ts-vmouse"
        ;;
esac

./configure \
  --host=aarch64-linux \
  --disable-debug \
  --enable-release \
  --disable-taskbar \
  --enable-vkeybd \
  --enable-text-console \
  --enable-ext-neon \
  --enable-dlc \
  --enable-scummvmdlc \
  --enable-freetype2 \
  --opengl-mode=gles2 \
  --with-sdl-prefix="$SYSROOT/usr/bin" \
  --with-freetype2-prefix="$SYSROOT/usr/bin" \
  --with-libcurl-prefix="$SYSROOT/usr" \
  $DEVICE_CONFIGURE_FLAGS

# ===== Build =====
echo "[Step 05] Building ScummVM..."
make -j"$(nproc)"

# ===== Prepare Binary =====
echo "[Step 06] Preparing binary for muOS..."
$STRIP "scummvm"
mv "scummvm" "$SVM_BIN"
md5sum "$SVM_BIN" | cut -d ' ' -f 1 > "$SVM_BIN.md5"
tar -czf "${SVM_BIN}.tar.gz" "$SVM_BIN"

# ===== Bundle Files =====
echo "[Step 07] Bundling all required files..."

mkdir -p "$OUT_DIR"

echo "Copying binary and hash..."
cp -f "$SCRIPT_DIR/scummvm/${SVM_BIN}.tar.gz" "$OUT_DIR/${SVM_BIN}.tar.gz"
cp -f "$SCRIPT_DIR/scummvm/${SVM_BIN}.md5" "$OUT_DIR/${SVM_BIN}.md5"

mkdir -p "$OUT_DIR/doc"
echo "Copying licenses..."
cp -f "$SCRIPT_DIR/scummvm/LICENSES/"* "$OUT_DIR/doc/"

mkdir -p "$OUT_DIR/Theme"
echo "Copying themes..."
cp -f "$SCRIPT_DIR/scummvm/gui/themes/"*.dat "$SCRIPT_DIR/scummvm/gui/themes/"*.zip "$OUT_DIR/Theme/"
cp -f "$SCRIPT_DIR/scummvm/dists/networking/wwwroot.zip" "$OUT_DIR/Theme/"

mkdir -p "$OUT_DIR/Extra"
echo "Copying extra data..."
cp -f -r "$SCRIPT_DIR/scummvm/dists/engine-data/"* "$OUT_DIR/Extra/"
cp -f "$SCRIPT_DIR/scummvm/backends/vkeybd/packs/vkeybd_default.zip" "$OUT_DIR/Extra"

mkdir -p "$OUT_DIR/Extra/shaders/"
echo "Collecting GLSL shaders..."
find "$SCRIPT_DIR/scummvm/engines/" -type f \( -name '*.fragment' -o -name '*.vertex' \) -exec cp -f {} "$OUT_DIR/Extra/shaders/" \;

# ===== Cleanup =====
rm -f "$SCRIPT_DIR/scummvm/$SVM_BIN"
rm -f "$SCRIPT_DIR/scummvm/${SVM_BIN}.md5"
rm -f "$SCRIPT_DIR/scummvm/${SVM_BIN}.tar.gz"

# ===== Finish =====
echo "✅ Build complete."
echo "All files should now be available in $OUT_DIR"
