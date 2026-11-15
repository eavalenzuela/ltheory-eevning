#include "RenderPass.h"

#include "Profiler.h"
#include "Renderer.h"
#include "RenderPasses.h"
#include "StackFrame.h"
#include "Vector.h"

#include "Module/Settings.h"

namespace {
  /* The names of the passes that are switched off (RenderPass_SetEnabled). */
  Vector<String>& GetDisabled() {
    static Vector<String> names;
    return names;
  }
}

void RenderPassT::Render(DrawState* state) {
  Vector<String> const& disabled = GetDisabled();
  if (disabled.size()) {
    String name = GetName();
    for (size_t i = 0; i < disabled.size(); ++i)
      if (disabled[i] == name)
        return;
  }

  if (Settings_Bool((String)"Graphics/" + ToString(), true)()) {
    FRAME(GetName()) {
      OnRender(state);
      Profiler_Flush();
    }
  }
}

bool RenderPass_IsEnabled(char const* name) {
  Vector<String> const& disabled = GetDisabled();
  for (size_t i = 0; i < disabled.size(); ++i)
    if (disabled[i] == name)
      return false;
  return true;
}

DefineFunction(RenderPass_SetEnabled) {
  Vector<String>& disabled = GetDisabled();
  for (size_t i = 0; i < disabled.size(); ++i) {
    if (disabled[i] == args.name) {
      if (args.enabled)
        disabled.removeIndex(i);
      return;
    }
  }
  if (!args.enabled)
    disabled.push(args.name);
}
