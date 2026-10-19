Ziel: Teste, ob Cycarla (Web-Oberfläche für CARLA) mit CARLA 0.9.16 auf meinem Rechner funktioniert.

Umgebung:
- Ubuntu 24.04, NVIDIA-GPU
- CARLA 0.9.16 (Pfad: <CARLA_PFAD>)
- Cycarla besteht aus cycarla-backend (Python/Flask, PyPI, Installation per pipx) und cycarla_frontend (Next.js, Port 3000). Das Backend spricht mit CARLA auf Port 2000.

Vorgehen:
1. Prüfe zuerst die Kompatibilität: Welche CARLA-Version und welche Python-Version erwarten cycarla-backend und -frontend (README, pyproject.toml, GitHub-Repo)? Ist die CARLA-Python-API für 0.9.16 auf meiner Python-Version verfügbar? Nenne mir mögliche Probleme, bevor du etwas installierst.
2. Ubuntu 24.04 bringt Python 3.12 mit, Cycarla ist laut Doku für Python 3.10 (Ubuntu 22.04) gedacht. Richte Python 3.10 isoliert ein (pyenv, uv oder Docker), ohne das System-Python zu verändern.
3. Installiere das Backend mit pipx und das Frontend (Node/npm, passende Node-Version prüfen).
4. Starte CARLA 0.9.16 (bei Bedarf mit -RenderOffscreen oder niedriger Qualität) und warte, bis Port 2000 erreichbar ist.
5. Starte Backend und Frontend und öffne http://localhost:3000.
6. Teste: Verbindung zu CARLA, Anzeige der Karte, Fahrzeug spawnen, Simulation starten und stoppen.

Regeln:
- Keine Systempakete entfernen oder Systemeinstellungen ändern, alles in venv/pipx/Docker/Projektordner.
- Bei Fehlern: Fehlermeldung und Ursache nennen, maximal zwei Lösungsversuche pro Problem, dann zusammenfassen.
- Arbeitsordner: ~/tests/cycarla

Abschluss: Kurzer Bericht mit
- funktioniert / funktioniert teilweise / funktioniert nicht
- genaue Versionen (CARLA, Python, Node, Cycarla)
- aufgetretene Fehler und Workarounds
- die Befehlsfolge, mit der ich es reproduzieren kann