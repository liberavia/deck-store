#!/bin/bash


DS_ROOT_DIR="$HOME/.deck-store"
DS_TMP_DIR="$DS_ROOT_DIR/tmp"
DS_EXTENSIONS_DIR="$DS_ROOT_DIR/extensions"
DS_PROGRESS_BASE_DIR="$DS_TMP_DIR/progress/extensions"

CURRENT_EXTENSION_ID=""
CURRENT_LOG_FILE=""

ds_init() {
    CURRENT_EXTENSION_ID="$1"
    CURRENT_LOG_FILE="$2"
    
    if [ -z "$CURRENT_EXTENSION_ID" ]; then
        echo "Error: ds_init called without extension ID" >&2
        return 1
    fi

    mkdir -p "$DS_PROGRESS_BASE_DIR"
    mkdir -p "$DS_EXTENSIONS_DIR"
    mkdir -p "$DS_TMP_DIR"
    
    local progress_file="$DS_PROGRESS_BASE_DIR/${CURRENT_EXTENSION_ID}.txt"
    if [ -f "$progress_file" ]; then
        rm "$progress_file"
    fi
}

ds_log() {
    local message="$1"
    echo "[DS_Extension] $message"
    
    if [ -n "$CURRENT_LOG_FILE" ]; then
        echo "[DS_Extension] $message" >> "$CURRENT_LOG_FILE"
    fi
}

ds_send_progress() {
    if [ -z "$CURRENT_EXTENSION_ID" ]; then
        echo "Error: ds_send_progress called before ds_init" >&2
        if [ -n "$CURRENT_LOG_FILE" ]; then
            echo "Error: ds_send_progress called before ds_init" >> "$CURRENT_LOG_FILE"
        fi
        return 1
    fi

    local percent="$1"
    local message="$2"
    local progress_file="$DS_PROGRESS_BASE_DIR/${CURRENT_EXTENSION_ID}.txt"

    echo "${percent}|${message}" > "$progress_file"
}

if [ -f /.flatpak-info ]; then
    DS_FLATPAK_CMD="flatpak-spawn --host flatpak"
    DS_HOST_SPAWN="flatpak-spawn --host"
else
    DS_FLATPAK_CMD="flatpak"
    DS_HOST_SPAWN=""
fi

ds_command_exists() {
    command -v "$1" &> /dev/null
}

ds_check_dependencies() {
    ds_log "Checking dependencies: curl, jq, and flatpak..."
    
    local base_cmd=$(echo "$DS_FLATPAK_CMD" | awk '{print $1}')
    if ! ds_command_exists "$base_cmd"; then
        ds_log "ERROR: $base_cmd command not found. Cannot manage Flatpaks."
        exit 1
    fi
    
    if ! ds_command_exists curl; then
        ds_log "ERROR: curl command not found. Please install curl."
        exit 1
    fi
    if ! ds_command_exists jq; then
        ds_log "ERROR: jq command not found. Please install jq (JSON processor)."
        exit 1
    fi
    ds_log "All dependencies found."
}
