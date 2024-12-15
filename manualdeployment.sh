#!/bin/bash

# Get absolute path to script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Progress bar function
progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    printf "\rProgress: [%${completed}s%${remaining}s] %d%%" | tr ' ' '=' | tr ' ' ' '
    printf "%s\n" ""
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies
check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"
    
    local missing_deps=()
    local base_deps=(
        "base-devel"
        "git"
        "go"
        "unzip"
        "wget"
        "sudo"
    )

    # Check if pacman is available (verify we're on Arch)
    if ! command_exists pacman; then
        handle_error "This script requires pacman package manager. Are you running Arch Linux?"
        exit 1
    fi

    # Check for required commands
    for dep in "${base_deps[@]}"; do
        if ! pacman -Qi "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    # If there are missing dependencies, install them
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}Installing missing dependencies: ${missing_deps[*]}${NC}"
        if ! sudo pacman -S --needed --noconfirm "${missing_deps[@]}"; then
            handle_error "Failed to install dependencies"
            exit 1
        fi
    fi

    # Verify jq is installed (needed for package list parsing)
    if ! command_exists jq; then
        echo -e "${YELLOW}Installing jq for JSON parsing...${NC}"
        if ! sudo pacman -S --needed --noconfirm jq; then
            handle_error "Failed to install jq"
            exit 1
        fi
    fi

    echo -e "${GREEN}All dependencies are satisfied${NC}"
    return 0
}

install_yay() {
    echo -e "${YELLOW}Installing yay...${NC}"
    
    if command_exists yay; then
        echo -e "${GREEN}yay is already installed${NC}"
        return 0
    fi

    # Create temporary build directory
    local build_dir="/tmp/yay-build"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    cd "$build_dir" || {
        handle_error "Failed to create temporary directory for yay build"
        return 1
    }

    # Clone yay repository
    if ! git clone https://aur.archlinux.org/yay.git .; then
        handle_error "Failed to clone yay repository"
        return 1
    fi

    # Build and install yay
    if ! makepkg -si --noconfirm; then
        handle_error "Failed to build yay"
        return 1
    fi

    # Verify installation
    if ! command_exists yay; then
        handle_error "Yay installation verification failed"
        return 1
    fi

    # Clean up build directory
    cd "$SCRIPT_DIR"
    rm -rf "$build_dir"

    echo -e "${GREEN}yay installed successfully${NC}"
    return 0
}

install_packages() {
    echo -e "${YELLOW}Installing packages from pkglist.json...${NC}"
    
    local pkglist_path="$SCRIPT_DIR/install/pkglist.json"
    
    if [ ! -f "$pkglist_path" ]; then
        handle_error "pkglist.json not found at $pkglist_path"
        return 1
    fi

    # Enable multilib repository if not already enabled
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        echo -e "${YELLOW}Enabling multilib repository...${NC}"
        sudo bash -c 'echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'
        sudo pacman -Sy
    fi

    # Read and parse JSON file
    local json_content
    json_content=$(cat "$pkglist_path")
    
    # Validate JSON content
    if ! echo "$json_content" | jq empty 2>/dev/null; then
        handle_error "Invalid JSON in pkglist.json"
        return 1
    fi
    
    # First pass: Install interactive packages
    echo -e "${YELLOW}Installing packages that require interaction...${NC}"
    if ! interactive_packages=$(echo "$json_content" | jq -r '.interactive_packages[]' 2>/dev/null); then
        handle_error "Failed to parse interactive_packages from JSON"
    else
        while IFS= read -r package; do
            [ -z "$package" ] && continue
            echo -e "${YELLOW}Installing interactive package: $package${NC}"
            if [ "$package" = "plasma" ]; then
                echo "1" | sudo pacman -S --needed --noconfirm plasma || true
            fi
        done <<< "$interactive_packages"
    fi
    
    # Second pass: Install regular pacman packages
    echo -e "${YELLOW}Installing packages from official repositories...${NC}"
    if ! pacman_packages=$(echo "$json_content" | jq -r '.pacman_packages[]' 2>/dev/null); then
        handle_error "Failed to parse pacman_packages from JSON"
    else
        # Convert newline-separated list to array
        local packages=()
        while IFS= read -r package; do
            [ -z "$package" ] && continue
            packages+=("$package")
        done <<< "$pacman_packages"
        
        if [ ${#packages[@]} -gt 0 ]; then
            # Process packages in batches of 32
            local batch_size=32
            local total_packages=${#packages[@]}
            local batch_count=$(( (total_packages + batch_size - 1) / batch_size ))
            
            for ((i = 0; i < batch_count; i++)); do
                local start=$((i * batch_size))
                local end=$((start + batch_size))
                [ $end -gt $total_packages ] && end=$total_packages
                
                local current_batch=("${packages[@]:start:batch_size}")
                
                echo -e "${YELLOW}Installing batch $((i+1))/$batch_count (packages $((start+1))-$end of $total_packages)${NC}"
                if ! sudo pacman -S --needed --noconfirm "${current_batch[@]}"; then
                    echo -e "${RED}Warning: Some packages in batch $((i+1)) failed to install${NC}"
                fi
                
                sleep 1
            done
        fi
    fi
    
    # Third pass: Install AUR packages
    echo -e "${YELLOW}Installing AUR packages...${NC}"
    if ! aur_packages=$(echo "$json_content" | jq -r '.aur_packages[]' 2>/dev/null); then
        handle_error "Failed to parse aur_packages from JSON"
    else
        while IFS= read -r package; do
            [ -z "$package" ] && continue
            echo -e "${YELLOW}Installing AUR package: $package${NC}"
            if ! yay -S --needed --noconfirm "$package"; then
                echo -e "${RED}Warning: Failed to install AUR package: $package${NC}"
            fi
        done <<< "$aur_packages"
    fi
    
    echo -e "${GREEN}Package installation completed${NC}"
    return 0
}

setup_dotfiles() {
    echo -e "${YELLOW}Setting up dotfiles...${NC}"
    
    # Create required directories
    local user_dirs=(
        "$HOME/.config"
        "$HOME/.local/share"
        "$HOME/bin"
    )

    for dir in "${user_dirs[@]}"; do
        mkdir -p "$dir" || {
            handle_error "Failed to create directory: $dir"
            return 1
        }
    done

    # Check for dotfiles directory
    local dotfiles_dir="$SCRIPT_DIR/dotfiles"
    if [ ! -d "$dotfiles_dir" ]; then
        handle_error "Dotfiles directory not found at $dotfiles_dir"
        return 1
    fi

    # Copy dotfiles
    echo "Copying dotfiles from $dotfiles_dir"
    find "$dotfiles_dir" -maxdepth 1 -type f \( -name ".*" -o -name "*" \) | while read -r file; do
        local basename=$(basename "$file")
        # Skip . and .. and omp.json
        if [[ "$basename" != "." && "$basename" != ".." && "$basename" != "omp.json" ]]; then
            echo "Copying $basename to $HOME/"
            cp "$file" "$HOME/$basename" || {
                echo -e "${RED}Warning: Failed to copy $basename${NC}"
                continue
            }
        fi
    done

    # Setup oh-my-posh config
    local omp_config="$dotfiles_dir/omp.json"
    if [ -f "$omp_config" ]; then
        echo "Setting up oh-my-posh configuration"
        mkdir -p "$HOME/.config"
        cp "$omp_config" "$HOME/.config/omp.json" || {
            echo -e "${RED}Warning: Failed to copy oh-my-posh configuration${NC}"
        }
    fi

    # Fix permissions
    chown -R "$USER:$USER" "$HOME/.config" "$HOME/.local" "$HOME/bin" 2>/dev/null || true

    echo -e "${GREEN}Dotfiles setup completed${NC}"
    return 0
}

setup_kde() {
    echo -e "${YELLOW}Setting up KDE configuration...${NC}"
    
    # Create KDE config directories
    local kde_dirs=(
        "$HOME/.config/kdedefaults"
        "$HOME/.config/plasma"
    )

    for dir in "${kde_dirs[@]}"; do
        mkdir -p "$dir" || {
            handle_error "Failed to create directory: $dir"
            return 1
        }
    done

    # Check for KDE config directory
    local kde_dir="$SCRIPT_DIR/kde"
    if [ ! -d "$kde_dir" ]; then
        handle_error "KDE configuration directory not found at $kde_dir"
        return 1
    fi

    # Copy KDE configurations
    echo "Setting up KDE configurations from $kde_dir"

    # Copy kdedefaults
    if [ -d "$kde_dir/kdedefaults" ]; then
        echo "Copying KDE defaults..."
        cp -r "$kde_dir/kdedefaults/"* "$HOME/.config/kdedefaults/" 2>/dev/null || {
            echo -e "${RED}Warning: Failed to copy KDE defaults${NC}"
        }
    fi

    # Copy KWin configurations
    if [ -d "$kde_dir/kwin" ]; then
        echo "Copying KWin configurations..."
        cp "$kde_dir/kwin/"* "$HOME/.config/" 2>/dev/null || {
            echo -e "${RED}Warning: Failed to copy KWin configurations${NC}"
        }
    fi

    # Copy shortcuts
    if [ -d "$kde_dir/shortcuts" ]; then
        echo "Copying shortcuts..."
        cp "$kde_dir/shortcuts/"* "$HOME/.config/" 2>/dev/null || {
            echo -e "${RED}Warning: Failed to copy shortcuts${NC}"
        }
    fi

    # Copy Plasma configurations
    if [ -d "$kde_dir/plasma" ]; then
        echo "Copying Plasma configurations..."
        cp -r "$kde_dir/plasma/"* "$HOME/.config/" 2>/dev/null || {
            echo -e "${RED}Warning: Failed to copy Plasma configurations${NC}"
        }
    fi

    # Copy theme configurations
    if [ -f "$kde_dir/kdeglobals" ]; then
        echo "Copying kdeglobals..."
        cp "$kde_dir/kdeglobals" "$HOME/.config/" || {
            echo -e "${RED}Warning: Failed to copy kdeglobals${NC}"
        }
    fi

    # Fix permissions
    chown -R "$USER:$USER" "$HOME/.config" 2>/dev/null || true

    echo -e "${GREEN}KDE configuration completed${NC}"
    return 0
}

setup_kitty() {
    echo -e "${YELLOW}Setting up kitty terminal...${NC}"
    
    # Create kitty config directory
    local kitty_config_dir="$HOME/.config/kitty"
    mkdir -p "$kitty_config_dir" || {
        handle_error "Failed to create kitty config directory"
        return 1
    }

    # Check for kitty configs directory
    local kitty_dir="$SCRIPT_DIR/kitty"
    if [ ! -d "$kitty_dir" ]; then
        handle_error "Kitty configuration directory not found at $kitty_dir"
        return 1
    fi

    # Copy main configuration files
    echo "Copying kitty configuration files..."
    for config_file in kitty.conf theme.conf; do
        if [ -f "$kitty_dir/$config_file" ]; then
            cp "$kitty_dir/$config_file" "$kitty_config_dir/" || {
                echo -e "${RED}Warning: Failed to copy $config_file${NC}"
            }
        fi
    done

    # Copy terminal images if they exist
    for img in terminal.png 0terminal.png 1terminal.png; do
        if [ -f "$kitty_dir/$img" ]; then
            cp "$kitty_dir/$img" "$kitty_config_dir/" || {
                echo -e "${RED}Warning: Failed to copy $img${NC}"
            }
        fi
    done

    # Copy kitty-themes directory if it exists
    if [ -d "$kitty_dir/kitty-themes" ]; then
        echo "Copying kitty themes..."
        cp -r "$kitty_dir/kitty-themes" "$kitty_config_dir/" || {
            echo -e "${RED}Warning: Failed to copy kitty themes${NC}"
        }
    fi

    # Fix permissions
    chown -R "$USER:$USER" "$kitty_config_dir" 2>/dev/null || true

    echo -e "${GREEN}Kitty terminal configuration completed${NC}"
    return 0
}

install_shell_tools() {
    echo -e "${YELLOW}Installing shell tools...${NC}"
    
    # Install zsh if not present
    if ! command_exists zsh; then
        echo "Installing zsh..."
        if ! sudo pacman -S --needed --noconfirm zsh; then
            handle_error "Failed to install zsh"
            return 1
        fi
    fi

    # Install zplug
    if [ ! -d "$HOME/.zplug" ]; then
        echo "Installing zplug..."
        git clone https://github.com/zplug/zplug "$HOME/.zplug" || {
            handle_error "Failed to install zplug"
            return 1
        }
    fi

    # Install oh-my-posh
    if ! command_exists oh-my-posh; then
        echo "Installing oh-my-posh..."
        mkdir -p "$HOME/bin"
        if ! curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/bin"; then
            handle_error "Failed to install oh-my-posh"
            return 1
        fi
    fi

    # Install atuin
    if ! command_exists atuin; then
        echo "Installing atuin..."
        if ! bash <(curl https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh); then
            echo -e "${RED}Warning: Failed to install atuin${NC}"
        fi
    fi

    # Install nnn with nerd fonts support
    echo "Installing nnn..."
    if ! sudo pacman -S --needed --noconfirm gcc make pkg-config ncurses readline; then
        handle_error "Failed to install nnn dependencies"
        return 1
    fi

    # Build and install nnn
    local build_dir="/tmp/nnn-build"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    cd "$build_dir" || return 1
    
    if ! git clone https://github.com/jarun/nnn.git .; then
        handle_error "Failed to clone nnn repository"
        return 1
    fi

    if ! make O_NERD=1; then
        handle_error "Failed to build nnn"
        return 1
    fi

    if ! sudo make install; then
        handle_error "Failed to install nnn"
        return 1
    fi

    # Setup nnn plugins
    echo "Setting up nnn plugins..."
    local plugins_dir="$HOME/.config/nnn/plugins"
    mkdir -p "$plugins_dir"

    # Clone plugins repository
    if ! git clone --depth 1 https://github.com/jarun/nnn.git "$build_dir/nnn-plugins"; then
        echo -e "${RED}Warning: Failed to clone nnn plugins repository${NC}"
    else
        # Copy plugins to user directory
        cp -r "$build_dir/nnn-plugins/plugins/"* "$plugins_dir/" || {
            echo -e "${RED}Warning: Failed to copy nnn plugins${NC}"
        }
        
        # Make all plugins executable
        chmod +x "$plugins_dir"/* || {
            echo -e "${RED}Warning: Failed to make plugins executable${NC}"
        }
    fi

    cd "$SCRIPT_DIR"
    rm -rf "$build_dir"

    # Change default shell to zsh
    echo "Changing default shell to zsh..."
    if ! sudo chsh -s /bin/zsh "$USER"; then
        echo -e "${RED}Warning: Failed to change shell to zsh${NC}"
    fi

    echo -e "${GREEN}Shell tools installation completed${NC}"
    return 0
}

setup_services() {
    echo -e "${YELLOW}Setting up system services...${NC}"
    
    # List of services to enable
    local services=(
        "NetworkManager"  # Network connectivity
        "bluetooth"       # Bluetooth support
        "cups"           # Printing system
        "avahi-daemon"   # Network discovery
        "fstrim.timer"   # SSD trimming
        "sddm"          # Display manager
    )

    # Enable each service
    for service in "${services[@]}"; do
        echo "Enabling $service..."
        if ! systemctl is-enabled "$service" &>/dev/null; then
            if ! sudo systemctl enable "$service"; then
                echo -e "${RED}Warning: Failed to enable $service${NC}"
            fi
        else
            echo -e "${GREEN}$service is already enabled${NC}"
        fi
    done

    # Start services that should be running immediately
    local immediate_services=(
        "NetworkManager"
        "bluetooth"
        "avahi-daemon"
    )

    for service in "${immediate_services[@]}"; do
        echo "Starting $service..."
        if ! systemctl is-active "$service" &>/dev/null; then
            if ! sudo systemctl start "$service"; then
                echo -e "${RED}Warning: Failed to start $service${NC}"
            fi
        else
            echo -e "${GREEN}$service is already running${NC}"
        fi
    done

    # Secure SSH configuration
    echo -e "${YELLOW}Securing SSH configuration...${NC}"
    local sshd_config="/etc/ssh/sshd_config"
    
    if [ -f "$sshd_config" ]; then
        # Disable password authentication
        sudo sed -i 's/^#\?PasswordAuthentication yes/PasswordAuthentication no/' "$sshd_config"
        # Disable root login
        sudo sed -i 's/^#\?PermitRootLogin yes/PermitRootLogin prohibit-password/' "$sshd_config"
       
        # Restart SSH service if it's running
        if systemctl is-active sshd &>/dev/null; then
            sudo systemctl restart sshd
        fi
    fi

    echo -e "${GREEN}System services setup completed${NC}"
    return 0
}

run_torun_scripts() {
    echo -e "${YELLOW}Running configuration scripts...${NC}"
    
    local torun_dir="$SCRIPT_DIR/torun"
    if [ ! -d "$torun_dir" ]; then
        echo -e "${YELLOW}No torun directory found at $torun_dir${NC}"
        return 0
    fi

    # Store current user info
    local CURRENT_USER="$USER"
    local CURRENT_HOME="$HOME"

    # Find and execute all .sh scripts in torun directory
    while IFS= read -r script; do
        if [ -n "$script" ]; then
            echo -e "${YELLOW}Running $(basename "$script")...${NC}"
            
            # Make script executable
            chmod +x "$script" || {
                echo -e "${RED}Warning: Failed to make script executable: $script${NC}"
                continue
            }
            
            # Run script with sudo bash, preserving original user environment
            if ! sudo -E bash -c "export HOME='$CURRENT_HOME' USER='$CURRENT_USER' LOGNAME='$CURRENT_USER'; bash '$script'"; then
                echo -e "${RED}Warning: Script $(basename "$script") failed but continuing...${NC}"
            fi
        fi
    done < <(find "$torun_dir" -type f -name "*.sh" 2>/dev/null)
    
    # Ensure any files created during script execution are owned by the original user
    if [ -d "$torun_dir" ]; then
        sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$torun_dir" 2>/dev/null || true
    fi
    
    return 0
}

setup_scripts() {
    echo -e "${YELLOW}Setting up utility scripts...${NC}"
    
    # Create bin directory if it doesn't exist
    local bin_dir="$HOME/bin"
    mkdir -p "$bin_dir"
    mkdir -p "$bin_dir/utils"

    # Look for scripts in script directory
    local scripts_dir="$SCRIPT_DIR/scripts"
    if [ ! -d "$scripts_dir" ]; then
        echo -e "${YELLOW}No scripts directory found at $scripts_dir${NC}"
        return 0
    fi

    echo "Copying scripts from $scripts_dir to $bin_dir"

    # Copy root level scripts
    find "$scripts_dir" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) -exec cp {} "$bin_dir/" \;

    # Copy utils subdirectory if it exists
    if [ -d "$scripts_dir/utils" ]; then
        echo "Copying utility scripts..."
        find "$scripts_dir/utils" -type f \( -name "*.sh" -o -name "*.py" \) -exec cp {} "$bin_dir/utils/" \;
    fi

    # Make all scripts executable
    find "$bin_dir" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} \;

    # Fix ownership
    chown -R "$USER:$USER" "$bin_dir"

    echo -e "${GREEN}Scripts setup completed${NC}"
    return 0
}

# Error handling function
handle_error() {
    echo -e "${RED}Error: $1${NC}" >&2
    return 1
}

# Main installation function
main() {
    echo -e "${GREEN}Starting manual deployment...${NC}"
    
    # Total steps for progress bar
    local total_steps=10
    local current_step=0
    
    # Check if running as root
    if [ "$(id -u)" = 0 ]; then
        handle_error "This script should not be run as root"
        exit 1
    fi
    
    # Main installation sequence
    check_dependencies
    progress $((++current_step)) $total_steps
    
    install_yay
    progress $((++current_step)) $total_steps
    
    install_packages
    progress $((++current_step)) $total_steps
    
    setup_dotfiles
    progress $((++current_step)) $total_steps
    
    setup_kde
    progress $((++current_step)) $total_steps
    
    setup_kitty
    progress $((++current_step)) $total_steps
    
    install_shell_tools
    progress $((++current_step)) $total_steps
    
    setup_scripts
    progress $((++current_step)) $total_steps
    
    run_torun_scripts
    progress $((++current_step)) $total_steps
    
    setup_services
    progress $((++current_step)) $total_steps
    
    echo -e "${GREEN}Manual deployment completed!${NC}"
    echo "Please log out and log back in for all changes to take effect."
}

# Script execution
main "$@" 