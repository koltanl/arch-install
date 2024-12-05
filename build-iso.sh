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

# Ensure scripts are executable
chmod +x ${work_dir}/airootfs/root/custom/install/preseedArch.sh
chmod +x ${work_dir}/airootfs/root/custom/install/deploymentArch.sh
chmod +x ${work_dir}/airootfs/root/custom/build-iso.sh
chmod +x ${work_dir}/airootfs/root/custom/test-installer.sh

# Near the top of the file, after the variable declarations
DEBUG=${DEBUG:-0}

# Update the .zprofile modification
cat >>${work_dir}/airootfs/root/.zprofile <<EOF
# Auto-start the installation script
(
    echo "[$(date)] Profile script starting..." >/tmp/install.log
    if [ -f ${script_path} ]; then
        echo "[$(date)] Installation script found at ${script_path}" >>/tmp/install.log
        export DEBUG=$DEBUG
        echo "[$(date)] Debug level: $DEBUG" >>/tmp/install.log
        echo "Starting automatic installation..."
        echo "You can find documentation in /root/custom/README.md"
        sleep 2
        
        # Create a flag file to prevent multiple runs
        if [ ! -f /tmp/.install_started ]; then
            echo "[$(date)] Creating install flag file" >>/tmp/install.log
            touch /tmp/.install_started
            
            # Check script permissions
            ls -l ${script_path} >>/tmp/install.log 2>&1
            
            echo "[$(date)] Executing installation script" >>/tmp/install.log
            # Run directly in the current shell
            exec ${script_path}
        else
            echo "[$(date)] Install already started flag found" >>/tmp/install.log
        fi
    else
        echo "[$(date)] Installation script not found!" >>/tmp/install.log
        ls -l /root/custom/install/ >>/tmp/install.log 2>&1
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
