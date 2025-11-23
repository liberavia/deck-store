#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

ACTION="$1"
FLATPAK_APP_ID="io.github.liberavia.steamshortcutmanager"
GITHUB_REPO_OWNER="liberavia" # Assuming this is the owner for the steam-shortcut-manager
GITHUB_REPO_NAME="steam-shortcut-manager"

FLATPAK_SOURCE_DIR="${HOME}/.deck-store/extensions/steam_shortcut_manager_files/"
FLATPAK_MANIFEST_FILE="${FLATPAK_APP_ID}.json"
VERSION_FILE="${FLATPAK_SOURCE_DIR}/VERSION" # File to store installed version

# Log-Funktion
log() {
    echo "[SSM_Extension_Script] $1"
}

# Checks if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

check_dependencies() {
    log "Checking dependencies: flatpak, flatpak-builder, curl, jq, unzip..."
    if ! command_exists flatpak; then
        log "ERROR: flatpak command not found. Please install flatpak."
        exit 1
    fi
    if ! command_exists flatpak-builder; then
        log "ERROR: flatpak-builder command not found. Please install flatpak-builder."
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
    if ! command_exists unzip; then
        log "ERROR: unzip command not found. Please install unzip."
        exit 1
    fi
    log "All dependencies found."
}

get_installed_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "0.0.0" # Default to 0.0.0 if version file doesn't exist
    fi
}

set_installed_version() {
    local version="$1"
    mkdir -p "$FLATPAK_SOURCE_DIR" # Ensure directory exists
    echo "$version" > "$VERSION_FILE"
    log "Installed version set to: $version"
}

install_ssm() {
    log "Starting installation of Steam Shortcut Manager Flatpak..."
    check_dependencies

    mkdir -p "$FLATPAK_SOURCE_DIR" # Ensure directory exists

    # Check if source code already exists, if not, clone.
    # This currently relies on the git clone method, which might not be ideal for versioned releases.
    # We will adjust this for the 'update' command to handle specific releases.
    if [ ! -d "${FLATPAK_SOURCE_DIR}/.git" ]; then
        log "Cloning repository to $FLATPAK_SOURCE_DIR..."
        git clone https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}.git "$FLATPAK_SOURCE_DIR" || { log "ERROR: Failed to clone repository."; exit 1; }
    else
        log "Repository already exists at $FLATPAK_SOURCE_DIR. Skipping clone."
    fi

    if [ ! -f "${FLATPAK_SOURCE_DIR}/${FLATPAK_MANIFEST_FILE}" ]; then
        log "ERROR: Flatpak manifest ${FLATPAK_MANIFEST_FILE} not found in ${FLATPAK_SOURCE_DIR}"
        exit 1
    }

    log "Building Steam Shortcut Manager Flatpak from source dir: ${FLATPAK_SOURCE_DIR}"
    cd "$FLATPAK_SOURCE_DIR" || { log "ERROR: Could not change to Flatpak source directory."; exit 1; }
    
    if [ -d "build-dir" ]; then
        log "Cleaning up old build-dir..."
        rm -rf "build-dir"
    }

    log "Running flatpak-builder..."
    # Der --user --install Teil ist wichtig für die Installation
    flatpak-builder --user --install --force-clean build-dir "$FLATPAK_MANIFEST_FILE"
    
    if flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
        log "SUCCESS: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) installed successfully."
        # After successful install, update the version file
        set_installed_version "1.0.0" # Placeholder, this should ideally come from the release
    else
        log "ERROR: Steam Shortcut Manager Flatpak installation failed or was not found after build."
        exit 1
    }
}

remove_ssm() {
    log "Starting removal of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    check_dependencies
    if flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
        flatpak uninstall --user --assumeyes "$FLATPAK_APP_ID"
        log "SUCCESS: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) uninstalled."
        # Remove version file upon uninstallation
        if [ -f "$VERSION_FILE" ]; then
            rm "$VERSION_FILE"
            log "Removed version file: $VERSION_FILE"
        }
    else
        log "INFO: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed."
    }
}

check_ssm() {
    log "Checking installation status of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    check_dependencies
    if flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
        log "INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is installed. Version: $(get_installed_version)"
        exit 0
    else
        log "NOT_INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed."
        exit 1
    }
}

update_ssm() {
    log "Checking for updates for Steam Shortcut Manager..."
    check_dependencies

    local current_version=$(get_installed_version)
    log "Currently installed version: $current_version"

    local api_url="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases/latest"
    local response=$(curl -s "$api_url")
    local latest_tag_name=$(echo "$response" | jq -r '.tag_name')
    local download_url=""

    if [ "$latest_tag_name" == "null" ] || [ -z "$latest_tag_name" ]; then
        log "ERROR: Could not fetch latest release information from GitHub API."
        exit 1
    fi
    
    # Extract only the numeric part of the version string (e.g., "v1.2.3" -> "1.2.3")
    latest_version=$(echo "$latest_tag_name" | sed 's/^v//')
    log "Latest available version: $latest_version"

    # Simple version comparison (major.minor.patch)
    IFS='.' read -r -a current_parts <<< "$current_version"
    IFS='.' read -r -a latest_parts <<< "$latest_version"

    if ((${latest_parts[0]} > ${current_parts[0]})) || \
       ((${latest_parts[0]} == ${current_parts[0]} && ${latest_parts[1]} > ${current_parts[1]})) || \
       ((${latest_parts[0]} == ${current_parts[0]} && ${latest_parts[1]} == ${current_parts[1]} && ${latest_parts[2]} > ${current_parts[2]})); then
        log "New version ($latest_version) available. Starting update..."

        download_url=$(echo "$response" | jq -r ".assets[] | select(.name == \"${FLATPAK_APP_ID}.zip\") | .browser_download_url") # Assuming the asset name matches FLATPAK_APP_ID.zip

        if [ "$download_url" == "null" ] || [ -z "$download_url" ]; then
            log "ERROR: Could not find download URL for asset '${FLATPAK_APP_ID}.zip' in the latest release."
            exit 1
        fi

        log "Downloading update from: $download_url"
        local temp_zip="/tmp/${FLATPAK_APP_ID}_${latest_version}.zip"
        curl -L -o "$temp_zip" "$download_url" || { log "ERROR: Failed to download update."; exit 1; }

        log "Extracting update to $FLATPAK_SOURCE_DIR..."
        rm -rf "$FLATPAK_SOURCE_DIR"/* # Clear existing source
        unzip -o "$temp_zip" -d "$FLATPAK_SOURCE_DIR" || { log "ERROR: Failed to extract update."; rm "$temp_zip"; exit 1; }
        rm "$temp_zip"
        
        log "Update downloaded and extracted. Re-running installation..."
        cd "$FLATPAK_SOURCE_DIR" || { log "ERROR: Could not change to Flatpak source directory for re-installation."; exit 1; }
        
        if [ -d "build-dir" ]; then
            log "Cleaning up old build-dir..."
            rm -rf "build-dir"
        }

        log "Running flatpak-builder for update..."
        flatpak-builder --user --install --force-clean build-dir "$FLATPAK_MANIFEST_FILE"
        
        if flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
            log "SUCCESS: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) updated successfully to version $latest_version."
            set_installed_version "$latest_version"
        else
            log "ERROR: Steam Shortcut Manager Flatpak update failed or was not found after build."
            exit 1
        }
    else
        log "Steam Shortcut Manager is already up to date."
    fi
}

# Hauptlogik des Skripts
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
        get_installed_version
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
