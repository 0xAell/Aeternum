-- Run from the repository root with Lua 5.1.
local addon = {}
assert(loadfile("Data.lua"))("Aeternum", addon)
assert(loadfile("Core.lua"))("Aeternum", addon)

local faction = "Alliance"
function UnitFactionGroup() return faction end
function strtrim(text) return text:match("^%s*(.-)%s*$") end
addon.LoadSettings()

local dungeons = {}
for _, dungeon in ipairs(addon.Data.dungeons) do
    dungeons[dungeon.id] = dungeon
end

local function assertPoint(point, mapID, x, y)
    assert(point and point.mapID == mapID and point.x == x and point.y == y,
        ("Expected map %d at %.1f, %.1f"):format(mapID, 100 * x, 100 * y))
end

local badlands, searingGorge, burningSteppes = 1418, 1427, 1428
local uldaman = dungeons.uldaman
assert(#uldaman.entrances == 2, "Uldaman has two recorded Badlands entrances")
assertPoint(uldaman.entrances[1], badlands, .446, .121)
assertPoint(uldaman.entrances[2], badlands, .652, .435)
for _, id in ipairs({"blackrock-depths", "lbrs", "ubrs"}) do
    local entrances = dungeons[id].entrances
    assert(#entrances == 2, id .. " has approaches from two zones")
    assertPoint(entrances[1], searingGorge, .348, .853)
    assertPoint(entrances[2], burningSteppes, .294, .383)
end

-- Dire Maul's area record names a different site from each wing's own entrance.
local direMaul = {["dm-east"] = {.625, .249}, ["dm-north"] = {.648, .302}, ["dm-west"] = {.603, .302}}
for id, xy in pairs(direMaul) do
    assert(#dungeons[id].entrances == 1, id .. " must retain its wing-specific entrance")
    assertPoint(dungeons[id].entrances[1], 1444, xy[1], xy[2])
end
assert(#dungeons.deadmines.entrances == 1 and #dungeons.deadmines.entrances[1].waypoints == 1)
assert(#dungeons["alcaz-prison"].entrances == 0)

local pins = addon.Entries(badlands, false, "Uldaman")
local found = {}
for _, pin in ipairs(pins) do
    if pin.source == uldaman then found[pin.point] = pin.subtitle end
end
assert(found[uldaman.entrances[1]]:find("44.6, 12.1", 1, true))
assert(found[uldaman.entrances[2]]:find("65.2, 43.5", 1, true))

-- Exercise the detail panel through the same selection call as pin and atlas clicks.
assert(loadfile("Navigation.lua"))("Aeternum", addon)
assert(loadfile("UI.lua"))("Aeternum", addon)
local function noop() end
local label = {SetText = noop}
local button = {SetEnabled = noop}
local caption = {SetText = function(self, text) self.text = text end}
local mapID
local zoneNames = {[badlands] = "Badlands", [searingGorge] = "Searing Gorge", [burningSteppes] = "Burning Steppes"}
UIParent = {GetWidth = function() return 1024 end, GetHeight = function() return 768 end}
C_Map = {GetMapInfo = function(id) return {name = zoneNames[id]} end}
local ui = addon.UI
ui.map = {GetMapID = function() return mapID end}
ui.ChangeBoss = noop
ui.detail = {
    SetSize = noop, GetWidth = UIParent.GetWidth, Show = noop,
    floorMap = {SetWidth = noop, SetDungeon = noop},
    title = label, levels = label, routeStatus = label,
    route = button, nextEntrance = button, stop = button, showZone = button, entranceText = caption,
}
local function chosen(dungeon, viewedMapID, clicked)
    mapID = viewedMapID
    ui:Select({category = "dungeon", source = dungeon, point = clicked})
    return ui.detail.entrances[ui.detail.entranceIndex]
end
local depths = dungeons["blackrock-depths"]
assert(chosen(depths, burningSteppes) == depths.entrances[2], "prefer the atlas map")
assert(caption.text == "Burning Steppes · 29.4, 38.3")
assert(chosen(depths, badlands) == depths.entrances[1], "fall back to the primary entrance")
assert(chosen(uldaman, badlands) == uldaman.entrances[1], "keep source order within a zone")
assert(chosen(uldaman, badlands, uldaman.entrances[2]) == uldaman.entrances[2], "respect the clicked pin")
assert(caption.text == "Badlands · 65.2, 43.5")
local alliance = {mapID = badlands, faction = "Alliance"}
local horde = {mapID = burningSteppes, faction = "Horde"}
local split = {entrances = {alliance, horde}}
assert(chosen(split, burningSteppes, horde) == alliance, "filter before choosing a destination")
faction = "Horde"
assert(chosen(split, badlands) == horde)
assert(chosen(dungeons["alcaz-prison"], badlands) == nil)
print("Dungeon entrance checks passed.")
