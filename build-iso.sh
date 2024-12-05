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
# Update the file permissions section
chmod 755 ${work_dir}/airootfs/root/custom/install/preseedArch.sh
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
    # More verbose debugging
    echo "[$(date)] Starting debug checks..." >/tmp/install.log
    
    # Check if script exists
    if [ -f ${script_path} ]; then
        echo "[$(date)] Script found. Checking permissions..." >>/tmp/install.log
        ls -la ${script_path} >>/tmp/install.log 2>&1
        
        # Try to make it executable again from within the environment
        echo "[$(date)] Attempting to set permissions..." >>/tmp/install.log
        chmod +x ${script_path} >>/tmp/install.log 2>&1
        
        # Check shell interpreter
        echo "[$(date)] Checking script interpreter..." >>/tmp/install.log
        head -n1 ${script_path} >>/tmp/install.log 2>&1
        
        # Try running with bash explicitly instead of exec
        echo "[$(date)] Attempting to run script with bash..." >>/tmp/install.log
        /bin/bash ${script_path} >>/tmp/install.log 2>&1
    else
        echo "[$(date)] Script not found at ${script_path}" >>/tmp/install.log
        echo "[$(date)] Listing /root/custom/install/ directory:" >>/tmp/install.log
        ls -la /root/custom/install/ >>/tmp/install.log 2>&1
    fi
) 2>>/tmp/install.log
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
