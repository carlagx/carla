# Prompt: CARLA-Paketgröße reduzieren (nur ausgewählte Maps cooken)

Wiederverwendbarer Prompt, um die Größe des aus diesem Repo gebauten Dist-/Release-Pakets
(`make package`) deutlich zu reduzieren. Parametrisiert über die Liste der zu behaltenden Maps.
Auf einem frischen Clone einem Agenten geben oder selbst abarbeiten.

---

```
Ziel: Die Größe des aus diesem CARLA-Repo gebauten Dist-/Release-Pakets
(`make package`) deutlich reduzieren, indem nur eine konfigurierbare Auswahl
an Maps gecookt wird.

ZU BEHALTENDE MAPS: Town01, Town04
(Anpassen nach Bedarf. Town01 = klein/schnell, gut als Standard-Startmap.)

KONTEXT (so entsteht die Größe):
- `make package` ruft Util/BuildTools/Package.sh -> RunUAT.sh BuildCookRun auf.
  Gecookt werden genau die Maps aus der `MapsToCook`-Liste in
  Unreal/CarlaUE4/Config/DefaultGame.ini. Das ist der HAUPT-Größentreiber.
- Standardmäßig sind 6 Towns gelistet (Town01-05 + Town10HD, je Standard + _Opt).
  Town03 und Town10HD sind die größten Posten.
- Town11/12/13/15 sind NICHT im Basispaket (separate "Additional Maps" über
  *.Package.json + --packages=). Nicht anfassen.
- Die Standard-Startmap steht in
  Unreal/CarlaUE4/Config/DefaultEngine.ini [GameMapsSettings].
  WICHTIG: Wird die aktuelle Default-Map nicht mehr gecookt, startet der Server
  NICHT. Default-Map muss eine der behaltenen Maps sein.
- Package.sh löscht den Build-Ordner zu Beginn (rm -Rf RELEASE_BUILD_FOLDER),
  also erzeugt jedes `make package` ein sauberes Paket ohne Reste alter Maps.
  Beim Bauen KEIN --packages= angeben.

AUFGABE:
1. In Unreal/CarlaUE4/Config/DefaultGame.ini die `MapsToCook`-Liste so kürzen,
   dass NUR die zu behaltenden Maps (je Standard + _Opt) übrig bleiben.
   Diese drei Support-Einträge MÜSSEN bleiben (für OpenDRIVE-Import und
   Semantik-/Sensor-Postprocessing):
     +MapsToCook=(FilePath="/Game/Carla/Maps/OpenDriveMap")
     +MapsToCook=(FilePath="/Game/Carla/Maps/TestMaps/EmptyMap")
     +MapsToCook=(FilePath="/Carla/PostProcessingMaterials/AnnotationColorLandscape")
   Die `DirectoriesToAlwaysCook`/`DirectoriesToAlwaysStageAsUFS`-Einträge
   unverändert lassen.

2. In Unreal/CarlaUE4/Config/DefaultEngine.ini im Block
   [/Script/EngineSettings.GameMapsSettings] ALLE vier Map-Einträge
   (EditorStartupMap, GameDefaultMap, ServerDefaultMap, TransitionMap) auf die
   kleinste behaltene Map setzen (z. B. Town01):
     .../Maps/Town01.Town01
   GlobalDefaultGameMode, GameInstanceClass, GlobalDefaultServerGameMode NICHT
   ändern.

KEINE Code-Änderungen, keine Änderung an Package.sh oder *.Package.json nötig.

VERIFIKATION (nach `make package`):
- Paketgröße mit `du -sh` gegen vorher vergleichen.
- Gepacktes CarlaUE4.sh starten -> Server kommt hoch und lädt die Default-Map.
- Python API: client.get_available_maps() zeigt NUR die behaltenen Maps
  (+ _Opt); load_world('Town04') lädt; load_world('Town03') schlägt fehl.
- Im gepackten Inhalt nach entfernten Town-.umap/Pak-Einträgen suchen ->
  dürfen nicht mehr vorhanden sein.

OPTIONAL (kleiner Zusatzgewinn): in Carla/Maps/OpenDrive, Nav, TM und in
HDMaps/*.pcd die Dateien nicht benötigter Towns entfernen.
```

---

## Beispiel: aktuell angewandte Konfiguration (Town01 + Town04)

`Unreal/CarlaUE4/Config/DefaultGame.ini` — `MapsToCook`:

```
+MapsToCook=(FilePath="/Game/Carla/Maps/Town01")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town01_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town04")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town04_Opt")
+MapsToCook=(FilePath="/Game/Carla/Maps/OpenDriveMap")
+MapsToCook=(FilePath="/Game/Carla/Maps/TestMaps/EmptyMap")
+MapsToCook=(FilePath="/Carla/PostProcessingMaterials/AnnotationColorLandscape")
```

`Unreal/CarlaUE4/Config/DefaultEngine.ini` — `[/Script/EngineSettings.GameMapsSettings]`:

```
EditorStartupMap=/Game/Carla/Maps/Town01.Town01
GameDefaultMap=/Game/Carla/Maps/Town01.Town01
ServerDefaultMap=/Game/Carla/Maps/Town01.Town01
TransitionMap=/Game/Carla/Maps/Town01.Town01
```
