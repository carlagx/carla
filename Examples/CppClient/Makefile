CARLADIR=$(CURDIR)/../..
BUILDDIR=$(CURDIR)/build
BINDIR=$(CURDIR)/bin
INSTALLDIR=$(CURDIR)/libcarla-install
TOOLCHAIN=$(CURDIR)/ToolChain.cmake

# The client must use the LibCarla of the server's CARLA version, otherwise
# sensor data and controls are misread. To build against another checkout,
# e.g. for a 0.9.16 server:
#   git worktree add --detach ../carla-0.9.16 0.9.16
#   make manual_control CARLA_SRC=/path/to/carla-0.9.16
# Build, install and binaries then go to *-<checkout name>, e.g. bin-carla-0.9.16.
ifdef CARLA_SRC
CARLADIR=$(abspath $(CARLA_SRC))
CHECKOUT=-$(notdir $(CARLADIR))
BUILDDIR=$(CURDIR)/build$(CHECKOUT)
BINDIR=$(CURDIR)/bin$(CHECKOUT)
INSTALLDIR=$(CURDIR)/libcarla-install$(CHECKOUT)
endif

CC=/usr/bin/gcc
CXX=/usr/bin/g++
CXXFLAGS=-std=c++17 -pthread -fPIC -O3 -DNDEBUG -Wall -Wextra

define log
	@echo "\033[1;35m$(1)\033[0m"
endef

default: build

clean:
	@rm -rf $(BUILDDIR) $(INSTALLDIR)
	@rm -f ToolChain.cmake

run: build
	$(call log,Running C++ Client...)
	@$(BINDIR)/cpp_client $(ARGS)

run.only:
	$(call log,Running C++ Client...)
	@$(BINDIR)/cpp_client $(ARGS)

build: $(BINDIR)/cpp_client

$(BINDIR)/cpp_client: main.cpp | build_libcarla
	$(call log,Compiling C++ Client...)
	@mkdir -p $(BINDIR)
	@$(CXX) $(CXXFLAGS) -I$(INSTALLDIR)/include -isystem $(INSTALLDIR)/include/system -L$(INSTALLDIR)/lib \
		-o $(BINDIR)/cpp_client main.cpp \
		-Wl,-Bstatic -lcarla_client -lrpc -lboost_filesystem -Wl,-Bdynamic \
		-lpng -ltiff -ljpeg -lRecast -lDetour -lDetourCrowd

build_libcarla: $(TOOLCHAIN)
	@cd $(CARLADIR); make setup
	@mkdir -p $(BUILDDIR)
	$(call log,Compiling LibCarla.client...)
	@{ \
		cd $(BUILDDIR); \
		if [ ! -f "build.ninja" ]; then \
		cmake \
			-G "Ninja" \
			-DCMAKE_BUILD_TYPE=Client \
			-DLIBCARLA_BUILD_RELEASE=ON \
			-DLIBCARLA_BUILD_DEBUG=OFF \
			-DLIBCARLA_BUILD_TEST=OFF \
			-DCMAKE_TOOLCHAIN_FILE=$(TOOLCHAIN) \
			-DCMAKE_INSTALL_PREFIX=$(INSTALLDIR) \
			-DCMAKE_EXPORT_COMPILE_COMMANDS=1 \
			$(CARLADIR); \
	  fi; \
		ninja; \
		ninja install | grep -v "Up-to-date:"; \
	}

$(TOOLCHAIN):
	@echo "set(CMAKE_C_COMPILER $(CC))" > $(TOOLCHAIN)
	@echo "set(CMAKE_CXX_COMPILER $(CXX))" >> $(TOOLCHAIN)
	@echo "set(CMAKE_CXX_FLAGS \"\$${CMAKE_CXX_FLAGS} $(CXXFLAGS)\" CACHE STRING \"\" FORCE)" >> $(TOOLCHAIN)

# GPU performance test client (vehicle + cameras, 10 s by default)
.PHONY: gpu_test run.gpu_test
gpu_test: $(BINDIR)/gpu_test

run.gpu_test: gpu_test
	@$(BINDIR)/gpu_test $(ARGS)

$(BINDIR)/gpu_test: gpu_test.cpp | build_libcarla
	$(call log,Compiling GPU test client...)
	@mkdir -p $(BINDIR)
	@$(CXX) $(CXXFLAGS) -I$(INSTALLDIR)/include -isystem $(INSTALLDIR)/include/system -L$(INSTALLDIR)/lib \
		-o $(BINDIR)/gpu_test gpu_test.cpp \
		-Wl,-Bstatic -lcarla_client -lrpc -lboost_filesystem -Wl,-Bdynamic \
		-lpng -ltiff -ljpeg -lRecast -lDetour -lDetourCrowd

# Keyboard-controlled vehicle (C++ port of PythonAPI/examples/manual_control.py).
# Needs SDL2 and SDL2_ttf: sudo apt install libsdl2-dev libsdl2-ttf-dev
SDL_CFLAGS ?= $(shell pkg-config --cflags sdl2 SDL2_ttf)
SDL_LIBS ?= $(shell pkg-config --libs sdl2 SDL2_ttf)

.PHONY: manual_control run.manual_control
manual_control: $(BINDIR)/manual_control

run.manual_control: manual_control
	@$(BINDIR)/manual_control $(ARGS)

$(BINDIR)/manual_control: manual_control.cpp | build_libcarla
	$(call log,Compiling manual control client...)
	@mkdir -p $(BINDIR)
	@$(CXX) $(CXXFLAGS) -I$(INSTALLDIR)/include -isystem $(INSTALLDIR)/include/system -L$(INSTALLDIR)/lib \
		$(SDL_CFLAGS) -o $(BINDIR)/manual_control manual_control.cpp \
		-Wl,-Bstatic -lcarla_client -lrpc -lboost_filesystem -Wl,-Bdynamic \
		-lpng -ltiff -ljpeg -lRecast -lDetour -lDetourCrowd $(SDL_LIBS)

# Same keyboard-controlled vehicle with GTK3 + Cairo instead of SDL2. Needs no extra
# packages on Ubuntu desktops that can build against GTK (libgtk-3-dev), and uses
# the system fonts through fontconfig.
GTK_CFLAGS ?= $(shell pkg-config --cflags gtk+-3.0)
GTK_LIBS ?= $(shell pkg-config --libs gtk+-3.0)

.PHONY: manual_control_gtk run.manual_control_gtk
manual_control_gtk: $(BINDIR)/manual_control_gtk

run.manual_control_gtk: manual_control_gtk
	@$(BINDIR)/manual_control_gtk $(ARGS)

$(BINDIR)/manual_control_gtk: manual_control_gtk.cpp | build_libcarla
	$(call log,Compiling GTK manual control client...)
	@mkdir -p $(BINDIR)
	@$(CXX) $(CXXFLAGS) -I$(INSTALLDIR)/include -isystem $(INSTALLDIR)/include/system -L$(INSTALLDIR)/lib \
		$(GTK_CFLAGS) -o $(BINDIR)/manual_control_gtk manual_control_gtk.cpp \
		-Wl,-Bstatic -lcarla_client -lrpc -lboost_filesystem -Wl,-Bdynamic \
		-lpng -ltiff -ljpeg -lRecast -lDetour -lDetourCrowd $(GTK_LIBS)
