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
- Log in and run `ip a` to find your new system's IP address

4. Complete Setup Remotely:
```bash
# From your original machine (with the git repo)

# Using default credentials from preseed.conf
./test-installer.sh -u --ip=192.168.1.100

# Or specify custom credentials
./test-installer.sh -u \
    --ip=192.168.1.100 \
    --username=myuser \
    --password=mypass
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
./test-installer.sh

# Quick test with existing ISO
./test-installer.sh --no-build
```

### Remote Deployment Options
```bash
# Default IP (192.168.111.207) and preseed.conf credentials
./test-installer.sh -u

# Custom IP address
./test-installer.sh -u --ip=192.168.1.100

# Custom credentials
./test-installer.sh -u \
    --ip=192.168.1.100 \
    --username=myuser \
    --password=mypass

# Save VM state for testing
./test-installer.sh --save

# Restore VM state
./test-installer.sh --restore
```

### Network Configuration
- Default target IP: 192.168.111.207
- Default network: 192.168.111.0/24
- Modify in test-installer.sh if needed

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
2. Test in VM with test-installer.sh
3. Use --save/--restore for quick iteration
4. Deploy with test-installer.sh -u

### Logs
- Installation: /tmp/install.log
- Deployment: Remote system logs via SSH

### Issues

- Decrypt the drive before running the `./test-installer.sh -u` command.
- Use the correct IP address.
- Ensure you are using the correct drivers.
- If you want to use interactive mode, make sure to rename the `preseed.conf` file.
- Sometimes the install will fail for no apparent reason and the VM won't bootstrap properly. Run `test-installer.sh -n` to redo the VM.
- Once you log in the first time, run `test-installer.sh -s` to save the VM state.
- the preseed.conf is being read for the username and password; send those manually if didnt use -u --ip=x.x.x.x --username=x --password=x
# Package Management

## Package List Configuration
The system uses a JSON-based package management configuration located at `install/pkglist.json`. This file controls which packages are installed during the deployment phase.

### Structure
```json
{
    "interactive_packages": [
        "plasma",
        // Packages that require user interaction during installation
    ],
    "pacman_packages": [
        // Official repository packages
    ],
    "aur_packages": [
        // AUR packages
    ]
}
```

### Handling Interactive Packages
Some packages require user interaction during installation. To add custom interactive package handling:

1. Add your package to the `interactive_packages` array in `pkglist.json`
2. Modify `install/deploymentArch.sh` to handle the interaction:
```bash
if [ "$package" = "your_package" ]; then
    # Example: Sending "1" and "2" as responses to prompts
    { echo "1"; echo "2"; } | sudo -S pacman -S --needed your_package
fi
```

### Customizing Packages
To modify the package selection:
1. Edit `install/pkglist.json`
2. Add or remove packages from appropriate sections:
   - `interactive_packages`: Packages requiring user input
   - `pacman_packages`: Official repository packages
   - `aur_packages`: AUR packages
3. Run the deployment script to apply changes
