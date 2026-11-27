local _, addon = ...

local data = addon.Data
local maps = {}
local dungeonRecords = {}
local questStarts = {}
local categoryOrder = { dungeon = 1, class = 2, profession = 3, quest = 4 }
local questRoles = { start = "Quest start", turnin = "Quest turn-in" }

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

-- Records --------------------------------------------------------------------

local function record(category, title, subtitle, point, source)
    return {
        category = category, title = title, subtitle = subtitle,
        mapID = point and point.mapID, x = point and point.x, y = point and point.y,
        faction = point and point.faction, source = source, point = point,
        search = (title .. " " .. subtitle):lower(),
    }
end

local function addToMap(entry)
    local entries = maps[entry.mapID]
    if not entries then
        entries = {}
        maps[entry.mapID] = entries
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
        addToMap(record("dungeon", dungeon.name, subtitle, entrance, dungeon))
    end
end

for _, trainer in ipairs(data.trainers) do
    addToMap(record(trainer.kind, trainer.name, trainer.specialty or "Trainer", trainer, trainer))
end

for _, pin in ipairs(data.questPins) do
    local quest = data.quests[pin.id]
    local subtitle = questRoles[pin.role]
    if quest.level then
        subtitle = subtitle .. " · Level " .. quest.level
    end
    local entry = record("quest", quest.name, subtitle, pin, quest)
    entry.questID, entry.role = pin.id, pin.role
    addToMap(entry)
    if pin.role == "start" then
        local starts = questStarts[pin.id]
        if not starts then
            starts = {}
            questStarts[pin.id] = starts
        end
        starts[#starts + 1] = entry
    end
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

table.sort(dungeonRecords, ordered)
for _, entries in pairs(maps) do
    table.sort(entries, ordered)
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

-- Returns the records on a world map, or every dungeon when atlas is true.
function addon.Entries(mapID, atlas, query)
    local result = {}
    local candidates = atlas and dungeonRecords or maps[mapID] or {}
    local search = strtrim(query or ""):lower()
    local faction = UnitFactionGroup("player")
    for _, entry in ipairs(candidates) do
        if (atlas or addon.CategoryEnabled(entry.category)) and visible(entry, faction)
            and (search == "" or entry.search:find(search, 1, true)) then
            result[#result + 1] = entry
        end
    end
    return result
end

-- The first recorded start of a quest that the player's faction can use.
function addon.QuestStart(questID)
    local faction = UnitFactionGroup("player")
    for _, entry in ipairs(questStarts[questID] or {}) do
        if addon.FactionAllowed(entry, faction) then
            return entry
        end
    end
end

-- Letter, colour, and subtitle for a record as the player currently sees it.
function addon.Presentation(entry)
    local category = addon.categoryByID[entry.category]
    if entry.category ~= "quest" then
        return category.letter, category.color, entry.subtitle
    end
    local state = addon.Quests:State(entry.questID)
    local letter = entry.role == "turnin" and "?" or "!"
    local style = addon.Quests:Style(state, entry.role)
    return letter, style.color, entry.subtitle .. " · " .. style.label
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

function addon.ItemQualityColor(itemID)
    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemID)
    elseif GetItemInfo then
        quality = select(3, GetItemInfo(itemID))
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then
        return { color.r, color.g, color.b }
    end
end

function addon.ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return GetItemIcon and GetItemIcon(itemID)
end

-- A full hyperlink when the client has the item cached, otherwise a bare item string.
function addon.ItemLink(itemID)
    local link
    if C_Item and C_Item.GetItemInfo then
        link = select(2, C_Item.GetItemInfo(itemID))
    elseif GetItemInfo then
        link = select(2, GetItemInfo(itemID))
    end
    return link, "item:" .. itemID
end

function addon.RequestItem(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end
