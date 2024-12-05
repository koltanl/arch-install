#!/bin/bash

# Add these lines at the very start of preseedArch.sh
echo "[$(date)] Script started" >/tmp/preseed.log
echo "[$(date)] Current permissions: $(stat -c '%a' $0)" >>/tmp/preseed.log
echo "[$(date)] Current user: $(whoami)" >>/tmp/preseed.log
echo "[$(date)] Current directory: $(pwd)" >>/tmp/preseed.log

# Debug control
DEBUG=${DEBUG:-0}
if [ "$DEBUG" -eq 1 ]; then
    set -x
else
    set +x
fi

# Function to log messages
log_msg() {
    echo "$@" >&2
    echo "[$(date)] $@" >>/tmp/preseed.log
}

# Function to check if running in UEFI mode
check_uefi() {
    if [ -d "/sys/firmware/efi" ]; then
        log_msg "UEFI mode detected"
        return 0
    else
        log_msg "Legacy BIOS mode detected"
        return 1
    fi
}

# Function to determine installation type
determine_install_type() {
    local config_file="/root/custom/install/preseed.conf"
    
    if [ -f "$config_file" ]; then
        log_msg "Found preseed configuration file. Running automated installation."
        return 0
    else
        log_msg "No preseed configuration found. Running interactive installation."
        return 1
    fi
}

# Main execution
main() {
    clear
    echo "Welcome to Arch Linux Installation"
    echo "================================="
    
    # Check if script is run as root
    if [ "$EUID" -ne 0 ]; then
        log_msg "Error: This script must be run as root"
        exit 1
    fi
    
    # Verify we're booted in the correct mode
    check_uefi
    UEFI_BOOT=$?
    
    # Determine installation type
    if determine_install_type; then
        log_msg "Starting automated installation..."
        source /root/custom/install/autoArch.sh
    else
        log_msg "Starting interactive installation..."
        source /root/custom/install/interactiveArch.sh
    fi
    echo "================================="
    echo "Installation complete!"
    echo "Please remove your installation media and reboot your system."
    echo "You can reboot now by typing 'reboot' and pressing Enter."
    echo "================================="
}

# Run main function
main
