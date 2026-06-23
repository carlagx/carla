# Prompt: CARLA Fahrzeug-/Fußgänger-Bibliothek auf Minimal-Set reduzieren

Wiederverwendbarer Prompt, um die spawnbare Aktor-Bibliothek zu verkleinern und damit
das `make package`-Paket weiter zu reduzieren. Es werden NUR die Factory-Arrays getrimmt;
Quell-Assets bleiben unangetastet (voll reversibel).

---

```
Ziel: Die Größe des aus diesem CARLA-Repo gebauten Dist-Pakets weiter reduzieren,
indem die spawnbare FAHRZEUG- und FUSSGÄNGER-Bibliothek auf ein konfigurierbares
Minimal-Set reduziert wird. NUR die Factory-Arrays werden getrimmt — KEINE
Quell-Assets werden gelöscht (voll reversibel).

WICHTIG — Verständnis (sonst Fehlannahme):
- Fahrzeuge/Fußgänger sind NICHT town-spezifisch. Sie sind eine GLOBALE, spawnbare
  Bibliothek, unabhängig von der geladenen Map (Town01/Town04/…) verfügbar.
- Registriert über zwei Factory-Blueprints:
    VehicleFactory: Content/Carla/Blueprints/Vehicles/VehicleFactory
                    (Array "Vehicles", Typ FVehicleParameters)
    WalkerFactory:  Content/Carla/Blueprints/Walkers/WalkerFactory
                    (Array, Typ FPedestrianParameters)
- Beide werden als Teil des "Carla"-Pakets gecookt. Der Cooker folgt den HARTEN
  Referenzen Factory -> Blueprint -> Mesh -> Material. Entfernt man einen Eintrag aus
  dem Factory-Array, fällt die Referenz weg -> Blueprint+Mesh+Texturen werden NICHT
  mehr gecookt -> kleineres Paket.
- "Nur für Town01/Town04 nötig" gibt es nicht — es geht darum, WELCHE Modelle du
  beim Simulieren verfügbar haben willst.

ZU BEHALTENDES MINIMAL-SET (anpassen nach Bedarf):
  Fahrzeuge (vehicle.*):
    vehicle.tesla.model3              # Standard-Ego in den meisten Beispielen
    vehicle.audi.a2                   # kleiner PKW
    vehicle.lincoln.mkz_2020          # mittlerer PKW (Szenarien)
    vehicle.dodge.charger_police      # Einsatzfahrzeug
    vehicle.carlamotors.firetruck     # 1 großes Fahrzeug (optional)
    vehicle.harley-davidson.low_rider # 1 Motorrad (optional)
    vehicle.diamondback.century       # 1 Fahrrad (optional)
  Fußgänger (walker.*):
    walker.pedestrian.0001
    walker.pedestrian.0002
    walker.pedestrian.0003
    walker.pedestrian.0004
  (Alle übrigen vehicle.*/walker.* aus den Factory-Arrays entfernen.)

NIEMALS entfernen (Basis-/Shared-Assets — Entfernen bricht den Build):
  Blueprints/Vehicles/: BaseVehiclePawn, BaseVehiclePawnNW, CommonTireConfig,
    CollisionWheel, BP_ParkCars, CustomNavegation
  Blueprints/Walkers/: alle Walker-Basisklassen (alles, was KEIN konkretes
    BP_Walker_XXXX-Modell ist)
  Die Factory-Blueprints selbst (VehicleFactory, WalkerFactory).

VORGEHEN (Factory-Arrays trimmen):
1. Exakte vorhandene IDs ermitteln (Server starten, dann Python):
     bp = client.get_blueprint_library()
     print(sorted(b.id for b in bp.filter('vehicle.*')))
     print(sorted(b.id for b in bp.filter('walker.pedestrian.*')))
   Zu LÖSCHENDE IDs = (alle) minus (Keep-Set).
2. Factory-Arrays bearbeiten. Die .uasset sind BINÄR — NICHT im Texteditor editieren.
   Zwei Wege:
   a) UE4-Editor: VehicleFactory bzw. WalkerFactory öffnen -> Array "Vehicles" bzw.
      Pedestrian-Array -> unerwünschte Einträge entfernen -> speichern.
   b) Skriptbasiert im Editor (Python-in-UE4), analog zu
      Plugins/CarlaTools/Content/Python/add_vehicle_to_vehicle_factory.py
      (umgekehrte Logik: Einträge entfernen statt hinzufügen) — für reproduzierbare
      Reduktion.
3. KEINE Quell-Asset-Ordner löschen (Static/Car/<Modell>, Static/Pedestrian/<Modell>
   bleiben -> Wiederherstellung allein über die Factory-Einträge möglich).
4. Neu bauen: make package (ohne --packages=).

ABHÄNGIGKEITEN PRÜFEN (sonst Laufzeitfehler):
- Skripte mit festen Blueprint-IDs müssen IDs aus dem Keep-Set verwenden.
  Filter wie 'vehicle.*' / generate_traffic.py funktionieren weiter (nutzen, was da
  ist). Demos mit hartem z. B. 'vehicle.lincoln.mkz...' ggf. anpassen.
- Das in deinen Skripten verwendete Ego-Fahrzeug muss im Keep-Set bleiben.

VERIFIKATION (nach make package):
- Paketgröße mit du -sh vor/nach vergleichen.
- Server starten; get_blueprint_library().filter('vehicle.*') und
  '...walker.pedestrian.*' zeigen NUR das Keep-Set.
- Je 1 Fahrzeug + 1 Fußgänger aus dem Keep-Set spawnen -> ok.
- Cook-Log auf "missing reference"-Warnungen prüfen.

REVERSIBEL: Entfernte Einträge wieder ins Factory-Array aufnehmen (Referenzen aus der
Git-Historie bzw. dem unveränderten Quellordner) und neu bauen.
```

---

## Praxis-Erkenntnis (am Repo verifiziert, 0.9.16 / ue4-min)

**Fahrzeuge und Fußgänger verhalten sich UNTERSCHIEDLICH:**

- **VehicleFactory** hat eine editierbare CDO-Member-Variable `Vehicles`
  (Array von `FVehicleParameters`). Diese lässt sich **headless** über ein
  UE4-Editor-Python-Skript trimmen — Muster:
  ```python
  import unreal
  pkg = '/Game/Carla/Blueprints/Vehicles/VehicleFactory'
  cdo = unreal.get_default_object(unreal.load_object(None, pkg + '.VehicleFactory_C'))
  KEEP = {"vehicle.tesla.model3","vehicle.audi.a2", ...}
  def vid(v): return "vehicle.%s.%s" % (str(v.get_editor_property("make")).lower(),
                                        str(v.get_editor_property("model")).lower())
  cdo.set_editor_property("Vehicles", [v for v in cdo.get_editor_property("Vehicles") if vid(v) in KEEP])
  unreal.EditorAssetLibrary.save_asset(pkg, False)
  ```
  Aufruf: `UE4Editor CarlaUE4.uproject -run=pythonscript -script="trim.py" -unattended -nosplash -nullrhi -NoShaderCompile`

- **WalkerFactory hat KEINE Member-Array-Variable.** Die Fußgänger sind in der
  Blueprint-Funktion `GenerateDefinitions` über einen inline `MakeArray`-Knoten
  **fest im Graph verdrahtet** (`get_editor_property` findet nur die leere
  C++-Output-Property `Definitions`). Walker lassen sich daher **NICHT headless**
  trimmen — nur **manuell im UE4-Editor-GUI**: WalkerFactory öffnen →
  Funktion `GenerateDefinitions` → unerwünschte Pins/Einträge aus dem
  `MakeArray`-Knoten entfernen → kompilieren/speichern.

- Die Factory-`.uasset` sind **nicht git-getrackt** (CARLA-Content wird separat
  verwaltet) → vor jeder Änderung **manuell sichern** (`cp`), da `git checkout`
  nicht zurückrollt.

---

## Referenz: Mechanismus (für Kontext)
- VehicleFactory: `Content/Carla/Blueprints/Vehicles/VehicleFactory.uasset`
  (Array `Vehicles`, Struct `FVehicleParameters` in
  `Plugins/Carla/Source/Carla/Actor/VehicleParameters.h`).
- WalkerFactory: `Content/Carla/Blueprints/Walkers/WalkerFactory.uasset`
  (Struct `FPedestrianParameters` in
  `Plugins/Carla/Source/Carla/Actor/PedestrianParameters.h`).
- Cook-Einbindung der Factories:
  `Plugins/Carla/Source/Carla/Commandlet/GenerateTaggedMaterialsRegistryCommandlet.cpp:117-120`.
- Definitionserzeugung: `MakeVehicleDefinition` / `MakePedestrianDefinitions` in
  `Plugins/Carla/Source/Carla/Actor/ActorBlueprintFunctionLibrary.cpp`.
- Editor-Skript-Vorlage: `Plugins/CarlaTools/Content/Python/add_vehicle_to_vehicle_factory.py`.

Siehe auch [reduce-package-size.prompt.md](reduce-package-size.prompt.md) (Map-Reduktion)
und [reduce-package-size.report.md](reduce-package-size.report.md).
