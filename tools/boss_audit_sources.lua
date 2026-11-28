-- Read only the declarative fields used in the boss audit. Never run game callbacks.
local mode, first, second = ...
local function emit(...)
    local t = {...}
    for i = 1, select("#", ...) do t[i] = tostring(t[i] or "") end
    io.write(table.concat(t, "\t"), "\n")
end

local function loadData(path, env, ns)
    local f = assert(io.open(path, "rb"))
    local code = f:read("*a"):gsub("^\239\187\191", "")
    f:close()
    local chunk = assert(loadstring(code, "@" .. path))
    setfenv(chunk, env)
    chunk("", ns)
end

if mode == "routes" then
    local ns = {}
    for _, file in ipairs({"Dungeons", "DefaultRoutes", "Encounters"}) do
        loadData(first .. "/ForeverDungeonRoutes/Data/" .. file .. ".lua", {}, ns)
    end
    for _, d in ipairs(ns.Dungeons) do
        local route = ns.DefaultRoutes[d.key] or {}
        for _, variant in ipairs(route.id and {route} or route) do
            for _, stop in ipairs(variant.stops or {}) do
                if stop.name and stop.x and stop.y then
                    emit("route", d.instanceID, stop.name, table.concat(stop.encounters or {}, ","), variant.name)
                end
            end
        end
    end
    for map, encounters in pairs(ns.Encounters) do
        for _, e in ipairs(encounters) do emit("journal", map, e.name, table.concat(e.ids, ",")) end
    end
    return
end

if mode == "names" then
    -- Load the project's pinned, packed Norgannon snapshot using its normal reader.
    dofile(first .. "/core/api.lua")
    dofile(first .. "/data/items.lua")
    for id, row in pairs(NorgannonDB.items) do
        if row.name then emit("item", id, row.name, NorgannonDB:Peek("items", id).class) end
    end
    return
end

if mode == "roster" then
    local addon = {}
    loadData(first, {}, addon)
    loadData(second, {}, addon)
    for _, d in ipairs(addon.Data.dungeons) do
        local map = addon.floorData[d.id]
        for _, b in ipairs(d.bosses) do
            emit("boss", d.id, d.name, map.instance, b.id, b.name, table.concat(b.loot, ","))
        end
        for index, floor in ipairs(map.floors) do
            for _, pin in ipairs(floor.bosses) do
                emit("pin", d.id, pin[1], index, floor.name, floor.mapID, pin[2], pin[3],
                    table.concat(pin.encounters or {}, ","), table.concat(floor.toMap or {}, ","))
            end
        end
    end
    return
end

if mode == "ez" or mode == "ez-positions" then
    local ns = {}
    loadData(first, {ipairs=ipairs}, ns)
    if mode == "ez-positions" then loadData(second, {ipairs=ipairs}, ns) end
    for _, d in ipairs(ns.Dungeons) do
        for _, step in ipairs(d.steps or {}) do
            for _, id in ipairs(step.npc or {}) do
                -- A shared step can have different loot on each individual corpse.
                local loot = #step.npc == 1 and step.loot or {}
                if mode == "ez" then
                    emit("ez", d.slug, id, step.kind, step.outside and "outside", table.concat(loot or {}, ","),
                        step.name.en, table.concat(step.npc, ","), table.concat(step.loot or {}, ","))
                elseif d.bliz and not step.outside and #step.npc == 1 then
                    local pin = d.bliz.steps[step.id]
                    for _, page in ipairs(d.bliz.pages) do
                        if pin and pin.pos and pin.page == page.key and page.world then
                            local world = page.world
                            emit("ez-map", d.slug, id, world.map, pin.page, pin.source, table.concat(pin.pos, ","),
                                table.concat(world.matrix, ","), table.concat(world.offset, ","), pin.approx)
                        end
                    end
                end
            end
        end
    end
    return
end

assert(mode == "att")
local categories = {}
local app = {OnTooltipDB={}, Settings={}, asset=function() end, ResolveQuestData=function(data) return data end}
app.AddEventHandler = function(_, build) build(categories) end
local constructors = {"Achievement","Header","CharacterClass","AchievementCriteria","Encounter","Faction",
    "CustomHeader","Item","Instance","Mount","NPC","Object","Species","Profession","Quest","QuestObjective",
    "Recipe","ItemSource","Toy"}
for _, kind in ipairs(constructors) do
    app["Create" .. kind] = function(id, props, sourceProps)
        local item
        if kind == "ItemSource" then item, props = props, sourceProps end
        props = props or {}
        local children = props.g or props
        if kind == "Item" or kind == "Toy" then item = id end
        if kind == "Recipe" or kind == "Species" or kind == "Mount" then item = props.itemID end
        return {kind=kind, id=id, props=props, item=item, children=children}
    end
end
loadData(first, {}, app)
local function scan(node, instance, header)
    local kind, props = node.kind, node.props
    if kind == "Instance" then instance = node.id end
    if kind == "CustomHeader" or kind == "Header" then header = node.id end
    if instance then
        local npc
        if kind == "NPC" and node.id > 0 then npc = node.id
        elseif kind == "Encounter" then npc = props.npcID end
        if npc then
            local loot = {}
            for _, child in ipairs(node.children) do
                if child.item and not child.props.cost and not child.props.providers then loot[#loot+1] = child.item end
            end
            emit("att", instance, npc, kind == "Encounter" and node.id, header, table.concat(loot, ","))
        end
        if (kind == "Encounter" or kind == "CustomHeader") and not npc and props.crs then
            local loot = {}
            for _, child in ipairs(node.children) do
                if child.item and not child.props.cost and not child.props.providers then loot[#loot+1] = child.item end
            end
            for _, id in ipairs(props.crs) do
                emit("att-group", instance, id, node.id, table.concat(props.crs, ","), table.concat(loot, ","))
            end
        end
        if node.item then
            for _, id in ipairs(props.crs or {}) do emit("att-drop", instance, id, node.item, header) end
        end
    end
    for _, child in ipairs(node.children) do scan(child, instance, header) end
end
scan(categories.Instances)
