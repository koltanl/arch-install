#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="arch-install-test"
ISO_PATH="$SCRIPT_DIR/isoout/archlinux-*.iso"
VM_DISK_PATH="$HOME/.local/share/libvirt/images/$VM_NAME.qcow2"
VM_DISK_SIZE="20"
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
    virsh --connect qemu:///session destroy "$VM_NAME" 2>/dev/null || true
    virsh --connect qemu:///session undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
    virsh --connect qemu:///session net-destroy "$VM_NETWORK_NAME" 2>/dev/null || true
    virsh --connect qemu:///session net-undefine "$VM_NETWORK_NAME" 2>/dev/null || true
}
trap cleanup ERR

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

# Remove existing VM if it exists
virsh --connect qemu:///session destroy "$VM_NAME" 2>/dev/null || true
virsh --connect qemu:///session undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true

echo "Creating new VM..."
setup_network() {
    # Remove existing network if it exists
    virsh --connect qemu:///session net-destroy "$VM_NETWORK_NAME" 2>/dev/null || true
    virsh --connect qemu:///session net-undefine "$VM_NETWORK_NAME" 2>/dev/null || true

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
    virsh --connect qemu:///session net-define /tmp/network.xml || handle_error "Failed to define network"
    virsh --connect qemu:///session net-start "$VM_NETWORK_NAME" || handle_error "Failed to start network"
    rm /tmp/network.xml
}

echo "Setting up VM network..."
setup_network

# Modify the virt-install command to use the custom network and MAC address
virt-install \
    --connect qemu:///session \
    --name "$VM_NAME" \
    --memory 4096 \
    --vcpus 2 \
    --disk path="$VM_DISK_PATH",size="$VM_DISK_SIZE",format=qcow2 \
    --os-variant archlinux \
    --cdrom "$ACTUAL_ISO" \
    --boot uefi \
    --network network=$VM_NETWORK_NAME,mac=52:54:00:11:11:11 \
    --graphics spice \
    --noautoconsole \
    --features smm=on \
    --machine q35 || handle_error "Failed to create VM"

echo "
-------------------------------------------------------------------------------
VM '$VM_NAME' has been created and is booting from the test ISO.

To connect to the VM console:
    virt-viewer --connect qemu:///session $VM_NAME

To destroy the test VM:
    virsh --connect qemu:///session destroy $VM_NAME
    virsh --connect qemu:///session undefine $VM_NAME --remove-all-storage

The VM is configured with:
- 4GB RAM
- 2 CPU cores
- 20GB disk
- UEFI boot
- SPICE display
-------------------------------------------------------------------------------
"

# Optional: Wait for VM to get an IP address
echo "Waiting for VM to obtain IP address..."
for i in {1..30}; do
    IP=$(virsh --connect qemu:///session domifaddr "$VM_NAME" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" || true)
    if [ ! -z "$IP" ]; then
        echo "VM IP address: $IP"
        
        # Wait for SSH connection
        if wait_for_ssh "$IP" "$ROOT_PASSWORD" "$SSH_TIMEOUT"; then
            echo "VM is ready for testing!"
            echo "You can connect to the VM using:"
            echo "    sshpass -p '$ROOT_PASSWORD' ssh root@$IP"
            echo "Or view the console with:"
            echo "    virt-viewer --connect qemu:///session $VM_NAME"
        fi
        break
    fi
    echo -n "."
    sleep 2
done

if [ -z "$IP" ]; then
    handle_error "Could not determine VM IP address after 60 seconds"
fi 