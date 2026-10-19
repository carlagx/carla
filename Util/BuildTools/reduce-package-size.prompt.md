# Prompt: CARLA-Paketgröße umfassend reduzieren

Wiederverwendbarer Prompt, um die Größe des aus diesem Repo gebauten Dist-/Release-Pakets
(`make package`) deutlich zu reduzieren. Deckt alle am Repo **verifizierten** Hebel ab,
nach gemessener Wirkung sortiert. Auf einem frischen Clone einem Agenten geben oder selbst
abarbeiten. Parametrisiert über die Keep-Listen (Maps / Fahrzeuge / Fußgänger).

---

```
Ziel: Das aus diesem CARLA-Repo gebaute Dist-Paket (`make package`) deutlich
verkleinern. KEIN --packages= angeben (sonst kommen Zusatz-Maps rein). Package.sh
löscht den Build-Ordner vorher -> jedes make package cookt sauber neu.

KEEP-LISTEN (anpassen):
  Maps:       Town01, Town04
  Fahrzeuge:  vehicle.tesla.model3, vehicle.audi.a2, vehicle.lincoln.mkz_2020,
              vehicle.dodge.charger_police, vehicle.carlamotors.firetruck,
              vehicle.harley-davidson.low_rider, vehicle.diamondback.century
  Fußgänger:  BP_Walker_Female1_v1, BP_Walker_Male1_v1

WICHTIG - WO DIE GRÖSSE STECKT (gemessen, nicht raten):
- Maps sind NICHT der Haupttreiber (Town-Reduktion brachte im Tarball nur ~100 MB).
- Echte Brocken im gecookten Paket (~13 GB extrahiert):
    Static/ 7,9 GB (Building 1,8 / Pedestrian 1,4 / Vegetation 1,2 / Car 0,9 /
                    Hair 0,69 / Truck 0,5 ...), Debug-Symbole 1,6 GB, HDMaps .pcd 1,6 GB.
- Immer am ECHTEN gebauten Paket messen (du -sh, find ... -size), nicht an Quell-Assets
  (Quelle ist viel größer; gecookt wird nur, was referenziert ist).

HEBEL nach Wirkung (verifiziert):

[A] Debug-Symbole abschalten  (~1,68 GB)  -- GRÖSSTER Config-Hebel
    DefaultGame.ini: IncludeDebugFiles=False
    Entfernt CarlaUE4-Linux-Shipping.debug (1,6 GB) + .sym (77 MB). Kein Funktionsverlust.

[B] Alle Gebäude aus den Keep-Maps entfernen  (~1,8 GB, falls gewünscht)
    Gebäude sind ein GETEILTER modularer Bausatz (Materials/WindowModules/pieces),
    keine großen Einzelmeshes -> nur das Entfernen ALLER Gebäude-Aktoren aus ALLEN
    gecookten Maps senkt die Größe (Referenz-Closure: ~98 % von Static/Building fällt
    weg). Ergebnis: gebäudelose Maps (Straßen/Vegetation/Props bleiben). Headless per
    UE4-Python: pro Map laden, alle Aktoren mit StaticMesh-Komponente unter
    /Static/Building/ via destroy_actor löschen, save_current_level. NUR machen, wenn
    gebäudelose Maps ok sind.

[C] Fußgänger-Bibliothek trimmen  (~2 GB: Pedestrian+Hair)
    WalkerFactory: Fußgänger stehen im Default-Wert der LOKALEN Variable `Walkers`
    der Funktion GenerateDefinitions -> nur im UE4-Editor-GUI editierbar (kein CDO-
    Member, NICHT headless). Im Details-Panel der Variable `Walkers` alle Array-
    Einträge bis auf die Keep-Modelle löschen. Einfache Female1/Male1-Modelle behalten
    -> die großen Hair-Grooms (AfroGirl 268 MB, kid 199 MB) entfallen.

[D] HDMaps .pcd selektiv  (~1,08 GB)
    Package.sh (~Z.327): statt aller *.pcd nur die der Keep-Maps kopieren:
      for HDMAP_TOWN in Town01 Town04 ; do
        copy_if_changed "./Unreal/CarlaUE4/Content/Carla/HDMaps/${HDMAP_TOWN}.pcd" "${DESTINATION}/HDMaps/"
      done

[E] Fahrzeug-Bibliothek trimmen  (~1 GB)
    VehicleFactory: editierbares Member-Array `Vehicles` -> HEADLESS skriptbar (UE4-
    Python: cdo.set_editor_property("Vehicles", [v for v in ... if vid(v) in KEEP])
    + EditorAssetLibrary.save_asset). Details siehe reduce-actor-library.prompt.md.

[F] Maps-Cook-Liste kürzen + Support behalten  (~100 MB + _Opt-Varianten)
    DefaultGame.ini MapsToCook: nur Keep-Maps (Standard, OHNE _Opt). Diese 3 Support-
    Einträge MÜSSEN bleiben:
      +MapsToCook=(FilePath="/Game/Carla/Maps/OpenDriveMap")
      +MapsToCook=(FilePath="/Game/Carla/Maps/TestMaps/EmptyMap")
      +MapsToCook=(FilePath="/Carla/PostProcessingMaterials/AnnotationColorLandscape")
    _Opt-Maps (layered) weglassen, wenn kein Runtime-Layer-Umschalten gebraucht wird.

[G] Pflicht-Begleitänderung: Default-Startmap
    DefaultEngine.ini [GameMapsSettings]: EditorStartupMap/GameDefaultMap/
    ServerDefaultMap/TransitionMap auf eine Keep-Map setzen (z. B. Town01.Town01),
    sonst startet der Server nicht.

[H] Kleinkram: bCompressed=True (kleineres .pak), ParkedVehicles aus
    DirectoriesToAlwaysCook entfernen.

REVERSIBILITÄT - WICHTIG:
- Configs (A,D,F,G,H) sind git-getrackt -> Restore via git.
- Asset-Änderungen (B,C,E: .uasset/.umap) sind NICHT git-getrackt (CARLA-Content separat,
  kein LFS). VOR jeder Änderung manuell sichern (cp); Restore nur über Backup oder
  erneutes Content-Beziehen.

HEADLESS UE4-PYTHON AUFRUF (für B und E):
  UE4Editor CarlaUE4.uproject -run=pythonscript -script="skript.py" \
    -unattended -nosplash -nullrhi -NoShaderCompile
  (UE4.26: EditorLevelLibrary statt UE5-EditorActorSubsystem.)

VERIFIKATION (nach make package):
- du -sh auf Tarball + extrahiertes LinuxNoEditor; gegen vorher vergleichen.
- find LinuxNoEditor -type f -size +50M  -> grosse Brocken prüfen (keine .debug, nur
  Keep-Town .pcd).
- Server starten (CarlaUE4.sh) -> kommt mit Keep-Default-Map hoch.
- Python: get_available_maps() = nur Keep-Maps; get_blueprint_library().filter('vehicle.*')
  und '...walker.pedestrian.*' = nur Keep-Set; load_world('<entfernte Town>') schlaegt fehl.
```

---

## Reihenfolge-Empfehlung
Config-Hebel zuerst (A, D, F, G, H — schnell, reversibel via git), dann Asset-Hebel
(E headless, C im GUI, B headless mit Backup), **dann genau EIN** `make package`
(Cooking dauert lange — alles in einem Rutsch erfassen).

## Methodik-Hinweis (am Repo bewährt)
- Vor dem Bauen **am bereits gebauten Paket messen**, wo die Größe sitzt
  (`du -sh */`, `find -size +50M`), statt an Quell-Assets.
- Erwartete Ersparnis ohne Build abschätzbar via **Referenz-Closure** (AssetRegistry
  `get_dependencies` über die gecookten Roots): Assets, die nicht in der Closure liegen,
  fallen weg. So wurde z. B. der ~98-%-Building-Drop vor dem Build bestätigt.

## Aktuell angewandter Stand (Beispiel)
`DefaultGame.ini` — `MapsToCook` (nur Town01/Town04, ohne `_Opt`):
```
+MapsToCook=(FilePath="/Game/Carla/Maps/Town01")
+MapsToCook=(FilePath="/Game/Carla/Maps/Town04")
+MapsToCook=(FilePath="/Game/Carla/Maps/OpenDriveMap")
+MapsToCook=(FilePath="/Game/Carla/Maps/TestMaps/EmptyMap")
+MapsToCook=(FilePath="/Carla/PostProcessingMaterials/AnnotationColorLandscape")
```
weiter: `bCompressed=True`, `IncludeDebugFiles=False`, `ParkedVehicles`-Zeile entfernt.

`DefaultEngine.ini` — `[/Script/EngineSettings.GameMapsSettings]`:
```
EditorStartupMap=/Game/Carla/Maps/Town01.Town01
GameDefaultMap=/Game/Carla/Maps/Town01.Town01
ServerDefaultMap=/Game/Carla/Maps/Town01.Town01
TransitionMap=/Game/Carla/Maps/Town01.Town01
```

Siehe auch [reduce-package-size.report.md](reduce-package-size.report.md) (was genau
geändert wurde + Restore) und [reduce-actor-library.prompt.md](reduce-actor-library.prompt.md)
(Fahrzeug-/Fußgänger-Bibliothek im Detail).
