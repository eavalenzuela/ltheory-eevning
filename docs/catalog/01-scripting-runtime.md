# 01 — LTSL Scripting Runtime + Reflection/Type System

Scope: `src/liblt/LTE/Expression/`, `LTE/Function/`, `LTE/Type/`, `LTE/ScriptAPI/`, `src/liblt/CodeGen/`, and the top-level `LTE/` files for the script/reflection core (Script, Expression, Type, Data, AutoClass, Function, DeclareFunction, StringList, Tokenizer, LTSL, Serializer, etc.).
Size: about 16k lines of C++ in total. That is ~2.9k in Expression/, ~2.8k in ScriptAPI/, ~9k in the core headers/sources (≈3.7k of that is macro-generated `AutoClass_Generated.h` / `Function_Generated.h` / `DeclareFunction.h`), ~0.5k in Function/ and ~0.4k in Type/.
The scripts that run on it: 141 `.lts` files, ~10.5k lines, in `resource/script/`.

Everything here comes from reading the code. Where something is inferred and not verified, it is marked **(unverified)**.

---

## 1. Overview

LTSL ("Limit Theory Scripting Language") is a small **statically-typed language with indentation-based blocks**, interpreted by walking a tree. Underneath it is a **runtime reflection system** that is built into every engine type through macros. The two halves are:

1. **Reflection.** Every C++ type gets a `Type` object (`TypeT`) holding its name, size, alignment, allocate/construct/assign/destruct function pointers, a field mapper (visitor), implicit conversions, aliases and member functions. Every C++ function exposed to scripts gets a `Function` object holding its name, parameter `Type`s, return `Type` and a uniform thunk `void call(void** args, void* ret)`. Both live in global name → object registries that fill up during static initialisation. `Data` is a type-erased owning value (`Type` + heap pointer). The same metadata drives binary **serialization** (`Serializer.cpp`) and debug printing.
2. **The LTSL compiler/interpreter.** Source text becomes an S-expression tree (`StringList`), then infix/dot rewrites are applied, then the tree is compiled into a typed `Expression` tree with overloads resolved at compile time, and that tree is evaluated against a register array of `void*`. Script `type`s become real runtime `Type`s with field layout, so script structs and native structs mix freely and can be passed to C++ as `Data`.

The engine calls into scripts through `ScriptFunction_Load("Path/To/Script:Function")->Call(...)`. Scripts call into the engine through any function registered with `FreeFunction` / `DefineFunction`, which is about 800 functions spread across the whole engine, not only `ScriptAPI/`.

---

## 2. Architecture

### 2.1 Pipeline: text to execution

```
 .lts file ──(Location_Script)──► String
   │  StringList_Create  (StringList.cpp + Tokenizer.h)
   ▼  indentation → nesting; whitespace-separated atoms; (...) → sublists; "..." literals
 StringList tree  (StringListAtom | StringListList)  — no line numbers kept
   │  LTSL_ApplyRewrites  (LTSL.cpp)
   ▼  a.b.c → (c (b a));  infix binary ops → prefix, by precedence table
 Rewritten StringList
   │  Expression_Compile(list, CompileEnvironment)  (Expression.cpp dispatcher)
   ▼  keyword forms / native call / script call / field access / constructor / conversion / constant
 Expression tree  (ExpressionT subclasses, pooled; each knows its static Type)
   │  ScriptFunctionT::Call → expression->Evaluate(void* ret, Environment&)
   ▼
 Execution: Environment.registers = Vector<void*> (args + locals), base offset per frame
```

* **Script loading** (`Script.cpp`): `Script_Load(name)` caches by name in a global `Map<String, Script>`. It inserts the new script into the cache *before* compiling it, so a script that is already being compiled is visible (half-built) to scripts it loads. `ScriptT::Reload()` hashes the file and returns early if the hash is unchanged. Otherwise it clears functions/types/deps, parses, rewrites, and compiles every top-level form. **Only `function` and `type` declarations at top level have any effect.** Other top-level expressions compile but are never evaluated, and a top-level `var` is an error ("not eligible for variable binding").
* **Entry points** (`Script.h`): `Script_Load`, `Script_Reload`, `Script_ClearCache`, `ScriptFunction_Load("Script:Fn")`, `ScriptType_Load("Script:Type")`. `ScriptFunction_Load` also calls `Script_Reload` (`#define AUTORELOAD 1`, Script.cpp:17,188).
* **Calling from C++** (`ScriptFunction.h`): `fn->Call(ret, p0, p1, p2)` is typed and asserts with `Type_Get<T>`. `fn->VoidCall(ret, DataRef...)` is untyped, asserts on `DataRef.type`, and allocates the return value if `ret` is null. Each call from C++ builds a fresh `Environment`.
* **Launcher** (`src/launch/launch.cpp`): `Script_ClearCache()`, then `ScriptFunction_Load("App/<app>:Main")`. It requires `Main`'s return type to carry a `ScriptType` in its aux data. It constructs an instance of that type, evaluates `Main` into it, then calls `Initialize(instance)` once and `Update(instance)` every frame. **F5 calls `Launch()` again**: the cache is cleared, every script is recompiled from scratch, and a new app instance is created. All script state is lost (this is a restart, not a state-preserving hot swap).

### 2.2 Compile dispatch (Expression.cpp:21–152)

For an **atom**, these are tried in order and the first non-null result wins: local variable → `ref` alias → **native** zero-arg function → **script** zero-arg function → type name (default-constructed value) → literal constant.

For a **list** whose head is a keyword: `#` (comment, gives null), `@`, `address`, `block`, `call`, `cast`, `desc`, `deref`, `for`, `function`, `if`, `list`, `ref`, `set`/`=`, `static`, `switch`/`?`, `type`, `var`, `while`.

Otherwise the order is: **native function call** → **script function call** → field access `(field obj)` → pointer field access → constructor `(Type args…)` → explicit conversion `(Type expr)` → if the list has one element, compile that element → error.

Consequences:
- A native function always shadows a script function with the same name and compatible arguments, and a native or script function shadows a field with the same name.
- Calls are bound at compile time to a specific `Function` / `ScriptFunction` object.

Method-call flattening: when a list's head is itself a 2-element list, `((Method obj) a b)` is flattened to `(Method obj a b)` (FunctionCall.cpp:208, ExpressionCall.cpp:110). Combined with the dot rewrite, this makes `obj.Method a b` work.

### 2.3 Runtime model

* `Environment { uint base; Vector<void*> registers; }`. Every variable is a `void*` to heap storage.
* A local is a register index assigned at compile time (`CompileEnvironment::Allocate`). `ExpressionDeclareLocal` heap-allocates (`type->Allocate()` = `new T`) and pushes the pointer. `ExpressionBlock` frees its locals in reverse order at block exit.
* Script call (`ExpressionExpressionCall`): for each argument, an **lvalue is passed by address** and an rvalue is evaluated into a fresh heap temporary. All are pushed, `base` moves, the body is evaluated into the caller's return slot, then everything is popped/freed. **Script parameters are effectively by-reference**: assigning to a parameter changes the caller's variable when the argument was a variable.
* Native call (`ExpressionFunctionCall`): the same lvalue/rvalue logic builds a `void*[]` (a **mutable member array of the expression node**, `argStack`), then calls `function->call(args, ret)`. The thunk does `*(RT*)ret = fn(*(T0*)args[0], …)`, so it *assigns* into an already-constructed return slot. Native "in-place" operators (`+=`, `++`) write through `const&` by casting away const (e.g. `Int_AddInPlace`, ScriptAPI/Int.cpp).
* Return value is the value of the **last expression in the body**. There is no `return`, `break` or `continue`.
* Temporaries: every non-final statement of a block whose type is allocatable, every rvalue argument, every conversion, and every field access on an rvalue goes through `new T`/`delete`. Even an integer literal argument is heap-copied on every evaluation.

### 2.4 Reflection / type system

| Piece | File | What it does |
|---|---|---|
| `TypeT` / `Type` | Type.h/.cpp | Intrusively ref-counted type descriptor: `name, size, alignment, base, GUID, pointer` plus fn-ptrs `allocate, assign, castInt, castReal, construct, deallocate, destruct, mapper, toString`. Extra data (aux `Data`, aliases, derived types, conversions, fields, functions, pointee type) is hidden in a `TypeImpl` behind the public struct (a manual pimpl done with a cast). |
| `Type_Create(name,size)` | Type.cpp | Pushes to the global type list and sets `typeMap[name]`. **Last writer wins for a name.** |
| `Type_Get<T>()` | Type.h | Dispatches through ADL `_Type_Get(T const&)`. Storage is `Type_GetStorage<T>()`, a function-template static local. Unknown types silently become `"unknown type"` (Type.h `#if 1 /* Allow unknown types */`). |
| `MAKE_DEFAULT_REFLECTION` / `DefineMetadata` / `DefineMetadataInline` | Type.h | Generate `_Type_Get` for primitives / classes (the class version adds `mapper = T::MapFields`, `base`, `FillMetadata`). |
| `AUTOMATIC_REFLECTION_PARAMETRIC1/2` | Type.h | Templates: the name becomes `"Vector<" + T->name + ">"`. Used by Vector, Array, List, Reference, Pointer, AutoPtr, Distribution. |
| `AutoClass(Name, T0,n0, …)` / `AutoClassDerived(Name, Base, …)` | AutoClass.h + AutoClass_Generated.h | Struct generator, up to 16 fields: members, a field-wise constructor, `GetX()` getters, `MapFields` visitor (type cached in a `static Type`), `_ToStream`, reflection. This is the main way engine data types are declared. |
| `BASE_TYPE` / `DERIVED_TYPE_EX` / `DERIVED_IMPLEMENT` | BaseType.h | Polymorphic hierarchy: virtual `GetDerivedTypeInfo()`, derived-type registration (`AddDerived`), used by the serializer to save/restore the concrete type of an abstract pointer. |
| `TypeAlias(Src, Alias)` | Type.h | Adds a second name to the type map, e.g. `TypeAlias(V3F, Vec3)`, `TypeAlias(Reference<ThreadT>, Thread)`. This is how scripts name engine types. |
| `DefineConversion(Name, Src, Dst)` | Function.h | Registers an implicit single-step conversion on `Src`. |
| `FreeFunction(RT, Name, "desc", T0,n0, …)` / `VoidFreeFunction` / `…NoParams` | Function_Generated.h | Declares and defines a C++ function plus its `Function` metadata (thunk, param types/names, description). Up to 8 params. Registers under `Name`. |
| `FunctionAlias(Source, Alias)` | Function.h | Appends **the overloads of `Source` registered so far** to the list for `Alias`, e.g. `FunctionAlias(Int_Add, +)`. Operators and short names come only from this. |
| `DeclareFunction(Name, RT, T0,n0…)` (header) + `DefineFunction(Name){…}` (cpp) | DeclareFunction.h | Same idea with an `args` struct (`args.n0`). Up to 12 params. `DeclareFunctionArgBind` also generates an AutoClass `Name_Args`. ~278 uses across the engine. |
| `MemberFunction` / `MEMBERFUNCTION` / `METADATA` | Function_Generated.h, Type.h | Member functions registered when the type's metadata is created. Only `Vector<T>` uses them (`Append`, `Get`, `Set`, `Size`, Vector.h:290–323). |
| `Data` / `DataRef` | Data.h | `Data` = owning, deep-copying (`allocate` + `assign`) type-erased value. `DataRef` = non-owning (type, ptr). `Convert<T>()` errors on type mismatch. The serialization format writes magic + type name + payload. |
| `Field`, `Parameter`, `FieldMapper`, `FieldType` | Field.h, Parameter.h, Type.h | Field descriptor; visitor interface used by `FindField`, `GetField`, `Type_Print`, the serializer and script-type mapping. |
| `Type_Array(elem)`, `Type_Pointer(elem)` | Type/Array.cpp, Type/Pointer.cpp | Runtime-constructed generic types for scripts: `(Array T)` is a type-erased growable array (`ArrayCustom`) with `+=`, `Clear`, `Get`→`T*`, `Remove`, `Size`; `(Pointer T)` is a raw pointer type. Cached per element type. |
| `Function_Create/Find/AddAlias/GetList` | Function.cpp | Global `Map<String, Vector<Function>>` overload sets. |

**Script types.** `Expression_Type` (Expression/Type.cpp) builds a `ScriptTypeT`: fields with offsets, per-field initializer expressions, and a method map. It then `Type_Create`s a real `Type` whose fn-ptrs (`ScriptType_Allocate/Construct/Assign/Destruct/Map/ToString`) walk the fields, and stores the `ScriptType` in `type->GetAux()`. Script objects are therefore **plain value structs**: `malloc`'d, assigned field by field, and deep-copied when wrapped in `Data`. Engine code recognises them by `type->GetAux().IsType<ScriptType>()` and calls methods by name (e.g. `Widget_Custom` looks up `Create`, `CreateChildren`, `PreUpdate`, … in UI/Widget/Custom.cpp:111). This is **structural "interfaces by naming convention"**.

### 2.5 Overload resolution and implicit conversions (FunctionCall.cpp:111–189, Conversion.cpp)

* Candidates are `Function_Find(name)`, filtered by parameter count.
* Each argument whose static type ≠ the parameter type costs 1 and must be convertible by `Expression_Conversion`.
* `Expression_Conversion(src→dst)`: identical type gives a no-op. **`src == Data` is always accepted** (`ExpressionConversionFromData`: at runtime `dst->Assign(source.data, ret)` with **no runtime type check**). `dst == Data` is always accepted (boxing). Otherwise a registered single-step `DefineConversion` is needed. There is no chaining.
* Exactly one match → it is chosen and conversion nodes are inserted. Several matches → the lowest cost wins **only if strictly lower than the runner-up**, otherwise it is ambiguous and returns null. The diagnostic code for "no match" and "ambiguous" is `#if 0`'d out, so the user only sees the generic "failed to compile".
* Script functions (`ExpressionCall`) do not overload: one name per script (or per type) and arguments are converted to the declared parameter types.
* Registered conversions (ScriptAPI): int→double/float/uint/long/llong/bool, uint→int, int32/int64→int, float→double/int, double→float/int, **all numerics and bool → String**, float/int→V2F/V3F/V4F (splat), V3F→V3D, V4F→V4D, Mesh→Geometry, Model→Renderable. Some are **lossy** (float→int, double→float) and are applied silently during overload resolution.

### 2.6 Modules, imports, path resolution

* There is no `import` statement. A cross-script reference is a name containing `:`, written `Path/Script:Name`. It works for functions (ExpressionCall.cpp:122) and for types anywhere a type is expected (`ScriptT::ResolveType`, Script.cpp:77). Example: `ref msg (cast Widget/Messages:MessageAddContextMenu data)` (App/map.lts:24).
* **Relative resolution** (`ResolveRelativePath`, Script.cpp:61): for a script named `A/B/C`, `X:Fn` tries `A/B/X`, then `A/X`, then `X`, and loads the first one that exists. So `widget:Create` in `App/ltheory.lts` resolves to `App/widget.lts`, and `HUD/HUDWidget:Create` in `Widget/HUD.lts` resolves to `Widget/HUD/HUDWidget.lts`.
* Resolution order for a bare type name: the current script's types, then the global `Type_Find` (natives, aliases, **and every script type from every script ever compiled, by name**).
* Cross-script references are recorded in `dependencies`. `Script_Reload(name)` re-hashes and recompiles `name` *and everything it depends on* (not the scripts that depend on it).

### 2.7 Caching

* An in-memory script cache with file-hash change detection (Script.cpp). Note that `ScriptFunction_Load` hashes the file(s) from disk on *every* call because of `AUTORELOAD`.
* Disk caching of script results (`ENABLE_SCRIPT_CACHING`, ScriptFunction.cpp) is `#if 0` (dead).
* The C++ side has `Function/Cached.h` (`Cached`, `DiskCached`), which memoises `Generic<>` functors to `cache/*.bin` through the serializer. This is used by procedural generators and is unrelated to LTSL.
* Expression nodes are `POOLED_TYPE` (pooled allocation). Values are not pooled.
* Constant folding is disabled (`IsConstant` on calls returns `false`, marked `/* TODO */`).

### 2.8 Serialization (Serializer.h/.cpp)

`SaveTo(t, location, version)` / `LoadFrom(t, location, min, max)` walk any reflected type through `mapper`:
- Primitives (no mapper) are raw bytes. `Array<char/uchar>` is a length plus a blob.
- Pointers become resource IDs (shared/cyclic graphs are preserved). For abstract pointees, the derived type name is written and looked up through `GetDerived()`.
- Composites recurse through their fields.

The format is binary and **field-order dependent**, with one global int version and no per-field names or tags. It breaks if fields are reordered. `Data` writes a magic number + type name, and loading resolves the name with `Type_Find`, which works for script types once their script has been compiled. Exposed to scripts as `SaveTo` / `LoadFrom` (ScriptAPI/Data.cpp).

---

## 3. LTSL language reference (as implemented)

### 3.1 Lexical structure and layout

| Rule | Detail |
|---|---|
| Tokens | Separated by **spaces only** at nesting level 0. `(` `)` group. `"..."` is a literal (spaces allowed, `\"` escapes the quote, **no other escape processing**: `\n` stays as backslash-n). `'...'` is also a string *constant*, but the tokenizer does not treat `'` as quoting, so it cannot contain spaces. |
| Lines | Each non-blank line becomes a list of its tokens. A line with a single atom becomes just that atom. |
| Indentation | **Spaces only** (`kTab = " "`). A tab is not indentation. Lines indented deeper than the previous line are appended to that line's list **as extra trailing elements**, one per child line. This is the only block syntax; it also passes "big" arguments (see Button.lts:12–15). |
| Comments | A line whose first token is exactly `#`. `#foo` is *not* a comment. Trailing `# ...` after code is *not* supported (it becomes extra arguments). Because the indented children of a `#` line belong to it, **`#` on a header line comments out its whole indented block** (App/widget.lts:31–44; App/observatory.lts:57 `# desc "Miners"`). |
| Line endings | LF only. A `\r` causes the tokenizer to skip the following character as well (Tokenizer.h `ReadTokenInPlace` advances twice on "ignore" chars), so CRLF files would merge lines. All shipped scripts are LF. |
| Literals | `123`, `-5`, `+5` give `int`. One `.` gives `float` (`0.5`, `-0.75`, `5.`). There is no `double` literal and no exponent form (`1e5` fails). `true` / `false`. `"string"`. |

### 3.2 Rewrites (LTSL.cpp)

**Dot sugar.** Any non-numeric atom without quotes that contains `.` is split: `a.b.c` → `(c (b a))`. So `obj.field` is field access, `obj.Method` is a 0-arg call, `obj.Method x y` is `(Method obj x y)` after flattening, `i.++` is `(++ i)`, `flag.!` is `(! flag)`, and `self.size.y` is `(y (size self))`.

**Infix operators**, applied left to right inside *each list*, highest precedence first:

| Prec | Operators |
|---|---|
| 1 | `^` |
| 2 | `*` `/` |
| 3 | `+` `-` |
| 4 | `<` `>` `<=` `>=` |
| 5 | `==` `!=` |
| 6 | `&&` |
| 7 | `\|\|` |
| 8 | `=` `+=` `-=` `*=` `/=` |

All of them are **left-associative**, including `=` and `^`. Operators **bind tighter than prefix application**:
- `Mod i + 1 nodes.Size` → `(Mod (+ i 1) (Size nodes))` (App/loading.lts:25).
- `ship.SetPos station.GetPos + 10000.0 * rng.Sphere` → `(SetPos ship (+ (GetPos station) (* 10000.0 (Sphere rng))))` (App/ltheory.lts:31).
- Footgun: `x = Foo a` → `((= x Foo) a)`, which fails. Write `x = (Foo a)` (App/ltheory.lts:15).

Operators are simply names of overloaded native functions (`FunctionAlias(Int_Add, +)`). Unary operators are prefix functions: `!`, `++`, `--`. **There is no unary minus and no `%`.** Use `-1.0 * x` (App/loading.lts:41) and `Mod a b`.

### 3.3 Forms

| Form | Syntax | Notes / example |
|---|---|---|
| Call native/script | `Fn a b` / `(Fn a b)` | Prefix. Zero-arg calls are bare atoms: `camera = Camera_Create`. Cross-script: `Widget/HUD:Create player` (ltheory.lts:59). |
| Method call | `obj.Method a b` | For a script type, the method is looked up in the type of `obj` at compile time; otherwise it is an ordinary overload search with `obj` as the first argument. |
| Field access | `obj.field` | Works on native AutoClass fields and script fields. On pointer types it dereferences one level. |
| `var name expr` | `var sum 0` | Type is **inferred** from `expr` (there is no type annotation). Only valid directly inside a block. `var l List`, `var icon Icon` default-construct. Indented initializers work (`var c` followed by an indented `switch`, Button.lts:19–22). |
| `ref name expr` | `ref node (nodes.Get i)` | Alias to an lvalue, or to the pointee of a pointer-typed expr (loading.lts:24). |
| `static name expr` | `static self` + indented `block …` | Evaluated once per **expression node** (it persists across calls and is shared by all instances when used in a method; it resets on recompile). Used for memoised icons (Icons.lts:1–7). |
| Assign | `x = e`, `x += e`, `set x e` | `=`/`set` is the built-in assign with implicit conversion. `+=` etc. are native in-place functions (they need an lvalue; on a converted temp they are a silent no-op). |
| `if pred body…` | `if (Mod n i) == 0` + indented body; or inline `if Key_H.Down dt *= 20.0` (ltheory.lts:82) | **There is no else.** Type is void. |
| `switch` / `?` | `switch` followed by indented `pred body…` cases and `otherwise body…` | Cond-style: first true predicate wins. Has a value if every case and `otherwise` have the same type, else void. `?` is inline: `(? (cond a) (otherwise b))` (Button.lts:9, Icons.lts:68). Mixed types such as `1` vs `0.5` make it void, so `var x (? …)` then fails. |
| `for v init pred step body…` | `for i 0 i < n (++ i)` / `for it coll.Iter it.HasMore it.Advance` | Desugars to `{var v init; while pred {body; step}}`. Iterator idiom: ltheory.lts:25. |
| `while pred body…` | `while (! x.IsFinished) 0` | An empty body does not compile, so scripts use a dummy `0` (threads.lts:11–12, ltheory.lts:37). |
| `block e…` | | A block expression whose value is the last expression. |
| `desc "label" e…` | `desc "Battle"` (observatory.lts:29) | A block that ignores its first element (a description). |
| `cast T e` | `cast Int thread.GetResult` | Forces `Expression_Conversion`. **The safe way to unbox `Data`** (see bug iii). |
| `(T e)` | `(Float x)` | Conversion, but only if no function named `T` matches first. |
| Constructor | `(TypeName a b c)` / bare `TypeName` | Positional fill of fields **without defaults**. The argument count must equal exactly the number of such fields (Button.lts:45). A bare name gives the default value. Native AutoClass types need all their fields. |
| `@ e…` | `@ "Result: " x` | Prints the values concatenated with no separators, plus a newline. |
| `address e` / `deref e` | `deref (ships.Get i)` (observatory.lts:55), `deref contents` (TextField.lts:13) | Pointer creation and dereference. |
| `call dataObj Method args…` | | Dynamic dispatch on a `Data` holding a script object (unused in the scripts; the return value is discarded and it works on a copy, see §6). |
| `list a b c` | | Quotes its arguments as a `StringList` constant (unused). |
| `function RT Name (T1 a T2 b) body…` | `function Bool IsPrime (Int n)` (prime.lts:1) | **`RT` is never read.** The return type is whatever the body's last expression has (e.g. 336 functions declare `Void`, which is not a registered type). Parameters come in `Type name` pairs. **The function exists only after its body compiles**: no recursion, and every callee in the same script must be defined *earlier* in the file. |
| `type Name` + indented fields/methods | Field: `Type name [default]`; method: nested `function` | Button.lts:1–5. Methods get an implicit first param `this`, and fields are in scope as bare names (`focus = true`, Button.lts:28). Methods are compiled after all fields, in order, so a method can only call methods defined above it (`this.Other`). No inheritance, no nested types. A field default is compiled in an empty environment and runs at every construction. |
| Generics | `Vector<Reference<RenderPassT>>`, `(Array Object)`, `(Pointer T)` | `X<...>` is just a type *name* string that must exactly match a type the C++ side has already instantiated and registered (ltheory.lts:53). Two-parameter names contain `", "`, a space, so they cannot be written in LTSL. `Array`/`Pointer` are real script-side generic constructors. |

### 3.4 Worked example (real code)

```lts
type Button                                  # Widget/Button.lts:1
  Data onPress
  String text
  Float size
  Bool focus false                           # field with default

  function Void PostUpdate (Widget self)     # 'Void' is decorative
    if self.focusMouse && (! focus)          # (&& (focusMouse self) (! focus))
      focus = true                           # bare field name = this.focus
      self.Rebuild
      Sound_Play "ui/hover.wav" 0.008

function Widget Create (Data onPress String text Float size)
  Components:CaptureMouse                    # relative cross-script call
    Components:Padding (Vec2 6 6) 6          # indented child = last arg
      Stack
        Custom Widget                        # native Widget_Custom(Widget, Data)
          Button onPress text size           # constructor; boxed to Data
```

The application pattern: `function Data Main ()` returns a script type instance whose `Initialize`/`Update` the launcher drives (App/ltheory.lts:85–88 → App/widget.lts:1–52).

### 3.5 Quirks and footguns (language level)

- **Silent drops.** A statement that fails to compile is removed from its block and compilation carries on. Errors are printed only for *lists that fall through every handler*, once per function (`hasErrors`). Failures inside keyword forms (`var x typo`, `x = typo`, `if typo …`, `cast`) usually print **nothing**, because atom failures are never reported and keyword handlers return null directly. No line numbers are available anywhere (StringList keeps none).
- **Data is a wildcard.** Data converts to anything at compile time (see §6 iii), so a native with a `Data` parameter can capture calls meant for other overloads or script methods of the same name.
- `int / int` resolves to `Int_DivideFloat` and returns **float** (`Int_Divide` has no alias).
- Mixing an `int` and a `float` in one operator call is often **ambiguous** (`Int_Add` with float→int and `Float_Add` with int→float both cost 1) and fails silently. Scripts write `2.0 * Pi` and not `2 * Pi`.
- Lossy implicit conversions (float→int, double→float) can be picked silently.
- Variables shadow zero-arg functions. Native functions shadow script functions. Functions shadow fields with the same name.
- Script type names are global for `Type_Find`, `IsType "Name"` and deserialization. There are two `App` types (App/ltheory.lts and App/widget.lts), and the last one compiled owns the name.
- Value semantics: `var b a` copies a script struct. Passing to C++ as `Data` deep-copies it. Script parameters alias the caller's variables.

---

## 4. File inventory

Status key: **complete** = works as used; **partial** = works but has TODOs or missing features; **stub** = skeleton; **dead** = not compiled in or not referenced; **debug** = debug-only.

### 4.1 Front end and script management

| File | Purpose | Status |
|---|---|---|
| Tokenizer.h | Char-level reader helpers (lines, tokens, delimited, indentation) | complete (CR double-skip bug) |
| StringList.h/.cpp | S-expression tree + indentation parser for `.lts` | complete (no line info) |
| LTSL.h/.cpp | Dot and infix-operator rewrites | complete |
| StringTree.h/.cpp | A separate indentation tree format (value + children + line numbers) for data files; exposed as `StringTree_*` | complete |
| Script.h/.cpp | Script object, cache, reload, path resolution, `ScriptFunction_Load` / `ScriptType_Load` | partial (reload staleness, AUTORELOAD cost) |
| ScriptFunction.h/.cpp | Compiled function + C++ call helpers; dead disk-cache block | complete / dead block |
| ScriptType.h | Script struct metadata (fields, initializers, methods, runtime Type) | complete |
| Environment.h | Runtime `Environment` + `CompileEnvironment` / `Variable` | complete |
| Expression.h/.cpp | `ExpressionT` interface + compile dispatcher | complete |
| Expressions.h | Factory declarations for all nodes | complete |

### 4.2 Expression nodes (`LTE/Expression/`)

| File | Node(s) / form | Status |
|---|---|---|
| Access.cpp | `obj.field` | complete |
| Address.cpp | `address` | complete |
| Array.cpp | `Expression_Array` | **stub/dead** (returns null, never dispatched) |
| Assign.cpp | `=` / `set` | complete |
| Block.cpp | blocks, local lifetime | complete |
| Cast.cpp | `cast` | complete |
| Constant.cpp | literals | complete (no double / exponent / escapes) |
| Constructor.cpp | `(Type args)` / bare `Type` | partial (re-evaluates defaults; reads out of bounds before its bounds check) |
| Conversion.cpp | implicit/explicit conversions, Data boxing/unboxing | complete (GetLValue null fix this session; unchecked unbox) |
| Declare.cpp | `var`, `ref`, `static` | complete |
| Dereference.cpp | pointer field access, `deref` | partial (no pointer-to-pointer, TODO) |
| DynamicDispatch.cpp | `call` | partial (works on a copy, discards the result; unused) |
| ExpressionCall.cpp | script function / method call | partial (TODO "unified lookup") |
| For.cpp | `for` | complete |
| Function.cpp | `function` definition | partial (no recursion, return type ignored, native wrapper `#if 0`) |
| FunctionCall.cpp | native call + overload resolution | complete (diagnostics `#if 0`; non-reentrant `argStack`) |
| If.cpp | `if` | complete (no else) |
| List.cpp | `list` quoting | complete (unused) |
| Noop.cpp | empty function body | complete |
| Print.cpp | `@` | complete |
| Reference.cpp | use of a `ref` / `static` name | complete |
| Switch.cpp | `switch` / `?` | complete |
| Type.cpp | `type` definition, script Type fn-ptrs | partial (wrong padding math, leaks a Type per compile) |
| Variable.cpp | use of a local / field | complete |
| While.cpp | `while` | complete |

### 4.3 Reflection, function registration, values

| File | Purpose | Status |
|---|---|---|
| Type.h/.cpp | Type descriptor, registry, aliases, printing, default reflection macros | complete (identity flaw on Windows) |
| Types.h, Type/Array.cpp, Type/Pointer.cpp | Script-constructed `Array<T>` / `T*` | partial (Array unusable after it is emptied, see §6) |
| BaseType.h | Polymorphic base/derived reflection | complete |
| AutoClass.h, AutoClass_Generated.h | Struct + reflection generator (≤16 fields) | complete (generated) |
| Field.h, Parameter.h | Field and parameter descriptors | complete |
| Function.h/.cpp | Function registry, `DefineConversion`, `FunctionAlias` | complete |
| Function_Generated.h | `FreeFunction` / `MemberFunction` macro family (≤8 params) | complete (generated) |
| DeclareFunction.h | `DeclareFunction` / `DefineFunction` / `ArgBind` (≤12 params); "DeclareFunction.py" generator not in repo **(unverified: not found)** | complete (generated) |
| Call.h | Generic `Call(fnptr, void**, void*)` helpers | complete; included only by LTE.h, effectively unused |
| Data.h | `Data` / `DataRef` | complete |
| TypeTraits.h | Deref / return-type traits for templates | complete |
| Mutable.h | `Mutable()` const_cast helper (used everywhere) | complete |
| Enum.h, XEnum.h | Enum wrapper with string names; X-macro enum generator | complete |
| Serializer.h/.cpp | Binary reflection-driven save/load | complete |
| Static.h/.cpp | Global `name → Data` registry (`nextObjectID`, `nextItemID`) | complete ("TODO static serialization") |
| Generic.h + Function/{Bind,Cached,Call,Cast,FreeFn,Lookup,MemberFn,Pointer,Value}.h | C++ hashable, type-erased functor/thunk library (`Generic<T,Arg>`, `Cached`, `DiskCached`, binders); used by ShaderInstance, generators and shading models (81 uses) | complete (not LTSL) |
| Function/Wrapper.h | `WrapperT` used by Cached/Generic | complete |
| Config.h/.cpp | `config.txt` key=value settings (`category` ignored) | partial — `Config_Set` signature mismatch (header `String const&`, cpp `String&`), so it would fail to link if anything called it; nothing does |
| Module.h/.cpp | Global per-frame module list (`Module_UpdateGlobal` from Program.cpp) | complete |
| Loader.h/.cpp | Deferred one-shot "on load" callbacks run on the first module update | complete |
| Package.h/.cpp | Named function/type namespaces | **dead** (never used) |
| Pushable.h | Static stack-of-instances mixin | **dead** (unused) |
| Singleton.h | Lazy singleton template | **dead** (unused) |
| DataStack.h | Bump allocator for typed temporaries (an unrealised optimisation for the interpreter) | **dead** (forward-declared only) |
| CodeGen/CodeBlock.h, CodeGen/Common.h | C++ code-emission helper | **dead** (never included; `CodeBlockT Indent(){return this;}` would not compile) |
| `ExpressionT::Emit` (all nodes) | LTSL→C++ transpile experiment, used only by `old/ltconsole` | **debug/dead**, partial (many nodes return "") |

### 4.4 ScriptAPI (`LTE/ScriptAPI/`, 27 files, ~322 functions)

| File | Category | Status |
|---|---|---|
| Bool, Int, Float, Double | scalar math, comparisons, conversions, operators | complete (duplicate `int→bool` conversion registered as "uint_to_bool") |
| V2, V3, V4 | vector math (f and d variants for V3/V4) | complete (V2 `Distance` alias broken: defined as `Vec3_Distance`, aliased from a nonexistent `Vec2_Distance`) |
| String, StringList, StringTree | strings, parse trees | complete |
| List | heterogeneous `List` of `Data` | complete |
| Data | Data introspection, binary save/load | complete |
| OS | directory listing, file tests, `File_Read` | complete |
| Thread | run a script method on a worker thread | partial (thread-safety, see §6) |
| Timer | timers | complete (`Timer` leaks a raw `new`) |
| Keyboard | `Key_*` constants, Down/Pressed/Released, modifiers, text input | complete |
| RNG | MT RNG, Float/Int/Gaussian/Sphere/Direction/Vec | complete |
| Expression, Grammar | `Compile` (no way to evaluate from script), procedural text grammar | partial |
| Mesh, Model, PlateMesh, Renderable, Renderer, ShaderInstance, Texture2D, Ray | thin graphics bindings | complete (cover only a small part; most graphics bindings live elsewhere) |

---

## 5. Script API surface

The API scripts can call is the union of every `FreeFunction` (~539, of which 322 are in ScriptAPI/) and every `DeclareFunction`/`DefineFunction` (~278) in the engine, plus `Vector<T>` members and `Array` built-ins. Outside ScriptAPI, the bindings live mostly in `Component/*.cpp` (object components: Cargo, Market, Motion, Tasks, …), `Game/` (Object_*, Item_*, Task_*, RenderPass_*, Player_*), `UI/` (Widget_*, Glyph_*, Compositor_*), `LTE/SDF`, `Module/`. Those belong to other catalogs.

| Category | Representative names (aliases in brackets) |
|---|---|
| Operators | `+ - * / ^ += -= *= /= ++ -- == != < > <= >= && \|\| !` (overloaded across Int/Float/Double/V2/V3/V4/String/Array/List) |
| Scalar math | `Abs Clamp Min Max Mod Sign Floor Ceil Round Fract Sqrt Pow2 Pow4 Exp ExpDecay Log Sin Cos Tan Atan Mix Saturate`, `Pi Pi2 Pi4 Pi6 2Pi`, `Int_Random`, `Float_Random`, `Double_Random` |
| Vectors | `Vec2 Vec3 Vec3d Vec4` constructors, `Dot Cross Length Normalize Distance Spherical Polar Cylinder MinComponent`, `RNG_*` vector sampling |
| Strings | `+` concat (all numerics auto-convert), `Length Substring Contains Split SplitLines UpperCase LowerCase CapitalCase ToInt ToFloat GetHash Get Pop IsEmpty` |
| Containers | `List`, `+=`, `Get Set Size Clear Shuffle GetRandom` (List of Data); `Vector<T>` `Append Get Set Size`; `(Array T)` `+= Get Remove Size Clear` |
| Data / reflection | `IsType "Name"`, `NotEmpty IsNull IsNotNull Data_None`, `SaveTo LoadFrom` (binary), `cast` |
| OS / files | `ListDir IsDirectory IsFile File_Read` |
| Threads | `Thread_Create obj "Method"`, `IsFinished`, `GetResult` (Data) |
| Time | `Timer GetElapsed Reset`; `FrameTimer_Get` (from Module/) |
| Input | `Key_A…` etc., `Down Pressed Released`, `Key_Shift/Control/Alt`, `Keyboard_GetPressed`, `Keyboard_ModifyString` |
| Random | `RNG_MTG seed`, `Float Int Gaussian Exp Angle Sphere Direction Sign Vec2 Vec3` |
| Text generation | `Grammar_Get text rng` |
| Graphics (here) | `Texture2D_Create/CreateHDR`, `GenerateFromShader`, `BeginDrawTo/EndDrawTo`, `SaveTo`, `ShaderInstance Set/SetFloat/…`, `Mesh_Create Center SetOcclusion`, `Model_Create Add`, `PlateMesh Add ReflectX/Y/Z GetMesh`, `Renderer_GetDrawCallCount/PolyCount` |
| Meta | `Expression_Compile` (StringList → Expression, cannot be run from script), `StringList_*`, `StringTree_*` |

There is no generic "list all functions" binding exposed to scripts, but `Function_GetList()` / `Type_GetList()` exist in C++ and every `Function` carries a description string. A self-documenting reference or REPL autocomplete could be generated from them cheaply.

---

## 6. Known bugs, quirks and design flaws

### Established this session (verified against the code)

| # | Issue | Where | Notes |
|---|---|---|---|
| i | **Type identity across module boundaries.** `Type_GetStorage<T>()` is a function-template static in a header, so on Windows the exe and the DLL each get their own `Type` for the same `T` and `==` fails. launch.cpp raw-casts `*(ScriptType*)GetAux().data` instead of `Convert<ScriptType>()`. | Type.h `Type_GetStorage`, launch.cpp | On Linux with default ELF visibility (no `-fvisibility=hidden` in CMakeLists) template statics are normally unified, so this probably does not reproduce here **(unverified)**. The workaround is still in place. The root problem: identity depends on a per-module static rather than the registry by name. |
| ii | **The declared return type is ignored.** `function Data Main ()` returning an `App` reports return type `App`. | Expression/Function.cpp:72 (`returnType = expression->GetType()`; `list->Get(1)` is never read) | This applies to *every* function, so `Void`, `Icon` etc. are documentation only. No check is done. A mismatch shows up only when C++ asserts in `Call<T>` or the launcher's aux check. |
| iii | **`Data` converts to anything during overload resolution.** `(Int someData)` matched `RNG_Int(RNG)` (alias `Int`) because Data→RNG costs 1, then reinterpreted the memory. | Conversion.cpp `Expression_Conversion` (`src == Data` gives FromData with no check) | `(cast Int x)` is the safe idiom. The same hazard hits any 1-overload native whose name matches a script method or conversion name. Even `cast` does no runtime type check, so guard with `IsType`. |
| iv | `ExpressionConversionFromData::GetLValue` dereferenced null for rvalue sources. | Conversion.cpp:71–75 | **Fixed** in commit 88bbac3. |
| v | There is no implicit V3D→V3(F) conversion, only V3F→V3D (and V4F→V4D). | ScriptAPI/V3.cpp, V4.cpp | Double-precision positions must be converted explicitly, and there is no `Vec3d→Vec3` function either **(unverified: none found in ScriptAPI)**. |
| vi | `switch` cases whose body is only a comment log "case statement did not compile" and the case is dropped. | Switch.cpp:128 | The body block contains only `(# …)`, which compiles to null, so the block is null. The same is true for `if`/`while` with empty or comment-only bodies (silently dropped, hence the `0` dummy bodies). |
| vii | You cannot call a method on a parenthesised expression: `(f x).SaveTo "a"`. | StringList.cpp `ParseLine` + LTSL.cpp `RewriteDot` | The token ends at `)`, so `.SaveTo` becomes its own atom and is rewritten as `(SaveTo "")`. Bind to a `var` first. |

### Additional findings

**Correctness**
1. **Script struct padding is wrong.** It uses `padding = size % align` instead of `(align - size % align) % align`, and the final padding has the same mistake (Expression/Type.cpp:182–184, 193). Fields after a `Bool` can be **misaligned**: for example `Bool` then `Reference` puts the pointer at offset 2. This is tolerated on x86, would break SSE or strict-alignment targets, and makes sizes differ from C++.
2. **`Array` cannot be used after it is emptied.** `ArrayCustom::Pop()` sets `type = 0` when the size reaches 0, so the next `+=` dereferences null (Type/Array.cpp `Pop`). The AutoClass copy constructor of `ArrayCustom` is a shallow copy of `buffer`, so it would double-free if it were ever copy-constructed.
3. **`call` (dynamic dispatch) works on a copy.** `Data objectData` deep-copies the object, so mutations are lost, and the return value is discarded (DynamicDispatch.cpp).
4. **Non-reentrant, non-thread-safe nodes.** `ExpressionFunctionCall::argStack` and the `static` value live *in the expression node*. `Thread_Create` runs script code on worker threads that can share nodes with the main thread, which is a data race. Re-entering the same node through a native→script callback overwrites `argStack` before it is freed.
5. **Stale code after reload.**
   - (a) `Script_Reload` recompiles dependencies but not dependents. A dependent keeps calling the *old* `ScriptFunctionT`/`Type` objects (kept alive by refcount).
   - (b) C++ callers cache `static ScriptFunction x = ScriptFunction_Load(...)` (e.g. Game/Object/WarpNode.cpp:252,302), so after F5 / `Script_ClearCache` they keep running the old compile, with old script `Type`s.
6. **A `Type` leaks per compile.** Every `type` declaration `Type_Create`s a new global type on each recompile ("TODO : Type leakage", Expression/Type.cpp:197). Global name collisions overwrite (two `App`s, shown above). `Type_Find`/`Function_Find` use `operator[]`, so every failed lookup inserts an empty entry.
7. **Constructor** reads `initializers[fieldIndex]` before its bounds check (Constructor.cpp:115). Default field initializers are evaluated twice per construction-with-args (once by `ScriptType_Construct`, once by `ConstructorDefault`). That is wasted work, and side effects (RNG) run twice.
8. Script-type method lookup checks name clashes against the *script-level* map (Expression/Function.cpp:26 `env.script->functions[name]`, which also inserts a null entry). As a result, a method cannot share a name with an earlier free function in the same script.
9. A one-word line inside a `type` body (an atom, not a list) crashes the compiler: `sub->Get(0)` returns null and is then dereferenced (Expression/Type.cpp:125).
10. `Expression_Compile(StringList)`, the script-exposed `Compile`, runs with `env.script == null`. Any type resolution then dereferences null.
11. `FunctionAlias` captures only the overloads registered *before* it runs (static-initialisation order). Aliases defined in a different translation unit from some of the source's overloads silently miss them.
12. `Vector<T>::Get` / `List_Get` / `Array Get` / `String_Get` do no bounds checks.
13. Serializer: binary, positional, one global version. Script type layouts change when fields change, which invalidates saved data without any detection.

**Error reporting and tooling**
- No line or column information anywhere. The only message is `'<script>' -- failed to compile (<re-printed s-expr>)` plus a detail trace from re-running the compile with `detail = true`. Only the first error per function is shown. Many failures are silent (§3.5). Overload-mismatch and ambiguity diagnostics exist but are `#if 0`.
- No debugger, no stack traces for scripts (only `FRAME` profiler markers with function names), no REPL (old `ltconsole` is dead), no type annotations on `var`, no recursion, no early return, no `else`/`break`/`continue`.

**Performance hazards**
- Tree-walking interpretation **every frame**: the launcher calls `Update` per frame, and `Widget_Custom` calls up to ~14 script methods per custom widget per frame (`PreUpdate`, `PostUpdate`, `PreDraw`, …). The HUD is built from dozens of such widgets.
- A heap `new`/`delete` per temporary, per rvalue argument and per non-final statement value. Constants are copied on every evaluation. `Vector<void*>` registers. `DataStack.h` (a bump allocator) was clearly meant to fix this and was never wired in.
- `ScriptFunction_Load` re-reads and hashes script files (and their dependencies) on every call because of `AUTORELOAD`.
- Overload resolution and the string-keyed lookups are compile-time only, which is good: runtime dispatch is direct function pointers.

---

## 7. Dependencies

**Uses (from other areas):** core containers and strings (`Vector`, `Map`, `String`, `Reference`/`RefCounted`, `Pool`, `AutoPtr`), `Location` (file IO + hashing), `ProgramLog`, `StackFrame`/`FRAME` (profiler), `Hash`, `OS`, `Thread`/`Job` (ScriptAPI/Thread), math (`V2/V3/V4`, `Math.h`, `RNG`), and rendering types for the graphics ScriptAPI files (Texture2D, ShaderInstance, Mesh, Model, PlateMesh, Renderer).

**Depended on by:**
- **Everything that reflects:** `AutoClass` / `Type_Get` / `Data` / `DefineFunction` / `FreeFunction` are used across the whole engine (Game, Component, UI, LTE). The reflection core is load-bearing for serialization, debug printing and script binding everywhere.
- **Engine → script calls:** `launch.cpp` (app lifecycle); `UI/Widget/Custom.cpp` (script widgets); `Game/Item/*Type.cpp` (procedural generation of ships, stations, turrets, weapons, thrusters, icons via `ScriptFunction_Load`); `Game/Object/{Colony,Ship,Thruster,WarpNode,Region}.cpp` (`Init` hooks); `Game/Player.cpp`, `Wormhole.cpp` (icons); `Component/Scriptable.cpp` (`Object_AddScript`).
- `Static_Get`: Game/Object.cpp, Game/Item.cpp (ID counters). `Module`/`Loader`: Program.cpp, FrameTimer, Scheduler, Profiler, and the Rail/Thruster/Beam/Shield/Pulse loaders.
- All 141 `.lts` scripts.

---

## 8. Assessment for the two goals

### (a) Pushing toward a playable game: keep building on LTSL?

**Viable in the short term, costly in the long term.** The language does what the existing 10.5k lines need: UI composition DSL, procedural generators, app glue. F5 restart-reload is a real productivity win. The problems:

| Gap | Impact | Cheapest fix |
|---|---|---|
| No line numbers, silent statement drops | Typos turn into missing behaviour with no message. This is the #1 productivity drain. | Store line numbers in `StringListAtom`/`StringListList` (the tokenizer already walks lines). Print every failure, not only the first. Turn on the `#if 0` overload diagnostics. Report atom failures inside keyword forms. ~1–2 days. |
| Declared return types ignored; Data wildcard | Wrong-type bugs reach C++ asserts or memory corruption | Resolve and check `RT` (allow `Void`/`Data`). Make Data→T conversion cost more than real conversions and add a runtime `type ==` check in `ConversionFromData`. ~1 day. |
| No recursion, define-before-use, no `else`/`return`/`break` | Awkward code, `0` dummy bodies | Two-pass compile (declare signatures first). Add `else` to `if`. Moderate effort. |
| Alignment bug | Latent memory corruption | One-line formula fix in Expression/Type.cpp. |
| Interpretive overhead per frame | Fine for UI glue; do not put simulation loops in LTSL | Keep hot loops in C++; optionally wire `DataStack` for temporaries. |
| No debugger, REPL or docs | Hard onboarding | Generate an API reference from `Function_GetList()` descriptions; revive a REPL using `Expression_Compile`. |

Recommendation: if the goal is "get the existing game playable", **keep LTSL** and spend a few days on error reporting, return-type checks, Data-conversion safety and the padding fix. Rewriting 141 scripts first would be the wrong order.

### (b) Cross-mapping into a new game: what is worth taking?

| Idea / code | Value | Coupling | Notes |
|---|---|---|---|
| **Reflection core** (Type + field mapper + Data + AutoClass + uniform `void(**,*)` thunk) | High as a *design* | Heavily macro-generated, C++03-era, tied to LTE's `Reference`/`String`/`Vector`; identity relies on template statics | Re-implement with modern C++ (constexpr type IDs, `std::any`-style Data, a visitor for fields) or use an existing library (e.g. a reflection library or codegen). The **single binding definition feeding scripting, serialization and debug-printing** is the idea to keep. |
| **`FreeFunction` binding macro + overload-aware registry** | High | Medium | A uniform ABI makes a generic bridge to *any* VM (Lua/AngelScript) a small, mechanical job: iterate `Function_GetList()`, marshal with `Type` fn-ptrs. |
| **Script types as real runtime Types** | High | Medium | Script structs are indistinguishable from native ones (serializable, printable, storable in C++ `Data`). Duck-typed method lookup by name (`Widget_Custom`) is a neat, low-ceremony extension point. |
| **Indentation-as-arguments syntax** | Medium-high for UI DSLs | Low (the parser is ~140 lines) | Nested widget trees read very well (Widget/HUD.lts). Worth copying in spirit (Lua table constructors, or a small DSL). |
| **Path-relative module resolution (`HUD/Log:Create`)** | Medium | Low | Simple and effective. Easy to reproduce with a Lua `require` searcher. |
| **F5 full-recompile restart** | Medium | Low | Simple; the real "hot reload" would need state migration (serialize the app instance with the reflection system, recompile, reload: the pieces exist). |
| Serializer | Medium | Low-medium | Pointer-graph + derived-type handling is good. Positional, unversioned fields are not; prefer tagged fields. |
| `Generic`/`Cached`/`DiskCached` functor lib | Medium (procedural-gen memoisation) | Low | A hashable lazy thunk plus disk cache is a nice pattern for procedural assets. |
| The interpreter itself | Low | — | Heap-heavy tree-walker with no tooling; do not port it. |

**Modern replacement and porting cost.**
- **Lua/LuaJIT** (via sol2 or a hand-written bridge over `Function_GetList()`): best ecosystem, debuggers, REPL, and real hot reload. Mismatches with LTSL: dynamic typing (native overloads such as `+` across Int/Float/V3 need runtime dispatch on argument type tags in the bridge), reference semantics for tables versus LTSL's value-copied structs and by-reference parameters, and no `Data` casts (they simply disappear). For context, the later Limit Theory rewrite reportedly moved to LuaJIT **(unverified: outside this repo)**.
- **AngelScript**: closest semantic match (static types, overloads, value types, C++-like). The port is more mechanical, but tooling is weaker.
- **Porting ~10.5k lines / 141 files.** The syntax is regular. After `LTSL_ApplyRewrites` each file is an s-expression tree, so a **semi-automatic transpiler** (StringList → Lua) is feasible. The `Emit()` scaffolding shows the author considered this. Type-dependent parts (overload choice, constructors vs calls, field vs call ambiguity) need the compile-time types, so the transpiler should walk the *compiled* Expression tree, not the raw list. Rough estimate **(unverified, judgement)**: 1–2 weeks for a bridge plus transpiler and a first pass, then 1–3 weeks of manual fixing (value-vs-reference semantics, `static` memoisation, Data casts, widget method conventions). Hand-porting would be roughly 3–6 weeks. The C++ callers (`ScriptFunction_Load` sites, `Widget_Custom`, launcher) are a small, well-defined surface, about 20 call sites.
