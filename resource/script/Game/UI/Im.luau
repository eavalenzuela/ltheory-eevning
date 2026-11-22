--!strict
-- A small immediate-mode layer for the game's interface. One widget draws
-- everything each frame by calling these; a button is a function that
-- draws itself and says whether it was just clicked. There is no widget
-- tree to rebuild, so a list of a few hundred rows costs what it draws.
--
-- Coordinates are the interface's units: window pixels at a scale of 1,
-- and more of them at more (Game/UI/Theme's scale, a setting). Call
-- Im.Begin once at the start of the frame's drawing.

local Colors = require("@lt/Colors")
local Fonts = require("@lt/Fonts")
local Icons = require("@lt/Game/UI/Icons")
local Theme = require("@lt/Game/UI/Theme")

local Im = {}

-- What draws: a panel, a text and how wide a text is, each given in the
-- interface's units and handed to the engine in pixels (Theme.scale). At
-- a scale of 1 they are what they were, to the pixel.
local function panel(x: number, y: number, w: number, h: number, color: vector, inner: number, alpha: number, bevel: number)
  local scale = Theme.scale
  if scale == 1 then
    WidgetRenderer_DrawPanel(vector.create(x, y), vector.create(w, h), color, inner, alpha, bevel)
    return
  end
  -- (its edges on whole pixels: a line a unit thick is one or two of them, and never a blur)
  local x0, y0 = math.floor(x * scale + 0.5), math.floor(y * scale + 0.5)
  local x1, y1 = math.floor((x + w) * scale + 0.5), math.floor((y + h) * scale + 0.5)
  WidgetRenderer_DrawPanel(vector.create(x0, y0), vector.create(math.max(1, x1 - x0), math.max(1, y1 - y0)), color, inner, alpha,
    if bevel > 0 then bevel * scale else bevel)
end

local function text(font: Font, s: string, x: number, y: number, size: number, color: vector, alpha: number)
  local scale = Theme.scale
  if scale == 1 then
    WidgetRenderer_DrawText(font, s, vector.create(x, y + 0.8 * size), size, color, alpha, false)
    return
  end
  local big = math.floor(size * scale + 0.5)
  WidgetRenderer_DrawText(font, s, vector.create(math.floor(x * scale + 0.5), math.floor(y * scale + 0.5) + 0.8 * big), big, color, alpha, false)
end

local function width(font: Font, s: string, size: number): number
  local scale = Theme.scale
  if scale == 1 then
    return WidgetRenderer_GetTextSize(font, s, size).x
  end
  return WidgetRenderer_GetTextSize(font, s, math.floor(size * scale + 0.5)).x / scale
end

-- True once the cursor has been found over a panel this frame.
Im.over = false

local cursor = vector.create(0, 0)
local pressed = false
local rightPressed = false
local held = false      -- this frame's click is being kept for what is drawn last (Im.Hold)
local clicked = false   -- a button was clicked with the mouse this frame
local double = false

-- A double click is worked out here: two clicks of the left button, the
-- second begun within so long of the first's end and so near it, and
-- neither of them a drag. (The engine's own notion of one,
-- Mouse_DoubleClicked, wants the second press within a tenth of a second
-- of the first's release, which a hand seldom manages; and it takes the
-- end of one drag and the start of the next for one, which out in space,
-- where a drag turns the camera and a double click flies the ship,
-- would not do.)
local DOUBLE_SECONDS = 0.4
local DOUBLE_NEAR = 8     -- pixels between the two clicks, at most
local CLICK_NEAR = 5      -- pixels the cursor may move in a click that is no drag
local clock = 0
local downAt: vector? = nil
local clickAt = vector.create(0, 0)
local clickTime = -1

-- Buttons drawn this frame and last, by name, with whether they were
-- enabled: so that a script can press one by name (Im.Press).
local seen: { [string]: boolean } = {}
local seenNow: { [string]: boolean } = {}
local pressNow: string? = nil
local pressNext: string? = nil

-- The field being typed into (of numbers, or of words), and what a
-- script has put in one.
local focus = ""
-- (whether the field with the keyboard was drawn this frame: one whose
-- window was shut while it was being typed in is not, and it lets the
-- keyboard go, or every key was the field's with no field on screen)
local focusSeen = false
local typed = ""
local entered: { [string]: number } = {}
local said: { [string]: string } = {}

-- How far each scrolling list is scrolled, by name.
local scrolls: { [string]: number } = {}

-- A part of the window that something drawn last is going to cover (the
-- map, which goes over everything): until that is drawn, the cursor is
-- not on anything there. (x, y, and the far corner.)
local covered: { number }? = nil

-- And the parts of the window that windows drawn later lie over
-- (Game/UI/Windows): the cursor is on nothing there either, for whatever
-- is drawn under them. (Each x, y, and the far corner.)
local shields: { { number } } = {}

-- What is being carried about by the mouse (Im.Grab, Im.Drop): what was
-- pressed on and has not moved yet, what is in hand, and what was let
-- go this frame, for the first place that asks for it. And a carrying a
-- script has asked for by the names of where from and where to.
type Carried = { payload: any, label: string, at: vector }
local grabbed: Carried? = nil
local carrying: Carried? = nil
local letGo: any = nil
local staged: { from: string, to: string, payload: any, armed: boolean, age: number }? = nil

-- The menu that is up (Im.OpenMenu): whose it is, where, what it
-- offers, and which of those can be had; the click it was given this
-- frame, kept from everything under it; and what was picked from it,
-- for its owner to ask after.
type Menu = { id: string, x: number, y: number, labels: { string }, enabled: { boolean } }
local menu: Menu? = nil
local menuClick, menuRight = false, false
local picked: { id: string, index: number }? = nil

-- What is said of the thing the cursor is on, this frame (Im.Tip): its
-- name, a line more, the key that does it; and where, if not by the cursor.
type Tip = { title: string, note: string?, key: string?, x: number?, y: number? }
local tip: Tip? = nil

-- Whether the controls are drawn to the new look (Im.Plain): a window
-- that has been made over says so while it draws, and one that has not
-- is drawn as it was. And, for the next button only, what it is among
-- the buttons about it ("primary": the main thing to do; "danger"),
-- and why it cannot be pressed, said while the cursor is on it.
local plain = false
local tone: string? = nil
local because: string? = nil

Im.TEXT = vector.create(0.82, 0.86, 0.9)
Im.DIM = vector.create(0.5, 0.55, 0.6)
Im.ACCENT = Colors.Primary
Im.WARN = Colors.Secondary

function Im.Begin()
  Im.over = false
  if focus ~= "" and not focusSeen then
    focus, typed = "", ""
  end
  focusSeen = false
  -- (where the cursor is, in the interface's units: Theme.scale)
  cursor = Cursor_Get() / Theme.scale
  pressed = Mouse_LeftPressed()
  rightPressed = Mouse_RightPressed()
  clock += FrameTimer_Get()
  double = false
  if pressed then
    if clickTime >= 0 and clock - clickTime <= DOUBLE_SECONDS and vector.magnitude(cursor - clickAt) <= DOUBLE_NEAR then
      double = true
      clickTime = -1
      downAt = nil
    else
      clickTime = -1
      downAt = cursor
    end
  elseif downAt and Mouse_LeftReleased() then
    if vector.magnitude(cursor - downAt) <= CLICK_NEAR then
      clickTime, clickAt = clock, cursor
    end
    downAt = nil
  end
  held = false
  covered = nil
  shields = {}
  tip = nil
  seen, seenNow = seenNow, {}
  pressNow, pressNext = pressNext, nil
  -- What is carried: let go when the button comes up, and in hand once
  -- it has moved from where it was pressed.
  letGo = nil
  if carrying then
    if not Mouse_LeftDown() then
      letGo, carrying = carrying.payload, nil
    end
  elseif grabbed then
    if not Mouse_LeftDown() then
      grabbed = nil
    elseif vector.magnitude(cursor - grabbed.at) > CLICK_NEAR then
      carrying, grabbed = grabbed, nil
    end
  end
  -- (with a menu up, a click is the menu's, and nobody else's)
  menuClick, menuRight = false, false
  if menu then
    menuClick, menuRight = pressed, rightPressed
    pressed, rightPressed, double = false, false, false
  end
end

-- Say which parts of the window are under windows that are drawn later:
-- from here on the cursor is on nothing there (Game/UI/Windows).
function Im.Shield(rects: { { number } })
  shields = rects
end

-- Say that a part of the window is going to be covered by what is drawn
-- last: from here on the cursor is on nothing there (a button under it
-- is not clicked, a list under it is not scrolled) until Im.Uncover,
-- which what covers it calls as it begins to draw.
function Im.Cover(x: number, y: number, w: number, h: number)
  covered = { x, y, x + w, y + h }
end

function Im.Uncover()
  covered = nil
end

-- Press a button by name on the next frame, as a click would: for
-- scripted runs. A button's name is its 'id', or its label if it has
-- none. Returns false if no such button was drawn enabled last frame.
function Im.Press(name: string): boolean
  if seen[name] ~= true then
    return false
  end
  pressNext = name
  return true
end

-- Whether a button of that name was drawn last frame, and enabled.
function Im.Has(name: string): (boolean, boolean)
  return seen[name] ~= nil, seen[name] == true
end

-- Put a value in a number field by name: for scripted runs.
function Im.Enter(name: string, value: number)
  entered[name] = value
end

-- Put words in a field of words by name: for scripted runs.
function Im.Say(name: string, text: string)
  said[name] = text
end

-- Asking twice, for what cannot be undone: the first press of a button
-- arms it for a few seconds ("Sure? ..."), the second does it.
-- Im.Asking(key): whether it is armed now (to label the button).
-- Im.Confirm(key): on a press, true if it was armed (do it), else arms it.
local ASK_SECONDS = 3
local asked: { [string]: number } = {}
function Im.Asking(key: string): boolean
  local until_ = asked[key]
  return until_ ~= nil and clock < until_
end
function Im.Confirm(key: string): boolean
  if Im.Asking(key) then
    asked[key] = nil
    return true
  end
  asked[key] = clock + ASK_SECONDS
  return false
end

-- Whether a field has the keyboard.
function Im.Typing(): boolean
  return focus ~= ""
end

-- The name of the field being typed into ("" if none).
function Im.Focus(): string
  return focus
end

function Im.Cursor(): vector
  return cursor
end

-- Whether the mouse button went down this frame (anywhere).
function Im.Pressed(): boolean
  return pressed
end

-- Whether the other mouse button went down this frame (anywhere).
function Im.RightPressed(): boolean
  return rightPressed
end

-- Whether this frame's press is the second of a double click (anywhere).
function Im.DoublePressed(): boolean
  return double
end

-- Keep this frame's click from everything drawn from here on, until
-- Im.Release: for a menu that is drawn last, over everything, when the
-- click is the menu's and not for what lies under it.
function Im.Hold()
  if pressed then
    held = true
    pressed = false
  end
  double = false
end

function Im.Release()
  if held then
    pressed = true
    held = false
  end
end

local function inside(x: number, y: number, w: number, h: number): boolean
  local under = covered
  if under and cursor.x >= under[1] and cursor.x < under[3] and cursor.y >= under[2] and cursor.y < under[4] then
    return false
  end
  for _, over in shields do
    if cursor.x >= over[1] and cursor.x < over[3] and cursor.y >= over[2] and cursor.y < over[4] then
      return false
    end
  end
  return cursor.x >= x and cursor.x < x + w and cursor.y >= y and cursor.y < y + h
end

Im.Inside = inside

function Im.TextWidth(s: string, size: number): number
  return width(Fonts.Default(), s, size)
end

-- Text with its top-left corner at (x, y).
function Im.Text(s: string, x: number, y: number, size: number, color: vector, alpha: number?)
  text(Fonts.Default(), s, x, y, size, color, alpha or 1)
end

-- Text ending at x.
function Im.TextRight(s: string, x: number, y: number, size: number, color: vector, alpha: number?)
  Im.Text(s, x - Im.TextWidth(s, size), y, size, color, alpha)
end

-- Text broken into lines no wider than 'width', at its spaces, from
-- (x, y) down, 'pitch' apart (1.4 of its size if not said). Returns the
-- y below the last line. (How a text breaks is worked out once: it is
-- for a paragraph that is the same from frame to frame.)
local broken: { [string]: { string } } = {}

function Im.Wrapped(s: string, x: number, y: number, width: number, size: number, color: vector, pitch: number?): number
  local key = `{size}:{width}:{s}`
  local lines = broken[key]
  if lines == nil then
    lines = {}
    local line = ""
    for word in string.gmatch(s, "%S+") do
      local longer = if line == "" then word else `{line} {word}`
      if line ~= "" and Im.TextWidth(longer, size) > width then
        table.insert(lines, line)
        line = word
      else
        line = longer
      end
    end
    if line ~= "" then
      table.insert(lines, line)
    end
    broken[key] = lines
  end
  local step = pitch or math.floor(1.4 * size + 0.5)
  for index, line in lines do
    Im.Text(line, x, y + (index - 1) * step, size, color)
  end
  return y + #lines * step
end

-- How wide a heading is.
function Im.HeadingWidth(s: string, size: number): number
  return width(Fonts.Heading(), s, size)
end

function Im.Heading(s: string, x: number, y: number, size: number, color: vector)
  text(Fonts.Heading(), s, x, y, size, color, 1)
end

-- A panel background. The camera ignores the mouse while it is over
-- one. (In the new look, Im.Plain, it is the look's panel: a screen
-- that has not been gone over yet is in the look's grounds and edges
-- all the same, where whoever draws it asks for that.)
function Im.Panel(x: number, y: number, w: number, h: number)
  if plain then
    panel(x, y, w, h, Theme.PANEL, 1, 0.94, -1)
    for _, edge in { { x, y, w, 1 }, { x, y + h - 1, w, 1 }, { x, y, 1, h }, { x + w - 1, y, 1, h } } do
      panel(edge[1], edge[2], edge[3], edge[4], Theme.EDGE_STRONG, 1, 1, -1)
    end
  else
    panel(x, y, w, h, vector.create(0.03, 0.05, 0.07), 0.9, 0.92, 6)
  end
  if inside(x, y, w, h) then
    Im.over = true
  end
end

-- A rectangle of solid colour. (In the new look it is a plain one: not
-- shaded, and with no glow about it.)
function Im.Fill(x: number, y: number, w: number, h: number, color: vector, alpha: number)
  if plain then
    panel(x, y, w, h, color, 1, alpha, -1)
  else
    panel(x, y, w, h, color, alpha, alpha, 0)
  end
end

-- ---------------------------------------------------------------------
-- The new look's own (Game/UI/Theme): plain grounds, hairlines, and
-- what is said of the thing the cursor is on.

-- A plain rectangle: the colour as it is given, to its edge and no
-- further (the panel shader's plain fill, asked for by a bevel under
-- zero: no shading, no light along its top, no shadow about it).
function Im.Flat(x: number, y: number, w: number, h: number, color: vector, alpha: number?)
  panel(x, y, w, h, color, 1, alpha or 1, -1)
end

-- The four hairlines about a rectangle, inside it.
function Im.Edge(x: number, y: number, w: number, h: number, color: vector, alpha: number?)
  Im.Flat(x, y, w, 1, color, alpha)
  Im.Flat(x, y + h - 1, w, 1, color, alpha)
  Im.Flat(x, y + 1, 1, h - 2, color, alpha)
  Im.Flat(x + w - 1, y + 1, 1, h - 2, color, alpha)
end

-- A panel of the new look: its ground and a hairline about it (a
-- stronger one for what is in front). The camera ignores the mouse
-- while it is over one, as over any panel.
function Im.Frame(x: number, y: number, w: number, h: number, strong: boolean?)
  Im.Flat(x, y, w, h, Theme.PANEL, 0.94)
  Im.Edge(x, y, w, h, if strong then Theme.EDGE_STRONG else Theme.EDGE)
  if inside(x, y, w, h) then
    Im.over = true
  end
end

-- Text a little heavier than Im.Text's: a name, a figure that matters.
function Im.Strong(s: string, x: number, y: number, size: number, color: vector, alpha: number?)
  text(Fonts.Medium(), s, x, y, size, color, alpha or 1)
end

function Im.StrongWidth(s: string, size: number): number
  return width(Fonts.Medium(), s, size)
end

-- A word or two on a tint of its own colour (what a thing is: secure,
-- hostile, a target). Returns how wide it came to.
function Im.Pill(s: string, x: number, y: number, color: vector): number
  local width = Im.StrongWidth(s, 11) + 12
  Im.Flat(x, y, width, 16, color, 0.18)
  Im.Strong(s, x + 6, y + 2, 11, color)
  return width
end

-- Say something of the thing the cursor is on, for this frame: its name,
-- a line more (what it is, or why it cannot be had), and the key that
-- does it. It is drawn last, over everything, by the cursor: or at
-- (x, y), for a thing that has a place of its own to say it in.
function Im.Tip(title: string, note: string?, key: string?, x: number?, y: number?)
  tip = { title = title, note = note, key = key, x = x, y = y }
end

-- A button that is a sign and no words (Game/UI/Icons); true on the
-- frame it is clicked, and whether the cursor is on it (for whoever
-- says what it is, with Im.Tip). 'id' is its name for a script.
function Im.IconButton(icon: string, x: number, y: number, w: number, h: number, enabled: boolean, id: string, color: vector?): (boolean, boolean)
  if seenNow[id] == nil or enabled then
    seenNow[id] = enabled
  end
  local scripted = enabled and pressNow == id
  if scripted then
    pressNow = nil
  end
  local hot = inside(x, y, w, h)
  if hot and enabled then
    Im.Flat(x, y, w, h, Theme.CONTROL_HOT, 0.9)
  end
  Icons.Draw(icon, x + w / 2, y + h / 2, math.min(w, h) * 0.26,
    if not enabled then Theme.FAINT elseif hot then Theme.TEXT else (color or Theme.DIM), 1)
  if hot and enabled and pressed then
    clicked = true
  end
  return scripted or (enabled and hot and pressed), hot
end

-- A button; true on the frame it is clicked. A disabled one is drawn
-- dimmed and never clicks. Give an 'id' where the label alone does not
-- say which button it is (one of a row of "Buy" buttons).
function Im.Button(label: string, x: number, y: number, w: number, h: number, enabled: boolean, id: string?): boolean
  local name = id or label
  if seenNow[name] == nil or enabled then
    seenNow[name] = enabled
  end
  local scripted = enabled and pressNow == name
  if scripted then
    pressNow = nil
  end
  local hot = enabled and inside(x, y, w, h)
  local kind, why = tone, because
  tone, because = nil, nil
  if plain then
    -- The new look: a plain control, lighter under the cursor; the
    -- main thing to do in the accent, a thing to be careful of in red,
    -- and one that cannot be pressed faint, saying why when asked.
    local size = math.min(14, h - 8)
    if not enabled then
      Im.Flat(x, y, w, h, Theme.CONTROL, 0.45)
      Im.Text(label, x + (w - Im.TextWidth(label, size)) / 2, y + (h - size) / 2 - 1, size, Theme.FAINT)
      if why and inside(x, y, w, h) then
        Im.Tip(label, why)
      end
      return false
    end
    if kind == "primary" then
      Im.Flat(x, y, w, h, Theme.ACCENT, if hot or scripted then 0.34 else 0.22)
      Im.Edge(x, y, w, h, Theme.ACCENT, 0.6)
    elseif kind == "danger" then
      Im.Flat(x, y, w, h, Theme.BAD, if hot or scripted then 0.30 else 0.18)
      Im.Edge(x, y, w, h, Theme.BAD, 0.55)
    else
      Im.Flat(x, y, w, h, if hot or scripted then Theme.CONTROL_HOT else Theme.CONTROL, 0.92)
      if hot then
        Im.Edge(x, y, w, h, Theme.EDGE_STRONG)
      end
    end
    Im.Strong(label, x + (w - Im.StrongWidth(label, size)) / 2, y + (h - size) / 2 - 1, size, Theme.TEXT)
    if hot and pressed then
      clicked = true
    end
    return scripted or (hot and pressed)
  end
  local base = if hot or scripted then vector.create(0.1, 0.3, 0.45) else vector.create(0.07, 0.12, 0.17)
  panel(x, y, w, h, base, 0.9, if enabled then 1 else 0.45, 4)
  local size = math.min(15, h - 8)
  Im.Text(label, x + (w - Im.TextWidth(label, size)) / 2, y + (h - size) / 2 - 1, size,
    if enabled then Im.TEXT else Im.DIM, if enabled then 1 else 0.6)
  if hot and pressed then
    clicked = true
  end
  return scripted or (hot and pressed)
end

-- Draw the controls that follow to the new look, or as they were:
-- returns what it was before, to be put back.
function Im.Plain(on: boolean): boolean
  local was = plain
  plain = on
  return was
end

-- What the next button is among the buttons about it: "primary" (the
-- main thing to do) or "danger". (The new look's only.)
function Im.Tone(kind: string)
  tone = kind
end

-- Why the next button cannot be pressed, if it cannot: said while the
-- cursor is on it. (The new look's only.)
function Im.Because(why: string?)
  because = why
end

-- Whether a button has been clicked with the mouse since this was last
-- asked: for whoever makes the click's sound.
function Im.Clicked(): boolean
  local was = clicked
  clicked = false
  return was
end

-- Text that can be clicked, lit while the cursor is on it; true on the
-- frame it is clicked. 'id' is its name for a script (Im.Press).
function Im.Link(label: string, x: number, y: number, size: number, color: vector, id: string): boolean
  seenNow[id] = true
  local scripted = pressNow == id
  if scripted then
    pressNow = nil
  end
  local hot = inside(x, y, Im.TextWidth(label, size), size + 5)
  Im.Text(label, x, y, size, if hot or scripted then Im.ACCENT else color)
  return scripted or (hot and pressed)
end

-- A bare area that can be clicked, for something that draws itself:
-- whether the cursor is on it, and whether it was just clicked. 'id' is
-- its name for a script (Im.Press).
function Im.Area(id: string, x: number, y: number, w: number, h: number, enabled: boolean): (boolean, boolean)
  if seenNow[id] == nil or enabled then
    seenNow[id] = enabled
  end
  local scripted = enabled and pressNow == id
  if scripted then
    pressNow = nil
  end
  local hot = inside(x, y, w, h)
  return hot, scripted or (enabled and hot and pressed)
end

-- A button that stays lit while 'on': a tab, or one of a set of choices.
function Im.Toggle(label: string, x: number, y: number, w: number, h: number, on: boolean, id: string?): boolean
  if plain then
    -- The new look: a switch in a hairline, lit in the accent while it is on.
    local name = id or label
    local hot, pressedNow = Im.Area(name, x, y, w, h, true)
    if on then
      Im.Flat(x, y, w, h, Theme.ACCENT, 0.14)
      Im.Edge(x, y, w, h, Theme.ACCENT, 0.6)
    else
      if hot then
        Im.Flat(x, y, w, h, Theme.TEXT, 0.05)
      end
      Im.Edge(x, y, w, h, Theme.EDGE)
    end
    local size = math.min(13, h - 8)
    Im.Strong(label, x + (w - Im.StrongWidth(label, size)) / 2, y + (h - size) / 2 - 1, size, if on or hot then Theme.TEXT else Theme.DIM)
    if hot and pressed then
      clicked = true
    end
    return pressedNow
  end
  local clicked = Im.Button(label, x, y, w, h, true, id)
  if on then
    Im.Fill(x, y + h - 3, w, 3, Im.ACCENT, 0.95)
  end
  return clicked
end

-- A page of a window, among its pages: lit and underlined while it is
-- the one shown, with a count beside its name if it has one. Returns
-- whether it was clicked, and how wide it came to. (The new look's.)
function Im.Tab(label: string, x: number, y: number, h: number, on: boolean, id: string, count: number?): (boolean, number)
  local badge = if count and count > 0 then tostring(count) else nil
  local width = Im.StrongWidth(label, 14) + 24 + (if badge then Im.StrongWidth(badge, 11) + 16 else 0)
  local hot, pressedNow = Im.Area(id, x, y, width, h, true)
  if on then
    Im.Flat(x, y, width, h, Theme.ACCENT, 0.07)
    Im.Flat(x, y + h - 2, width, 2, Theme.ACCENT)
  elseif hot then
    Im.Flat(x, y, width, h, Theme.TEXT, 0.04)
  end
  Im.Strong(label, x + 12, y + (h - 14) / 2 - 1, 14, if on or hot then Theme.TEXT else Theme.DIM)
  if badge then
    local bx = x + 12 + Im.StrongWidth(label, 14) + 6
    Im.Flat(bx, y + (h - 15) / 2, Im.StrongWidth(badge, 11) + 10, 15, Theme.CONTROL, 0.92)
    Im.Strong(badge, bx + 5, y + (h - 15) / 2 + 2, 11, Theme.TEXT)
  end
  if hot and pressed then
    clicked = true
  end
  return pressedNow, width
end

-- A field holding a whole number of at most nine digits ('digits': as
-- many as that, for a price, which runs to tens of billions). Click it
-- and type; Return or a click elsewhere finishes. Returns the number it
-- holds now.
function Im.Number(name: string, value: number, x: number, y: number, w: number, h: number, digits: number?): number
  if focus == name then
    focusSeen = true
  end
  local set = entered[name]
  if set then
    entered[name] = nil
    value = set
    if focus == name then
      focus = ""
    end
  end
  local hot = inside(x, y, w, h)
  if pressed then
    if hot then
      focus = name
      focusSeen = true
      typed = if value > 0 then tostring(value) else ""
    elseif focus == name then
      focus = ""
    end
  end
  if focus == name then
    for digit in string.gmatch(Keyboard_GetText(), "%d") do
      if #typed < (digits or 9) then
        typed ..= digit
      end
    end
    if Key_Pressed(Key_BackSpace()) then
      typed = string.sub(typed, 1, -2)
    end
    if Key_Pressed(Key_Return()) then
      focus = ""
    end
    value = tonumber(typed) or 0
  end
  local focused = focus == name
  if plain then
    Im.Flat(x, y, w, h, Theme.WELL, 0.9)
    Im.Edge(x, y, w, h, if focused then Theme.ACCENT else Theme.EDGE, if focused then 0.9 else 1)
  else
    panel(x, y, w, h, vector.create(0.02, 0.03, 0.04), 0.95, 1, 3)
    if focused then
      Im.Fill(x, y + h - 2, w, 2, Im.ACCENT, 0.95)
    end
  end
  local size = math.min(15, h - 8)
  local text = if focused then typed .. "_" else tostring(value)
  Im.TextRight(text, x + w - 8, y + (h - size) / 2 - 1, size, Im.TEXT)
  return value
end

-- A field holding a line of words, 'limit' letters at most: letters,
-- figures, spaces and the few marks a name has. Click it and type;
-- Return or a click elsewhere finishes. Returns what it holds now.
-- 'hint' is shown, dim, while it is empty and nobody is typing in it.
-- 'allowed' is a pattern of the letters it takes, if not those (a path's
-- field takes slashes and colons too).
function Im.Words(name: string, value: string, x: number, y: number, w: number, h: number, limit: number, hint: string?,
  allowed: string?): string
  if focus == name then
    focusSeen = true
  end
  local set = said[name]
  if set then
    said[name] = nil
    value = string.sub(set, 1, limit)
    if focus == name then
      focus = ""
    end
  end
  local hot = inside(x, y, w, h)
  if pressed then
    if hot then
      focus = name
      focusSeen = true
      typed = value
    elseif focus == name then
      focus = ""
    end
  end
  if focus == name then
    for letter in string.gmatch(Keyboard_GetText(), allowed or "[%w '&%.%-]") do
      if #typed < limit then
        typed ..= letter
      end
    end
    if Key_Pressed(Key_BackSpace()) then
      typed = string.sub(typed, 1, -2)
    end
    if Key_Pressed(Key_Return()) then
      focus = ""
    end
    value = typed
  end
  local focused = focus == name
  if plain then
    Im.Flat(x, y, w, h, Theme.WELL, 0.9)
    Im.Edge(x, y, w, h, if focused then Theme.ACCENT else Theme.EDGE, if focused then 0.9 else 1)
  else
    panel(x, y, w, h, vector.create(0.02, 0.03, 0.04), 0.95, 1, 3)
    if focused then
      Im.Fill(x, y + h - 2, w, 2, Im.ACCENT, 0.95)
    end
  end
  local size = math.min(15, h - 8)
  if focused then
    Im.Text(typed .. "_", x + 8, y + (h - size) / 2 - 1, size, Im.TEXT)
  elseif value == "" and hint then
    Im.Text(hint, x + 8, y + (h - size) / 2 - 1, size, Im.DIM, 0.7)
  else
    Im.Text(value, x + 8, y + (h - size) / 2 - 1, size, Im.TEXT)
  end
  return value
end

-- The slider being dragged, by name; "" if none.
local sliding = ""

-- Whether a slider is being dragged.
function Im.Sliding(): boolean
  return sliding ~= ""
end

-- A slider: a track with a knob on it, for a whole number from 'low' to
-- 'high'. The knob is dragged, or the track clicked where the knob is
-- to go. Returns the number it holds now. 'name' is its name for a
-- script, which puts a number in it with Im.Enter.
function Im.Slider(name: string, value: number, low: number, high: number, x: number, y: number, w: number, h: number,
  enabled: boolean): number
  if seenNow[name] == nil or enabled then
    seenNow[name] = enabled
  end
  local set = entered[name]
  if set then
    entered[name] = nil
    value = math.clamp(math.floor(set + 0.5), low, high)
  end
  -- (the knob's middle runs from half a knob in at one end to half a knob in at the other)
  local knob = h
  local run = w - knob
  if enabled then
    if pressed and inside(x, y - 4, w, h + 8) then
      sliding = name
    end
    if sliding == name then
      if Mouse_LeftDown() then
        local share = math.clamp((cursor.x - x - knob / 2) / run, 0, 1)
        value = low + math.floor(share * (high - low) + 0.5)
      else
        sliding = ""
      end
    end
  elseif sliding == name then
    sliding = ""
  end
  local share = if high > low then (value - low) / (high - low) else 0
  local middle = y + h / 2
  Im.Fill(x + knob / 2, middle - 2, run, 4, Im.DIM, 0.3)
  Im.Fill(x + knob / 2, middle - 2, run * share, 4, Im.ACCENT, if enabled then 0.9 else 0.3)
  local hot = enabled and (sliding == name or inside(x, y - 4, w, h + 8))
  panel(x + run * share, y, knob, h,
    if hot then vector.create(0.1, 0.3, 0.45) else vector.create(0.07, 0.12, 0.17), 0.95, if enabled then 1 else 0.45, 4)
  Im.Fill(x + run * share + knob / 2 - 1, y + 4, 2, h - 8, if enabled then Im.TEXT else Im.DIM, if enabled then 0.8 else 0.4)
  return value
end

-- The first row to draw of a scrolling list of 'count' rows of which
-- 'visible' fit, moved by the wheel while the cursor is over the list.
-- (the list whose scroll bar is being dragged, if one is)
local dragging: string? = nil
function Im.Scroll(name: string, x: number, y: number, w: number, h: number, count: number, visible: number): number
  local at = scrolls[name] or 0
  if inside(x, y, w, h) then
    at -= 3 * Mouse_GetScrollDelta()
  end
  -- (and by its bar, at the right edge: pressed there, it goes where it
  -- is pressed, and follows while the button is held. It went by the
  -- wheel alone, and a long list was many turns of it)
  if count > visible then
    local track = h - 4
    local size = math.max(16, track * visible / count)
    if pressed and inside(x + w - 10, y, 10, h) then
      dragging = name
    end
    if dragging == name then
      if Mouse_LeftDown() then
        local share = (cursor.y - y - 2 - size / 2) / math.max(1, track - size)
        at = share * (count - visible)
      else
        dragging = nil
      end
    end
  end
  at = math.clamp(math.floor(at + 0.5), 0, math.max(0, count - visible))
  scrolls[name] = at
  if count > visible then
    -- a thumb down the right edge
    local track = h - 4
    local size = math.max(16, track * visible / count)
    if plain then
      Im.Flat(x + w - 4, y + 2 + (track - size) * at / (count - visible), 4, size, Theme.DIM, 0.55)
    else
      Im.Fill(x + w - 3, y + 2 + (track - size) * at / (count - visible), 3, size, Im.DIM, 0.6)
    end
  end
  return at
end

-- Put a scrolling list at a row (0: its top).
function Im.ScrollTo(name: string, at: number)
  scrolls[name] = at
end

-- A list row; returns whether the cursor is on it, whether it was just
-- clicked, and whether that click was a double click.
function Im.Row(x: number, y: number, w: number, h: number, selected: boolean, id: string?): (boolean, boolean, boolean)
  local hot = inside(x, y, w, h)
  -- (with a name, a script can click it as it can a button: Im.Press)
  local scripted = false
  if id then
    seenNow[id] = true
    scripted = pressNow == id
    if scripted then
      pressNow = nil
    end
  end
  if plain then
    -- (picked: a tint, and a bar of the accent at its left; under the cursor: a lighter row)
    if selected then
      Im.Flat(x, y, w, h, Theme.ACCENT, 0.13)
      Im.Flat(x, y, 3, h, Theme.ACCENT)
    elseif hot then
      Im.Flat(x, y, w, h, Theme.TEXT, 0.045)
    end
  elseif selected then
    Im.Fill(x, y, w, h, Im.ACCENT, 0.22)
  elseif hot then
    Im.Fill(x, y, w, h, Im.ACCENT, 0.1)
  end
  return hot, (hot and pressed) or scripted, hot and double
end

-- Something a script can do by name that has no button of its own
-- (what a menu offers for a thing, which a script cannot point at):
-- true on the frame a script presses it (Im.Press). It is there to be
-- asked after with Im.Has, enabled or not, like a button.
function Im.Hook(name: string, enabled: boolean): boolean
  if seenNow[name] == nil or enabled then
    seenNow[name] = enabled
  end
  if enabled and pressNow == name then
    pressNow = nil
    return true
  end
  return false
end

-- ---------------------------------------------------------------------
-- Carrying things about

-- Something that can be picked up and carried: pressed on and moved, it
-- is in hand ('payload', whatever its owner makes of it; 'label' is
-- what is drawn at the cursor while it is carried). 'id' is its name
-- for a script (Im.Carry).
function Im.Grab(id: string, payload: any, label: string, x: number, y: number, w: number, h: number)
  seenNow[id] = true
  if staged and staged.from == id and not staged.armed then
    staged.payload, staged.armed = payload, true
  end
  if pressed and carrying == nil and inside(x, y, w, h) then
    grabbed = { payload = payload, label = label, at = cursor }
  end
end

-- What is in hand, if anything is.
function Im.Carried(): any
  return if carrying then carrying.payload else nil
end

-- Somewhere a carried thing can be put down: what was let go on it this
-- frame, if anything was (the first place that asks has it, so what
-- lies inside another asks first). It is lit while something is held
-- over it. 'id' is its name for a script (Im.Carry).
function Im.Drop(id: string, x: number, y: number, w: number, h: number): any
  seenNow[id] = true
  if staged and staged.armed and staged.to == id then
    local payload = staged.payload
    staged = nil
    return payload
  end
  if letGo ~= nil and inside(x, y, w, h) then
    local payload = letGo
    letGo = nil
    return payload
  end
  if carrying and inside(x, y, w, h) then
    Im.Fill(x, y, w, h, Im.ACCENT, 0.1)
  end
  return nil
end

-- Carry what is named 'from' to what is named 'to', as a hand would:
-- for scripted runs. False if either was not drawn last frame.
function Im.Carry(from: string, to: string): boolean
  if seen[from] == nil or seen[to] == nil then
    return false
  end
  staged = { from = from, to = to, payload = nil, armed = false, age = 0 }
  return true
end

-- ---------------------------------------------------------------------
-- A menu

-- Put up a menu at a point: a list of things to pick from, some of
-- which may not be had now. Its owner asks what was picked with
-- Im.Picked, by the 'id' it gave. One menu is up at a time.
function Im.OpenMenu(id: string, x: number, y: number, labels: { string }, enabled: { boolean }?)
  local can: { boolean } = {}
  for index in labels do
    can[index] = enabled == nil or enabled[index] ~= false
  end
  menu = { id = id, x = x, y = y, labels = labels, enabled = can }
  picked = nil
end

function Im.MenuOpen(): boolean
  return menu ~= nil
end

-- What was picked from the menu of that id, once: its place in the
-- list. Nil if nothing has been.
function Im.Picked(id: string): number?
  local was = picked
  if was and was.id == id then
    picked = nil
    return was.index
  end
  return nil
end

local MENU_ROW = 24

-- Draw the menu that is up, and what is in hand, over everything: once
-- a frame, after all else. A click on something the menu offers picks
-- it; a click anywhere else puts the menu away. (A script picks by
-- name: "Menu:" and the label.)
function Im.Overlay(right: number, bottom: number)
  local up = menu
  if up then
    local width = 120
    for _, label in up.labels do
      width = math.max(width, Im.TextWidth(label, 13) + 28)
    end
    local height = #up.labels * MENU_ROW + 8
    local x, y = math.min(up.x, right - width - 4), math.min(up.y, bottom - height - 4)
    -- (the look's: a plain ground, and a hairline about it)
    panel(x, y, width, height, Theme.PANEL, 1, 0.98, -1)
    for _, edge in { { x, y, width, 1 }, { x, y + height - 1, width, 1 }, { x, y, 1, height }, { x + width - 1, y, 1, height } } do
      panel(edge[1], edge[2], edge[3], edge[4], Theme.EDGE_STRONG, 1, 1, -1)
    end
    Im.over = true
    local chosen = 0
    for index, label in up.labels do
      local ry = y + 4 + (index - 1) * MENU_ROW
      local can = up.enabled[index]
      local name = `Menu:{label}`
      seenNow[name] = can
      local scripted = can and pressNow == name
      if scripted then
        pressNow = nil
      end
      local hot = can and cursor.x >= x and cursor.x < x + width and cursor.y >= ry and cursor.y < ry + MENU_ROW
      if hot then
        panel(x + 1, ry, width - 2, MENU_ROW, Theme.ACCENT, 1, 0.16, -1)
        panel(x + 1, ry, 3, MENU_ROW, Theme.ACCENT, 1, 1, -1)
      end
      Im.Text(label, x + 14, ry + 5, 13, if can then Im.TEXT else Im.DIM, if can then 1 else 0.6)
      if scripted or (hot and menuClick) then
        chosen = index
      end
    end
    if chosen ~= 0 then
      picked = { id = up.id, index = chosen }
      menu = nil
    elseif menuClick or menuRight then
      menu = nil
    end
  end
  -- What was said of the thing the cursor is on: with no menu up and
  -- nothing in hand.
  local say = tip
  if say and up == nil and carrying == nil then
    local titleWidth = Im.TextWidth(say.title, 13)
    local keyWidth = if say.key then Im.TextWidth(say.key, 12) + 10 else 0
    local width = titleWidth + (if say.key then keyWidth + 10 else 0)
    if say.note then
      width = math.max(width, Im.TextWidth(say.note, 12))
    end
    width += 20
    local height = if say.note then 45 else 28
    local x = math.min(say.x or cursor.x + 16, right - width - 4)
    local y = math.min(say.y or cursor.y + 20, bottom - height - 4)
    Im.Flat(x, y, width, height, vector.create(0.05, 0.075, 0.105), 1)
    Im.Edge(x, y, width, height, Theme.EDGE_STRONG)
    Im.Text(say.title, x + 10, y + 7, 13, Theme.TEXT)
    if say.key then
      local kx = x + 10 + titleWidth + 10
      Im.Edge(kx, y + 6, keyWidth, 17, Theme.EDGE_STRONG)
      Im.Text(say.key, kx + 5, y + 8, 12, Theme.DIM)
    end
    if say.note then
      Im.Text(say.note, x + 10, y + 26, 12, Theme.DIM)
    end
  end
  local hand = carrying
  if hand then
    Im.over = true
    local width = Im.TextWidth(hand.label, 13) + 18
    panel(cursor.x + 14, cursor.y + 10, width, 24, vector.create(0.1, 0.3, 0.45), 0.9, 0.95, 4)
    Im.Text(hand.label, cursor.x + 23, cursor.y + 15, 13, Im.TEXT)
  end
  -- (a carrying a script asked for, whose ends never showed, is forgotten)
  if staged then
    staged.age += 1
    if staged.age > 6 then
      staged = nil
    end
  end
end

return Im
