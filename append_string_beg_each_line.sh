#!/bin/bash

# Get the file path from the user
read -p "Enter the path to the file: " file_path

# Get the string to append from the user
read -p "Enter the string to append: " append_string

# Verify if the file exists
if [ ! -f "$file_path" ]; then
  echo "File not found!"
  exit 1
fi

# Create a temporary file for storing the modified content
temp_file="${file_path}.temp"

# Append the string to the beginning of each line
sed "s/^/${append_string}/" "$file_path" > "$temp_file"

# Replace the original file with the modified content
mv "$temp_file" "$file_path"

echo "String appended to each line in the file!"
