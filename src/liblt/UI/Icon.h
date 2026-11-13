#ifndef UI_Icon_h__
#define UI_Icon_h__

#include "Common.h"
#include "Glyph.h"
#include "LTE/AutoClass.h"
#include "LTE/DeclareFunction.h"
#include "LTE/Vector.h"
#include "LTE/V3.h"

#include <vector>

/* A glyph of an icon that stands at a place in space, and not at a place
 * on the icon: a chart of many places, looked at from any side, is then
 * turned by saying how it is looked at (IconT::View) and not by making
 * every glyph of it again. */
struct IconAnchor {
  V3 a;         // where it is: a box; or one end of a line
  V3 b;         // the other end of a line
  V2 size;      // a box: its size, before View's 'boxScale'
  V2 lo;        // where View last put it on the icon: the corners
  V2 hi;        //   of the room it takes
  uint glyph;   // which of the icon's glyphs it is
  bool line;
};

AutoClassDerived(IconT, RefCounted,
  Vector<Glyph>, glyphs)

  std::vector<IconAnchor> anchors;

  IconT() {}

  /* A line between two places in space, and a box at one. They are
   * nowhere until the icon is looked at (View). */
  LT_API void AddLine3(V3 const& a, V3 const& b);
  LT_API void AddBox3(V3 const& position, V2 const& size);

  /* Look at the places in space so: a place p is put on the icon at
   * (Dot(right, p), Dot(down, p)) * scale + offset, and a box there is
   * 'boxScale' times its size. */
  LT_API void View(
    V3 const& right,
    V3 const& down,
    V2 const& offset,
    float scale,
    float boxScale);

  /* Draw, as Draw does, but of the glyphs at places in space only those
   * that come within the rectangle from 'lo' to 'hi' of the screen. */
  LT_API void DrawWithin(
    GlyphState const& state,
    V2 const& lo,
    V2 const& hi) const;

  Icon Add(Glyph const& glyph) {
    glyphs.push(glyph);
    return this;
  }

  Icon Add(Icon const& icon, V2 const& offset, V2 const& scale) {
    for (size_t i = 0; i < icon->glyphs.size(); ++i)
      glyphs.push(icon->glyphs[i]->Clone()->Transform(offset, scale));
    return this;
  }

  void Draw(GlyphState const& state) const {
    for (size_t i = 0; i < glyphs.size(); ++i)
      glyphs[i]->Draw(state);
  }

  void Transform(V2 const& offset, V2 const& scale) {
    for (size_t i = 0; i < glyphs.size(); ++i)
      glyphs[i]->Transform(offset, scale);
  }
};

DeclareFunctionNoParams(Icon_Create, Icon)

#endif
