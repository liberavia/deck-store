#!/bin/bash

source "$(dirname "$0")/../deckstore_base.sh"

OPERATION="$1"
LOG_FILE="$2"
EXTENSION_ID="decky_loader"

USER_NAME=$($DS_HOST_SPAWN id -un 2>/dev/null || whoami)
DECKY_HOME="$HOME/homebrew"
DECKY_SERVICES="$DECKY_HOME/services"
DECKY_PLUGINS="$DECKY_HOME/plugins"
LOADER_BIN="$DECKY_SERVICES/PluginLoader"
VERSION_FILE="$DECKY_SERVICES/.loader.version"
SYSTEM_SERVICE_FILE="/etc/systemd/system/plugin_loader.service"
LEGACY_USER_SERVICE="$HOME/.config/systemd/user/decky-loader.service"

ds_init "$EXTENSION_ID" "$LOG_FILE"

check_host_access() {
    if ! $DS_HOST_SPAWN true 2>/dev/null; then
        ds_log "ERROR: Cannot execute commands on host."
        return 1
    fi
    return 0
}

cleanup_legacy_user_service() {
    if $DS_HOST_SPAWN test -f "$LEGACY_USER_SERVICE"; then
        ds_log "Migrating away from legacy user-mode decky-loader.service..."
        $DS_HOST_SPAWN systemctl --user disable --now decky-loader >/dev/null 2>&1 || true
        $DS_HOST_SPAWN rm -f "$LEGACY_USER_SERVICE"
        $DS_HOST_SPAWN rm -rf "$DECKY_SERVICES/decky-loader"
        $DS_HOST_SPAWN systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
}

install_decky() {
    ds_log "Starting official Decky Loader installation..."
    check_host_access || exit 1

    ds_send_progress 10 "Fetching latest release info..."
    RELEASE_JSON=$(curl -sL https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases/latest)

    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name=="PluginLoader") | .browser_download_url')
    VERSION_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')

    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        ds_log "ERROR: Could not find PluginLoader asset in latest release."
        exit 1
    fi

    cleanup_legacy_user_service

    ds_log "Installing Decky Loader version: $VERSION_TAG"
    ds_send_progress 25 "Preparing homebrew directories..."

    $DS_HOST_SPAWN mkdir -p "$DECKY_SERVICES" "$DECKY_PLUGINS" "$DECKY_HOME/data"
    ds_sudo chown -R "$USER_NAME:$USER_NAME" "$DECKY_HOME"

    ds_send_progress 45 "Stopping running plugin_loader service if active..."
    ds_sudo systemctl stop plugin_loader.service >/dev/null 2>&1 || true

    ds_send_progress 60 "Downloading official PluginLoader binary..."
    TMP_BIN="$DS_TMP_DIR/PluginLoader.tmp"
    if ! curl -L --fail "$DOWNLOAD_URL" -o "$TMP_BIN"; then
        ds_log "ERROR: Failed to download PluginLoader."
        exit 1
    fi

    ds_sudo cp -f "$TMP_BIN" "$LOADER_BIN"
    rm -f "$TMP_BIN"
    ds_sudo chmod +x "$LOADER_BIN"
    echo "$VERSION_TAG" | ds_sudo tee "$VERSION_FILE" >/dev/null
    ds_sudo chown root:root "$DECKY_SERVICES" "$LOADER_BIN" "$VERSION_FILE"
    ds_sudo chmod 755 "$DECKY_SERVICES" "$LOADER_BIN"

    ds_send_progress 75 "Configuring official systemd service (plugin_loader.service)..."
    SERVICE_CONTENT="[Unit]
Description=SteamDeck Plugin Loader
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Restart=always
ExecStart=${DECKY_SERVICES}/PluginLoader
WorkingDirectory=${DECKY_SERVICES}
KillSignal=SIGINT
LimitNOFILE=32768
Environment=PLUGIN_PATH=${DECKY_PLUGINS}
Environment=LOG_LEVEL=INFO
Environment=UNPRIVILEGED_PATH=${DECKY_HOME}
Environment=PRIVILEGED_PATH=${DECKY_HOME}
Environment=UNPRIVILEGED_USER=${USER_NAME}
Environment=PluginLoader_VERSION=${VERSION_TAG}

[Install]
WantedBy=multi-user.target"

    echo "$SERVICE_CONTENT" | ds_sudo tee "$SYSTEM_SERVICE_FILE" >/dev/null

    ds_send_progress 85 "Enabling Steam CEF remote debugging..."
    $DS_HOST_SPAWN touch "$HOME/.steam/steam/.cef-enable-remote-debugging" 2>/dev/null || true
    $DS_HOST_SPAWN touch "$HOME/.local/share/Steam/.cef-enable-remote-debugging" 2>/dev/null || true

    ds_send_progress 92 "Starting plugin_loader.service..."
    ds_sudo systemctl daemon-reload
    if ds_sudo systemctl enable --now plugin_loader.service; then
        ds_send_progress 100 "Decky Loader installed and running."
        ds_log "SUCCESS: Official Decky Loader ($VERSION_TAG) installed and active."
    else
        ds_log "ERROR: Failed to enable and start plugin_loader.service."
        exit 1
    fi
}

case "$OPERATION" in
    "install"|"update")
        install_decky
        ;;

    "check")
        check_host_access || exit 1
        if $DS_HOST_SPAWN systemctl is-active plugin_loader.service >/dev/null 2>&1; then
            exit 0
        elif $DS_HOST_SPAWN test -f "$LOADER_BIN"; then
            exit 0
        elif $DS_HOST_SPAWN systemctl --user is-active decky-loader >/dev/null 2>&1; then
            exit 0
        else
            exit 1
        fi
        ;;

    "remove")
        ds_log "Uninstalling Decky Loader..."
        check_host_access || exit 1

        ds_send_progress 20 "Stopping plugin_loader service..."
        cleanup_legacy_user_service
        ds_sudo systemctl disable --now plugin_loader.service >/dev/null 2>&1 || true
        ds_sudo rm -f "$SYSTEM_SERVICE_FILE"
        ds_sudo systemctl daemon-reload >/dev/null 2>&1 || true

        ds_send_progress 60 "Removing PluginLoader binary..."
        ds_sudo rm -f "$LOADER_BIN" "$VERSION_FILE"

        ds_send_progress 100 "Decky Loader uninstalled."
        ds_log "SUCCESS: Decky Loader removed (plugins preserved in $DECKY_PLUGINS)."
        ;;

    "version")
        VERSION=""
        if $DS_HOST_SPAWN test -f "$VERSION_FILE"; then
            VERSION=$($DS_HOST_SPAWN cat "$VERSION_FILE" 2>/dev/null | head -n 1 | tr -d '[:space:]')
        fi
        if [ -z "$VERSION" ] && $DS_HOST_SPAWN test -f "$SYSTEM_SERVICE_FILE"; then
            VERSION=$($DS_HOST_SPAWN grep "Environment=PluginLoader_VERSION=" "$SYSTEM_SERVICE_FILE" 2>/dev/null | sed -E 's/.*Environment=PluginLoader_VERSION=(.*)/\1/' | tr -d '[:space:]')
        fi
        if [ -z "$VERSION" ] && $DS_HOST_SPAWN test -x "$LOADER_BIN"; then
            VERSION=$($DS_HOST_SPAWN "$LOADER_BIN" --version 2>/dev/null | head -n 1 | awk '{print $NF}' | tr -d '[:space:]')
        fi
        if [ -z "$VERSION" ] && $DS_HOST_SPAWN test -f "$LEGACY_USER_SERVICE"; then
            VERSION=$($DS_HOST_SPAWN grep "Environment=PluginLoader_VERSION=" "$LEGACY_USER_SERVICE" 2>/dev/null | sed -E 's/.*Environment=PluginLoader_VERSION=(.*)/\1/' | tr -d '[:space:]')
        fi

        if [ -z "$VERSION" ]; then
            echo "0.0.0" > "$LOG_FILE"
        else
            echo "${VERSION#v}" > "$LOG_FILE"
        fi
        ;;
esac