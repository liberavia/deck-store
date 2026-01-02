# DeckStore Extensions System

The extensions system allows developers to add external functionality to DeckStore. Each extension is a self-contained bundle residing in its own directory within `extensions/`.

## Directory Structure

Each extension MUST be in its own subdirectory inside `extensions/`. The name of the directory does not matter, but using the extension ID is recommended for clarity.

```
extensions/
├── my_extension_id/
│   ├── extension.json   (Metadata)
│   ├── main_script.sh   (Logic)
│   └── icon.png         (Display Icon)
├── deckstore_base.sh    (Shared Library)
└── README.md
```

## Creating a New Extension

### 1. The Metadata (`extension.json`)
Create a folder and add an `extension.json` file.

```json
{
  "id": "my_extension_id",
  "name": "My Extension Name",
  "description": "A clear description of what this extension adds or manages.",
  "version": "1.0.0",
  "author": "Your Name",
  "script_name": "main_script.sh",
  "icon": "icon.png",
  "tags": ["utility", "tool"],
  "repository_url": "https://github.com/user/repo",
  "dependencies": ["other_extension_id"]
}
```
*   **id**: Unique identifier (string).
*   **script_name**: The filename of your bash script within the same folder.
*   **icon**: The filename of your icon within the same folder.
*   **dependencies**: Array of IDs of other extensions that MUST be installed for this one to work.

### 2. The Logic (`main_script.sh`)
Your script handles all operations. It **MUST** source `../deckstore_base.sh` to access progress and logging functions.

**Full Template:**

```bash
#!/bin/bash
# 1. Setup paths
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/../deckstore_base.sh"

# 2. Get arguments from DeckStore
ACTION="$1"
OUT_FILE="$2"
EXTENSION_ID="my_extension_id"

# 3. Initialize DeckStore Context
ds_init "$EXTENSION_ID" "$OUT_FILE"

install_ext() {
    ds_send_progress 0 "Starting installation..."
    ds_log "Installing..."
    
    # Perform your logic (e.g., flatpak install, file copy)
    # Use ds_send_progress to update the UI
    ds_send_progress 50 "Halfway there..."
    
    # Always end with 100%
    ds_send_progress 100 "Installation Complete"
}

remove_ext() {
    ds_send_progress 0 "Preparing removal..."
    # Cleanup logic
    ds_send_progress 100 "Removal Complete"
}

update_ext() {
    ds_log "Update requested..."
    # Usually, an update is just a clean re-installation
    install_ext
}

check_ext() {
    # DeckStore calls this to see if the extension is currently active/installed.
    # Exit with 0 if installed, 1 if not.
    if [ -f "$HOME/.my_tool_check" ]; then
        exit 0
    else
        exit 1
    fi
}

case "$ACTION" in
    install) install_ext ;;
    update)  update_ext ;;
    remove)  remove_ext ;;
    check)   check_ext ;;
    version) echo "1.0.0" > "$OUT_FILE" ;;
    *)       exit 2 ;;
esac
exit 0
```

## Built-in Functions (`deckstore_base.sh`)

*   `ds_init "id" "logfile"`: Initializes the environment. Call this first.
*   `ds_log "message"`: Writes a timestamped message to the DeckStore log.
*   `ds_send_progress <percent> "message"`: Updates the real-time progress bar and status text in the UI (0-100).
*   `ds_check_dependencies`: Automatically checks for `curl`, `jq`, and `flatpak-spawn`.

## Behavior Notes

*   **Recursion:** If you define dependencies, DeckStore will automatically prompt the user to install them before your extension. Conversely, if a dependency is removed, your extension will also be flagged for removal.
*   **Updates:** DeckStore checks the `repository_url` (GitHub only) for new releases. If a newer version is found, the "Update" button appears.
