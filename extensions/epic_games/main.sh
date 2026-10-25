#!/bin/bash

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/../deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="epic_games"

ds_init "$EXTENSION_ID" "$OUT_FILE"

EPIC_URL="https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncher-x86_64.AppImage"
APPS_DIR="$HOME/Applications"
APPIMAGE_PATH="$APPS_DIR/EpicGamesLauncher-x86_64.AppImage"
VERSION_FILE="$HOME/.deck-store/extensions/epic_games.version"
ICON_PATH="$HOME/.deck-store/extensions/epic_games_icon.png"

install_epic() {
    ds_send_progress 15 "Checking Epic Games Launcher release..."
    ds_log "Fetching Epic Games Launcher Linux AppImage..."

    REDIRECT_LOC=$($DS_HOST_SPAWN curl -sI "$EPIC_URL" | grep -i "^location:" | head -n 1 | tr -d '\r')
    DETECTED_VER=$(echo "$REDIRECT_LOC" | sed -E 's|.*/EGLv2/([0-9.]+).*|\1|')
    if [ -z "$DETECTED_VER" ] || [[ "$DETECTED_VER" == *"http"* ]]; then
        DETECTED_VER="0.97.0"
    fi

    $DS_HOST_SPAWN mkdir -p "$APPS_DIR" "$HOME/.deck-store/extensions"
    cp -f "$SCRIPT_DIR/epic_games_icon.png" "$ICON_PATH" 2>/dev/null || true

    ds_send_progress 40 "Downloading Epic Games Launcher (${DETECTED_VER})..."
    if ! $DS_HOST_SPAWN curl -L --fail -o "$APPIMAGE_PATH" "$EPIC_URL"; then
        ds_log "ERROR: Failed to download Epic Games Launcher AppImage."
        exit 1
    fi

    $DS_HOST_SPAWN chmod +x "$APPIMAGE_PATH"
    echo "$DETECTED_VER" > "$VERSION_FILE"

    ds_send_progress 85 "Adding Epic Games Launcher to Steam..."
    ds_add_steam_shortcut "com.epicgames.LauncherLinux" "Epic Games Launcher" "$APPIMAGE_PATH" "--no-sandbox" "$ICON_PATH" || true

    $DS_HOST_SPAWN mkdir -p "$HOME/.local/share/applications"
    cat << EOF > "$HOME/.local/share/applications/epic-games-launcher.desktop"
[Desktop Entry]
Name=Epic Games Launcher
Comment=Native Epic Games Launcher for Linux
Exec="$APPIMAGE_PATH" --no-sandbox
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Game;
EOF
    chmod +x "$HOME/.local/share/applications/epic-games-launcher.desktop" 2>/dev/null || true

    ds_send_progress 100 "Epic Games Launcher installed."
    ds_log "SUCCESS: Epic Games Launcher ($DETECTED_VER) installed at $APPIMAGE_PATH."
}

case "$ACTION" in
    install|update)
        install_epic
        ;;
    check)
        if $DS_HOST_SPAWN test -f "$APPIMAGE_PATH"; then
            exit 0
        else
            exit 1
        fi
        ;;
    remove)
        ds_send_progress 30 "Removing Epic Games Launcher..."
        ds_remove_steam_shortcut "com.epicgames.LauncherLinux" || true
        $DS_HOST_SPAWN rm -f "$APPIMAGE_PATH" "$VERSION_FILE" "$HOME/.local/share/applications/epic-games-launcher.desktop"
        ds_send_progress 100 "Removed."
        ds_log "SUCCESS: Epic Games Launcher removed."
        ;;
    version)
        if [ -f "$VERSION_FILE" ]; then
            cat "$VERSION_FILE" > "$OUT_FILE"
        else
            echo "0.0.0" > "$OUT_FILE"
        fi
        ;;
esac
