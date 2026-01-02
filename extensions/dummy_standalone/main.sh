#!/bin/bash
# 1. Setup paths
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/../deckstore_base.sh"

# 2. Get arguments from DeckStore
ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="dummy_standalone"

# 3. Initialize DeckStore Context
ds_init "$EXTENSION_ID" "$OUT_FILE"

VERSION_FILE="${HOME}/.deck-store/extensions/${EXTENSION_ID}.version"

install_ext() {
    ds_send_progress 0 "Starting installation..."
    ds_log "Installing ${EXTENSION_ID}..."
    
    ds_send_progress 50 "Doing standalone things..."
    sleep 1
    
    mkdir -p "$(dirname "$VERSION_FILE")"
    echo "1.0.0" > "$VERSION_FILE"
    
    ds_send_progress 100 "Installation Complete"
    ds_log "${EXTENSION_ID} installed."
}

remove_ext() {
    ds_send_progress 0 "Preparing removal..."
    ds_log "Removing ${EXTENSION_ID}..."
    sleep 0.5
    rm -f "$VERSION_FILE"
    ds_send_progress 100 "Removal Complete"
}

update_ext() {
    ds_log "Update requested..."
    install_ext
}

check_ext() {
    if [ -f "$VERSION_FILE" ]; then
        exit 0
    else
        exit 1
    fi
}

case "$ACTION" in
    install) install_ext ;;
    update)  update_ext ;;
    remove)  remove_ext ;;
    check)   check_ext ;;
    version) echo "1.0.0" > "$OUT_FILE" ;;
    *)       exit 2 ;;
esac
exit 0
