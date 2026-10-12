#!/usr/bin/env python3
"""
check-listen-exposure.py - prove whether a running CARLA server is reachable
from the network (exposed) or only from the local machine (hardened).

Run it twice against the same machine: once after a fresh CARLA install
(expect EXPOSED) and once after applying the localhost-bind fix or any other
hardening (expect HARDENED). The exit code makes the result scriptable.

    python3 tools/check-listen-exposure.py                 # auto-detect this host's IPs
    python3 tools/check-listen-exposure.py --expect exposed  # before the fix, exit 0 if exposed
    python3 tools/check-listen-exposure.py --expect hardened # after the fix, exit 0 if hardened
    python3 tools/check-listen-exposure.py --host 192.168.1.10 --with-tm   # from a second machine

Exit codes: 0 = verdict matches --expect (or HARDENED without --expect),
            2 = EXPOSED (without --expect) or verdict differs from --expect,
            1 = error (no CARLA server found, bad arguments).

Only the Python standard library is required. If the `carla` module is
importable the script also proves full control by calling the RPC API from the
external address instead of just opening a TCP connection.

Note on firewall-based hardening: a check run on the CARLA host itself goes
through the loopback interface even when it targets the host's LAN address, so
host firewall rules (ufw, Windows Firewall) are not exercised. To verify a
firewall, run this script on a second machine with --host <carla-host-ip>.
"""

import argparse
import re
import socket
import subprocess
import sys

RPC_OFFSETS = {"rpc": 0, "streaming": 1, "secondary": 2}


def local_ipv4_addresses():
    """Return the non-loopback IPv4 addresses of this machine (best effort)."""
    addrs = set()
    try:
        host = socket.gethostname()
        for info in socket.getaddrinfo(host, None, socket.AF_INET):
            addrs.add(info[4][0])
    except socket.gaierror:
        pass
    # The UDP trick returns the address of the default route interface without sending anything.
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


def rpc_version(host, port, timeout):
    """Return the server version via the CARLA RPC API, or None if carla is unavailable/unreachable."""
    try:
        import carla  # noqa: F401
    except ImportError:
        return None
    try:
        client = carla.Client(host, port)
        client.set_timeout(timeout)
        return client.get_server_version()
    except RuntimeError:
        return None


def spawn_traffic_manager(host, rpc_port, tm_port, timeout):
    """Create a Traffic Manager through the local server so its RPC port is open during the test."""
    try:
        import carla
    except ImportError:
        print("  --with-tm ignored: carla module not importable")
        return None
    try:
        client = carla.Client(host, rpc_port)
        client.set_timeout(timeout)
        tm = client.get_trafficmanager(tm_port)
        return tm  # keep the reference alive; the TM server lives in this process
    except RuntimeError as exc:
        print(f"  --with-tm failed: {exc}")
        return None


def bind_addresses(ports):
    """Best-effort list of (bind_address, port) for the given ports from the OS socket table."""
    found = []
    cmds = [["ss", "-Hltn"], ["netstat", "-ant"], ["netstat", "-ano", "-p", "tcp"]]
    for cmd in cmds:
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        for line in out.splitlines():
            # netstat prints a localized status word ("LISTENING", "ABHÖREN", ...), so a
            # listener is recognised by its empty remote endpoint instead; ss -l lists only listeners.
            cols = line.split()
            is_listener = cmd[0] == "ss" or "LISTEN" in line.upper() or \
                (len(cols) >= 3 and cols[2] in ("0.0.0.0:0", "[::]:0", "*.*", "*:*"))
            if not is_listener or len(cols) < 2:
                continue
            # The local endpoint is the first "addr:port" column (ss: after the counters, netstat: column 2).
            m = next((mm for mm in (re.match(r"(.*):(\d+)$", c) for c in cols) if mm), None)
            if not m:
                continue
            addr, port = m.group(1).strip("[]"), int(m.group(2))
            if port in ports and (addr, port) not in found:
                found.append((addr, port))
        if found:
            break
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", action="append", default=[],
                    help="external address to test (repeatable); default: this machine's non-loopback IPv4s")
    ap.add_argument("--local", default="127.0.0.1", help="loopback address the server is expected on")
    ap.add_argument("--rpc-port", type=int, default=2000)
    ap.add_argument("--tm-port", type=int, default=8000)
    ap.add_argument("--with-tm", action="store_true",
                    help="spawn a Traffic Manager through the local server so port 8000 is tested too")
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--expect", choices=["exposed", "hardened"],
                    help="assert the verdict; exit 0 when it matches, 2 otherwise")
    args = ap.parse_args()

    ports = {name: args.rpc_port + off for name, off in RPC_OFFSETS.items()}
    hosts = args.host or local_ipv4_addresses()
    if not hosts:
        print("ERROR: no non-loopback IPv4 address found; pass --host explicitly.")
        return 1

    print(f"CARLA listen exposure check  (local={args.local}, external={', '.join(hosts)})")
    print()

    # 1. The server must be running on loopback, otherwise there is nothing to prove.
    if not tcp_open(args.local, ports["rpc"], args.timeout):
        print(f"ERROR: no CARLA RPC server on {args.local}:{ports['rpc']}. Start CarlaUE4 first.")
        return 1
    version = rpc_version(args.local, ports["rpc"], args.timeout)
    print(f"Server on {args.local}:{ports['rpc']}: reachable" + (f" (version {version})" if version else ""))

    tm = None
    if args.with_tm:
        tm = spawn_traffic_manager(args.local, ports["rpc"], args.tm_port, args.timeout)
        if tm is not None:
            ports["traffic_manager"] = args.tm_port

    # 2. Show what the OS says about the bind addresses (informational).
    binds = bind_addresses(set(ports.values()))
    if binds:
        print("Bind addresses reported by the OS:")
        for addr, port in sorted(binds, key=lambda x: x[1]):
            flag = "ALL INTERFACES" if addr in ("0.0.0.0", "*", "::", "[::]") else "loopback" if addr.startswith("127.") or addr == "::1" else "specific"
            print(f"  {addr}:{port:<6} {flag}")
    print()

    # 3. Try every port from every external address.
    print(f"{'port':<17}{'number':<8}" + "".join(f"{h:<18}" for h in hosts))
    exposed = []
    for name, port in ports.items():
        row = f"{name:<17}{port:<8}"
        for h in hosts:
            is_open = tcp_open(h, port, args.timeout)
            row += f"{'OPEN' if is_open else 'closed':<18}"
            if is_open:
                exposed.append((name, h, port))
        print(row)
    print()

    # 4. If the RPC port is open externally and carla is importable, prove full control.
    for name, h, port in exposed:
        if name == "rpc":
            v = rpc_version(h, port, args.timeout)
            if v:
                print(f"Proof of control: carla.Client('{h}', {port}).get_server_version() -> {v}")
                print("  Anyone who can reach this address can load maps, spawn actors and read all sensors.")
            break

    verdict = "exposed" if exposed else "hardened"
    if exposed:
        print("VERDICT: EXPOSED - CARLA accepts connections from a non-loopback address:")
        for name, h, port in exposed:
            print(f"  {name} on {h}:{port}")
        print("Fix: launch with --listen-host=127.0.0.1 (patched build), use the LD_PRELOAD wrapper,")
        print("     publish Docker ports as -p 127.0.0.1:2000-2002:2000-2002, or add a host firewall rule.")
    else:
        print("VERDICT: HARDENED - the server answers on loopback only.")
        print("  (Run from a second machine with --host to also confirm firewall-based setups.)")

    if args.expect:
        ok = args.expect == verdict
        print(f"Expected {args.expect.upper()}: {'match' if ok else 'MISMATCH'}")
        return 0 if ok else 2
    return 2 if exposed else 0


if __name__ == "__main__":
    sys.exit(main())
