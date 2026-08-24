#!/usr/bin/env bash
#
# Genera un pacchetto di installazione RustDesk preconfigurato, pronto da
# inviare a un cliente, e lo pubblica nella cartella scaricabile dell'API.
#
# Uso:
#   ./genera-client.sh --dominio rd.tuodominio.it --api https://rd.tuodominio.it
#
# Opzioni:
#   --dominio <host>     Host del server ID (obbligatorio)
#   --api <url>          URL pubblico dell'API (default: https://<dominio>)
#   --chiave <file>      File della chiave pubblica. Se omesso, la chiave
#                        viene letta dal container hbbs, che funziona
#                        qualunque sia il percorso dei volumi.
#   --chiave-testo <k>   Incolla la chiave direttamente (la trovi nella home
#                        della console, riquadro "Configurazione del server")
#   --container <nome>   Container da cui leggere la chiave (default: hbbs)
#   --uscita <dir>       Cartella di pubblicazione
#                        (default: /opt/rustdesk/downloads)
#   --versione <ver>     Versione RustDesk da scaricare (default: ultima)
#   --senza-download     Non scaricare l'eseguibile (per provare la generazione)
#   --con-exe            Compila anche l'installer Windows con icona, invocando
#                        genera-exe.sh, e lo propone nella pagina di download
#
set -euo pipefail

DOMINIO=""
API_URL=""
CHIAVE_FILE=""
CHIAVE_TESTO=""
CONTAINER="hbbs"
USCITA="/opt/rustdesk/downloads"
VERSIONE=""
SCARICA=1
CON_EXE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dominio)        DOMINIO="$2"; shift 2 ;;
    --api)            API_URL="$2"; shift 2 ;;
    --chiave)         CHIAVE_FILE="$2"; shift 2 ;;
    --chiave-testo)   CHIAVE_TESTO="$2"; shift 2 ;;
    --container)      CONTAINER="$2"; shift 2 ;;
    --uscita)         USCITA="$2"; shift 2 ;;
    --versione)       VERSIONE="$2"; shift 2 ;;
    --senza-download) SCARICA=0; shift ;;
    --con-exe)        CON_EXE=1; shift ;;
    -h|--help)        sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Opzione sconosciuta: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$DOMINIO" ]] || { echo "Errore: --dominio è obbligatorio." >&2; exit 1; }
[[ -n "$API_URL" ]] || API_URL="https://${DOMINIO}"

# La chiave si può ottenere in tre modi. Il percorso su disco è il meno
# affidabile: con uno stack Portainer i volumi relativi finiscono nella
# directory di lavoro interna, non dove ci si aspetta. Per questo, se non
# viene indicato nulla, la si cerca direttamente nei container in esecuzione.
CHIAVE=""
ORIGINE=""
DIAGNOSI=""

# Individua come invocare docker: diretto, con sudo, o per niente.
DOCKER=""
if command -v docker >/dev/null 2>&1; then
  if docker ps >/dev/null 2>&1; then
    DOCKER="docker"
  elif sudo -n docker ps >/dev/null 2>&1; then
    DOCKER="sudo docker"
    echo "Nota: docker richiede privilegi elevati, uso sudo."
  else
    DIAGNOSI="$(docker ps 2>&1 | head -2 || true)"
  fi
else
  DIAGNOSI="il comando docker non è installato"
fi

# Cerca la chiave dentro un container, provando i percorsi noti.
leggi_da_container () {
  $DOCKER exec "$1" sh -c '
    cat /root/id_ed25519.pub 2>/dev/null ||
    cat /rustdesk_key/id_ed25519.pub 2>/dev/null ||
    { f=$(find / -maxdepth 5 -name id_ed25519.pub -print -quit 2>/dev/null); [ -n "$f" ] && cat "$f"; }
  ' 2>/dev/null
}

if [[ -n "$CHIAVE_TESTO" ]]; then
  CHIAVE="$CHIAVE_TESTO"
  ORIGINE="parametro --chiave-testo"

elif [[ -n "$CHIAVE_FILE" ]]; then
  [[ -r "$CHIAVE_FILE" ]] || { echo "Errore: file non leggibile: $CHIAVE_FILE" >&2; exit 1; }
  CHIAVE="$(cat "$CHIAVE_FILE")"
  ORIGINE="file $CHIAVE_FILE"

elif [[ -n "$DOCKER" ]]; then
  # Il nome del container non è prevedibile: Portainer antepone il nome dello
  # stack, e chi ha scritto il compose può averlo cambiato. Si costruisce
  # quindi una lista di candidati per nome e per immagine.
  CANDIDATI=("$CONTAINER")
  while IFS= read -r n; do [[ -n "$n" ]] && CANDIDATI+=("$n"); done < <(
    $DOCKER ps --format '{{.Names}}' 2>/dev/null | grep -iE 'hbbs|hbbr' || true
  )
  while IFS= read -r n; do [[ -n "$n" ]] && CANDIDATI+=("$n"); done < <(
    $DOCKER ps --format '{{.Names}}|{{.Image}}' 2>/dev/null \
      | awk -F'|' '$2 ~ /rustdesk/ {print $1}' || true
  )

  VISTI=""
  for c in "${CANDIDATI[@]}"; do
    [[ -z "$c" ]] && continue
    case " $VISTI " in *" $c "*) continue ;; esac
    VISTI="$VISTI $c"
    echo "Cerco la chiave nel container ${c}..."
    K="$(leggi_da_container "$c" || true)"
    if [[ -n "$K" ]]; then
      CHIAVE="$K"
      ORIGINE="container ${c}"
      break
    fi
  done

  if [[ -z "$CHIAVE" ]]; then
    DIAGNOSI="container esaminati:${VISTI:- nessuno}"
  fi
fi

# Rimuove spazi e ritorni a capo: hbbs salva la chiave senza newline finale,
# ma docker exec e gli editor ne aggiungono uno, e finirebbe dentro la
# stringa di configurazione rendendo la chiave non corrispondente.
CHIAVE="$(printf '%s' "$CHIAVE" | tr -d '[:space:]')"

if [[ -z "$CHIAVE" ]]; then
  {
    echo "Errore: chiave pubblica non trovata."
    echo
    echo "Diagnosi: ${DIAGNOSI:-nessuna}"
    if [[ -n "$DOCKER" ]]; then
      echo
      echo "Container attualmente in esecuzione:"
      $DOCKER ps --format '  {{.Names}}  ({{.Image}})' 2>/dev/null || true
    fi
    cat <<'AIUTO'

Come procedere, in ordine di comodità:

  1. Copiala dalla console web: home -> "Configurazione del server",
     campo "Chiave pubblica", pulsante Copia. Poi rilancia con:
       ./genera-client.sh --dominio ... --chiave-testo "LA_CHIAVE"

  2. Indica il container giusto, scegliendolo dall'elenco qui sopra:
       ./genera-client.sh --dominio ... --container <nome>

  3. Cerca il file sul disco e passalo con --chiave:
       sudo find /var/lib/docker -name id_ed25519.pub 2>/dev/null

Se docker richiede privilegi, rilancia lo script con sudo.
AIUTO
  } >&2
  exit 1
fi

echo "Chiave letta da: ${ORIGINE:-sconosciuta}"

# RustDesk accetta la configurazione come base64 del JSON, con la stringa
# risultante rovesciata e senza il riempimento finale.
JSON="$(printf '{"host":"%s:21116","key":"%s","api":"%s"}' "$DOMINIO" "$CHIAVE" "$API_URL")"
CONFIG="$(printf '%s' "$JSON" | base64 -w0 | tr -d '=' | rev)"

# La cartella di solito viene creata con sudo, quindi appartiene a root
# mentre lo script gira da utente normale: senza questo controllo il primo
# segnale del problema sarebbe un errore di curl a metà download.
if ! mkdir -p "$USCITA" 2>/dev/null; then
  echo "Errore: impossibile creare $USCITA" >&2
  exit 1
fi
if [[ ! -w "$USCITA" ]]; then
  cat >&2 <<AIUTO
Errore: non hai permesso di scrittura su $USCITA

La cartella appartiene probabilmente a root. Due soluzioni:

  sudo chown -R "\$USER" "$USCITA"
     (assegna la cartella al tuo utente, poi rilancia lo script)

  sudo ./scripts/genera-client.sh ...
     (oppure esegui direttamente lo script con sudo)
AIUTO
  exit 1
fi

# --- eseguibile ------------------------------------------------------------
EXE="rustdesk.exe"
if [[ "$SCARICA" -eq 1 ]]; then
  URL=""
  if [[ -z "$VERSIONE" ]]; then
    echo "Cerco l'ultima versione di RustDesk..."
    # Una sola chiamata: da qui si ricavano sia la versione sia l'indirizzo
    # reale dell'eseguibile, senza doverlo ricostruire a mano e senza
    # rompersi se un domani cambia lo schema dei nomi.
    REL="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest 2>/dev/null || true)"
    VERSIONE="$(printf '%s' "$REL" | grep -m1 '"tag_name"' | cut -d'"' -f4 || true)"
    URL="$(printf '%s' "$REL" | grep -oE 'https://[^"]+-x86_64\.exe' | head -1 || true)"
    [[ -n "$VERSIONE" ]] || { echo "Errore: versione non determinata. Usa --versione." >&2; exit 1; }
  fi
  [[ -n "$URL" ]] || URL="https://github.com/rustdesk/rustdesk/releases/download/${VERSIONE}/rustdesk-${VERSIONE}-x86_64.exe"
  echo "Scarico RustDesk ${VERSIONE}..."
  echo "  da: ${URL}"
  if ! curl -fL --progress-bar "$URL" -o "${USCITA}/${EXE}"; then
    rm -f "${USCITA}/${EXE}"
    echo "Errore: download non riuscito da ${URL}" >&2
    echo "Verifica la connessione, oppure indica una versione con --versione." >&2
    exit 1
  fi
  echo "Scaricato: ${USCITA}/${EXE} ($(du -h "${USCITA}/${EXE}" | cut -f1))"
else
  VERSIONE="${VERSIONE:-non-scaricata}"
  echo "Download saltato (--senza-download)."
fi

EXE_URL="${API_URL%/}/upload/${EXE}"

# --- script di installazione per il cliente --------------------------------
cat > "${USCITA}/installa-rustdesk.bat" <<'BAT_EOF'
@echo off
setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
title Installazione assistenza remota

rem Se non siamo amministratori ci si rilancia da soli, chiedendo a Windows
rem l'elevazione: al cliente basta un doppio clic e un "Si" alla richiesta,
rem senza dover conoscere il menu del tasto destro.
net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo  Richiedo l'autorizzazione di Windows...
  rem il percorso passa da una variabile d'ambiente: cosi' spazi e apostrofi
  rem nel nome utente non rompono la riga di comando di PowerShell
  set "SELF=%~f0"
  powershell -NoProfile -Command "try { Start-Process -FilePath $env:SELF -Verb RunAs } catch { exit 1 }"
  if errorlevel 1 (
    echo.
    echo  Autorizzazione negata.
    echo  Senza i permessi di amministratore l'installazione non puo' proseguire.
    echo  Riprova e rispondi "Si" alla richiesta di Windows.
    echo.
    pause
  )
  exit /b
)

set "CFG=@@CONFIG@@"
set "EXEURL=@@EXE_URL@@"
set "DOMINIO=@@DOMINIO@@"
set "APIURL=@@API@@"
set "CHIAVE=@@CHIAVE@@"

rem password permanente casuale di 12 caratteri
set "ALFA=ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
set "PWD="
for /L %%b in (1,1,12) do (
  set /A R=!RANDOM! %% 57
  for %%c in (!R!) do set "PWD=!PWD!!ALFA:~%%c,1!"
)

if not exist "%TEMP%\rd" mkdir "%TEMP%\rd"
pushd "%TEMP%\rd"

echo.
echo  [1/4] Scarico il programma...
curl -fL --progress-bar "%EXEURL%" -o rustdesk.exe
if errorlevel 1 (
  echo  Download non riuscito. Controlla la connessione a Internet.
  pause & popd & exit /b 1
)

echo  [2/4] Installo...
start /wait "" rustdesk.exe --silent-install
timeout /t 15 /nobreak >nul

set "RD=%ProgramFiles%\RustDesk\rustdesk.exe"
if not exist "%RD%" (
  echo  Installazione non riuscita: %RD% non trovato.
  pause & popd & exit /b 1
)

echo  [3/4] Configuro il collegamento al server...
start /wait "" "%RD%" --install-service
timeout /t 10 /nobreak >nul
"%RD%" --config %CFG%
"%RD%" --password %PWD%

rem Alcune versioni applicano host e chiave della stringa --config ma
rem ignorano il campo 'api': senza, il client si inventa http://<host>:21114
rem e il login va in timeout. Le opzioni si scrivono quindi anche nei file
rem di configurazione, sia dell'utente che del servizio.
for %%d in ("%APPDATA%\RustDesk\config" "%WinDir%\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config") do (
  if not exist "%%~d" mkdir "%%~d"
  > "%%~d\RustDesk2.toml" (
    echo rendezvous_server = '%DOMINIO%:21116'
    echo.
    echo [options]
    echo custom-rendezvous-server = '%DOMINIO%'
    echo relay-server = '%DOMINIO%:21117'
    echo api-server = '%APIURL%'
    echo key = '%CHIAVE%'
  )
)

rem il servizio rilegge la configurazione solo al riavvio
net stop RustDesk >nul 2>&1
net start RustDesk >nul 2>&1
timeout /t 5 /nobreak >nul

popd

echo  [4/4] Leggo l'identificativo...
rem eseguito dalla cartella di installazione: un percorso con spazi dentro
rem un for /f richiede un annidamento di virgolette che cmd sbaglia spesso
pushd "%ProgramFiles%\RustDesk"
for /f "delims=" %%i in ('rustdesk.exe --get-id') do set "RID=%%i"
popd
cls
echo.
echo  ===========================================================
echo    Installazione completata.
echo.
echo    Comunica questi due dati al tecnico:
echo.
echo      ID        : %RID%
echo      Password  : %PWD%
echo.
echo  ===========================================================
echo.
echo  Puoi chiudere questa finestra.
echo.
pause
BAT_EOF

# I segnaposto sono sostituiti dopo la scrittura, così il contenuto del file
# batch (pieno di % e !) non viene toccato dalla shell.
sed -i "s|@@CONFIG@@|${CONFIG}|; s|@@EXE_URL@@|${EXE_URL}|; s|@@DOMINIO@@|${DOMINIO}|g; s|@@API@@|${API_URL}|g; s|@@CHIAVE@@|${CHIAVE}|g" "${USCITA}/installa-rustdesk.bat"

# --- pacchetto portable ----------------------------------------------------
# Nessuna installazione e nessun privilegio: il cliente esegue, legge ID e
# password dalla finestra di RustDesk, e a fine intervento non resta nulla.
# Gira l'eseguibile ufficiale, firmato, quindi niente avviso SmartScreen.
if [[ -f "${USCITA}/${EXE}" ]]; then
  PORTATILE="$(mktemp -d)"
  cp "${USCITA}/${EXE}" "${PORTATILE}/rustdesk.exe"

  cat > "${PORTATILE}/avvia-assistenza.bat" <<'PORT_EOF'
@echo off
setlocal
title Assistenza remota
cd /d "%~dp0"

if not exist "rustdesk.exe" (
  echo.
  echo  Manca il file rustdesk.exe.
  echo  Estrai TUTTO il contenuto della cartella compressa, non solo questo file.
  echo.
  pause
  exit /b 1
)

echo.
echo  Avvio in corso, attendi qualche secondo...

rem applica la configurazione del server, poi apre il programma
rustdesk.exe --config @@CONFIG@@
start "" "rustdesk.exe"

echo.
echo  Si aprira' una finestra con il tuo ID e la tua password:
echo  comunicali al tecnico e lascia la finestra aperta.
echo.
timeout /t 8 /nobreak >nul
PORT_EOF

  sed -i "s|@@CONFIG@@|${CONFIG}|" "${PORTATILE}/avvia-assistenza.bat"

  if command -v zip >/dev/null 2>&1; then
    ( cd "$PORTATILE" && zip -q -j "${USCITA}/assistenza-rapida.zip" avvia-assistenza.bat rustdesk.exe )
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$PORTATILE" "${USCITA}/assistenza-rapida.zip" <<'PYZIP'
import sys, zipfile, os
d, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for f in ('avvia-assistenza.bat', 'rustdesk.exe'):
        z.write(os.path.join(d, f), f)
PYZIP
  fi
  rm -rf "$PORTATILE"
  echo "Pacchetto portable creato."
else
  echo "Attenzione: manca ${EXE}, pacchetto portable non creato." >&2
fi

# --- icona ----------------------------------------------------------------
# Serve solo al momento della compilazione dell'eseguibile, ma pubblicandola
# qui la si scarica dalla macchina Windows con lo stesso indirizzo degli altri
# file, senza passare da GitHub e senza autenticazione.
ICONA="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/branding/elettrosmart.ico"
if [[ -f "$ICONA" ]]; then
  cp -f "$ICONA" "${USCITA}/elettrosmart.ico"
fi

# --- script PowerShell (sorgente per l'eseguibile) -------------------------
cat > "${USCITA}/installa-rustdesk.ps1" <<'PS_EOF'
# Installazione assistenza remota.
# Compilabile in .exe con PS2EXE: vedi README, sezione "Eseguibile con icona".

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # senza questo Invoke-WebRequest e' lentissimo

$Cfg    = '@@CONFIG@@'
$ExeUrl = '@@EXE_URL@@'

function Riga($testo, $colore = 'Gray') { Write-Host $testo -ForegroundColor $colore }

try {
    $Host.UI.RawUI.WindowTitle = 'Assistenza remota'
} catch { }

# --- privilegi -------------------------------------------------------------
$identita  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identita)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Riga ''
    Riga '  Servono i privilegi di amministratore.' 'Yellow'
    Riga '  Chiudi questa finestra, riavvia il programma e rispondi Si'
    Riga '  alla richiesta di Windows.'
    Riga ''
    Read-Host '  Premi INVIO per chiudere' | Out-Null
    exit 1
}

try {
    # --- password permanente casuale ---------------------------------------
    $alfabeto = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $Password = -join (1..12 | ForEach-Object { $alfabeto[(Get-Random -Maximum $alfabeto.Length)] })

    $cartella = Join-Path $env:TEMP 'rustdesk-setup'
    New-Item -ItemType Directory -Force -Path $cartella | Out-Null
    $scaricato = Join-Path $cartella 'rustdesk.exe'

    Riga ''
    Riga '  [1/4] Scarico il programma...' 'Cyan'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ExeUrl -OutFile $scaricato -UseBasicParsing

    Riga '  [2/4] Installo...' 'Cyan'
    Start-Process -FilePath $scaricato -ArgumentList '--silent-install' -Wait

    # L'installer termina prima che i file siano al loro posto: si attende
    # l'eseguibile invece di sperare in una pausa a tempo fisso.
    $rustdesk = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'
    $scadenza = (Get-Date).AddSeconds(120)
    while (-not (Test-Path $rustdesk) -and (Get-Date) -lt $scadenza) {
        Start-Sleep -Seconds 2
    }
    if (-not (Test-Path $rustdesk)) {
        throw "Installazione non riuscita: $rustdesk non trovato."
    }

    Riga '  [3/4] Configuro il collegamento al server...' 'Cyan'
    Start-Process -FilePath $rustdesk -ArgumentList '--install-service' -Wait
    Start-Sleep -Seconds 8
    & $rustdesk --config $Cfg
    & $rustdesk --password $Password

    # Alcune versioni applicano host e chiave della stringa --config ma
    # ignorano il campo 'api': senza, il client si inventa http://<host>:21114
    # e il login va in timeout. Le opzioni si scrivono quindi anche nei file
    # di configurazione, sia dell'utente che del servizio.
    $Toml = @'
rendezvous_server = '@@DOMINIO@@:21116'

[options]
custom-rendezvous-server = '@@DOMINIO@@'
relay-server = '@@DOMINIO@@:21117'
api-server = '@@API@@'
key = '@@CHIAVE@@'
'@
    $percorsi = @(
        (Join-Path $env:APPDATA 'RustDesk\config\RustDesk2.toml'),
        (Join-Path $env:WinDir 'ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml')
    )
    foreach ($p in $percorsi) {
        New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
        Set-Content -Path $p -Value $Toml -Encoding ASCII
    }

    # il servizio rilegge la configurazione solo al riavvio
    Restart-Service -Name 'RustDesk' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    Riga '  [4/4] Leggo l''identificativo...' 'Cyan'
    $Identificativo = (& $rustdesk --get-id | Select-Object -Last 1)
    if ($Identificativo) { $Identificativo = $Identificativo.ToString().Trim() }

    Clear-Host
    Riga ''
    Riga '  ===========================================================' 'DarkCyan'
    Riga ''
    Riga '    Installazione completata.' 'Green'
    Riga ''
    Riga '    Comunica questi due dati al tecnico:'
    Riga ''
    Riga "      ID        :  $Identificativo" 'White'
    Riga "      Password  :  $Password" 'White'
    Riga ''
    Riga '  ===========================================================' 'DarkCyan'
    Riga ''
    Read-Host '  Premi INVIO per chiudere' | Out-Null
}
catch {
    Riga ''
    Riga '  Qualcosa non ha funzionato:' 'Red'
    Riga "  $($_.Exception.Message)" 'Red'
    Riga ''
    Riga '  Riferisci questo messaggio al tecnico.'
    Riga ''
    Read-Host '  Premi INVIO per chiudere' | Out-Null
    exit 1
}
PS_EOF

sed -i "s|@@CONFIG@@|${CONFIG}|; s|@@EXE_URL@@|${EXE_URL}|; s|@@DOMINIO@@|${DOMINIO}|g; s|@@API@@|${API_URL}|g; s|@@CHIAVE@@|${CHIAVE}|g" "${USCITA}/installa-rustdesk.ps1"

# --- archivio ZIP ----------------------------------------------------------
# Chrome ed Edge bloccano il download diretto dei file .bat, spesso senza
# spiegazioni. Dentro uno ZIP passano, quindi lo ZIP è la via principale e il
# .bat resta disponibile come ripiego.
if command -v zip >/dev/null 2>&1; then
  ( cd "$USCITA" && zip -q -j installa-rustdesk.zip installa-rustdesk.bat installa-rustdesk.ps1 )
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$USCITA" <<'PY'
import sys, zipfile, os
d = sys.argv[1]
with zipfile.ZipFile(os.path.join(d, 'installa-rustdesk.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
    for f in ('installa-rustdesk.bat', 'installa-rustdesk.ps1'):
        z.write(os.path.join(d, f), f)
PY
else
  echo "Attenzione: né zip né python3 disponibili, archivio non creato." >&2
  echo "I browser bloccano il download diretto dei .bat: installa uno dei due." >&2
fi

# --- installer Windows compilato -------------------------------------------
# Va fatto prima della pagina, che decide cosa proporre in base alla presenza
# dell'eseguibile: invertendo l'ordine servirebbe una seconda passata.
if [[ "$CON_EXE" -eq 1 ]]; then
  COMPILA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/genera-exe.sh"
  if [[ ! -x "$COMPILA" ]]; then
    echo "Errore: $COMPILA non trovato o non eseguibile." >&2
    exit 1
  fi
  echo
  "$COMPILA" --ps1 "${USCITA}/installa-rustdesk.ps1" --uscita "$USCITA"
  echo
fi

# --- pagina di download ----------------------------------------------------
# Due percorsi con priorita' diverse. Il portable e' in evidenza: usa
# l'eseguibile ufficiale firmato, non chiede privilegi e non lascia tracce,
# quindi e' quello giusto per l'assistenza occasionale. L'installazione
# permanente resta piu' in basso, in tono minore.
if [[ -f "${USCITA}/assistenza-rapida.zip" ]]; then
  PORTABILE_OK=1
else
  PORTABILE_OK=0
  echo "Attenzione: la pagina proporra' solo l'installazione." >&2
fi

if [[ -f "${USCITA}/installa-rustdesk.exe" ]]; then
  INSTALL_FILE="installa-rustdesk.exe"
  INSTALL_NOTA="Aprilo con un doppio clic e rispondi <strong>Sì</strong> alla richiesta di Windows."
  echo "Trovato installa-rustdesk.exe: sara' quello proposto per l'installazione."
else
  INSTALL_FILE="installa-rustdesk.zip"
  INSTALL_NOTA="Estrai la cartella compressa, apri <code>installa-rustdesk.bat</code> e rispondi <strong>Sì</strong> alla richiesta di Windows."
fi

cat > "${USCITA}/index.html" <<'HTML_EOF'
<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Assistenza remota — Download</title>
<style>
  :root {
    --bg: #f4f6fb; --surface: #fff; --border: #e4e9f2;
    --text: #1f2733; --muted: #6b7a90; --primary: #3b6ef0;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0f141d; --surface: #171e2a; --border: #273140;
      --text: #e6ebf2; --muted: #93a1b5;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 32px 20px; background: var(--bg); color: var(--text);
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    line-height: 1.6;
  }
  .wrap { max-width: 620px; margin: 0 auto; }
  h1 { font-size: 24px; margin: 0 0 8px; letter-spacing: -0.02em; }
  .sub { color: var(--muted); margin: 0 0 28px; }
  .card {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 12px; padding: 24px; margin-bottom: 20px;
  }
  .btn {
    display: inline-block; background: var(--primary); color: #fff;
    text-decoration: none; padding: 14px 24px; border-radius: 8px;
    font-weight: 600; font-size: 16px;
  }
  .btn:hover { filter: brightness(1.08); }
  ol { padding-left: 20px; margin: 0; }
  li { margin-bottom: 10px; }
  .warn {
    background: color-mix(in srgb, #d97706 12%, transparent);
    border-left: 3px solid #d97706; padding: 12px 16px;
    border-radius: 6px; font-size: 14px; margin-top: 16px;
  }
  code {
    background: var(--bg); border: 1px solid var(--border);
    padding: 2px 6px; border-radius: 4px; font-size: 13px;
  }
  footer { color: var(--muted); font-size: 13px; text-align: center; }
  h2 { font-size: 17px; margin: 0 0 12px; }
  /* l'installazione permanente e' un'opzione, non la scelta principale:
     tono ridotto per non contendere l'attenzione al pulsante sopra */
  .secondaria { border-style: dashed; padding: 18px 24px; }
  .secondaria h2 { font-size: 15px; color: var(--muted); }
  .secondaria p { margin: 0; font-size: 14px; color: var(--muted); }
  .secondaria a { color: var(--primary); font-weight: 600; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Assistenza remota</h1>
  <p class="sub">Scarica il programma e comunica al tecnico i due codici che compariranno a schermo.</p>

  <div class="card">
@@SCHEDA_PORTABLE@@
  </div>

  <div class="card">
    <h2>Cosa succede</h2>
    <ol>
      <li>Apri la cartella compressa scaricata ed <strong>estrai</strong> il contenuto (clic destro &rarr; <code>Estrai tutto</code>).</li>
      <li>Fai doppio clic su <code>avvia-assistenza.bat</code>.</li>
      <li>Windows potrebbe avvisarti che il file proviene da Internet: scegli <code>Ulteriori informazioni</code> e poi <code>Esegui comunque</code>.</li>
      <li>Si apre la finestra di RustDesk con un <strong>ID</strong> e una <strong>Password</strong>.</li>
      <li>Comunicali al tecnico e <strong>lascia la finestra aperta</strong> per tutta la durata dell&rsquo;intervento.</li>
    </ol>
  </div>

@@SCHEDA_INSTALL@@
  <footer>Il collegamento è cifrato e avviene solo quando lo autorizzi.</footer>
</div>
</body>
</html>
HTML_EOF

if [[ "$PORTABILE_OK" -eq 1 ]]; then
  SCHEDA_PORT='    <p><a class="btn" href="assistenza-rapida.zip" download>Scarica il programma</a></p>
    <div class="warn">
      Non installa nulla sul computer e non richiede permessi di amministratore.
      A fine intervento basta chiudere la finestra.
    </div>'
  SCHEDA_INST='  <div class="card secondaria">
    <h2>Assistenza continuativa</h2>
    <p>Se il tecnico ti ha chiesto di lasciare il collegamento sempre attivo, scarica
    invece <a href="'"$INSTALL_FILE"'" download>la versione con installazione</a>.
    '"$INSTALL_NOTA"'</p>
  </div>

'
else
  SCHEDA_PORT='    <p><a class="btn" href="'"$INSTALL_FILE"'" download>Scarica il programma</a></p>
    <div class="warn">'"$INSTALL_NOTA"'</div>'
  SCHEDA_INST=''
fi

python3 - "${USCITA}/index.html" "$SCHEDA_PORT" "$SCHEDA_INST" <<'PYPAG'
import sys
percorso, portable, install = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(percorso, encoding='utf-8').read()
t = t.replace('@@SCHEDA_PORTABLE@@', portable).replace('@@SCHEDA_INSTALL@@', install)
open(percorso, 'w', encoding='utf-8').write(t)
PYPAG

echo
echo "Fatto. Pacchetto in ${USCITA}:"
ls -1sh "${USCITA}"
echo
echo "Pagina da inviare al cliente:"
echo "  ${API_URL%/}/upload/"
