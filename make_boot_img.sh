#!/usr/bin/env bash
# Helper script to unpack stock boot.img, optionally apply APatch, and repack it
# Created for Lavender Kernel Build by Antigravity AI

set -e

KITCHEN_DIR="/home/dev/KernelBuild/BootKitchen"
KERNEL_IMG_MYSTIC="/home/dev/KernelBuild/mystic-caf/out/arch/arm64/boot/Image.gz"
KERNEL_IMG_STORMBREAKER="/home/dev/KernelBuild/stormbreaker_official/out/arch/arm64/boot/Image.gz-dtb"
KERNEL_IMG_XBORE="/home/dev/KernelBuild/xbore_strmbreakr_lavender/out/arch/arm64/boot/Image.gz-dtb"

# Telegram Settings
ENABLE_TELEGRAM=true
TG_BOT_TOKEN="8969845430:AAFSC5uOY43wQYD_n2DgjE4HDYBKCCVwdpY"
TG_CHAT_ID="-1004470799223"

cd "$KITCHEN_DIR"

if [ ! -f "boot.img" ]; then
    echo -e "\033[0;31mError: Please place your stock boot.img inside $KITCHEN_DIR/ and name it 'boot.img'!\033[0m"
    exit 1
fi

echo -e "\033[0;36mSelect which compiled kernel to inject:\033[0m"
select opt in "Mystic (Image.gz)" "Stormbreaker (Image.gz-dtb)" "xBore (Image.gz-dtb)"; do
    case $opt in
        "Mystic (Image.gz)")
            KERNEL_SRC="$KERNEL_IMG_MYSTIC"
            break
            ;;
        "Stormbreaker (Image.gz-dtb)")
            KERNEL_SRC="$KERNEL_IMG_STORMBREAKER"
            break
            ;;
        "xBore (Image.gz-dtb)")
            KERNEL_SRC="$KERNEL_IMG_XBORE"
            break
            ;;
        *) echo -e "\033[0;31mInvalid option. Choose 1, 2, or 3.\033[0m" ;;
    esac
done

if [ ! -f "$KERNEL_SRC" ]; then
    echo -e "\033[0;31mError: Compiled kernel image not found at $KERNEL_SRC!\033[0m"
    echo -e "\033[0;31mPlease compile your kernel first using the build scripts.\033[0m"
    exit 1
fi

echo -e "\033[0;33m🧹 Cleaning kitchen directory...\033[0m"
./magiskboot cleanup
rm -f kernel_unpatched kernel_patched lavender-patched-0.12.6.img new-boot.img

echo -e "\033[0;33m📦 Unpacking stock boot.img...\033[0m"
./magiskboot unpack boot.img

# Ask if user wants to patch with APatch
read -p "Do you want to patch this kernel with APatch 0.12.6? (y/n): " APPLY_APATCH
if [[ "$APPLY_APATCH" =~ ^[Yy]$ ]]; then
    # Ask for Superkey (default: kuystore26)
    read -p "Enter APatch Superkey (default: kuystore26): " SKEY
    if [ -z "$SKEY" ]; then
        SKEY="kuystore26"
    fi
    echo -e "\033[0;32mUsing Superkey: $SKEY\033[0m"

    echo -e "\033[0;33m🔧 Applying APatch 0.12.6 (KernelPatch) to kernel image...\033[0m"
    # Decompress the kernel image first, as kptools requires an uncompressed kernel image (e.g. raw Image)
    if ! ./magiskboot decompress "$KERNEL_SRC" kernel_unpatched 2>/dev/null; then
        cp "$KERNEL_SRC" kernel_unpatched
    fi
    
    # Run the native kptools-linux executable
    ./kptools-linux -p -i kernel_unpatched -k kpimg-android -s "$SKEY" -o kernel

    echo -e "\033[0;33m🔨 Repacking patched boot image...\033[0m"
    ./magiskboot repack boot.img lavender-patched-0.12.6.img

    # Cleanup temp kernel files
    rm -f kernel_unpatched kernel

    echo -e "\033[0;32m=================================================\033[0m"
    echo -e "\033[0;32m🎉 Success! Patched APatch boot image is ready at:\033[0m"
    echo -e "\033[0;32m   $KITCHEN_DIR/lavender-patched-0.12.6.img\033[0m"
    echo -e "\033[0;32m=================================================\033[0m"
else
    echo -e "\033[0;33m🔧 Injecting raw unpatched kernel image...\033[0m"
    cp "$KERNEL_SRC" kernel

    echo -e "\033[0;33m🔨 Repacking standard boot image...\033[0m"
    ./magiskboot repack boot.img new-boot.img

    # Cleanup temp kernel file
    rm -f kernel

    echo -e "\033[0;32m=================================================\033[0m"
    echo -e "\033[0;32m🎉 Success! Standard boot image is ready at:\033[0m"
    echo -e "\033[0;32m   $KITCHEN_DIR/new-boot.img\033[0m"
    echo -e "\033[0;32m=================================================\033[0m"
fi

# Telegram Notification integration
if [ "$ENABLE_TELEGRAM" = "true" ] && [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    echo -e "\033[0;34mPreparing and compressing boot image for Telegram...\033[0m"
    if [ -f "lavender-patched-0.12.6.img" ]; then
        IMG_FILE="lavender-patched-0.12.6.img"
        IMG_TYPE="APatch v0.12.6 (Patched)"
    elif [ -f "new-boot.img" ]; then
        IMG_FILE="new-boot.img"
        IMG_TYPE="Standard Boot Image (Unpatched)"
    else
        echo -e "\033[0;31mError: No generated boot image found to send to Telegram!\033[0m"
        exit 1
    fi

    # Calculate original MD5 checksum
    MD5_SUM=$(md5sum "$IMG_FILE" | cut -d' ' -f1)
    
    # Create ZIP archive of the boot image (to bypass Telegram Bot API 50MB file size limit)
    ZIP_FILE="$IMG_FILE.zip"
    rm -f "$ZIP_FILE"
    zip -q -j9 "$ZIP_FILE" "$IMG_FILE"

    echo -e "\033[0;34mSending compressed boot image and notification to Telegram...\033[0m"
    CAPTION="<b>device :</b> <code>lavender</code>
<b>type :</b> <code>$IMG_TYPE</code>
<b>md5 checksum :</b> <code>$MD5_SUM</code>"

    curl -X POST https://api.telegram.org/bot"${TG_BOT_TOKEN}"/sendDocument \
        -F chat_id="${TG_CHAT_ID}" \
        -F "document=@$ZIP_FILE" \
        --form-string caption="$CAPTION" \
        -F "parse_mode=html" \
        -F "disable_web_page_preview=true"
    
    # Clean up the temporary ZIP file
    rm -f "$ZIP_FILE"
    
    echo -e "\033[0;32mTelegram notification sent successfully!\033[0m"
fi
