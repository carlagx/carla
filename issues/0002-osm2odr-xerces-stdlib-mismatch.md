---
id: 0002
title: CarlaUE4 plugin fails to link osm2odr/xerces-c (C++ stdlib mismatch)
status: verified
phase: build
signature: 'osm2odr|OSM2ODR|libxerces-c\.a.*(undefined|std::__1|std::__cxx11)|std::__cxx11::basic_string.*xerces'
sources: [UE4 module build (UnrealBuildTool), build-check-logs/*/server-ue4.log]
first_seen: 2026-10-16
fixed_in: e4906b96e
---
## Symptom

Linking the `Carla` UE4 module fails with undefined references between
`libxerces-c.a` / `libosm2odr.a` and the UE libc++ toolchain, typically
`std::__cxx11::basic_string` vs `std::__1::basic_string` symbol mismatches.

## Cause

`libxerces-c.a` and `libosm2odr.a` in `LibCarlaInstallPath/lib` were built
against a different C++ standard library than the one Unreal links with
(libstdc++ vs. bundled libc++).

## Solution (verified 2026-10-16, commit e4906b96e)

This is a workaround that disables the feature, not a root-cause fix: the
OSM-to-OpenDRIVE conversion inside the editor is not needed for this project.

- `Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Carla.Build.cs`: the
  `xerces-c`, `proj` and `osm2odr` libraries are no longer added to
  `PublicAdditionalLibraries` (Linux and Windows blocks).
- `Unreal/CarlaUE4/Plugins/CarlaTools/Source/CarlaTools/Private/Online/CustomFileDownloader.cpp`:
  `ConvertOSMInOpenDrive` logs an error instead of calling `osm2odr`.

## How it was verified

The CarlaUE4 editor target built and the server started afterwards (commit
is the base of the ue4-cpp-api branch; see `check-buildable.sh` runs in
`build-check-logs/`).

## Did not work / untested

- Rebuilding xerces-c/osm2odr against libc++ so they can stay linked: not
  tried. Would be the real fix if OSM import is ever needed.
