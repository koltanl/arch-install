#!/bin/bash

# Add these lines at the very start of autoArch.sh
echo "[$(date)] Automated installation script started" >/tmp/autoinstall.log
echo "[$(date)] Current user: $(whoami)" >>/tmp/autoinstall.log
echo "[$(date)] Current directory: $(pwd)" >>/tmp/autoinstall.log

# Debug control
DEBUG=${DEBUG:-0}
if [ "$DEBUG" -eq 1 ]; then
    set -x
else
    set +x
fi

# Configuration handling
CONFIG_FILE=${CONFIG_FILE:-"/root/custom/install/preseed.conf"}

# Function to log messages
log_msg() {
    echo "$@" >&2
    echo "[$(date)] $@" >>/tmp/autoinstall.log
}

# Function to validate configuration values
validate_config() {
    local errors=0
    
    # Validate DISK_TYPE
    if [[ ! $DISK_TYPE =~ ^[1-3]$ ]]; then
        log_msg "Error: DISK_TYPE must be 1 (SATA/IDE), 2 (NVMe), or 3 (Virtio)"
        errors=$((errors + 1))
    fi
    
    # Validate DISK exists
    if [ ! -e "$DISK" ]; then
        log_msg "Error: DISK $DISK does not exist"
        errors=$((errors + 1))
    fi
    
    # Validate USERNAME format
    if [[ ! $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_msg "Error: USERNAME must contain only lowercase letters, numbers, underscore"
        errors=$((errors + 1))
    fi
    
    # Validate passwords are not empty
    for pass in "$ROOT_PASSWORD" "$USER_PASSWORD" "$ENCRYPTION_PASSWORD"; do
        if [ ${#pass} -lt 4 ]; then
            log_msg "Error: Passwords must be at least 4 characters"
            errors=$((errors + 1))
            break
        fi
    done
    
    # Validate BOOTLOADER
    if [[ ! $BOOTLOADER =~ ^(UEFI|BIOS)$ ]]; then
        log_msg "Error: BOOTLOADER must be UEFI or BIOS"
        errors=$((errors + 1))
    fi
    
    # Validate PROCESSOR_TYPE
    if [[ ! $PROCESSOR_TYPE =~ ^[1-2]$ ]]; then
        log_msg "Error: PROCESSOR_TYPE must be 1 (Intel) or 2 (AMD)"
        errors=$((errors + 1))
    fi
    
    # Validate GRAPHICS_TYPE
    if [[ ! $GRAPHICS_TYPE =~ ^[1-5]$ ]]; then
        log_msg "Error: GRAPHICS_TYPE must be 1-5"
        errors=$((errors + 1))
    fi
    
    # Validate partition sizes are numbers greater than 0
    for size in $ROOT_PARTITION_SIZE $BOOT_PARTITION_SIZE $EFI_PARTITION_SIZE $SWAP_SIZE; do
        if ! [[ "$size" =~ ^[0-9]+$ ]] || [ "$size" -lt 1 ]; then
            log_msg "Error: Partition sizes must be positive integers"
            errors=$((errors + 1))
            break
        fi
    done
    
    return $errors
}

# Function to load and validate configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_msg "Error: Configuration file not found at $CONFIG_FILE"
        exit 1
    fi

    log_msg "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    if ! validate_config; then
        log_msg "Configuration validation failed"
        exit 1
    fi
    
    log_msg "Configuration validated successfully"
}

# Function to set up installation environment
setup_environment() {
    # Set disk configuration based on DISK_TYPE
    case $DISK_TYPE in
        1) PART_SUFFIX="" ;;
        2) PART_SUFFIX="p" ;;
        3) PART_SUFFIX="" ;;
    esac

    # Set graphics driver
    case $GRAPHICS_TYPE in
        1) GRAPHICS_DRIVER="mesa libva-intel-driver intel-media-driver" ;;
        2) GRAPHICS_DRIVER="mesa libva-mesa-driver mesa-vdpau" ;;
        3) GRAPHICS_DRIVER="nvidia nvidia-utils nvidia-settings opencl-nvidia" ;;
        4) GRAPHICS_DRIVER="xf86-video-vesa" ;;
        5) GRAPHICS_DRIVER="xf86-video-qxl" ;;
    esac

    # Set processor microcode
    case $PROCESSOR_TYPE in
        1) PROCESSOR_UCODE="intel-ucode" ;;
        2) PROCESSOR_UCODE="amd-ucode" ;;
    esac
}

# Main installation function
perform_installation() {
    log_msg "Starting automated Arch Linux installation..."

    # Clean and partition disk
    log_msg "Preparing disk..."
    wipefs -a "$DISK"
    sgdisk -Z "$DISK"
    sgdisk -o "$DISK"

    # Create partitions
    if [ "$BOOTLOADER" == "UEFI" ]; then
        sgdisk -n 1:0:+${EFI_PARTITION_SIZE}G -t 1:ef00 "$DISK"
        sgdisk -n 2:0:+${BOOT_PARTITION_SIZE}G -t 2:8300 "$DISK"
    else
        sgdisk -n 1:0:+1M -t 1:ef02 "$DISK"
        sgdisk -n 2:0:+${BOOT_PARTITION_SIZE}G -t 2:8300 "$DISK"
    fi
    
    sgdisk -n 3:0:+${ROOT_PARTITION_SIZE}G -t 3:8300 "$DISK"
    sgdisk -n 4:0:0 -t 4:8300 "$DISK"

    # Format and mount partitions
    log_msg "Formatting and mounting partitions..."
    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkfs.fat -F32 "${DISK}${PART_SUFFIX}1"
    fi
    mkfs.ext4 "${DISK}${PART_SUFFIX}2"
    mkfs.ext4 "${DISK}${PART_SUFFIX}3"

    # Encrypt home partition
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat "${DISK}${PART_SUFFIX}4" -
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup open "${DISK}${PART_SUFFIX}4" home

    mkfs.ext4 /dev/mapper/home

    # Mount filesystems
    mount "${DISK}${PART_SUFFIX}3" /mnt
    mkdir -p /mnt/{boot,home}
    mount "${DISK}${PART_SUFFIX}2" /mnt/boot
    
    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkdir -p /mnt/boot/efi
        mount "${DISK}${PART_SUFFIX}1" /mnt/boot/efi
    fi
    
    mount /dev/mapper/home /mnt/home

    # Create and enable swap
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((SWAP_SIZE * 1024))
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile

    # Install base system
    log_msg "Installing base system..."
    pacstrap /mnt base base-devel linux linux-firmware grub efibootmgr

    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

    # Configure system
    log_msg "Configuring system..."
    arch-chroot /mnt /bin/bash <<CHROOT
# Set up system
echo "${HOSTNAME}" > /etc/hostname
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
hwclock --systohc

# Set root password
echo "root:${ROOT_PASSWORD}" | chpasswd

# Create user
useradd -m "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
usermod -aG wheel "${USERNAME}"

# Install and configure sudo
pacman -S --noconfirm sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install packages
pacman -Syu --noconfirm
pacman -S --noconfirm \
    xorg sddm plasma kde-system-meta kde-utilities-meta \
    networkmanager ${GRAPHICS_DRIVER} ${PROCESSOR_UCODE} \
    grub efibootmgr os-prober

# Enable services
systemctl enable sddm
systemctl enable NetworkManager

# Install GRUB
if [ "$BOOTLOADER" == "UEFI" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "${DISK}"
fi
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

+    # Configure encryption support
+    echo "Configuring encryption support..."
+
+    # Add encryption modules to mkinitcpio.conf
+    arch-chroot /mnt sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
+
+    # Get the UUID of the encrypted partition
+    CRYPT_UUID=$(blkid -s UUID -o value ${DISK}${PART_SUFFIX}4)
+
+    # Configure crypttab
+    echo "cryptroot UUID=${CRYPT_UUID} none luks" > /mnt/etc/crypttab
+
+    # Update GRUB configuration for encryption
+    arch-chroot /mnt sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cryptdevice=UUID='${CRYPT_UUID}':cryptroot root=\/dev\/mapper\/cryptroot"/' /etc/default/grub
+
+    # Regenerate initramfs
+    arch-chroot /mnt mkinitcpio -P
+
+    # Regenerate GRUB config
+    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

    log_msg "Installation completed successfully!"
}

# Main execution
main() {
    load_config
    setup_environment
    perform_installation
}

main 