#!/usr/bin/env python3
import sys
import subprocess
import shutil

def parse_input(input_str):
    programs = [p.strip() for p in input_str.replace(';', ',').split(',')]
    parsed_programs = []
    for program in programs:
        parts = program.split()
        program_name = parts[0]
        invocation_name = ' '.join(parts[1:]) if len(parts) > 1 else program_name
        parsed_programs.append((program_name, invocation_name))
    return parsed_programs

def remove_program(program_name):
    if not shutil.which(program_name):
        print(f"'{program_name}' is not installed.")
        return

    # Try removing with apt
    try:
        print(f"Attempting to remove {program_name} using apt...")
        if subprocess.run(["sudo", "apt", "remove", "-y", program_name], check=True).returncode == 0:
            print(f"{program_name} removed successfully using apt.")
            return
    except subprocess.CalledProcessError:
        print(f"Failed to remove {program_name} using apt.")

    # Try removing with pacman
    try:
        print(f"Attempting to remove {program_name} using pacman...")
        if subprocess.run(["sudo", "pacman", "-R", "--noconfirm", program_name], check=True).returncode == 0:
            print(f"{program_name} removed successfully using pacman.")
            return
    except subprocess.CalledProcessError:
        print(f"Failed to remove {program_name} using pacman.")

    # Try removing with yay
    try:
        print(f"Attempting to remove {program_name} using yay...")
        if subprocess.run(["yay", "-R", "--noconfirm", program_name], check=True).returncode == 0:
            print(f"{program_name} removed successfully using yay.")
            return
    except subprocess.CalledProcessError:
        print(f"Failed to remove {program_name} using yay.")

    # Add similar blocks for other package managers as needed
    print(f"Could not remove {program_name} with any available package manager.")

if __name__ == "__main__":
    input_str = ' '.join(sys.argv[1:])
    parsed_programs = parse_input(input_str)
    for program_name, invocation_name in parsed_programs:
        print(f"Program name: '{program_name}', Invocation name: '{invocation_name}'")
        remove_program(invocation_name)
