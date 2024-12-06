#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
LAUNCHDIR="/root/arch-install"

# Source the preseed configuration
if [ -f "$LAUNCHDIR/install/preseed.conf" ]; then
    # shellcheck source=/dev/null
    source "$LAUNCHDIR/install/preseed.conf"
else
    echo -e "${RED}Error: preseed.conf not found at $LAUNCHDIR/install/preseed.conf${NC}"
    exit 1
fi

# Test mode flag
TEST_MODE=${TEST_MODE:-false}

# Set user variables from preseed configuration
REAL_USER="${USERNAME:-$SUDO_USER}"
REAL_HOME="/home/$REAL_USER"

# Verify user exists
if ! id "$REAL_USER" >/dev/null 2>&1; then
    echo -e "${RED}Error: User $REAL_USER does not exist${NC}"
    exit 1
fi

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
        # Install dependencies
        sudo pacman -S --needed git base-devel --noconfirm || handle_error "Failed to install yay dependencies"
        
        # Create build directory
        local BUILD_DIR="/tmp/yay-build"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        chown -R "$REAL_USER":"$REAL_USER" "$BUILD_DIR"
        
        # Clone and build yay as the real user
        cd "$BUILD_DIR" || return 1
        sudo -u "$REAL_USER" git clone https://aur.archlinux.org/yay.git "$BUILD_DIR"
        cd "$BUILD_DIR" || return 1
        sudo -u "$REAL_USER" makepkg -si --noconfirm
        
        # Clean up
        cd /
        rm -rf "$BUILD_DIR"
        
        if ! command_exists yay; then
            handle_error "Yay installation failed"
            return 1
        fi
    fi
}

# Function to install zplug if not present
install_zplug() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install zplug to $REAL_HOME/.zplug${NC}"
        return 0
    fi

    if [ ! -d "$REAL_HOME/.zplug" ]; then
        echo -e "${YELLOW}Installing zplug...${NC}"
        sudo -u "$REAL_USER" git clone https://github.com/zplug/zplug "$REAL_HOME/.zplug"
    fi
}

# Function to install packages from pkglist.txt
install_packages() {
    echo -e "${YELLOW}Installing packages from pkglist.txt...${NC}"
    
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install packages from pkglist.txt${NC}"
        return 0
    }
    
    # Define the correct path to pkglist.txt
    local pkglist_path="$LAUNCHDIR/install/pkglist.txt"
    
    if [ ! -f "$pkglist_path" ]; then
        echo -e "${RED}Error: pkglist.txt not found at $pkglist_path${NC}"
        return 1
    }
    
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
    done < "$pkglist_path"
    
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
        echo -e "${YELLOW}TEST MODE: Would copy dotfiles to $REAL_HOME${NC}"
        return 0
    fi
    
    # Create necessary directories
    mkdir -p "$REAL_HOME/.config"
    mkdir -p "$REAL_HOME/bin"
    mkdir -p "$REAL_HOME/.local/share"
    
    # Set proper ownership
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config"
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/bin"
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.local"
    
    # Copy dotfiles
    if [ -d "$LAUNCHDIR/dotfiles" ]; then
        echo "Copying dotfiles from $LAUNCHDIR/dotfiles to $REAL_HOME"
        for file in "$LAUNCHDIR/dotfiles"/.* "$LAUNCHDIR/dotfiles"/*; do
            basename=$(basename "$file")
            # Skip . .. and omp.json
            if [[ "$basename" != "." && "$basename" != ".." && "$basename" != "omp.json" && -f "$file" ]]; then
                echo "Copying $basename to $REAL_HOME/"
                cp "$file" "$REAL_HOME/$basename"
                chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/$basename"
            fi
        done
    else
        handle_error "Dotfiles directory not found at $LAUNCHDIR/dotfiles"
    fi
}

# Function to install oh-my-posh
install_oh_my_posh() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would install oh-my-posh to $REAL_HOME/bin${NC}"
        return 0
    fi

    if ! command_exists oh-my-posh; then
        echo -e "${YELLOW}Installing oh-my-posh...${NC}"
        mkdir -p "$REAL_HOME/bin"
        chown "$REAL_USER":"$REAL_USER" "$REAL_HOME/bin"
        sudo -u "$REAL_USER" curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$REAL_HOME/bin"
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

    # Create kitty config directory
    mkdir -p "$REAL_HOME/.config/kitty"
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/kitty"

    # Copy kitty configuration files
    if [ -d "$LAUNCHDIR/kitty" ]; then
        cp -r "$LAUNCHDIR/kitty/"* "$REAL_HOME/.config/kitty/" 2>/dev/null || true
        chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.config/kitty"
    else
        handle_error "Kitty configuration directory not found"
    fi
}

# Function to setup KDE configurations
setup_kde() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would setup KDE configurations in $REAL_HOME/.config${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up KDE configurations...${NC}"
    local kde_config_dir="$REAL_HOME/.config"
    
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
        cp "$LAUNCHDIR/kde/kwin/"* "$kde_config_dir/" 2>/dev/null || true
    fi
    
    # Copy shortcuts
    if [ -d "$LAUNCHDIR/kde/shortcuts" ]; then
        cp "$LAUNCHDIR/kde/shortcuts/"* "$kde_config_dir/" 2>/dev/null || true
    fi
    
    # Copy Plasma configurations
    if [ -d "$LAUNCHDIR/kde/plasma" ]; then
        cp -r "$LAUNCHDIR/kde/plasma/"* "$kde_config_dir/" 2>/dev/null || true
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
        echo -e "${YELLOW}TEST MODE: Would copy and make executable scripts in $REAL_HOME/bin${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up utility scripts...${NC}"
    local bin_dir="$REAL_HOME/bin"
    mkdir -p "$bin_dir"
    
    # Create utils subdirectory if it exists in source
    if [ -d "$LAUNCHDIR/scripts/utils" ]; then
        mkdir -p "$bin_dir/utils"
        cp "$LAUNCHDIR/scripts/utils/"*.sh "$bin_dir/utils/" 2>/dev/null || true
    fi
    
    # Copy scripts with error suppression
    cp "$LAUNCHDIR/scripts/"*.sh "$bin_dir/" 2>/dev/null || true
    cp "$LAUNCHDIR/scripts/"*.py "$bin_dir/" 2>/dev/null || true
    
    # Make everything executable
    find "$bin_dir" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
}

# Function to setup oh-my-posh theme
setup_omp() {
    if [ "$TEST_MODE" = true ]; then
        echo -e "${YELLOW}TEST MODE: Would setup oh-my-posh configuration in $REAL_HOME/.config${NC}"
        return 0
    fi

    echo -e "${YELLOW}Setting up oh-my-posh configuration...${NC}"
    local config_dir="$REAL_HOME/.config"
    mkdir -p "$config_dir"
    
    cp "$LAUNCHDIR/dotfiles/omp.json" "$config_dir/"
    chown "$REAL_USER":"$REAL_USER" "$config_dir/omp.json"
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