# Report: Paketgröße-Reduktion — entfernte Maps & stufenweise Wiederherstellung

Dieser Report dokumentiert **exakt**, was geändert wurde, um die Größe des
`make package`-Pakets zu reduzieren, und wie sich die Maps **stufenweise**
wieder hinzufügen lassen.

## Wichtig: Es wurden keine Quelldateien gelöscht

Physisch wurde **keine** `.umap`/Asset-Datei aus dem Repo entfernt. Reduziert
wurde ausschließlich, **welche Maps beim Packen gecookt werden** — über das
Entfernen von Einträgen aus der `MapsToCook`-Liste in
[Unreal/CarlaUE4/Config/DefaultGame.ini](../../Unreal/CarlaUE4/Config/DefaultGame.ini).
Maps, die nicht in dieser Liste stehen, landen nicht im Paket → kleineres Paket.

„Wiederherstellen" bedeutet daher: den/die Eintrag/Einträge wieder in die Liste
aufnehmen und **neu bauen** (`make package`). Die zugehörigen Assets liegen
unverändert im Repo, es geht nichts verloren.

## Was geändert wurde

### 1. Entfernte Cook-Einträge (DefaultGame.ini, `[/Script/UnrealEd.ProjectPackagingSettings]`)

Vorher: 6 Towns (je Standard + `_Opt`). Nachher: nur Town01 + Town04.
Entfernt wurden diese **8 Zeilen**:

| Map         | Entfernte Zeile                                          | ca. Größe* |
|-------------|----------------------------------------------------------|-----------|
| Town02      | `+MapsToCook=(FilePath="/Game/Carla/Maps/Town02")`       | ~11 MB    |
| Town02_Opt  | `+MapsToCook=(FilePath="/Game/Carla/Maps/Town02_Opt")`   | (Variante)|
| Town03      | `+MapsToCook=(FilePath="/Game/Carla/Maps/Town03")`       | ~180 MB   |
| Town03_Opt  | `+MapsToCook=(FilePath="/Game/Carla/Maps/Town03_Opt")`   | (Variante)|
| Town05      | `+MapsToCook=(FilePath="/Game/Carla/Maps/Town05")`       | ~mittel   |
| Town05_Opt  | `+MapsToCook=(FilePath="/Game/Carla/Maps/Town05_Opt")`   | (Variante)|
| Town10HD    | `+MapsToCook=(FilePath="/Game/Carla/Maps/Town10HD")`     | ~43 MB    |
| Town10HD_Opt| `+MapsToCook=(FilePath="/Game/Carla/Maps/Town10HD_Opt")` | (Variante)|

\* Grobe Richtwerte der gecookten Map-Inhalte; Town03 und Town10HD sind die
größten Posten und liefern den größten Reduktionsgewinn.

**Behalten** wurden: Town01, Town01_Opt, Town04, Town04_Opt sowie die drei
Support-Einträge `OpenDriveMap`, `TestMaps/EmptyMap`, `AnnotationColorLandscape`
(notwendig für OpenDRIVE-Import und Semantik-/Sensor-Postprocessing).

### 2. Standard-Startmap umgestellt (DefaultEngine.ini, `[/Script/EngineSettings.GameMapsSettings]`)

Da `Town10HD_Opt` nicht mehr gecookt wird, würde der Server mit der alten
Default-Map nicht starten. Deshalb **zwingend** geändert (4 Einträge):

| Einstellung       | vorher                                       | nachher                              |
|-------------------|----------------------------------------------|--------------------------------------|
| EditorStartupMap  | `/Game/Carla/Maps/Town10HD_Opt.Town10HD_Opt` | `/Game/Carla/Maps/Town01.Town01`     |
| GameDefaultMap    | `/Game/Carla/Maps/Town10HD_Opt.Town10HD_Opt` | `/Game/Carla/Maps/Town01.Town01`     |
| ServerDefaultMap  | `/Game/Carla/Maps/Town10HD_Opt.Town10HD_Opt` | `/Game/Carla/Maps/Town01.Town01`     |
| TransitionMap     | `/Game/Carla/Maps/Town10HD_Opt.Town10HD_Opt` | `/Game/Carla/Maps/Town01.Town01`     |

---

## Stufenweise Wiederherstellung

Reihenfolge frei wählbar; pro Town je **beide** Zeilen (Standard + `_Opt`) wieder
einfügen. Jeweils unter die bestehenden `+MapsToCook=`-Zeilen in
[DefaultGame.ini](../../Unreal/CarlaUE4/Config/DefaultGame.ini) setzen, dann
`make package` neu ausführen. Empfohlene Reihenfolge: kleinste zuerst.

### Stufe A — Town02 zurückholen (~+11 MB, kleinster Schritt)
```
+MapsToCook=(FilePath="/Game/Carla/Maps/Town02")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town02_Opt")
```

### Stufe B — Town05 zurückholen
```
+MapsToCook=(FilePath="/Game/Carla/Maps/Town05")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town05_Opt")
```

### Stufe C — Town10HD zurückholen (~+43 MB)
```
+MapsToCook=(FilePath="/Game/Carla/Maps/Town10HD")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town10HD_Opt")
```
> Optional: Wenn Town10HD wieder die Standard-Startmap sein soll, in
> [DefaultEngine.ini](../../Unreal/CarlaUE4/Config/DefaultEngine.ini) die 4
> Einträge zurück auf `/Game/Carla/Maps/Town10HD_Opt.Town10HD_Opt` setzen.

### Stufe D — Town03 zurückholen (~+180 MB, größter Posten)
```
+MapsToCook=(FilePath="/Game/Carla/Maps/Town03")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town03_Opt")
```

### Voll-Wiederherstellung (Originalzustand)

Komplette `MapsToCook`-Liste wie vor der Reduktion — alle 6 Towns:
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
Plus in [DefaultEngine.ini](../../Unreal/CarlaUE4/Config/DefaultEngine.ini) die 4
Map-Einträge zurück auf `Town10HD_Opt`.

### Alternative: kompletter Rückbau per Git
Wenn die Reduktion als ein Commit vorliegt, lässt sich der Originalzustand auch
direkt wiederherstellen:
```
git checkout <commit-vor-der-reduktion> -- \
  Unreal/CarlaUE4/Config/DefaultGame.ini \
  Unreal/CarlaUE4/Config/DefaultEngine.ini
```

---

## Nach jeder Wiederherstellungsstufe
1. `make package` (ohne `--packages=`).
2. Größe mit `du -sh` prüfen.
3. Server starten; Python: `client.get_available_maps()` muss die wieder
   hinzugefügte Town zeigen, `load_world('<Town>')` muss laden.

Siehe auch [reduce-package-size.prompt.md](reduce-package-size.prompt.md) für den
allgemeinen Reduktions-Prompt.
