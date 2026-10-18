---
id: 0004
title: Ensure "VendorId != EGpuVendorId::Unknown" in VulkanDevice.cpp at startup
status: noise
phase: run
signature: 'VendorId != EGpuVendorId::Unknown'
sources: [Unreal/CarlaUE4/Saved/Logs/CarlaUE4*.log, Unreal/CarlaUE4/Saved/Crashes/ensureinfo-*]
first_seen: 2026-10-14
fixed_in: -
---
## Symptom

Every editor/server start logs an ensure, and an `ensureinfo-CarlaUE4-pid-*`
folder appears under `Saved/Crashes`:

```
LogOutputDevice: Error: Ensure condition failed: VendorId != EGpuVendorId::Unknown
[File:.../VulkanRHI/Private/VulkanDevice.cpp] [Line: 182]
```

followed by roughly 15 `[Callstack]` lines.

## Cause

UE 4.26's Vulkan RHI does not recognise the vendor id reported by the current
NVIDIA driver / Vulkan 1.4 loader and falls into the `Unknown` branch. The
ensure is non-fatal; the device is still created and rendering works (all
`test-carla.sh` runs with camera checks passed).

## Solution

None needed. The scanner counts the hits and hides them. Watch for a change
in frequency only: it fires once per start, so the number of ensures should
equal the number of server starts.

## How it was verified

n/a (noise)

## Did not work / untested

- Patching `VulkanDevice.cpp` to map the id: not tried, no functional impact.
