#!/bin/bash

# DeckStore Base Script for Extensions
# Provides common functionality like progress reporting and dependency checking.

# Base directories
# Note: When running via flatpak-spawn --host, $HOME is the host user's home directory (/home/deck).
DS_ROOT_DIR="$HOME/.deck-store"
DS_TMP_DIR="$DS_ROOT_DIR/tmp"
DS_EXTENSIONS_DIR="$DS_ROOT_DIR/extensions"
DS_PROGRESS_BASE_DIR="$DS_TMP_DIR/progress/extensions"

# Current Extension Context
CURRENT_EXTENSION_ID=""
CURRENT_LOG_FILE=""

# Initialize the extension context
# Usage: ds_init "extension_id" "log_file_path"
ds_init() {
    CURRENT_EXTENSION_ID="$1"
    CURRENT_LOG_FILE="$2"
    
    if [ -z "$CURRENT_EXTENSION_ID" ]; then
        echo "Error: ds_init called without extension ID" >&2
        return 1
    fi

    # Create directory structure if it doesn't exist
    mkdir -p "$DS_PROGRESS_BASE_DIR"
    mkdir -p "$DS_EXTENSIONS_DIR"
    mkdir -p "$DS_TMP_DIR"
    
    # Clean up old progress file for this extension
    local progress_file="$DS_PROGRESS_BASE_DIR/${CURRENT_EXTENSION_ID}.txt"
    if [ -f "$progress_file" ]; then
        rm "$progress_file"
    fi
}

# Log to the Godot-provided log file and stdout
# Usage: ds_log "message"
ds_log() {
    local message="$1"
    # Print to stdout/stderr (captured by Godot's OS.execute in some modes, but we mainly rely on the log file)
    echo "[DS_Extension] $message"
    
    # Append to the log file if set
    if [ -n "$CURRENT_LOG_FILE" ]; then
        echo "[DS_Extension] $message" >> "$CURRENT_LOG_FILE"
    fi
}

# Send progress update
# Usage: ds_send_progress <percent> "<message>"
# percent: Integer 0-100
# message: String description
ds_send_progress() {
    if [ -z "$CURRENT_EXTENSION_ID" ]; then
        echo "Error: ds_send_progress called before ds_init" >&2
        # Fallback logging if init failed/wasn't called
        if [ -n "$CURRENT_LOG_FILE" ]; then
            echo "Error: ds_send_progress called before ds_init" >> "$CURRENT_LOG_FILE"
        fi
        return 1
    fi

    local percent="$1"
    local message="$2"
    local progress_file="$DS_PROGRESS_BASE_DIR/${CURRENT_EXTENSION_ID}.txt"

    # Write to file atomically (overwrite)
    # Format: PERCENT|MESSAGE
    echo "${percent}|${message}" > "$progress_file"
}

# Check if a command exists
ds_command_exists() {
    command -v "$1" &> /dev/null
}

# Basic dependency check
ds_check_dependencies() {
    ds_log "Checking dependencies: flatpak-spawn, curl, jq..."
    if ! ds_command_exists flatpak-spawn; then
        ds_log "ERROR: flatpak-spawn command not found. This script must be run in a Flatpak environment."
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
