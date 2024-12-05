#!/bin/bash

file="$1"
editor="${EDITOR:-nano}"  # Default to nano if $EDITOR is not set
$EDITOR "$file" >/dev/null 2>&1
# Attempt to open the file using xdg-open
xdg-open "$file" >/dev/null 2>&1

# Check if xdg-open succeeded
if [ $? -ne 0 ]; then
    # xdg-open failed, fallback to the text editor
    $editor "$file"
fi
