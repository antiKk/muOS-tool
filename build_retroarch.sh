#!/bin/sh

# shellcheck source=/dev/null

# ==== About ====
# Retroarch build script for MustardOS
# Created specifically for MustardOS 2508.0 Goose
# This assumes you have a Cross Compile environment setup with appropriate toolchains.

# Stop if any command fails
set -e

# ===== Args =====
# Usage: ./build_retroarch.sh <device> [tag]
# If no tag is supplied, master is used.
DEVICE="$1"
TAG="${2:-}"

# ===== Device Info =====
# Set the appropriate toolchain script based on device selected
# Adjust paths to suit
case "$DEVICE" in
    h700)
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/h700-muos-cc.sh"
        RA_BIN="retroarch-rg"
        ;;
    a133p)
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/a133p-muos-cc.sh"
        RA_BIN="retroarch-tui"
        ;;
    rk3326)
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/rk3326-muos-cc.sh"
        RA_BIN="retroarch-rk"
        ;;
    rk3576)
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/rk3576-muos-cc.sh"
        RA_BIN="retroarch-vita"
        EXTRA_CFLAGS="-DHAVE_RGA_ROTATION"
        EXTRA_LDFLAGS="-lrga"
        ;;
    *)
        echo "Error: Unknown device '$DEVICE'. Supported: h700, a133p, rk3326, rk3576"
        exit 1
        ;;
esac

echo "Device:    $DEVICE"
echo "Tag:       ${TAG:-master (latest)}"
echo "Toolchain: $TOOLCHAIN_SCRIPT"

# ===== Settings =====
REPO_URL="https://github.com/libretro/RetroArch.git"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# We patch Ozone to better scale on small screens (maybe other things?)
# Assumes patches live in "retroarch-patches" folder in script directory.
# Patch naming convention:
#   retroarch-patch-NNN-description.patch        — applied to all devices
#   retroarch-patch-NNN-description_device.patch — applied to matching device only
PATCH_DIR="$SCRIPT_DIR/retroarch-patches"

# ===== Clone or Update =====
if [ -d "RetroArch/.git" ]; then
    echo "[1/8] Updating existing RetroArch clone..."
    cd RetroArch

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
else
    if [ -n "$TAG" ]; then
        echo "[1/8] Cloning RetroArch at tag $TAG..."
        git clone --branch "$TAG" "$REPO_URL"
    else
        echo "[1/8] Cloning RetroArch (master)..."
        git clone "$REPO_URL"
    fi
    cd RetroArch
fi

echo "[2/8] Loading toolchain environment..."
. "$TOOLCHAIN_SCRIPT"

export CXXFLAGS="$CXXFLAGS -I${SYSROOT}/usr/include/glslang"

echo "[3/8] Applying patches..."
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

export CFLAGS="-I${SYSROOT}/usr/include/freetype2 -fno-tree-vectorize ${EXTRA_CFLAGS:-}"
export CPPFLAGS="-I${SYSROOT}/usr/include/freetype2"
export LDFLAGS="-L${SYSROOT}/usr/lib ${EXTRA_LDFLAGS:-}"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
export PKG_CONFIG_PATH="${SYSROOT}/usr/lib/pkgconfig:${SYSROOT}/usr/share/pkgconfig"
export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig"

# ===== Configure Flags =====
# Common flags shared across all devices
CONFIGURE_FLAGS="
  --enable-xdelta
  --enable-sdl2
  --enable-udev
  --enable-egl
  --enable-kms
  --enable-opengles
  --disable-neon
  --disable-rbmp
  --disable-translate
  --disable-opengl
  --disable-glslang
  --disable-nvda
  --disable-materialui
  --disable-systemd
  --disable-x11
  --disable-xrandr
  --disable-xinerama
  --disable-wayland
  --disable-cdrom
  --enable-libshake
  --disable-crtswitchres
  --enable-hid
  --disable-vulkan
  --disable-qt
  --disable-pulse
  --disable-oss
  --enable-alsa
  --enable-pipewire
  --enable-command
  --enable-threads
  --enable-bluetooth
  --disable-parport
  --disable-ffmpeg
"

# Device-specific flag overrides/additions
# Add flags here that differ from or extend the common set above
case "$DEVICE" in
    h700)
        # No overrides needed — common flags cover this device
        ;;
    a133p)
        # No overrides needed — common flags cover this device
        ;;
    rk3326)
        # No overrides needed — common flags cover this device
        ;;
    rk3576)
        CONFIGURE_FLAGS="$CONFIGURE_FLAGS
  --enable-vulkan
  --enable-wayland
  --enable-builtinglslang
"
        CONFIGURE_FLAGS=$(echo "$CONFIGURE_FLAGS" | grep -v -- "--disable-vulkan" | grep -v -- "--disable-wayland" | grep -v -- "--disable-glslang")
        ;;
esac

echo "[4/8] Configuring RetroArch..."
# shellcheck disable=SC2086
./configure $CONFIGURE_FLAGS

echo "[5/8] Fixing include/lib paths..."
#sed -i s#/usr/include#"$SYSROOT"/usr/include#g config.mk
#sed -i s#/usr/lib#"$SYSROOT"/usr/lib#g config.mk

#sed -i 's/vshll_n_u16(vget_low_u16(vmovl_u8(a)),  24)/vshlq_n_u32(vmovl_u16(vget_low_u16(vmovl_u8(a))), 24)/' libretro-common/formats/png/rpng.c
#sed -i 's/vshll_n_u16(vget_high_u16(vmovl_u8(a)), 24)/vshlq_n_u32(vmovl_u16(vget_high_u16(vmovl_u8(a))), 24)/' libretro-common/formats/png/rpng.c

echo "[6/8] Building RetroArch..."
make -j"$(nproc)"

echo "[7/8] Stripping RetroArch binary..."
$STRIP "retroarch"

echo "[8/8] Calculating MD5 and renaming for MustardOS..."
mv "retroarch" "$RA_BIN"
md5sum "$RA_BIN" | cut -d ' ' -f 1 > "$RA_BIN.md5"

echo "✅ Build complete."
echo "$RA_BIN and $RA_BIN.md5 have been created in $SCRIPT_DIR/RetroArch."
