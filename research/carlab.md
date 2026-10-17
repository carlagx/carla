Ziel: Teste CARLA_MCP / CARLab WebUI (https://github.com/Croquembouche/CARLA_MCP) mit CARLA 0.10 (UE5) auf meinem Rechner und bewerte, ob es mit dem offiziellen CARLA 0.10 läuft oder den angepassten CARLab-Build braucht.

Hintergrund (laut README, bitte selbst gegenprüfen):
- CARLA_MCP enthält die WebUI und einen MCP-Server (laut README 49 Tools, 9 Resources), der dieselbe API wie die Oberfläche nutzt und keine zweite Simulationsuhr startet.
- Die vollständige WebUI erwartet den passenden nativen CARLA-Build (angepasstes CARLA UE5), Python 3.10 und ROS 2 Humble auf Ubuntu 22.04.
- Companion-Repos: Croquembouche/CARLA_CARLab und Croquembouche/UE5_CARLab.
- Start der UI mit ./run.sh, CARLA wird über die Start-Aktion der UI gestartet.
- Der eigenständige MCP-Bridge kann sich mit einer bereits laufenden WebUI verbinden, ohne CARLA oder ROS zu importieren.

Umgebung:
- Ubuntu <24.04 oder 22.04 eintragen>, NVIDIA-GPU
- Offizielles CARLA 0.10 (Pfad: <CARLA_010_PFAD>)

Vorgehen:
1. Analyse ohne Installation: Lies README, run.sh, Abhängigkeitsdateien (package-lock.json, Python-Requirements) und die Companion-Repos. Beantworte:
   a) Welche CARLA-Version/welchen Build setzt die WebUI voraus (offizielles 0.10 oder eigener CARLab-Build)?
   b) Welche CARLA-Python-API-Version und welche Python-Version werden benötigt?
   c) Ist ROS 2 zwingend oder nur für Aufzeichnung (ROS-2-Bags) nötig?
   d) Was ist der Aufwand, den CARLab-Build selbst zu bauen (Plattenplatz, Unreal-Engine-Zugang, Dauer)?
   Fasse das in einem kurzen Plan zusammen und warte nicht auf meine Antwort, sondern wähle den sinnvollsten Pfad (siehe unten).
2. Pfad A (bevorzugt, falls Standard-0.10 laut Analyse ausreicht oder teilweise geht): Starte offizielles CARLA 0.10, richte Python 3.10 isoliert ein (uv, pyenv oder Docker, System-Python nicht verändern), installiere die WebUI und teste.
3. Pfad B (falls der angepasste Build zwingend ist): Teste nur den Teil, der ohne ihn geht, nämlich die WebUI-Oberfläche und den MCP-Server im Standalone-Modus. Baue den CARLab-Build NICHT, sondern schätze den Aufwand ab und berichte.
4. Funktionstest, soweit möglich:
   - UI erreichbar im Browser (Port aus run.sh)
   - CARLA starten/stoppen über die UI
   - Karte laden, Ego-Fahrzeug spawnen, Simulation run/pause/step
   - Wetter ändern
   - MCP-Server mit einem MCP-Client verbinden und 2 bis 3 Tools aufrufen (z. B. Szenenstatus lesen, Fahrzeug spawnen)
5. Prüfe optional, ob sich die Aufzeichnung (State/Sensor-Recording) starten lässt, auch ohne ROS-Bags.

Regeln:
- Keine Systempakete entfernen oder Systemeinstellungen ändern, alles in venv/Docker/Projektordner.
- Kein Bau von Unreal Engine und keine großen Downloads (mehr als ca. 20 GB) ohne vorherige Rückfrage.
- Bei Fehlern: Fehlermeldung und Ursache nennen, maximal zwei Lösungsversuche pro Problem, dann zusammenfassen.
- Lizenzhinweis aus dem README beachten: CARLA/Unreal-abgeleitete Assets behalten ihre Upstream-Lizenzen.
- Arbeitsordner: ~/tests/carlab-webui

Abschluss: Kurzer Bericht mit
- Ergebnis: funktioniert mit Standard-0.10 / nur mit CARLab-Build / funktioniert nicht
- genaue Versionen (CARLA, Python, Node, ROS falls genutzt, Commit-Hash der Repos)
- welche Funktionen getestet wurden und welche liefen
- was der angepasste Build zusätzlich nötig macht und geschätzter Aufwand
- aufgetretene Fehler und Workarounds
- Befehlsfolge zum Reproduzieren