# GUI-Frameworks für CARLA-Clients: SDL2 und GTK3 + Cairo im Vergleich

Entscheidungshilfe für künftige Oberflächen (Fahr-Clients, Sensor-Viewer, Werkzeuge).
Grundlage sind die beiden C++-Clients dieses Repos, `Examples/CppClient/manual_control.cpp`
(SDL2 + SDL2_ttf) und `manual_control_gtk.cpp` (GTK3 + Cairo + Pango), die dasselbe können,
und eigene Messungen vom 2026-10-17.

Kennzeichnung der Aussagen: **[gemessen]** hier mit den Skripten in `benchmarks/` ·
**[geprüft]** an Headern, Paketen oder Containern festgestellt · **[recherchiert]** aus den
Quellen am Ende · **[Erfahrung]** aus der Entwicklung der beiden Clients ·
**[Wissen]** aus allgemeinem Wissen, hier nicht überprüft.

---

## 1. Kurzfassung

### SDL2 (+ SDL2_ttf)

| Pro | Contra |
|---|---|
| Gamepad, Joystick, Lenkrad mit Force Feedback, Audio, Sensoren eingebaut (`SDL_gamecontroller.h`, `SDL_haptic.h`, `SDL_joystick.h`) **[geprüft]** | Keine Widgets (Menüs, Dialoge, Eingabefelder, Dateiauswahl): alles selbst bauen |
| Programmiermodell wie pygame (eigene Schleife, Tastenzustand abfragen); pygame setzt selbst auf SDL auf, Code lässt sich fast 1:1 übertragen **[Erfahrung]** | Text nur mit SDL2_ttf **und festem Schriftpfad**; der Pfad ist je Distribution anders (4 verschiedene Pfade bei 9 Distributionen) **[geprüft]** |
| Kleine Abhängigkeitskette: 69 Pakete gegenüber 277 bei GTK3 (Ubuntu 22.04) **[geprüft]**; Lizenz zlib, auch statisch linkbar **[geprüft]** | Im Test auf 2 von 9 Distributionen Absturz des Wayland-Treibers (Ubuntu 22.04, Debian 12) **[gemessen]** |
| GPU-beschleunigter 2D-Renderer, OpenGL-/Vulkan-Kontext für 3D (z. B. Lidar-Punktwolken) **[geprüft]** | SDL2 ist im Wartungsmodus, Nachfolger ist SDL3 **[recherchiert]**; Fedora, Arch, Tumbleweed liefern „SDL2“ schon als `sdl2-compat` **[geprüft]** |
| Bei 4K auf dieser Maschine 41 fps gegen 23 fps bei GTK/Cairo, bei 1080p in der Gesamtkette etwas sparsamer (76 % gegen 83 %) **[gemessen]** | Kamerabild hochladen kostete in unserem Test ~29 Prozentpunkte CPU und ließ sich mit den üblichen Mitteln nicht senken **[gemessen]** |
| Für die echten Clients die niedrigste Gesamtlast über die ganze Darstellungskette (116 % gegen 123–139 % bei GTK) **[gemessen]** | PNG speichern braucht zusätzlich SDL2_image (nicht installiert), eingebaut ist nur BMP **[geprüft]** |

### GTK3 + Cairo + Pango

| Pro | Contra |
|---|---|
| Auf jedem Ubuntu-/GNOME-Desktop vorhanden (`ubuntu-desktop` hängt von `libgtk-3-0` und `libcairo2` ab) **[geprüft]**, Schriften über fontconfig/Pango ohne Pfade | 277 Pakete Abhängigkeitskette, `libgtk-3-0` allein 10 MB; LGPL, statisches Linken unrealistisch **[geprüft]** |
| Echte Widgets, Dialoge, Dateiauswahl, Theming, Eingabemethoden, Barrierefreiheit **[Wissen]**; `GtkGLArea` für OpenGL **[geprüft]** | Kein Gamepad-/Lenkrad-/Haptik-API (kein Treffer in den GTK-Headern) **[geprüft]** |
| Cairo: Vektorzeichnen mit Alpha, PNG/SVG/PDF-Export ohne Zusatzbibliothek **[geprüft]**; CARLAs BGRA8 ist Cairos ARGB32, keine Umrechnung | Zeichnen auf der CPU, die Pixel gehen anschließend durch X-Server und Compositor: 1080p kostet in Summe etwas mehr als bei SDL (83 % gegen 76 %), bei 4K nur 23 fps **[gemessen]** |
| Wayland nativ stabil auf allen 9 getesteten Distributionen **[gemessen]** | Ereignisgesteuert: eigene Hauptschleife passt nicht, blockierende CARLA-Aufrufe (`Tick`) blockieren die Oberfläche; Tastenzustand muss man selbst führen **[Erfahrung]** |
| Geringster Speicherbedarf (165 MB gegen 217 MB bei SDL) und leichter Hauptthread **[gemessen]** | GTK3 ist im Wartungsmodus (eine Veröffentlichung pro Jahr), Zukunft ist GTK4 mit anderem API **[recherchiert]** |
| Python-Anbindung (PyGObject 3.42.1 ist hier installiert) **[geprüft]** | Umgebungsfallen: Locale (`LC_NUMERIC=de_DE` ließ LibCarla abstürzen) und Snap-Variablen aus dem VS-Code-Terminal **[gemessen]** |

---

## 2. Empfehlung nach Einsatzzweck

| Einsatzzweck | Empfehlung | Begründung |
|---|---|---|
| **Manuell fahren** mit Kamerabild, später mit Gamepad oder Lenkrad | **SDL** (für Neues SDL3) | Eingabegeräte und Force Feedback eingebaut, niedrigste Gesamtlast, GPU-Pfad skaliert besser |
| **Mehrere Kamerabilder / hohe Auflösung** (Mosaik, 4K) | **SDL/OpenGL oder Qt** | GTK3/Cairo schaffte bei 4K nur 23 fps; Pixel müssten sonst durch X-Server und Compositor |
| **Werkzeug mit Formularen**, Einstellungsdialogen, Dateiauswahl, Tabellen | **GTK (besser GTK4) oder Qt 6** | Widgets, Theming, Barrierefreiheit gibt es nur dort |
| **Kleine Hilfsfenster ohne zusätzliche Pakete**, nur auf GNOME/Ubuntu-Desktop | **GTK3 + Cairo** | Alles schon installiert, saubere Schrift, PNG-Export |
| **Debug-Overlay / Parameter-Regler** über einer laufenden Ansicht | **Dear ImGui** (auf SDL) | Sehr wenig Code für Regler, Plots, Tabellen **[Wissen]** |
| **Ohne Bildschirm / remote / Cluster** | **Web-Oberfläche** oder **Rerun** | Kein Display nötig, Anzeige im Browser **[Wissen]** |
| **Vektorgrafik, Diagramme, Berichte (PNG/SVG/PDF)** | **Cairo** (auch zusammen mit SDL nutzbar) | Eingebaute Ausgabeformate |

Faustregel: **Spiele-/Fahrcharakter und Eingabegeräte → SDL; Anwendungs-/Werkzeugcharakter
mit Dialogen → GTK oder Qt; viele Pixel pro Sekunde → GPU-Pfad.**

---

## 3. Messergebnisse: Effizienz und Performance

Rechner: Intel i7-6850K (12 Threads), NVIDIA GeForce RTX 2080 Ti (Treiber 595.84), Ubuntu 22.04.5,
X11-Sitzung (GNOME, Bildschirm 3072×1920). Server CARLA 0.9.16 offscreen auf demselben Rechner.
CPU-Werte sind **Prozent eines Kerns** (200 % = zwei Kerne ausgelastet).

### 3.1 Die echten Clients (Autopilot, RGB-Kamera 1280×720, 20 s, 3 Läufe)

Gemessen wird der Client-Prozess (alle Threads) **plus die Darstellungskette**
(X-Server `Xorg` und Compositor `gnome-shell`), weil ein Fenster erst dort auf den Schirm kommt.

| Client | Client-CPU | Darstellungskette | **Gesamt** | Speicher | Hauptthread |
|---|---|---|---|---|---|
| Python / pygame (Vorlage) | 145–153 % | 15 % | **160–168 %** | 270–274 MB | 52–54 % |
| C++ / SDL2 | 98–99 % | 17 % | **115–116 %** | 217–221 MB | 30–32 % |
| C++ / GTK3 + Cairo | 81–97 % | 41–42 % | **123–139 %** | 162–165 MB | 20 % |

Bedeutung:

- Die C++-Clients brauchen **weniger CPU als die Python-Vorlage: SDL2 etwa 30 %, GTK3 etwa 20 % weniger**
  (115–139 % gegen 160–168 %); die GUI-Wahl ist daneben zweitrangig. Den Großteil liefern **nicht** der Hauptthread
  mit der Oberfläche, sondern die übrigen Threads des Prozesses (C++: 62–77 %, Python: ~95 % eines Kerns).
  Das sind vermutlich der Empfang der Sensordaten und das Umrechnen der Bilder in LibCarla und im
  Sensor-Rückruf, was bei allen gleich ist; das wurde hier nicht einzeln profiliert.
- **SDL liegt in der Gesamtkette um etwa 15–25 Prozentpunkte vorn.** GTK spart im eigenen
  Prozess (leichterer Hauptthread, 55 MB weniger Speicher), verschiebt die Arbeit aber in
  den X-Server und den Compositor.
- Die Werte des GTK-Clients schwanken zwischen den Läufen stärker (81 → 94 → 97 % im Client).
- Ohne die Darstellungskette (nur Client) wäre GTK3 gleichauf bis sparsamer erschienen
  (`results/apps_client_only_15s.txt`: SDL2 78–101 %, GTK3 80–88 %). **Immer die ganze Kette messen.**

### 3.2 Zeichentest: Kamerabild + HUD mit 60 fps (`bench_sdl`, `bench_gtk`)

Gleiche Szene in beiden: 1280×720 Kamerabild, das sich jedes Frame ändert, halbtransparentes HUD-Panel,
28 Textzeilen (9 ändern sich jedes Frame), drei Balken, Graph, Benachrichtigungsleiste.

**Ganze Kette (Client + Xorg + gnome-shell), `results/system_cpu.txt`:**

| Variante | 720p | 1080p |
|---|---|---|
| SDL, OpenGL-Renderer, Text gecacht | **45 %** (Client 33 + 12) | **76 %** (Client 63 + 13) |
| SDL, Software-Renderer | 72 % | 81 % |
| GTK3 + Cairo, Text gecacht | **54 %** (Client 17 + 37) | **83 %** (Client 25 + 58) |

**Nur der Client-Prozess (`results/local.txt`, ohne Darstellungskette, 720p):**

| Variante | CPU | Zeichenzeit je Frame |
|---|---|---|
| SDL OpenGL, Text jedes Frame neu | 42,6 % | 7,1 ms |
| SDL OpenGL, Text gecacht | 35,5 % | 5,9 ms |
| SDL Software-Renderer | 59,8 % | 9,9 ms |
| GTK3 Fenster, Text jedes Frame neu | 19,4 % | 2,9 ms |
| GTK3 Fenster, Text gecacht | 18,6 % | 2,7 ms |
| Offscreen SDL Software / Cairo (reine CPU-Zeichenkosten) | 29,3 % / 22,3 % | 4,9 ms / 3,7 ms |

**Auflösung (`results/resolution.txt`, Client-Prozess, Text gecacht):**

| | SDL OpenGL | GTK3 + Cairo | Offscreen SDL / Cairo |
|---|---|---|---|
| 1280×720 | 36 % bei 60 fps | 19 % bei 60 fps | 28 % / 21 % |
| 1920×1080 | 64 % bei 60 fps | 27 % bei 60 fps | 50 % / 34 % |
| 3840×2160 | 86 % bei **41 fps** | 27 % bei **23 fps** | 77 % / 72 % |

Bei 4K schafft keine der beiden Varianten 60 fps. GTK liefert nur 23 fps, obwohl der Client
kaum ausgelastet ist: der Engpass liegt vermutlich im X-Server/Compositor (rund 33 MB je Frame;
nicht einzeln nachgewiesen).

**Aufschlüsselung, wohin die CPU geht (`results/ablation.txt`, SDL OpenGL, 720p, nur Client):**

| Weglassen | SDL | GTK3 |
|---|---|---|
| nichts (voller Test) | 42,9 % | 19,3 % |
| Kamerabild | 13,8 % → Bild ≈ **29 Pkt** | 12,0 % → Bild ≈ 7 Pkt |
| Text | 31,4 % → Text ≈ 11 Pkt | 9,2 % → Text ≈ 10 Pkt |
| beides | 1,8 % (Grundlast) | 2,1 % |

Der Text kostet in beiden Frameworks etwa gleich viel. Der Unterschied liegt beim Kamerabild:
bei SDL über den Upload in die GPU-Textur im eigenen Prozess, bei GTK über den X-Server.
Drei Versuche, den SDL-Upload zu senken (`SDL_TEXTUREACCESS_STATIC`, `SDL_LockTexture`,
2–3 abwechselnde Texturen) blieben ohne Wirkung. **Die Ursache ließ sich nicht klären:**
`perf` ist hier gesperrt (`perf_event_paranoid=4`), der Verbrauch ist fast reine User-Zeit im
Hauptthread (42,6 % user, 0,2 % sys).

### 3.3 Ressourcen und Abhängigkeiten

| | SDL2 + SDL2_ttf | GTK3 + Cairo + Pango |
|---|---|---|
| Laufzeitpakete (Ubuntu 22.04, alle Abhängigkeiten) | 69 | 277 |
| Größe Hauptbibliothek | 1,7 MB + 0,1 MB | 10,3 MB (+ Cairo 1,4, Pango 0,7 MB) |
| Dynamisch gelinkte Bibliotheken des Clients | 63 (19 GUI) | 72 (34 GUI) |
| Programmgröße (LibCarla dominiert) | 5,1 MB | 5,1 MB |
| Übersetzungszeit des Benchmarks | 1,4 s | 1,2 s (788 statt 240 Header) |
| Code der Clients | 2121 Zeilen | 2275 Zeilen |
| Anteil, der sich zwischen beiden unterscheidet | 455 Zeilen entfernt | 609 Zeilen hinzugefügt |
| Speicher im Betrieb | 217 MB | 165 MB |
| `ubuntu-desktop` hängt davon ab | `libsdl2-2.0-0` ja, `SDL2_ttf` nein | `libgtk-3-0`, `libcairo2` ja |

### 3.4 Grenzen der Messung

- **Eine Maschine, eine GPU, ein Treiber:** NVIDIA-Proprietärtreiber unter X11. Auf Intel/AMD (Mesa)
  oder unter Wayland können SDL (GL-Pfad) und GTK (Compositor-Pfad) ganz anders abschneiden.
- Die Messungen in Containern (Xvfb, Mesa-Software-Rendering) taugen nur zur **Funktionsprüfung**.
  Deren CPU-Werte (z. B. SDL OpenGL 200–240 %) sind Software-OpenGL und nicht übertragbar.
- Latenz (Eingabe bis Bild), Stromverbrauch, Mehrmonitor, HiDPI und echte Wayland-Sitzungen
  (GNOME/KDE) wurden **nicht** gemessen.
- Getestet sind nur SDL2 und GTK3. SDL3, GTK4, Qt, Dear ImGui sind nur über Paketversionen
  erfasst (Abschnitt 7).
- Die CPU-Werte der echten Clients schwanken zwischen Läufen um bis zu ±10 Prozentpunkte (GTK).

---

## 4. Entwicklung

### 4.1 Programmiermodell

| | SDL2 | GTK3 + Cairo |
|---|---|---|
| Hauptschleife | **Eigene** Schleife, Ereignisse abholen (`SDL_PollEvent`) | **GLib-Hauptschleife** mit Rückrufen (`g_timeout_add`, Signale) |
| Tastatur | Zustand abfragen (`SDL_GetKeyboardState`), wie `pygame.key.get_pressed()` | Nur Ereignisse: gehaltene Tasten selbst mitführen, bei Fokusverlust leeren |
| Blockierende Aufrufe (`world.Tick`) | unproblematisch in der eigenen Schleife | blockieren die Oberfläche, solange sie laufen |
| Zeichnen | Renderer-Aufrufe (Rechteck, Textur, Linie), Text als Textur je Zeile | Cairo-Pfade, Alpha überall, Text über Pango-Layouts |
| Speicherverwaltung | `SDL_Destroy*`, `unique_ptr` mit eigenem Deleter | `g_object_unref`, `cairo_*_destroy`; Cairo-Oberfläche verweist auf Pixel, **Besitzer muss länger leben** |
| Bild speichern | `SDL_SaveBMP` (BMP) | `cairo_surface_write_to_png` (PNG) |
| Fremde Threads → Oberfläche | selbst absichern (Mutex) | selbst absichern (Mutex); GTK ist nicht threadsicher |

Aufwand der Portierung SDL → GTK: rund ein Viertel der Datei musste neu geschrieben werden
(Fenster, Zeichnen, Tastatur, Hauptschleife). Die CARLA-Logik (Welt, Sensoren, Steuerung) blieb gleich.

### 4.2 Stolpersteine aus diesem Projekt **[Erfahrung]**

| Problem | Framework | Folge | Lösung |
|---|---|---|---|
| `gtk_init()` ruft `setlocale(LC_ALL, "")` auf; `LC_NUMERIC=de_DE` | GTK | LibCarla liest OpenDRIVE-Zahlen („1.5“) falsch, **Absturz** in `MapBuilder` | `gtk_disable_setlocale()` und Locale `C` |
| VS-Code-Snap-Terminal setzt `GTK_PATH`, `GIO_MODULE_DIR` … auf `/snap/code` | GTK | „undefined symbol `__libc_pthread_init`“, **Absturz** beim Start | Variablen vor `gtk_init` entfernen |
| Schriftpfad fest eingetragen | SDL | auf Fedora, Arch, openSUSE vermutlich keine Schrift (siehe 6.3) | Schrift über fontconfig suchen |
| SDL installiert eigene Signalbehandlung | SDL | Strg+C wirkte nicht | `SDL_HINT_NO_SIGNAL_HANDLERS` |
| Hilfetext höher als ein 720p-Fenster | SDL, Original | abgeschnitten | in der GTK-Version skaliert |
| Text je Frame neu rendern | SDL | ~11 Prozentpunkte CPU | Cache für unveränderten Text |
| Gleiche Tasten, aber Press/Release nur als Ereignisse | GTK | gehaltene Taste blieb nach Fensterwechsel „gedrückt“ | `focus-out-event` leert den Zustand (getestet) |

### 4.3 Dokumentation, Gemeinschaft, Werkzeuge **[Wissen]**

SDL hat sehr viel Spiele-Literatur und eine ausführliche Wiki-Referenz; GTK hat die GNOME-Entwicklerdoku
und Glade/Builder für Oberflächen; Cairo/Pango sind überall dokumentiert. Beide sind in jeder Distribution
paketiert. Ein ausgereifter Debugger- oder Inspektor-Support ist bei GTK besser (`GTK_DEBUG=interactive`).

---

## 5. Schnittstellen

| Bereich | SDL2 | GTK3 + Cairo + Pango |
|---|---|---|
| Tastatur, Maus | ja | ja |
| **Gamepad, Joystick, Lenkrad, Force Feedback** | **ja** (`SDL_gamecontroller`, `SDL_joystick`, `SDL_haptic`) **[geprüft]** | **nein** (kein Treffer in den Headern); extern nötig (evdev, libmanette) **[geprüft]** |
| Audio, Sensoren | ja (`SDL_audio`, `SDL_sensor`) **[geprüft]** | nein |
| 2D-Zeichnen | Renderer (GPU), Rechtecke, Linien, Texturen | Cairo (CPU, Vektor, Alpha, Verläufe) |
| GPU / 3D | OpenGL, OpenGL ES, Vulkan **[geprüft]** | `GtkGLArea` **[geprüft]**; Cairo selbst CPU |
| Text | SDL2_ttf: Pfad nötig, kein BiDi/Shaping | Pango + fontconfig: Pfad nicht nötig, Shaping, Unicode **[Wissen]** |
| Bildausgabe | BMP; PNG nur mit SDL2_image | **PNG, SVG, PDF, PS** direkt **[geprüft]** |
| Widgets | keine | umfangreich (Menüs, Dialoge, Listen, Dateiauswahl) |
| Sprachanbindung | C-API; gängig für C++, Rust, C#, Python (pygame) | C-API über GObject; Python (PyGObject, **installiert**), Rust, JS, Vala, C++ (gtkmm) **[geprüft/Wissen]** |
| Pixelformat zu CARLA | BGRA8 = `SDL_PIXELFORMAT_BGRA32` (kein Umrechnen) | BGRA8 = `CAIRO_FORMAT_ARGB32` (kein Umrechnen, nur little endian) |
| Lizenz | **zlib** (frei, statisch linkbar) **[geprüft]** | **LGPL** (dynamisch linken) **[geprüft]** |

---

## 6. Kompatibilität mit anderen Linux-Distributionen

### 6.1 Getestet in Containern (`benchmarks/run_distros.sh`)

In jedem Container: distributionseigene Pakete installieren, beide Benchmarks bauen, offscreen laufen
lassen, unter Xvfb (X11) und unter Weston headless (Wayland) starten, die fertigen Clients prüfen.

| Distribution | glibc | SDL2 | GTK3 | beide bauen | X11 | Wayland SDL | Wayland GTK | fertige Clients¹ |
|---|---|---|---|---|---|---|---|---|
| Ubuntu 20.04 | 2.31 | 2.0.10 | 3.24.20 | ja | ja | ok | ok | **nein (glibc)** |
| Ubuntu 22.04 | 2.35 | 2.0.20 | 3.24.33 | ja | ja | **Absturz** | ok | ja |
| Ubuntu 24.04 | 2.39 | 2.30.0 | 3.24.41 | ja | ja | ok | ok | ja |
| Ubuntu 26.04 | 2.43 | 2.32.10 (`libsdl2-classic`) | 3.24.52 | ja | ja | ok | ok | ja |
| Debian 12 | 2.36 | 2.26.5 | 3.24.38 | ja | ja | **Absturz** | ok | ja |
| Debian 13 | 2.41 | 2.32.4 | 3.24.49 | ja | ja | ok | ok | ja |
| Fedora 44 | 2.43 | 2.32.74 (**sdl2-compat**, Paketname) | 3.24.52 | ja | ja | ok | ok | ja |
| Arch Linux | 2.44 | 2.32.74 (**sdl2-compat**, Paketname) | 3.24.52 | ja | ja | ok | ok | ja |
| openSUSE Tumbleweed | 2.44 | 2.32.74 (Versionsnummer wie sdl2-compat) | 3.24.53 | ja | ja | ok | ok | ja |

¹ Die fertigen Clients (auf Ubuntu 22.04 gebaut) wurden nur mit `--help` gestartet: das prüft, dass sich alle
Bibliotheken auflösen lassen, **nicht** die Fensterfunktion. Sie brauchen glibc ≥ 2.34 und libstdc++ ≥ 3.4.30.

### 6.2 Auswertung

- **Quelltext-Kompatibilität ist unkritisch:** Beide Benchmarks bauten ohne Warnung mit SDL 2.0.10 bis
  2.32.74, GTK 3.24.20 bis 3.24.53 und Compilern von GCC 9 bis 16.
- **GTK3 lief auf allen 9 Distributionen unter X11 und unter Wayland.** SDL lief überall unter X11.
- **SDL unter Wayland stürzte bei 2 von 9 Distributionen ab** (Ubuntu 22.04 mit SDL 2.0.20, Debian 12 mit
  SDL 2.26.5): Segfault in `libSDL2` beim Anlegen des Fensters im Weston-headless-Test (Ubuntu 22.04 per `gdb` bestätigt).
  Auf Ubuntu 20.04 und 24.04 sowie allen neueren Distributionen lief es. **Ob das auf einen echten Compositor
  (GNOME, KDE) übertragbar ist, wurde nicht geprüft**; es ist mindestens ein Warnsignal für ältere SDL-Versionen.
- **Fertige Programme sind an die glibc des Bauorts gebunden:** auf Ubuntu 20.04 (glibc 2.31) starten sie nicht.
  Regel: auf der **ältesten** zu unterstützenden Distribution bauen.
- **`sdl2-compat` ist schon Alltag:** Fedora und Arch liefern „SDL2“ (Version 2.32.74) als Paket `sdl2-compat`, also als
  Schicht auf SDL3; Tumbleweed hat dieselbe Versionsnummer (dort nicht am Paketnamen bestätigt). Der SDL-Client band dort
  per Bibliothekssuche, die Fensterfunktion wurde dort nicht geprüft. Der Software-Renderer
  kostete offscreen dort 35–38 % statt 29 % auf klassischem SDL2 (mehr Aufwand in der Schicht).
- Debian hat laut Änderungsprotokoll im April 2026 `sdl2-compat` zur Standardumsetzung von SDL2 gemacht
  **[recherchiert]**; Debian 13 und Ubuntu 26.04 liefern dagegen noch klassisches SDL2.

### 6.3 Weitere Punkte

| Punkt | Befund |
|---|---|
| **Schriften** | `fc-match monospace` liefert je Distribution einen anderen Pfad: `/usr/share/fonts/truetype/dejavu/` (Debian/Ubuntu), `/usr/share/fonts/dejavu-sans-mono-fonts/` (Fedora), `/usr/share/fonts/TTF/` (Arch), `/usr/share/fonts/truetype/` (Tumbleweed) **[geprüft]**. Unsere SDL-Client-Liste enthält nur Debian/Ubuntu-Pfade und Liberation/Noto. Dort wäre daher vermutlich „no usable TrueType font“ zu erwarten **[abgeleitet, nicht gestartet]**. GTK/Pango ist davon nicht betroffen. |
| **X11 und Wayland** | Ohne X-Display wählte SDL in allen Containern, in denen es lief, selbstständig den Wayland-Treiber; GTK nutzt Wayland nativ. Reines Xlib (nicht verwendet) liefe nur über XWayland. |
| **Snap, Flatpak, AppImage** | GTK-Clients reagieren auf Snap-Umgebungsvariablen (siehe 4.2); SDL nicht. Flatpak/AppImage wurden **nicht** getestet. |
| **Locale** | Nur GTK ändert die Locale des Prozesses; LibCarla ist gegen Komma-Dezimalzeichen empfindlich (siehe 4.2). |
| **Architektur** | Nur x86_64 getestet; ARM (z. B. Jetson) offen. |
| **Aktualität** | GTK 3.24.5x erscheint nur noch einmal im Jahr, nächste Version erwartet März 2027 **[recherchiert]**. SDL2 bekommt nur noch Fehlerkorrekturen, Empfehlung der Entwickler ist SDL3 bzw. `sdl2-compat` **[recherchiert]**. |

---

## 7. Weitere Kandidaten und Vorschläge

Versionen aus den Distributions-Paketquellen des Tests **[geprüft]**; alles andere **[Wissen]**, nicht getestet.

| Kandidat | Stärken | Schwächen | Passt zu | Verfügbarkeit im Test |
|---|---|---|---|---|
| **SDL3** (+ SDL3_ttf) | Nachfolger von SDL2 (3.0 im Januar 2025, 3.4 im Januar 2026 **[recherchiert]**); bessere Wayland-/HiDPI-Unterstützung, eigene GPU-API, Gamepad/Haptik | Noch nicht in Ubuntu 22.04/24.04 und Debian 12; dort selbst bauen (zlib-Lizenz, schlank) | Neuentwicklung von Fahr-Clients und Viewern | 3.2.10 (Debian 13), 3.4.2 (Ubuntu 26.04), 3.4.18 (Fedora, Arch, Tumbleweed) |
| **GTK4** (+ Cairo/GSK) | Nachfolger von GTK3, GPU-Rendering, aktiv gepflegt | Anderes API (Ereignis-Controller statt Signale); Cairo-Zeichnen wird eingebettet, für schnelle Videobilder besser `GdkTexture` | Werkzeuge mit Dialogen auf GNOME | 4.6 (Ubuntu 22.04) bis 4.24 (Arch) |
| **Qt 6** (Widgets/QML) | Vollständigstes Angebot: Docking, Diagramme, 3D, Multimedia, `QImage`/`QPainter`; Eingabegeräte über Zusatzmodule | Groß (viele MB/Module), LGPL/kommerziell, eigenes Build-System und Typen | Professionelle Werkzeuge, ROS-Umfeld (RViz) | 6.2 (Ubuntu 22.04) bis 6.12 (Arch) |
| **Dear ImGui** | Regler, Plots, Tabellen in wenigen Zeilen, MIT-Lizenz, läuft **auf SDL oder GLFW** | Kein natives Aussehen, schwache Barrierefreiheit, Text ohne fontconfig | Debug-Overlays, Parameter-Fenster über SDL | als Quelle einbinden (nicht in allen Distributionen) |
| **Web-Oberfläche** (WebSocket/MJPEG) oder **Rerun** | Läuft ohne Display auf dem Rechner, Anzeige im Browser, Plattform egal | Zusätzliche Schicht, Latenz, kein direktes Gamepad ohne Browser-API | Headless-Server, Cluster, Remote-Training | – |
| **wxWidgets**, **FLTK** | wx: native Optik (auf Linux GTK3); FLTK: winzig | wx: gleiche Abhängigkeiten wie GTK; FLTK: kleines Ökosystem | Einfache Werkzeuge | nicht geprüft |
| **SFML**, **raylib** | Sehr einfach für 2D, Audio, Netzwerk | Weniger verbreitet als SDL; keine Widgets | Kleine Lern- und Spiel-Prototypen | nicht geprüft |
| **GLFW + OpenGL/Vulkan** | Fenster plus volle GPU-Kontrolle | Text, Eingabegeräte selbst bauen | 3D-Punktwolken (Lidar) | – |
| **Reines Xlib** | keine Abhängigkeiten | nur X11/XWayland, alles selbst; **nicht empfohlen** | – | – |
| **SDL + Cairo/Pango** (Mischform) | SDL-Fenster und Eingabegeräte, aber Text und Vektorzeichnen mit Pango/Cairo (kein Schriftpfad, PNG-Export) | Zwei Bibliotheken, ein Zusatzschritt (Cairo-Fläche → SDL-Textur) | Fahr-Client, der Schrift sauber und portabel braucht | **nicht erprobt, Vorschlag** |

Im selben Ordner liegen Aufgabenbeschreibungen für Web- und ROS-2-Oberflächen (`carlab.md`, `cycarla.md`,
`foxglove.md`, `ros2.md`). Diese Wege sind hier nur als Kategorie „Web-Oberfläche“ erfasst und **nicht** getestet.

---

## 8. Entscheidungshilfe und nächste Schritte

### Welches Framework?

```
Soll ein Gamepad oder Lenkrad (Force Feedback) bedient werden?   → ja  → SDL (SDL3 bei Neuem)
Sind viele Pixel pro Sekunde zu zeigen (4K, viele Kameras)?       → ja  → SDL/OpenGL oder Qt
Braucht die Oberfläche Dialoge, Formulare, Dateiauswahl?         → ja  → GTK4 oder Qt 6
Muss es ohne zusätzliche Pakete auf GNOME/Ubuntu laufen?          → ja  → GTK3 + Cairo (kleine Fenster)
Läuft es ohne Bildschirm / remote?                                → ja  → Web-Oberfläche / Rerun
Nur Regler und Diagramme zum Testen?                              → ja  → Dear ImGui auf SDL
```

### Für dieses Projekt vorgeschlagen (nicht umgesetzt)

1. **SDL-Schriftsuche über fontconfig statt fester Pfade** (`FcFontMatch` oder `fc-match`): behebt den
   wahrscheinlichen Fehlstart auf Fedora, Arch und openSUSE.
2. **Fertige Programme auf der ältesten unterstützten glibc bauen** (Ubuntu 22.04 reicht für ≥ 22.04;
   für 20.04 dort bauen) und das in der Dokumentation nennen.
3. **Echte Wayland-Sitzungen testen** (GNOME 50 auf Ubuntu 26.04, KDE). Bis dahin bei älteren SDL-Versionen
   `SDL_VIDEODRIVER=x11` als Ausweichmöglichkeit nennen, weil der Wayland-Treiber im Test zweimal abstürzte.
4. **SDL3-Umstieg vorbereiten**, sobald Ubuntu 22.04/24.04 keine Rolle mehr spielen oder SDL3 mitgebaut wird.
   Der SDL2-Code läuft bis dahin über `sdl2-compat`.
5. **Bei GTK bleiben nur als „keine Zusatzpakete“-Variante**; für Neues GTK4 oder Qt 6 prüfen.
6. **`benchmarks/run_distros.sh` in die CI aufnehmen**, damit Bauen und Start auf allen 9 Distributionen
   bei jeder Änderung geprüft werden.
7. **Eine Messung auf Intel/AMD-Grafik** (Mesa) und unter Wayland nachholen; die Ergebnisse zum GPU-Pfad von
   SDL gelten bisher nur für NVIDIA unter X11.

---

## 9. Methodik und Reproduktion

Alle Skripte und Rohdaten liegen unter `research/benchmarks/`.

| Datei | Zweck |
|---|---|
| `scene.h` | gemeinsame Szene und Messhilfen für beide Benchmarks |
| `bench_sdl.cpp`, `bench_gtk.cpp` | Zeichentest mit SDL2 bzw. GTK3 + Cairo (Schalter `--cache`, `--no-picture`, `--no-text`, `--static-texture`, `--lock-texture`, `--ring N`; Auflösung per `-DBENCH_W/H`) |
| `run_local.sh` | alle Varianten auf diesem Rechner (Client-Prozess) → `results/local.txt` |
| `run_system_cpu.sh` | Client **plus** X-Server und Compositor → `results/system_cpu.txt` |
| `run_apps.sh` | die drei echten Clients (Python, SDL, GTK) gegen einen CARLA-Server → `results/apps.txt` |
| `distro_test.sh`, `run_distros.sh` | Test in 9 Containern → `results/distros/*.txt` |
| `results/ablation.txt`, `resolution.txt` | Aufschlüsselung und Auflösungsreihe |
| `results/apps_first_run.txt`, `apps_client_only_15s.txt` | frühere Läufe der echten Clients, nur Client-Prozess |

Aufruf (Beispiele, aus `research/benchmarks/`):

```bash
./run_local.sh 6 2              # Zeichentest, 6 s je Lauf, 2 Wiederholungen (öffnet Fenster)
./run_system_cpu.sh 6           # ganze Darstellungskette
./run_apps.sh 20 3              # echte Clients; startet bei Bedarf einen Server offscreen
./run_distros.sh                # braucht docker und Netz; ./run_distros.sh fedora:latest für eine Distribution
```

Vorgehen und Vorbehalte:

- Jede Variante läuft mit 60 fps-Taktung; die ersten Sekunden (Aufwärmen) zählen nicht.
- CPU ist `getrusage` des Prozesses bzw. `/proc/<pid>/stat` (Client, Xorg, gnome-shell).
- Messung und Text sind in beiden Frameworks gleich gebaut (Text jedes Frame neu, wie in den Clients),
  zusätzlich mit Cache. Weitere Feinarbeit (Glyphen-Atlas, Dirty-Rectangles) wäre in beiden möglich.
- Ergebnisse zwischen Läufen schwanken, besonders bei den echten Clients. Zahlen sind Größenordnungen.
- Die Messreihe hat anfangs nur den Client-Prozess gezählt und dadurch GTK zu günstig dargestellt;
  die Dateien mit „client only“ im Namen oder Kopf sind aus diesem Grund markiert.

## Quellen

- SDL-Wiki, SDL2 im Wartungsmodus und `sdl2-compat`: <https://wiki.libsdl.org/SourceCode>
- Phoronix, SDL 3 (3.0 am 2025-01-21, 3.4 am 2026-01-01): <https://www.phoronix.com/search/SDL+3>
- Debian-Änderungsprotokoll `sdl2-compat` (Umstellung der SDL2-Standardumsetzung): <https://metadata.ftp-master.debian.org/changelogs/main/s/sdl2-compat/testing_changelog>
- Phoronix, GTK3 nur noch eine Veröffentlichung pro Jahr (3.24.52, März 2026): <https://phoronix.com/news/gtk3-annual-release-cadence>
- Paketversionen, Header und Messwerte: eigene Messung (siehe Abschnitt 9)
