#!/bin/bash

# Check if the file exists
if [ ! -f "ips_to_lookup.txt" ]; then
    echo "File ips_to_lookup.txt not found!"
    exit 1
fi

# Remove whois_results.txt if it exists, to start fresh
if [ -f "whois_results.txt" ]; then
    rm "whois_results.txt"
fi

# Perform the WHOIS lookup for each IP in the file
while IFS= read -r ip
do
    echo "Looking up IP: $ip" >> whois_results.txt
    whois $ip >> whois_results.txt
    echo "=======================" >> whois_results.txt
done < "ips_to_lookup.txt"
