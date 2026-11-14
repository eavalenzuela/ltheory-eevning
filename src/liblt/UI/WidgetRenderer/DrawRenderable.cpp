#include "UI/WidgetRenderer.h"

#include "LTE/Color.h"
#include "LTE/Data.h"
#include "LTE/DrawState.h"
#include "LTE/Geometry.h"
#include "LTE/Math.h"
#include "LTE/Renderable.h"
#include "LTE/Renderer.h"
#include "LTE/RenderStyle.h"
#include "LTE/ShaderInstance.h"
#include "LTE/Transform.h"
#include "LTE/View.h"
#include "LTE/Viewport.h"
#include "LTE/GL.h"
#include "LTE/RenderPass.h"
#include "LTE/Shader.h"
#include "LTE/Texture2D.h"
#include "LTE/Vector.h"

namespace {

  struct HoloStyle : public RenderStyleT {
    ShaderInstance currentShader;
    ShaderInstance holoShader;

    HoloStyle() :
      holoShader(ShaderInstance_Create("npm.jsl", "hologram.jsl"))
      {}

    Shader const& GetShader () const {
      return holoShader->GetShader();
    }

    void OnBegin() {
      Renderer_PushBlendMode(BlendMode::Additive);
      Renderer_PushZBuffer(true);
      Renderer_PushZWritable(true);
      (*holoShader)("seed", Rand());
    }

    void OnEnd() {
      Renderer_PopBlendMode();
      Renderer_PopZBuffer();
      Renderer_PopZWritable();
    }

    void Render(Geometry const& geometry) {
      currentShader->Begin();
      geometry->Draw();
      currentShader->End();
    }

    void SetShader(ShaderInstanceT* shader) {
      bool hasBlending = shader->HasBlending();
      if (hasBlending)
        currentShader = shader;
      else
        currentShader = holoShader;

      currentShader->GetShader()->SetInt("prepass", 0);
      DrawState_Inject(currentShader->GetShader());
    }

    void SetTransform(Transform const& transform) {
      Renderer_SetWorldTransform(transform);
    }

    bool WillRender() const {
      return true;
    }
  };

  Reference<HoloStyle> holoStyle;

  void Initialize() {
    static bool init = false;
    if (!init) {
      init = true;
      holoStyle = new HoloStyle;
    }
  }
}

DefineFunction(WidgetRenderer_DrawRenderable) {
  Initialize();
  WidgetRenderer_Flush();

  Viewport const& currentVp = Viewport_Get();
  Viewport vp = Viewport_Create(args.pos, args.size, 1, currentVp->windowSpace);
  Viewport_Push(vp);
  DrawState state;
  state.Push();

#if 0
  float angle = Radians(60.0f);
  float h = 15.0f;
  float d = 0.5f * h / tan(0.5f * angle);
#endif
  View view(
    Transform_LookUp(args.camPos, args.camLook, args.camUp),
    args.camFov,
    args.size.x / args.size.y,
    0.05f,
    1.0e6f);

  Renderer_PushScissorOff();
  Renderer_SetViewTransform(view.transform);
  Renderer_SetProjMatrix(view.proj);

  Shader const& shader = holoStyle->GetShader();
  (*shader)
    ("baseAlpha", args.alpha)
    ("baseColor", V3(args.color))
    ("time", args.time);

  RenderStyle_Push(holoStyle);

  holoStyle->OnBegin();
  holoStyle->SetTransform(args.transform);
  args.renderable->Render(&state);
  holoStyle->OnEnd();

  RenderStyle_Pop();

  state.Pop();
  Viewport_Pop();
  Renderer_PopScissor();
} FunctionAlias(WidgetRenderer_DrawRenderable, DrawRenderable);

/* Render passes into a picture, and show it at a place in the
   interface: what Widget_Rendered does for a whole widget
   (UI/Widget/Rendered.cpp), for whatever is drawing the interface now.
   One set of buffers is kept, of the size last asked for: it is for a
   window of one size (the ship on the fitting screen). */

namespace {
  const uint kPassesDSFactor = 4;

  struct Target {
    Shader presentShader;
    Shader roundShader;
    GL_Texture depthBuffer;
    Texture2D buffers[3];
    Texture2D smallBuffers[2];
    uint width;
    uint height;

    Target() : depthBuffer(GL_NullTexture), width(0), height(0) {}

    Texture2D CreateBuffer(uint w, uint h) {
      Texture2D self = Texture_Create(w, h, GL_TextureFormat::RGBA16F);
      self->SetMagFilter(GL_TextureFilter::Linear);
      self->SetMinFilter(GL_TextureFilterMip::Linear);
      self->SetWrapMode(GL_TextureWrapMode::ClampToEdge);
      return self;
    }

    void Fit(uint w, uint h) {
      if (!presentShader) {
        presentShader = Shader_Create("widgetTexture.jsl", "ui/texture.jsl");
        roundShader = Shader_Create("widgetTexture.jsl", "ui/texture_round.jsl");
      }
      if (buffers[0] && w == width && h == height)
        return;
      if (depthBuffer != GL_NullTexture)
        GL_DeleteTexture(depthBuffer);
      width = w;
      height = h;
      for (size_t i = 0; i < 3; ++i)
        buffers[i] = CreateBuffer(width, height);
      for (size_t i = 0; i < 2; ++i)
        smallBuffers[i] = CreateBuffer(Max(1u, width / kPassesDSFactor), Max(1u, height / kPassesDSFactor));
      depthBuffer = GL_GenTexture();
      GL_BindTexture(GL_TextureTargetBindable::T2D, depthBuffer);
      GL_TexImage2D(
        GL_TextureTarget::T2D, 0,
        GL_TextureFormat::DepthComponent32F,
        width, height,
        GL_PixelFormat::DepthComponent,
        GL_DataFormat::Float, nullptr);
    }
  };

  Target& GetTarget() {
    static Target target;
    return target;
  }
}

DefineFunction(WidgetRenderer_DrawPasses) {
  uint w = (uint)args.size.x;
  uint h = (uint)args.size.y;
  if (w < 4 || h < 4)
    return;
  WidgetRenderer_Flush();

  Target& target = GetTarget();
  target.Fit(w, h);

  Viewport vp = Viewport_Create(0, V2((float)w, (float)h), 1, true);
  Viewport_Push(vp);
  DrawState state;
  state.Push();

  state.color[0] = target.buffers[0];
  state.color[1] = target.buffers[1];
  state.color[2] = target.buffers[2];
  state.smallColor[0] = target.smallBuffers[0];
  state.smallColor[1] = target.smallBuffers[1];
  state.primary = state.color[0];
  state.secondary = state.color[2];
  state.tertiary = state.color[1];

  Renderer_PushAllBuffers();
  Renderer_PushCullMode(CullMode::Backface);
  Renderer_PushDepthBuffer(target.depthBuffer);
  Renderer_PushScissorOff();
  Renderer_PushBlendMode(BlendMode::Disabled);
  Renderer_PushZBuffer(true);

  for (size_t i = 0; i < args.passes.size(); ++i)
    args.passes[i]->Render(&state);

  Renderer_PopZBuffer();
  Renderer_PopBlendMode();
  Renderer_PopScissor();
  Renderer_PopDepthBuffer();
  Renderer_PopCullMode();
  Renderer_PopAllBuffers();

  Texture2D shown = state.primary;
  state.Pop();
  Viewport_Pop();

  {
    RendererState s(BlendMode::Alpha, CullMode::Disabled, false, false);
    Shader const& present = args.round ? target.roundShader : target.presentShader;
    DrawState_Link(present);
    Renderer_SetShader((*present)
      ("texture", shown)
      ("alpha", args.alpha));
    Renderer_DrawQuad(
      args.pos,
      args.pos + args.size,
      V2(0, 1),
      V2(1, 0));
    Renderer_Flush();
  }
} FunctionAlias(WidgetRenderer_DrawPasses, DrawPasses);
