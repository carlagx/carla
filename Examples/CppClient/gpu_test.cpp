// GPU performance test: spawns a vehicle on autopilot plus N RGB cameras,
// lets it drive for a fixed time and reports frame rates and nvidia-smi load.
//
// Usage: gpu_test [host port [seconds [cameras [width height]]]]

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include <carla/actors/ActorBlueprint.h>
#include <carla/actors/BlueprintLibrary.h>
#include <carla/client/Client.h>
#include <carla/client/Map.h>
#include <carla/client/Sensor.h>
#include <carla/client/TimeoutException.h>
#include <carla/client/Vehicle.h>
#include <carla/client/World.h>
#include <carla/geom/Transform.h>
#include <carla/sensor/data/Image.h>
#include <carla/trafficmanager/TrafficManager.h>

namespace cc = carla::client;
namespace cg = carla::geom;
namespace csd = carla::sensor::data;
namespace ctm = carla::traffic_manager;

using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

static const auto TIMEOUT = 60s;

/// Query "util%, used MiB, watts" from nvidia-smi; empty on failure.
static std::string QueryGpu() {
  std::unique_ptr<FILE, int (*)(FILE *)> pipe(
      popen("nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw "
            "--format=csv,noheader,nounits 2>/dev/null", "r"), pclose);
  if (!pipe) return {};
  char buf[128];
  std::string out;
  while (fgets(buf, sizeof(buf), pipe.get())) out += buf;
  while (!out.empty() && (out.back() == '\n' || out.back() == '\r')) out.pop_back();
  return out;
}

int main(int argc, const char *argv[]) {
  std::vector<carla::SharedPtr<cc::Actor>> actors;
  try {
    const std::string host = argc > 2 ? argv[1] : "localhost";
    const uint16_t port = argc > 2 ? static_cast<uint16_t>(std::stoi(argv[2])) : 2000;
    const int seconds = argc > 3 ? std::stoi(argv[3]) : 10;
    const int cameras = argc > 4 ? std::stoi(argv[4]) : 4;
    const std::string width = argc > 6 ? argv[5] : "1280";
    const std::string height = argc > 6 ? argv[6] : "720";

    cc::Client client(host, port);
    client.SetTimeout(TIMEOUT);
    std::cout << "Server " << client.GetServerVersion()
              << ", map " << client.GetWorld().GetMap()->GetName() << '\n';

    auto world = client.GetWorld();
    auto library = world.GetBlueprintLibrary();

    // Vehicle on autopilot.
    auto vehicle_bp = *library->Find("vehicle.tesla.model3");
    auto spawn_points = world.GetMap()->GetRecommendedSpawnPoints();
    if (spawn_points.empty()) throw std::runtime_error("no spawn points");
    carla::SharedPtr<cc::Actor> vehicle;
    for (const auto &t : spawn_points) {
      vehicle = world.TrySpawnActor(vehicle_bp, t);
      if (vehicle) break;
    }
    if (!vehicle) throw std::runtime_error("no free spawn point");
    actors.push_back(vehicle);
    boost::static_pointer_cast<cc::Vehicle>(vehicle)->SetAutopilot(true);

    // Cameras attached to the vehicle; each one is rendered by the GPU.
    auto camera_bp = *library->Find("sensor.camera.rgb");
    camera_bp.SetAttribute("image_size_x", width);
    camera_bp.SetAttribute("image_size_y", height);
    camera_bp.SetAttribute("sensor_tick", "0.0");
    std::atomic<uint64_t> frames{0};
    std::atomic<uint64_t> bytes{0};
    for (int i = 0; i < cameras; ++i) {
      cg::Transform t(cg::Location(1.5f, 0.0f, 2.0f), cg::Rotation(-5.0f, 90.0f * i, 0.0f));
      auto cam = boost::static_pointer_cast<cc::Sensor>(
          world.SpawnActor(camera_bp, t, vehicle.get()));
      actors.push_back(cam);
      cam->Listen([&](carla::SharedPtr<carla::sensor::SensorData> data) {
        auto img = boost::static_pointer_cast<csd::Image>(data);
        ++frames;
        bytes += img->size() * sizeof(csd::Color);
      });
    }
    std::cout << cameras << " camera(s) @ " << width << "x" << height
              << ", running " << seconds << " s\n"
              << "GPU before (util%, MiB, W): " << QueryGpu() << '\n';

    // Measure server ticks for the duration. Works in async and sync mode.
    std::vector<double> gpu_util;
    uint64_t ticks = 0;
    double max_tick_ms = 0.0;
    const auto start = Clock::now();
    auto last = start;
    auto next_sample = start + 1s;
    float max_speed = 0.0f;
    while (Clock::now() - start < std::chrono::seconds(seconds)) {
      world.WaitForTick(TIMEOUT);
      const auto now = Clock::now();
      max_tick_ms = std::max(max_tick_ms,
          std::chrono::duration<double, std::milli>(now - last).count());
      last = now;
      ++ticks;
      max_speed = std::max(max_speed,
          3.6f * boost::static_pointer_cast<cc::Vehicle>(vehicle)->GetVelocity().Length());
      if (now >= next_sample) {
        next_sample += 1s;
        const auto s = QueryGpu();
        std::cout << "  t=" << std::chrono::duration_cast<std::chrono::seconds>(now - start).count()
                  << "s  GPU: " << s << "  camera frames so far: " << frames << '\n';
        gpu_util.push_back(std::atof(s.c_str()));
      }
    }
    const double elapsed = std::chrono::duration<double>(Clock::now() - start).count();

    double avg_util = 0;
    for (double u : gpu_util) avg_util += u;
    if (!gpu_util.empty()) avg_util /= gpu_util.size();

    std::cout << std::fixed << std::setprecision(1)
              << "\n===== Result =====\n"
              << "Duration            : " << elapsed << " s\n"
              << "Server ticks/s      : " << ticks / elapsed << "  (slowest tick " << max_tick_ms << " ms)\n"
              << "Camera frames/s     : " << frames / elapsed << "  (total " << frames << ")\n"
              << "Camera data rate    : " << bytes / elapsed / 1e6 << " MB/s\n"
              << "Avg GPU util        : " << avg_util << " %\n"
              << "Max vehicle speed   : " << max_speed << " km/h\n"
              << "GPU after (util%, MiB, W): " << QueryGpu() << std::endl;
  } catch (const cc::TimeoutException &e) {
    std::cout << "\nTimeout: " << e.what() << std::endl;
    for (auto &a : actors) { try { a->Destroy(); } catch (...) {} }
    return 1;
  } catch (const std::exception &e) {
    std::cout << "\nException: " << e.what() << std::endl;
    for (auto &a : actors) { try { a->Destroy(); } catch (...) {} }
    try { ctm::TrafficManager::Release(); } catch (...) {}
    return 2;
  }
  for (auto it = actors.rbegin(); it != actors.rend(); ++it) {
    if (auto s = boost::dynamic_pointer_cast<cc::Sensor>(*it)) s->Stop();
    (*it)->Destroy();
  }
  try { ctm::TrafficManager::Release(); } catch (...) {}
  return 0;
}
