Ziel: Teste, ob ich CARLA 0.9.16 über ROS 2 mit Foxglove im Browser visualisieren kann (Kamera, Lidar, Fahrzeugposition).

Umgebung:
- Ubuntu 24.04, NVIDIA-GPU
- CARLA 0.9.16 (Pfad: <CARLA_PFAD>)
- Gewünschte Kette: CARLA -> ROS 2 -> foxglove_bridge (WebSocket, Standardport 8765) -> Foxglove im Browser

Vorgehen:
1. Prüfe zuerst, welche Wege es für 0.9.16 gibt:
   a) CARLA-eigene ROS-2-Unterstützung (Startoption --ros2), falls in 0.9.16 vorhanden
   b) die separate carla-simulator/ros-bridge
   Prüfe offizielle CARLA-Doku und Repo auf Kompatibilität mit 0.9.16 und mit der ROS-2-Distribution für Ubuntu 24.04 (Jazzy). Falls Humble nötig ist (Ubuntu 22.04), schlage einen Docker-Container vor. Nenne mir den Plan, bevor du installierst.
2. Installiere ROS 2 in der passenden Distribution (bei Bedarf im Docker-Container) und ros-<distro>-foxglove-bridge.
3. Starte CARLA 0.9.16 und warte, bis Port 2000 erreichbar ist.
4. Spawne ein Fahrzeug mit RGB-Kamera und Lidar (Python-Skript über die CARLA-API oder die Mittel der gewählten Bridge) und lasse es fahren (Autopilot).
5. Prüfe mit `ros2 topic list` und `ros2 topic hz`, ob Kamera, Lidar und Odometrie/Position als Topics ankommen.
6. Starte foxglove_bridge und verbinde Foxglove (Browser, "Foxglove WebSocket", ws://localhost:8765). Lege ein Layout mit 3D-Panel, Bild-Panel und Plot an.

Regeln:
- Keine Systempakete entfernen, alles in Docker oder Projektordner.
- Bei Fehlern: Fehlermeldung und Ursache nennen, maximal zwei Lösungsversuche pro Problem, dann zusammenfassen.
- Arbeitsordner: ~/tests/carla-foxglove

Abschluss: Kurzer Bericht mit
- funktioniert / funktioniert teilweise / funktioniert nicht
- genutzter Weg (natives --ros2 oder ros-bridge), ROS-Distribution und Versionen
- welche Topics kamen an und mit welcher Rate
- aufgetretene Fehler und Workarounds
- Befehlsfolge zum Reproduzieren