# Installation Guide

This guide explains the two-phase installation process using `preseedArch.sh` and `deploymentArch.sh`.

## Prerequisites

- A bootable Arch Linux USB (see main README for build instructions)
- Internet connection
- Target disk or partition for installation

## Phase 1: Base System Installation

### Pre-Installation Steps

1. Boot from Arch Linux USB
2. Verify internet connection:
   ```bash
   ping -c 3 archlinux.org
   ```

### Running preseedArch.sh

1. Get the installation files:
```bash
# Clone the repository
git clone https://github.com/koltanl/arch-install.git
cd arch-install/install
```

2. Start the installation:
```bash
./preseedArch.sh
```

#### Script Prompts

The script will ask for:

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

## Phase 2: System Configuration

After rebooting into your new system, run the deployment script for additional setup.

### Running deploymentArch.sh

1. Log into your new system
2. Run the deployment script:
```bash
./deploymentArch.sh
```

#### What Gets Configured

- **Package Management**
  - Yay AUR helper
  - System packages
  - Custom Pacman configuration

- **Desktop Environment**
  - KDE Plasma with custom configs
  - Window management rules
  - System shortcuts

- **Development Environment**
  - Kitty terminal + themes
  - Zsh + plugins
  - Development tools
  - Utility scripts

- **Virtualization**
  - KVM/QEMU configuration
  - Network bridges
  - SPICE support

## Partition Layouts

### Single Partition Setup
- Selected partition will be encrypted and used as root
- Boot/EFI partitions created at end of disk
- 8GB swap file created on root partition

### Full Disk Setup
- EFI/Boot partitions (based on bootloader type)
- 100GB root partition (ext4)
- Remaining space for encrypted home partition (ext4)
- 8GB swap file

## Troubleshooting

### Phase 1 Issues:
1. **GRUB Installation Fails**
   - Script attempts multiple installation methods
   - Check EFI/BIOS settings

2. **Encryption Issues**
   - Verify password input
   - Check if cryptsetup is working properly

3. **Partition Mounting Fails**
   - Verify partition exists
   - Check filesystem creation success

### Phase 2 Issues:
1. **Package Installation**
   - Check internet connection
   - Update package databases
   - Verify package names

2. **Desktop Environment**
   - Ensure plasma-desktop is installed
   - Check KDE dependencies

3. **Virtualization**
   - Verify CPU virtualization support
   - Check kernel modules

## Notes

- Backup any important data before installation
- Ensure secure password selection
- Note your encryption password - it cannot be recovered
- For VMs, ensure EFI/BIOS settings match host configuration

For additional help, file an issue at https://github.com/koltanl/arch-install/issues