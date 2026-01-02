#!/bin/bash

# Source base functionality
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="dummy_middle"

# Initialize Base
ds_init "$EXTENSION_ID" "$OUT_FILE"

VERSION_FILE="${HOME}/.deck-store/extensions/dummy_middle.version"
LEAF_VERSION_FILE="${HOME}/.deck-store/extensions/dummy_leaf.version"

install_dummy() {
    ds_send_progress 0 "Checking dependencies..."
    ds_log "Installing Dummy Middle..."
    
    # Check if Leaf is actually installed (simulating runtime dependency check)
    if [ ! -f "$LEAF_VERSION_FILE" ]; then
        ds_log "CRITICAL ERROR: Dummy Leaf is NOT installed!"
        exit 1
    fi
    
    ds_send_progress 50 "Simulating work..."
    sleep 1 # Fake work
    
    mkdir -p "$(dirname "$VERSION_FILE")"
    echo "1.0.0" > "$VERSION_FILE"
    
    ds_send_progress 100 "Done"
    ds_log "Dummy Middle installed."
}

remove_dummy() {
    ds_send_progress 0 "Removing..."
    rm -f "$VERSION_FILE"
    sleep 0.5
    ds_send_progress 100 "Removed"
    ds_log "Dummy Middle removed."
}

check_dummy() {
    if [ -f "$VERSION_FILE" ]; then
        exit 0
    else
        exit 1
    fi
}

case "$ACTION" in
    install|update) install_dummy ;;
    remove) remove_dummy ;;
    check) check_dummy ;;
    version) echo "1.0.0" > "$OUT_FILE" ;;
esac
exit 0