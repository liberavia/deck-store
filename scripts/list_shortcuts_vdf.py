#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import vdf  # Benötigt: pip install vdf
from pathlib import Path
import sys
import datetime # Für die Umwandlung von LastPlayTime
import re # Für die Extraktion der ID aus dem Icon-Pfad

# --- Steam Userdata Path Logic (angepasst von list_steam_shortcuts.py) ---
def find_steam_userdata_path_for_listing():
    """Versucht, das relevanteste Steam Userdata-Verzeichnis zu finden."""
    home = Path.home()
    steam_paths_to_check = [
        home / ".steam/root/userdata",
        home / ".local/share/Steam/userdata",
        home / ".steam/steam/userdata",
        home / ".var/app/com.valvesoftware.Steam/data/Steam/userdata"
    ]
    candidate_user_dirs = []
    for steam_base_path in steam_paths_to_check:
        if steam_base_path.is_dir():
            for user_id_dir in steam_base_path.iterdir():
                if user_id_dir.is_dir() and user_id_dir.name.isdigit():
                    localconfig_vdf = user_id_dir / "config" / "localconfig.vdf"
                    if localconfig_vdf.is_file():
                        try:
                            mtime = localconfig_vdf.stat().st_mtime
                            candidate_user_dirs.append({'path': user_id_dir, 'mtime': mtime, 'steam_base': steam_base_path})
                        except OSError: pass
    if not candidate_user_dirs: return None
    candidate_user_dirs.sort(key=lambda x: x['mtime'], reverse=True)
    most_likely_user_dir_info = candidate_user_dirs[0]
    most_likely_user_path = most_likely_user_dir_info['path']
    loginusers_vdf_path = most_likely_user_dir_info['steam_base'].parent / "config/loginusers.vdf"
    if loginusers_vdf_path.is_file():
        try:
            with open(loginusers_vdf_path, 'r', encoding='utf-8') as f:
                login_users_data = vdf.load(f)
            active_user_id_from_loginfile = None
            latest_timestamp = 0
            users = login_users_data.get('users', {})
            if isinstance(users, dict):
                for user_id, user_details in users.items():
                    if isinstance(user_details, dict):
                        timestamp = int(user_details.get('Timestamp', 0))
                        path_for_this_user = most_likely_user_dir_info['steam_base'] / user_id
                        if path_for_this_user.is_dir() and timestamp > latest_timestamp:
                            latest_timestamp = timestamp
                            active_user_id_from_loginfile = user_id
            if active_user_id_from_loginfile:
                confirmed_active_path = most_likely_user_dir_info['steam_base'] / active_user_id_from_loginfile
                if (confirmed_active_path / "config" / "localconfig.vdf").is_file():
                    most_likely_user_path = confirmed_active_path
        except Exception as e:
            print(f"WARN: Fehler beim Verarbeiten von '{loginusers_vdf_path}': {e}", file=sys.stderr)
    if most_likely_user_path:
         print(f"INFO: Steam Userdata-Verzeichnis ausgewählt: {most_likely_user_path}")
    return most_likely_user_path

# --- AppID Generation Logic (aus steam_shortcut_manager.py) ---
_crc32_tab = []
def _init_crc32_tab():
    global _crc32_tab
    if _crc32_tab: return
    _crc32_tab = [0] * 256
    for i in range(256):
        crc_val = i
        for _ in range(8): crc_val = (crc_val >> 1) ^ 0xEDB88320 if crc_val & 1 else crc_val >> 1
        _crc32_tab[i] = crc_val
_init_crc32_tab()

def manual_crc32(data: bytes) -> int:
    """Calculates CRC32 using a manual implementation."""
    crc_val = 0xFFFFFFFF
    for byte_val in data: crc_val = (crc_val >> 8) ^ _crc32_tab[(crc_val ^ byte_val) & 0xFF]
    return ~crc_val & 0xFFFFFFFF

def _calculate_crc32_int(text: str) -> int:
    """Calculates the CRC32 checksum using manual implementation."""
    return manual_crc32(text.encode('utf-8'))

def generate_64bit_appid_int(exe_path: str, app_name: str) -> int:
    """Generates the 64-bit integer AppID (SRM: generatePreliminaryId)."""
    # print(f"DEBUG ID GEN: exe='{exe_path}', name='{app_name}'")
    crc = _calculate_crc32_int(exe_path + app_name)
    result_int = (crc | 0x80000000) << 32 | 0x02000000
    return result_int

def generate_short_appid_str(exe_path: str, app_name: str) -> str:
    """Generates the short 32-bit AppID by shifting the 64-bit one (SRM: generateShortAppId)."""
    long_appid_int = generate_64bit_appid_int(exe_path, app_name)
    short_id = long_appid_int >> 32
    return str(short_id)

# --- Main Listing Function ---
def analyze_shortcuts_and_ids():
    """Listet Shortcuts auf und berechnet die erwartete Short-AppID."""

    userdata_path = find_steam_userdata_path_for_listing()
    if not userdata_path:
        print("FEHLER: Steam Userdata-Verzeichnis konnte nicht gefunden werden.", file=sys.stderr)
        sys.exit(1)

    shortcuts_file_path = userdata_path / "config" / "shortcuts.vdf"
    grid_base_path = userdata_path / "config" / "grid" # Für den Vergleich mit Icon-Pfaden

    if not shortcuts_file_path.is_file():
        print(f"INFO: Datei '{shortcuts_file_path}' nicht gefunden.")
        return

    print(f"Lese Shortcuts aus: {shortcuts_file_path}\n")

    try:
        with open(shortcuts_file_path, 'rb') as f:
            data = vdf.binary_load(f)

        if 'shortcuts' in data and isinstance(data['shortcuts'], dict):
            shortcut_entries = data['shortcuts']
        elif isinstance(data, dict) and all(k.isdigit() for k in data.keys()):
             shortcut_entries = data
        else:
            shortcut_entries = {}

        if not isinstance(shortcut_entries, dict):
            print(f"FEHLER: Unerwartete Struktur in shortcuts.vdf.", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"FEHLER: Konnte '{shortcuts_file_path}' nicht lesen/parsen: {e}", file=sys.stderr)
        sys.exit(1)

    if not shortcut_entries:
        print("Keine Shortcut-Einträge gefunden.")
        return

    def sort_key_func(k):
        if k.isdigit(): return int(k)
        return float('inf')
    sorted_keys = sorted(shortcut_entries.keys(), key=sort_key_func)

    print(f"Gefundene Shortcut-Einträge: {len(sorted_keys)}\n")

    for key in sorted_keys:
        entry = shortcut_entries[key]
        if not isinstance(entry, dict): continue

        app_name = entry.get('AppName', '')
        exe_path_from_vdf = entry.get('Exe', '')

        # WICHTIG: Die Bereinigung des Exe-Pfads muss der Logik in `steam_shortcut_manager.py` entsprechen,
        # als es den Shortcut HINZUGEFÜGT hat. Dort wurde `exe.strip('"')` auf den *übergebenen* Exe-Pfad angewendet.
        # Hier nehmen wir den Wert, wie er im VDF steht. Wenn er von deinem Skript geschrieben wurde,
        # war der `exe`-Parameter deines Skripts der Input für die ID-Generierung.
        # Für die *Analyse* ist es am besten, den `exe_path_from_vdf` so zu nehmen, wie er ist,
        # da andere Tools (oder manuelle Einträge) die Argumente im `Exe`-Feld haben könnten.
        # Dein `add_shortcut` verwendet `clean_exe = exe.strip('"')`.
        # Wenn der Eintrag von deinem Skript stammt, war `exe` der Wert VOR dem Quoting für VDF.
        # Hier müssen wir eine Annahme treffen. Die gängigste ist, den Wert aus VDF zu nehmen und
        # die äußeren VDF-spezifischen Anführungszeichen zu entfernen (was python-vdf beim Lesen macht)
        # und dann die Logik `strip('"')` anzuwenden, die dein Skript für die ID-Generierung anwendet.

        # Annahme: Der 'Exe'-Wert aus VDF (den python-vdf liefert) ist der,
        # den dein Skript auch für die ID-Generierung verwenden würde, nach `strip('"')`.
        # Jedoch ist es komplexer: Wenn dein Skript `exe="/usr/bin/flatpak"` und `params="run..."` hatte,
        # dann war `exe` "/usr/bin/flatpak" für die ID. Im VDF steht dann `Exe: "\"/usr/bin/flatpak\""`
        # (VDF-Quoting) und `LaunchOptions` enthält die Parameter.
        # Wenn aber der VDF-Eintrag `Exe: "\"/usr/bin/flatpak\" run..."` hat, wurde das evtl. anders erstellt.

        # Für diese Analyse verwenden wir den `Exe`-Wert, wie er im VDF steht (python-vdf gibt den String-Inhalt).
        # Dein ID-Algorithmus verwendet dann `exe.strip('"')` auf diesen Wert.
        cleaned_exe_for_id = exe_path_from_vdf.strip('"') # So wie dein Algorithmus es tun würde

        calculated_short_id = "Fehler bei Berechnung"
        try:
            if app_name and cleaned_exe_for_id : # Nur berechnen, wenn beide Werte vorhanden sind
                 calculated_short_id = generate_short_appid_str(cleaned_exe_for_id, app_name)
            elif not app_name:
                 calculated_short_id = "AppName fehlt"
            elif not cleaned_exe_for_id:
                 calculated_short_id = "Exe-Pfad fehlt/leer"

        except Exception as e_calc:
            calculated_short_id = f"Berechnungsfehler: {e_calc}"


        icon_path_str = entry.get('icon', '')
        id_from_icon_field = "N/A"
        icon_points_to_grid = False

        if icon_path_str:
            icon_p = Path(icon_path_str)
            try: # Überprüfen, ob der Icon-Pfad im Grid-Ordner liegt
                if icon_p.is_absolute() and icon_p.parent == grid_base_path:
                    icon_points_to_grid = True
            except OSError: # Kann bei ungültigen Pfaden passieren
                pass

            if icon_points_to_grid:
                # Extrahiere ID aus Dateinamen wie "1234567p.png" oder "1234567_icon.png"
                stem_name = icon_p.stem # z.B. "1234567p" oder "1234567_icon"
                match = re.match(r"(\d+)", stem_name)
                if match:
                    id_from_icon_field = match.group(1)
            else:
                id_from_icon_field = "(externer Pfad)"


        print(f"--- Shortcut Index: {key} ---")
        print(f"  AppName:          {app_name}")
        print(f"  Exe (aus VDF):    {exe_path_from_vdf}")
        print(f"  Exe (für ID-Gen): '{cleaned_exe_for_id}'") # Zeigt, was für die ID-Generierung verwendet wurde
        print(f"  LaunchOptions:    {entry.get('LaunchOptions', '')}")
        print(f"  icon (aus VDF):   {icon_path_str}")
        print(f"  > ID aus Icon-Feld: {id_from_icon_field}")
        print(f"  > Berechnete Short-ID: {calculated_short_id}")

        # Zusätzliche Infos (optional anzeigen)
        # print(f"  StartDir:        {entry.get('StartDir', 'N/A')}")
        # ... (andere Felder wie LastPlayTime, IsHidden etc. können hier auch wieder rein) ...
        if 'FlatpakAppID' in entry:
            print(f"  FlatpakAppID:     {entry.get('FlatpakAppID', 'N/A')}")
        tags_dict = entry.get('tags', {})
        if isinstance(tags_dict, dict) and tags_dict:
            tag_list = [v for v in tags_dict.values() if v]
            print(f"  Tags:             {', '.join(tag_list) if tag_list else '(Keine)'}")
        else:
            print(f"  Tags:             (Keine)")
        print("-" * 30 + "\n")

if __name__ == "__main__":
    _init_crc32_tab() # Wichtig für die CRC32-Berechnung
    analyze_shortcuts_and_ids()
