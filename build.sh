#!/bin/bash

# This script generates a standalone shell script from a source script
# that includes other files using a special syntax.
#
# Usage: ./build.sh <source_script> <output_script>
#
# The source script can include other files using the following syntax:
# # BUILD_INCLUDE_START: <path_to_file>
# source "<path_to_file>"
# # BUILD_INCLUDE_END: <path_to_file>
#
# The script will replace the block with the content of the included file.

set -euo pipefail

# Check for correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <source_script> <output_script>"
    exit 1
fi

SOURCE_SCRIPT=$1
OUTPUT_SCRIPT=$2
SOURCE_DIR=$(dirname "$SOURCE_SCRIPT")

# Ensure the output directory exists
mkdir -p "$(dirname "$OUTPUT_SCRIPT")"

# Clear the output file before writing
> "$OUTPUT_SCRIPT"

# Process the source script
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*#\ BUILD_INCLUDE_START:\ (.*) ]]; then
        # Extract the file path to include
        INCLUDE_FILE_REL_PATH="${BASH_REMATCH[1]}"
        INCLUDE_FILE_ABS_PATH="$SOURCE_DIR/$INCLUDE_FILE_REL_PATH"

        # Check if the file exists
        if [ ! -f "$INCLUDE_FILE_ABS_PATH" ]; then
            echo "Error: Included file not found: $INCLUDE_FILE_ABS_PATH" >&2
            exit 1
        fi

        # Append the content of the included file
        cat "$INCLUDE_FILE_ABS_PATH" >> "$OUTPUT_SCRIPT"

        # Skip lines until the END marker
        END_MARKER="# BUILD_INCLUDE_END: $INCLUDE_FILE_REL_PATH"
        while IFS= read -r skipline && [[ ! "$skipline" =~ ^[[:space:]]*${END_MARKER} ]]; do
            : # Do nothing, just skip the line
        done
    else
        # Copy the line to the output script
        echo "$line" >> "$OUTPUT_SCRIPT"
    fi
done < "$SOURCE_SCRIPT"

# Make the output script executable
chmod +x "$OUTPUT_SCRIPT"