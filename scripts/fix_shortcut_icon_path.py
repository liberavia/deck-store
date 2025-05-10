#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import vdf # Benötigt: pip install vdf
from pathlib import Path
import sys
import shutil # Für das Backup der Datei
import datetime # Für den Backup-Dateinamen

# Funktion zur Pfadfindung (angepasst aus deinen vorherigen Skripten)
def find_steam_userdata_path_for_modification():
    """
    Versucht, das relevanteste Steam Userdata-Verzeichnis zu finden.
    """
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

def fix_shortcut_icon_quotes(shortcut_index_to_fix_str: str):
    """
    Entfernt führende/abschließende Anführungszeichen aus dem 'icon'-Feld
    eines spezifischen Shortcut-Eintrags in shortcuts.vdf.
    """
    userdata_path = find_steam_userdata_path_for_modification()
    if not userdata_path:
        print("FEHLER: Steam Userdata-Verzeichnis konnte nicht gefunden werden.", file=sys.stderr)
        sys.exit(1)

    shortcuts_file_path = userdata_path / "config" / "shortcuts.vdf"

    if not shortcuts_file_path.is_file():
        print(f"FEHLER: Datei '{shortcuts_file_path}' nicht gefunden.", file=sys.stderr)
        sys.exit(1)

    # Backup der Originaldatei erstellen
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file_path = shortcuts_file_path.parent / f"shortcuts.vdf.backup_{timestamp}"
    try:
        shutil.copy2(shortcuts_file_path, backup_file_path)
        print(f"INFO: Backup der Originaldatei erstellt: {backup_file_path}")
    except Exception as e:
        print(f"FEHLER: Konnte kein Backup von '{shortcuts_file_path}' erstellen: {e}", file=sys.stderr)
        print("FEHLER: Skript wird aus Sicherheitsgründen beendet.")
        sys.exit(1)

    try:
        with open(shortcuts_file_path, 'rb') as f:
            data = vdf.binary_load(f)

        # Die Struktur von 'data' kann variieren. Manchmal ist es {'shortcuts': {...}},
        # manchmal direkt das Dictionary der Shortcuts.
        if 'shortcuts' in data and isinstance(data['shortcuts'], dict):
            shortcut_entries = data['shortcuts']
            data_to_write_back = data # Ändere direkt in der Hauptstruktur
        elif isinstance(data, dict) and all(k.isdigit() for k in data.keys()):
             shortcut_entries = data
             data_to_write_back = shortcut_entries # Schreibe das Shortcut-Dict direkt zurück
        else:
            print(f"FEHLER: Unerwartete Struktur in shortcuts.vdf. Konnte Shortcut-Einträge nicht als Dictionary interpretieren. Inhalt: {data}", file=sys.stderr)
            sys.exit(1)

        if not isinstance(shortcut_entries, dict):
             print(f"FEHLER: Shortcut-Einträge sind kein Dictionary.", file=sys.stderr)
             sys.exit(1)


    except Exception as e:
        print(f"FEHLER: Konnte '{shortcuts_file_path}' nicht lesen oder parsen: {e}", file=sys.stderr)
        sys.exit(1)

    if shortcut_index_to_fix_str not in shortcut_entries:
        print(f"FEHLER: Shortcut-Index '{shortcut_index_to_fix_str}' nicht in der Datei gefunden.")
        print(f"Verfügbare Indizes: {list(shortcut_entries.keys())}")
        sys.exit(1)

    entry_to_fix = shortcut_entries[shortcut_index_to_fix_str]
    if not isinstance(entry_to_fix, dict):
        print(f"FEHLER: Eintrag mit Index '{shortcut_index_to_fix_str}' hat ein unerwartetes Format.", file=sys.stderr)
        sys.exit(1)

    original_icon_path = entry_to_fix.get('icon', '')

    if not original_icon_path:
        print(f"INFO: Eintrag '{shortcut_index_to_fix_str}' ('{entry_to_fix.get('AppName', 'N/A')}') hat keinen 'icon'-Pfad. Nichts zu tun.")
        return

    print(f"INFO: Original 'icon'-Pfad für Index '{shortcut_index_to_fix_str}' ('{entry_to_fix.get('AppName', 'N/A')}'): '{original_icon_path}'")

    # Entferne führende und abschließende Anführungszeichen, falls vorhanden
    # Dies ist die Kernlogik der Korrektur
    if isinstance(original_icon_path, str) and \
       original_icon_path.startswith('"') and \
       original_icon_path.endswith('"'):

        corrected_icon_path = original_icon_path.strip('"')
        entry_to_fix['icon'] = corrected_icon_path # Aktualisiere den Wert im Dictionary

        print(f"INFO: 'icon'-Pfad korrigiert zu: '{corrected_icon_path}'")

        # Schreibe die modifizierten Daten zurück
        try:
            with open(shortcuts_file_path, 'wb') as f:
                vdf.binary_dump(data_to_write_back, f) # Schreibe die korrekte Datenstruktur zurück
            print(f"INFO: '{shortcuts_file_path}' erfolgreich aktualisiert.")
            print("INFO: Bitte starte Steam neu, um die Änderungen zu sehen.")
        except Exception as e:
            print(f"FEHLER: Konnte '{shortcuts_file_path}' nicht schreiben: {e}", file=sys.stderr)
            print("INFO: Die Originaldatei wurde möglicherweise nicht geändert, aber das Backup existiert.")
    else:
        print(f"INFO: 'icon'-Pfad für Index '{shortcut_index_to_fix_str}' scheint bereits korrekt formatiert zu sein (keine äußeren Anführungszeichen im Wert).")
        print("INFO: Keine Änderungen vorgenommen.")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Verwendung: python fix_shortcut_icon_path.py <shortcut_index>")
        print("Beispiel: python fix_shortcut_icon_path.py 25")
        sys.exit(1)

    shortcut_index_arg = sys.argv[1]
    if not shortcut_index_arg.isdigit():
        print(f"FEHLER: Shortcut-Index '{shortcut_index_arg}' ist keine gültige Zahl.")
        sys.exit(1)

    fix_shortcut_icon_quotes(shortcut_index_arg)
