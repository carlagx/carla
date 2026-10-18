---
id: 0003
title: Traffic Manager server fails to bind its RPC port and never falls back to a free port
status: verified
phase: run
signature: 'TrafficManager.*(bind|port)|Failed to bind|[Aa]ddress already in use|RPC server.*bind'
sources: [Python client stderr, test-logs/*/generate_traffic_py*.log]
first_seen: 2026-06-25
fixed_in: 9abec9f85
---
## Symptom

Starting a Traffic Manager (e.g. `generate_traffic.py`) throws a bind error
when port 8000 is already taken, for instance by a stale ScenarioRunner
process. The retry loop logged "Update port number and try again" but kept
using the same port.

## Cause

In `LibCarla/source/carla/trafficmanager/TrafficManagerServer.h` the catch
block of the retry loop only slept 500 ms; it never incremented `RPCPort`, so
every one of the `MIN_TRY_COUNT` attempts hit the same occupied port.

## Solution (verified 2026-06-25, commit 9abec9f85)

On a bind failure the port is advanced (`RPCPort++`) before the next attempt.
On success `_RPCPort` is set to the port that was really bound, so `port()`
reports the actual port to `AddTrafficManagerRunning` / `DestroyTrafficManager`.

## How it was verified

With port 8000 occupied the TM started on 8001 and the client used that port.
`generate_traffic.py` runs green in `test-logs/` since.

## Did not work / untested

- Killing stale processes by hand works but is not a fix.
