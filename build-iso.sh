#!/bin/bash

# Required packages: archiso, sudo

# Set up working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="/tmp/archiso-custom"
out_dir="${SCRIPT_DIR}/out"
script_path="/root/custom/makeitarchinstall.sh"

# Clean up previous builds
sudo rm -rf ${work_dir}
mkdir -p ${out_dir}

# Copy the baseline archiso profile
cp -r /usr/share/archiso/configs/releng/ ${work_dir}

# Create directory structure in ISO
mkdir -p ${work_dir}/airootfs/root/custom

# Copy our installation script and make it executable
cp "${SCRIPT_DIR}/makeitarchinstall.sh" ${work_dir}/airootfs/root/custom/
chmod +x ${work_dir}/airootfs/root/custom/makeitarchinstall.sh

# Copy README for reference
cp "${SCRIPT_DIR}/README.md" ${work_dir}/airootfs/root/custom/

# Add autostart to .zprofile
cat >> ${work_dir}/airootfs/root/.zprofile <<EOF
# Auto-start the installation script
if [ -f ${script_path} ]; then
    echo "Starting automatic installation..."
    echo "You can find documentation in /root/custom/README.md"
    sleep 2
    ${script_path}
fi
EOF

# Add additional packages
cat >> ${work_dir}/packages.x86_64 <<EOF
git
wget
dialog
cryptsetup
gptfdisk
reflector
EOF

# Build the ISO
sudo mkarchiso -v -w ${work_dir} -o ${out_dir} ${work_dir}

# Clean up
sudo rm -rf ${work_dir}

echo "ISO has been created in ${out_dir}"
echo "You can write it to a USB drive using:"
echo "sudo dd bs=4M if=${out_dir}/archlinux-custom-*.iso of=/dev/sdX status=progress oflag=sync"