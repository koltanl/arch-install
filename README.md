# Arch Linux Installation Guide

Custom Arch Linux installation with automated setup scripts and remote deployment tools.

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)

## Quick Start

1. Build the installation ISO:
```bash
# Install required packages
sudo pacman -S archiso

# Clone repository
git clone https://github.com/koltanl/arch-install.git
cd arch-install

# Build ISO
./build-iso.sh
```

2. Write ISO to USB drive:
```bash
# List available devices
lsblk

# Write ISO (replace sdX with your device)
sudo dd bs=4M if=isoout/archlinux*.iso of=/dev/sdX status=progress oflag=sync
```

3. Install Arch Linux:
- Boot from the USB drive
- Follow the installation prompts
- After installation completes, reboot into your new system

4. Complete Setup (Choose one method):

A. Remote Deployment (Recommended for debugging):
```bash
# From your original machine
./arch-deploy.sh -u --ip=192.168.1.100
# Or specify custom credentials
./arch-deploy.sh -u \
    --ip=192.168.1.100 \
    --username=myuser \
    --password=mypass
```

B. Manual Deployment (Alternative method):
```bash
# From your new Arch installation
git clone https://github.com/koltanl/arch-install.git
cd arch-install
./manualdeployment.sh
```

The remote deployment will:
- Connect to the target system using provided credentials
- Configure your desktop environment
- Install development tools
- Set up system services
- Apply custom configurations

## Directory Structure
```
arch-install/
├── install/          # Installation scripts
├── kde/              # KDE Plasma configs
├── kitty/           # Terminal configs
├── scripts/         # Utility scripts
├── docs/            # Documentation
├── dotfiles/        # User configs
└── isoout/          # Built ISOs
```

## Advanced Usage

### Testing in VM
```bash
# Install dependencies
sudo pacman -S virt-install libvirt
sudo systemctl enable --now libvirtd

# Full test with fresh ISO
./arch-deploy.sh

# Quick test with existing ISO
./arch-deploy.sh --no-build
```

### Remote Deployment Options
```bash
# Default IP (192.168.111.207) and preseed.conf credentials
./arch-deploy.sh -u

# Custom IP address
./arch-deploy.sh -u --ip=192.168.1.100

# Custom credentials
./arch-deploy.sh -u \
    --ip=192.168.1.100 \
    --username=myuser \
    --password=mypass

# Save VM state for testing
./arch-deploy.sh --save

# Restore VM state
./arch-deploy.sh --restore
```

### Network Configuration
- Default network: 192.168.111.0/24
- Modify VM_IP in arch-deploy.sh to set target

### Build Options
The build-iso.sh script includes:
- Base Arch Linux system
- Custom installation scripts
- Required packages (git, wget, dialog, etc.)
- Deployment configurations

For detailed installation instructions, see [install/README.md](install/README.md)

## Development

### Prerequisites
- archiso
- libvirt (for testing)
- virt-install (for testing)
- QEMU/KVM (for testing)


### Testing Changes
1. Make script modifications
2. Test in VM with arch-deploy.sh
3. Use --save/--restore for quick iteration
4. Deploy with arch-deploy.sh -u

### Logs
- Installation: /tmp/install.log
- Deployment: Remote system logs via SSH

### Package List Configuration
- The package list is automatically included when you generate the ISO. The configuration is defined in `install/pkglist.json`, which specifies the packages to be installed during the deployment phase.

### Issues

- Decrypt the drive before running the `./arch-deploy.sh -u` command.
- Use the correct IP address.
- Ensure you are using the correct drivers.
- If you want to use interactive mode, make sure to rename the `preseed.conf` file.
- Sometimes the install will fail for no apparent reason and the VM won't bootstrap properly. Run `arch-deploy.sh -n` to redo the VM.
- Once you log in the first time, run `arch-deploy.sh -s` to save the VM state.
- the preseed.conf is being read for the username and password; send those manually: ```./arch-deploy.sh -u --ip=x.x.x.x --username=x --password=x```
