#!/usr/bin/env bash
# CARLA / Unreal Engine 4 Treiber- & Umgebungs-Check (Ubuntu)
# Nutzung: ./check-drivers.sh [-r REPORT.txt] [-j] [-v] [-t] [-h]
#   -r  Report zusätzlich in Datei schreiben (ohne Farben)
#   -j  Nur Zusammenfassung als JSON ausgeben
#   -v  Verbose: zusätzliche Rohdaten (vulkaninfo, glxinfo, Kernel-Logs)
#   -t  Kurzer Funktionstest (vkcube/glxgears, Vulkan-Device-Enumeration)
# Exit-Code: 0 = alles OK, 1 = Warnungen, 2 = Fehler

REPORT=""; JSON=0; VERBOSE=0; TEST=0
UE_ROOT="${UE4_ROOT:-$HOME/UnrealEngine_4.26}"
CARLA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while getopts "r:jvth" opt; do
  case $opt in
    r) REPORT=$OPTARG ;;
    j) JSON=1 ;;
    v) VERBOSE=1 ;;
    t) TEST=1 ;;
    *) sed -n '2,8p' "$0"; exit 0 ;;
  esac
done

if [ -t 1 ] && [ -z "$REPORT" ]; then
  G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; B=$'\e[1m'; N=$'\e[0m'
else
  G=""; Y=""; R=""; B=""; N=""
fi

OK=0; WARN=0; FAIL=0
declare -a FIXES=() RESULTS=()

out() { if [ "$JSON" = 0 ]; then if [ -n "$REPORT" ]; then echo -e "$*" | tee -a "$REPORT"; else echo -e "$*"; fi; fi; }
hdr() { out "\n${B}== $* ==${N}"; }
ok()   { OK=$((OK+1));     RESULTS+=("ok|$1");   out "  ${G}[OK]${N}   $1"; }
warn() { WARN=$((WARN+1)); RESULTS+=("warn|$1"); out "  ${Y}[WARN]${N} $1"; [ -n "$2" ] && FIXES+=("$2"); }
fail() { FAIL=$((FAIL+1)); RESULTS+=("fail|$1"); out "  ${R}[FAIL]${N} $1"; [ -n "$2" ] && FIXES+=("$2"); }
info() { out "         $*"; }
have() { command -v "$1" >/dev/null 2>&1; }
pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
vercmp_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; } # $1 >= $2

[ -n "$REPORT" ] && : > "$REPORT"

# ---------------------------------------------------------------- System
hdr "System"
. /etc/os-release 2>/dev/null
KERNEL=$(uname -r)
info "OS: ${PRETTY_NAME:-unbekannt}  | Kernel: $KERNEL  | Arch: $(uname -m)"
info "CPU: $(lscpu 2>/dev/null | awk -F: '/Model name/{gsub(/^ +/,"",$2);print $2}')"
info "RAM: $(free -g | awk '/Mem:/{print $2" GB (frei: "$7" GB)"}')  | Swap: $(free -g | awk '/Swap:/{print $2" GB"}')"
case "${VERSION_ID:-}" in
  18.04|20.04|22.04) ok "Ubuntu $VERSION_ID (von CARLA/UE4.26 unterstützt)" ;;
  *) warn "Ubuntu ${VERSION_ID:-?} – UE4.26/CARLA offiziell getestet mit 18.04/20.04/22.04" "" ;;
esac
[ "$(uname -m)" = x86_64 ] && ok "Architektur x86_64" || fail "Architektur $(uname -m) wird nicht unterstützt" ""
[ "${XDG_SESSION_TYPE:-}" = wayland ] && warn "Wayland-Session aktiv – UE4 läuft stabiler unter X11" "Beim Login 'Ubuntu on Xorg' wählen oder SDL_VIDEODRIVER=x11 setzen"
[ -n "${XDG_SESSION_TYPE:-}" ] && info "Session: $XDG_SESSION_TYPE  DISPLAY=${DISPLAY:-<leer>}"
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  warn "Kein DISPLAY gesetzt (headless?) – Server nur mit -RenderOffScreen nutzbar" ""
fi

# ---------------------------------------------------------------- GPU-Hardware
hdr "GPU-Hardware"
if have lspci; then
  GPUS=$(lspci -nn | grep -Ei 'vga|3d controller|display controller')
  [ -n "$GPUS" ] && while IFS= read -r l; do info "$l"; done <<< "$GPUS" || warn "Keine GPU per lspci gefunden" ""
  HAS_NVIDIA=$(echo "$GPUS" | grep -ci nvidia)
  HAS_OTHER=$(echo "$GPUS" | grep -Eci 'intel corp|advanced micro|\bamd\b|\bati\b')
  [ "$HAS_NVIDIA" -gt 0 ] && ok "NVIDIA-GPU erkannt ($HAS_NVIDIA)" || fail "Keine NVIDIA-GPU erkannt (CARLA benötigt i.d.R. NVIDIA)" ""
  [ "$HAS_NVIDIA" -gt 0 ] && [ "$HAS_OTHER" -gt 0 ] && info "Hybrid-System (iGPU + NVIDIA) – PRIME-Offload beachten"
else
  warn "lspci fehlt" "sudo apt install pciutils"
fi

# ---------------------------------------------------------------- NVIDIA-Treiber
hdr "NVIDIA-Treiber"
DRV=""
if have nvidia-smi && nvidia-smi >/dev/null 2>&1; then
  DRV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
  ok "nvidia-smi funktioniert – Treiber $DRV"
  nvidia-smi --query-gpu=index,name,memory.total,compute_cap,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,temperature.gpu,persistence_mode --format=csv,noheader 2>/dev/null \
    | while IFS= read -r l; do info "GPU: $l"; done
  VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
  if [ "${VRAM:-0}" -ge 8000 ]; then ok "VRAM ${VRAM} MiB (>= 8 GB empfohlen)"
  elif [ "${VRAM:-0}" -ge 6000 ]; then warn "VRAM ${VRAM} MiB – knapp, Low-Quality-Modus (-quality-level=Low) nutzen" ""
  else fail "VRAM ${VRAM} MiB – zu wenig für CARLA" ""; fi
  vercmp_ge "$DRV" 450 && ok "Treiberversion >= 450 (Vulkan-Mindestanforderung)" \
    || warn "Treiber $DRV ist alt (>= 450 empfohlen)" "sudo ubuntu-drivers autoinstall"
  PM=$(nvidia-smi --query-gpu=persistence_mode --format=csv,noheader | head -1)
  if [ "$PM" = Enabled ]; then ok "Persistence-Mode aktiv"
  else warn "Persistence-Mode aus – erhöht Startlatenz" "sudo nvidia-smi -pm 1"; fi
  CUDA_V=$(nvidia-smi | sed -n 's/.*CUDA Version: \([0-9.]*\).*/\1/p' | head -1)
  [ -n "$CUDA_V" ] && info "Max. unterstützte CUDA-Version (Treiber): $CUDA_V"
else
  if have nvidia-smi; then
    fail "nvidia-smi schlägt fehl (Kernelmodul nicht geladen / Versionskonflikt?)" "sudo dmesg | grep -i nvrm; Reboot oder: sudo apt install --reinstall nvidia-driver-<VERSION>"
    have nvidia-smi && info "$(nvidia-smi 2>&1 | head -2 | tr '\n' ' ')"
  else
    fail "nvidia-smi nicht gefunden – kein NVIDIA-Treiber installiert" "ubuntu-drivers devices && sudo ubuntu-drivers autoinstall && sudo reboot"
  fi
fi

# Kernelmodule
if lsmod | grep -q '^nvidia '; then
  ok "Kernelmodul nvidia geladen"
  lsmod | grep -q '^nvidia_drm' && ok "nvidia_drm geladen" || warn "nvidia_drm nicht geladen" ""
  MODV=$(cat /sys/module/nvidia/version 2>/dev/null)
  [ -n "$MODV" ] && info "Kernelmodul-Version: $MODV"
  if [ -n "$MODV" ] && [ -n "$DRV" ] && [ "$MODV" != "$DRV" ]; then
    fail "Version Kernelmodul ($MODV) != Userspace-Treiber ($DRV) – Reboot nötig" "sudo reboot"
  fi
  if [ -r /sys/module/nvidia_drm/parameters/modeset ]; then
    [ "$(cat /sys/module/nvidia_drm/parameters/modeset)" = Y ] && info "nvidia-drm.modeset=Y" || info "nvidia-drm.modeset=N (für Wayland/PRIME-Sync nötig: nvidia-drm.modeset=1)"
  fi
else
  have nvidia-smi && fail "Kernelmodul nvidia nicht geladen" "sudo modprobe nvidia || DKMS prüfen: dkms status"
fi
lsmod | grep -q '^nouveau' && fail "nouveau-Treiber aktiv (Konflikt mit NVIDIA)" "echo -e 'blacklist nouveau\noptions nouveau modeset=0' | sudo tee /etc/modprobe.d/blacklist-nouveau.conf && sudo update-initramfs -u && sudo reboot"

# Secure Boot / DKMS
if have mokutil; then
  SB=$(mokutil --sb-state 2>&1 | head -1)
  info "Secure Boot: $SB"
  echo "$SB" | grep -qi enabled && ! lsmod | grep -q '^nvidia ' && warn "Secure Boot aktiv – unsignierte NVIDIA-Module werden blockiert" "MOK enrollen (sudo mokutil --import /var/lib/shim-signed/mok/MOK.der) oder Secure Boot deaktivieren"
fi
if have dkms; then
  DK=$(dkms status 2>/dev/null | grep -i nvidia)
  if [ -n "$DK" ]; then
    while IFS= read -r l; do info "DKMS: $l"; done <<< "$DK"
    echo "$DK" | grep -qi "$KERNEL.*installed" || echo "$DK" | grep -qi installed || warn "DKMS-Modul für Kernel $KERNEL evtl. nicht gebaut" "sudo dkms autoinstall"
  fi
fi
# Installierte Pakete
NVPKGS=$(dpkg -l 2>/dev/null | awk '/^ii/ && $2 ~ /^(nvidia-driver|nvidia-dkms|nvidia-utils|libnvidia-gl|nvidia-kernel)/ {print $2"="$3}')
if [ -n "$NVPKGS" ]; then
  NVMAJ=$(echo "$NVPKGS" | grep -o 'nvidia-[a-z-]*-[0-9]\{3\}' | grep -o '[0-9]\{3\}$' | sort -u)
  [ "$(echo "$NVMAJ" | wc -w)" -gt 1 ] && warn "Mehrere NVIDIA-Treiber-Hauptversionen installiert: $(echo $NVMAJ)" "sudo apt purge 'nvidia-*' 'libnvidia-*' && sudo ubuntu-drivers autoinstall"
  [ "$VERBOSE" = 1 ] && echo "$NVPKGS" | while read -r p; do info "pkg: $p"; done
fi
have ubuntu-drivers && { REC=$(ubuntu-drivers devices 2>/dev/null | grep recommended | awk '{print $3}'); [ -n "$REC" ] && info "Empfohlener Ubuntu-Treiber: $REC"; }
have prime-select && info "prime-select: $(prime-select query 2>/dev/null)"

# ---------------------------------------------------------------- Vulkan
hdr "Vulkan (UE4 -vulkan / CARLA)"
if have vulkaninfo; then
  VKS=$(vulkaninfo --summary 2>&1)
  if echo "$VKS" | grep -q deviceName; then
    ok "Vulkan funktioniert"
    echo "$VKS" | grep -E 'deviceName|deviceType|apiVersion|driverName' | while IFS= read -r l; do info "$l"; done
    echo "$VKS" | grep deviceName | grep -qi nvidia && ok "NVIDIA-GPU als Vulkan-Device sichtbar" || warn "NVIDIA nicht als Vulkan-Device sichtbar" "ls /usr/share/vulkan/icd.d/ /etc/vulkan/icd.d/; sudo apt install libnvidia-gl-<VERSION>"
    echo "$VKS" | grep -qi llvmpipe && info "llvmpipe (CPU-Fallback) ist gelistet – harmlos, solange UE4 die NVIDIA-GPU wählt"
  else
    fail "vulkaninfo liefert keine Geräte" "sudo apt install libvulkan1 vulkan-tools libnvidia-gl-<VERSION>; ICD prüfen"
    [ "$VERBOSE" = 1 ] && echo "$VKS" | head -15 | while IFS= read -r l; do info "$l"; done
  fi
else
  fail "vulkaninfo fehlt" "sudo apt install vulkan-tools libvulkan1"
fi
pkg_installed libvulkan1 && ok "libvulkan1 installiert" || fail "libvulkan1 fehlt" "sudo apt install libvulkan1"
ICDS=$(ls /usr/share/vulkan/icd.d/*.json /etc/vulkan/icd.d/*.json 2>/dev/null)
if [ -n "$ICDS" ]; then
  for f in $ICDS; do info "ICD: $f"; done
  ls $ICDS 2>/dev/null | grep -qi nvidia && ok "NVIDIA Vulkan-ICD vorhanden" || warn "Kein nvidia_icd.json gefunden" "sudo apt install libnvidia-gl-<VERSION>"
else
  fail "Keine Vulkan-ICD-Dateien gefunden" "sudo apt install libnvidia-gl-<VERSION> mesa-vulkan-drivers"
fi
[ -n "${VK_ICD_FILENAMES:-}${VK_DRIVER_FILES:-}" ] && info "VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-} VK_DRIVER_FILES=${VK_DRIVER_FILES:-}"
have vkcube || info "Tipp: sudo apt install vulkan-tools (vkcube) für Sichttest"
[ "$VERBOSE" = 1 ] && have vulkaninfo && { info "--- vulkaninfo (Auszug) ---"; vulkaninfo 2>&1 | head -40 | while IFS= read -r l; do info "$l"; done; }

# ---------------------------------------------------------------- OpenGL / X
hdr "OpenGL / X11"
if have glxinfo; then
  GL=$(glxinfo -B 2>/dev/null)
  if [ -n "$GL" ]; then
    RENDERER=$(echo "$GL" | awk -F': ' '/OpenGL renderer/{print $2}')
    info "OpenGL renderer: $RENDERER"
    info "OpenGL version:  $(echo "$GL" | awk -F': ' '/OpenGL version/{print $2}')"
    echo "$RENDERER" | grep -Eqi 'llvmpipe|software' && warn "Software-Rendering (llvmpipe) aktiv" "PRIME: __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -B"
    echo "$RENDERER" | grep -qi nvidia && ok "OpenGL läuft auf NVIDIA" || info "OpenGL läuft nicht auf NVIDIA (bei Hybrid-Laptops ggf. Offload nötig)"
  else
    warn "glxinfo liefert nichts (kein X-Display?)" ""
  fi
else
  warn "glxinfo fehlt" "sudo apt install mesa-utils"
fi
[ -n "${DISPLAY:-}" ] && have xrandr && info "Displays: $(xrandr --query 2>/dev/null | grep ' connected' | awk '{print $1}' | tr '\n' ' ')"

# ---------------------------------------------------------------- CUDA / cuDNN
hdr "CUDA (optional, für ML/Sensor-Pipelines)"
if have nvcc; then
  NVCC_V=$(nvcc --version | sed -n 's/.*release \([0-9.]*\).*/\1/p')
  ok "CUDA-Toolkit (nvcc) $NVCC_V"
  [ -n "$CUDA_V" ] && ! vercmp_ge "$CUDA_V" "$NVCC_V" && fail "Toolkit $NVCC_V neuer als Treiber-CUDA $CUDA_V" "Treiber aktualisieren"
else
  info "nvcc nicht gefunden (für CARLA-Server nicht nötig)"
fi
ls -d /usr/local/cuda* 2>/dev/null | while IFS= read -r d; do info "CUDA-Dir: $d"; done
pkg_installed nvidia-cuda-toolkit && info "nvidia-cuda-toolkit (Ubuntu-Paket) installiert"
if ldconfig -p 2>/dev/null | grep -q libcudnn; then ok "cuDNN gefunden"; else info "cuDNN nicht gefunden (nur für PyTorch/TF mit System-CUDA relevant)"; fi
have python3 && python3 - <<'PY' 2>/dev/null | while IFS= read -r l; do info "$l"; done
try:
    import torch
    print("PyTorch %s, CUDA verfügbar: %s" % (torch.__version__, torch.cuda.is_available()))
except Exception: pass
PY

# ---------------------------------------------------------------- Unreal Engine 4.26
hdr "Unreal Engine 4.26"
if [ -d "$UE_ROOT" ]; then
  ok "UE4 gefunden: $UE_ROOT"
  [ -x "$UE_ROOT/Engine/Binaries/Linux/UE4Editor" ] && ok "UE4Editor gebaut" || warn "UE4Editor-Binary fehlt (Engine nicht gebaut?)" "cd $UE_ROOT && make"
  if [ -f "$UE_ROOT/Engine/Build/Build.version" ]; then
    UEV=$(sed -n 's/.*"MajorVersion": *\([0-9]*\).*/\1/p;s/.*"MinorVersion": *\([0-9]*\).*/.\1/p;s/.*"PatchVersion": *\([0-9]*\).*/.\1/p' "$UE_ROOT/Engine/Build/Build.version" | tr -d '\n')
    info "Engine-Version: $UEV"
    [ "${UEV%.*}" = "4.26" ] && ok "Engine-Version 4.26 (passend zu CARLA)" || warn "Engine-Version $UEV – CARLA erwartet 4.26.x (CARLA-Fork)" ""
  fi
  [ -d "$UE_ROOT/Engine/Extras/ThirdPartyNotUE/SDKs/HostLinux/Linux_x64" ] && ok "UE4 Linux-Toolchain (clang) vorhanden" || warn "UE4-Toolchain nicht im Engine-Ordner" "cd $UE_ROOT && ./Setup.sh"
else
  fail "UE4-Verzeichnis $UE_ROOT nicht gefunden" "export UE4_ROOT=/pfad/zu/UnrealEngine_4.26"
fi
[ -n "${UE4_ROOT:-}" ] && ok "UE4_ROOT=$UE4_ROOT" || warn "Umgebungsvariable UE4_ROOT nicht gesetzt" "echo 'export UE4_ROOT=$UE_ROOT' >> ~/.bashrc"

# ---------------------------------------------------------------- Build-Toolchain
hdr "Build-Toolchain (CARLA / UE4)"
for t in git make cmake ninja python3 pip3 curl wget unzip rsync; do
  have $t && ok "$t: $($t --version 2>&1 | head -1 | cut -c1-60)" || warn "$t fehlt" "sudo apt install $t"
done
have clang && info "clang: $(clang --version | head -1)"
have clang-8 && ok "clang-8 vorhanden (CARLA/UE4.26 Standard)" || info "clang-8 nicht im PATH (CARLA nutzt UE4-eigenes clang oder clang-8)"
have g++ && info "g++: $(g++ --version | head -1)"
have cmake && ! vercmp_ge "$(cmake --version | awk 'NR==1{print $3}')" 3.13 && warn "cmake < 3.13" "pip3 install --user cmake"
have mono && info "mono: $(mono --version | head -1)" || info "mono nicht gefunden (UE4 bringt eigenes Mono mit)"
for p in libpng-dev libjpeg-dev libtiff5-dev libxml2-dev libsdl2-2.0-0 libxerces-c-dev build-essential; do
  pkg_installed "$p" || { dpkg -l 2>/dev/null | grep -q "^ii  ${p%-dev}" && continue; info "Paket fehlt (ggf. optional): $p"; }
done
have python3 && python3 -c "import carla" 2>/dev/null && ok "Python-Modul 'carla' importierbar" || info "Python-Modul 'carla' nicht installiert (PythonAPI bauen: make PythonAPI)"

# ---------------------------------------------------------------- CARLA
hdr "CARLA"
[ -d "$CARLA_ROOT/Unreal/CarlaUE4" ] && ok "CARLA-Repo: $CARLA_ROOT" || warn "Unreal/CarlaUE4 nicht im Skriptordner" ""
if [ -f "$CARLA_ROOT/Unreal/CarlaUE4/CarlaUE4.uproject" ]; then
  info "EngineAssociation: $(sed -n 's/.*"EngineAssociation": *"\([^"]*\)".*/\1/p' "$CARLA_ROOT/Unreal/CarlaUE4/CarlaUE4.uproject")"
fi
[ -d "$CARLA_ROOT/Unreal/CarlaUE4/Plugins/Carla/CarlaDependencies" ] && ok "CarlaDependencies gebaut" || warn "CarlaDependencies fehlen (LibCarla nicht gebaut)" "make LibCarla"
[ -d "$CARLA_ROOT/Unreal/CarlaUE4/Content/Carla" ] && ok "CARLA-Content vorhanden" || warn "CARLA-Content fehlt" "make import / ./Update.sh"
ls "$CARLA_ROOT"/PythonAPI/carla/dist/*.whl "$CARLA_ROOT"/PythonAPI/carla/dist/*.egg >/dev/null 2>&1 && ok "PythonAPI-Paket gebaut" || info "PythonAPI-Paket noch nicht gebaut"
PKGD=$(ls -d "$CARLA_ROOT"/Dist/*/ 2>/dev/null | head -1); [ -n "$PKGD" ] && info "Package: $PKGD"
if pgrep -fa CarlaUE4 >/dev/null; then
  ok "CARLA-Server läuft (PID $(pgrep -f CarlaUE4 | head -1))"
  ss -ltn 2>/dev/null | grep -q ':2000 ' && ok "Port 2000 lauscht" || info "Server läuft, Port 2000 lauscht (noch) nicht – evtl. startet er noch / anderer -carla-rpc-port"
else
  info "CARLA-Server läuft aktuell nicht"
fi

# ---------------------------------------------------------------- Audio/Input/Limits
hdr "Sonstiges (Limits, Platz, Netzwerk)"
ULIM=$(ulimit -n); [ "$ULIM" -ge 4096 ] && ok "ulimit -n = $ULIM" || warn "ulimit -n = $ULIM (UE4 braucht >= 4096)" "ulimit -n 10240 oder /etc/security/limits.conf anpassen"
MMC=$(cat /proc/sys/vm/max_map_count 2>/dev/null); [ "${MMC:-0}" -ge 262144 ] && ok "vm.max_map_count=$MMC" || warn "vm.max_map_count=$MMC (UE4 empfiehlt >= 262144)" "sudo sysctl -w vm.max_map_count=262144"
FREE=$(df -BG --output=avail "$CARLA_ROOT" | tail -1 | tr -dc 0-9)
[ "${FREE:-0}" -ge 50 ] && ok "Freier Platz: ${FREE} GB" || warn "Freier Platz nur ${FREE} GB (UE4+CARLA-Build ~150 GB)" ""
have ss && info "Belegte Ports 2000-2002: $(ss -ltn 2>/dev/null | grep -E ':200[0-2] ' | wc -l)"
id -nG | grep -qwE 'video|render' && ok "Benutzer in Gruppe video/render" || info "Benutzer nicht in Gruppe video/render – unter Desktop-Login meist unkritisch (logind-ACLs), bei SSH/headless: sudo usermod -aG video,render \$USER"
if [ -e /dev/nvidiactl ]; then ok "/dev/nvidiactl vorhanden"; elif have nvidia-smi; then warn "/dev/nvidiactl fehlt" ""; fi
if [ -e /dev/dri ]; then info "DRI-Geräte: $(ls /dev/dri | tr '\n' ' ')"; fi
if have docker; then if docker info 2>/dev/null | grep -qi nvidia; then ok "Docker nvidia-runtime verfügbar"; else info "Docker vorhanden, nvidia-container-toolkit nicht erkannt (nur für CARLA-Docker nötig)"; fi; fi

# ---------------------------------------------------------------- Kernel-Logs
hdr "Kernel-Logs (NVIDIA)"
if LOGS=$(dmesg 2>/dev/null | grep -Ei 'nvrm|nvidia|xid' | tail -8) && [ -n "$LOGS" ]; then
  echo "$LOGS" | grep -qi 'xid' && warn "GPU-Xid-Fehler im Kernel-Log (Hardware/Treiber-Crash)" "sudo dmesg | grep -i xid; Treiber/Temperatur/Netzteil prüfen"
  [ "$VERBOSE" = 1 ] && echo "$LOGS" | while IFS= read -r l; do info "$l"; done
  echo "$LOGS" | grep -qi 'xid' || ok "Keine Xid-Fehler in den letzten NVIDIA-Logzeilen"
else
  info "dmesg nicht lesbar (sudo ./check-drivers.sh -v für Kernel-Logs)"
fi
LATEST_CRASH=$(ls -t "$CARLA_ROOT"/Unreal/CarlaUE4/Saved/Crashes 2>/dev/null | head -1)
[ -n "$LATEST_CRASH" ] && info "Letzter UE4-Crash: Unreal/CarlaUE4/Saved/Crashes/$LATEST_CRASH"

# ---------------------------------------------------------------- Funktionstest
if [ "$TEST" = 1 ]; then
  hdr "Funktionstests (-t)"
  if have vulkaninfo; then
    NDEV=$(vulkaninfo --summary 2>/dev/null | grep -c deviceName)
    [ "$NDEV" -gt 0 ] && ok "Vulkan-Instanz + $NDEV Device(s) erstellbar" || fail "Vulkan-Instanz fehlgeschlagen" ""
  fi
  if have vkcube && [ -n "${DISPLAY:-}" ]; then
    timeout 4 vkcube --c 60 >/dev/null 2>&1; RC=$?
    { [ $RC -eq 0 ] || [ $RC -eq 124 ]; } && ok "vkcube lief ohne Absturz" || fail "vkcube fehlgeschlagen (rc=$RC)" ""
  fi
  if have glxgears && [ -n "${DISPLAY:-}" ]; then
    timeout 3 glxgears 2>&1 | tail -1 | while IFS= read -r l; do info "glxgears: $l"; done
  fi
  if have nvidia-smi; then
    nvidia-smi -q -d PERFORMANCE 2>/dev/null | grep -A8 'Clocks Throttle\|Clocks Event' | grep -i active | grep -qi 'Active' \
      && info "Throttle-Gründe: $(nvidia-smi -q -d PERFORMANCE | grep -i ': Active' | tr -s ' ' | tr '\n' ';')"
  fi
fi

# ---------------------------------------------------------------- Zusammenfassung
if [ "$JSON" = 1 ]; then
  printf '{"ok":%d,"warn":%d,"fail":%d,"driver":"%s","kernel":"%s","checks":[' "$OK" "$WARN" "$FAIL" "${DRV:-}" "$KERNEL"
  first=1; for r in "${RESULTS[@]}"; do
    [ $first = 0 ] && printf ','; first=0
    msg=${r#*|}; msg=${msg//\\/\\\\}; msg=${msg//\"/\\\"}
    printf '{"status":"%s","msg":"%s"}' "${r%%|*}" "$msg"
  done; printf ']}\n'
else
  hdr "Zusammenfassung"
  out "  ${G}OK: $OK${N}   ${Y}Warnungen: $WARN${N}   ${R}Fehler: $FAIL${N}"
  if [ ${#FIXES[@]} -gt 0 ]; then
    out "\n${B}Lösungsvorschläge:${N}"
    printf '%s\n' "${FIXES[@]}" | awk '!s[$0]++' | while IFS= read -r f; do out "  → $f"; done
  fi
  out "\nStart-Tipps:"
  out "  Hybrid-Laptop:  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ./CarlaUE4.sh -vulkan"
  out "  Headless:       ./CarlaUE4.sh -RenderOffScreen -nosound"
  out "  Monitoring:     ./monitor-carla-gpu.sh -l gpu.csv"
  [ -n "$REPORT" ] && out "\nReport gespeichert: $REPORT"
fi

[ "$FAIL" -gt 0 ] && exit 2
[ "$WARN" -gt 0 ] && exit 1
exit 0
