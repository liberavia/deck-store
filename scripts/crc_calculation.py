#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# AppID Generation Logic (aus deinem steam_shortcut_manager.py)
# --------------------------------------------------------------------
_crc32_tab = []

def _init_crc32_tab():
    global _crc32_tab
    if _crc32_tab: return
    _crc32_tab = [0] * 256
    for i in range(256):
        crc_val = i
        for _ in range(8): crc_val = (crc_val >> 1) ^ 0xEDB88320 if crc_val & 1 else crc_val >> 1
        _crc32_tab[i] = crc_val

def manual_crc32(data: bytes) -> int:
    crc_val = 0xFFFFFFFF
    for byte_val in data: crc_val = (crc_val >> 8) ^ _crc32_tab[(crc_val ^ byte_val) & 0xFF]
    return ~crc_val & 0xFFFFFFFF

def _calculate_crc32_int(text: str) -> int:
    return manual_crc32(text.encode('utf-8'))

def generate_64bit_appid_int(exe_path: str, app_name: str) -> int:
    # print(f"DEBUG 64bit_int: exe='{exe_path}', name='{app_name}'")
    crc = _calculate_crc32_int(exe_path + app_name)
    # print(f"DEBUG 64bit_int: CRC32 result = {crc}")
    result_int = (crc | 0x80000000) << 32 | 0x02000000
    # print(f"DEBUG 64bit_int: 64-bit Int = {result_int}")
    return result_int

def generate_short_appid_str(exe_path: str, app_name: str) -> str:
    long_appid_int = generate_64bit_appid_int(exe_path, app_name)
    short_id = long_appid_int >> 32
    # print(f"DEBUG short_id_str: Short Int (long >> 32) = {short_id}")
    return str(short_id)
# --------------------------------------------------------------------

def test_id_generation(case_name, exe_input, name_input, target_id_str, game_name_for_msg):
    print(f"--- Testfall für {game_name_for_msg}: {case_name} ---")
    print(f"  Input Exe : '{exe_input}'")
    print(f"  Input Name: '{name_input}'")
    try:
        generated_id = generate_short_appid_str(exe_input, name_input)
        print(f"  Erzeugte Short ID  : {generated_id}")
        if target_id_str:
            if generated_id == target_id_str:
                print(f"  >>>> TREFFER für {game_name_for_msg}! ID {target_id_str} wurde reproduziert! <<<<")
            else:
                print(f"  Kein Treffer (Ziel war {target_id_str})")
    except Exception as e:
        print(f"  Fehler bei der ID-Generierung: {e}")
    print("-" * 50 + "\n")

if __name__ == "__main__":
    _init_crc32_tab() # Initialisiere die CRC32-Tabelle

    print("Starte ID-Generierungsversuche für Discord (Ziel-ID: 3432892263)...")
    discord_target_id = "3432892263"
    discord_vdf_app_name = "Discord"
    discord_flatpak_app_id = "com.discordapp.Discord"

    # Exe-Pfade basierend auf VDF und Hypothesen
    discord_vdf_exe_full_path = "/usr/bin/flatpak" # bereits .strip('"') angewendet
    discord_exe_basename = "flatpak" # Deine neue Hypothese

    # Mögliche Exec-Zeile aus einer .desktop-Datei (aus ShortcutPath abgeleitet oder LaunchOptions)
    # LaunchOptions: run --branch=stable --arch=x86_64 --command=discord com.discordapp.Discord
    discord_desktop_exec_approx = f"flatpak run --branch=stable --arch=x86_64 --command=discord {discord_flatpak_app_id}"


    # Test D-New1: Basename des Exe + VDF AppName
    test_id_generation("D-New1: Basename Exe ('flatpak') + VDF AppName ('Discord')",
                       discord_exe_basename, discord_vdf_app_name,
                       discord_target_id, "Discord")

    # Test D-New2: Basename des Exe + Flatpak App ID als AppName
    test_id_generation("D-New2: Basename Exe ('flatpak') + FlatpakID als AppName",
                       discord_exe_basename, discord_flatpak_app_id,
                       discord_target_id, "Discord")

    # Test D-New3: Basename des Exe + (VDF AppName + Flatpak App ID) als AppName
    test_id_generation("D-New3: Basename Exe ('flatpak') + (VDF AppName + FlatpakID)",
                       discord_exe_basename, discord_vdf_app_name + discord_flatpak_app_id,
                       discord_target_id, "Discord")

    # Wiederholung von D6a (war einer der logischsten Ansätze, falls über .desktop-Datei hinzugefügt)
    test_id_generation("D6a-Wdh: Desktop Exec-Zeile als Exe + VDF AppName",
                       discord_desktop_exec_approx, discord_vdf_app_name,
                       discord_target_id, "Discord")

    # Wiederholung von D3a/D7 (FlatpakID als Exe)
    test_id_generation("D3a/D7-Wdh: FlatpakID als Exe + VDF AppName",
                       discord_flatpak_app_id, discord_vdf_app_name,
                       discord_target_id, "Discord")

    # Wiederholung von D2a/D8 (Vollständiger Pfad Exe + FlatpakID als AppName)
    test_id_generation("D2a/D8-Wdh: Vollst. Pfad Exe + FlatpakID als AppName",
                       discord_vdf_exe_full_path, discord_flatpak_app_id,
                       discord_target_id, "Discord")

    # Ein neuer Gedanke: Was ist, wenn der AppName für die ID-Generierung
    # die Flatpak-ID war und der Exe-Pfad die "Desktop Exec-Zeile"?
    test_id_generation("D-New4: Desktop Exec-Zeile als Exe + FlatpakID als AppName",
                       discord_desktop_exec_approx, discord_flatpak_app_id,
                       discord_target_id, "Discord") # Identisch zu D6b

    # Was ist, wenn der AppName der "command" aus den LaunchOptions ist?
    # LaunchOptions: run --branch=stable --arch=x86_64 --command=discord com.discordapp.Discord
    # Der Befehl ist "discord"
    discord_command_from_lo = "discord"
    test_id_generation("D-New5: Basename Exe ('flatpak') + Command aus LO ('discord') als AppName",
                       discord_exe_basename, discord_command_from_lo,
                       discord_target_id, "Discord")
    test_id_generation("D-New6: Vollst. Pfad Exe + Command aus LO ('discord') als AppName",
                       discord_vdf_exe_full_path, discord_command_from_lo,
                       discord_target_id, "Discord") # Identisch zu D4a/D5

    # Der `ShortcutPath` war /var/lib/flatpak/exports/share/applications/com.discordapp.Discord.desktop
    # Was, wenn dieser Pfad (oder Teile davon) verwendet wurde?
    discord_shortcut_path_vdf = "/var/lib/flatpak/exports/share/applications/com.discordapp.Discord.desktop"
    discord_shortcut_path_basename = "com.discordapp.Discord.desktop" # basename des ShortcutPath

    test_id_generation("D-New7: ShortcutPath (vollst.) als Exe + VDF AppName",
                       discord_shortcut_path_vdf, discord_vdf_app_name,
                       discord_target_id, "Discord")
    test_id_generation("D-New8: ShortcutPath Basename als Exe + VDF AppName",
                       discord_shortcut_path_basename, discord_vdf_app_name,
                       discord_target_id, "Discord")

    print("Alle Testfälle für Discord abgeschlossen.")
