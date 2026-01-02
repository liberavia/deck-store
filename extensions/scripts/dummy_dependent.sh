#!/bin/bash

# Source base functionality
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="dependent_dummy_tool"

# Initialize Base
ds_init "$EXTENSION_ID" "$OUT_FILE"

VERSION_FILE="${HOME}/.deck-store/extensions/dummy.version"

install_dummy() {
    ds_send_progress 0 "Checking dependencies..."
    ds_log "Installing Dependent Dummy Tool..."
    
    # Check if SSM is actually installed (simulating runtime dependency check)
    if ! flatpak-spawn --host flatpak info "io.github.liberavia.steamshortcutmanager" &> /dev/null; then
        ds_log "CRITICAL ERROR: Steam Shortcut Manager is NOT installed!"
        exit 1
    fi
    
    ds_send_progress 50 "Simulating work..."
    sleep 2 # Fake work
    
    mkdir -p "$(dirname "$VERSION_FILE")"
    echo "1.0.0" > "$VERSION_FILE"
    
    ds_send_progress 100 "Done"
    ds_log "Dummy Tool installed."
}

remove_dummy() {
    ds_send_progress 0 "Removing..."
    rm -f "$VERSION_FILE"
    sleep 1
    ds_send_progress 100 "Removed"
    ds_log "Dummy Tool removed."
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
