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
REMOTE_DEPLOYMENT_PATH="/root/arch-install/install/deploymentArch.sh"
SSH_TIMEOUT=300  # 5 minutes timeout for SSH connection attempts
VM_IP="${VM_IP:-192.168.111.113}"  # Default IP, can be overridden
VM_NETWORK_NAME="arch-test-net"
VM_NETWORK_ADDR="192.168.111.0/24"
SSH_USER="${SSH_USER:-}"  # Will be set from preseed.conf if not provided
SSH_PASS="${SSH_PASS:-}"  # Will be set from preseed.conf if not provided

# Source credentials from preseed.conf
if [ -f "$PRESEED_CONF" ]; then
    # Use grep and cut to extract values, with error checking
    ROOT_PASSWORD=$(grep "^ROOT_PASSWORD=" "$PRESEED_CONF" | cut -d'"' -f2)
    USERNAME=$(grep "^USERNAME=" "$PRESEED_CONF" | cut -d'"' -f2)
    USER_PASSWORD=$(grep "^USER_PASSWORD=" "$PRESEED_CONF" | cut -d'"' -f2)
    
    if [ -z "$ROOT_PASSWORD" ]; then
        echo "Error: Could not extract ROOT_PASSWORD from preseed.conf"
        exit 1
    fi
    if [ -z "$USERNAME" ]; then
        echo "Error: Could not extract USERNAME from preseed.conf"
        exit 1
    fi
    if [ -z "$USER_PASSWORD" ]; then
        echo "Error: Could not extract USER_PASSWORD from preseed.conf"
        exit 1
    fi
else
    echo "Error: preseed.conf not found at $PRESEED_CONF"
    exit 1
fi

# Now define variables that depend on preseed values
SSH_USER="$USERNAME"
SSH_PASS="$USER_PASSWORD"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --no-build, -n       Skip ISO build, use existing ISO"
    echo "  --fresh, -f          Start fresh VM from ISO (default behavior)"
    echo "  --debug, -d          Enable debug output for build and installation"
    echo "  --update-deploy, -u  Update and run deployment script on VM"
    echo "  --save|-s            Save current VM state"
    echo "  --restore|-r         Restore VM from saved state"
    echo "  --help|-h           Show this help message"
    exit 1
}
setup_network() {
    echo "Setting up VM network..."
    
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

    # Define and start the network
    sudo virsh --connect qemu:///system net-define /tmp/network.xml || {
        echo "Error: Failed to define network"
        rm -f /tmp/network.xml
        return 1
    }
    
    sudo virsh --connect qemu:///system net-start "$VM_NETWORK_NAME" || {
        echo "Error: Failed to start network"
        rm -f /tmp/network.xml
        return 1
    }
    
    rm -f /tmp/network.xml
    return 0
}
# Function to wait for VM creation
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
    local state_name="saved-state"
    echo "Saving VM state..."
    
    # Check if VM exists
    if ! virsh --connect qemu:///system list --all | grep -q "$VM_NAME"; then
        echo "Error: VM $VM_NAME does not exist"
        return 1
    fi
    
    # Stop the VM if it's running
    if virsh --connect qemu:///system domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
        echo "Stopping VM for snapshot..."
        virsh --connect qemu:///system destroy "$VM_NAME"
    fi
    
    # Get the disk path
    local disk_path=$(virsh --connect qemu:///system domblklist "$VM_NAME" | grep vda | awk '{print $2}')
    
    # Create backup of current disk
    local backup_path="${disk_path}.${state_name}"
    echo "Creating disk backup at ${backup_path}..."
    
    # Remove old backup if it exists
    sudo rm -f "$backup_path" 2>/dev/null || true
    
    # Create new backup
    if ! sudo cp "$disk_path" "$backup_path"; then
        echo "Error: Failed to create disk backup"
        return 1
    fi
    
    echo "VM state saved successfully to ${backup_path}"
    return 0
}

restore_vm_state() {
    local state_name="saved-state"
    echo "Restoring VM state..."
    
    # Stop VM if running
    if virsh --connect qemu:///system domstate "$VM_NAME" 2>/dev/null | grep -q "running"; then
        echo "Stopping VM for restore..."
        virsh --connect qemu:///system destroy "$VM_NAME"
        sleep 5  # Give more time for cleanup
    fi
    
    # More aggressive SSH cleanup
    echo "Cleaning up SSH known hosts..."
    # Remove all entries for the VM IP
    ssh-keygen -R "$VM_IP" 2>/dev/null || true
    # Also remove entries by hostname
    ssh-keygen -R "$VM_NAME" 2>/dev/null || true
    # Remove entries from known_hosts2 if it exists
    [ -f ~/.ssh/known_hosts2 ] && ssh-keygen -R "$VM_IP" -f ~/.ssh/known_hosts2 2>/dev/null || true
    
    # Clean up network state
    echo "Cleaning up network state..."
    sudo virsh --connect qemu:///system net-destroy "$VM_NETWORK_NAME" 2>/dev/null || true
    sudo virsh --connect qemu:///system net-undefine "$VM_NETWORK_NAME" 2>/dev/null || true
    
    # Recreate network
    echo "Recreating network..."
    setup_network
    
    # Get the disk path
    local disk_path=$(virsh --connect qemu:///system domblklist "$VM_NAME" | grep vda | awk '{print $2}')
    local backup_path="${disk_path}.${state_name}"
    
    if [ ! -f "$backup_path" ]; then
        echo "Error: No saved state found at ${backup_path}"
        return 1
    fi
    
    # Restore from backup
    echo "Restoring disk from backup..."
    if ! sudo cp "$backup_path" "$disk_path"; then
        echo "Error: Failed to restore from backup"
        return 1
    fi
    
    # Start the VM with a longer delay
    echo "Starting VM..."
    virsh --connect qemu:///system start "$VM_NAME"
    sleep 30  # Give VM more time to fully initialize
    
    # Verify network connectivity
    echo "Verifying network connectivity..."
    for i in {1..10}; do
        if ping -c 1 -W 2 "$VM_IP" >/dev/null 2>&1; then
            echo "Network connectivity established!"
            return 0
        fi
        echo "Waiting for network... attempt $i/10"
        sleep 5
    done
    
    echo "Warning: Could not verify network connectivity"
    return 1
}

verify_vm_state() {
    echo "Verifying target state..."
    
    # Check if VM is running
    if ! virsh --connect qemu:///system domstate "$VM_NAME" | grep -q "running"; then
        echo "VM is not running, attempting to start..."
        virsh --connect qemu:///system start "$VM_NAME"
        sleep 20  # Give VM time to boot
    fi
    
    # Verify network
    echo "Checking network connectivity..."
    if ! ping -c 1 -W 2 "$VM_IP" >/dev/null 2>&1; then
        echo "Network appears down, recreating..."
        setup_network
        sleep 10
    fi
    
    # Try to get VM IP
    local actual_ip=$(virsh --connect qemu:///system net-dhcp-leases "$VM_NETWORK_NAME" | grep "$VM_NAME" | awk '{print $5}' | cut -d'/' -f1)
    if [ -n "$actual_ip" ] && [ "$actual_ip" != "$VM_IP" ]; then
        echo "Warning: VM has IP $actual_ip but we're trying to connect to $VM_IP"
    fi
    
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
        --ip=*)
            VM_IP="${1#*=}"
            shift
            ;;
        --username=*)
            SSH_USER="${1#*=}"
            shift
            ;;
        --password=*)
            SSH_PASS="${1#*=}"
            shift
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
    echo "Updating deployment script on target..."
    
    # Verify VM state first
    verify_vm_state
    
    # First copy to user's home
    if ! sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no "$DEPLOYMENT_SCRIPT" "${SSH_USER}@${VM_IP}:/home/${SSH_USER}/deploymentArch.sh"; then
        echo "Failed to copy deployment script to VM"
        return 1
    fi
    
    echo "Running updated deployment script..."
    # Use heredoc for debugging and proper error handling
    if ! sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "${SSH_USER}@${VM_IP}" /bin/bash << EOF
        
        # Create askpass script
        cat > /home/${SSH_USER}/askpass.sh << 'ASKPASS'
#!/bin/bash
echo "$SSH_PASS"
ASKPASS
        chmod +x /home/${SSH_USER}/askpass.sh
        
        # Create directory and set permissions
        echo "$SSH_PASS" | sudo -S mkdir -p /root/arch-install/install
        echo "$SSH_PASS" | sudo -S chmod 755 /root/arch-install
        echo "$SSH_PASS" | sudo -S chmod 755 /root/arch-install/install
        
        # Copy script and set permissions ensuring both root and user can access
        echo "$SSH_PASS" | sudo -S cp /home/${SSH_USER}/deploymentArch.sh ${REMOTE_DEPLOYMENT_PATH}
        echo "$SSH_PASS" | sudo -S chown root:root ${REMOTE_DEPLOYMENT_PATH}
        echo "$SSH_PASS" | sudo -S chmod 755 ${REMOTE_DEPLOYMENT_PATH}
        
        # Also keep a copy in user's home with proper permissions
        cp /home/${SSH_USER}/deploymentArch.sh /home/${SSH_USER}/deploymentArch.sh.local
        chmod 755 /home/${SSH_USER}/deploymentArch.sh.local
        
        # Debug information
        echo "Script permissions:"
        sudo ls -l ${REMOTE_DEPLOYMENT_PATH}
        ls -l /home/${SSH_USER}/deploymentArch.sh.local
        
        # Execute script with environment variables for sudo password handling
        export SUDO_ASKPASS="/home/${SSH_USER}/askpass.sh"
        export USERNAME="${SSH_USER}"
        export SUDO_PASS="${SSH_PASS}"
        /home/${SSH_USER}/deploymentArch.sh.local
        
        # Clean up askpass script
        rm /home/${SSH_USER}/askpass.sh
EOF
    then
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
    exit 0
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



# Wait for VM creation
if ! wait_for_vm_creation; then
    handle_error "Failed to confirm VM creation"
fi

