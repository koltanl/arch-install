# Arch Linux Installation System

Automated, interactive, and preseeded installation system for Arch Linux with full disk encryption support.

## Quick Start

1. Run the build script to create installation media:
```bash
./build-iso.sh
```

2. The installation type is determined automatically:
- If `preseed.conf` exists: Runs unattended installation
- If `preseed.conf` is missing/renamed: Runs interactive installation

> **Note:** For interactive installation, simply rename or delete `preseed.conf`

## Configuration Options

### preseed.conf (for unattended installation)
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

### Package Management
The system uses a customizable JSON-based package configuration:

```bash
install/pkglist.json    # Package list configuration
```

You can modify this file to include your preferred packages while maintaining the following structure:

```json
{
    "interactive_packages": [
        # Packages requiring user interaction
    ],
    "pacman_packages": [
        # Official repository packages
    ],
    "aur_packages": [
        # AUR packages
    ]
}
```

> **Note:** The current configuration includes a full KDE Plasma desktop environment by default.

### Handling Interactive Packages
For packages requiring custom interaction during installation:

1. Add the package to `interactive_packages` in `pkglist.json`
2. Add handling in `deploymentArch.sh`:
```bash
if [ "$package" = "your_package" ]; then
    # Handle package's interactive installation
    { echo "1"; echo "2"; } | sudo -S pacman -S --needed your_package
fi
```

## Development Workflow

The development process follows these steps:

1. Run the full test suite:
   ```bash
   ./test-installer.sh
   ```

2. If VM issues occur, rebuild using the `-n` flag:
   ```bash
   ./test-installer.sh -n
   ```

3. Once you reach the first TTY in the new Arch installation, save the VM state:
   ```bash
   ./test-installer.sh -s
   ```

4. Iterate on your deployment script using `-u` (deploy) and `-r` (restore) flags:
   ```bash
   # Deploy changes to test system
   ./test-installer.sh -u

   # Restore to last saved state if needed
   ./test-installer.sh -r
   ```
   This allows for rapid testing cycles without rebuilding from scratch.

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

## Remote Deployment

The system is designed to complete installation over SSH, allowing you to monitor logs and debug from a working device. To deploy remotely:

```bash
./test-installer.sh -u --ip=192.168.1.100 --username=myuser --password=mypass
```

This approach offers several advantages:
- Full installation logs are available on your working device
- Real-time monitoring of the deployment process
- Ability to debug issues without switching machines
- Changes to deployment scripts can be made up until execution

> **Note:** The `-u` flag replaces the deployment script on the target system with your current version. This means you can modify the deployment script right up until you execute it, as it's not baked into the ISO like other installation files.

### Remote Deployment Process
1. Boot the target machine from installation media
2. Follow the instructions to complete the installation; reboot
3. Decrypt the drive and wait for the system to reach the first TTY and obtain network connectivity. 
> **Note:** Can get the device ip by logging in and running ```ip addr```
4. Run the test-installer with appropriate connection details
5. Monitor the installation progress from your working machine

## Additional Deployment Files

Any files placed in the `torun` folder will be automatically deployed alongside the deployment script. This allows you to:
- Include additional scripts or configurations
- Deploy custom themes or assets
- Add post-installation utilities

Current contents include:
```bash
torun/
├── arch-linux-grub-theme.tar    # Custom GRUB theme
├── grubthemer.sh               # GRUB theme installer
└── pacmaneyecandy.sh          # Pacman configuration utilities
```

> **Note:** Files in the `torun` folder are deployed upon creation of the iso.