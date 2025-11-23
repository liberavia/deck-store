#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

ACTION="$1"
OUT_FILE="$2"

# Log-Funktion: Leitet die Ausgabe in die von Godot angegebene Log-Datei um.
log() {
    echo "[SSM_Extension_Script] $1" >> "$OUT_FILE"
}

FLATPAK_APP_ID="io.github.liberavia.steamshortcutmanager"
GITHUB_REPO_OWNER="liberavia"
GITHUB_REPO_NAME="steam-shortcut-manager"

VERSION_FILE="${HOME}/.deck-store/extensions/ssm.version"

# Checks if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

check_dependencies() {
    log "Checking dependencies: flatpak-spawn, curl, jq..."
    if ! command_exists flatpak-spawn; then
        log "ERROR: flatpak-spawn command not found. This script must be run in a Flatpak environment."
        exit 1
    fi
    if ! command_exists curl; then
        log "ERROR: curl command not found. Please install curl."
        exit 1
    fi
    if ! command_exists jq; then
        log "ERROR: jq command not found. Please install jq (JSON processor)."
        exit 1
    fi
    log "All dependencies found."
}

# Gibt die installierte Version in die Log-Datei aus.
# WICHTIG: Diese Funktion wird nur für den 'version'-Befehl verwendet und schreibt NUR die Version.
get_installed_version_for_file() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE" > "$OUT_FILE"
    else
        echo "0.0.0" > "$OUT_FILE"
    fi
}

# Holt die Version für interne Skript-Nutzung, ohne die Log-Datei zu beeinflussen.
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
    log "Installed version set to: $version"
}

install_ssm() {
    log "Starting installation of pre-built Steam Shortcut Manager..."
    check_dependencies
    
    log "Fetching latest release information from GitHub..."
    local api_url="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/latest"
    local response=$(curl -s "$api_url")
    local latest_tag_name=$(echo "$response" | jq -r '.tag_name')

    if [ "$latest_tag_name" == "null" ] || [ -z "$latest_tag_name" ]; then
        log "ERROR: Could not fetch latest release information from GitHub API."
        exit 1
    fi
    local latest_version=$(echo "$latest_tag_name" | sed 's/^v//')
    log "Latest available version is $latest_version. Proceeding with installation."

    local bundle_filename="${FLATPAK_APP_ID}.flatpak"
    local download_url="https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/download/${latest_tag_name}/${bundle_filename}"
    
    # Download to a shared location in the user's home directory
    local temp_dir="${HOME}/.deck-store/tmp"
    mkdir -p "$temp_dir"
    local temp_bundle_path="${temp_dir}/${bundle_filename}"

    log "Downloading to: $temp_bundle_path"
    curl -L -o "$temp_bundle_path" "$download_url" || { log "ERROR: Failed to download bundle from $download_url"; exit 1; }

    log "Installing bundle..."
    flatpak-spawn --host flatpak install --user -y "$temp_bundle_path" >> "$OUT_FILE" 2>&1
    
    rm "$temp_bundle_path"

    if flatpak-spawn --host flatpak info "${FLATPAK_APP_ID}" &> /dev/null; then
        log "SUCCESS: Steam Shortcut Manager Flatpak (${FLATPAK_APP_ID}) installed successfully."
        set_installed_version "$latest_version"
    else
        log "ERROR: Steam Shortcut Manager Flatpak installation failed or was not found after install."
        if [ -f "$VERSION_FILE" ]; then
            rm "$VERSION_FILE"
            log "Removed stale version file."
        fi
        exit 1
    fi
}

remove_ssm() {
    log "Starting removal of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    check_dependencies
    if flatpak-spawn --host flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
        flatpak-spawn --host flatpak uninstall --user --assumeyes "$FLATPAK_APP_ID"
        log "SUCCESS: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) uninstalled."
        if [ -f "$VERSION_FILE" ]; then
            rm "$VERSION_FILE"
            log "Removed version file: $VERSION_FILE"
        fi
    else
        log "INFO: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed."
    fi
}

check_ssm() {
    log "Checking installation status of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    check_dependencies

    local version="0.0.0"
    if [ -f "$VERSION_FILE" ]; then
        version=$(cat "$VERSION_FILE")
    fi

    if flatpak-spawn --host flatpak info "$FLATPAK_APP_ID" &> /dev/null && [ "$version" != "0.0.0" ]; then
        log "INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is installed. Version: $version"
        exit 0
    else
        log "NOT_INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed or version is invalid."
        # Clean up potentially stale file
        if [ -f "$VERSION_FILE" ]; then
            rm "$VERSION_FILE"
            log "Removed stale or invalid version file."
        fi
        exit 1
    fi
}

update_ssm() {
    log "Update requested. Fetching and installing latest version..."
    install_ssm
}

# --- Main Logic ---
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
        log "Error: Invalid action '$ACTION'. Use 'install', 'remove', 'check', 'version', or 'update'."
        exit 2
        ;; 
esac

exit 0