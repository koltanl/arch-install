#!/bin/bash
set -e

# Define variables
ISO_PATH="/home/anon/Downloads/debian.iso"
EXTRACT_DIR="/tmp/iso_extract"
NEW_ISO_PATH="/home/anon/Downloads/debianRepack.iso"
PRESEED_PATH="/home/anon/Downloads/preseed.cfg"


# Create extraction directory
mkdir -p "$EXTRACT_DIR"

# Mount the ISO
sudo mount -o loop "$ISO_PATH" "$EXTRACT_DIR"

# Create a working directory
WORK_DIR=$(mktemp -d)

# Copy ISO contents
cp -rT "$EXTRACT_DIR" "$WORK_DIR"

# Unmount the ISO
sudo umount "$EXTRACT_DIR"

# Copy preseed file
cp "$PRESEED_PATH" "$WORK_DIR/preseed.cfg"

# Regenerate MD5 sums
cd "$WORK_DIR"
find . -type f -print0 | xargs -0 md5sum > md5sum.txt

# Create new ISO
xorriso -as mkisofs -r -J -joliet-long -l -iso-level 3 \
    -partition_offset 16 \
        -V "Debian custom" \
            -b isolinux/isolinux.bin \
                -c isolinux/boot.cat \
                    -no-emul-boot -boot-load-size 4 -boot-info-table \
                        -eltorito-alt-boot \
                            -e boot/grub/efi.img \
                                -no-emul-boot \
                                    -isohybrid-gpt-basdat \
                                        -o "$NEW_ISO_PATH" "$WORK_DIR"

                                    # Clean up
                                    rm -rf "$WORK_DIR" "$EXTRACT_DIR"

                                    echo "New ISO created at $NEW_ISO_PATH"
