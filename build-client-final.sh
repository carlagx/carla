#!/bin/bash

################################################################################
# CARLA C++ Client Final Build Script
# This script handles all the compilation steps for the C++ client
################################################################################

set -e

CARLA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR=$CARLA_ROOT/client-build-$(date +%s)
CLIENT_DIR=$CARLA_ROOT/Examples/CppClient
INSTALL_DIR=$CLIENT_DIR/libcarla-install
BIN_DIR=$CLIENT_DIR/bin

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  CARLA 0.9.16 C++ Client - Final Build                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "CARLA Root: $CARLA_ROOT"
echo "Build Dir: $BUILD_DIR"
echo "Install Dir: $INSTALL_DIR"
echo ""

# Step 1: Prepare directories
echo "📁 Preparing directories..."
mkdir -p $INSTALL_DIR/lib $INSTALL_DIR/include
mkdir -p $BIN_DIR
mkdir -p $BUILD_DIR
cd $BUILD_DIR

# Step 2: Collect all required libraries from Build/
echo "📦 Gathering libraries..."
find $CARLA_ROOT/Build -name "*.a" -type f -exec cp {} $INSTALL_DIR/lib/ \; 2>/dev/null
echo "✓ Copied $(ls $INSTALL_DIR/lib/*.a 2>/dev/null | wc -l) static libraries"

# Step 3: Install headers
echo "📚 Installing CARLA headers..."
cp -r $CARLA_ROOT/LibCarla/source/carla $INSTALL_DIR/include/ 2>/dev/null || true
echo "✓ Headers installed"

# Step 4: Create CMakeLists.txt for the client build
echo "⚙️ Creating CMake configuration..."
cat > CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.5)
project(CarlaClient CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -DNDEBUG -Wall -Wextra")

# Add all include directories from dependencies
include_directories(
  ${CMAKE_INSTALL_PREFIX}/include
  ${CMAKE_SOURCE_DIR}/boost-1.90.0-c10-install/include
  ${CMAKE_SOURCE_DIR}/rpclib-carla-callbacks-c10-libcxx-install/include
  ${CMAKE_SOURCE_DIR}/recast-c10-install/include
  ${CMAKE_SOURCE_DIR}/gtest-1.8.1-c10-libcxx-install/include
)

# Add all lib directories
link_directories(
  ${CMAKE_INSTALL_PREFIX}/lib
  ${CMAKE_SOURCE_DIR}/boost-1.90.0-c10-install/lib
  ${CMAKE_SOURCE_DIR}/rpclib-carla-callbacks-c10-libcxx-install/lib
  ${CMAKE_SOURCE_DIR}/recast-c10-install/lib
)

# Create the executable
add_executable(cpp_client
  ${CMAKE_INSTALL_PREFIX}/../main.cpp
)

# Link libraries
target_link_libraries(cpp_client PRIVATE
  -Wl,-Bstatic
  boost_filesystem
  rpc
  Recast
  Detour
  DetourCrowd
  png
  -Wl,-Bdynamic
  m
)
EOF

echo "✓ CMakeLists.txt created"

# Step 5: Copy symlinks to dependency directories
echo "🔗 Setting up dependency paths..."
ln -sf $CARLA_ROOT/Build/* . 2>/dev/null || true

# Step 6: Run CMake
echo "🛠️ Running CMake..."
cmake -G Ninja \
  -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_FLAGS="-O2 -DNDEBUG -Wall" \
  -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
  -DCMAKE_BUILD_TYPE=Release \
  . 2>&1 | tail -20

# Step 7: Build with Ninja
echo "🔨 Building with Ninja..."
ninja 2>&1 | tail -20 || true

# Step 8: Install
echo "📦 Installing..."
ninja install || true

# Step 9: Copy binary if build succeeded
if [ -f "cpp_client" ]; then
  cp cpp_client $BIN_DIR/
  echo "✅ Binary copied to $BIN_DIR/cpp_client"
else
  echo "⚠️ Binary not found, trying manual compilation..."

  # Manual fallback compilation
  cd $CARLA_ROOT/Examples/CppClient

  echo "🔨 Falling back to manual compilation..."

  g++ -std=c++17 -pthread -fPIC -O2 -DNDEBUG \
    -I$INSTALL_DIR/include \
    -I$CARLA_ROOT/Build/boost-1.90.0-c10-install/include \
    -I$CARLA_ROOT/Build/rpclib-carla-callbacks-c10-libcxx-install/include \
    -I$CARLA_ROOT/Build/recast-c10-install/include \
    -L$INSTALL_DIR/lib \
    -L$CARLA_ROOT/Build/boost-1.90.0-c10-install/lib \
    -L$CARLA_ROOT/Build/rpclib-carla-callbacks-c10-libcxx-install/lib \
    -L$CARLA_ROOT/Build/recast-c10-install/lib \
    -o $BIN_DIR/cpp_client main.cpp \
    -Wl,-Bstatic \
    -lboost_filesystem \
    -lrpc \
    -lRecast \
    -lDetour \
    -lDetourCrowd \
    -Wl,-Bdynamic \
    -lstdc++ -lm 2>&1 | tail -30
fi

# Step 10: Verify
echo ""
echo "✅ Build verification:"
if [ -f "$BIN_DIR/cpp_client" ]; then
  file $BIN_DIR/cpp_client
  ls -lh $BIN_DIR/cpp_client
  echo ""
  echo "🎉 SUCCESS! Binary ready at: $BIN_DIR/cpp_client"
  echo ""
  echo "To test:"
  echo "  $BIN_DIR/cpp_client localhost 2000"
else
  echo "❌ Binary not created. Build may have failed."
  exit 1
fi

# Cleanup
# rm -rf $BUILD_DIR
