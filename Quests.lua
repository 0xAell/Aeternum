local _, addon = ...

-- Decides what the player can do with each quest, from the bundled quest rules
-- and the client's quest log and completion records.
local Quests = {}
addon.Quests = Quests

local data = addon.Data
local states = {}
local player = {}

local styles = {
    available = { label = "Available", color = { 1, .82, 0 } },
    trivial = { label = "Low level", color = { .62, .62, .62 } },
    ready = { label = "Ready to turn in", color = { 1, .82, 0 } },
    active = { label = "In your quest log", color = { .78, .78, .78 } },
    done = { label = "Completed", color = { .4, .75, .4 } },
    locked = { label = "Not yet available", color = { .5, .5, .5 } },
    unavailable = { label = "Not for this character", color = { .45, .45, .45 } },
    unknown = { label = "Reference location", color = { 1, .89, .54 } },
}
local turnInStyles = {
    available = { label = "Turn-in after accepting", color = { .62, .62, .62 } },
    trivial = styles.trivial,
}

-- Masks can pass 2^32, so they are tested with arithmetic rather than bit operations.
local function hasFlag(mask, flag)
    return mask % (2 * flag) >= flag
end

local function isCompleted(questID)
    return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
end

-- IsOnQuest also sees quests under a collapsed quest log header.
local function inLog(questID)
    return C_QuestLog.IsOnQuest(questID) and true or false
end

local function isComplete(questID)
    return C_QuestLog.IsComplete(questID) and true or false
end

local function started(questID)
    return inLog(questID) or isCompleted(questID)
end

local function playerInfo()
    if not player.level then
        local level = UnitLevel("player") or 1
        player.level = math.max(level, player.newLevel or 0)
        local raceID = select(3, UnitRace("player"))
        local class = select(2, UnitClass("player"))
        player.raceMask = raceID and data.raceMasks[raceID]
        player.classMask = class and data.classMasks[class]
        -- The same rule the client uses to grey out quests (GetQuestDifficultyColor).
        local range = UnitQuestTrivialLevelRange("player")
        player.greenRange = type(range) == "number" and range or nil
    end
    return player
end

local function allows(mask, playerMask)
    return not mask or not playerMask or hasFlag(mask, playerMask)
end

local function anyCompleted(list)
    for _, questID in ipairs(list) do
        if isCompleted(questID) then
            return true
        end
    end
    return false
end

local function prerequisitesMet(prerequisites)
    if not prerequisites then
        return true
    end
    for _, questID in ipairs(prerequisites.all or {}) do
        if not isCompleted(questID) then
            return false
        end
    end
    return not prerequisites.any or anyCompleted(prerequisites.any)
end

local function exclusiveTaken(list)
    for _, questID in ipairs(list or {}) do
        if started(questID) then
            return true
        end
    end
    return false
end

local function evaluate(questID)
    local quest = addon.Quest(questID)
    if not quest then
        return "unknown"
    end
    -- A quest in the log can always be turned in, whatever rule would keep it from being offered.
    if inLog(questID) then
        return isComplete(questID) and "ready" or "active"
    end
    if isCompleted(questID) and not quest.repeatable then
        return "done"
    end
    local info = playerInfo()
    if not allows(quest.races, info.raceMask) or not allows(quest.classes, info.classMask)
        or quest.event or (quest.maxLevel and info.level > quest.maxLevel)
        or (quest.availableUntilCompleted and isCompleted(quest.availableUntilCompleted))
        or exclusiveTaken(quest.exclusiveTo) then
        return "unavailable"
    end
    if (quest.minLevel and info.level < quest.minLevel) or not prerequisitesMet(quest.prerequisites)
        or (quest.availableStartingWith and not started(quest.availableStartingWith))
        or (quest.disabledByQuest and inLog(quest.disabledByQuest)) then
        return "locked"
    end
    if quest.level and info.greenRange and info.level - quest.level > info.greenRange then
        return "trivial"
    end
    return "available"
end

function Quests:State(questID)
    local state = states[questID]
    if not state then
        state = evaluate(questID)
        states[questID] = state
    end
    return state
end

function Quests:Style(state, role)
    return role == "turnin" and turnInStyles[state] or styles[state] or styles.unknown
end

function Quests:Icon(state, role)
    if role == "turnin" then return 132048, state ~= "ready" end
    return 132049, state ~= "available"
end

function Quests:IsPinVisible(entry)
    local settings = addon.settings
    if settings.questMode == "all" then
        return true
    end
    local state = self:State(entry.questID)
    if entry.role == "turnin" then
        return state == "active" or state == "ready"
    end
    return state == "available" or (state == "trivial" and settings.lowLevelQuests)
end

-- A short requirement note for a quest that needs something the addon cannot check.
function Quests:Requirement(questID)
    local quest = addon.Quest(questID)
    local skill = quest and quest.requiredSkill
    if skill then
        return ("Requires %s %d"):format(data.professions[skill[1]], skill[2])
    end
end

-- Forget cached states. newLevel is the level from PLAYER_LEVEL_UP, which can
-- arrive before UnitLevel reports it; it is kept until UnitLevel catches up.
function Quests:Invalidate(newLevel)
    local level = newLevel or player.newLevel
    wipe(states)
    wipe(player)
    if level and level > (UnitLevel("player") or 0) then
        player.newLevel = level
    end
end
