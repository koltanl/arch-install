#!/bin/bash

# Function to draw a right triangle with given base length and height
draw_right_triangle() {
    local base_length=$1
    local height=$2

    # Draw the triangle
    for (( i = 1; i <= height; i++ )); do
    for (( j = 1; j <= i; j++ )); do
    echo -n "* "
    done
    echo
    done
    }

# Main script
base_length=151  # Example base length
height=71     # Example height

echo "Drawing a right triangle with base length $base_length and height $height:"

# Draw the right triangle
draw_right_triangle $base_length $height
