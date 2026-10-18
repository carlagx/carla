---
id: 0007
title: LogLinker warnings for missing MDL OmniSurface materials and GEN3 walker animations
status: noise
phase: run
signature: "Failed to load '/Game/(MDL/|Carla/Static/Pedestrian/Animations/GEN3/)"
sources: [Unreal/CarlaUE4/Saved/Logs/CarlaUE4*.log]
first_seen: 2026-10-14
fixed_in: -
---
## Symptom

Repeated on every start, hundreds of lines:

```
LogLinker: Warning: [AssetLog] .../BP_Walker_AB001_G3.uasset: Failed to load '/Game/Carla/Static/Pedestrian/Animations/GEN3/Nos_/AS_walkingG3': Can't find file.
LogLinker: Warning: Failed to load '/Game/MDL/Base/OmniSurface_...': Can't find file.
```

## Cause

The downloaded Content package does not ship the MDL base materials
(Omniverse) or the GEN3 pedestrian animation set these assets reference.
The referencing assets load with the missing parts defaulted; no functional
impact on the checks in `test-carla.sh`.

## Solution

None needed for this project. Hidden by the scanner.

## How it was verified

n/a (noise)

## Did not work / untested

- Importing the Omniverse MDL pack or the GEN3 animations would silence it;
  not needed.
