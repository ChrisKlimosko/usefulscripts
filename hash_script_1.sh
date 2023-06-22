#!/bin/bash

# Get the current date and time
timestamp=$(date +"%Y-%m-%d %H:%M:%S")

# Prompt the user for the path and name of the file
read -p "Enter the path and name of the file: " filepath

# Expand the tilde (~) in the file path
eval filepath=$filepath

# Check if the file exists
if [ ! -f "$filepath" ]; then
    echo "File not found: $filepath"
    exit 1
fi

# Extract the file name and extension from the path
filename=$(basename "$filepath")
extension="${filename##*.}"
filename_without_ext="${filename%.*}"

# Generate the output file name
output_filename="${filename_without_ext}_hash.txt"

# Get the directory of the file
filedir=$(dirname "$filepath")

# Get the version of RHASH
rhash_version=$(rhash --version)

# Run rhash with all available hash algorithms and format the output using awk
{
    echo "Script run on: $timestamp"
    echo "RHASH version: $rhash_version"
    echo "File: $filepath"
    echo
    echo "MD5:"
    rhash --md5 "$filepath" | awk '{print $1}'
    echo
    echo "SHA1:"
    rhash --sha1 "$filepath" | awk '{print $1}'
    echo
    echo "SHA256:"
    rhash --sha256 "$filepath" | awk '{print $1}'
    echo
    echo "SHA512:"
    rhash --sha512 "$filepath" | awk '{print $1}'
    echo
    echo "CRC32:"
    cksum "$filepath" | awk '{print $1}'
    echo
    echo "Tiger:"
    rhash --tiger "$filepath" | awk '{print $1}'
    echo
    echo "Whirlpool:"
    rhash --whirlpool "$filepath" | awk '{print $1}'
    echo
    echo "ED2K:"
    rhash --ed2k "$filepath" | awk '{print $1}'
} > "$output_filename"

# Display a success message
echo "Hash results saved to $output_filename"

