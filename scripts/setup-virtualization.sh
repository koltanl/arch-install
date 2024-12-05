#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling
set -e
trap 'echo -e "${RED}An error occurred during virtualization setup.${NC}" >&2' ERR

echo -e "${GREEN}Starting KVM/QEMU virtualization setup...${NC}"

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Function to enable multilib repository
enable_multilib() {
    echo -e "${YELLOW}Enabling multilib repository...${NC}"
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
        pacman -Sy
    fi
}

# Function to install dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing virtualization dependencies...${NC}"
    
    # Core virtualization packages
    pacman -S --needed --noconfirm \
        qemu-full \
        libvirt \
        virt-manager \
        dnsmasq \
        iptables-nft
        
    # Optional but recommended packages
    pacman -S --needed --noconfirm \
        bridge-utils \
        openbsd-netcat \
        vde2 \
        ebtables
}

# Function to configure system
configure_system() {
    echo -e "${YELLOW}Configuring system for virtualization...${NC}"
    
    # Enable and start services
    systemctl enable --now libvirtd.service
    systemctl enable --now virtlogd.service
    
    # Enable default network
    virsh net-autostart default
    virsh net-start default 2>/dev/null || true
    
    # Add current user to groups
    local CURRENT_USER=$(logname || echo $SUDO_USER)
    usermod -aG libvirt,kvm,input,disk "$CURRENT_USER"
    
    # Configure QEMU
    if [ ! -f "/etc/libvirt/qemu.conf.backup" ]; then
        cp /etc/libvirt/qemu.conf /etc/libvirt/qemu.conf.backup
    fi
    
    # Set security driver to none for better performance
    sed -i 's/#security_driver = "selinux"/security_driver = "none"/' /etc/libvirt/qemu.conf
}

# Function to setup CPU-specific features
setup_cpu_features() {
    echo -e "${YELLOW}Setting up CPU-specific features...${NC}"
    
    # Enable nested virtualization based on CPU
    if grep -q "AMD" /proc/cpuinfo; then
        echo "options kvm-amd nested=1" > /etc/modprobe.d/kvm-amd.conf
    elif grep -q "Intel" /proc/cpuinfo; then
        echo "options kvm-intel nested=1" > /etc/modprobe.d/kvm-intel.conf
    fi
}

# Function to configure SPICE
configure_spice() {
    echo -e "${YELLOW}Configuring SPICE...${NC}"
    
    # Install SPICE packages
    pacman -S --needed --noconfirm \
        spice-vdagent \
        spice-gtk
    
    # Configure SPICE settings
    sed -i 's/#spice_listen = "0.0.0.0"/spice_listen = "127.0.0.1"/' /etc/libvirt/qemu.conf
    sed -i 's/#spice_password = ""/spice_password = ""/' /etc/libvirt/qemu.conf
    
    # Enable SPICE features
    echo 'spice_options = "-agent-mouse=on -clipboard"' >> /etc/libvirt/qemu.conf
    
    # Enable SPICE agent service
    systemctl enable --now spice-vdagentd.service
}

# Function to setup storage
setup_storage() {
    echo -e "${YELLOW}Setting up storage pool...${NC}"
    
    # Create default storage pool if it doesn't exist
    if ! virsh pool-info default >/dev/null 2>&1; then
        virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
        virsh pool-build default
        virsh pool-start default
        virsh pool-autostart default
    fi
}

# Main function
main() {
    check_root
    enable_multilib
    install_dependencies
    configure_system
    setup_cpu_features
    configure_spice
    setup_storage
    
    # Restart libvirtd to apply all changes
    systemctl restart libvirtd.service
    
    echo -e "${GREEN}KVM/QEMU setup complete!${NC}"
    echo -e "${YELLOW}Notes:${NC}"
    echo -e "- Log out and back in for group changes to take effect"
    echo -e "- Install spice-vdagent in VMs for clipboard sharing"
    echo -e "- Use virt-manager to create and manage VMs"
    echo -e "- Check 'virsh list --all' to see all VMs"
}

# Run the script
main 