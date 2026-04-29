#!/bin/bash
# decrypt_and_unzip.sh
# Decrypts GPG-encrypted zip files and unzips them.
# Usage: ./decrypt_and_unzip.sh [directory]
# If no directory is given, the current directory is used.

set -uo pipefail

SEARCH_DIR="${1:-.}"

# Prompt for password securely (not visible in process list)
read -rsp "Enter GPG passphrase: " GPG_PASSPHRASE
echo

SUCCESS=0
FAILED=0

# Use bash glob instead of find — handles special chars like brackets in filenames
shopt -s nullglob
for gpg_file in "$SEARCH_DIR"/*.gpg; do
    zip_file="${gpg_file%.gpg}"
    base="${zip_file%.zip}"

    echo "Decrypting: $gpg_file"
    if gpg --batch --yes --passphrase "$GPG_PASSPHRASE" \
           --output "$zip_file" \
           --decrypt "$gpg_file" 2>/dev/null; then

        echo "Unzipping:  $zip_file -> ${base}/"
        if unzip -q -o "$zip_file" -d "$base"; then
            echo "  Done: ${base}/"
            rm -f "$zip_file"   # Remove intermediate .zip; delete this line to keep it
            ((SUCCESS++)) || true
        else
            echo "  ERROR: Failed to unzip $zip_file"
            ((FAILED++)) || true
        fi
    else
        echo "  ERROR: Failed to decrypt $gpg_file (wrong password?)"
        ((FAILED++)) || true
    fi
done

echo ""
echo "Done. $SUCCESS succeeded, $FAILED failed."
