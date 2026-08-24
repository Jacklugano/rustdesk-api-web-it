#!/usr/bin/env bash
#
# Pubblica il pacchetto di assistenza su un indirizzo temporaneo e non
# indovinabile, da mandare al cliente per il singolo intervento.
#
# Il pacchetto "sorgente" sta in una cartella NON pubblicata; questo script ne
# espone una copia sotto un percorso casuale in quella servita dal server, e
# rimuove le pubblicazioni scadute a ogni esecuzione.
#
# Uso:
#   ./nuovo-link.sh --url https://edesk.tuodominio.ch
#   ./nuovo-link.sh --url https://edesk.tuodominio.ch --ore 2
#   ./nuovo-link.sh --elenco          mostra i link attivi
#   ./nuovo-link.sh --revoca <id>     rimuove subito una pubblicazione
#
# Nota: il collegamento limita chi puo' TROVARE il pacchetto, non chi lo ha
# gia' scaricato. La chiave del server e' incorporata e non cambia, quindi un
# pacchetto scaricato resta valido anche dopo la scadenza del link.
#
set -euo pipefail

PACCHETTO="/opt/rustdesk/pacchetto"
PUBBLICA="/opt/rustdesk/downloads"
BASE_URL=""
ORE=8
AZIONE="crea"
ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pacchetto) PACCHETTO="$2"; shift 2 ;;
    --pubblica)  PUBBLICA="$2"; shift 2 ;;
    --url)       BASE_URL="${2%/}"; shift 2 ;;
    --ore)       ORE="$2"; shift 2 ;;
    --elenco)    AZIONE="elenco"; shift ;;
    --revoca)    AZIONE="revoca"; ID="$2"; shift 2 ;;
    -h|--help)   sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Opzione sconosciuta: $1" >&2; exit 1 ;;
  esac
done

[[ -d "$PUBBLICA" ]] || { echo "Errore: cartella pubblicata assente: $PUBBLICA" >&2; exit 1; }

# --- pulizia delle pubblicazioni scadute -----------------------------------
# Eseguita a ogni invocazione: nessun cron da configurare, e la cartella non
# accumula link dimenticati.
SCADUTI=0
while IFS= read -r d; do
  rm -rf "$d"; SCADUTI=$((SCADUTI + 1))
done < <(find "$PUBBLICA" -mindepth 1 -maxdepth 1 -type d -name 's-*' -mmin "+$((ORE * 60))" 2>/dev/null)
[[ "$SCADUTI" -gt 0 ]] && echo "Rimosse $SCADUTI pubblicazioni scadute."

case "$AZIONE" in
  elenco)
    echo "Link attivi in ${PUBBLICA}:"
    trovato=0
    for d in "$PUBBLICA"/s-*/; do
      [[ -d "$d" ]] || continue
      n="$(basename "$d")"
      eta="$(( ( $(date +%s) - $(stat -c %Y "$d") ) / 60 ))"
      echo "  ${n#s-}   creato ${eta} minuti fa"
      trovato=1
    done
    [[ "$trovato" -eq 0 ]] && echo "  nessuno"
    exit 0
    ;;
  revoca)
    [[ -n "$ID" ]] || { echo "Errore: indica l'identificativo da revocare." >&2; exit 1; }
    if [[ -d "${PUBBLICA}/s-${ID}" ]]; then
      rm -rf "${PUBBLICA}/s-${ID}"
      echo "Revocato: ${ID}"
    else
      echo "Nessuna pubblicazione con identificativo ${ID}." >&2
      exit 1
    fi
    exit 0
    ;;
esac

# --- creazione --------------------------------------------------------------
[[ -n "$BASE_URL" ]] || { echo "Errore: indica --url (es. https://edesk.tuodominio.ch)" >&2; exit 1; }
if [[ ! -f "${PACCHETTO}/index.html" ]]; then
  cat >&2 <<AIUTO
Errore: pacchetto sorgente non trovato in ${PACCHETTO}

Generalo indicando una cartella NON pubblicata, cosi' resta raggiungibile solo
attraverso i link temporanei:

  ./scripts/genera-client.sh --dominio ... --chiave-testo "..." \\
      --uscita ${PACCHETTO}
AIUTO
  exit 1
fi
[[ -w "$PUBBLICA" ]] || { echo "Errore: non hai permesso di scrittura su $PUBBLICA" >&2; exit 1; }

TOKEN="$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
DEST="${PUBBLICA}/s-${TOKEN}"
mkdir -p "$DEST"

# Collegamenti fisici invece di copie: i file pesanti sono identici a ogni
# intervento, quindi cento link occupano lo spazio di uno.
for f in "$PACCHETTO"/*; do
  [[ -f "$f" ]] || continue
  n="$(basename "$f")"
  [[ "$n" == "assistenza-rapida.zip" ]] && continue   # ricostruito qui sotto
  ln "$f" "${DEST}/${n}" 2>/dev/null || cp "$f" "${DEST}/"
done

# Gli installer scaricano il programma dalla radice pubblicata
# (/upload/rustdesk.exe): il binario generico deve quindi stare li'. Non
# contiene ne' chiave ne' configurazione, pubblicarlo non espone nulla.
if [[ -f "${PACCHETTO}/rustdesk.exe" ]]; then
  ln -f "${PACCHETTO}/rustdesk.exe" "${PUBBLICA}/rustdesk.exe" 2>/dev/null \
    || cp -f "${PACCHETTO}/rustdesk.exe" "${PUBBLICA}/rustdesk.exe"
fi

# --- configurazione servita a parte, non incorporata ------------------------
# La chiave resta fuori dal pacchetto scaricato: il programma la preleva
# all'avvio da questo indirizzo. Alla scadenza il file sparisce insieme alla
# cartella, quindi una copia vecchia del pacchetto non riesce piu' a
# configurarsi e si ferma con un messaggio chiaro.
# Nel batch la stringa e' in  set "CFG=..."  e nel PowerShell in  $Cfg = '...'
CONFIG_STR=""
if [[ -f "${PACCHETTO}/installa-rustdesk.bat" ]]; then
  CONFIG_STR="$(sed -n 's/^set "CFG=\([^"]*\)".*/\1/p' "${PACCHETTO}/installa-rustdesk.bat" | head -1)"
fi
if [[ -z "$CONFIG_STR" && -f "${PACCHETTO}/installa-rustdesk.ps1" ]]; then
  CONFIG_STR="$(sed -n "s/^\$Cfg[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" "${PACCHETTO}/installa-rustdesk.ps1" | head -1)"
fi
if [[ -z "$CONFIG_STR" ]]; then
  echo "Errore: configurazione non estraibile dal pacchetto in ${PACCHETTO}" >&2
  echo "Rigeneralo con genera-client.sh." >&2
  rm -rf "$DEST"; exit 1
fi
printf '%s' "$CONFIG_STR" > "${DEST}/config.txt"

SESSIONE="${BASE_URL}/upload/s-${TOKEN}"
TMPZIP="$(mktemp -d)"
cat > "${TMPZIP}/avvia-assistenza.bat" <<'PORT_EOF'
@echo off
setlocal
title Assistenza remota
cd /d "%TEMP%"

set "BASE=@@SESSIONE@@"

echo.
echo  Preparazione in corso, attendi qualche secondo...
echo.

curl -fsS "%BASE%/config.txt" -o rd-config.txt
if errorlevel 1 goto scaduto
set /p CFG=<rd-config.txt
del rd-config.txt >nul 2>&1
if "%CFG%"=="" goto scaduto

if not exist rustdesk-assistenza.exe (
  curl -fL --progress-bar "%BASE%/rustdesk.exe" -o rustdesk-assistenza.exe
  if errorlevel 1 goto scaduto
)

rustdesk-assistenza.exe --config %CFG%
start "" "rustdesk-assistenza.exe"

echo.
echo  Si aprira' una finestra con il tuo ID e la tua password:
echo  comunicali al tecnico e lascia la finestra aperta.
echo.
timeout /t 8 /nobreak >nul
exit /b 0

:scaduto
echo.
echo  ===========================================================
echo    Questo collegamento non e' piu' valido.
echo.
echo    Chiedi al tecnico un nuovo link per l'assistenza.
echo  ===========================================================
echo.
pause
exit /b 1
PORT_EOF
sed -i "s|@@SESSIONE@@|${SESSIONE}|" "${TMPZIP}/avvia-assistenza.bat"

if command -v zip >/dev/null 2>&1; then
  ( cd "$TMPZIP" && zip -q -j "${DEST}/assistenza-rapida.zip" avvia-assistenza.bat )
else
  python3 - "$TMPZIP" "${DEST}/assistenza-rapida.zip" <<'PYZ'
import sys, zipfile, os
d, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(d, 'avvia-assistenza.bat'), 'avvia-assistenza.bat')
PYZ
fi
rm -rf "$TMPZIP"

echo
echo "Link per questo intervento (valido ${ORE} ore):"
echo
echo "  ${BASE_URL}/upload/s-${TOKEN}/"
echo
echo "Per revocarlo subito:  ./nuovo-link.sh --revoca ${TOKEN}"
