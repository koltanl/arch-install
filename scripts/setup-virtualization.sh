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

# Function to check and handle iptables
handle_iptables() {
    echo -e "${YELLOW}Checking iptables configuration...${NC}"
    
    # Check if iptables is required by other packages
    if pacman -Qi iptables >/dev/null 2>&1; then
        DEPS=$(pacman -Qii iptables | grep "Required By" | cut -d: -f2-)
        if [ -n "$DEPS" ] && [ "$DEPS" != "None" ]; then
            echo -e "${YELLOW}Warning: Cannot replace iptables with iptables-nft as it is required by other packages:${NC}"
            echo "$DEPS"
            echo -e "${YELLOW}Continuing with traditional iptables...${NC}"
            return 0
        else
            echo -e "${YELLOW}Removing traditional iptables...${NC}"
            pacman -R --noconfirm iptables || return 1
        fi
    fi
    
    # Install iptables-nft if iptables was successfully removed or wasn't installed
    if ! pacman -Qi iptables >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing iptables-nft...${NC}"
        pacman -S --noconfirm iptables-nft || return 1
    fi
}

# Function to install dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing virtualization dependencies...${NC}"
    
    # Handle iptables first
    handle_iptables || {
        echo -e "${RED}Failed to configure iptables${NC}"
        return 1
    }
    
    # Core virtualization packages (excluding iptables-nft as it's handled separately)
    for pkg in qemu-full libvirt virt-manager dnsmasq; do
        echo -e "${YELLOW}Installing $pkg...${NC}"
        pacman -S --needed --noconfirm "$pkg" || {
            echo -e "${RED}Failed to install $pkg${NC}"
            return 1
        }
    done
        
    # Optional but recommended packages
    for pkg in bridge-utils openbsd-netcat vde2 ebtables; do
        echo -e "${YELLOW}Installing optional package $pkg...${NC}"
        pacman -S --needed --noconfirm "$pkg" || {
            echo -e "${YELLOW}Warning: Failed to install optional package $pkg${NC}"
        }
    done
}

# Update verify_installation to handle either iptables or iptables-nft
verify_installation() {
    echo -e "${YELLOW}Verifying installation...${NC}"
    
    # Check if critical packages are installed
    local required_pkgs=(qemu-full libvirt virt-manager dnsmasq)
    local missing_pkgs=()
    
    # Check for either iptables or iptables-nft
    if ! (pacman -Qi iptables >/dev/null 2>&1 || pacman -Qi iptables-nft >/dev/null 2>&1); then
        missing_pkgs+=("iptables/iptables-nft")
    fi
    
    for pkg in "${required_pkgs[@]}"; do
        if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
            missing_pkgs+=("$pkg")
        fi
    done
    
    if [ ${#missing_pkgs[@]} -ne 0 ]; then
        echo -e "${RED}Error: The following required packages are not installed:${NC}"
        printf '%s\n' "${missing_pkgs[@]}"
        return 1
    fi
    
    echo -e "${GREEN}All required packages are installed${NC}"
    return 0
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
    install_dependencies || {
        echo -e "${RED}Failed to install dependencies${NC}"
        exit 1
    }
    verify_installation || {
        echo -e "${RED}Installation verification failed${NC}"
        exit 1
    }
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