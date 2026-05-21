#!/bin/sh

# shellcheck source=/dev/null

# ==== About ====
# PPSSPP build script for MustardOS (H700)
# Created specifically for muOS 2508.0 Goose
# This assumes you have a Cross Compile environment setup with appropriate toolchains.

# Stop if any command fails
set -e

# ===== Args =====
# Usage: ./build_ppsspp.sh <device> [tag]
# If no tag is supplied, master is used.
DEVICENAME="$1"
TAG="${2:-}"

# Set the appropriate toolchain script based on device selected
# Adjust paths to suit
case "$DEVICENAME" in
    h700)
        TOOLCHAIN_CMAKE="$HOME/dev/x-tools/h700-muos-cc.cmake"
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/h700-muos-cc.sh"
        PPSSPP_BIN="PPSSPP-rg"
        ;;
    a133p)
        TOOLCHAIN_CMAKE="$HOME/dev/x-tools/a133p-muos-cc.cmake"
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/a133p-muos-cc.sh"
        PPSSPP_BIN="PPSSPP-tui"
        ;;
    rk3326)
        TOOLCHAIN_CMAKE="$HOME/dev/x-tools/rk3326-muos-cc.cmake"
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/rk3326-muos-cc.sh"
        PPSSPP_BIN="PPSSPP-rk"
        ;;
    rk3576)
        TOOLCHAIN_CMAKE="$HOME/dev/x-tools/rk3576-muos-cc.cmake"
        TOOLCHAIN_SCRIPT="$HOME/dev/x-tools/rk3576-muos-cc.sh"
        PPSSPP_BIN="PPSSPP-vita"
        ;;
    *)
        echo "Error: Unknown device '$DEVICENAME'. Supported: h700, a133p, rk3326, rk3576"
        exit 1
        ;;
esac

echo "Device:    $DEVICENAME"
echo "Tag:       ${TAG:-master (latest)}"
echo "Toolchain: $TOOLCHAIN_CMAKE"

# ===== Settings =====
REPO_URL="https://github.com/hrydgard/ppsspp.git"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/ppsspp/output/"

PATCH_DIR="$SCRIPT_DIR/ppsspp-patches"

. "$TOOLCHAIN_SCRIPT"

# ===== Prerequisites =====
# Build SDL2_ttf 2.20.2 if not already present in the sysroot.
# We check for the cmake config file specifically, as that's what cmake needs
# to resolve the SDL2_ttf::SDL2_ttf imported target.

SDL2_TTF_CMAKE_DIR="${SYSROOT}/usr/lib/cmake/SDL2_ttf"

if [ -f "${SDL2_TTF_CMAKE_DIR}/SDL2_ttfConfig.cmake" ]; then
    echo "SDL2_ttf found in sysroot, skipping build."
else
    echo "SDL2_ttf not found in sysroot, building from source..."
    rm -rf SDL2_ttf
    git clone -b release-2.20.2 https://github.com/libsdl-org/SDL_ttf.git SDL2_ttf
    cd SDL2_ttf
    mkdir build
    cd build

    cmake .. \
      -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_CMAKE" \
      -DCMAKE_INSTALL_PREFIX="/usr" \
      -DCMAKE_SYSROOT="$SYSROOT"

    make -j"$(nproc)"
    make DESTDIR="$SYSROOT" install

    cd "$SCRIPT_DIR"
fi

# ===== Start PPSSPP Build Process =====
# ===== 01 Clone PPSSPP =====

# Tag reference:
# v1.20.3, v1.20.2, v1.19.3, v1.18.1, v1.17.1

echo "[Step 01] Cloning PPSSPP..."
if [ -d "ppsspp/.git" ]; then
    echo "Updating existing PPSSPP clone..."
    cd ppsspp

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
        echo "Cloning PPSSPP at tag $TAG..."
        git clone --recursive --branch "$TAG" "$REPO_URL" ppsspp
    else
        echo "Cloning PPSSPP (master)..."
        git clone --recursive "$REPO_URL" ppsspp
    fi
    cd ppsspp
fi

# ===== 02 Apply PPSSPP patches =====

echo "[Step 02] Applying patch(es)..."
# Check if patch directory exists
if [ -d "$PATCH_DIR" ]; then
    # Loop over all patch files
    for PATCH_FILE in "$PATCH_DIR"/${DEVICENAME}*; do
        # Skip if no files match
        [ -f "$PATCH_FILE" ] || continue

        echo "Applying patch: $(basename "$PATCH_FILE")"
        patch -p1 < "$PATCH_FILE"
    done
else
    echo "Patch directory not found: $PATCH_DIR"
fi

# ===== 03 Setup CMAKE =====

echo "[Step 03] Setting cmake options..."
rm -rf build
mkdir build
cd build

# Further work may be required to optimise different device build options
case "$DEVICENAME" in
    h700)
        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_CMAKE" \
            -DCMAKE_BUILD_TYPE=Release \
            -DUSING_EGL=ON \
            -DUSING_GLES2=ON \
            -DUSING_FBDEV=ON \
            -DVULKAN=OFF \
            -DARM_NO_VULKAN=ON \
            -DCMAKE_DISABLE_FIND_PACKAGE_X11=ON \
            -DUSING_X11_VULKAN=OFF \
            -DUSE_DISCORD=OFF \
            -DMOBILE_DEVICE=ON \
            -DHEADLESS=OFF \
            -DUNITTEST=OFF \
            -DATLAS_TOOL=OFF \
            -DUSE_WAYLAND_WSI=OFF \
            -DCMAKE_C_FLAGS_RELEASE="-O3 -mcpu=cortex-a53 -mtune=cortex-a53 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_CXX_FLAGS_RELEASE="-O3 -mcpu=cortex-a53 -mtune=cortex-a53 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_PREFIX_PATH="${SYSROOT}/usr;${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -DSDL2_ttf_DIR="${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -Wno-dev
        ;;
    a133p)
        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_CMAKE" \
            -DCMAKE_BUILD_TYPE=Release \
            -DUSING_EGL=ON \
            -DUSING_GLES2=ON \
            -DUSING_FBDEV=ON \
            -DVULKAN=ON \
            -DUSING_X11_VULKAN=OFF \
            -DUSE_WAYLAND_WSI=OFF \
            -DUSE_DISCORD=OFF \
            -DUSE_MINIUPNPC=OFF \
            -DUSE_FFMPEG=ON \
            -DUSE_SYSTEM_FFMPEG=OFF \
            -DUSE_SYSTEM_LIBPNG=OFF \
            -DMOBILE_DEVICE=ON \
            -DHEADLESS=OFF \
            -DUNITTEST=OFF \
            -DATLAS_TOOL=OFF \
            -DSIMULATOR=OFF \
            -DCMAKE_C_FLAGS_RELEASE="-O3 -march=armv8-a+simd -mcpu=cortex-a53 -mtune=cortex-a53 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_CXX_FLAGS_RELEASE="-O3 -march=armv8-a+simd -mcpu=cortex-a53 -mtune=cortex-a53 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_PREFIX_PATH="${SYSROOT}/usr;${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -DSDL2_ttf_DIR="${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -Wno-dev
        ;;
    rk3326)
        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_CMAKE" \
            -DCMAKE_BUILD_TYPE=Release \
            -DUSING_EGL=ON \
            -DUSING_GLES2=ON \
            -DUSING_FBDEV=ON \
            -DCMAKE_DISABLE_FIND_PACKAGE_Vulkan=ON \
            -DCMAKE_DISABLE_FIND_PACKAGE_X11=ON \
            -DUSING_X11_VULKAN=OFF \
            -DUSING_X11=OFF \
            -DUSE_DISCORD=OFF \
            -DCMAKE_C_FLAGS_RELEASE="-O3 -mcpu=cortex-a35 -mtune=cortex-a35 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_CXX_FLAGS_RELEASE="-O3 -mcpu=cortex-a35 -mtune=cortex-a35 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_PREFIX_PATH="${SYSROOT}/usr;${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -DSDL2_ttf_DIR="${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -Wno-dev
        ;;
    rk3576)
        cmake .. \
            -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_CMAKE" \
            -DCMAKE_BUILD_TYPE=Release \
            -DUSING_EGL=ON \
            -DUSING_GLES2=ON \
            -DUSING_FBDEV=ON \
            -DVULKAN=ON \
            -DUSE_VULKAN_DISPLAY_KHR=ON \
            -DCMAKE_DISABLE_FIND_PACKAGE_X11=ON \
            -DUSING_X11_VULKAN=OFF \
            -DUSING_X11=OFF \
            -DUSE_WAYLAND_WSI=OFF \
            -DUSE_DISCORD=OFF \
            -DUSE_MINIUPNPC=OFF \
            -DMOBILE_DEVICE=ON \
            -DHEADLESS=OFF \
            -DUNITTEST=OFF \
            -DATLAS_TOOL=OFF \
            -DCMAKE_C_FLAGS_RELEASE="-O3 -march=armv8-a+simd -mcpu=cortex-a72 -mtune=cortex-a72 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_CXX_FLAGS_RELEASE="-O3 -march=armv8-a+simd -mcpu=cortex-a72 -mtune=cortex-a72 -fomit-frame-pointer -fstrict-aliasing" \
            -DCMAKE_PREFIX_PATH="${SYSROOT}/usr;${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -DSDL2_ttf_DIR="${SYSROOT}/usr/lib/cmake/SDL2_ttf" \
            -Wno-dev
        ;;
    *)
        exit 1
        ;;
esac

# ===== 04 Make PPSSPP =====

echo "[Step 04] Building PPSSPP..."
make -j"$(nproc)"

# ===== 05 Cleanup the binary =====

echo "[Step 05] Prepare the resultant binary"

# Strip binary
$STRIP PPSSPPSDL

# Calculate MD5 and rename
mv "PPSSPPSDL" "$PPSSPP_BIN"
md5sum "$PPSSPP_BIN" | cut -d ' ' -f 1 > "$PPSSPP_BIN.md5"

# Compress binary for use in muOS
cd "$SCRIPT_DIR"
tar -czf "$SCRIPT_DIR/ppsspp/build/${PPSSPP_BIN}.tar.gz" -C ppsspp/build "$PPSSPP_BIN"
rm "$SCRIPT_DIR/ppsspp/build/$PPSSPP_BIN"

# ===== 06 Package PPSSPP =====

echo "[Step 06] Package PPSSPP files for use in muOS"

mkdir -p "$OUT_DIR"
rsync -a --exclude=debugger ppsspp/assets/ "$OUT_DIR"
cp -f $SCRIPT_DIR/ppsspp/build/${PPSSPP_BIN}.* "$OUT_DIR"

# ===== Finish =====

echo "✅ Build complete."
echo "All files have been placed in $OUT_DIR"
