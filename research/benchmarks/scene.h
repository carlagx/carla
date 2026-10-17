// Synthetic scene shared by bench_sdl.cpp and bench_gtk.cpp, so that both frameworks
// draw exactly the same thing: a 1280x720 camera picture that changes every frame, a
// translucent HUD panel with 28 text lines, three bars, a 200 point graph and a
// notification strip; 9 text lines change on every frame. The drawing code mirrors what manual_control.cpp and
// manual_control_gtk.cpp do per frame (text is rendered anew every frame, as there).
#pragma once

#include <sys/resource.h>
#include <time.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

// Picture size; override with -DBENCH_W=1920 -DBENCH_H=1080 to measure other resolutions.
#ifndef BENCH_W
#define BENCH_W 1280
#define BENCH_H 720
#endif
constexpr int W = BENCH_W;
constexpr int H = BENCH_H;
constexpr int kPictures = 8;      // distinct camera pictures, cycled
constexpr double kFps = 60.0;

struct Scene {
  std::vector<std::vector<uint8_t>> pictures;  // BGRA8, alpha 255
  std::vector<std::string> lines;  // template; Lines() makes some of them change every frame
  std::vector<float> graph;

  Scene() {
    pictures.resize(kPictures);
    for (int f = 0; f < kPictures; ++f) {
      auto &px = pictures[f];
      px.resize(static_cast<size_t>(W) * H * 4);
      uint32_t seed = 2463534242u + static_cast<uint32_t>(f);
      for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
          seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
          const size_t i = (static_cast<size_t>(y) * W + x) * 4;
          px[i + 0] = static_cast<uint8_t>(x * 255 / W);                    // B
          px[i + 1] = static_cast<uint8_t>(y * 255 / H);                    // G
          px[i + 2] = static_cast<uint8_t>((f * 32 + (seed & 31)) & 255);   // R
          px[i + 3] = 255;
        }
      }
    }
    const char *fixed[] = {"Vehicle:             Audi A2", "Map:                 Town06",
                           "Simulation time:    0:02:12", "Speed:              57 km/h",
                           "Compass:            90\xC2\xB0  E", "Accelero: ( 5.4, -0.0,  9.7)",
                           "Gyroscop: (-0.0, -1.2,  0.0)", "Location:     (576.5, 38.2)",
                           "GNSS:   (0.000343, 0.005189)", "Height:                -0 m",
                           "Throttle:", "Steer:", "Brake:", "Reverse:", "Hand brake:", "Manual:",
                           "Gear:        4", "Collision:", "Number of vehicles:        2",
                           "Nearby vehicles:", "  30m Audi A2", "  58m Tesla Model3",
                           "  75m Mercedes Coupe", "  90m Dodge Charger", "Server:   47 FPS",
                           "Client:   60 FPS", "Weather: Clear Noon", "Layer: MapLayer.All"};
    for (const char *line : fixed) lines.emplace_back(line);
    graph.resize(200);
    for (size_t i = 0; i < graph.size(); ++i) graph[i] = (i % 40) < 5 ? 0.8f : 0.05f;
  }

  // The HUD of the real programs changes its numbers on every frame while driving
  // (time, speed, accelerometer, gyroscope, location, GNSS, height, FPS): 9 of the 28 lines.
  std::vector<std::string> Lines(int frame) const {
    static const int kDynamic[] = {2, 3, 5, 6, 7, 8, 9, 24, 25};
    std::vector<std::string> out = lines;
    char buffer[64];
    for (int index : kDynamic) {
      std::snprintf(buffer, sizeof(buffer), "%s #%d", lines[index].substr(0, 18).c_str(), frame % 100000);
      out[index] = buffer;
    }
    return out;
  }
};

inline double Now() {
  timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return static_cast<double>(t.tv_sec) + static_cast<double>(t.tv_nsec) * 1e-9;
}

inline double CpuSeconds() {
  rusage u;
  getrusage(RUSAGE_SELF, &u);
  return static_cast<double>(u.ru_utime.tv_sec + u.ru_stime.tv_sec) +
         static_cast<double>(u.ru_utime.tv_usec + u.ru_stime.tv_usec) * 1e-6;
}

inline double UserSeconds() {
  rusage u;
  getrusage(RUSAGE_SELF, &u);
  return static_cast<double>(u.ru_utime.tv_sec) + static_cast<double>(u.ru_utime.tv_usec) * 1e-6;
}

inline double MaxRssMb() {
  rusage u;
  getrusage(RUSAGE_SELF, &u);
  return static_cast<double>(u.ru_maxrss) / 1024.0;
}

// Collects the time the drawing code needs per frame and prints one result line.
class Stats {
public:
  void Begin() { wall0_ = Now(); cpu0_ = CpuSeconds(); user0_ = UserSeconds(); }
  void Add(double seconds) { draw_ms_.push_back(seconds * 1000.0); }

  void Report(const char *name) const {
    std::vector<double> v = draw_ms_;
    std::sort(v.begin(), v.end());
    const double wall = Now() - wall0_;
    const double cpu = CpuSeconds() - cpu0_;
    const double user = UserSeconds() - user0_;
    double sum = 0;
    for (double d : v) sum += d;
    auto pct = [&](double p) { return v.empty() ? 0.0 : v[std::min(v.size() - 1, static_cast<size_t>(p * v.size()))]; };
    std::printf("%-27s frames=%zu fps=%.1f cpu=%.1f%% (user %.1f%% sys %.1f%%) draw_ms mean=%.2f p50=%.2f p99=%.2f max=%.2f maxrss=%.0fMB\n",
                name, v.size(), static_cast<double>(v.size()) / wall, 100.0 * cpu / wall,
                100.0 * user / wall, 100.0 * (cpu - user) / wall,
                v.empty() ? 0.0 : sum / static_cast<double>(v.size()), pct(0.50), pct(0.99),
                v.empty() ? 0.0 : v.back(), MaxRssMb());
    std::fflush(stdout);
  }

private:
  std::vector<double> draw_ms_;
  double wall0_ = 0;
  double cpu0_ = 0;
  double user0_ = 0;
};

// First readable font out of the usual places (SDL_ttf needs a path, Pango does not).
inline std::string FindMonoFont(const char *override_path) {
  if (override_path) return override_path;
  const char *candidates[] = {
      "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",            // Debian, Ubuntu
      "/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf",     // Fedora
      "/usr/share/fonts/dejavu/DejaVuSansMono.ttf",                     // openSUSE, Alpine
      "/usr/share/fonts/TTF/DejaVuSansMono.ttf",                        // Arch
  };
  for (const char *path : candidates) {
    if (FILE *f = std::fopen(path, "rb")) {
      std::fclose(f);
      return path;
    }
  }
  return {};
}
