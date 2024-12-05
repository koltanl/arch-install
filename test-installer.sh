#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="arch-install-test"
ISO_PATH="$SCRIPT_DIR/isoout/archlinux-*.iso"
VM_DISK_PATH="$HOME/.local/share/libvirt/images/$VM_NAME.qcow2"
VM_DISK_SIZE="40"
ROOT_PASSWORD="2312"  # Default password matching preseedArch.sh
SSH_TIMEOUT=300  # 5 minutes timeout for SSH connection attempts
VM_IP="192.168.111.111"
VM_NETWORK_NAME="arch-test-net"
VM_NETWORK_ADDR="192.168.111.0/24"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --refresh, -r  Redeploy VM using existing ISO without rebuilding"
    echo "  --skip-build   Skip ISO build, use existing ISO"
    echo "  --no-build     Skip ISO build, use existing ISO"
    echo "  --quick        Quick redeploy without rebuilding ISO"
    echo "  --help         Show this help message"
    exit 1
}

# Parse command line arguments
REBUILD_ISO=true
while [[ $# -gt 0 ]]; do
    case $1 in
        --refresh|-r|--skip-build|--no-build|--quick)
            REBUILD_ISO=false
            shift
            ;;
        --help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Function for cleanup
cleanup() {
    echo "Cleaning up any failed states..."
    
    # List of possible VM states to check and clean
    local VM_STATES=("running" "paused" "shut off")
    
    # Check each possible state and handle accordingly
    for state in "${VM_STATES[@]}"; do
        if sudo virsh --connect qemu:///system list --all | grep -q "$VM_NAME.*$state"; then
            echo "Found $VM_NAME in state: $state"
            
            # Handle running or paused states
            if [ "$state" != "shut off" ]; then
                echo "Shutting down VM..."
                sudo virsh --connect qemu:///system shutdown "$VM_NAME" 2>/dev/null || true
                sleep 2
                # Force destroy if shutdown didn't work
                sudo virsh --connect qemu:///system destroy "$VM_NAME" 2>/dev/null || true
            fi
            
            # Undefine the VM with all storage and snapshots
            echo "Undefining VM..."
            sudo virsh --connect qemu:///system undefine "$VM_NAME" --remove-all-storage --snapshots-metadata --nvram 2>/dev/null || true
        fi
    done
    
    # Force cleanup network
    echo "Cleaning up network..."
    sudo virsh --connect qemu:///system net-destroy "$VM_NETWORK_NAME" 2>/dev/null || true
    sudo virsh --connect qemu:///system net-undefine "$VM_NETWORK_NAME" 2>/dev/null || true
    
    # Clean up all possible disk locations
    echo "Cleaning up disk images..."
    local DISK_PATHS=(
        "$VM_DISK_PATH"
        "/var/lib/libvirt/images/${VM_NAME}.qcow2"
        "$HOME/.local/share/libvirt/images/${VM_NAME}.qcow2"
        "/var/lib/libvirt/images/default/${VM_NAME}.qcow2"
    )
    
    for disk in "${DISK_PATHS[@]}"; do
        sudo rm -f "$disk" 2>/dev/null || true
    done
    
    # Clean up lock files and NVRAM files
    echo "Cleaning up lock and NVRAM files..."
    sudo rm -f "/var/lib/libvirt/qemu/domain-${VM_NAME}-*/master-key.aes" 2>/dev/null || true
    sudo rm -f "/var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd" 2>/dev/null || true
    
    # Wait for resources to be released
    sleep 3
    
    echo "Cleanup completed"
}

# Ensure cleanup is called both on error and before creating new VM
trap cleanup ERR

# Add this right before creating the new VM
echo "Ensuring clean environment before VM creation..."
cleanup

# Function to handle errors
handle_error() {
    echo "Error: $1"
    cleanup
    exit 1
}

# Check for required tools
command -v virt-install >/dev/null 2>&1 || handle_error "virt-install is required. Install with: sudo pacman -S virt-install"
command -v virsh >/dev/null 2>&1 || handle_error "virsh is required. Install with: sudo pacman -S libvirt"

# Ensure user is in libvirt group
if ! groups | grep -q libvirt; then
    echo "Adding user to libvirt group..."
    sudo usermod -aG libvirt "$USER"
    echo "Please log out and back in for group changes to take effect"
    exit 1
fi

# Ensure libvirtd is running
if ! systemctl is-active --quiet libvirtd; then
    echo "Starting libvirtd service..."
    sudo systemctl start libvirtd || handle_error "Failed to start libvirtd"
fi

# Create user images directory if it doesn't exist
mkdir -p "$(dirname "$VM_DISK_PATH")"

if [ "$REBUILD_ISO" = true ]; then
    echo "Building fresh ISO..."
    ./build-iso.sh || handle_error "ISO build failed"
else
    echo "Using existing ISO..."
fi

# Get the actual ISO path (most recent if multiple exist)
ACTUAL_ISO=$(ls -t $ISO_PATH | head -n1)
if [ ! -f "$ACTUAL_ISO" ]; then
    handle_error "ISO file not found at $ACTUAL_ISO"
fi

echo "Setting up fresh VM environment..."
cleanup  # Call cleanup before starting to ensure clean slate

# Remove existing VM if it exists
virsh --connect qemu:///system destroy "$VM_NAME" 2>/dev/null || true
virsh --connect qemu:///system undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true

echo "Creating new VM..."
setup_network() {
    echo "Setting up VM network..."
    
    # Check if running as root, if not, use sudo
    if [ "$EUID" -ne 0 ]; then
        echo "Network setup requires root privileges..."
        
        # Remove existing network if it exists
        sudo virsh --connect qemu:///system net-destroy "$VM_NETWORK_NAME" 2>/dev/null || true
        sudo virsh --connect qemu:///system net-undefine "$VM_NETWORK_NAME" 2>/dev/null || true

        # Create network XML
        cat > /tmp/network.xml <<EOF
<network>
  <name>$VM_NETWORK_NAME</name>
  <bridge name='virbr111'/>
  <forward mode='nat'/>
  <ip address='192.168.111.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.111.2' end='192.168.111.254'/>
      <host mac='52:54:00:11:11:11' name='$VM_NAME' ip='$VM_IP'/>
    </dhcp>
  </ip>
</network>
EOF

        # Define and start the network with sudo
        sudo virsh --connect qemu:///system net-define /tmp/network.xml || handle_error "Failed to define network"
        sudo virsh --connect qemu:///system net-start "$VM_NETWORK_NAME" || handle_error "Failed to start network"
        rm /tmp/network.xml
    else
        # Original commands if already root
        virsh --connect qemu:///system net-destroy "$VM_NETWORK_NAME" 2>/dev/null || true
        virsh --connect qemu:///system net-undefine "$VM_NETWORK_NAME" 2>/dev/null || true

        # Create network XML
        cat > /tmp/network.xml <<EOF
<network>
  <name>$VM_NETWORK_NAME</name>
  <bridge name='virbr111'/>
  <forward mode='nat'/>
  <ip address='192.168.111.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.111.2' end='192.168.111.254'/>
      <host mac='52:54:00:11:11:11' name='$VM_NAME' ip='$VM_IP'/>
    </dhcp>
  </ip>
</network>
EOF

        virsh --connect qemu:///system net-define /tmp/network.xml || handle_error "Failed to define network"
        virsh --connect qemu:///system net-start "$VM_NETWORK_NAME" || handle_error "Failed to start network"
        rm /tmp/network.xml
    fi
}

echo "Setting up VM network..."
setup_network

# Update virt-install command
virt-install \
    --connect qemu:///system \
    --name "$VM_NAME" \
    --memory 4096 \
    --vcpus 2 \
    --disk path="$VM_DISK_PATH",size="$VM_DISK_SIZE",format=qcow2 \
    --os-variant archlinux \
    --cdrom "$ACTUAL_ISO" \
    --boot uefi \
    --network bridge=virbr111 \
    --graphics spice \
    --console pty,target_type=virtio \
    --serial pty \
    --machine q35 \
    --check path_in_use=off \
    --noautoconsole || handle_error "Failed to create VM"

echo "
-------------------------------------------------------------------------------
VM '$VM_NAME' has been created and is booting from the test ISO.

The VM is configured with:
- 4GB RAM
- 2 CPU cores
- 20GB disk
- UEFI boot
- SPICE display

Waiting for VM to initialize..."

# Give the VM a moment to start up
sleep 5

# Launch virt-viewer
echo "Launching VM console..."
virt-viewer --connect qemu:///system "$VM_NAME" &

echo "
If the console window doesn't open automatically, you can connect manually with:
    virt-viewer --connect qemu:///system $VM_NAME

To destroy the test VM when done:
    virsh --connect qemu:///system destroy $VM_NAME
    virsh --connect qemu:///system undefine $VM_NAME --remove-all-storage
-------------------------------------------------------------------------------" 