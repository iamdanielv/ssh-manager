#!/bin/bash

# This script generates a standalone shell script from a source script
# that includes other files using a special syntax.
#
# Usage: ./build.sh
#
# The source script can include other files using the following syntax:
# # BUILD_INCLUDE_START: <path_to_file>
# source "<path_to_file>"
# # BUILD_INCLUDE_END: <path_to_file>
#
# The script will replace the block with the content of the included file and place the output in the `dist` directory.

set -euo pipefail

# Check for correct number of arguments
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <source_script>"
    exit 1
fi

SOURCE_SCRIPT=$1
SOURCE_DIR="src"

# Ensure the output directory exists
DIST_DIR="dist"
mkdir -p "$DIST_DIR"
OUTPUT_SCRIPT="$DIST_DIR/$(basename "${SOURCE_SCRIPT%.sh}").sh"

# Clear the output file before writing
> "$OUTPUT_SCRIPT"

# Process the source script
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*#\ BUILD_INCLUDE_START:\ (lib/.*) ]]; then
        # Extract the file path to include
        INCLUDE_FILE_REL_PATH="${BASH_REMATCH[1]}"
        INCLUDE_FILE_ABS_PATH="${SOURCE_DIR}/${INCLUDE_FILE_REL_PATH}"
        START_MARKER="$line"
        END_MARKER="# BUILD_INCLUDE_END: ${INCLUDE_FILE_REL_PATH}"

        # Check if the file exists
        if [ ! -f "$INCLUDE_FILE_ABS_PATH" ]; then
            echo "Error: Included file not found: $INCLUDE_FILE_ABS_PATH" >&2
            exit 1
        fi

        # Write the start marker, the file content, and the end marker
        echo "$START_MARKER" >> "$OUTPUT_SCRIPT"
        # Append the content of the included file
        # Using printf ensures that we handle files with or without a trailing newline correctly.
        # It prints the file content, then adds exactly one newline.
        printf '%s\n' "$(cat "$INCLUDE_FILE_ABS_PATH")" >> "$OUTPUT_SCRIPT"
        echo "$END_MARKER" >> "$OUTPUT_SCRIPT"

        # Skip lines until the END marker
        # This consumes the development-only `source` command and comments.
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

echo "Build successful: ${SOURCE_SCRIPT} -> ${OUTPUT_SCRIPT}"