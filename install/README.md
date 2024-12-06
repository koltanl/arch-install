# Arch Linux Installation System

Automated, interactive, and preseeded installation system for Arch Linux with full disk encryption support.

## Installation Methods

### 1. Interactive Mode (Default)
```bash
./install/preseedArch.sh
```
Guided installation with prompts for hardware, disk, and system configuration.

### 2. Automated Mode
```bash
CONFIG_FILE=/path/to/preseed.conf ./install/preseedArch.sh
```
Unattended installation using a configuration file.

### 3. Preseeded Mode
```bash
# Place preseed.conf in installation media
./install/preseedArch.sh
```

## Configuration

### preseed.conf
```bash
# Hardware Configuration
DISK_TYPE=3              # 1=SATA, 2=NVMe, 3=Virtio
DISK="/dev/vda"         # Target disk
PROCESSOR_TYPE=2        # 1=Intel, 2=AMD
GRAPHICS_TYPE=5         # 1=Intel, 2=AMD, 3=NVIDIA, 4=Basic, 5=VM
BOOTLOADER="UEFI"       # UEFI or BIOS

# System Configuration
USERNAME="anon"         # Primary user account
HOSTNAME="lapbox"       # System hostname
ROOT_PARTITION_SIZE=20  # Root partition size (GB)
SWAP_SIZE=8            # Swap size (GB)
```

## Installation Process

1. Base System (`preseedArch.sh`)
   - Hardware detection
   - Disk partitioning and encryption
   - Base system installation
   - Initial configuration

2. Post-Installation (`deploymentArch.sh`)
```bash
cd /root/arch-install
./install/deploymentArch.sh
```
   - Package management (yay)
   - Desktop environment (KDE Plasma)
   - Development tools
   - User configurations

## System Layout

### Partition Scheme
- EFI System Partition (1GB)
- Boot Partition (1GB)
- Encrypted Root Partition
- Swap (file-based)

### Hardware Support
- Storage: SATA, NVMe, Virtio
- CPU: Intel, AMD
- Graphics: Intel, AMD, NVIDIA, VM
- Boot: UEFI, Legacy BIOS

## Troubleshooting

### Common Issues
- UEFI/BIOS: Verify boot mode matches configuration
- Encryption: Check LUKS setup and passwords
- Graphics: Ensure correct driver selection
- Network: Verify NetworkManager status

### Logs
Installation logs are available at `/tmp/preseed.log`