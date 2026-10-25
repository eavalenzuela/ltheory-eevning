#ifndef UI_Interface_h__
#define UI_Interface_h__

#include "Common.h"
#include "LTE/DeclareFunction.h"
#include "LTE/RenderPass.h"
#include "LTE/String.h"
#include "LTE/V2.h"
#include "LTE/Vector.h"

struct InterfaceT : public RefCounted {
  virtual ~InterfaceT() {}

  virtual void Add(Widget const& widget) = 0;
  virtual void Clear() = 0;
  virtual void Draw() = 0;
  virtual void Update() = 0;
};

/* A named, visible widget in a live interface, for test tooling. */
struct InterfaceWidgetInfo {
  String name;
  V2 pos;
  V2 size;
};

/* Every named widget with a non-empty, visible rect in all live interfaces,
   in draw order (later entries are drawn on top). */
LT_API void Interface_GetNamedWidgets(Vector<InterfaceWidgetInfo>& out);

DeclareFunction(Interface_Create, Interface,
  String, name)

DeclareFunction(RenderPass_Interface, RenderPass,
  Interface, interface)

#endif
