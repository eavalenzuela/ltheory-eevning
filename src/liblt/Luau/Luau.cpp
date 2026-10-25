/* Luau's headers first: the engine defines an 'error' macro. */
#include "lua.h"
#include "lualib.h"
#include "luacode.h"

#include "Luau.h"

#include "LTE/AutoClass.h"
#include "LTE/Data.h"
#include "LTE/Function.h"
#include "LTE/Pool.h"
#include "LTE/Script.h"
#include "LTE/ScriptFunction.h"
#include "LTE/Map.h"
#include "LTE/Type.h"
#include "LTE/V3.h"
#include "LTE/V4.h"
#include "LTE/Vector.h"

#include "UI/Widget.h"
#include "UI/WidgetComponent.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <fstream>
#include <limits>
#include <list>
#include <map>
#include <unordered_map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

/* How engine values cross into Luau:
   - Scalars (bool, integers, reals, String, V3/V3D) become Luau values.
   - Data (the engine's "any") becomes whatever it holds.
   - Everything else is a box: a userdata holding a copy of the value, with
     a shared metatable that resolves fields through reflection and methods
     through the function registry. A null reference becomes nil. */

namespace {
  lua_State* gL = nullptr;
  /* Boxes are tagged userdata: identifying one is a tag compare, and the
     tag carries their metatable and destructor. */
  const int kBoxTag = 1;

  /* A Luau value (a table, a function) carried through the engine as Data,
     e.g. a script-defined widget message passed along with SendUp. It comes
     back out as the same Luau value. */
  AutoClassDerived(LuauValueT, RefCounted,
    int, ref)

    lua_State* state;

    LuauValueT() : ref(0), state(nullptr) {}

    ~LuauValueT() {
      if (ref && state && state == gL)
        lua_unref(state, ref);
    }
  };

  typedef Reference<LuauValueT> LuauValue;

  TypeT* LuauValueType() {
    static TypeT* type = Type_Get<LuauValue>().t;
    return type;
  }

  enum Kind {
    Kind_Box,
    Kind_Bool,
    Kind_Int,
    Kind_Real,
    Kind_String,
    Kind_Vec2F,
    Kind_Vec2D,
    Kind_Vec3F,
    Kind_Vec3D,
    Kind_Data,
    Kind_Void
  };

  struct TypeInfo {
    Kind kind;
    bool isSigned;
    size_t size;
  };

  /* Doubles hold every integer up to 2^53 exactly. */
  const double kMaxExactInt = 9007199254740992.0;

  std::unordered_map<TypeT*, TypeInfo>& GetKinds() {
    static std::unordered_map<TypeT*, TypeInfo> kinds;
    return kinds;
  }

  template <class T>
  void AddKind(Kind kind) {
    TypeInfo info;
    info.kind = kind;
    info.isSigned = std::numeric_limits<T>::is_signed;
    info.size = sizeof(T);
    GetKinds()[Type_Get<T>().t] = info;
  }

  void InitKinds() {
    if (GetKinds().size())
      return;
    AddKind<bool>(Kind_Bool);
    AddKind<char>(Kind_Int);
    AddKind<signed char>(Kind_Int);
    AddKind<unsigned char>(Kind_Int);
    AddKind<signed short>(Kind_Int);
    AddKind<unsigned short>(Kind_Int);
    AddKind<signed int>(Kind_Int);
    AddKind<unsigned int>(Kind_Int);
    AddKind<signed long>(Kind_Int);
    AddKind<unsigned long>(Kind_Int);
    AddKind<signed long long>(Kind_Int);
    AddKind<unsigned long long>(Kind_Int);
    AddKind<float>(Kind_Real);
    AddKind<double>(Kind_Real);
    AddKind<String>(Kind_String);
    AddKind<V2F>(Kind_Vec2F);
    AddKind<V2D>(Kind_Vec2D);
    AddKind<V3F>(Kind_Vec3F);
    AddKind<V3D>(Kind_Vec3D);
    AddKind<Data>(Kind_Data);
    TypeInfo v = { Kind_Void, false, 0 };
    GetKinds()[Type_Get<void>().t] = v;
  }

  TypeInfo GetInfo(TypeT* t) {
    std::unordered_map<TypeT*, TypeInfo>::const_iterator it = GetKinds().find(t);
    if (it != GetKinds().end())
      return it->second;
    TypeInfo box = { Kind_Box, false, 0 };
    return box;
  }

  String TypeName(TypeT* t) {
    return t ? t->GetAliasName() : String("void");
  }

  /* References, pointers and handles record a pointee type. (Not
     IsPseudoPointer: it compares the bare template name, "Reference",
     against full names like "Reference<ObjectT>", so it is never true.) */
  bool IsNullable(TypeT* t) {
    return t->IsPointer() || t->GetPointeeType();
  }

  bool IsNullValue(TypeT* t, void const* p) {
    return IsNullable(t) && *(void* const*)p == nullptr;
  }

  ConversionFn FindConversion(TypeT* src, TypeT* dst) {
    Vector<ConversionType> const& conversions = src->GetConversions();
    for (size_t i = 0; i < conversions.size(); ++i)
      if (conversions[i].other == dst)
        return conversions[i].fn;
    return nullptr;
  }

  /* ------------------------------------------------------------------ */
  /* Integers                                                            */

  double IntToDouble(lua_State* L, TypeT* t, TypeInfo const& info, void const* p) {
    if (info.size == 8 && !info.isSigned) {
      uint64 v = *(uint64 const*)p;
      if ((double)v > kMaxExactInt)
        luaL_error(L, "%s value %llu is too large for a Luau number",
          TypeName(t).c_str(), (unsigned long long)v);
      return (double)v;
    }

    int64 v;
    switch (info.size) {
      case 1: v = info.isSigned ? (int64)*(int8_t const*)p : (int64)*(uint8_t const*)p; break;
      case 2: v = info.isSigned ? (int64)*(int16_t const*)p : (int64)*(uint16_t const*)p; break;
      case 4: v = info.isSigned ? (int64)*(int32_t const*)p : (int64)*(uint32_t const*)p; break;
      default: v = *(int64 const*)p; break;
    }
    if (std::fabs((double)v) > kMaxExactInt)
      luaL_error(L, "%s value %lld is too large for a Luau number",
        TypeName(t).c_str(), (long long)v);
    return (double)v;
  }

  void IntRange(TypeInfo const& info, double& lo, double& hi) {
    if (info.size >= 8) {
      lo = info.isSigned ? -kMaxExactInt : 0;
      hi = kMaxExactInt;
      return;
    }
    double span = std::ldexp(1.0, (int)(8 * info.size));
    lo = info.isSigned ? -span / 2 : 0;
    hi = info.isSigned ? span / 2 - 1 : span - 1;
  }

  /* Why 'v' doesn't fit an integer type, or null if it does. */
  char const* IntProblem(TypeInfo const& info, double v) {
    if (v != std::floor(v) || std::isinf(v) || std::isnan(v))
      return "expected a whole number";
    double lo, hi;
    IntRange(info, lo, hi);
    if (v < lo || v > hi)
      return "out of range";
    return nullptr;
  }

  void WriteInt(TypeInfo const& info, double v, void* p) {
    switch (info.size) {
      case 1: if (info.isSigned) *(int8_t*)p = (int8_t)v; else *(uint8_t*)p = (uint8_t)v; break;
      case 2: if (info.isSigned) *(int16_t*)p = (int16_t)v; else *(uint16_t*)p = (uint16_t)v; break;
      case 4: if (info.isSigned) *(int32_t*)p = (int32_t)v; else *(uint32_t*)p = (uint32_t)v; break;
      default: if (info.isSigned) *(int64*)p = (int64)v; else *(uint64*)p = (uint64)v; break;
    }
  }

  /* ------------------------------------------------------------------ */
  /* Boxes                                                               */

  const size_t kBoxHeader = 16;

  struct Box {
    TypeT* type;
  };

  void* BoxData(Box* box) {
    return (char*)box + kBoxHeader;
  }

  void BoxDestructor(lua_State*, void* ud) {
    Box* box = (Box*)ud;
    if (box->type)
      box->type->Destruct(BoxData(box));
  }

  void PushBox(lua_State* L, TypeT* t, void const* src) {
    if (!t->construct || !t->assign)
      luaL_error(L, "engine type %s cannot be held by a script", TypeName(t).c_str());
    void* ud = lua_newuserdatataggedwithmetatable(L, kBoxHeader + t->size, kBoxTag);
    Box* box = (Box*)ud;
    box->type = nullptr;
    t->Construct(BoxData(box));
    box->type = t;
    if (src)
      t->Assign(src, BoxData(box));
  }

  Box* ToBox(lua_State* L, int idx) {
    return (Box*)lua_touserdatatagged(L, idx, kBoxTag);
  }

  /* ------------------------------------------------------------------ */
  /* Engine -> Luau                                                      */

  /* Push the value at 'p' of type 't'; returns the number of values. */
  int Push(lua_State* L, TypeT* t, void const* p) {
    TypeInfo info = GetInfo(t);
    switch (info.kind) {
      case Kind_Void:
        return 0;
      case Kind_Bool:
        lua_pushboolean(L, *(bool const*)p);
        return 1;
      case Kind_Int:
        lua_pushnumber(L, IntToDouble(L, t, info, p));
        return 1;
      case Kind_Real:
        lua_pushnumber(L, info.size == 4 ? (double)*(float const*)p : *(double const*)p);
        return 1;
      case Kind_String: {
        String const& s = *(String const*)p;
        lua_pushlstring(L, s.data(), s.size());
        return 1;
      }
      case Kind_Vec2F: {
        V2F const& v = *(V2F const*)p;
        lua_pushvector(L, v.x, v.y, 0);
        return 1;
      }
      case Kind_Vec2D: {
        V2D const& v = *(V2D const*)p;
        lua_pushvector(L, (float)v.x, (float)v.y, 0);
        return 1;
      }
      case Kind_Vec3F: {
        V3F const& v = *(V3F const*)p;
        lua_pushvector(L, v.x, v.y, v.z);
        return 1;
      }
      case Kind_Vec3D: {
        V3D const& v = *(V3D const*)p;
        lua_pushvector(L, (float)v.x, (float)v.y, (float)v.z);
        return 1;
      }
      case Kind_Data: {
        Data const& d = *(Data const*)p;
        if (!d.type || !d.data) {
          lua_pushnil(L);
          return 1;
        }
        return Push(L, d.type, d.data) ? 1 : (lua_pushnil(L), 1);
      }
      case Kind_Box:
        break;
    }

    if (t == LuauValueType()) {
      LuauValue const& value = *(LuauValue const*)p;
      if (value && value->state == L)
        lua_getref(L, value->ref);
      else
        lua_pushnil(L);
      return 1;
    }

    if (IsNullValue(t, p))
      lua_pushnil(L);
    else
      PushBox(L, t, p);
    return 1;
  }

  /* ------------------------------------------------------------------ */
  /* Luau -> engine                                                      */

  enum {
    Match_None = -1,
    Match_Exact = 0,
    Match_Convert = 1,
    Match_Any = 2
  };

  /* The engine types a script scalar can be converted from. */
  void ScalarSources(lua_State* L, int idx, std::vector<TypeT*>& sources) {
    switch (lua_type(L, idx)) {
      case LUA_TNUMBER: {
        double v = lua_tonumber(L, idx);
        if (v == std::floor(v) && std::fabs(v) < 2147483648.0)
          sources.push_back(Type_Get<int>().t);
        sources.push_back(Type_Get<float>().t);
        sources.push_back(Type_Get<double>().t);
        break;
      }
      case LUA_TBOOLEAN: sources.push_back(Type_Get<bool>().t); break;
      case LUA_TSTRING: sources.push_back(Type_Get<String>().t); break;
      case LUA_TVECTOR: sources.push_back(Type_Get<V3F>().t); break;
      default: break;
    }
  }

  /* Write the script scalar at 'idx' as engine type 'src' into 'out'. */
  void ReadScalar(lua_State* L, int idx, TypeT* src, void* out) {
    TypeInfo info = GetInfo(src);
    switch (info.kind) {
      case Kind_Bool: *(bool*)out = lua_toboolean(L, idx) != 0; break;
      case Kind_Int: WriteInt(info, lua_tonumber(L, idx), out); break;
      case Kind_Real:
        if (info.size == 4) *(float*)out = (float)lua_tonumber(L, idx);
        else *(double*)out = lua_tonumber(L, idx);
        break;
      case Kind_String: {
        size_t len;
        char const* s = lua_tolstring(L, idx, &len);
        ((String*)out)->assign(s, len);
        break;
      }
      case Kind_Vec3F: {
        float const* v = lua_tovector(L, idx);
        *(V3F*)out = V3F(v[0], v[1], v[2]);
        break;
      }
      default: break;
    }
  }

  /* How well the script value at 'idx' fits engine type 't'. */
  int Match(lua_State* L, int idx, TypeT* t, TypeInfo const& info, char const** why = nullptr) {
    int lt = lua_type(L, idx);
    switch (info.kind) {
      case Kind_Bool:
        return lt == LUA_TBOOLEAN ? Match_Exact : Match_None;
      case Kind_Int: {
        if (lt != LUA_TNUMBER)
          return Match_None;
        char const* problem = IntProblem(info, lua_tonumber(L, idx));
        if (problem && why)
          *why = problem;
        return problem ? Match_None : Match_Exact;
      }
      case Kind_Real:
        return lt == LUA_TNUMBER ? Match_Exact : Match_None;
      case Kind_String:
        return lt == LUA_TSTRING ? Match_Exact : Match_None;
      case Kind_Vec2F:
      case Kind_Vec2D:
        /* A number is a uniform 2D value, as in LTSL ("MinSize 36"). */
        if (lt == LUA_TVECTOR)
          return Match_Exact;
        return lt == LUA_TNUMBER ? Match_Convert : Match_None;
      case Kind_Vec3F:
      case Kind_Vec3D:
        return lt == LUA_TVECTOR ? Match_Exact : Match_None;
      case Kind_Data:
        return Match_Any;
      case Kind_Void:
        return Match_None;
      case Kind_Box:
        break;
    }

    if (lt == LUA_TNIL) {
      if (!IsNullable(t) && why)
        *why = "cannot be nil";
      return IsNullable(t) ? Match_Exact : Match_None;
    }

    Box* box = ToBox(L, idx);
    if (box) {
      if (box->type == t)
        return Match_Exact;
      return FindConversion(box->type, t) ? Match_Convert : Match_None;
    }

    std::vector<TypeT*> sources;
    ScalarSources(L, idx, sources);
    for (size_t i = 0; i < sources.size(); ++i)
      if (FindConversion(sources[i], t))
        return Match_Convert;
    return Match_None;
  }

  int Match(lua_State* L, int idx, TypeT* t, char const** why = nullptr) {
    return Match(L, idx, t, GetInfo(t), why);
  }

  /* Write the script value at 'idx' into 'out', a constructed 't'. Only
     called after Match accepted it. */
  void Read(lua_State* L, int idx, TypeT* t, TypeInfo const& info, void* out) {
    switch (info.kind) {
      case Kind_Bool:
      case Kind_Int:
      case Kind_Real:
      case Kind_String:
      case Kind_Vec3F:
        ReadScalar(L, idx, t, out);
        return;
      case Kind_Vec3D: {
        float const* v = lua_tovector(L, idx);
        *(V3D*)out = V3D(v[0], v[1], v[2]);
        return;
      }
      case Kind_Vec2F:
      case Kind_Vec2D: {
        double x, y;
        if (lua_type(L, idx) == LUA_TVECTOR) {
          float const* v = lua_tovector(L, idx);
          x = v[0];
          y = v[1];
        } else
          x = y = lua_tonumber(L, idx);
        if (info.kind == Kind_Vec2F)
          *(V2F*)out = V2F((float)x, (float)y);
        else
          *(V2D*)out = V2D(x, y);
        return;
      }
      case Kind_Data: {
        Data& d = *(Data*)out;
        Box* box = ToBox(L, idx);
        if (lua_isnil(L, idx))
          d.Clear();
        else if (box) {
          d.Construct(box->type);
          box->type->Assign(BoxData(box), d.data);
        } else if (lua_type(L, idx) == LUA_TNUMBER) {
          double v = lua_tonumber(L, idx);
          if (v == std::floor(v) && std::fabs(v) < 2147483648.0)
            d = (int)v;
          else
            d = (float)v;
        } else if (lua_type(L, idx) == LUA_TBOOLEAN)
          d = (bool)(lua_toboolean(L, idx) != 0);
        else if (lua_type(L, idx) == LUA_TSTRING)
          d = String(lua_tostring(L, idx));
        else if (lua_type(L, idx) == LUA_TVECTOR) {
          float const* v = lua_tovector(L, idx);
          d = V3F(v[0], v[1], v[2]);
        } else {
          LuauValue value = new LuauValueT;
          value->ref = lua_ref(L, idx);
          value->state = L;
          d = value;
        }
        return;
      }
      case Kind_Void:
        return;
      case Kind_Box:
        break;
    }

    if (lua_isnil(L, idx)) {
      /* A default-constructed reference is null; assign one over 'out'. */
      void* null = t->Allocate();
      t->Assign(null, out);
      t->Deallocate(null);
      return;
    }

    Box* box = ToBox(L, idx);
    if (box) {
      if (box->type == t)
        t->Assign(BoxData(box), out);
      else
        FindConversion(box->type, t)(box->type, BoxData(box), out);
      return;
    }

    std::vector<TypeT*> sources;
    ScalarSources(L, idx, sources);
    for (size_t i = 0; i < sources.size(); ++i) {
      ConversionFn convert = FindConversion(sources[i], t);
      if (!convert)
        continue;
      void* scalar = sources[i]->Allocate();
      ReadScalar(L, idx, sources[i], scalar);
      convert(sources[i], scalar, out);
      sources[i]->Deallocate(scalar);
      return;
    }
  }

  void Read(lua_State* L, int idx, TypeT* t, void* out) {
    Read(L, idx, t, GetInfo(t), out);
  }

  String DescribeArg(lua_State* L, int idx) {
    Box* box = ToBox(L, idx);
    if (box)
      return TypeName(box->type);
    if (lua_type(L, idx) == LUA_TNUMBER) {
      std::ostringstream s;
      s << "number " << lua_tonumber(L, idx);
      return s.str();
    }
    return luaL_typename(L, idx);
  }

  /* ------------------------------------------------------------------ */
  /* Calls                                                               */

  /* One overload with its parameter kinds worked out in advance. */
  const uint kMaxParams = 10;

  struct Overload {
    FunctionT* fn;
    uint paramCount;
    bool selfFirst;
    TypeT* types[kMaxParams];
    TypeInfo infos[kMaxParams];
    TypeT* returnType;
    TypeInfo returnInfo;
  };

  /* The overloads one script-visible name can resolve to. 'owner' is the
     box type for methods, whose member functions take it as 'self'. */
  struct Candidates {
    String name;
    TypeT* owner;
    Vector<Function> functions;
    std::vector<Overload> overloads;
    int closureRef;

    Candidates() : owner(nullptr), closureRef(0) {}

    void Prepare() {
      overloads.clear();
      for (size_t i = 0; i < functions.size(); ++i) {
        FunctionT* fn = functions[i];
        if (fn->paramCount > kMaxParams)
          continue;
        Overload o;
        o.fn = fn;
        o.paramCount = fn->paramCount;
        o.selfFirst = fn->paramCount > 0 && !fn->params[0].type;
        for (uint p = 0; p < fn->paramCount; ++p) {
          o.types[p] = fn->params[p].type;
          if (o.types[p])
            o.infos[p] = GetInfo(o.types[p]);
        }
        o.returnType = fn->returnType;
        o.returnInfo = GetInfo(fn->returnType);
        overloads.push_back(o);
      }
    }
  };

  /* Candidates live for the whole run; the list keeps addresses stable. */
  std::list<Candidates>& GetCandidateStore() {
    static std::list<Candidates> store;
    return store;
  }

  bool IsSelfParam(FunctionT const* fn, uint i) {
    return i == 0 && !fn->params[0].type;
  }

  int MatchCall(lua_State* L, Candidates const& c, Overload const& o, int argc) {
    if ((int)o.paramCount != argc)
      return Match_None;
    int score = 0;
    for (uint i = 0; i < o.paramCount; ++i) {
      int m;
      if (i == 0 && o.selfFirst) {
        Box* box = ToBox(L, 1);
        m = (box && box->type == c.owner) ? Match_Exact : Match_None;
      } else
        m = Match(L, (int)i + 1, o.types[i], o.infos[i]);
      if (m == Match_None)
        return Match_None;
      score += m;
    }
    return score;
  }

  Overload const* Resolve(lua_State* L, Candidates const& c, int argc) {
    Overload const* best = nullptr;
    int bestScore = 0;
    for (size_t i = 0; i < c.overloads.size(); ++i) {
      Overload const& o = c.overloads[i];
      int score = MatchCall(L, c, o, argc);
      if (score == Match_Exact)
        return &o;
      if (score != Match_None && (!best || score < bestScore)) {
        best = &o;
        bestScore = score;
      }
    }
    return best;
  }

  void NoOverload(lua_State* L, Candidates const& c, int argc) {
    std::ostringstream s;

    /* One overload with this arity: say which argument is wrong. */
    FunctionT* only = nullptr;
    int count = 0;
    for (size_t i = 0; i < c.functions.size(); ++i)
      if ((int)c.functions[i]->paramCount == argc) {
        only = c.functions[i];
        count++;
      }

    if (count == 1) {
      for (uint i = 0; i < only->paramCount; ++i) {
        if (IsSelfParam(only, i))
          continue;
        char const* why = nullptr;
        if (Match(L, (int)i + 1, only->params[i].type, &why) == Match_None) {
          s << "argument " << (i + 1) << " ('" << only->params[i].name
            << "') of " << c.name << ": expected "
            << TypeName(only->params[i].type) << ", got "
            << DescribeArg(L, (int)i + 1);
          if (why)
            s << " (" << why << ")";
          s << "\n  " << only->GetSignature();
          break;
        }
      }
    } else {
      s << "no overload of " << c.name << " accepts (";
      for (int i = 1; i <= argc; ++i)
        s << (i > 1 ? ", " : "") << DescribeArg(L, i);
      s << ")";
      for (size_t i = 0; i < c.functions.size() && i < 8; ++i)
        s << "\n  " << c.functions[i]->GetSignature();
    }

    String message = s.str();
    luaL_where(L, 1);
    lua_pushlstring(L, message.data(), message.size());
    lua_concat(L, 2);
    lua_error(L);
  }

  /* Temporaries for one call, in a stack buffer when they fit, released
     even when a script error unwinds. */
  struct CallFrame {
    struct Temp {
      TypeT* type;
      void* p;
      bool heap;
    };

    alignas(16) char storage[512];
    size_t used;
    Temp temps[kMaxParams + 1];
    uint count;

    CallFrame() : used(0), count(0) {}

    void* Own(TypeT* t) {
      Temp& temp = temps[count++];
      temp.type = t;
      size_t align = t->alignment ? t->alignment : 1;
      size_t offset = (used + align - 1) & ~(align - 1);
      if (align <= 16 && offset + t->size <= sizeof(storage)) {
        temp.p = storage + offset;
        temp.heap = false;
        used = offset + t->size;
        t->Construct(temp.p);
      } else {
        temp.p = t->Allocate();
        temp.heap = true;
      }
      return temp.p;
    }

    ~CallFrame() {
      for (uint i = count; i-- > 0;) {
        if (temps[i].heap)
          temps[i].type->Deallocate(temps[i].p);
        else
          temps[i].type->Destruct(temps[i].p);
      }
    }
  };

  int Invoke(lua_State* L, Overload const& o) {
    CallFrame frame;
    void* argv[kMaxParams + 1];

    for (uint i = 0; i < o.paramCount; ++i) {
      int idx = (int)i + 1;
      Box* box = ToBox(L, idx);
      if (i == 0 && o.selfFirst) {
        argv[i] = BoxData(box);
        continue;
      }

      /* An exact box is passed in place, so functions that modify their
         argument (Vector Append, ...) modify the script's value. */
      TypeT* t = o.types[i];
      if (box && box->type == t)
        argv[i] = BoxData(box);
      else {
        argv[i] = frame.Own(t);
        Read(L, idx, t, o.infos[i], argv[i]);
      }
    }

    if (o.returnInfo.kind == Kind_Void) {
      o.fn->call(argv, nullptr);
      return 0;
    }

    void* result = frame.Own(o.returnType);
    o.fn->call(argv, result);
    return Push(L, o.returnType, result);
  }

  int Call(lua_State* L, Candidates const& c) {
    int argc = lua_gettop(L);
    Overload const* o = Resolve(L, c, argc);
    if (!o)
      NoOverload(L, c, argc);
    return Invoke(L, *o);
  }

  int Dispatch(lua_State* L) {
    return Call(L, *(Candidates const*)lua_touserdata(L, lua_upvalueindex(1)));
  }

  void PushDispatcher(lua_State* L, Candidates& c) {
    if (!c.closureRef) {
      lua_pushlightuserdata(L, &c);
      lua_pushcclosure(L, Dispatch, c.name.c_str(), 1);
      c.closureRef = lua_ref(L, -1);
      lua_pop(L, 1);
    }
    lua_getref(L, c.closureRef);
  }

  void AddUnique(Vector<Function>& list, Function const& fn) {
    for (size_t i = 0; i < list.size(); ++i)
      if (list[i] == fn)
        return;
    list.push(fn);
  }

  bool IsFreeFunction(FunctionT const* fn) {
    for (uint i = 0; i < fn->paramCount; ++i)
      if (!fn->params[i].type)
        return false;
    return fn->call != nullptr;
  }

  Candidates* FreeCandidates(String const& name) {
    static std::map<String, Candidates*> cache;
    std::map<String, Candidates*>::iterator it = cache.find(name);
    if (it != cache.end())
      return it->second;

    Candidates c;
    c.name = name;
    Vector<Function> const& found = Function_Find(name);
    for (size_t i = 0; i < found.size(); ++i)
      if (IsFreeFunction(found[i]))
        AddUnique(c.functions, found[i]);

    Candidates* result = nullptr;
    if (c.functions.size()) {
      GetCandidateStore().push_back(c);
      result = &GetCandidateStore().back();
      result->Prepare();
    }
    cache[name] = result;
    return result;
  }

  /* Methods of 't' named 'name': its member functions (and its bases'),
     and free functions whose first parameter accepts a 't'. */
  Candidates* MethodCandidates(TypeT* t, String const& name) {
    static std::map<std::pair<TypeT*, String>, Candidates*> cache;
    std::pair<TypeT*, String> key(t, name);
    std::map<std::pair<TypeT*, String>, Candidates*>::iterator it = cache.find(key);
    if (it != cache.end())
      return it->second;

    Candidates c;
    c.name = TypeName(t) + ":" + name;
    c.owner = t;
    for (TypeT* type = t; type; type = type->base) {
      Vector<Function> const& members = type->GetFunctions();
      for (size_t i = 0; i < members.size(); ++i)
        if (members[i]->name == name && members[i]->call)
          AddUnique(c.functions, members[i]);
    }

    Vector<Function> const& found = Function_Find(name);
    for (size_t i = 0; i < found.size(); ++i) {
      FunctionT* fn = found[i];
      if (!IsFreeFunction(fn) || fn->paramCount < 1)
        continue;
      TypeT* first = fn->params[0].type;
      if (first == t || FindConversion(t, first))
        AddUnique(c.functions, found[i]);
    }

    Candidates* result = nullptr;
    if (c.functions.size()) {
      GetCandidateStore().push_back(c);
      result = &GetCandidateStore().back();
      result->Prepare();
    }
    cache[key] = result;
    return result;
  }

  /* ------------------------------------------------------------------ */
  /* Box metatable                                                       */

  /* The field 'name' of the boxed value, looking through references. */
  bool FindBoxField(Box* box, char const* name, FieldType& field) {
    TypeT* t = box->type;
    void* data = BoxData(box);
    if (t->IsComposite() && t->HasField(data, name)) {
      field = t->FindField(data, name);
      return field.address != nullptr;
    }

    if (IsNullable(t) && *(void**)data) {
      TypeT* pointee = t->GetPointeeType();
      void* target = *(void**)data;
      if (pointee && pointee->IsComposite() && pointee->HasField(target, name)) {
        field = pointee->FindField(target, name);
        return field.address != nullptr;
      }
    }
    return false;
  }

  /* What a key names on a box type, resolved once per (type, atom). Field
     offsets are cached only for fields inside the struct (or its pointee);
     container mappers that point into heap storage go through reflection
     every time. */
  struct Member {
    enum Kind { Unresolved, None, Field, PointeeField, DynamicField, Method };
    Kind kind;
    size_t offset;
    TypeT* type;
    Candidates* method;

    Member() : kind(Unresolved), offset(0), type(nullptr), method(nullptr) {}
  };

  Member const& ResolveMember(Box* box, char const* key, int atom) {
    static std::unordered_map<TypeT*, std::vector<Member> > tables;
    static Member uncached;

    /* Through a null reference the pointee's fields are invisible, so a
       resolution made then must not be cached. */
    bool nullRef = IsNullable(box->type) && !*(void**)BoxData(box);

    Member* member = &uncached;
    if (atom >= 0 && !nullRef) {
      std::vector<Member>& table = tables[box->type];
      if ((size_t)atom >= table.size())
        table.resize(atom + 64);
      member = &table[atom];
      if (member->kind != Member::Unresolved)
        return *member;
    }
    *member = Member();

    FieldType field;
    if (FindBoxField(box, key, field)) {
      char* data = (char*)BoxData(box);
      char* address = (char*)field.address;
      TypeT* t = box->type;
      member->type = field.type.t;
      if (address >= data && address + field.type->size <= data + t->size) {
        member->kind = Member::Field;
        member->offset = address - data;
      } else if (IsNullable(t) && *(char**)data && t->GetPointeeType()) {
        char* target = *(char**)data;
        size_t size = t->GetPointeeType()->size;
        if (address >= target && address + field.type->size <= target + size) {
          member->kind = Member::PointeeField;
          member->offset = address - target;
        } else
          member->kind = Member::DynamicField;
      } else
        member->kind = Member::DynamicField;
      return *member;
    }

    member->method = MethodCandidates(box->type, key);
    member->kind = member->method ? Member::Method : Member::None;
    return *member;
  }

  /* The address of the field 'member' names in 'box', or null. */
  void* MemberAddress(Box* box, Member const& member, char const* key) {
    char* data = (char*)BoxData(box);
    switch (member.kind) {
      case Member::Field:
        return data + member.offset;
      case Member::PointeeField: {
        char* target = *(char**)data;
        return target ? target + member.offset : nullptr;
      }
      case Member::DynamicField: {
        FieldType field;
        return FindBoxField(box, key, field) ? field.address : nullptr;
      }
      default:
        return nullptr;
    }
  }

  int Box_Index(lua_State* L) {
    Box* box = ToBox(L, 1);
    int atom = -1;
    char const* key = lua_tostringatom(L, 2, &atom);
    if (!key)
      luaL_error(L, "%s fields are named by strings", TypeName(box->type).c_str());

    Member const& member = ResolveMember(box, key, atom);
    if (member.kind == Member::Method) {
      PushDispatcher(L, *member.method);
      return 1;
    }

    void* address = MemberAddress(box, member, key);
    if (!address) {
      if (member.kind == Member::PointeeField)
        luaL_error(L, "field '%s' of a null %s", key, TypeName(box->type).c_str());
      luaL_error(L, "%s has no field or method '%s'", TypeName(box->type).c_str(), key);
    }
    return Push(L, member.type, address) ? 1 : (lua_pushnil(L), 1);
  }

  int Box_NewIndex(lua_State* L) {
    Box* box = ToBox(L, 1);
    int atom = -1;
    char const* key = lua_tostringatom(L, 2, &atom);
    if (!key)
      luaL_error(L, "%s fields are named by strings", TypeName(box->type).c_str());

    Member const& member = ResolveMember(box, key, atom);
    void* address = MemberAddress(box, member, key);
    if (!address)
      luaL_error(L, "%s has no field '%s'", TypeName(box->type).c_str(), key);

    char const* why = nullptr;
    if (Match(L, 3, member.type, &why) == Match_None)
      luaL_error(L, "field '%s' of %s: expected %s, got %s%s%s",
        key, TypeName(box->type).c_str(), TypeName(member.type).c_str(),
        DescribeArg(L, 3).c_str(), why ? " - " : "", why ? why : "");
    Read(L, 3, member.type, address);
    return 0;
  }

  int Box_ToString(lua_State* L) {
    Box* box = ToBox(L, 1);
    String s = box->type->toString
      ? box->type->ToString(BoxData(box))
      : "<" + TypeName(box->type) + ">";
    lua_pushlstring(L, s.data(), s.size());
    return 1;
  }

  int Box_Eq(lua_State* L) {
    Box* a = ToBox(L, 1);
    Box* b = ToBox(L, 2);
    if (a && b && a->type == b->type && IsNullable(a->type)) {
      lua_pushboolean(L, *(void**)BoxData(a) == *(void**)BoxData(b));
      return 1;
    }

    Candidates* c = FreeCandidates("==");
    Overload const* o = c ? Resolve(L, *c, 2) : nullptr;
    if (!o) {
      lua_pushboolean(L, false);
      return 1;
    }
    return Invoke(L, *o);
  }

  int Operator(lua_State* L, char const* name, int argc) {
    lua_settop(L, argc);
    Candidates* c = FreeCandidates(name);
    if (!c) {
      Candidates none;
      none.name = name;
      NoOverload(L, none, argc);
    }
    return Call(L, *c);
  }

  /* obj:Method(...) goes through __namecall, which gets the method name as
     an interned atom: methods are cached per box type in a vector indexed
     by atom, so a call costs an array lookup instead of a string-keyed one
     plus fetching a closure. */
  std::unordered_map<std::string, int16_t>& GetAtoms() {
    static std::unordered_map<std::string, int16_t> atoms;
    return atoms;
  }

  std::vector<String>& GetAtomNames() {
    static std::vector<String> names;
    return names;
  }

  int16_t UserAtom(lua_State*, char const* s, size_t len) {
    std::string name(s, len);
    std::unordered_map<std::string, int16_t>::const_iterator it = GetAtoms().find(name);
    if (it != GetAtoms().end())
      return it->second;
    if (GetAtomNames().size() >= 32000)
      return -1;
    int16_t atom = (int16_t)GetAtomNames().size();
    GetAtoms()[name] = atom;
    GetAtomNames().push_back(name);
    return atom;
  }

  /* Per box type: atom -> candidates (null: no such method), resolved on
     first use. */
  struct MethodTable {
    std::vector<Candidates*> methods;
    std::vector<bool> resolved;
  };

  Candidates* MethodByAtom(TypeT* t, int atom) {
    static std::unordered_map<TypeT*, MethodTable> tables;
    static TypeT* lastType = nullptr;
    static MethodTable* lastTable = nullptr;

    MethodTable* table = lastTable;
    if (t != lastType) {
      table = &tables[t];
      lastType = t;
      lastTable = table;
    }
    if ((size_t)atom >= table->methods.size()) {
      table->methods.resize(GetAtomNames().size() + 64, nullptr);
      table->resolved.resize(table->methods.size(), false);
    }
    if (!table->resolved[atom]) {
      table->methods[atom] = MethodCandidates(t, GetAtomNames()[atom]);
      table->resolved[atom] = true;
    }
    return table->methods[atom];
  }

  int Box_Namecall(lua_State* L) {
    int atom = -1;
    char const* name = lua_namecallatom(L, &atom);
    Box* box = ToBox(L, 1);
    if (!box || !name)
      luaL_error(L, "bad method call");
    Candidates* c = atom >= 0
      ? MethodByAtom(box->type, atom)
      : MethodCandidates(box->type, name);
    if (!c)
      luaL_error(L, "%s has no method '%s'", TypeName(box->type).c_str(), name);
    return Call(L, *c);
  }

  int Box_Add(lua_State* L) { return Operator(L, "+", 2); }
  int Box_Sub(lua_State* L) { return Operator(L, "-", 2); }
  int Box_Mul(lua_State* L) { return Operator(L, "*", 2); }
  int Box_Div(lua_State* L) { return Operator(L, "/", 2); }
  int Box_Unm(lua_State* L) { return Operator(L, "-", 1); }
  int Box_Lt(lua_State* L) { return Operator(L, "<", 2); }
  int Box_Le(lua_State* L) { return Operator(L, "<=", 2); }

  void CreateBoxMetatable(lua_State* L) {
    lua_newtable(L);
    lua_pushcfunction(L, Box_Index, "__index");
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, Box_NewIndex, "__newindex");
    lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, Box_ToString, "__tostring");
    lua_setfield(L, -2, "__tostring");
    lua_pushcfunction(L, Box_Eq, "__eq");
    lua_setfield(L, -2, "__eq");
    lua_pushcfunction(L, Box_Add, "__add");
    lua_setfield(L, -2, "__add");
    lua_pushcfunction(L, Box_Sub, "__sub");
    lua_setfield(L, -2, "__sub");
    lua_pushcfunction(L, Box_Mul, "__mul");
    lua_setfield(L, -2, "__mul");
    lua_pushcfunction(L, Box_Div, "__div");
    lua_setfield(L, -2, "__div");
    lua_pushcfunction(L, Box_Unm, "__unm");
    lua_setfield(L, -2, "__unm");
    lua_pushcfunction(L, Box_Lt, "__lt");
    lua_setfield(L, -2, "__lt");
    lua_pushcfunction(L, Box_Le, "__le");
    lua_setfield(L, -2, "__le");
    lua_pushcfunction(L, Box_Namecall, "__namecall");
    lua_setfield(L, -2, "__namecall");
    lua_pushstring(L, "engine value");
    lua_setfield(L, -2, "__metatable");
    lua_setuserdatametatable(L, kBoxTag);
    lua_setuserdatadtor(L, kBoxTag, BoxDestructor);
  }

  /* ------------------------------------------------------------------ */
  /* Globals                                                             */

  bool IsIdentifier(String const& s) {
    if (s.empty() || !(isalpha((unsigned char)s[0]) || s[0] == '_'))
      return false;
    for (size_t i = 1; i < s.size(); ++i)
      if (!(isalnum((unsigned char)s[i]) || s[i] == '_'))
        return false;
    return true;
  }

  /* Whether 'fn' is some type's member function (Vector Get, ...). */
  bool IsMemberFunction(FunctionT const* fn) {
    static std::set<FunctionT const*> members;
    if (members.empty()) {
      Vector<Type> const& types = Type_GetList();
      for (size_t i = 0; i < types.size(); ++i) {
        Vector<Function> const& fns = types[i]->GetFunctions();
        for (size_t j = 0; j < fns.size(); ++j)
          members.insert(fns[j].t);
      }
    }
    return members.count(fn) != 0;
  }

  /* Globals are functions' own names (Object_GetPos) and "Type_Name"-style
     aliases (Sound_Play). Bare method aliases (GetPos, Get, Size) are for
     method calls; as globals they would merge every type's overloads. */
  bool IsGlobalName(String const& name) {
    if (!IsIdentifier(name))
      return false;
    if (name.find('_') != String::npos)
      return true;
    Vector<Function> const& found = Function_Find(name);
    for (size_t i = 0; i < found.size(); ++i)
      if (found[i]->name == name && IsFreeFunction(found[i]) && !IsMemberFunction(found[i]))
        return true;
    return false;
  }

  void BindFunctions(lua_State* L) {
    Vector<String> names = Function_GetNames();
    for (size_t i = 0; i < names.size(); ++i) {
      if (!IsGlobalName(names[i]))
        continue;
      lua_getglobal(L, names[i].c_str());
      bool taken = !lua_isnil(L, -1);
      lua_pop(L, 1);
      if (taken)
        continue;
      Candidates* c = FreeCandidates(names[i]);
      if (!c)
        continue;
      PushDispatcher(L, *c);
      lua_setglobal(L, names[i].c_str());
    }
  }

  /* lt.new(typeName): a default-constructed engine value. */
  int Lt_New(lua_State* L) {
    char const* name = luaL_checkstring(L, 1);
    Type t = Type_Find(name);
    if (!t)
      luaL_error(L, "lt.new: unknown engine type '%s'", name);
    PushBox(L, t.t, nullptr);
    return 1;
  }

  /* lt.typeof(value): the engine type name, or the Luau type. */
  int Lt_TypeOf(lua_State* L) {
    Box* box = ToBox(L, 1);
    String name = box ? TypeName(box->type) : String(luaL_typename(L, 1));
    lua_pushlstring(L, name.data(), name.size());
    return 1;
  }

  /* ltsl("Widget/Components:AlignCenter")(...) calls an LTSL function, for
     code that still lives in LTSL during the migration. Arguments are
     checked against its parameter types like engine calls. */
  int Ltsl_Call(lua_State* L) {
    ScriptFunctionT* fn = (ScriptFunctionT*)lua_touserdata(L, lua_upvalueindex(1));
    int argc = lua_gettop(L);
    if (argc != (int)fn->parameters.size())
      luaL_error(L, "%s expects %d argument(s), got %d",
        fn->name.c_str(), (int)fn->parameters.size(), argc);

    CallFrame frame;
    std::vector<void*> argv(fn->parameters.size() + 1, nullptr);
    for (int i = 0; i < argc; ++i) {
      TypeT* t = fn->parameters[i].type;
      char const* why = nullptr;
      if (Match(L, i + 1, t, &why) == Match_None)
        luaL_error(L, "argument %d ('%s') of %s: expected %s, got %s%s%s",
          i + 1, fn->parameters[i].name.c_str(), fn->name.c_str(),
          TypeName(t).c_str(), DescribeArg(L, i + 1).c_str(),
          why ? " - " : "", why ? why : "");
      Box* box = ToBox(L, i + 1);
      if (box && box->type == t)
        argv[i] = BoxData(box);
      else {
        argv[i] = frame.Own(t);
        Read(L, i + 1, t, argv[i]);
      }
    }

    TypeT* rt = fn->returnType;
    if (!rt || GetInfo(rt).kind == Kind_Void || !rt->allocate) {
      fn->Call(nullptr, argv.data());
      return 0;
    }
    void* result = frame.Own(rt);
    fn->Call(result, argv.data());
    return Push(L, rt, result);
  }

  int Ltsl_Get(lua_State* L) {
    String path = luaL_checkstring(L, 1);
    static std::map<String, ScriptFunction> cache;
    ScriptFunction& fn = cache[path];
    if (!fn)
      fn = ScriptFunction_Load(path);
    if (!fn)
      luaL_error(L, "ltsl: no LTSL function '%s'", path.c_str());
    lua_pushlightuserdata(L, fn.t);
    lua_pushcclosure(L, Ltsl_Call, path.c_str(), 1);
    return 1;
  }

  /* ltsl_new("Widget/Messages:MessageAddWidget"): an instance of an LTSL
     type (fields zeroed; LTSL default values are not applied). */
  int Ltsl_New(lua_State* L) {
    String path = luaL_checkstring(L, 1);
    ScriptType type = ScriptType_Load(path);
    if (!type || !type->type)
      luaL_error(L, "ltsl_new: no LTSL type '%s'", path.c_str());
    PushBox(L, type->type.t, nullptr);
    return 1;
  }

  int New_Create(lua_State* L) {
    PushBox(L, (TypeT*)lua_touserdata(L, lua_upvalueindex(1)), nullptr);
    return 1;
  }

  void BindHelpers(lua_State* L) {
    lua_newtable(L);
    lua_pushcfunction(L, Lt_New, "new");
    lua_setfield(L, -2, "new");
    lua_pushcfunction(L, Lt_TypeOf, "typeof");
    lua_setfield(L, -2, "typeof");
    lua_setglobal(L, "lt");
    lua_pushcfunction(L, Ltsl_Get, "ltsl");
    lua_setglobal(L, "ltsl");
    lua_pushcfunction(L, Ltsl_New, "ltsl_new");
    lua_setglobal(L, "ltsl_new");
  }

  /* ------------------------------------------------------------------ */
  /* Modules                                                             */

  /* Modules are named "@lt/Path/Name" (Luau's alias form, which editor
     tooling also understands) for resource/script/Path/Name.luau. */
  String ModulePath(String const& module) {
    String path = module.compare(0, 4, "@lt/") == 0 ? String(module.substr(4)) : module;
    return "resource/script/" + path + ".luau";
  }

  bool ReadFile(String const& path, String& out) {
    std::ifstream file(path.c_str(), std::ios::binary);
    if (!file)
      return false;
    std::ostringstream s;
    s << file.rdbuf();
    out = s.str();
    return true;
  }

  int Require(lua_State* L) {
    String module = luaL_checkstring(L, 1);

    lua_getfield(L, LUA_REGISTRYINDEX, "_LT_MODULES");
    int cache = lua_gettop(L);
    lua_getfield(L, cache, module.c_str());
    if (!lua_isnil(L, -1))
      return 1;
    lua_pop(L, 1);

    String path = ModulePath(module);
    String source;
    if (!ReadFile(path, source))
      luaL_error(L, "module '%s' not found (%s)", module.c_str(), path.c_str());

    lua_CompileOptions options;
    memset(&options, 0, sizeof(options));
    options.optimizationLevel = 1;
    options.debugLevel = 1;
    size_t size = 0;
    char* bytecode = luau_compile(source.data(), source.size(), &options, &size);
    String chunk = "@" + path;
    int status = luau_load(L, chunk.c_str(), bytecode, size, 0);
    free(bytecode);
    if (status != 0)
      lua_error(L);

    lua_call(L, 0, 1);
    if (lua_isnil(L, -1)) {
      lua_pop(L, 1);
      lua_pushboolean(L, true);
    }
    lua_pushvalue(L, -1);
    lua_setfield(L, cache, module.c_str());
    return 1;
  }

  int Traceback(lua_State* L) {
    char const* message = lua_tostring(L, 1);
    luaL_traceback(L, L, message ? message : "(non-string error)", 1);
    return 1;
  }

  void BindNew(lua_State* L);

  lua_State* CreateState() {
    InitKinds();
    lua_State* L = luaL_newstate();
    lua_callbacks(L)->useratom = UserAtom;
    luaL_openlibs(L);
    lua_newtable(L);
    lua_setfield(L, LUA_REGISTRYINDEX, "_LT_MODULES");
    lua_pushcfunction(L, Require, "require");
    lua_setglobal(L, "require");
    CreateBoxMetatable(L);
    BindHelpers(L);
    BindFunctions(L);
    BindNew(L);
    return L;
  }
}

namespace {
  /* ------------------------------------------------------------------ */
  /* Type definitions for the checker                                    */

  bool IsKeyword(String const& s) {
    static char const* const words[] = {
      "and", "break", "do", "else", "elseif", "end", "false", "for",
      "function", "if", "in", "local", "nil", "not", "or", "repeat",
      "return", "then", "true", "until", "while", "continue", "type",
      "export", "typeof", nullptr };
    for (size_t i = 0; words[i]; ++i)
      if (s == words[i])
        return true;
    return false;
  }

  struct DefinitionWriter {
    std::ostringstream out;
    std::map<TypeT*, String> classNames;
    std::vector<TypeT*> pending;
    std::map<TypeT*, std::vector<TypeT*> > convertibleFrom;

    DefinitionWriter() {
      Vector<Type> const& types = Type_GetList();
      for (size_t i = 0; i < types.size(); ++i) {
        Vector<ConversionType> const& conversions = types[i]->GetConversions();
        for (size_t j = 0; j < conversions.size(); ++j)
          convertibleFrom[conversions[j].other.t].push_back(types[i].t);
      }
    }

    std::set<String> usedNames;

    static String Mangle(String const& full) {
      String name;
      bool underscore = false;
      for (size_t i = 0; i < full.size(); ++i) {
        char c = full[i];
        if (isalnum((unsigned char)c)) {
          name += c;
          underscore = false;
        } else if (!underscore && !name.empty()) {
          name += '_';
          underscore = true;
        }
      }
      while (!name.empty() && name[name.size() - 1] == '_')
        name.erase(name.size() - 1);
      if (name.empty() || isdigit((unsigned char)name[0]))
        name = "T_" + name;
      return name;
    }

    /* Raw pointer types (T*) are presented as T's class. */
    std::map<TypeT*, std::vector<TypeT*> > pointersTo;

    /* A class name for a boxed engine type, queued for declaration. */
    String ClassName(TypeT* t) {
      std::map<TypeT*, String>::iterator it = classNames.find(t);
      if (it != classNames.end())
        return it->second;

      if (t->IsPointer() && t->GetPointeeType()) {
        TypeT* pointee = t->GetPointeeType();
        String name = ClassName(pointee);
        classNames[t] = name;
        pointersTo[pointee].push_back(t);
        return name;
      }

      /* The alias if it's a unique identifier, else the mangled full name
      (template instances share aliases like "Map"), else numbered. */
      String alias = t->GetAliasName();
      String name;
      if (IsIdentifier(alias) && !IsKeyword(alias) && !usedNames.count(alias))
        name = alias;
      else {
        name = Mangle(t->name);
        if (usedNames.count(name)) {
          for (int n = 2;; ++n) {
            std::ostringstream numbered;
            numbered << name << "_" << n;
            if (!usedNames.count(numbered.str())) {
              name = numbered.str();
              break;
            }
          }
        }
      }

      usedNames.insert(name);
      classNames[t] = name;
      pending.push_back(t);
      return name;
    }

    String ScalarName(TypeT* t) {
      switch (GetInfo(t).kind) {
        case Kind_Bool: return "boolean";
        case Kind_Int: return "int";
        case Kind_Real: return "number";
        case Kind_String: return "string";
        case Kind_Vec2F:
        case Kind_Vec2D:
        case Kind_Vec3F:
        case Kind_Vec3D: return "vector";
        case Kind_Data: return "any";
        case Kind_Void: return "()";
        default: return "";
      }
    }

    /* The type a script may pass for parameter type 't'. */
    String ParamType(TypeT* t) {
      Kind kind = GetInfo(t).kind;
      if (kind == Kind_Vec2F || kind == Kind_Vec2D)
        return "vector | number";
      String scalar = ScalarName(t);
      if (!scalar.empty())
        return scalar;

      std::vector<String> options;
      options.push_back(ClassName(t));
      std::vector<TypeT*> const& from = convertibleFrom[t];
      for (size_t i = 0; i < from.size(); ++i) {
        String option = ScalarName(from[i]);
        if (option.empty())
          option = ClassName(from[i]);
        if (option == "int" || option == "()")
          option = "number";
        if (std::find(options.begin(), options.end(), option) == options.end())
          options.push_back(option);
      }

      String result;
      for (size_t i = 0; i < options.size(); ++i)
        result += (i ? " | " : "") + options[i];
      if (IsNullable(t))
        result = options.size() > 1 ? "(" + result + ")?" : result + "?";
      return result;
    }

    /* Results are declared non-optional: most getters never return null,
       and a call on a nil result still fails loudly at runtime. */
    String ReturnType(TypeT* t) {
      String scalar = ScalarName(t);
      return scalar.empty() ? ClassName(t) : scalar;
    }

    String ParamName(FunctionT const* fn, uint i) {
      String name = fn->params[i].name;
      if (!IsIdentifier(name) || IsKeyword(name) || name == "self") {
        std::ostringstream s;
        s << "arg" << i;
        return s.str();
      }
      return name;
    }

    /* "(a: A, b: B)" with an optional leading self. */
    String Params(FunctionT const* fn, bool method) {
      std::ostringstream s;
      s << "(";
      bool first = true;
      if (method) {
        s << "self";
        first = false;
      }
      for (uint i = method ? 1 : 0; i < fn->paramCount; ++i) {
        s << (first ? "" : ", ") << ParamName(fn, i) << ": "
          << ParamType(fn->params[i].type);
        first = false;
      }
      s << ")";
      return s.str();
    }

    String FunctionType(FunctionT const* fn) {
      return Params(fn, false) + " -> " + ReturnType(fn->returnType);
    }

    void WriteGlobals() {
      Vector<String> names = Function_GetNames();
      for (size_t i = 0; i < names.size(); ++i) {
        if (!IsGlobalName(names[i]) || IsKeyword(names[i]))
          continue;
        Candidates* c = FreeCandidates(names[i]);
        if (!c)
          continue;

        if (c->functions.size() == 1) {
          FunctionT const* fn = c->functions[0];
          out << "declare function " << names[i] << Params(fn, false);
          if (GetInfo(fn->returnType).kind != Kind_Void)
            out << ": " << ReturnType(fn->returnType);
          out << "\n";
        } else {
          out << "declare " << names[i] << ": ";
          for (size_t j = 0; j < c->functions.size(); ++j)
            out << (j ? " & " : "") << "(" << FunctionType(c->functions[j]) << ")";
          out << "\n";
        }
      }
    }

    /* Field names and types, read from a temporary instance. */
    void Fields(TypeT* t, std::vector<std::pair<String, TypeT*> >& fields) {
      /* Through a reference or pointer, the pointee's fields are visible. */
      if (IsNullable(t)) {
        if (t->GetPointeeType())
          Fields(t->GetPointeeType(), fields);
        return;
      }
      if (!t->IsComposite() || !t->allocate)
        return;
      void* instance = t->Allocate();
      size_t count = t->GetFieldCount(instance);
      for (size_t i = 0; i < count; ++i) {
        FieldType f = t->GetField(instance, i);
        if (f.name && f.type && IsIdentifier(f.name) && !IsKeyword(f.name))
          fields.push_back(std::make_pair(String(f.name), f.type.t));
      }
      t->Deallocate(instance);
    }

    bool IsFieldName(std::vector<std::pair<String, TypeT*> > const& fields, String const& name) {
      for (size_t i = 0; i < fields.size(); ++i)
        if (fields[i].first == name)
          return true;
      return false;
    }

    void WriteMethods(String const& name, Candidates const* c) {
      for (size_t i = 0; i < c->functions.size(); ++i) {
        FunctionT const* fn = c->functions[i];
        if (fn->paramCount < 1)
          continue;
        out << "  function " << name << Params(fn, true);
        if (GetInfo(fn->returnType).kind != Kind_Void)
          out << ": " << ReturnType(fn->returnType);
        out << "\n";
      }
    }

    void WriteOperators(TypeT* t) {
      static char const* const ops[][2] = {
        { "+", "__add" }, { "-", "__sub" }, { "*", "__mul" }, { "/", "__div" },
        { "<", "__lt" }, { "<=", "__le" } };
      for (size_t i = 0; i < sizeof(ops) / sizeof(ops[0]); ++i) {
        Candidates* c = FreeCandidates(ops[i][0]);
        if (!c)
          continue;
        for (size_t j = 0; j < c->functions.size(); ++j) {
          FunctionT const* fn = c->functions[j];
          if (fn->paramCount == 2 && fn->params[0].type == t)
            out << "  function " << ops[i][1] << "(self, other: "
                << ParamType(fn->params[1].type) << "): "
                << ReturnType(fn->returnType) << "\n";
        }
      }
    }

    /* Fields, then methods: the type's own, and those of the raw pointer
       types that share its class. Fields win over same-named methods, as
       at runtime. */
    void WriteClass(TypeT* t, Vector<String> const& names) {
      out << "declare extern type " << classNames[t] << " with\n";

      std::vector<std::pair<String, TypeT*> > fields;
      Fields(t, fields);
      for (size_t i = 0; i < fields.size(); ++i)
        out << "  " << fields[i].first << ": " << ReturnType(fields[i].second) << "\n";

      std::vector<TypeT*> receivers(1, t);
      std::vector<TypeT*> const& pointers = pointersTo[t];
      receivers.insert(receivers.end(), pointers.begin(), pointers.end());

      for (size_t r = 0; r < receivers.size(); ++r)
        for (size_t i = 0; i < names.size(); ++i) {
          String const& name = names[i];
          if (!IsIdentifier(name) || IsKeyword(name) || IsFieldName(fields, name))
            continue;
          Candidates* c = MethodCandidates(receivers[r], name);
          if (c)
            WriteMethods(name, c);
        }

      WriteOperators(t);
      out << "end\n\n";
    }

    String Generate() {
      out << "-- Engine API for Luau scripts, generated from the engine's\n"
          << "-- reflection by luaucheck. Do not edit.\n\n"
          << "-- Engine integers: whole numbers only (checked at runtime)\n"
          << "export type int = number\n\n"
          << "declare lt: {\n"
          << "  new: (typeName: string) -> any,\n"
          << "  typeof: (value: any) -> string,\n"
          << "}\n\n"
          << "-- Call an LTSL function (\"Script/Path:Function\"); untyped\n"
          << "declare function ltsl(path: string): (...any) -> any\n"
          << "-- An instance of an LTSL type (\"Script/Path:Type\"); untyped\n"
          << "declare function ltsl_new(path: string): any\n\n";

      std::ostringstream globals;
      std::swap(out, globals);
      WriteGlobals();
      std::swap(out, globals);

      Vector<String> names = Function_GetNames();

      std::ostringstream classes;
      std::swap(out, classes);
      std::map<TypeT*, bool> written;
      while (!pending.empty()) {
        TypeT* t = pending.back();
        pending.pop_back();
        if (written[t])
          continue;
        written[t] = true;

        /* Pointer types are folded into their pointee's class. */
        if (t->IsPointer() && t->GetPointeeType())
          continue;
        WriteClass(t, names);
      }
      std::swap(out, classes);

      out << classes.str() << globals.str() << "\n";

      /* New.ClassName(): a default-constructed engine value. */
      out << "declare extern type EngineConstructors with\n";
      std::map<String, TypeT*> constructible = Constructible();
      for (std::map<String, TypeT*>::const_iterator it = constructible.begin();
           it != constructible.end(); ++it)
        out << "  " << it->first << ": () -> " << it->first << "\n";
      out << "end\n\ndeclare New: EngineConstructors\n";
      return out.str();
    }

    /* Declared classes a script can create with New: concrete value types
       (not references or pointers, which would only ever be null). */
    std::map<String, TypeT*> Constructible() {
      std::map<String, TypeT*> result;
      for (std::map<TypeT*, String>::const_iterator it = classNames.begin();
           it != classNames.end(); ++it) {
        TypeT* t = it->first;
        if (t->allocate && t->construct && t->assign && !IsNullable(t))
          result[it->second] = t;
      }
      return result;
    }
  };
}

namespace {
  std::map<String, TypeT*>& GetConstructible() {
    static std::map<String, TypeT*> constructible;
    if (constructible.empty()) {
      DefinitionWriter writer;
      writer.Generate();
      constructible = writer.Constructible();
    }
    return constructible;
  }

  int New_Index(lua_State* L) {
    char const* name = luaL_checkstring(L, 2);
    std::map<String, TypeT*>::const_iterator it = GetConstructible().find(name);
    if (it == GetConstructible().end())
      luaL_error(L, "New.%s: no engine type by that name can be created", name);
    lua_pushlightuserdata(L, it->second);
    lua_pushcclosure(L, New_Create, name, 1);
    return 1;
  }

  void BindNew(lua_State* L) {
    lua_newtable(L);
    lua_newtable(L);
    lua_pushcfunction(L, New_Index, "__index");
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);
    lua_setglobal(L, "New");
  }
}

namespace {
  /* A widget component whose events are methods of a Luau object:
     obj:PreUpdate(widget), obj:CreateChildren(widget) -> { Widget },
     obj:Receive(widget, data), ... - the Luau counterpart of LTSL's
     Custom widgets. */
  AutoClassDerived(WidgetLuau, WidgetComponentT,
    LuauValue, instance)
    DERIVED_TYPE_EX(WidgetLuau)
    POOLED_TYPE

    WidgetLuau() {}

    /* Push instance.method and instance; false if there's no such method. */
    bool PushMethod(lua_State* L, char const* method) const {
      if (!instance || instance->state != L)
        return false;
      lua_getref(L, instance->ref);
      lua_getfield(L, -1, method);
      if (!lua_isfunction(L, -1)) {
        lua_pop(L, 2);
        return false;
      }
      lua_insert(L, -2);
      return true;
    }

    bool Call(char const* method, Widget const& self, Data const* data, int nresults) const {
      lua_State* L = gL;
      if (!L || !PushMethod(L, method))
        return false;
      Push(L, Type_Get<Widget>().t, &self);
      int nargs = 2;
      if (data) {
        Push(L, Type_Get<Data>().t, data);
        nargs++;
      }
      return Luau_Call(nargs, nresults);
    }

    void CaptureFocus(Widget const& self) { Call("CaptureFocus", self, nullptr, 0); }
    void Create(Widget const& self) { Call("Create", self, nullptr, 0); }
    void Destroy(Widget const& self) { Call("Destroy", self, nullptr, 0); }
    void PostDraw(Widget const& self) { Call("PostDraw", self, nullptr, 0); }
    void PostPosition(Widget const& self) { Call("PostPosition", self, nullptr, 0); }
    void PostUpdate(Widget const& self) { Call("PostUpdate", self, nullptr, 0); }
    void PreDraw(Widget const& self) { Call("PreDraw", self, nullptr, 0); }
    void PrePosition(Widget const& self) { Call("PrePosition", self, nullptr, 0); }
    void PreUpdate(Widget const& self) { Call("PreUpdate", self, nullptr, 0); }

    void Receive(Widget const& self, Data const& data) {
      Call("Receive", self, &data, 0);
    }

    void CreateChildren(Widget const& self, Vector<Widget>& children) {
      lua_State* L = gL;
      if (!Call("CreateChildren", self, nullptr, 1))
        return;
      if (lua_istable(L, -1)) {
        int count = lua_objlen(L, -1);
        for (int i = 1; i <= count; ++i) {
          lua_rawgeti(L, -1, i);
          Box* box = ToBox(L, -1);
          if (box && box->type == Type_Get<Widget>().t)
            children.push(*(Widget*)BoxData(box));
          else
            printf("LUAU ERROR: CreateChildren entry %d is not a Widget\n", i);
          lua_pop(L, 1);
        }
      }
      lua_pop(L, 1);
    }

    void GetHash(Widget const& self, HashT& out) {
      if (!Call("GetHash", self, nullptr, 1))
        return;
      if (lua_isnumber(gL, -1))
        out = (HashT)lua_tonumber(gL, -1);
      lua_pop(gL, 1);
    }

    void GetName(Widget const& self, String& out) {
      if (!Call("GetName", self, nullptr, 1))
        return;
      if (lua_isstring(gL, -1))
        out = lua_tostring(gL, -1);
      lua_pop(gL, 1);
    }

    /* Returns a Vec4f: inner x, inner y, outer x, outer y. */
    void GetPadding(Widget const& self, V4& out) {
      if (!Call("GetPadding", self, nullptr, 1))
        return;
      Box* box = ToBox(gL, -1);
      if (box && box->type == Type_Get<V4>().t)
        out = *(V4*)BoxData(box);
      lua_pop(gL, 1);
    }
  };
}

FreeFunction(Widget, Widget_Luau,
  "Make the Luau object 'instance' a component of 'widget': its methods receive the widget's events",
  Widget, widget,
  Data, instance)
{
  if (instance.type != LuauValueType()) {
    printf("ERROR: Widget_Luau expects a Luau table, got %s\n",
      instance.type ? instance.type->name.c_str() : "nothing");
    return widget;
  }
  Reference<WidgetLuau> component = new WidgetLuau;
  component->instance = *(LuauValue const*)instance.data;
  widget->Add(component);
  return widget;
}

FreeFunction(Widget, Luau_CreateWidget,
  "Return Create('arg') of the Luau module 'module' (\"@lt/Path\"), a widget",
  String, module,
  Data, arg)
{
  lua_State* L = Luau_GetState();
  Widget result;
  if (Luau_Require(module)) {
    lua_getfield(L, -1, "Create");
    lua_remove(L, -2);
    Push(L, Type_Get<Data>().t, &arg);
    if (Luau_Call(1, 1)) {
      Box* box = ToBox(L, -1);
      if (box && box->type == Type_Get<Widget>().t)
        result = *(Widget*)BoxData(box);
      else
        printf("LUAU ERROR: %s Create did not return a Widget\n", module.c_str());
      lua_pop(L, 1);
    }
  }
  return result ? result : Widget_Create();
}

bool Luau_IsValue(Data const& value) {
  return value.type == LuauValueType();
}

namespace {
  /* Push script.method and script; false if there's no such method. */
  bool PushScriptMethod(lua_State* L, Data const& script, char const* method) {
    LuauValue const& value = *(LuauValue const*)script.data;
    if (!value || value->state != L)
      return false;
    lua_getref(L, value->ref);
    lua_getfield(L, -1, method);
    if (!lua_isfunction(L, -1)) {
      lua_pop(L, 2);
      return false;
    }
    lua_insert(L, -2);
    return true;
  }
}

bool Luau_ObjectScriptUpdate(Data const& script, Data const& object) {
  lua_State* L = gL;
  if (!L || !PushScriptMethod(L, script, "Update"))
    return false;
  Push(L, Type_Get<Data>().t, &object);
  if (!Luau_Call(2, 1))
    return false;
  bool alive = !(lua_type(L, -1) == LUA_TBOOLEAN && !lua_toboolean(L, -1));
  lua_pop(L, 1);
  return alive;
}

void Luau_ObjectScriptReceive(Data const& script, Data const& object, Data const& message) {
  lua_State* L = gL;
  if (!L || !PushScriptMethod(L, script, "Receive"))
    return;
  Push(L, Type_Get<Data>().t, &object);
  Push(L, Type_Get<Data>().t, &message);
  Luau_Call(3, 0);
}

String Luau_GenerateDefinitions() {
  InitKinds();
  DefinitionWriter writer;
  return writer.Generate();
}

bool Luau_WriteDefinitions(char const* path) {
  std::ofstream file(path, std::ios::binary);
  if (!file)
    return false;
  file << Luau_GenerateDefinitions();
  return (bool)file;
}

lua_State* Luau_GetState() {
  if (!gL)
    gL = CreateState();
  return gL;
}

void Luau_Reset() {
  if (!gL)
    return;
  lua_close(gL);
  gL = nullptr;
  /* Cached dispatcher closures belonged to the old state. */
  for (std::list<Candidates>::iterator it = GetCandidateStore().begin();
       it != GetCandidateStore().end(); ++it)
    it->closureRef = 0;
}

bool Luau_HasModule(String const& module) {
  std::ifstream file(ModulePath(module).c_str());
  return (bool)file;
}

bool Luau_Call(int nargs, int nresults) {
  lua_State* L = Luau_GetState();
  int base = lua_gettop(L) - nargs;
  lua_pushcfunction(L, Traceback, "traceback");
  lua_insert(L, base);
  int status = lua_pcall(L, nargs, nresults, base);
  lua_remove(L, base);
  if (status != LUA_OK) {
    printf("LUAU ERROR: %s\n", lua_tostring(L, -1));
    fflush(stdout);
    lua_pop(L, 1);
    return false;
  }
  return true;
}

bool Luau_Require(String const& module) {
  lua_State* L = Luau_GetState();
  lua_getglobal(L, "require");
  lua_pushlstring(L, module.data(), module.size());
  return Luau_Call(1, 1);
}
