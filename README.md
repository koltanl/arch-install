# Arch Linux Installation Guide

This guide explains how to use the `makeitarchinstall.sh` script to install Arch Linux.

## Prerequisites

- A bootable Arch Linux USB
- Internet connection
- Target disk or partition for installation

## Pre-Installation Steps

1. Boot from Arch Linux USB
2. Verify internet connection:
   ```bash
   ping -c 3 archlinux.org
   ```

## Installation Process

### 1. Get the Installation Files
```bash
# Clone the repository
git clone https://github.com/koltanl/arch-install.git
cd arch-install
```

### 2. Run the Installation Script
```bash
./makeitarchinstall.sh
```

### 3. Script Prompts

The script will ask for several pieces of information:

- **Disk Type Selection**
  - SATA/IDE (e.g., /dev/sda)
  - NVMe (e.g., /dev/nvme0n1)

- **Installation Target**
  - Whole disk
  - Specific partition (e.g., /dev/nvme0n1p4)

- **User Information**
  - Root password
  - Username
  - User password

- **Encryption Password**
  - For root partition (if using single partition)
  - For home partition (if using whole disk)

- **Bootloader Type**
  - UEFI
  - Legacy BIOS

- **Hardware Information**
  - Processor type (Intel/AMD)
  - Graphics card type (Intel/AMD/Nvidia)

### 4. Installation Process

The script will then:
1. Format and encrypt the selected partition(s)
2. Install base system
3. Configure system settings
4. Install bootloader
5. Set up user accounts

### 5. Post-Installation

After the script completes:
1. Reboot the system
2. Remove the installation media
3. Log in to your new Arch Linux installation
4. Run the post-installation script (`insidearchinstall.sh`)

## Partition Layouts

### Single Partition Setup
When using a single partition:
- Selected partition will be encrypted and used as root
- Boot/EFI partitions created at end of disk
- 8GB swap file created on root partition

### Full Disk Setup
When using entire disk:
- EFI/Boot partitions (based on bootloader type)
- 100GB root partition (ext4)
- Remaining space for encrypted home partition (ext4)
- 8GB swap file

## Troubleshooting

### Common Issues:
1. **GRUB Installation Fails**
   - Script attempts multiple installation methods
   - Check EFI/BIOS settings

2. **Encryption Issues**
   - Verify password input
   - Check if cryptsetup is working properly

3. **Partition Mounting Fails**
   - Verify partition exists
   - Check filesystem creation success

### Getting Help
If you encounter issues:
1. Check the error messages
2. Verify hardware compatibility
3. Ensure UEFI/BIOS settings are correct
4. File an issue at https://github.com/koltanl/arch-install/issues

## Notes

- Backup any important data before installation
- Ensure secure password selection
- Note your encryption password - it cannot be recovered
- For VMs, ensure EFI/BIOS settings match host configuration
