#!/bin/bash

# pull-data-hrpt.sh
# Usage: ./pull-data-hrpt.sh /path/to/live_output
# Recursively finds METEOR HRPT pass directories and copies key files to ./data/

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

# Find HRPT pass directories containing dataset.json (i.e. completed passes)
find "$SOURCE" -path "*_hrpt_*/dataset.json" | while read -r dataset; do
    PASS_DIR="$(dirname "$dataset")"
    PASS_NAME="$(basename "$PASS_DIR")"
    DEST="$DATA_DIR/$PASS_NAME"

    if [ -d "$DEST" ]; then
        echo "Skipping (already exists): $PASS_NAME"
        echo ""
        continue
    fi

    MSU_SRC="$PASS_DIR/MSU-MR"

    # Passes that failed to decode have product.cbor but no images
    if ! ls "$MSU_SRC"/*.png >/dev/null 2>&1; then
        echo "Skipping (no images): $PASS_NAME"
        echo ""
        continue
    fi

    echo "Found pass: $PASS_NAME"
    mkdir -p "$DEST"

    # --- Root level files ---
    if [ -f "$PASS_DIR/dataset.json" ]; then
        cp -n "$PASS_DIR/dataset.json" "$DEST/dataset.json"
        echo "  + dataset.json"
    fi

    # --- MSU-MR subdirectory ---
    MSU_DEST="$DEST/MSU-MR"
    mkdir -p "$MSU_DEST"

    # HRPT keeps telemetry under MSU-MR instead of the pass root
    for f in telemetry.json msu_mr_rgb_MSA_corrected.png msu_mr_rgb_AVHRR_221_False_Color_corrected.png; do
        if [ -f "$MSU_SRC/$f" ]; then
            cp -n "$MSU_SRC/$f" "$MSU_DEST/$f"
            echo "  + MSU-MR/$f"
        fi
    done

    # Individual channel images (1-6, not always all present)
    for ch in 1 2 3 4 5 6; do
        f="MSU-MR-${ch}.png"
        if [ -f "$MSU_SRC/$f" ]; then
            cp -n "$MSU_SRC/$f" "$MSU_DEST/$f"
            echo "  + MSU-MR/$f"
        fi
    done

    # --- MTVZA subdirectory (microwave, small) ---
    MTVZA_SRC="$PASS_DIR/MTVZA"
    if [ -f "$MTVZA_SRC/mtvza_rgb_Microwave_Airmass.png" ]; then
        mkdir -p "$DEST/MTVZA"
        cp -n "$MTVZA_SRC/mtvza_rgb_Microwave_Airmass.png" "$DEST/MTVZA/"
        echo "  + MTVZA/mtvza_rgb_Microwave_Airmass.png"
    fi

    echo ""
done

echo "Done. Files written to: $DATA_DIR"
