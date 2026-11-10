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

function Format.Speed(metresPerSecond: number): string
  if metresPerSecond < 10000 then
    return string.format("%d m/s", math.floor(metresPerSecond + 0.5))
  elseif metresPerSecond < 0.001 * Constants.AU then
    return string.format("%d km/s", math.floor(metresPerSecond / 1000 + 0.5))
  end
  return string.format("%.2f AU/s", metresPerSecond / Constants.AU)
end

return Format
