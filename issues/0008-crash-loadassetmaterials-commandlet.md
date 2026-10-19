---
id: 0008
title: Editor crashes (SIGSEGV) in ULoadAssetMaterialsCommandlet constructor at startup
status: open
phase: run
signature: 'ULoadAssetMaterialsCommandlet::ULoadAssetMaterialsCommandlet'
sources: [Unreal/CarlaUE4/Saved/Crashes/crashinfo-CarlaUE4-pid-{339341,342397,345854,349045}-*]
first_seen: 2026-10-15
fixed_in: -
---
## Symptom

Four crashes between 2026-10-15 00:37 and 01:55, all with the same callstack:

```
Caught signal 11 Segmentation fault
libUE4Editor-Carla.so!ULoadAssetMaterialsCommandlet::ULoadAssetMaterialsCommandlet() [LoadAssetMaterialsCommandlet.cpp:38]
libUE4Editor-CoreUObject.so!UClass::CreateDefaultObject()
libUE4Editor-CoreUObject.so!ProcessNewlyLoadedUObjects(FName, bool)
UE4Editor!FEngineLoop::PreInitPostStartupScreen(char16_t const*)
```

The crash happens while the engine creates the class default object of the
commandlet, i.e. before any map is loaded.

## Cause

`Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Commandlet/LoadAssetMaterialsCommandlet.cpp:38`:

```cpp
static ConstructorHelpers::FObjectFinder<UBlueprint> RoadPainterBlueprint(TEXT(
  "Blueprint'/Game/Carla/Blueprints/LevelDesign/RoadPainterPreset.RoadPainterPreset'"));
RoadPainterSubclass = (UClass*)RoadPainterBlueprint.Object->GeneratedClass;
```

`RoadPainterBlueprint.Object` is dereferenced without a null check. If the
asset `/Game/Carla/Blueprints/LevelDesign/RoadPainterPreset` cannot be loaded
at that moment (Content not fully downloaded / not yet cooked), the
constructor segfaults. No crash since 01:55 on 2026-10-15, which matches the
Content download finishing around then.

## Solution (verified <date>, commit <hash>)

none yet. Candidate: guard the dereference
(`if (RoadPainterBlueprint.Succeeded())`) so a missing preset only logs an
error. Unverified.

## How it was verified

n/a

## Did not work / untested

- Guard with `Succeeded()`: untested.
