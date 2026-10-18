---
id: 0005
title: Editor SIGSEGV in FDistanceFieldVolumeTexture::IsValidDistanceFieldVolume while shaders compile
status: open
phase: run
signature: 'FDistanceFieldVolumeTexture::IsValidDistanceFieldVolume'
sources: [Unreal/CarlaUE4/Saved/Logs/CarlaUE4-backup-2026.10.14-23.55.05.log, Unreal/CarlaUE4/Saved/Crashes/crashinfo-CarlaUE4-pid-387719-*]
first_seen: 2026-10-14
fixed_in: -
---
## Symptom

```
LogCore: === Critical error: ===
Unhandled Exception: SIGSEGV: invalid attempt to read memory at address 0x0000000000000018
libUE4Editor-Engine.so!FDistanceFieldVolumeTexture::IsValidDistanceFieldVolume() const [DistanceFieldAtlas.cpp:868]
libUE4Editor-Engine.so!FPrimitiveSceneShaderData::FPrimitiveSceneShaderData(FPrimitiveSceneProxy const*)
libUE4Editor-Renderer.so!UpdateGPUSceneInternal<FRWBufferStructured>(...)
libUE4Editor-Renderer.so!FDeferredShadingSceneRenderer::Render_CARLA(...)
```

Happened once on 2026-10-14 23:55 during the first editor start while the
shader compiler still had ~17800 shaders queued. Not reproduced since.

## Cause

Unknown. Null `DistanceFieldData` on a primitive whose mesh distance field
had not been generated yet (first cook of a fresh Content download) is the
likely candidate. Subsequent starts with a warm DerivedDataCache did not
crash.

## Solution (verified <date>, commit <hash>)

none yet

## How it was verified

n/a

## Did not work / untested

- Hypothesis: let the first editor start finish shader/DDC generation before
  loading a map. Not tested deliberately.
