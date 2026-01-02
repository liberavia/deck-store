#!/bin/bash

# Source base functionality
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="dummy_root"

# Initialize Base
ds_init "$EXTENSION_ID" "$OUT_FILE"

VERSION_FILE="${HOME}/.deck-store/extensions/dummy_root.version"
MIDDLE_VERSION_FILE="${HOME}/.deck-store/extensions/dummy_middle.version"

install_dummy() {
    ds_send_progress 0 "Checking dependencies..."
    ds_log "Installing Dummy Root..."
    
    # Check if Middle is actually installed
    if [ ! -f "$MIDDLE_VERSION_FILE" ]; then
        ds_log "CRITICAL ERROR: Dummy Middle is NOT installed!"
        exit 1
    fi
    
    ds_send_progress 50 "Simulating work..."
    sleep 1 # Fake work
    
    mkdir -p "$(dirname "$VERSION_FILE")"
    echo "1.0.0" > "$VERSION_FILE"
    
    ds_send_progress 100 "Done"
    ds_log "Dummy Root installed."
}

remove_dummy() {
    ds_send_progress 0 "Removing..."
    rm -f "$VERSION_FILE"
    sleep 0.5
    ds_send_progress 100 "Removed"
    ds_log "Dummy Root removed."
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