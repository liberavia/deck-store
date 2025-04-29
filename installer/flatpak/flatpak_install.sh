#!/bin/bash

# Stellt sicher, dass die Ausgabe auf Englisch ist
export LC_ALL=C

COMMAND=$1
APP_ID=$2
OUTPUT_FILE=$3
OPERATION_ID=$(uuidgen)

# Funktion zur Ausgabe von JSON Status-Updates
output_json() {
  local status=${1:-null}
  local progress=${2:-null}
  local speed=${3:-null}
  local eta=${4:-null}
  local error=${5:-null}
  [[ -z "$progress" || "$progress" == "null" ]] && progress_json="null" || progress_json=$progress
  if [[ -n "$speed" ]]; then
    speed_clean=$(echo "$speed" | sed -E 's/([0-9.,]+)\?/\1/' | xargs) #? entfernen
    speed_json="\"$speed_clean\""
  else
    speed_json="null"
  fi
  if [[ -n "$eta" ]]; then
      eta_clean=$(echo "$eta" | xargs) # Leerzeichen entfernen
      eta_json="\"$eta_clean\""
  else
      eta_json="null"
  fi
  if [[ -z "$error" || "$error" == "null" ]]; then
    error_json="null"
  else
    error_escaped=$(echo "$error" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
    error_json="\"$error_escaped\""
  fi
  echo "{\"operation_id\": \"$OPERATION_ID\", \"app_id\": \"$APP_ID\", \"status\": \"$status\", \"progress\": $progress_json, \"speed\": $speed_json, \"eta\": $eta_json, \"error\": $error_json}" >> "$OUTPUT_FILE"
}


# Initialer Status - abhängig vom Befehl?
# Vorerst lassen wir es bei "preparing" für beide.
output_json "preparing" null null null null

# Führe flatpak aus OHNE tr
stdbuf -oL flatpak "$COMMAND" --user --assumeyes "$APP_ID" 2>&1 | while IFS= read -r line; do
  line=$(echo "$line" | sed $'s/^\r*//') # Entferne führende \r

  # Variablen für jede Zeile zurücksetzen
  STATUS="unknown"
  PROGRESS=null
  SPEED=null
  ETA=null
  ERROR=null

  # --- Parsing Logic: Install, Uninstall, Andere ---

  # 1. Installation: Prüfe auf Fortschrittszeile UND extrahiere Prozente
  REGEX_PERCENT='^Installing\?\s+\?+\s+([0-9]+)%'
  if [[ "$COMMAND" == "install" && "$line" =~ $REGEX_PERCENT ]]; then
      PROGRESS=${BASH_REMATCH[1]} # Prozentzahl holen
      STATUS="installing" # Standardstatus

      # Versuche, Speed zu extrahieren
      SPEED_RAW=$(echo "$line" | grep -oP '[0-9.,]+\??\s*(?:k|M|G)i?B\/s')
      if [[ -n "$SPEED_RAW" ]]; then
          STATUS="downloading"
          SPEED=$SPEED_RAW
      fi

      # Versuche, ETA zu extrahieren
      ETA_RAW=$(echo "$line" | grep -oP '[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$')
      if [[ -n "$ETA_RAW" ]]; then
          ETA=$ETA_RAW
      fi

      # Status-Korrektur bei 100%
      if [[ "$PROGRESS" -eq 100 && "$STATUS" == "downloading" ]]; then
           STATUS="installing"
      fi

      output_json "$STATUS" "$PROGRESS" "$SPEED" "$ETA" "$ERROR"

  # 2. Deinstallation: Prüfe auf "Uninstalling?"
  elif [[ "$COMMAND" == "uninstall" && "$line" == "Uninstalling?" ]]; then
      STATUS="removing" # Oder "uninstalling"
      # Kein Progress, Speed, ETA bei Deinstallation bekannt
      output_json "$STATUS" null null null null

  # --- Fallback für andere Zeilentypen / Abschluss / Fehler ---
  elif [[ "$line" =~ ^Looking\ for\ matches\? ]]; then
     : # Ignoriere "preparing" hier (wurde schon initial gesendet)
  elif [[ "$line" =~ ^(Installation|Uninstall)\ complete\.? ]]; then # Erkennt beide Abschlussmeldungen
     STATUS="completed"
     # Setze Progress auf 100 bei erfolgreichem Abschluss, auch wenn es Uninstall war
     PROGRESS=100
     output_json "$STATUS" "$PROGRESS" null null null # Speed/ETA löschen
  elif [[ "$line" =~ Error:|error: ]]; then
     STATUS="failed"
     ERROR=$(echo "$line" | sed -e 's/^Error: //' -e 's/^error: //')
     output_json "$STATUS" null null null "$ERROR" # Progress/Speed/ETA löschen
  # Andere Zeilen ignorieren
  fi
done

EXIT_CODE=${PIPESTATUS[0]}
# Optional: Finalen Fehlerstatus senden, wenn Exit Code != 0 und kein Fehler erfasst wurde

# echo "--- Script Finished (Exit Code: $EXIT_CODE) ---" # Kann entfernt werden
exit $EXIT_CODE
