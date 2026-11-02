#!/bin/bash

# pull-data-hrit.sh
# Usage: ./pull-data-hrit.sh /path/to/live_output
# Recursively finds GOES/Elektro HRIT pass directories and copies key files to ./data/
# Keeps the IMAGES/<satellite>/<sector>/<timestamp>/ layout so goes_timelapse.py
# can be pointed at data/<pass>/IMAGES/GOES-19/Full Disk

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <target_directory>"
    exit 1
fi

SOURCE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

# Images to keep from each frame directory (full res, ~37 MB per Full Disk frame)
KEEP=(abi_rgb_ABI_False_Color.png)

if [ ! -d "$SOURCE" ]; then
    echo "Error: '$SOURCE' is not a directory"
    exit 1
fi

echo "Scanning: $SOURCE"
echo "Output:   $DATA_DIR"
echo ""

# HRIT passes have no dataset.json, so match on the directory name instead
find "$SOURCE" -type d -name "*_hrit_*" -prune | while read -r PASS_DIR; do
    PASS_NAME="$(basename "$PASS_DIR")"
    DEST="$DATA_DIR/$PASS_NAME"

    if [ -d "$DEST" ]; then
        echo "Skipping (already exists): $PASS_NAME"
        echo ""
        continue
    fi

    # Collect wanted images first so empty passes don't create a directory
    MATCHES=()
    for name in "${KEEP[@]}"; do
        while IFS= read -r f; do
            MATCHES+=("$f")
        done < <(find "$PASS_DIR/IMAGES" -type f -name "$name" 2>/dev/null | sort)
    done

    if [ ${#MATCHES[@]} -eq 0 ]; then
        echo "Skipping (no images): $PASS_NAME"
        echo ""
        continue
    fi

    echo "Found pass: $PASS_NAME (${#MATCHES[@]} images)"

    for f in "${MATCHES[@]}"; do
        REL="${f#$PASS_DIR/}"
        mkdir -p "$DEST/$(dirname "$REL")"
        cp -n "$f" "$DEST/$REL"
        echo "  + $REL"
    done

    echo ""
done

echo "Done. Files written to: $DATA_DIR"
