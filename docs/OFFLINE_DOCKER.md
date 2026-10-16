# CARLA-Entwicklungsumgebung im Docker (offline-fähig)

Ein Container mit Build-Toolchain, Web-VS-Code (code-server, Port 8080) und Download-Server für Build-Ergebnisse (Port 8081). Dateien liegen in `Util/Docker/DevEnv/`.

## Ablauf
```bash
cd Util/Docker/DevEnv
./manage.sh creds                 # credentials/credentials.env mit Zufallspasswort anlegen, dann Werte eintragen
./manage.sh build                 # Image bauen (einmalig mit Internet)
./manage.sh save carla-dev.tar.zst   # Image exportieren; auf dem Zielsystem: ./manage.sh load carla-dev.tar.zst
export UE4_ROOT_HOST=~/UnrealEngine_4.26    # Engine wird gemountet, nicht ins Image gepackt
./manage.sh up                    # http://localhost:8080 (VS Code), :8081 (Artefakte); GPU=1 ./manage.sh up für NVIDIA
./manage.sh build-carla all       # Python-Wheel, C++-Client, Server (Town06 + Town04), danach Sammeln
./manage.sh pull-artifacts ./download   # oder im Browser / per curl von :8081
```
Auf dem Zielsystem ohne Internet zusätzlich: CARLA-Quellen (`CARLA_SRC`), Engine (`UE4_ROOT_HOST`) und den Download-Cache (`OFFLINE_CACHE_DIR`, siehe `docs/BUILD_AND_TEST.md` Abschnitt 8) bereitstellen und in der Credentials-Datei `OFFLINE=1` setzen.

## Credentials per Datei
Der Ordner `credentials/` wird read-only nach `/run/credentials` gemountet. Der Entrypoint liest `credentials.env` (Zeilen `KEY=VALUE`, wird geparst, nicht ausgeführt). Jeder Schlüssel geht auch als `KEY_FILE=/run/credentials/datei`. Vorlage mit allen Schlüsseln: `credentials/credentials.env.example`.

| Zweck | Schlüssel |
|---|---|
| Web-Zugang | `CODE_SERVER_PASSWORD` (leer = zufällig, steht im Container-Log), `ARTIFACT_PASSWORD`, `ARTIFACT_USER` |
| Git / GitHub (UE4-Fork, Plugins) | `GIT_USER_NAME`, `GIT_USER_EMAIL`, `GITHUB_USER`, `GITHUB_TOKEN`, `GIT_CREDENTIAL_<name>=https://user:token@host` |
| SSH | `SSH_KEY_FILE`, `SSH_KNOWN_HOSTS_FILE` |
| Firmennetz | `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `CA_CERT_FILE`, `PIP_INDEX_URL` |
| Sonstiges | `CARLA_REPO_URL`, `CARLA_REPO_BRANCH`, `OFFLINE`, `CARLA_DEFAULT_MAPS` |

Alle Werte sind im Container für Prozesse und VS-Code-Terminals sichtbar. Die echte Datei nie committen (`.gitignore` im Ordner schließt sie aus).

## Artefakte herunterladen
`carla-build` ruft am Ende `carla-collect` auf: `/artifacts/<zeit>-<version>/` (Host: `Util/Docker/DevEnv/artifacts/`), `latest` zeigt auf den neuesten Stand. Enthalten: Python-Wheel, `cpp-client/` (`cpp_client`, `gpu_test`), `libcarla-client-install.tar.zst`, Server-Paket, optional Editor-Binaries, dazu `SHA256SUMS` und `manifest.json`.

- Browser: `http://HOST:8081/latest/` (Basic Auth, Benutzer `carla`), Ordner als Zip über `?zip=1`
- curl, fortsetzbar: `curl -C - -O -u carla:PASSWORT http://HOST:8081/latest/<datei>`
- In VS Code: Rechtsklick auf Datei oder Ordner im Explorer, „Download“

## Maps
Das Server-Paket enthält standardmäßig nur **Town06 (Standardkarte)** und **Town04** (`CARLA_DEFAULT_MAPS`). Weitere Maps nachinstallieren:
```bash
./manage.sh build-carla maps Town01,Town02    # baut ein neues Server-Paket mit Town06, Town04, Town01, Town02
```
Das Ergebnis ist ein vollständiges Server-Paket (gecookte Inhalte stecken in der Pak-Datei, ein reines Zusatzpaket gibt es nicht). Es wird als neues Artefakt zum Download bereitgestellt und ersetzt das bisherige Paket.
