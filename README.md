# RustDesk API Web IT

Console di amministrazione per [RustDesk API](https://github.com/lejianwen/rustdesk-api)
**in italiano**, con l'interfaccia rinnovata.

Fork di [lejianwen/rustdesk-api-web](https://github.com/lejianwen/rustdesk-api-web)
(Vue 3 + Element Plus + Vite), il frontend servito dal backend su `/_admin/`.

L'originale non include l'italiano tra le lingue disponibili.

## Cosa cambia rispetto all'originale

### Lingua italiana

| File | Modifica |
|---|---|
| `src/utils/i18n/it.json` | **Nuovo.** Tutte le 184 chiavi tradotte |
| `src/utils/i18n/en.json` | Aggiunte 11 chiavi mancanti usate dalla nuova home |
| `src/utils/i18n.js` | Registrato `it`; aggiunto ripiego sull'inglese |
| `src/store/app.js` | Locale Element Plus italiana; italiano come predefinito |

Oltre alla traduzione sono stati corretti due difetti presenti a monte:

- **Rilevamento della lingua del browser.** `navigator.language` restituisce
  `it-IT`, che non corrispondeva a nessuna chiave: l'interfaccia mostrava le
  chiavi grezze (`PeerManage`, `LastOnlineTime`…) invece del testo tradotto. Il
  problema riguardava ogni lingua, non solo l'italiano. Ora il tag regionale
  viene normalizzato (`it-IT` → `it`, `zh-HK` → `zh-TW`).
- **Ripiego sull'inglese.** Una chiave assente da una traduzione mostrava il
  proprio nome; ora ricade sull'inglese prima di arrendersi.

### Interfaccia

| File | Modifica |
|---|---|
| `src/styles/style.scss` | Sistema di design a token (colori, raggi, ombre) con tema chiaro e scuro; allineamento delle variabili Element Plus |
| `src/layout/index.vue` | Intestazione chiara e fissa, sfondo pagina, spaziature |
| `src/layout/components/aside.vue` | Barra laterale con gradiente, voci arrotondate, voce attiva evidenziata |
| `src/layout/components/header.vue` | Logo e titolo ricomposti, pulsanti con stato hover |
| `src/layout/components/setting/index.vue` | Contrasto corretto sull'intestazione chiara; lingua attiva evidenziata |
| `src/views/login/login.vue` | Accesso rinnovato: sfondo sfumato, scheda in vetro smerigliato, layout adattivo |
| `src/views/my/info.vue` | Home ricostruita, con il nuovo riquadro **Configurazione del server** |

Il riquadro «Configurazione del server» mostra Server ID, relay, API e chiave
pubblica, ciascuno con pulsante di copia: sono i valori da inserire nei client
RustDesk, che prima andavano cercati altrove.

La palette è definita una sola volta come token CSS in `style.scss`: per
cambiare il colore principale basta modificare `$primaryColor`.

## Compilazione

Servono Node.js 18+ e npm.

```bash
npm install
npm run build
```

Il risultato finisce in `dist/`.

> Il `package-lock.json` originale puntava a `registry.npmmirror.com` (mirror
> cinese), spesso lento o irraggiungibile dall'Europa. I 257 URL sono stati
> riscritti su `registry.npmjs.org`.

## Installazione nel container

Il backend serve la console dalla cartella `resources/admin`. Copia lì il
contenuto di `dist/` e montalo nel container:

```bash
mkdir -p ~/rustdesk/admin-it
cp -r dist/* ~/rustdesk/admin-it/
```

Poi aggiungi il montaggio al servizio `api` nel `docker-compose.yml`:

```yaml
    volumes:
      - ./api_data:/app/data
      - ./data:/rustdesk_key:ro
      - ./admin-it:/app/resources/admin:ro   # console personalizzata
```

Infine:

```bash
docker compose up -d --force-recreate api
```

La console resta su `http://<dominio>:21114/_admin/`.

Il montaggio è in sola lettura e separato dall'immagine, quindi un aggiornamento
di `lejianwen/rustdesk-api` non sovrascrive la personalizzazione. Il rovescio
della medaglia: se una versione futura del backend cambia le API chiamate dal
frontend, la console montata resta indietro e va riallineata al repo originale.

## Pacchetto client pronto da inviare

Lo script [`scripts/genera-client.sh`](./scripts/genera-client.sh) produce un
pacchetto di installazione già configurato sul tuo server, con una pagina di
download da mandare al cliente.

```bash
sudo mkdir -p /opt/rustdesk/downloads

./scripts/genera-client.sh \
  --dominio rd.tuodominio.it \
  --api https://rd.tuodominio.it
```

La chiave pubblica viene letta dal container `hbbs`, quindi funziona
qualunque sia il percorso dei volumi. Se il container ha un altro nome usa
`--container <nome>`; in alternativa puoi incollare la chiave direttamente con
`--chiave-testo` (la copi dalla home della console, riquadro «Configurazione
del server») o indicare il file con `--chiave`.

> Non fidarti di un percorso fisso come `/opt/rustdesk/data/id_ed25519.pub`:
> con uno stack creato in Portainer i volumi relativi finiscono nella sua
> directory di lavoro interna, non dove ci si aspetta.

Genera tre file in `/opt/rustdesk/downloads`:

| File | Contenuto |
|---|---|
| `index.html` | Pagina di download in italiano, con le istruzioni per il cliente |
| `installa-rustdesk.bat` | Installazione automatica: scarica, installa, configura, imposta una password casuale e mostra ID e password |
| `rustdesk.exe` | L'eseguibile ufficiale, servito dal tuo server invece che da GitHub |

Monta la cartella nel servizio `api` (già presente in `deploy/portainer-stack.yml`):

```yaml
      - /opt/rustdesk/downloads:/app/resources/public/upload:ro
```

Poi invii al cliente un solo indirizzo: `https://<dominio>/upload/`

### Eseguibile con icona

Lo script genera anche `installa-rustdesk.ps1`, la versione PowerShell dello
stesso installer, pensata per essere compilata in un `.exe`. Rispetto al file
batch dentro lo ZIP il cliente guadagna parecchio: un solo doppio clic, niente
estrazione, niente blocco del browser sugli script, e la richiesta di Windows
mostra il tuo nome invece di `cmd.exe`.

Sulla macchina Windows, scarica i due file dal tuo stesso server — il
generatore pubblica anche l'icona, così non serve passare da GitHub né
autenticarsi:

```powershell
mkdir $env:USERPROFILE\rustdesk-build -Force
cd $env:USERPROFILE\rustdesk-build

Invoke-WebRequest https://<dominio>/upload/installa-rustdesk.ps1 -OutFile installa-rustdesk.ps1
Invoke-WebRequest https://<dominio>/upload/elettrosmart.ico      -OutFile elettrosmart.ico
```

Lo script **va preso dal server**, non dal repository: quello pubblicato
contiene già la configurazione del tuo server, mentre nel repository esiste
solo il modello con i segnaposto. Poi:

```powershell
Install-Module ps2exe -Scope CurrentUser

Invoke-PS2EXE .\installa-rustdesk.ps1 .\installa-rustdesk.exe `
  -iconFile .\elettrosmart.ico `
  -requireAdmin `
  -title "Assistenza Remota" `
  -company "Elettrosmart Sagl" `
  -version "1.0.0"
```

`-requireAdmin` incorpora il manifesto di elevazione: Windows chiede i privilegi
prima ancora di avviare il programma.

Copia poi l'`.exe` nella cartella di pubblicazione e rilancia `genera-client.sh`:
rilevando il file, la pagina di download proporrà quello al posto dell'archivio,
e le istruzioni per il cliente si accorciano di conseguenza.

> Ricompila l'eseguibile se cambi dominio o chiave: la configurazione è
> incorporata al momento della compilazione, e un `.exe` vecchio accanto a un
> `.bat` rigenerato punterebbe al server sbagliato senza dirlo.

**La firma digitale è un discorso a parte.** Senza un certificato di code
signing, Windows mostra comunque «Windows ha protetto il PC» al primo avvio.
L'icona rende il pacchetto riconoscibile, non fidato. Per togliere l'avviso
serve un certificato OV (la reputazione si costruisce nel tempo) o EV (fiducia
immediata, costo maggiore).

### L'icona

In [`branding/`](./branding/) trovi `elettrosmart.ico` con sette risoluzioni,
da 16 a 256 pixel. Sotto i 48 pixel viene disegnata una variante semplificata
col solo fulmine: la cornice del monitor, a quelle dimensioni, diventerebbe una
macchia illeggibile.

Il sorgente vettoriale è `elettrosmart.svg`; `genera-icona.py` ridisegna il
`.ico` senza bisogno di alcuna libreria esterna. Se modifichi i colori o la
forma, riportali su entrambi i file.

### Perché uno script e non un eseguibile rinominato

Il metodo storico — rinominare l'eseguibile in
`rustdesk-host=dominio,key=chiave.exe` — **non funziona più** dalla versione
1.4.x ([issue #15177](https://github.com/rustdesk/rustdesk/issues/15177)): il
client si avvia ma resta su «Not Ready». Lo script usa invece `--config`, che
è il meccanismo supportato e documentato per il deployment.

La stringa di configurazione è il JSON `{"host","key","api"}` codificato in
base64, con la stringa risultante rovesciata e privata del riempimento finale.
Lo script la costruisce leggendo direttamente `id_ed25519.pub`, così non puoi
sbagliare a trascrivere la chiave.

### Da sapere

- **La cartella `/upload` è pubblica**, senza autenticazione: chiunque conosca
  l'indirizzo può scaricare il pacchetto. Il file contiene la chiave *pubblica*
  del server, che non è un segreto, ma rivela l'indirizzo della tua
  infrastruttura. Se ti interessa limitarlo, proteggi il percorso `/upload` con
  una regola sul reverse proxy.
- Il cliente deve avviare il file con **«Esegui come amministratore»**:
  l'installazione del servizio richiede privilegi elevati. La pagina di download
  lo spiega, ed è comunque il punto in cui si blocca più spesso.
- Rigenera il pacchetto dopo aver cambiato dominio o chiave del server:
  i valori sono incorporati nel file batch al momento della generazione.

## Web client

Il backend serve un client web su `https://<dominio>/webclient/` (l'anteprima v2
è su `/webclient2/`). È attivo per impostazione predefinita: la voce
`app.web-client` vale `1`.

Aprirlo però non basta. Su una pagina HTTPS il browser rifiuta le WebSocket in
chiaro, e il client web parla con hbbs e hbbr **solo** via WebSocket, non su
TCP/UDP. Servono quindi due cose.

### 1. Il reverse proxy inoltra le WebSocket

Su pfSense, nel frontend HAProxy, due ACL e due backend:

| Percorso | Backend |
|---|---|
| `/ws/id` | `<ip-del-server>:21118` (hbbs) |
| `/ws/relay` | `<ip-del-server>:21119` (hbbr) |

Nel backend attiva l'opzione per l'inoltro delle WebSocket e assicurati che
l'header `X-Real-IP` venga impostato dal proxy.

L'equivalente in Nginx, per riferimento:

```nginx
location /ws/id {
    proxy_pass http://127.0.0.1:21118;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    proxy_set_header X-Real-IP $remote_addr;
    proxy_read_timeout 120s;
}
location /ws/relay {
    proxy_pass http://127.0.0.1:21119;
    # ...stesse direttive
}
```

### 2. Il backend dichiara l'indirizzo WebSocket

```yaml
      - RUSTDESK_API_RUSTDESK_WS_HOST=wss://<dominio>
```

Il valore viene iniettato nella pagina del client web come `window.ws_host`.
Senza, il client non sa dove aprire la connessione.

### Le porte 21118 e 21119 non vanno aperte sul firewall

Vanno raggiunte **solo** dal reverse proxy. hbbs e hbbr si fidano ciecamente
degli header `X-Real-IP` e `X-Forwarded-For` sulle connessioni WebSocket, senza
validarli: chi le raggiunge direttamente da Internet può dichiarare qualsiasi
IP, falsificando i log e aggirando eventuali blocchi per indirizzo. Niente port
forward su queste due, quindi.

Ricorda però il firewall **dell'host Docker**: hbbs e hbbr girano in
`network_mode: host` e non beneficiano dello scavalcamento che Docker applica
alle porte pubblicate, quindi le loro porte vanno permesse esplicitamente.

```bash
sudo ufw allow from <IP_del_proxy> to any port 21118,21119 proto tcp
```

### Nota sul comportamento

Un client che usa WebSocket non impiega TCP/UDP diretti e passa **sempre dal
relay**, tranne che nelle connessioni per IP diretto. Le sessioni dal browser
saranno quindi un po' più lente di quelle da client nativo.

## Distribuzione con Portainer

Il repository contiene un [`Dockerfile`](./Dockerfile) che compila la console e
la inserisce nell'immagine del backend, e uno stack pronto in
[`deploy/portainer-stack.yml`](./deploy/portainer-stack.yml).

In Portainer: **Stacks → Add stack → Repository**

| Campo | Valore |
|---|---|
| Repository URL | `https://github.com/Jacklugano/rustdesk-api-web-it` |
| Compose path | `deploy/portainer-stack.yml` |

Prima di distribuire, crea le cartelle sull'host:

```bash
sudo mkdir -p /opt/rustdesk/{data,api_data,postgres_data}
```

Poi compila le variabili nella sezione «Environment variables» dello stack:
`MY_DOMAIN`, `API_PORT_EXTERNAL`, `API_SERVER_URL`, `DB_NAME`, `DB_USER`,
`DB_PASSWORD`, `API_SECRET_KEY`.

I percorsi dei volumi nello stack sono **assoluti** di proposito: in Portainer
un percorso relativo non si riferisce alla cartella dello stack come ci si
aspetterebbe, ma a una directory di lavoro interna, ed è la causa più comune di
dati che «spariscono» dopo un aggiornamento dello stack.

## Verifica dopo il primo avvio

1. L'interfaccia è in italiano. In caso contrario selezionala dal menu della
   lingua in alto a destra.
2. Nella home compare il riquadro «Configurazione del server» con i valori
   corretti. Se mostra «Non configurato», mancano le variabili
   `RUSTDESK_API_RUSTDESK_*` nel `docker-compose.yml` del backend.
3. Il tema scuro funziona con l'interruttore in alto a destra.

## Allineamento con il repo originale

```bash
git remote add upstream https://github.com/lejianwen/rustdesk-api-web
git fetch upstream
git merge upstream/master
```

I conflitti si concentrano nei file elencati sopra. `src/utils/i18n/it.json` non
esiste a monte e non genera conflitti, ma dopo un merge conviene controllare che
non siano state aggiunte nuove chiavi da tradurre:

```bash
node -e "const a=require('./src/utils/i18n/en.json'),b=require('./src/utils/i18n/it.json');
console.log('da tradurre:', Object.keys(a).filter(k=>!(k in b)))"
```

## Licenza

MIT, come l'originale. Il file [`LICENSE`](./LICENSE) conserva la nota di
copyright a monte (vue-manage-system). Grazie a
[lejianwen](https://github.com/lejianwen) per il progetto di partenza.
