#!/bin/bash

# Check if input file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <input_file>"
    exit 1
fi

input_file=$1

# Check if input file exists
if [ ! -f "$input_file" ]; then
    echo "Input file '$input_file' not found."
    exit 1
fi

# Perform WHOIS lookup for each IP address in the input file
while IFS= read -r ip; do
    echo "WHOIS lookup for IP: $ip"
    # Perform the WHOIS lookup and extract organization field
    org=$(whois "$ip" | awk -F ':' '/^Organization:/ {print $2}')
    # Print IP address and organization
    echo "IP: $ip"
    echo "Organization: $org"
    echo "-----------------------------------"
done < "$input_file"
