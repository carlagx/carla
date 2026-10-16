#!/bin/bash
################################################################################
# CARLA test runner: server + Python client + C++ client, local or in Docker.
#
# Usage:
#   ./test-carla.sh [minimal|middle|full] [options]
#
# Levels (each includes the previous one):
#   minimal  prerequisites, server start, Python connect + version match
#   middle   + spawn vehicle with autopilot, camera sensor, C++ client (cpp_client)
#   full     + sync mode, map switching, GPU test client, generate_traffic.py,
#              server restart check
#
# Options:
#   --mode=local|docker   Where the server runs (default: local)
#   --image=NAME          Docker image (default: carla-xil:local)
#   --dist=DIR            Packaged server dir (default: newest Dist/*/LinuxNoEditor)
#   --port=N              RPC port (default: 2000)
#   --use-running         Do not start a server, test the one already on --host:--port
#   --keep-server         Leave the server running afterwards
#   --host=H              Host of the server (default: localhost)
#   --timeout=S           Seconds to wait for the server to come up (default: 300)
#   -h, --help
#
# Exit code is the number of failed checks (0 = all good).
################################################################################

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEVEL=minimal
MODE=local
IMAGE=carla-xil:local
DIST=""
PORT=2000
HOST=localhost
USE_RUNNING=0
KEEP=0
WAIT=300

for arg in "$@"; do
  case "$arg" in
    minimal|middle|full) LEVEL=$arg ;;
    --mode=*) MODE=${arg#*=} ;;
    --image=*) IMAGE=${arg#*=} ;;
    --dist=*) DIST=${arg#*=} ;;
    --port=*) PORT=${arg#*=} ;;
    --host=*) HOST=${arg#*=} ;;
    --timeout=*) WAIT=${arg#*=} ;;
    --use-running) USE_RUNNING=1 ;;
    --keep-server) KEEP=1 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $arg" >&2; exit 64 ;;
  esac
done

LOGDIR="$ROOT/test-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"
SERVER_PID=""
CONTAINER=""
PASS=0
FAIL=0
SKIP=0

rank() { case "$1" in minimal) echo 1;; middle) echo 2;; full) echo 3;; esac; }
at_least() { [ "$(rank "$LEVEL")" -ge "$(rank "$1")" ]; }

ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
skip() { echo "  [SKIP] $1"; SKIP=$((SKIP+1)); }
head_() { echo; echo "== $1 =="; }

# check "name" cmd...   (output goes to the log dir)
check() {
  local name=$1; shift
  local log="$LOGDIR/$(echo "$name" | tr -c 'A-Za-z0-9\n' '_').log"
  if "$@" >"$log" 2>&1; then ok "$name"; else bad "$name  (log: $log)"; fi
}

py() { python3 - "$HOST" "$PORT" "$@"; }

cleanup() {
  [ "$KEEP" -eq 1 ] && { echo; echo "Server left running (--keep-server)."; return; }
  if [ -n "$CONTAINER" ]; then docker rm -f "$CONTAINER" >/dev/null 2>&1; fi
  if [ -n "$SERVER_PID" ]; then
    # kill the whole process group of the server we started, nothing else
    kill -- -"$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null
    sleep 3
  fi
}
trap cleanup EXIT

port_open() { (exec 3<>/dev/tcp/"$HOST"/"$PORT") 2>/dev/null; }

# A real RPC round trip: with docker the port is open before the server is ready.
rpc_ready() {
  python3 -c "
import sys, carla
c = carla.Client(sys.argv[1], int(sys.argv[2])); c.set_timeout(5)
c.get_server_version()" "$HOST" "$PORT" >/dev/null 2>&1
}

################################################################################
head_ "Prerequisites"
################################################################################

check "python3 available" python3 --version
check "python module 'carla' importable" python3 -c "import carla"
# The wheel must come from this tree, not PyPI: versions must match the server.
check "ulimit -n >= 4096" bash -c '[ "$(ulimit -n)" -ge 4096 ]'
if [ "$MODE" = local ] && [ "$USE_RUNNING" -eq 0 ]; then
  [ "$(ulimit -n)" -lt 4096 ] && ulimit -n 10240 2>/dev/null
  check "NVIDIA GPU visible" nvidia-smi -L
  check "Vulkan works" bash -c 'vulkaninfo --summary 2>/dev/null | grep -q NVIDIA'
fi
if [ "$MODE" = docker ] && [ "$USE_RUNNING" -eq 0 ]; then
  check "docker available" docker info
  check "docker image $IMAGE exists" docker image inspect "$IMAGE"
  check "docker GPU runtime" docker run --rm --gpus all --entrypoint nvidia-smi "$IMAGE" -L
fi
if at_least middle; then
  if [ -x "$ROOT/Examples/CppClient/bin/cpp_client" ]; then ok "cpp_client binary present"
  else bad "cpp_client binary missing (cd Examples/CppClient && make build)"; fi
fi
if at_least full; then
  [ -x "$ROOT/Examples/CppClient/bin/gpu_test" ] && ok "gpu_test binary present" \
    || bad "gpu_test binary missing (cd Examples/CppClient && make gpu_test)"
  [ -f "$ROOT/PythonAPI/examples/generate_traffic.py" ] && ok "generate_traffic.py present" \
    || bad "generate_traffic.py missing"
fi

################################################################################
head_ "Server ($MODE)"
################################################################################

if [ "$USE_RUNNING" -eq 1 ]; then
  port_open && ok "server reachable on $HOST:$PORT" || bad "nothing listening on $HOST:$PORT"
else
  if port_open; then
    bad "port $PORT already in use (use --use-running or stop the other server)"
  elif [ "$MODE" = local ]; then
    [ -z "$DIST" ] && DIST=$(ls -dt "$ROOT"/Dist/*/LinuxNoEditor 2>/dev/null | head -1)
    if [ -z "$DIST" ] || [ ! -x "$DIST/CarlaUE4.sh" ]; then
      bad "no packaged server found (--dist=DIR or ./build-carla-server.sh)"
    else
      echo "  using $DIST"
      ( cd "$DIST" && exec setsid ./CarlaUE4.sh -RenderOffScreen -nosound \
          -carla-rpc-port="$PORT" ) >"$LOGDIR/server.log" 2>&1 &
      SERVER_PID=$!
    fi
  else
    CONTAINER="carla-test-$$"
    docker run -d --name "$CONTAINER" --gpus all -p "$PORT-$((PORT+2)):$PORT-$((PORT+2))" \
      "$IMAGE" /bin/bash CarlaUE4.sh -RenderOffScreen -nosound -carla-rpc-port="$PORT" \
      >"$LOGDIR/docker-run.log" 2>&1 || { bad "docker run failed (see $LOGDIR/docker-run.log)"; CONTAINER=""; }
  fi

  if [ -n "$SERVER_PID" ] || [ -n "$CONTAINER" ]; then
    echo "  waiting up to ${WAIT}s for the RPC port (first start compiles shaders)..."
    t=0
    until rpc_ready; do
      sleep 2; t=$((t+2))
      if [ "$t" -ge "$WAIT" ]; then break; fi
      if [ -n "$SERVER_PID" ] && ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
    done
    if rpc_ready; then ok "server answers RPC on port $PORT after ~${t}s"
    else
      bad "server did not come up (see $LOGDIR/server.log)"
      [ -n "$CONTAINER" ] && docker logs "$CONTAINER" >"$LOGDIR/server.log" 2>&1
    fi
  fi
fi

if ! port_open; then
  echo; echo "Server is not reachable, aborting."
  echo "Logs: $LOGDIR"; exit $((FAIL > 0 ? FAIL : 1))
fi

################################################################################
head_ "Level: minimal (Python connect)"
################################################################################

check "python connect + version match" py <<'PY'
import sys, carla
c = carla.Client(sys.argv[1], int(sys.argv[2])); c.set_timeout(120)
cv, sv = c.get_client_version(), c.get_server_version()
print(cv, sv)
assert cv == sv, f"client {cv} != server {sv}"
PY

check "python get_world + map + blueprints" py <<'PY'
import sys, carla
c = carla.Client(sys.argv[1], int(sys.argv[2])); c.set_timeout(120)
w = c.get_world()
print(w.get_map().name)
assert len(w.get_map().get_spawn_points()) > 0
assert len(w.get_blueprint_library().filter('vehicle.*')) > 0
PY

################################################################################
if at_least middle; then
head_ "Level: middle (actors, sensors, C++ client)"

check "python spawn vehicle + autopilot moves" py <<'PY'
import sys, time, carla
c = carla.Client(sys.argv[1], int(sys.argv[2])); c.set_timeout(120)
w = c.get_world()
bp = w.get_blueprint_library().filter('vehicle.tesla.model3')[0]
v = None
for sp in w.get_map().get_spawn_points():
    v = w.try_spawn_actor(bp, sp)
    if v: break
assert v, "no free spawn point"
try:
    tm = c.get_trafficmanager(); v.set_autopilot(True, tm.get_port())
    time.sleep(8)
    speed = v.get_velocity().length()
    print("speed m/s:", speed)
    assert speed > 0.5, "vehicle did not move"
finally:
    v.destroy()
PY

check "python RGB camera delivers images" py <<'PY'
import sys, time, carla
c = carla.Client(sys.argv[1], int(sys.argv[2])); c.set_timeout(120)
w = c.get_world()
bp = w.get_blueprint_library().find('sensor.camera.rgb')
bp.set_attribute('image_size_x', '640'); bp.set_attribute('image_size_y', '480')
cam = w.spawn_actor(bp, carla.Transform(carla.Location(z=30)))
frames = []
try:
    cam.listen(frames.append)
    time.sleep(5)
finally:
    cam.stop(); cam.destroy()
print("frames:", len(frames))
assert len(frames) > 0, "no image received"
PY

if [ -x "$ROOT/Examples/CppClient/bin/cpp_client" ]; then
  check "C++ cpp_client (Town06, autopilot)" timeout 600 \
    "$ROOT/Examples/CppClient/bin/cpp_client" "$HOST" "$PORT"
fi
fi

################################################################################
if at_least full; then
head_ "Level: full (sync mode, maps, GPU, traffic, restart)"

check "python synchronous mode ticks" py <<'PY'
import sys, carla
c = carla.Client(sys.argv[1], int(sys.argv[2])); c.set_timeout(120)
w = c.get_world(); orig = w.get_settings()
s = carla.WorldSettings(synchronous_mode=True, fixed_delta_seconds=0.05)
try:
    w.apply_settings(s)
    f0 = w.tick()
    for _ in range(50): f1 = w.tick()
    print(f0, f1)
    assert f1 - f0 == 50
finally:
    w.apply_settings(orig)
PY

check "python switch maps (Town04 -> Town06)" py <<'PY'
import sys, carla
c = carla.Client(sys.argv[1], int(sys.argv[2])); c.set_timeout(600)
for m in ('Town04', 'Town06'):
    avail = [x.split('/')[-1] for x in c.get_available_maps()]
    if m not in avail:
        print("map not packaged:", m, avail); continue
    w = c.load_world(m)
    print(w.get_map().name)
    assert w.get_map().name.endswith(m)
PY

[ -x "$ROOT/Examples/CppClient/bin/gpu_test" ] && \
  check "C++ gpu_test (vehicle + cameras)" timeout 600 \
    "$ROOT/Examples/CppClient/bin/gpu_test" "$HOST" "$PORT"

if [ -f "$ROOT/PythonAPI/examples/generate_traffic.py" ]; then
  check "generate_traffic.py (30 vehicles, 20 s)" bash -c \
    "timeout -s INT 20 python3 '$ROOT/PythonAPI/examples/generate_traffic.py' \
       --host '$HOST' -p '$PORT' -n 30 -w 0 --safe; rc=\$?; [ \$rc -eq 0 ] || [ \$rc -eq 124 ]"
fi

if [ "$USE_RUNNING" -eq 0 ] && { [ -n "$SERVER_PID" ] || [ -n "$CONTAINER" ]; }; then
  [ -n "$CONTAINER" ] && docker logs "$CONTAINER" >"$LOGDIR/server.log" 2>&1
  check "server has no fatal errors in log" bash -c \
    "! grep -E 'Fatal error|Segmentation fault|Unhandled Exception' '$LOGDIR/server.log'"
fi
fi

################################################################################
echo
echo "============================================================"
echo " Level: $LEVEL | Mode: $MODE | PASS: $PASS  FAIL: $FAIL  SKIP: $SKIP"
echo " Logs : $LOGDIR"
echo "============================================================"
exit "$FAIL"
