# Prompt: Apply the CARLA localhost-bind security fix to a fresh clone

Copy everything below the line into a new Claude Code session that is opened in
the root of a freshly cloned CARLA repository (UE4 branch, e.g. `ue4-dev`).

---

You are working in a freshly cloned CARLA simulator repository (Unreal Engine 4
branch). Apply the security fix described below, verify it, and finish by
writing a Markdown document that explains the fix and how to use it. All files,
code, comments and identifiers must be in English.

## Problem

The CARLA server exposes its network listeners on **all interfaces
(`0.0.0.0`)** by default:

- the RPC server (default port `2000`),
- the streaming server (sensor data, default `2001` = RPC port + 1),
- the multi-GPU router / secondary server (default `2002` = RPC port + 2),
- the Traffic Manager RPC server (default port `8000`).

The CARLA RPC/streaming protocol has **no authentication and no encryption**.
Anyone who can reach these ports on the network gets full control of the
simulation (spawn/destroy actors, load maps, run the recorder, read every
sensor stream). On a workstation or cloud VM with a public or shared network
this is a remote-control vulnerability. The bind address is hard-coded, so
users cannot restrict it.

## Goal

1. All server listeners bind to **`127.0.0.1` (localhost) by default**.
2. The bind address is **configurable**, so remote access stays possible as an
   explicit opt-in:
   - command line: `--listen-host=<ip>` (e.g. `--listen-host=0.0.0.0`),
   - INI file: `ListenHost=<ip>` under `[CARLA/Server]` in `CarlaSettings.ini`,
   - `Util/BuildTools/BuildCarlaUE4.sh --launch --listen-host=<ip>` forwards the
     flag to the editor.
   Command line wins over the INI file; an empty INI value keeps the default.
3. The Traffic Manager RPC server always binds to `127.0.0.1` (the address it
   advertises to clients via `GetLocalIP()` / `AddTrafficManagerRunning()` is
   already loopback, so listening on all interfaces only adds exposure).
4. Existing public C++ APIs keep working (add overloads, do not break callers).
5. Documentation and changelog describe the new default and how to restore the
   old behavior.

## Required changes

Inspect each file first; adapt to the actual code in this clone if it differs
slightly from the description.

1. `Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.h`
   Add a public member, with a doc comment, before `RPCPort`:
   `std::string ListenHost = "127.0.0.1";`
2. `Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.cpp`
   - In `LoadSettingsFromConfig`, inside the `[CARLA/Server]` networking block,
     read `ListenHost` via `ConfigFile.GetString` and assign it only if not empty.
   - In `UCarlaSettings::LoadSettings`, parse `-listen-host=` from
     `FCommandLine::Get()` with `FParse::Value` (next to the existing
     `-carla-primary-port=` parsing) and assign it.
   - In `LogSettings`, log `Listen Host = %s` before `RPC Port`.
3. `Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.h/.cpp`
   - Change `FCarlaServer::Start` to
     `Start(const std::string &Host, uint16_t RPCPort, uint16_t StreamingPort, uint16_t SecondaryPort)`.
   - Pass `Host` into `FPimpl`, and from there to the RPC server
     (`Server(Host, RPCPort)`), the streaming server
     (`StreamingServer(Host, StreamingPort)`) and the multi-GPU router
     (`std::make_shared<carla::multigpu::Router>(Host, SecondaryPort)`).
   - Include the host in the "Initialized CarlaServer" log line.
   - Verify that `carla::rpc::Server` and `carla::streaming::Server` already
     accept a `(host, port)` constructor; if not, add the overloads.
4. `Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Game/CarlaEngine.cpp`
   Call `Server.Start(Settings.ListenHost, Settings.RPCPort, StreamingPort, SecondaryPort)`.
5. `LibCarla/source/carla/multigpu/router.h/.cpp`
   Add `Router(const std::string &address, uint16_t port);` (include
   `<string>`), build the endpoint with `boost::asio::ip::make_address(address)`,
   and make the existing `Router(uint16_t port)` delegate to it with
   `"0.0.0.0"` so other callers keep their behavior.
6. `LibCarla/source/carla/trafficmanager/TrafficManagerServer.h`
   Replace `new ::rpc::server(RPCPort)` with
   `new ::rpc::server("127.0.0.1", RPCPort)` and add a comment explaining why.
7. `Util/BuildTools/BuildCarlaUE4.sh`
   Add a `--listen-host=IP` option: usage string, `getopt` long option
   `listen-host:`, a `LISTEN_HOST` variable, and append
   `--listen-host=${LISTEN_HOST}` to `EDITOR_FLAGS` when set.
8. `CHANGELOG.md` — add an entry at the top of "Latest Changes".
9. `Docs/foundations.md` — add a `!!! Note` after the `carla.Client('localhost', 2000)`
   explanation describing the default, the security reason, how to opt in, and
   recommending an SSH tunnel or VPN for remote access.
10. `Util/Docker/README.md` — create it (or extend it) with a "Networking"
    section: inside a container the default loopback bind makes the server
    unreachable through `-p`, so the container must be started with
    `--listen-host=0.0.0.0` and the ports published **only on the host's
    loopback** (`-p 127.0.0.1:2000-2002:2000-2002`), or with `--net=host`.

If `tools/apply-localhost-bind-fix.sh` exists in this clone, you may run it
instead of editing by hand, but still review the result against the list above
and do steps 10 and the final document yourself.

## Verification

- `git diff` touches only the files above; no unrelated changes.
- `grep -rn '"0.0.0.0"'` in `Unreal/CarlaUE4/Plugins/Carla/Source` and
  `LibCarla/source/carla` shows no remaining server bind to all interfaces
  (the delegating `Router(uint16_t)` constructor is the only expected hit).
- If a build environment is available, build LibCarla and the plugin
  (`make LibCarla`, `make launch` or `make package` on Linux) and check that the
  log prints `Listen Host = 127.0.0.1` and `Host(127.0.0.1)`. Then check with
  `ss -ltnp | grep -E ':(2000|2001|2002|8000)'` that the ports listen on
  `127.0.0.1` only. If you cannot build here, say so explicitly in your final
  answer instead of claiming the build passed.
- Commit the change on a new branch (e.g. `security/localhost-bind`) with
  Conventional Commit messages, one commit for the server/settings change and
  one for the Traffic Manager change, plus one for docs.

## Final deliverable: `SECURITY-LOCALHOST-BIND.md`

Create `SECURITY-LOCALHOST-BIND.md` in the repository root. Audience: CARLA
users and operators who run the simulator locally, on a server, or in Docker.
It must contain:

1. **Summary** — one paragraph: what changed and why.
2. **Problem** — the exposed ports, no authentication/encryption, the
   resulting risk.
3. **What the fix does** — new default, affected listeners, Traffic Manager
   behavior, list of changed files.
4. **Usage**
   - Default local use (no flags needed, `carla.Client('localhost', 2000)`).
   - Allowing remote clients: `./CarlaUE4.sh --listen-host=0.0.0.0`, binding to
     one specific interface (`--listen-host=192.168.1.10`), INI example:
     ```ini
     [CARLA/Server]
     ListenHost=127.0.0.1
     ```
   - Editor launch: `make launch-only ARGS="--listen-host=0.0.0.0"` or
     `Util/BuildTools/BuildCarlaUE4.sh --launch --listen-host=0.0.0.0`
     (not `make launch ARGS=...`, because that target also passes `ARGS` to
     `BuildUE4Plugins.sh`, which does not know the flag).
   - Recommended secure remote access via SSH tunnel:
     `ssh -N -L 2000:127.0.0.1:2000 -L 2001:127.0.0.1:2001 -L 2002:127.0.0.1:2002 user@carla-host`.
   - How to verify the bind address (`ss -ltnp` / log line).
5. **Running CARLA securely in Docker** — explain that the official
   `carlasim/carla` images do **not** contain this fix, so the image must be
   built from the patched source (package with `make package`, then build
   `Util/Docker/Release.Dockerfile`, tagged e.g. `carla-secure:latest`).
   Then provide this ready-to-copy command in its own code block:

   ```bash
   docker run --rm -it \
     --name carla \
     --gpus all \
     --user carla \
     --cap-drop ALL \
     --security-opt no-new-privileges \
     -p 127.0.0.1:2000-2002:2000-2002 \
     carla-secure:latest \
     /bin/bash ./CarlaUE4.sh -RenderOffScreen -nosound --listen-host=0.0.0.0
   ```

   Explain each security-relevant flag: `--listen-host=0.0.0.0` is needed so
   Docker's port forwarding can reach the server inside the container's own
   network namespace; `-p 127.0.0.1:...` publishes the ports **only on the
   host's loopback**, so the server is still not reachable from the network;
   `--cap-drop ALL` and `--security-opt no-new-privileges` reduce the impact of
   a compromised process; `--user carla` avoids running as root. Also show the
   `--net=host` alternative (default bind, no `-p`, client on the same host)
   and warn that `-p 2000-2002:2000-2002` without `127.0.0.1:` exposes CARLA to
   the whole network again. Mention that the Traffic Manager (port 8000) must
   run in the same network namespace as its client.
6. **Restoring the old behavior** — `--listen-host=0.0.0.0`, with a warning to
   only do this on a trusted network or behind a firewall.
7. **Troubleshooting** — "connection refused from another machine/container",
   "Docker port published but client times out", Traffic Manager not reachable.

Keep the document concise, use code blocks for every command, and make every
command copy-paste ready.

When finished, report: the branch name, the commits, the verification you ran
(and what you could not run), and the path to `SECURITY-LOCALHOST-BIND.md`.
