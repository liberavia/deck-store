# ----- BEGINN Testskript-Ausschnitt (benötigt deine ID-Funktionen) -----
# Annahme: Deine ID-Funktionen (_init_crc32_tab, manual_crc32, etc.) sind hier definiert
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

# --- Steam ID Calculation Functions ---
def _calculate_crc32_int(text: str) -> int:
    """Calculates the CRC32 checksum using manual implementation."""
    crc = manual_crc32(text.encode('utf-8')); print(f"DEBUG ID:   Manual CRC32 Result={crc}"); return crc

def generate_64bit_appid_int(exe_path: str, app_name: str) -> int:
    """Generates the 64-bit integer AppID (SRM: generatePreliminaryId)."""
    print(f"DEBUG ID: generate_64bit_appid_int called with exe='{exe_path}', name='{app_name}'")
    crc = _calculate_crc32_int(exe_path + app_name)
    result_int = (crc | 0x80000000) << 32 | 0x02000000; print(f"DEBUG ID:   64-bit Int={result_int}"); return result_int

def generate_short_appid_str(exe_path: str, app_name: str) -> str:
    """Generates the short 32-bit AppID by shifting the 64-bit one (SRM: generateShortAppId)."""
    print(f"DEBUG ID: generate_short_appid_str (Shifted) called")
    long_appid_int = generate_64bit_appid_int(exe_path, app_name)
    short_id = long_appid_int >> 32; print(f"DEBUG ID:   Short Int (long >> 32)={short_id}"); return str(short_id)


def manual_crc32(data: bytes) -> int:
    """Calculates CRC32 using a manual implementation."""
    crc = 0xFFFFFFFF
    for byte in data: crc = (crc >> 8) ^ _crc32_tab[(crc ^ byte) & 0xFF]
    return ~crc & 0xFFFFFFFF


def test_id_generation(case_name, exe_input, name_input):
    generated_id = generate_short_appid_str(exe_input, name_input)
    print(f"Testfall: {case_name}")
    print(f"  Exe Input: '{exe_input}'")
    print(f"  Name Input: '{name_input}'")
    print(f"  Erzeugte Short ID: {generated_id}")
    if generated_id == "2491305535": # Die Ziel-ID für Fall Guys
        print("  >>>> TREFFER!!! <<<<")
    print("-" * 20)

# Bekannte Daten aus VDF
vdf_app_name = "Fall Guys"
vdf_exe_path = "/home/deck/Games/epic/FallGuys/RunFallGuys.exe" # Bereits von VDF-Quotes befreit
vdf_launch_options = "/home/deck/homebrew/plugins/Junk-Store/scripts/Extensions/Epic/epic-launcher.sh 0a2d9f6403244d12969e11da6713137b%command%"
epic_game_id = "0a2d9f6403244d12969e11da6713137b"
launcher_script_path = "/home/deck/homebrew/plugins/Junk-Store/scripts/Extensions/Epic/epic-launcher.sh"

# --- Testfälle ---
print("Starte ID-Generierungsversuche für Fall Guys (Ziel-ID: 2491305535)...\n")

# Baseline (hat 3796148381 ergeben)
test_id_generation("Baseline (dein Analyse-Skript)", vdf_exe_path, vdf_app_name)

# Test 1a
test_id_generation("1a: LaunchOptions als Exe", vdf_launch_options, vdf_app_name)

# Test 1b
test_id_generation("1b: Nur Launcher-Skript als Exe", launcher_script_path, vdf_app_name)

# Test 2a
test_id_generation("2a: VDF Exe + Epic ID", vdf_exe_path + epic_game_id, vdf_app_name)

# Test 2b
test_id_generation("2b: VDF Exe, AppName + Epic ID", vdf_exe_path, vdf_app_name + epic_game_id)

# Test 2c
test_id_generation("2c: Launcher-Skript + Epic ID als Exe", launcher_script_path + epic_game_id, vdf_app_name)

# ... weitere Tests nach Bedarf ...
# Beispiel: Was, wenn der AppName die Epic ID enthält?
test_id_generation("Custom: Launcher-Skript als Exe, Epic ID als Name", launcher_script_path, epic_game_id)

# ----- ENDE Testskript-Ausschnitt -----
