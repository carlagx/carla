#!/usr/bin/env bash
# Scans every log the CARLA build/test/run leaves behind, drops the known noise,
# matches the remaining errors against the knowledge base in issues/ and writes
# a Markdown report.
#
# Usage:
#   ./scan-carla-logs.sh [--since YYYY-MM-DD] [--ubt] [--out FILE] [--quiet]
#
#   --since DATE   only look at log files modified on/after DATE
#   --ubt          also scan UnrealBuildTool logs under $UE4_ROOT
#   --out FILE     report path (default issues/reports/scan-<timestamp>.md)
#   --quiet        no terminal summary, only the report
#
# Exit code: number of unknown error groups (0 = everything is known or clean).
#
# Sources and rules:
#   UE4 logs      Saved/Logs/CarlaUE4*.log, test-logs/*/server.log, Dist/**/Saved/Logs
#                 only "Log*: Error|Fatal:", LoadErrors, Unhandled Exception,
#                 Caught signal, Fatal error. [Callstack] lines are folded.
#   crashes       Saved/Crashes/*/CrashContext.runtime-xml (+ top frame)
#   test-logs     summary.txt (PASS/FAIL) + Traceback/RuntimeError/Error: in check logs
#   build-check   summary.txt + compiler/linker errors; missing "Success!" = incomplete
#   cmake         CMakeError/CMakeOutput/config.log are only listed, never grepped
#                 (their failures are expected probes); config.log exit code checked
#   UBT           Log.txt / Log_UHT*.txt (--ubt)
#
# NOTE: plain `grep` in this environment is an ugrep wrapper that silently skips
# binary files (server.log contains NUL bytes), so GNU grep is called by path.

set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$PWD"
GREP=/usr/bin/grep
[ -x "$GREP" ] || GREP=$(command -v grep)
UE4_ROOT="${UE4_ROOT:-$HOME/UnrealEngine_4.26}"

SINCE="" UBT=0 OUT="" QUIET=0
while [ $# -gt 0 ]; do
    case "$1" in
        --since) SINCE="$2"; shift 2 ;;
        --ubt) UBT=1; shift ;;
        --out) OUT="$2"; shift 2 ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

TS=$(date +%Y%m%d-%H%M%S)
[ -n "$OUT" ] || OUT="issues/reports/scan-$TS.md"
mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
HITS="$TMP/hits.tsv"      # source \t file \t line \t text
RUNS="$TMP/runs.tsv"      # kind \t run \t result
LISTED="$TMP/listed.tsv"  # file \t date \t note
: >"$HITS"; : >"$RUNS"; : >"$LISTED"

# ---------------------------------------------------------------- helpers
fdate() { date -r "$1" +%F 2>/dev/null || echo "?"; }
recent() { [ -z "$SINCE" ] || [ "$(fdate "$1")" \> "$SINCE" ] || [ "$(fdate "$1")" = "$SINCE" ]; }
hit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$HITS"; }
strip_ansi() { sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\r$//; s/[[:space:]]*$//'; }

# Lines that look like errors but never are.
NOISE_PRE='error code: 143|Disabling core dumps|\[Callstack\]|Error: Stack:|Error: *$|=== Handled ensure: ===|=== Critical error: ===|0 [Ee]rror\(s\)|Success - 0 error|S_LightError|CodeLite|-Werror'

UE_PAT='\]Log[A-Za-z0-9_]+: (Error|Fatal): |LoadErrors: Error: |Unhandled Exception|Caught signal|Fatal error'

# scan_ue <source> <file>: UE4 log rules; a critical error carries its first frame.
scan_ue() {
    local src="$1" f="$2"
    recent "$f" || return 0
    $GREP -aEn -A4 "$UE_PAT" "$f" 2>/dev/null | strip_ansi | awk -v src="$src" -v f="$f" -v noise="$NOISE_PRE" -v pat="$UE_PAT" '
        /^--$/ { next }
        {
            n = $0; sub(/[-:].*/, "", n)
            t = $0; sub(/^[0-9]+[-:]/, "", t)
            if (t ~ pat && t !~ noise) {
                if (pending != "") print src "\t" f "\t" pl "\t" pending
                pending = t; pl = n
                if (t ~ /Unhandled Exception|Caught signal/) wantframe = 1; else wantframe = 0
                next
            }
            if (wantframe && t ~ /\.so!|UE4Editor!|CarlaUE4(-Linux-Shipping)?!/) {
                sub(/^.*LogCore: (0x[0-9a-fA-F]+ )?/, "", t); sub(/ \[\/.*$/, "", t)
                pending = pending " | " t; wantframe = 0
            }
        }
        END { if (pending != "") print src "\t" f "\t" pl "\t" pending }
    ' >>"$HITS"
}

# ---------------------------------------------------------------- 1. UE4 logs
for f in Unreal/CarlaUE4/Saved/Logs/CarlaUE4*.log Dist/*/LinuxNoEditor/CarlaUE4/Saved/Logs/*.log; do
    [ -f "$f" ] || continue
    case "$f" in *-CRC*) continue ;; esac
    scan_ue ue "$f"
done

# ---------------------------------------------------------------- 2. crashes
for d in Unreal/CarlaUE4/Saved/Crashes/*/; do
    x="$d/CrashContext.runtime-xml"
    [ -f "$x" ] || continue
    recent "$x" || continue
    type=$($GREP -ao '<CrashType>[^<]*' "$x" | head -1 | sed 's/<CrashType>//')
    msg=$($GREP -ao '<ErrorMessage>[^<]*' "$x" | head -1 | sed 's/<ErrorMessage>//' | cut -c1-160)
    frame=""
    if [ -f "$d/Diagnostics.txt" ]; then
        frame=$($GREP -a -A1 'CALLSTACK START' "$d/Diagnostics.txt" | tail -1 | sed 's/ \[\/.*$//')
    fi
    hit crash "${d%/}" "$(fdate "$x")" "$type: $msg${frame:+ | $frame}"
done

# ---------------------------------------------------------------- 3. test-logs
for d in test-logs/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; run=$(basename "$d")
    if [ -f "$d/summary.txt" ]; then
        res=$($GREP -a '^TOTAL' "$d/summary.txt" | cut -f2- | tail -1)
        [ -n "$res" ] || res="$(( $($GREP -ac '^PASS' "$d/summary.txt") )) pass / $(( $($GREP -ac '^FAIL' "$d/summary.txt") )) fail (no total)"
        printf 'test\t%s\t%s\n' "$run" "$res" >>"$RUNS"
        $GREP -a '^FAIL' "$d/summary.txt" | while IFS=$'\t' read -r _ name; do
            hit test "$d/summary.txt" 0 "FAIL: $name"
        done
    else
        printf 'test\t%s\tunknown (no summary.txt; older run)\n' "$run" >>"$RUNS"
    fi
    for f in "$d"/*.log; do
        [ -f "$f" ] || continue
        recent "$f" || continue
        case "$(basename "$f")" in
            server.log) scan_ue test "$f"; continue ;;
            docker-run.log) continue ;;
        esac
        strip_ansi <"$f" | $GREP -aEn 'RuntimeError|[A-Za-z]+Error:|Exception:|\[FAIL\]|error:|Segmentation fault|core dumped' 2>/dev/null \
            | $GREP -aEv "$NOISE_PRE" | while IFS=: read -r n t; do hit test "$f" "$n" "$t"; done
    done
done

# ---------------------------------------------------------------- 4. build-check-logs
BUILD_ERR='error:|FAILED:|undefined reference|ninja: build stopped|make: \*\*\*|fatal error|No such file or directory|Permission denied'
for d in build-check-logs/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"; run=$(basename "$d")
    if [ -f "$d/summary.txt" ]; then
        res=$($GREP -a '^TOTAL' "$d/summary.txt" | cut -f2- | tail -1)
        printf 'build\t%s\t%s\n' "$run" "${res:-no total}" >>"$RUNS"
    else
        printf 'build\t%s\tunknown (no summary.txt; older run)\n' "$run" >>"$RUNS"
    fi
    for f in "$d"/*.log; do
        [ -f "$f" ] || continue
        recent "$f" || continue
        errs=$(strip_ansi <"$f" | $GREP -aEn "$BUILD_ERR" | $GREP -aEv "$NOISE_PRE")
        if [ -n "$errs" ]; then
            echo "$errs" | while IFS=: read -r n t; do hit build "$f" "$n" "$t"; done
        elif ! strip_ansi <"$f" | $GREP -aq 'Success!'; then
            hit build "$f" 0 "INCOMPLETE: no error and no 'Success!' marker (interrupted?)"
        fi
    done
done

# ---------------------------------------------------------------- 5. cmake / autoconf (list only)
for f in Build/*/CMakeFiles/CMakeError.log Build/*/CMakeFiles/CMakeOutput.log \
         client-build*/CMakeFiles/CMake*.log Examples/CppClient/build/CMakeFiles/CMake*.log \
         Build/*/build/config.log Build/*/config.log; do
    [ -f "$f" ] || continue
    note="probe log, not scanned"
    case "$f" in
        *config.log)
            if $GREP -aEq 'configure: exit [1-9]' "$f"; then
                note="configure FAILED"; hit build "$f" 0 "configure exited non-zero: $($GREP -aE 'configure: exit [1-9]' "$f" | tail -1)"
            else note="configure ok"; fi ;;
    esac
    printf '%s\t%s\t%s\n' "$f" "$(fdate "$f")" "$note" >>"$LISTED"
done

# ---------------------------------------------------------------- 6. UnrealBuildTool (optional)
if [ $UBT = 1 ]; then
    for f in "$UE4_ROOT"/Engine/Programs/UnrealBuildTool/Log.txt "$UE4_ROOT"/Engine/Programs/UnrealBuildTool/Log_UHT*.txt; do
        [ -f "$f" ] || continue
        recent "$f" || continue
        $GREP -aEn 'error|ERROR:|Fatal|failed' "$f" 2>/dev/null | $GREP -aEv "$NOISE_PRE|warning" \
            | while IFS=: read -r n t; do hit ubt "$f" "$n" "$t"; done
    done
fi

# ---------------------------------------------------------------- classify against issues/
SIGS="$TMP/sigs.tsv"   # id \t status \t file \t title \t signature
for m in issues/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$m" ] || continue
    awk -v file="$m" '
        /^---$/ { fm++; next }
        fm == 1 && /^id:/        { id = $2 }
        fm == 1 && /^status:/    { st = $2 }
        fm == 1 && /^title:/     { t = $0; sub(/^title: */, "", t) }
        fm == 1 && /^signature:/ { s = $0; sub(/^signature: */, "", s)
                                   q = substr(s, 1, 1)
                                   if ((q == "\047" || q == "\"") && substr(s, length(s), 1) == q) s = substr(s, 2, length(s) - 2) }
        fm >= 2 { exit }
        END { if (id != "" && s != "") printf "%s\t%s\t%s\t%s\t%s\n", id, st, file, t, s }
    ' "$m"
done | sort >"$SIGS"

CLASS="$TMP/class.tsv"  # class \t id \t source \t file \t line \t text \t normalized
awk -F'\t' -v OFS='\t' '
    NR == FNR { n++; id[n] = $1; st[n] = $2; sig[n] = $5; next }
    {
        cls = "unknown"; which = "-"
        for (i = 1; i <= n; i++) if ($4 ~ sig[i]) { cls = st[i]; which = id[i]; break }
        norm = $4
        gsub(/0x[0-9a-fA-F]+/, "#", norm); gsub(/\/[^ ]+/, "#", norm); gsub(/[0-9]+/, "#", norm)
        gsub(/^\[#\.#\.#-#\.#\.#:#\]\[ *#\]/, "", norm)
        print cls, which, $1, $2, $3, $4, norm
    }
' "$SIGS" "$HITS" >"$CLASS"

count() { awk -F'\t' -v c="$1" '$1 == c' "$CLASS" | wc -l; }
N_UNKNOWN=$(count unknown); N_VERIFIED=$(count verified); N_OPEN=$(count open); N_NOISE=$(count noise)
N_GROUPS=$(awk -F'\t' '$1 == "unknown" { print $7 }' "$CLASS" | sort -u | wc -l)

issue_link() { awk -F'\t' -v id="$1" '$1 == id { printf "[%s](../%s) %s", $1, $3, $4 }' "$SIGS"; }

# ---------------------------------------------------------------- report
{
    echo "# CARLA log scan $TS"
    echo
    echo "Repo: \`$ROOT\` | branch: \`$(git rev-parse --abbrev-ref HEAD 2>/dev/null)\` | since: ${SINCE:-all} | UBT: $UBT"
    echo
    echo "| Class | Hits |"; echo "|---|---|"
    echo "| Unknown (needs a look) | $N_UNKNOWN in $N_GROUPS group(s) |"
    echo "| Known, verified solution | $N_VERIFIED |"
    echo "| Known, still open | $N_OPEN |"
    echo "| Noise (hidden) | $N_NOISE |"
    echo

    echo "## 1. Unknown problems"
    echo
    if [ "$N_UNKNOWN" -eq 0 ]; then echo "none"; else
        awk -F'\t' '$1 == "unknown" { c[$7]++; if (!($7 in first)) { first[$7] = NR } ; ex[$7] = ex[$7] "\n" $4 "\t" $5 "\t" $6 }
            END { for (k in c) print c[k] "\t" first[k] "\t" k }' "$CLASS" | sort -t$'\t' -k1,1nr -k2,2n |
        while IFS=$'\t' read -r cnt _ norm; do
            echo "### ${cnt}x  \`$(printf '%s' "$norm" | cut -c1-120)\`"
            echo
            awk -F'\t' -v n="$norm" '$1 == "unknown" && $7 == n { print $3 "\t" $4 "\t" $5 "\t" $6 }' "$CLASS" | head -3 |
            while IFS=$'\t' read -r src f ln txt; do
                echo "- \`$f:$ln\` ($src)"
                echo '  ```'
                echo "  $(printf '%s' "$txt" | cut -c1-300)"
                if [ "$ln" -gt 0 ] 2>/dev/null && [ "$src" != crash ]; then
                    sed -n "$((ln > 3 ? ln - 3 : 1)),$((ln + 3))p" "$f" 2>/dev/null | strip_ansi | tr -d '\000' | cut -c1-200 | sed 's/^/  > /'
                fi
                echo '  ```'
            done
            echo
        done
    fi

    echo "## 2. Known problems with a verified solution"
    echo
    if [ "$N_VERIFIED" -eq 0 ]; then echo "none"; else
        awk -F'\t' '$1 == "verified" { print $2 }' "$CLASS" | sort | uniq -c | while read -r cnt id; do
            echo "- ${cnt}x $(issue_link "$id")"
            awk -F'\t' -v id="$id" '$1 == "verified" && $2 == id { print "  - `" $4 ":" $5 "` " substr($6, 1, 160) }' "$CLASS" | head -5
        done
    fi
    echo

    echo "## 3. Known problems, still open"
    echo
    if [ "$N_OPEN" -eq 0 ]; then echo "none"; else
        awk -F'\t' '$1 == "open" { print $2 }' "$CLASS" | sort | uniq -c | while read -r cnt id; do
            echo "- ${cnt}x $(issue_link "$id")"
            awk -F'\t' -v id="$id" '$1 == "open" && $2 == id { print "  - `" $4 ":" $5 "` " substr($6, 1, 160) }' "$CLASS" | head -5
        done
    fi
    echo

    echo "## 4. Noise (counted, hidden)"
    echo
    if [ "$N_NOISE" -eq 0 ]; then echo "none"; else
        awk -F'\t' '$1 == "noise" { print $2 }' "$CLASS" | sort | uniq -c | while read -r cnt id; do
            echo "- ${cnt}x $(issue_link "$id")"
        done
    fi
    echo

    echo "## 5. Test and build runs"
    echo
    echo "| Kind | Run | Result |"; echo "|---|---|---|"
    sort -t$'\t' -k2,2 "$RUNS" | awk -F'\t' '{ print "| " $1 " | " $2 " | " $3 " |" }'
    [ -s "$RUNS" ] || echo "| - | - | no runs found |"
    echo

    echo "## 6. Probe logs (listed only, failures inside are expected)"
    echo
    if [ -s "$LISTED" ]; then
        echo "| File | Date | Note |"; echo "|---|---|---|"
        awk -F'\t' '{ print "| `" $1 "` | " $2 " | " $3 " |" }' "$LISTED"
    else echo "none"; fi
    echo

    if [ "$N_UNKNOWN" -gt 0 ]; then
        echo "## 7. Templates for new issues/ entries"
        echo
        next_id=$(ls issues/[0-9][0-9][0-9][0-9]-*.md 2>/dev/null | sed 's|.*/||; s|-.*||' | sort -n | tail -1)
        next_id=$(printf '%04d' $((10#${next_id:-0} + 1)))
        awk -F'\t' '$1 == "unknown" && !($7 in seen) { seen[$7] = 1; print $4 "\t" $6 }' "$CLASS" | head -10 |
        while IFS=$'\t' read -r f txt; do
            sig=$(printf '%s' "$txt" | sed 's/^\[[^]]*\]\[[^]]*\]//; s/[][\\.^$*+?(){}|]/\\&/g' | cut -c1-80)
            echo '```markdown'
            printf -- '---\nid: %s\ntitle: \nstatus: open\nphase: run\nsignature: %s\nsources: [%s]\nfirst_seen: %s\nfixed_in: -\n---\n' \
                "$next_id" "'$sig'" "$f" "$(date +%F)"
            echo '```'
            next_id=$(printf '%04d' $((10#$next_id + 1)))
        done
    fi
} >"$OUT"

if [ $QUIET = 0 ]; then
    echo "Unknown: $N_UNKNOWN ($N_GROUPS groups)  Verified: $N_VERIFIED  Open: $N_OPEN  Noise: $N_NOISE"
    echo "Report: $OUT"
fi
exit "$N_GROUPS"
