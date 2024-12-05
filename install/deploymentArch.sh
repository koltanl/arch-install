#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test mode flag
TEST_MODE=${TEST_MODE:-false}

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
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install yay if not present${NC}"
        return 0
    fi

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
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install zplug to $HOME/.zplug${NC}"
        return 0
    fi

    if [ ! -d "$HOME/.zplug" ]; then
        echo -e "${YELLOW}Installing zplug...${NC}"
        git clone https://github.com/zplug/zplug "$HOME/.zplug"
    fi
}

# Function to install packages from pkglist.txt
install_packages() {
    echo -e "${YELLOW}Installing packages from pkglist.txt...${NC}"
    
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install the following packages:${NC}"
        grep -v '^#' pkglist.txt | grep -v '^$'
        return 0
    fi
    
    # Enable multilib repository if not already enabled
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo -e "${YELLOW}Enabling multilib repository...${NC}"
        sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
        sudo pacman -Sy
    fi
    
    # First try with pacman
    while read -r package; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^# ]] && continue
        
        echo -e "${YELLOW}Installing $package...${NC}"
        sudo pacman -S --needed --noconfirm "$package" || true
    done < pkglist.txt
    
    # Then try remaining packages with yay
    while read -r package; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^# ]] && continue
        
        if ! pacman -Qi "$package" >/dev/null 2>&1; then
            echo -e "${YELLOW}Installing $package with yay...${NC}"
            yay -S --needed --noconfirm "$package" || true
        fi
    done < pkglist.txt
}

# Function to setup dotfiles
setup_dotfiles() {
    echo -e "${YELLOW}Setting up dotfiles...${NC}"
    
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would copy dotfiles to $HOME${NC}"
        return 0
    fi
    
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
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install oh-my-posh to $HOME/bin${NC}"
        return 0
    fi

    if ! command_exists oh-my-posh; then
        echo -e "${YELLOW}Installing oh-my-posh...${NC}"
        sudo mkdir -p /tmp/bin
        mkdir -p "$HOME/bin"
        sudo curl -s https://ohmyposh.dev/install.sh | sudo bash -s -- -d /tmp/bin
        curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/bin"
    fi
}

# Function to install atuin
install_atuin() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install atuin${NC}"
        return 0
    fi

    if ! command_exists atuin; then
        echo -e "${YELLOW}Installing atuin...${NC}"
        bash <(curl https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh)
    fi
}

# Function to setup kitty configuration
setup_kitty() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would setup kitty configuration in $HOME/.config/kitty${NC}"
        echo -e "${YELLOW}TEST MODE: Would clone kitty-themes repository${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up kitty terminal configuration...${NC}"
    local kitty_config_dir="$HOME/.config/kitty"
    mkdir -p "$kitty_config_dir"
    
    cp -r kitty/* "$kitty_config_dir/"
    
    if [ ! -d "$kitty_config_dir/kitty-themes" ]; then
        git clone https://github.com/dexpota/kitty-themes.git "$kitty_config_dir/kitty-themes"
    fi
}

# Function to setup KDE configurations
setup_kde() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would setup KDE configurations in $HOME/.config${NC}"
        echo -e "${YELLOW}TEST MODE: Would backup existing KDE configs${NC}"
        echo -e "${YELLOW}TEST MODE: Would copy KDE configuration files:${NC}"
        echo "  - KWin configurations"
        echo "  - Shortcuts"
        echo "  - Plasma configurations"
        echo "  - Theme configurations"
        return 0
    fi

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
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would copy and make executable scripts in $HOME/bin${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up utility scripts...${NC}"
    local bin_dir="$HOME/bin"
    mkdir -p "$bin_dir"
    
    cp scripts/*.sh "$bin_dir/"
    cp scripts/*.py "$bin_dir/"
    
    chmod +x "$bin_dir"/*.sh
    chmod +x "$bin_dir"/*.py
}

# Function to setup oh-my-posh theme
setup_omp() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would setup oh-my-posh configuration in $HOME/.config${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up oh-my-posh configuration...${NC}"
    local config_dir="$HOME/.config"
    
    cp dotfiles/omp.json "$config_dir/"
}

setup_pacman() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would configure pacman eye candy${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up Pacman configuration...${NC}"
    if [ -f "scripts/pacmaneyecandy.sh" ]; then
        sudo bash scripts/pacmaneyecandy.sh
    fi
}

# Main installation process
main() {
    # Check if running on Arch Linux
    if [ ! -f "/etc/arch-release" ]; then
        echo -e "${RED}This script is designed for Arch Linux. Exiting...${NC}"
        exit 1
    fi

    # Update system first
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would update system packages${NC}"
    else
        echo -e "${YELLOW}Updating system...${NC}"
        sudo pacman -Syu --noconfirm
    fi

    # Install core dependencies
    install_yay
    setup_pacman
    install_packages
    install_zplug
    install_oh_my_posh
    install_atuin
    setup_dotfiles
    setup_kitty
    setup_kde
    setup_scripts
    setup_omp

    # Set zsh as default shell if it isn't already
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would set zsh as default shell${NC}"
    elif [ "$SHELL" != "/usr/bin/zsh" ]; then
        echo -e "${YELLOW}Setting zsh as default shell...${NC}"
        sudo chsh -s /usr/bin/zsh "$USER"
    fi

    # Reload KDE configurations if running
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would reload KDE configurations if running${NC}"
    elif pgrep -x "plasmashell" > /dev/null; then
        echo -e "${YELLOW}Reloading KDE configurations...${NC}"
        qdbus org.kde.KWin /KWin reconfigure
        qdbus org.kde.plasmashell /PlasmaShell evaluateScript "refreshAllDesktops()"
    fi

    echo -e "${GREEN}Installation complete! Please log out and log back in for all changes to take effect.${NC}"
}

# Run the script
main 