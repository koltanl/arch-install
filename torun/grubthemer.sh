#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
LAUNCHDIR="/root/arch-install"
# Error handling
set -e
trap 'echo -e "${RED}An error occurred. GRUB theme installation failed.${NC}" >&2' ERR

THEME_DIR="/boot/grub/themes/arch"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Check if LAUNCHDIR is set
if [ -z "$LAUNCHDIR" ]; then
    echo -e "${RED}LAUNCHDIR environment variable is not set${NC}"
    exit 1
fi

echo -e "${YELLOW}Installing GRUB theme...${NC}"

# Create theme directory
mkdir -p "$THEME_DIR"

# Extract theme using absolute path
tar xf "$LAUNCHDIR/torun/arch-linux-grub-theme.tar" -C "$THEME_DIR"

# Backup existing GRUB config
if [ ! -f "/etc/default/grub.backup" ]; then
    cp /etc/default/grub /etc/default/grub.backup
fi

# Configure GRUB to use the theme
sed -i 's|^#\?GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/arch/theme.txt"|' /etc/default/grub

# Enable graphical terminal output
sed -i 's|^#\?GRUB_TERMINAL_OUTPUT=.*|GRUB_TERMINAL_OUTPUT="gfxterm"|' /etc/default/grub

# Set resolution
echo -e "${YELLOW}Setting GRUB resolution...${NC}"
sed -i 's|^#\?GRUB_GFXMODE=.*|GRUB_GFXMODE="1920x1080,auto"|' /etc/default/grub

# Update GRUB configuration
echo -e "${YELLOW}Updating GRUB configuration...${NC}"
grub-mkconfig -o /boot/grub/grub.cfg

echo -e "${GREEN}GRUB theme installation complete!${NC}" 