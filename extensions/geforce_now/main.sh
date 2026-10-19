#!/bin/bash

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/../deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="geforce_now"

ds_init "$EXTENSION_ID" "$OUT_FILE"

GFN_REMOTE_NAME="GeForceNOW"
GFN_REPO_URL="https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo"
GFN_APP_ID="com.nvidia.geforcenow"
ICON_PATH="$HOME/.deck-store/extensions/geforce_now_icon.png"

install_gfn() {
    ds_send_progress 15 "Adding official NVIDIA GeForce NOW repository..."
    ds_log "Adding NVIDIA GeForce NOW Flatpak remote..."

    $DS_FLATPAK_CMD remote-add --user --if-not-exists "$GFN_REMOTE_NAME" "$GFN_REPO_URL" >> "$OUT_FILE" 2>&1

    ds_send_progress 45 "Installing com.nvidia.geforcenow..."
    ds_log "Installing GeForce NOW client via Flatpak..."
    $DS_FLATPAK_CMD install --user --assumeyes "$GFN_REMOTE_NAME" "$GFN_APP_ID" >> "$OUT_FILE" 2>&1

    ds_send_progress 75 "Configuring controller permissions..."
    $DS_FLATPAK_CMD override --user --filesystem=/run/udev:ro "$GFN_APP_ID" >> "$OUT_FILE" 2>&1 || true

    mkdir -p "$HOME/.deck-store/extensions"
    cp -f "$SCRIPT_DIR/geforce_now_icon.png" "$ICON_PATH" 2>/dev/null || true

    ds_send_progress 90 "Adding GeForce NOW to Steam..."
    ds_add_steam_shortcut "$GFN_APP_ID" "NVIDIA GeForce NOW" "/usr/bin/flatpak" "run $GFN_APP_ID" "$ICON_PATH" || true

    ds_send_progress 100 "GeForce NOW installed."
    ds_log "SUCCESS: NVIDIA GeForce NOW installed and added to Steam."
}

case "$ACTION" in
    install)
        install_gfn
        ;;
    update)
        ds_send_progress 30 "Updating NVIDIA GeForce NOW..."
        $DS_FLATPAK_CMD update --user --assumeyes "$GFN_APP_ID" >> "$OUT_FILE" 2>&1
        ds_send_progress 100 "Updated."
        ;;
    check)
        if $DS_FLATPAK_CMD info --user "$GFN_APP_ID" >/dev/null 2>&1 || $DS_FLATPAK_CMD info "$GFN_APP_ID" >/dev/null 2>&1; then
            exit 0
        else
            exit 1
        fi
        ;;
    remove)
        ds_send_progress 30 "Uninstalling NVIDIA GeForce NOW..."
        ds_remove_steam_shortcut "$GFN_APP_ID" || true
        $DS_FLATPAK_CMD uninstall --user --assumeyes "$GFN_APP_ID" >> "$OUT_FILE" 2>&1 || true
        ds_send_progress 100 "Removed."
        ds_log "SUCCESS: NVIDIA GeForce NOW uninstalled."
        ;;
    version)
        VER=$($DS_FLATPAK_CMD info "$GFN_APP_ID" 2>/dev/null | grep -i "Version:" | awk '{print $2}' | head -n 1)
        echo "${VER:-1.0.0}" > "$OUT_FILE"
        ;;
esac
