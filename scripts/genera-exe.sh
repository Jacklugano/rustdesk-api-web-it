#!/usr/bin/env bash
#
# Compila sul server l'installer Windows con icona, a partire dallo script
# PowerShell prodotto da genera-client.sh.
#
# PS2EXE richiede Windows PowerShell e non gira su Linux: qui si usa invece il
# cross-compilatore mingw-w64. L'eseguibile prodotto incorpora lo script, il
# manifesto di elevazione (Windows chiede i privilegi prima dell'avvio),
# l'icona e le informazioni di versione.
#
# Uso:
#   ./genera-exe.sh
#   ./genera-exe.sh --azienda "Nome Srl" --titolo "Assistenza"
#
# Opzioni:
#   --ps1 <file>       script PowerShell da incorporare
#                      (default: /opt/rustdesk/downloads/installa-rustdesk.ps1)
#   --icona <file>     icona .ico (default: branding/elettrosmart.ico del repo)
#   --uscita <dir>     dove scrivere l'eseguibile (default: /opt/rustdesk/downloads)
#   --nome <file>      nome dell'eseguibile (default: installa-rustdesk.exe)
#   --azienda <testo>  campo CompanyName
#   --titolo <testo>   campo ProductName, mostrato anche nella richiesta di Windows
#   --versione <x.y.z> versione del file
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PS1_FILE="/opt/rustdesk/downloads/installa-rustdesk.ps1"
ICONA="${REPO}/branding/elettrosmart.ico"
USCITA="/opt/rustdesk/downloads"
NOME="installa-rustdesk.exe"
AZIENDA="Elettrosmart Sagl"
TITOLO="Assistenza Remota"
VERSIONE="1.0.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ps1)      PS1_FILE="$2"; shift 2 ;;
    --icona)    ICONA="$2"; shift 2 ;;
    --uscita)   USCITA="$2"; shift 2 ;;
    --nome)     NOME="$2"; shift 2 ;;
    --azienda)  AZIENDA="$2"; shift 2 ;;
    --titolo)   TITOLO="$2"; shift 2 ;;
    --versione) VERSIONE="$2"; shift 2 ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Opzione sconosciuta: $1" >&2; exit 1 ;;
  esac
done

# --- prerequisiti ----------------------------------------------------------
CC="x86_64-w64-mingw32-gcc"
RC="x86_64-w64-mingw32-windres"
if ! command -v "$CC" >/dev/null 2>&1 || ! command -v "$RC" >/dev/null 2>&1; then
  cat >&2 <<'AIUTO'
Errore: manca il cross-compilatore per Windows.

  sudo apt install mingw-w64

Su Debian e Ubuntu il pacchetto fornisce sia x86_64-w64-mingw32-gcc sia
x86_64-w64-mingw32-windres. Su Fedora il pacchetto e' mingw64-gcc.
AIUTO
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo "Errore: serve python3." >&2; exit 1; }

[[ -r "$PS1_FILE" ]] || { echo "Errore: script non leggibile: $PS1_FILE" >&2
                          echo "Genera prima il pacchetto con genera-client.sh." >&2; exit 1; }
[[ -r "$ICONA" ]]    || { echo "Errore: icona non leggibile: $ICONA" >&2; exit 1; }

if grep -q '@@CONFIG@@' "$PS1_FILE"; then
  echo "Errore: $PS1_FILE contiene ancora i segnaposto." >&2
  echo "E' il modello, non lo script generato: usa quello prodotto da genera-client.sh." >&2
  exit 1
fi

if [[ ! -w "$USCITA" ]]; then
  echo "Errore: non hai permesso di scrittura su $USCITA" >&2
  echo "  sudo chown -R \"\$USER\" \"$USCITA\"" >&2
  exit 1
fi

# versione in formato numerico per le risorse Windows (x,y,z,0).
# Il riempimento con zeri copre le forme abbreviate come "1" o "1.2"; il campo
# finale scarta l'eccedenza, altrimenti "read" gli assegnerebbe tutto il resto
# della stringa e la risorsa risulterebbe malformata.
if [[ ! "$VERSIONE" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "Errore: versione non valida: $VERSIONE (attesa nella forma 1.0.0)" >&2
  exit 1
fi
IFS='.' read -r V1 V2 V3 _ <<< "${VERSIONE}.0.0.0"
VERNUM="${V1},${V2},${V3},0"

LAVORO="$(mktemp -d)"
trap 'rm -rf "$LAVORO"' EXIT
cp "$ICONA" "${LAVORO}/icona.ico"

# --- manifesto: elevazione richiesta all'avvio ------------------------------
cat > "${LAVORO}/app.manifest" <<'MANIFEST_EOF'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>
    </application>
  </compatibility>
</assembly>
MANIFEST_EOF

# --- risorse: icona, manifesto, informazioni di versione --------------------
cat > "${LAVORO}/app.rc" <<RC_EOF
1 ICON "icona.ico"
1 24 "app.manifest"

1 VERSIONINFO
FILEVERSION ${VERNUM}
PRODUCTVERSION ${VERNUM}
FILEOS 0x4L
FILETYPE 0x1L
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040904B0"
    BEGIN
      VALUE "CompanyName",      "${AZIENDA}"
      VALUE "FileDescription",  "${TITOLO}"
      VALUE "FileVersion",      "${VERSIONE}"
      VALUE "InternalName",     "${NOME}"
      VALUE "OriginalFilename", "${NOME}"
      VALUE "ProductName",      "${TITOLO}"
      VALUE "ProductVersion",   "${VERSIONE}"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x409, 1200
  END
END
RC_EOF

# --- sorgente C: incorpora lo script come array di byte ---------------------
# Un array di byte invece di una stringa letterale: nessun problema di
# escape con virgolette, apostrofi o accapo presenti nello script.
python3 - "$PS1_FILE" "${LAVORO}/script.h" <<'PY'
import sys
dati = open(sys.argv[1], 'rb').read()
righe = []
for i in range(0, len(dati), 16):
    righe.append('  ' + ','.join(f'0x{b:02x}' for b in dati[i:i+16]) + ',')
with open(sys.argv[2], 'w') as f:
    f.write('static const unsigned char SCRIPT[] = {\n')
    f.write('\n'.join(righe))
    f.write('\n};\n')
print(f'script incorporato: {len(dati)} byte')
PY

cat > "${LAVORO}/launcher.c" <<'C_EOF'
#include <windows.h>
#include <stdio.h>
#include "script.h"

/* Scrive lo script incorporato in una cartella temporanea e lo esegue.
   Il manifesto ha gia' richiesto l'elevazione, quindi qui si e' amministratori. */
int main(void)
{
    char cartella[MAX_PATH], percorso[MAX_PATH], comando[MAX_PATH * 2];
    FILE *f;
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    DWORD uscita = 1;

    if (!GetTempPathA(MAX_PATH, cartella)) {
        printf("\n  Impossibile determinare la cartella temporanea.\n");
        getchar();
        return 1;
    }
    snprintf(percorso, sizeof(percorso), "%sinstalla-rustdesk.ps1", cartella);

    f = fopen(percorso, "wb");
    if (!f) {
        printf("\n  Impossibile scrivere %s\n", percorso);
        getchar();
        return 1;
    }
    fwrite(SCRIPT, 1, sizeof(SCRIPT), f);
    fclose(f);

    snprintf(comando, sizeof(comando),
             "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%s\"",
             percorso);

    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    if (!CreateProcessA(NULL, comando, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
        printf("\n  Avvio di PowerShell non riuscito (errore %lu).\n",
               (unsigned long)GetLastError());
        DeleteFileA(percorso);
        getchar();
        return 1;
    }

    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &uscita);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    DeleteFileA(percorso);

    return (int)uscita;
}
C_EOF

# --- compilazione -----------------------------------------------------------
echo "Compilo..."
( cd "$LAVORO" && "$RC" app.rc -O coff -o app.res )
( cd "$LAVORO" && "$CC" launcher.c app.res -o uscita.exe \
    -O2 -s -static-libgcc -Wall )

cp "${LAVORO}/uscita.exe" "${USCITA}/${NOME}"
echo
echo "Fatto: ${USCITA}/${NOME} ($(du -h "${USCITA}/${NOME}" | cut -f1))"
echo
echo "Rilancia genera-client.sh: la pagina di download proporra' l'eseguibile."
