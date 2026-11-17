#include "../Renderables.h"

#include "Game/Materials.h"

#include "LTE/Math.h"
#include "LTE/Model.h"
#include "LTE/Plane.h"
#include "LTE/Vector.h"
#include "LTE/SDFs.h"
#include "LTE/SDFMesh.h"

const size_t kUniqueModels = 3;
namespace {
  Renderable Generate(Renderable_Ice_Args const& args) {
    static Renderable models[kUniqueModels];
    if (!models[0]) {
      for (size_t i = 0; i < kUniqueModels; ++i) {
        SDF d = SDF_Radial(SDF_FractalWorley(Rand(1, 1000), 4, 2.0f), 0.5f, 1.5f);
        models[i] = (Renderable)Model_Create()
          ->Add(SDFMesh_Create(d), Material_Ice());
      }
    }
    return models[args.seed % kUniqueModels];
  }
}

DefineFunction(Renderable_Ice) {
  return Generate(args);
}

namespace {
  /* A random direction, from the engine's own dice (as the shapes above). */
  V3 RandDirection() {
    for (;;) {
      V3 v(Rand(-1, 1), Rand(-1, 1), Rand(-1, 1));
      float l = Length(v);
      if (l > 0.1f && l <= 1.0f)
        return v / l;
    }
  }

  Renderable GenerateDeep(Renderable_IceDeep_Args const& args) {
    static Renderable models[kUniqueModels];
    if (!models[0]) {
      for (size_t i = 0; i < kUniqueModels; ++i) {
        SDF d = SDF_Radial(SDF_FractalWorley(Rand(1, 1000), 4, 2.0f), 0.5f, 1.5f);
        models[i] = (Renderable)Model_Create()
          ->Add(SDFMesh_Create(d), Material_IceDeep());
      }
    }
    return models[args.seed % kUniqueModels];
  }

  /* One crystal: a long many-sided prism to a point at each end, along
     'axis', so long and so thick, 'off' from the middle. */
  SDF Crystal(V3 const& axis, float length, float thickness, V3 const& off) {
    Vector<Plane> planes;
    V3 side = Normalize(Cross(axis, Abs(axis.x) < 0.9f ? V3(1, 0, 0) : V3(0, 1, 0)));
    V3 other = Cross(axis, side);
    int sides = 6;
    for (int k = 0; k < sides; ++k) {
      float a = kTau * ((float)k + Rand(-0.15f, 0.15f)) / (float)sides;
      V3 n = Normalize(side * Cos(a) + other * Sin(a));
      planes.push(Plane(off + n * thickness * Rand(0.8f, 1.2f), n));
    }
    /* (the points: faces leaning in toward each end) */
    for (int end = -1; end <= 1; end += 2) {
      for (int k = 0; k < 3; ++k) {
        float a = kTau * ((float)k + 0.5f) / 3.0f + Rand(-0.3f, 0.3f);
        V3 n = Normalize(axis * (float)end * 0.45f + side * Cos(a) + other * Sin(a));
        planes.push(Plane(off + axis * (float)end * length, n));
      }
    }
    return SDF_Polyhedron(planes, 0);
  }

  /* Sharp: a cluster of long pointed crystals growing out of one side of
     a shared root, cut to a sphere so that the mesh has a bound. */
  Renderable GenerateShard(Renderable_IceShard_Args const& args) {
    static Renderable models[kUniqueModels];
    if (!models[0]) {
      for (size_t i = 0; i < kUniqueModels; ++i) {
        V3 up = RandDirection();
        V3 root = up * -0.6f;
        SDF d = Crystal(up, Rand(1.2f, 1.5f), Rand(0.2f, 0.26f), root + up * 0.7f);
        int more = 6 + 2 * (int)i;
        for (int c = 0; c < more; ++c) {
          /* (each leaning out from the first, none pointing back in) */
          V3 axis = Normalize(up * 1.2f + RandDirection());
          float length = Rand(0.5f, 1.1f);
          d = SDF_Union(d, Crystal(axis, length, Rand(0.1f, 0.2f), root + axis * length * 0.8f), -1);
        }
        d = d->Intersect(SDF_Sphere(V3(0), 2.0f));
        models[i] = (Renderable)Model_Create()
          ->Add(SDFMesh_Create(d), Material_IcePale());
      }
    }
    return models[args.seed % kUniqueModels];
  }
}

DefineFunction(Renderable_IceDeep) {
  return GenerateDeep(args);
}

DefineFunction(Renderable_IceShard) {
  return GenerateShard(args);
}
