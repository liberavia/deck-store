#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
import sys
import struct
import binascii # Für binascii.crc32, um näher an Lutris zu sein (optional, zlib.crc32 ist auch ok)
import zlib # Standard Python CRC32
import vdf # Requires: pip install vdf
from pathlib import Path
try:
    from PIL import Image, ImageOps # Requires: pip install Pillow
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("WARN: Pillow (PIL) library not found. Artwork processing will be skipped.", file=sys.stderr)

# --- CRC32 Manual Implementation (Alternative, falls zlib/binascii Probleme machen) ---
_crc32_tab_manual = []
def _init_crc32_tab_manual():
    global _crc32_tab_manual
    if _crc32_tab_manual: return
    _crc32_tab_manual = [0] * 256
    for i in range(256):
        crc = i
        for _ in range(8): crc = (crc >> 1) ^ 0xEDB88320 if crc & 1 else crc >> 1
        _crc32_tab_manual[i] = crc

def manual_crc32(data: bytes) -> int:
    """Calculates CRC32 using a manual implementation."""
    if not _crc32_tab_manual: _init_crc32_tab_manual()
    crc = 0xFFFFFFFF
    for byte in data: crc = (crc >> 8) ^ _crc32_tab_manual[(crc ^ byte) & 0xFF]
    return ~crc & 0xFFFFFFFF
# --- End Manual CRC32 ---

# --- Steam Path Finding (aus deinem Skript, leicht angepasst für Klarheit) ---
def find_steam_userdata_path():
    """Tries to find the active Steam userdata directory."""
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
                            candidate_user_dirs.append({'path': user_id_dir, 'mtime': mtime, 'steam_base': steam_base_path, 'user_id_str': user_id_dir.name})
                        except OSError:
                            pass # Fehler beim Lesen von Metadaten ignorieren

    if not candidate_user_dirs:
        return None

    # Sortiere Kandidaten nach Modifikationszeit von localconfig.vdf (aktuellste zuerst)
    candidate_user_dirs.sort(key=lambda x: x['mtime'], reverse=True)

    # Versuche, den aktivsten Nutzer über loginusers.vdf zu bestimmen
    # Dies ist oft zuverlässiger als nur die Modifikationszeit von localconfig.vdf
    latest_login_timestamp = 0
    active_user_dir_from_login = None

    for candidate in candidate_user_dirs:
        loginusers_path = candidate['steam_base'].parent / "config/loginusers.vdf"
        user_id_str_candidate = candidate['user_id_str']
        try:
            if loginusers_path.is_file():
                with open(loginusers_path, 'r', encoding='utf-8') as f:
                    login_users_data = vdf.load(f) # Text VDF

                user_details = login_users_data.get('users', {}).get(user_id_str_candidate)
                if user_details and isinstance(user_details, dict):
                    timestamp = int(user_details.get('Timestamp', 0))
                    if timestamp > latest_login_timestamp:
                        latest_login_timestamp = timestamp
                        active_user_dir_from_login = candidate['path']
        except Exception as e:
            print(f"WARN: Could not process loginusers.vdf for user {user_id_str_candidate}: {e}", file=sys.stderr)

    if active_user_dir_from_login:
        print(f"INFO: Active Steam user directory found via loginusers.vdf: {active_user_dir_from_login}")
        return active_user_dir_from_login
    elif candidate_user_dirs:
        # Fallback: Nimm den Ordner mit der neuesten localconfig.vdf, wenn loginusers.vdf nicht hilft
        fallback_user_dir = candidate_user_dirs[0]['path']
        print(f"INFO: Using fallback Steam user directory (latest localconfig.vdf): {fallback_user_dir}")
        return fallback_user_dir

    return None


# --- Steam ID Calculation Functions (Lutris-inspirierte Änderungen) ---
def _calculate_crc32_for_steam_id(text_to_hash: str) -> int:
    """Calculates CRC32. Lutris verwendet binascii.crc32. zlib.crc32 ist oft kompatibel."""
    # return binascii.crc32(text_to_hash.encode('utf-8')) # Wie Lutris (benötigt import binascii)
    return zlib.crc32(text_to_hash.encode('utf-8')) # Standard Python, sollte meistens gehen
    # return manual_crc32(text_to_hash.encode('utf-8')) # Deine manuelle Implementierung als Fallback

def generate_preliminary_64bit_id(exe_path_for_hash: str, app_name_for_hash: str) -> int:
    """
    Generiert die 64-bit integer AppID.
    WICHTIG: exe_path_for_hash sollte hier bereits die Form haben, die gehasht werden soll
    (z.B. gequotet, wenn das die Methode ist).
    """
    # print(f"DEBUG ID GEN (prelim): exe_for_hash='{exe_path_for_hash}', name_for_hash='{app_name_for_hash}'")

    # Lutris bildet: unique_id = "".join([exe_quoted, game.name])
    # Wir nehmen an, dass exe_path_for_hash bereits die gewünschte Form hat (z.B. gequotet)
    # und app_name_for_hash der saubere Name ist.
    string_to_hash = exe_path_for_hash + app_name_for_hash

    # print(f"DEBUG ID GEN (prelim): string_to_hash='{string_to_hash}'")

    # CRC32 Berechnung
    crc = _calculate_crc32_for_steam_id(string_to_hash)
    # print(f"DEBUG ID GEN (prelim): CRC32 result = {crc}")

    # Bit-Operationen wie bei Lutris und anderen Tools
    top_32_bits = crc | 0x80000000
    full_64_bit_id = (top_32_bits << 32) | 0x02000000 # 0x02000000 kennzeichnet Non-Steam Game

    # print(f"DEBUG ID GEN (prelim): Full 64-bit ID = {full_64_bit_id}")
    return full_64_bit_id

def generate_short_appid_for_artwork(exe_path_cleaned: str, app_name_cleaned: str) -> str:
    """
    Generiert die kurze 32-bit AppID (als String) für Artwork-Dateinamen.
    Nimmt saubere (nicht für VDF gequotete) exe und app_name entgegen und
    quotet den exe_path intern für die Hash-Generierung, ähnlich wie Lutris.
    """
    # Lutris-Stil: Den exe-Pfad für die Hash-Generierung quoten
    exe_path_quoted_for_hash = f'"{exe_path_cleaned}"'

    prelim_id = generate_preliminary_64bit_id(exe_path_quoted_for_hash, app_name_cleaned)
    short_id = prelim_id >> 32
    return str(short_id)

def generate_appid_for_vdf_entry(exe_path_cleaned: str, app_name_cleaned: str) -> int:
    """
    Generiert die 'appid' (als Integer), die in den Shortcut-Eintrag der VDF geschrieben wird.
    Nimmt saubere (nicht für VDF gequotete) exe und app_name entgegen.
    """
    exe_path_quoted_for_hash = f'"{exe_path_cleaned}"'

    prelim_id = generate_preliminary_64bit_id(exe_path_quoted_for_hash, app_name_cleaned)
    short_id_val = prelim_id >> 32
    # Lutris-Formel für das 'appid'-Feld in der VDF:
    vdf_entry_appid = short_id_val - 0x100000000 # Entspricht short_id_val - 4294967296
    return int(vdf_entry_appid) # Sicherstellen, dass es ein Python-Integer ist

# --- Artwork Handling ---
def save_steam_artwork(artwork_short_appid_str: str, icon_source_path_str: str, grid_dir: Path):
    """Saves artwork using the provided artwork_short_appid_str."""
    if not PIL_AVAILABLE:
        print("WARN: Pillow library not available. Artwork processing skipped.", file=sys.stderr)
        return False

    icon_source_path = Path(icon_source_path_str)
    if not grid_dir or not icon_source_path.is_file():
        print(f"ERROR: Invalid icon source path or grid directory. Icon='{icon_source_path}', Grid='{grid_dir}'", file=sys.stderr)
        return False

    try:
        grid_dir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"ERROR: Could not create grid directory: {grid_dir} - {e}", file=sys.stderr)
        return False

    try:
        img = Image.open(icon_source_path).convert("RGBA")
        # Dateinamen basierend auf dem Short AppID String
        base_name = artwork_short_appid_str

        # Standard Grid (vertikal)
        grid_path_png = grid_dir / f"{base_name}.png"
        img.save(grid_path_png, "PNG"); print(f"INFO: Grid image saved: {grid_path_png}")

        # Portrait Grid (für Listenansicht, oft als 'p' oder '_icon' referenziert)
        grid_path_p_png = grid_dir / f"{base_name}p.png"
        img.save(grid_path_p_png, "PNG"); print(f"INFO: Portrait grid image ('p') saved: {grid_path_p_png}")

        # Hero Banner
        hero_path_png = grid_dir / f"{base_name}_hero.png"
        img.save(hero_path_png, "PNG"); print(f"INFO: Hero image saved: {hero_path_png}")

        # Explizites Icon (wie bei Lutris und SRM oft üblich)
        icon_specific_png = grid_dir / f"{base_name}_icon.png"
        img.save(icon_specific_png, "PNG"); print(f"INFO: Specific icon image ('_icon') saved: {icon_specific_png}")

        # Optional: Logo
        logo_path_png = grid_dir / f"{base_name}_logo.png"
        img.save(logo_path_png, "PNG"); print(f"INFO: Logo image saved: {logo_path_png}")

        return True
    except FileNotFoundError:
        print(f"ERROR: Icon source file not found: {icon_source_path}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"ERROR: Artwork processing failed for {icon_source_path}: {e}", file=sys.stderr)
        return False

# --- Shortcut Management ---
def add_shortcut(userdata_path: Path, flatpak_appid_tag: str, app_name_param: str, exe_param: str, launch_options_param: str, icon_source_param: str):
    shortcuts_path = userdata_path / "config/shortcuts.vdf"
    grid_path = userdata_path / "config/grid"
    print(f"INFO: Adding shortcut: FlatpakAppIDTag='{flatpak_appid_tag}', Name='{app_name_param}'")

    shortcuts = {}
    try:
        if shortcuts_path.is_file():
             with open(shortcuts_path, 'rb') as f:
                 loaded_data = vdf.binary_load(f)
                 # Struktur kann {'shortcuts': {'0': ..., '1': ...}} oder direkt {'0': ..., '1': ...} sein
                 shortcuts = loaded_data.get('shortcuts', loaded_data) if isinstance(loaded_data, dict) else {}
             if not isinstance(shortcuts, dict): # Fallback, falls unerwartete Struktur
                 shortcuts = {}
        else:
            print(f"INFO: {shortcuts_path} does not exist, creating new.")
            shortcuts_path.parent.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        print(f"ERROR: Failed reading {shortcuts_path}: {e}", file=sys.stderr)
        shortcuts = {} # Starte mit leeren Shortcuts bei Lesefehler

    # Finde nächste verfügbare numerische ID für den Shortcut-Eintrag
    next_id = 0
    numeric_keys = sorted([int(k) for k in shortcuts.keys() if k.isdigit()])
    if numeric_keys:
        next_id = numeric_keys[-1] + 1
    shortcut_key_str = str(next_id)

    # Überprüfe, ob ein Shortcut mit diesem Tag bereits existiert
    # (flatpak_appid_tag ist z.B. "DeckStore_com.discordapp.Discord")
    tag_to_find = f'DeckStore_{flatpak_appid_tag}' # Konsistent mit deiner vorherigen Logik
    for key, entry_dict in shortcuts.items():
         if isinstance(entry_dict, dict) and tag_to_find in entry_dict.get('tags', {}).values():
             print(f"WARN: Shortcut für Flatpak AppID '{flatpak_appid_tag}' (Tag: '{tag_to_find}') scheint bereits zu existieren (Index: {key}). Überspringe das Hinzufügen.")
             return True # Gibt True zurück, als ob es erfolgreich wäre, um den Flow nicht zu unterbrechen

    # Bereinige exe und name für die ID-Generierung (Entferne äußere Anführungszeichen, falls vom Parameter übergeben)
    # Wichtig: Die ID-Generierungsfunktionen erwarten "saubere" Strings.
    clean_exe_for_id_gen = exe_param.strip('"')
    clean_name_for_id_gen = app_name_param.strip('"') # AppName sollte normalerweise keine Quotes enthalten

    # Generiere die verschiedenen IDs basierend auf der Lutris-inspirierten Logik
    # 1. Short AppID für Artwork-Dateinamen (als String)
    artwork_short_id_str = generate_short_appid_for_artwork(clean_exe_for_id_gen, clean_name_for_id_gen)
    print(f"INFO: Generierte Short AppID für Artwork: {artwork_short_id_str}")

    # 2. 'appid'-Feld für den VDF-Eintrag (als Integer)
    vdf_entry_appid_int = generate_appid_for_vdf_entry(clean_exe_for_id_gen, clean_name_for_id_gen)
    print(f"INFO: Generierte 'appid' für VDF-Eintrag: {vdf_entry_appid_int}")

    # Pfad für das Icon in der VDF (sollte auf eine der erstellten Artwork-Dateien zeigen)
    # Wir verwenden hier das "...p.png" oder "..._icon.png". Nehmen wir "_icon.png" für Konsistenz mit Lutris.
    icon_path_in_vdf = ""
    if icon_source_param: # Nur wenn ein Icon-Quellpfad angegeben wurde
        icon_path_in_vdf = str(grid_path / f"{artwork_short_id_str}_icon.png")
        # Alternativ: icon_path_in_vdf = str(grid_path / f"{artwork_short_id_str}p.png")

    # Erstelle den Shortcut-Eintrag
    # WICHTIG: Die Werte für 'Exe' und 'StartDir' in der VDF werden oft von Steam/Tools gequotet.
    # Die python-vdf Bibliothek sollte das korrekte Schreiben von Strings handhaben.
    # Wir übergeben die Strings hier ohne explizite äußere VDF-Formatierungsquotes.
    shortcut_entry = {
        'appid': vdf_entry_appid_int, # Das spezifische 'appid'-Feld
        'AppName': app_name_param,    # Der Anzeigename
        'Exe': exe_param,             # Der Pfad zur Exe (z.B. "/usr/bin/flatpak")
        'StartDir': os.path.dirname(exe_param), # Startverzeichnis
        'icon': icon_path_in_vdf,     # Pfad zum Icon (KEINE extra Anführungszeichen hier im Wert!)
        'ShortcutPath': '',           # Oft leer für Non-Steam-Spiele, die nicht auf .desktop basieren
        'LaunchOptions': launch_options_param,
        'IsHidden': 0,
        'AllowDesktopConfig': 1,
        'AllowOverlay': 1,
        'OpenVR': 0,
        'Devkit': 0,
        'DevkitGameID': '',
        'DevkitOverrideAppID': 0, # Nicht zu verwechseln mit dem 'appid'-Feld
        'LastPlayTime': 0,
        'FlatpakAppID': flatpak_appid_tag, # Dein benutzerdefiniertes Feld
        'tags': {'0': tag_to_find }
    }

    shortcuts[shortcut_key_str] = shortcut_entry
    print(f"INFO: Shortcut-Eintrag mit Index {shortcut_key_str} erstellt.")

    # Datenstruktur für das Schreiben vorbereiten (kann direkt das Shortcut-Dict sein oder in 'shortcuts' gewrapped)
    # Wir nehmen an, dass die gelesene Struktur (data_to_write_back aus dem Lese-Teil) korrekt ist.
    # Wenn `shortcuts` direkt das Dictionary der Einträge ist:
    vdf_data_to_write = {'shortcuts': shortcuts} if not shortcuts_path.is_file() or 'shortcuts' in vdf.binary_load(open(shortcuts_path, 'rb')) else shortcuts


    try:
        with open(shortcuts_path, 'wb') as f:
            vdf.binary_dump(vdf_data_to_write, f)
        print(f"INFO: Erfolgreich in {shortcuts_path} geschrieben.")
    except Exception as e:
        print(f"ERROR: Fehler beim Schreiben von {shortcuts_path}: {e}", file=sys.stderr)
        return False # Fehler beim Schreiben

    # Speichere Artwork, falls ein Icon-Pfad angegeben wurde
    if icon_source_param:
        if not save_steam_artwork(artwork_short_id_str, icon_source_param, grid_path):
           print(f"WARN: Fehler beim Speichern des Artworks, aber Shortcut wurde hinzugefügt.", file=sys.stderr)
           # Shortcut wurde trotzdem hinzugefügt, daher nicht unbedingt False zurückgeben

    return True


def remove_shortcut(userdata_path: Path, flatpak_appid_tag_to_remove: str):
    shortcuts_path = userdata_path / "config/shortcuts.vdf"
    grid_path = userdata_path / "config/grid"
    print(f"INFO: Entferne Shortcut für Flatpak AppID Tag: {flatpak_appid_tag_to_remove}")

    if not shortcuts_path.is_file():
        print(f"INFO: {shortcuts_path} existiert nicht. Nichts zu entfernen.")
        return True

    current_shortcuts = {}
    original_vdf_structure = {} # Um die ursprüngliche Struktur beizubehalten
    try:
        with open(shortcuts_path, 'rb') as f:
            original_vdf_structure = vdf.binary_load(f)
            current_shortcuts = original_vdf_structure.get('shortcuts', original_vdf_structure) if isinstance(original_vdf_structure, dict) else {}
            if not isinstance(current_shortcuts, dict): current_shortcuts = {}
    except Exception as e:
        print(f"ERROR: Fehler beim Lesen von {shortcuts_path} zum Entfernen: {e}", file=sys.stderr)
        return False

    shortcut_key_to_delete = None
    shortcut_entry_to_delete = None
    tag_to_find_for_removal = f'DeckStore_{flatpak_appid_tag_to_remove}'

    for key, entry_dict in list(current_shortcuts.items()): # list() für sicheres Löschen während Iteration
        if isinstance(entry_dict, dict) and tag_to_find_for_removal in entry_dict.get('tags', {}).values():
            shortcut_key_to_delete = key
            shortcut_entry_to_delete = entry_dict
            break

    if shortcut_key_to_delete and shortcut_entry_to_delete:
        print(f"INFO: Shortcut zum Entfernen gefunden (Index: {shortcut_key_to_delete}, Name: '{shortcut_entry_to_delete.get('AppName', 'N/A')}')")

        # Hole Exe und Name für die Artwork-ID-Generierung, bevor der Eintrag gelöscht wird
        exe_for_artwork_id = shortcut_entry_to_delete.get('Exe', '').strip('"')
        name_for_artwork_id = shortcut_entry_to_delete.get('AppName', '').strip('"')

        del current_shortcuts[shortcut_key_to_delete]

        # Datenstruktur für das Schreiben vorbereiten
        # Wenn die Originalstruktur {'shortcuts': {...}} war, behalte sie bei.
        if 'shortcuts' in original_vdf_structure:
            data_to_write_back_after_delete = {'shortcuts': current_shortcuts}
        else: # Sonst war es direkt das Dictionary der Shortcuts
            data_to_write_back_after_delete = current_shortcuts

        try:
            with open(shortcuts_path, 'wb') as f:
                vdf.binary_dump(data_to_write_back_after_delete, f)
            print(f"INFO: {shortcuts_path} erfolgreich nach Entfernung aktualisiert.")
        except Exception as e:
            print(f"ERROR: Fehler beim Schreiben von {shortcuts_path} nach Entfernung: {e}", file=sys.stderr)
            return False # Fehler beim Schreiben

        # Versuche, zugehöriges Artwork zu löschen
        if exe_for_artwork_id and name_for_artwork_id:
            try:
                artwork_appid_str_to_delete = generate_short_appid_for_artwork(exe_for_artwork_id, name_for_artwork_id)
                print(f"INFO: Versuche Artwork für Short AppID {artwork_appid_str_to_delete} zu löschen.")
                art_patterns_to_delete = [
                    f"{artwork_appid_str_to_delete}.png", f"{artwork_appid_str_to_delete}.jpg",
                    f"{artwork_appid_str_to_delete}p.png", f"{artwork_appid_str_to_delete}p.jpg",
                    f"{artwork_appid_str_to_delete}_hero.png", f"{artwork_appid_str_to_delete}_hero.jpg",
                    f"{artwork_appid_str_to_delete}_icon.png", f"{artwork_appid_str_to_delete}_icon.jpg",
                    f"{artwork_appid_str_to_delete}_logo.png", f"{artwork_appid_str_to_delete}_logo.jpg"
                ]
                for pattern in art_patterns_to_delete:
                    art_path = grid_path / pattern
                    if art_path.is_file():
                        print(f"INFO: Lösche Artwork: {art_path}")
                        art_path.unlink()
            except Exception as e_art:
                print(f"WARN: Fehler beim Löschen von Artwork: {e_art}", file=sys.stderr)
        else:
            print(f"WARN: Konnte Exe/AppName nicht aus dem gelöschten Shortcut extrahieren, um Artwork zu löschen.")
        return True
    else:
        print(f"INFO: Kein Shortcut mit Tag '{tag_to_find_for_removal}' zum Entfernen gefunden.")
        return True


def check_shortcut(userdata_path: Path, flatpak_appid_tag_to_check: str):
    shortcuts_path = userdata_path / "config/shortcuts.vdf"
    print(f"INFO: Überprüfe Shortcut für Flatpak AppID Tag: {flatpak_appid_tag_to_check}")

    if not shortcuts_path.is_file():
        print("INFO: shortcuts.vdf existiert nicht.")
        return False

    shortcuts = {}
    try:
        with open(shortcuts_path, 'rb') as f:
            loaded_data = vdf.binary_load(f)
            shortcuts = loaded_data.get('shortcuts', loaded_data) if isinstance(loaded_data, dict) else {}
            if not isinstance(shortcuts, dict): shortcuts = {}
    except Exception as e:
        print(f"ERROR: Fehler beim Lesen von {shortcuts_path} für Überprüfung: {e}", file=sys.stderr)
        return False

    tag_to_find_for_check = f'DeckStore_{flatpak_appid_tag_to_check}'
    for entry_dict in shortcuts.values():
        if isinstance(entry_dict, dict) and tag_to_find_for_check in entry_dict.get('tags', {}).values():
            print(f"INFO: Shortcut gefunden.")
            return True

    print(f"INFO: Shortcut nicht gefunden.")
    return False


if __name__ == "__main__":
    # Initialisiere die manuelle CRC32-Tabelle, falls sie verwendet wird
    _init_crc32_tab_manual()

    parser = argparse.ArgumentParser(description="Manage Steam non-game shortcuts for Flatpak apps (Lutris-inspired).")
    parser.add_argument('--action', choices=['add', 'remove', 'check'], required=True, help="Aktion, die ausgeführt werden soll.")
    parser.add_argument('--appid_tag', required=True, help="Eindeutiger Tag für die App (z.B. Flatpak App ID wie 'com.discordapp.Discord'). Wird für das 'DeckStore_'-Tag verwendet.")
    parser.add_argument('--name', help="Anzeigename der App in Steam.")
    parser.add_argument('--icon', help="Pfad zur Icon-Datei für das Artwork.")
    parser.add_argument('--exe', default='/usr/bin/flatpak', help="Pfad zur auszuführenden Datei (z.B. '/usr/bin/flatpak').")
    parser.add_argument('--params', help="Startparameter für die Exe (z.B. 'run com.discordapp.Discord').")

    args = parser.parse_args()

    userdata_dir = find_steam_userdata_path()
    if not userdata_dir:
        print("FEHLER: Steam Userdata-Verzeichnis nicht gefunden.", file=sys.stderr)
        sys.exit(1)

    print(f"INFO: Steam Userdata-Verzeichnis verwendet: {userdata_dir}")
    exit_code = 1 # Standard-Exit-Code bei Fehler

    if args.action == 'add':
        if not args.name or not args.icon or not args.params: # Params sind jetzt auch für 'add' erforderlich
            parser.error("--name, --icon und --params sind für die Aktion 'add' erforderlich.")
        # Stelle sicher, dass appid_tag für das FlatpakAppID-Feld und das Tag verwendet wird
        success = add_shortcut(userdata_dir, args.appid_tag, args.name, args.exe, args.params, args.icon)
        exit_code = 0 if success else 1
    elif args.action == 'remove':
        success = remove_shortcut(userdata_dir, args.appid_tag)
        exit_code = 0 if success else 1
    elif args.action == 'check':
        found = check_shortcut(userdata_dir, args.appid_tag)
        exit_code = 0 if found else 1

    sys.exit(exit_code)
