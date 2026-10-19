#!/usr/bin/env python3
"""
carla-security-audit.py - audit a running CARLA server for network and host
security weaknesses and print concrete remediation steps.

    python3 tools/carla-security-audit.py                       # audit the local machine
    python3 tools/carla-security-audit.py --carla-root /opt/carla   # also read logs/settings
    python3 tools/carla-security-audit.py --host 192.168.1.10   # remote reachability only
    python3 tools/carla-security-audit.py --json > audit.json

Checks (local run):
  LISTEN-ANY      CARLA TCP listeners bound to 0.0.0.0 / ::
  UDP-ANY         CARLA UDP sockets bound to all interfaces (ROS 2 / DDS, Zenoh)
  REACHABLE       simulator ports reachable from a non-loopback address
  CONTROL         RPC API answers from that address (full control confirmed)
  TM-ANY          Traffic Manager RPC port listening on all interfaces
  ROOT            CarlaUE4 process running as root (Linux)
  DOCKER-PUBLISH  docker container publishing CARLA ports on 0.0.0.0
  FIREWALL        no host firewall rule covering the CARLA ports (best effort)
  BUILD           whether the running build supports --listen-host (log/settings)
  RECORDER-PATH   by design: clients choose arbitrary server-side file paths
  NO-AUTH         by design: the protocol has no authentication or encryption

Exit codes: 0 = no HIGH findings, 2 = at least one HIGH finding, 1 = error.
Standard library only; `psutil` and `carla` are used when importable.
"""

import argparse
import json
import os
import platform
import re
import socket
import subprocess
import sys
from pathlib import Path

SEVERITY_ORDER = {"HIGH": 0, "MEDIUM": 1, "LOW": 2, "INFO": 3}
ANY_ADDRS = {"0.0.0.0", "*", "::", "[::]", "0.0.0.0:*"}
CARLA_PROC_PATTERN = re.compile(r"carla", re.IGNORECASE)
DDS_PORT_RANGE = range(7400, 7700)   # DDS discovery/user traffic for domains 0..~10
ZENOH_PORT = 7447

findings = []


def add(code, severity, title, evidence, fix):
    findings.append({"code": code, "severity": severity, "title": title,
                     "evidence": evidence, "fix": fix})


def run(cmd, timeout=15):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


# ---------------------------------------------------------------------------
# Socket table
# ---------------------------------------------------------------------------

def proc_name(pid):
    if pid is None:
        return ""
    try:
        import psutil
        return psutil.Process(pid).name()
    except Exception:
        pass
    try:
        return Path(f"/proc/{pid}/comm").read_text().strip()
    except OSError:
        pass
    if platform.system() == "Windows":
        out = run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"])
        m = re.match(r'"([^"]+)"', out.strip())
        if m:
            return m.group(1)
    return ""


def proc_cmdline(pid):
    try:
        import psutil
        return " ".join(psutil.Process(pid).cmdline())
    except Exception:
        pass
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return ""


def proc_uid(pid):
    try:
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("Uid:"):
                return int(line.split()[1])
    except (OSError, ValueError):
        pass
    return None


def listening_sockets():
    """Return list of dicts: proto, addr, port, pid, name. Best effort across psutil/ss/netstat."""
    socks = []
    try:
        import psutil
        for c in psutil.net_connections(kind="inet"):
            if c.type == socket.SOCK_STREAM and c.status != psutil.CONN_LISTEN:
                continue
            if c.type == socket.SOCK_DGRAM and c.raddr:
                continue
            if not c.laddr:
                continue
            socks.append({"proto": "tcp" if c.type == socket.SOCK_STREAM else "udp",
                          "addr": c.laddr.ip, "port": c.laddr.port, "pid": c.pid,
                          "name": proc_name(c.pid)})
        return socks
    except ImportError:
        pass
    except Exception as exc:  # e.g. AccessDenied on macOS/Windows without privileges
        print(f"note: psutil.net_connections failed ({exc}); falling back to ss/netstat", file=sys.stderr)

    out = run(["ss", "-Hlntup"])
    if out:
        for line in out.splitlines():
            parts = line.split()
            if len(parts) < 5:
                continue
            proto = parts[0]
            m = re.match(r"(.*):(\d+)$", parts[4])
            if not m:
                continue
            pid_m = re.search(r"pid=(\d+)", line)
            name_m = re.search(r'users:\(\("([^"]+)"', line)
            pid = int(pid_m.group(1)) if pid_m else None
            socks.append({"proto": proto, "addr": m.group(1).strip("[]"), "port": int(m.group(2)),
                          "pid": pid, "name": name_m.group(1) if name_m else proc_name(pid)})
        return socks

    if platform.system() == "Windows":
        out = run(["netstat", "-ano"])
        for line in out.splitlines():
            parts = line.split()
            if len(parts) < 4 or parts[0] not in ("TCP", "UDP"):
                continue
            # The status word is localized ("LISTENING", "ABHÖREN", ...): a TCP listener is
            # recognised by its empty remote endpoint instead.
            if parts[0] == "TCP" and (len(parts) < 5 or parts[2] not in ("0.0.0.0:0", "[::]:0")):
                continue
            m = re.match(r"(.*):(\d+)$", parts[1])
            if not m:
                continue
            pid = int(parts[-1]) if parts[-1].isdigit() else None
            socks.append({"proto": parts[0].lower(), "addr": m.group(1).strip("[]"),
                          "port": int(m.group(2)), "pid": pid, "name": proc_name(pid)})
        return socks

    out = run(["netstat", "-tulpn"])
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4 or not parts[0].startswith(("tcp", "udp")):
            continue
        m = re.match(r"(.*):(\d+)$", parts[3])
        if not m:
            continue
        pid_m = re.search(r"(\d+)/(\S+)", parts[-1])
        socks.append({"proto": parts[0][:3], "addr": m.group(1).strip("[]"), "port": int(m.group(2)),
                      "pid": int(pid_m.group(1)) if pid_m else None,
                      "name": pid_m.group(2) if pid_m else ""})
    return socks


def is_any(addr):
    return addr in ANY_ADDRS


def is_loopback(addr):
    return addr.startswith("127.") or addr == "::1"


# ---------------------------------------------------------------------------
# Network helpers
# ---------------------------------------------------------------------------

def local_ipv4_addresses():
    addrs = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            addrs.add(info[4][0])
    except socket.gaierror:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("10.255.255.255", 1))
        addrs.add(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    return sorted(a for a in addrs if not a.startswith("127."))


def tcp_open(host, port, timeout):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def carla_probe(host, port, timeout):
    """Return (version, actor_count) via the RPC API or None."""
    try:
        import carla
    except ImportError:
        return None
    try:
        client = carla.Client(host, port)
        client.set_timeout(timeout)
        version = client.get_server_version()
        actors = len(client.get_world().get_actors())
        return version, actors
    except RuntimeError:
        return None


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_sockets(rpc_port, tm_port):
    socks = listening_sockets()
    carla_socks = [s for s in socks if CARLA_PROC_PATTERN.search(s["name"] or "")]
    sim_ports = {rpc_port, rpc_port + 1, rpc_port + 2}

    # Simulator ports may belong to a process we could not name (no privileges): include them by port.
    for s in socks:
        if s["proto"] == "tcp" and s["port"] in sim_ports and s not in carla_socks:
            carla_socks.append(s)

    if not any(s["proto"] == "tcp" and s["port"] == rpc_port for s in socks):
        return None, socks  # no server on this machine

    tcp_any = [s for s in carla_socks if s["proto"] == "tcp" and is_any(s["addr"])]
    if tcp_any:
        add("LISTEN-ANY", "HIGH",
            "CARLA TCP listeners are bound to all interfaces",
            [f"{s['proto']} {s['addr']}:{s['port']} pid={s['pid']} {s['name']}" for s in tcp_any],
            ["Patched build: launch with --listen-host=127.0.0.1 or set [CARLA/Server] ListenHost=127.0.0.1 "
             "in CarlaSettings.ini (option A).",
             "Stock Linux build: start through an LD_PRELOAD bind interposer wrapper (option C) or "
             "systemd-run -p IPAddressDeny=any -p IPAddressAllow=localhost (option D).",
             "Docker: publish ports as -p 127.0.0.1:2000-2002:2000-2002 (option E).",
             "Add a host firewall rule for the ports as a second layer (option F)."])
    else:
        bound = sorted({f"{s['addr']}:{s['port']}" for s in carla_socks if s["proto"] == "tcp"})
        add("LISTEN-ANY", "INFO", "CARLA TCP listeners are bound to specific addresses", bound,
            ["No action if every address is loopback. A LAN address is still network-reachable: "
             "prefer 127.0.0.1 plus an SSH tunnel for remote clients (option G)."])

    udp_any = [s for s in carla_socks if s["proto"] == "udp" and is_any(s["addr"])]
    if udp_any:
        dds = [s for s in udp_any if s["port"] in DDS_PORT_RANGE or s["port"] == ZENOH_PORT]
        add("UDP-ANY", "MEDIUM",
            "CARLA UDP sockets are bound to all interfaces" + (" (ROS 2 / DDS discovery)" if dds else ""),
            [f"udp {s['addr']}:{s['port']} pid={s['pid']}" for s in udp_any],
            ["ROS 2 native mode: set ROS_LOCALHOST_ONLY=1 before launching, or restrict the DDS/Zenoh "
             "participant to a specific interface in the middleware XML.",
             "Pick a dedicated --ros-domain-id and keep it off shared networks.",
             "Firewall UDP 7400-7699 and 7447 inbound, or run inside a Docker network without -p."])

    tm_socks = [s for s in socks if s["proto"] == "tcp" and s["port"] == tm_port]
    if tm_socks:
        tm_any = [s for s in tm_socks if is_any(s["addr"])]
        if tm_any:
            add("TM-ANY", "HIGH",
                "Traffic Manager RPC port is listening on all interfaces",
                [f"tcp {s['addr']}:{s['port']} pid={s['pid']} {s['name']} (the TM server lives in the "
                 f"client process that created it)" for s in tm_any],
                ["Use a client built from the patched LibCarla (TrafficManagerServer binds 127.0.0.1).",
                 "Otherwise run the client under the LD_PRELOAD wrapper too, or firewall port "
                 f"{tm_port} inbound (option F).",
                 "In Docker, run the client in a container without publishing the TM port."])
        else:
            add("TM-ANY", "INFO", "Traffic Manager RPC port is bound to loopback",
                [f"tcp {s['addr']}:{s['port']}" for s in tm_socks], [])
    else:
        add("TM-ANY", "INFO", "No Traffic Manager server running right now",
            [f"port {tm_port} not in LISTEN state; the TM opens when a client calls get_trafficmanager()"],
            ["Re-run the audit while a client with a Traffic Manager is connected."])

    pids = sorted({s["pid"] for s in carla_socks if s["pid"]})
    return pids, socks


def check_reachability(hosts, rpc_port, tm_port, timeout, socks):
    ports = {"rpc": rpc_port, "streaming": rpc_port + 1, "secondary": rpc_port + 2}
    if any(s["proto"] == "tcp" and s["port"] == tm_port for s in socks):
        ports["traffic_manager"] = tm_port
    reachable = []
    for h in hosts:
        for name, port in ports.items():
            if tcp_open(h, port, timeout):
                reachable.append((name, h, port))
    if reachable:
        add("REACHABLE", "HIGH",
            "Simulator ports accept connections from a non-loopback address",
            [f"{name} {h}:{port} OPEN" for name, h, port in reachable],
            ["Bind to loopback (options A/C/D), or publish only on 127.0.0.1 in Docker (option E), "
             "and verify again from a second machine."])
        rpc_hits = [(h, p) for n, h, p in reachable if n == "rpc"]
        if rpc_hits:
            probe = carla_probe(rpc_hits[0][0], rpc_hits[0][1], timeout)
            if probe:
                version, actors = probe
                add("CONTROL", "HIGH",
                    "Full simulator control confirmed from the external address, no credentials needed",
                    [f"carla.Client('{rpc_hits[0][0]}', {rpc_hits[0][1]}): server {version}, "
                     f"{actors} actors visible; load_world/spawn/destroy/recorder are all available"],
                    ["Same as REACHABLE. There is no authentication to enable; isolation is the only control."])
    else:
        add("REACHABLE", "INFO" if hosts else "LOW",
            "Simulator ports are not reachable from " + (", ".join(hosts) if hosts else "any tested address"),
            [f"tested ports {sorted(ports.values())}"],
            ["Host firewall rules are not exercised by a local test; confirm from a second machine "
             "with --host <carla-host-ip>."] if hosts else ["No non-loopback address found; pass --host."])


def check_process(pids):
    if platform.system() != "Linux" or not pids:
        return
    root = [pid for pid in pids if proc_uid(pid) == 0]
    if root:
        add("ROOT", "MEDIUM", "CarlaUE4 is running as root",
            [f"pid {pid} uid=0" for pid in root],
            ["Run the server as a dedicated unprivileged user (the Docker images use user 'carla').",
             "A remote client can make the server write files anywhere that user can write "
             "(see RECORDER-PATH), so least privilege matters."])
    else:
        add("ROOT", "INFO", "CarlaUE4 runs as a non-root user", [f"pids {pids}"], [])

    for pid in pids:
        cl = proc_cmdline(pid)
        if "listen-host" in cl:
            m = re.search(r"-listen-host=(\S+)", cl)
            add("BUILD", "INFO", "Server was launched with an explicit --listen-host",
                [f"pid {pid}: --listen-host={m.group(1) if m else '?'}"],
                ["0.0.0.0 re-opens the exposure; use it only behind a firewall or VPN."] if m and m.group(1) == "0.0.0.0" else [])


def check_docker(rpc_port, tm_port):
    if Path("/.dockerenv").exists():
        add("DOCKER-PUBLISH", "INFO", "Audit is running inside a container",
            ["Inside the container the bind address matters less than how the host publishes ports."],
            ["Run this audit on the Docker host as well to inspect the published ports."])
        return
    out = run(["docker", "ps", "--format", "{{.ID}}\t{{.Image}}\t{{.Ports}}\t{{.Names}}"])
    if not out:
        return
    bad, ok = [], []
    for line in out.splitlines():
        cid, image, ports, name = (line.split("\t") + ["", "", "", ""])[:4]
        if not re.search(r"carla", image + name + ports, re.IGNORECASE) and str(rpc_port) not in ports:
            continue
        for m in re.finditer(r"(\S+?):(\d+)(?:-(\d+))?->", ports):
            host_ip = m.group(1)
            (bad if host_ip in ("0.0.0.0", "::", "[::]") else ok).append(f"{name} ({image}): {m.group(0)}")
    if bad:
        add("DOCKER-PUBLISH", "HIGH", "A CARLA container publishes ports on all host interfaces",
            bad, ["Use -p 127.0.0.1:2000-2002:2000-2002 instead of -p 2000-2002:2000-2002.",
                  "Or set \"ip\": \"127.0.0.1\" in /etc/docker/daemon.json so this is the default.",
                  "Docker bypasses ufw: a ufw 'deny incoming' does NOT protect published ports."])
    elif ok:
        add("DOCKER-PUBLISH", "INFO", "CARLA container ports are published on specific host addresses", ok, [])


def check_firewall(rpc_port, tm_port):
    system = platform.system()
    ports = [rpc_port, rpc_port + 1, rpc_port + 2, tm_port]
    if system == "Linux":
        ufw = run(["ufw", "status"]) or run(["sudo", "-n", "ufw", "status"])
        nft = run(["nft", "list", "ruleset"]) or run(["sudo", "-n", "nft", "list", "ruleset"])
        ipt = run(["iptables", "-S", "INPUT"]) or run(["sudo", "-n", "iptables", "-S", "INPUT"])
        text = ufw + nft + ipt
        if not text.strip():
            add("FIREWALL", "LOW", "Could not read host firewall state (no permission or no tool)",
                ["ufw/nft/iptables returned nothing; re-run with sudo for this check"], [])
            return
        covered = [p for p in ports if re.search(rf"\b{p}\b", text)]
        active = "Status: active" in ufw or "chain input" in nft.lower() or "-A INPUT" in ipt
        if not active:
            add("FIREWALL", "MEDIUM", "No active host firewall detected",
                ["ufw inactive / no INPUT rules"],
                [f"sudo ufw enable && sudo ufw deny in proto tcp to any port {rpc_port}:{rpc_port + 2} "
                 f"&& sudo ufw deny in proto tcp to any port {tm_port}"])
        elif not covered:
            add("FIREWALL", "LOW", "Host firewall is active but has no rule mentioning the CARLA ports",
                ["default policy decides; verify from a second machine"],
                [f"sudo ufw deny in proto tcp to any port {rpc_port}:{rpc_port + 2}",
                 f"sudo ufw deny in proto tcp to any port {tm_port}"])
        else:
            add("FIREWALL", "INFO", "Host firewall has rules mentioning the CARLA ports",
                [f"ports referenced: {covered}"], ["Confirm the rules block, not allow, from a second machine."])
    elif system == "Windows":
        print("note: querying Windows Firewall rules (can take up to a minute)...", file=sys.stderr)
        port_list = ",".join(str(p) for p in ports)
        # Enumerate port filters first (fast), then resolve only the matching rules.
        out = run(["powershell", "-NoProfile", "-Command",
                   f"$ports = @({port_list}); "
                   "Get-NetFirewallPortFilter -PolicyStore ActiveStore | "
                   "Where-Object { $_.Protocol -eq 'TCP' -and ($_.LocalPort | Where-Object { $ports -contains [int]($_ -replace '-.*','') }) } | "
                   "Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' } | "
                   "ForEach-Object { \"$($_.DisplayName)|$($_.Action)|\" + (($_ | Get-NetFirewallPortFilter).LocalPort -join ',') }; "
                   "Write-Output '__DONE__'"], timeout=120)
        if "__DONE__" not in out:
            add("FIREWALL", "LOW", "Could not read Windows Firewall rules (PowerShell query failed or timed out)",
                ["Get-NetFirewallPortFilter returned nothing"],
                ["Check manually: Get-NetFirewallRule -Direction Inbound -Enabled True | Get-NetFirewallPortFilter | "
                 f"Where-Object LocalPort -in {port_list}"])
            return
        rules = [l for l in out.splitlines() if "|" in l]
        covered = [p for p in ports if any(re.search(rf"\b{p}\b", r) for r in rules)]
        if not covered:
            add("FIREWALL", "LOW", "No enabled inbound Windows Firewall rule mentions the CARLA ports",
                ["Windows Firewall's default inbound block applies only if the profile is on and CarlaUE4 "
                 "was not allowed through when it first asked"],
                ['New-NetFirewallRule -DisplayName "CARLA loopback only" -Direction Inbound -Protocol TCP '
                 f'-LocalPort {rpc_port},{rpc_port + 1},{rpc_port + 2},{tm_port} -Action Block'])
        else:
            allow = [r for r in rules if "|Allow|" in r]
            add("FIREWALL", "MEDIUM" if allow else "INFO",
                "Windows Firewall has inbound rules for the CARLA ports" + (" that ALLOW traffic" if allow else ""),
                rules, ["Block rules win over Allow rules only if no Allow rule matches; replace Allow rules for "
                        "CarlaUE4 with a Block rule or scope them to -RemoteAddress LocalSubnet/specific IPs."] if allow else [])


def check_build(carla_root, rpc_port):
    if not carla_root:
        add("BUILD", "INFO", "Build type unknown (pass --carla-root to read the server log and settings)",
            [], ["A patched build prints 'Listen Host = ...' in CarlaUE4/Saved/Logs/CarlaUE4.log."])
        return
    root = Path(carla_root)
    logs = sorted(root.glob("**/Saved/Logs/CarlaUE4.log"), key=lambda p: p.stat().st_mtime, reverse=True)
    if logs:
        text = logs[0].read_text(errors="replace")
        m = re.search(r"Listen Host = (\S+)", text)
        if m:
            add("BUILD", "INFO", "Patched build detected (configurable ListenHost)",
                [f"{logs[0]}: Listen Host = {m.group(1)}"],
                [] if m.group(1).startswith("127.") else ["Set --listen-host=127.0.0.1 to close the exposure."])
        else:
            add("BUILD", "MEDIUM", "Stock build detected: no ListenHost support, listeners always bind 0.0.0.0",
                [f"{logs[0]}: no 'Listen Host =' line"],
                ["Rebuild with the localhost-bind fix (tools/apply-localhost-bind-fix.sh), or use "
                 "LD_PRELOAD / systemd-run / Docker 127.0.0.1 publishing / firewall as post-install options."])
    inis = list(root.glob("**/Config/CarlaSettings.ini"))
    for ini in inis:
        m = re.search(r"^\s*ListenHost\s*=\s*(\S+)", ini.read_text(errors="replace"), re.MULTILINE)
        if m:
            add("BUILD", "INFO", "CarlaSettings.ini sets ListenHost", [f"{ini}: ListenHost={m.group(1)}"],
                ["0.0.0.0 re-opens the exposure."] if m.group(1) == "0.0.0.0" else [])


def check_by_design(rpc_port):
    add("NO-AUTH", "INFO",
        "The CARLA RPC/streaming protocol has no authentication or encryption (by design)",
        [f"any TCP peer of port {rpc_port} is a fully trusted client"],
        ["Treat network reachability as full access. Keep the server on loopback and reach it through "
         "an SSH tunnel or VPN: ssh -N -L 2000:127.0.0.1:2000 -L 2001:127.0.0.1:2001 "
         "-L 2002:127.0.0.1:2002 user@carla-host"])
    add("RECORDER-PATH", "INFO",
        "Clients choose server-side file paths for the recorder/replayer (by design)",
        ["GetRecorderFilename() uses any name containing '/', '\\\\' or ':' verbatim, so "
         "client.start_recorder('/tmp/x.log') writes outside Saved/ with the server's privileges; "
         "show_recorder_* reads arbitrary files the server can open"],
        ["Run CarlaUE4 as an unprivileged user with a writable Saved/ only (read-only root filesystem "
         "in Docker: --read-only --tmpfs /tmp -v carla-saved:/home/carla/CarlaUE4/Saved).",
         "Never expose the RPC port to untrusted clients; this is not fixable with a bind address."])


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

def print_report(hosts, as_json):
    findings.sort(key=lambda f: (SEVERITY_ORDER[f["severity"]], f["code"]))
    if as_json:
        print(json.dumps({"hosts": hosts, "findings": findings}, indent=2))
        return
    counts = {}
    for f in findings:
        counts[f["severity"]] = counts.get(f["severity"], 0) + 1
    print("CARLA security audit")
    print("=" * 72)
    print("Summary: " + ", ".join(f"{counts.get(s, 0)} {s}" for s in SEVERITY_ORDER))
    print()
    for f in findings:
        print(f"[{f['severity']:<6}] {f['code']}: {f['title']}")
        for e in f["evidence"]:
            print(f"    evidence: {e}")
        for r in f["fix"]:
            print(f"    fix:      {r}")
        print()
    print("Options A-G refer to tools/security-hardening-options.md.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", action="append", default=[],
                    help="external address to test (repeatable); default: this machine's non-loopback IPv4s")
    ap.add_argument("--rpc-port", type=int, default=2000)
    ap.add_argument("--tm-port", type=int, default=8000)
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--carla-root", help="installed CARLA directory, to read CarlaUE4.log and CarlaSettings.ini")
    ap.add_argument("--remote-only", action="store_true",
                    help="skip local socket/process/firewall checks (run from a second machine)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    hosts = args.host or local_ipv4_addresses()
    socks, pids = [], []
    if not args.remote_only:
        pids, socks = check_sockets(args.rpc_port, args.tm_port)
        if pids is None:
            if not args.host:
                print(f"ERROR: no process listening on tcp port {args.rpc_port} on this machine. "
                      "Start CarlaUE4 first, or use --host/--remote-only for a remote server.", file=sys.stderr)
                return 1
            pids = []
    # Reachability first: it is the core finding and must not wait behind slow firewall queries.
    check_reachability(hosts, args.rpc_port, args.tm_port, args.timeout, socks)
    if not args.remote_only:
        check_process(pids)
        check_docker(args.rpc_port, args.tm_port)
        check_firewall(args.rpc_port, args.tm_port)
        check_build(args.carla_root, args.rpc_port)
    check_by_design(args.rpc_port)

    print_report(hosts, args.json)
    return 2 if any(f["severity"] == "HIGH" for f in findings) else 0


if __name__ == "__main__":
    sys.exit(main())
