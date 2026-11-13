#include "PlateMesh.h"

#include "Matrix.h"
#include "Meshes.h"
#include "StackFrame.h"
#include "Warp.h"

#include "Array.h"
#include "Location.h"
#include "OS.h"
#include "Renderer.h"
#include "Shader.h"
#include "Texture2D.h"
#include "GL.h"
#include "Math.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>

#ifdef LIBLT_WINDOWS
  #include <process.h>
  #define LT_PROCESS_ID _getpid
#else
  #include <unistd.h>
  #define LT_PROCESS_ID getpid
#endif

/* Max vertex-surfel pairs evaluated per occlusion draw call. Roughly 30ms on
   a mid-range dGPU, leaving lots of headroom under driver GPU timeouts. */
const double kOcclusionJobWork = 2e9;

namespace {
  AutoClass(Plate,
    V3, center,
    V3, scale,
    V3, rotation,
    float, bevel,
    float, tag)
    Plate() {}
  };

  AutoClassDerived(PlateMeshImpl, PlateMeshT,
    Vector<Plate>, plates,
    Vector<PlateMesh>, children,
    Vector<Matrix>, childTransforms,
    Vector<Warp>, warps,
    uint, quality)
    DERIVED_TYPE_EX(PlateMeshImpl)

    PlateMeshImpl() {}

    void Add(
      V3 const& center,
      V3 const& scale,
      V3 const& rotation,
      float bevel)
    {
      plates.push(Plate(center, scale, rotation, bevel, -1.0f));
    }

    void AddTagged(
      V3 const& center,
      V3 const& scale,
      V3 const& rotation,
      float bevel,
      float tag)
    {
      plates.push(Plate(center, scale, rotation, bevel, tag));
    }

    void Add(Warp const& warp) {
      warps.push(warp);
    }

    void Add(
      PlateMesh const& pm,
      V3 const& offset = 0,
      V3 const& scale = 1)
    {
      children.push(pm);
      childTransforms.push(
        Matrix::Translation(offset) *
        Matrix::Scale(scale));
    }

    Mesh GetMesh() const {
      Mesh self = Mesh_Create();

      for (size_t i = 0; i < plates.size(); ++i) {
        Plate const& plate = plates[i];
        size_t first = self->vertices.size();
        self->AddMesh(
          Mesh_BoxRounded(quality, plate.bevel),
          Matrix::Translation(plate.center) *
          Matrix::RotationYPR(plate.rotation) *
          Matrix::Scale(plate.scale));
        if (plate.tag >= 0)
          for (size_t j = first; j < self->vertices.size(); ++j)
            self->vertices[j].v = plate.tag;
      }

      for (size_t i = 0; i < children.size(); ++i)
        self->AddMesh(children[i]->GetMesh(), childTransforms[i]);

      for (size_t i = 0; i < self->vertices.size(); ++i) {
        V3& p = self->vertices[i].p;
        V3 delta = 0;
        for (size_t j = 0; j < warps.size(); ++j)
          delta += warps[j]->GetDelta(p);
        p += delta;
      }

      self->ComputeNormals();
      return self;
    }

    void ReflectX() {
      for (size_t i = 0; i < plates.size(); ++i) {
        plates[i].center.x *= -1;
        plates[i].rotation.z *= -1;
      }
    }

    void ReflectY() {
      for (size_t i = 0; i < plates.size(); ++i) {
        plates[i].center.y *= -1;
        plates[i].rotation.y *= -1;
      }
    }

    void ReflectZ() {
      for (size_t i = 0; i < plates.size(); ++i) {
        plates[i].center.z *= -1;
        plates[i].rotation.x *= -1;
      }
    }
  };
}

DefineFunction(PlateMesh_Create) {
  Reference<PlateMeshImpl> self = new PlateMeshImpl;
  self->quality = args.quality;
  return self;
}

/* A mesh's occlusion follows from where its vertices are, which way they
   face and what triangles they make, and from nothing else; and working
   it out takes seconds for a hull. So it is kept on disk, in the cache
   directory, under a hash of those, and the next time the same mesh is
   made it is read back. A mesh that has changed at all has another hash,
   so nothing kept is ever stale. LT_OCCLUSION_CACHE=0 in the environment
   turns the keeping off (nothing is read, and nothing written). */
namespace {
  const char kOcclusionMagic[4] = { 'L', 'T', 'A', 'O' };
  const uint32_t kOcclusionVersion = 1;

  struct OcclusionHeader {
    char magic[4];
    uint32_t version;
    uint32_t vertices;
    uint32_t indices;
  };

  bool OcclusionCacheOn() {
    static int on = -1;
    if (on < 0) {
      char const* said = getenv("LT_OCCLUSION_CACHE");
      on = (said && said[0] == '0') ? 0 : 1;
    }
    return on == 1;
  }

  /* (FNV-1a, 64 bits. Not 'u', which is where the occlusion is written,
     nor 'v', which it does not depend on.) */
  String OcclusionCachePath(Mesh const& m) {
    uint64_t hash = 14695981039346656037ULL;
    auto feed = [&hash](void const* data, size_t bytes) {
      unsigned char const* d = (unsigned char const*)data;
      for (size_t i = 0; i < bytes; ++i) {
        hash ^= d[i];
        hash *= 1099511628211ULL;
      }
    };
    for (size_t i = 0; i < m->vertices.size(); ++i) {
      feed(&m->vertices[i].p, sizeof(V3));
      feed(&m->vertices[i].n, sizeof(V3));
    }
    if (m->indices.size())
      feed(m->indices.data(), m->indices.size() * sizeof(m->indices[0]));
    char name[64];
    snprintf(name, sizeof(name), "occlusion_%016llx.bin", (unsigned long long)hash);
    return Location_Cache(name)->ToString();
  }

  bool OcclusionCacheRead(String const& path, Mesh const& m) {
    std::ifstream stream(path.c_str(), std::ios::binary);
    if (!stream)
      return false;
    OcclusionHeader header;
    if (!stream.read((char*)&header, sizeof(header))
        || memcmp(header.magic, kOcclusionMagic, 4) != 0
        || header.version != kOcclusionVersion
        || header.vertices != (uint32_t)m->vertices.size()
        || header.indices != (uint32_t)m->indices.size())
      return false;
    Array<float> kept(m->vertices.size());
    if (m->vertices.size()
        && !stream.read((char*)kept.data(), m->vertices.size() * sizeof(float)))
      return false;
    for (size_t i = 0; i < m->vertices.size(); ++i)
      m->vertices[i].u = kept[i];
    return true;
  }

  /* (Written beside where it goes and moved there whole, so that nobody
     reads half of one.) */
  void OcclusionCacheWrite(String const& path, Mesh const& m) {
    char suffix[32];
    snprintf(suffix, sizeof(suffix), ".%u.tmp", (unsigned)LT_PROCESS_ID());
    String partial = path + suffix;
    std::ofstream stream(partial.c_str(), std::ios::binary);
    if (!stream) {
      OS_CreatePath(partial.c_str());
      stream.clear();
      stream.open(partial.c_str(), std::ios::binary);
      if (!stream)
        return;
    }
    OcclusionHeader header;
    memcpy(header.magic, kOcclusionMagic, 4);
    header.version = kOcclusionVersion;
    header.vertices = (uint32_t)m->vertices.size();
    header.indices = (uint32_t)m->indices.size();
    stream.write((char const*)&header, sizeof(header));
    for (size_t i = 0; i < m->vertices.size(); ++i)
      stream.write((char const*)&m->vertices[i].u, sizeof(float));
    stream.close();
    if (!stream.good() || rename(partial.c_str(), path.c_str()) != 0)
      remove(partial.c_str());
  }
}

DefineFunction(Mesh_ComputeOcclusion) {
  AUTO_FRAME;
  Mesh const& m = args.mesh;

  String kept;
  if (OcclusionCacheOn()) {
    kept = OcclusionCachePath(m);
    if (OcclusionCacheRead(kept, m)) {
      m->version++;
      return;
    }
  }

  Vector<V4> points;
  Vector<V4> normals;

  /* Fill surfel buffers. */
  for (size_t i = 0; i < m->indices.size(); i += 3) {
    Vertex const& v0 = m->vertices[m->indices[i + 0]];
    Vertex const& v1 = m->vertices[m->indices[i + 1]];
    Vertex const& v2 = m->vertices[m->indices[i + 2]];

    V3 normal = Cross(v2.p - v0.p, v1.p - v0.p);
    float area = 0.5f * Length(normal) / kPi;
    points.push(V4((v0.p + v1.p + v2.p) / 3.0f, area));
    normals.push(V4(Normalize(normal), 0.0f));
  }

  int sDim = (int)Ceil(Sqrt((float)points.size()));

  while ((int)points.size() < sDim * sDim) {
    points.push(V4(0));
    normals.push(V4(0));
  }

  Texture2D sPointBuffer =
    Texture_Create(sDim, sDim, GL_TextureFormat::RGBA32F, points.data());
  Texture2D sNormalBuffer =
    Texture_Create(sDim, sDim, GL_TextureFormat::RGBA32F, normals.data());

  /* Fill vertex buffers. */
  points.clear();
  normals.clear();
  for (size_t i = 0; i < m->vertices.size(); ++i) {
    points.push(V4(m->vertices[i].p, 0));
    normals.push(V4(m->vertices[i].n, 0));
  }
  
  int vDim = (int)Ceil(Sqrt((float)points.size()));

  while ((int)points.size() < vDim * vDim) {
    points.push(V4(0));
    normals.push(V4(0));
  }

  Texture2D vPointBuffer =
    Texture_Create(vDim, vDim, GL_TextureFormat::RGBA32F, points.data());
  Texture2D vNormalBuffer = 
    Texture_Create(vDim, vDim, GL_TextureFormat::RGBA32F, normals.data());

  /* GPU computation. */
  Texture2D occlusionBuffer =
    Texture_Create(vDim, vDim, GL_TextureFormat::R32F);
  static Shader shader = Shader_Create("identity.jsl", "compute/occlusion.jsl");

  occlusionBuffer->Bind(0);
  (*shader)
    ("sDim", sDim)
    ("sPointBuffer", sPointBuffer)
    ("sNormalBuffer", sNormalBuffer)
    ("vPointBuffer", vPointBuffer)
    ("vNormalBuffer", vNormalBuffer);
  Renderer_SetShader(*shader);

  /* Every texel loops over every surfel, so a large ship mesh is ~1e11 pairs
     and takes seconds as a single draw -- long enough to trip the driver's
     GPU timeout (and a GPU reset) on slower hardware. Draw it in bands of rows
     sized to a fixed work budget, finishing each before submitting the next. */
  uint rowsPerJob =
    Max((uint)(kOcclusionJobWork / ((double)vDim * sDim * sDim)), 1U);

  Renderer_PushBlendMode(BlendMode::Disabled);
  Renderer_PushZBuffer(false);
  for (uint y = 0; y < (uint)vDim; y += rowsPerJob) {
    Renderer_DrawFSQPart(0, y, vDim, Min(rowsPerJob, (uint)vDim - y));
    GL_Finish();
  }
  Renderer_PopZBuffer();
  Renderer_PopBlendMode();
  occlusionBuffer->Unbind();

  /* Write result to mesh. */
  Array<float> result(vDim * vDim);
  occlusionBuffer->GetData(result.data());
  for (size_t i = 0; i < m->vertices.size(); ++i)
    m->vertices[i].u = result[i];
  m->version++;

  if (OcclusionCacheOn())
    OcclusionCacheWrite(kept, m);
}
