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

# Collegamenti fisici invece di copie: i pacchetti sono identici a ogni
# intervento, quindi cento link occupano lo spazio di uno.
for f in "$PACCHETTO"/*; do
  [[ -f "$f" ]] || continue
  ln "$f" "${DEST}/$(basename "$f")" 2>/dev/null || cp "$f" "${DEST}/"
done

echo
echo "Link per questo intervento (valido ${ORE} ore):"
echo
echo "  ${BASE_URL}/upload/s-${TOKEN}/"
echo
echo "Per revocarlo subito:  ./nuovo-link.sh --revoca ${TOKEN}"
