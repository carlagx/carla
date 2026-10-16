# Tipps: Rendering und Map-Laden beschleunigen (CARLA / UE4)

Hinweis: Die Werte sind für UE4.26 (CARLA) gedacht und nicht alle gemessen. Ändere immer nur ein bis zwei Dinge auf einmal und miss vorher und nachher. Einige Optionen verändern das Rendering und damit die Kamera-Sensordaten.

## 1. Maps im Editor öffnen

### Distance Fields abschalten
- GUI: Edit → Project Settings → Engine → Rendering → Software Ray Tracing → **Generate Mesh Distance Fields** deaktivieren, dann Editor neu starten.
- `Config/DefaultEngine.ini`, Sektion `[/Script/Engine.RendererSettings]`:
  ```ini
  r.GenerateMeshDistanceFields=False
  ```
- Verlust: Distance-Field-Shadows, DF-Ambient-Occlusion und Features auf Basis von Software Ray Tracing.
- `r.DistanceFieldBuild.Compress=False` beibehalten (Kompression kann Hitches beim Streaming verursachen).

### Editor-Einstellungen
- Realtime im Viewport ausschalten (senkt die GPU-Last).
- Editor Preferences → Performance: `bMonitorEditorPerformance` ausschalten, damit der Editor die Scalability nicht selbst ändert.
- Scalability im Editor auf Low oder Medium stellen.
- Auto-Load der letzten Map ausschalten, Startmap klein halten (`EditorStartupMap`).

### Derived Data Cache (DDC)
- Den DDC auf eine schnelle NVMe-SSD legen (Umgebungsvariable `UE-LocalDataCachePath`).
- Der erste Load einer Map ist langsam, weil Shader und Mesh-Daten gebaut werden. Danach ist er deutlich schneller.
- Mehr Shader-Compile-Worker nutzen, falls CPU-Kerne frei sind.

### Weitere Rendering-Optionen (Kandidaten, vorher testen)
| Option | Wirkung |
|---|---|
| `r.RayTracing=False` | Weniger Shader-Compile |
| `r.AllowStaticLighting=False` | Weniger Lightmap-Daten (nur ohne baked Lighting) |
| `r.DefaultFeature.MotionBlur=False` | Weniger Post-Process |
| `r.DefaultFeature.Bloom=False` | Weniger Post-Process |
| `r.DefaultFeature.AmbientOcclusion=False` | Weniger Post-Process |
| `r.ReflectionEnvironment=0` (nur Editor) | Weniger Capture-Arbeit |
| `r.Streaming.PoolSize` anpassen | Zu klein: Streaming-Probleme, zu groß: VRAM |

## 2. Maps zur Laufzeit laden (`load_world`, `-map`)

### Async Loading in `DefaultEngine.ini`
```ini
[/Script/Engine.StreamingSettings]
s.AsyncLoadingThreadEnabled=True
s.AsyncLoadingTimeLimit=20.0
s.PriorityAsyncLoadingExtraTime=20.0
s.LevelStreamingActorsUpdateTimeLimit=10.0
s.UseBackgroundLevelStreaming=True
s.EventDrivenLoaderEnabled=True
s.AsyncLoadingUseFullTimeLimit=True
```
`s.AsyncLoadingThreadEnabled` ist vermutlich der wichtigste Wert.

### Garbage Collection
```ini
[/Script/Engine.GarbageCollectionSettings]
gc.TimeBetweenPurgingPendingKillObjects=120
```

### CARLA-spezifisch
- `_Opt`-Maps nutzen (z. B. `Town10HD_Opt`) und Layer gezielt laden:
  ```python
  client.load_world('Town10HD_Opt', map_layers=carla.MapLayer.NONE)
  client.load_world_layer(...)  # Layer bei Bedarf nachladen
  ```
- `reset_settings=False` bei `load_world` spart etwas Zeit.
- Server nicht neu starten: Der Kaltstart (GPU-Init, Shader) ist langsamer als ein Map-Wechsel.
- Startflag `-quality-level=Low` verkürzt das Laden spürbar.

## 3. Packaged Build

- Pak-Dateien auf SSD/NVMe legen.
- Pak-Kompression mit Oodle statt Zlib:
  ```ini
  [/Script/UnrealEd.ProjectPackagingSettings]
  bCompressed=True
  PackageCompressionFormat=Oodle
  ```
- Shader: `r.ShaderPipelineCache.Enabled=1` mit PSO-Cache vermeidet Hitches nach dem Load. `bShareMaterialShaderCode=True` plus Shader-Library kann den Shader-Load beschleunigen (aktuell `False` in `DefaultGame.ini`).
- Texture Streaming: `r.Streaming.UseFixedPoolSize=1` verhindert Neuberechnungen des Pools.

## 4. Messen

- `stat startfile` / `stat stopfile` für Frame-Profile.
- `-LogCmds="LogStreaming Verbose"` für Streaming-Zeiten.
- Zeit von `load_world` bis zum ersten Tick im Python-Client stoppen (vorher/nachher).

## 5. Empfohlene Reihenfolge

1. Async-Loading-Werte setzen.
2. DDC auf NVMe.
3. Distance Fields aus (bereits erledigt).
4. Oodle und Paks auf NVMe im Packaged Build.
5. Weitere Rendering-Optionen einzeln testen.

## Quellen

- UEditorPerformanceSettings (UE 4.27): https://docs.unrealengine.com/4.27/API/Editor/UnrealEd/Editor/UEditorPerformanceSettings/index.html
- Mesh Distance Fields Properties: https://dev.epicgames.com/documentation/unreal-engine/mesh-distance-fields-properties-in-unreal-engine
- Epic Answers, Realtime-Viewport und GPU-Last: https://answers.unrealengine.com/questions/483551/view.html
