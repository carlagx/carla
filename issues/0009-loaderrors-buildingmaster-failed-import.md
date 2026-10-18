---
id: 0009
title: LoadErrors "Failed import" for BuildingMaster / BuildingSpawnableItems blueprint properties
status: open
phase: run
signature: 'LoadErrors: Error: .*Failed import for .*BuildingSpawnableItems'
sources: [Unreal/CarlaUE4/Saved/Logs/CarlaUE4*.log]
first_seen: 2026-10-14
fixed_in: -
---
## Symptom

Three lines per editor start, 21 in total so far:

```
LoadErrors: Error: /Game/Carla/Blueprints/LevelDesign/BuildingMaster : Failed import for BoolProperty   .../BuildingSpawnableItems:BlockSpawn_12_... Referenced by export Function BuildingMaster_C:PlaceItems
LoadErrors: Error: /Game/Carla/Blueprints/LevelDesign/BuildingMaster : Failed import for ObjectProperty .../BuildingSpawnableItems:Item_16_...       Referenced by export Function BuildingMaster_C:PlaceItems
LoadErrors: Error: /Game/Carla/Blueprints/LevelDesign/BuildingMaster : Failed import for StructProperty .../BuildingSpawnableItems:Transform_5_...  Referenced by export Function BuildingMaster_C:PlaceItems
```

## Cause

The `BuildingMaster` blueprint was saved against an older version of the
`BuildingSpawnableItems` struct whose member GUIDs no longer match. UE logs
this as an error but keeps loading. Only affects the LevelDesign building
spawner, which the test checks never use.

## Solution (verified <date>, commit <hash>)

none yet. Re-saving `BuildingMaster` in the editor would likely regenerate
the imports; untested, and it would modify a Content asset.

## How it was verified

n/a

## Did not work / untested

- Re-save in editor: untested.
