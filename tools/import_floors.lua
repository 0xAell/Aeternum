-- Extract floor geometry and boss stops from the pinned MIT Forever Dungeon Routes data.
-- The addon uses only file IDs of textures already in the WoW client.
local source, database, output = ...
assert(output, "Usage: lua tools/import_floors.lua ROUTES_DIR Data.lua FloorData.lua")
local routes, addon = {}, {}
for _, name in ipairs({"Dungeons", "Floors", "Rooms", "Pictures", "Minimaps", "DefaultRoutes", "Encounters"}) do
    assert(loadfile(source .. "/ForeverDungeonRoutes/Data/" .. name .. ".lua"))("", routes)
end
assert(loadfile(database))("", addon)
local function key(text) return text:lower():gsub("[^%w]", "") end
local aliases = {
    blackfathomdeeps = "blackfathom", cityofdalaran = "dalaran", dmeast = "diremauleast",
    dmnorth = "diremaulnorth", dmwest = "diremaulwest", excavationsitewetlands = "excavationsite",
    kroldokstronghold = "kroldok", lbrs = "lowerblackrock", ragefirechasm = "ragefire",
    shadowfangkeep = "shadowfang", ubrs = "upperblackrock",
}
local byKey = {}
for _, dungeon in ipairs(routes.Dungeons) do byKey[key(dungeon.key)] = dungeon end

local function array(numbers)
    return "{" .. table.concat(numbers, ",") .. "}"
end

-- These roster members share the encounter's recorded location. Match them
-- within the same dungeon only. Several can have separate loot tables.
local sharedStops = {
    ["blackrock-depths"] = {
        ["Ring of Law"] = {"Gorosh the Dervish", "Grizzle", "Eviscerator", "Ok'thor the Breaker",
            "Anub'shiah", "Hedrum the Creeper"},
        ["Warder Stilgiss & Verek"] = {"Warder Stilgiss", "Verek"}, ["The Seven"] = {"Doom'rel"},
    },
    uldaman = {["The Lost Dwarves"] = {"Baelog", 'Eric "The Swift"', "Olaf"}},
    ubrs = {["Warchief Rend Blackhand"] = {"Gyth"}},
}

local function transform(floor)
    if floor.frame then return floor.frame end
    if not floor.world then return end
    local south, east, north, west = unpack(floor.world)
    if north <= south or west <= east then return end
    return {0, -1/(west-east), west/(west-east), -1/(north-south), 0, north/(north-south)}
end

local function writeStops(file, id, floorID, variants, bosses, encounters)
    local seen, count = {}, 0
    for _, route in ipairs(variants) do
        for _, stop in ipairs(route.stops or {}) do
            if stop.floor == floorID and stop.name and stop.x and stop.y
                and stop.x >= 0 and stop.x <= 1 and stop.y >= 0 and stop.y <= 1 then
                local names = {stop.name}
                for _, e in ipairs(stop.encounters or {}) do names[#names + 1] = encounters[e] end
                for _, name in ipairs((sharedStops[id] or {})[stop.name] or {}) do names[#names + 1] = name end
                for _, name in ipairs(names) do
                    local npc = bosses[key(name)]
                    if npc and not seen[npc] then
                        file:write(("{%d,%s,%s"):format(npc, stop.x, stop.y))
                        if stop.encounters and #stop.encounters > 0 then
                            file:write(",encounters=", array(stop.encounters))
                        end
                        if name ~= stop.name then file:write((",label=%q"):format(stop.name)) end
                        file:write("},")
                        seen[npc], count = true, count + 1
                    end
                end
            end
        end
    end
    return count
end

-- A room which crosses two floors cannot identify the player's floor.
local function collectNames(set, record)
    for _, suffix in ipairs({"", "DE", "FR", "ES", "PT", "RU", "KO", "CN", "TW"}) do
        local name = record["name" .. suffix]
        if name and name ~= "" then
            assert(not name:find("|", 1, true))
            set[name] = true
        end
    end
end

local function zoneNames(floor, id, rooms)
    local names, sorted = {}, {}
    collectNames(names, floor)
    for _, room in ipairs(rooms or {}) do
        local single = #room.boxes > 0
        for _, box in ipairs(room.boxes) do
            if box[1] ~= id then single = false break end
        end
        if single then collectNames(names, room) end
    end
    for name in pairs(names) do sorted[#sorted + 1] = name end
    table.sort(sorted)
    return "|" .. table.concat(sorted, "|") .. "|"
end

local file = assert(io.open(output, "w"))
file:write("-- Generated from Forever Dungeon Routes. See DATA_SOURCES.md and licenses/ForeverDungeonRoutes-MIT.txt.\n")
file:write("local _, addon = ...\naddon.floorData = {\n")
local floorCount, pinCount = 0, 0
for _, dungeon in ipairs(addon.Data.dungeons) do
    local nameKey = key(dungeon.id)
    local original = assert(byKey[aliases[nameKey] or nameKey], dungeon.id)
    local route = routes.DefaultRoutes[original.key] or {}
    local variants = route.id and {route} or route
    local bosses = {}
    for _, boss in ipairs(dungeon.bosses) do bosses[key(boss.name)] = boss.id end
    local encounters = {}
    for _, encounter in ipairs(routes.Encounters[original.instanceID] or {}) do
        for _, id in ipairs(encounter.ids) do encounters[id] = encounter.name end
    end
    file:write(("    [%q] = {instance=%d, floors={\n"):format(dungeon.id, original.instanceID))
    for _, floorID in ipairs(original.floors) do
        local floor = assert(routes.Floors[floorID])
        local mosaic = routes.MinimapArt[floorID]
        floorCount = floorCount + 1
        file:write(("        {name=%q, zones=%q, "):format(floor.name,
            zoneNames(floor, floorID, routes.Rooms[original.key])))
        local projection = transform(floor)
        if projection then file:write("toMap=", array(projection), ", ") end
        if floor.tiles then
            assert(#floor.tiles == 12)
            file:write("mapID=", floorID, ", tiles=", array(floor.tiles))
            if mosaic and #mosaic > 0 then
                local pieces = {}
                for i, piece in ipairs(mosaic) do
                    assert(#piece == 14)
                    pieces[i] = table.concat(piece, ",")
                end
                file:write((", fallback=%q"):format(table.concat(pieces, ";")))
            end
        elseif mosaic and #mosaic > 0 then
            file:write("pieces={")
            for _, piece in ipairs(mosaic) do
                assert(#piece == 14)
                file:write(array(piece), ",")
            end
            file:write("}")
        else
            file:write("paths={")
            local count = 0
            for _, variant in ipairs(variants) do
                for _, path in ipairs(variant.paths or {}) do
                    if path.floor == floorID and #path.pts >= 4 then
                        file:write(array(path.pts), ",")
                        count = count + 1
                    end
                end
            end
            assert(count > 0, "Missing floor geometry for " .. floor.name)
            file:write("}")
        end
        file:write(", bosses={")
        pinCount = pinCount + writeStops(file, dungeon.id, floorID, variants, bosses, encounters)
        file:write("}},\n")
    end
    file:write("    }},\n")
end
file:write("}\n")
assert(file:close())
print(("%d dungeon floors, %d mapped boss stops"):format(floorCount, pinCount))
