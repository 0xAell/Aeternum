local _, addon = ...

local data = addon.Data
local maps = {}
local dungeonRecords = {}
local categoryOrder = { dungeon = 1, class = 2, profession = 3, quest = 4 }
local questRoles = { start = "Quest start", turnin = "Quest turn-in", objective = "Quest objective" }

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

function addon.DungeonLevel(dungeon)
    local low, high = dungeon.levelMin, dungeon.levelMax
    if low and high and low ~= high then
        return ("Levels %d–%d"):format(low, high)
    elseif low or high then
        return ("Level %d"):format(low or high)
    end
end

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
    for _, entrance in ipairs(dungeon.entrances or {}) do
        local subtitle = entrance.label or "Dungeon entrance"
        if levels then
            subtitle = subtitle .. " · " .. levels
        end
        addToMap(record("dungeon", dungeon.name, subtitle, entrance, dungeon))
    end
end

for _, trainer in ipairs(data.trainers) do
    local title = trainer.specialty or "Trainer"
    addToMap(record(trainer.kind, trainer.name, title, trainer, trainer))
end

for _, quest in ipairs(data.quests) do
    local subtitle = questRoles[quest.role] or "Quest"
    if quest.level and quest.level > 0 then
        subtitle = subtitle .. " · Level " .. quest.level
    end
    addToMap(record("quest", quest.name, subtitle, quest, quest))
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

function addon.LoadSettings()
    if type(AeternumDB) ~= "table" then
        AeternumDB = {}
    end
    if type(AeternumDB.filters) ~= "table" then
        AeternumDB.filters = {}
    end
    addon.settings = AeternumDB
end

function addon.CategoryEnabled(id)
    return addon.settings.filters[id] ~= false
end

function addon.FactionAllowed(entry, faction)
    return not entry.faction or not faction or entry.faction == faction
end

function addon.Entries(mapID, atlas, query)
    local result = {}
    local candidates = atlas and dungeonRecords or maps[mapID] or {}
    local search = strtrim(query or ""):lower()
    local faction = UnitFactionGroup("player")
    for _, entry in ipairs(candidates) do
        if (atlas or addon.CategoryEnabled(entry.category)) and addon.FactionAllowed(entry, faction)
            and (search == "" or entry.search:find(search, 1, true)) then
            result[#result + 1] = entry
        end
    end
    return result
end

function addon.ZoneName(mapID)
    local map = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return map and map.name or "Current map"
end

function addon.ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if name and name ~= "" then
        return name
    end
    return (data.items and data.items[itemID]) or ("Item " .. itemID)
end
