#!/bin/bash

# Function to determine the subnet
get_subnet() {
    # Identify the active network interface (assuming it's the one with a valid IP address)
    INTERFACE=$(ip -o -4 addr list | awk '{print $2 " " $4}' | grep -v "127.0.0.1" | head -n 1 | awk '{print $1}')

    # Get the IP address and CIDR notation of the subnet
    CIDR=$(ip -o -4 addr show dev $INTERFACE | awk '{print $4}')

    # Extract base address and subnet mask
    BASE_ADDRESS=$(ipcalc -n $CIDR | grep Network | awk '{print $2}')
    echo $BASE_ADDRESS
    }

# Define the subnet to scan dynamically
SUBNET=$(get_subnet)

# Perform the network scan and extract IP addresses
echo "Scanning the network $SUBNET..."
IP_LIST=$(nmap -sP $SUBNET -oG - | grep "Host" | awk '{print $2}')

# Function to check and open web browser if port is open using nmap
check_and_open() {
    IP=$1
    PORT=$2
    if nmap -p $PORT $IP | grep "$PORT/tcp open" > /dev/null; then
    echo "Port $PORT is open on $IP. Opening in web browser..."
    xdg-open http://$IP:$PORT
    fi
    }

# Check each IP address for open ports 80 and 443
for IP in $IP_LIST; do
check_and_open $IP 80
check_and_open $IP 443
done

echo "Done."
