#!/bin/bash

# Get the file path from the user
read -p "Enter the path to the file you want to split: " file_path

# Get the desired number of equal parts to split the file into from the user
read -p "Enter the number of equal parts to split the file: " num_parts

# Verify if the file exists
if [ ! -f "$file_path" ]; then
  echo "File not found!"
  exit 1
fi

# Get the total number of lines in the file
total_lines=$(wc -l < "$file_path")

# Calculate the number of lines per part
lines_per_part=$((total_lines / num_parts))

# Split the file
split -l "$lines_per_part" "$file_path" split_file

echo "File split completed!"
