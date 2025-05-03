#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
import sys
import struct
import zlib # For CRC32 calculation
import vdf # Requires: pip install vdf
from pathlib import Path
try:
    from PIL import Image, ImageOps # Requires: pip install Pillow
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("WARN: Pillow (PIL) library not found. Artwork processing will be skipped.", file=sys.stderr)
    # No need to print pip install instruction here as it's meant to be bundled eventually
    # print("WARN: Please install it via pip install Pillow", file=sys.stderr)

# --- CRC32 Manual Implementation (to bypass potentially faulty zlib) ---
_crc32_tab = []
def _init_crc32_tab():
    global _crc32_tab
    if _crc32_tab: return
    _crc32_tab = [0] * 256
    for i in range(256):
        crc = i
        for _ in range(8): crc = (crc >> 1) ^ 0xEDB88320 if crc & 1 else crc >> 1
        _crc32_tab[i] = crc
_init_crc32_tab()

def manual_crc32(data: bytes) -> int:
    """Calculates CRC32 using a manual implementation."""
    crc = 0xFFFFFFFF
    for byte in data: crc = (crc >> 8) ^ _crc32_tab[(crc ^ byte) & 0xFF]
    return ~crc & 0xFFFFFFFF
# --- End Manual CRC32 ---

# --- Steam Path Finding ---
def find_steam_userdata_path():
    """Tries to find the active Steam userdata directory."""
    home = Path.home(); steam_paths = [home / ".steam/root/userdata", home / ".local/share/Steam/userdata", home / ".steam/steam/userdata", home / ".var/app/com.valvesoftware.Steam/data/Steam/userdata"]; active_user_dir = None; latest_mtime = 0
    for path in steam_paths:
        if path.is_dir():
            user_dirs = [d for d in path.iterdir() if d.is_dir() and d.name.isdigit()];
            if not user_dirs: continue
            for user_dir in user_dirs:
                loginusers_path = path.parent / "config/loginusers.vdf"; user_id_str = user_dir.name
                try:
                    if loginusers_path.is_file():
                        with open(loginusers_path, 'r') as f: login_users_data = vdf.load(f)
                        if user_id_str in login_users_data.get('users', {}):
                            timestamp = int(login_users_data['users'][user_id_str].get('Timestamp', 0))
                            if timestamp > latest_mtime: latest_mtime = timestamp; active_user_dir = user_dir
                except Exception as e: print(f"WARN: Could not process loginusers.vdf: {e}", file=sys.stderr)
            if not active_user_dir and user_dirs:
                latest_mtime_config = 0; fallback_user_dir = None; print(f"INFO: Using localconfig.vdf modification time as fallback for user detection.")
                for user_dir in user_dirs:
                    localconfig_path = user_dir / "config/localconfig.vdf"
                    if localconfig_path.is_file():
                        try:
                            mtime = localconfig_path.stat().st_mtime
                            if mtime > latest_mtime_config:
                                latest_mtime_config = mtime
                                fallback_user_dir = user_dir
                        except OSError as e: print(f"WARN: Could not stat {localconfig_path}: {e}", file=sys.stderr)
                if fallback_user_dir: active_user_dir = fallback_user_dir
            if not active_user_dir and user_dirs: active_user_dir = user_dirs[0]; print(f"WARN: Using first found user dir: {active_user_dir}", file=sys.stderr)
            if active_user_dir: return active_user_dir
    return None

# --- Steam ID Calculation Functions ---
def _calculate_crc32_int(text: str) -> int:
    """Calculates the CRC32 checksum using manual implementation."""
    crc = manual_crc32(text.encode('utf-8')); print(f"DEBUG ID:   Manual CRC32 Result={crc}"); return crc

def generate_64bit_appid_int(exe_path: str, app_name: str) -> int:
    """Generates the 64-bit integer AppID (SRM: generatePreliminaryId)."""
    print(f"DEBUG ID: generate_64bit_appid_int called with exe='{exe_path}', name='{app_name}'")
    crc = _calculate_crc32_int(exe_path + app_name)
    result_int = (crc | 0x80000000) << 32 | 0x02000000; print(f"DEBUG ID:   64-bit Int={result_int}"); return result_int

def generate_artwork_appid_str(exe_path: str, app_name: str) -> str:
    """DEPRECATED (for artwork filenames) - Calculates ONLY the 32-bit CRC32 AppID string."""
    print(f"DEBUG ID: generate_artwork_appid_str (CRC32 only) called")
    crc = _calculate_crc32_int(exe_path + app_name); return str(crc)

def generate_short_appid_str(exe_path: str, app_name: str) -> str:
    """Generates the short 32-bit AppID by shifting the 64-bit one (SRM: generateShortAppId)."""
    print(f"DEBUG ID: generate_short_appid_str (Shifted) called")
    long_appid_int = generate_64bit_appid_int(exe_path, app_name)
    short_id = long_appid_int >> 32; print(f"DEBUG ID:   Short Int (long >> 32)={short_id}"); return str(short_id)

# --- Artwork Handling ---
def save_steam_artwork(artwork_appid_str: str, icon_source_path: str, grid_dir: Path):
    """Saves artwork using the provided artwork_appid_str."""
    print(f"DEBUG ART: save_steam_artwork called with ID='{artwork_appid_str}'")
    if not PIL_AVAILABLE: print("WARN: Pillow library not available.", file=sys.stderr); return False
    if not grid_dir or not icon_source_path or not Path(icon_source_path).is_file(): print(f"ERROR: Invalid icon path or grid dir. Icon='{icon_source_path}', Grid='{grid_dir}'", file=sys.stderr); return False
    try: grid_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e: print(f"ERROR: Could not create grid directory: {grid_dir} - {e}", file=sys.stderr); return False
    try:
        img = Image.open(icon_source_path).convert("RGBA"); grid_path_png = grid_dir / f"{artwork_appid_str}.png"; grid_path_p_png = grid_dir / f"{artwork_appid_str}p.png"; hero_path_png = grid_dir / f"{artwork_appid_str}_hero.png";
        img.save(grid_path_png, "PNG"); print(f"INFO: Grid image saved: {grid_path_png}")
        img.save(grid_path_p_png, "PNG"); print(f"INFO: Portrait grid image ('p') saved: {grid_path_p_png}")
        img.save(hero_path_png, "PNG"); print(f"INFO: Hero image saved: {hero_path_png}")
        return True
    except FileNotFoundError: print(f"ERROR: Icon source file not found: {icon_source_path}", file=sys.stderr); return False
    except Exception as e: print(f"ERROR: Artwork processing failed for {icon_source_path}: {e}", file=sys.stderr); return False

# --- Shortcut Management ---
def add_shortcut(userdata_path: Path, flatpak_appid: str, name: str, exe: str, params: str, icon: str):
    shortcuts_path = userdata_path / "config/shortcuts.vdf"; grid_path = userdata_path / "config/grid"; print(f"INFO: Adding shortcut: AppID='{flatpak_appid}', Name='{name}'"); shortcuts = {};
    try: # Read VDF
        if shortcuts_path.is_file():
             with open(shortcuts_path, 'rb') as f: shortcuts_data = vdf.binary_load(f); shortcuts = shortcuts_data.get('shortcuts', shortcuts_data) if isinstance(shortcuts_data, dict) else {};
             if not isinstance(shortcuts, dict): shortcuts = {}
        else: print(f"INFO: {shortcuts_path} does not exist, creating new."); shortcuts_path.parent.mkdir(parents=True, exist_ok=True)
    except Exception as e: print(f"ERROR: Failed reading {shortcuts_path}: {e}", file=sys.stderr); shortcuts = {}
    next_id = 0; numeric_keys = sorted([int(k) for k in shortcuts.keys() if k.isdigit()]);
    if numeric_keys: next_id = numeric_keys[-1] + 1
    shortcut_key = str(next_id)
    tag_to_find = f'DeckStore_{flatpak_appid}';
    for key, entry in shortcuts.items():
         if isinstance(entry, dict) and tag_to_find in entry.get('tags', {}).values(): print(f"WARN: Shortcut for {flatpak_appid} seems to exist. Skipping."); return True

    clean_exe = exe.strip('"'); clean_name = name;

    # --- NEU: Verwende die "Short" (Shifted) ID für Artwork gemäß SRM Kommentar ---
    artwork_id_to_use = generate_short_appid_str(clean_exe, clean_name)
    print(f"INFO: Using Shifted Short AppID for filenames: {artwork_id_to_use}")
    # --- Ende NEU ---

    icon_path_for_vdf = str(grid_path / f"{artwork_id_to_use}p.png") if icon else ""

    shortcut_entry = { # Verwende artwork_id_to_use für den Icon-Pfad
        'AppName': name, 'Exe': f'"{exe}"', 'StartDir': f'"{os.path.dirname(exe)}"', 'icon': f'"{icon_path_for_vdf}"',
        'ShortcutPath': '', 'LaunchOptions': params, 'IsHidden': 0, 'AllowDesktopConfig': 1, 'AllowOverlay': 1, 'OpenVR': 0,
        'Devkit': 0, 'DevkitGameID': '', 'DevkitOverrideAppID': 0, 'LastPlayTime': 0, 'FlatpakAppID': flatpak_appid,
        'tags': {'0': tag_to_find } }

    shortcuts[shortcut_key] = shortcut_entry; print(f"INFO: Shortcut entry created with index {shortcut_key}")
    vdf_data_to_write = {'shortcuts': shortcuts};
    try: # Save VDF
        with open(shortcuts_path, 'wb') as f: vdf.binary_dump(vdf_data_to_write, f); print(f"INFO: Successfully wrote {shortcuts_path}.")
    except Exception as e: print(f"ERROR: Failed writing {shortcuts_path}: {e}", file=sys.stderr); return False
    if icon:
        if not save_steam_artwork(artwork_id_to_use, icon, grid_path): # Pass correct ID
           print(f"WARN: Failed to save artwork, but shortcut was added.", file=sys.stderr)
    return True


def remove_shortcut(userdata_path: Path, flatpak_appid: str):
    shortcuts_path = userdata_path / "config/shortcuts.vdf"; grid_path = userdata_path / "config/grid"; print(f"INFO: Removing shortcut for Flatpak AppID: {flatpak_appid}");
    if not shortcuts_path.is_file(): print(f"INFO: {shortcuts_path} does not exist."); return True;
    shortcuts = {}; shortcut_key_to_remove = None; shortcut_to_remove = None; tag_to_find = f'DeckStore_{flatpak_appid}'
    try: # Read VDF
        with open(shortcuts_path, 'rb') as f: shortcuts_data = vdf.binary_load(f); shortcuts = shortcuts_data.get('shortcuts', shortcuts_data) if isinstance(shortcuts_data, dict) else {};
        if not isinstance(shortcuts, dict): shortcuts = {}
    except Exception as e: print(f"ERROR: Failed reading {shortcuts_path}: {e}", file=sys.stderr); return False
    for key in list(shortcuts.keys()): # Find
        entry = shortcuts.get(key, {});
        if isinstance(entry, dict) and tag_to_find in entry.get('tags', {}).values(): shortcut_key_to_remove = key; shortcut_to_remove = entry; break
    if shortcut_key_to_remove:
        print(f"INFO: Found shortcut to remove (Index: {shortcut_key_to_remove})"); exe_for_appid = shortcut_to_remove.get('Exe', '').strip('"'); name_for_appid = shortcut_to_remove.get('AppName', ''); del shortcuts[shortcut_key_to_remove];
        try: # Save VDF
            with open(shortcuts_path, 'wb') as f: vdf.binary_dump({'shortcuts': shortcuts}, f); print(f"INFO: Successfully wrote {shortcuts_path} after removal.")
        except Exception as e: print(f"ERROR: Failed writing {shortcuts_path} after removal: {e}", file=sys.stderr); return False

        # --- NEU: Artwork löschen mit "Short" (Shifted) ID ---
        try:
            if exe_for_appid and name_for_appid:
                 artwork_appid_str = generate_short_appid_str(exe_for_appid, name_for_appid) # <-- Geänderter Aufruf!
                 print(f"INFO: Attempting to delete artwork for Shifted Short AppID {artwork_appid_str}")
                 patterns = [f"{artwork_appid_str}.png", f"{artwork_appid_str}p.png", f"{artwork_appid_str}_hero.png", f"{artwork_appid_str}_logo.png"]
                 for pattern in patterns:
                    art_path = grid_path / pattern
                    if art_path.is_file():
                        print(f"INFO: Deleting artwork: {art_path}")
                        art_path.unlink()
            else: print(f"WARN: Could not get Exe/AppName to delete artwork.")
        except Exception as e: print(f"WARN: Failed deleting artwork: {e}", file=sys.stderr)
        # --- Ende NEU ---
        return True
    else: print(f"INFO: No shortcut found with tag '{tag_to_find}'."); return True


def check_shortcut(userdata_path: Path, flatpak_appid: str):
    # ... (check function bleibt unverändert, nutzt Tag) ...
    shortcuts_path = userdata_path / "config/shortcuts.vdf"; print(f"INFO: Checking shortcut for Flatpak AppID: {flatpak_appid}");
    if not shortcuts_path.is_file(): print("INFO: shortcuts.vdf does not exist."); return False;
    shortcuts = {};
    try:
        with open(shortcuts_path, 'rb') as f: shortcuts_data = vdf.binary_load(f); shortcuts = shortcuts_data.get('shortcuts', shortcuts_data) if isinstance(shortcuts_data, dict) else {};
        if not isinstance(shortcuts, dict): shortcuts = {}
    except Exception as e: print(f"ERROR: Failed reading {shortcuts_path} for check: {e}", file=sys.stderr); return False;
    tag_to_find = f'DeckStore_{flatpak_appid}';
    for entry in shortcuts.values():
        if isinstance(entry, dict) and tag_to_find in entry.get('tags', {}).values(): print(f"INFO: Shortcut found."); return True;
    print(f"INFO: Shortcut not found."); return False;


# --- Argument Parser und Main Execution (unverändert) ---
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Manage Steam non-game shortcuts for Flatpak apps.")
    # ... (Argument parsing bleibt gleich) ...
    parser.add_argument('--action', choices=['add', 'remove', 'check'], required=True); parser.add_argument('--appid', required=True); parser.add_argument('--name'); parser.add_argument('--icon'); parser.add_argument('--exe', default='/usr/bin/flatpak'); parser.add_argument('--params'); args = parser.parse_args(); userdata_dir = find_steam_userdata_path();
    if not userdata_dir: print("ERROR: Steam userdata directory not found.", file=sys.stderr); sys.exit(1);
    print(f"INFO: Steam userdata directory found: {userdata_dir}"); exit_code = 1;
    if args.action == 'add':
        if not args.name or not args.icon: parser.error("--name and --icon are required for action 'add'.")
        params = args.params if args.params else f"run {args.appid}"; success = add_shortcut(userdata_dir, args.appid, args.name, args.exe, params, args.icon); exit_code = 0 if success else 1
    elif args.action == 'remove':
        success = remove_shortcut(userdata_dir, args.appid); exit_code = 0 if success else 1
    elif args.action == 'check':
        found = check_shortcut(userdata_dir, args.appid); exit_code = 0 if found else 1
    sys.exit(exit_code)

# Initialisiere die CRC32 Tabelle beim Laden des Moduls
_crc32_tab = []
def _init_crc32_tab():
    global _crc32_tab;
    if _crc32_tab: return;
    _crc32_tab = [0]*256;
    for i in range(256):
        crc = i;
        for _ in range(8): crc = (crc>>1)^0xEDB88320 if crc&1 else crc>>1;
        _crc32_tab[i] = crc;
_init_crc32_tab();
