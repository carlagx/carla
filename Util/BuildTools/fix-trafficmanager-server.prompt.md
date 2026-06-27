# Prompt: CARLA Traffic-Manager-RPC-Server abhärten (Bind + Port-Fallback)

Wiederverwendbarer Prompt, um den Traffic-Manager-RPC-Server in LibCarla zu fixen:
**localhost-only Bind** (Security), **automatischer Ausweichport** bei belegtem Port und
**Rückgabe des real gebundenen Ports**. Einem Agenten auf einem frischen Clone geben oder
selbst abarbeiten. Es ist ein **minimal-invasiver** Fix in genau **einer** Datei.

Mechanisches Gegenstück (idempotentes Patch-+Build-Script):
[fix-trafficmanager-server.sh](fix-trafficmanager-server.sh) — `bash fix-trafficmanager-server.sh -y`.

Hintergrund: Die TM-Instanz registriert ihren Port beim Server über
`AddTrafficManagerRunning(GetLocalIP(port))` und meldet ihn beim Beenden über
`DestroyTrafficManager(server.port())` ab. Die Port-Referenz threadet von
`TrafficManager::CreateTrafficManagerServer(port)` → `TrafficManagerLocal(uint16_t &RPCportTM)`
→ `TrafficManagerServer(uint16_t &RPCPort)`. Wird der Port im Konstruktor hochgezählt, muss
dieser neue Wert über die Referenz zurückfließen, sonst registriert der Client den falschen Port.

---

```
Ziel: Bug in der Traffic-Manager-Server-Retry-Schleife in CARLA beheben.

Datei:       LibCarla/source/carla/trafficmanager/TrafficManagerServer.h
Konstruktor: TrafficManagerServer(uint16_t &RPCPort, TrafficManagerBase* tm)

PROBLEM:
Der Kommentar im catch-Block sagt "Update port number and try again", aber der
Code erhoeht den Port NICHT - er schlaeft nur 500 ms und probiert denselben Port
erneut. Ist der Port belegt (z.B. von einem haengenden ScenarioRunner-Prozess),
scheitern alle MIN_TRY_COUNT Versuche und es wird geworfen:
"trying to create rpc server for traffic manager; but the system failed to
create because of bind error." Es gibt also keinen automatischen Ausweichport.

GEWUENSCHTES VERHALTEN:
[1] SECURITY  Server nur an localhost binden:
                new ::rpc::server("127.0.0.1", RPCPort)
              NICHT an 0.0.0.0 / alle Interfaces. Die an Clients via
              GetLocalIP()/AddTrafficManagerRunning() angekuendigte Adresse ist
              ohnehin loopback, und der TM-RPC hat weder Auth noch Crypto.
[2] FALLBACK  Im catch-Block bei Bind-Fehler den Port WIRKLICH hochzaehlen
                RPCPort++;
              damit der naechste Schleifendurchlauf einen anderen Port probiert -
              wie der Kommentar es verspricht. Die 500-ms-Pause kann bleiben.
[3] REPORT    Nach erfolgreichem new den real gebundenen Port festhalten:
                _RPCPort = RPCPort;   // direkt nach dem erfolgreichen new
              _RPCPort wurde im Initializer aus dem URSPRUENGLICHEN Wert gesetzt
              und waere sonst veraltet. port() muss den echten Port liefern.
[4] Da RPCPort eine Referenz (uint16_t &) ist - und das GEWOLLT ist -, halten
    nach dem Konstruktor sowohl die Referenz RPCPort als auch _RPCPort den real
    gebundenen Port. Der Aufrufer (TrafficManagerLocal) registriert anschliessend
    diesen Port ueber AddTrafficManagerRunning / DestroyTrafficManager(port()).

CONSTRAINTS:
- localhost-Bind beibehalten: rpc::server("127.0.0.1", RPCPort) NICHT auf
  0.0.0.0 zurueckaendern.
- runtime_error erst NACH Ausschoepfen aller MIN_TRY_COUNT-Versuche werfen
  (bestehendes Verhalten beibehalten).
- Kein Speicherleck: server ist ein Raw-Pointer (Default nullptr); bei
  new-Fehlschlag bleibt er nullptr, im Erfolgsfall nicht ueberschreiben.
- Nur diese eine Datei aendern, minimal-invasiv.

ZIELZUSTAND (Retry-Schleife):

  uint16_t counter = 0;
  while(counter < MIN_TRY_COUNT) {
    try {
      // Bind nur localhost (kein Auth/Crypto; angekuendigte Adresse ist loopback).
      server = new ::rpc::server("127.0.0.1", RPCPort);

      // Bind ok: real gebundenen Port merken (Referenz -> Aufrufer + _RPCPort).
      _RPCPort = RPCPort;

    } catch(std::exception) {
      using namespace std::chrono_literals;
      // Bind-Fehler (Port belegt): naechsten Port nehmen -> faellt auf freien.
      RPCPort++;
      std::this_thread::sleep_for(500ms);
    }
    if(server != nullptr) { break; }
    counter ++;
  }
  if(server == nullptr) {
    carla::throw_exception(std::runtime_error(
      "trying to create rpc server for traffic manager; "
      "but the system failed to create because of bind error."));
  } else { ... server->bind(...) ... server->async_run(); }

VERIFIKATION:
- LibCarla-Client baut und linkt sauber (kompiliert den Traffic Manager):
    make LibCarla.client.release
  Inkrementell (ninja) werden nur TrafficManager.cpp und
  TrafficManagerLocal.cpp neu uebersetzt; danach libcarla_client.a archiviert.
- Optional fuer TM-Clients: make PythonAPI (uebernimmt die neue .a).

COMMIT (aussagekraeftige Message):
  fix(trafficmanager): increment RPC port on bind failure and report bound port
  Body: catch-Block zaehlt den Port jetzt hoch (RPCPort++), faellt bei belegtem
  Port automatisch auf einen freien; nach erfolgreichem Bind liefert port() ueber
  Referenz + _RPCPort den real gebundenen Port. localhost-Bind, Post-Retry-Throw
  und nullptr-Handling unveraendert.
```
