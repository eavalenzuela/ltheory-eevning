#include "LTE/Function.h"

#include "UI/Icon.h"

TypeAlias(Reference<GlyphT>, Glyph);
TypeAlias(Reference<IconT>, Icon);

VoidFreeFunction(Icon_AddGlyph,
  "Add 'glyph' to 'icon'",
  Icon, icon,
  Glyph, glyph)
{
  icon->Add(glyph);
} FunctionAlias(Icon_AddGlyph, +=);

VoidFreeFunction(Icon_AddIcon,
  "Add a copy of 'source' to 'icon' with translation 'offset' and scale 'scale'",
  Icon, icon,
  Icon, source,
  V2, offset,
  V2, scale)
{
  icon->Add(source, offset, scale);
} FunctionAlias(Icon_AddIcon, +=);

VoidFreeFunction(Icon_Draw,
  "Draw 'icon' to the screen at 'center' with 'scale,' 'color,' and 'alpha'",
  Icon, icon,
  V2, center,
  V2, scale,
  Color, color,
  float, alpha)
{
  icon->Draw(GlyphState(center, scale, color, alpha));
} FunctionAlias(Icon_Draw, Draw);

VoidFreeFunction(Icon_AddLine3,
  "Add to 'icon' a line between the places 'a' and 'b' in space: where it is on the icon is as the icon is looked at (Icon_View)",
  Icon, icon,
  V3, a,
  V3, b)
{
  icon->AddLine3(a, b);
} FunctionAlias(Icon_AddLine3, AddLine3);

VoidFreeFunction(Icon_AddBox3,
  "Add to 'icon' a box of 'size' at the place 'position' in space: where it is on the icon is as the icon is looked at (Icon_View)",
  Icon, icon,
  V3, position,
  V2, size)
{
  icon->AddBox3(position, size);
} FunctionAlias(Icon_AddBox3, AddBox3);

VoidFreeFunction(Icon_View,
  "Look at the places in space of 'icon' so: a place p goes on the icon at (p . 'right', p . 'down') * 'scale' + 'offset', and a box there is 'boxScale' times its size",
  Icon, icon,
  V3, right,
  V3, down,
  V2, offset,
  float, scale,
  float, boxScale)
{
  icon->View(right, down, offset, scale, boxScale);
} FunctionAlias(Icon_View, View);

VoidFreeFunction(Icon_DrawWithin,
  "Draw 'icon' as Icon_Draw does, but of its glyphs at places in space only those that come within the rectangle of the screen from 'lo' to 'hi'",
  Icon, icon,
  V2, center,
  V2, scale,
  Color, color,
  float, alpha,
  V2, lo,
  V2, hi)
{
  icon->DrawWithin(GlyphState(center, scale, color, alpha), lo, hi);
} FunctionAlias(Icon_DrawWithin, DrawWithin);

VoidFreeFunction(Icon_Transform,
  "Scale 'icon' by 'scale,' then move by 'offset'",
  Icon, icon,
  V2, offset,
  V2, scale)
{
  icon->Transform(offset, scale);
} FunctionAlias(Icon_Transform, Transform);
