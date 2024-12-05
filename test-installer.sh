#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="arch-install-test"
ISO_PATH="$SCRIPT_DIR/isoout/archlinux-*.iso"
VM_DISK_PATH="/var/lib/libvirt/images/$VM_NAME.qcow2"
VM_DISK_SIZE="50G"

# Function for cleanup
cleanup() {
    echo "Cleaning up any failed states..."
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
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

# Ensure libvirtd is running
if ! systemctl is-active --quiet libvirtd; then
    echo "Starting libvirtd service..."
    sudo systemctl start libvirtd || handle_error "Failed to start libvirtd"
fi

echo "Building fresh ISO..."
./build-iso.sh || handle_error "ISO build failed"

# Get the actual ISO path (most recent if multiple exist)
ACTUAL_ISO=$(ls -t $ISO_PATH | head -n1)
if [ ! -f "$ACTUAL_ISO" ]; then
    handle_error "ISO file not found at $ACTUAL_ISO"
fi

echo "Setting up fresh VM environment..."

# Remove existing VM if it exists
virsh destroy "$VM_NAME" 2>/dev/null || true
virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true

echo "Creating new VM..."
virt-install \
    --name "$VM_NAME" \
    --memory 4096 \
    --vcpus 2 \
    --disk path="$VM_DISK_PATH",size=50,format=qcow2 \
    --os-variant archlinux \
    --cdrom "$ACTUAL_ISO" \
    --boot uefi \
    --network bridge=virbr0 \
    --graphics spice \
    --noautoconsole || handle_error "Failed to create VM"

echo "
-------------------------------------------------------------------------------
VM '$VM_NAME' has been created and is booting from the test ISO.

To connect to the VM console:
    virt-viewer $VM_NAME

To destroy the test VM:
    virsh destroy $VM_NAME
    virsh undefine $VM_NAME --remove-all-storage

The VM is configured with:
- 4GB RAM
- 2 CPU cores
- 50GB disk
- UEFI boot
- SPICE display
-------------------------------------------------------------------------------
"

# Optional: Wait for VM to get an IP address
echo "Waiting for VM to obtain IP address..."
for i in {1..30}; do
    IP=$(virsh domifaddr "$VM_NAME" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" || true)
    if [ ! -z "$IP" ]; then
        echo "VM IP address: $IP"
        break
    fi
    echo -n "."
    sleep 2
done

if [ -z "$IP" ]; then
    echo "Warning: Could not determine VM IP address after 60 seconds"
fi 