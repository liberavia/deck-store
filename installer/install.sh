#!/bin/bash

set -e

DS_ROOT_DIR="$HOME/.deck-store"
DS_BIN_DIR="$DS_ROOT_DIR/bin"
DS_TMP_DIR="$DS_ROOT_DIR/tmp"
DS_EXT_DIR="$DS_ROOT_DIR/extensions"
GITHUB_REPO="liberavia/deck-store"
SSM_REPO="liberavia/steam-shortcut-manager"
SSM_APP_ID="io.github.liberavia.steamshortcutmanager"

mkdir -p "$DS_BIN_DIR" "$DS_TMP_DIR" "$DS_EXT_DIR"
LOG_FILE="$DS_TMP_DIR/install.log"
: > "$LOG_FILE"

log() {
    echo "[DeckStore Installer] $1" | tee -a "$LOG_FILE"
}

run_installation() {
    echo "10"
    echo "# Creating directories and checking Flathub remote..."
    log "Ensuring user Flathub remote exists..."
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$LOG_FILE" 2>&1 || true

    echo "25"
    echo "# Fetching latest DeckStore release from GitHub..."
    log "Querying GitHub API for latest DeckStore release..."
    RELEASE_JSON=$(curl -sL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")
    LATEST_TAG=$(echo "$RELEASE_JSON" | grep -m 1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -B 3 -A 5 '"name": "deck-store-linux.zip"' | grep '"browser_download_url":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/deck-store-linux.zip"
    fi

    log "Latest tag: ${LATEST_TAG:-unknown}, URL: $DOWNLOAD_URL"

    echo "40"
    echo "# Downloading DeckStore (${LATEST_TAG:-latest})..."
    ZIP_FILE="$DS_TMP_DIR/deck-store-linux.zip"
    rm -f "$ZIP_FILE"
    if ! curl -L --fail -o "$ZIP_FILE" "$DOWNLOAD_URL" >> "$LOG_FILE" 2>&1; then
        log "ERROR: Failed to download DeckStore release archive."
        exit 1
    fi

    echo "60"
    echo "# Extracting DeckStore files..."
    unzip -o -q "$ZIP_FILE" -d "$DS_BIN_DIR"
    rm -f "$ZIP_FILE"

    if [ -n "$LATEST_TAG" ] && [ ! -f "$DS_BIN_DIR/version.txt" ]; then
        echo "$LATEST_TAG" > "$DS_BIN_DIR/version.txt"
    fi

    rm -f "$DS_BIN_DIR/steam_appid.txt"

    if [ ! -f "$DS_BIN_DIR/launch.sh" ]; then
        cat << 'EOF' > "$DS_BIN_DIR/launch.sh"
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DS_ROOT_DIR="$HOME/.deck-store"
STAGED_DIR="$DS_ROOT_DIR/tmp/staged_update"
BINARY_PATH="$SCRIPT_DIR/deck-store.x86_64"

apply_staged_update() {
    if [ -d "$STAGED_DIR" ] && [ -f "$STAGED_DIR/deck-store.x86_64" ] && [ -f "$STAGED_DIR/deck-store.pck" ]; then
        cp -rf "$STAGED_DIR"/* "$SCRIPT_DIR"/
        rm -f "$SCRIPT_DIR/steam_appid.txt"
        chmod +x "$SCRIPT_DIR/deck-store.x86_64" "$SCRIPT_DIR/launch.sh" 2>/dev/null || true
        rm -rf "$STAGED_DIR"
    fi
}

cd "$SCRIPT_DIR" || exit 1
export DECKSTORE_WRAPPER_ACTIVE=1

if [ -n "$LD_PRELOAD" ]; then
    CLEAN_PRELOAD=""
    IFS=':' read -ra ADDR <<< "$LD_PRELOAD"
    for p in "${ADDR[@]}"; do
        if [[ "$p" != *"ubuntu12_32"* ]]; then
            CLEAN_PRELOAD="${CLEAN_PRELOAD:+$CLEAN_PRELOAD:}$p"
        fi
    done
    export LD_PRELOAD="$CLEAN_PRELOAD"
fi

while true; do
    apply_staged_update
    rm -f "$SCRIPT_DIR/steam_appid.txt"
    chmod +x "$BINARY_PATH" 2>/dev/null || true
    "$BINARY_PATH" "$@"
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 42 ]; then
        sleep 0.5
        continue
    fi
    exit "$EXIT_CODE"
done
EOF
    fi

    chmod +x "$DS_BIN_DIR/deck-store.x86_64" "$DS_BIN_DIR/launch.sh"

    echo "75"
    echo "# Installing Steam Shortcut Manager helper..."
    SSM_JSON=$(curl -sL "https://api.github.com/repos/${SSM_REPO}/releases/latest" || true)
    SSM_TAG=$(echo "$SSM_JSON" | grep -m 1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -n "$SSM_TAG" ]; then
        SSM_URL="https://github.com/${SSM_REPO}/releases/download/${SSM_TAG}/${SSM_APP_ID}.flatpak"
        SSM_BUNDLE="$DS_TMP_DIR/${SSM_APP_ID}.flatpak"
        if curl -L --fail -o "$SSM_BUNDLE" "$SSM_URL" >> "$LOG_FILE" 2>&1; then
            flatpak uninstall --user --assumeyes "$SSM_APP_ID" >> "$LOG_FILE" 2>&1 || true
            if flatpak install --user --assumeyes "$SSM_BUNDLE" >> "$LOG_FILE" 2>&1; then
                echo "${SSM_TAG#v}" > "$DS_EXT_DIR/ssm.version"
            fi
            rm -f "$SSM_BUNDLE"
        fi
    fi

    echo "90"
    echo "# Registering DeckStore in Steam & applying Library Artwork..."
    python3 - << 'PYEOF' >> "$LOG_FILE" 2>&1
import os
import glob
import struct
import zlib
import shutil

home = os.path.expanduser("~")
bin_dir = os.path.join(home, ".deck-store", "bin")
exe_path = f'"{os.path.join(bin_dir, "launch.sh")}"'
start_dir = f'"{bin_dir}"'
app_name = "DeckStore"
marketing_dir = os.path.join(bin_dir, "marketing")
icon_path = os.path.join(marketing_dir, "library_capsule_600x900.png")

# Calculate Steam Non-Steam Shortcut AppID (unsigned 32-bit CRC32 with top bit set)
input_str = (exe_path + app_name).encode("utf-8")
crc = zlib.crc32(input_str) & 0xffffffff
shortcut_id = crc | 0x80000000
signed_id = struct.unpack("<i", struct.pack("<I", shortcut_id))[0]

steam_userdata_dirs = glob.glob(os.path.join(home, ".steam/steam/userdata/*")) + glob.glob(os.path.join(home, ".local/share/Steam/userdata/*"))
seen_configs = set()

for udir in steam_userdata_dirs:
    if not os.path.isdir(udir) or os.path.basename(udir) in ("0", "ac"):
        continue
    cfg_dir = os.path.realpath(os.path.join(udir, "config"))
    if cfg_dir in seen_configs:
        continue
    seen_configs.add(cfg_dir)
    os.makedirs(cfg_dir, exist_ok=True)
    grid_dir = os.path.join(cfg_dir, "grid")
    os.makedirs(grid_dir, exist_ok=True)

    # Copy Steam Grid Artworks
    artwork_map = {
        "library_capsule_600x900.png": f"{shortcut_id}p.png",
        "library_hero_3840x1240.png": f"{shortcut_id}_hero.png",
        "library_logo.png": f"{shortcut_id}_logo.png",
        "library_header_920x430.png": f"{shortcut_id}.png",
    }
    for src_name, dst_name in artwork_map.items():
        src_file = os.path.join(marketing_dir, src_name)
        if os.path.isfile(src_file):
            shutil.copyfile(src_file, os.path.join(grid_dir, dst_name))

    vdf_path = os.path.join(cfg_dir, "shortcuts.vdf")
    data = b"\x00shortcuts\x00\x08\x08"
    if os.path.isfile(vdf_path):
        with open(vdf_path, "rb") as f:
            raw = f.read()
        if raw.startswith(b"\x00shortcuts\x00") and raw.endswith(b"\x08\x08"):
            data = raw

    if os.path.join(bin_dir, "launch.sh").encode("utf-8") not in data:
        # Count existing entries to assign next index
        idx = data.count(b"\x00AppName\x00")
        entry = (
            b"\x00" + str(idx).encode("utf-8") + b"\x00"
            + b"\x02appid\x00" + struct.pack("<i", signed_id)
            + b"\x01AppName\x00" + app_name.encode("utf-8") + b"\x00"
            + b"\x01Exe\x00" + exe_path.encode("utf-8") + b"\x00"
            + b"\x01StartDir\x00" + start_dir.encode("utf-8") + b"\x00"
            + b"\x01icon\x00" + (icon_path if os.path.isfile(icon_path) else "").encode("utf-8") + b"\x00"
            + b"\x01ShortcutPath\x00\x00"
            + b"\x01LaunchOptions\x00\x00"
            + b"\x02IsHidden\x00\x00\x00\x00\x00"
            + b"\x02AllowDesktopConfig\x00\x01\x00\x00\x00"
            + b"\x02AllowOverlay\x00\x01\x00\x00\x00"
            + b"\x02OpenVR\x00\x00\x00\x00\x00"
            + b"\x00tags\x00\x08"
            + b"\x08"
        )
        new_data = data[:-2] + entry + b"\x08\x08"
        with open(vdf_path, "wb") as f:
            f.write(new_data)
        print(f"Added DeckStore shortcut (ID {shortcut_id}) to {vdf_path}")
    else:
        print(f"DeckStore shortcut already present in {vdf_path}, updated grid artwork.")
PYEOF

    # Create Desktop Menu entry
    APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$APPS_DIR"
    cat << EOF > "$APPS_DIR/deck-store.desktop"
[Desktop Entry]
Name=DeckStore
Comment=Flatpak & Community App Store for Steam Deck
Exec=$DS_BIN_DIR/launch.sh
Icon=$DS_BIN_DIR/marketing/library_capsule_600x900.png
Terminal=false
Type=Application
Categories=Game;PackageManager;
EOF
    chmod +x "$APPS_DIR/deck-store.desktop"

    echo "100"
    echo "# Installation complete!"
}

if command -v zenity >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
    ( run_installation ) | zenity --progress \
        --title="DeckStore Installer" \
        --text="Preparing installation..." \
        --percentage=0 \
        --auto-close \
        --width=420
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
        zenity --info --title="DeckStore Installed" \
            --text="DeckStore has been installed and added to your Steam Library!\n\nPlease restart Steam (or switch back to Gaming Mode) to see DeckStore in your library." \
            --width=420
    else
        zenity --error --title="DeckStore Installation Failed" \
            --text="An error occurred during installation. Check ~/.deck-store/tmp/install.log for details." \
            --width=420
        exit 1
    fi
else
    run_installation
    log "DeckStore installation finished! Restart Steam to see DeckStore in your library."
fi
