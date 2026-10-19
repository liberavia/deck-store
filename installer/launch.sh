#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DS_ROOT_DIR="$HOME/.deck-store"
STAGED_DIR="$DS_ROOT_DIR/tmp/staged_update"
BINARY_PATH="$SCRIPT_DIR/deck-store.x86_64"

apply_staged_update() {
    if [ -d "$STAGED_DIR" ] && [ -f "$STAGED_DIR/deck-store.x86_64" ] && [ -f "$STAGED_DIR/deck-store.pck" ]; then
        echo "[DeckStore Launcher] Applying staged update from $STAGED_DIR..."
        cp -rf "$STAGED_DIR"/* "$SCRIPT_DIR"/
        chmod +x "$SCRIPT_DIR/deck-store.x86_64"
        if [ -f "$SCRIPT_DIR/launch.sh" ]; then
            chmod +x "$SCRIPT_DIR/launch.sh"
        fi
        rm -rf "$STAGED_DIR"
        echo "[DeckStore Launcher] Update applied successfully."
    fi
}

cd "$SCRIPT_DIR" || exit 1
export DECKSTORE_WRAPPER_ACTIVE=1

while true; do
    apply_staged_update

    if [ ! -x "$BINARY_PATH" ]; then
        chmod +x "$BINARY_PATH" 2>/dev/null || true
    fi

    "$BINARY_PATH" "$@"
    EXIT_CODE=$?

    if [ "$EXIT_CODE" -eq 42 ]; then
        echo "[DeckStore Launcher] Update restart requested (exit code 42). Restarting..."
        sleep 0.5
        continue
    fi

    exit "$EXIT_CODE"
done
