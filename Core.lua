local _, addon = ...

local data = addon.Data
local maps = {}
local dungeonRecords = {}
local categoryOrder = { dungeon = 1, class = 2, profession = 3, quest = 4 }
local questRoles = { start = "Quest start", turnin = "Quest turn-in", objective = "Quest objective" }

function addon.FormatCoordinates(point)
    return ("%.1f, %.1f"):format(100 * point.x, 100 * point.y)
end

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

function addon.Trim(text)
    if type(text) ~= "string" then
        return ""
    end
    if type(strtrim) == "function" then
        return strtrim(text)
    end
    return text:match("^%s*(.-)%s*$") or ""
end

function addon.DungeonLevel(dungeon)
    local low, high = dungeon.levelMin, dungeon.levelMax
    if low and high and low ~= high then
        return ("Levels %d–%d"):format(low, high)
    elseif low or high then
        return ("Level %d"):format(low or high)
    end
end

local function dungeonSearchText(dungeon, title, subtitle)
    local parts = { title or "", subtitle or "" }
    for _, boss in ipairs(dungeon.bosses or {}) do
        if boss.name and boss.name ~= "" then
            parts[#parts + 1] = boss.name
        end
    end
    return table.concat(parts, " "):lower()
end

local function record(category, title, subtitle, point, source, searchText)
    return {
        category = category, title = title, subtitle = subtitle,
        mapID = point and point.mapID, x = point and point.x, y = point and point.y,
        faction = point and point.faction, source = source, point = point,
        search = searchText or ((title or "") .. " " .. (subtitle or "")):lower(),
    }
end

local function addToMap(entry)
    if not entry.mapID then
        return
    end
    local entries = maps[entry.mapID]
    if not entries then
        entries = {}
        maps[entry.mapID] = entries
    end
    entries[#entries + 1] = entry
end

for _, dungeon in ipairs(data.dungeons or {}) do
    local levels = addon.DungeonLevel(dungeon)
    local atlasSubtitle = levels or "Dungeon"
    local atlasSearch = dungeonSearchText(dungeon, dungeon.name, atlasSubtitle)
    dungeonRecords[#dungeonRecords + 1] = record("dungeon", dungeon.name, atlasSubtitle, nil, dungeon, atlasSearch)
    for _, entrance in ipairs(dungeon.entrances or {}) do
        local subtitle = entrance.label or "Dungeon entrance"
        if #dungeon.entrances > 1 then
            subtitle = subtitle .. " · " .. addon.FormatCoordinates(entrance)
        end
        if levels then
            subtitle = subtitle .. " · " .. levels
        end
        local search = dungeonSearchText(dungeon, dungeon.name, subtitle)
        addToMap(record("dungeon", dungeon.name, subtitle, entrance, dungeon, search))
    end
end

for _, trainer in ipairs(data.trainers or {}) do
    local title = trainer.specialty or "Trainer"
    addToMap(record(trainer.kind, trainer.name, title, trainer, trainer))
end

for _, quest in ipairs(data.quests or {}) do
    local subtitle = questRoles[quest.role] or "Quest"
    if quest.level and quest.level > 0 then
        subtitle = subtitle .. " · Level " .. quest.level
    end
    addToMap(record("quest", quest.name, subtitle, quest, quest))
end

local function ordered(a, b)
    local groupA = categoryOrder[a.category] or 99
    local groupB = categoryOrder[b.category] or 99
    if groupA ~= groupB then
        return groupA < groupB
    elseif (a.title or "") ~= (b.title or "") then
        return (a.title or "") < (b.title or "")
    elseif (a.subtitle or "") ~= (b.subtitle or "") then
        return (a.subtitle or "") < (b.subtitle or "")
    elseif (a.x or 0) ~= (b.x or 0) then
        return (a.x or 0) < (b.x or 0)
    end
    return (a.y or 0) < (b.y or 0)
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
    local filters = addon.settings and addon.settings.filters
    return not filters or filters[id] ~= false
end

function addon.FactionAllowed(entry, faction)
    if not entry.faction then
        return true
    end
    if faction ~= "Alliance" and faction ~= "Horde" then
        return true
    end
    return entry.faction == faction
end

local function searchTokens(query)
    local trimmed = addon.Trim(query):lower()
    if trimmed == "" then
        return nil
    end
    local tokens = {}
    for token in trimmed:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end
    return tokens
end

local function matchesTokens(haystack, tokens)
    if not tokens then
        return true
    end
    for _, token in ipairs(tokens) do
        if not haystack:find(token, 1, true) then
            return false
        end
    end
    return true
end

function addon.Entries(mapID, atlas, query)
    local result = {}
    local candidates = atlas and dungeonRecords or maps[mapID] or {}
    local tokens = searchTokens(query)
    local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    for _, entry in ipairs(candidates) do
        if (atlas or addon.CategoryEnabled(entry.category))
            and addon.FactionAllowed(entry, faction)
            and matchesTokens(entry.search, tokens) then
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
    if type(itemID) == "number" then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
        if name and name ~= "" then
            return name
        end
        if C_Item and C_Item.GetItemInfo then
            local infoName = C_Item.GetItemInfo(itemID)
            if infoName and infoName ~= "" then
                return infoName
            end
        end
        if type(GetItemInfo) == "function" then
            local infoName = GetItemInfo(itemID)
            if infoName and infoName ~= "" then
                return infoName
            end
        end
    end
    return (data.items and data.items[itemID]) or ("Item " .. tostring(itemID or ""))
end

function addon.ItemCached(itemID)
    if type(itemID) ~= "number" then
        return true
    end
    if C_Item and C_Item.IsItemDataCachedByID then
        return C_Item.IsItemDataCachedByID(itemID) == true
    end
    if C_Item and C_Item.GetItemInfo then
        return select(2, C_Item.GetItemInfo(itemID)) ~= nil
    end
    if type(GetItemInfo) == "function" then
        return select(2, GetItemInfo(itemID)) ~= nil
    end
    return true
end

function addon.ItemLink(itemID, fallbackName)
    if type(itemID) ~= "number" then
        return nil
    end
    local link
    if C_Item and C_Item.GetItemInfo then
        link = select(2, C_Item.GetItemInfo(itemID))
    elseif type(GetItemInfo) == "function" then
        link = select(2, GetItemInfo(itemID))
    end
    if type(link) == "string" and link ~= "" then
        return link
    end
    local label = fallbackName or addon.ItemName(itemID)
    return ("|Hitem:%d|h[%s]|h"):format(itemID, label)
end

function addon.ItemColor(itemID)
    if type(itemID) ~= "number" or type(ITEM_QUALITY_COLORS) ~= "table" then
        return nil
    end
    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemID)
    end
    if quality == nil and C_Item and C_Item.GetItemInfo then
        quality = select(3, C_Item.GetItemInfo(itemID))
    elseif quality == nil and type(GetItemInfo) == "function" then
        quality = select(3, GetItemInfo(itemID))
    end
    local color = quality and ITEM_QUALITY_COLORS[quality]
    if color and type(color.r) == "number" and type(color.g) == "number" and type(color.b) == "number" then
        return { color.r, color.g, color.b }
    end
end

function addon.RequestItemData(itemID)
    if type(itemID) == "number" and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end
