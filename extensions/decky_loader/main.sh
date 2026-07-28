#!/bin/bash

source "$(dirname "$0")/../deckstore_base.sh"

OPERATION="$1"
LOG_FILE="$2"
EXTENSION_ID="decky_loader"

DECKY_HOME="$HOME/homebrew"
DECKY_SERVICES="$DECKY_HOME/services"
DECKY_DIR="$DECKY_SERVICES/decky-loader"
DECKY_PLUGINS="$DECKY_HOME/plugins"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/decky-loader.service"

ds_init "$EXTENSION_ID" "$LOG_FILE"

check_host_access() {
    if ! $DS_HOST_SPAWN true 2>/dev/null; then
        ds_log "ERROR: Cannot execute commands on host. Missing permissions?"
        return 1
    fi
    return 0
}

get_latest_release_info() {
    curl -s https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases/latest
}

install_decky() {
    ds_log "Starting Manual Decky Loader installation..."
    check_host_access || exit 1
    
    ds_send_progress 10 "Fetching latest release info..."
    RELEASE_JSON=$(get_latest_release_info)
    
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name=="PluginLoader") | .browser_download_url')
    VERSION_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
    
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        ds_log "ERROR: Could not find PluginLoader asset in latest release."
        exit 1
    fi
    
    ds_log "Latest version: $VERSION_TAG"
    ds_send_progress 30 "Creating directories..."
    
    $DS_HOST_SPAWN mkdir -p "$DECKY_DIR"
    $DS_HOST_SPAWN mkdir -p "$DECKY_PLUGINS"
    $DS_HOST_SPAWN mkdir -p "$SYSTEMD_USER_DIR"
    
    ds_send_progress 50 "Downloading PluginLoader..."
    
    if ! $DS_HOST_SPAWN curl -L "$DOWNLOAD_URL" -o "$DECKY_DIR/PluginLoader"; then
        ds_log "ERROR: Download failed."
        exit 1
    fi
    
    $DS_HOST_SPAWN chmod +x "$DECKY_DIR/PluginLoader"
    
    ds_send_progress 70 "Creating Systemd Service..."
    
    SERVICE_CONTENT="[Unit]
Description=Decky Loader
Documentation=https://github.com/SteamDeckHomebrew/decky-loader

[Service]
Type=simple
ExecStart=%h/homebrew/services/decky-loader/PluginLoader
Restart=always
Environment=HOMEBREW_PLUGIN_PATH=%h/homebrew/plugins
Environment=HOMEBREW_DATA_PATH=%h/homebrew/data
Environment=PluginLoader_VERSION=$VERSION_TAG

[Install]
WantedBy=default.target"

    ENCODED_CONTENT=$(echo "$SERVICE_CONTENT" | base64 -w 0)
    $DS_HOST_SPAWN sh -c "echo '$ENCODED_CONTENT' | base64 -d > '$SERVICE_FILE'"
    
    ds_send_progress 80 "Enabling CEF Debugging for Steam..."
    $DS_HOST_SPAWN touch "$HOME/.steam/steam/.cef-enable-remote-debugging"
    
    ds_send_progress 90 "Enabling Service..."
    
    $DS_HOST_SPAWN systemctl --user daemon-reload
    if $DS_HOST_SPAWN systemctl --user enable --now decky-loader; then
        ds_send_progress 100 "Installation completed."
        ds_log "SUCCESS: Decky Loader installed and started."
        
    else
        ds_log "ERROR: Failed to enable systemd service."
        exit 1
    fi
}

case "$OPERATION" in
    "install")
        install_decky
        ;;
        
    "check")
        check_host_access || exit 1
        if $DS_HOST_SPAWN systemctl --user is-active decky-loader > /dev/null 2>&1; then
            exit 0
        elif $DS_HOST_SPAWN test -f "$DECKY_DIR/PluginLoader"; then
             exit 0
        else
             exit 1
        fi
        ;;
    
    "remove")
        ds_log "Uninstalling Decky Loader..."
        check_host_access || exit 1
        
        ds_send_progress 20 "Stopping service..."
        $DS_HOST_SPAWN systemctl --user disable --now decky-loader
        $DS_HOST_SPAWN rm "$SERVICE_FILE"
        $DS_HOST_SPAWN systemctl --user daemon-reload
        
        ds_send_progress 50 "Removing files..."
        $DS_HOST_SPAWN rm "$DECKY_DIR/PluginLoader"
        
        ds_send_progress 100 "Uninstalled."
        ds_log "SUCCESS: Decky Loader uninstalled (Plugins kept in $DECKY_PLUGINS)."
        ;;
        
    "update")
         ds_log "Updating Decky Loader..."
         install_decky
         ;;
        
    "version")
        VERSION=$($DS_HOST_SPAWN sh -c 'grep "Environment=PluginLoader_VERSION=" "$HOME/.config/systemd/user/decky-loader.service"' 2>/dev/null | sed -E 's/.*Environment=PluginLoader_VERSION=(.*)/\1/')
        
        if [ -z "$VERSION" ]; then
             echo "0.0.0" > "$LOG_FILE"
        else
             echo "${VERSION#v}" > "$LOG_FILE"
        fi
        ;;
esac