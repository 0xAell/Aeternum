-- SPDX-License-Identifier: GPL-3.0-only
-- Run from the repository root with Lua 5.1 (or LuaJIT) and the pinned source checkout.
local source, output, entranceFile = ...
assert(source and output and entranceFile, "Usage: lua tools/import_norgannon.lua SOURCE_DIR Data.lua ENTRANCES_LUA")

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
local questContacts = {}

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
                                local contact = (kind == "npcs" and "n" or "o") .. sourceID
                                questContacts[contact] = sourceRecord.name or ""
                                local key = string.format("%d:%.6f:%.6f:%s", point.mapID, point.x, point.y, contact)
                                if rows[key] then
                                    rows[key].faction = nil
                                else
                                    point.id, point.role, point.faction, point.contact = id, role, faction, contact
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

-- Representative outdoor sites for the one quest the player is tracking.
-- Objective indexes are the client's ordering, so completed steps can disappear.
local function objectiveOrder(obj)
    if obj.order then return obj.order end
    local order = {}
    for _, kind in ipairs({"npcs", "objects", "items", "killCredit", "spells"}) do
        for index in ipairs(obj[kind] or {}) do order[#order + 1] = {kind, index} end
    end
    if obj.explore or obj.areaTriggers then order[#order + 1] = {"explore", 1} end
    if #order == 1 then return order end
    return {}
end

local function objectiveSources(obj, kind, i, horde, add)
    local target = obj[kind] and obj[kind][i]
    local function creatureOrObject(typeName, id)
        if not id then return end
        local row = entity(typeName, id)
        if not row or not row.name then return end
        local variant = horde and (hordeVariants[typeName] or {})[id]
        local contact = (typeName == "npcs" and "n" or "o") .. id
        for _, point in ipairs(positions(variant and variant.spawns or row.spawns)) do
            add(point, contact, row.name)
        end
    end
    if (kind == "npcs" or kind == "objects") and target then
        creatureOrObject(kind, target.id)
    elseif kind == "killCredit" and target then
        for _, id in ipairs(target.npcs or {}) do creatureOrObject("npcs", id) end
    elseif kind == "items" and target then
        local item = db:Peek("items", target.id)
        local drops = item and item.drops
        if not drops then return end
        local npcs, objects = keys(drops.npcs), keys(drops.objects)
        -- A world-drop material has no useful single quest location.
        if #npcs + #objects > 12 then return end
        for _, id in ipairs(npcs) do creatureOrObject("npcs", id) end
        for _, id in ipairs(objects) do creatureOrObject("objects", id) end
    elseif kind == "explore" or kind == "areaTriggers" then
        for _, point in ipairs(positions(obj.explore and obj.explore.spawns)) do add(point, "z0") end
        for _, id in ipairs(obj.areaTriggers or {}) do
            local trigger = db:Peek("areaTriggers", id)
            for _, point in ipairs(positions(trigger and trigger.spawns)) do add(point, "z0") end
        end
    end
end

local function importObjectives(quests)
    local packed = {}
    for id in pairs(quests) do
        local quest = usableQuest(id)
        local variant = (hordeVariants.quests or {})[id]
        local sites = {}
        for _, faction in ipairs({"A", "H"}) do
            local horde = faction == "H"
            local obj = horde and variant and variant.objectives or quest.objectives or {}
            for index, step in ipairs(objectiveOrder(obj)) do
                local counts, seen = {}, {}
                objectiveSources(obj, step[1], step[2], horde, function(point, contact, name)
                    local x, y = math.floor(point.x * 10000 + .5), math.floor(point.y * 10000 + .5)
                    local site = ("%d:%d:%d,%d%s"):format(index, point.mapID, x, y, contact)
                    if seen[site] or (counts[point.mapID] or 0) >= 3 then return end
                    seen[site] = true
                    counts[point.mapID] = (counts[point.mapID] or 0) + 1
                    if sites[site] then sites[site] = "" else sites[site] = faction end
                    if name then questContacts[contact] = name end
                end)
            end
        end
        local entries = {}
        for _, site in ipairs(keys(sites)) do entries[#entries + 1] = site .. sites[site] .. ";" end
        if #entries > 0 then packed[id] = table.concat(entries) end
    end
    return packed
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

-- Exterior landmarks and portals recorded on the Forever zone maps. These
-- supply only entrances missing from the pinned database. See DATA_SOURCES.md.
local foreverDoors = {
    ["alcaz-prison"] = {mapID=1445, x=.755, y=.137, label="Prison cellar",
        waypoints={{mapID=1445, x=.746, y=.146, label="Prison building"}},
        hint="Enter the prison building and take the stairs down to the cellar."},
    ["blackmaw-hold"] = {mapID=1447, x=.349, y=.238, label="Blackmaw tunnel portal",
        waypoints={{mapID=1447, x=.387, y=.332, label="Tunnel mouth"}},
        hint="Enter the furbolg tunnel and follow it northwest to the portal."},
    ["kroldok-stronghold"] = {mapID=2548, x=.375, y=.379, label="Stronghold cave",
        waypoints={{mapID=2548, x=.391, y=.388, label="Meeting stone"}},
        hint="From the meeting stone, take the cave west of the fortress gates."},
    ["shapers-terrace"] = {mapID=1449, x=.482, y=.057, label="Titan doorway",
        waypoints={{mapID=1449, x=.484, y=.086, label="Stone staircase"}},
        hint="Climb the stone staircase above Marshal's Refuge to the titan doorway."},
}

-- Wing portals from the pinned Forever Dungeon Routes Entrances.lua, derived
-- from named Classic AreaTriggers on these same outdoor zone maps.
local reference, wingPortals = {}, {}
assert(loadfile(entranceFile))("", reference)
for _, family in pairs(reference.WingPortals) do
    for _, portal in ipairs(family) do
        local id = portal.key:gsub("^diremaul_", "dm-"):gsub("_", "-")
        local doors = wingPortals[id] or {}
        wingPortals[id] = doors
        doors[#doors + 1] = {mapID=family.map, x=portal.x, y=portal.y}
    end
end

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
    local portals = wingPortals[id]
    if portals then
        for _, door in ipairs(portals) do
            if door.mapID == 1420 and primary and primary.mapID == door.mapID then
                door.waypoints = {{mapID=primary.mapID, x=primary.x, y=primary.y, label="Monastery entrance"}}
                door.hint = "Enter the monastery grounds and follow the marker to the wing portal."
            end
        end
        return portals
    end
    if not primary then
        if #entrances == 0 and foreverDoors[id] then return {foreverDoors[id]} end
        return entrances
    end

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

-- Forever's new encounters also have named equipment in NPC drop records.
-- Keep a direct drop only when the item independently names the same NPC.
local function extraDrops(npc, npcID, seen, loot)
    for _, id in ipairs(keys(npc.drops)) do
        local item = not seen[id] and db:Peek("items", id)
        if item and (item.class == 2 or item.class == 4 or item.class == 9)
            and item.drops and item.drops.npcs and item.drops.npcs[npcID] ~= nil and itemName(id) then
            loot[#loot + 1] = id
            seen[id] = true
        end
    end
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
            if row.forever then extraDrops(sourceNPC, sourceBoss.id, seen, boss.loot) end
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
                id = id, name = name, entrances = dungeonEntrances(id, row), bosses = bosses(row),
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
    if lower == "weapon master" then return "weapon", "Weapon Master" end
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
    local classTokens, skillIDs = {}, {}
    for token, name in pairs(classes) do classTokens[name] = token end
    for skillID, name in pairs(professions) do skillIDs[name] = skillID end
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
                    point.classToken, point.skillID = classTokens[specialty], skillIDs[specialty]
                    trainers[#trainers + 1] = point
                end
            end
        end
    end
    return trainers
end

-- A lesson can cost different amounts at different NPCs. Keep the price on
-- the NPC assignment and store common spell details only once.
local function importLessons(trainers)
    local spells, offers, packed = {}, {}, {}
    local function offer(npcID, id, price, name, rank, level, skill, need, faction)
        if not offers[npcID] then return end
        spells[id] = table.concat({name, rank or "", level or "", skill or "", need or "", faction or ""}, "|")
        offers[npcID][id] = price or ""
    end
    for _, npc in ipairs(trainers) do offers[npc.id] = {} end
    for _, class in ipairs(keys(db.training)) do
        for id, spell in pairs(db.training[class]) do
            if not spell.pet and not spell.how then
                for _, npcID in ipairs(spell.trainers or {}) do
                    offer(npcID, id, spell.cost, spell.name, spell.rank, spell.level, nil, nil, spell.faction)
                end
            end
        end
    end
    for id, recipe in pairs(db.recipes) do
        for npcID, cost in pairs(recipe.trainers or {}) do
            offer(npcID, id, cost, recipe.name, nil, nil, recipe.skill, recipe.learn)
        end
    end
    for npcID, assignments in pairs(offers) do
        local parts = {}
        for _, id in ipairs(keys(assignments)) do
            parts[#parts + 1] = id .. ":" .. assignments[id]
        end
        if #parts > 0 then packed[npcID] = table.concat(parts, ";") end
    end
    return spells, packed
end

-- Packing --------------------------------------------------------------------

-- Quest pins and quest rules are packed into strings that the addon decodes
-- only for the map or quest it shows. The layouts are documented in DATA_SOURCES.md
-- and decoded by Core.lua.
local QUEST_FIELDS = {
    "name", "level", "minLevel", "maxLevel", "races", "classes", "requiresAll", "requiresAny",
    "exclusiveTo", "availableStartingWith", "availableUntilCompleted", "disabledByQuest",
    "requiredSkill", "repeatable", "event",
}
local FACTION_CODES = {Alliance = "A", Horde = "H"}

local function number(value)
    return string.format("%.0f", value)
end

local function packQuest(quest)
    local values = {
        name = quest.name, level = quest.level, minLevel = quest.minLevel, maxLevel = quest.maxLevel,
        races = quest.races, classes = quest.classes,
        requiresAll = quest.prerequisites and quest.prerequisites.all,
        requiresAny = quest.prerequisites and quest.prerequisites.any,
        exclusiveTo = quest.exclusiveTo, availableStartingWith = quest.availableStartingWith,
        availableUntilCompleted = quest.availableUntilCompleted, disabledByQuest = quest.disabledByQuest,
        requiredSkill = quest.requiredSkill and (quest.requiredSkill[1] .. ":" .. quest.requiredSkill[2]),
        repeatable = quest.repeatable and "1", event = quest.event and "1",
    }
    local fields = {}
    for index, field in ipairs(QUEST_FIELDS) do
        local value = values[field]
        if type(value) == "table" then
            local ids = {}
            for i, id in ipairs(value) do ids[i] = number(id) end
            value = table.concat(ids, ",")
        elseif type(value) == "number" then
            value = number(value)
        end
        assert(value == nil or not value:find("|", 1, true), "Separator in quest field")
        fields[index] = value or ""
    end
    while fields[#fields] == "" do
        fields[#fields] = nil
    end
    return table.concat(fields, "|")
end

-- Coordinates are in ten-thousandths. Contacts use n<NPC ID> or o<object ID>.
local function packPins(pins)
    local byMap = {}
    for _, pin in ipairs(pins) do
        local parts = byMap[pin.mapID]
        if not parts then
            parts = {}
            byMap[pin.mapID] = parts
        end
        parts[#parts + 1] = string.format("%d%s%s%d,%d%s;", pin.id, pin.role == "start" and "s" or "t",
            FACTION_CODES[pin.faction] or "", math.floor(pin.x * 10000 + .5), math.floor(pin.y * 10000 + .5),
            pin.contact)
    end
    local packed = {}
    for mapID, parts in pairs(byMap) do
        packed[mapID] = table.concat(parts)
    end
    return packed
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
local objectiveRows = importObjectives(quests)

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
local lessons, offers = importLessons(trainers)
map("lessons", lessons)
map("offers", offers)
local packedQuests = {}
for id, quest in pairs(quests) do
    packedQuests[id] = packQuest(quest)
end
map("questPins", packPins(questPinRows))
map("objectiveSites", objectiveRows)
map("questContacts", questContacts)
map("quests", packedQuests)
map("items", items)
for id, name in pairs(professions) do usedProfessions[id] = name end
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
