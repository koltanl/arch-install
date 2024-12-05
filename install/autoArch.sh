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

# Function to perform installation
perform_installation() {
    log_msg "Starting automated Arch Linux installation..."

    # Clean and partition disk
    log_msg "Preparing disk..."
    wipefs -a "$DISK"
    sgdisk -Z "$DISK"
    sgdisk -o "$DISK"

    # Create partitions
    if [ "$BOOTLOADER" == "UEFI" ]; then
        sgdisk -n 1:0:+${EFI_PARTITION_SIZE}G -t 1:ef00 "$DISK"    # EFI System Partition
        sgdisk -n 2:0:+${BOOT_PARTITION_SIZE}G -t 2:8300 "$DISK"    # Boot Partition
    else
        sgdisk -n 1:0:+1M -t 1:ef02 "$DISK"    # BIOS boot partition
        sgdisk -n 2:0:+${BOOT_PARTITION_SIZE}G -t 2:8300 "$DISK"    # Boot Partition
    fi

    sgdisk -n 3:0:+${ROOT_PARTITION_SIZE}G -t 3:8300 "$DISK"   # Root partition
    sgdisk -n 4:0:0 -t 4:8300 "$DISK"      # Home partition

    # Format partitions
    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkfs.fat -F32 "${DISK}${PART_SUFFIX}1"
    fi
    mkfs.ext4 "${DISK}${PART_SUFFIX}2"  # Boot
    mkfs.ext4 "${DISK}${PART_SUFFIX}3"  # Root

    # Setup encryption for home partition
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat "${DISK}${PART_SUFFIX}4"
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup open "${DISK}${PART_SUFFIX}4" crypthome
    mkfs.ext4 /dev/mapper/crypthome

    # Mount partitions
    mount "${DISK}${PART_SUFFIX}3" /mnt  # Mount root
    mkdir -p /mnt/boot
    mount "${DISK}${PART_SUFFIX}2" /mnt/boot  # Mount boot

    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkdir -p /mnt/boot/efi
        mount "${DISK}${PART_SUFFIX}1" /mnt/boot/efi  # Mount EFI
    fi

    mkdir -p /mnt/home
    mount /dev/mapper/crypthome /mnt/home  # Mount encrypted home

    # Create and mount swap file
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((SWAP_SIZE * 1024))
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile

    # Generate fstab with UUIDs
    mkdir -p /mnt/etc
    genfstab -U /mnt > /mnt/etc/fstab
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

    # Setup crypttab
    HOME_UUID=$(blkid -s UUID -o value "${DISK}${PART_SUFFIX}4")
    echo "crypthome UUID=${HOME_UUID} none luks" > /mnt/etc/crypttab

    # Install base system
    pacstrap /mnt base base-devel linux linux-firmware

    # Chroot and configure system
    arch-chroot /mnt /bin/bash <<CHROOT
# Set timezone and locale
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "Setting hostname..."
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Install and configure sudo
echo "Installing sudo..."
pacman -S --needed sudo --noconfirm

# Set passwords and create user
echo "Setting root password..."
echo "root:${ROOT_PASSWORD}" | chpasswd
echo "Creating new user and setting password..."
useradd -m "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

# Configure groups
if ! getent group wheel > /dev/null 2>&1; then
    groupadd wheel
fi
if ! getent group sudo > /dev/null 2>&1; then
    groupadd sudo
fi
usermod -aG wheel,sudo "${USERNAME}"

# Configure sudoers
echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers

# Configure passwordless sudo for wheel group
echo "Setting up passwordless sudo..."
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Update mirrors and install packages
echo "Updating mirrorlist..."
pacman -S --needed reflector --noconfirm
reflector --verbose --country 'US' --latest 100 --download-timeout 1 --number 15 --sort rate --save /etc/pacman.d/mirrorlist

# Configure pacman
sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 32/' /etc/pacman.conf

# Install bootloader packages
pacman -S --noconfirm grub efibootmgr os-prober

# Configure mkinitcpio with encryption support
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf

# Generate initramfs
mkinitcpio -P

# Install bootloader
if [ "$BOOTLOADER" == "UEFI" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "${DISK}"
fi

# Configure GRUB for encryption
HOME_UUID=$(blkid -s UUID -o value "${DISK}${PART_SUFFIX}4")
sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="cryptdevice=UUID='${HOME_UUID}':crypthome"/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Install yay
pacman -S --needed git go base-devel --noconfirm
sudo -u "${USERNAME}" bash -c "
    cd ~
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
"

# Install desktop environment and utilities
pacman -S --needed sddm plasma-desktop plasma-wayland-session plasma-pa plasma-nm \
    "${GRAPHICS_DRIVER}" "${PROCESSOR_UCODE}" networkmanager dhclient \
    grub efibootmgr os-prober zsh nano wget --noconfirm


# Enable services
systemctl enable sddm
systemctl enable NetworkManager
systemctl enable cups
systemctl enable bluetooth
systemctl enable sshd

# Setup deployment script to run on first login
echo "Setting up deployment script to run on first login..."
cat >> /home/${USERNAME}/.bashrc <<'EOF'

# Check for first-time deployment
if [ ! -f "$HOME/.deployment_done" ]; then
    echo "Running first-time system deployment..."
    sudo /root/arch-install/install/deploymentArch.sh
    touch "$HOME/.deployment_done"
    # Prompt for reboot after deployment
    echo "Deployment complete. Please reboot your system."
    read -p "Would you like to reboot now? [Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        sudo reboot
    fi
fi
EOF

# Set proper ownership
chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.bashrc
chmod 644 /home/${USERNAME}/.bashrc

CHROOT

    # Copy installation files to new system
    echo "Copying installation files to new system..."
    mkdir -p /mnt/root/arch-install
    cp -r /root/custom/* /mnt/root/arch-install/

    # Ensure scripts are executable in the new system
    chmod +x /mnt/root/arch-install/install/preseedArch.sh
    chmod +x /mnt/root/arch-install/install/deploymentArch.sh

    echo "Installation files copied to /root/arch-install/"
}

# Main execution
main() {
    load_config
    setup_environment
    perform_installation
}

main 