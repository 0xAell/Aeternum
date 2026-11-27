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

local function call(namespace, method, ...)
    local api = namespace and namespace[method]
    if api then
        return api(...)
    end
end

local function completedAPI()
    return (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
end

local function isCompleted(questID)
    local api = completedAPI()
    return api and api(questID) and true or false
end

local function logIndex(questID)
    local index = call(C_QuestLog, "GetLogIndexForQuestID", questID)
    if index == nil and GetQuestLogIndexByID then
        index = GetQuestLogIndexByID(questID)
    end
    return index and index > 0 and index or nil
end

-- IsOnQuest also sees quests under a collapsed quest log header.
local function inLog(questID)
    local onQuest = call(C_QuestLog, "IsOnQuest", questID)
    if onQuest ~= nil then
        return onQuest and true or false
    end
    return logIndex(questID) ~= nil
end

local function isComplete(questID)
    local complete = call(C_QuestLog, "IsComplete", questID)
    if complete == nil and IsQuestComplete then
        complete = IsQuestComplete(questID)
    end
    if complete == nil and GetQuestLogTitle then
        local index = logIndex(questID)
        complete = index and select(6, GetQuestLogTitle(index)) == 1
    end
    return complete and true or false
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
        local range = (GetQuestGreenRange and GetQuestGreenRange())
            or (UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange("player"))
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
    local quest = data.quests[questID]
    if not quest then
        return "unknown"
    end
    -- A quest in the log can always be turned in, whatever rule would keep it from being offered.
    if inLog(questID) then
        return isComplete(questID) and "ready" or "active"
    end
    local info = playerInfo()
    if not allows(quest.races, info.raceMask) or not allows(quest.classes, info.classMask)
        or quest.event or (quest.maxLevel and info.level > quest.maxLevel)
        or (quest.availableUntilCompleted and isCompleted(quest.availableUntilCompleted))
        or exclusiveTaken(quest.exclusiveTo) then
        return "unavailable"
    end
    if isCompleted(questID) and not quest.repeatable then
        return "done"
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

-- True when the client reports quest completion, so states can be trusted.
function Quests:CanTrackProgress()
    return completedAPI() ~= nil
end

function Quests:State(questID)
    if not self:CanTrackProgress() then
        return "unknown"
    end
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

function Quests:IsPinVisible(entry)
    local settings = addon.settings
    if settings.questMode == "all" or not self:CanTrackProgress() then
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
    local quest = data.quests[questID]
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
