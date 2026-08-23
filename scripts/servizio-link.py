#!/usr/bin/env python3
"""
Servizio minimo che genera i link di assistenza, protetto dal login di RustDesk.

Non ha una propria password: valida ogni richiesta chiedendo alla API di
RustDesk chi sia il portatore del token, e procede solo se e' un
amministratore. Chi non e' autenticato nella console non puo' usarlo.

    ./servizio-link.py --url https://edesk.tuodominio.ch

Opzioni principali:
    --url <base>       indirizzo pubblico, per comporre i link generati
    --bind <ip>        interfaccia di ascolto (default 127.0.0.1)
    --porta <n>        porta di ascolto (default 21120)
    --api <url>        API di RustDesk (default http://127.0.0.1:21114)
    --script <file>    percorso di nuovo-link.sh
    --pacchetto <dir>  cartella sorgente non pubblicata
    --pubblica <dir>   cartella servita dal server

ATTENZIONE: questo servizio esegue uno script sul server. Esponilo solo
attraverso il reverse proxy in HTTPS e limita la porta con il firewall
all'indirizzo del proxy. Non pubblicarlo direttamente su Internet.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PREFISSO = '/assistenza-api'
ID_VALIDO = re.compile(r'^[0-9a-f]{6,64}$')

CFG = {}


def _chiama_api(percorso, token):
    """Interroga la API di RustDesk con il token dell'utente."""
    req = urllib.request.Request(
        CFG['api'].rstrip('/') + percorso,
        headers={'api-token': token},
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            if r.status != 200:
                return None
            dati = json.loads(r.read().decode('utf-8'))
    except (urllib.error.URLError, ValueError, TimeoutError, OSError):
        return None
    if dati.get('code') not in (0, None):
        return None
    return dati


def utente_autorizzato(token):
    """Verifica identita' e privilegi chiedendo alla API di RustDesk.

    Il profilo restituito da /user/current non espone il ruolo, quindi non e'
    sufficiente: si interroga anche un endpoint riservato agli amministratori,
    lasciando che sia RustDesk stessa a decidere. Un utente normale ottiene un
    rifiuto e non arriva qui.
    """
    if not token or len(token) > 4096:
        return None

    profilo = _chiama_api('/api/admin/user/current', token)
    if not profilo:
        return None

    if _chiama_api('/api/admin/user/list?page=1&page_size=1', token) is None:
        return None

    dati = profilo.get('data') or {}
    return dati.get('username') or 'amministratore'


def esegui(*argomenti):
    """Lancia nuovo-link.sh senza passare da una shell: gli argomenti sono
    una lista, quindi non esiste modo di iniettare comandi."""
    cmd = [CFG['script'],
           '--pacchetto', CFG['pacchetto'],
           '--pubblica', CFG['pubblica'],
           '--url', CFG['url'], *argomenti]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return p.returncode, p.stdout, p.stderr


class Gestore(BaseHTTPRequestHandler):
    server_version = 'assistenza-link'

    def log_message(self, formato, *args):
        sys.stderr.write('%s %s\n' % (self.address_string(), formato % args))

    def _rispondi(self, codice, oggetto):
        corpo = json.dumps(oggetto).encode('utf-8')
        self.send_response(codice)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(corpo)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(corpo)

    def _autentica(self):
        chi = utente_autorizzato(self.headers.get('api-token'))
        if not chi:
            self._rispondi(401, {'errore': 'Accedi alla console come amministratore.'})
            return None
        return chi

    def _corpo(self):
        try:
            n = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            return {}
        if n <= 0 or n > 8192:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode('utf-8'))
        except ValueError:
            return {}

    def do_GET(self):
        if self.path.rstrip('/') != PREFISSO + '/elenco':
            return self._rispondi(404, {'errore': 'non trovato'})
        if not self._autentica():
            return
        rc, out, err = esegui('--elenco')
        voci = []
        for riga in out.splitlines():
            r = riga.strip()
            if r and not r.endswith(':') and 'nessuno' not in r:
                parti = r.split()
                if parti and ID_VALIDO.match(parti[0]):
                    voci.append({'id': parti[0], 'descrizione': ' '.join(parti[1:])})
        return self._rispondi(200 if rc == 0 else 500,
                              {'link': voci, 'errore': err.strip() or None})

    def do_POST(self):
        percorso = self.path.rstrip('/')
        if percorso not in (PREFISSO + '/genera', PREFISSO + '/revoca'):
            return self._rispondi(404, {'errore': 'non trovato'})
        chi = self._autentica()
        if not chi:
            return
        dati = self._corpo()

        if percorso.endswith('/genera'):
            try:
                ore = int(dati.get('ore', 8))
            except (TypeError, ValueError):
                ore = 8
            ore = max(1, min(ore, 168))
            rc, out, err = esegui('--ore', str(ore))
            link = next((r.strip() for r in out.splitlines()
                         if r.strip().startswith('http')), None)
            if rc != 0 or not link:
                return self._rispondi(500, {'errore': err.strip() or 'generazione non riuscita'})
            self.log_message('link generato da %s (%s ore)', chi, ore)
            return self._rispondi(200, {'link': link, 'ore': ore})

        ident = str(dati.get('id', ''))
        if not ID_VALIDO.match(ident):
            return self._rispondi(400, {'errore': 'identificativo non valido'})
        rc, out, err = esegui('--revoca', ident)
        self.log_message('revoca %s da %s', ident, chi)
        return self._rispondi(200 if rc == 0 else 500,
                              {'ok': rc == 0, 'errore': err.strip() or None})


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--url', required=True)
    ap.add_argument('--bind', default='127.0.0.1')
    ap.add_argument('--porta', type=int, default=21120)
    ap.add_argument('--api', default='http://127.0.0.1:21114')
    ap.add_argument('--script', default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'nuovo-link.sh'))
    ap.add_argument('--pacchetto', default='/opt/rustdesk/pacchetto')
    ap.add_argument('--pubblica', default='/opt/rustdesk/downloads')
    a = ap.parse_args()

    if not os.access(a.script, os.X_OK):
        sys.exit(f'Errore: {a.script} non eseguibile.')
    CFG.update(url=a.url.rstrip('/'), api=a.api, script=a.script,
               pacchetto=a.pacchetto, pubblica=a.pubblica)

    srv = ThreadingHTTPServer((a.bind, a.porta), Gestore)
    print(f'In ascolto su {a.bind}:{a.porta}, autenticazione delegata a {a.api}')
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
