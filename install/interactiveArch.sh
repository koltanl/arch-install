#!/bin/bash

# Add these lines at the very start of preseedArch.sh, before the shebang
echo "[$(date)] Script started" >/tmp/preseed.log
echo "[$(date)] Current permissions: $(stat -c '%a' $0)" >>/tmp/preseed.log
echo "[$(date)] Current user: $(whoami)" >>/tmp/preseed.log
echo "[$(date)] Current directory: $(pwd)" >>/tmp/preseed.log

# Debug control
DEBUG=${DEBUG:-0}
if [ "$DEBUG" -eq 1 ]; then
    set -x
else
    set +x  # Explicitly disable debug mode
fi

# Partition size configurations (in GB)
BOOT_PARTITION_SIZE=1
EFI_PARTITION_SIZE=1
SWAP_SIZE=8  # Size in GB for swap file




# Function to log messages even when debug is off
log_msg() {
    echo "$@" >&2
}

# Function to prompt for disk type
prompt_for_disk_type() {
    echo -e "\nDetected storage devices:"
    echo "------------------------"
    
    # Show storage controllers with better formatting
    echo "Storage Controllers:"
    echo "-------------------"
    if systemd-detect-virt -q; then
        lspci | grep -i 'storage\|sata\|nvme\|virtio' | while read -r line; do
            if echo "$line" | grep -qi 'nvme'; then
                echo "✓ NVMe controller detected: $line"
            elif echo "$line" | grep -qi 'sata\|ide'; then
                echo "✓ SATA/IDE controller detected: $line"
            elif echo "$line" | grep -qi 'virtio'; then
                echo "✓ Virtio controller detected: $line"
            else
                echo "- Other storage controller: $line"
            fi
        done
    else
        echo "No storage controllers detected"
    fi
    # Function to prompt for root partition size
prompt_for_root_size() {
    local default_root=100
    local min_root=20

    echo -e "\nRoot Partition Size Configuration:"
    echo "----------------------------------------"
    echo "Default root size: ${default_root}GB"
    echo "Minimum required: ${min_root}GB"
    echo
    echo "After root partition, remaining space will go to /home"
    echo "----------------------------------------"
    
    while true; do
        read -p "Enter root partition size [${default_root}GB]: " ROOT_PARTITION_SIZE
        
        # If empty, use default
        if [ -z "$ROOT_PARTITION_SIZE" ]; then
            ROOT_PARTITION_SIZE=$default_root
            echo "Using default size: ${default_root}GB"
            break
        fi

        # Validate input is a number
        if ! [[ "$ROOT_PARTITION_SIZE" =~ ^[0-9]+$ ]]; then
            echo "Please enter a valid number"
            continue
        fi
        
        # Only check minimum size
        if [ "$ROOT_PARTITION_SIZE" -lt "$min_root" ]; then
            echo "Root partition must be at least ${min_root}GB"
            continue
        fi

        # If we get here, the size is valid
        break
    done

    echo "Setting root partition size to: ${ROOT_PARTITION_SIZE}GB"
}
    # Show available disks with type identification
    echo -e "\nAvailable Disks:"
    echo "---------------"
    echo "Type    Device     Size   Model"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -v "loop\|sr" | while read -r name size type model; do
        if [[ $name == "NAME" ]]; then
            continue
        fi
        
        device="/dev/$name"
        if echo "$name" | grep -q "^nvme"; then
            echo "NVMe    $device  $size  $model"
        elif echo "$name" | grep -q "^vd"; then
            echo "Virtio  $device  $size  $model"
        else
            echo "SATA    $device  $size  $model"
        fi
    done
    
    # Add disk type recommendation
    echo -e "\nRecommended Selection:"
    if systemd-detect-virt -q; then
        echo "→ Select option 3 (Virtio) - Virtual machine detected"
    elif lsblk -d | grep -q "^nvme"; then
        echo "→ Select option 2 (NVMe) - NVMe drives detected"
    elif lsblk -d | grep -q "^sd"; then
        echo "→ Select option 1 (SATA/IDE) - SATA drives detected"
    else
        echo "! No standard drives detected"
    fi
    echo "------------------------"
    
    while true; do
        echo -e "\nSelect disk type:"
        echo "1) SATA/IDE (e.g., /dev/sda)"
        echo "2) NVMe (e.g., /dev/nvme0n1)"
        echo "3) Virtio (e.g., /dev/vda)"
        read -p "Enter the number corresponding to your disk type: " DISK_TYPE
        case $DISK_TYPE in
            1) 
                PART_SUFFIX=""
                echo "Selected SATA/IDE disk type"
                break
                ;;
            2) 
                PART_SUFFIX="p"
                echo "Selected NVMe disk type"
                break
                ;;
            3)
                PART_SUFFIX=""
                echo "Selected Virtio disk type"
                break
                ;;
            *) 
                echo "Invalid option. Please select 1, 2, or 3."
                sleep 1
                ;;
        esac
    done
}
# Function to prompt for bootloader type
prompt_for_bootloader() {
    echo -e "\nSystem Boot Configuration:"
    echo "------------------------"
    
    # Check for UEFI
    if [ -d "/sys/firmware/efi" ]; then
        echo "✓ UEFI boot mode detected"
        SECURE_BOOT_STATUS=$(mokutil --sb-state 2>/dev/null || echo 'unknown')
        if [ "$SECURE_BOOT_STATUS" != "unknown" ]; then
            echo "→ Secure Boot: $SECURE_BOOT_STATUS"
        fi
        echo "→ Recommended: UEFI (option 1)"
    else
        echo "✓ Legacy BIOS mode detected"
        echo "→ Recommended: Legacy BIOS (option 2)"
    fi
    echo "------------------------"
    
    while true; do
        echo -e "\nSelect bootloader type:"
        echo "1) UEFI     (Modern systems, recommended if available)"
        echo "2) Legacy   (Older systems, use only if UEFI is unavailable)"
        read -p "Enter selection [1/2]: " BOOTLOADER_TYPE
        case $BOOTLOADER_TYPE in
            1) 
                BOOTLOADER="UEFI"
                echo "Selected: UEFI bootloader"
                break
                ;;
            2) 
                BOOTLOADER="BIOS"
                echo "Selected: Legacy BIOS bootloader"
                break
                ;;
            *) 
                echo "Invalid option. Please select 1 or 2."
                sleep 1
                ;;
        esac
    done
}

# Function to prompt for processor and graphics type
prompt_for_processor_and_graphics() {
    echo -e "\nHardware Detection:"
    echo "------------------------"
    
    # CPU Detection
    CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^[ \t]*//')
    echo "CPU Information:"
    echo "→ $CPU_MODEL"
    
    # Recommend CPU type based on detection
    case $CPU_VENDOR in
        *Intel*|*intel*)
            echo "→ Recommended: Intel (option 1)"
            DEFAULT_CPU=1
            ;;
        *AMD*|*amd*)
            echo "→ Recommended: AMD (option 2)"
            DEFAULT_CPU=2
            ;;
        *)
            echo "→ CPU vendor not detected"
            DEFAULT_CPU=0
            ;;
    esac
    
    # Graphics Detection
    echo -e "\nGraphics Hardware:"
    if lspci | grep -i 'vga\|3d\|display' | grep -qi 'intel'; then
        echo "→ Intel Graphics detected (option 1)"
        DEFAULT_GPU=1
    elif lspci | grep -i 'vga\|3d\|display' | grep -qi 'amd\|ati'; then
        echo "→ AMD Graphics detected (option 2)"
        DEFAULT_GPU=2
    elif lspci | grep -i 'vga\|3d\|display' | grep -qi 'nvidia'; then
        echo "→ NVIDIA Graphics detected (option 3)"
        DEFAULT_GPU=3
    else
        echo "→ No dedicated graphics detected"
        DEFAULT_GPU=4
    fi
    echo "------------------------"
    
    # Processor selection
    while true; do
        echo -e "\nSelect processor type for microcode updates:"
        echo "1) Intel"
        echo "2) AMD"
        read -p "Enter selection [1/2] (detected: $DEFAULT_CPU): " PROCESSOR_TYPE
        PROCESSOR_TYPE=${PROCESSOR_TYPE:-$DEFAULT_CPU}
        case $PROCESSOR_TYPE in
            1) 
                PROCESSOR_UCODE="intel-ucode"
                echo "Selected: Intel microcode"
                break
                ;;
            2) 
                PROCESSOR_UCODE="amd-ucode"
                echo "Selected: AMD microcode"
                break
                ;;
            *) 
                echo "Invalid option. Please select 1 or 2."
                sleep 1
                ;;
        esac
    done

    # Graphics selection
    while true; do
        echo -e "\nSelect graphics driver:"
        echo "1) Intel    (Open source, good performance)"
        echo "2) AMD      (Open source, good performance)"
        echo "3) NVIDIA   (Proprietary, best for NVIDIA cards)"
        echo "4) None     (Basic display driver)"
        echo "5) Virtual Machine (Best for VM environments)"
        read -p "Enter selection [1-5] (detected: $DEFAULT_GPU): " GRAPHICS_TYPE
        GRAPHICS_TYPE=${GRAPHICS_TYPE:-$DEFAULT_GPU}
        case $GRAPHICS_TYPE in
            1) 
                GRAPHICS_DRIVER="mesa xf86-video-intel vulkan-intel"
                echo "Selected: Intel graphics drivers"
                break
                ;;
            2) 
                GRAPHICS_DRIVER="mesa xf86-video-amdgpu"
                echo "Selected: AMD graphics drivers"
                break
                ;;
            3) 
                GRAPHICS_DRIVER="nvidia nvidia-utils nvidia-settings"
                echo "Selected: NVIDIA graphics drivers"
                break
                ;;
            4) 
                GRAPHICS_DRIVER="xf86-video-vesa"
                echo "Selected: Basic display driver"
                break
                ;;
            5)
                GRAPHICS_DRIVER="xf86-video-qxl"
                echo "Selected: Virtual Machine graphics driver"
                break
                ;;
            *) 
                echo "Invalid option. Please select 1-5."
                sleep 1
                ;;
        esac
    done
}

# Function to prompt for disk
prompt_for_disk() {
    echo -e "\nDisk information:"
    echo "------------------------"
    echo "Block devices:"
    lsblk -o NAME,SIZE,TYPE,MODEL,FSTYPE,MOUNTPOINT || echo "No block devices detected"
    
    if command -v fdisk >/dev/null; then
        echo -e "\nPartition tables:"
        fdisk -l 2>/dev/null | grep "Disk /dev" || echo "No partition tables found"
    fi
    echo "------------------------"
    
    while true; do
        echo -e "\nYou can specify either:"
        echo "1. A whole disk (e.g., /dev/nvme0n1)"
        echo "2. A specific partition (e.g., /dev/nvme0n1p4)"
        read -p "Enter the disk or partition to use: " DISK

        # Validate input exists
        if [ ! -e "$DISK" ]; then
            echo "Error: Device $DISK does not exist."
            echo "Please enter a valid disk or partition."
            sleep 1
            continue
        fi

        # Check if input is a partition
        if echo "$DISK" | grep -q "p[0-9]\+$"; then
            IS_PARTITION=true
            # Extract the base disk name
            BASE_DISK=$(echo "$DISK" | sed 's/p[0-9]\+$//' | sed 's/[0-9]\+$//')
            if [ -e "$BASE_DISK" ]; then
                echo "Using partition $DISK on disk $BASE_DISK"
                break
            else
                echo "Error: Base disk $BASE_DISK not found."
                sleep 1
                continue
            fi
        else
            IS_PARTITION=false
            BASE_DISK=$DISK
            echo "Using entire disk $DISK"
            break
        fi
    done
}

# Function to prompt for hostname
prompt_for_hostname() {
    echo -e "\nHostname Configuration:"
    echo "------------------------"
    echo "The hostname is your computer's network name."
    echo "Requirements:"
    echo "→ Use only letters, numbers, and hyphens"
    echo "→ Start and end with a letter or number"
    echo "→ Maximum length: 63 characters"
    echo "------------------------"
    
    while true; do
        read -p "Enter hostname: " HOSTNAME
        # Validate hostname
        if [[ $HOSTNAME =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$ ]]; then
            echo "Hostname set to: $HOSTNAME"
            break
        else
            echo "Invalid hostname. Please follow the requirements above."
        fi
    done
}

# Function to prompt for encryption password
prompt_for_encryption_password() {
    echo -e "\nDisk Encryption Setup:"
    echo "------------------------"
    echo "Your disk encryption password:"
    echo "→ Should be at least 8 characters"
    echo "→ Mix of letters, numbers, and symbols recommended"
    echo "→ Will be required at every boot"
    echo "------------------------"
    
    while true; do
        read -sp "Enter encryption password: " ENCRYPTION_PASSWORD
        echo
        read -sp "Confirm encryption password: " ENCRYPTION_CONFIRM
        echo
        
        if [ ${#ENCRYPTION_PASSWORD} -lt 8 ]; then
            echo "Password too short! Minimum 8 characters required."
            continue
        elif [ "$ENCRYPTION_PASSWORD" != "$ENCRYPTION_CONFIRM" ]; then
            echo "Passwords do not match! Please try again."
            continue
        else
            echo "Encryption password set successfully."
            break
        fi
    done
}

# Function to prompt for user passwords
prompt_for_user_passwords() {
    echo -e "\nUser Account Setup:"
    echo "------------------------"
    echo "Creating system accounts:"
    echo "1. Root (administrator) account"
    echo "2. Regular user account"
    echo "------------------------"
    
    # Username setup
    while true; do
        read -p "Enter username (letters, numbers, underscore only): " USERNAME
        if [[ $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            break
        else
            echo "Invalid username format. Please use only lowercase letters, numbers, and underscore."
        fi
    done
    
    # Root password
    while true; do
        read -sp "Enter root password: " ROOT_PASSWORD
        echo
        read -sp "Confirm root password: " ROOT_CONFIRM
        echo
        
        if [ ${#ROOT_PASSWORD} -lt 4 ]; then
            echo "Root password too short! Minimum 6 characters required."
            continue
        elif [ "$ROOT_PASSWORD" != "$ROOT_CONFIRM" ]; then
            echo "Root passwords do not match! Please try again."
            continue
        else
            echo "Root password set successfully."
            break
        fi
    done
    
    # User password
    while true; do
        read -sp "Enter password for $USERNAME: " USER_PASSWORD
        echo
        read -sp "Confirm password for $USERNAME: " USER_CONFIRM
        echo
        
        if [ ${#USER_PASSWORD} -lt 4 ]; then
            echo "User password too short! Minimum 6 characters required."
            continue
        elif [ "$USER_PASSWORD" != "$USER_CONFIRM" ]; then
            echo "User passwords do not match! Please try again."
            continue
        else
            echo "User password set successfully."
            break
        fi
    done
}

# Function to prompt for installation type
prompt_for_install_type() {
    echo -e "\nInstallation Type Selection:"
    echo "------------------------"
    echo "Available installation methods:"
    echo "1) Classic    - Direct disk partitioning with LUKS encryption"
    echo "               ✓ Stable and well-tested"
    echo "               ✓ Simple partition structure"
    echo "               ✓ Separate encrypted root and home"
    
    echo "2) LVM Whole  - LVM on LUKS with single encrypted container"
    echo "               ✓ Flexible storage management"
    echo "               ✓ Easy volume resizing"
    echo "               ✓ Snapshot capability"
    
    echo "3) LVM Split  - LVM on LUKS with preserved /home"
    echo "               ✓ All LVM benefits"
    echo "               ✓ Separate home encryption"
    echo "               ✓ Easier system reinstall"
    echo "------------------------"
    
    while true; do
        read -p "Select installation type [1-3]: " INSTALL_TYPE
        case $INSTALL_TYPE in
            1)
                echo "Selected: Classic installation"
                INSTALL_METHOD="classic"
                break
                ;;
            2)
                echo "Selected: LVM Whole Disk"
                INSTALL_METHOD="lvm_whole"
                break
                ;;
            3)
                echo "Selected: LVM Split Disk"
                INSTALL_METHOD="lvm_split"
                break
                ;;
            *)
                echo "Invalid option. Please select 1-3."
                ;;
        esac
    done
}

# Function to detect Windows and ESP
detect_windows_esp() {
    echo -e "\nChecking for existing Windows installation:"
    echo "----------------------------------------"
    
    # Look for existing EFI partition
    ESP_PART=$(fdisk -l | grep "EFI System" | awk '{print $1}' | head -n1)
    if [ -n "$ESP_PART" ]; then
        echo "✓ Found EFI System Partition at: $ESP_PART"
        EXISTING_ESP=1
        ESP_SIZE=$(lsblk -b -n -o SIZE "$ESP_PART")
        echo "  Size: $(numfmt --to=iec $ESP_SIZE)"
    else
        echo "✗ No existing EFI System Partition found"
        EXISTING_ESP=0
    fi

    # Look for Windows bootloader
    if [ -d "/sys/firmware/efi" ] && [ -n "$ESP_PART" ]; then
        mkdir -p /tmp/esp
        mount "$ESP_PART" /tmp/esp
        if [ -d "/tmp/esp/EFI/Microsoft" ]; then
            echo "✓ Windows bootloader detected"
            WINDOWS_DETECTED=1
        else
            echo "✗ No Windows bootloader found"
            WINDOWS_DETECTED=0
        fi
        umount /tmp/esp
    fi
}

# Function to setup LVM split installation
setup_partitions_lvm_split() {
    echo "Setting up LVM on LUKS partitions (Split Installation)..."
    
    # First check for Windows/ESP
    detect_windows_esp
    
    # Show current partition layout
    echo -e "\nCurrent partition layout:"
    echo "----------------------------------------"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$DISK"
    echo "----------------------------------------"
    
    # Only partition the free space
    if [[ "$DISK" =~ ^/dev/(nvme[0-9]+n[0-9]+|sd[a-z]|vd[a-z])$ ]]; then
        echo "ERROR: Please specify a partition, not an entire disk"
        echo "Example: ${DISK}p4 or ${DISK}4"
        exit 1
    fi

    # Setup LUKS on the specified partition
    echo "Setting up LUKS encryption on $DISK..."
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat "$DISK"
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup open "$DISK" cryptlvm

    # Setup LVM
    echo "Configuring LVM..."
    pvcreate /dev/mapper/cryptlvm
    vgcreate vg0 /dev/mapper/cryptlvm
    
    # Create logical volumes
    lvcreate -L ${ROOT_PARTITION_SIZE}G vg0 -n root
    lvcreate -l 100%FREE vg0 -n home

    # Format logical volumes
    mkfs.ext4 /dev/vg0/root
    mkfs.ext4 /dev/vg0/home

    # Mount filesystems
    echo "Mounting filesystems..."
    mount /dev/vg0/root /mnt
    mkdir -p /mnt/home
    mount /dev/vg0/home /mnt/home
    
    # Handle boot partition
    mkdir -p /mnt/boot
    if [ "$BOOTLOADER" == "UEFI" ]; then
        # Use existing ESP
        mkdir -p /mnt/boot/efi
        mount "$ESP_PART" /mnt/boot/efi
        
        # Create separate /boot if it doesn't exist
        BOOT_PART=$(lsblk -l -o NAME,MOUNTPOINT | grep '/boot$' | cut -d' ' -f1)
        if [ -z "$BOOT_PART" ]; then
            echo "Creating new boot partition..."
            # Logic to create boot partition in remaining space
            # This needs to be implemented based on available space
        fi
    fi

    # Create and mount swap file
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((SWAP_SIZE * 1024))
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile

    # Generate fstab
    mkdir -p /mnt/etc
    genfstab -U /mnt > /mnt/etc/fstab
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

    # Setup crypttab
    CRYPT_UUID=$(blkid -s UUID -o value "$DISK")
    echo "cryptlvm UUID=${CRYPT_UUID} none luks" > /mnt/etc/crypttab

    # Configure GRUB for dual-boot
    if [ "$WINDOWS_DETECTED" -eq 1 ]; then
        echo "Configuring dual-boot with Windows..."
        echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
        pacstrap /mnt os-prober
    fi
}

# Function to setup LVM whole disk installation
setup_partitions_lvm() {
    echo "Setting up LVM on LUKS partitions..."
    
    # Clean and partition disk
    wipefs -a "$DISK"
    sgdisk -Z "$DISK"
    sgdisk -o "$DISK"

    # Create partitions based on bootloader type
    if [ "$BOOTLOADER" == "UEFI" ]; then
        sgdisk -n 1:0:+${EFI_PARTITION_SIZE}G -t 1:ef00 "$DISK"    # EFI
        sgdisk -n 2:0:+${BOOT_PARTITION_SIZE}G -t 2:8300 "$DISK"    # Boot
        sgdisk -n 3:0:0 -t 3:8309 "$DISK"    # Linux LUKS
    else
        sgdisk -n 1:0:+1M -t 1:ef02 "$DISK"    # BIOS boot
        sgdisk -n 2:0:+${BOOT_PARTITION_SIZE}G -t 2:8300 "$DISK"    # Boot
        sgdisk -n 3:0:0 -t 3:8309 "$DISK"    # Linux LUKS
    fi

    # Format EFI/Boot partitions
    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkfs.fat -F32 "${DISK}${PART_SUFFIX}1"
    fi
    mkfs.ext4 "${DISK}${PART_SUFFIX}2"  # Boot

    # Setup LUKS encryption
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat "${DISK}${PART_SUFFIX}3"
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup open "${DISK}${PART_SUFFIX}3" cryptlvm

    # Setup LVM
    pvcreate /dev/mapper/cryptlvm
    vgcreate vg0 /dev/mapper/cryptlvm
    
    # Create logical volumes
    lvcreate -L ${ROOT_PARTITION_SIZE}G vg0 -n root
    lvcreate -l 100%FREE vg0 -n home

    # Format logical volumes
    mkfs.ext4 /dev/vg0/root
    mkfs.ext4 /dev/vg0/home

    # Mount filesystems
    mount /dev/vg0/root /mnt
    mkdir -p /mnt/home
    mount /dev/vg0/home /mnt/home
    mkdir -p /mnt/boot
    mount "${DISK}${PART_SUFFIX}2" /mnt/boot

    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkdir -p /mnt/boot/efi
        mount "${DISK}${PART_SUFFIX}1" /mnt/boot/efi
    fi

    # Create and mount swap file
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$((SWAP_SIZE * 1024))
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile

    # Generate fstab
    mkdir -p /mnt/etc
    genfstab -U /mnt > /mnt/etc/fstab
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

    # Setup crypttab
    CRYPT_UUID=$(blkid -s UUID -o value "${DISK}${PART_SUFFIX}3")
    echo "cryptlvm UUID=${CRYPT_UUID} none luks" > /mnt/etc/crypttab

    # Configure GRUB for dual-boot
    if [ "$WINDOWS_DETECTED" -eq 1 ]; then
        echo "Configuring dual-boot with Windows..."
        echo "GRUB_DISABLE_OS_PROBER=false" >> /mnt/etc/default/grub
        pacstrap /mnt os-prober
    fi
}

# Update the chroot configuration section to match autoArch.sh
configure_system() {
    # First install base system
    echo "Installing base system..."
    pacstrap /mnt base base-devel linux linux-firmware \
        grub efibootmgr dosfstools os-prober lvm2 cryptsetup \
        networkmanager dhclient bluez bluez-utils \
        sudo reflector openssh zsh nano wget

    # Install processor microcode separately
    echo "Installing processor microcode..."
    if ! pacstrap /mnt "${PROCESSOR_UCODE}"; then
        echo "Warning: Failed to install ${PROCESSOR_UCODE}, continuing anyway..."
    fi

    # Install graphics drivers separately
    echo "Installing graphics drivers..."
    if ! pacstrap /mnt ${GRAPHICS_DRIVER}; then
        echo "Warning: Failed to install ${GRAPHICS_DRIVER}, continuing anyway..."
    fi

    # Now do the chroot configuration
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
    echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel
    chmod 440 /etc/sudoers.d/wheel

    # Update mirrors and install packages
    echo "Updating mirrorlist..."
    reflector --verbose --country 'US' --latest 100 --download-timeout 1 --number 15 --sort rate --save /etc/pacman.d/mirrorlist

    # Configure pacman
    sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 32/' /etc/pacman.conf

    # Install base packages
    pacman -S --needed grub efibootmgr os-prober --noconfirm

    # Install graphics and processor-specific packages
    pacman -S --needed "${GRAPHICS_DRIVER}" "${PROCESSOR_UCODE}" --noconfirm

    # Install networking tools
    pacman -S --needed networkmanager dhclient bluez bluez-utils --noconfirm

    # Install basic utilities
    pacman -S --needed zsh nano wget --noconfirm

    # Install and configure SSH
    echo "Installing and configuring SSH..."
    pacman -S --needed openssh --noconfirm

    # Configure SSH to allow password authentication
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

    # Enable SSH service
    systemctl enable sshd

    # Configure mkinitcpio with encryption and LVM support
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck)/' /etc/mkinitcpio.conf

    # Install necessary LVM packages
    pacman -S --needed lvm2 --noconfirm

    # Generate initramfs
    mkinitcpio -P

    # Configure GRUB for encryption
    LUKS_UUID=\$(blkid -s UUID -o value "${DISK}${PART_SUFFIX}3")
    echo "GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/vg0-root\"" > /etc/default/grub
    echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
    
    # Configure GRUB modules
    sed -i 's|^GRUB_PRELOAD_MODULES=.*|GRUB_PRELOAD_MODULES="part_gpt part_msdos lvm cryptodisk luks2"|' /etc/default/grub

    # Install bootloader
    if [ "$BOOTLOADER" == "UEFI" ]; then
        # Ensure EFI variables are available
        if [ ! -d /sys/firmware/efi/efivars ]; then
            echo "Error: EFI variables not available. Are you booted in UEFI mode?"
            exit 1
        fi

        # Ensure EFI partition is mounted
        if ! mountpoint -q /boot/efi; then
            echo "Error: EFI partition not mounted at /boot/efi"
            exit 1
        fi

        # Install required packages
        pacman -S --noconfirm efibootmgr dosfstools

        # Install GRUB with proper configuration
        grub-install --target=x86_64-efi --efi-directory=/boot/efi \
        --bootloader-id=GRUB \
        --modules="luks2 cryptodisk part_gpt lvm" \
        --removable \
        --recheck

        # Create fallback boot entry
        mkdir -p /boot/efi/EFI/BOOT
        cp /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI
        chmod 644 /boot/efi/EFI/BOOT/BOOTX64.EFI
        chmod 644 /boot/efi/EFI/GRUB/grubx64.efi

        # Configure GRUB default settings without indentation
        cat > /etc/default/grub <<EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Arch"
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_TERMINAL_INPUT=console
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_CMDLINE_LINUX="cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/vg0-root"
GRUB_ENABLE_CRYPTODISK=y
GRUB_PRELOAD_MODULES="part_gpt part_msdos lvm cryptodisk luks2"
EOF

        # Force update EFI boot entries
        efibootmgr --create --disk "${DISK}" --part 1 --loader /EFI/BOOT/BOOTX64.EFI --label "Arch Linux Fallback" --verbose
        efibootmgr --create --disk "${DISK}" --part 1 --loader /EFI/GRUB/grubx64.efi --label "GRUB" --verbose

        # Set boot order to prioritize GRUB
        BOOT_ENTRY=$(efibootmgr | grep "GRUB" | cut -c 5-8)
        if [ -n "$BOOT_ENTRY" ]; then
            efibootmgr -o "$BOOT_ENTRY"
        fi

        # Verify EFI boot entries
        echo "Current EFI boot entries:"
        efibootmgr -v
    else
        grub-install --target=i386-pc "${DISK}" \
        --modules="luks2 cryptodisk part_gpt lvm"
    fi

    # Generate GRUB config
    echo "Generating GRUB configuration..."
    grub-mkconfig -o /boot/grub/grub.cfg

    # Verify GRUB configuration
    if [ ! -f /boot/grub/grub.cfg ]; then
        echo "Error: GRUB configuration file not generated"
        exit 1
    fi

    # Add debug output for boot configuration
    echo "Debug: EFI partition contents:"
    ls -la /boot/efi/EFI/
    
    echo "Debug: GRUB installation:"
    ls -la /boot/efi/EFI/GRUB/
    
    echo "Debug: Boot entries:"
    efibootmgr -v

    # Enable services
    systemctl enable sddm
    systemctl enable NetworkManager
    systemctl enable bluetooth

    # Enable LUKS support in GRUB
    echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub

    # Debug output
    echo "Debug: GRUB configuration:"
    cat /etc/default/grub
    
    echo "Debug: Crypttab contents:"
    cat /etc/crypttab
    
    echo "Debug: LUKS UUID:"
    blkid -s UUID -o value "${DISK}${PART_SUFFIX}3"
    
    echo "Debug: LVM status:"
    lvs
    vgs
    
    echo "Debug: mkinitcpio hooks:"
    grep ^HOOKS /etc/mkinitcpio.conf

CHROOT

    # Add verification steps after chroot
    echo "Verifying installation..."
    echo "Mounted filesystems:"
    lsblk -f
    
    echo "LUKS status:"
    cryptsetup status cryptlvm
    
    echo "LVM volumes:"
    lvs
    vgs
}

# Update the main execution flow
main() {
    prompt_for_disk_type
    prompt_for_root_size
    prompt_for_disk
    prompt_for_install_type
    prompt_for_user_passwords
    prompt_for_encryption_password
    prompt_for_bootloader
    prompt_for_processor_and_graphics
    prompt_for_hostname

    # Update partition setup to use selected method
    case $INSTALL_METHOD in
        "classic")
            setup_partitions
            ;;
        "lvm_whole")
            setup_partitions_lvm
            ;;
        "lvm_split")
            setup_partitions_lvm_split
            ;;
    esac

    configure_system

    echo "Installation completed successfully!"
}

main

