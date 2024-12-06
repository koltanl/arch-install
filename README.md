# Arch Linux Installation Guide

Custom Arch Linux installation with automated setup scripts and configurations.

## What's Included

- Automated installation scripts
- KDE Plasma desktop environment
- Development environment setup
- Virtualization support (KVM/QEMU)
- Custom utility scripts and configurations

## Directory Structure
```
arch-install/
├── install/          # Installation scripts and documentation
├── kde/              # KDE Plasma configuration files
├── kitty/            # Kitty terminal configuration
├── scripts/          # Utility scripts
├── docs/             # Additional documentation
├── dotfiles/         # User configuration files
└── isoout/           # Built ISO files
```

## Building the ISO

### Prerequisites
```bash
# Install required packages
sudo pacman -S archiso
```

### Build Process

1. Clone the repository:
```bash
git clone https://github.com/koltanl/arch-install.git
cd arch-install
```

2. Make the build script executable:
```bash
chmod +x build-iso.sh
```

3. Run the build script:
```bash
./build-iso.sh
```
The script will:
- Create a temporary build environment
- Copy the base Arch ISO profile
- Add our custom installation scripts
- Include additional required packages
- Build a custom ISO file
- Ensure deployment files are included for post-install setup

4. Write the ISO to a USB drive:
```bash
# Replace sdX with your USB device (e.g., sdb)
sudo dd bs=4M if=isoout/archlinux*.iso of=/dev/sdX status=progress oflag=sync
```

> **Warning**: Be very careful with the `dd` command. Using the wrong device name can overwrite your system drive.

### Verifying USB Device Name
Before writing to USB:
```bash
# List all drives
lsblk

# Or for more detailed information
sudo fdisk -l
```

For detailed installation instructions, see [install/README.md](install/README.md)

## Post-Installation Setup

After completing the base installation and booting into your new system for the first time:

1. Log in with your user credentials
2. Run the deployment script to complete the setup:
```bash
sudo sh /root/arch-install/install/deploymentArch.sh
```
This script will:
- Configure your desktop environment
- Install additional packages
- Set up development tools
- Configure system services
- Apply custom configurations

> **Note**: The deployment script will automatically handle all post-installation configurations.

## Testing the Installation

### Using the VM Tester

The project includes an automated VM testing script that helps validate the installation process:

```bash
# Make the test script executable
chmod +x test-installer.sh

# Full test with fresh ISO build
./test-installer.sh

# Quick test using existing ISO (any of these options)
./test-installer.sh --refresh
./test-installer.sh -r
./test-installer.sh --skip-build
./test-installer.sh --no-build
./test-installer.sh --quick
```

The test script will:
- Build a fresh ISO using build-iso.sh (unless using quick options)
- Create a clean KVM virtual machine
- Boot the VM from the new ISO
- Provide connection details for testing

The test VM is configured with:
- 4GB RAM
- 2 CPU cores
- 20GB disk
- UEFI boot
- SPICE display

**Prerequisites:**
```bash
# Install required packages
sudo pacman -S virt-install libvirt
sudo systemctl enable --now libvirtd
```

To connect to the test VM:
```bash
virt-viewer --connect qemu:///session arch-install-test
```

This testing environment allows for rapid iteration and validation of the installation process without needing physical hardware.

**Quick Testing Tips:**
- Use `--quick` or `-r` when iterating on VM-related changes
- Use full build when testing ISO or installation script changes
- The VM's disk image is stored in your home directory at `~/.local/share/libvirt/images/`

