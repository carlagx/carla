// SDL2 + SDL2_ttf side of the GUI benchmark (see scene.h).
//   bench_sdl accel|software|offscreen [seconds] [--font PATH] [--cache] [--no-picture] [--no-text]
//                                              [--static-texture] [--lock-texture] [--ring N]
//   accel      window, SDL's hardware accelerated renderer (OpenGL), paced to 60 fps
//   software   window, SDL's software renderer
//   offscreen  software renderer into a memory surface, no window: pure CPU drawing cost
#include <SDL.h>
#include <SDL_ttf.h>

#include <cstring>
#include <map>
#include <memory>

#include "scene.h"

// With --cache, rendered lines are kept as textures and reused when the same text comes
// again (the 19 static HUD lines); changing lines are rendered anew. Bounded size.
static bool g_cache = false;
static bool g_no_picture = false;  // ablation: skip the camera picture
static bool g_no_text = false;     // ablation: skip all text
static bool g_static_texture = false;  // picture texture is SDL_TEXTUREACCESS_STATIC instead of STREAMING
static bool g_lock_texture = false;    // upload with SDL_LockTexture + memcpy instead of SDL_UpdateTexture
static int g_textures_ring = 1;        // --ring N: rotate through N picture textures (avoids overwriting one the GPU still reads)
static std::map<std::string, SDL_Texture *> g_textures;

static void Text(SDL_Renderer *r, TTF_Font *font, const std::string &text, int x, int y) {
  if (g_no_text) return;
  if (g_cache) {
    auto it = g_textures.find(text);
    if (it == g_textures.end()) {
      if (g_textures.size() > 200) {
        for (auto &entry : g_textures) SDL_DestroyTexture(entry.second);
        g_textures.clear();
      }
      SDL_Surface *s = TTF_RenderUTF8_Blended(font, text.c_str(), SDL_Color{255, 255, 255, 255});
      it = g_textures.emplace(text, s ? SDL_CreateTextureFromSurface(r, s) : nullptr).first;
      if (s) SDL_FreeSurface(s);
    }
    if (it->second) {
      int w = 0, h = 0;
      SDL_QueryTexture(it->second, nullptr, nullptr, &w, &h);
      const SDL_Rect dst{x, y, w, h};
      SDL_RenderCopy(r, it->second, nullptr, &dst);
    }
    return;
  }
  SDL_Surface *s = TTF_RenderUTF8_Blended(font, text.c_str(), SDL_Color{255, 255, 255, 255});
  if (!s) return;
  if (SDL_Texture *t = SDL_CreateTextureFromSurface(r, s)) {
    const SDL_Rect dst{x, y, s->w, s->h};
    SDL_RenderCopy(r, t, nullptr, &dst);
    SDL_DestroyTexture(t);
  }
  SDL_FreeSurface(s);
}

static void Fill(SDL_Renderer *r, SDL_Rect rect, Uint8 red, Uint8 g, Uint8 b, Uint8 a) {
  SDL_SetRenderDrawColor(r, red, g, b, a);
  SDL_RenderFillRect(r, &rect);
}

static void Draw(SDL_Renderer *r, SDL_Texture *const *pictures, const Scene &scene, TTF_Font *font, int frame) {
  SDL_Texture *picture = pictures[frame % g_textures_ring];
  SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
  SDL_RenderClear(r);
  if (!g_no_picture) {
    const uint8_t *pixels = scene.pictures[frame % kPictures].data();
    if (g_lock_texture) {
      void *dst = nullptr;
      int pitch = 0;
      if (SDL_LockTexture(picture, nullptr, &dst, &pitch) == 0) {
        for (int row = 0; row < H; ++row) std::memcpy(static_cast<uint8_t *>(dst) + static_cast<size_t>(row) * pitch, pixels + static_cast<size_t>(row) * W * 4, W * 4);
        SDL_UnlockTexture(picture);
      }
    } else {
      SDL_UpdateTexture(picture, nullptr, pixels, W * 4);
    }
    SDL_RenderCopy(r, picture, nullptr, nullptr);
  }

  Fill(r, {0, 0, 220, H}, 0, 0, 0, 100);
  int y = 4;
  for (const auto &line : scene.Lines(frame)) {
    Text(r, font, line, 8, y);
    y += 18;
  }
  for (int bar = 0; bar < 3; ++bar) {  // outlined bar with a fill, like Throttle/Steer/Brake
    const int by = 4 + (10 + bar) * 18 + 8;
    SDL_SetRenderDrawColor(r, 255, 255, 255, 255);
    const SDL_Rect outline{100, by, 106, 6};
    SDL_RenderDrawRect(r, &outline);
    Fill(r, {100, by, 20 + (frame * 3 + bar * 30) % 80, 6}, 255, 255, 255, 255);
  }
  SDL_Point points[200];
  for (int i = 0; i < 200; ++i) points[i] = {i + 8, y + 8 + static_cast<int>((1.0f - scene.graph[i]) * 30.0f)};
  SDL_SetRenderDrawColor(r, 255, 136, 0, 255);
  SDL_RenderDrawLines(r, points, 200);
  for (auto &p : points) ++p.y;
  SDL_RenderDrawLines(r, points, 200);

  Fill(r, {0, H - 40, W, 40}, 0, 0, 0, 200);
  Text(r, font, "Collision with 'Traffic Light'", 10, H - 40 + 11);
}

int main(int argc, char **argv) {
  const std::string mode = argc > 1 ? argv[1] : "accel";
  const double seconds = argc > 2 ? std::atof(argv[2]) : 10.0;
  const char *font_arg = nullptr;
  for (int i = 3; i < argc; ++i) {
    if (!std::strcmp(argv[i], "--font") && i + 1 < argc) font_arg = argv[i + 1];
    if (!std::strcmp(argv[i], "--cache")) g_cache = true;
    if (!std::strcmp(argv[i], "--no-picture")) g_no_picture = true;
    if (!std::strcmp(argv[i], "--no-text")) g_no_text = true;
    if (!std::strcmp(argv[i], "--static-texture")) g_static_texture = true;
    if (!std::strcmp(argv[i], "--lock-texture")) g_lock_texture = true;
    if (!std::strcmp(argv[i], "--ring") && i + 1 < argc) g_textures_ring = std::max(1, std::atoi(argv[i + 1]));
  }

  Scene scene;
  if (SDL_Init(SDL_INIT_VIDEO) != 0 || TTF_Init() != 0) { std::fprintf(stderr, "init failed: %s\n", SDL_GetError()); return 1; }
  const std::string font_path = FindMonoFont(font_arg);
  std::unique_ptr<TTF_Font, decltype(&TTF_CloseFont)> font(TTF_OpenFont(font_path.c_str(), 14), &TTF_CloseFont);
  if (!font) { std::fprintf(stderr, "no font (%s): %s\n", font_path.c_str(), TTF_GetError()); return 1; }

  SDL_Window *window = nullptr;
  SDL_Surface *surface = nullptr;
  SDL_Renderer *renderer = nullptr;
  if (mode == "offscreen") {
    surface = SDL_CreateRGBSurfaceWithFormat(0, W, H, 32, SDL_PIXELFORMAT_BGRA32);
    renderer = SDL_CreateSoftwareRenderer(surface);
  } else {
    window = SDL_CreateWindow("bench_sdl", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, W, H, SDL_WINDOW_SHOWN);
    renderer = window ? SDL_CreateRenderer(window, -1, mode == "software" ? SDL_RENDERER_SOFTWARE : SDL_RENDERER_ACCELERATED) : nullptr;
  }
  if (!renderer) { std::fprintf(stderr, "no renderer: %s\n", SDL_GetError()); return 1; }
  SDL_RendererInfo info{};
  SDL_GetRendererInfo(renderer, &info);
  SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
  SDL_Texture *pictures[16] = {};
  for (int i = 0; i < std::min(g_textures_ring, 16); ++i) pictures[i] = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_BGRA32, g_static_texture ? SDL_TEXTUREACCESS_STATIC : SDL_TEXTUREACCESS_STREAMING, W, H);

  Stats stats;
  const double start = Now();
  double next = start;
  int frame = 0;
  const double warmup = 1.0;
  bool began = false;
  while (Now() - start < seconds + warmup) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {}
    if (!began && Now() - start >= warmup) { stats.Begin(); began = true; }
    const double t0 = Now();
    Draw(renderer, pictures, scene, font.get(), frame++);
    SDL_RenderPresent(renderer);
    if (began) stats.Add(Now() - t0);
    next += 1.0 / kFps;
    const double wait = next - Now();
    if (wait > 0) SDL_Delay(static_cast<Uint32>(wait * 1000.0));
  }
  char name[96];
  std::snprintf(name, sizeof(name), "sdl_%s%s%s%s[%s]", mode.c_str(), g_cache ? "+cache" : "",
                g_no_picture ? "-picture" : "", g_no_text ? "-text" : "", info.name);
  {
    // which SDL video driver was picked (x11, wayland, dummy ...)
    const char *driver = SDL_GetCurrentVideoDriver();
    std::snprintf(name + std::strlen(name) - 1, sizeof(name) - std::strlen(name) + 1, "/%s]", driver ? driver : "?");
  }
  if (g_static_texture) std::strcat(name, "+static");
  if (g_lock_texture) std::strcat(name, "+lock");
  if (g_textures_ring > 1) std::snprintf(name + std::strlen(name), sizeof(name) - std::strlen(name), "+ring%d", g_textures_ring);
  stats.Report(name);
  return 0;
}
