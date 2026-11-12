--!strict
-- The keys a pilot flies with. Each thing a key does has a name here
-- (an action), and whoever draws the thing asks whether its key has
-- just been pressed (Keys.Did) and what that key is, to show it
-- (Keys.Of). The keys they have at first:
--
--   Q approach    W orbit       E keep at range   A align
--   S warp to     D dock, jump  L lock, unlock    Space stop
--   Tab the next hostile ship   M the map         F1 to F8 the rack
--   C the camera follows what is selected (and again, lets it go)
--   P pause       F9 save       F10 load
--
-- A person can give any of them another key (the menu's Options, Keys:
-- Game/UI/Menu). Two actions never have the same key: one given a key
-- another has takes it, and the other gets the key the first had.
-- Escape is the menu's and is nobody else's.
--
-- A scripted run has no keyboard: GameDebug.Key presses a key by its
-- name, and it counts as pressed for whoever asks during the next
-- frame.

local Im = require("@lt/Game/UI/Im")

local Keys = {}

export type Action = { id: string, label: string, key: string }

-- What there is a key for, in the order the keys screen lists them,
-- each with the key it has at first.
Keys.ACTIONS = {
  { id = "approach", label = "Approach", key = "Q" },
  { id = "orbit", label = "Orbit", key = "W" },
  { id = "keep", label = "Keep at range", key = "E" },
  { id = "align", label = "Align to", key = "A" },
  { id = "warp", label = "Warp to", key = "S" },
  { id = "dock", label = "Dock, or jump", key = "D" },
  { id = "lock", label = "Lock, or unlock", key = "L" },
  { id = "stop", label = "Stop the ship", key = "Space" },
  { id = "next", label = "Next hostile ship", key = "Tab" },
  { id = "camera", label = "Camera follows", key = "C" },
  { id = "map", label = "Star map", key = "M" },
  { id = "pause", label = "Pause", key = "P" },
  { id = "rack1", label = "Module 1", key = "F1" },
  { id = "rack2", label = "Module 2", key = "F2" },
  { id = "rack3", label = "Module 3", key = "F3" },
  { id = "rack4", label = "Module 4", key = "F4" },
  { id = "rack5", label = "Module 5", key = "F5" },
  { id = "rack6", label = "Module 6", key = "F6" },
  { id = "rack7", label = "Module 7", key = "F7" },
  { id = "rack8", label = "Module 8", key = "F8" },
  { id = "save", label = "Quick save", key = "F9" },
  { id = "load", label = "Quick load", key = "F10" },
} :: { Action }

-- The keys an action can be given, by the name each is shown and kept
-- under, in the order they are listened for.
local CODES: { [string]: () -> number } = {
  A = Key_A, B = Key_B, C = Key_C, D = Key_D, E = Key_E, F = Key_F, G = Key_G, H = Key_H, I = Key_I, J = Key_J,
  K = Key_K, L = Key_L, M = Key_M, N = Key_N, O = Key_O, P = Key_P, Q = Key_Q, R = Key_R, S = Key_S, T = Key_T,
  U = Key_U, V = Key_V, W = Key_W, X = Key_X, Y = Key_Y, Z = Key_Z,
  ["0"] = Key_N0, ["1"] = Key_N1, ["2"] = Key_N2, ["3"] = Key_N3, ["4"] = Key_N4,
  ["5"] = Key_N5, ["6"] = Key_N6, ["7"] = Key_N7, ["8"] = Key_N8, ["9"] = Key_N9,
  F1 = Key_F1, F2 = Key_F2, F3 = Key_F3, F4 = Key_F4, F5 = Key_F5, F6 = Key_F6,
  F7 = Key_F7, F8 = Key_F8, F9 = Key_F9, F10 = Key_F10, F11 = Key_F11, F12 = Key_F12,
  Space = Key_Space, Tab = Key_Tab,
  Comma = Key_Comma, Period = Key_Period, Slash = Key_Slash, SemiColon = Key_SemiColon, Quote = Key_Quote,
  LBracket = Key_LBracket, RBracket = Key_RBracket, BackSlash = Key_BackSlash, Dash = Key_Dash, Equal = Key_Equal,
  Tilde = Key_Tilde, Insert = Key_Insert, Delete = Key_Delete, Home = Key_Home, End = Key_End,
  PageUp = Key_PageUp, PageDown = Key_PageDown,
}
local ORDER = {
  "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
  "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Space", "Tab",
  "Comma", "Period", "Slash", "SemiColon", "Quote", "LBracket", "RBracket", "BackSlash", "Dash", "Equal", "Tilde",
  "Insert", "Delete", "Home", "End", "PageUp", "PageDown",
}

-- What a key is called where it is shown, where that is not its name.
local SHOWN: { [string]: string } = {
  Comma = ",", Period = ".", Slash = "/", SemiColon = ";", Quote = "'", LBracket = "[", RBracket = "]", BackSlash = "\\",
  Dash = "-", Equal = "=", Tilde = "`", Insert = "Ins", Delete = "Del", PageUp = "PgUp", PageDown = "PgDn",
}

-- The key each action has now.
local bound: { [string]: string } = {}
for _, action in Keys.ACTIONS do
  bound[action.id] = action.key
end

-- Keys pressed by a script, and how many frames each still counts for.
local scripted: { [string]: number } = {}

local function known(id: string): Action?
  for _, action in Keys.ACTIONS do
    if action.id == id then
      return action
    end
  end
  return nil
end

-- The action of the nth module of the rack, if it has a key.
function Keys.Rack(index: number): string?
  return if index >= 1 and index <= 8 then `rack{index}` else nil
end

-- The key an action has, as it is shown ("Q", "F1", "Space", ";").
function Keys.Of(id: string): string
  local key = bound[id] or ""
  return SHOWN[key] or key
end

-- Words that name keys, with the keys as they are now: "<lock> locks
-- it" is "L locks it" until a person gives locking another key. (What
-- the Core has to say about keys, it says this way: it knows the things
-- keys do and not the keys.)
function Keys.Say(text: string): string
  return (string.gsub(text, "<(%w+)>", function(id: string): string
    return if bound[id] then Keys.Of(id) else `<{id}>`
  end))
end

local function pressed(key: string): boolean
  if scripted[key] then
    scripted[key] = nil
    return true
  end
  local code = CODES[key]
  return code ~= nil and not Im.Typing() and Key_Pressed(code())
end

-- Whether an action's key has just been pressed. Never while something
-- is being typed into, nor while a key is being listened for.
local listening = false
function Keys.Did(id: string): boolean
  local key = bound[id]
  return key ~= nil and not listening and pressed(key)
end

-- While a key is being listened for (the keys screen, giving an action
-- another one), no key does what it otherwise does.
function Keys.Listen(on: boolean)
  listening = on
end

-- A key that has just been pressed, by its name, of those an action can
-- be given: for the keys screen. Nil with none.
function Keys.Heard(): string?
  for _, key in ORDER do
    if pressed(key) then
      return key
    end
  end
  return nil
end

-- Give an action a key. Another action that has it gets the key this
-- one had. False if there is no such action or no such key.
function Keys.Bind(id: string, key: string): boolean
  if known(id) == nil or CODES[key] == nil then
    return false
  end
  local was = bound[id]
  for other, theirs in bound do
    if theirs == key and other ~= id then
      bound[other] = was
    end
  end
  bound[id] = key
  return true
end

-- Every action back on the key it had at first.
function Keys.Reset()
  for _, action in Keys.ACTIONS do
    bound[action.id] = action.key
  end
end

-- Whether every action is on the key it had at first.
function Keys.AtFirst(): boolean
  for _, action in Keys.ACTIONS do
    if bound[action.id] ~= action.key then
      return false
    end
  end
  return true
end

-- The keys as a line of text, to be kept (Game/Settings): only those
-- that are not what they were at first ("approach:G,stop:X").
function Keys.Export(): string
  local parts: { string } = {}
  for _, action in Keys.ACTIONS do
    if bound[action.id] ~= action.key then
      table.insert(parts, `{action.id}:{bound[action.id]}`)
    end
  end
  return table.concat(parts, ",")
end

-- The keys from such a line: everything at first, and then what the
-- line says, as far as it makes sense (an action or a key nobody knows
-- is passed over).
function Keys.Import(text: string)
  Keys.Reset()
  for id: string, key: string in string.gmatch(text, "(%w+):(%w+)") :: any do
    Keys.Bind(id, key)
  end
end

-- Press a key by name, as a script does. False if there is no such key.
function Keys.Press(name: string): boolean
  if CODES[name] == nil then
    return false
  end
  scripted[name] = 2
  return true
end

-- Once a frame, after everybody has asked: a key a script pressed that
-- nobody wanted is forgotten after a frame or two.
function Keys.EndFrame()
  for name, left in scripted do
    if left > 1 then
      scripted[name] = left - 1
    else
      scripted[name] = nil
    end
  end
end

return Keys
