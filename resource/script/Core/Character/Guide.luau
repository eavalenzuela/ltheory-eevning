--!strict
-- The guide: the things there are to do, and which of them the pilot
-- has done.
--
-- Each step is one thing done once: undock, warp somewhere, mine a
-- rock, sell something, destroy a pirate, hire a pilot. A step is done
-- when the Core says the thing happened (an event of the tick), and
-- stays done. Nothing is given for it: it is a list to find one's way
-- about by, with a line on how each thing is done.
--
-- (A list of opportunities. Not yet: agents who walk a new
-- pilot through a career.)

local State = require("@lt/Core/Kernel/State")

local Guide = {}

export type Event = { [string]: any }

-- A step: the event that does it, the field of the event that has to
-- be the pilot's own ship (where others cause such events too), and
-- anything more the event has to say.
export type Step = {
  id: string,
  group: string,
  title: string,
  how: string,
  on: string,
  mine: string?,
  also: ((event: Event) -> boolean)?,
}

Guide.steps = {
  { id = "undock", group = "Flying", title = "Undock", on = "Undocked", mine = "ship",
    how = "UNDOCK, at the foot of the station screen." },
  { id = "warp", group = "Flying", title = "Warp somewhere", on = "WarpStarted", mine = "ball",
    how = "Pick a place on the overview, then Warp to (S)." },
  { id = "jump", group = "Flying", title = "Jump to another system", on = "Jumped", mine = "ship",
    how = "Pick a stargate, then Jump (D). The Map (M) plans longer ways." },
  { id = "bookmark", group = "Flying", title = "Mark a place to come back to", on = "Bookmarked",
    how = "Mark, at the top of the overview." },

  { id = "mine", group = "Making a living", title = "Mine an asteroid", on = "Mined", mine = "ball",
    how = "Fit the Mining Laser in the hangar. At a belt, lock a rock (L) and switch it on." },
  { id = "refine", group = "Making a living", title = "Refine ore into minerals", on = "Reprocessed", mine = "ship",
    how = "Industry tab, at a station with a refining array." },
  { id = "sell", group = "Making a living", title = "Sell something", on = "Sold",
    how = "Market tab: pick what you have and sell it." },
  { id = "build", group = "Making a living", title = "Build from a blueprint", on = "JobDone",
    how = "Industry tab. The hangar has a blueprint for rounds: it wants minerals." },
  { id = "job", group = "Making a living", title = "Finish a job for a station", on = "MissionCompleted",
    how = "Missions tab: bounties, courier runs and supply orders." },
  { id = "loyalty", group = "Making a living", title = "Spend loyalty points", on = "LoyaltyRedeemed",
    how = "Jobs earn them. The Missions tab has the faction's store, at the foot." },
  { id = "research", group = "Making a living", title = "Research a blueprint", on = "ResearchDone",
    how = "Industry tab, at a station with a laboratory." },
  { id = "invent", group = "Making a living", title = "Try to invent a tech 2 blueprint", on = "InventionDone",
    how = "Industry tab: Invent tech 2. It wants datacores, which derelicts have." },

  { id = "fit", group = "Fighting", title = "Fit a module", on = "Fitted",
    how = "Fitting tab: a module in the hangar goes into a free slot." },
  { id = "kill", group = "Fighting", title = "Destroy a pirate", on = "WalletChanged",
    also = function(event: Event): boolean
      return event.reason == "bounty"
    end,
    how = "They come to belts. Tab picks one out, L locks it, F1 and F2 fire." },
  { id = "loot", group = "Fighting", title = "Loot a wreck", on = "Looted", mine = "ship",
    how = "Approach the wreck (Q), then Loot." },
  { id = "salvage", group = "Fighting", title = "Salvage a wreck", on = "Salvaged", mine = "ball",
    how = "A Salvager wants the Salvaging skill. What it brings off builds rigs." },
  { id = "drones", group = "Fighting", title = "Launch a drone", on = "DroneLaunched", mine = "owner",
    how = "Drones are bought, carried in the hold and launched in space." },
  { id = "cloak", group = "Fighting", title = "Cloak", on = "Cloaked", mine = "ball",
    how = "A Cloaking Device, switched on before anybody has you targeted." },

  { id = "train", group = "Getting on", title = "Train a skill", on = "SkillTrained",
    how = "Skills tab. A skill not known yet is learned from its book, on the market." },
  { id = "board", group = "Getting on", title = "Board another ship", on = "ShipBoarded",
    how = "Buy a hull on the market, then assemble and board it on the Ships tab." },
  { id = "hire", group = "Getting on", title = "Hire a pilot", on = "PilotHired",
    how = "Crew tab. Give them a second ship and they go where you go." },
  { id = "implant", group = "Getting on", title = "Plug in an implant", on = "ImplantPlugged",
    how = "Skills tab, with Cybernetics. Implants are on the market." },
  { id = "site", group = "Getting on", title = "Find a hidden site", on = "Scanned", mine = "ball",
    also = function(event: Event): boolean
      return (event.found or 0) > 0
    end,
    how = "Scan, at the top of the overview, until a signal is found." },
  { id = "hack", group = "Getting on", title = "Hack a derelict's sealed hold", on = "HackDone",
    also = function(event: Event): boolean
      return event.success == true
    end,
    how = "A Data Analyzer fitted, by a derelict's hull: Hack. Get the safeguards' key in." },
  { id = "colony", group = "Getting on", title = "Found a colony on a planet", on = "ColonyDeployed",
    how = "A Colony Command Centre in the hold, in space by a planet: Colony." },
  { id = "tower", group = "Getting on", title = "Anchor a tower of your own", on = "StarbaseAnchored",
    how = "A control tower in the hold, at a moon: Anchor tower." },
} :: { Step }

Guide.byId = {} :: { [string]: Step }
for _, step in Guide.steps do
  Guide.byId[step.id] = step
end

-- Whether the pilot has done a step.
function Guide.Done(state: State.State, id: string): boolean
  return table.find(state.guide, id) ~= nil
end

-- Once a tick: what the events since 'first' (the place in the list
-- this tick's begin at) say has now been done.
function Guide.Step(state: State.State, events: { Event }, first: number)
  if #state.guide >= #Guide.steps then
    return
  end
  local last = #events
  for at = first, last do
    local event = events[at]
    for _, step in Guide.steps do
      if step.on == event.kind and (step.mine == nil or event[step.mine] == state.player.ship)
        and (step.also == nil or step.also(event)) and not Guide.Done(state, step.id) then
        table.insert(state.guide, step.id)
        table.insert(events, { kind = "Guided", step = step.id, title = step.title, done = #state.guide, of = #Guide.steps })
      end
    end
  end
end

return Guide
