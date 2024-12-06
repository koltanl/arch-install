# Arch Linux Installation System

A three-phase installation system for Arch Linux: preseed, interactive, or automated installation.

## Scripts Overview

### preseedArch.sh
Base installation script that can run in three modes:
```bash
# Interactive mode (default)
./preseedArch.sh

# Automated mode with config
CONFIG_FILE=/path/to/preseed.conf ./preseedArch.sh

# Preseeded mode (looks for preseed.conf in installation media)
./preseedArch.sh
```

### deploymentArch.sh
Post-installation configuration script that sets up:
```bash
# Run after first boot
cd /root/arch-install
./install/deploymentArch.sh
```

Configures:
- Package management (yay)
- Desktop environment (KDE Plasma)
- Development tools (kitty, zsh, nnn)
- User configurations and dotfiles

## Configuration Files

### preseed.conf.template
Base template for system configuration:
```bash
# Disk setup
DISK_TYPE=3                # 1=SATA, 2=NVMe, 3=Virtio
DISK="/dev/vda"           # Target installation disk

# User accounts
USERNAME="archuser"        # Regular user account
ROOT_PASSWORD="root123"    # Root password
USER_PASSWORD="user123"    # User password
ENCRYPTION_PASSWORD="enc123" # Disk encryption

# System config
BOOTLOADER="UEFI"         # UEFI or BIOS
PROCESSOR_TYPE=1          # 1=Intel, 2=AMD
GRAPHICS_TYPE=5           # 1=Intel, 2=AMD, 3=NVIDIA, 4=Basic, 5=VM
HOSTNAME="archbox"        # System hostname

# Partition sizes (GB)
ROOT_PARTITION_SIZE=20    # Root partition
BOOT_PARTITION_SIZE=1     # Boot partition
EFI_PARTITION_SIZE=1      # EFI partition
SWAP_SIZE=8              # Swap file size
```

### .preseed.conf
Example configuration for VM testing:
```bash
DISK_TYPE=3              # Virtio for VM
DISK="/dev/vda"         # VM disk device
USERNAME="anon"         # Test account
HOSTNAME="lapbox"       # VM hostname
ROOT_PARTITION_SIZE=100 # Larger root for testing
SWAP_SIZE=4            # Smaller swap for VM
```

## Installation Methods

### Interactive Mode
Guided installation with prompts for:
- Hardware detection/configuration
- Disk partitioning
- User setup
- System configuration

### Automated Mode
Unattended installation using config file:
1. `cp install/.preseed.conf install/preseed.conf`
2. Edit `preseed.conf`
3. Run with `CONFIG_FILE` set

### Preseeded Mode
For reproducible installations:
1. Use template from `.preseed.conf`
2. Place in installation media
3. Boot and run

## System Layout

### Partition Schemes
- **Single Partition**: Encrypted root + boot/EFI + swap
- **Full Disk**: EFI + boot + root (100GB) + encrypted home + swap

### Hardware Support
- Storage: SATA, NVMe, Virtio
- CPU: Intel/AMD
- Graphics: Intel/AMD/NVIDIA
- Boot: UEFI/Legacy BIOS

## Troubleshooting

### Installation
- Boot issues: Check UEFI/BIOS settings
- Encryption: Verify cryptsetup config
- Hardware: Check compatibility/drivers

### Configuration
- Desktop: Check graphics/display setup
- Network: Verify NetworkManager
- Users: Check sudo/permissions
