#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
echo "Please run this script as root or using sudo."
exit 1
fi

# Define the target device
TARGET_DEVICE="/dev/sdc"

# Print drive size
echo "Drive size of $TARGET_DEVICE:"
lsblk -ndo SIZE $TARGET_DEVICE

# Confirmation prompt
read -p "Are you sure you want to wipe $TARGET_DEVICE and write the ISO to it? This will erase all data on the device. (y/N): " confirm
if [[ $confirm != [yY] ]]; then
echo "Operation cancelled."
exit 1
fi

# Unmount the device if it's mounted
echo "Unmounting $TARGET_DEVICE if mounted..."
umount ${TARGET_DEVICE}* 2>/dev/null

# Wipe out the partition table
echo "Wiping out the partition table on $TARGET_DEVICE..."
dd if=/dev/zero of=$TARGET_DEVICE bs=512 count=1 conv=notrunc

# Check if wiping was successful
if [ $? -ne 0 ]; then
echo "Wiping partition table failed. Exiting."
exit 1
fi
echo "Partition table wiped successfully."



# Update checksums for all files
echo "Updating checksums for all files..."
cd iso_temp || { echo "Failed to change directory to iso_temp. Exiting."; exit 1; }

# Remove the old md5sum.txt file
rm -f md5sum.txt

# Calculate new checksums for all files
find . -type f ! -name "md5sum.txt" -print0 | xargs -0 md5sum > md5sum.txt

# Sort the md5sum.txt file for consistency
sort -k2 md5sum.txt -o md5sum.txt

echo "Checksums updated successfully."

cd ..



# Create ISO
echo "Creating ISO..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "DEBIAN_CUSTOM" \
    -eltorito-boot isolinux/isolinux.bin \
    -eltorito-catalog isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -isohybrid-mbr /usr/lib/syslinux/bios/isohdpfx.bin \
    -eltorito-alt-boot \
    -e /boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -output preseed-debian-custom.iso \
    iso_temp

    # Check if ISO creation was successful
    if [ $? -ne 0 ]; then
    echo "ISO creation failed. Exiting."
    exit 1
    fi
    echo "ISO created successfully."

    # Write ISO to device
    echo "Writing ISO to $TARGET_DEVICE..."
    dd bs=4M if=preseed-debian-custom.iso of=$TARGET_DEVICE status=progress oflag=sync

    # Check if dd was successful
    if [ $? -ne 0 ]; then
    echo "Writing ISO to device failed. Exiting."
    exit 1
    fi

    echo "ISO written successfully."
    echo "All operations completed successfully."
