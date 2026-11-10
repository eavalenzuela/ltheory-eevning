/* luaucheck: type-check the game's Luau scripts against the engine API.

     luaucheck [--defs FILE] [--no-generate] [script.luau ...]

   Generates Luau type definitions for every bound engine function and type
   from the engine's reflection (so they can't drift from the bindings),
   writes them to resource/script/engine.d.luau (or FILE) for editor
   tooling, then checks the given scripts, or every .luau file under
   resource/script, in strict mode. --no-generate checks against an
   existing FILE instead (for debugging the definitions). "@lt/Path" requires resolve to
   resource/script/Path.luau, as at runtime. Exits non-zero on any error.

   Scripts under resource/script/Core, Sim and Tool are the engine-free
   part of the game: they must also run in bin/ltcore, which has no engine.
   They are checked against the built-ins and the Host table only
   (resource/script/host.d.luau), so a call into the engine from there is a
   type error. Everything else sees the engine API and Host. */

#include "Luau/BuiltinDefinitions.h"
#include "Luau/Common.h"
#include "Luau/Frontend.h"

#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

LUAU_FASTINT(LuauTarjanChildLimit)

/* From liblt (src/liblt/Luau/Luau.h); declared here to keep engine headers
   out of this C++17 translation unit. */
bool Luau_WriteDefinitions(char const* path);

namespace {
  const char* kScriptRoot = "resource/script";

  std::optional<std::string> ReadFile(std::string const& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file)
      return std::nullopt;
    std::ostringstream s;
    s << file.rdbuf();
    return s.str();
  }

  struct ScriptResolver : Luau::FileResolver {
    std::optional<Luau::SourceCode> readSource(const Luau::ModuleName& name) override {
      std::optional<std::string> source = ReadFile(name);
      if (!source)
        return std::nullopt;
      return Luau::SourceCode{*source, Luau::SourceCode::Module};
    }

    std::optional<Luau::ModuleInfo> resolveModule(
      const Luau::ModuleInfo*,
      Luau::AstExpr* expr,
      const Luau::TypeCheckLimits&) override
    {
      Luau::AstExprConstantString* str = expr->as<Luau::AstExprConstantString>();
      if (!str)
        return std::nullopt;
      std::string module(str->value.data, str->value.size);
      if (module.compare(0, 4, "@lt/") != 0)
        return std::nullopt;
      std::string path = std::string(kScriptRoot) + "/" + module.substr(4) + ".luau";
      if (!std::filesystem::exists(path))
        return std::nullopt;
      return Luau::ModuleInfo{path};
    }

    std::string getHumanReadableModuleName(const Luau::ModuleName& name) const override {
      return name;
    }
  };

  struct StrictConfig : Luau::ConfigResolver {
    Luau::Config config;

    StrictConfig() {
      config.mode = Luau::Mode::Strict;
    }

    const Luau::Config& getConfig(const Luau::ModuleName&, const Luau::TypeCheckLimits&) const override {
      return config;
    }
  };

  /* Directories under the script root that may not use the engine. */
  const char* kEngineFreeRoots[] = { "Core/", "Sim/", "Tool/" };

  bool IsEngineFree(std::string const& file) {
    std::string root = std::string(kScriptRoot) + "/";
    size_t at = file.find(root);
    if (at == std::string::npos)
      return false;
    std::string rest = file.substr(at + root.size());
    for (const char* dir : kEngineFreeRoots)
      if (rest.compare(0, strlen(dir), dir) == 0)
        return true;
    return false;
  }

  void Report(Luau::Frontend const& frontend, Luau::TypeError const& error) {
    std::string message;
    if (const Luau::SyntaxError* syntax = Luau::get_if<Luau::SyntaxError>(&error.data))
      message = syntax->message;
    else
      message = Luau::toString(error, Luau::TypeErrorToStringOptions{frontend.fileResolver});
    printf("%s:%d:%d: %s\n",
      error.moduleName.c_str(),
      error.location.begin.line + 1,
      error.location.begin.column + 1,
      message.c_str());
  }
}

int main(int argc, char** argv) {
  std::string defsPath = std::string(kScriptRoot) + "/engine.d.luau";
  std::vector<std::string> files;
  bool generate = true;

  for (int i = 1; i < argc; ++i) {
    if (strcmp(argv[i], "--defs") == 0 && i + 1 < argc)
      defsPath = argv[++i];
    else if (strcmp(argv[i], "--no-generate") == 0)
      generate = false;
    else
      files.push_back(argv[i]);
  }

  /* The engine API is one large type graph; the default substitution
     budget (10000 nodes) is sized for ordinary scripts. */
  FInt::LuauTarjanChildLimit.value = 1000000;

  if (!std::filesystem::is_directory(kScriptRoot))
    std::filesystem::current_path("..");

  if (generate && !Luau_WriteDefinitions(defsPath.c_str())) {
    fprintf(stderr, "luaucheck: cannot write %s\n", defsPath.c_str());
    return 2;
  }

  if (files.empty())
    for (auto const& entry : std::filesystem::recursive_directory_iterator(kScriptRoot))
      if (entry.is_regular_file() && entry.path().extension() == ".luau"
          && entry.path().string().find(".d.luau") == std::string::npos)
        files.push_back(entry.path().string());

  ScriptResolver resolver;
  StrictConfig config;
  Luau::FrontendOptions options;
  options.runLintChecks = true;
  Luau::Frontend frontend(&resolver, &config, options);

  Luau::registerBuiltinGlobals(frontend, frontend.globals);
  std::optional<std::string> defs = ReadFile(defsPath);
  Luau::LoadDefinitionFileResult loaded = frontend.loadDefinitionFile(
    frontend.globals, frontend.globals.globalScope, *defs, "@engine", false);
  if (!loaded.success) {
    fprintf(stderr, "luaucheck: generated definitions are invalid:\n");
    for (auto const& error : loaded.parseResult.errors)
      fprintf(stderr, "  %s:%d: %s\n", defsPath.c_str(),
        error.getLocation().begin.line + 1, error.getMessage().c_str());
    if (loaded.module)
      for (auto const& error : loaded.module->errors)
        Report(frontend, error);
    return 2;
  }

  /* Host is available everywhere; the engine-free environment has nothing
     else beyond the built-ins. */
  std::string hostPath = std::string(kScriptRoot) + "/host.d.luau";
  std::optional<std::string> hostDefs = ReadFile(hostPath);
  if (!hostDefs) {
    fprintf(stderr, "luaucheck: cannot read %s\n", hostPath.c_str());
    return 2;
  }
  Luau::Frontend coreFrontend(&resolver, &config, options);
  Luau::registerBuiltinGlobals(coreFrontend, coreFrontend.globals);
  for (Luau::Frontend* f : { &frontend, &coreFrontend }) {
    Luau::LoadDefinitionFileResult host = f->loadDefinitionFile(
      f->globals, f->globals.globalScope, *hostDefs, "@host", false);
    if (!host.success) {
      fprintf(stderr, "luaucheck: %s is invalid:\n", hostPath.c_str());
      for (auto const& error : host.parseResult.errors)
        fprintf(stderr, "  %s:%d: %s\n", hostPath.c_str(),
          error.getLocation().begin.line + 1, error.getMessage().c_str());
      if (host.module)
        for (auto const& error : host.module->errors)
          Report(*f, error);
      return 2;
    }
    Luau::freeze(f->globals.globalTypes);
  }

  size_t errors = 0;
  size_t engineFree = 0;
  for (std::string const& file : files) {
    bool core = IsEngineFree(file);
    engineFree += core ? 1 : 0;
    Luau::Frontend& checker = core ? coreFrontend : frontend;
    Luau::CheckResult result = checker.check(file);
    for (auto const& error : result.errors) {
      Report(checker, error);
      errors++;
    }
    for (auto const& warning : result.lintResult.warnings)
      printf("%s:%d:%d: warning: %s\n", file.c_str(),
        warning.location.begin.line + 1, warning.location.begin.column + 1,
        warning.text.c_str());
  }

  printf("luaucheck: %zu file(s), %zu of them engine-free, %zu error(s)\n",
    files.size(), engineFree, errors);
  return errors ? 1 : 0;
}
