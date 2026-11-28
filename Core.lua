local _, addon = ...

local data = addon.Data
local categoryOrder = { dungeon = 1, weapon = 2, class = 3, profession = 4, quest = 5 }
local questRoles = { s = "Quest start", t = "Quest turn-in" }
local factionCodes = { A = "Alliance", H = "Horde" }

function addon.IsReadableNumber(value)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

function addon.Trim(value)
    if type(value) ~= "string" then return "" end
    return strtrim and strtrim(value) or value:match("^%s*(.-)%s*$")
end

addon.categories = {
    { id = "dungeon", label = "Dungeon entrances", icon = "Dungeon" },
    { id = "class", label = "Class trainers", icon = 136455 },
    { id = "profession", label = "Profession trainers", icon = 136463 },
    { id = "weapon", label = "Weapon masters", icon = 135274 },
    { id = "quest", label = "Quests" },
}
addon.categoryByID = {}
for _, category in ipairs(addon.categories) do
    addon.categoryByID[category.id] = category
end

local defaults = {
    questMode = "available",
    lowLevelQuests = false,
    otherTrainers = false,
    atlasTerrain = true,
}

function addon.DungeonLevel(dungeon, short)
    local low, high = dungeon.levelMin, dungeon.levelMax
    if low and high and low ~= high then
        return (short and "%d–%d" or "Levels %d–%d"):format(low, high)
    elseif low or high then
        return (short and "%d" or "Level %d"):format(low or high)
    end
end

function addon.ColorText(text, r, g, b)
    if not r then return text end
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + .5) end
    return ("|cff%02x%02x%02x%s|r"):format(byte(r), byte(g), byte(b), text)
end

-- A level range in the game's quest difficulty colours, seen from the character's level:
-- red or orange above it, yellow inside the range, green below it, grey once trivial.
function addon.LevelColor(low, high)
    low, high = low or high, high or low
    local level = UnitLevel("player")
    if not low or not addon.IsReadableNumber(level) or not GetRelativeDifficultyColor then return end
    local color = GetRelativeDifficultyColor(level, math.max(low, math.min(high, level)))
    if type(color) == "table" and color.r then return color.r, color.g, color.b end
end

function addon.ColoredDungeonLevel(dungeon, short)
    local text = addon.DungeonLevel(dungeon, short)
    return text and addon.ColorText(text, addon.LevelColor(dungeon.levelMin, dungeon.levelMax))
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
    local groupA, groupB = categoryOrder[a.category] or 99, categoryOrder[b.category] or 99
    if groupA ~= groupB then
        return groupA < groupB
    elseif (a.title or "") ~= (b.title or "") then
        return (a.title or "") < (b.title or "")
    end
    if (a.subtitle or "") ~= (b.subtitle or "") then return (a.subtitle or "") < (b.subtitle or "") end
    if (a.x or 0) ~= (b.x or 0) then return (a.x or 0) < (b.x or 0) end
    return (a.y or 0) < (b.y or 0)
end

-- Dungeons and trainers are few, so they are indexed by map at load. Quest pins
-- stay packed until their map is first shown.
local dungeonRecords = {}
local staticByMap = {}
local entrancesByDungeon = {}

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
    local doors = {}
    entrancesByDungeon[dungeon.id] = doors
    for _, entrance in ipairs(dungeon.entrances) do
        local subtitle = entrance.label or "Dungeon entrance"
        if #dungeon.entrances > 1 then
            subtitle = ("%s · %.1f, %.1f"):format(subtitle, entrance.x * 100, entrance.y * 100)
        end
        if levels then
            subtitle = subtitle .. " · " .. levels
        end
        local door = record("dungeon", dungeon.name, subtitle, entrance, dungeon)
        doors[#doors + 1] = door
        addStatic(door)
    end
end
table.sort(dungeonRecords, ordered)

local byLevel
-- Every dungeon and wing from the lowest level range to the highest.
function addon.DungeonsByLevel()
    if not byLevel then
        byLevel = {}
        for _, entry in ipairs(dungeonRecords) do byLevel[#byLevel + 1] = entry end
        table.sort(byLevel, function(a, b)
            local x, y = a.source.levelMin or math.huge, b.source.levelMin or math.huge
            if x ~= y then return x < y end
            x, y = a.source.levelMax or math.huge, b.source.levelMax or math.huge
            if x ~= y then return x < y end
            return a.title < b.title
        end)
    end
    return byLevel
end

function addon.DungeonEntrances(dungeon, selectedPoint, viewedMap)
    local list = dungeon and entrancesByDungeon[dungeon.id]
    if not list then return {} end
    local doors, preferred = {}, nil
    local faction = UnitFactionGroup("player")
    for _, door in ipairs(list) do
        if addon.FactionAllowed(door, faction) then
            doors[#doors + 1] = door
            if door.point == selectedPoint or (not preferred and door.mapID == viewedMap) then preferred = #doors end
        end
    end
    if preferred and preferred > 1 then table.insert(doors, 1, table.remove(doors, preferred)) end
    return doors
end

for _, trainer in ipairs(data.trainers) do
    addStatic(record(trainer.kind, trainer.name, trainer.specialty or "Trainer", trainer, trainer))
end

local PIN_PATTERN = "(%d+)([st])([AH]?)(%d+),(%d+)([no]%d+);"

local function questRecord(questID, role, faction, x, y, contact, mapID)
    local quest = addon.Quest(questID)
    if not quest then return end
    local subtitle = questRoles[role]
    if quest.level then
        subtitle = subtitle .. " · Level " .. quest.level
    end
    local point = { mapID = mapID, x = x / 10000, y = y / 10000, faction = factionCodes[faction] }
    local entry = record("quest", quest.name, subtitle, point, quest)
    entry.questID, entry.role = questID, role == "s" and "start" or "turnin"
    entry.contact = data.questContacts[contact]
    return entry
end

local mapRecords = {}

local function isAncestor(zone, target)
    for _ = 1, 8 do
        if zone == target then return true end
        local info = C_Map.GetMapInfo(zone)
        if not info or not info.parentMapID or info.parentMapID == 0 then return false end
        zone = info.parentMapID
    end
    return false
end

local function projectEntrance(door, allowEdge, left, right, top, bottom)
    if addon.IsReadableNumber(left) and addon.IsReadableNumber(right)
        and addon.IsReadableNumber(top) and addon.IsReadableNumber(bottom)
        and right > left and bottom > top then
        local x, y = left + door.x * (right - left), top + door.y * (bottom - top)
        if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
        -- Ragefire is just north of the Durotar artwork. Keep the pin visible at the edge.
        if allowEdge and x >= -.01 and x <= 1.01 and y >= -.01 and y <= 1.01 then
            return math.max(.02, math.min(.98, x)), math.max(.02, math.min(.98, y)), true
        end
    end
end

local function overviewEntrances(entries, mapID)
    local bounds = addon.overviewBounds[mapID]
    local types = Enum and Enum.UIMapType
    local info = types and C_Map.GetMapInfo(mapID)
    if not bounds and not (info and (info.mapType == types.Continent or info.mapType == types.World)) then return end
    local zone = info and info.mapType == types.Zone
    for _, dungeon in ipairs(data.dungeons) do
        local levels = addon.DungeonLevel(dungeon)
        for _, door in ipairs(dungeon.entrances) do
            local x, y, atEdge
            if C_Map.GetMapRectOnMap and door.mapID ~= mapID and isAncestor(door.mapID, mapID) then
                x, y = projectEntrance(door, false, C_Map.GetMapRectOnMap(door.mapID, mapID))
            end
            local fallback = bounds and bounds[door.mapID]
            if not x and fallback then x, y, atEdge = projectEntrance(door, zone, unpack(fallback)) end
            if x then
                local subtitle = addon.ZoneName(door.mapID)
                if atEdge then subtitle = subtitle .. " · Beyond the map edge" end
                if levels then subtitle = subtitle .. " · " .. levels end
                local entry = record("dungeon", dungeon.name, subtitle, door, dungeon)
                entry.mapID, entry.x, entry.y = mapID, x, y
                entries[#entries + 1] = entry
            end
        end
    end
end

-- Every record on a world map, sorted, built the first time the map is shown.
function addon.MapRecords(mapID)
    local entries = mapRecords[mapID]
    if entries then
        return entries
    end
    entries = {}
    overviewEntrances(entries, mapID)
    for _, entry in ipairs(staticByMap[mapID] or {}) do
        entries[#entries + 1] = entry
    end
    local packed = data.questPins[mapID]
    if packed then
        for questID, role, faction, x, y, contact in packed:gmatch(PIN_PATTERN) do
            local entry = questRecord(tonumber(questID), role, faction, tonumber(x), tonumber(y), contact, mapID)
            if entry then entries[#entries + 1] = entry end
        end
    end
    table.sort(entries, ordered)
    mapRecords[mapID] = entries
    return entries
end

local locations, indexedFaction
local function locationMaps(questID, role)
    local faction = UnitFactionGroup("player")
    if faction ~= "Alliance" and faction ~= "Horde" then faction = nil end
    local key = role == "turnin" and "t" or "s"
    if locations and indexedFaction == faction then return locations[key][questID] end
    indexedFaction = faction
    locations = {s={}, t={}}
    local maps = {}
    for mapID in pairs(data.questPins) do maps[#maps + 1] = mapID end
    table.sort(maps)
    for _, mapID in ipairs(maps) do
        for raw, kind, side in data.questPins[mapID]:gmatch(PIN_PATTERN) do
            if side == "" or not faction or factionCodes[side] == faction then
                local id = tonumber(raw)
                local list = locations[kind][id]
                if not list then list = {}; locations[kind][id] = list end
                if list[#list] ~= mapID then list[#list + 1] = mapID end
            end
        end
    end
    return locations[key][questID]
end

function addon.HasQuestLocation(questID, role)
    return locationMaps(questID, role) ~= nil
end

function addon.QuestLocation(questID, role, preferredMap)
    local maps = locationMaps(questID, role)
    if not maps then return end
    local playerMap = C_Map.GetBestMapForUnit("player")
    if issecretvalue and issecretvalue(playerMap) then playerMap = nil end
    local selected = maps[1]
    for _, mapID in ipairs(maps) do
        if mapID == preferredMap then selected = mapID; break end
        if mapID == playerMap then selected = mapID end
    end
    for _, entry in ipairs(addon.MapRecords(selected)) do
        if entry.questID == questID and entry.role == role and addon.FactionAllowed(entry, indexedFaction) then
            return entry
        end
    end
end

function addon.QuestStart(questID) return addon.QuestLocation(questID, "start") end

-- Settings -------------------------------------------------------------------

function addon.LoadSettings()
    if type(AeternumDB) ~= "table" then
        AeternumDB = {}
    end
    if type(AeternumDB.filters) ~= "table" then
        AeternumDB.filters = {}
    end
    AeternumDB.showMapPins, AeternumDB.pinsWithPanelClosed, AeternumDB.panelOpen = nil, nil, nil
    if type(AeternumTrainerDB) ~= "table" then AeternumTrainerDB = {} end
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
    local filters = addon.settings and addon.settings.filters
    return not filters or filters[id] ~= false
end

-- Queries --------------------------------------------------------------------

function addon.FactionAllowed(entry, faction)
    return not entry.faction or (faction ~= "Alliance" and faction ~= "Horde") or entry.faction == faction
end

local function visible(entry, faction)
    if not addon.FactionAllowed(entry, faction) then
        return false
    end
    if entry.category == "quest" then
        return addon.Quests:IsPinVisible(entry)
    end
    if entry.category ~= "dungeon" and not (addon.settings and addon.settings.otherTrainers) then
        return addon.Trainers:Relevant(entry.source)
    end
    return true
end

local function searchWords(query)
    local text = addon.Trim(query):lower()
    if text == "" then return end
    local words = {}
    for word in text:gmatch("%S+") do words[#words + 1] = word end
    return words
end

local foldedNames = {}
local function foldedName(name)
    local folded = foldedNames[name]
    if not folded then
        folded = name:lower()
        foldedNames[name] = folded
    end
    return folded
end

local function containsWords(words, name, boss, dungeon)
    for _, word in ipairs(words) do
        if not name:find(word, 1, true) and not (boss and boss:find(word, 1, true))
            and not (dungeon and dungeon:find(word, 1, true)) then return false end
    end
    return true
end

local function matches(entry, words)
    if not words then return true end
    if not entry.search then
        local parts = {entry.title, entry.subtitle, entry.contact}
        if entry.category == "dungeon" then
            for _, boss in ipairs(entry.source.bosses) do parts[#parts + 1] = boss.name end
        end
        entry.search = table.concat(parts, " "):lower()
    end
    return containsWords(words, entry.search)
end

-- Match the most specific result a query asks for. Searching a dungeon's
-- name alone should not also list every item from that dungeon.
local function dungeonResults(words)
    local result, bosses, drops = {}, {}, {}
    local usable = words and addon.LootFilter()
    for _, entry in ipairs(dungeonRecords) do
        local dungeon = entry.source
        local parent = foldedName(dungeon.name)
        if not words or containsWords(words, parent, foldedName(entry.subtitle)) then
            result[#result + 1] = entry
        else
            for index, boss in ipairs(dungeon.bosses) do
                local bossName = foldedName(boss.name)
                if containsWords(words, bossName, parent) then
                    local hit = record("dungeon", boss.name, dungeon.name, nil, dungeon)
                    hit.bossIndex = index
                    bosses[#bosses + 1] = hit
                else
                    for _, id in ipairs(boss.loot) do
                        local name = data.items[id]
                        if name and containsWords(words, foldedName(name), bossName, parent) and usable(id) then
                            local hit = record("dungeon", name, boss.name .. " · " .. dungeon.name, nil, dungeon)
                            hit.bossIndex, hit.itemID = index, id
                            drops[#drops + 1] = hit
                        end
                    end
                end
            end
        end
    end
    for _, boss in ipairs(bosses) do result[#result + 1] = boss end
    for _, drop in ipairs(drops) do result[#result + 1] = drop end
    return result
end

-- Returns the records on a world map, or every dungeon when atlas is true.
function addon.Entries(mapID, atlas, query)
    local search = searchWords(query)
    if atlas then return dungeonResults(search) end
    local result = {}
    local candidates = mapID and addon.MapRecords(mapID) or {}
    local faction = UnitFactionGroup("player")
    for _, entry in ipairs(candidates) do
        if addon.CategoryEnabled(entry.category) and visible(entry, faction)
            and matches(entry, search) then
            result[#result + 1] = entry
        end
    end
    if addon.CategoryEnabled("quest") then
        for _, entry in ipairs(addon.Quests:ObjectiveSites(mapID) or {}) do
            if matches(entry, search) then result[#result + 1] = entry end
        end
    end
    return result
end

-- Choose the Blizzard icon and tooltip for a map pin.
function addon.Presentation(entry)
    local category = addon.categoryByID[entry.category]
    if entry.category == "dungeon" then
        -- The level range at the end of the line takes the character's difficulty colour.
        local levels, text = addon.DungeonLevel(entry.source), entry.subtitle
        if levels and text:sub(-#levels) == levels then
            text = text:sub(1, -#levels - 1) .. addon.ColoredDungeonLevel(entry.source)
        end
        return category.icon, nil, text
    end
    if entry.category ~= "quest" then
        return category.icon, nil, entry.subtitle
    end
    if entry.role == "objective" then
        return "Quest-In-Progress-Icon-yellow", nil, entry.detail or entry.subtitle
    end
    local state = addon.Quests:State(entry.questID)
    local style = addon.Quests:Style(state, entry.role)
    if entry.style ~= style then
        entry.style, entry.styledSubtitle = style, entry.subtitle .. " · " .. style.label
    end
    local icon, dim = addon.Quests:Icon(state, entry.role)
    return icon, style.color, entry.styledSubtitle, dim
end

function addon.SetIcon(texture, icon, dim)
    if type(icon) == "string" then
        texture:SetAtlas(icon)
    else
        texture:SetTexture(icon)
        texture:SetTexCoord(0, 1, 0, 1)
    end
    texture:SetDesaturated(not not dim)
    texture:SetAlpha(dim and .72 or 1)
end

function addon.ZoneName(mapID)
    local map = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return map and map.name or "Current map"
end

-- Items ----------------------------------------------------------------------

function addon.ItemName(itemID)
    if type(itemID) == "number" then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
        if name and name ~= "" then
            return name
        end
    end
    return data.items[itemID] or ("Item " .. tostring(itemID or ""))
end

function addon.ItemCached(itemID)
    if type(itemID) ~= "number" then return true end
    if C_Item and C_Item.IsItemDataCachedByID then return C_Item.IsItemDataCachedByID(itemID) end
    return C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID)) ~= nil
end

local qualityColors = {}

function addon.ItemQualityColor(itemID)
    if type(itemID) ~= "number" then return nil end
    local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID)
    if quality == nil or not C_Item.GetItemQualityColor then
        return nil
    end
    local color = qualityColors[quality]
    if color == nil then
        local red, green, blue = C_Item.GetItemQualityColor(quality)
        color = red and { red, green, blue } or false
        qualityColors[quality] = color
    end
    return color or nil
end

function addon.ItemIcon(itemID)
    return type(itemID) == "number" and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil
end

-- Links work before the client has cached the item name or quality.
function addon.ItemLink(itemID)
    if type(itemID) ~= "number" then return nil end
    local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(itemID))
    local ref = "item:" .. itemID
    return link or ("|H%s|h[%s]|h"):format(ref, addon.ItemName(itemID)), ref
end

function addon.RequestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end
