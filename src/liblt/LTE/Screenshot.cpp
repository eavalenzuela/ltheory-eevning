#include "Screenshot.h"

#include "Array.h"
#include "Function.h"
#include "GL.h"
#include "Mouse.h"
#include "OS.h"
#include "Vector.h"
#include "Window.h"

#include "SFML/Graphics.hpp"

#include <cstdio>

namespace {
  Vector<String> gRequests;
  String gDirectory;
  uint gDownscale = 1;

  String GetDirectory() {
    if (gDirectory.empty())
      gDirectory = OS_GetUserDataPath() + "screenshot/";
    return gDirectory;
  }

  String NextFreeName(String const& dir) {
    for (uint i = 0;; ++i)
      if (!OS_FileExists(dir + ToString(i) + ".png"))
        return ToString(i);
  }

  void Save(String const& path) {
    V2U size = Window_Get()->GetSize();
    Array<uchar> pixels(size.x * size.y * 4);

    GL_BindFramebuffer(GL_FramebufferTarget::Read, GL_NullFramebuffer);
    glReadBuffer(GL_BACK);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    GL_ReadPixels(
      0, 0, size.x, size.y,
      GL_PixelFormat::RGBA,
      GL_DataFormat::UnsignedByte,
      pixels.data());

    /* Flip vertically (GL's origin is bottom-left), force opaque alpha, and
       box-filter down by the downscale factor. */
    uint f = Max(1u, gDownscale);
    uint w = size.x / f;
    uint h = size.y / f;
    Array<uchar> out(w * h * 4);
    for (uint y = 0; y < h; ++y)
    for (uint x = 0; x < w; ++x) {
      uint sum[3] = { 0, 0, 0 };
      for (uint dy = 0; dy < f; ++dy)
      for (uint dx = 0; dx < f; ++dx) {
        uint sy = size.y - 1 - (y * f + dy);
        uchar const* p = &pixels[(sy * size.x + x * f + dx) * 4];
        for (uint c = 0; c < 3; ++c)
          sum[c] += p[c];
      }
      uchar* q = &out[(y * w + x) * 4];
      for (uint c = 0; c < 3; ++c)
        q[c] = (uchar)(sum[c] / (f * f));
      q[3] = 0xff;
    }

    /* When input is synthetic the OS cursor is not where the app thinks it
       is, so mark the app's cursor position with a magenta crosshair. */
    if (Mouse_IsSynthetic()) {
      V2 m = Mouse_GetPos() / (float)f;
      int cx = (int)m.x, cy = (int)m.y;
      for (int d = -8; d <= 8; ++d) {
        if (d > -3 && d < 3)
          continue;
        int pts[2][2] = { { cx + d, cy }, { cx, cy + d } };
        for (int k = 0; k < 2; ++k) {
          int x = pts[k][0], y = pts[k][1];
          if (x < 0 || y < 0 || x >= (int)w || y >= (int)h)
            continue;
          uchar* q = &out[(y * w + x) * 4];
          q[0] = 0xff; q[1] = 0x00; q[2] = 0xff;
        }
      }
    }

    sf::Image image;
    image.create(w, h, out.data());
    if (image.saveToFile(path))
      printf("SCREENSHOT %s\n", path.c_str());
    else
      printf("ERROR: Failed to save screenshot %s\n", path.c_str());
    fflush(stdout);
  }
}

void Screenshot_Request(String const& name) {
  gRequests.push(name);
}

void Screenshot_Flush() {
  if (gRequests.empty())
    return;
  String dir = GetDirectory();
  OS_CreatePath(dir);
  for (size_t i = 0; i < gRequests.size(); ++i) {
    String name = gRequests[i].empty() ? NextFreeName(dir) : gRequests[i];
    Save(dir + name + ".png");
  }
  gRequests.clear();
}

void Screenshot_SetDirectory(String const& directory) {
  gDirectory = directory;
  if (!gDirectory.empty() && gDirectory[gDirectory.size() - 1] != '/')
    gDirectory += "/";
}

void Screenshot_SetDownscale(uint factor) {
  gDownscale = factor;
}

VoidFreeFunction(Screenshot,
  "Save a screenshot named 'name' once the current frame is drawn",
  String, name)
{
  Screenshot_Request(name);
}
