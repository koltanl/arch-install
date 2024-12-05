#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create a test user and environment
setup_test_env() {
    local test_user="test_deployment"
    local test_home="/home/$test_user"

    echo -e "${YELLOW}Setting up test environment...${NC}"
    
    # Create test user if doesn't exist
    if ! id "$test_user" &>/dev/null; then
        sudo useradd -m -s /bin/bash "$test_user"
        echo -e "${GREEN}Created test user: $test_user${NC}"
    fi

    # Create temporary working directory
    local temp_dir=$(mktemp -d)
    echo -e "${YELLOW}Created temporary directory: $temp_dir${NC}"

    # Copy deployment files to temp directory
    cp -r ../* "$temp_dir/"
    
    # Give ownership to test user
    sudo chown -R "$test_user:$test_user" "$temp_dir"

    echo "$temp_dir"
}

# Clean up test environment
cleanup_test_env() {
    local test_user="test_deployment"
    local temp_dir="$1"

    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    
    # Remove temporary directory
    sudo rm -rf "$temp_dir"

    # Optionally remove test user (commented out for safety)
    # sudo userdel -r "$test_user"

    echo -e "${GREEN}Cleanup complete${NC}"
}

# Main test function
run_test() {
    local temp_dir=$(setup_test_env)
    
    echo -e "${YELLOW}Running deployment script in test environment...${NC}"
    
    # Modify the original script to run in test mode
    sed -i 's/sudo chsh -s \/usr\/bin\/zsh "$USER"/echo "Would change shell to zsh"/' "$temp_dir/install/deploymentArch.sh"
    
    # Run the script as test user
    sudo -u test_deployment bash -c "cd $temp_dir/install && TEST_MODE=true bash deploymentArch.sh"
    
    local exit_status=$?
    
    if [ $exit_status -eq 0 ]; then
        echo -e "${GREEN}Test completed successfully${NC}"
    else
        echo -e "${RED}Test failed with exit status $exit_status${NC}"
    fi

    # Ask if user wants to inspect the results
    read -p "Would you like to inspect the test results before cleanup? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Test environment is at: $temp_dir${NC}"
        echo "Press any key to cleanup when done..."
        read -n 1
    fi

    cleanup_test_env "$temp_dir"
}

# Run the test
run_test 