# DeckStore Extensions System

This directory contains the extensions system for DeckStore. Extensions allow adding external functionality to the application, usually by installing applications or managing system configurations.

## Structure

*   `extensions.json`: The central registry of all available extensions.
*   `scripts/`: Contains the bash scripts executed for each extension operation.
*   `icons/`: Contains the icons displayed in the UI.
*   `deckstore_base.sh`: A library of common functions for extension scripts.

## Creating a New Extension

To add a new extension, follow these steps:

### 1. Create the Script

Create a new bash script in `scripts/`. It **MUST** source `deckstore_base.sh` and implement the standard interface.

**Template:**

```bash
#!/bin/bash
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/deckstore_base.sh"

ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="my_new_extension"

# Initialize
ds_init "$EXTENSION_ID" "$OUT_FILE"

install_ext() {
    ds_send_progress 0 "Starting..."
    # ... your installation logic ...
    ds_send_progress 100 "Done"
}

remove_ext() {
    # ... removal logic ...
}

check_ext() {
    # Exit 0 if installed, 1 if not
}

case "$ACTION" in
    install|update) install_ext ;;
    remove) remove_ext ;;
    check) check_ext ;;
    version) echo "1.0.0" > "$OUT_FILE" ;;
esac
exit 0
```

### 2. Register in `extensions.json`

Add an entry to `extensions.json`:

```json
{
  "id": "my_new_extension",
  "name": "My New Extension",
  "description": "Description of what it does.",
  "version": "1.0.0",
  "author": "Your Name",
  "script_name": "my_new_extension.sh",
  "icon": "my_icon.png",
  "tags": ["tool"],
  "repository_url": "https://github.com/...",
  "dependencies": []
}
```

### 3. Dependencies

You can define dependencies by adding their IDs to the `dependencies` array.
*   When a user installs your extension, all missing dependencies will be installed first (recursively).
*   When a user uninstalls a dependency, your extension will also be removed.

### 4. Progress Reporting

Use `ds_send_progress <percent> "<message>"` in your script to update the UI in real-time.

```bash
ds_send_progress 50 "Downloading resources..."
```

### 5. Logging

Use `ds_log "<message>"` to write to the debug log.
