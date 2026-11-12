--!strict
-- The keys a pilot flies with. Each has a name here, and whoever draws
-- the thing a key stands for asks whether it has just been pressed:
--
--   Q approach    W orbit       E keep at range   A align
--   S warp to     D dock, jump  L lock, unlock    Space stop
--   Tab the next hostile ship   M the map         F1 to F12 the rack
--   C the camera follows what is selected (and again, lets it go)
--
-- (Not yet: a screen to
-- change them.)
--
-- A scripted run has no keyboard: GameDebug.Key presses one by name,
-- and it counts as pressed for whoever asks during the next frame.

local Im = require("@lt/Game/UI/Im")

local Keys = {}

local CODES: { [string]: () -> number } = {
  Q = Key_Q, W = Key_W, E = Key_E, A = Key_A, S = Key_S, D = Key_D, L = Key_L, M = Key_M, C = Key_C,
  Space = Key_Space, Tab = Key_Tab,
  F1 = Key_F1, F2 = Key_F2, F3 = Key_F3, F4 = Key_F4, F5 = Key_F5, F6 = Key_F6,
  F7 = Key_F7, F8 = Key_F8, F9 = Key_F9, F10 = Key_F10, F11 = Key_F11, F12 = Key_F12,
}

-- Keys pressed by a script, and how many frames each still counts for.
local scripted: { [string]: number } = {}

-- The key of the nth module of the rack ("F1" for the first), if it has one.
function Keys.Rack(index: number): string?
  -- (F9 and F10 save and load, as they did before the rack had keys)
  return if index >= 1 and index <= 8 then `F{index}` else nil
end

-- Whether a key has just been pressed. Never while something is being
-- typed into.
function Keys.Pressed(name: string): boolean
  if scripted[name] then
    scripted[name] = nil
    return true
  end
  local code = CODES[name]
  return code ~= nil and not Im.Typing() and Key_Pressed(code())
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
