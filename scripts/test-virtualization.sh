#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Error counter
ERRORS=0

# Function to check and print test results
check_test() {
    local test_name="$1"
    local test_result="$2"
    local error_msg="$3"
    
    echo -n "Testing $test_name... "
    if [ "$test_result" -eq 0 ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL${NC}"
        echo -e "${YELLOW}$error_msg${NC}"
        ERRORS=$((ERRORS + 1))
    fi
}

# Test KVM kernel modules
test_kvm_modules() {
    echo -e "\n${YELLOW}Testing KVM kernel modules:${NC}"
    
    # Check if KVM modules are loaded
    lsmod | grep -q "kvm" 
    check_test "KVM module" $? "KVM module not loaded"
    
    # Check CPU-specific module (Intel or AMD)
    if grep -q "Intel" /proc/cpuinfo; then
        lsmod | grep -q "kvm_intel"
        check_test "KVM Intel module" $? "KVM Intel module not loaded"
    elif grep -q "AMD" /proc/cpuinfo; then
        lsmod | grep -q "kvm_amd"
        check_test "KVM AMD module" $? "KVM AMD module not loaded"
    fi
}

# Test libvirt service
test_libvirt() {
    echo -e "\n${YELLOW}Testing libvirt service:${NC}"
    
    # Check if libvirtd is running
    systemctl is-active --quiet libvirtd
    check_test "libvirtd service" $? "libvirtd service not running"
    
    # Check if current user is in libvirt group
    groups | grep -q "libvirt"
    check_test "User groups" $? "Current user not in libvirt group"
}

# Test QEMU/virsh functionality
test_qemu() {
    echo -e "\n${YELLOW}Testing QEMU/virsh functionality:${NC}"
    
    # Check if virsh command exists
    command -v virsh >/dev/null 2>&1
    check_test "virsh command" $? "virsh command not found"
    
    # Check if we can connect to libvirt
    virsh connect qemu:///system >/dev/null 2>&1
    check_test "libvirt connection" $? "Cannot connect to libvirt"
    
    # Check default network
    virsh net-list --all | grep -q "default"
    check_test "Default network" $? "Default network not configured"
}

# Test storage pool
test_storage() {
    echo -e "\n${YELLOW}Testing storage configuration:${NC}"
    
    # Check if default storage pool exists
    virsh pool-list --all | grep -q "default"
    check_test "Default storage pool" $? "Default storage pool not found"
    
    # Check if storage pool is active
    virsh pool-list | grep -q "default"
    check_test "Storage pool active" $? "Default storage pool not active"
    
    # Check if storage directory exists
    [ -d "/var/lib/libvirt/images" ]
    check_test "Storage directory" $? "Storage directory not found"
}

# Test hardware virtualization support
test_hardware() {
    echo -e "\n${YELLOW}Testing hardware virtualization support:${NC}"
    
    # Check if CPU supports virtualization
    grep -q -E 'svm|vmx' /proc/cpuinfo
    check_test "CPU virtualization support" $? "CPU virtualization not supported or disabled in BIOS"
    
    # Check if nested virtualization is enabled
    if grep -q "AMD" /proc/cpuinfo; then
        cat /sys/module/kvm_amd/parameters/nested | grep -q "1"
        check_test "Nested virtualization (AMD)" $? "Nested virtualization not enabled for AMD"
    elif grep -q "Intel" /proc/cpuinfo; then
        cat /sys/module/kvm_intel/parameters/nested | grep -q "1"
        check_test "Nested virtualization (Intel)" $? "Nested virtualization not enabled for Intel"
    fi
}

# Main function
main() {
    # Check if running as root
    if [ "$(id -u)" = 0 ]; then
        echo -e "${RED}This script should not be run as root${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Starting virtualization tests...${NC}"
    
    test_hardware
    test_kvm_modules
    test_libvirt
    test_qemu
    test_storage
    
    echo -e "\n${YELLOW}Test Summary:${NC}"
    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}All tests passed successfully!${NC}"
        echo -e "Your system is properly configured for virtualization."
    else
        echo -e "${RED}$ERRORS test(s) failed.${NC}"
        echo -e "Please check the errors above and fix any issues."
        echo -e "You may need to run setup-virtualization.sh again."
    fi
}

# Run the script
main 