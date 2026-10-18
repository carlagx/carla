#!/usr/bin/env bash
# Removes logs, temp files and build leftovers created while building/testing CARLA,
# to get back towards the pristine state of the repository.
#
# Dry run by default: nothing is deleted until you pass --yes.
# Only paths WITHOUT tracked git files are ever removed.
#
# Usage:
#   ./clean-carla.sh [levels] [--yes]
#
# Levels (combine freely):
#   (none)           logs & temp: build-check-logs, test-logs, client-build*, Saved/Logs,
#                    Saved/Crashes, DerivedDataCache, *.log, __pycache__, *~, *.orig, *.swp ...
#   --build          build outputs: Build, Dist, Intermediate, Binaries, CppClient
#                    build/bin/libcarla-install, PythonAPI build/dist/dependencies, Version.h ...
#   --ide            generated IDE/project files (.vscode, .kdev4, *.pri, Makefile ...)
#   --saved          all of Unreal Saved/ (Cooked + StagedBuilds, ~17 GB)
#   --docker         Util/Docker/DevEnv download/artifacts/offline-cache, RecastBuilder
#   --all            all of the above
#   --content        ALSO Unreal/CarlaUE4/Content (24 GB of downloaded assets!) - never in --all
#   --credentials    ALSO Util/Docker/DevEnv/credentials/credentials.env - never in --all
#   --reset-tracked  ALSO discard local changes to tracked files (git checkout) - never in --all
#   --yes            really delete (otherwise only list)

set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOT="$PWD"

LOGS=1 BUILD=0 IDE=0 SAVED=0 DOCKER=0 CONTENT=0 CREDS=0 RESET=0 YES=0
for a in "$@"; do
    case "$a" in
        --build) BUILD=1 ;;
        --ide) IDE=1 ;;
        --saved) SAVED=1 ;;
        --docker) DOCKER=1 ;;
        --all) BUILD=1 IDE=1 SAVED=1 DOCKER=1 ;;
        --content) CONTENT=1 ;;
        --credentials) CREDS=1 ;;
        --reset-tracked) RESET=1 ;;
        --yes) YES=1 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "Unknown option: $a" >&2; exit 1 ;;
    esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository" >&2; exit 1; }

TARGETS=()
add() { for p in "$@"; do [ -e "$p" ] || [ -L "$p" ] && TARGETS+=("$p"); done; return 0; }

if [ $LOGS = 1 ]; then
    add build-check-logs test-logs client-build client-build-* \
        Unreal/CarlaUE4/Saved/Logs Unreal/CarlaUE4/Saved/Crashes \
        Unreal/CarlaUE4/Saved/MaterialStats Unreal/CarlaUE4/Saved/MaterialStatsDebug \
        Unreal/CarlaUE4/Saved/Autosaves Unreal/CarlaUE4/Saved/RegisteredObjects.txt \
        Unreal/CarlaUE4/DerivedDataCache PythonAPI/carla/source/carla.egg-info
    while IFS= read -r f; do TARGETS+=("$f"); done < <(
        find . \( -path ./.git -o -path ./Unreal/CarlaUE4/Content -o -path ./Build -o -path ./Dist \) -prune -o \
            \( -name '*.log' -o -name '*.tmp' -o -name '*.orig' -o -name '*.rej' -o -name '*.swp' \
               -o -name '*~' -o -name '*.pyc' -o -name 'nohup.out' -o -name '.gdb_history' \
               -o -name '__pycache__' -o -name '*.bak-carla' \) -print 2>/dev/null)
fi

if [ $BUILD = 1 ]; then
    add Build Dist Examples/CppClient/build Examples/CppClient/bin Examples/CppClient/libcarla-install \
        PythonAPI/carla/build PythonAPI/carla/dist PythonAPI/carla/dependencies \
        LibCarla/source/carla/Version.h \
        Unreal/CarlaUE4/Binaries Unreal/CarlaUE4/Build Unreal/CarlaUE4/Intermediate \
        Unreal/CarlaUE4/Script Unreal/CarlaUE4/Config/CarSimConfig.ini Unreal/CarlaUE4/Config/OptionalModules.ini \
        Unreal/CarlaUE4/Plugins/Carla/Binaries Unreal/CarlaUE4/Plugins/Carla/Intermediate \
        Unreal/CarlaUE4/Plugins/Carla/CarlaDependencies \
        Unreal/CarlaUE4/Plugins/CarlaExporter/Binaries Unreal/CarlaUE4/Plugins/CarlaExporter/Intermediate \
        Unreal/CarlaUE4/Plugins/CarlaTools/Binaries Unreal/CarlaUE4/Plugins/CarlaTools/Intermediate \
        Unreal/CarlaUE4/Plugins/Converters/MDL/Binaries Unreal/CarlaUE4/Plugins/Converters/MDL/Intermediate \
        Unreal/CarlaUE4/Plugins/Converters/MDL/Library Unreal/CarlaUE4/Plugins/Converters/MDL/Source/ThirdParty \
        Unreal/CarlaUE4/Plugins/Converters/MDL/Source/MDL/Private/Engine \
        Unreal/CarlaUE4/Plugins/Converters/SimReady/Binaries Unreal/CarlaUE4/Plugins/Converters/SimReady/Intermediate \
        Unreal/CarlaUE4/Plugins/Carla/Content/PostProcessingMaterials/TaggedMaterials/TaggedMaterials_Carla.uasset \
        Unreal/CarlaUE4/Plugins/Carla/Content/PostProcessingMaterials/TaggedMaterials/TaggedMaterials_Carla_Map.umap \
        Unreal/CarlaUE4/Plugins/Carla/Content/PostProcessingMaterials/TaggedMaterials/TaggedMaterials_Editor.uasset
fi

if [ $IDE = 1 ]; then
    add Unreal/CarlaUE4/.ignore Unreal/CarlaUE4/.kdev4 Unreal/CarlaUE4/.vscode \
        Unreal/CarlaUE4/CMakeLists.txt Unreal/CarlaUE4/Makefile \
        Unreal/CarlaUE4/CarlaUE4.code-workspace Unreal/CarlaUE4/CarlaUE4.kdev4 \
        Unreal/CarlaUE4/CarlaUE4.pro Unreal/CarlaUE4/CarlaUE4.workspace \
        Unreal/CarlaUE4/CarlaUE4CodeCompletionFolders.txt Unreal/CarlaUE4/CarlaUE4CodeLitePreProcessor.txt \
        Unreal/CarlaUE4/CarlaUE4Config.pri Unreal/CarlaUE4/CarlaUE4Defines.pri \
        Unreal/CarlaUE4/CarlaUE4Header.pri Unreal/CarlaUE4/CarlaUE4Includes.pri Unreal/CarlaUE4/CarlaUE4Source.pri
fi

[ $SAVED = 1 ] && add Unreal/CarlaUE4/Saved
[ $DOCKER = 1 ] && add Util/Docker/DevEnv/download Util/Docker/DevEnv/artifacts \
    Util/Docker/DevEnv/offline-cache Util/DockerUtils/dist/RecastBuilder
[ $CONTENT = 1 ] && add Unreal/CarlaUE4/Content
[ $CREDS = 1 ] && add Util/Docker/DevEnv/credentials/credentials.env

# Keep only paths that contain no tracked files; dedupe; drop children of listed parents.
SAFE=(); SKIPPED=0
while IFS= read -r p; do
    p="${p#./}"
    if [ -n "$(git ls-files -- "$p" | head -1)" ]; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    SAFE+=("$p")
done < <(printf '%s\n' "${TARGETS[@]:-}" | sed '/^$/d' | sort -u)

FINAL=()
for p in "${SAFE[@]:-}"; do
    [ -z "$p" ] && continue
    skip=0
    for q in "${SAFE[@]}"; do
        [ "$p" != "$q" ] && [[ "$p" == "$q"/* ]] && { skip=1; break; }
    done
    [ $skip = 0 ] && FINAL+=("$p")
done

[ $SKIPPED -gt 0 ] && echo "($SKIPPED tracked paths skipped, e.g. logs that belong to the repo)"
if [ ${#FINAL[@]} -eq 0 ]; then
    echo "Nothing to clean."
else
    [ $YES = 1 ] && echo "Deleting:" || echo "Would delete (dry run, pass --yes to delete):"
    TOTAL=0
    for p in "${FINAL[@]}"; do
        kb=$(du -sk -- "$p" 2>/dev/null | cut -f1); kb=${kb:-0}
        TOTAL=$((TOTAL + kb))
        printf '  %8s  %s\n' "$(du -sh -- "$p" 2>/dev/null | cut -f1)" "$p"
        [ $YES = 1 ] && rm -rf -- "$p"
    done
    printf 'Total: %s MB\n' $((TOTAL / 1024))
fi

if [ $RESET = 1 ]; then
    echo
    echo "Tracked files with local changes:"
    git status --short | grep -v '^??' || echo "  (none)"
    if [ $YES = 1 ]; then
        git checkout -- . && echo "Tracked changes discarded."
    else
        echo "(dry run: would run 'git checkout -- .')"
    fi
fi

# Untracked, non-ignored files are never touched; show what is left over.
LEFT=$(git status --short | grep '^??' || true)
if [ -n "$LEFT" ]; then
    echo
    echo "Untracked (not touched, remove manually if wanted):"
    echo "$LEFT" | sed 's/^/  /'
fi
