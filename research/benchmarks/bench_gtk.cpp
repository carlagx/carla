// GTK3 + Cairo + Pango side of the GUI benchmark (see scene.h).
//   bench_gtk window|offscreen [seconds] [--cache] [--no-picture] [--no-text]
//   window     GtkDrawingArea in a GtkWindow, redrawn every 16 ms
//   offscreen  the same drawing code into a cairo image surface, no window and no GTK:
//              pure CPU drawing cost
#include <gtk/gtk.h>
#include <pango/pangocairo.h>

#include <clocale>
#include <cstring>
#include <map>
#include <memory>

#include "scene.h"

struct Ctx {
  Scene scene;
  Stats stats;
  PangoFontDescription *font = nullptr;
  GtkWidget *area = nullptr;
  int frame = 0;
  bool window_mode = false;
  double seconds = 10.0;
  double start = 0;
  bool began = false;
};

// With --cache, the shaped PangoLayout of a line is kept and reused when the same text comes
// again (the 19 static HUD lines); changing lines get a new layout. Bounded size.
static bool g_cache = false;
static bool g_no_picture = false;  // ablation: skip the camera picture
static bool g_no_text = false;     // ablation: skip all text
static std::map<std::string, PangoLayout *> g_layouts;

static void Text(cairo_t *cr, const PangoFontDescription *font, const std::string &text, double x, double y) {
  if (g_no_text) return;
  PangoLayout *layout = nullptr;
  if (g_cache) {
    auto it = g_layouts.find(text);
    if (it == g_layouts.end()) {
      if (g_layouts.size() > 200) {
        for (auto &entry : g_layouts) g_object_unref(entry.second);
        g_layouts.clear();
      }
      layout = pango_cairo_create_layout(cr);
      pango_layout_set_font_description(layout, font);
      pango_layout_set_text(layout, text.c_str(), -1);
      it = g_layouts.emplace(text, layout).first;
    }
    layout = it->second;
    pango_cairo_update_layout(cr, layout);
  } else {
    layout = pango_cairo_create_layout(cr);
    pango_layout_set_font_description(layout, font);
    pango_layout_set_text(layout, text.c_str(), -1);
  }
  cairo_set_source_rgb(cr, 1, 1, 1);
  cairo_move_to(cr, x, y);
  pango_cairo_show_layout(cr, layout);
  if (!g_cache) g_object_unref(layout);
}

static void Fill(cairo_t *cr, double x, double y, double w, double h, double r, double g, double b, double a) {
  cairo_set_source_rgba(cr, r, g, b, a);
  cairo_rectangle(cr, x, y, w, h);
  cairo_fill(cr);
}

static void Draw(cairo_t *cr, Ctx &ctx) {
  cairo_set_source_rgb(cr, 0, 0, 0);
  cairo_paint(cr);
  if (!g_no_picture) {
    cairo_surface_t *picture = cairo_image_surface_create_for_data(
        ctx.scene.pictures[ctx.frame % kPictures].data(), CAIRO_FORMAT_ARGB32, W, H, W * 4);
    cairo_set_source_surface(cr, picture, 0, 0);
    cairo_paint(cr);
    cairo_surface_destroy(picture);
  }

  Fill(cr, 0, 0, 220, H, 0, 0, 0, 100.0 / 255.0);
  double y = 4;
  for (const auto &line : ctx.scene.Lines(ctx.frame)) {
    Text(cr, ctx.font, line, 8, y);
    y += 18;
  }
  for (int bar = 0; bar < 3; ++bar) {
    const double by = 4 + (10 + bar) * 18 + 8;
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_set_line_width(cr, 1);
    cairo_rectangle(cr, 100.5, by + 0.5, 105, 5);
    cairo_stroke(cr);
    Fill(cr, 100, by, 20 + (ctx.frame * 3 + bar * 30) % 80, 6, 1, 1, 1, 1);
  }
  cairo_set_source_rgb(cr, 1, 136.0 / 255.0, 0);
  cairo_set_line_width(cr, 2);
  for (size_t i = 0; i < ctx.scene.graph.size(); ++i) {
    const double px = static_cast<double>(i) + 8;
    const double py = y + 8 + static_cast<int>((1.0f - ctx.scene.graph[i]) * 30.0f);
    if (i == 0) cairo_move_to(cr, px, py); else cairo_line_to(cr, px, py);
  }
  cairo_stroke(cr);

  Fill(cr, 0, H - 40, W, 40, 0, 0, 0, 200.0 / 255.0);
  Text(cr, ctx.font, "Collision with 'Traffic Light'", 10, H - 40 + 11);
}

static std::string Name(const char *base) {
  return std::string(base) + (g_cache ? "+cache" : "") + (g_no_picture ? "-picture" : "") + (g_no_text ? "-text" : "") + "[cairo]";
}

static gboolean OnDraw(GtkWidget *, cairo_t *cr, gpointer data) {
  auto &ctx = *static_cast<Ctx *>(data);
  const double t0 = Now();
  Draw(cr, ctx);
  if (ctx.began) ctx.stats.Add(Now() - t0);
  return FALSE;
}

static gboolean OnTimer(gpointer data) {
  auto &ctx = *static_cast<Ctx *>(data);
  ++ctx.frame;
  if (!ctx.began && Now() - ctx.start >= 1.0) { ctx.stats.Begin(); ctx.began = true; }
  if (Now() - ctx.start >= ctx.seconds + 1.0) { gtk_main_quit(); return G_SOURCE_REMOVE; }
  gtk_widget_queue_draw(ctx.area);
  return G_SOURCE_CONTINUE;
}

int main(int argc, char **argv) {
  Ctx ctx;
  const std::string mode = argc > 1 ? argv[1] : "window";
  ctx.seconds = argc > 2 ? std::atof(argv[2]) : 10.0;
  for (int i = 3; i < argc; ++i) {
    if (!std::strcmp(argv[i], "--cache")) g_cache = true;
    if (!std::strcmp(argv[i], "--no-picture")) g_no_picture = true;
    if (!std::strcmp(argv[i], "--no-text")) g_no_text = true;
  }
  ctx.window_mode = mode == "window";
  ctx.font = pango_font_description_from_string("Monospace 10");
  pango_font_description_set_absolute_size(ctx.font, 14 * PANGO_SCALE);

  if (!ctx.window_mode) {
    cairo_surface_t *surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, W, H);
    cairo_t *cr = cairo_create(surface);
    ctx.start = Now();
    double next = ctx.start;
    while (Now() - ctx.start < ctx.seconds + 1.0) {
      if (!ctx.began && Now() - ctx.start >= 1.0) { ctx.stats.Begin(); ctx.began = true; }
      const double t0 = Now();
      Draw(cr, ctx);
      if (ctx.began) ctx.stats.Add(Now() - t0);
      ++ctx.frame;
      next += 1.0 / kFps;
      const double wait = next - Now();
      if (wait > 0) { timespec ts{0, static_cast<long>(wait * 1e9)}; nanosleep(&ts, nullptr); }
    }
    ctx.stats.Report(Name("gtk_offscreen").c_str());
    return 0;
  }

  gtk_init(&argc, &argv);
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_resizable(GTK_WINDOW(window), FALSE);
  GtkWidget *area = gtk_drawing_area_new();
  gtk_widget_set_size_request(area, W, H);
  gtk_container_add(GTK_CONTAINER(window), area);
  g_signal_connect(area, "draw", G_CALLBACK(OnDraw), &ctx);
  g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), nullptr);
  gtk_widget_show_all(window);
  ctx.area = area;
  ctx.start = Now();
  g_timeout_add(16, OnTimer, &ctx);
  gtk_main();
  std::setlocale(LC_ALL, "C");  // gtk_init() switched to the user's locale: "59,9" instead of "59.9"
  ctx.stats.Report(Name("gtk_window").c_str());
  return 0;
}
