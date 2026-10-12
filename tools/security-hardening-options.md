# Closing the CARLA "listen on all interfaces" exposure — options and decision guide

## The exposure in one paragraph

An unmodified CARLA server (UE4 branch, prebuilt releases included) opens four
TCP listeners on **all interfaces (`0.0.0.0`)**: RPC (`2000`), sensor
streaming (`2001`), multi-GPU secondary (`2002`) and the Traffic Manager RPC
(`8000`, opened by the first client that creates a TM). None of them has
authentication or encryption. Any host that can reach the ports can load maps,
spawn and drive actors, read every sensor and record the session. On a
laptop in a shared Wi-Fi, a lab machine or a cloud VM this is a remote-control
hole. The bind address is hard-coded; the stock build has no setting for it.

The goal of every option below is the same: **only clients you intend to allow
can reach those ports**, by default only the local machine.

---

## Option catalogue

Options are grouped by *where* the control sits: inside the CARLA source, in
the running process, on the host, or in the network around it.

### A. Change the server source (the "proper" fix)

Make the bind address a setting, default it to `127.0.0.1`, and bind the
Traffic Manager to loopback. This is what the `ue4-xil` branch of this repo
does (`aef7be4fb`, `8706769cf`): `ListenHost` in `CarlaSettings.h`, read from
`[CARLA/Server] ListenHost` and `--listen-host=<ip>`, threaded through
`FCarlaServer::Start` into the RPC, streaming and multi-GPU servers;
`TrafficManagerServer` binds to `127.0.0.1` unconditionally.

- Requires: UE4 toolchain, full rebuild (`make launch` / `make package`),
  hours on first build.
- Reversible: yes, via `--listen-host=0.0.0.0`; the *code* change itself is a
  commit you can revert, but you then rebuild again.
- Covers: all four ports, every launch path (editor, package, Docker).
- Works with prebuilt `carlasim/carla` images / release zips: **no** — you
  must build and ship your own package.
- Upstreamable, documented, visible in logs (`Listen Host = ...`).

### B. Source patch script on a fresh clone

`tools/apply-localhost-bind-fix.sh` applies the two commits from A to a fresh
`ue4-dev` clone with `git am`. Same result and same cost as A; it only
removes the manual editing. It is a *build-time* option, not a post-install
one. Keep it if you build from source regularly (CI, several machines).

### C. Runtime interposition without touching any CARLA file (`LD_PRELOAD`)

Linux only. A ~40-line shared library hooks `bind(2)`; whenever a process
binds an IPv4 TCP socket to `INADDR_ANY`, the library rewrites the address to
`127.0.0.1` (or any address from an environment variable) before calling the
real `bind`. Launch CARLA through a wrapper:

```bash
LD_PRELOAD=/opt/carla-hardening/bind_localhost.so ./CarlaUE4.sh -RenderOffScreen
```

- Requires: `gcc`, no CARLA rebuild, no edit to `CarlaUE4.sh` or the binary.
- Reversible: **instantly** — start without the env var and you have the stock
  behaviour. Nothing in the CARLA install directory changes.
- Covers: all four ports, including the Traffic Manager (its `rpc::server`
  also calls `bind`). Also any other listener UE4 might open.
- Works with prebuilt release packages: yes. In Docker: yes (mount the `.so`,
  set `LD_PRELOAD` in the `docker run` command).
- Caveats: hooks *every* IPv4 `INADDR_ANY` bind in the process, so if you
  ever rely on another feature that must be network-reachable it is hidden
  too (acceptable — nothing in CARLA legitimately needs that). Does not touch
  IPv6 `in6addr_any` unless you add it. Not applicable on Windows. Survives
  CARLA upgrades unchanged because it is independent of CARLA's code.
- Verification: `ss -ltnp | grep -E ':(2000|2001|2002|8000)'` must show
  `127.0.0.1:` only.

A sketch of the interposer is in Appendix 1. It is untested in this repo —
treat it as a starting point, not a drop-in.

### D. Kernel-level sandbox of the process (`systemd-run` / network namespace)

Linux only, no CARLA changes.

- **systemd IP filtering** (cgroup v2 + BPF, Ubuntu 20.04+):
  ```bash
  systemd-run --user --scope -p IPAddressDeny=any -p IPAddressAllow=localhost ./CarlaUE4.sh -RenderOffScreen
  ```
  The server still *binds* to `0.0.0.0`, but the kernel drops every packet
  that is not loopback. Clients on the same host connect normally.
- **Separate network namespace** (`ip netns` / `unshare -n`): CARLA sees only a
  loopback interface. The Python client must then run in the same namespace
  (`ip netns exec`), which is inconvenient outside Docker. Docker (option E)
  is the practical form of this.

Reversible instantly (run without the wrapper). Covers all four ports. Works
with prebuilt packages. Weak spot: `--user` scopes need a logged-in systemd
user session; headless/SSH setups may need the system instance (`sudo`), and
some cloud images ship cgroup v1 where `IPAddressDeny` is silently ignored —
**always verify with a connection attempt from another host**.

### E. Docker: let the container bind `0.0.0.0`, control exposure on the host

The unmodified server inside a container listens on the *container's*
interfaces. What reaches it is decided entirely by `docker run`:

- **Publish only on the host loopback** — the recommended form:
  ```bash
  docker run --rm -it --gpus all \
    -p 127.0.0.1:2000-2002:2000-2002 \
    carlasim/carla:0.9.15 /bin/bash ./CarlaUE4.sh -RenderOffScreen -nosound
  ```
  Clients on the host use `carla.Client('127.0.0.1', 2000)`. The network sees
  nothing.
- **Fixed container IP on a user-defined bridge** (`docker network create
  --subnet 172.30.0.0/24 carla-net`, then `--network carla-net --ip
  172.30.0.10`, no `-p`): reachable only from that bridge (other containers
  on `carla-net`, and the host). Good for multi-container setups where the
  client is also a container.
- **`--network none`** is not usable (no loopback bridge to the host either),
  and `--net=host` re-exposes everything — avoid unless combined with A/C/D.

- Requires: Docker + NVIDIA runtime; the official image, no rebuild.
- Reversible: yes; change the `-p` and the exposure changes. The image is
  untouched.
- Covers: ports 2000–2002 as published. **Traffic Manager (8000)**: the TM
  server is created by the *client* process, so it lives wherever the Python
  client runs — on the host if the client is on the host (then it is exposed
  on `0.0.0.0` of the host, unaffected by Docker!), inside the container if
  the client is containerised.
- Known trap: Docker inserts its own iptables chains and **bypasses `ufw`**;
  `-p 2000:2000` is open to the world even if `ufw` says "deny incoming".
  Always write `127.0.0.1:` in the `-p` mapping, or set `"ip": "127.0.0.1"`
  in `/etc/docker/daemon.json` as the default publish address.

### F. Host firewall (ufw / nftables / Windows Firewall)

Do not touch CARLA at all; block inbound to the four ports except from
loopback (and, if needed, from a specific client IP):

```bash
# Linux, ufw
sudo ufw deny in proto tcp to any port 2000:2002
sudo ufw deny in proto tcp to any port 8000
# or allow exactly one client:
sudo ufw allow in proto tcp from 192.168.1.50 to any port 2000:2002
```
```powershell
# Windows (admin PowerShell)
New-NetFirewallRule -DisplayName "CARLA loopback only" -Direction Inbound -Protocol TCP `
  -LocalPort 2000,2001,2002,8000 -RemoteAddress Any -Action Block
```
Loopback traffic never traverses the inbound firewall, so local clients work.

- Requires: admin rights, nothing else. Works on Windows — the only
  post-install option here that does.
- Reversible: delete the rules.
- Covers: all four ports, including a Traffic Manager started on the host.
- Weak spots: rules are per machine, easy to forget on a new box or after an
  OS reinstall; the Docker/ufw bypass above; the server still *listens*
  publicly, so a tool like `ss` still shows `0.0.0.0` and a misconfigured
  firewall silently reopens it. Good as a **second layer**, weak as the only
  one.

### G. Network perimeter: SSH tunnel, VPN, cloud security groups

These do not close the listener; they control who reaches the machine.
Cloud security groups / VPC rules are the firewall of option F moved into the
provider. An SSH tunnel is the recommended way to *use* a localhost-bound
server from another machine:

```bash
ssh -N -L 2000:127.0.0.1:2000 -L 2001:127.0.0.1:2001 -L 2002:127.0.0.1:2002 user@carla-host
```
Combine with A, C, D or E; never rely on them alone for a server that binds to
`0.0.0.0`.

### H. Not viable / not recommended

- **Hex-patching the binary**: the RPC and streaming servers build their
  endpoints from `INADDR_ANY` numerically, not from a `"0.0.0.0"` string, so
  there is no literal to replace. Fragile, breaks on every release.
- **Reverse proxy / `socat` in front of CARLA**: the server still listens
  publicly; a proxy adds nothing unless the server itself is hidden (then it
  is just a tunnel, see G).
- **Relying on `-carla-rpc-port` obscurity**: port scanning finds it in
  seconds.

---

## Comparison

| | A. Source fix | B. Patch script | C. LD_PRELOAD | D. systemd / netns | E. Docker `-p 127.0.0.1` | F. Firewall | G. Tunnel/VPN |
|---|---|---|---|---|---|---|---|
| Rebuild CARLA | yes | yes | no | no | no | no | no |
| Works with prebuilt release/image | no | no | yes | yes | yes | yes | yes |
| Touches CARLA install files | commit | commit | **none** | none | none | none | none |
| Restore stock behaviour | flag / rebuild | flag / rebuild | **drop env var** | drop wrapper | change `-p` | delete rules | — |
| Closes port 8000 (Traffic Manager) | yes | yes | yes | yes | only if client is in container | yes | n/a |
| Server actually binds to loopback | yes | yes | yes | no (filtered) | inside container only | no | no |
| Linux | yes | yes | yes | yes | yes | yes | yes |
| Windows | yes | yes | no | no | partly (Docker Desktop) | yes | yes |
| Survives CARLA upgrade without rework | rebase + rebuild | re-run + rebuild | yes | yes | yes | yes | yes |
| Visible/auditable (`ss`, logs) | yes, logged | yes | yes (`ss`) | needs test from 2nd host | `docker port` | needs test | — |
| Typical setup effort | hours (build) | hours (build) | 15 min | 10 min | 5 min | 5 min | 5 min |
| Main risk | build cost, forks diverge | same as A | preload not applied (typo, `setuid`) | cgroup v1 ignores rule | `-p` without `127.0.0.1:`, ufw bypass | forgotten rule, ufw bypass | not a fix on its own |

---

## Decision guide

**Which solution is best overall?**
**A (source fix)**, if you build CARLA from source anyway or ship your own
package/image. It is the only option where the server itself does the right
thing by default, it is documented, logged, platform-independent, and it
removes the dependency on every operator remembering a wrapper or rule.
Use B to apply it reproducibly; combine with G for remote use.

**Which solution only lightly manipulates an installed CARLA and can be
restored at any time?**
**C (`LD_PRELOAD` interposer)** on Linux. It changes zero files in the CARLA
directory, works with the prebuilt release, closes all four ports including
the Traffic Manager, and reverts by starting CARLA without the variable. The
server really binds to loopback, so `ss` shows the hardened state directly.
Ship it as a separate `CarlaUE4-secure.sh` wrapper next to the stock
`CarlaUE4.sh`, so the original launcher stays untouched.

If you do not want to compile even a tiny `.so`, **D (`systemd-run
IPAddressDeny`)** is the next lightest, with the caveat that it filters rather
than binds and must be verified on each machine.

**If CARLA runs in Docker**: **E with `-p 127.0.0.1:…`** is enough for the
simulator ports and needs no custom image. Keep the Python client in a
container too (or add F on the host) so the Traffic Manager's port 8000 is not
left open on the host. Set `"ip": "127.0.0.1"` in `daemon.json` to make the
safe form the default.

**On Windows without source build**: **F (Windows Firewall rule)** is the only
post-install option; A is the only one that fixes the binding itself.

**Always**, regardless of the primary choice: add **F** as defence in depth
and use **G** for remote access instead of opening the port.

### Recommended combinations

| Situation | Primary | Add |
|---|---|---|
| Build from source, own packages/images | A (+B for automation) | F, G |
| Prebuilt release on a Linux workstation / lab box, must be revertible | C | F |
| Prebuilt release on a Linux server, no compiler available | D | F, G |
| Official Docker image | E (`-p 127.0.0.1`) | F on host, client in container |
| Windows, prebuilt release | F | G |

---

## Appendix 1 — `LD_PRELOAD` interposer sketch (option C)

Untested starting point; compile with
`gcc -shared -fPIC -O2 -o bind_localhost.so bind_localhost.c -ldl`.

```c
// bind_localhost.c — rewrite IPv4 INADDR_ANY binds to a loopback address.
// Override the target with CARLA_LISTEN_HOST=<ipv4> (default 127.0.0.1).
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

typedef int (*bind_fn)(int, const struct sockaddr *, socklen_t);

int bind(int fd, const struct sockaddr *addr, socklen_t len) {
  static bind_fn real_bind = NULL;
  if (!real_bind) real_bind = (bind_fn)dlsym(RTLD_NEXT, "bind");

  if (addr && addr->sa_family == AF_INET && len >= sizeof(struct sockaddr_in)) {
    const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
    if (in->sin_addr.s_addr == htonl(INADDR_ANY)) {
      struct sockaddr_in patched;
      memcpy(&patched, in, sizeof(patched));
      const char *host = getenv("CARLA_LISTEN_HOST");
      if (!host || inet_pton(AF_INET, host, &patched.sin_addr) != 1) {
        patched.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      }
      return real_bind(fd, (const struct sockaddr *)&patched, sizeof(patched));
    }
  }
  return real_bind(fd, addr, len);
}
```

Wrapper `CarlaUE4-secure.sh` placed next to the stock launcher:

```bash
#!/usr/bin/env bash
# Launch CARLA with all listeners forced to loopback. Stock CarlaUE4.sh is unchanged.
export LD_PRELOAD="$(dirname "$0")/bind_localhost.so${LD_PRELOAD:+:$LD_PRELOAD}"
exec "$(dirname "$0")/CarlaUE4.sh" "$@"
```

Verification after start:
```bash
ss -ltnp | grep -E ':(2000|2001|2002|8000)'   # expect 127.0.0.1:* only
```

## Appendix 2 — Verification scripts

Two Python 3 scripts in `tools/` (standard library only, Windows and Linux;
`psutil` and `carla` are used when importable):

- `check-listen-exposure.py` proves the exposure before a fix and its absence
  after. Run it on the CARLA host while the server is up:
  ```bash
  python3 tools/check-listen-exposure.py --expect exposed    # fresh install: exit 0 when EXPOSED
  python3 tools/check-listen-exposure.py --expect hardened   # after the fix: exit 0 when HARDENED
  python3 tools/check-listen-exposure.py --host <carla-host-ip> --with-tm   # from a second machine
  ```
- `carla-security-audit.py` audits a running instance (bind addresses, UDP/DDS
  sockets, reachability, Traffic Manager, root, Docker port publishing, host
  firewall, patched vs. stock build) and prints a fix for every finding:
  ```bash
  python3 tools/carla-security-audit.py --carla-root /opt/carla     # exit 2 when a HIGH finding exists
  python3 tools/carla-security-audit.py --json > audit.json
  sudo python3 tools/carla-security-audit.py                        # Linux: full process names and firewall state
  ```

A local run reaches the host's own LAN address through loopback, so it does
not exercise host firewall rules (option F). Those need the run from a second
machine below.

## Appendix 3 — Verifying any option from a second machine

```bash
# from another host on the same network; must fail (timeout / refused)
nc -vz -w 3 <carla-host-ip> 2000
python3 -c "import carla; carla.Client('<carla-host-ip>', 2000).set_timeout(3.0); print(carla.Client('<carla-host-ip>', 2000).get_server_version())"
```
A hardening that has not been tested from a second host is not verified.
