---
id: 0006
title: test-carla.sh client check times out waiting for the simulator (120000 ms)
status: open
phase: test
signature: 'time-out of [0-9]+ms while waiting for the simulator'
sources: [test-logs/20261016-151839/python_connect___version_match.log]
first_seen: 2026-10-16
fixed_in: -
---
## Symptom

```
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
RuntimeError: time-out of 120000ms while waiting for the simulator, make sure the simulator is ready and connected to localhost:2000
```

Seen once in the Docker-mode run `test-logs/20261016-151839`. The port was
open (Docker publishes it before the server is ready) but the RPC server did
not answer within the client timeout. The next run (`20261016-152140`) was
green.

## Cause

Not pinned down. Most likely the server was still loading the map when the
check started (the `rpc_ready` probe in `test-carla.sh` passed, so either the
probe is too lenient or the server stalled right after).

## Solution (verified <date>, commit <hash>)

none yet

## How it was verified

n/a

## Did not work / untested

- Re-running the test passed; that is not a fix.
