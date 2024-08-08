#!/bin/bash

# Directory containing the RTF files
RTF_DIR="./"
OUTPUT_FILE="combined_text.txt"

# Empty the output file if it already exists
> "$OUTPUT_FILE"

# Loop through each RTF file in the directory
for rtf_file in *.rtf; do
  # Get the filename without the path
  filename=$(basename "$rtf_file")
  
  # Add the filename as a header
  echo "### $filename ###" >> "$OUTPUT_FILE"
  
  # Convert RTF to plain text and append to the output file
  unrtf --text "$rtf_file" >> "$OUTPUT_FILE"
  # or if you use pandoc
  # pandoc "$rtf_file" -t plain >> "$OUTPUT_FILE"

  # Add a newline for separation
  echo "" >> "$OUTPUT_FILE"
done

echo "Conversion and concatenation complete. Output saved to $OUTPUT_FILE"
