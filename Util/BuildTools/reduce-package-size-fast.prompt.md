# Prompt: CARLA-Paketgröße schnell & effizient reduzieren (Windows + Linux)

Wiederverwendbarer Prompt, um das `make package`-Dist-Paket mit **maximalem GB-Gewinn pro
Aufwand** zu verkleinern — auf **Windows** und **Linux**. Einem Agenten auf einem frischen
Clone geben oder selbst abarbeiten. Keep-Listen unten anpassen.

Quellen: Linux-Build <https://carla.readthedocs.io/en/latest/build_linux/> ·
Windows-Build <https://carla.readthedocs.io/en/latest/build_windows/> ·
OpenDRIVE-Standalone <https://carla.readthedocs.io/en/latest/adv_opendrive/>

Belegte Referenz-Reduktion (UE4.26): Tarball ~5,5 → **2,8 GB**, entpackt ~13 → **7,3 GB**
(~halbiert, ohne Funktionsverlust für den Kern-Sim). Details:
[reduce-package-size.report.md](reduce-package-size.report.md).

---

```
Ziel: Das aus diesem CARLA-Repo gebaute Dist-Paket (make package) schnell und
effizient verkleinern - fuer Windows UND Linux. KEIN --packages= angeben.

KEEP-LISTEN (anpassen):
  Maps:       Town01, Town04
  Fahrzeuge:  vehicle.tesla.model3, vehicle.audi.a2, vehicle.lincoln.mkz_2020,
              vehicle.dodge.charger_police, vehicle.carlamotors.firetruck,
              vehicle.harley-davidson.low_rider, vehicle.diamondback.century
  Fussgaenger: BP_Walker_Female1_v1, BP_Walker_Male1_v1

GRUNDPRINZIP:
- Inhaltliche Reduktionen (Config + Assets) wirken auf BEIDE Plattformen, weil sie
  Quell-/Content-Dateien aendern, die in den .pak gecookt werden. Einmal machen,
  fuer Win+Linux nutzen.
- Lose Dateien (Debug-Symbole, HD-Punktwolken, Beispiele) lassen sich auch NACH dem
  Build per Skript loeschen (schnell, ohne Rebuild) - aber NUR lose Dateien, nicht
  den gecookten .pak-Content.
- Immer am ECHTEN gebauten Paket messen (du / Explorer), nicht an Quell-Assets.

================ REIHENFOLGE NACH EFFIZIENZ (GB pro Aufwand) ================

[1] Debug-Symbole AUS  (~1,7 GB, 1 Zeile)  <-- bester Hebel
    Unreal/CarlaUE4/Config/DefaultGame.ini: IncludeDebugFiles=False
    (entfernt *.debug/*.sym/*.pdb). Zusaetzlich bCompressed=True.

[2] Maps-Cook-Liste kuerzen + Default-Map  (Config, schnell)
    DefaultGame.ini MapsToCook: nur Keep-Maps (Standard, OHNE _Opt). Diese 3
    Support-Eintraege MUESSEN bleiben:
      +MapsToCook=(FilePath="/Game/Carla/Maps/OpenDriveMap")
      +MapsToCook=(FilePath="/Game/Carla/Maps/TestMaps/EmptyMap")
      +MapsToCook=(FilePath="/Carla/PostProcessingMaterials/AnnotationColorLandscape")
    DefaultEngine.ini [GameMapsSettings]: EditorStartupMap/GameDefaultMap/
    ServerDefaultMap/TransitionMap auf eine Keep-Map (z. B. Town01.Town01), sonst
    startet der Server nicht. ParkedVehicles-Zeile aus DirectoriesToAlwaysCook raus.

[3] HD-Punktwolken selektiv  (~1,08 GB)
    Nur die .pcd der Keep-Maps behalten. Entweder Package.sh (Linux) auf selektives
    Kopieren patchen, ODER nach dem Build per Skript loeschen (siehe [7]).

[4] Fahrzeug-Bibliothek trimmen  (~1 GB, headless)
    VehicleFactory hat ein editierbares Member-Array `Vehicles` -> per UE4-Python:
      cdo = unreal.get_default_object(unreal.load_object(None,
            '/Game/Carla/Blueprints/Vehicles/VehicleFactory.VehicleFactory_C'))
      def vid(v): return "vehicle.%s.%s"%(str(v.get_editor_property("make")).lower(),
                                          str(v.get_editor_property("model")).lower())
      cdo.set_editor_property("Vehicles",[v for v in cdo.get_editor_property("Vehicles")
                                          if vid(v) in KEEP])
      unreal.EditorAssetLibrary.save_asset('/Game/Carla/Blueprints/Vehicles/VehicleFactory',False)

[5] Alle Gebaeude aus den Keep-Maps  (~1,8 GB, headless; gebaeudelose Maps!)
    Nur wenn gebaeudelose Maps ok sind. Pro Keep-Map (Standard, ohne _Opt):
      unreal.EditorLoadingAndSavingUtils.load_map('/Game/Carla/Maps/Town01.Town01')
      fuer jeden Aktor mit StaticMesh-Komponente unter '/Carla/Static/Building/':
        unreal.EditorLevelLibrary.destroy_actor(a)
      unreal.EditorLevelLibrary.save_current_level()
    Referenz-Closure: ~98 % von Static/Building faellt weg.

[6] Fussgaenger-Bibliothek trimmen  (~2 GB Pedestrian+Hair; NUR GUI)
    WalkerFactory speichert die Fussgaenger im DEFAULT-WERT der LOKALEN Variable
    `Walkers` der Funktion GenerateDefinitions -> NICHT headless editierbar. Im UE4-
    Editor: WalkerFactory oeffnen -> Funktion GenerateDefinitions -> Variable
    `Walkers` anklicken -> Details -> Default Value -> alle Array-Eintraege bis auf
    die Keep-Modelle loeschen -> Compile -> Save. Einfache Female1/Male1 behalten ->
    grosse Hair-Grooms (AfroGirl 268 MB, kid 199 MB) entfallen.

[7] Lose Extras nach dem Build  (~0,2-1+ GB, ohne Rebuild)
    Mitgelieferte Skripte ausfuehren auf das entpackte Paket:
      Linux:   bash Util/BuildTools/reduce-linux-package.sh   /pfad/LinuxNoEditor -y
      Windows: Util\BuildTools\reduce-windows-package.bat      C:\pfad\WindowsNoEditor /y
    (loeschen ueberzaehlige .pcd, Debug-Symbole, PythonAPI\examples\nvidia,
     Co-Simulation, statische Link-Libs, TownBig.xodr).

[8] OPTIONAL maximal: Town-Maps GANZ weglassen (OpenDRIVE-Standalone)
    Wenn das Szenario .xodr-basiert ist: in MapsToCook nur OpenDriveMap+Support
    behalten (keine Towns), Welt zur Laufzeit via client.generate_opendrive_world()
    erzeugen -> entfernt restlichen Town-Content (Vegetation ~1,2 GB, Strassen, Props)
    -> mehrere GB. Dann sind [5]/[6] fuer Towns gegenstandslos.

REVERSIBILITAET:
- Config ([1][2][3]) ist git-getrackt -> git checkout.
- Assets ([4][5][6]: .uasset/.umap) sind NICHT git-getrackt (CARLA-Content separat,
  kein LFS). VOR jeder Aenderung manuell sichern (cp/copy); Restore nur ueber Backup
  oder erneutes Content-Beziehen (Update.sh / Update.bat).

================ PLATTFORM-SPEZIFISCH ================

Gemeinsam: UE4_ROOT auf den UE4.26-Fork setzen. Inhaltliche Hebel [1]-[6] EINMAL
machen; die geaenderten .uasset/.umap sind plattformunabhaengig und gelten fuer
beide Builds (ggf. in den anderen Clone unter identische Content/-Pfade kopieren).

Headless UE4-Python-Aufruf (fuer [4]/[5]):
  Linux:   "$UE4_ROOT/Engine/Binaries/Linux/UE4Editor"  CarlaUE4.uproject \
             -run=pythonscript -script="x.py" -unattended -nosplash -nullrhi -NoShaderCompile
  Windows: "%UE4_ROOT%\Engine\Binaries\Win64\UE4Editor.exe" CarlaUE4.uproject ^
             -run=pythonscript -script="x.py" -unattended -nosplash -nullrhi -NoShaderCompile

LINUX bauen:
  export UE4_ROOT=~/UnrealEngine_4.26
  make package
  -> Dist/CARLA_<id>/LinuxNoEditor/   (starten: ./CarlaUE4.sh)
  danach [7]: bash Util/BuildTools/reduce-linux-package.sh Dist/CARLA_<id>/LinuxNoEditor -y

WINDOWS bauen (x64 Native Tools Command Prompt for VS 2022, im CARLA-Root):
  set UE4_ROOT=<Pfad-zum-UE4.26-Fork>
  Update.bat            (Assets beziehen, beim ersten Mal)
  make PythonAPI        (beim ersten Build noetig)
  make package
  -> WindowsNoEditor-Paketordner   (starten: CarlaUE4.exe)
  danach [7]: Util\BuildTools\reduce-windows-package.bat <Pfad>\WindowsNoEditor /y

VERIFIKATION (beide):
- Paketgroesse vor/nach vergleichen (du -sh bzw. Explorer); grosse Brocken pruefen
  (keine *.debug/*.sym/*.pdb; nur Keep-Town .pcd).
- Server starten -> kommt mit Keep-Default-Map hoch.
- Python: get_available_maps() = nur Keep-Maps; get_blueprint_library().filter('vehicle.*')
  und '...walker.pedestrian.*' = nur Keep-Set.
```

---

## Schnellster sinnvoller Pfad (Minimalaufwand, ~3 GB ohne GUI)
[1] Debug aus + [2] Maps/Config + [3] pcd + [4] Fahrzeuge (headless) + [7] Extras —
alles Config/Skript/headless in Minuten, **ein** Build. Gebäude [5] (headless, gebäudelose
Maps) und Fußgänger [6] (GUI) nur, wenn die zusätzlichen ~3,8 GB den Aufwand wert sind.

## Verwandte Dateien
- [reduce-package-size.report.md](reduce-package-size.report.md) — was genau geändert wurde + Restore.
- [reduce-actor-library.prompt.md](reduce-actor-library.prompt.md) — Fahrzeug-/Fußgänger-Bibliothek im Detail.
- [reduce-linux-package.sh](reduce-linux-package.sh) / [reduce-windows-package.bat](reduce-windows-package.bat) — Post-Build-Cleanup loser Dateien.
