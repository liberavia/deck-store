#!/bin/bash
# Decky Loader Extension Script (Manual User-Mode Install)

# Import base functions
source "$(dirname "$0")/../deckstore_base.sh"

OPERATION="$1"
LOG_FILE="$2"
EXTENSION_ID="decky_loader"

# Base paths (on Host)
DECKY_HOME="$HOME/homebrew"
DECKY_SERVICES="$DECKY_HOME/services"
DECKY_DIR="$DECKY_SERVICES/decky-loader"
DECKY_PLUGINS="$DECKY_HOME/plugins"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/decky-loader.service"

ds_init "$EXTENSION_ID" "$LOG_FILE"

check_host_access() {
    if ! flatpak-spawn --host true 2>/dev/null; then
        ds_log "ERROR: Cannot execute commands on host. Missing permissions?"
        return 1
    fi
    return 0
}

get_latest_release_info() {
    # Returns JSON string
    curl -s https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases/latest
}

install_decky() {
    ds_log "Starting Manual Decky Loader installation..."
    check_host_access || exit 1
    
    ds_send_progress 10 "Fetching latest release info..."
    RELEASE_JSON=$(get_latest_release_info)
    
    # Parse URL and Version
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r '.assets[] | select(.name=="PluginLoader") | .browser_download_url')
    VERSION_TAG=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
    
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        ds_log "ERROR: Could not find PluginLoader asset in latest release."
        exit 1
    fi
    
    ds_log "Latest version: $VERSION_TAG"
    ds_send_progress 30 "Creating directories..."
    
    # Create directories on host
    flatpak-spawn --host mkdir -p "$DECKY_DIR"
    flatpak-spawn --host mkdir -p "$DECKY_PLUGINS"
    flatpak-spawn --host mkdir -p "$SYSTEMD_USER_DIR"
    
    ds_send_progress 50 "Downloading PluginLoader..."
    
    # Download binary to host
    if ! flatpak-spawn --host curl -L "$DOWNLOAD_URL" -o "$DECKY_DIR/PluginLoader"; then
        ds_log "ERROR: Download failed."
        exit 1
    fi
    
    flatpak-spawn --host chmod +x "$DECKY_DIR/PluginLoader"
    
    ds_send_progress 70 "Creating Systemd Service..."
    
    # Create Service File Content
    # Using 'cat' trick to write to host file
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

    # We use base64 to safely transport the content through flatpak-spawn
    ENCODED_CONTENT=$(echo "$SERVICE_CONTENT" | base64 -w 0)
    flatpak-spawn --host sh -c "echo '$ENCODED_CONTENT' | base64 -d > '$SERVICE_FILE'"
    
    ds_send_progress 80 "Enabling Service..."
    
    # Reload daemon and enable service
    flatpak-spawn --host systemctl --user daemon-reload
    if flatpak-spawn --host systemctl --user enable --now decky-loader; then
        ds_send_progress 100 "Installation completed."
        ds_log "SUCCESS: Decky Loader installed and started."
        
        # Write version file locally for our check
        # We can't easily write to host only, so we rely on 'version' command fetching from running process or file
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
        if flatpak-spawn --host systemctl --user is-active decky-loader > /dev/null 2>&1; then
            exit 0
        elif flatpak-spawn --host test -f "$DECKY_DIR/PluginLoader"; then
             # Binary exists but maybe not running? Return true as 'installed' but maybe issue warning?
             # For ExtensionsManager, exit 0 means installed.
             exit 0
        else
             exit 1
        fi
        ;;
    
    "remove")
        ds_log "Uninstalling Decky Loader..."
        check_host_access || exit 1
        
        ds_send_progress 20 "Stopping service..."
        flatpak-spawn --host systemctl --user disable --now decky-loader
        flatpak-spawn --host rm "$SERVICE_FILE"
        flatpak-spawn --host systemctl --user daemon-reload
        
        ds_send_progress 50 "Removing files..."
        # Optional: Ask user if they want to keep plugins? For now we remove the loader binary but keep data?
        # Standard uninstall usually removes everything. Let's be safe and remove loader binary.
        flatpak-spawn --host rm "$DECKY_DIR/PluginLoader"
        # We keep plugins folder to not delete user data accidentally
        
        ds_send_progress 100 "Uninstalled."
        ds_log "SUCCESS: Decky Loader uninstalled (Plugins kept in $DECKY_PLUGINS)."
        ;;
        
    "update")
         ds_log "Updating Decky Loader..."
         # Update is same as install (overwrite binary)
         install_decky
         ;;
        
    "version")
        # Extract version using host shell to resolve paths correctly
        # We rely on $HOME resolving correctly on host side if we use sh -c
        VERSION=$(flatpak-spawn --host sh -c 'grep "Environment=PluginLoader_VERSION=" "$HOME/.config/systemd/user/decky-loader.service"' 2>/dev/null | sed -E 's/.*Environment=PluginLoader_VERSION=(.*)/\1/')
        
        if [ -z "$VERSION" ]; then
             echo "0.0.0" > "$LOG_FILE"
        else
             # Remove 'v' prefix if present
             echo "${VERSION#v}" > "$LOG_FILE"
        fi
        ;;
esac