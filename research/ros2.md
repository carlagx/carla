Ziel: Installiere ROS 2 in der zu meinem Ubuntu passenden Distribution, installiere und (falls nötig) baue foxglove_bridge, und weise nach, dass ich Live-Daten im Foxglove-Browser/-Desktop sehe. Das ist die Grundlage für einen späteren CARLA-Test.

Umgebung:
- Ubuntu <24.04 oder 22.04 eintragen>, x86_64
- Arbeitsordner: ~/ros2_foxglove

Vorgehen:
1. Analyse zuerst, ohne zu installieren:
   a) Ubuntu-Version prüfen (lsb_release -a).
   b) Welche ROS-2-Distribution gehört offiziell zu dieser Ubuntu-Version (24.04 -> Jazzy, 22.04 -> Humble)? Prüfe in der offiziellen ROS-2-Dokumentation (docs.ros.org) und auf index.ros.org, ob es für diese Distribution ein Binärpaket ros-<distro>-foxglove-bridge gibt.
   c) Prüfe im Repo foxglove/ros-foxglove-bridge und in der Foxglove-Doku, wo die ROS-2-Bridge aktuell gepflegt wird (README-Hinweise auf foxglove-sdk beachten) und welche Distributionen unterstützt sind.
   d) Entscheide: Binärpaket per apt (bevorzugt) oder Bau aus dem Quellcode. Nenne kurz die Begründung.
2. ROS 2 installieren (nach offizieller Anleitung):
   - Locale (UTF-8) prüfen, universe-Repository aktivieren
   - ROS-2-apt-Quelle und Schlüssel einrichten (offizielle Methode über das ros2-apt-source-Paket, falls in der Doku vorgesehen)
   - ros-<distro>-ros-base installieren (kein Desktop-Vollpaket, außer ich brauche rviz)
   - ros-dev-tools installieren (colcon, rosdep, vcstool)
   - rosdep init/update
   - Setup in ~/.bashrc NICHT dauerhaft eintragen, sondern ein Skript ~/ros2_foxglove/env.sh mit "source /opt/ros/<distro>/setup.bash" anlegen
3. foxglove_bridge:
   - Variante A (Binär): sudo apt install ros-<distro>-foxglove-bridge
   - Variante B (Quellcode, nur wenn A nicht verfügbar): Workspace ~/ros2_foxglove/ws/src anlegen, Repo klonen, rosdep install --from-paths src --ignore-src -y, colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release, danach source install/setup.bash
4. Funktionstest ohne CARLA:
   - Terminal 1: ros2 run demo_nodes_cpp talker (alternativ ein eigenes kleines Python-Publisher-Skript mit sensor_msgs/Image oder PointCloud2 als Testdaten)
   - Terminal 2: ros2 launch foxglove_bridge foxglove_bridge_launch.xml (Standardport 8765, prüfen mit ss -ltnp)
   - Foxglove verbinden: Foxglove-Desktop-App oder Web-App, "Open connection" -> "Foxglove WebSocket" -> ws://localhost:8765
   - Panels: Raw Messages für /chatter, optional Image- und 3D-Panel für den Test-Publisher
   - Hinweis: Falls der Browser die ws://-Verbindung von einer https-Seite blockiert, Desktop-App oder lokal gehosteten Foxglove verwenden und mir das melden.
5. Optional (nur wenn Zeit): Kurzer Vorbereitungscheck für CARLA 0.9.16:
   - Gibt es in der CARLA-Doku die native ROS-2-Unterstützung (Startoption --ros2) und welche ROS-Distribution wird dort genannt?
   - Falls dort Humble verlangt wird, ich aber Jazzy nutze: Docker-Variante mit Humble beschreiben (nur beschreiben, nicht bauen).

Regeln:
- Systempakete nicht entfernen, keine fremden PPA-Experimente. Nur offizielle ROS-Quellen.
- Bei Fehlern: Fehlermeldung und Ursache nennen, maximal zwei Lösungsversuche pro Problem, dann zusammenfassen.
- Alle Befehle, die du ausführst, in ~/ros2_foxglove/install_log.md mitschreiben, damit ich es reproduzieren kann.
- Vor sudo-Befehlen, die dauerhafte Systemänderungen machen (apt-Quellen, Schlüssel), kurz sagen, was passiert.

Abschluss: Kurzer Bericht mit
- gewählte ROS-Distribution und Begründung
- Binär oder Quellcode, genaue Paketversionen (ros2 --version bzw. apt policy, foxglove_bridge-Version)
- Ergebnis des Funktionstests (Topics sichtbar? Rate? Verbindung stabil?)
- Fehler und Workarounds
- fertiges Start-Skript (start_bridge.sh), das ROS-Umgebung lädt und foxglove_bridge startet