#!/bin/bash

# Required packages: archiso, sudo

# Set up working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="/tmp/archiso-custom"
out_dir="${SCRIPT_DIR}/isoout"
script_path="/root/custom/install/preseedArch.sh"

# Clean up previous builds
sudo rm -rf ${work_dir}
mkdir -p ${out_dir}

# Copy the baseline archiso profile
cp -r /usr/share/archiso/configs/releng/ ${work_dir}

# Create directory structure in ISO
mkdir -p ${work_dir}/airootfs/root/custom

# Copy the entire repository to the ISO
cp -r "${SCRIPT_DIR}"/* ${work_dir}/airootfs/root/custom/
# Remove any build artifacts or temporary files
rm -rf ${work_dir}/airootfs/root/custom/isoout
rm -rf ${work_dir}/airootfs/root/custom/work

# After copying files but before building ISO, update permissions
# Main installation scripts
chmod 755 ${work_dir}/airootfs/root/custom/install/preseedArch.sh
chmod 755 ${work_dir}/airootfs/root/custom/install/autoArch.sh
chmod 755 ${work_dir}/airootfs/root/custom/install/interactiveArch.sh
chmod 755 ${work_dir}/airootfs/root/custom/install/deploymentArch.sh
chmod 755 ${work_dir}/airootfs/root/custom/build-iso.sh
chmod 755 ${work_dir}/airootfs/root/custom/test-installer.sh

# Ensure root ownership and proper permissions for the entire custom directory
chown -R root:root ${work_dir}/airootfs/root/custom
find ${work_dir}/airootfs/root/custom -type d -exec chmod 755 {} \;
find ${work_dir}/airootfs/root/custom -type f -exec chmod 644 {} \;
find ${work_dir}/airootfs/root/custom -name "*.sh" -exec chmod 755 {} \;

# Near the top of the file, after the variable declarations
DEBUG=${DEBUG:-0}

# Add debug output to .zprofile to check permissions
cat >>${work_dir}/airootfs/root/.zprofile <<EOF
# Auto-start the installation script
(
    exec 1> >(tee -a /tmp/install.log)
    exec 2> >(tee -a /tmp/install.log >&2)
    set -x  # Enable command tracing
    
    echo "[$(date)] Starting debug checks..."
    
    # Check if script exists
    if [ -f ${script_path} ]; then
        echo "[$(date)] Script found. Checking permissions..."
        ls -la ${script_path}
        
        # Try to make it executable again from within the environment
        echo "[$(date)] Attempting to set permissions..."
        chmod +x ${script_path}
        
        # Check shell interpreter
        echo "[$(date)] Checking script interpreter..."
        head -n1 ${script_path}
        
        # Try running with bash explicitly and trace execution
        echo "[$(date)] Attempting to run script with bash..."
        exec /bin/bash -x ${script_path}
    else
        echo "[$(date)] Script not found at ${script_path}"
        echo "[$(date)] Listing /root/custom/install/ directory:"
        ls -la /root/custom/install/
    fi
)
EOF

# Add additional packages
cat >>${work_dir}/packages.x86_64 <<EOF
git
wget
dialog
cryptsetup
gptfdisk
reflector
pciutils
util-linux
mokutil
EOF

# Build the ISO
if ! sudo mkarchiso -v -w ${work_dir} -o ${out_dir} ${work_dir}; then
    echo "Error: ISO build failed"
    sudo rm -rf ${work_dir}
    exit 1
fi

# Verify the ISO was created successfully
if [ ! -f "${out_dir}/archlinux-"*".iso" ]; then
    echo "Error: ISO file not found after build"
    sudo rm -rf ${work_dir}
    exit 1
fi

# Clean up
sudo rm -rf ${work_dir}

echo "ISO has been created in ${out_dir}"
echo "You can write it to a USB drive using:"
echo "sudo dd bs=4M if=${out_dir}/archlinux*.iso of=/dev/sdX status=progress oflag=sync"
