--!strict
-- Characters: the pilots a player has, kept outside any one game.
--
-- The owner's rulings of 2026-11-17 (B3 on the roadmap): a character is
-- kept apart from the saves, so that what is trained by time is not
-- lost with a new game. Every character trains its own queue by real
-- time, all of them at once ("All train at once"), game or no game. A
-- galaxy keeps what is its own: the wallet, ships and items, implants
-- ("Stay in the galaxy"), standings, the corporation. A character's
-- face is a badge from a set, or a picture of the player's own ("Pick
-- from a set + import"). Another of the player's characters can be
-- asked into their corporation in a game, and works there as a member
-- does, with the skills it has ("Members with their own skills").
--
-- What a character is: a name, a face, the skills it knows and their
-- levels, the queue of levels to train, how far into the first of them
-- it is, and when that was so (seconds since 1970). It is plain data,
-- written as lines of text (Characters.Encode), one file each beside
-- the saves (Game/Session). Nothing here reads a clock: whoever calls
-- says what the time is.
--
-- In a game the pilot's character is the game's skills and queue
-- (Characters.Into), trained by real time while the game runs
-- (Core.Credit) and not by the game's own time, which can be run on
-- faster; and what the game has done to them is the character's again
-- when it is saved (Characters.From).

local Constants = require("@lt/Core/Data/Constants")
local Skills = require("@lt/Core/Data/Skills")
local State = require("@lt/Core/Kernel/State")

local Characters = {}

export type Entry = { skill: string, level: number }

export type Character = {
  id: string,            -- a file name: letters, digits and dashes
  name: string,
  portrait: string,      -- "portrait:<n>" of the game's own, "badge:<n>", or "file:<name>" for a picture beside the file
  skills: { [string]: number },
  training: { Entry },
  done: number,          -- seconds into the first level of the queue
  at: number,            -- when 'done' was so: seconds since 1970
  made: number,          -- when the character was made
}

-- How many badges there are (Game/UI/Portrait draws them), and how many
-- portraits the game has: the owner's set of sixteen, 2026-11-17, which
-- are what a face is picked from (a badge is what a character made
-- before then has, and what one whose picture is lost falls back on).
Characters.BADGES = 24
Characters.PORTRAITS = 16
-- The longest a name may be.
Characters.NAME_MOST = 24

-- A file name made from a name: lower case, letters and digits, dashes
-- between; and something, whatever the name was.
function Characters.Slug(name: string): string
  local slug = string.lower(name)
  slug = string.gsub(slug, "[^%w]+", "-")
  slug = string.gsub(slug, "^%-+", "")
  slug = string.gsub(slug, "%-+$", "")
  if slug == "" then
    slug = "pilot"
  end
  return string.sub(slug, 1, 32)
end

-- Whether a name will do for a character, and why not.
function Characters.NameOk(name: string): (boolean, string?)
  local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
  if trimmed == "" then
    return false, "a character needs a name"
  elseif #trimmed > Characters.NAME_MOST then
    return false, `a name is {Characters.NAME_MOST} letters at most`
  elseif string.find(trimmed, "[\n=]") then
    return false, "a name cannot have that in it"
  end
  return true
end

-- A new character: the skills every pilot begins with, nothing queued.
function Characters.New(id: string, name: string, portrait: string, now: number): Character
  return { id = id, name = name, portrait = portrait, skills = Skills.Starting(), training = {}, done = 0, at = now, made = now }
end

local function seconds(entry: Entry): number
  -- (whole ticks, as the game counts them: Character/Training)
  return math.ceil(Skills.TrainingSeconds(Skills.byId[entry.skill], entry.level) / Constants.TICK) * Constants.TICK
end

-- The seconds left of the whole queue.
function Characters.Left(character: Character): number
  local left = -character.done
  for _, entry in character.training do
    left += seconds(entry)
  end
  return math.max(0, left)
end

-- Bring the character's training up to 'now': the levels whose time has
-- come are trained, in order, and the next is that far in. Returns the
-- levels trained. (Time that finds the queue empty goes to nothing.)
function Characters.CatchUp(character: Character, now: number): { Entry }
  local trained: { Entry } = {}
  local gone = math.max(0, now - character.at)
  character.at = math.max(character.at, now)
  while gone > 0 do
    local first = character.training[1]
    if first == nil or Skills.byId[first.skill] == nil then
      if first then
        table.remove(character.training, 1)
      else
        character.done = 0
        break
      end
    else
      local need = seconds(first) - character.done
      if gone >= need then
        gone -= need
        character.skills[first.skill] = math.max(character.skills[first.skill] or 0, first.level)
        table.remove(character.training, 1)
        character.done = 0
        table.insert(trained, first)
      else
        character.done += gone
        gone = 0
      end
    end
  end
  return trained
end

-- The character as text: a line for each thing, key=value.
function Characters.Encode(character: Character): string
  local lines = {
    "character=1", `id={character.id}`, `name={character.name}`, `portrait={character.portrait}`,
    `done={character.done}`, `at={character.at}`, `made={character.made}`,
  }
  local known: { string } = {}
  for skill in character.skills do
    table.insert(known, skill)
  end
  table.sort(known)
  for _, skill in known do
    table.insert(lines, `skill.{skill}={character.skills[skill]}`)
  end
  for _, entry in character.training do
    table.insert(lines, `train={entry.skill}:{entry.level}`)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- A character from its text; nil, and why, if it is not one.
function Characters.Decode(text: string): (Character?, string?)
  local character: Character = { id = "", name = "", portrait = "badge:1", skills = {}, training = {}, done = 0, at = 0, made = 0 }
  local isOne = false
  for line in string.gmatch(text, "[^\n]+") do
    local key, value = string.match(line, "^([%w%._]+)=(.*)$")
    if key and value then
      if key == "character" then
        isOne = true
      elseif key == "id" then
        character.id = value
      elseif key == "name" then
        character.name = value
      elseif key == "portrait" then
        character.portrait = value
      elseif key == "done" then
        character.done = tonumber(value) or 0
      elseif key == "at" then
        character.at = tonumber(value) or 0
      elseif key == "made" then
        character.made = tonumber(value) or 0
      elseif string.sub(key, 1, 6) == "skill." then
        local skill = string.sub(key, 7)
        local level = tonumber(value)
        -- (a skill the game no longer has is let go)
        if level and Skills.byId[skill] then
          character.skills[skill] = math.clamp(math.floor(level), 0, Skills.MAX_LEVEL)
        end
      elseif key == "train" then
        local skill, level = string.match(value, "^([%w%.]+):(%d+)$")
        if skill and level and Skills.byId[skill] then
          table.insert(character.training, { skill = skill, level = tonumber(level) :: number })
        end
      end
    end
  end
  if not isOne or character.id == "" or character.name == "" then
    return nil, "not a character"
  end
  return character, nil
end

-- Put a character into a game, as its pilot: the skills are what both
-- have (the character's, and any the game has given, such as what it
-- takes to fly the ship the pilot begins in); the queue is the
-- character's, that far in; and from now on it is trained by the time
-- the player gives it (Core.Credit), not by the game's ticks.
function Characters.Into(state: State.State, character: Character)
  for skill, level in character.skills do
    state.skills[skill] = math.max(state.skills[skill] or -1, level)
  end
  state.training = table.clone(character.training)
  state.trainingStarted = state.tick - math.floor(character.done / Constants.TICK)
  state.trainingByClock = true
  state.character = character.id
end

-- What a game has made of its pilot, into their character, as of 'now':
-- the skills, and the queue that far in.
function Characters.From(state: State.State, character: Character, now: number)
  for skill, level in state.skills do
    character.skills[skill] = math.max(character.skills[skill] or -1, level)
  end
  character.training = table.clone(state.training)
  character.done = if #state.training > 0 then math.max(0, (state.tick - state.trainingStarted) * Constants.TICK) else 0
  character.at = now
end

-- A game's pilot made into a character (a game saved before there were
-- characters): its skills and queue, as of when it was saved.
function Characters.Adopt(state: State.State, id: string, name: string, savedAt: number): Character
  local character = Characters.New(id, name, `portrait:{(#name % Characters.PORTRAITS) + 1}`, savedAt)
  character.skills = {}
  Characters.From(state, character, savedAt)
  character.made = savedAt
  return character
end

-- How many levels a character has trained in all (a measure of it, for a list).
function Characters.Levels(character: Character): number
  local total = 0
  for _, level in character.skills do
    total += math.max(0, level)
  end
  return total
end

return Characters
