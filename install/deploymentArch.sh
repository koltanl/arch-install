#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
LAUNCHDIR="/root/arch-install"

# Get the real user (the one who invoked sudo, or default to the regular user)
REAL_USER=${SUDO_USER:-$USERNAME}

if [ -z "$REAL_USER" ]; then
    echo "Error: Could not determine user. Set USERNAME in environment"
    exit 1
fi

export HOME="/home/$REAL_USER"  # Force HOME to be user's home
REAL_HOME="$HOME"

# Verify user exists
if ! id "$REAL_USER" >/dev/null 2>&1; then
    echo -e "${RED}Error: User $REAL_USER does not exist${NC}"
    exit 1
fi

# Test mode flag
TEST_MODE=${TEST_MODE:-false}

# Near the top of the file, after the initial variable declarations
# Add better sudo password handling
if [ -n "$SUDO_PASS" ]; then
    # Create a temporary askpass script
    ASKPASS_SCRIPT=$(mktemp)
    cat > "$ASKPASS_SCRIPT" << EOF
#!/bin/bash
echo "$SUDO_PASS"
EOF
    chmod +x "$ASKPASS_SCRIPT"
    export SUDO_ASKPASS="$ASKPASS_SCRIPT"
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

# Function to run sudo commands with askpass
sudo_run() {
    local retries=3
    local cmd=("$@")
    local success=false

    for ((i=1; i<=retries; i++)); do
        if [ -n "$SUDO_PASS" ]; then
            if echo "$SUDO_PASS" | sudo -S "${cmd[@]}" 2>/dev/null; then
                success=true
                break
            fi
        elif [ -n "$SUDO_ASKPASS" ]; then
            if sudo -A "${cmd[@]}" 2>/dev/null; then
                success=true
                break
            fi
        else
            if sudo "${cmd[@]}" 2>/dev/null; then
                success=true
                break
            fi
        fi
        sleep 1
    done

    if ! $success; then
        echo "Error: Failed to run sudo command after $retries attempts"
        return 1
    fi
    return 0
}

# System update function
update_system() {
    echo "Updating system..."
    if ! sudo_run pacman -Syu --noconfirm; then
        echo "Error: System update failed"
        return 1
    fi
    return 0
}

# Install dependencies function
install_dependencies() {
    echo "Installing dependencies..."
    if ! sudo_run pacman -S --needed --noconfirm base-devel git go unzip; then
        echo "Error: Failed to install dependencies"
        return 1
    fi
    return 0
}

# Function to install yay if not present
install_yay() {
    echo "Installing yay..."
    if ! command_exists yay; then
        if ! install_dependencies; then
            echo "Error: Failed to install yay dependencies"
            return 1
        fi
        
        cd /tmp
        rm -rf yay  # Clean up any existing directory
        git clone https://aur.archlinux.org/yay.git
        cd yay
        
        # Set ownership and permissions
        if ! sudo_run chown -R "$REAL_USER:$REAL_USER" .; then
            echo "Error: Failed to set ownership for yay build"
            return 1
        fi
        
        # Build yay
        if ! sudo -u "$REAL_USER" makepkg -s --noconfirm; then
            echo "Error: Failed to build yay"
            return 1
        fi
        
        # Install yay package
        local pkg=$(ls yay-*.pkg.tar.zst 2>/dev/null | head -n1)
        if [ -n "$pkg" ]; then
            if ! sudo_run pacman -U --noconfirm "$pkg"; then
                echo "Error: Failed to install yay package"
                return 1
            fi
        else
            echo "Error: Could not find built yay package"
            return 1
        fi
        
        # Verify installation
        if ! command_exists yay; then
            echo "Error: Yay installation verification failed"
            return 1
        fi
    fi
    return 0
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
    fi
    
    # Define the correct path to pkglist.txt
    local pkglist_path="$LAUNCHDIR/install/pkglist.txt"
    
    if [ ! -f "$pkglist_path" ]; then
        echo -e "${RED}Error: pkglist.txt not found at $pkglist_path${NC}"
        return 1
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
    
    # Create required directories first
    create_required_dirs
    
    # Check multiple locations for dotfiles
    local dotfiles_locations=(
        "/root/arch-install/dotfiles"
        "./dotfiles"
        "$LAUNCHDIR/dotfiles"
        "$HOME/dotfiles"
        "$(dirname "$0")/../dotfiles"
    )
    
    local dotfiles_dir=""
    for loc in "${dotfiles_locations[@]}"; do
        # Use sudo to check directory existence
        if sudo test -d "$loc"; then
            echo "Found dotfiles in $loc"
            dotfiles_dir="$loc"
            break
        fi
    done
    
    if [ -n "$dotfiles_dir" ]; then
        echo "Copying dotfiles from $dotfiles_dir to $REAL_HOME"
        # Use sudo to list and copy files
        sudo find "$dotfiles_dir" -maxdepth 1 -type f -name ".*" -o -type f -name "*" | while read -r file; do
            basename=$(basename "$file")
            if [[ "$basename" != "." && "$basename" != ".." && "$basename" != "omp.json" ]]; then
                echo "Copying $basename to $REAL_HOME/"
                sudo cp "$file" "$REAL_HOME/$basename"
                sudo_run chown "$REAL_USER:$REAL_USER" "$REAL_HOME/$basename"
            fi
        done
    else
        handle_error "No dotfiles directory found in known locations"
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
        sudo_run chown "$REAL_USER:$REAL_USER" "$REAL_HOME/bin"
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
    sudo_run chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/kitty"

    # Look for kitty configs in multiple locations
    local kitty_locations=(
        "/root/arch-install/kitty"
        "./kitty"
        "$LAUNCHDIR/kitty"
        "$HOME/kitty"
        "$(dirname "$0")/../kitty"
    )
    
    local kitty_dir=""
    for loc in "${kitty_locations[@]}"; do
        if sudo test -d "$loc"; then
            echo "Found kitty config in $loc"
            kitty_dir="$loc"
            break
        fi
    done
    
    if [ -n "$kitty_dir" ]; then
        echo "Copying kitty configuration from $kitty_dir"
        # Copy config files first
        sudo cp "$kitty_dir/kitty.conf" "$REAL_HOME/.config/kitty/" 2>/dev/null || true
        sudo cp "$kitty_dir/theme.conf" "$REAL_HOME/.config/kitty/" 2>/dev/null || true
        
        # Copy themes directory if it exists
        if sudo test -d "$kitty_dir/kitty-themes"; then
            sudo cp -r "$kitty_dir/kitty-themes" "$REAL_HOME/.config/kitty/" 2>/dev/null || true
        fi
        
        # Copy terminal images if they exist
        for img in terminal.png 0terminal.png 1terminal.png; do
            if sudo test -f "$kitty_dir/$img"; then
                sudo cp "$kitty_dir/$img" "$REAL_HOME/.config/kitty/" 2>/dev/null || true
            fi
        done
        
        sudo_run chown -R "$REAL_USER:$REAL_USER" "$REAL_HOME/.config/kitty"
    else
        handle_error "Kitty configuration directory not found in known locations"
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
    
    # Look for scripts in multiple locations
    local scripts_locations=(
        "/root/arch-install/scripts"
        "./scripts"
        "$LAUNCHDIR/scripts"
        "$(dirname "$0")/../scripts"
    )
    
    local scripts_dir=""
    for loc in "${scripts_locations[@]}"; do
        if sudo test -d "$loc"; then
            echo "Found scripts in $loc"
            scripts_dir="$loc"
            break
        fi
    done
    
    if [ -n "$scripts_dir" ]; then
        # Create utils subdirectory if it exists in source
        if sudo test -d "$scripts_dir/utils"; then
            mkdir -p "$bin_dir/utils"
            sudo cp "$scripts_dir/utils/"*.{sh,py} "$bin_dir/utils/" 2>/dev/null || true
        fi
        
        # Copy scripts with error suppression
        sudo cp "$scripts_dir/"*.sh "$bin_dir/" 2>/dev/null || true
        sudo cp "$scripts_dir/"*.py "$bin_dir/" 2>/dev/null || true
        
        # Make everything executable and fix ownership
        sudo find "$bin_dir" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
        sudo_run chown -R "$REAL_USER:$REAL_USER" "$bin_dir"
    else
        handle_error "Scripts directory not found in known locations"
    fi
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
    
    # Look for omp.json in multiple locations
    local omp_locations=(
        "/root/arch-install/dotfiles/omp.json"
        "./dotfiles/omp.json"
        "$LAUNCHDIR/dotfiles/omp.json"
        "$HOME/dotfiles/omp.json"
        "$(dirname "$0")/../dotfiles/omp.json"
    )
    
    local omp_file=""
    for loc in "${omp_locations[@]}"; do
        if sudo test -f "$loc"; then
            echo "Found omp.json in $loc"
            omp_file="$loc"
            break
        fi
    done
    
    if [ -n "$omp_file" ]; then
        echo "Copying oh-my-posh configuration from $omp_file"
        sudo cp "$omp_file" "$config_dir/omp.json"
        sudo_run chown "$REAL_USER:$REAL_USER" "$config_dir/omp.json"
    else
        handle_error "Could not find omp.json in known locations"
    fi
}

# Function to install nnn from source with nerd fonts support
install_nnn() {
    echo "Installing nnn and required fonts..."
    echo "Installing dependencies and fonts..."
    if ! sudo_run pacman -S --needed --noconfirm gcc make pkg-config ncurses readline git; then
        echo "Error: Failed to install dependencies"
        return 1
    fi
    
    # Create and clean build directory
    local BUILD_DIR="/tmp/nnn-build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Clone and build nnn
    echo "Cloning and building nnn with nerd fonts support..."
    git clone https://github.com/jarun/nnn.git .
    make O_NERD=1
    if ! sudo_run make install; then
        echo "Error: Failed to install nnn"
        return 1
    fi
    
    return 0
}

# Function to change default shell to zsh
change_shell_to_zsh() {
    echo "Changing default shell to zsh..."
    if ! sudo_run pacman -S --needed --noconfirm zsh; then
        return 1
    fi
    
    echo "Changing shell for $USERNAME to zsh..."
    if ! sudo_run chsh -s /bin/zsh "$USERNAME"; then
        echo "Error: Failed to change shell to zsh"
        return 1
    fi
    return 0
}

# Add a function to create required directories
create_required_dirs() {
    echo "Creating required directories..."
    local dirs=(
        "$REAL_HOME/.config"
        "$REAL_HOME/.config/kitty"
        "$REAL_HOME/bin"
        "$REAL_HOME/.local/share"
        "$REAL_HOME/.config/plasma"
        "$REAL_HOME/.config/kdedefaults"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        sudo_run chown -R "$REAL_USER:$REAL_USER" "$dir"
    done
}

# Add a function to verify sudo access
verify_sudo_access() {
    echo "Verifying sudo access..."
    if ! sudo_run true; then
        echo "Error: Could not verify sudo access"
        return 1
    fi
    return 0
}

# Main installation process
main() {
    # Verify sudo access before proceeding
    if ! verify_sudo_access; then
        echo -e "${RED}Error: Could not obtain sudo access. Please check your permissions.${NC}"
        exit 1
    fi

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
    # install_packages || handle_error "Package installation failed"
    install_nnn || handle_error "NNN installation failed"
    change_shell_to_zsh || handle_error "Shell change failed"
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

    # Clean up installation files with proper permissions
    echo -e "${YELLOW}Cleaning up installation files...${NC}"
    cd /
    if [ -d "$LAUNCHDIR" ]; then
        sudo_run rm -rf "$LAUNCHDIR" || echo "Warning: Could not remove $LAUNCHDIR"
    fi
    
    # Clean up temporary files
    if [ -n "$ASKPASS_SCRIPT" ] && [ -f "$ASKPASS_SCRIPT" ]; then
        rm -f "$ASKPASS_SCRIPT" || echo "Warning: Could not remove askpass script"
    fi
    
    echo -e "${GREEN}Installation complete! Please log out and log back in for all changes to take effect.${NC}"
}

# Run the script
if [ "$(whoami)" = "root" ]; then
    # If running as root, re-execute as the target user with sudo
    exec sudo -u "$REAL_USER" -E "$0" "$@"
else
    main
fi 