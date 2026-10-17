// Keyboard-controlled vehicle (or walker) for CARLA: C++ counterpart of
// PythonAPI/examples/manual_control.py, using GTK3 + Cairo + Pango instead of
// pygame. Same features as manual_control.cpp (the SDL2 version), but it only
// needs libraries that Ubuntu desktops ship with: no SDL2, no SDL2_ttf, and the
// fonts come from fontconfig.
//
// Usage: manual_control_gtk [--config FILE] [--host H] [-p PORT] [-a] [--res WIDTHxHEIGHT]
//                           [--filter PATTERN] [--generation G] [--rolename NAME]
//                           [--gamma G] [--sync] [--screenshot FILE.png [--screenshot-delay S]]
//
// Defaults to vehicle.audi.a2 and reads CARLA_HOST, CARLA_PORT, VEHICLE and
// CPP_GTK_ARGS from carla.conf (see PrintUsage); command line options win.

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <clocale>
#include <cstdio>
#include <deque>
#include <csignal>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <random>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <unistd.h>

#include <gdk/gdkkeysyms.h>
#include <gtk/gtk.h>
#include <pango/pangocairo.h>

// The blueprint classes moved from carla::client to carla::actors after 0.9.16;
// both layouts are supported so the client can be built for a 0.9.16 server.
#if __has_include(<carla/actors/ActorBlueprint.h>)
#include <carla/actors/ActorBlueprint.h>
#include <carla/actors/BlueprintLibrary.h>
namespace ca = carla::actors;
#else
#include <carla/client/ActorBlueprint.h>
#include <carla/client/BlueprintLibrary.h>
namespace ca = carla::client;
#endif
#include <carla/client/ActorList.h>
#include <carla/client/Client.h>
#include <carla/client/DebugHelper.h>
#include <carla/client/Map.h>
#include <carla/client/Sensor.h>
#include <carla/client/Vehicle.h>
#include <carla/client/Walker.h>
#include <carla/client/World.h>
#include <carla/geom/Transform.h>
#include <carla/image/CityScapesPalette.h>
#include <carla/rpc/AttachmentType.h>
#include <carla/rpc/MapLayer.h>
#include <carla/rpc/VehicleLightState.h>
#include <carla/rpc/WeatherParameters.h>
#include <carla/sensor/data/CollisionEvent.h>
#include <carla/sensor/data/DVSEventArray.h>
#include <carla/sensor/data/GnssMeasurement.h>
#include <carla/sensor/data/IMUMeasurement.h>
#include <carla/sensor/data/Image.h>
#include <carla/sensor/data/LaneInvasionEvent.h>
#include <carla/sensor/data/LidarMeasurement.h>
#include <carla/sensor/data/RadarMeasurement.h>
#include <carla/trafficmanager/TrafficManager.h>

namespace cc = carla::client;
namespace cg = carla::geom;
namespace crpc = carla::rpc;
namespace csd = carla::sensor::data;

using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;
using SensorDataPtr = carla::SharedPtr<carla::sensor::SensorData>;
using LightState = crpc::VehicleLightState::LightState;
using LightFlags = uint32_t;

static const auto TIMEOUT = 2000s;  // same client timeout as the Python example
static const char *RECORDING_FILE = "manual_recording.log";
static constexpr double kPi = 3.14159265358979323846;

static const char *kHelpText = R"(Welcome to CARLA manual control.

Use ARROWS or WASD keys for control.

    W            : throttle
    S            : brake
    A/D          : steer left/right
    Q            : toggle reverse
    Space        : hand-brake
    P            : toggle autopilot
    M            : toggle manual transmission
    ,/.          : gear up/down
    CTRL + W     : toggle constant velocity mode at 60 km/h

    L            : toggle next light type
    SHIFT + L    : toggle high beam
    Z/X          : toggle right/left blinker
    I            : toggle interior light

    TAB          : change sensor position
    ` or N       : next sensor
    [1-9]        : change to sensor [1-9]
    G            : toggle radar visualization
    C            : change weather (Shift+C reverse)
    Backspace    : change vehicle

    O            : open/close all doors of vehicle
    T            : toggle vehicle's telemetry

    V            : Select next map layer (Shift+V reverse)
    B            : Load current selected map layer (Shift+B to unload)

    R            : toggle recording images to disk

    CTRL + R     : toggle recording of simulation (replacing any previous)
    CTRL + P     : start replaying last recorded simulation
    CTRL + +     : increments the start time of the replay by 1 second (+SHIFT = 10 seconds)
    CTRL + -     : decrements the start time of the replay by 1 second (+SHIFT = 10 seconds)

    F1           : toggle HUD
    H/?          : toggle help
    ESC          : quit
)";

// ==============================================================================
// -- Global functions ----------------------------------------------------------
// ==============================================================================

// Ctrl+C / SIGTERM: the first one ends the game loop cleanly (actors destroyed,
// settings restored, like KeyboardInterrupt in the Python example); a second one
// exits at once, e.g. while still blocked waiting for the server.
static volatile std::sig_atomic_t g_quit_requested = 0;

static void OnQuitSignal(int signal) {
  if (g_quit_requested) std::_Exit(128 + signal);
  g_quit_requested = 1;
  const char message[] = "\nStopping... press Ctrl+C again to quit immediately.\n";
  [[maybe_unused]] const auto written = write(STDERR_FILENO, message, sizeof(message) - 1);
}

static std::string Format(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

static std::string Format(const char *fmt, ...) {
  char buffer[512];
  va_list args;
  va_start(args, fmt);
  vsnprintf(buffer, sizeof(buffer), fmt, args);
  va_end(args);
  return buffer;
}

static bool StartsWith(const std::string &text, const std::string &prefix) {
  return text.rfind(prefix, 0) == 0;
}

// Python: ' '.join(type_id.replace('_', '.').title().split('.')[1:])
static std::string GetActorDisplayName(std::string type_id, size_t truncate = 250) {
  std::replace(type_id.begin(), type_id.end(), '_', '.');
  std::vector<std::string> words;
  std::stringstream stream(type_id);
  std::string part;
  while (std::getline(stream, part, '.')) {
    for (size_t i = 0; i < part.size(); ++i) {
      part[i] = static_cast<char>(i == 0 ? std::toupper(part[i]) : std::tolower(part[i]));
    }
    words.push_back(part);
  }
  std::string name;
  for (size_t i = 1; i < words.size(); ++i) {
    if (!name.empty()) name += ' ';
    name += words[i];
  }
  if (name.size() > truncate) name = name.substr(0, truncate - 1) + "\xE2\x80\xA6";  // ellipsis
  return name;
}

// "ClearNoon" -> "Clear Noon", like find_weather_presets() in the Python example.
static std::string SplitCamelCase(const std::string &name) {
  std::string out;
  for (size_t i = 0; i < name.size(); ++i) {
    if (i > 0 && std::isupper(name[i]) &&
        (std::islower(name[i - 1]) ||
         (i + 1 < name.size() && std::isupper(name[i - 1]) && std::islower(name[i + 1])))) {
      out += ' ';
    }
    out += name[i];
  }
  return out;
}

static std::string FormatDuration(long seconds) {  // like str(datetime.timedelta)
  return Format("%ld:%02ld:%02ld", seconds / 3600, (seconds % 3600) / 60, seconds % 60);
}

static double Degrees(double radians) {
  return radians * 180.0 / kPi;
}

static double Round(double value, int digits) {
  const double scale = std::pow(10.0, digits);
  return std::round(value * scale) / scale;
}

static size_t StepIndex(size_t index, size_t size, bool reverse) {
  return (index + size + (reverse ? size - 1 : 1)) % size;
}

template <typename T>
static const T &Pick(const std::vector<T> &items, std::mt19937 &rng) {
  std::uniform_int_distribution<size_t> dist(0, items.size() - 1);
  return items[dist(rng)];
}

static LightFlags Flag(LightState state) {
  return static_cast<LightFlags>(state);
}

// Client::ReplayFile gained replay_weather and map_override after 0.9.16; the
// int/long overloads pick whichever signature this LibCarla provides.
template <typename C>
static auto ReplayFile(C &client, const std::string &name, double start, int)
    -> decltype(client.ReplayFile(name, start, 0.0, 0u, false, true, cg::Transform(), std::string())) {
  return client.ReplayFile(name, start, 0.0, 0u, false, true, cg::Transform(), std::string());
}

template <typename C>
static auto ReplayFile(C &client, const std::string &name, double start, long)
    -> decltype(client.ReplayFile(name, start, 0.0, 0u, false, cg::Transform())) {
  return client.ReplayFile(name, start, 0.0, 0u, false, cg::Transform());
}

static const char *LaneMarkingName(carla::road::element::LaneMarking::Type type) {
  using Type = carla::road::element::LaneMarking::Type;
  switch (type) {
    case Type::Other: return "Other";
    case Type::Broken: return "Broken";
    case Type::Solid: return "Solid";
    case Type::SolidSolid: return "SolidSolid";
    case Type::SolidBroken: return "SolidBroken";
    case Type::BrokenSolid: return "BrokenSolid";
    case Type::BrokenBroken: return "BrokenBroken";
    case Type::BottsDots: return "BottsDots";
    case Type::Grass: return "Grass";
    case Type::Curb: return "Curb";
    case Type::None: return "NONE";
  }
  return "Unknown";
}

// Weather presets, the same set as carla.WeatherParameters in the Python API.
struct WeatherTable {
  const char *name;
  const crpc::WeatherParameters *params;
};

static const std::vector<WeatherTable> kWeatherTable = {
    {"Default", &crpc::WeatherParameters::Default},
    {"ClearNoon", &crpc::WeatherParameters::ClearNoon},
    {"CloudyNoon", &crpc::WeatherParameters::CloudyNoon},
    {"WetNoon", &crpc::WeatherParameters::WetNoon},
    {"WetCloudyNoon", &crpc::WeatherParameters::WetCloudyNoon},
    {"MidRainyNoon", &crpc::WeatherParameters::MidRainyNoon},
    {"HardRainNoon", &crpc::WeatherParameters::HardRainNoon},
    {"SoftRainNoon", &crpc::WeatherParameters::SoftRainNoon},
    {"ClearSunset", &crpc::WeatherParameters::ClearSunset},
    {"CloudySunset", &crpc::WeatherParameters::CloudySunset},
    {"WetSunset", &crpc::WeatherParameters::WetSunset},
    {"WetCloudySunset", &crpc::WeatherParameters::WetCloudySunset},
    {"MidRainSunset", &crpc::WeatherParameters::MidRainSunset},
    {"HardRainSunset", &crpc::WeatherParameters::HardRainSunset},
    {"SoftRainSunset", &crpc::WeatherParameters::SoftRainSunset},
    {"ClearNight", &crpc::WeatherParameters::ClearNight},
    {"CloudyNight", &crpc::WeatherParameters::CloudyNight},
    {"WetNight", &crpc::WeatherParameters::WetNight},
    {"WetCloudyNight", &crpc::WeatherParameters::WetCloudyNight},
    {"SoftRainNight", &crpc::WeatherParameters::SoftRainNight},
    {"MidRainyNight", &crpc::WeatherParameters::MidRainyNight},
    {"HardRainNight", &crpc::WeatherParameters::HardRainNight},
    {"DustStorm", &crpc::WeatherParameters::DustStorm},
};

static const std::vector<std::pair<crpc::MapLayer, const char *>> kMapLayers = {
    {crpc::MapLayer::None, "MapLayer.NONE"},
    {crpc::MapLayer::Buildings, "MapLayer.Buildings"},
    {crpc::MapLayer::Decals, "MapLayer.Decals"},
    {crpc::MapLayer::Foliage, "MapLayer.Foliage"},
    {crpc::MapLayer::Ground, "MapLayer.Ground"},
    {crpc::MapLayer::ParkedVehicles, "MapLayer.ParkedVehicles"},
    {crpc::MapLayer::Particles, "MapLayer.Particles"},
    {crpc::MapLayer::Props, "MapLayer.Props"},
    {crpc::MapLayer::StreetLights, "MapLayer.StreetLights"},
    {crpc::MapLayer::Walls, "MapLayer.Walls"},
    {crpc::MapLayer::All, "MapLayer.All"},
};

// ==============================================================================
// -- Options -------------------------------------------------------------------
// ==============================================================================

struct Options {
  std::string host = "127.0.0.1";
  uint16_t port = 2000;
  bool autopilot = false;
  int width = 1280;
  int height = 720;
  std::string filter = "vehicle.audi.a2";
  std::string generation = "2";
  std::string role_name = "hero";
  double gamma = 2.2;
  bool sync = false;
  std::string screenshot;          // --screenshot: PNG of the first frame with a camera picture
  double screenshot_delay = 3.0;   // seconds after the start before the screenshot is taken
  std::string config_path;  // carla.conf that was read, empty if none
};

static void PrintUsage() {
  std::cout << "usage: manual_control_gtk [--config FILE] [--host H] [-p P] [-a] [--res WIDTHxHEIGHT]\n"
               "                          [--filter PATTERN] [--generation G] [--rolename NAME]\n"
               "                          [--gamma GAMMA] [--sync]\n"
               "                          [--screenshot FILE.png [--screenshot-delay SECONDS]]\n"
               "\n"
               "Settings are taken from the built-in defaults (vehicle.audi.a2), then from\n"
               "carla.conf (CARLA_HOST, CARLA_PORT, VEHICLE, CPP_GTK_ARGS), then from the\n"
               "command line. carla.conf is FILE, else $CARLA_CONF, else the first carla.conf\n"
               "in the working directory or in the folder of the binary or one of its parents.\n";
}

static std::string Trim(const std::string &text) {
  const auto begin = text.find_first_not_of(" \t\r");
  if (begin == std::string::npos) return {};
  const auto end = text.find_last_not_of(" \t\r");
  return text.substr(begin, end - begin + 1);
}

// Reads the KEY=value lines of a carla.conf (the bash syntax carla-start.sh sources).
// Values may be quoted; an unquoted value ends at the first blank. Variables are not expanded.
static std::map<std::string, std::string> ReadConfigFile(const std::string &path) {
  std::ifstream file(path);
  if (!file) throw std::runtime_error("cannot read config file: " + path);
  std::map<std::string, std::string> values;
  std::string line;
  while (std::getline(file, line)) {
    line = Trim(line);
    if (line.empty() || line[0] == '#') continue;
    if (StartsWith(line, "export ")) line = Trim(line.substr(7));
    const auto equals = line.find('=');
    if (equals == std::string::npos) continue;
    const std::string key = line.substr(0, equals);
    std::string value = line.substr(equals + 1);
    if (!value.empty() && (value[0] == '"' || value[0] == '\'')) {
      const auto close = value.find(value[0], 1);
      value = value.substr(1, close == std::string::npos ? std::string::npos : close - 1);
    } else {
      value = value.substr(0, value.find_first_of(" \t"));
    }
    values[key] = value;
  }
  return values;
}

static std::string FindConfigFile() {
  if (const char *env = std::getenv("CARLA_CONF")) return env;
  namespace fs = std::filesystem;
  std::error_code error;
  if (fs::exists("carla.conf", error)) return fs::absolute("carla.conf", error).string();
  for (fs::path dir = fs::canonical("/proc/self/exe", error).parent_path(); !dir.empty();
       dir = dir.parent_path()) {
    if (fs::exists(dir / "carla.conf", error)) return (dir / "carla.conf").string();
    if (dir == dir.root_path()) break;
  }
  return {};
}

static std::vector<std::string> SplitWords(const std::string &text) {
  std::istringstream stream(text);
  std::vector<std::string> words;
  std::string word;
  while (stream >> word) words.push_back(word);
  return words;
}

static void ApplyArgs(const std::vector<std::string> &args, Options &options) {
  for (size_t i = 0; i < args.size(); ++i) {
    const std::string &arg = args[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= args.size()) throw std::invalid_argument("missing value for " + arg);
      return args[++i];
    };
    if (arg == "--host") {
      options.host = next();
    } else if (arg == "-p" || arg == "--port") {
      options.port = static_cast<uint16_t>(std::stoi(next()));
    } else if (arg == "-a" || arg == "--autopilot") {
      options.autopilot = true;
    } else if (arg == "--res") {
      const std::string res = next();
      const auto x = res.find('x');
      if (x == std::string::npos) throw std::invalid_argument("--res expects WIDTHxHEIGHT");
      options.width = std::stoi(res.substr(0, x));
      options.height = std::stoi(res.substr(x + 1));
    } else if (arg == "--filter") {
      options.filter = next();
    } else if (arg == "--generation") {
      options.generation = next();
    } else if (arg == "--rolename") {
      options.role_name = next();
    } else if (arg == "--gamma") {
      options.gamma = std::stod(next());
    } else if (arg == "--sync") {
      options.sync = true;
    } else if (arg == "--screenshot") {
      options.screenshot = next();
    } else if (arg == "--screenshot-delay") {
      options.screenshot_delay = std::stod(next());
    } else if (arg == "--config") {
      next();  // already handled by ParseArgs
    } else if (arg == "-v" || arg == "--verbose") {
      // Accepted for compatibility with the Python example.
    } else if (arg == "-h" || arg == "--help") {
      PrintUsage();
      std::exit(0);
    } else {
      throw std::invalid_argument("unknown option " + arg);
    }
  }
}

// Built-in defaults, then carla.conf, then the command line.
static Options ParseArgs(int argc, const char *argv[]) {
  const std::vector<std::string> args(argv + 1, argv + argc);
  Options options;

  std::string config_path;
  for (size_t i = 0; i + 1 < args.size(); ++i) {
    if (args[i] == "--config") config_path = args[i + 1];
  }
  if (config_path.empty()) config_path = FindConfigFile();

  if (!config_path.empty()) {
    const auto config = ReadConfigFile(config_path);
    options.config_path = config_path;
    if (const auto it = config.find("CARLA_HOST"); it != config.end() && !it->second.empty()) {
      options.host = it->second;
    }
    if (const auto it = config.find("CARLA_PORT"); it != config.end() && !it->second.empty()) {
      options.port = static_cast<uint16_t>(std::stoi(it->second));
    }
    // VEHICLE="" in carla.conf means a random vehicle.
    if (const auto it = config.find("VEHICLE"); it != config.end()) {
      options.filter = it->second.empty() ? "vehicle.*" : it->second;
    }
    if (const auto it = config.find("CPP_GTK_ARGS"); it != config.end()) {
      ApplyArgs(SplitWords(it->second), options);
    }
  }

  ApplyArgs(args, options);
  return options;
}

// ==============================================================================
// -- Cairo helpers -------------------------------------------------------------
// ==============================================================================

struct Rgba {
  double r = 1.0;
  double g = 1.0;
  double b = 1.0;
  double a = 1.0;
};

static void FillRect(cairo_t *cr, double x, double y, double w, double h, Rgba color) {
  cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
  cairo_rectangle(cr, x, y, w, h);
  cairo_fill(cr);
}

// One pixel wide white outline covering exactly the pixels of the rectangle.
static void OutlineRect(cairo_t *cr, double x, double y, double w, double h) {
  cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
  cairo_set_line_width(cr, 1.0);
  cairo_rectangle(cr, x + 0.5, y + 0.5, w - 1.0, h - 1.0);
  cairo_stroke(cr);
}

using FontPtr = std::unique_ptr<PangoFontDescription, decltype(&pango_font_description_free)>;

// Proportional bold font of the notification line.
static FontPtr MakeSansFont(double pixel_size) {
  FontPtr font(pango_font_description_new(), &pango_font_description_free);
  pango_font_description_set_family(font.get(), "Sans");
  pango_font_description_set_weight(font.get(), PANGO_WEIGHT_BOLD);
  pango_font_description_set_absolute_size(font.get(), pixel_size * PANGO_SCALE);
  return font;
}

// Monospace font scaled so that one character is `advance` pixels wide. The HUD
// layout (columns, bars) then does not depend on which font fontconfig picks.
static FontPtr MakeMonoFont(double advance) {
  FontPtr font(pango_font_description_new(), &pango_font_description_free);
  pango_font_description_set_family(font.get(), "Ubuntu Mono,DejaVu Sans Mono,Monospace");
  const double probe_size = 14.0;
  pango_font_description_set_absolute_size(font.get(), probe_size * PANGO_SCALE);

  cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1, 1);
  cairo_t *cr = cairo_create(surface);
  PangoLayout *layout = pango_cairo_create_layout(cr);
  pango_layout_set_font_description(layout, font.get());
  pango_layout_set_text(layout, "MMMMMMMMMM", -1);
  PangoRectangle logical{};
  pango_layout_get_extents(layout, nullptr, &logical);
  g_object_unref(layout);
  cairo_destroy(cr);
  cairo_surface_destroy(surface);

  const double probe_advance = logical.width / (10.0 * PANGO_SCALE);
  if (probe_advance > 0.0) {
    pango_font_description_set_absolute_size(font.get(), probe_size * advance / probe_advance * PANGO_SCALE);
  }
  return font;
}

static void DrawText(cairo_t *cr, const PangoFontDescription *font, const std::string &text, double x, double y,
                     Rgba color = {}) {
  if (text.empty()) return;
  PangoLayout *layout = pango_cairo_create_layout(cr);
  pango_layout_set_font_description(layout, font);
  pango_layout_set_text(layout, text.c_str(), -1);
  cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
  cairo_move_to(cr, x, y);
  pango_cairo_show_layout(cr, layout);
  g_object_unref(layout);
}

// Average frame rate over the last ten ticks, like pygame.time.Clock.get_fps().
class FpsCounter {
public:
  void Tick() {
    times_.push_back(Clock::now());
    if (times_.size() > 11) times_.pop_front();
  }

  double Fps() const {
    if (times_.size() < 2) return 0.0;
    const double seconds = std::chrono::duration<double>(times_.back() - times_.front()).count();
    return seconds > 0.0 ? static_cast<double>(times_.size() - 1) / seconds : 0.0;
  }

private:
  std::deque<Clock::time_point> times_;
};

// ==============================================================================
// -- HUD -----------------------------------------------------------------------
// ==============================================================================

// One HUD row: text, a bar (value between low and high), a check box or a graph.
struct InfoItem {
  enum class Kind { Text, Bar, Flag, Graph };
  Kind kind = Kind::Text;
  std::string text;
  float value = 0.0f;
  float low = 0.0f;
  float high = 1.0f;
  bool flag = false;
  std::vector<float> graph;
};

static InfoItem TextItem(std::string text) {
  InfoItem item;
  item.text = std::move(text);
  return item;
}

static InfoItem BarItem(std::string label, float value, float low, float high) {
  InfoItem item;
  item.kind = InfoItem::Kind::Bar;
  item.text = std::move(label);
  item.value = value;
  item.low = low;
  item.high = high;
  return item;
}

static InfoItem FlagItem(std::string label, bool flag) {
  InfoItem item;
  item.kind = InfoItem::Kind::Flag;
  item.text = std::move(label);
  item.flag = flag;
  return item;
}

static InfoItem GraphItem(std::vector<float> graph) {
  InfoItem item;
  item.kind = InfoItem::Kind::Graph;
  item.graph = std::move(graph);
  return item;
}

class World;

class Hud {
public:
  Hud(int width, int height)
    : width_(width),
      height_(height),
      font_(MakeSansFont(20.0)),
      font_mono_(MakeMonoFont(7.0)),
      font_help_(MakeMonoFont(8.0)) {
    std::istringstream help(kHelpText);
    std::string line;
    while (std::getline(help, line)) help_lines_.push_back(line);
    // The help text is taller than a 720 pixel window; shrink it to fit, down to a readable size.
    help_scale_ = std::clamp((height_ - 12.0) / (static_cast<double>(help_lines_.size()) * 18.0), 0.6, 1.0);
    font_help_ = MakeMonoFont(8.0 * help_scale_);
  }

  int width() const { return width_; }
  int height() const { return height_; }

  // Called from the client thread on every world tick.
  void OnWorldTick(size_t frame, double elapsed_seconds) {
    std::lock_guard<std::mutex> lock(mutex_);
    server_clock_.Tick();
    frame_ = frame;
    simulation_time_ = elapsed_seconds;
  }

  // Thread safe, sensor callbacks use it too.
  void Notification(const std::string &text, double seconds = 2.0) {
    std::lock_guard<std::mutex> lock(mutex_);
    notification_ = text;
    notification_color_ = {1.0, 1.0, 1.0, 1.0};
    notification_seconds_left_ = seconds;
  }

  void Error(const std::string &text) {
    std::lock_guard<std::mutex> lock(mutex_);
    notification_ = "Error: " + text;
    notification_color_ = {1.0, 0.0, 0.0, 1.0};
    notification_seconds_left_ = 2.0;
  }

  void ToggleInfo() { show_info_ = !show_info_; }
  void ToggleHelp() { show_help_ = !show_help_; }
  bool help_visible() const { return show_help_; }
  void ShowAckermannInfo(bool enabled) { show_ackermann_info_ = enabled; }
  void UpdateAckermannControl(const crpc::VehicleAckermannControl &control) { ackermann_control_ = control; }

  // Rebuilds the info rows from the world state (defined after World).
  void Tick(const World &world, double client_fps, double milliseconds);

  void Render(cairo_t *cr) const {
    if (show_info_) {
      FillRect(cr, 0, 0, 220, height_, {0.0, 0.0, 0.0, 100.0 / 255.0});
      int v_offset = 4;
      const int bar_h_offset = 100;
      const int bar_width = 106;
      for (const auto &item : info_) {
        if (v_offset + 18 > height_) break;
        std::string text = item.text;
        switch (item.kind) {
          case InfoItem::Kind::Graph:
            if (item.graph.size() > 1) {
              cairo_set_source_rgb(cr, 1.0, 136.0 / 255.0, 0.0);
              cairo_set_line_width(cr, 2.0);
              for (size_t x = 0; x < item.graph.size(); ++x) {
                const double px = static_cast<double>(x) + 8.0;
                const double py = v_offset + 8 + static_cast<int>((1.0f - item.graph[x]) * 30.0f);
                if (x == 0) {
                  cairo_move_to(cr, px, py);
                } else {
                  cairo_line_to(cr, px, py);
                }
              }
              cairo_stroke(cr);
            }
            text.clear();
            v_offset += 18;
            break;
          case InfoItem::Kind::Flag:
            if (item.flag) {
              FillRect(cr, bar_h_offset, v_offset + 8, 6, 6, {});
            } else {
              OutlineRect(cr, bar_h_offset, v_offset + 8, 6, 6);
            }
            break;
          case InfoItem::Kind::Bar: {
            OutlineRect(cr, bar_h_offset, v_offset + 8, bar_width, 6);
            const float f = std::clamp((item.value - item.low) / (item.high - item.low), 0.0f, 1.0f);
            if (item.low < 0.0f) {
              FillRect(cr, bar_h_offset + static_cast<int>(f * (bar_width - 6)), v_offset + 8, 6, 6, {});
            } else {
              FillRect(cr, bar_h_offset, v_offset + 8, static_cast<int>(f * bar_width), 6, {});
            }
            break;
          }
          case InfoItem::Kind::Text:
            break;
        }
        DrawText(cr, font_mono_.get(), text, 8, v_offset);
        v_offset += 18;
      }
    }
    RenderNotification(cr);
    RenderHelp(cr);
  }

private:
  void RenderNotification(cairo_t *cr) const {
    std::string text;
    Rgba color;
    double seconds_left = 0.0;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      text = notification_;
      color = notification_color_;
      seconds_left = notification_seconds_left_;
    }
    const double alpha = std::min(1.0, 500.0 * seconds_left / 255.0);
    if (alpha <= 0.0) return;
    FillRect(cr, 0, height_ - 40, width_, 40, {0.0, 0.0, 0.0, alpha});
    color.a = alpha;
    DrawText(cr, font_.get(), text, 10, height_ - 40 + 8, color);
  }

  void RenderHelp(cairo_t *cr) const {
    if (!show_help_) return;
    const double line_space = 18.0 * help_scale_;
    const double w = 780.0 * help_scale_;
    const double h = static_cast<double>(help_lines_.size()) * line_space + 12.0;
    const double x = width_ / 2.0 - w / 2.0;
    const double y = std::max(0.0, height_ / 2.0 - h / 2.0);
    const double alpha = 220.0 / 255.0;
    FillRect(cr, x, y, w, h, {0.0, 0.0, 0.0, alpha});
    for (size_t n = 0; n < help_lines_.size(); ++n) {
      DrawText(cr, font_help_.get(), help_lines_[n], x + 22.0 * help_scale_, y + static_cast<double>(n) * line_space,
               {1.0, 1.0, 1.0, alpha});
    }
  }

  const int width_;
  const int height_;
  FontPtr font_;
  FontPtr font_mono_;
  FontPtr font_help_;
  std::vector<std::string> help_lines_;
  double help_scale_ = 1.0;

  mutable std::mutex mutex_;  // guards the fields written by other threads
  FpsCounter server_clock_;
  size_t frame_ = 0;
  double simulation_time_ = 0.0;
  std::string notification_;
  Rgba notification_color_;
  double notification_seconds_left_ = 0.0;

  bool show_info_ = true;
  bool show_help_ = false;
  bool show_ackermann_info_ = false;
  crpc::VehicleAckermannControl ackermann_control_;
  std::vector<InfoItem> info_;
};

// ==============================================================================
// -- Sensors -------------------------------------------------------------------
// ==============================================================================

// Values written by the sensor callbacks (client thread) and read by the HUD.
struct SensorState {
  std::mutex mutex;
  std::deque<std::pair<size_t, double>> collision_history;  // (frame, intensity)
  std::array<double, 3> accelerometer{0.0, 0.0, 0.0};
  std::array<double, 3> gyroscope{0.0, 0.0, 0.0};
  double compass = 0.0;
  double latitude = 0.0;
  double longitude = 0.0;
};

static carla::SharedPtr<cc::Sensor> SpawnSensor(cc::World &world, const ca::ActorBlueprint &blueprint,
                                                const cg::Transform &transform, cc::Actor *parent,
                                                crpc::AttachmentType attachment = crpc::AttachmentType::Rigid) {
  try {
    return boost::static_pointer_cast<cc::Sensor>(world.SpawnActor(blueprint, transform, parent, attachment));
  } catch (const std::exception &error) {
    throw std::runtime_error(blueprint.GetId() + ": " + error.what());
  }
}

static ca::ActorBlueprint FindBlueprint(const cc::World &world, const std::string &id) {
  // Find() points into the library, so the library must outlive the copy below.
  const auto library = world.GetBlueprintLibrary();
  const auto blueprint = library->Find(id);
  if (!blueprint) throw std::runtime_error("blueprint not found: " + id);
  return *blueprint;
}

// Sensor callbacks run on LibCarla threads, where an escaping exception would
// terminate the process; report the first failure of each sensor instead.
template <typename F>
static void ListenSafely(cc::Sensor &sensor, const std::string &name, F callback) {
  auto reported = std::make_shared<std::atomic<bool>>(false);
  sensor.Listen([name, reported, callback = std::move(callback)](SensorDataPtr data) mutable {
    try {
      callback(std::move(data));
    } catch (const std::exception &error) {
      if (!reported->exchange(true)) {
        std::cerr << "ERROR: " << name << " callback failed: " << error.what() << std::endl;
      }
    }
  });
}

static void StopAndDestroy(carla::SharedPtr<cc::Sensor> &sensor) {
  if (sensor) {
    sensor->Stop();
    sensor->Destroy();
    sensor.reset();
  }
}

// Draws the radar detections as debug points in the simulator.
class RadarSensor {
public:
  RadarSensor(cc::World world, cc::Actor &parent) {
    const auto extent = parent.GetBoundingBox().extent;
    const float bound_x = 0.5f + extent.x;
    const float bound_z = 0.5f + extent.z;
    const float velocity_range = 7.5f;  // m/s

    ca::ActorBlueprint blueprint = FindBlueprint(world, "sensor.other.radar");
    blueprint.SetAttribute("horizontal_fov", "35");
    blueprint.SetAttribute("vertical_fov", "20");
    sensor_ = SpawnSensor(world,
                          blueprint,
                          cg::Transform(cg::Location(bound_x + 0.05f, 0.0f, bound_z + 0.05f),
                                        cg::Rotation(5.0f, 0.0f, 0.0f)),
                          &parent);

    auto debug = world.MakeDebugHelper();
    ListenSafely(*sensor_, "radar", [debug, velocity_range](SensorDataPtr data) mutable {
      auto radar = boost::static_pointer_cast<csd::RadarMeasurement>(data);
      const auto &sensor_transform = radar->GetSensorTransform();
      const auto &current_rot = sensor_transform.rotation;
      auto clamp = [](float min_v, float max_v, float value) { return std::max(min_v, std::min(value, max_v)); };
      for (const auto &detect : *radar) {
        const float azi = static_cast<float>(Degrees(detect.azimuth));
        const float alt = static_cast<float>(Degrees(detect.altitude));
        // The 0.25 adjusts a bit the distance so the dots can be properly seen.
        cg::Vector3D fw_vec(detect.depth - 0.25f, 0.0f, 0.0f);
        cg::Transform(cg::Location(),
                      cg::Rotation(current_rot.pitch + alt, current_rot.yaw + azi, current_rot.roll))
            .TransformPoint(fw_vec);

        const float norm_velocity = detect.velocity / velocity_range;  // range [-1, 1]
        const auto r = static_cast<uint8_t>(clamp(0.0f, 1.0f, 1.0f - norm_velocity) * 255.0f);
        const auto g = static_cast<uint8_t>(clamp(0.0f, 1.0f, 1.0f - std::abs(norm_velocity)) * 255.0f);
        const auto b = static_cast<uint8_t>(std::abs(clamp(-1.0f, 0.0f, -1.0f - norm_velocity)) * 255.0f);
        debug.DrawPoint(cg::Location(sensor_transform.location.x + fw_vec.x,
                                     sensor_transform.location.y + fw_vec.y,
                                     sensor_transform.location.z + fw_vec.z),
                        0.075f, cc::DebugHelper::Color{r, g, b}, 0.06f, false);
      }
    });
  }

  ~RadarSensor() { StopAndDestroy(sensor_); }

  RadarSensor(const RadarSensor &) = delete;
  RadarSensor &operator=(const RadarSensor &) = delete;

private:
  carla::SharedPtr<cc::Sensor> sensor_;
};

// ==============================================================================
// -- CameraManager -------------------------------------------------------------
// ==============================================================================

enum class Conversion { Raw, Depth, LogarithmicDepth, CityScapesPalette };

struct SensorSpec {
  std::string id;
  Conversion conversion;
  std::string name;
  std::vector<std::pair<std::string, std::string>> attributes;
};

static const std::vector<SensorSpec> kSensorSpecs = {
    {"sensor.camera.rgb", Conversion::Raw, "Camera RGB", {}},
    {"sensor.camera.depth", Conversion::Raw, "Camera Depth (Raw)", {}},
    {"sensor.camera.depth", Conversion::Depth, "Camera Depth (Gray Scale)", {}},
    {"sensor.camera.depth", Conversion::LogarithmicDepth, "Camera Depth (Logarithmic Gray Scale)", {}},
    {"sensor.camera.semantic_segmentation", Conversion::Raw, "Camera Semantic Segmentation (Raw)", {}},
    {"sensor.camera.semantic_segmentation", Conversion::CityScapesPalette,
     "Camera Semantic Segmentation (CityScapes Palette)", {}},
    {"sensor.camera.instance_segmentation", Conversion::CityScapesPalette,
     "Camera Instance Segmentation (CityScapes Palette)", {}},
    {"sensor.camera.instance_segmentation", Conversion::Raw, "Camera Instance Segmentation (Raw)", {}},
    {"sensor.camera.cosmos_visualization", Conversion::Raw, "Cosmos Control Visualization", {}},
    {"sensor.lidar.ray_cast", Conversion::Raw, "Lidar (Ray-Cast)", {{"range", "50"}}},
    {"sensor.camera.dvs", Conversion::Raw, "Dynamic Vision Sensor", {}},
    {"sensor.camera.rgb", Conversion::Raw, "Camera RGB Distorted",
     {{"lens_circle_multiplier", "3.0"},
      {"lens_circle_falloff", "3.0"},
      {"chromatic_aberration_intensity", "0.5"},
      {"chromatic_aberration_offset", "0"}}},
    {"sensor.camera.optical_flow", Conversion::Raw, "Optical Flow", {}},
    {"sensor.camera.normals", Conversion::Raw, "Camera Normals", {}},
};

// A BGRA8 picture, the pixel layout of CARLA images and of cairo's ARGB32.
struct Frame {
  std::vector<uint8_t> pixels;
  int width = 0;
  int height = 0;

  void Resize(int w, int h) {
    width = w;
    height = h;
    pixels.assign(static_cast<size_t>(w) * static_cast<size_t>(h) * 4u, 0u);
  }

  void Set(size_t index, uint8_t r, uint8_t g, uint8_t b) {
    pixels[4 * index] = b;
    pixels[4 * index + 1] = g;
    pixels[4 * index + 2] = r;
    pixels[4 * index + 3] = 255;
  }
};

// Latest frame of the active sensor, handed from the client thread to GTK. The
// picture is shared so a cairo surface can point into it while a newer one arrives.
struct FrameBuffer {
  std::mutex mutex;
  std::shared_ptr<Frame> frame;
  bool updated = false;
};

// Same formulas as carla/image/ColorConverter.h.
static void ConvertImage(const csd::Image &image, Conversion conversion, Frame &out) {
  out.Resize(static_cast<int>(image.GetWidth()), static_cast<int>(image.GetHeight()));
  for (size_t i = 0; i < image.size(); ++i) {
    const csd::Color &pixel = image[i];
    switch (conversion) {
      case Conversion::Raw:
        out.Set(i, pixel.r, pixel.g, pixel.b);
        break;
      case Conversion::Depth:
      case Conversion::LogarithmicDepth: {
        const float depth = (pixel.r + pixel.g * 256.0f + pixel.b * 256.0f * 256.0f) /
                            static_cast<float>(256 * 256 * 256 - 1);
        float value = depth;
        if (conversion == Conversion::LogarithmicDepth) {
          value = std::clamp(1.0f + std::log(depth) / 5.70378f, 0.005f, 1.0f);
        }
        const auto gray = static_cast<uint8_t>(value * 255.0f);
        out.Set(i, gray, gray, gray);
        break;
      }
      case Conversion::CityScapesPalette: {
        const auto color = carla::image::CityScapesPalette::GetColor(pixel.r);
        out.Set(i, color[0], color[1], color[2]);
        break;
      }
    }
  }
}

// Same colour coding as OpticalFlowImage.get_color_coded_flow() in the Python API.
static void ConvertOpticalFlow(const csd::OpticalFlowImage &image, Frame &out) {
  constexpr float pi = 3.1415f;
  constexpr float rad2ang = 360.f / (2.f * pi);
  out.Resize(static_cast<int>(image.GetWidth()), static_cast<int>(image.GetHeight()));
  for (size_t index = 0; index < image.size(); ++index) {
    const csd::OpticalFlowPixel &pixel = image[index];
    float angle = 180.f + std::atan2(pixel.y, pixel.x) * rad2ang;
    if (angle < 0) angle = 360.f + angle;
    angle = std::fmod(angle, 360.f);

    const float norm = std::sqrt(pixel.x * pixel.x + pixel.y * pixel.y);
    const float shift = 0.999f;
    const float a = 1.f / std::log(0.1f + shift);
    const float intensity = std::clamp(a * std::log(norm + shift), 0.f, 1.f);

    const float h_60 = angle * (1.f / 60.f);
    const float c = intensity;  // V * S with S = 1
    const float x = c * (1.f - std::abs(std::fmod(h_60, 2.f) - 1.f));
    const float m = intensity - c;
    float r = 1, g = 1, b = 1;
    switch (static_cast<unsigned int>(h_60)) {
      case 0: r = c; g = x; b = 0; break;
      case 1: r = x; g = c; b = 0; break;
      case 2: r = 0; g = c; b = x; break;
      case 3: r = 0; g = x; b = c; break;
      case 4: r = x; g = 0; b = c; break;
      case 5: r = c; g = 0; b = x; break;
      default: break;
    }
    out.Set(index,
            static_cast<uint8_t>((r + m) * 255.f),
            static_cast<uint8_t>((g + m) * 255.f),
            static_cast<uint8_t>((b + m) * 255.f));
  }
}

// Top view of the lidar points, scaled so that `range` fits the shorter side.
static void ConvertLidar(const csd::LidarMeasurement &lidar, int width, int height, double range, Frame &out) {
  out.Resize(width, height);
  const double scale = std::min(width, height) / (2.0 * range);
  for (const auto &detection : lidar) {
    const int x = static_cast<int>(std::fabs(detection.point.x * scale + 0.5 * width));
    const int y = static_cast<int>(std::fabs(detection.point.y * scale + 0.5 * height));
    if (x < width && y < height) {
      out.Set(static_cast<size_t>(y) * static_cast<size_t>(width) + static_cast<size_t>(x), 255, 255, 255);
    }
  }
}

// Blue is positive, red is negative.
static void ConvertDvs(const csd::DVSEventArray &events, Frame &out) {
  out.Resize(static_cast<int>(events.GetWidth()), static_cast<int>(events.GetHeight()));
  for (const auto &event : events) {
    if (event.x >= out.width || event.y >= out.height) continue;
    const size_t index = static_cast<size_t>(event.y) * static_cast<size_t>(out.width) + event.x;
    out.pixels[4 * index + (event.pol ? 0 : 2)] = 255;
    out.pixels[4 * index + 3] = 255;
  }
}

// Cairo's ARGB32 is BGRA8 on little-endian machines, the layout of CARLA images.
static_assert(G_BYTE_ORDER == G_LITTLE_ENDIAN, "Frame pixels are BGRA, which is cairo ARGB32 on little endian only");

// Wraps the pixels of `frame` without copying; `frame` must outlive the surface.
static cairo_surface_t *SurfaceFromFrame(const Frame &frame) {
  return cairo_image_surface_create_for_data(const_cast<uint8_t *>(frame.pixels.data()), CAIRO_FORMAT_ARGB32,
                                             frame.width, frame.height, frame.width * 4);
}

static void SaveToDisk(const Frame &frame, size_t frame_number) {
  std::error_code error;
  std::filesystem::create_directories("_out", error);
  cairo_surface_t *surface = SurfaceFromFrame(frame);
  cairo_surface_write_to_png(surface, Format("_out/%08zu.png", frame_number).c_str());
  cairo_surface_destroy(surface);
}

class CameraManager {
public:
  CameraManager(cc::World world, carla::SharedPtr<cc::Actor> parent, std::shared_ptr<Hud> hud, double gamma)
    : world_(world),
      parent_(std::move(parent)),
      hud_(std::move(hud)),
      recording_(std::make_shared<std::atomic<bool>>(false)) {
    const auto extent = parent_->GetBoundingBox().extent;
    const float bound_x = 0.5f + extent.x;
    const float bound_y = 0.5f + extent.y;
    const float bound_z = 0.5f + extent.z;
    using Attachment = crpc::AttachmentType;

    if (!StartsWith(parent_->GetTypeId(), "walker.pedestrian")) {
      camera_transforms_ = {
          {cg::Transform(cg::Location(-2.0f * bound_x, +0.0f * bound_y, 2.0f * bound_z), cg::Rotation(8.0f, 0.0f, 0.0f)), Attachment::SpringArmGhost},
          {cg::Transform(cg::Location(+0.8f * bound_x, +0.0f * bound_y, 1.3f * bound_z)), Attachment::Rigid},
          {cg::Transform(cg::Location(+1.9f * bound_x, +1.0f * bound_y, 1.2f * bound_z)), Attachment::SpringArmGhost},
          {cg::Transform(cg::Location(-2.8f * bound_x, +0.0f * bound_y, 4.6f * bound_z), cg::Rotation(6.0f, 0.0f, 0.0f)), Attachment::SpringArmGhost},
          {cg::Transform(cg::Location(-1.0f, -1.0f * bound_y, 0.4f * bound_z)), Attachment::Rigid}};
    } else {
      camera_transforms_ = {
          {cg::Transform(cg::Location(-2.5f, 0.0f, 0.0f), cg::Rotation(-8.0f, 0.0f, 0.0f)), Attachment::SpringArmGhost},
          {cg::Transform(cg::Location(1.6f, 0.0f, 1.7f)), Attachment::Rigid},
          {cg::Transform(cg::Location(2.5f, 0.5f, 0.0f), cg::Rotation(-8.0f, 0.0f, 0.0f)), Attachment::SpringArmGhost},
          {cg::Transform(cg::Location(-4.0f, 0.0f, 2.0f), cg::Rotation(6.0f, 0.0f, 0.0f)), Attachment::SpringArmGhost},
          {cg::Transform(cg::Location(0.0f, -2.5f, -0.0f), cg::Rotation(0.0f, 90.0f, 0.0f)), Attachment::Rigid}};
    }

    const auto library = world_.GetBlueprintLibrary();
    for (const auto &spec : kSensorSpecs) {
      const auto found = library->Find(spec.id);
      if (!found) continue;  // e.g. the Cosmos visualization only exists in some builds
      ca::ActorBlueprint blueprint = *found;
      if (StartsWith(spec.id, "sensor.camera")) {
        blueprint.SetAttribute("image_size_x", std::to_string(hud_->width()));
        blueprint.SetAttribute("image_size_y", std::to_string(hud_->height()));
        if (blueprint.ContainsAttribute("gamma")) blueprint.SetAttribute("gamma", Format("%g", gamma));
        for (const auto &attribute : spec.attributes) blueprint.SetAttribute(attribute.first, attribute.second);
      } else if (StartsWith(spec.id, "sensor.lidar")) {
        lidar_range_ = 50.0;
        for (const auto &attribute : spec.attributes) {
          blueprint.SetAttribute(attribute.first, attribute.second);
          if (attribute.first == "range") lidar_range_ = std::stod(attribute.second);
        }
      }
      sensors_.push_back({spec, blueprint});
    }
  }

  ~CameraManager() {
    StopAndDestroy(sensor_);
    if (surface_) cairo_surface_destroy(surface_);
  }

  CameraManager(const CameraManager &) = delete;
  CameraManager &operator=(const CameraManager &) = delete;

  int index() const { return index_; }
  size_t transform_index() const { return transform_index_; }
  void set_transform_index(size_t index) { transform_index_ = index % camera_transforms_.size(); }

  void ToggleCamera() {
    transform_index_ = (transform_index_ + 1) % camera_transforms_.size();
    SetSensor(index_, false, true);
  }

  void SetSensor(int index, bool notify = true, bool force_respawn = false) {
    if (sensors_.empty()) return;
    const int count = static_cast<int>(sensors_.size());
    index = ((index % count) + count) % count;
    const bool needs_respawn = index_ < 0 || force_respawn || sensors_[index].spec.name != sensors_[index_].spec.name;
    if (needs_respawn) {
      StopAndDestroy(sensor_);
      frame_ = std::make_shared<FrameBuffer>();
      const auto &camera = camera_transforms_[transform_index_];
      sensor_ = SpawnSensor(world_, sensors_[index].blueprint, camera.first, parent_.get(), camera.second);

      // The callback holds only shared state, never `this`.
      auto frame = frame_;
      auto recording = recording_;
      const SensorSpec spec = sensors_[index].spec;
      const int width = hud_->width();
      const int height = hud_->height();
      const double lidar_range = lidar_range_;
      ListenSafely(*sensor_, spec.name, [frame, recording, spec, width, height, lidar_range](SensorDataPtr data) {
        auto image = std::make_shared<Frame>();
        if (StartsWith(spec.id, "sensor.lidar")) {
          ConvertLidar(*boost::static_pointer_cast<csd::LidarMeasurement>(data), width, height, lidar_range, *image);
        } else if (StartsWith(spec.id, "sensor.camera.dvs")) {
          ConvertDvs(*boost::static_pointer_cast<csd::DVSEventArray>(data), *image);
        } else if (StartsWith(spec.id, "sensor.camera.optical_flow")) {
          ConvertOpticalFlow(*boost::static_pointer_cast<csd::OpticalFlowImage>(data), *image);
        } else {
          ConvertImage(*boost::static_pointer_cast<csd::Image>(data), spec.conversion, *image);
        }
        if (*recording) SaveToDisk(*image, data->GetFrame());
        std::lock_guard<std::mutex> lock(frame->mutex);
        frame->frame = std::move(image);
        frame->updated = true;
      });
    }
    if (notify) hud_->Notification(sensors_[index].spec.name);
    index_ = index;
  }

  void NextSensor() { SetSensor(index_ < 0 ? 0 : index_ + 1); }

  // Destroys the sensor but keeps the configuration (used before replaying).
  void DestroySensor() {
    StopAndDestroy(sensor_);
    frame_ = std::make_shared<FrameBuffer>();
    index_ = -1;
  }

  void ToggleRecording() {
    *recording_ = !*recording_;
    hud_->Notification(std::string("Recording ") + (*recording_ ? "On" : "Off"));
  }

  bool has_frame() const { return current_ != nullptr; }

  // Draws the latest picture of the active sensor at the top left corner.
  void Render(cairo_t *cr) {
    if (!frame_) return;
    {
      std::lock_guard<std::mutex> lock(frame_->mutex);
      if (frame_->updated) {
        // Swap in the new picture: the surface points into it, so release the surface first.
        if (surface_) cairo_surface_destroy(surface_);
        current_ = frame_->frame;
        surface_ = SurfaceFromFrame(*current_);
        frame_->updated = false;
        current_owner_ = frame_;
      }
    }
    // Only show a picture that belongs to the current sensor (pygame: surface = None).
    if (surface_ && current_owner_.lock() == frame_) {
      cairo_set_source_surface(cr, surface_, 0, 0);
      cairo_paint(cr);
    }
  }

private:
  struct Entry {
    SensorSpec spec;
    ca::ActorBlueprint blueprint;
  };

  cc::World world_;
  carla::SharedPtr<cc::Actor> parent_;
  std::shared_ptr<Hud> hud_;
  std::shared_ptr<std::atomic<bool>> recording_;
  std::vector<std::pair<cg::Transform, crpc::AttachmentType>> camera_transforms_;
  size_t transform_index_ = 1;
  std::vector<Entry> sensors_;
  double lidar_range_ = 50.0;
  int index_ = -1;
  carla::SharedPtr<cc::Sensor> sensor_;
  std::shared_ptr<FrameBuffer> frame_;

  // Only used by the GTK thread: the picture on screen and the surface that points into it.
  std::shared_ptr<Frame> current_;
  cairo_surface_t *surface_ = nullptr;
  std::weak_ptr<FrameBuffer> current_owner_;
};

// ==============================================================================
// -- World ---------------------------------------------------------------------
// ==============================================================================

class World {
public:
  World(cc::World carla_world, std::shared_ptr<Hud> hud, const Options &options)
    : world_(carla_world),
      options_(options),
      hud_(std::move(hud)),
      state_(std::make_shared<SensorState>()),
      rng_(std::random_device{}()) {
    try {
      map_ = world_.GetMap();
    } catch (const std::exception &error) {
      throw std::runtime_error(std::string(error.what()) +
                               "\n  The server could not send the OpenDRIVE (.xodr) file:"
                               "\n  Make sure it exists, has the same name of your town, and is correct.");
    }
    for (const auto &preset : kWeatherTable) {
      weather_presets_.push_back({SplitCamelCase(preset.name), *preset.params});
    }
    Restart();
    tick_id_ = world_.OnTick([hud = hud_](cc::WorldSnapshot snapshot) {
      hud->OnWorldTick(snapshot.GetFrame(), snapshot.GetTimestamp().elapsed_seconds);
    });
  }

  ~World() {
    world_.RemoveOnTick(tick_id_);
    Destroy();
  }

  World(const World &) = delete;
  World &operator=(const World &) = delete;

  const cc::World &carla_world() const { return world_; }
  const cc::Map &map() const { return *map_; }
  Hud &hud() const { return *hud_; }
  SensorState &sensor_state() const { return *state_; }
  CameraManager &camera_manager() const { return *camera_manager_; }

  carla::SharedPtr<cc::Actor> player() const { return player_; }
  carla::SharedPtr<cc::Vehicle> vehicle() const { return boost::dynamic_pointer_cast<cc::Vehicle>(player_); }
  carla::SharedPtr<cc::Walker> walker() const { return boost::dynamic_pointer_cast<cc::Walker>(player_); }

  void Restart() {
    player_max_speed = 1.589f;
    player_max_speed_fast = 3.713f;
    // Keep same camera config if the camera manager exists.
    const int cam_index = camera_manager_ ? std::max(camera_manager_->index(), 0) : 0;
    const size_t cam_pos_index = camera_manager_ ? camera_manager_->transform_index() : 0;

    // Get a random blueprint.
    const auto blueprints = GetActorBlueprints();
    if (blueprints.empty()) throw std::runtime_error("Couldn't find any blueprints with the specified filters");
    ca::ActorBlueprint blueprint = Pick(blueprints, rng_);
    blueprint.SetAttribute("role_name", options_.role_name);
    if (blueprint.ContainsAttribute("terramechanics")) blueprint.SetAttribute("terramechanics", "true");
    if (blueprint.ContainsAttribute("color")) {
      blueprint.SetAttribute("color", Pick(blueprint.GetAttribute("color").GetRecommendedValues(), rng_));
    }
    if (blueprint.ContainsAttribute("driver_id")) {
      blueprint.SetAttribute("driver_id", Pick(blueprint.GetAttribute("driver_id").GetRecommendedValues(), rng_));
    }
    if (blueprint.ContainsAttribute("is_invincible")) blueprint.SetAttribute("is_invincible", "true");
    // Set the max speed.
    if (blueprint.ContainsAttribute("speed")) {
      const auto &speeds = blueprint.GetAttribute("speed").GetRecommendedValues();
      if (speeds.size() > 2) {
        player_max_speed = std::stof(speeds[1]);
        player_max_speed_fast = std::stof(speeds[2]);
      }
    }

    // Spawn the player.
    if (player_) {
      cg::Transform spawn_point = player_->GetTransform();
      spawn_point.location.z += 2.0f;
      spawn_point.rotation.roll = 0.0f;
      spawn_point.rotation.pitch = 0.0f;
      Destroy();
      player_ = world_.TrySpawnActor(blueprint, spawn_point);
      show_vehicle_telemetry = false;
      ModifyVehiclePhysics();
    }
    while (!player_) {
      const auto spawn_points = map_->GetRecommendedSpawnPoints();
      if (spawn_points.empty()) {
        throw std::runtime_error("There are no spawn points available in your map/town.\n"
                                 "Please add some Vehicle Spawn Point to your UE4 scene.");
      }
      player_ = world_.TrySpawnActor(blueprint, Pick(spawn_points, rng_));
      show_vehicle_telemetry = false;
      ModifyVehiclePhysics();
    }

    // Set up the sensors.
    SetUpSensors();
    camera_manager_ = std::make_unique<CameraManager>(world_, player_, hud_, options_.gamma);
    camera_manager_->set_transform_index(cam_pos_index);
    camera_manager_->SetSensor(cam_index, false);
    hud_->Notification(GetActorDisplayName(player_->GetTypeId()));

    if (options_.sync) {
      world_.Tick(TIMEOUT);
    } else {
      world_.WaitForTick(TIMEOUT);
    }
  }

  void NextWeather(bool reverse = false) {
    weather_index_ = StepIndex(weather_index_, weather_presets_.size(), reverse);
    const auto &preset = weather_presets_[weather_index_];
    hud_->Notification("Weather: " + preset.first);
    world_.SetWeather(preset.second);
  }

  void NextMapLayer(bool reverse = false) {
    current_map_layer_ = StepIndex(current_map_layer_, kMapLayers.size(), reverse);
    hud_->Notification(std::string("LayerMap selected: ") + kMapLayers[current_map_layer_].second);
  }

  void LoadMapLayer(bool unload = false) {
    const auto &selected = kMapLayers[current_map_layer_];
    if (unload) {
      hud_->Notification(std::string("Unloading map layer: ") + selected.second);
      world_.UnloadLevelLayer(selected.first);
    } else {
      hud_->Notification(std::string("Loading map layer: ") + selected.second);
      world_.LoadLevelLayer(selected.first);
    }
  }

  void ToggleRadar() {
    if (radar_sensor_) {
      radar_sensor_.reset();
    } else {
      radar_sensor_ = std::make_unique<RadarSensor>(world_, *player_);
    }
  }

  void Tick(double client_fps, double milliseconds) const {
    hud_->Tick(*this, client_fps, milliseconds);
  }

  void Render(cairo_t *cr) const {
    camera_manager_->Render(cr);
    hud_->Render(cr);
  }

  void DestroySensors() { camera_manager_->DestroySensor(); }

  // Shared with KeyboardControl, as in the Python example.
  float player_max_speed = 1.589f;
  float player_max_speed_fast = 3.713f;
  bool recording_enabled = false;
  double recording_start = 0.0;
  bool constant_velocity_enabled = false;
  bool show_vehicle_telemetry = false;
  bool doors_are_open = false;

private:
  // Blueprints matching the filter and generation, as in get_actor_blueprints().
  std::vector<ca::ActorBlueprint> GetActorBlueprints() const {
    const auto library = world_.GetBlueprintLibrary()->Filter(options_.filter);
    std::vector<ca::ActorBlueprint> blueprints;
    for (size_t i = 0; i < library->size(); ++i) blueprints.push_back((*library)[i]);

    std::string generation = options_.generation;
    std::transform(generation.begin(), generation.end(), generation.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (generation == "all") return blueprints;
    // If the filter returns only one bp, we assume that this one needed
    // and therefore, we ignore the generation.
    if (blueprints.size() == 1) return blueprints;

    int wanted = 0;
    try {
      wanted = std::stoi(generation);
    } catch (const std::exception &) {
      wanted = 0;
    }
    if (wanted < 1 || wanted > 3) {
      std::cout << "   Warning! Actor Generation is not valid. No actor will be spawned.\n";
      return {};
    }
    std::vector<ca::ActorBlueprint> filtered;
    for (const auto &blueprint : blueprints) {
      if (blueprint.ContainsAttribute("generation") &&
          std::stoi(blueprint.GetAttribute("generation").GetValue()) == wanted) {
        filtered.push_back(blueprint);
      }
    }
    return filtered;
  }

  void ModifyVehiclePhysics() {
    // If actor is not a vehicle, we cannot use the physics control.
    auto vehicle = this->vehicle();
    if (!vehicle) return;
    try {
      auto physics_control = vehicle->GetPhysicsControl();
      physics_control.use_sweep_wheel_collision = true;
      vehicle->ApplyPhysicsControl(physics_control);
    } catch (const std::exception &) {
    }
  }

  void SetUpSensors() {
    auto state = state_;
    auto hud = hud_;

    collision_sensor_ = SpawnSensor(world_, FindBlueprint(world_, "sensor.other.collision"), cg::Transform(), player_.get());
    ListenSafely(*collision_sensor_, "collision sensor", [state, hud](SensorDataPtr data) {
      auto event = boost::static_pointer_cast<csd::CollisionEvent>(data);
      const auto other = event->GetOtherActor();
      hud->Notification("Collision with '" + (other ? GetActorDisplayName(other->GetTypeId()) : std::string()) + "'");
      const auto &impulse = event->GetNormalImpulse();
      const double intensity = std::sqrt(impulse.x * impulse.x + impulse.y * impulse.y + impulse.z * impulse.z);
      std::lock_guard<std::mutex> lock(state->mutex);
      state->collision_history.emplace_back(event->GetFrame(), intensity);
      if (state->collision_history.size() > 4000) state->collision_history.pop_front();
    });

    // If the spawn object is not a vehicle, we cannot use the Lane Invasion Sensor.
    if (StartsWith(player_->GetTypeId(), "vehicle.")) {
      lane_invasion_sensor_ = SpawnSensor(world_, FindBlueprint(world_, "sensor.other.lane_invasion"), cg::Transform(), player_.get());
      ListenSafely(*lane_invasion_sensor_, "lane invasion sensor", [hud](SensorDataPtr data) {
        auto event = boost::static_pointer_cast<csd::LaneInvasionEvent>(data);
        std::set<std::string> lane_types;
        for (const auto &marking : event->GetCrossedLaneMarkings()) lane_types.insert(LaneMarkingName(marking.type));
        std::string text;
        for (const auto &type : lane_types) text += (text.empty() ? "'" : " and '") + type + "'";
        hud->Notification("Crossed line " + text);
      });
    }

    gnss_sensor_ = SpawnSensor(world_, FindBlueprint(world_, "sensor.other.gnss"),
                               cg::Transform(cg::Location(1.0f, 0.0f, 2.8f)), player_.get());
    ListenSafely(*gnss_sensor_, "GNSS sensor", [state](SensorDataPtr data) {
      auto event = boost::static_pointer_cast<csd::GnssMeasurement>(data);
      std::lock_guard<std::mutex> lock(state->mutex);
      state->latitude = event->GetLatitude();
      state->longitude = event->GetLongitude();
    });

    imu_sensor_ = SpawnSensor(world_, FindBlueprint(world_, "sensor.other.imu"), cg::Transform(), player_.get());
    ListenSafely(*imu_sensor_, "IMU sensor", [state](SensorDataPtr data) {
      auto sensor_data = boost::static_pointer_cast<csd::IMUMeasurement>(data);
      const auto accel = sensor_data->GetAccelerometer();
      const auto gyro = sensor_data->GetGyroscope();
      auto limit = [](double value) { return std::clamp(value, -99.9, 99.9); };
      std::lock_guard<std::mutex> lock(state->mutex);
      state->accelerometer = {limit(accel.x), limit(accel.y), limit(accel.z)};
      state->gyroscope = {limit(Degrees(gyro.x)), limit(Degrees(gyro.y)), limit(Degrees(gyro.z))};
      state->compass = Degrees(sensor_data->GetCompass());
    });
  }

  void Destroy() {
    radar_sensor_.reset();
    camera_manager_.reset();
    StopAndDestroy(collision_sensor_);
    StopAndDestroy(lane_invasion_sensor_);
    StopAndDestroy(gnss_sensor_);
    StopAndDestroy(imu_sensor_);
    if (player_) {
      player_->Destroy();
      player_.reset();
    }
  }

  cc::World world_;
  Options options_;
  std::shared_ptr<Hud> hud_;
  std::shared_ptr<SensorState> state_;
  std::mt19937 rng_;
  carla::SharedPtr<cc::Map> map_;
  carla::SharedPtr<cc::Actor> player_;
  carla::SharedPtr<cc::Sensor> collision_sensor_;
  carla::SharedPtr<cc::Sensor> lane_invasion_sensor_;
  carla::SharedPtr<cc::Sensor> gnss_sensor_;
  carla::SharedPtr<cc::Sensor> imu_sensor_;
  std::unique_ptr<RadarSensor> radar_sensor_;
  std::unique_ptr<CameraManager> camera_manager_;
  size_t tick_id_ = 0;
  std::vector<std::pair<std::string, crpc::WeatherParameters>> weather_presets_;
  size_t weather_index_ = 0;
  size_t current_map_layer_ = 0;
};

void Hud::Tick(const World &world, double client_fps, double milliseconds) {
  size_t frame = 0;
  double simulation_time = 0.0;
  double server_fps = 0.0;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    notification_seconds_left_ = std::max(0.0, notification_seconds_left_ - 1e-3 * milliseconds);
    frame = frame_;
    simulation_time = simulation_time_;
    server_fps = server_clock_.Fps();
  }
  if (!show_info_) return;

  const auto player = world.player();
  const cg::Transform t = player->GetTransform();
  const auto v = player->GetVelocity();

  SensorState &sensors = world.sensor_state();
  double compass = 0.0;
  std::array<double, 3> accelerometer{};
  std::array<double, 3> gyroscope{};
  double lat = 0.0;
  double lon = 0.0;
  std::map<long long, double> colhist;
  {
    std::lock_guard<std::mutex> lock(sensors.mutex);
    compass = sensors.compass;
    accelerometer = sensors.accelerometer;
    gyroscope = sensors.gyroscope;
    lat = sensors.latitude;
    lon = sensors.longitude;
    for (const auto &entry : sensors.collision_history) colhist[static_cast<long long>(entry.first)] += entry.second;
  }

  std::string heading;
  if (compass > 270.5 || compass < 89.5) heading += 'N';
  if (90.5 < compass && compass < 269.5) heading += 'S';
  if (0.5 < compass && compass < 179.5) heading += 'E';
  if (180.5 < compass && compass < 359.5) heading += 'W';

  std::vector<float> collision(200, 0.0f);
  for (int x = 0; x < 200; ++x) {
    const auto it = colhist.find(static_cast<long long>(frame) + x - 200);
    if (it != colhist.end()) collision[x] = static_cast<float>(it->second);
  }
  const float max_col = std::max(1.0f, *std::max_element(collision.begin(), collision.end()));
  for (auto &value : collision) value /= max_col;

  const auto vehicles = world.carla_world().GetActors()->Filter("vehicle.*");
  const std::string &map_name = world.map().GetName();

  info_ = {
      TextItem(Format("Server:  % 16.0f FPS", server_fps)),
      TextItem(Format("Client:  % 16.0f FPS", client_fps)),
      TextItem(""),
      TextItem(Format("Vehicle: %20s", GetActorDisplayName(player->GetTypeId(), 20).c_str())),
      TextItem(Format("Map:     %20s", map_name.substr(map_name.find_last_of('/') + 1).c_str())),
      TextItem(Format("Simulation time: %12s", FormatDuration(static_cast<long>(simulation_time)).c_str())),
      TextItem(""),
      TextItem(Format("Speed:   % 15.0f km/h", 3.6 * std::sqrt(v.x * v.x + v.y * v.y + v.z * v.z))),
      TextItem(Format("Compass:% 17.0f\xC2\xB0 %2s", compass, heading.c_str())),
      TextItem(Format("Accelero: (%5.1f,%5.1f,%5.1f)", accelerometer[0], accelerometer[1], accelerometer[2])),
      TextItem(Format("Gyroscop: (%5.1f,%5.1f,%5.1f)", gyroscope[0], gyroscope[1], gyroscope[2])),
      TextItem(Format("Location:%20s", Format("(% 5.1f, % 5.1f)", t.location.x, t.location.y).c_str())),
      TextItem(Format("GNSS:%24s", Format("(% 2.6f, % 3.6f)", lat, lon).c_str())),
      TextItem(Format("Height:  % 18.0f m", t.location.z)),
      TextItem(""),
  };
  if (const auto vehicle = world.vehicle()) {
    const auto c = vehicle->GetControl();
    info_.push_back(BarItem("Throttle:", c.throttle, 0.0f, 1.0f));
    info_.push_back(BarItem("Steer:", c.steer, -1.0f, 1.0f));
    info_.push_back(BarItem("Brake:", c.brake, 0.0f, 1.0f));
    info_.push_back(FlagItem("Reverse:", c.reverse));
    info_.push_back(FlagItem("Hand brake:", c.hand_brake));
    info_.push_back(FlagItem("Manual:", c.manual_gear_shift));
    info_.push_back(TextItem("Gear:        " + (c.gear == -1 ? std::string("R") : c.gear == 0 ? std::string("N") : std::to_string(c.gear))));
    if (show_ackermann_info_) {
      info_.push_back(TextItem(""));
      info_.push_back(TextItem("Ackermann Controller:"));
      info_.push_back(TextItem(Format("  Target speed: % 8.0f km/h", 3.6 * ackermann_control_.speed)));
    }
  } else if (const auto walker = world.walker()) {
    const auto c = walker->GetWalkerControl();
    info_.push_back(BarItem("Speed:", c.speed, 0.0f, 5.556f));
    info_.push_back(FlagItem("Jump:", c.jump));
  }
  info_.push_back(TextItem(""));
  info_.push_back(TextItem("Collision:"));
  info_.push_back(GraphItem(collision));
  info_.push_back(TextItem(""));
  info_.push_back(TextItem(Format("Number of vehicles: %8zu", vehicles->size())));

  if (vehicles->size() > 1) {
    info_.push_back(TextItem("Nearby vehicles:"));
    std::vector<std::pair<double, std::string>> nearby;
    for (const auto &vehicle : *vehicles) {
      if (vehicle->GetId() == player->GetId()) continue;
      const auto l = vehicle->GetLocation();
      const double dx = l.x - t.location.x;
      const double dy = l.y - t.location.y;
      const double dz = l.z - t.location.z;
      nearby.emplace_back(std::sqrt(dx * dx + dy * dy + dz * dz), GetActorDisplayName(vehicle->GetTypeId(), 22));
    }
    std::sort(nearby.begin(), nearby.end());
    for (const auto &entry : nearby) {
      if (entry.first > 200.0) break;
      info_.push_back(TextItem(Format("% 4dm %s", static_cast<int>(entry.first), entry.second.c_str())));
    }
  }
}

// ==============================================================================
// -- KeyboardControl -----------------------------------------------------------
// ==============================================================================

// A key event reduced to what the controls need. `key` is the key without Shift
// and Ctrl applied (like pygame/SDL key codes, so Shift+1 is still '1' and
// Ctrl+W is 'w'); `shifted` is the character the key produces with the modifiers.
struct KeyInfo {
  guint key = 0;
  guint shifted = 0;
  bool ctrl = false;
  bool shift = false;
};

static KeyInfo MakeKeyInfo(const GdkEventKey &event) {
  KeyInfo info;
  info.shifted = event.keyval;
  info.ctrl = (event.state & GDK_CONTROL_MASK) != 0;
  info.shift = (event.state & GDK_SHIFT_MASK) != 0;
  info.key = gdk_keyval_to_lower(event.keyval);
  GdkKeymap *keymap = gdk_keymap_get_for_display(gdk_display_get_default());
  guint unmodified = 0;
  if (keymap && gdk_keymap_translate_keyboard_state(keymap, event.hardware_keycode, static_cast<GdkModifierType>(0),
                                                    event.group, &unmodified, nullptr, nullptr, nullptr) &&
      unmodified != 0) {
    info.key = gdk_keyval_to_lower(unmodified);
  }
  return info;
}

// The keys that are down right now, replacing pygame.key.get_pressed().
class HeldKeys {
public:
  void Press(guint key) { keys_.insert(key); }
  void Release(guint key) { keys_.erase(key); }
  void Clear() { keys_.clear(); }
  bool IsHeld(guint key) const { return keys_.count(key) != 0; }
  bool Shift() const { return IsHeld(GDK_KEY_Shift_L) || IsHeld(GDK_KEY_Shift_R); }

private:
  std::set<guint> keys_;
};

class KeyboardControl {
public:
  KeyboardControl(World &world, bool start_in_autopilot) : autopilot_enabled_(start_in_autopilot) {
    if (const auto vehicle = world.vehicle()) {
      is_vehicle_ = true;
      vehicle->SetAutopilot(autopilot_enabled_);
      vehicle->SetLightState(static_cast<LightState>(lights_));
    } else if (const auto walker = world.walker()) {
      autopilot_enabled_ = false;
      rotation_ = walker->GetTransform().rotation;
    } else {
      throw std::runtime_error("Actor type not supported");
    }
    world.hud().Notification("Press 'H' or '?' for help.", 4.0);
  }

  void OnKeyPress(const KeyInfo &info) { held_.Press(info.key); }

  // A window that loses the focus gets no key releases: forget all held keys.
  void ReleaseAllKeys() { held_.Clear(); }

  // Handles a key release like the KEYUP events of the Python example.
  // Returns true to quit.
  bool OnKeyRelease(cc::Client &client, World &world, const KeyInfo &info, bool sync_mode) {
    held_.Release(info.key);
    const guint key = info.key;
    const bool ctrl = info.ctrl;
    const bool shift = info.shift;

    if (key == GDK_KEY_Escape || (key == GDK_KEY_q && ctrl)) {
      return true;
    } else if (key == GDK_KEY_BackSpace) {
      if (autopilot_enabled_ && world.vehicle()) {
        world.vehicle()->SetAutopilot(false);
        world.Restart();
        if (const auto vehicle = world.vehicle()) vehicle->SetAutopilot(true);
      } else {
        world.Restart();
      }
    } else if (key == GDK_KEY_F1) {
      world.hud().ToggleInfo();
    } else if (key == GDK_KEY_v && shift) {
      world.NextMapLayer(true);
    } else if (key == GDK_KEY_v) {
      world.NextMapLayer();
    } else if (key == GDK_KEY_b && shift) {
      world.LoadMapLayer(true);
    } else if (key == GDK_KEY_b) {
      world.LoadMapLayer();
    } else if (key == GDK_KEY_h || info.shifted == GDK_KEY_question || (key == GDK_KEY_slash && shift)) {
      world.hud().ToggleHelp();
    } else if (key == GDK_KEY_Tab || key == GDK_KEY_ISO_Left_Tab) {
      world.camera_manager().ToggleCamera();
    } else if (key == GDK_KEY_c && shift) {
      world.NextWeather(true);
    } else if (key == GDK_KEY_c) {
      world.NextWeather();
    } else if (key == GDK_KEY_g) {
      world.ToggleRadar();
    } else if (key == GDK_KEY_grave || key == GDK_KEY_dead_grave || key == GDK_KEY_n) {
      world.camera_manager().NextSensor();
    } else if (key == GDK_KEY_w && ctrl) {
      if (world.constant_velocity_enabled) {
        world.player()->DisableConstantVelocity();
        world.constant_velocity_enabled = false;
        world.hud().Notification("Disabled Constant Velocity Mode");
      } else {
        world.player()->EnableConstantVelocity(cg::Vector3D(17.0f, 0.0f, 0.0f));
        world.constant_velocity_enabled = true;
        world.hud().Notification("Enabled Constant Velocity Mode at 60 km/h");
      }
    } else if (key == GDK_KEY_o) {
      if (const auto vehicle = world.vehicle()) {
        try {
          if (world.doors_are_open) {
            world.hud().Notification("Closing Doors");
            world.doors_are_open = false;
            vehicle->CloseDoor(crpc::VehicleDoor::All);
          } else {
            world.hud().Notification("Opening doors");
            world.doors_are_open = true;
            vehicle->OpenDoor(crpc::VehicleDoor::All);
          }
        } catch (const std::exception &) {
        }
      }
    } else if (key == GDK_KEY_t) {
      if (const auto vehicle = world.vehicle()) {
        if (world.show_vehicle_telemetry) {
          vehicle->ShowDebugTelemetry(false);
          world.show_vehicle_telemetry = false;
          world.hud().Notification("Disabled Vehicle Telemetry");
        } else {
          try {
            vehicle->ShowDebugTelemetry(true);
            world.show_vehicle_telemetry = true;
            world.hud().Notification("Enabled Vehicle Telemetry");
          } catch (const std::exception &) {
          }
        }
      }
    } else if (key >= GDK_KEY_1 && key <= GDK_KEY_9) {
      const int index_ctrl = ctrl ? 9 : 0;
      world.camera_manager().SetSensor(static_cast<int>(key - GDK_KEY_1) + index_ctrl);
    } else if (key == GDK_KEY_r && !ctrl) {
      world.camera_manager().ToggleRecording();
    } else if (key == GDK_KEY_r && ctrl) {
      if (world.recording_enabled) {
        client.StopRecorder();
        world.recording_enabled = false;
        world.hud().Notification("Recorder is OFF");
      } else {
        client.StartRecorder(RECORDING_FILE);
        world.recording_enabled = true;
        world.hud().Notification("Recorder is ON");
      }
    } else if (key == GDK_KEY_p && ctrl) {
      // stop recorder
      client.StopRecorder();
      world.recording_enabled = false;
      // work around to fix camera at start of replaying
      const int current_index = world.camera_manager().index();
      world.DestroySensors();
      // disable autopilot
      autopilot_enabled_ = false;
      if (const auto vehicle = world.vehicle()) vehicle->SetAutopilot(autopilot_enabled_);
      world.hud().Notification(std::string("Replaying file '") + RECORDING_FILE + "'");
      // replayer
      ReplayFile(client, RECORDING_FILE, world.recording_start, 0);
      world.camera_manager().SetSensor(std::max(current_index, 0));
    } else if ((key == GDK_KEY_minus || key == GDK_KEY_KP_Subtract) && ctrl) {
      world.recording_start -= shift ? 10 : 1;
      world.hud().Notification(Format("Recording start time is %d", static_cast<int>(world.recording_start)));
    } else if ((key == GDK_KEY_equal || key == GDK_KEY_plus || key == GDK_KEY_KP_Add) && ctrl) {
      world.recording_start += shift ? 10 : 1;
      world.hud().Notification(Format("Recording start time is %d", static_cast<int>(world.recording_start)));
    }

    if (is_vehicle_) {
      if (key == GDK_KEY_f) {
        // Toggle ackermann controller
        ackermann_enabled_ = !ackermann_enabled_;
        world.hud().ShowAckermannInfo(ackermann_enabled_);
        world.hud().Notification(std::string("Ackermann Controller ") + (ackermann_enabled_ ? "Enabled" : "Disabled"));
      }
      if (key == GDK_KEY_q && !ctrl) {
        if (!ackermann_enabled_) {
          control_.gear = control_.reverse ? 1 : -1;
        } else {
          ackermann_reverse_ *= -1;
          // Reset ackermann control
          ackermann_control_ = crpc::VehicleAckermannControl();
        }
      } else if (key == GDK_KEY_m) {
        control_.manual_gear_shift = !control_.manual_gear_shift;
        if (const auto vehicle = world.vehicle()) control_.gear = vehicle->GetControl().gear;
        world.hud().Notification(std::string(control_.manual_gear_shift ? "Manual" : "Automatic") + " Transmission");
      } else if (control_.manual_gear_shift && key == GDK_KEY_comma) {
        control_.gear = std::max(-1, control_.gear - 1);
      } else if (control_.manual_gear_shift && key == GDK_KEY_period) {
        control_.gear = control_.gear + 1;
      } else if (key == GDK_KEY_p && !ctrl) {
        if (!autopilot_enabled_ && !sync_mode) {
          std::cout << "WARNING: You are currently in asynchronous mode and could "
                       "experience some issues with the traffic simulation" << std::endl;
        }
        autopilot_enabled_ = !autopilot_enabled_;
        if (const auto vehicle = world.vehicle()) vehicle->SetAutopilot(autopilot_enabled_);
        world.hud().Notification(std::string("Autopilot ") + (autopilot_enabled_ ? "On" : "Off"));
      } else if (key == GDK_KEY_l && ctrl) {
        pending_lights_ ^= Flag(LightState::Special1);
      } else if (key == GDK_KEY_l && shift) {
        pending_lights_ ^= Flag(LightState::HighBeam);
      } else if (key == GDK_KEY_l) {
        // Use 'L' key to switch between lights:
        // closed -> position -> low beam -> fog
        if (!(lights_ & Flag(LightState::Position))) {
          world.hud().Notification("Position lights");
          pending_lights_ |= Flag(LightState::Position);
        } else {
          world.hud().Notification("Low beam lights");
          pending_lights_ |= Flag(LightState::LowBeam);
        }
        if (lights_ & Flag(LightState::LowBeam)) {
          world.hud().Notification("Fog lights");
          pending_lights_ |= Flag(LightState::Fog);
        }
        if (lights_ & Flag(LightState::Fog)) {
          world.hud().Notification("Lights off");
          pending_lights_ ^= Flag(LightState::Position);
          pending_lights_ ^= Flag(LightState::LowBeam);
          pending_lights_ ^= Flag(LightState::Fog);
        }
      } else if (key == GDK_KEY_i) {
        pending_lights_ ^= Flag(LightState::Interior);
      } else if (key == GDK_KEY_z) {
        pending_lights_ ^= Flag(LightState::LeftBlinker);
      } else if (key == GDK_KEY_x) {
        pending_lights_ ^= Flag(LightState::RightBlinker);
      }
    }
    return false;
  }

  // Applies the held keys to the actor. Called once per frame.
  void Apply(World &world, double milliseconds) {
    LightFlags current_lights = pending_lights_;
    if (!autopilot_enabled_) {
      if (is_vehicle_) {
        if (const auto vehicle = world.vehicle()) {
          ParseVehicleKeys(milliseconds);
          control_.reverse = control_.gear < 0;
          // Set automatic control-related vehicle lights
          if (control_.brake > 0.0f) {
            current_lights |= Flag(LightState::Brake);
          } else {  // Remove the Brake flag
            current_lights &= ~Flag(LightState::Brake);
          }
          if (control_.reverse) {
            current_lights |= Flag(LightState::Reverse);
          } else {  // Remove the Reverse flag
            current_lights &= ~Flag(LightState::Reverse);
          }
          if (current_lights != lights_) {  // Change the light state only if necessary
            lights_ = current_lights;
            vehicle->SetLightState(static_cast<LightState>(lights_));
          }
          // Apply control
          if (!ackermann_enabled_) {
            vehicle->ApplyControl(control_);
          } else {
            vehicle->ApplyAckermannControl(ackermann_control_);
            // Update control to the last one applied by the ackermann controller.
            control_ = vehicle->GetControl();
            // Update hud with the newest ackermann control
            world.hud().UpdateAckermannControl(ackermann_control_);
          }
        }
      } else if (const auto walker = world.walker()) {
        ParseWalkerKeys(milliseconds, world);
        walker->ApplyControl(walker_control_);
      }
    }
    // The Python example starts every frame from the applied light state.
    pending_lights_ = lights_;
  }

private:
  bool Pressed(guint key) const { return held_.IsHeld(key); }

  void ParseVehicleKeys(double milliseconds) {
    if (Pressed(GDK_KEY_Up) || Pressed(GDK_KEY_w)) {
      if (!ackermann_enabled_) {
        control_.throttle = std::min(control_.throttle + 0.1f, 1.00f);
      } else {
        ackermann_control_.speed += static_cast<float>(Round(milliseconds * 0.005, 2)) * ackermann_reverse_;
      }
    } else if (!ackermann_enabled_) {
      control_.throttle = 0.0f;
    }

    if (Pressed(GDK_KEY_Down) || Pressed(GDK_KEY_s)) {
      if (!ackermann_enabled_) {
        control_.brake = std::min(control_.brake + 0.2f, 1.0f);
      } else {
        ackermann_control_.speed -= std::min(std::abs(ackermann_control_.speed),
                                             static_cast<float>(Round(milliseconds * 0.005, 2))) * ackermann_reverse_;
        ackermann_control_.speed = std::max(0.0f, std::abs(ackermann_control_.speed)) * ackermann_reverse_;
      }
    } else if (!ackermann_enabled_) {
      control_.brake = 0.0f;
    }

    const double steer_increment = 5e-4 * milliseconds;
    if (Pressed(GDK_KEY_Left) || Pressed(GDK_KEY_a)) {
      if (steer_cache_ > 0) {
        steer_cache_ = 0;
      } else {
        steer_cache_ -= steer_increment;
      }
    } else if (Pressed(GDK_KEY_Right) || Pressed(GDK_KEY_d)) {
      if (steer_cache_ < 0) {
        steer_cache_ = 0;
      } else {
        steer_cache_ += steer_increment;
      }
    } else {
      steer_cache_ = 0.0;
    }
    steer_cache_ = std::min(0.7, std::max(-0.7, steer_cache_));
    if (!ackermann_enabled_) {
      control_.steer = static_cast<float>(Round(steer_cache_, 1));
      control_.hand_brake = Pressed(GDK_KEY_space);
    } else {
      ackermann_control_.steer = static_cast<float>(Round(steer_cache_, 1));
    }
  }

  void ParseWalkerKeys(double milliseconds, const World &world) {
    walker_control_.speed = 0.0f;
    if (Pressed(GDK_KEY_Down) || Pressed(GDK_KEY_s)) {
      walker_control_.speed = 0.0f;
    }
    if (Pressed(GDK_KEY_Left) || Pressed(GDK_KEY_a)) {
      walker_control_.speed = 0.01f;
      rotation_.yaw -= static_cast<float>(0.08 * milliseconds);
    }
    if (Pressed(GDK_KEY_Right) || Pressed(GDK_KEY_d)) {
      walker_control_.speed = 0.01f;
      rotation_.yaw += static_cast<float>(0.08 * milliseconds);
    }
    if (Pressed(GDK_KEY_Up) || Pressed(GDK_KEY_w)) {
      walker_control_.speed = held_.Shift() ? world.player_max_speed_fast : world.player_max_speed;
    }
    walker_control_.jump = Pressed(GDK_KEY_space);
    rotation_.yaw = static_cast<float>(Round(rotation_.yaw, 1));
    walker_control_.direction = rotation_.GetForwardVector();
  }

  bool autopilot_enabled_;
  bool is_vehicle_ = false;
  bool ackermann_enabled_ = false;
  float ackermann_reverse_ = 1.0f;
  crpc::VehicleControl control_;
  crpc::VehicleAckermannControl ackermann_control_;
  crpc::WalkerControl walker_control_;
  cg::Rotation rotation_;
  LightFlags lights_ = Flag(LightState::None);          // last state sent to the server
  LightFlags pending_lights_ = Flag(LightState::None);  // lights_ plus the toggles of this frame
  double steer_cache_ = 0.0;
  HeldKeys held_;
};

// ==============================================================================
// -- game_loop() ---------------------------------------------------------------
// ==============================================================================

// Runs a function when the scope is left, also by an exception (Python: finally).
template <typename F>
class ScopeExit {
public:
  explicit ScopeExit(F function) : function_(std::move(function)) {}
  ~ScopeExit() {
    try {
      function_();
    } catch (const std::exception &error) {
      std::cerr << "cleanup failed: " << error.what() << std::endl;
    }
  }
  ScopeExit(const ScopeExit &) = delete;
  ScopeExit &operator=(const ScopeExit &) = delete;

private:
  F function_;
};

// Everything the GTK callbacks work on. Callbacks must not let exceptions escape
// into GLib, so they store the message in `error` and stop the main loop.
struct Gui {
  const Options *options = nullptr;
  cc::Client *client = nullptr;
  cc::World *sim_world = nullptr;
  World *world = nullptr;
  KeyboardControl *controller = nullptr;
  GtkWidget *area = nullptr;
  Clock::time_point started;
  Clock::time_point previous;
  FpsCounter client_clock;
  bool screenshot_done = false;
  std::string error;
};

static void Fail(Gui &gui, const std::exception &error) {
  gui.error = error.what();
  gtk_main_quit();
}

static void DrawScene(Gui &gui, cairo_t *cr) {
  cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);
  cairo_paint(cr);
  gui.world->Render(cr);
}

// --screenshot: saves the first complete frame that shows a camera picture.
static void MaybeSaveScreenshot(Gui &gui) {
  const Options &options = *gui.options;
  if (options.screenshot.empty() || gui.screenshot_done || !gui.world->camera_manager().has_frame()) return;
  if (Clock::now() - gui.started < std::chrono::duration<double>(options.screenshot_delay)) return;

  cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, options.width, options.height);
  cairo_t *cr = cairo_create(surface);
  DrawScene(gui, cr);
  cairo_destroy(cr);
  const bool saved = cairo_surface_write_to_png(surface, options.screenshot.c_str()) == CAIRO_STATUS_SUCCESS;
  cairo_surface_destroy(surface);
  gui.screenshot_done = true;
  std::cout << (saved ? "Screenshot saved: " : "Screenshot FAILED: ") << options.screenshot << std::endl;
}

static gboolean OnDraw(GtkWidget *, cairo_t *cr, gpointer data) {
  auto &gui = *static_cast<Gui *>(data);
  if (!gui.world) {  // still connecting: show a black window
    cairo_set_source_rgb(cr, 0.0, 0.0, 0.0);
    cairo_paint(cr);
    return FALSE;
  }
  DrawScene(gui, cr);
  MaybeSaveScreenshot(gui);
  return FALSE;
}

static gboolean OnKeyPress(GtkWidget *, GdkEventKey *event, gpointer data) {
  auto &gui = *static_cast<Gui *>(data);
  if (gui.controller) gui.controller->OnKeyPress(MakeKeyInfo(*event));
  return TRUE;
}

static gboolean OnKeyRelease(GtkWidget *, GdkEventKey *event, gpointer data) {
  auto &gui = *static_cast<Gui *>(data);
  if (!gui.controller) return TRUE;
  try {
    if (gui.controller->OnKeyRelease(*gui.client, *gui.world, MakeKeyInfo(*event), gui.options->sync)) {
      gtk_main_quit();
    }
  } catch (const std::exception &error) {
    Fail(gui, error);
  }
  return TRUE;
}

static gboolean OnFocusOut(GtkWidget *, GdkEventFocus *, gpointer data) {
  auto &gui = *static_cast<Gui *>(data);
  if (gui.controller) gui.controller->ReleaseAllKeys();
  return FALSE;
}

static gboolean OnDelete(GtkWidget *, GdkEvent *, gpointer) {
  gtk_main_quit();
  return TRUE;  // the window is destroyed after the main loop, with the rest of the cleanup
}

// One frame, about every 16 ms: like one pass of the pygame loop.
static gboolean OnTick(gpointer data) {
  auto &gui = *static_cast<Gui *>(data);
  if (g_quit_requested) {
    gtk_main_quit();
    return G_SOURCE_REMOVE;
  }
  try {
    if (gui.options->sync) gui.sim_world->Tick(TIMEOUT);
    const auto now = Clock::now();
    const double milliseconds = std::chrono::duration<double, std::milli>(now - gui.previous).count();
    gui.previous = now;
    gui.client_clock.Tick();
    gui.controller->Apply(*gui.world, milliseconds);
    gui.world->Tick(gui.client_clock.Fps(), milliseconds);
    gtk_widget_queue_draw(gui.area);
  } catch (const std::exception &error) {
    Fail(gui, error);
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

// A terminal started from the VS Code snap exports GTK_PATH, GIO_MODULE_DIR, ... pointing
// into /snap/code. GTK would load those modules, which are built against the snap's own
// glibc, into this program and die with "undefined symbol: __libc_pthread_init". Drop
// such variables, and restore the XDG paths the snap saved, before GTK starts.
static void ScrubSnapEnvironment() {
  static const char *const kGtkVariables[] = {"GTK_PATH",          "GTK_EXE_PREFIX",       "GTK_IM_MODULE_FILE",
                                              "GDK_PIXBUF_MODULE_FILE", "GDK_PIXBUF_MODULEDIR", "GIO_MODULE_DIR",
                                              "GSETTINGS_SCHEMA_DIR", "LOCPATH"};
  auto points_into_snap = [](const char *value) {
    return value != nullptr && std::string(value).find("/snap/") != std::string::npos;
  };
  for (const char *name : kGtkVariables) {
    if (points_into_snap(std::getenv(name))) unsetenv(name);
  }
  for (const char *name : {"XDG_DATA_DIRS", "XDG_CONFIG_DIRS"}) {
    const char *original = std::getenv((std::string(name) + "_VSCODE_SNAP_ORIG").c_str());
    if (original != nullptr && points_into_snap(std::getenv(name))) setenv(name, original, 1);
  }
}

static void GameLoop(const Options &options) {
  ScrubSnapEnvironment();
  // gtk_init() would call setlocale(LC_ALL, ""). With a German LC_NUMERIC, LibCarla then
  // reads the OpenDRIVE map ("1.5") and the config values wrongly, and parsing the map
  // crashes. Keep the "C" locale; GTK and Pango work with UTF-8 text regardless of it.
  gtk_disable_setlocale();
  if (!gtk_init_check(nullptr, nullptr)) {
    throw std::runtime_error("cannot open the display (is DISPLAY set?)");
  }
  std::setlocale(LC_ALL, "C");

  cc::Client client(options.host, options.port);
  client.SetTimeout(TIMEOUT);

  cc::World sim_world = client.GetWorld();
  const crpc::EpisodeSettings original_settings = sim_world.GetSettings();
  ScopeExit restore_settings([&] {
    if (options.sync) sim_world.ApplySettings(original_settings, TIMEOUT);
  });
  if (options.sync) {
    auto settings = sim_world.GetSettings();
    if (!settings.synchronous_mode) {
      settings.synchronous_mode = true;
      settings.fixed_delta_seconds = 0.05;
    }
    sim_world.ApplySettings(settings, TIMEOUT);

    auto traffic_manager = client.GetInstanceTM();
    traffic_manager.SetSynchronousMode(true);
  }

  if (options.autopilot && !sim_world.GetSettings().synchronous_mode) {
    std::cout << "WARNING: You are currently in asynchronous mode and could "
                 "experience some issues with the traffic simulation" << std::endl;
  }

  Gui gui;
  gui.options = &options;
  gui.client = &client;
  gui.sim_world = &sim_world;

  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  ScopeExit destroy_window([&] { gtk_widget_destroy(window); });
  gtk_window_set_title(GTK_WINDOW(window), "CARLA Manual Control");
  gtk_window_set_resizable(GTK_WINDOW(window), FALSE);
  gtk_widget_add_events(window, GDK_KEY_PRESS_MASK | GDK_KEY_RELEASE_MASK | GDK_FOCUS_CHANGE_MASK);
  gui.area = gtk_drawing_area_new();
  gtk_widget_set_size_request(gui.area, options.width, options.height);
  gtk_container_add(GTK_CONTAINER(window), gui.area);
  g_signal_connect(gui.area, "draw", G_CALLBACK(OnDraw), &gui);
  g_signal_connect(window, "key-press-event", G_CALLBACK(OnKeyPress), &gui);
  g_signal_connect(window, "key-release-event", G_CALLBACK(OnKeyRelease), &gui);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(OnFocusOut), &gui);
  g_signal_connect(window, "delete-event", G_CALLBACK(OnDelete), &gui);
  gtk_widget_show_all(window);
  // Show the black window now: setting up the world below blocks for a while.
  while (gtk_events_pending()) gtk_main_iteration();

  auto hud = std::make_shared<Hud>(options.width, options.height);
  World world(sim_world, hud, options);
  gui.world = &world;
  ScopeExit stop_recorder([&] {
    if (world.recording_enabled) client.StopRecorder();
  });
  KeyboardControl controller(world, options.autopilot);
  gui.controller = &controller;

  if (options.sync) {
    sim_world.Tick(TIMEOUT);
  } else {
    sim_world.WaitForTick(TIMEOUT);
  }

  gui.started = gui.previous = Clock::now();
  g_timeout_add(16, OnTick, &gui);
  gtk_main();

  gui.controller = nullptr;
  gui.world = nullptr;
  if (!gui.error.empty()) throw std::runtime_error(gui.error);
}

// ==============================================================================
// -- main() --------------------------------------------------------------------
// ==============================================================================

int main(int argc, const char *argv[]) {
  Options options;
  try {
    options = ParseArgs(argc, argv);
  } catch (const std::exception &error) {
    std::cerr << error.what() << "\n";
    PrintUsage();
    return 2;
  }

  std::cout << "INFO: config " << (options.config_path.empty() ? "none (built-in defaults)" : options.config_path)
            << ", vehicle " << options.filter << "\n";
  std::cout << "INFO: listening to server " << options.host << ":" << options.port << "\n";
  std::cout << kHelpText << std::endl;

  std::signal(SIGINT, OnQuitSignal);
  std::signal(SIGTERM, OnQuitSignal);
  try {
    GameLoop(options);
    if (g_quit_requested) std::cout << "\nCancelled by user. Bye!" << std::endl;
  } catch (const std::exception &error) {
    std::cerr << "ERROR: " << error.what() << std::endl;
    return 1;
  }
  return 0;
}
