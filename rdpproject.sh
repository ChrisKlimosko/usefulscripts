#!/bin/bash

# Step 1: Init Shodan CLI
#sudo apt update && sudo apt install python3-shodan -y
#shodan init <apikey>

# Step 2: Download the list
shodan download --limit 600 edm3389.json.gz 'city:"edmonton" port:"3389"'

# Step 3: Sort your data
shodan parse --fields ip_str edm3389.json.gz > 2IPList.txt
shodan convert edm3389.json.gz images

# Step 4: Nmap scan to check if the host is alive and output to a file
nmap -p 3389 -sT -Pn -iL "2IPList.txt" -oN "nmaptemp.txt"
grep -B 8 open nmaptemp.txt | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" > "Open3389.txt"

# Step 5: Split the output into equal parts based on workers
read -p "Enter the number of people working on the project: " num_parts
total_lines=$(wc -l < "Open3389.txt")
lines_per_part=$((total_lines / num_parts))
split -l "$lines_per_part" "$file_path" split_file
count=$(wc -l split_fileaa)

echo "IP's have been split into $num_parts with $count IP's each"
