# Report: Paketgröße-Reduktion — alle Hebel & Wiederherstellung

Dieser Report dokumentiert **exakt**, was geändert wurde, um die Größe des
`make package`-Pakets zu reduzieren, mit **gemessenen** Größen und einer
Wiederherstellungs-Anleitung je Hebel.

## Ergebnis (gemessen, Build `aaf63ca0d`)

| | vorher (Original, 6 Towns) | nachher (alle Hebel) | Ersparnis |
|---|---|---|---|
| Tarball `.tar.gz` | ~5,5 GB | **2,8 GB** (2.793.556.529 B) | **~49 %** |
| Entpackt (`LinuxNoEditor`) | ~13 GB | **7,3 GB** (12.945 Dateien) | **~44 %** |

Das Dist-Paket ist damit grob **halbiert** — ohne Funktionsverlust für den Kern-Sim:
Town01/Town04 fahrbar, reduzierte aber funktionale Fahrzeug-/Fußgänger-Bibliothek,
Maps gebäudelos. **Stand: abgeschlossen, keine weiteren Reduzierungen geplant.**

### Was insgesamt noch möglich wäre (bewusst NICHT umgesetzt)
- **OpenDRIVE-Standalone:** Town-Maps ganz weglassen (nur `OpenDriveMap`), Welt zur
  Laufzeit aus `.xodr` generieren (`client.generate_opendrive_world`) → entfernt den
  restlichen Town-Content (Vegetation ~1,2 GB, Straßen, Props, Mauern) → mehrere GB.
  Nur sinnvoll, wenn das Szenario `.xodr`-basiert ist (siehe CARLA-Doku „OpenDRIVE
  standalone mode").
- **Gebündelte Extras via Package.sh** (~230 MB): `PythonAPI/examples` (nvidia/cosmos
  ~142 MB), `Co-Simulation/` (25 MB), statische `.a`-Libs (~44 MB, nur Link-Zeit),
  `TownBig.xodr` (15 MB).
- **Vegetation aus den Maps entfernen** (analog zu den Gebäuden) → ~1,2 GB, aber kahle Maps.
- Features wie RSS/ROS2/Chrono/CarSim sind in diesem Build ohnehin **nicht** enthalten.

## Wichtigste Erkenntnis (gemessen)

Die **Maps sind NICHT der Haupttreiber**: Town01+Town04 statt 6 Towns brachte im
Tarball nur ~100 MB (5,5 → 5,4 GB). Die Größe steckt im **geteilten gecookten
Content**, in **Debug-Symbolen** und in den **HD-Punktwolken**. Gemessenes
Paket (`CARLA_Shipping_<rev>/LinuxNoEditor`, ~13 GB extrahiert):

| Posten im Paket | Größe |
|---|---|
| `CarlaUE4/Content/Carla/Static/` (gecookt) | 7,9 GB |
| ‣ Building 1,8 · Pedestrian 1,4 · Vegetation 1,2 · Car 0,9 · Hair 0,69 · Truck 0,5 GB | |
| `CarlaUE4-Linux-Shipping.debug` (Debug-Symbole) | 1,6 GB |
| `HDMaps/*.pcd` (7 Towns) | 1,6 GB |
| `CarlaUE4-Linux-Shipping.sym` | 77 MB |

## Hebel-Übersicht

| # | Hebel | gemessen/geschätzt | Datei | git? |
|---|---|---|---|---|
| 1 | MapsToCook nur Town01+Town04 (ohne `_Opt`) | ~100 MB + einige 100 MB | DefaultGame.ini | ✅ |
| 2 | Default-Startmap → Town01 (zwingend) | — | DefaultEngine.ini | ✅ |
| 3 | `bCompressed=True` | kleineres .pak | DefaultGame.ini | ✅ |
| 4 | `ParkedVehicles` aus DirectoriesToAlwaysCook | gering | DefaultGame.ini | ✅ |
| 5 | **`IncludeDebugFiles=False`** | **~1,68 GB** (.debug+.sym) | DefaultGame.ini | ✅ |
| 6 | **HDMaps `.pcd` selektiv (Town01/04)** | **~1,08 GB** | Package.sh | ✅ |
| 7 | **VehicleFactory 41 → 7 Fahrzeuge** | ~1 GB | VehicleFactory.uasset | ❌ |
| 8 | **WalkerFactory 52 → 2 Fußgänger** | ~2 GB (Pedestrian+Hair) | WalkerFactory.uasset | ❌ |
| 9 | **Alle Gebäude aus Town01+Town04** | **~1,81 GB** (98,4 % Building) | Town01.umap, Town04.umap | ❌ |

Grobe Gesamtprojektion: von ~13 GB extrahiert **~7–8 GB** weg. Exakt erst nach Build.

> ⚠️ **git-getrackt vs. nicht:** Configs (1–6) liegen in git → Restore via `git checkout`.
> Die Asset-Änderungen (7–9: `.uasset`/`.umap`) sind **NICHT** in git (CARLA-Content wird
> separat verwaltet, kein LFS). Restore nur über **eigenes Backup** oder erneutes Beziehen
> des CARLA-Contents. Vor solchen Änderungen **immer manuell sichern** (`cp`).

---

## Detail je Hebel

### 1–6: Config-Änderungen (git-getrackt)

**DefaultGame.ini** (`[/Script/UnrealEd.ProjectPackagingSettings]`):
- `MapsToCook`: nur `Town01`, `Town04` + Support (`OpenDriveMap`, `TestMaps/EmptyMap`,
  `AnnotationColorLandscape`). Entfernt: Town02/03/05/10HD **und** alle `_Opt`-Varianten
  (Town01_Opt/Town04_Opt — `_Opt` = layered/Runtime-Layer-Maps, ohne Gebäude unnötig).
- `bCompressed=False` → `True`
- `IncludeDebugFiles=True` → `False`  ← **größter Config-Hebel (~1,68 GB)**
- Zeile `+DirectoriesToAlwaysCook=(Path="Carla/Static/Car/4Wheeled/ParkedVehicles")` entfernt.

**DefaultEngine.ini** (`[/Script/EngineSettings.GameMapsSettings]`): alle 4 Map-Einträge
(`EditorStartupMap`, `GameDefaultMap`, `ServerDefaultMap`, `TransitionMap`) von
`Town10HD_Opt` → `Town01.Town01` (sonst startet der Server nicht).

**Package.sh** (~Zeile 327): `HDMaps/*.pcd` wird nicht mehr pauschal kopiert, sondern nur
für die gecookten Towns:
```bash
for HDMAP_TOWN in Town01 Town04 ; do
  copy_if_changed "./Unreal/CarlaUE4/Content/Carla/HDMaps/${HDMAP_TOWN}.pcd" "${DESTINATION}/HDMaps/"
done
```

### 7: VehicleFactory 41 → 7 (nicht git)
`Content/Carla/Blueprints/Vehicles/VehicleFactory.uasset` — Member-Array `Vehicles`
(headless via UE4-Python skriptbar). Behalten: `vehicle.tesla.model3`, `audi.a2`,
`lincoln.mkz_2020`, `dodge.charger_police`, `carlamotors.firetruck`,
`harley-davidson.low_rider`, `diamondback.century`. Siehe
[reduce-actor-library.prompt.md](reduce-actor-library.prompt.md).

### 8: WalkerFactory 52 → 2 (nicht git, nur GUI)
`Content/Carla/Blueprints/Walkers/WalkerFactory.uasset` — die Fußgänger stehen im
**Default-Wert der lokalen Variable `Walkers`** der Funktion `GenerateDefinitions`
(kein CDO-Member → headless NICHT editierbar, nur UE4-Editor-GUI). Behalten:
`BP_Walker_Female1_v1`, `BP_Walker_Male1_v1` (einfache Modelle → die großen Hair-Grooms
AfroGirl 268 MB / kid 199 MB entfallen).

### 9: Alle Gebäude aus Town01+Town04 (nicht git)
`Content/Carla/Maps/Town01.umap` (232 Aktoren) und `Town04.umap` (110 Aktoren) — alle
Aktoren mit einer StaticMesh-Komponente unter `/Static/Building/` headless gelöscht
(`destroy_actor` + `save_current_level`). Verifiziert: 0 verbleibende Gebäude-Aktoren;
Referenz-Closure-Analyse zeigt **98,4 %** des Building-Contents (4.705 von 4.783 MB Quelle)
fällt weg → **~1,81 GB** gecookt. Übrig bleiben nur ~78 MB Rest-Texturen (geteilte
Prozedural-/Window-Materialien). Maps sind danach **gebäudelos** (Straßen/Gehwege/Mauern/
Vegetation/Props/Verkehr bleiben; gebackenes Licht `_BuiltData` ist veraltet → evtl.
leichte Schatten-Artefakte).

---

## Wiederherstellung

### Config (1–6) — via git
```
git checkout <commit-vor-reduktion> -- \
  Unreal/CarlaUE4/Config/DefaultGame.ini \
  Unreal/CarlaUE4/Config/DefaultEngine.ini \
  Util/BuildTools/Package.sh
```
Einzeln: `MapsToCook`-Zeilen wieder ergänzen (`_Opt` + weitere Towns), `bCompressed=False`,
`IncludeDebugFiles=True`, `ParkedVehicles`-Zeile zurück, Package.sh-`.pcd`-Loop auf
`*.pcd` zurück, Default-Map zurücksetzen.

Volle Original-`MapsToCook` (6 Towns + `_Opt` + Support):
```
+MapsToCook=(FilePath="/Game/Carla/Maps/Town01")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town01_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town02")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town02_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town03")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town03_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town04")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town04_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town05")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town05_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town10HD")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town10HD_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/OpenDriveMap")
+MapsToCook=(FilePath="/Game/Carla/Maps/TestMaps/EmptyMap")
+MapsToCook=(FilePath="/Carla/PostProcessingMaterials/AnnotationColorLandscape")
```

### Assets (7–9) — NICHT via git
Diese `.uasset`/`.umap` sind nicht versioniert. Restore nur über:
- ein **eigenes Backup** der Originaldateien (vor der Änderung anlegen!), oder
- erneutes Beziehen des CARLA-Contents (Content-Download/Update des Repos).

Betroffene Dateien:
```
Unreal/CarlaUE4/Content/Carla/Blueprints/Vehicles/VehicleFactory.uasset
Unreal/CarlaUE4/Content/Carla/Blueprints/Walkers/WalkerFactory.uasset
Unreal/CarlaUE4/Content/Carla/Maps/Town01.umap (+ Town01_BuiltData.uasset)
Unreal/CarlaUE4/Content/Carla/Maps/Town04.umap (+ Town04_BuiltData.uasset)
```

---

## Nach jeder Änderung
1. `make package` (ohne `--packages=`; Package.sh löscht den Build-Ordner vorher).
2. Größe mit `du -sh` prüfen (Tarball + extrahiert).
3. Gepacktes `CarlaUE4.sh` starten → Server kommt mit Town01 hoch.
4. Python: `client.get_available_maps()` zeigt nur Town01/Town04;
   `get_blueprint_library().filter('vehicle.*')` / `'walker.pedestrian.*'` zeigt das Keep-Set.

Siehe auch [reduce-package-size.prompt.md](reduce-package-size.prompt.md) (Gesamt-Prompt)
und [reduce-actor-library.prompt.md](reduce-actor-library.prompt.md) (Aktor-Bibliothek).
