#!/bin/bash

# pull-data.sh
# Usage: ./pull-data.sh /path/to/live_output
# Recursively finds METEOR pass directories and copies key files to ./data/

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <target_directory>"
    exit 1
fi

SOURCE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"

if [ ! -d "$SOURCE" ]; then
    echo "Error: '$SOURCE' is not a directory"
    exit 1
fi

echo "Scanning: $SOURCE"
echo "Output:   $DATA_DIR"
echo ""

# Find directories containing dataset.json (i.e. completed pass directories)
find "$SOURCE" -name "dataset.json" | while read -r dataset; do
    PASS_DIR="$(dirname "$dataset")"
    PASS_NAME="$(basename "$PASS_DIR")"
    DEST="$DATA_DIR/$PASS_NAME"

    if [ -d "$DEST" ]; then
        echo "Skipping (already exists): $PASS_NAME"
        echo ""
        continue
    fi

    echo "Found pass: $PASS_NAME"
    mkdir -p "$DEST"

    # --- Root level files ---
    for f in dataset.json telemetry.json; do
        if [ -f "$PASS_DIR/$f" ]; then
            cp -n "$PASS_DIR/$f" "$DEST/$f"
            echo "  + $f"
        fi
    done

    # --- MSU-MR subdirectory ---
    MSU_SRC="$PASS_DIR/MSU-MR"
    MSU_DEST="$DEST/MSU-MR"

    if [ -d "$MSU_SRC" ]; then
        mkdir -p "$MSU_DEST"

        # Best composite
        if [ -f "$MSU_SRC/msu_mr_rgb_MSA_corrected.png" ]; then
            cp -n "$MSU_SRC/msu_mr_rgb_MSA_corrected.png" "$MSU_DEST/"
            echo "  + MSU-MR/msu_mr_rgb_MSA_corrected.png"
        fi

        # Another composite
        if [ -f "$MSU_SRC/msu_mr_rgb_AVHRR_221_False_Color_corrected.png" ]; then
            cp -n "$MSU_SRC/msu_mr_rgb_AVHRR_221_False_Color_corrected.png" "$MSU_DEST/"
            echo "  + MSU-MR/msu_mr_rgb_AVHRR_221_False_Color_corrected.png"
        fi



        # Individual channel images (1-3, not always all present)
        for ch in 1 2 3; do
            f="MSU-MR-${ch}.png"
            if [ -f "$MSU_SRC/$f" ]; then
                cp -n "$MSU_SRC/$f" "$MSU_DEST/$f"
                echo "  + MSU-MR/$f"
            fi
        done
    fi

    echo ""
done

echo "Done. Files written to: $DATA_DIR"
