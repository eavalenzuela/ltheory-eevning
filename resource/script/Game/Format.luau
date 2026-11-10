--!strict
-- How numbers are shown to the player.

local Constants = require("@lt/Core/Data/Constants")

local Format = {}

-- 850 m, 12.4 km, 1,250 km, 3.2 AU
function Format.Distance(metres: number): string
  if metres < 1000 then
    return string.format("%d m", math.floor(metres + 0.5))
  elseif metres < 1e5 then
    return string.format("%.1f km", metres / 1000)
  elseif metres < 0.01 * Constants.AU then
    local km = math.floor(metres / 1000 + 0.5)
    local text = tostring(km)
    -- thousands separators
    local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
    if string.sub(grouped, 1, 1) == "," then
      grouped = string.sub(grouped, 2)
    end
    return grouped .. " km"
  end
  return string.format("%.2f AU", metres / Constants.AU)
end

-- 1,250,000
function Format.Whole(n: number): string
  local text = string.format("%d", math.floor(math.abs(n) + 0.5))
  local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
  if string.sub(grouped, 1, 1) == "," then
    grouped = string.sub(grouped, 2)
  end
  return if n < 0 then "-" .. grouped else grouped
end

-- 1,250,000 cr
function Format.Credits(n: number): string
  return Format.Whole(n) .. " cr"
end

-- A price per unit: 20.40 cr below a thousand, 7,231 cr above.
function Format.Price(n: number): string
  return if n < 1000 then string.format("%.2f cr", n) else Format.Credits(n)
end

-- 45 s, 4m 10s, 2h 05m, 3d 04h
function Format.Duration(seconds: number): string
  local s = math.max(0, math.ceil(seconds))
  if s < 60 then
    return `{s} s`
  elseif s < 3600 then
    return string.format("%dm %02ds", s // 60, s % 60)
  elseif s < 86400 then
    return string.format("%dh %02dm", s // 3600, s % 3600 // 60)
  end
  return string.format("%dd %02dh", s // 86400, s % 86400 // 3600)
end

-- The game clock at a tick: day 1, 02:15
function Format.Clock(tick: number): string
  local s = tick * Constants.TICK
  return string.format("day %d, %02d:%02d", s // 86400 + 1, s % 86400 // 3600, s % 3600 // 60)
end

function Format.Speed(metresPerSecond: number): string
  if metresPerSecond < 10000 then
    return string.format("%d m/s", math.floor(metresPerSecond + 0.5))
  elseif metresPerSecond < 0.001 * Constants.AU then
    return string.format("%d km/s", math.floor(metresPerSecond / 1000 + 0.5))
  end
  return string.format("%.2f AU/s", metresPerSecond / Constants.AU)
end

return Format
