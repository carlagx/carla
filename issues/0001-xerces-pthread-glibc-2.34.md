---
id: 0001
title: Xerces-C 3.2.3 fails to link its test/sample executables on glibc >= 2.34 (Ubuntu 22.04+)
status: verified
phase: build
signature: 'undefined reference to .?pthread_(create|join|mutex|key|cond)|xerces.*(pthread|libpthread)'
sources: [make setup terminal output, Build/xerces-c-3.2.3-source/build/, build-check-logs/*/server-libcarla.log]
first_seen: 2026-06-22
fixed_in: 65171332f
---
## Symptom

During `make setup` (Util/BuildTools/Setup.sh) the Xerces-C build aborts while
linking its test, sample and doc executables:

```
undefined reference to `pthread_create'
ninja: build stopped: subcommand failed.
```

`libxerces-c.a`, the only artifact CARLA needs, had already built fine. The
libc++ server variant of the Xerces build is the one that actually hits it.

## Cause

On glibc >= 2.34 `libpthread` is a stub; pthread symbols live in `libc`. The
implicit pthread linkage that Xerces' CMake files relied on no longer works, so
`-pthread` has to be passed explicitly.

## Solution (verified 2026-06-22, commit 65171332f)

Add `-pthread` to `CMAKE_CXX_FLAGS` of both Xerces-C cmake invocations in
`Util/BuildTools/Setup.sh` (client/libstdc++ and server/UE-libc++):

```
-DCMAKE_CXX_FLAGS="-std=c++14 -fPIC -w -pthread"
-DCMAKE_CXX_FLAGS="-std=c++14 -stdlib=libc++ -fPIC -w -pthread ${UNREAL_HOSTED_CFLAGS} ..."
```

Upstream Xerces sources stay untouched.

## How it was verified

On glibc 2.35: `make PythonAPI` (client Xerces) and `make launch` (server
Xerces) both compiled, linked and ran. See also
`tools/CARLA_COMPLETE_BUILD_GUIDE_UBUNTU22.md` from the same commit.

## Did not work / untested

- Patching the Xerces sources: not tried, the flag is enough.
