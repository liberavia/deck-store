#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

ACTION="$1"
FLATPAK_APP_ID="io.github.liberavia.steamshortcutmanager"

FLATPAK_SOURCE_DIR="${HOME}/.deck-store/extensions/steam_shortcut_manager_files/"
FLATPAK_MANIFEST_FILE="${FLATPAK_APP_ID}.json"

# Log-Funktion
log() {
    echo "[SSM_Extension_Script] $1"
}

check_dependencies() {
    log "Checking dependencies: flatpak, flatpak-builder..."
    if ! command -v flatpak &> /dev/null; then
        log "ERROR: flatpak command not found. Please install flatpak."
        exit 1
    fi
    if ! command -v flatpak-builder &> /dev/null; then
        log "ERROR: flatpak-builder command not found. Please install flatpak-builder."
        exit 1
    fi
    log "Dependencies found."
}

install_ssm() {
    log "Starting installation of Steam Shortcut Manager Flatpak..."
    check_dependencies

    if [ ! -d "$FLATPAK_SOURCE_DIR" ]; then
        log "ERROR: Flatpak source directory not found at $FLATPAK_SOURCE_DIR"
        log "Attempting to clone from GitHub..."
        git clone https://github.com/liberavia/steam-shortcut-manager.git "$FLATPAK_SOURCE_DIR" || { log "ERROR: Failed to clone repository."; exit 1; }
    fi

    if [ ! -f "${FLATPAK_SOURCE_DIR}/${FLATPAK_MANIFEST_FILE}" ]; then
        log "ERROR: Flatpak manifest ${FLATPAK_MANIFEST_FILE} not found in ${FLATPAK_SOURCE_DIR}"
        exit 1
    fi

    log "Building Steam Shortcut Manager Flatpak from source dir: ${FLATPAK_SOURCE_DIR}"
    cd "$FLATPAK_SOURCE_DIR" || { log "ERROR: Could not change to Flatpak source directory."; exit 1; }
    
    if [ -d "build-dir" ]; then
        log "Cleaning up old build-dir..."
        rm -rf "build-dir"
    fi

    log "Running flatpak-builder..."
    # Der --user --install Teil ist wichtig für die Installation
    flatpak-builder --user --install --force-clean build-dir "$FLATPAK_MANIFEST_FILE"
    
    if flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
        log "SUCCESS: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) installed successfully."
    else
        log "ERROR: Steam Shortcut Manager Flatpak installation failed or was not found after build."
        exit 1
    fi
}

remove_ssm() {
    log "Starting removal of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    check_dependencies
    if flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
        flatpak uninstall --user --assumeyes "$FLATPAK_APP_ID"
        log "SUCCESS: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) uninstalled."
    else
        log "INFO: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed."
    fi
}

check_ssm() {
    log "Checking installation status of Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID)..."
    check_dependencies
    if flatpak info "$FLATPAK_APP_ID" &> /dev/null; then
        log "INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is installed."
        exit 0
    else
        log "NOT_INSTALLED: Steam Shortcut Manager Flatpak ($FLATPAK_APP_ID) is not installed."
        exit 1
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
    *)
        log "Error: Invalid action '$ACTION'. Use 'install', 'remove', or 'check'."
        exit 2
        ;;
esac

exit 0

