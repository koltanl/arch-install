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
    }

    # Build and install yay
    if ! makepkg -si --noconfirm; then
        handle_error "Failed to build yay"
        return 1
    }

    # Verify installation
    if ! command_exists yay; then
        handle_error "Yay installation verification failed"
        return 1
    }

    # Clean up build directory
    cd "$SCRIPT_DIR"
    rm -rf "$build_dir"

    echo -e "${GREEN}yay installed successfully${NC}"
    return 0
}

install_packages() {
    echo "Installing packages..."
    # TODO: Implement package installation
}

setup_dotfiles() {
    echo "Setting up dotfiles..."
    # TODO: Implement dotfiles setup
}

setup_kde() {
    echo "Setting up KDE configuration..."
    # TODO: Implement KDE setup
}

setup_kitty() {
    echo "Setting up kitty terminal..."
    # TODO: Implement kitty setup
}

install_shell_tools() {
    echo "Installing shell tools..."
    # TODO: Implement shell tools installation
}

setup_services() {
    echo "Setting up system services..."
    # TODO: Implement services setup
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
    local total_steps=8
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
    
    setup_services
    progress $((++current_step)) $total_steps
    
    echo -e "${GREEN}Manual deployment completed!${NC}"
    echo "Please log out and log back in for all changes to take effect."
}

# Script execution
main "$@" 