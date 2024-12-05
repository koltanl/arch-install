#!/bin/bash
set -x  # Enable debug output

echo "Installation script starting..."
echo "Current directory: $(pwd)"
echo "Current user: $(whoami)"
echo "Environment variables:"
env

# At the beginning of the script, add:
clear
echo "Welcome to Automated Arch Linux Installation"
echo "============================================"
sleep 2

# Function to prompt for disk type
prompt_for_disk_type() {
    echo -e "\nDetected storage devices:"
    echo "------------------------"
    # Show storage controllers
    lspci | grep -i 'storage\|sata\|nvme' || echo "No storage controllers detected"
    echo -e "\nAvailable disks:"
    lsblk -o NAME,SIZE,TYPE,MODEL || echo "No disks detected"
    echo "------------------------"
    
    while true; do
        echo "Select disk type:"
        echo "1) SATA/IDE (e.g., /dev/sda)"
        echo "2) NVMe (e.g., /dev/nvme0n1)"
        read -p "Enter the number corresponding to your disk type: " DISK_TYPE
        case $DISK_TYPE in
            1) 
                PART_SUFFIX=""
                break
                ;;
            2) 
                PART_SUFFIX="p"
                break
                ;;
            *) 
                echo "Invalid option. Please select 1 or 2."
                sleep 1
                ;;
        esac
    done
}

# Function to prompt for bootloader type
prompt_for_bootloader() {
    echo -e "\nSystem boot information:"
    echo "------------------------"
    # Check if we're in a VM
    systemd-detect-virt > /dev/null 2>&1
    IS_VM=$?
    if [ $IS_VM -eq 0 ]; then
        echo "Running in virtual machine: $(systemd-detect-virt)"
    else
        echo "Running on physical hardware"
    fi
    
    # Check for UEFI
    if [ -d "/sys/firmware/efi" ]; then
        echo "UEFI boot detected"
        echo "Secure Boot: $(mokutil --sb-state 2>/dev/null || echo 'unknown')"
    else
        echo "Legacy BIOS boot detected"
    fi
    echo "------------------------"
    
    while true; do
        echo "Select bootloader type:"
        echo "1) UEFI"
        echo "2) Legacy BIOS"
        read -p "Enter the number corresponding to your bootloader type: " BOOTLOADER_TYPE
        case $BOOTLOADER_TYPE in
            1) 
                BOOTLOADER="UEFI"
                break
                ;;
            2) 
                BOOTLOADER="BIOS"
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
    echo -e "\nSystem hardware information:"
    echo "------------------------"
    echo "CPU Information:"
    lscpu | grep -E "Model name|Vendor ID" || echo "CPU information unavailable"
    
    echo -e "\nGraphics Information:"
    lspci | grep -i 'vga\|3d\|display' || echo "No graphics hardware detected"
    echo "------------------------"
    
    # Processor selection
    while true; do
        echo "Select processor type for ucode:"
        echo "1) Intel"
        echo "2) AMD"
        read -p "Enter the number corresponding to your processor type: " PROCESSOR_TYPE
        case $PROCESSOR_TYPE in
            1) 
                PROCESSOR_UCODE="intel-ucode"
                break
                ;;
            2) 
                PROCESSOR_UCODE="amd-ucode"
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
        echo "Select graphics type:"
        echo "1) Intel"
        echo "2) AMD"
        echo "3) Nvidia"
        echo "4) None"
        read -p "Enter the number corresponding to your graphics type: " GRAPHICS_TYPE
        case $GRAPHICS_TYPE in
            1) 
                GRAPHICS_DRIVER="mesa"
                break
                ;;
            2) 
                GRAPHICS_DRIVER="mesa"
                break
                ;;
            3) 
                GRAPHICS_DRIVER="nvidia nvidia-utils nvidia-settings opencl-nvidia xorg-server-devel"
                break
                ;;
            4) 
                GRAPHICS_DRIVER=""
                break
                ;;
            *) 
                echo "Invalid option. Please select 1, 2, 3, or 4."
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
        if echo "$DISK" | grep -q "p[0-9]$\|[0-9]$"; then
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
prompt_for_hostname() {
    read -p "Enter your desired hostname: " HOSTNAME
}
# Function to prompt for encryption password
prompt_for_encryption_password() {
    ENCRYPTION_PASSWORD=${ENCRYPTION_PASSWORD:-"changeme"}
    read -sp "Enter encryption password [default: changeme]: " ENCRYPTION_INPUT
    echo
    ENCRYPTION_PASSWORD=${ENCRYPTION_INPUT:-$ENCRYPTION_PASSWORD}
}

# Function to prompt for root and user passwords
prompt_for_user_passwords() {
    # You could set default values here
    ROOT_PASSWORD=${ROOT_PASSWORD:-"changeme"}
    USERNAME=${USERNAME:-"archuser"}
    USER_PASSWORD=${USER_PASSWORD:-"changeme"}
    
    # Or still prompt interactively
    read -p "Enter username [default: archuser]: " USERNAME_INPUT
    USERNAME=${USERNAME_INPUT:-$USERNAME}
    
    read -sp "Enter root password [default: changeme]: " ROOT_PASSWORD_INPUT
    echo
    ROOT_PASSWORD=${ROOT_PASSWORD_INPUT:-$ROOT_PASSWORD}
    
    read -sp "Enter user password [default: changeme]: " USER_PASSWORD_INPUT
    echo
    USER_PASSWORD=${USER_PASSWORD_INPUT:-$USER_PASSWORD}
}

prompt_for_disk_type
prompt_for_disk
prompt_for_user_passwords
prompt_for_encryption_password
prompt_for_bootloader
prompt_for_processor_and_graphics


# Clean the disk to remove existing filesystems
echo "Cleaning the disk to remove existing filesystems..."
wipefs -a $DISK



# Partition the disk based on bootloader type
echo "Partitioning the disk..."
if [ "$IS_PARTITION" = true ]; then
    echo "Using existing partition $DISK"
    
    # Encrypt the entire partition
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat "$DISK" -
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup open "$DISK" cryptroot
    
    # Format the encrypted partition
    mkfs.ext4 /dev/mapper/cryptroot
    
    # Mount the encrypted root
    mount /dev/mapper/cryptroot /mnt
    
    # Create boot and EFI partitions at the end of the disk
    LAST_SECTOR=$(sgdisk -E "$BASE_DISK")
    if [ "$BOOTLOADER" == "UEFI" ]; then
        sgdisk -n 0:0:+1G -t 0:ef00 "$BASE_DISK"    # EFI System Partition
        sgdisk -n 0:0:+2G -t 0:8300 "$BASE_DISK"    # Boot Partition
        EFI_PARTITION="${BASE_DISK}${PART_SUFFIX}$(($(sgdisk -p "$BASE_DISK" | tail -n 1 | awk '{print $1}' ) - 1))"
        BOOT_PARTITION="${BASE_DISK}${PART_SUFFIX}$(sgdisk -p "$BASE_DISK" | tail -n 1 | awk '{print $1}')"
        
        # Format and mount boot partitions
        mkfs.fat -F32 "$EFI_PARTITION"
        mkfs.ext4 "$BOOT_PARTITION"
        
        mkdir -p /mnt/boot
        mount "$BOOT_PARTITION" /mnt/boot
        mkdir -p /mnt/boot/efi
        mount "$EFI_PARTITION" /mnt/boot/efi
    else
        sgdisk -n 0:0:+1M -t 0:ef02 "$BASE_DISK"    # BIOS boot partition
        sgdisk -n 0:0:+2G -t 0:8300 "$BASE_DISK"    # Boot Partition
        BOOT_PARTITION="${BASE_DISK}${PART_SUFFIX}$(sgdisk -p "$BASE_DISK" | tail -n 1 | awk '{print $1}')"
        
        # Format and mount boot partition
        mkfs.ext4 "$BOOT_PARTITION"
        mkdir -p /mnt/boot
        mount "$BOOT_PARTITION" /mnt/boot
    fi
    
    # Create swap file
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=8192
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
    
    # Add to crypttab
    mkdir -p /mnt/etc
    echo "cryptroot UUID=$(blkid -s UUID -o value $DISK) none luks" > /mnt/etc/crypttab
    
    # Add to fstab
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
else
    echo "Partitioning the disk..."
    sgdisk -o "$DISK"

    if [ "$BOOTLOADER" == "UEFI" ]; then
        sgdisk -n 1:0:+1G -t 1:ef00 $DISK    # EFI System Partition
        sgdisk -n 2:0:+2G -t 2:8300 $DISK    # Boot Partition
    else
        sgdisk -n 1:0:+1M -t 1:ef02 $DISK    # BIOS boot partition
        sgdisk -n 2:0:+2G -t 2:8300 $DISK    # Boot Partition
    fi

    sgdisk -n 3:0:+100G -t 3:8300 $DISK   # Root (increased to 100GB)
    sgdisk -n 4:0:0 -t 4:8300 $DISK      # Home
fi


# Format partitions based on bootloader type
echo "Formatting partitions..."
if [ "$IS_PARTITION" = true ]; then
    echo "Formatting partitions..."
    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkfs.fat -F32 "$EFI_PARTITION"
    fi
    mkfs.ext4 "$BOOT_PARTITION"
    mkfs.ext4 "$ROOT_PARTITION"     # Format the provided partition as root

    # Mount partitions
    mount "$ROOT_PARTITION" /mnt
    mkdir -p /mnt/boot
    mount "$BOOT_PARTITION" /mnt/boot

    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkdir -p /mnt/boot/efi
        mount "$EFI_PARTITION" /mnt/boot/efi
    fi
else
    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkfs.fat -F32 ${DISK}${PART_SUFFIX}1
    fi
    mkfs.ext4 ${DISK}${PART_SUFFIX}2
    mkfs.ext4 ${DISK}${PART_SUFFIX}3     # Root partition as ext4

    # Encrypt home partition
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup luksFormat ${DISK}${PART_SUFFIX}4 -
    echo -n "$ENCRYPTION_PASSWORD" | cryptsetup open ${DISK}${PART_SUFFIX}4 home

    # Verify if the encrypted home partition is successfully opened
    if [ ! -e /dev/mapper/home ]; then
        echo "Error: Encrypted home partition failed to open"
        exit 1
    fi

    # Format the opened encrypted home partition
    echo "Formatting the opened encrypted home partition..."
    mkfs.ext4 /dev/mapper/home           # Home partition as ext4

    # Mount partitions based on bootloader type
    echo "Mounting partitions..."
    mount ${DISK}${PART_SUFFIX}3 /mnt    # Mount root
    mkdir -p /mnt/boot
    mount ${DISK}${PART_SUFFIX}2 /mnt/boot
    if [ $? -ne 0 ]; then
        echo "Error: Failed to mount boot partition ${DISK}${PART_SUFFIX}2."
        exit 1
    fi

    if [ "$BOOTLOADER" == "UEFI" ]; then
        mkdir -p /mnt/boot/efi
        mount ${DISK}${PART_SUFFIX}1 /mnt/boot/efi
        if [ $? -ne 0 ]; then
            echo "Error: Failed to mount EFI partition ${DISK}${PART_SUFFIX}1."
            exit 1
        fi
    fi

    mkdir -p /mnt/home
    mount /dev/mapper/home /mnt/home
    if [ $? -ne 0 ]; then
        echo "Error: Failed to mount home partition /dev/mapper/home."
        exit 1
    fi

    # Create and enable swap file (after mounting root)
    echo "Creating swap file..."
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=8192    # 8GB swap file
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile

    # Add swap file to fstab
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab


    pacstrap /mnt base base-devel linux linux-firmware

    # Generate fstab
    echo "Generating fstab..."
    mkdir -p /mnt/etc
    genfstab -U /mnt >> /mnt/etc/fstab
    # Ensure /mnt/etc/crypttab exists
    echo "Generating crypttab..."
    touch /mnt/etc/crypttab
    # Create crypttab entry for encrypted home
    echo "home UUID=$(blkid -s UUID -o value ${DISK}${PART_SUFFIX}4) none luks" >> /mnt/etc/crypttab

    # Verify kernel image exists
    if [ ! -e /mnt/boot/vmlinuz-linux ]; then
        echo "Error: Kernel image /mnt/boot/vmlinuz-linux not found."
        exit 1
    fi
    # Generate initramfs
    arch-chroot /mnt mkinitcpio -P

    echo "Entering installed enviroment..."
    arch-chroot /mnt /bin/bash <<EOF
    pacman-key --init
    pacman-key --populate archlinux
    pacman -Syu --noconfirm

    echo "Setting locale..."
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen

    ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
    hwclock --systohc

    echo "Setting hostname..."
    echo $HOSTNAME > /etc/hostname
    echo "127.0.0.1   localhost" >> /etc/hosts
    echo "::1         localhost" >> /etc/hosts
    echo "127.0.1.1   $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts
    echo "Hostname set to:"
    cat /etc/hostname


    # Install sudo before configuring sudoers
    echo "Installing sudo..."
    pacman -S --needed sudo --noconfirm

    echo "Setting root password..."
    echo root:$ROOT_PASSWORD | chpasswd
    echo "Creating new user and setting password..."
    useradd -m $USERNAME
    echo $USERNAME:$USER_PASSWORD | chpasswd

    # Ensure the wheel group exists
    if ! getent group wheel > /dev/null 2>&1; then
        groupadd wheel
        echo "Wheel group created."
    fi

    # Ensure the sudo group exists
    if ! getent group sudo > /dev/null 2>&1; then
        groupadd sudo
        echo "Sudo group created."
    fi

    echo "Adding new user to the wheel and sudo groups..."
    usermod -aG wheel,sudo $USERNAME

    echo "Configuring sudoers..."
    echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
    echo '%sudo ALL=(ALL) ALL' >> /etc/sudoers

    echo "Updating mirrorlist..."
    pacman -S --needed reflector --noconfirm
    reflector --verbose --country 'US' --latest 100 --download-timeout 1 --number 15 --sort rate --save /etc/pacman.d/mirrorlist
    echo "Configuring parallel downloads in pacman.conf..."
    sed -i 's/^#ParallelDownloads = .*/ParallelDownloads = 32/' /etc/pacman.conf
    grep 'ParallelDownloads' /etc/pacman.conf

    pacman -S --needed git go --noconfirm
    sudo -u $USERNAME bash -c "
    cd ~
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    "

    pacman -S --needed xorg btop btrfs-progs chromium sddm plasma kde-system-meta kde-utilities-meta mpv okular gwenview kolourpaint spectacle k3b elisa unzip ffmpegthumbs kitty p7zip libreoffice-fresh $GRAPHICS_DRIVER $PROCESSOR_UCODE sddm networkmanager dhclient grub efibootmgr os-prober snapper openssh cups bluez bluez-utils zsh curl chezmoi openssl ttf-noto-nerd keepassxc qemu libvirt virt-manager nano wget --noconfirm

    systemctl enable sddm
    systemctl enable NetworkManager
    systemctl enable cups
    systemctl enable bluetooth
    systemctl enable sshd
    systemctl enable libvirtd

    sudo usermod -aG libvirt $(whoami)


    echo "Changing default shell to zsh for the user..."
    chsh -s /bin/zsh $USERNAME
     
    EOF

    # Ensure /boot/grub directory exists before generating GRUB configuration
    mkdir -p /mnt/boot/grub

    # Attempt to install GRUB bootloader based on bootloader type
    echo "Attempting to install GRUB bootloader..."

    GRUB_SUCCESS=0

    if [ "$BOOTLOADER" == "UEFI" ]; then
        GRUB_INSTALL_COMMANDS=(
            "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB"
            "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck --removable"
            "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --boot-directory=/boot --recheck"
        )
    else
        GRUB_INSTALL_COMMANDS=(
            "grub-install --target=i386-pc --boot-directory=/boot $DISK --recheck"
            "grub-install --target=i386-pc --boot-directory=/boot $DISK --force"
        )
    fi

    # Loop through each command until one succeeds
    for CMD in "${GRUB_INSTALL_COMMANDS[@]}"; do
        echo "Trying: $CMD"
        if arch-chroot /mnt /bin/bash -c "$CMD"; then
            echo "GRUB installation succeeded with: $CMD"
            GRUB_SUCCESS=1
            break
        else
            echo "GRUB installation failed with: $CMD"
        fi
    done

    # Check if GRUB installation was successful
    if [ $GRUB_SUCCESS -ne 1 ]; then
        echo "Error: GRUB installation failed for all tried methods."
        exit 1
    fi

    # Generate GRUB configuration
    echo "Generating GRUB configuration..."
    if ! arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
        echo "Error: Failed to generate GRUB configuration."
        exit 1
    fi

    echo "GRUB installation and configuration completed successfully."
    echo "
    -------------------------------------------------------------------------------"
    echo "Installation complete. Please reboot your system and remove your installation boot media..."
fi

# Add this after the GRUB configuration but before the final success message
echo "Copying installation files to new system..."
mkdir -p /mnt/root/arch-install
cp -r /root/custom/* /mnt/root/arch-install/

# Ensure scripts are executable in the new system
chmod +x /mnt/root/arch-install/install/preseedArch.sh
chmod +x /mnt/root/arch-install/install/deploymentArch.sh
chmod +x /mnt/root/arch-install/build-iso.sh
chmod +x /mnt/root/arch-install/test-installer.sh

echo "Installation files copied to /root/arch-install/"
echo "
-------------------------------------------------------------------------------"
echo "Installation complete. Please reboot your system and remove your installation boot media..."
