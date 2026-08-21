#!/bin/bash
# ==============================================================================
# Dracin Kernel Build Script - KernelSU Variant (QTI EAS)
# Source: xbore_strmbreakr_lavender
# ==============================================================================

set -e

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Configuration & Variables ---
KERNEL_DIR="$(pwd)"
OUT_DIR="$KERNEL_DIR/out"
DEFCONFIG="lavender-perf_defconfig"
CUSTOM_LOCALVERSION="-Dracin"
VERSION_TAG="LV1.0"
ROOT_METHOD="ksu"

# Output Format: "zip" (default) or "img"
OUTPUT_FORMAT="${1:-zip}"

# Handle special arguments
CLEAN_BUILD=false
for arg in "$@"; do
    case "$arg" in
        clean|--clean)
            CLEAN_BUILD=true
            ;;
        zip)
            OUTPUT_FORMAT="zip"
            ;;
        img|image)
            OUTPUT_FORMAT="img"
            ;;
    esac
done

# Base KernelBuild Root Directory
KB_ROOT="$(cd "$KERNEL_DIR/../.." && pwd)"

# Directories
OUTPUT_DIR="$KB_ROOT/ScriptBuild/output"
ANYKERNEL_DIR="$KB_ROOT/ak3/Lavender"
WINDOWS_DEST="/mnt/c/Users/KUYANG/Documents/KernelZip"

# Compiler: Proton Clang 11
CLANG_DIR="$KB_ROOT/compiler/proton-clang-11"
export PATH="$CLANG_DIR/bin:$PATH"

# Build Metadata
CLGV="$("$CLANG_DIR/bin/clang" --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
BINV="$("$CLANG_DIR/bin/aarch64-linux-gnu-ld" --version | head -n 1 | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"
LLDV="$("$CLANG_DIR/bin/ld.lld" --version | head -n 1 | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

export KBUILD_COMPILER_STRING="$CLGV - $BINV - $LLDV"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="root"
export KBUILD_BUILD_HOST="KuyStore"
export HOSTCFLAGS="-fcommon"

MAKE_ARGS=(
    ARCH=arm64
    SUBARCH=arm64
    CC=clang
    CLANG_TRIPLE=aarch64-linux-gnu-
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    STRIP=llvm-strip
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    HOSTCC=gcc
    HOSTCXX=g++
    HOSTCFLAGS="-fcommon"
    HOSTLDFLAGS="-fcommon"
)

# Banner
echo -e "${PURPLE}=================================================${NC}"
echo -e "${CYAN}   Dracin Kernel Compiler (KernelSU Variant)     ${NC}"
echo -e "${PURPLE}=================================================${NC}"
echo -e "${BLUE}📌 Source Architecture : QTI - EAS               ${NC}"
echo -e "${BLUE}📌 Target Defconfig    : $DEFCONFIG${NC}"
echo -e "${BLUE}📌 Variant             : KernelSU${NC}"
echo -e "${BLUE}📌 Output Format       : $OUTPUT_FORMAT${NC}"
echo -e "${BLUE}📌 Compiler            : $CLGV${NC}"
echo -e "${PURPLE}=================================================${NC}"

# Clean out directory if requested
if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${YELLOW}🧹 Cleaning build output directory ($OUT_DIR)...${NC}"
    rm -rf "$OUT_DIR"
fi

BUILD_START=$(date +"%s")
mkdir -p "$OUT_DIR"

# Generate Base Config
echo -e "${BLUE}⚙️ Loading base defconfig: $DEFCONFIG...${NC}"
make O=out "${MAKE_ARGS[@]}" "$DEFCONFIG"

# Apply Custom Config Options (KSU)
echo -e "${BLUE}⚙️ Customizing config options for KernelSU (EAS - QTI)...${NC}"
scripts/config --file out/.config --set-str LOCALVERSION "$CUSTOM_LOCALVERSION"
scripts/config --file out/.config --disable LOCALVERSION_AUTO

echo -e "${YELLOW}⚙️ Enabling KernelSU & OverlayFS...${NC}"
scripts/config --file out/.config --enable CONFIG_KSU
scripts/config --file out/.config --enable CONFIG_OVERLAY_FS

# Sync Config
make O=out "${MAKE_ARGS[@]}" olddefconfig

# Compile Kernel
echo -e "${BLUE}🔧 Compiling kernel with $(nproc --all) threads...${NC}"
make -j"$(nproc --all)" O=out "${MAKE_ARGS[@]}"

# Check Outcome
KERNEL_IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
if [ ! -f "$KERNEL_IMG" ]; then
    echo -e "${RED}❌ Error: Build failed! Compiled image not found at $KERNEL_IMG${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Kernel compiled successfully!${NC}"

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))
MINUTES=$((DIFF / 60))
SECONDS=$((DIFF % 60))

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WINDOWS_DEST"

BASE_NAME="Dracin-${VERSION_TAG}-EAS-QTI-${ROOT_METHOD}"

if [ "$OUTPUT_FORMAT" = "img" ]; then
    OUTPUT_FILE="$OUTPUT_DIR/${BASE_NAME}-boot.img"
    cp "$KERNEL_IMG" "$OUTPUT_FILE"
    cp "$OUTPUT_FILE" "$WINDOWS_DEST/"
    echo -e "${GREEN}📦 Output Image: $OUTPUT_FILE${NC}"
else
    OUTPUT_FILE="$OUTPUT_DIR/${BASE_NAME}.zip"
    echo -e "${BLUE}📦 Packaging AnyKernel3 flashable ZIP: $(basename "$OUTPUT_FILE")...${NC}"
    
    cd "$ANYKERNEL_DIR"
    cp "$KERNEL_IMG" .
    zip -r9 "$OUTPUT_FILE" * -x .git README.md *placeholder
    cd "$KERNEL_DIR"
    
    cp "$OUTPUT_FILE" "$WINDOWS_DEST/"
    echo -e "${GREEN}📦 Output ZIP: $OUTPUT_FILE${NC}"
fi

echo -e "${PURPLE}=================================================${NC}"
echo -e "${GREEN}🎉 Build Completed in ${MINUTES}m ${SECONDS}s!${NC}"
echo -e "${CYAN}📁 Saved to Linux   : $OUTPUT_FILE${NC}"
echo -e "${CYAN}📁 Copied to Windows : $WINDOWS_DEST/$(basename "$OUTPUT_FILE")${NC}"
echo -e "${PURPLE}=================================================${NC}"
