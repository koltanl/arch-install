#!/bin/bash

# Start time measurement
START_TIME=$(date +%s)

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
            if sudo -S "${cmd[@]}" 2>/dev/null; then
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

# Function to install packages from pkglist.json
install_packages() {
    echo -e "${YELLOW}Installing packages from pkglist.json...${NC}"
    
    # First, ensure jq is installed
    if ! command -v jq >/dev/null 2>&1; then
        echo "Installing jq for JSON parsing..."
        if [ -n "$SUDO_PASS" ]; then
            printf "%s\n" "$SUDO_PASS" | sudo -S pacman -S --needed --noconfirm jq || {
                echo -e "${RED}Error: Failed to install jq. Cannot proceed with package installation.${NC}"
                return 1
            }
        else
            sudo pacman -S --needed --noconfirm jq || {
                echo -e "${RED}Error: Failed to install jq. Cannot proceed with package installation.${NC}"
                return 1
            }
        fi
    fi
    
    local pkglist_path="/root/arch-install/install/pkglist.json"
    
    if ! sudo test -f "$pkglist_path"; then
        echo -e "${RED}Error: pkglist.json not found at $pkglist_path${NC}"
        return 1
    fi

    # Enable multilib repository first
    echo "DEBUG: Enabling multilib repository..."
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo "DEBUG: Adding multilib repository to pacman.conf"
        sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
        sudo pacman -Sy
    else
        echo "DEBUG: multilib repository already enabled"
    fi

    # Read and parse JSON file
    local json_content
    json_content=$(sudo cat "$pkglist_path")
    
    # Validate JSON content
    if ! echo "$json_content" | jq empty 2>/dev/null; then
        echo -e "${RED}Error: Invalid JSON in pkglist.json${NC}"
        return 1
    fi
    
    echo "DEBUG: Successfully parsed JSON file"
    
    # First pass: Install interactive packages
    echo -e "${YELLOW}Installing packages that require interaction...${NC}"
    if ! interactive_packages=$(echo "$json_content" | jq -r '.interactive_packages[]' 2>/dev/null); then
        echo -e "${RED}Error: Failed to parse interactive_packages from JSON${NC}"
        echo "DEBUG: JSON content for interactive_packages:"
        echo "$json_content" | jq '.interactive_packages' || echo "Failed to show interactive_packages content"
    else
        echo "DEBUG: Found interactive packages:"
        echo "$interactive_packages"
        
        while IFS= read -r package; do
            [ -z "$package" ] && continue
            echo "DEBUG: Installing interactive package: $package"
            if [ "$package" = "plasma" ]; then
                    { echo "1"; } | sudo -S pacman -S --needed --noconfirm plasma || true
            fi
        done <<< "$interactive_packages"
    fi
    
    # Second pass: Install regular pacman packages
    echo -e "${YELLOW}Installing packages from official repositories...${NC}"
    if ! pacman_packages=$(echo "$json_content" | jq -r '.pacman_packages[]' 2>/dev/null); then
        echo -e "${RED}Error: Failed to parse pacman_packages from JSON${NC}"
        echo "DEBUG: JSON content for pacman_packages:"
        echo "$json_content" | jq '.pacman_packages' || echo "Failed to show pacman_packages content"
    else
        echo "DEBUG: Found pacman packages, converting to array..."
        
        # Convert newline-separated list to array
        local packages=()
        while IFS= read -r package; do
            [ -z "$package" ] && continue
            packages+=("$package")
        done <<< "$pacman_packages"
        
        if [ ${#packages[@]} -gt 0 ]; then
            echo "DEBUG: Installing ${#packages[@]} regular packages in batches"
            
            # Process packages in batches of 32
            local batch_size=32
            local total_packages=${#packages[@]}
            local batch_count=$(( (total_packages + batch_size - 1) / batch_size ))
            
            for ((i = 0; i < batch_count; i++)); do
                local start=$((i * batch_size))
                local end=$((start + batch_size))
                # Ensure we don't go past the array bounds
                if [ $end -gt $total_packages ]; then
                    end=$total_packages
                fi
                
                echo "DEBUG: Installing batch $((i+1))/$batch_count (packages $((start+1))-$end of $total_packages)"
                
                # Extract the current batch of packages
                local current_batch=("${packages[@]:start:batch_size}")
                
                if [ -n "$SUDO_PASS" ]; then
                    printf "%s\n" "$SUDO_PASS" | \
                        sudo -S pacman -S --needed --noconfirm "${current_batch[@]}" || {
                            echo -e "${RED}Warning: Some packages in batch $((i+1)) failed to install${NC}"
                        }
                else
                    sudo pacman -S --needed --noconfirm "${current_batch[@]}" || {
                        echo -e "${RED}Warning: Some packages in batch $((i+1)) failed to install${NC}"
                    }
                fi
                
                # Small delay between batches to allow system to settle
                sleep 1
            done
        else
            echo "DEBUG: No regular packages to install"
        fi
    fi
    
    # Third pass: Install AUR packages
    echo -e "${YELLOW}Installing AUR packages...${NC}"
    if ! aur_packages=$(echo "$json_content" | jq -r '.aur_packages[]' 2>/dev/null); then
        echo -e "${RED}Error: Failed to parse aur_packages from JSON${NC}"
        echo "DEBUG: JSON content for aur_packages:"
        echo "$json_content" | jq '.aur_packages' || echo "Failed to show aur_packages content"
    else
        echo "DEBUG: Found AUR packages:"
        echo "$aur_packages"
        
        while IFS= read -r package; do
            [ -z "$package" ] && continue
            echo "DEBUG: Installing AUR package: $package"
            if [ -n "$SUDO_PASS" ]; then
                printf "%s\n" "$SUDO_PASS" | \
                sudo -u "$REAL_USER" \
                    SUDO_ASKPASS="$ASKPASS_SCRIPT" \
                    HOME="/home/$REAL_USER" \
                    USER="$REAL_USER" \
                    LOGNAME="$REAL_USER" \
                    PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl" \
                    yay -S --needed --noconfirm --sudoflags "-S" "$package" || {
                        echo -e "${RED}Warning: Failed to install AUR package: $package${NC}"
                    }
            else
                sudo -u "$REAL_USER" \
                    HOME="/home/$REAL_USER" \
                    USER="$REAL_USER" \
                    LOGNAME="$REAL_USER" \
                    PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl" \
                    yay -S --needed --noconfirm "$package" || {
                        echo -e "${RED}Warning: Failed to install AUR package: $package${NC}"
                    }
            fi
        done <<< "$aur_packages"
    fi
    
    echo "DEBUG: Package installation completed"
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
    sudo_run chown -R "$REAL_USER:$REAL_USER" "$kde_config_dir"
    
    # Look for KDE configs in multiple locations
    local kde_locations=(
        "/root/arch-install/kde"
        "./kde"
        "$LAUNCHDIR/kde"
        "$(dirname "$0")/../kde"
    )
    
    local kde_dir=""
    for loc in "${kde_locations[@]}"; do
        if sudo test -d "$loc"; then
            echo "Found KDE configs in $loc"
            kde_dir="$loc"
            break
        fi
    done
    
    if [ -n "$kde_dir" ]; then
        echo "Setting up KDE configurations from $kde_dir"
        
        # Backup existing configs
        if [ -d "$kde_config_dir" ]; then
            echo "Backing up existing KDE configs..."
            for file in kwinrc kwinrulesrc kglobalshortcutsrc plasmarc plasmashellrc kdeglobals; do
                [ -f "$kde_config_dir/$file" ] && sudo cp "$kde_config_dir/$file" "$kde_config_dir/$file.backup"
            done
        fi
        
        # Copy KWin configurations
        if sudo test -d "$kde_dir/kwin"; then
            echo "Copying KWin configurations..."
            sudo cp "$kde_dir/kwin/"* "$kde_config_dir/" 2>/dev/null || true
        fi
        
        # Copy shortcuts
        if sudo test -d "$kde_dir/shortcuts"; then
            echo "Copying shortcuts..."
            sudo cp "$kde_dir/shortcuts/"* "$kde_config_dir/" 2>/dev/null || true
        fi
        
        # Copy Plasma configurations
        if sudo test -d "$kde_dir/plasma"; then
            echo "Copying Plasma configurations..."
            sudo cp -r "$kde_dir/plasma/"* "$kde_config_dir/" 2>/dev/null || true
        fi
        
        # Copy theme configurations
        if sudo test -f "$kde_dir/kdeglobals"; then
            echo "Copying kdeglobals..."
            sudo cp "$kde_dir/kdeglobals" "$kde_config_dir/"
        fi
        
        if sudo test -d "$kde_dir/kdedefaults"; then
            echo "Copying KDE defaults..."
            sudo cp -r "$kde_dir/kdedefaults/"* "$kde_config_dir/kdedefaults/" 2>/dev/null || true
        fi
        
        # Fix ownership
        sudo_run chown -R "$REAL_USER:$REAL_USER" "$kde_config_dir"
        
        # List what we copied
        echo "KDE configurations installed:"
        ls -la "$kde_config_dir"
        echo "KDE defaults installed:"
        ls -la "$kde_config_dir/kdedefaults"
    else
        handle_error "KDE configuration directory not found in known locations"
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
        echo "Setting up scripts from $scripts_dir"
        
        # Create utils subdirectory if it exists in source
        if sudo test -d "$scripts_dir/utils"; then
            echo "Found utils directory, copying utils scripts..."
            mkdir -p "$bin_dir/utils"
            # Copy utils scripts separately to avoid brace expansion issues
            sudo find "$scripts_dir/utils" -type f -name "*.sh" -exec cp {} "$bin_dir/utils/" \;
            sudo find "$scripts_dir/utils" -type f -name "*.py" -exec cp {} "$bin_dir/utils/" \;
        fi
        
        # Copy root scripts separately
        echo "Copying root scripts..."
        sudo find "$scripts_dir" -maxdepth 1 -type f -name "*.sh" -exec cp {} "$bin_dir/" \;
        sudo find "$scripts_dir" -maxdepth 1 -type f -name "*.py" -exec cp {} "$bin_dir/" \;
        
        # Make everything executable and fix ownership
        echo "Setting permissions..."
        sudo find "$bin_dir" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;
        sudo_run chown -R "$REAL_USER:$REAL_USER" "$bin_dir"
        
        # List what we copied
        echo "Scripts installed:"
        ls -la "$bin_dir"
        echo "Utils installed:"
        ls -la "$bin_dir/utils"
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

# Add this function before main()
secure_ssh() {
    echo -e "${YELLOW}Securing SSH configuration...${NC}"
    
    local sshd_config="/etc/ssh/sshd_config"
    
    if [ -f "$sshd_config" ]; then
        echo "Disabling SSH password authentication and root login..."
        # Disable password authentication
        sudo sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication no/' "$sshd_config"
        # Disable root login
        sudo sed -i 's/^PermitRootLogin yes/#PermitRootLogin prohibit-password/' "$sshd_config"
        
        # Restart SSH service to apply changes
        if systemctl is-active sshd >/dev/null 2>&1; then
            echo "Restarting SSH service..."
            sudo_run systemctl restart sshd
        fi
    else
        handle_error "SSH config file not found at $sshd_config"
    fi
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
    install_packages || handle_error "Package installation failed"
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
    sudo systemctl enable sddm

    # Clean up installation files with proper permissions
    echo -e "${YELLOW}Cleaning up installation files...${NC}"
    
    # Secure SSH first
    secure_ssh || handle_error "Failed to secure SSH configuration"
    
    # Then clean up files
    cd /
    if [ -d "$LAUNCHDIR" ]; then
        sudo_run rm -rf "$LAUNCHDIR" || echo "Warning: Could not remove $LAUNCHDIR"
    fi
    
    # Clean up temporary files
    if [ -n "$ASKPASS_SCRIPT" ] && [ -f "$ASKPASS_SCRIPT" ]; then
        rm -f "$ASKPASS_SCRIPT" || echo "Warning: Could not remove askpass script"
    fi
    
    echo -e "${GREEN}Installation complete! Please log out and log back in for all changes to take effect.${NC}"
    
    # Calculate and display elapsed time
    END_TIME=$(date +%s)
    ELAPSED_TIME=$((END_TIME - START_TIME))
    HOURS=$((ELAPSED_TIME / 3600))
    MINUTES=$(( (ELAPSED_TIME % 3600) / 60 ))
    SECONDS=$((ELAPSED_TIME % 60))
    echo -e "${GREEN}Total installation time: ${HOURS}h ${MINUTES}m ${SECONDS}s${NC}"
}

# Run the script
if [ "$(whoami)" = "root" ]; then
    # If running as root, re-execute as the target user with sudo
    exec sudo -u "$REAL_USER" -E "$0" "$@"
else
    main
fi 