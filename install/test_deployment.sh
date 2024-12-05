#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Error handling
set -o pipefail

# Add this function near the top of the script
verify_file() {
    local file="$1"
    local user="$2"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}File not found: $file${NC}"
        return 1
    fi
    
    if [ ! -r "$file" ]; then
        echo -e "${RED}File not readable: $file${NC}"
        return 1
    fi
    
    if [ -n "$user" ] && [ "$(stat -c '%U' "$file")" != "$user" ]; then
        echo -e "${RED}File not owned by $user: $file${NC}"
        return 1
    fi
    
    return 0
}

# Create a test user and environment
setup_test_env() {
    local test_user="test_deployment"
    local test_home="/home/$test_user"
    local temp_dir
    local repo_root

    echo -e "${YELLOW}Setting up test environment...${NC}"
    
    # Create test user if doesn't exist
    if ! id "$test_user" &>/dev/null; then
        if ! sudo useradd -m -s /bin/bash "$test_user"; then
            echo -e "${RED}Failed to create test user${NC}"
            return 1
        fi
        echo -e "${GREEN}Created test user: $test_user${NC}"
    fi

    # Get the absolute path of the repository root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || {
        echo -e "${RED}Failed to determine repository root${NC}"
        return 1
    }
    echo -e "${YELLOW}Repository root: $repo_root${NC}"

    # Create temporary working directory
    temp_dir=$(mktemp -d) || {
        echo -e "${RED}Failed to create temporary directory${NC}"
        return 1
    }
    echo -e "${YELLOW}Created temporary directory: $temp_dir${NC}"

    # Create directory structure
    mkdir -p "$temp_dir/install" || {
        echo -e "${RED}Failed to create install directory${NC}"
        rm -rf "$temp_dir"
        return 1
    }
    
    echo -e "${YELLOW}Copying files...${NC}"

    # Debug: Check source file existence
    if [ ! -f "$repo_root/install/deploymentArch.sh" ]; then
        echo -e "${RED}Source deploymentArch.sh not found at $repo_root/install/deploymentArch.sh${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    # Copy deployment script with verbose output
    echo -e "${YELLOW}Copying deploymentArch.sh...${NC}"
    cp -v "$repo_root/install/deploymentArch.sh" "$temp_dir/install/" || {
        echo -e "${RED}Failed to copy deploymentArch.sh${NC}"
        rm -rf "$temp_dir"
        return 1
    }

    # Verify the copy
    if [ ! -f "$temp_dir/install/deploymentArch.sh" ]; then
        echo -e "${RED}Verification failed: deploymentArch.sh not found after copy${NC}"
        ls -la "$temp_dir/install/"
        rm -rf "$temp_dir"
        return 1
    fi

    # Copy pkglist.txt if it exists
    if [ -f "$repo_root/install/pkglist.txt" ]; then
        echo -e "${YELLOW}Copying pkglist.txt...${NC}"
        cp -v "$repo_root/install/pkglist.txt" "$temp_dir/install/" || {
            echo -e "${RED}Failed to copy pkglist.txt${NC}"
            rm -rf "$temp_dir"
            return 1
        }
    fi

    # Copy directories we need
    for dir in dotfiles kde kitty scripts torun; do
        if [ -d "$repo_root/$dir" ]; then
            echo -e "${YELLOW}Copying directory: $dir${NC}"
            cp -r "$repo_root/$dir" "$temp_dir/" || {
                echo -e "${RED}Failed to copy $dir directory${NC}"
                rm -rf "$temp_dir"
                return 1
            }
        else
            echo -e "${YELLOW}Warning: Directory $dir not found in repository${NC}"
        fi
    done

    # List contents of temp directory for verification
    echo -e "${YELLOW}Verifying directory structure:${NC}"
    ls -la "$temp_dir"
    echo -e "${YELLOW}Contents of install directory:${NC}"
    ls -la "$temp_dir/install"

    # Verify critical files
    if [ ! -f "$temp_dir/install/deploymentArch.sh" ]; then
        echo -e "${RED}Critical file deploymentArch.sh missing after copy${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    echo -e "${YELLOW}Setting permissions...${NC}"

    # Set proper ownership and permissions
    echo -e "${YELLOW}Setting ownership to $test_user${NC}"
    if ! sudo chown -R "$test_user:$test_user" "$temp_dir"; then
        echo -e "${RED}Failed to set ownership${NC}"
        sudo ls -la "$temp_dir/install"  # Use sudo to list files
        rm -rf "$temp_dir"
        return 1
    fi

    echo -e "${YELLOW}Setting read/write permissions${NC}"
    if ! sudo chmod -R u+rw "$temp_dir"; then
        echo -e "${RED}Failed to set read/write permissions${NC}"
        sudo ls -la "$temp_dir/install"  # Use sudo to list files
        rm -rf "$temp_dir"
        return 1
    fi

    echo -e "${YELLOW}Making scripts executable${NC}"
    if ! sudo chmod +x "$temp_dir/install/deploymentArch.sh"; then
        echo -e "${RED}Failed to make deployment script executable${NC}"
        sudo ls -la "$temp_dir/install"  # Use sudo to list files
        rm -rf "$temp_dir"
        return 1
    fi

    # Verify permissions as root first
    echo -e "${YELLOW}Verifying permissions as root...${NC}"
    sudo ls -la "$temp_dir/install"

    # Verify permissions as test user
    echo -e "${YELLOW}Verifying permissions as test user...${NC}"
    if ! sudo -u "$test_user" test -r "$temp_dir/install/deploymentArch.sh"; then
        echo -e "${RED}Test user cannot read deployment script${NC}"
        sudo ls -la "$temp_dir/install"  # Use sudo to list files
        rm -rf "$temp_dir"
        return 1
    fi

    if ! sudo -u "$test_user" test -x "$temp_dir/install/deploymentArch.sh"; then
        echo -e "${RED}Test user cannot execute deployment script${NC}"
        sudo ls -la "$temp_dir/install"  # Use sudo to list files
        rm -rf "$temp_dir"
        return 1
    fi

    # Create necessary directories with proper permissions
    echo -e "${YELLOW}Creating user directories...${NC}"
    if ! sudo -u "$test_user" mkdir -p "$test_home/.config" "$test_home/bin"; then
        echo -e "${RED}Failed to create user directories${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    # Final verification
    echo -e "${YELLOW}Final verification...${NC}"
    if ! sudo -u "$test_user" bash -c "ls -la '$temp_dir/install'"; then
        echo -e "${RED}Test user cannot list install directory${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    echo -e "${GREEN}Test environment setup complete${NC}"
    echo -e "${YELLOW}Test directory: $temp_dir${NC}"
    
    # Return the temp directory path
    echo "$temp_dir"
    return 0
}

# Clean up test environment
cleanup_test_env() {
    local test_user="test_deployment"
    local temp_dir="$1"

    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    
    if [ -d "$temp_dir" ]; then
        echo -e "${YELLOW}Removing temporary directory: $temp_dir${NC}"
        sudo rm -rf "$temp_dir"
    fi

    # Clean up test user's home directory
    if [ -d "/home/$test_user" ]; then
        echo -e "${YELLOW}Cleaning up test user home directory${NC}"
        sudo rm -rf "/home/$test_user/.config"
        sudo rm -rf "/home/$test_user/bin"
    fi

    echo -e "${GREEN}Cleanup complete${NC}"
}

# Main test function
run_test() {
    local temp_dir
    local setup_output
    
    echo -e "${YELLOW}Starting test deployment...${NC}"
    
    # Setup test environment and capture both stdout and stderr
    setup_output=$(setup_test_env 2>&1)
    temp_dir=$(echo "$setup_output" | tail -n1)
    
    # Show setup output except the last line (which is the temp_dir)
    echo "$setup_output" | sed '$d'
    
    # Check if setup was successful
    if [ $? -ne 0 ] || [ -z "$temp_dir" ] || [ ! -d "$temp_dir" ]; then
        echo -e "${RED}Failed to set up test environment${NC}"
        if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
            cleanup_test_env "$temp_dir"
        fi
        exit 1
    fi
    
    echo -e "${YELLOW}Running deployment script in test environment...${NC}"
    
    # Set up the environment
    export HOME="/home/test_deployment"
    export USER="test_deployment"
    export TEST_MODE=true
    
    # Run the script as test user with environment preservation
    sudo -E -u test_deployment bash -c "
        cd '$temp_dir/install' || exit 1
        if [ ! -f ./deploymentArch.sh ]; then
            echo -e '${RED}Cannot find deploymentArch.sh in working directory${NC}'
            exit 1
        fi
        if [ ! -x ./deploymentArch.sh ]; then
            echo -e '${RED}deploymentArch.sh is not executable${NC}'
            exit 1
        fi
        bash ./deploymentArch.sh
    "
    
    local exit_status=$?
    
    if [ $exit_status -eq 0 ]; then
        echo -e "${GREEN}Test completed successfully${NC}"
    else
        echo -e "${RED}Test failed with exit status $exit_status${NC}"
        # Show the contents of the directory where the script should be
        echo -e "${YELLOW}Contents of install directory:${NC}"
        sudo -u test_deployment ls -la "$temp_dir/install"
    fi

    # Ask if user wants to inspect the results
    read -p "Would you like to inspect the test results before cleanup? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Test environment is at: $temp_dir${NC}"
        echo -e "${YELLOW}Test user home is at: /home/test_deployment${NC}"
        echo -e "${YELLOW}Current contents of test directory:${NC}"
        sudo -u test_deployment ls -la "$temp_dir/install"
        echo "Press any key to cleanup when done..."
        read -n 1
    fi

    cleanup_test_env "$temp_dir"
}

# Run the test
run_test