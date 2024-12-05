#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error handling
set -e
trap 'echo -e "${RED}An error occurred during execution. Installation failed.${NC}" >&2' ERR

echo -e "${GREEN}Starting system setup...${NC}"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install yay if not present
install_yay() {
    if ! command_exists yay; then
        echo -e "${YELLOW}Installing yay...${NC}"
        sudo pacman -S --needed git base-devel --noconfirm
        git clone https://aur.archlinux.org/yay.git /tmp/yay
        (cd /tmp/yay && makepkg -si --noconfirm)
        rm -rf /tmp/yay
    fi
}

# Function to install zplug if not present
install_zplug() {
    if [ ! -d "$HOME/.zplug" ]; then
        echo -e "${YELLOW}Installing zplug...${NC}"
        git clone https://github.com/zplug/zplug "$HOME/.zplug"
    fi
}

# Function to install packages from pkglist.txt
install_packages() {
    echo -e "${YELLOW}Installing packages from pkglist.txt...${NC}"
    # First try with pacman
    sudo pacman -S --needed --noconfirm - < pkglist.txt || true
    # Then try remaining packages with yay
    yay -S --needed --noconfirm - < pkglist.txt || true
}

# Function to setup dotfiles
setup_dotfiles() {
    echo -e "${YELLOW}Setting up dotfiles...${NC}"
    
    # Create necessary directories
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/bin"
    
    # Copy dotfiles
    for file in dotfiles/.*; do
        if [ -f "$file" ]; then
            basename=$(basename "$file")
            if [ "$basename" != "." ] && [ "$basename" != ".." ]; then
                echo "Copying $basename to $HOME/"
                cp "$file" "$HOME/$basename"
            fi
        fi
    done
}

# Function to install oh-my-posh
install_oh_my_posh() {
    if ! command_exists oh-my-posh; then
        echo -e "${YELLOW}Installing oh-my-posh...${NC}"
        curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/bin"
    fi
}

# Function to install atuin
install_atuin() {
    if ! command_exists atuin; then
        echo -e "${YELLOW}Installing atuin...${NC}"
        bash <(curl https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh)
    fi
}

# Function to setup kitty configuration
setup_kitty() {
    echo -e "${YELLOW}Setting up kitty terminal configuration...${NC}"
    local kitty_config_dir="$HOME/.config/kitty"
    mkdir -p "$kitty_config_dir"
    
    # Copy kitty configuration files
    cp -r kitty/* "$kitty_config_dir/"
    
    # Clone kitty-themes if not already present
    if [ ! -d "$kitty_config_dir/kitty-themes" ]; then
        git clone https://github.com/dexpota/kitty-themes.git "$kitty_config_dir/kitty-themes"
    fi
}

# Function to setup KDE configurations
setup_kde() {
    echo -e "${YELLOW}Setting up KDE configurations...${NC}"
    local kde_config_dir="$HOME/.config"
    
    # Backup existing configs
    if [ -d "$kde_config_dir" ]; then
        echo "Backing up existing KDE configs..."
        for file in kwinrc kwinrulesrc kglobalshortcutsrc plasmarc plasmashellrc kdeglobals; do
            [ -f "$kde_config_dir/$file" ] && cp "$kde_config_dir/$file" "$kde_config_dir/$file.backup"
        done
    fi
    
    # Copy KWin configurations
    if [ -d "kde/kwin" ]; then
        cp kde/kwin/* "$kde_config_dir/"
    fi
    
    # Copy shortcuts
    if [ -d "kde/shortcuts" ]; then
        cp kde/shortcuts/* "$kde_config_dir/"
    fi
    
    # Copy Plasma configurations
    if [ -d "kde/plasma" ]; then
        cp -r kde/plasma/* "$kde_config_dir/"
    fi
    
    # Copy theme configurations
    if [ -f "kde/kdeglobals" ]; then
        cp kde/kdeglobals "$kde_config_dir/"
    fi
    
    if [ -d "kde/kdedefaults" ]; then
        cp -r kde/kdedefaults "$kde_config_dir/"
    fi
}

# Function to setup scripts
setup_scripts() {
    echo -e "${YELLOW}Setting up utility scripts...${NC}"
    local bin_dir="$HOME/bin"
    mkdir -p "$bin_dir"
    
    # Copy all scripts to bin directory
    cp scripts/*.sh "$bin_dir/"
    cp scripts/*.py "$bin_dir/"
    
    # Make scripts executable
    chmod +x "$bin_dir"/*.sh
    chmod +x "$bin_dir"/*.py
    
}


# Function to setup oh-my-posh theme
setup_omp() {
    echo -e "${YELLOW}Setting up oh-my-posh configuration...${NC}"
    local config_dir="$HOME/.config"
    
    # Copy oh-my-posh configuration
    cp dotfiles/omp.json "$config_dir/"
}

setup_pacman() {
    echo -e "${YELLOW}Setting up Pacman configuration...${NC}"
    if [ -f "scripts/pacmaneyecandy.sh" ]; then
        sudo bash scripts/pacmaneyecandy.sh
    fi
}

# Function to setup KVM/QEMU
setup_virtualization() {
    echo -e "${YELLOW}Setting up KVM/QEMU virtualization...${NC}"
    
    # Enable multilib repository if not already enabled
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo -e "${YELLOW}Enabling multilib repository...${NC}"
        sudo sh -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
        sudo pacman -Sy
    fi
    
    # Remove conflicting iptables if present
    if pacman -Qi iptables &>/dev/null; then
        echo -e "${YELLOW}Removing conflicting iptables package...${NC}"
        sudo pacman -R --noconfirm iptables
    fi
    
    # Install required packages
    echo -e "${YELLOW}Installing virtualization dependencies...${NC}"
    sudo pacman -S --needed --noconfirm \
        qemu-full \
        libvirt \
        virt-manager \
        dnsmasq \
        iptables-nft \
        ebtables \
        bridge-utils \
        openbsd-netcat \
        lib32-gnutls \
        lib32-libxft \
        lib32-libpulse
    
    # Enable and start libvirtd service
    sudo systemctl enable --now libvirtd.service
    
    # Enable default network for VMs
    sudo virsh net-autostart default
    sudo virsh net-start default
    
    # Add user to required groups
    sudo usermod -aG libvirt,kvm,input,disk "$(whoami)"
    
    # Configure QEMU for better performance
    if [ ! -f "/etc/libvirt/qemu.conf.backup" ]; then
        sudo cp /etc/libvirt/qemu.conf /etc/libvirt/qemu.conf.backup
    fi
    
    # Set security driver to none for better performance
    sudo sed -i 's/#security_driver = "selinux"/security_driver = "none"/' /etc/libvirt/qemu.conf
    
    # Enable nested virtualization if AMD CPU
    if grep -q "AMD" /proc/cpuinfo; then
        echo "options kvm-amd nested=1" | sudo tee /etc/modprobe.d/kvm-amd.conf
    # Enable nested virtualization if Intel CPU
    elif grep -q "Intel" /proc/cpuinfo; then
        echo "options kvm-intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf
    fi
    
    # Configure SPICE for better clipboard and performance
    if [ ! -f "/etc/libvirt/qemu.conf.backup" ]; then
        sudo cp /etc/libvirt/qemu.conf /etc/libvirt/qemu.conf.backup
    fi
    
    # Configure SPICE settings
    sudo sed -i 's/#spice_listen = "0.0.0.0"/spice_listen = "127.0.0.1"/' /etc/libvirt/qemu.conf
    sudo sed -i 's/#spice_password = ""/spice_password = ""/' /etc/libvirt/qemu.conf
    
    # Enable SPICE features
    echo 'spice_options = "-agent-mouse=on -clipboard"' | sudo tee -a /etc/libvirt/qemu.conf
    
    # Ensure spice-vdagentd service is enabled
    sudo systemctl enable --now spice-vdagentd.service
    
    # Create default storage pool if it doesn't exist
    if ! sudo virsh pool-info default >/dev/null 2>&1; then
        sudo virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
        sudo virsh pool-build default
        sudo virsh pool-start default
        sudo virsh pool-autostart default
    fi
    
    # Restart libvirtd to apply changes
    sudo systemctl restart libvirtd.service
    
    echo -e "${GREEN}KVM/QEMU setup complete!${NC}"
    echo -e "${YELLOW}Note: You may need to log out and back in for group changes to take effect.${NC}"
    echo -e "${YELLOW}SPICE clipboard sharing has been configured.${NC}"
    echo -e "${YELLOW}Remember to install spice-vdagent inside your VMs for clipboard sharing to work.${NC}"
}

# Main installation process
main() {
    # Check if running on Arch Linux
    if [ ! -f "/etc/arch-release" ]; then
        echo -e "${RED}This script is designed for Arch Linux. Exiting...${NC}"
        exit 1
    fi

    # Update system first
    echo -e "${YELLOW}Updating system...${NC}"
    sudo pacman -Syu --noconfirm

    # Install core dependencies
    install_yay
    setup_pacman
    install_packages
    setup_virtualization
    install_zplug
    install_oh_my_posh
    install_atuin
    setup_dotfiles

    # Set zsh as default shell if it isn't already
    if [ "$SHELL" != "/usr/bin/zsh" ]; then
        echo -e "${YELLOW}Setting zsh as default shell...${NC}"
        chsh -s /usr/bin/zsh
    fi

    setup_kitty
    setup_kde
    setup_scripts
    setup_omp

    # Reload KDE configurations if running
    if pgrep -x "plasmashell" > /dev/null; then
        echo -e "${YELLOW}Reloading KDE configurations...${NC}"
        qdbus org.kde.KWin /KWin reconfigure
        qdbus org.kde.plasmashell /PlasmaShell evaluateScript "refreshAllDesktops()"
    fi

    echo -e "${GREEN}Installation complete! Please log out and log back in for all changes to take effect.${NC}"
}

# Run the script
main 