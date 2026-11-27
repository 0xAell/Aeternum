-- SPDX-License-Identifier: GPL-3.0-only
-- Run from the repository root with Lua 5.1 (or LuaJIT) and the pinned source checkout.
local source, output = ...
assert(source and output, "Usage: lua tools/import_norgannon.lua SOURCE_DIR Data.lua")

local SOURCE_COMMIT = "d3d144a8b2d32ae7fb6a0390141f35b3aa55d216"

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

local function hasFlag(mask, flag)
    return type(mask) == "number" and mask % (2 * flag) >= flag
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

local records = {npcs = {}, objects = {}, quests = {}}
local function entity(kind, id)
    local record = records[kind][id]
    if record == nil then
        record = db:Peek(kind, id) or false
        records[kind][id] = record
    end
    return record
end

local factions = {A = "Alliance", H = "Horde"}
local items = {}

local function itemName(itemID)
    local record = db.items[itemID]
    if record and record.name then
        items[itemID] = record.name
        return record.name
    end
end

-- Quests ---------------------------------------------------------------------

local function nonEmpty(list)
    if type(list) == "table" and #list > 0 then
        return list
    end
end

-- Only the rules the addon evaluates in game are exported. Requirements it cannot
-- read reliably (reputation, specialization) are left out rather than guessed.
local function questRecord(quest)
    local prerequisites = quest.prerequisites and {
        all = nonEmpty(quest.prerequisites.all), any = nonEmpty(quest.prerequisites.any),
    }
    if prerequisites and not prerequisites.all and not prerequisites.any then
        prerequisites = nil
    end
    local skill = quest.requiredSkill
    return {
        name = quest.name,
        level = quest.level and quest.level > 0 and quest.level or nil,
        minLevel = quest.minLevel and quest.minLevel > 1 and quest.minLevel or nil,
        maxLevel = quest.maxLevel and quest.maxLevel > 0 and quest.maxLevel or nil,
        races = quest.races and quest.races > 0 and quest.races or nil,
        classes = quest.classes and quest.classes > 0 and quest.classes or nil,
        prerequisites = prerequisites,
        exclusiveTo = nonEmpty(quest.exclusiveTo),
        availableStartingWith = quest.availableStartingWith,
        availableUntilCompleted = quest.availableUntilCompleted,
        disabledByQuest = quest.disabledByQuest,
        requiredSkill = skill and db.professions[skill[1]] and {skill[1], skill[2]} or nil,
        repeatable = (hasFlag(quest.specialFlags, db.enums.specialFlags.REPEATABLE)
            or hasFlag(quest.flags, db.enums.questFlags.DAILY)) or nil,
        event = quest.event or nil,
    }
end

local function usableQuest(id)
    local quest = entity("quests", id)
    return quest and quest.name and quest.name ~= "" and not quest.hidden and quest
end

local hordeVariants = db.variants and db.variants.faction and db.variants.faction.Horde or {}

local function questPins(id, quest, role, field)
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
                                    point.id, point.role, point.faction = id, role, faction
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

local function importQuestPins(quests)
    local pins = {}
    for _, id in ipairs(keys(db.quests)) do
        local quest = usableQuest(id)
        if quest then
            local found = false
            for _, role in ipairs({{"start", "starters"}, {"turnin", "finishers"}}) do
                for _, pin in ipairs(questPins(id, quest, role[1], role[2])) do
                    pins[#pins + 1] = pin
                    found = true
                end
            end
            if found then
                quests[id] = questRecord(quest)
            end
        end
    end
    return pins
end

-- Dungeons -------------------------------------------------------------------

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

local function entrances(id, row)
    local result = {}
    if row.entrance then
        local entrance = coord(row.entrance.area, row.entrance.x, row.entrance.y)
        if entrance then
            local approach = approaches[id]
            if approach and approach.waypoint.mapID == entrance.mapID then
                entrance.label = approach.label
                entrance.waypoints = {approach.waypoint}
            end
            result[1] = entrance
        end
    end
    if #result == 0 then
        local fallback = db.dungeons[row.area]
        for _, rowEntrance in ipairs((fallback and fallback.entrances) or {}) do
            local entrance = coord(rowEntrance[1], rowEntrance[2], rowEntrance[3])
            if entrance then
                result[#result + 1] = entrance
            end
        end
    end
    return result
end

local function bosses(row)
    local result = {}
    for _, sourceBoss in ipairs(row.bosses) do
        local sourceNPC = sourceBoss.id and entity("npcs", sourceBoss.id)
        if sourceNPC and sourceNPC.name then
            local boss = {id = sourceBoss.id, name = sourceNPC.name, loot = {}}
            local seen = {}
            for _, itemID in ipairs(sourceBoss.loot or {}) do
                if not seen[itemID] and itemName(itemID) then
                    seen[itemID] = true
                    boss.loot[#boss.loot + 1] = itemID
                end
            end
            result[#result + 1] = boss
        end
    end
    return result
end

local function importDungeons(quests)
    local dungeons = {}
    for _, id in ipairs(keys(db.instances)) do
        local row = db.instances[id]
        local name = dungeonName(row)
        if name and not row.raid and #(row.bosses or {}) > 0 then
            local dungeon = {
                id = id, name = name, floors = {}, entrances = entrances(id, row), bosses = bosses(row),
                levelMin = row.levels and row.levels.min, levelMax = row.levels and row.levels.max,
                size = row.size, note = row.note, keys = {}, quests = {},
            }
            for _, itemID in ipairs(row.keys or {}) do
                if itemName(itemID) then
                    dungeon.keys[#dungeon.keys + 1] = itemID
                end
            end
            for _, questID in ipairs(row.quests or {}) do
                local quest = usableQuest(questID)
                if quest then
                    quests[questID] = quests[questID] or questRecord(quest)
                    dungeon.quests[#dungeon.quests + 1] = questID
                end
            end
            if #dungeon.bosses > 0 then
                dungeons[#dungeons + 1] = dungeon
            end
        end
    end
    return dungeons
end

-- Trainers -------------------------------------------------------------------

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

-- Output ---------------------------------------------------------------------

local function literal(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" then
        -- Race masks pass 2^32, so whole numbers are written out in full.
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            return string.format("%.0f", value)
        end
        return string.format("%.10g", value)
    end
    if kind == "boolean" then return tostring(value) end
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

local quests = {}
local questPinRows = importQuestPins(quests)
local dungeons = importDungeons(quests)
local trainers = importTrainers()

local usedProfessions = {}
for _, quest in pairs(quests) do
    if quest.requiredSkill then
        usedProfessions[quest.requiredSkill[1]] = db.professions[quest.requiredSkill[1]]
    end
end

assert(#dungeons >= 25 and #trainers >= 100 and #questPinRows >= 2000,
    "The source snapshot unexpectedly produced an incomplete dataset")

local file = assert(io.open(output, "w"))
local function section(name, rows)
    file:write("    ", name, " = {\n")
    for _, row in ipairs(rows) do
        file:write("        ", literal(row), ",\n")
    end
    file:write("    },\n")
end
local function map(name, values)
    file:write("    ", name, " = {\n")
    for _, id in ipairs(keys(values)) do
        file:write("        [", literal(id), "] = ", literal(values[id]), ",\n")
    end
    file:write("    },\n")
end

file:write("-- SPDX-License-Identifier: GPL-3.0-only\n",
    "-- Generated from NorgannonDB ", SOURCE_COMMIT, ". See DATA_SOURCES.md.\n",
    "local _, addon = ...\n\naddon.Data = {\n")
section("dungeons", dungeons)
section("trainers", trainers)
section("questPins", questPinRows)
map("quests", quests)
map("items", items)
map("professions", usedProfessions)
map("raceMasks", db.enums.raceMaskById)
local classMasks = {}
for class, mask in pairs(db.enums.classKeys) do
    if class ~= "NONE" and class ~= "ALL_CLASSES" then
        classMasks[class] = mask
    end
end
map("classMasks", classMasks)
file:write("}\n")
assert(file:close())
print(string.format("Wrote %d dungeons, %d trainer pins, %d quest pins, %d quests, and %d item names",
    #dungeons, #trainers, #questPinRows, #keys(quests), #keys(items)))
