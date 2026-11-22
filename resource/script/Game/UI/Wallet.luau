--!strict
-- The wallet: a window of its own (Game/UI/Windows). A station's:
-- opened from the dock, and shut when the pilot undocks. The pilot's
-- balance and journal: what has come in and gone out, on the one list.
-- (The corporation's side, which was a tab here, is a window of its own
-- since 2026-11-16: Game/UI/Corporation; "Wallet:corporation" opens it.)
-- "Wallet" opens it.

local Core = require("@lt/Core/Api")
local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local List = require("@lt/Game/UI/List")
local Session = require("@lt/Game/Session")
local Theme = require("@lt/Game/UI/Theme")
local Windows = require("@lt/Game/UI/Windows")

local Wallet = {}

Wallet.ID = "wallet"

local current: Session.Session? = nil

function Wallet.Open()
  Windows.Open(Wallet.ID)
  Windows.Raise(Wallet.ID)
end

function Wallet.Close()
  Windows.Close(Wallet.ID)
end

function Wallet.IsOpen(): boolean
  return Windows.IsOpen(Wallet.ID)
end

-- How the corporation's window is opened, for the wallet's old way in
-- to it ("Wallet:corporation"): set by Game/UI/Corporation.
Wallet.ToCorporation = nil :: (() -> ())?

local JOURNAL: { List.Column } = {
  { id = "when", label = "When", width = 140, sort = false }, { id = "what", label = "What", width = 0, sort = false },
  { id = "amount", label = "Amount", width = 120, right = true, sort = false },
  { id = "balance", label = "Balance", width = 130, right = true, sort = false },
}

-- A journal as a list: what has come in and gone out, the newest first
-- (the corporation's window shows its own with it).
local function drawJournal(name: string, journal: { { tick: number, reason: string, amount: number, balance: number } }, x: number, y: number,
  w: number, h: number)
  local layout = List.Columns(JOURNAL, x, w - 6)
  List.Head(name, x, y, w, JOURNAL, layout, "", false)
  local top = y + List.HEAD
  if #journal == 0 then
    Im.Text("Nothing has been paid or earned yet.", x + 12, top + 8, 13, Theme.DIM)
  end
  local first, visible = List.Body(name, x, top, w, h - List.HEAD, #journal)
  for row = 1, visible do
    local entry = journal[#journal - (row + first) + 1]
    if entry == nil then
      break
    end
    local rowY = top + (row - 1) * List.ROW
    local hot = List.Row(x, rowY, w - 5, false)
    List.Text(Format.Clock(entry.tick), layout.when, rowY, false, Theme.DIM, 13)
    List.Text(entry.reason, layout.what, rowY, hot, Theme.TEXT, 14)
    List.Text((if entry.amount >= 0 then "+" else "") .. Format.Whole(entry.amount), layout.amount, rowY, false,
      if entry.amount >= 0 then Theme.GOOD else Theme.CAUTION, 14)
    List.Text(Format.Whole(entry.balance), layout.balance, rowY, false, Theme.DIM, 13)
  end
end

Wallet.Journal = drawJournal

-- The window's inside: the balance, and the journal on the one list.
local function drawWallet(game: Core.Game, x: number, y: number, w: number, h: number)
  local left, top = x + 14, y + 10
  Im.Text("Balance", left, top + 7, 13, Theme.DIM)
  Im.Heading(Format.Credits(game.state.wallet), left + 70, top, 22, Theme.TEXT)
  drawJournal("journal", Core.Query.Journal(game), x + 1, top + 40, w - 2, y + h - (top + 40) - 4)
end

-- Open the window ("mine"; "corporation" opens the corporation's own window).
function Wallet.Show(which: string)
  if which == "corporation" and Wallet.ToCorporation then
    Wallet.ToCorporation()
    return
  end
  Wallet.Open()
end

-- Once a frame, before the windows are drawn: whose game it is, and
-- whether the pilot is docked (the window is a station's: Windows.Berthed).
function Wallet.Frame(session: Session.Session, docked: boolean)
  current = session
  Windows.Berthed(Wallet.ID, docked)
end

Windows.Kind(Wallet.ID, function(_: Windows.Window, x: number, y: number, w: number, h: number)
  local session = current
  if session == nil then
    return
  end
  local game = session.game
  if Core.Query.Player(game).at == 0 then
    Im.Text("The books are kept at a station: dock at one.", x + 14, y + 14, 14, Theme.DIM)
    return
  end
  local was = Im.Plain(true)
  -- (the corporation's side was a tab of this window until 2026-11-16: its way in, for a script, opens its own window)
  if Im.Hook("Wallet:corporation", true) and Wallet.ToCorporation then
    Wallet.ToCorporation()
  end
  local _ = Im.Hook("Wallet:mine", true)
  drawWallet(game, x, y, w, h)
  Im.Plain(was)
end)
Windows.Make(Wallet.ID, Wallet.ID, "Wallet", 534, 130, 820, 600, 640, 420, nil)
Windows.Icon(Wallet.ID, "wallet")

return Wallet
