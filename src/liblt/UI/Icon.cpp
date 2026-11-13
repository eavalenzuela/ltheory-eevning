#include "Icon.h"
#include "Glyphs.h"

void IconT::AddLine3(V3 const& a, V3 const& b) {
  IconAnchor anchor;
  anchor.a = a;
  anchor.b = b;
  anchor.size = V2(0);
  anchor.lo = V2(0);
  anchor.hi = V2(0);
  anchor.glyph = (uint)glyphs.size();
  anchor.line = true;
  anchors.push_back(anchor);
  glyphs.push(Glyph_Line(V2(0), V2(0), 1, 1));
}

void IconT::AddBox3(V3 const& position, V2 const& size) {
  IconAnchor anchor;
  anchor.a = position;
  anchor.b = position;
  anchor.size = size;
  anchor.lo = V2(0);
  anchor.hi = V2(0);
  anchor.glyph = (uint)glyphs.size();
  anchor.line = false;
  anchors.push_back(anchor);
  glyphs.push(Glyph_Box(V2(0), size, 1, 1));
}

void IconT::View(
  V3 const& right,
  V3 const& down,
  V2 const& offset,
  float scale,
  float boxScale)
{
  for (size_t i = 0; i < anchors.size(); ++i) {
    IconAnchor& anchor = anchors[i];
    V2 a = V2(Dot(right, anchor.a), Dot(down, anchor.a)) * scale + offset;
    if (anchor.line) {
      V2 b = V2(Dot(right, anchor.b), Dot(down, anchor.b)) * scale + offset;
      anchor.lo = Min(a, b);
      anchor.hi = Max(a, b);
      glyphs[anchor.glyph]->Place(a, b);
    } else {
      V2 size = anchor.size * boxScale;
      anchor.lo = a - size;
      anchor.hi = a + size;
      glyphs[anchor.glyph]->Place(a, size);
    }
  }
}

void IconT::DrawWithin(
  GlyphState const& state,
  V2 const& lo,
  V2 const& hi) const
{
  /* The glyphs that stand at places in space are in the order they were
   * added, as all the glyphs are: the two lists are gone through
   * together. */
  size_t next = 0;
  for (size_t i = 0; i < glyphs.size(); ++i) {
    if (next < anchors.size() && anchors[next].glyph == i) {
      IconAnchor const& anchor = anchors[next++];
      V2 l = anchor.lo * state.scale + state.center;
      V2 h = anchor.hi * state.scale + state.center;
      if (h.x < lo.x || l.x > hi.x || h.y < lo.y || l.y > hi.y)
        continue;
    }
    glyphs[i]->Draw(state);
  }
}

DefineFunction(Icon_Create) {
  return new IconT;
} FunctionAlias(Icon_Create, Icon);
