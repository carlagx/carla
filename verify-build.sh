#!/bin/bash

################################################################################
# CARLA Build Verification Script
#
# This script checks if the build was successful and all artifacts are in place.
# It provides a detailed report of what was built and what's ready to use.
#
# Usage:
#   ./verify-build.sh [--verbose]
#
# Output:
#   - Check results (OK/MISSING)
#   - File sizes
#   - Build artifacts summary
#   - Next steps
#
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CARLA_ROOT="$(cd "$(dirname "$0")" && pwd)"
VERBOSE="${1:---}"

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

section() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

# Main verification
main() {
    clear 2>/dev/null || true

    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         CARLA Build Verification Script                   ║"
    echo "║                    $(date +'%Y-%m-%d %H:%M:%S')                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    info "CARLA Root: $CARLA_ROOT"
    info "Git Branch: $(cd "$CARLA_ROOT" && git branch --show-current 2>/dev/null || echo 'unknown')"

    local error_count=0
    local warn_count=0
    local pass_count=0

    # ==================================================================
    # Check 1: Repository Structure
    # ==================================================================
    section "1. Repository Structure"

    if [ -f "$CARLA_ROOT/Makefile" ]; then
        pass "Makefile found"
        ((pass_count++))
    else
        fail "Makefile not found"
        ((error_count++))
    fi

    if [ -d "$CARLA_ROOT/Examples/CppClient" ]; then
        pass "Examples/CppClient directory exists"
        ((pass_count++))
    else
        fail "Examples/CppClient directory not found"
        ((error_count++))
    fi

    if [ -d "$CARLA_ROOT/LibCarla" ]; then
        pass "LibCarla source directory exists"
        ((pass_count++))
    else
        fail "LibCarla source directory not found"
        ((error_count++))
    fi

    # ==================================================================
    # Check 2: Dependencies (make setup)
    # ==================================================================
    section "2. Dependencies Built by 'make setup'"

    local build_dir="$CARLA_ROOT/Build"
    if [ -d "$build_dir" ]; then
        pass "Build directory exists ($build_dir)"
        ((pass_count++))

        # Check individual dependencies
        local boost_ok=false
        if [ -f "$build_dir/boost-1.90.0-c10-install/lib/libboost_filesystem.a" ] 2>/dev/null; then
            pass "Boost built (libboost_filesystem.a)"
            ((pass_count++))
            boost_ok=true
        elif find "$build_dir" -name "libboost_filesystem.a" 2>/dev/null | grep -q .; then
            pass "Boost found in Build/"
            ((pass_count++))
            boost_ok=true
        else
            warn "Boost not found - may still be compiling"
            ((warn_count++))
        fi

        if [ -f "$build_dir/rpclib-install/lib/librpc.a" ] 2>/dev/null; then
            pass "rpclib built (librpc.a)"
            ((pass_count++))
        else
            warn "rpclib not found - check if make setup completed"
            ((warn_count++))
        fi

        if find "$build_dir" -name "libRecast.a" 2>/dev/null | grep -q .; then
            pass "Recast library found"
            ((pass_count++))
        else
            warn "Recast library not found"
            ((warn_count++))
        fi

    else
        fail "Build directory does not exist"
        fail "Run 'make setup' first to download and build dependencies"
        ((error_count++))
    fi

    # ==================================================================
    # Check 3: C++ Client Build Artifacts
    # ==================================================================
    section "3. C++ Client Build Artifacts"

    local client_dir="$CARLA_ROOT/Examples/CppClient"

    if [ -d "$client_dir/libcarla-install" ]; then
        pass "LibCarla installation directory exists"
        ((pass_count++))

        if [ -f "$client_dir/libcarla-install/lib/libcarla_client.a" ]; then
            local size=$(ls -lh "$client_dir/libcarla-install/lib/libcarla_client.a" | awk '{print $5}')
            pass "libcarla_client.a exists ($size)"
            ((pass_count++))
        else
            warn "libcarla_client.a not found - run 'make build-client'"
            ((warn_count++))
        fi

        if [ -f "$client_dir/libcarla-install/lib/librpc.a" ]; then
            local size=$(ls -lh "$client_dir/libcarla-install/lib/librpc.a" | awk '{print $5}')
            pass "librpc.a installed ($size)"
            ((pass_count++))
        else
            warn "librpc.a not installed"
            ((warn_count++))
        fi

        if [ -d "$client_dir/libcarla-install/include/carla" ]; then
            local count=$(find "$client_dir/libcarla-install/include/carla" -name "*.h" 2>/dev/null | wc -l)
            pass "CARLA headers present ($count files)"
            ((pass_count++))
        else
            warn "CARLA headers not found"
            ((warn_count++))
        fi
    else
        warn "LibCarla installation directory not found"
        warn "Run 'make build-client' to build the client library"
        ((warn_count++))
    fi

    if [ -f "$client_dir/bin/cpp_client" ]; then
        if file "$client_dir/bin/cpp_client" | grep -q "executable"; then
            local size=$(ls -lh "$client_dir/bin/cpp_client" | awk '{print $5}')
            pass "C++ client binary built and executable ($size)"
            ((pass_count++))
        else
            fail "cpp_client exists but is not executable"
            ((error_count++))
        fi
    else
        warn "cpp_client binary not found"
        warn "Run 'make build-client' in Examples/CppClient/ to build"
        ((warn_count++))
    fi

    # ==================================================================
    # Check 4: Build Configuration Files
    # ==================================================================
    section "4. Build Configuration"

    if [ -f "$client_dir/ToolChain.cmake" ]; then
        pass "ToolChain.cmake configured"
        ((pass_count++))
    else
        info "ToolChain.cmake will be auto-generated on next build"
    fi

    if [ -f "$client_dir/CMakeLists.txt" ]; then
        pass "CMakeLists.txt present"
        ((pass_count++))
    else
        fail "CMakeLists.txt not found"
        ((error_count++))
    fi

    if [ -f "$client_dir/Makefile" ]; then
        pass "Examples/CppClient/Makefile exists"
        ((pass_count++))
    else
        fail "Examples/CppClient/Makefile not found"
        ((error_count++))
    fi

    # ==================================================================
    # Check 5: Build Scripts
    # ==================================================================
    section "5. Build Automation"

    if [ -f "$CARLA_ROOT/carla-build-and-test.sh" ]; then
        if [ -x "$CARLA_ROOT/carla-build-and-test.sh" ]; then
            pass "Build script exists and is executable"
            ((pass_count++))
        else
            warn "Build script exists but is not executable"
            warn "Fix with: chmod +x $CARLA_ROOT/carla-build-and-test.sh"
            ((warn_count++))
        fi
    else
        warn "Build script not found"
        ((warn_count++))
    fi

    # ==================================================================
    # Check 6: Documentation
    # ==================================================================
    section "6. Documentation"

    local docs_ok=0
    [ -f "$CARLA_ROOT/QUICK_START.md" ] && { pass "QUICK_START.md"; ((docs_ok++)); } || warn "QUICK_START.md missing"
    [ -f "$CARLA_ROOT/BUILD_STEPS.md" ] && { pass "BUILD_STEPS.md"; ((docs_ok++)); } || warn "BUILD_STEPS.md missing"
    [ -f "$CARLA_ROOT/BUILD_SUMMARY.md" ] && { pass "BUILD_SUMMARY.md"; ((docs_ok++)); } || warn "BUILD_SUMMARY.md missing"

    pass_count=$((pass_count + docs_ok))
    [ $docs_ok -lt 3 ] && ((warn_count++))

    # ==================================================================
    # Check 7: Disk Usage
    # ==================================================================
    section "7. Disk Space Usage"

    if [ -d "$build_dir" ]; then
        local build_size=$(du -sh "$build_dir" 2>/dev/null | awk '{print $1}')
        info "Build directory: $build_size"
    fi

    if [ -d "$client_dir/libcarla-install" ]; then
        local install_size=$(du -sh "$client_dir/libcarla-install" 2>/dev/null | awk '{print $1}')
        info "LibCarla installation: $install_size"
    fi

    local free_space=$(df -h "$CARLA_ROOT" | tail -1 | awk '{print $4}')
    info "Free disk space in $CARLA_ROOT: $free_space"

    # ==================================================================
    # Check 8: Environment
    # ==================================================================
    section "8. Build Environment"

    if command -v gcc &> /dev/null; then
        local gcc_version=$(gcc --version | head -1)
        pass "GCC: $gcc_version"
        ((pass_count++))
    else
        fail "GCC not found"
        ((error_count++))
    fi

    if command -v cmake &> /dev/null; then
        local cmake_version=$(cmake --version | head -1)
        pass "CMake: $cmake_version"
        ((pass_count++))
    else
        fail "CMake not found"
        ((error_count++))
    fi

    if command -v ninja &> /dev/null; then
        local ninja_version=$(ninja --version)
        pass "Ninja: $ninja_version"
        ((pass_count++))
    else
        fail "Ninja not found"
        ((error_count++))
    fi

    if python3 --version &> /dev/null; then
        local python_version=$(python3 --version)
        pass "Python: $python_version"
        ((pass_count++))
    else
        fail "Python3 not found"
        ((error_count++))
    fi

    # ==================================================================
    # Summary
    # ==================================================================
    section "Verification Summary"

    echo ""
    info "Results: ${GREEN}$pass_count passed${NC} | ${YELLOW}$warn_count warnings${NC} | ${RED}$error_count errors${NC}"
    echo ""

    if [ $error_count -eq 0 ] && [ $warn_count -eq 0 ]; then
        pass "All checks passed! ✨"
        echo ""
        info "Next step: Run the C++ client"
        echo "    ./carla-build-and-test.sh test"
        return 0
    elif [ $error_count -eq 0 ] && [ $warn_count -gt 0 ]; then
        warn "Build appears to be in progress"
        echo ""
        info "To complete the build:"
        echo "    cd $CARLA_ROOT/Examples/CppClient"
        echo "    make build"
        echo ""
        info "Then test with:"
        echo "    ./carla-build-and-test.sh test"
        return 0
    else
        fail "Build verification found issues"
        echo ""
        info "To fix, try:"
        echo "    cd $CARLA_ROOT"
        echo "    ./carla-build-and-test.sh full"
        return 1
    fi
}

main "$@"
