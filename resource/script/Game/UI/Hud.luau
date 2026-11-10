--!strict
-- The in-space interface, drawn every frame by one widget.

local Colors = require("@lt/Colors")
local Core = require("@lt/Core/Api")
local Fonts = require("@lt/Fonts")
local Format = require("@lt/Game/Format")
local Scene = require("@lt/Game/View/Scene")
local Session = require("@lt/Game/Session")

local Hud = {}

local overInterface = false

-- Whether the cursor was over a panel last frame (the camera then leaves
-- the mouse alone).
function Hud.CursorOverInterface(): boolean
  return overInterface
end

local function text(s: string, x: number, y: number, size: number, color: vector, alpha: number)
  WidgetRenderer_DrawText(Fonts.Default(), s, vector.create(x, y + 0.8 * size), size, color, alpha, false)
end

function Hud.Create(session: Session.Session, scene: Scene.Scene): Widget
  return Widget_Luau(Widget_Create(), {
    PostDraw = function(_, w: Widget)
      overInterface = false
      local game = session.game
      local player = Core.Query.Player(game)
      local ball = Core.Query.Ball(game, player.ship)
      local x, y = w.pos.x + 24, w.pos.y + 20
      text(player.systemName, x, y, 28, Colors.White, 1)
      y += 34
      if ball then
        local speed = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
        local doing = if ball.warp then (if ball.warp.stage == "warp" then "warping" else "aligning") else ball.mode
        text(`{player.shipName}  {Format.Speed(speed)}  {doing}`, x, y, 18, Colors.Primary, 1)
      else
        local station = Core.Query.Body(game, player.docked)
        text(`Docked at {if station then station.name else "?"}`, x, y, 18, Colors.Primary, 1)
      end
      y += 24
      text(`tick {game.state.tick}  x{session.clock.scale}{if session.clock.paused then "  PAUSED" else ""}`,
        x, y, 14, Colors.Gray, 1)
      if session.message ~= "" and game.state.tick - session.messageTick < 8 then
        text(session.message, x, y + 22, 16, Colors.Secondary, 1)
      end
    end,
  })
end

return Hud
