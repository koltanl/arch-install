#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling
set -e
trap 'echo -e "${RED}An error occurred during virtualization removal.${NC}" >&2' ERR

echo -e "${GREEN}Starting KVM/QEMU virtualization removal...${NC}"

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Function to stop and disable services
disable_services() {
    echo -e "${YELLOW}Stopping and disabling virtualization services...${NC}"
    
    # Stop and disable services
    systemctl stop libvirtd.service 2>/dev/null || true
    systemctl disable libvirtd.service 2>/dev/null || true
    systemctl stop virtlogd.service 2>/dev/null || true
    systemctl disable virtlogd.service 2>/dev/null || true
    systemctl stop spice-vdagentd.service 2>/dev/null || true
    systemctl disable spice-vdagentd.service 2>/dev/null || true
}

# Function to remove user from groups
remove_user_groups() {
    echo -e "${YELLOW}Removing user from virtualization groups...${NC}"
    
    local CURRENT_USER=$(logname || echo $SUDO_USER)
    for group in libvirt kvm; do
        gpasswd -d "$CURRENT_USER" "$group" 2>/dev/null || true
    done
}

# Function to remove virtualization packages
remove_packages() {
    echo -e "${YELLOW}Removing virtualization packages...${NC}"
    
    # Core packages
    pacman -Rns --noconfirm \
        qemu-full \
        libvirt \
        virt-manager \
        dnsmasq \
        iptables-nft \
        bridge-utils \
        openbsd-netcat \
        vde2 \
        ebtables \
        spice-vdagent \
        spice-gtk 2>/dev/null || true
}

# Function to restore original configurations
restore_configs() {
    echo -e "${YELLOW}Restoring original configurations...${NC}"
    
    # Restore QEMU config if backup exists
    if [ -f "/etc/libvirt/qemu.conf.backup" ]; then
        mv /etc/libvirt/qemu.conf.backup /etc/libvirt/qemu.conf
    fi
    
    # Remove CPU-specific configurations
    rm -f /etc/modprobe.d/kvm-amd.conf
    rm -f /etc/modprobe.d/kvm-intel.conf
}

# Function to clean up storage pools and VMs
cleanup_storage() {
    echo -e "${YELLOW}Cleaning up storage pools and VMs...${NC}"
    
    # Stop all running VMs
    if command -v virsh >/dev/null 2>&1; then
        virsh list --all --name | while read domain; do
            [ ! -z "$domain" ] && virsh destroy "$domain" 2>/dev/null || true
        done
        
        # Remove all VM definitions
        virsh list --all --name | while read domain; do
            [ ! -z "$domain" ] && virsh undefine "$domain" --remove-all-storage 2>/dev/null || true
        done
        
        # Stop and remove default storage pool
        virsh pool-destroy default 2>/dev/null || true
        virsh pool-undefine default 2>/dev/null || true
    fi
    
    # Remove storage directory
    rm -rf /var/lib/libvirt/images
}

# Function to clean up remaining files
cleanup_files() {
    echo -e "${YELLOW}Cleaning up remaining files...${NC}"
    
    # Remove libvirt configuration directory
    rm -rf /etc/libvirt
    
    # Remove libvirt runtime directory
    rm -rf /var/run/libvirt
    
    # Remove libvirt log directory
    rm -rf /var/log/libvirt
}

# Main function
main() {
    check_root
    
    echo -e "${RED}WARNING: This will remove all virtualization capabilities and delete all VMs!${NC}"
    read -p "Are you sure you want to continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
    
    disable_services
    remove_user_groups
    cleanup_storage
    remove_packages
    restore_configs
    cleanup_files
    
    echo -e "${GREEN}Virtualization removal complete!${NC}"
    echo -e "${YELLOW}Notes:${NC}"
    echo -e "- System reboot recommended"
    echo -e "- All VMs and related configurations have been removed"
    echo -e "- Run setup-virtualization.sh to reinstall virtualization support"
}

# Run the script
main 