#!/bin/bash

# Script to enable enhanced eye candy for Pacman in Arch Linux

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

# Backup the original pacman.conf
cp /etc/pacman.conf /etc/pacman.conf.backup

# Enable eye candy options in pacman.conf
sed -i '/^#Color/s/^#//' /etc/pacman.conf
sed -i '/^#VerbosePkgLists/s/^#//' /etc/pacman.conf

# Add ILoveCandy option if it doesn't exist
if ! grep -q "ILoveCandy" /etc/pacman.conf; then
    sed -i '/\[options\]/a ILoveCandy' /etc/pacman.conf
fi

# Set ParallelDownloads to 5 if not already set
sed -i 's/^ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf

echo "Enhanced eye candy has been enabled for Pacman"
echo "A backup of the original configuration has been created at /etc/pacman.conf.backup"

# Refresh the package databases
pacman -Sy

echo "Pacman configuration updated and package databases refreshed"
echo "You should now see colorized output, verbose package lists, and Pacman eating dots!"
