local _, addon = ...

local data = addon.Data
local categoryOrder = { dungeon = 1, class = 2, profession = 3, quest = 4 }
local questRoles = { s = "Quest start", t = "Quest turn-in" }
local factionCodes = { A = "Alliance", H = "Horde" }

addon.categories = {
    { id = "dungeon", label = "Dungeons", letter = "D", color = { 1, .71, .33 } },
    { id = "class", label = "Class trainers", letter = "C", color = { .63, .81, 1 } },
    { id = "profession", label = "Profession trainers", letter = "P", color = { .53, .89, .68 } },
    { id = "quest", label = "Quests", letter = "Q", color = { 1, .89, .54 } },
}
addon.categoryByID = {}
for _, category in ipairs(addon.categories) do
    addon.categoryByID[category.id] = category
end

local defaults = {
    questMode = "available",
    lowLevelQuests = true,
    pinsWithPanelClosed = false,
    panelOpen = false,
}

function addon.DungeonLevel(dungeon)
    local low, high = dungeon.levelMin, dungeon.levelMax
    if low and high and low ~= high then
        return ("Levels %d–%d"):format(low, high)
    elseif low or high then
        return ("Level %d"):format(low or high)
    end
end

-- Quests ---------------------------------------------------------------------

-- Field order of the packed quest strings written by tools/import_norgannon.lua.
local QUEST_FIELDS = {
    "name", "level", "minLevel", "maxLevel", "races", "classes", "requiresAll", "requiresAny",
    "exclusiveTo", "availableStartingWith", "availableUntilCompleted", "disabledByQuest",
    "requiredSkill", "repeatable", "event",
}
local LIST_FIELDS = { requiresAll = true, requiresAny = true, exclusiveTo = true }
local FLAG_FIELDS = { repeatable = true, event = true }

local function split(text, separator)
    local fields, start = {}, 1
    while true do
        local stop = text:find(separator, start, true)
        fields[#fields + 1] = text:sub(start, (stop or 0) - 1)
        if not stop then
            return fields
        end
        start = stop + 1
    end
end

local function decodeQuest(packed)
    local quest = {}
    for index, value in ipairs(split(packed, "|")) do
        local field = QUEST_FIELDS[index]
        if value ~= "" then
            if index == 1 then
                quest.name = value
            elseif LIST_FIELDS[field] then
                local ids = {}
                for id in value:gmatch("%d+") do
                    ids[#ids + 1] = tonumber(id)
                end
                quest[field] = ids
            elseif FLAG_FIELDS[field] then
                quest[field] = true
            elseif field == "requiredSkill" then
                local skill, rank = value:match("^(%d+):(%d+)$")
                quest.requiredSkill = { tonumber(skill), tonumber(rank) }
            else
                quest[field] = tonumber(value)
            end
        end
    end
    if quest.requiresAll or quest.requiresAny then
        quest.prerequisites = { all = quest.requiresAll, any = quest.requiresAny }
    end
    quest.requiresAll, quest.requiresAny = nil, nil
    return quest
end

local quests = {}

-- The quest's name and rules, decoded on first use; nil for an unknown quest.
function addon.Quest(questID)
    local quest = quests[questID]
    if quest == nil then
        local packed = data.quests[questID]
        quest = packed and decodeQuest(packed) or false
        quests[questID] = quest
    end
    return quest or nil
end

-- Records --------------------------------------------------------------------

local function record(category, title, subtitle, point, source)
    return {
        category = category, title = title, subtitle = subtitle,
        mapID = point and point.mapID, x = point and point.x, y = point and point.y,
        faction = point and point.faction, source = source, point = point,
    }
end

local function ordered(a, b)
    local groupA, groupB = categoryOrder[a.category], categoryOrder[b.category]
    if groupA ~= groupB then
        return groupA < groupB
    elseif a.title ~= b.title then
        return a.title < b.title
    end
    return a.subtitle < b.subtitle
end

-- Dungeons and trainers are few, so they are indexed by map at load. Quest pins
-- stay packed until their map is first shown.
local dungeonRecords = {}
local staticByMap = {}

local function addStatic(entry)
    local entries = staticByMap[entry.mapID]
    if not entries then
        entries = {}
        staticByMap[entry.mapID] = entries
    end
    entries[#entries + 1] = entry
end

for _, dungeon in ipairs(data.dungeons) do
    local levels = addon.DungeonLevel(dungeon)
    dungeonRecords[#dungeonRecords + 1] = record("dungeon", dungeon.name, levels or "Dungeon", nil, dungeon)
    for _, entrance in ipairs(dungeon.entrances) do
        local subtitle = entrance.label or "Dungeon entrance"
        if levels then
            subtitle = subtitle .. " · " .. levels
        end
        addStatic(record("dungeon", dungeon.name, subtitle, entrance, dungeon))
    end
end
table.sort(dungeonRecords, ordered)

for _, trainer in ipairs(data.trainers) do
    addStatic(record(trainer.kind, trainer.name, trainer.specialty or "Trainer", trainer, trainer))
end

local PIN_PATTERN = "(%d+)([st])([AH]?)(%d+),(%d+);"

local function questRecord(questID, role, faction, x, y, mapID)
    local quest = addon.Quest(questID)
    local subtitle = questRoles[role]
    if quest.level then
        subtitle = subtitle .. " · Level " .. quest.level
    end
    local point = { mapID = mapID, x = x / 10000, y = y / 10000, faction = factionCodes[faction] }
    local entry = record("quest", quest.name, subtitle, point, quest)
    entry.questID, entry.role = questID, role == "s" and "start" or "turnin"
    return entry
end

local mapRecords = {}

-- Every record on a world map, sorted, built the first time the map is shown.
function addon.MapRecords(mapID)
    local entries = mapRecords[mapID]
    if entries then
        return entries
    end
    entries = {}
    for _, entry in ipairs(staticByMap[mapID] or {}) do
        entries[#entries + 1] = entry
    end
    local packed = data.questPins[mapID]
    if packed then
        for questID, role, faction, x, y in packed:gmatch(PIN_PATTERN) do
            entries[#entries + 1] = questRecord(tonumber(questID), role, faction, tonumber(x), tonumber(y), mapID)
        end
    end
    table.sort(entries, ordered)
    mapRecords[mapID] = entries
    return entries
end

local startMaps

-- The first recorded start of a quest that the player's faction can use.
function addon.QuestStart(questID)
    if not startMaps then
        startMaps = {}
        for mapID, packed in pairs(data.questPins) do
            for id, role in packed:gmatch(PIN_PATTERN) do
                id = tonumber(id)
                local list = startMaps[id]
                if role == "s" and (not list or list[#list] ~= mapID) then
                    if not list then
                        list = {}
                        startMaps[id] = list
                    end
                    list[#list + 1] = mapID
                end
            end
        end
    end
    local faction = UnitFactionGroup("player")
    for _, mapID in ipairs(startMaps[questID] or {}) do
        for _, entry in ipairs(addon.MapRecords(mapID)) do
            if entry.questID == questID and entry.role == "start" and addon.FactionAllowed(entry, faction) then
                return entry
            end
        end
    end
end

-- Settings -------------------------------------------------------------------

function addon.LoadSettings()
    if type(AeternumDB) ~= "table" then
        AeternumDB = {}
    end
    if type(AeternumDB.filters) ~= "table" then
        AeternumDB.filters = {}
    end
    for key, value in pairs(defaults) do
        if type(AeternumDB[key]) ~= type(value) then
            AeternumDB[key] = value
        end
    end
    if AeternumDB.questMode ~= "all" then
        AeternumDB.questMode = "available"
    end
    addon.settings = AeternumDB
end

function addon.ResetSettings()
    AeternumDB = nil
    addon.LoadSettings()
end

function addon.CategoryEnabled(id)
    return addon.settings.filters[id] ~= false
end

-- Queries --------------------------------------------------------------------

function addon.FactionAllowed(entry, faction)
    return not entry.faction or not faction or entry.faction == faction
end

local function visible(entry, faction)
    if not addon.FactionAllowed(entry, faction) then
        return false
    end
    if entry.category == "quest" then
        return addon.Quests:IsPinVisible(entry)
    end
    return true
end

local function matches(entry, search)
    if search == "" then
        return true
    end
    if not entry.search then
        entry.search = (entry.title .. " " .. entry.subtitle):lower()
    end
    return entry.search:find(search, 1, true) ~= nil
end

-- Returns the records on a world map, or every dungeon when atlas is true.
function addon.Entries(mapID, atlas, query)
    local result = {}
    local candidates = atlas and dungeonRecords or (mapID and addon.MapRecords(mapID)) or {}
    local search = strtrim(query or ""):lower()
    local faction = UnitFactionGroup("player")
    for _, entry in ipairs(candidates) do
        if (atlas or addon.CategoryEnabled(entry.category)) and visible(entry, faction)
            and matches(entry, search) then
            result[#result + 1] = entry
        end
    end
    return result
end

-- Letter, colour, and subtitle for a record as the player currently sees it.
function addon.Presentation(entry)
    local category = addon.categoryByID[entry.category]
    if entry.category ~= "quest" then
        return category.letter, category.color, entry.subtitle
    end
    local style = addon.Quests:Style(addon.Quests:State(entry.questID), entry.role)
    if entry.style ~= style then
        entry.style, entry.styledSubtitle = style, entry.subtitle .. " · " .. style.label
    end
    return entry.role == "turnin" and "?" or "!", style.color, entry.styledSubtitle
end

function addon.ZoneName(mapID)
    local map = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return map and map.name or "Current map"
end

-- Items ----------------------------------------------------------------------

function addon.ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if name and name ~= "" then
        return name
    end
    return data.items[itemID] or ("Item " .. itemID)
end

local qualityColors = {}

function addon.ItemQualityColor(itemID)
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    if not quality or not C_Item.GetItemQualityColor then
        return nil
    end
    local color = qualityColors[quality]
    if not color then
        local red, green, blue = C_Item.GetItemQualityColor(quality)
        color = red and { red, green, blue } or false
        qualityColors[quality] = color
    end
    return color or nil
end

function addon.ItemIcon(itemID)
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
end

-- A full hyperlink when the client has the item cached, and a bare item string.
function addon.ItemLink(itemID)
    local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID))
    return link, "item:" .. itemID
end

function addon.RequestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end
