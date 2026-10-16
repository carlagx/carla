#!/usr/bin/env bash
# CARLA Server GPU/Performance Monitor
# Nutzung: ./monitor-carla-gpu.sh [-i SEKUNDEN] [-l LOGDATEI.csv] [-p PROZESSNAME]
#   -i  Intervall (Standard 2)
#   -l  CSV-Log schreiben (optional)
#   -p  Prozessmuster (Standard: CarlaUE4)

INTERVAL=2
LOGFILE=""
PATTERN="CarlaUE4"

while getopts "i:l:p:h" opt; do
  case $opt in
    i) INTERVAL=$OPTARG ;;
    l) LOGFILE=$OPTARG ;;
    p) PATTERN=$OPTARG ;;
    *) sed -n '2,6p' "$0"; exit 0 ;;
  esac
done

command -v nvidia-smi >/dev/null || { echo "nvidia-smi nicht gefunden (NVIDIA-Treiber installiert?)"; exit 1; }

echo "== GPU =="
nvidia-smi --query-gpu=index,name,driver_version --format=csv,noheader
echo
echo "== Renderer-Check =="
echo "PRIME offload: __NV_PRIME_RENDER_OFFLOAD=${__NV_PRIME_RENDER_OFFLOAD:-nicht gesetzt}  __GLX_VENDOR_LIBRARY_NAME=${__GLX_VENDOR_LIBRARY_NAME:-nicht gesetzt}"
command -v prime-select >/dev/null && echo "prime-select: $(prime-select query 2>/dev/null)"
command -v vulkaninfo >/dev/null && vulkaninfo --summary 2>/dev/null | grep -E "deviceName|deviceType" | head -4
echo "Tipp: Bei Hybrid-Laptops Server starten mit:"
echo "  __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ./CarlaUE4.sh -vulkan"
echo

[ -n "$LOGFILE" ] && [ ! -s "$LOGFILE" ] && \
  echo "time,pid,gpu_util_%,mem_util_%,vram_used_MB,vram_total_MB,temp_C,power_W,sm_clock_MHz,gpu_proc_vram_MB,cpu_%,rss_MB" > "$LOGFILE"

trap 'echo; echo "Beendet."; exit 0' INT TERM

while true; do
  # Bevorzugt der Prozess, den nvidia-smi auf der GPU sieht (auch bei Docker, wo
  # `docker run ... CarlaUE4.sh` und bash-Wrapper sonst zuerst von pgrep -f gefunden werden).
  PID=$(nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader 2>/dev/null \
        | awk -F', *' -v pat="$PATTERN" '$2 ~ pat {print $1; exit}')
  # Fallback: Prozessname (nicht Kommandozeile), Wrapper wie docker/bash ausschließen
  [ -z "$PID" ] && PID=$(pgrep -f "$PATTERN" | while read -r p; do
      case "$(ps -p "$p" -o comm= 2>/dev/null)" in docker|bash|sh|docker-proxy) ;; *) echo "$p"; break ;; esac
    done)
  TS=$(date +%H:%M:%S)

  read -r GUTIL MUTIL VUSED VTOTAL TEMP PWR CLK < <(
    nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw,clocks.sm \
      --format=csv,noheader,nounits | head -1 | tr -d ',' )

  if [ -n "$PID" ]; then
    # VRAM des CARLA-Prozesses (Compute + Graphics)
    PVRAM=$(nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null \
            | awk -F', *' -v p="$PID" '$1==p{print $2}')
    if [ -z "$PVRAM" ]; then
      PVRAM=$(nvidia-smi 2>/dev/null | awk -v p="$PID" '$0 ~ " "p" " {for(i=NF;i>0;i--) if($i ~ /MiB/){gsub("MiB","",$i); print $i; exit}}')
    fi
    PVRAM=${PVRAM:-0}
    read -r CPU RSS < <(ps -p "$PID" -o %cpu=,rss= | awk '{printf "%s %d", $1, $2/1024}')
    ONGPU="ja"; [ "$PVRAM" = "0" ] && ONGPU="NEIN (Prozess nicht auf GPU!)"
    printf "[%s] PID %-7s | GPU %3s%% | MemCtl %3s%% | VRAM %5s/%s MB | CARLA-VRAM %5s MB | %s°C | %sW | %sMHz | CPU %5s%% | RAM %s MB | auf NVIDIA: %s\n" \
      "$TS" "$PID" "$GUTIL" "$MUTIL" "$VUSED" "$VTOTAL" "$PVRAM" "$TEMP" "$PWR" "$CLK" "$CPU" "$RSS" "$ONGPU"
    [ -n "$LOGFILE" ] && echo "$TS,$PID,$GUTIL,$MUTIL,$VUSED,$VTOTAL,$TEMP,$PWR,$CLK,$PVRAM,$CPU,$RSS" >> "$LOGFILE"
  else
    printf "[%s] kein '%s'-Prozess gefunden | GPU %3s%% | VRAM %s/%s MB | %s°C\n" \
      "$TS" "$PATTERN" "$GUTIL" "$VUSED" "$VTOTAL" "$TEMP"
  fi
  sleep "$INTERVAL"
done
