#!/usr/bin/env bash
#
# apply-localhost-bind-fix.sh
#
# Applies the "bind CARLA server listeners to localhost by default" security fix
# to a freshly cloned CARLA repository (branch ue4-dev). It recreates the two
# upstream commits via `git am --3way`:
#   1. feat(Carla): make server bind address configurable, default to localhost
#   2. feat(trafficmanager): bind the Traffic Manager RPC server to localhost
#
# Usage:
#   git clone --branch ue4-dev https://github.com/carla-simulator/carla.git
#   cd carla
#   /path/to/apply-localhost-bind-fix.sh
#
# Re-running is a no-op if the fix is already present. The patch is embedded
# below, so this single file is all you need.

set -euo pipefail

# Move to the repository root.
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository. cd into your CARLA clone first." >&2
  exit 1
fi
cd "$(git rev-parse --show-toplevel)"

# Sanity check: does this look like a CARLA checkout?
SETTINGS="Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.h"
if [ ! -f "$SETTINGS" ]; then
  echo "ERROR: this does not look like a CARLA repository ($SETTINGS missing)." >&2
  exit 1
fi

# Idempotency: already applied?
if grep -q "ListenHost" "$SETTINGS"; then
  echo "Fix already present (ListenHost found in CarlaSettings.h). Nothing to do."
  exit 0
fi

# git am needs a clean working tree.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: working tree has uncommitted changes. Commit or stash them first." >&2
  exit 1
fi

# Warn if not on ue4-dev (the patch base).
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
if [ "$BRANCH" != "ue4-dev" ]; then
  echo "WARNING: current branch is '$BRANCH', the patch targets 'ue4-dev'. Continuing." >&2
fi

# Write the embedded patch to a temp file.
PATCH_FILE="$(mktemp)"
trap 'rm -f "$PATCH_FILE"' EXIT
cat > "$PATCH_FILE" <<'FIX_PATCH_EOF'
From aef7be4fb60da8d914eabe0763e7f1f2e3301a58 Mon Sep 17 00:00:00 2001
From: carlagx <carlagx@gmx.net>
Date: Tue, 23 Jun 2026 00:22:49 +0200
Subject: [PATCH 1/2] feat(Carla): make server bind address configurable,
 default to localhost

The RPC, streaming and multi-GPU listeners bound to 0.0.0.0 (all
interfaces); only the port was configurable. CARLA's RPC/streaming
protocol has no authentication or encryption, so this exposed full
control of the simulation and all sensor data to any reachable network.

Add a ListenHost setting (default 127.0.0.1) threaded through
CarlaSettings -> CarlaEngine -> FCarlaServer::Start -> FPimpl to all three
listeners, plus an address constructor on multigpu::Router to replace its
hardcoded 0.0.0.0. Configurable via [CARLA/Server] ListenHost in
CarlaSettings.ini or --listen-host=<ip> (forwarded by BuildCarlaUE4.sh for
make launch). Use --listen-host=0.0.0.0 to restore the previous behavior.

Verified on Ubuntu glibc 2.35: default binds RPC/streaming/secondary on
127.0.0.1; --listen-host=0.0.0.0 binds them on 0.0.0.0.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
---
 CHANGELOG.md                                      |  1 +
 Docs/foundations.md                               |  3 +++
 LibCarla/source/carla/multigpu/router.cpp         |  5 ++++-
 LibCarla/source/carla/multigpu/router.h           |  2 ++
 .../Carla/Source/Carla/Game/CarlaEngine.cpp       |  2 +-
 .../Carla/Source/Carla/Server/CarlaServer.cpp     | 15 ++++++++-------
 .../Carla/Source/Carla/Server/CarlaServer.h       |  2 +-
 .../Carla/Source/Carla/Settings/CarlaSettings.cpp | 12 ++++++++++++
 .../Carla/Source/Carla/Settings/CarlaSettings.h   |  6 ++++++
 Util/BuildTools/BuildCarlaUE4.sh                  | 13 +++++++++++--
 10 files changed, 49 insertions(+), 12 deletions(-)

diff --git a/CHANGELOG.md b/CHANGELOG.md
index 5ce0e7d65..b65ef1aa2 100644
--- a/CHANGELOG.md
+++ b/CHANGELOG.md
@@ -1,4 +1,5 @@
 ## Latest Changes
+ * Made the server bind address configurable and changed the default from `0.0.0.0` (all interfaces) to `127.0.0.1` (localhost only) for security. The RPC, streaming and multi-GPU listeners now honor a `ListenHost` setting, configurable via `[CARLA/Server] ListenHost` in `CarlaSettings.ini` or `--listen-host=<ip>` on the command line (use `--listen-host=0.0.0.0` to restore the previous behavior).
  * Upgraded the bundled eProsima Fast-DDS used by the native ROS 2 integration from v2.11.2 to the v2.14.6 LTS line, moving serialization onto Fast-CDR 2.x while keeping the classic XCDRv1 wire format so published topics stay compatible with every ROS 2 distribution.
  * Added Zenoh as a third ROS 2 middleware backend, selectable at runtime via `--rmw=zenoh` alongside `--rmw=fastdds` and `--rmw=cyclonedds`.
  * Added a `--ros-domain-id=<N>` server option to set the ROS2 domain ID at startup. The value (0 to 232) is stored in the middleware abstraction layer and honored by every middleware (FastDDS, CycloneDDS, and Zenoh), so future middlewares pick it up automatically. When the option is omitted, the server falls back to the `ROS_DOMAIN_ID` environment variable, and then to the default domain 0. The resolution order is: `--ros-domain-id`, then `ROS_DOMAIN_ID`, then 0.
diff --git a/Docs/foundations.md b/Docs/foundations.md
index 8d6252a58..24ea0636a 100644
--- a/Docs/foundations.md
+++ b/Docs/foundations.md
@@ -40,6 +40,9 @@ client = carla.Client('localhost', 2000)
 
 This sets up the client to communicate with a CARLA server running on `localhost`, the local machine. Alternatively, the IP address of a network machine can be used if running the client on a separate machine. The second argument is the port number. By default, the CARLA server will run on port 2000, you can alter this in the settings when you launch CARLA if necessary. 
 
+!!! Note
+    For security, the server binds its listeners (RPC, streaming and multi-GPU) to `127.0.0.1` (localhost) by default, so only clients on the same machine can connect. CARLA's RPC/streaming protocol has no authentication or encryption, so exposing it on a network grants full control of the simulation. To accept clients from other machines, launch with `--listen-host=<ip>` (e.g. `--listen-host=0.0.0.0` to listen on all interfaces) or set `ListenHost` under `[CARLA/Server]` in `CarlaSettings.ini`. When possible, prefer keeping the default and reaching a remote server through an SSH tunnel or VPN.
+
 The client object can be used for a number of functions including loading new maps, recording the simulation and initialising the traffic manager:
 
 ```py
diff --git a/LibCarla/source/carla/multigpu/router.cpp b/LibCarla/source/carla/multigpu/router.cpp
index 85fc88a9f..6b73dbcbb 100644
--- a/LibCarla/source/carla/multigpu/router.cpp
+++ b/LibCarla/source/carla/multigpu/router.cpp
@@ -27,9 +27,12 @@ void Router::Stop() {
 }
 
 Router::Router(uint16_t port) :
+  Router(std::string("0.0.0.0"), port) { }
+
+Router::Router(const std::string &address, uint16_t port) :
   _next(0) {
 
-  _endpoint = boost::asio::ip::tcp::endpoint(boost::asio::ip::make_address("0.0.0.0"), port);
+  _endpoint = boost::asio::ip::tcp::endpoint(boost::asio::ip::make_address(address), port);
   _listener = std::make_shared<carla::multigpu::Listener>(_pool.io_context(), _endpoint);
 }
 
diff --git a/LibCarla/source/carla/multigpu/router.h b/LibCarla/source/carla/multigpu/router.h
index 43bb835e3..d5850e9c8 100644
--- a/LibCarla/source/carla/multigpu/router.h
+++ b/LibCarla/source/carla/multigpu/router.h
@@ -17,6 +17,7 @@
 #include <boost/asio/ip/tcp.hpp>
 
 #include <mutex>
+#include <string>
 #include <vector>
 #include <sstream>
 #include <unordered_map>
@@ -37,6 +38,7 @@ namespace multigpu {
 
     Router(void);
     explicit Router(uint16_t port);
+    Router(const std::string &address, uint16_t port);
     ~Router();
 
     void Write(MultiGPUCommand id, Buffer &&buffer);
diff --git a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Game/CarlaEngine.cpp b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Game/CarlaEngine.cpp
index 95e852f54..009d8ad07 100644
--- a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Game/CarlaEngine.cpp
+++ b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Game/CarlaEngine.cpp
@@ -85,7 +85,7 @@ void FCarlaEngine::NotifyInitGame(const UCarlaSettings &Settings)
     const auto PrimaryIP     = Settings.PrimaryIP;
     const auto PrimaryPort   = Settings.PrimaryPort;
 
-    auto BroadcastStream     = Server.Start(Settings.RPCPort, StreamingPort, SecondaryPort);
+    auto BroadcastStream     = Server.Start(Settings.ListenHost, Settings.RPCPort, StreamingPort, SecondaryPort);
     Server.AsyncRun(FCarlaEngine_GetNumberOfThreadsForRPCServer());
 
     WorldObserver.SetStream(BroadcastStream);
diff --git a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.cpp b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.cpp
index e64e00cfe..35863d407 100644
--- a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.cpp
+++ b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.cpp
@@ -115,13 +115,13 @@ class FCarlaServer::FPimpl: public carla::rpc::RpcServerInterface
 {
 public:
 
-  FPimpl(uint16_t RPCPort, uint16_t StreamingPort, uint16_t SecondaryPort)
-    : Server(RPCPort),
-      StreamingServer(StreamingPort),
+  FPimpl(const std::string &Host, uint16_t RPCPort, uint16_t StreamingPort, uint16_t SecondaryPort)
+    : Server(Host, RPCPort),
+      StreamingServer(Host, StreamingPort),
       BroadcastStream(StreamingServer.MakeStream())
   {
     // we need to create shared_ptr from the router for some handlers to live
-    SecondaryServer = std::make_shared<carla::multigpu::Router>(SecondaryPort);
+    SecondaryServer = std::make_shared<carla::multigpu::Router>(Host, SecondaryPort);
     SecondaryServer->SetCallbacks();
     BindActions();
 
@@ -3801,16 +3801,17 @@ FCarlaServer::~FCarlaServer() {
   Stop();
 }
 
-FDataMultiStream FCarlaServer::Start(uint16_t RPCPort, uint16_t StreamingPort, uint16_t SecondaryPort)
+FDataMultiStream FCarlaServer::Start(const std::string &Host, uint16_t RPCPort, uint16_t StreamingPort, uint16_t SecondaryPort)
 {
-  Pimpl = MakeUnique<FPimpl>(RPCPort, StreamingPort, SecondaryPort);
+  Pimpl = MakeUnique<FPimpl>(Host, RPCPort, StreamingPort, SecondaryPort);
   StreamingPort = Pimpl->StreamingServer.GetLocalEndpoint().port();
   SecondaryPort = Pimpl->SecondaryServer->GetLocalEndpoint().port();
 
   UE_LOG(
       LogCarlaServer,
       Log,
-      TEXT("Initialized CarlaServer: Ports(rpc=%d, streaming=%d, secondary=%d)"),
+      TEXT("Initialized CarlaServer: Host(%s) Ports(rpc=%d, streaming=%d, secondary=%d)"),
+      *FString(Host.c_str()),
       RPCPort,
       StreamingPort,
       SecondaryPort);
diff --git a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.h b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.h
index 9e9d03284..fe001a46a 100644
--- a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.h
+++ b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Server/CarlaServer.h
@@ -32,7 +32,7 @@ public:
 
   ~FCarlaServer();
 
-  FDataMultiStream Start(uint16_t RPCPort, uint16_t StreamingPort, uint16_t SecondaryPort);
+  FDataMultiStream Start(const std::string &Host, uint16_t RPCPort, uint16_t StreamingPort, uint16_t SecondaryPort);
 
   void NotifyBeginEpisode(UCarlaEpisode &Episode);
 
diff --git a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.cpp b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.cpp
index 790bae3aa..2af772cdd 100644
--- a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.cpp
+++ b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.cpp
@@ -78,6 +78,12 @@ static void LoadSettingsFromConfig(
     ConfigFile.GetString(S_CARLA_SERVER, TEXT("PrimaryIP"), Tmp);
     Settings.PrimaryIP = TCHAR_TO_UTF8(*Tmp);
     ConfigFile.GetInt(S_CARLA_SERVER,    TEXT("PrimaryPort"), Settings.PrimaryPort);
+    FString HostTmp;
+    ConfigFile.GetString(S_CARLA_SERVER, TEXT("ListenHost"), HostTmp);
+    if (!HostTmp.IsEmpty())
+    {
+      Settings.ListenHost = TCHAR_TO_UTF8(*HostTmp);
+    }
   }
   ConfigFile.GetBool(S_CARLA_SERVER, TEXT("SynchronousMode"), Settings.bSynchronousMode);
   ConfigFile.GetBool(S_CARLA_SERVER, TEXT("DisableRendering"), Settings.bDisableRendering);
@@ -146,6 +152,11 @@ void UCarlaSettings::LoadSettings()
     {
       PrimaryPort = Value;
     }
+    FString HostTmp;
+    if (FParse::Value(FCommandLine::Get(), TEXT("-listen-host="), HostTmp))
+    {
+      ListenHost = TCHAR_TO_UTF8(*HostTmp);
+    }
     FString StringQualityLevel;
     if (FParse::Value(FCommandLine::Get(), TEXT("-quality-level="), StringQualityLevel))
     {
@@ -189,6 +200,7 @@ void UCarlaSettings::LogSettings() const
       TEXT("== CARLA Settings =============================================================="));
   UE_LOG(LogCarla, Log, TEXT("Last settings file loaded: %s"), *CurrentFileName);
   UE_LOG(LogCarla, Log, TEXT("[%s]"), S_CARLA_SERVER);
+  UE_LOG(LogCarla, Log, TEXT("Listen Host = %s"), *FString(ListenHost.c_str()));
   UE_LOG(LogCarla, Log, TEXT("RPC Port = %d"), RPCPort);
   UE_LOG(LogCarla, Log, TEXT("Streaming Port = %d"), StreamingPort);
   UE_LOG(LogCarla, Log, TEXT("Secondary Port = %d"), SecondaryPort);
diff --git a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.h b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.h
index 1b4b16214..111d1a685 100644
--- a/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.h
+++ b/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Settings/CarlaSettings.h
@@ -78,6 +78,12 @@ private:
 
 public:
 
+  /// IP/host the server binds its listeners (RPC, streaming, multi-GPU) to.
+  /// Default 127.0.0.1 (localhost only) for security. Set to 0.0.0.0 to listen
+  /// on all interfaces. Configurable via [CARLA/Server] ListenHost in the INI
+  /// file or --listen-host=<ip> on the command line.
+  std::string ListenHost = "127.0.0.1";
+
   /// World port to listen for client connections.
   UPROPERTY(Category = "CARLA Server", VisibleAnywhere, meta = (EditCondition = bUseNetworking))
   uint32 RPCPort = 2000u;
diff --git a/Util/BuildTools/BuildCarlaUE4.sh b/Util/BuildTools/BuildCarlaUE4.sh
index 1b26351e0..1aafd9fc3 100755
--- a/Util/BuildTools/BuildCarlaUE4.sh
+++ b/Util/BuildTools/BuildCarlaUE4.sh
@@ -6,7 +6,7 @@
 
 DOC_STRING="Build and launch CarlaUE4."
 
-USAGE_STRING="Usage: $0 [-h|--help] [--build] [--rebuild] [--launch] [--clean] [--hard-clean] [--opengl] [--chrono] [--chrono-path=PATH] [--ros2] [--rmw=MIDDLEWARE] [--ros-domain-id=N]"
+USAGE_STRING="Usage: $0 [-h|--help] [--build] [--rebuild] [--launch] [--clean] [--hard-clean] [--opengl] [--chrono] [--chrono-path=PATH] [--ros2] [--rmw=MIDDLEWARE] [--ros-domain-id=N] [--listen-host=IP]"
 
 REMOVE_INTERMEDIATE=false
 HARD_CLEAN=false
@@ -24,13 +24,16 @@ RMW=""
 # does not shadow the standard ROS_DOMAIN_ID environment variable, which the
 # launched editor reads as a fallback when --ros-domain-id is not given.
 ROS_DOMAIN_ID_ARG=""
+# Holds the value of --listen-host (the IP/host the server binds its listeners
+# to). Empty leaves the editor/CarlaSettings default (127.0.0.1).
+LISTEN_HOST=""
 
 EDITOR_FLAGS=""
 
 GDB=
 RHI="-vulkan"
 
-OPTS=`getopt -o h --long help,build,rebuild,launch,clean,hard-clean,gdb,opengl,carsim,pytorch,chrono,chrono-path:,ros2,rmw:,ros-domain-id:,no-simready,no-unity,editor-flags: -n 'parse-options' -- "$@"`
+OPTS=`getopt -o h --long help,build,rebuild,launch,clean,hard-clean,gdb,opengl,carsim,pytorch,chrono,chrono-path:,ros2,rmw:,ros-domain-id:,listen-host:,no-simready,no-unity,editor-flags: -n 'parse-options' -- "$@"`
 
 eval set -- "$OPTS"
 
@@ -84,6 +87,9 @@ while [[ $# -gt 0 ]]; do
     --ros-domain-id )
       ROS_DOMAIN_ID_ARG=$2;
       shift 2 ;;
+    --listen-host )
+      LISTEN_HOST=$2;
+      shift 2 ;;
     --no-simready )
       USE_SIMREADY=false
       shift ;;
@@ -112,6 +118,9 @@ fi
 if [ -n "${ROS_DOMAIN_ID_ARG}" ] ; then
   EDITOR_FLAGS="${EDITOR_FLAGS} --ros-domain-id=${ROS_DOMAIN_ID_ARG}"
 fi
+if [ -n "${LISTEN_HOST}" ] ; then
+  EDITOR_FLAGS="${EDITOR_FLAGS} --listen-host=${LISTEN_HOST}"
+fi
 
 # ==============================================================================
 # -- Set up environment --------------------------------------------------------
-- 
2.34.1


From 8706769cf84dbb0ff920c017e6df66981ac82d5a Mon Sep 17 00:00:00 2001
From: carlagx <carlagx@gmx.net>
Date: Tue, 23 Jun 2026 00:35:13 +0200
Subject: [PATCH 2/2] feat(trafficmanager): bind the Traffic Manager RPC server
 to localhost

The Traffic Manager RPC server bound to 0.0.0.0 (all interfaces) via
::rpc::server(port), even though the address it advertises to clients
(GetLocalIP/AddTrafficManagerRunning) is already the loopback address and
the protocol has no authentication or encryption. Bind it explicitly to
127.0.0.1 so it is not exposed on the network, consistent with the
server's localhost ListenHost default.

Verified: LibCarla client (which compiles the traffic manager) builds and
links cleanly with the change.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
---
 .../source/carla/trafficmanager/TrafficManagerServer.h     | 7 +++++--
 1 file changed, 5 insertions(+), 2 deletions(-)

diff --git a/LibCarla/source/carla/trafficmanager/TrafficManagerServer.h b/LibCarla/source/carla/trafficmanager/TrafficManagerServer.h
index 94352d024..514e04097 100644
--- a/LibCarla/source/carla/trafficmanager/TrafficManagerServer.h
+++ b/LibCarla/source/carla/trafficmanager/TrafficManagerServer.h
@@ -45,8 +45,11 @@ public:
     while(counter < MIN_TRY_COUNT) {
       try {
 
-        /// Create server instance.
-        server = new ::rpc::server(RPCPort);
+        /// Create server instance. Bind to localhost only: the TM RPC has no
+        /// authentication or encryption, and the address advertised to clients
+        /// via GetLocalIP()/AddTrafficManagerRunning() is already the loopback
+        /// address, so it must not listen on all interfaces.
+        server = new ::rpc::server("127.0.0.1", RPCPort);
 
       } catch(std::exception) {
         using namespace std::chrono_literals;
-- 
2.34.1

FIX_PATCH_EOF

echo ">> Applying localhost-bind security fix (2 commits) via 'git am --3way' ..."
if git am --3way "$PATCH_FILE"; then
  echo
  echo ">> Success. Added commits:"
  git log --oneline -2
else
  git am --abort 2>/dev/null || true
  echo "ERROR: git am failed -- upstream ue4-dev likely drifted from the patch base." >&2
  echo "       Resolve conflicts manually, or apply to the working tree only with:" >&2
  echo "         git apply --3way <patch>   (the patch is embedded in this script)" >&2
  exit 1
fi

echo
echo ">> Rebuild to apply the change:  make launch   (or: make PythonAPI / make CarlaUE4Editor)"
echo ">> The server now binds to 127.0.0.1 by default."
echo ">> For external access: --listen-host=<ip> (e.g. 0.0.0.0) on the command line,"
echo "   or set 'ListenHost' under [CARLA/Server] in CarlaSettings.ini."
