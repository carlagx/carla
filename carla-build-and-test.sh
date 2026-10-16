#!/bin/bash

################################################################################
# CARLA 0.9.16 Linux C++ Client - Complete Build & Test Script
#
# This script automates the full build process for CARLA C++ client on Linux.
# It handles system setup, dependency installation, building LibCarla client,
# and provides a test harness to run the example client.
#
# Usage:
#   ./carla-build-and-test.sh [command]
#
# Commands:
#   setup           Install system dependencies
#   build-deps      Run 'make setup' to download/build all dependencies
#   build-client    Build the C++ client library and example
#   test            Run the C++ client test (assumes server on localhost:2000)
#   clean           Remove build artifacts
#   full            Run all steps: setup, build-deps, build-client
#   all             Run everything including test prompt
#
# Environment variables:
#   CARLA_ROOT      Path to CARLA repo (default: script directory)
#   VERBOSE         Set to 1 for detailed output
#
# Example:
#   ./carla-build-and-test.sh full
#   ./carla-build-and-test.sh test --host=192.168.1.100 --port=2000
#
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CARLA_ROOT="${CARLA_ROOT:=$(cd "$(dirname "$0")" && pwd)}"
VERBOSE="${VERBOSE:-0}"
SERVER_HOST="${SERVER_HOST:-localhost}"
SERVER_PORT="${SERVER_PORT:-2000}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Ensure we're in the CARLA root
if [ ! -f "$CARLA_ROOT/Makefile" ]; then
    echo -e "${RED}ERROR: Cannot find CARLA Makefile at $CARLA_ROOT${NC}"
    echo "Set CARLA_ROOT environment variable to point to CARLA repo root"
    exit 1
fi

cd "$CARLA_ROOT"

################################################################################
# Helper Functions
################################################################################

log_header() {
    echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

log_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

run_cmd() {
    local cmd="$1"
    local description="$2"

    log_info "$description"

    if [ "$VERBOSE" = "1" ]; then
        echo -e "${YELLOW}Command: $cmd${NC}"
        eval "$cmd" || {
            log_error "Command failed: $cmd"
            return 1
        }
    else
        if eval "$cmd" > /dev/null 2>&1; then
            log_success "$description"
        else
            log_error "$description"
            echo "Run with VERBOSE=1 for details: VERBOSE=1 $0 $@"
            return 1
        fi
    fi
}

################################################################################
# Step: Install System Dependencies
################################################################################

step_setup() {
    log_header "Step 1: System Dependencies Installation"

    # Check if already installed
    if command -v cmake &> /dev/null && command -v ninja &> /dev/null; then
        log_success "System dependencies already installed"
        return 0
    fi

    log_info "Installing required Ubuntu packages..."
    echo "This may require your sudo password."

    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        g++-12 \
        cmake \
        ninja-build \
        libvulkan1 \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        autoconf \
        wget \
        curl \
        rsync \
        unzip \
        git \
        git-lfs \
        libpng-dev \
        libtiff5-dev \
        libjpeg-dev

    log_success "System dependencies installed"
}

################################################################################
# Step: Build Dependencies (make setup)
################################################################################

step_build_deps() {
    log_header "Step 2: Build LibCarla Dependencies"

    if [ -d "$CARLA_ROOT/Build" ]; then
        log_info "Build directory already exists. Skipping dependency download..."
        log_info "Use 'clean' command to force rebuild."
        return 0
    fi

    log_info "This step downloads and builds: Boost, rpclib, Recast, StreetMap, etc."
    log_info "Expected time: 30-90 minutes (depends on internet speed)"
    log_info "Expected disk space: ~15GB"

    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipped"
        return 0
    fi

    log_info "Running: make setup"
    if make setup; then
        log_success "Dependencies built successfully"
    else
        log_error "Dependency build failed"
        return 1
    fi
}

################################################################################
# Step: Build C++ Client
################################################################################

step_build_client() {
    log_header "Step 3: Build C++ Client"

    if [ ! -d "$CARLA_ROOT/Build" ]; then
        log_error "Dependencies not built! Run 'build-deps' first."
        return 1
    fi

    log_info "Building LibCarla.client and example application..."
    log_info "Expected time: 5-15 minutes"

    cd "$CARLA_ROOT/Examples/CppClient"

    if make build; then
        log_success "C++ client built successfully"

        # Show build artifacts
        echo ""
        log_info "Build artifacts:"
        if [ -f "bin/cpp_client" ]; then
            echo "  • Binary: bin/cpp_client"
            file "bin/cpp_client"
        fi

        if [ -d "libcarla-install/lib" ]; then
            echo "  • Static libraries:"
            ls -lh libcarla-install/lib/*.a 2>/dev/null | awk '{print "    - " $9 " (" $5 ")"}'
        fi

        if [ -d "libcarla-install/include" ]; then
            echo "  • Include directory: libcarla-install/include/"
            echo "    Headers: $(find libcarla-install/include -name '*.h' | wc -l) files"
        fi

    else
        log_error "C++ client build failed"
        return 1
    fi
}

################################################################################
# Step: Test the Client
################################################################################

step_test() {
    log_header "Step 4: Test C++ Client"

    if [ ! -f "$CARLA_ROOT/Examples/CppClient/bin/cpp_client" ]; then
        log_error "Client binary not found! Run 'build-client' first."
        return 1
    fi

    # Parse command line arguments for host/port
    local host="$SERVER_HOST"
    local port="$SERVER_PORT"

    for arg in "$@"; do
        case "$arg" in
            --host=*)
                host="${arg#--host=}"
                ;;
            --port=*)
                port="${arg#--port=}"
                ;;
        esac
    done

    log_info "Testing C++ client connection to $host:$port"
    log_info "Make sure CARLA server is running: make launch"
    log_info ""
    log_info "The client will:"
    log_info "  1. Connect to server at $host:$port"
    log_info "  2. Load a random town"
    log_info "  3. Spawn a random vehicle"
    log_info "  4. Apply throttle (accelerate)"
    log_info "  5. Reposition spectator camera"
    log_info "  6. Wait 10 seconds"
    log_info "  7. Exit gracefully"
    log_info ""

    echo ""
    read -p "Start test? (y/n) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Test skipped"
        return 0
    fi

    log_info "Starting C++ client..."
    cd "$CARLA_ROOT/Examples/CppClient"

    if ./bin/cpp_client "$host" "$port"; then
        log_success "Client test completed successfully!"
        return 0
    else
        log_error "Client test failed"
        echo ""
        log_info "Troubleshooting:"
        echo "  • Is the CARLA server running? (make launch in repo root)"
        echo "  • Check firewall rules on ports 2000/2001"
        echo "  • Try: ./bin/cpp_client --help"
        return 1
    fi
}

################################################################################
# Step: Clean Build Artifacts
################################################################################

step_clean() {
    log_header "Cleaning Build Artifacts"

    log_info "This will remove:"
    echo "  • Examples/CppClient/build/"
    echo "  • Examples/CppClient/bin/"
    echo "  • Examples/CppClient/libcarla-install/"
    echo "  • Examples/CppClient/ToolChain.cmake"

    read -p "Continue? (y/n) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi

    cd "$CARLA_ROOT/Examples/CppClient"
    make clean

    log_success "Cleaned successfully"
}

################################################################################
# Show Usage
################################################################################

show_usage() {
    cat << EOF

${BLUE}CARLA 0.9.16 Linux C++ Client Build & Test${NC}

${YELLOW}Usage:${NC}
  $(basename "$0") [command] [options]

${YELLOW}Commands:${NC}
  setup              Install system dependencies (requires sudo)
  build-deps         Download and build all dependencies (~30-90 min)
  build-client       Build LibCarla.client and example
  test               Run the C++ client example
  clean              Remove build artifacts
  full               Run: setup → build-deps → build-client
  all                Run all steps including test prompt
  help               Show this message

${YELLOW}Options for 'test' command:${NC}
  --host=HOSTNAME    Server hostname (default: localhost)
  --port=PORT        Server port (default: 2000)

${YELLOW}Environment Variables:${NC}
  CARLA_ROOT         Path to CARLA repo (default: script directory)
  VERBOSE            Set to 1 for detailed build output
  SERVER_HOST        Default server hostname
  SERVER_PORT        Default server port

${YELLOW}Examples:${NC}
  # Full build (interactive)
  ./$(basename "$0") full

  # Quick test with custom server
  ./$(basename "$0") test --host=192.168.1.100 --port=2000

  # Build with verbose output
  VERBOSE=1 ./$(basename "$0") build-client

  # Just clean up
  ./$(basename "$0") clean

${YELLOW}Prerequisites:${NC}
  • Ubuntu 20.04 or 22.04
  • ~130 GB free disk space (for full server build)
  • ~15 GB for just the C++ client dependencies
  • NVIDIA GPU recommended (RTX 2000 series or better)
  • CARLA server running (or will be built in full setup)

${YELLOW}More Information:${NC}
  • Docs: $CARLA_ROOT/Docs/
  • Build Linux: $CARLA_ROOT/Docs/build_linux.md
  • C++ Client: $CARLA_ROOT/Docs/adv_cpp_client.md
  • Examples: $CARLA_ROOT/Examples/CppClient/

EOF
}

################################################################################
# Main Entry Point
################################################################################

main() {
    local command="${1:-help}"

    # Print header
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         CARLA 0.9.16 Linux C++ Client Build & Test       ║"
    echo "║                    $(date +'%Y-%m-%d %H:%M:%S')                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    log_info "CARLA Root: $CARLA_ROOT"
    log_info "Git Branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"

    case "$command" in
        setup)
            step_setup
            ;;
        build-deps)
            step_build_deps
            ;;
        build-client)
            step_build_client
            ;;
        test)
            step_test "$@"
            ;;
        clean)
            step_clean
            ;;
        full)
            step_setup && \
            step_build_deps && \
            step_build_client && \
            log_success "Full build completed successfully!"
            ;;
        all)
            step_setup && \
            step_build_deps && \
            step_build_client && \
            step_test "$@" && \
            log_success "All steps completed successfully!"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
