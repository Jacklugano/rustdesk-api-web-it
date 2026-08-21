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

net session >nul 2>&1
if errorlevel 1 (
  echo.
  echo  Questo programma va avviato come amministratore.
  echo  Chiudi questa finestra, fai clic destro sul file
  echo  e scegli "Esegui come amministratore".
  echo.
  pause
  exit /b 1
)

set "CFG=@@CONFIG@@"
set "EXEURL=@@EXE_URL@@"

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
sed -i "s|@@CONFIG@@|${CONFIG}|; s|@@EXE_URL@@|${EXE_URL}|" "${USCITA}/installa-rustdesk.bat"

# --- archivio ZIP ----------------------------------------------------------
# Chrome ed Edge bloccano il download diretto dei file .bat, spesso senza
# spiegazioni. Dentro uno ZIP passano, quindi lo ZIP è la via principale e il
# .bat resta disponibile come ripiego.
if command -v zip >/dev/null 2>&1; then
  ( cd "$USCITA" && zip -q -j installa-rustdesk.zip installa-rustdesk.bat )
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$USCITA" <<'PY'
import sys, zipfile, os
d = sys.argv[1]
with zipfile.ZipFile(os.path.join(d, 'installa-rustdesk.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(d, 'installa-rustdesk.bat'), 'installa-rustdesk.bat')
PY
else
  echo "Attenzione: né zip né python3 disponibili, archivio non creato." >&2
  echo "I browser bloccano il download diretto dei .bat: installa uno dei due." >&2
fi

# --- pagina di download ----------------------------------------------------
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
</style>
</head>
<body>
<div class="wrap">
  <h1>Assistenza remota</h1>
  <p class="sub">Scarica e avvia il programma, poi comunica al tecnico i due dati che compariranno a schermo.</p>

  <div class="card">
    <p><a class="btn" href="installa-rustdesk.zip" download>Scarica il programma</a></p>
    <div class="warn">
      Il file scaricato è una cartella compressa. <strong>Estraila</strong>, poi fai
      <strong>clic destro</strong> su <code>installa-rustdesk.bat</code> e scegli
      <strong>«Esegui come amministratore»</strong>. Un doppio clic normale non basta.
    </div>
  </div>

  <div class="card">
    <h2 style="font-size:17px;margin:0 0 12px;">Cosa succede</h2>
    <ol>
      <li>Apri la cartella compressa scaricata ed <strong>estrai</strong> il contenuto (clic destro &rarr; <code>Estrai tutto</code>).</li>
      <li>Windows potrebbe avvisarti che il file proviene da Internet: scegli <code>Ulteriori informazioni</code> e poi <code>Esegui comunque</code>.</li>
      <li>Si apre una finestra nera: lascia che finisca, ci vuole circa un minuto.</li>
      <li>Alla fine compaiono un <strong>ID</strong> e una <strong>Password</strong>.</li>
      <li>Comunica quei due dati al tecnico, poi puoi chiudere la finestra.</li>
    </ol>
  </div>

  <footer>Il collegamento è cifrato e avviene solo quando lo autorizzi.</footer>
</div>
</body>
</html>
HTML_EOF

echo
echo "Fatto. Pacchetto in ${USCITA}:"
ls -1sh "${USCITA}"
echo
echo "Pagina da inviare al cliente:"
echo "  ${API_URL%/}/upload/"
