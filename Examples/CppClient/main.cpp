#include <algorithm>
#include <chrono>
#include <iomanip>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <thread>
#include <tuple>
#include <utility>

#include <carla/actors/ActorBlueprint.h>
#include <carla/actors/BlueprintLibrary.h>
#include <carla/client/Client.h>
#include <carla/client/Map.h>
#include <carla/client/TimeoutException.h>
#include <carla/client/Vehicle.h>
#include <carla/client/World.h>
#include <carla/geom/Transform.h>
#include <carla/trafficmanager/TrafficManager.h>

namespace ca = carla::actors;
namespace cc = carla::client;
namespace ctm = carla::traffic_manager;

using namespace std::chrono_literals;
using namespace std::string_literals;

#define EXPECT_TRUE(pred) if (!(pred)) { throw std::runtime_error(#pred); }

/// Map the vehicle is supposed to drive in.
static const std::string MAP_NAME = "Town06";

/// A cold map load also triggers shader builds, which block the simulator for
/// far longer than the usual handful of seconds.
static const auto TIMEOUT = 600s;

/// Distance the vehicle covers on autopilot before it is braked to a halt.
static const float DEFAULT_DRIVE_DISTANCE = 20.0f;

/// The autopilot obeys traffic lights and other cars, so the vehicle can
/// legitimately stand still for a while. Give up rather than hang forever.
static const auto DRIVE_TIMEOUT = 120s;

/// Below this speed the vehicle counts as standing still.
static const float STANDSTILL_SPEED = 0.1f;

/// Pick a random element from @a range.
template <typename RangeT, typename RNG>
static auto &RandomChoice(const RangeT &range, RNG &&generator) {
  EXPECT_TRUE(range.size() > 0u);
  std::uniform_int_distribution<size_t> dist{0u, range.size() - 1u};
  return range[dist(std::forward<RNG>(generator))];
}

static auto ParseArguments(int argc, const char *argv[]) {
  EXPECT_TRUE((argc == 1) || (argc == 3) || (argc == 4));
  using ResultType = std::tuple<std::string, uint16_t, float>;
  if (argc == 1) {
    return ResultType{"localhost", 2000u, DEFAULT_DRIVE_DISTANCE};
  }
  return ResultType{
      argv[1u],
      static_cast<uint16_t>(std::stoi(argv[2u])),
      argc == 4 ? std::stof(argv[3u]) : DEFAULT_DRIVE_DISTANCE};
}

/// Pick a random four-wheeled vehicle, so the autopilot behaves predictably,
/// and randomize its color when it has one.
static ca::ActorBlueprint PickVehicle(const cc::World &world, std::mt19937_64 &rng) {
  auto library = world.GetBlueprintLibrary();
  auto vehicles = library->Filter("vehicle.*");
  EXPECT_TRUE(vehicles->size() > 0u);
  auto cars = vehicles->FilterByAttribute("number_of_wheels", "4");

  auto blueprint = RandomChoice((cars->size() > 0u) ? *cars : *vehicles, rng);

  if (blueprint.ContainsAttribute("color")) {
    const auto &attribute = blueprint.GetAttribute("color");
    blueprint.SetAttribute(
        "color",
        RandomChoice(attribute.GetRecommendedValues(), rng));
  }
  return blueprint;
}

/// Try the recommended spawn points in random order until one is free. Points
/// can be occupied by traffic already present in the episode, so spawning at a
/// single fixed point is unreliable.
static carla::SharedPtr<cc::Actor> SpawnVehicle(
    cc::World &world,
    const ca::ActorBlueprint &blueprint,
    std::mt19937_64 &rng) {
  auto map = world.GetMap();
  auto spawn_points = map->GetRecommendedSpawnPoints();
  EXPECT_TRUE(spawn_points.size() > 0u);
  std::shuffle(spawn_points.begin(), spawn_points.end(), rng);

  for (const auto &transform : spawn_points) {
    auto actor = world.TrySpawnActor(blueprint, transform);
    if (actor != nullptr) {
      return actor;
    }
  }
  throw std::runtime_error("no free spawn point left in "s + map->GetName());
}

/// Place the spectator behind and above the vehicle, looking its way.
static void ChaseWithSpectator(
    const carla::SharedPtr<cc::Actor> &spectator,
    const carla::geom::Transform &vehicle_transform) {
  auto camera = vehicle_transform;
  camera.location -= 8.0f * vehicle_transform.GetForwardVector();
  camera.location.z += 3.5f;
  camera.rotation.pitch = -12.0f;
  spectator->SetTransform(camera);
}

int main(int argc, const char *argv[]) {
  carla::SharedPtr<cc::Vehicle> vehicle;
  try {

    std::string host;
    uint16_t port;
    float drive_distance;
    std::tie(host, port, drive_distance) = ParseArguments(argc, argv);

    std::mt19937_64 rng((std::random_device())());

    auto client = cc::Client(host, port);
    client.SetTimeout(TIMEOUT);

    std::cout << "Client API version : " << client.GetClientVersion() << '\n';
    std::cout << "Server API version : " << client.GetServerVersion() << '\n';

    // Loading a map is expensive, so only switch when a different one is
    // active. Repeated runs against an already loaded Town06 start instantly.
    std::cout << "Current map        : "
              << client.GetWorld().GetMap()->GetName() << '\n';
    client.LoadWorldIfDifferent(MAP_NAME);

    auto world = client.GetWorld();
    std::cout << "Active map         : " << world.GetMap()->GetName() << '\n';

    auto blueprint = PickVehicle(world, rng);
    auto actor = SpawnVehicle(world, blueprint, rng);
    vehicle = boost::static_pointer_cast<cc::Vehicle>(actor);
    std::cout << "Spawned            : " << actor->GetDisplayId() << '\n';

    auto spectator = world.GetSpectator();
    ChaseWithSpectator(spectator, vehicle->GetTransform());

    // Hand the vehicle over to the Traffic Manager. This also starts a local
    // TM instance on TM_DEFAULT_PORT (8000) if none is running yet, which then
    // steers, brakes and obeys traffic lights on its own.
    vehicle->SetAutopilot(true);

    auto traffic_manager = client.GetInstanceTM();
    traffic_manager.SetAutoLaneChange(actor, false);  // keep it on its lane

    std::cout << std::fixed << std::setprecision(1)
              << "Driving " << drive_distance << " m on autopilot...\n";

    // Sum up the path actually covered, rather than the straight-line offset
    // from the spawn point, so a curve still counts its real length.
    auto last_location = vehicle->GetLocation();
    float covered = 0.0f;
    const auto started = std::chrono::steady_clock::now();
    auto next_report = started;

    while (covered < drive_distance) {
      if (std::chrono::steady_clock::now() - started > DRIVE_TIMEOUT) {
        std::cout << "Autopilot covered only " << covered
                  << " m before timing out.\n";
        break;
      }

      world.WaitForTick(TIMEOUT);

      const auto transform = vehicle->GetTransform();
      covered += transform.location.Distance(last_location);
      last_location = transform.location;

      ChaseWithSpectator(spectator, transform);

      const auto now = std::chrono::steady_clock::now();
      if (now >= next_report) {
        next_report = now + 1s;
        std::cout << "  " << covered << " m"
                  << "  speed=" << 3.6f * vehicle->GetVelocity().Length()
                  << " km/h\n";
      }
    }

    // Take control back from the Traffic Manager and brake to a standstill.
    vehicle->SetAutopilot(false);

    cc::Vehicle::Control stop;
    stop.throttle = 0.0f;
    stop.steer = 0.0f;
    stop.brake = 1.0f;
    stop.hand_brake = true;
    vehicle->ApplyControl(stop);

    const auto braking_started = std::chrono::steady_clock::now();
    while (vehicle->GetVelocity().Length() > STANDSTILL_SPEED) {
      if (std::chrono::steady_clock::now() - braking_started > DRIVE_TIMEOUT) {
        std::cout << "Vehicle did not come to a full stop.\n";
        break;
      }
      world.WaitForTick(TIMEOUT);
      covered += vehicle->GetLocation().Distance(last_location);
      last_location = vehicle->GetLocation();
      ChaseWithSpectator(spectator, vehicle->GetTransform());
    }

    ctm::TrafficManager::Release();

    const auto location = vehicle->GetLocation();
    std::cout << "Stopped after " << covered << " m at ("
              << location.x << ", " << location.y << ", " << location.z << ").\n"
              << "Vehicle " << actor->GetDisplayId()
              << " is left standing in the episode." << std::endl;

  } catch (const cc::TimeoutException &e) {
    std::cout << '\n' << e.what() << std::endl;
    return 1;
  } catch (const std::exception &e) {
    // A vehicle left behind mid-drive would keep driving on autopilot.
    if (vehicle != nullptr) {
      try { vehicle->Destroy(); } catch (...) {}
    }
    try { ctm::TrafficManager::Release(); } catch (...) {}
    std::cout << "\nException: " << e.what() << std::endl;
    return 2;
  }
}
