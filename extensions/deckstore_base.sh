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

ds_sudo() {
    local askpass_file="$DS_TMP_DIR/.ds_askpass.sh"
    if [ -f "$askpass_file" ]; then
        chmod 700 "$askpass_file" 2>/dev/null || true
        $DS_HOST_SPAWN env SUDO_ASKPASS="$askpass_file" sudo -A "$@"
    else
        $DS_HOST_SPAWN sudo -n "$@"
    fi
}

ds_add_steam_shortcut() {
    local appid_tag="$1"
    local app_name="$2"
    local exe_path="$3"
    local launch_params="$4"
    local icon_path="$5"

    if $DS_FLATPAK_CMD info io.github.liberavia.steamshortcutmanager &> /dev/null; then
        $DS_FLATPAK_CMD run io.github.liberavia.steamshortcutmanager \
            --action add \
            --appid_tag "$appid_tag" \
            --name "$app_name" \
            --exe "$exe_path" \
            --params "$launch_params" \
            --icon "$icon_path" && return 0
    fi

    $DS_HOST_SPAWN python3 - "$app_name" "$exe_path" "$launch_params" "$icon_path" << 'PYEOF'
import sys, os, glob, struct, zlib

app_name, exe_raw, params, icon_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
exe_path = f'"{exe_raw}"'
start_dir = f'"{os.path.dirname(exe_raw)}"'
crc = zlib.crc32((exe_path + app_name).encode("utf-8")) & 0xffffffff
shortcut_id = crc | 0x80000000
signed_id = struct.unpack("<i", struct.pack("<I", shortcut_id))[0]

home = os.path.expanduser("~")
udirs = glob.glob(os.path.join(home, ".steam/steam/userdata/*")) + glob.glob(os.path.join(home, ".local/share/Steam/userdata/*"))
seen = set()
for u in udirs:
    if not os.path.isdir(u) or os.path.basename(u) in ("0", "ac"):
        continue
    cfg = os.path.realpath(os.path.join(u, "config"))
    if cfg in seen:
        continue
    seen.add(cfg)
    os.makedirs(cfg, exist_ok=True)
    vdf = os.path.join(cfg, "shortcuts.vdf")
    data = b"\x00shortcuts\x00\x08\x08"
    if os.path.isfile(vdf):
        with open(vdf, "rb") as f:
            raw = f.read()
        if raw.startswith(b"\x00shortcuts\x00") and raw.endswith(b"\x08\x08"):
            data = raw
    if exe_raw.encode("utf-8") not in data and app_name.encode("utf-8") not in data:
        idx = data.count(b"\x00AppName\x00")
        entry = (
            b"\x00" + str(idx).encode("utf-8") + b"\x00"
            + b"\x02appid\x00" + struct.pack("<i", signed_id)
            + b"\x01AppName\x00" + app_name.encode("utf-8") + b"\x00"
            + b"\x01Exe\x00" + exe_path.encode("utf-8") + b"\x00"
            + b"\x01StartDir\x00" + start_dir.encode("utf-8") + b"\x00"
            + b"\x01icon\x00" + icon_path.encode("utf-8") + b"\x00"
            + b"\x01ShortcutPath\x00\x00"
            + b"\x01LaunchOptions\x00" + params.encode("utf-8") + b"\x00"
            + b"\x02IsHidden\x00\x00\x00\x00\x00"
            + b"\x02AllowDesktopConfig\x00\x01\x00\x00\x00"
            + b"\x02AllowOverlay\x00\x01\x00\x00\x00"
            + b"\x02OpenVR\x00\x00\x00\x00\x00"
            + b"\x00tags\x00\x08\x08"
        )
        with open(vdf, "wb") as f:
            f.write(data[:-2] + entry + b"\x08\x08")
PYEOF
}

ds_remove_steam_shortcut() {
    local appid_tag="$1"
    if $DS_FLATPAK_CMD info io.github.liberavia.steamshortcutmanager &> /dev/null; then
        $DS_FLATPAK_CMD run io.github.liberavia.steamshortcutmanager \
            --action remove \
            --appid_tag "$appid_tag" || true
    fi
}

