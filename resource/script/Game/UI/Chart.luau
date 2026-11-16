--!strict
-- A chart of a price day by day, with what was traded each day under it.
--
-- Two measures, so two panels on one row of days and never two scales
-- on one: the price as a line above (its scale from a little under its
-- lowest to a little over its highest, the two written at the left),
-- and the units traded as bars below, each as tall as its share of the
-- busiest day. The last day is today, marked with a dot. The cursor
-- over either panel picks a day: a hairline through both, a dot on the
-- line, and the day's place in the series given back, for whoever drew
-- the chart to say what that day was.
--
-- Small ('plain'), it is the line and the bars and nothing written: a
-- glance, on a screen that has other things to say.

local Format = require("@lt/Game/Format")
local Im = require("@lt/Game/UI/Im")
local Theme = require("@lt/Game/UI/Theme")

local Chart = {}

export type Day = { day: number, price: number, volume: number, value: number }

-- The lowest and the highest price of a series.
function Chart.Range(series: { Day }): (number, number)
  local low, high = math.huge, 0
  for _, day in series do
    low, high = math.min(low, day.price), math.max(high, day.price)
  end
  return if low == math.huge then 0 else low, high
end

-- How many units were traded over a series, and what they went for.
function Chart.Traded(series: { Day }): (number, number)
  local units, value = 0, 0
  for _, day in series do
    units += day.volume
    value += day.value
  end
  return units, value
end

-- The most units traded in one day of a series.
function Chart.Busiest(series: { Day }): number
  local most = 0
  for _, day in series do
    most = math.max(most, day.volume)
  end
  return most
end

-- Draw a series in a panel 'w' by 'h' for the price, with a strip
-- 'bars' high under it for what was traded (0: none). Returns the place
-- in the series of the day the cursor is over, if it is over one.
function Chart.Draw(series: { Day }, x: number, y: number, w: number, h: number, bars: number, plain: boolean): number?
  local count = #series
  if count == 0 then
    return nil
  end
  local low, high = Chart.Range(series)
  -- (a price that has not moved is drawn level through the middle; one
  -- that has is given a little room above and below)
  local bottom, top = low, high
  if high - low < high * 0.002 then
    bottom, top = low * 0.95, math.max(high * 1.05, low + 1e-6)
  else
    local room = (high - low) * 0.12
    bottom, top = low - room, high + room
  end
  local slot = w / count
  local gap = if bars > 0 then 6 else 0
  local function at(index: number): (number, number)
    local share = (series[index].price - bottom) / (top - bottom)
    return x + (index - 0.5) * slot, y + h - share * h
  end

  -- The frame: faint lines at the top, the middle and the foot, and
  -- what the top and the foot are worth.
  for _, share in { 0, 0.5, 1 } do
    Im.Fill(x, y + h * share, w, 1, Im.DIM, if share == 0.5 then 0.1 else 0.2)
  end
  if not plain then
    Im.Text(Format.Price(top), x + 4, y + 3, 11, Im.DIM)
    Im.Text(Format.Price(bottom), x + 4, y + h - 15, 11, Im.DIM)
  end

  -- What was traded: a bar a day.
  if bars > 0 then
    local most = Chart.Busiest(series)
    local base = y + h + gap + bars
    Im.Fill(x, base, w, 1, Im.DIM, 0.2)
    local width = math.max(2, math.floor(slot - 2))
    for index, day in series do
      if day.volume > 0 then
        local tall = math.max(2, math.floor(bars * day.volume / most + 0.5))
        Im.Fill(math.floor(x + (index - 0.5) * slot - width / 2), base - tall, width, tall, Im.TEXT, 0.7)
      end
    end
  end

  -- The price: a line from day to day (drawn twice, a pixel apart, for
  -- its weight), and a dot on today.
  for index = 2, count do
    local ax, ay = at(index - 1)
    local bx, by = at(index)
    for lift = 0, 1 do
      -- (a line is the engine's, in pixels)
      Glyph_Draw(Glyph_Line(Theme.Point(ax, ay) + vector.create(0, lift), Theme.Point(bx, by) + vector.create(0, lift), 1, 1), 0, 1, Im.ACCENT, 0.95)
    end
  end
  local lastX, lastY = at(count)
  Im.Fill(math.floor(lastX) - 2, math.floor(lastY) - 2, 5, 5, Im.ACCENT, 1)

  -- The day under the cursor.
  local cursor = Im.Cursor()
  if cursor.x >= x and cursor.x < x + w and cursor.y >= y and cursor.y < y + h + gap + bars then
    local index = math.clamp(math.floor((cursor.x - x) / slot) + 1, 1, count)
    local px, py = at(index)
    Im.Fill(math.floor(px), y, 1, h + gap + bars, Im.TEXT, 0.3)
    Im.Fill(math.floor(px) - 2, math.floor(py) - 2, 5, 5, Im.TEXT, 1)
    return index
  end
  return nil
end

return Chart
