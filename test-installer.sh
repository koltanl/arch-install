#!/bin/bash
set -euo pipefail

# First define basic variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="arch-install-test"
ISO_PATH="$SCRIPT_DIR/isoout/archlinux-*.iso"
VM_DISK_PATH="$HOME/.local/share/libvirt/images/$VM_NAME.qcow2"
VM_DISK_SIZE="40"
PRESEED_CONF="$SCRIPT_DIR/install/preseed.conf"
VM_STATE_DIR="$SCRIPT_DIR/vm_states"
DEBUG=0
DEPLOYMENT_SCRIPT="install/deploymentArch.sh"
REMOTE_DEPLOYMENT_PATH="/root/deploymentArch.sh"
SSH_TIMEOUT=300  # 5 minutes timeout for SSH connection attempts
VM_IP="192.168.111.111"
VM_NETWORK_NAME="arch-test-net"
VM_NETWORK_ADDR="192.168.111.0/24"

# Source credentials from preseed.conf
if [ -f "$PRESEED_CONF" ]; then
    # Use grep and cut to extract values, with error checking
    ROOT_PASSWORD=$(grep "^ROOT_PASSWORD=" "$PRESEED_CONF" | cut -d'"' -f2)
    USERNAME=$(grep "^USERNAME=" "$PRESEED_CONF" | cut -d'"' -f2)
    
    if [ -z "$ROOT_PASSWORD" ]; then
        echo "Error: Could not extract ROOT_PASSWORD from preseed.conf"
        exit 1
    fi
    if [ -z "$USERNAME" ]; then
        echo "Error: Could not extract USERNAME from preseed.conf"
        exit 1
    fi
else
    echo "Error: preseed.conf not found at $PRESEED_CONF"
    exit 1
fi

# Now define variables that depend on preseed values
SSH_USER="$USERNAME"
SSH_PASS="$ROOT_PASSWORD"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --no-build, -n       Skip ISO build, use existing ISO"
    echo "  --fresh, -f          Start fresh VM from ISO (default behavior)"
    echo "  --debug, -d          Enable debug output for build and installation"
    echo "  --update-deploy, -u  Update and run deployment script on VM"
    echo "  --save, -s           Save current VM state"
    echo "  --restore, -r        Restore VM from saved state"
    echo "  --help, -h           Show this help message"
    exit 1
}

# Function for cleanup
cleanup() {
    echo "Cleaning up any failed states..."
    
    # Add cleanup of VM state files first
    echo "Cleaning up VM state files..."
    sudo rm -rf "$VM_STATE_DIR"/*
    
    # Clean up temp build directories
    echo "Cleaning up build directories..."
    sudo rm -rf /tmp/archiso-custom
    sudo rm -rf /tmp/archiso-tmp
    
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

# Define save and restore functions
save_vm_state() {
    local state_dir="$1"
    echo "Saving VM state to $state_dir..."
    
    # Ensure VM is shut down
    sudo virsh --connect qemu:///system destroy "$VM_NAME" 2>/dev/null || true
    
    # Create state directory with proper permissions
    sudo mkdir -p "$state_dir"
    sudo chown "$USER:$USER" "$state_dir"
    
    # Copy disk image with sudo
    if [ -f "$VM_DISK_PATH" ]; then
        echo "Copying disk image..."
        sudo cp "$VM_DISK_PATH" "$state_dir/disk.qcow2"
        sudo chown "$USER:$USER" "$state_dir/disk.qcow2"
    else
        echo "Error: VM disk image not found"
        return 1
    fi
    
    # Export VM configuration
    echo "Saving VM configuration..."
    sudo virsh --connect qemu:///system dumpxml "$VM_NAME" > "$state_dir/config.xml"
    
    echo "VM state saved successfully"
    return 0
}

restore_vm_state() {
    local state_dir="$1"
    
    if [ ! -d "$state_dir" ]; then
        echo "Error: No saved state found in $state_dir"
        return 1
    fi
    
    echo "Restoring VM state from $state_dir..."
    
    # Clean up existing VM
    cleanup
    
    # Restore disk image
    echo "Restoring disk image..."
    cp "$state_dir/disk.qcow2" "$VM_DISK_PATH"
    
    # Restore VM configuration
    echo "Restoring VM configuration..."
    sudo virsh --connect qemu:///system define "$state_dir/config.xml"
    
    echo "VM state restored successfully"
    return 0
}

# Parse command line arguments
REBUILD_ISO=true
UPDATE_DEPLOY=false
SAVE_STATE=false
RESTORE=false
FRESH_START=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-build|-n)
            REBUILD_ISO=false
            shift
            ;;
        --fresh|-f)
            FRESH_START=true
            shift
            ;;
        --debug|-d)
            DEBUG=1
            shift
            ;;
        --update-deploy|-u)
            UPDATE_DEPLOY=true
            shift
            ;;
        --save|-s)
            SAVE_STATE=true
            shift
            ;;
        --restore|-r)
            RESTORE=true
            REBUILD_ISO=false
            shift
            ;;
        --help|-h)
            show_usage
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Add this near the start of the main execution flow
if [ "$FRESH_START" = true ]; then
    echo "Starting fresh VM from ISO..."
    # The rest of the script will continue with normal VM creation
    # No need for additional code since this is the default behavior
elif [ "$SAVE_STATE" = true ]; then
    save_vm_state "$VM_STATE_DIR"
    exit 0
elif [ "$RESTORE" = true ]; then
    # Try both state directories, preferring no_iso state if it exists
    if [ -d "$VM_STATE_DIR" ]; then
        restore_vm_state "$VM_STATE_DIR"
    else
        echo "Error: No saved VM state found"
        exit 1
    fi
    sudo virsh --connect qemu:///system start "$VM_NAME"
    exit 0
fi

# Add these functions before the main execution flow
wait_for_ssh() {
    local retries=30
    local wait_time=10
    
    echo "Waiting for SSH to become available..."
    for ((i=1; i<=retries; i++)); do
        if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${SSH_USER}@${VM_IP}" "exit" >/dev/null 2>&1; then
            echo "SSH connection established!"
            return 0
        fi
        echo "Attempt $i/$retries - SSH not ready, waiting ${wait_time}s..."
        sleep $wait_time
    done
    
    echo "Failed to establish SSH connection after $retries attempts"
    return 1
}

update_deployment_script() {
    echo "Updating deployment script on VM..."
    if ! sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no "$DEPLOYMENT_SCRIPT" "${SSH_USER}@${VM_IP}:${REMOTE_DEPLOYMENT_PATH}"; then
        echo "Failed to copy deployment script to VM"
        return 1
    fi
    
    echo "Running updated deployment script..."
    if ! sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "${SSH_USER}@${VM_IP}" "chmod +x ${REMOTE_DEPLOYMENT_PATH} && ${REMOTE_DEPLOYMENT_PATH}"; then
        echo "Failed to execute deployment script on VM"
        return 1
    fi
    
    echo "Deployment script update completed successfully"
    return 0
}

# Add this near the end of the script, after the VM is created and booted
if [ "$UPDATE_DEPLOY" = true ]; then
    if wait_for_ssh; then
        update_deployment_script
    else
        echo "Failed to establish SSH connection to update deployment script"
        exit 1
    fi
fi

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
    if ! DEBUG=$DEBUG ./build-iso.sh; then
        handle_error "ISO build failed - check build-iso.sh output for details"
    fi
    
    # Double check ISO exists and is valid
    ACTUAL_ISO=$(ls -t $ISO_PATH 2>/dev/null | head -n1)
    if [ ! -f "$ACTUAL_ISO" ] || [ ! -s "$ACTUAL_ISO" ]; then
        handle_error "No valid ISO found after build"
    fi
    
    echo "Successfully built ISO: $ACTUAL_ISO"
else
    echo "Using existing ISO..."
fi

# Add ISO validation before VM creation
ACTUAL_ISO=$(ls -t $ISO_PATH 2>/dev/null | head -n1)
if [ ! -f "$ACTUAL_ISO" ] || [ ! -s "$ACTUAL_ISO" ]; then
    handle_error "No valid ISO found at $ISO_PATH"
fi

# Add size check
ISO_SIZE=$(stat -c%s "$ACTUAL_ISO")
MIN_SIZE=$((700*1024*1024))  # 700MB minimum
if [ "$ISO_SIZE" -lt "$MIN_SIZE" ]; then
    handle_error "ISO file appears incomplete (size: $ISO_SIZE bytes)"
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

wait_for_vm_creation() {
    local retries=30
    local wait_time=5
    
    echo "Waiting for VM to be created..."
    for ((i=1; i<=retries; i++)); do
        if virsh --connect qemu:///system list | grep -q "$VM_NAME"; then
            echo "VM creation confirmed!"
            return 0
        fi
        echo "Attempt $i/$retries - VM not ready, waiting ${wait_time}s..."
        sleep $wait_time
    done
    
    echo "Failed to confirm VM creation after $retries attempts"
    return 1
}

# Add this after the virt-install command:
if ! wait_for_vm_creation; then
    handle_error "Failed to confirm VM creation"
fi

