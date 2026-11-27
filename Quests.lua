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
    local profession = quest.requiredSkill
    local rank = profession and addon.Trainers:SkillRank(profession[1])
    if (quest.minLevel and info.level < quest.minLevel) or (rank and rank < profession[2])
        or not prerequisitesMet(quest.prerequisites)
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

function Quests:Requirement(questID)
    local quest = addon.Quest(questID)
    local skill = quest and quest.requiredSkill
    if skill then
        return ("Requires %s %d"):format(data.professions[skill[1]], skill[2])
    end
end

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

function Quests:AddObjectives(tooltip, id, alreadyShown)
    if not inLog(id) or not C_QuestLog.GetQuestObjectives then return end
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
        if readable(objective.text) and type(objective.text) == "string" and objective.text ~= ""
            and objective.text ~= alreadyShown then
            local done = readable(objective.finished) and objective.finished
            tooltip:AddLine(objective.text, done and .55 or 1, done and .8 or 1, .72, true)
        end
    end
end

local function trackedQuest()
    local id = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    if addon.IsReadableNumber(id) and id > 0 and inLog(id) then return id end
    if C_QuestLog.GetQuestIDForQuestWatchIndex then
        local count = C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()
        if addon.IsReadableNumber(count) and count > 0 then
            id = C_QuestLog.GetQuestIDForQuestWatchIndex(1)
            if addon.IsReadableNumber(id) and inLog(id) then return id end
        end
    end
end

local SITE_PATTERN = "(%d+):(%d+):(%d+),(%d+)([noz]%d+)([AH]?);"
local siteQuest, siteFaction, sitesByMap
local function sitesFor(id, faction)
    if siteQuest == id and siteFaction == faction then return sitesByMap end
    siteQuest, siteFaction, sitesByMap = id, faction, {}
    local quest = addon.Quest(id)
    local code = faction == "Alliance" and "A" or (faction == "Horde" and "H")
    for index, zone, x, y, contact, side in data.objectiveSites[id]:gmatch(SITE_PATTERN) do
        if side == "" or side == code then
            local mapID, px, py = tonumber(zone), tonumber(x)/10000, tonumber(y)/10000
            local point = {mapID=mapID, x=px, y=py}
            local list = sitesByMap[mapID] or {}
            sitesByMap[mapID] = list
            list[#list + 1] = {category="quest", role="objective", questID=id, index=tonumber(index), point=point,
                x=px, y=py, mapID=mapID, title=data.questContacts[contact] or quest.name,
                subtitle=quest.name, source=quest}
        end
    end
    return sitesByMap
end

function Quests:ObjectiveSites(mapID)
    local id = trackedQuest()
    if not mapID or not id or not data.objectiveSites[id] or isComplete(id) then return end
    if C_CVar and C_CVar.GetCVarBool then
        local enabled = C_CVar.GetCVarBool("questPOI")
        if readable(enabled) and enabled == false then return end
    end
    local sites = sitesFor(id, UnitFactionGroup("player"))[mapID]
    if not sites then return end
    -- Give the game's own objective pin precedence whenever it has one here.
    if C_QuestLog.GetQuestsOnMap then
        for _, poi in ipairs(C_QuestLog.GetQuestsOnMap(mapID) or {}) do
            if addon.IsReadableNumber(poi.questID) and poi.questID == id and readable(poi.isQuestStart)
                and not poi.isQuestStart and addon.IsReadableNumber(poi.mapID) and poi.mapID == mapID
                and addon.IsReadableNumber(poi.x) and poi.x >= 0 and poi.x <= 1
                and addon.IsReadableNumber(poi.y) and poi.y >= 0 and poi.y <= 1
                and (poi.x > 0 or poi.y > 0) then return end
        end
    end
    local result = {}
    local progress = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {}
    for _, site in ipairs(sites) do
        local objective = progress[site.index]
        if not objective or (readable(objective.finished) and not objective.finished) then
            site.detail = objective and readable(objective.text) and objective.text or nil
            result[#result + 1] = site
        end
    end
    return result
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
