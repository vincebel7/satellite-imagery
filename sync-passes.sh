#!/bin/bash

# sync-passes.sh
# Usage: ./sync-passes.sh [-n] [directory ...]
#
# Uploads every SatDump pass found in the given directories (default:
# ~/Documents/live_output) to the file server, complete and unfiltered: images,
# composites, EMWIN, text, telemetry, CADU. Only .DS_Store files are left out.
#
#   <directory>/2026-11-01_15-47_goes_hrit_1.6941 GHz/
#     -> /zfs0/satellite/goes19/2026-11-01/2026-11-01_15-47_goes_hrit_1.6941GHz/
#     -> https://sat.vincebel.net/goes19/2026-11-01/2026-11-01_15-47_goes_hrit_1.6941GHz/
#
# Safe to re-run. Files already on the server are never changed or deleted, so
# only new files are sent.
#
#   -n    Dry run: list what would be sent, change nothing
#
# Environment overrides:
#   SAT_REMOTE          SSH target (default satsync@192.168.1.200)
#   SAT_REMOTE_ROOT     Dataset path (default /zfs0/satellite)
#   SAT_SETTLE_MINUTES  Skip passes written to this recently (default 10)

set -u

REMOTE="${SAT_REMOTE:-satsync@192.168.1.200}"
REMOTE_ROOT="${SAT_REMOTE_ROOT:-/zfs0/satellite}"
SETTLE_MINUTES="${SAT_SETTLE_MINUTES:-10}"
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=10"

DRY_RUN=()
if [ "${1:-}" = "-n" ]; then
    DRY_RUN=(--dry-run)
    shift
fi

if [ $# -eq 0 ]; then
    set -- "$HOME/Documents/live_output"
fi

# Maps a pass directory name to its top-level folder on the server.
# Add a line here for each new satellite or downlink.
source_for_pass() {
    case "$1" in
        *_goes_*)        echo "goes19" ;;
        *_meteor*_lrpt_*) echo "meteor-lrpt" ;;
        *_meteor*_hrpt_*) echo "meteor-hrpt" ;;
        *_elektro_*)     echo "elektro" ;;
        *)               echo "" ;;
    esac
}

synced=0
skipped=0
failed=0

for ROOT in "$@"; do
    if [ ! -d "$ROOT" ]; then
        echo "Error: '$ROOT' is not a directory" >&2
        failed=$((failed + 1))
        continue
    fi

    echo "Scanning: $ROOT"
    echo ""

    for PASS_DIR in "$ROOT"/*/; do
        [ -d "$PASS_DIR" ] || continue
        PASS_DIR="${PASS_DIR%/}"
        PASS_NAME="$(basename "$PASS_DIR")"

        if [[ ! "$PASS_NAME" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})_ ]]; then
            echo "Skipping (not a pass directory): $PASS_NAME"
            continue
        fi
        DATE="${BASH_REMATCH[1]}"

        SOURCE="$(source_for_pass "$PASS_NAME")"
        if [ -z "$SOURCE" ]; then
            echo "FAILED (no source folder mapped, edit source_for_pass): $PASS_NAME" >&2
            failed=$((failed + 1))
            continue
        fi

        if [ -z "$(find "$PASS_DIR" -type f ! -name .DS_Store -print -quit)" ]; then
            echo "Skipping (no files): $PASS_NAME"
            skipped=$((skipped + 1))
            continue
        fi

        # A file sent half-written would never be corrected, because existing
        # files are not overwritten. Wait until SatDump has finished.
        if [ -n "$(find "$PASS_DIR" -type f -mmin "-$SETTLE_MINUTES" -print -quit)" ]; then
            echo "Skipping (still being written): $PASS_NAME"
            skipped=$((skipped + 1))
            continue
        fi

        # Spaces are dropped so URLs and the remote command line stay simple.
        # Passes get their own folder: a day can hold several passes, and each
        # one has its own dataset.json.
        DEST="$SOURCE/$DATE/${PASS_NAME// /}"

        echo "Syncing: $PASS_NAME"
        echo "     to: $DEST/"

        if [ ${#DRY_RUN[@]} -eq 0 ] && ! $SSH_CMD "$REMOTE" "umask 022; mkdir -p '$REMOTE_ROOT/$DEST'"; then
            echo "FAILED (could not create remote folder): $PASS_NAME" >&2
            failed=$((failed + 1))
            continue
        fi

        if ! rsync -a ${DRY_RUN[@]+"${DRY_RUN[@]}"} --ignore-existing \
            --exclude=.DS_Store -e "$SSH_CMD" \
            "$PASS_DIR/" "$REMOTE:$REMOTE_ROOT/$DEST/"; then
            echo "FAILED (rsync): $PASS_NAME" >&2
            failed=$((failed + 1))
            RSYNC_FAILED=1
        else
            RSYNC_FAILED=0
        fi

        [ ${#DRY_RUN[@]} -eq 0 ] || { synced=$((synced + 1)); continue; }

        # The public web container reads these as "other", so everything must
        # be 755/644. This is done on the server because macOS openrsync's
        # --chmod has no effect on a push (it also rejects D755,F644). Runs even
        # after a failed rsync, so whatever arrived stays readable.
        if ! $SSH_CMD "$REMOTE" "cd '$REMOTE_ROOT/$DEST' && find . -type d ! -perm 755 -exec chmod 755 {} + && find . -type f ! -perm 644 -exec chmod 644 {} +"; then
            echo "FAILED (could not set permissions): $PASS_NAME" >&2
            [ "$RSYNC_FAILED" -eq 1 ] || failed=$((failed + 1))
            continue
        fi

        [ "$RSYNC_FAILED" -eq 1 ] || synced=$((synced + 1))
    done
done

echo ""
echo "Done. $synced synced, $skipped skipped, $failed failed."
[ "$failed" -eq 0 ]
