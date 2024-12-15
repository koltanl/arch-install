#!/bin/bash

# Global variables
BORDER_THICKNESS=60
DEBUG=true  # Set to false to disable debugging output

# Function for debug output
debug_echo() {
    if [ "$DEBUG" = true ]; then
    echo "[DEBUG] $1" >&2
    fi
    }

# Function to scan networks using nmap
scan_networks() {
    debug_echo "Entering scan_networks function"

    if ! command -v nmap &> /dev/null; then
    echo "nmap could not be found. Please install nmap to use this script." >&2
    return 1
fi

    debug_echo "nmap found, proceeding with scan"

    # Get default gateway
    local default_gateway=$(ip route | grep '^default' | awk '{print $3}')
    debug_echo "Default gateway: $default_gateway"

    # Construct nmap command
    local nmap_cmd="sudo nmap -sn -oX - ${default_gateway}/22"
    debug_echo "Executing nmap command: $nmap_cmd"

    # Run nmap and process output
    local scan_result=$($nmap_cmd | awk '
                        /<address addr=/{
                        if (mac != "") {
                        print ssid "," signal "," channel "," encryption "," mac
                        ssid = ""; signal = "N/A"; channel = "N/A"; encryption = "N/A"; mac = ""
                        }
                        if ($0 ~ /addrtype="mac"/) {
                        mac = $2
                        sub(/.*"/, "", mac)
                        sub(/".*/, "", mac)
                        }
                        }
                        /<hostname name=/{
                        ssid = $2
                        sub(/.*"/, "", ssid)
                        sub(/".*/, "", ssid)
                        }
                        /<wireless-network type="infrastructure"/{
                        getline
                        if ($0 ~ /channel/) {
                        channel = $2
                        sub(/.*"/, "", channel)
                        sub(/".*/, "", channel)
                        }
                        getline
                        if ($0 ~ /signal_strength/) {
                        signal = $2
                        sub(/.*"/, "", signal)
                        sub(/".*/, "", signal)
                        # Convert dBm to percentage (approximation)
                        signal = int((signal + 100) * 2)
                        if (signal > 100) signal = 100
                        if (signal < 0) signal = 0
                        }
                        getline
                        if ($0 ~ /encryption/) {
                        encryption = $2
                        sub(/.*"/, "", encryption)
                        sub(/".*/, "", encryption)
                        }
                        }
                        END {
                        if (mac != "") {
                        print ssid "," signal "," channel "," encryption "," mac
                        }
                        }')

    debug_echo "Scan result:"
    debug_echo "$scan_result"

    echo "$scan_result"
    }

    # Function to get color based on signal strength
    get_signal_color() {
        local signal=$1
        if [ "$signal" == "N/A" ]; then
        echo -e "\e[90m"  # Gray
        elif [ "$signal" -ge 75 ]; then
        echo -e "\e[32m"  # Green
        elif [ "$signal" -ge 50 ]; then
        echo -e "\e[33m"  # Yellow
        else
        echo -e "\e[31m"  # Red
        fi
        }

    # Function to display data
    display_data() {
        local title=$1
        shift
        local -a data_collection=("$@")
        local border=$(printf "%${BORDER_THICKNESS}s" | tr ' ' '-')
        echo -e "\e[36m$border\e[0m"
        echo -e "\e[33m$title\e[0m"
        echo -e "\e[36m$border\e[0m"
        printf "%-30s %5s %5s %-10s %s\n" "SSID" "Signal" "Ch" "Encryption" "MAC"
        for item in "${data_collection[@]}"; do
        IFS=',' read -r ssid signal channel encryption mac <<< "$item"
        color=$(get_signal_color "$signal")
        printf "${color}%-30s %5s%% %5s %-10s %s\e[0m\n" "$ssid" "$signal" "$channel" "$encryption" "$mac"
        done
        }

    # Main function
    main() {
        debug_echo "Starting main function"

        # Scan networks
        debug_echo "Calling scan_networks function"
        mapfile -t networks < <(scan_networks)

        debug_echo "Number of networks found: ${#networks[@]}"

        if [ ${#networks[@]} -eq 0 ]; then
        echo "No networks found or unable to scan networks."
        debug_echo "Exiting script due to no networks found"
        exit 1
        fi

        # Display all networks
        debug_echo "Displaying all networks"
        display_data "All Networks Detected (${#networks[@]})" "${networks[@]}"

        # Sort networks by signal strength and display top 10
        debug_echo "Sorting networks and displaying top 10"
        mapfile -t sorted_networks < <(printf '%s\n' "${networks[@]}" | sort -t',' -k2 -nr | head -n 10)
        display_data "Top 10 Networks by Signal Strength (Higher % is better)" "${sorted_networks[@]}"

        debug_echo "Script execution completed"
        }

    # Run the main function
    main
