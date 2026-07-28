#!/bin/bash

set -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/../deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="steam_shortcut_manager_installer"

ds_init "$EXTENSION_ID" "$OUT_FILE"

FLATPAK_APP_ID="io.github.liberavia.steamshortcutmanager"
GITHUB_REPO_OWNER="liberavia"
GITHUB_REPO_NAME="steam-shortcut-manager"

VERSION_FILE="${HOME}/.deck-store/extensions/ssm.version"

get_installed_version_for_file() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" > "$OUT_FILE"
    else
        echo "0.0.0" > "$OUT_FILE"
    fi
}

get_installed_version_for_var() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "0.0.0"
    fi
}

set_installed_version() {
    local version="$1"
    mkdir -p "$(dirname "$VERSION_FILE")"
    echo "$version" > "$VERSION_FILE"
    ds_log "Installed version set to: $version"
}

install_ssm() {
    ds_send_progress 0 "Starting installation..."
    ds_log "Starting installation of pre-built Steam Shortcut Manager..."
    ds_check_dependencies
    
    ds_send_progress 10 "Fetching release info..."
    ds_log "Fetching latest release information from GitHub..."
    local api_url="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/latest"
    local response=$(curl -s "$api_url")
    local latest_tag_name=$(echo "$response" | jq -r '.tag_name')

    if [ "$latest_tag_name" == "null" ] || [ -z "$latest_tag_name" ]; then
        ds_log "ERROR: Could not fetch latest release information from GitHub API."
        exit 1
    fi
    local latest_version=$(echo "$latest_tag_name" | sed 's/^v//')
    ds_log "Latest available version is $latest_version. Proceeding with installation."

    local bundle_filename="${FLATPAK_APP_ID}.flatpak"
    local download_url="https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/download/${latest_tag_name}/${bundle_filename}"
    
    local temp_dir="${HOME}/.deck-store/tmp"
    mkdir -p "$temp_dir"
    local temp_bundle_path="${temp_dir}/${bundle_filename}"

    ds_send_progress 30 "Downloading Bundle..."
    ds_log "Downloading to: $temp_bundle_path"
    curl -L -o "$temp_bundle_path" "$download_url" || { ds_log "ERROR: Failed to download bundle from $download_url"; exit 1; }

    ds_send_progress 60 "Installing Flatpak..."
    ds_log "Installing bundle..."

    if $DS_FLATPAK_CMD info "${FLATPAK_APP_ID}" &> /dev/null; then
         ds_log "Removing existing version to ensure clean install..."
         $DS_FLATPAK_CMD uninstall --user --assumeyes "${FLATPAK_APP_ID}" >> "$OUT_FILE" 2>&1
    fi

    $DS_FLATPAK_CMD install --user -y "$temp_bundle_path" >> "$OUT_FILE" 2>&1
    
    rm "$temp_bundle_path"

    ds_send_progress 90 "Verifying installation..."
    if $DS_FLATPAK_CMD info "${FLATPAK_APP_ID}" &> /dev/null; then
        ds_log "SUCCESS: Steam Shortcut Manager Flatpak (${FLATPAK_APP_ID}) installed successfully."
        set_installed_version "$latest_version"
        ds_send_progress 100 "Installation Complete"
    else
        ds_log "ERROR: Steam Shortcut Manager Flatpak installation failed or was not found after install."
        if [ -f "$VERSION_FILE" ]; then
            rm "$VERSION_FILE"
            ds_log "Removed stale version file."
        fi
        exit 1
    fi
}

remove_ssm() {
    ds_send_progress 0 "Starting removal..."
    ds_log "Starting removal of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    ds_check_dependencies
    
    ds_send_progress 20 "Checking installation..."
    if $DS_FLATPAK_CMD info "$FLATPAK_APP_ID" &> /dev/null; then
        ds_send_progress 50 "Uninstalling..."
        $DS_FLATPAK_CMD uninstall --user --assumeyes "$FLATPAK_APP_ID"
        ds_log "SUCCESS: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) uninstalled."
        if [ -f "$VERSION_FILE" ]; then
            rm "$VERSION_FILE"
            ds_log "Removed version file: $VERSION_FILE"
        fi
        ds_send_progress 100 "Removal Complete"
    else
        ds_log "INFO: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed."
        ds_send_progress 100 "Not Installed"
    fi
}

check_ssm() {
    ds_log "Checking installation status of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    ds_check_dependencies

    local version="0.0.0"
    if [ -f "$VERSION_FILE" ]; then
        version=$(cat "$VERSION_FILE")
    fi

    if $DS_FLATPAK_CMD info "$FLATPAK_APP_ID" &> /dev/null && [ "$version" != "0.0.0" ]; then
        ds_log "INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is installed. Version: $version"
        exit 0
    else
        ds_log "NOT_INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed or version is invalid."
        if [ -f "$VERSION_FILE" ]; then
            rm "$VERSION_FILE"
            ds_log "Removed stale or invalid version file."
        fi
        exit 1
    fi
}

update_ssm() {
    ds_log "Update requested. Fetching and installing latest version..."
    install_ssm
}

case "$ACTION" in
    install)
        install_ssm
        ;; 
    remove)
        remove_ssm
        ;; 
    check)
        check_ssm
        ;; 
    version)
        get_installed_version_for_file
        ;; 
    update)
        update_ssm
        ;; 
    *)
        ds_log "Error: Invalid action '$ACTION'. Use 'install', 'remove', 'check', 'version', or 'update'."
        exit 2
        ;; 
esac

exit 0