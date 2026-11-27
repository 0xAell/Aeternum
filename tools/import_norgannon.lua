-- SPDX-License-Identifier: GPL-3.0-only
-- Run from the repository root with Lua 5.1 and the pinned source checkout.
local source, output = ...
assert(source and output, "Usage: lua tools/import_norgannon.lua SOURCE_DIR Data.lua")

dofile(source .. "/core/api.lua")
for _, name in ipairs({"info", "world", "index", "quests", "npcs", "objects", "items", "variants", "recipes"}) do
    dofile(source .. "/data/" .. name .. ".lua")
end
local db = NorgannonDB
assert(db.info.flavor == "Forever" and db.info.interface == 16001, "Expected WoW Forever data")
assert(db.info.generated == "2026-11-22", "Expected the pinned NorgannonDB snapshot documented in DATA_SOURCES.md")

local function keys(tableToSort)
    local result = {}
    for key in pairs(tableToSort or {}) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end

local function coord(areaID, x, y)
    local zone = db.zones[areaID]
    local mapID = db.maps.areaToUiMap[areaID] or (zone and zone.uiMapId)
    if mapID and type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
        return {mapID = mapID, x = x / 100, y = y / 100}
    end
end

local function positions(spawns)
    local result, used = {}, {}
    for _, areaID in ipairs(keys(spawns)) do
        for _, spawn in ipairs(spawns[areaID]) do
            local point = coord(areaID, spawn[1], spawn[2])
            if point and not used[point.mapID] then
                used[point.mapID] = true
                result[#result + 1] = point
            end
        end
    end
    return result
end

local records = {npcs = {}, objects = {}}
local function entity(kind, id)
    local record = records[kind][id]
    if record == nil then
        record = db:Peek(kind, id) or false
        records[kind][id] = record
    end
    return record
end

local function dungeonName(row)
    local area = db.zones[row.area]
    local label = row.name or row.groupName or (area and area.name)
    if label and row.wing then
        label = label .. " - " .. row.wing
    end
    return label
end

local approaches = {
    deadmines = {
        label = "Moonbrook entrance approach",
        waypoint = {mapID = 1436, x = 0.430, y = 0.693, label = "Moonbrook road"},
    },
    ["ragefire-chasm"] = {
        waypoint = {mapID = 1454, x = 0.395, y = 0.540, label = "Cleft of Shadow descent"},
    },
}

local function findEntrance(entrances, point)
    for index, entrance in ipairs(entrances) do
        if entrance.mapID == point.mapID and entrance.x == point.x and entrance.y == point.y then
            return index
        end
    end
end

local function dungeonEntrances(id, row)
    local entrances = {}
    local area = db.dungeons[row.area]
    for _, entry in ipairs(area and area.entrances or {}) do
        local point = coord(entry[1], entry[2], entry[3])
        if point and not findEntrance(entrances, point) then
            entrances[#entrances + 1] = point
        end
    end

    local entry = row.entrance
    local primary = entry and coord(entry.area, entry.x, entry.y)
    if not primary then return entrances end

    local approach = approaches[id]
    if approach and approach.waypoint.mapID == primary.mapID then
        primary.label = approach.label
        primary.waypoints = {approach.waypoint}
    end

    -- An area can describe several wings. Only add its other entrances when
    -- the list also identifies this dungeon's primary on the same map.
    local match = findEntrance(entrances, primary)
    if not match then return {primary} end
    table.remove(entrances, match)
    table.insert(entrances, 1, primary)
    return entrances
end

local function importDungeons()
    local dungeons, items = {}, {}
    for _, id in ipairs(keys(db.instances)) do
        local row = db.instances[id]
        local name = dungeonName(row)
        if name and not row.raid and #(row.bosses or {}) > 0 then
            local dungeon = {
                id = id, name = name, floors = {}, entrances = dungeonEntrances(id, row), bosses = {},
                levelMin = row.levels and row.levels.min, levelMax = row.levels and row.levels.max,
            }
            for _, sourceBoss in ipairs(row.bosses) do
                local sourceNPC = sourceBoss.id and entity("npcs", sourceBoss.id)
                if sourceNPC and sourceNPC.name then
                    local boss = {id = sourceBoss.id, name = sourceNPC.name, loot = {}}
                    local seen = {}
                    for _, itemID in ipairs(sourceBoss.loot or {}) do
                        local record = db.items[itemID]
                        if record and record.name and not seen[itemID] then
                            items[itemID] = record.name
                            seen[itemID] = true
                            boss.loot[#boss.loot + 1] = itemID
                        end
                    end
                    dungeon.bosses[#dungeon.bosses + 1] = boss
                end
            end
            if #dungeon.bosses > 0 then
                dungeons[#dungeons + 1] = dungeon
            end
        end
    end
    return dungeons, items
end

local classes = {
    DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest",
    ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
}
local professions = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring",
    [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning",
}
local professionTokens = {
    {"Alchemy", "alchem"}, {"Blacksmithing", "blacksmith", "armorsmith", "weaponsmith"},
    {"Cooking", "cook"}, {"Enchanting", "enchant"}, {"Engineering", "engineer"},
    {"First Aid", "first aid", "trauma surgeon", "physician", "medic"},
    {"Fishing", "fish"}, {"Herbalism", "herbal"}, {"Leatherworking", "leather"},
    {"Mining", "mining", "miner"}, {"Skinning", "skinn"}, {"Tailoring", "tailor"},
}
local factions = {A = "Alliance", H = "Horde"}

local function classifyTrainer(title)
    local lower = title:lower()
    for _, key in ipairs(keys(classes)) do
        if lower:find(classes[key]:lower(), 1, true) then
            return "class", classes[key]
        end
    end
    if lower == "portal trainer" then
        return "class", "Mage"
    end
    for _, names in ipairs(professionTokens) do
        for i = 2, #names do
            if lower:find(names[i], 1, true) then
                return "profession", names[1]
            end
        end
    end
end

local function importTrainers()
    local trainers, inferredClass, inferredProfession = {}, {}, {}
    for _, class in ipairs(keys(db.training)) do
        for _, spell in pairs(db.training[class]) do
            if not spell.pet then
                for _, id in ipairs(spell.trainers or {}) do
                    inferredClass[id] = inferredClass[id] or classes[class]
                end
            end
        end
    end
    for _, spellID in ipairs(keys(db.recipes)) do
        local recipe = db.recipes[spellID]
        if professions[recipe.skill] then
            for id in pairs(recipe.trainers or {}) do
                inferredProfession[id] = inferredProfession[id] or professions[recipe.skill]
            end
        end
    end
    local candidates = {}
    for id in pairs(db.categories.trainer.npcs) do candidates[id] = true end
    for id in pairs(inferredClass) do candidates[id] = true end
    for id in pairs(inferredProfession) do candidates[id] = true end
    for _, id in ipairs(keys(candidates)) do
        local npc = entity("npcs", id)
        if npc and npc.name then
            local kind, specialty = classifyTrainer(npc.subName or "")
            if not kind and inferredClass[id] then
                kind, specialty = "class", inferredClass[id]
            elseif not kind and inferredProfession[id] then
                kind, specialty = "profession", inferredProfession[id]
            end
            if kind then
                for _, point in ipairs(positions(npc.spawns)) do
                    point.id, point.name, point.kind = id, npc.name, kind
                    point.specialty, point.faction = specialty, factions[npc.reaction]
                    trainers[#trainers + 1] = point
                end
            end
        end
    end
    return trainers
end

local hordeVariants = db.variants and db.variants.faction and db.variants.faction.Horde or {}

local function questRows(id, quest, role, field)
    local rows = {}
    local variant = (hordeVariants.quests or {})[id]
    for _, faction in ipairs({"Alliance", "Horde"}) do
        local horde = faction == "Horde"
        local sources = horde and variant and variant[field] or quest[field]
        local used = {}
        for _, kind in ipairs({"npcs", "objects"}) do
            for _, sourceID in ipairs(sources and sources[kind] or {}) do
                local sourceRecord = entity(kind, sourceID)
                local override = horde and (hordeVariants[kind] or {})[sourceID]
                if sourceRecord then
                    local reaction = override and override.reaction or sourceRecord.reaction
                    if not factions[reaction] or factions[reaction] == faction then
                        local spawns = override and override.spawns or sourceRecord.spawns
                        for _, point in ipairs(positions(spawns)) do
                            if not used[point.mapID] then
                                used[point.mapID] = true
                                local key = string.format("%d:%.6f:%.6f", point.mapID, point.x, point.y)
                                if rows[key] then
                                    rows[key].faction = nil
                                else
                                    point.id, point.name, point.role = id, quest.name, role
                                    point.faction, point.level = faction, quest.level
                                    rows[key] = point
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local result = {}
    for _, key in ipairs(keys(rows)) do
        result[#result + 1] = rows[key]
    end
    return result
end

local function importQuests()
    local quests = {}
    for _, id in ipairs(keys(db.quests)) do
        local quest = db:Peek("quests", id)
        if quest.name and quest.name ~= "" and not quest.hidden then
            for _, row in ipairs(questRows(id, quest, "start", "starters")) do
                quests[#quests + 1] = row
            end
            for _, row in ipairs(questRows(id, quest, "turnin", "finishers")) do
                quests[#quests + 1] = row
            end
        end
    end
    return quests
end

local function literal(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" then return string.format("%.10g", value) end
    assert(kind == "table", "Unexpected literal type: " .. kind)
    local parts = {}
    for _, key in ipairs(keys(value)) do
        if type(key) == "string" then
            parts[#parts + 1] = key .. "=" .. literal(value[key])
        else
            parts[#parts + 1] = literal(value[key])
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local dungeons, items = importDungeons()
local trainers, quests = importTrainers(), importQuests()
assert(#dungeons >= 25 and #trainers >= 100 and #quests >= 2000, "The source snapshot unexpectedly produced an incomplete dataset")
local file = assert(io.open(output, "w"))
file:write("-- SPDX-License-Identifier: GPL-3.0-only\n",
    "-- Generated from NorgannonDB d3d144a8b2d32ae7fb6a0390141f35b3aa55d216. See DATA_SOURCES.md.\n",
    "local _, addon = ...\n\naddon.Data = {\n")
for _, section in ipairs({{"dungeons", dungeons}, {"trainers", trainers}, {"quests", quests}}) do
    file:write("    ", section[1], " = {\n")
    for _, row in ipairs(section[2]) do
        file:write("        ", literal(row), ",\n")
    end
    file:write("    },\n")
end
file:write("    items = {\n")
for _, id in ipairs(keys(items)) do
    file:write("        [", id, "] = ", literal(items[id]), ",\n")
end
file:write("    },\n}\n")
assert(file:close())
print(string.format("Wrote %d dungeons, %d trainer pins, %d quest pins, and %d item names",
    #dungeons, #trainers, #quests, #keys(items)))
