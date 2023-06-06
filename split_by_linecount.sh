#!/bin/bash

# Get the file path from the user
read -p "Enter the path to the file you want to split: " file_path

# Get the desired line count for each split file from the user
read -p "Enter the number of lines per split file: " lines_per_file

# Verify if the file exists
if [ ! -f "$file_path" ]; then
  echo "File not found!"
  exit 1
fi

# Split the file
split -l "$lines_per_file" "$file_path" split_file

echo "File split completed!"
