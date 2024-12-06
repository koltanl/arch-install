#!/bin/bash

# Add at the beginning of deploymentArch.sh
if [ ! -f "/var/lib/first-login-deploy" ]; then
    echo "First-login deployment already completed"
    systemctl disable --now first-login-deploy
    exit 0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
LAUNCHDIR="/root/arch-install"
# Test mode flag
TEST_MODE=${TEST_MODE:-false}

# Function to handle errors but continue execution
handle_error() {
    echo -e "${RED}Error: $1${NC}" >&2
    return 0  # Continue execution
}

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
        echo -e "${YELLOW}TEST MODE: Would install packages from pkglist.txt${NC}"
        return 0
    fi
    
    # Enable multilib repository if not already enabled
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo -e "${YELLOW}Enabling multilib repository...${NC}"
        sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
        sudo pacman -Sy
    fi

    # Create array of packages from pkglist.txt
    local packages=()
    while read -r package; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^# ]] && continue
        packages+=("$package")
    done < pkglist.txt
    
    # Install all packages in a single pacman command
    if [ ${#packages[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing packages with pacman...${NC}"
        sudo pacman -S --needed --noconfirm "${packages[@]}" || true
        
        # Try remaining packages with yay
        echo -e "${YELLOW}Installing remaining packages with yay...${NC}"
        for package in "${packages[@]}"; do
            if ! pacman -Qi "$package" >/dev/null 2>&1; then
                yay -S --needed --noconfirm "$package" || true
            fi
        done
    fi
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
    mkdir -p "$HOME/.local/share"  # Some apps need this
    
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
    echo -e "${YELLOW}Setting up kitty terminal configuration...${NC}"
    
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would set up kitty configuration${NC}"
        return 0
    fi

    # Create kitty config directory if it doesn't exist
    mkdir -p "$HOME/.config/kitty"

    # Copy kitty configuration files
    if [ -d "$LAUNCHDIR/kitty" ]; then
        cp -r "$LAUNCHDIR/kitty/*" "$HOME/.config/kitty/"
    else
        echo -e "${RED}Warning: kitty configuration directory not found${NC}"
    fi
}

# Function to setup KDE configurations
setup_kde() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would setup KDE configurations in $HOME/.config${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up KDE configurations...${NC}"
    local kde_config_dir="$HOME/.config"
    
    # Create necessary directories
    mkdir -p "$kde_config_dir"
    mkdir -p "$kde_config_dir/kdedefaults"
    mkdir -p "$kde_config_dir/plasma"
    
    # Backup existing configs
    if [ -d "$kde_config_dir" ]; then
        echo "Backing up existing KDE configs..."
        for file in kwinrc kwinrulesrc kglobalshortcutsrc plasmarc plasmashellrc kdeglobals; do
            [ -f "$kde_config_dir/$file" ] && cp "$kde_config_dir/$file" "$kde_config_dir/$file.backup"
        done
    fi
    
    # Copy KWin configurations
    if [ -d "$LAUNCHDIR/kde/kwin" ]; then
        cp "$LAUNCHDIR/kde/kwin/*" "$kde_config_dir/"
    fi
    
    # Copy shortcuts
    if [ -d "$LAUNCHDIR/kde/shortcuts" ]; then
        cp "$LAUNCHDIR/kde/shortcuts/*" "$kde_config_dir/"
    fi
    
    # Copy Plasma configurations
    if [ -d "$LAUNCHDIR/kde/plasma" ]; then
        cp -r "$LAUNCHDIR/kde/plasma/*" "$kde_config_dir/"
    fi
    
    # Copy theme configurations
    if [ -f "$LAUNCHDIR/kde/kdeglobals" ]; then
        cp "$LAUNCHDIR/kde/kdeglobals" "$kde_config_dir/"
    fi
    
    if [ -d "$LAUNCHDIR/kde/kdedefaults" ]; then
        cp -r "$LAUNCHDIR/kde/kdedefaults" "$kde_config_dir/"
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
    
    # Create utils subdirectory if it exists in source
    if [ -d "scripts/utils" ]; then
        mkdir -p "$bin_dir/utils"
        cp "$LAUNCHDIR/scripts/utils/*.sh" "$bin_dir/utils/" 2>/dev/null || true
    fi
    
    # Copy scripts with error suppression
    cp "$LAUNCHDIR/scripts/*.sh" "$bin_dir/" 2>/dev/null || true
    cp "$LAUNCHDIR/scripts/*.py" "$bin_dir/" 2>/dev/null || true
    
    # Make everything executable
    find "$bin_dir" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
}

# Function to setup oh-my-posh theme
setup_omp() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would setup oh-my-posh configuration in $HOME/.config${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up oh-my-posh configuration...${NC}"
    local config_dir="$HOME/.config"
    mkdir -p "$config_dir"
    
    cp "$LAUNCHDIR/dotfiles/omp.json" "$config_dir/"
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
        sudo pacman -Syu --noconfirm || handle_error "System update failed"
    fi

    # Install core dependencies
    install_yay || handle_error "Yay installation failed"
    install_packages || handle_error "Package installation failed"
    install_zplug || handle_error "Zplug installation failed"
    install_oh_my_posh || handle_error "Oh-my-posh installation failed"
    install_atuin || handle_error "Atuin installation failed"
    setup_dotfiles || handle_error "Dotfiles setup failed"
    setup_kitty || handle_error "Kitty setup failed"
    setup_kde || handle_error "KDE setup failed"
    setup_scripts || handle_error "Scripts setup failed"
    setup_omp || handle_error "Oh-my-posh setup failed"

    # Run all scripts in torun directory
    echo -e "${YELLOW}Running additional configuration scripts...${NC}"
    if [ -d "$LAUNCHDIR/torun" ]; then
        for script in "$LAUNCHDIR/torun"/*.sh; do
            if [ -f "$script" ]; then
                echo -e "${YELLOW}Running $(basename "$script")...${NC}"
                sudo bash "$script" || handle_error "Failed to run $(basename "$script")"
            fi
        done
    fi

    echo -e "${GREEN}Installation complete! Please log out and log back in for all changes to take effect.${NC}"

    # Clean up installation files; ALWAYS KEEP THIS AT END OF SCRIPT
    echo -e "${YELLOW}Cleaning up installation files...${NC}"
    cd /
    rm -rf "$LAUNCHDIR"
}

# Run the script
main 

# At the end of the script
rm -f /var/lib/first-login-deploy
systemctl disable --now first-login-deploy 