-- Type definitions for the Host table: the services an engine-free script
-- gets from whatever runs it. Implemented in src/liblt/Luau/LuauHost.h and
-- registered by both the engine and bin/ltcore; keep the two in step.
-- Functions return false or nil on failure instead of raising.

declare Host: {
  -- Command-line arguments after the module name (empty in the engine).
  args: { string },
  -- True under bin/ltcore, false inside the engine.
  headless: boolean,
  -- True when a harness is driving the app (bin/launch APP --do or
  -- --script): an app that opens on a menu for a person goes straight to
  -- work for a script.
  scripted: boolean,

  ReadFile: (path: string) -> buffer?,
  WriteFile: (path: string, data: buffer | string, length: number?) -> boolean,
  AppendFile: (path: string, data: buffer | string, length: number?) -> boolean,
  Rename: (from: string, to: string) -> boolean,
  Remove: (path: string) -> boolean,
  Exists: (path: string) -> boolean,
  MakeDir: (path: string) -> boolean,
  -- Entry names in byte order; directories end in "/".
  ListDir: (path: string) -> { string },

  -- Monotonic seconds, and seconds since 1970. For tools only: game rules
  -- must not read a clock.
  Clock: () -> number,
  Time: () -> number,

  -- Ends the process with this status; never returns.
  Exit: (code: number?) -> never,
}
