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

### Package Management
The system uses a JSON-based package configuration file:

```bash
install/pkglist.json    # Package list configuration
```

#### Package List Structure
```json
{
    "interactive_packages": [
        # Packages requiring user interaction during installation
        # e.g., "plasma"
    ],
    "pacman_packages": [
        # Official repository packages
        # e.g., "firefox", "git"
    ],
    "aur_packages": [
        # AUR packages
        # e.g., "visual-studio-code-bin"
    ]
}
```

#### Customizing Interactive Package Installation
For packages requiring custom interaction during installation:

1. Add the package to the `interactive_packages` array in `pkglist.json`
2. Modify the `install_packages` function in `deploymentArch.sh`:
```bash
if [ "$package" = "your_package" ]; then
    # Handle your package's interactive installation
    { echo "1"; echo "2"; } | sudo -S pacman -S --needed your_package
fi
```
The example above sends "1" and "2" as responses to interactive prompts.

#### Customizing Package Selection
1. Edit `pkglist.json`
2. Modify package lists in appropriate sections
3. Run deployment script to apply changes:
```bash
cd /root/arch-install
./install/deploymentArch.sh
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

### Development Workflow
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