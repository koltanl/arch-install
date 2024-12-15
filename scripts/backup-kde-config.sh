#!/bin/bash

# Create directory structure
mkdir -p kde/{plasma,kwin,shortcuts,kdedefaults}

# KWin configs
cp ~/.config/kwinrc kde/kwin/
cp ~/.config/kwinrulesrc kde/kwin/
cp ~/.config/kglobalshortcutsrc kde/shortcuts/

# Plasma configs
cp ~/.config/plasmarc kde/plasma/
cp ~/.config/plasmashellrc kde/plasma/
cp -r ~/.config/plasma-org.kde.* kde/plasma/

# Theme configs
cp ~/.config/kdeglobals kde/
cp -r ~/.config/kdedefaults/* kde/kdedefaults/

# Export current window rules
kwriteconfig5 --file kde/kwin/kwinrulesrc --group 1 --key rules "$(kcmshell5 kwinrules)" 