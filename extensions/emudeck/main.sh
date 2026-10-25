#!/bin/bash

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/../deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="emudeck"

ds_init "$EXTENSION_ID" "$OUT_FILE"

APPS_DIR="$HOME/Applications"
APPIMAGE_PATH="$APPS_DIR/EmuDeck.AppImage"
VERSION_FILE="$HOME/.deck-store/extensions/emudeck.version"
ICON_PATH="$HOME/.deck-store/extensions/emudeck_icon.png"

install_emudeck() {
    ds_send_progress 10 "Fetching latest EmuDeck release..."
    ds_log "Fetching latest EmuDeck release from GitHub..."

    RELEASE_JSON=$(curl -sL "https://api.github.com/repos/EmuDeck/emudeck-electron/releases/latest")
    LATEST_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name | endswith("-x86_64.AppImage")) | .browser_download_url' | head -n 1)

    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        ds_log "ERROR: Could not find EmuDeck x86_64 AppImage in latest release."
        exit 1
    fi

    $DS_HOST_SPAWN mkdir -p "$APPS_DIR" "$HOME/.deck-store/extensions"
    cp -f "$SCRIPT_DIR/emudeck_icon.png" "$ICON_PATH" 2>/dev/null || true

    ds_send_progress 40 "Downloading EmuDeck (${LATEST_TAG})..."
    if ! $DS_HOST_SPAWN curl -L --fail -o "$APPIMAGE_PATH" "$DOWNLOAD_URL"; then
        ds_log "ERROR: Failed to download EmuDeck AppImage."
        exit 1
    fi

    $DS_HOST_SPAWN chmod +x "$APPIMAGE_PATH"
    echo "${LATEST_TAG#v}" > "$VERSION_FILE"

    ds_send_progress 85 "Adding EmuDeck shortcut to Steam..."
    ds_add_steam_shortcut "io.github.emudeck.AppImage" "EmuDeck" "$APPIMAGE_PATH" "--no-sandbox" "$ICON_PATH" || true

    $DS_HOST_SPAWN mkdir -p "$HOME/.local/share/applications"
    cat << EOF > "$HOME/.local/share/applications/emudeck.desktop"
[Desktop Entry]
Name=EmuDeck
Comment=Emulator Manager and Configuration Tool for SteamOS
Exec="$APPIMAGE_PATH" --no-sandbox
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Game;Emulator;
EOF
    chmod +x "$HOME/.local/share/applications/emudeck.desktop" 2>/dev/null || true

    ds_send_progress 100 "EmuDeck installed."
    ds_log "SUCCESS: EmuDeck (${LATEST_TAG}) installed at $APPIMAGE_PATH."
}

case "$ACTION" in
    install|update)
        install_emudeck
        ;;
    check)
        if $DS_HOST_SPAWN test -f "$APPIMAGE_PATH"; then
            exit 0
        else
            exit 1
        fi
        ;;
    remove)
        ds_send_progress 30 "Removing EmuDeck AppImage and shortcut..."
        ds_remove_steam_shortcut "io.github.emudeck.AppImage" || true
        $DS_HOST_SPAWN rm -f "$APPIMAGE_PATH" "$VERSION_FILE" "$HOME/.local/share/applications/emudeck.desktop"
        ds_send_progress 100 "EmuDeck removed."
        ds_log "SUCCESS: EmuDeck removed."
        ;;
    version)
        if [ -f "$VERSION_FILE" ]; then
            cat "$VERSION_FILE" > "$OUT_FILE"
        else
            echo "0.0.0" > "$OUT_FILE"
        fi
        ;;
esac
