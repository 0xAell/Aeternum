-- Headless tests: luajit tests/run.lua (from the repository root).
local testDirectory = arg[0]:match("^(.*)/") or "."
package.path = testDirectory .. "/?.lua;" .. package.path
local Wow = require("wow")

local ADDON = "Aeternum"
local passed, failed = 0, 0

local function test(name, body)
    local ok, problem = xpcall(body, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n" .. problem)
    end
end

local function check(condition, message)
    if not condition then
        error(message or "check failed", 2)
    end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(message or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function tocFiles()
    local files = {}
    for line in io.lines(ADDON .. ".toc") do
        if line ~= "" and not line:match("^##") then
            files[#files + 1] = line
        end
    end
    return files
end

local dataChunk = assert(loadfile("Data.lua"))

-- Loads the addon into a fresh client. state sets the character and saved data.
local function load(state)
    state = state or {}
    local env = Wow.new(state)
    local addon = {}
    for _, file in ipairs(tocFiles()) do
        if file:match("%.lua$") then
            local chunk = file == "Data.lua" and dataChunk or assert(loadfile(file))
            setfenv(chunk, env)
            chunk(ADDON, addon)
        else
            check(file == "WorldMap.xml", "unexpected TOC file " .. file)
        end
    end
    Wow.fire("ADDON_LOADED", ADDON)
    Wow.fire("PLAYER_LOGIN")
    return addon, env, state
end

local function slash(env, text)
    env.SlashCmdList.AETERNUM(text or "")
end

local function pins(env)
    local result = {}
    for _, template in ipairs({"AeternumMapPinTemplate", "AeternumEntrancePinTemplate"}) do
        for pin in env.WorldMapFrame:EnumeratePinsByTemplate(template) do result[#result + 1] = pin end
    end
    return result
end

local function findEntry(entries, predicate)
    for _, entry in ipairs(entries) do
        if predicate(entry) then
            return entry
        end
    end
end

local function questPin(addon, mapID, questID, role)
    return findEntry(addon.Entries(mapID, false, ""), function(entry)
        return entry.questID == questID and entry.role == role
    end)
end

test("bundled data is consistent", function()
    local addon = load()
    local data = addon.Data
    equal(#data.dungeons, 34, "dungeons")
    local packedPins, records = 0, 0
    for mapID, packed in pairs(data.questPins) do
        local _, count = packed:gsub(";", "")
        packedPins = packedPins + count
        for _, entry in ipairs(addon.MapRecords(mapID)) do
            if entry.questID then
                records = records + 1
                check(addon.Quest(entry.questID), "quest pin without a quest record " .. entry.questID)
                check(entry.x >= 0 and entry.x <= 1 and entry.y >= 0 and entry.y <= 1, "pin outside its map")
            end
        end
    end
    equal(packedPins, 11100, "packed quest pins")
    equal(records, 11100, "decoded quest pins")
    for id in pairs(data.quests) do
        local quest = addon.Quest(id)
        check(quest.name and quest.name ~= "", "quest name " .. id)
        if quest.requiredSkill then
            check(data.professions[quest.requiredSkill[1]], "unnamed profession")
        end
    end
    for _, dungeon in ipairs(data.dungeons) do
        for _, boss in ipairs(dungeon.bosses) do
            for _, itemID in ipairs(boss.loot) do
                check(data.items[itemID], "loot without a name " .. itemID)
            end
        end
        for _, itemID in ipairs(dungeon.keys) do
            check(data.items[itemID], "key without a name " .. itemID)
        end
        for _, questID in ipairs(dungeon.quests) do
            check(addon.Quest(questID), "dungeon quest without a record " .. questID)
        end
    end
end)

test("packed quest rules decode to the source fields", function()
    local addon = load()
    -- Quest 2: level 30, from level 20, Horde races, after quest 6383.
    local quest = addon.Quest(2)
    equal(quest.name, "Sharptalon's Claw", "name")
    equal(quest.level, 30, "level")
    equal(quest.minLevel, 20, "minimum level")
    equal(quest.races, 8589934770, "race mask beyond 2^32")
    equal(quest.prerequisites.any[1], 6383, "prerequisite")
    check(not quest.prerequisites.all, "no required-all list")
    check(addon.Quest(999999) == nil, "unknown quest")
end)

test("unknown slash commands print help", function()
    local _, env, state = load()
    slash(env, "nonsense")
    check(#state.messages > 0, "help printed")
end)

test("quest pins follow the character's progress", function()
    local addon, env, state = load({ level = 1 })
    slash(env)
    check(questPin(addon, 1429, 783, "start"), "first quest available")
    check(not questPin(addon, 1429, 7, "start"), "follow-up locked")
    check(not questPin(addon, 1429, 783, "turnin"), "turn-in hidden before accepting")

    state.log[783] = 1
    addon.Quests:Invalidate()
    check(not questPin(addon, 1429, 783, "start"), "start hidden once accepted")
    check(questPin(addon, 1429, 783, "turnin"), "turn-in shown while active")
    equal(addon.Quests:State(783), "active", "active")
    state.complete[783] = true
    addon.Quests:Invalidate()
    equal(addon.Quests:State(783), "ready", "ready to turn in")

    state.log[783], state.completed[783] = nil, true
    addon.Quests:Invalidate()
    check(not questPin(addon, 1429, 783, "turnin"), "turn-in hidden once done")
    equal(addon.Quests:State(783), "done", "done")
    check(questPin(addon, 1429, 7, "start"), "follow-up unlocked")
end)

test("level, class, and race rules apply", function()
    local addon, _, state = load({ level = 1 })
    local data = addon.Data
    local highLevel, mageOnly, raceID95
    for id in pairs(data.quests) do
        local quest = addon.Quest(id)
        if not highLevel and quest.minLevel and quest.minLevel >= 30 and not quest.races and not quest.classes
            and not quest.prerequisites and not quest.event and not quest.exclusiveTo then
            highLevel = id
        end
        if not mageOnly and quest.classes == data.classMasks.MAGE and not quest.prerequisites
            and not quest.exclusiveTo and (not quest.races or quest.races % 2 == 1) then
            mageOnly = id
        end
        if not raceID95 and quest.races and quest.races >= 2 ^ 32 then
            raceID95 = id
        end
    end
    check(highLevel and mageOnly and raceID95, "sample quests found")
    equal(addon.Quests:State(highLevel), "locked", "too low")
    equal(addon.Quests:State(mageOnly), "unavailable", "warrior")
    state.class, state.level = "MAGE", 60
    addon.Quests:Invalidate()
    check(addon.Quests:State(mageOnly) ~= "unavailable", "mage")
    check(addon.Quests:State(highLevel) == "available" or addon.Quests:State(highLevel) == "trivial", "level 60")
    local quest = addon.Quest(raceID95)
    local allowed95 = quest.races % (2 * data.raceMasks[95]) >= data.raceMasks[95]
    state.raceID = 95
    addon.Quests:Invalidate()
    equal(addon.Quests:State(raceID95) ~= "unavailable", allowed95, "race above 2^32")
end)

test("faction-specific pins stay with their faction", function()
    local addon = load({ faction = "Horde", level = 10 })
    addon.settings.questMode = "all"
    for _, entry in ipairs(addon.Entries(1429, false, "")) do
        check(entry.faction ~= "Alliance", "no Alliance-only pins for Horde")
    end
end)

test("pins show quest marks coloured by state", function()
    local _, env = load({ level = 1 })
    slash(env)
    local found
    for _, pin in ipairs(pins(env)) do
        for _, entry in ipairs(pin.entries) do
            if entry.questID == 783 and entry.role == "start" and pin.entry == entry then
                found = pin
            end
        end
    end
    check(found, "quest start pin")
    equal(found.icon.texture, 132049, "Blizzard available-quest mark")
    found:OnMouseEnter()
    check(env.GameTooltip:IsOwned(found), "tooltip")
    check(env.GameTooltip.lines[2]:find("Available", 1, true), "state in tooltip")
end)

test("the arrow points at the target on a fixed minimap", function()
    local addon, _, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .5, .5
    check(addon.Navigation:Start("North point", { mapID = 1429, x = .5, y = .15 }), "started")
    local overlay = addon.Navigation.overlay
    check(overlay and overlay:IsShown(), "arrow shown")
    local location = overlay.arrow.points[1]
    check(math.abs(location[4]) < .01 and location[5] > 0, "north is up")
    equal(overlay.arrow.atlas, "Navigation-Tracked-Arrow", "game's edge arrow")
    equal(overlay.arrow.rotation, 0, "points up")
    check(overlay.arrow:IsVisible() and not overlay.marker:IsVisible(), "only the edge arrow for a distant point")
    check(addon.Navigation:GetStatus():find("North point", 1, true), "status names target")
end)

test("the arrow turns with a rotating minimap", function()
    local addon, _, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .5, .5
    state.rotate, state.facing = true, -math.pi / 2 -- facing east
    addon.Navigation:Start("North point", { mapID = 1429, x = .5, y = .15 })
    local arrow = addon.Navigation.overlay.arrow
    local location = arrow.points[1]
    check(location[4] < 0 and math.abs(location[5]) < .01, "north is to the left when facing east")
    check(math.abs(arrow.rotation - math.pi / 2) < .01, "arrowhead points left")
end)

test("guidance follows approach points and stops on arrival", function()
    local addon, _, state = load()
    local destination = {
        mapID = 1429, x = .5, y = .9, label = "Entrance",
        waypoints = { { mapID = 1429, x = .5, y = .5, label = "Road" } },
    }
    state.playerMap, state.playerX, state.playerY = 1429, .5, .1
    addon.Navigation:Start("Test dungeon", destination)
    check(addon.Navigation:GetStatus():find("^Road"), "heads for the approach point first")
    state.playerY = .7
    addon.Navigation.step = nil
    addon.Navigation:Update()
    check(addon.Navigation:GetStatus():find("^Test dungeon"), "skips a passed approach point")
    state.playerY = .9
    addon.Navigation:Update()
    check(not addon.Navigation:IsActive(), "stopped")
    equal(addon.Navigation:GetStatus(), "Arrived near Test dungeon.", "arrival")
end)

test("guidance pauses on another continent and inside instances", function()
    local addon, _, state = load()
    state.playerMap, state.playerX, state.playerY = 1454, .5, .5
    addon.Navigation:Start("Goldshire", { mapID = 1429, x = .4, y = .6 })
    check(addon.Navigation:GetStatus():find("continent", 1, true), "continent pause")
    state.inInstance = true
    addon.Navigation:Update()
    check(addon.Navigation:GetStatus():find("instance", 1, true), "instance pause")
    check(addon.Navigation:IsActive(), "still active")
end)

test("guidance rejects points without coordinates", function()
    local addon = load()
    check(not addon.Navigation:Start("Nowhere", { mapID = 1429 }), "rejected")
    check(not addon.Navigation:IsActive(), "inactive")
end)

test("a quest in the log stays turn-in-able whatever its offer rules say", function()
    local addon, _, state = load({ level = 60 })
    local seasonal
    for id in pairs(addon.Data.quests) do
        local quest = addon.Quest(id)
        if quest.event and not quest.races and not quest.classes then
            seasonal = id
            break
        end
    end
    check(seasonal, "sample quest")
    equal(addon.Quests:State(seasonal), "unavailable", "not offered")
    state.log[seasonal] = 1
    addon.Quests:Invalidate()
    equal(addon.Quests:State(seasonal), "active", "in the log")
end)

test("a new level from PLAYER_LEVEL_UP survives later quest events", function()
    -- Quest 783 is level 1; with a green range of 5 it turns grey at level 7.
    local addon, _, state = load({ level = 6 })
    equal(addon.Quests:State(783), "available", "level 6")
    Wow.fire("PLAYER_LEVEL_UP", 7)
    Wow.fire("QUEST_LOG_UPDATE")
    equal(addon.Quests:State(783), "trivial", "level 7 before UnitLevel catches up")
    state.level = 7
    Wow.fire("QUEST_LOG_UPDATE")
    equal(addon.Quests:State(783), "trivial", "level 7")
end)

test("the edge arrow becomes a waypoint at the target's true minimap distance", function()
    local addon, _, state = load()
    -- Elwynn is 2000 yards tall, so .05 of the map is 100 yards: half the 200-yard view radius.
    state.playerMap, state.playerX, state.playerY = 1429, .5, .7
    addon.Navigation:Start("North point", { mapID = 1429, x = .5, y = .45 })
    local overlay = addon.Navigation.overlay
    check(overlay.arrow:IsVisible(), "outside the minimap")
    state.playerY = .5
    addon.Navigation:Update()
    local point = overlay.marker.points[1]
    check(overlay.marker:IsVisible() and not overlay.arrow:IsVisible(), "one waypoint inside the minimap")
    equal(overlay.marker.atlas, "waypoint-mappin-minimap-tracked", "stock minimap waypoint")
    check(math.abs(point[5] - 35) < .01, "35 pixels on a 140-pixel minimap, got " .. point[5])
end)

test("completed quests read as completed in reference mode", function()
    local addon, _, state = load({ level = 60 })
    local seasonal
    for id in pairs(addon.Data.quests) do
        local quest = addon.Quest(id)
        if quest.event and not quest.races and not quest.classes and not quest.repeatable then
            seasonal = id
            break
        end
    end
    state.completed[seasonal] = true
    equal(addon.Quests:State(seasonal), "done", "done, not unavailable")
end)

test("opening the map refreshes the pins once", function()
    local addon, env = load({ savedVariables = { pinsWithPanelClosed = true } })
    local refreshes = 0
    local original = addon.Entries
    addon.Entries = function(...)
        refreshes = refreshes + 1
        return original(...)
    end
    env.WorldMapFrame:Show()
    equal(refreshes, 1, "one refresh")
end)


local function dungeonNamed(addon, id)
    return assert(findEntry(addon.Data.dungeons, function(dungeon) return dungeon.id == id end))
end

local function locate(env, predicate)
    for _, pin in ipairs(pins(env)) do
        for _, entry in ipairs(pin.entries) do
            if predicate(entry) then return pin, entry end
        end
    end
end

local function menuRow(menu, name)
    return findEntry(menu.children, function(row) return row.label:find(name, 1, true) end)
end

local function openDeadmines(character)
    character = character or {}
    character.mapID = 1436
    local addon, env, state = load(character)
    env.WorldMapFrame:Show()
    local pin = locate(env, function(entry) return entry.title == "The Deadmines" end)
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    return addon, env, state
end

test("M shows dungeon entrances and relevant map pins without any launcher", function()
    local addon, env = load({mapID=1436, savedVariables={panelOpen=true, showMapPins=false}})
    env.WorldMapFrame:Show()
    check(locate(env, function(entry) return entry.title == "The Deadmines" end), "entrance visible on first visit")
    check(not addon.DungeonMap.frame and not addon.Navigation.overlay, "outdoors opens no extra surface")
    for _, entry in ipairs(Wow.trackingMenu().children) do check(entry.label ~= "Aeternum", "no addon submenu") end
    equal(#env.WorldMapFrame.ScrollContainer.points, 0, "game canvas anchors unchanged")
    check(addon.settings.showMapPins == nil and addon.settings.panelOpen == nil, "obsolete launcher options migrated")
end)

test("outdoor wheel zoom fills single-layer ranges and preserves native multi-layer zoom", function()
    local _, env = load()
    local scroll = env.WorldMapFrame.ScrollContainer
    equal(scroll.wheelMode, 2, "native wheel enabled")
    equal(#scroll.zoomLevels, 5, "single-layer zoom stops")
    scroll:CreateZoomLevels()
    equal(#scroll.zoomLevels, 5, "rebuild does not duplicate stops")
    equal(scroll.zoomLevels[5].scale, 4, "4x detail")
    local native = {{scale=.5, layerIndex=1}, {scale=2, layerIndex=2}}
    local _, second = load({zoomLevels=native})
    equal(second.WorldMapFrame.ScrollContainer.zoomLevels, native, "native levels kept")
    equal(#native, 2, "extra layers unaffected")
end)

test("dungeon right-click offers directions and does not zoom the map", function()
    local addon, env, state = load({mapID=1436, playerMap=1436, playerX=.2, playerY=.2, inCombat=true})
    env.WorldMapFrame:Show()
    local pin = locate(env, function(entry) return entry.source.id == "deadmines" end)
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    check(not env.WorldMapFrame.zoomedOut and not addon.Navigation:IsActive(), "menu first")
    state.menu:Find("Show path to The Deadmines"):Click()
    equal(addon.Navigation:GetTarget(), "The Deadmines entrance", "clicked entrance")
    equal(#addon.Navigation.points, 2, "recorded outdoor approach included")
    check(addon.Navigation.overlay:IsShown() and not addon.DungeonMap.frame, "minimap only")
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    state.menu:Find("Stop directions"):Click()
    check(not addon.Navigation:IsActive(), "stopped in place")
end)

test("Westfall entrance artwork has padding for either mouse button and survives focus and pin reuse", function()
    local addon, env, state = load({mapID=1436})
    local map = env.WorldMapFrame
    map:Show()
    local function isDeadmines(entry) return entry.source.id == "deadmines" end
    local pin, door = locate(env, isDeadmines)
    local function size(icon, target)
        equal(pin.icon:GetWidth(), icon); equal(pin.icon:GetHeight(), icon)
        equal(pin:GetWidth(), target); equal(pin:GetHeight(), target)
    end
    size(30, 40)
    equal(pin.icon.points[1][1], "CENTER")
    equal(pin.tracked.points[1][2], pin.icon, "route badge follows the artwork")
    addon.FocusLocation(door)
    size(36, 46)
    addon.FocusLocation(nil)
    size(30, 40)
    addon.settings.filters.dungeon = false
    addon.RefreshMap()
    addon.FocusLocation(door)
    pin = locate(env, isDeadmines)
    size(36, 46)
    addon.FocusLocation(nil)
    addon.settings.filters.dungeon = true
    addon.RefreshMap()
    equal(locate(env, isDeadmines), pin, "entrance frame reused")
    size(30, 40)
    map:ClickPin(pin, "LeftButton", 21, 0)
    check(not addon.DungeonMap.dungeon, "outside the target")
    map:ClickPin(pin, "RightButton", -19, 19)
    state.menu:Find("Show path to The Deadmines")
    map:ClickPin(pin, "LeftButton", 19, -19)
    equal(addon.DungeonMap.dungeon, door.source, "padding opens the floor map")
end)

test("nearby entrances to different dungeons stay selectable and split on zoom", function()
    local addon, env, state = load({mapID=1413})
    local map = env.WorldMapFrame
    map.ScrollContainer:SetSize(400, 320)
    map:Show()
    local function kraul(e) return e.source.id == "razorfen-kraul" end
    local function downs(e) return e.source.id == "razorfen-downs" end
    local pin = locate(env, kraul)
    equal(locate(env, downs), pin, "one marker on the small map")
    map:ClickPin(pin, "RightButton", 19, 0)
    state.menu:Find("Show path to Razorfen Downs")
    state.menu:Find("Show path to Razorfen Kraul")
    map:ClickPin(pin, "LeftButton", -19, 0)
    state.menu:Find("Razorfen Downs")
    state.menu:Find("Razorfen Kraul"):Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.dungeon.id, "razorfen-kraul")
    addon.DungeonMap:Close()
    state.viewWidth = .25
    map.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    check(locate(env, kraul) ~= locate(env, downs), "each door gets its own target at higher zoom")
end)

test("shared entrances retain the chosen wing for both buttons", function()
    local addon, env, state = load({mapID=1420, playerMap=1420, playerX=.2, playerY=.2})
    env.WorldMapFrame:Show()
    local pin = locate(env, function(entry) return entry.source.id == "sm-armory" end)
    equal(#pin.entries, 4, "one pin")
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    state.menu:Find("Show path to Scarlet Monastery - Library"):Click()
    equal(addon.Navigation:GetTarget(), "Scarlet Monastery - Library entrance", "wing route")
    equal(env.AeternumRouteDB.x, .8538); equal(env.AeternumRouteDB.y, .3246)
    equal(env.AeternumRouteDB.waypoints[1].label, "Monastery entrance")
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    check(not menuRow(state.menu, "Show path to Scarlet Monastery - Library"), "route to selected wing is active")
    state.menu:Find("Show path to Scarlet Monastery - Armory")
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    state.menu:Find("Scarlet Monastery - Cathedral"):Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.dungeon.id, "sm-cathedral", "chosen wing opens on the map")
end)

test("Dire Maul wing portals agree with the zone map and alternate doors carry distinct directions", function()
    local addon, env, state = load({mapID=1444, playerMap=1444, playerX=.2, playerY=.2})
    local east = addon.DungeonEntrances(dungeonNamed(addon, "dm-east"))
    local north = addon.DungeonEntrances(dungeonNamed(addon, "dm-north"))
    equal(#east, 3); equal(east[1].x, .6486); equal(north[1].x, .6292)
    env.WorldMapFrame:Show()
    local west = locate(env, function(e) return e.source.id == "dm-west" end)
    env.WorldMapFrame:ClickPin(west, "RightButton")
    local second = assert(menuRow(state.menu, "60.3, 29.7"))
    second:Click()
    equal(env.AeternumRouteDB.y, .2968)
    state.viewWidth = .25
    env.WorldMapFrame.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    local a = locate(env, function(e) return e.source.id == "dm-west" and e.y == .2968 end)
    local b = locate(env, function(e) return e.source.id == "dm-west" and e.y == .3175 end)
    check(a ~= b and a.tracked:IsShown() and not b.tracked:IsShown(), "zoom separates the two doorways")
end)

test("a live dungeon map ID identifies the wing before a localized room name is available", function()
    local addon, env, state = load({inInstance=true, instanceID=189, playerMap=303})
    env.WorldMapFrame:Show()
    equal(addon.DungeonMap.dungeon.id, "sm-library")
    check(not state.menu, "no wing picker required")
    state.instanceID, state.playerMap = 36, 292
    Wow.fire("PLAYER_ENTERING_WORLD")
    equal(addon.DungeonMap.dungeon.id, "deadmines")
    equal(addon.DungeonMap.index, 2)
    state.subzone = "Mastraum"
    Wow.fire("ZONE_CHANGED_INDOORS")
    equal(addon.DungeonMap.index, 1, "identified current room overrides a stale map ID")
end)

test("clicking an entrance uses only the existing viewport and named floors", function()
    local addon, env = openDeadmines()
    local floors, frame = addon.DungeonMap, addon.DungeonMap.frame
    equal(floors.dungeon.id, "deadmines", "map opened from pin")
    equal(frame:GetParent(), env.WorldMapFrame, "part of the map")
    equal(frame.points[1][2], env.WorldMapFrame.ScrollContainer, "fits existing canvas")
    equal(frame.tiles[1].texture, 449591, "native first-floor art")
    frame.dropdown:OpenMenu():Find("Ironclad Cove"):Click()
    equal(frame.tiles[1].texture, 449603, "second-floor art")
    Wow.pressEscape()
    check(not floors.dungeon and env.WorldMapFrame:IsShown(), "first Escape returns to zone")
    check(not frame.tiles[1].texture, "closed floor releases tiles")
    Wow.pressEscape()
    check(not env.WorldMapFrame:IsShown(), "native map closes next")
end)

test("a boss skull opens the correct drop list with modified clicks and native tooltips", function()
    local addon, _, state = openDeadmines()
    local frame = addon.DungeonMap.frame
    check(not state.requested, "viewing a floor requests no loot")
    frame.dropdown:OpenMenu():Find("Ironclad Cove"):Click()
    local skull = findEntry(frame.pins, function(pin) return pin.boss and pin.boss.id == 639 end)
    check(skull and skull:IsVisible(), "VanCleef has a floor-bound skull")
    equal(skull.normal, 137025, "Blizzard skull")
    skull:Click()
    check(state.requested[5191] and not state.requested[5443], "only VanCleef's loot requested")
    equal(state.menu.children[1].label, "Edwin VanCleef", "correct boss")
    local barb = menuRow(state.menu, "Cruel Barb")
    local _, env = addon, Wow.env
    barb.tooltip(env.GameTooltip)
    equal(env.GameTooltip.lines[1], "item:5191", "Blizzard item tooltip")
    state.modified = true
    barb:Click()
    check(state.modifiedClick:find("Hitem:5191", 1, true), "chat or dressing-room link")
end)

test("floor zoom follows the cursor and dragging stays within its viewport", function()
    local addon, _, state = openDeadmines()
    local frame = addon.DungeonMap.frame
    state.cursorX, state.cursorY, frame.top = 650, 340, 540
    local before = (650 - frame.x) / frame.art.scale
    frame:Fire("OnMouseWheel", 2)
    check(frame.zoom > 1, "wheel zoom")
    check(math.abs((650 - frame.x) / frame.art.scale - before) < .01, "point under cursor stays put")
    frame:Fire("OnDragStart")
    state.cursorX = 590
    frame:Fire("OnUpdate")
    check(frame.x <= 0, "pan clamped")
    frame:Fire("OnDragStop")
    check(not frame:GetScript("OnUpdate"), "idle map has no drag update")
    frame:Fire("OnMouseWheel", 99)
    equal(frame.zoom, 4, "upper bound")
    frame:Fire("OnMouseWheel", -99)
    equal(frame.zoom, 1, "lower bound")
end)

test("all dungeon floor references and boss stops resolve to their own dungeon", function()
    local addon = load()
    local floors, stops, sketches = 0, 0, 0
    for _, d in ipairs(addon.Data.dungeons) do
        local geo = addon.floorData[d.id]
        check(geo.instance > 0 and #geo.floors > 0, d.name)
        for _, floor in ipairs(geo.floors) do
            floors = floors + 1
            if floor.tiles then equal(#floor.tiles, 12, d.name)
            elseif floor.pieces then check(#floor.pieces > 0 and #floor.pieces[1] == 14, "client minimap geometry")
            else check(#floor.paths > 0, "surveyed route sketch"); sketches = sketches + 1 end
            for _, stop in ipairs(floor.bosses) do
                check(findEntry(d.bosses, function(b) return b.id == stop[1] end), d.name .. " boss identity")
                check(stop[2]>=0 and stop[2]<=1 and stop[3]>=0 and stop[3]<=1, "coordinates inside floor")
                stops = stops + 1
            end
        end
    end
    equal(floors, 71, "floors")
    equal(stops, 277, "displayed boss positions")
    equal(sketches, 1, "documented fallback sketch")
end)

test("opening M inside a dungeon automatically shows its floor and leaving restores the zone", function()
    local addon, env, state = load({inInstance=true, instanceID=36, subzone="Ironclad Cove"})
    env.WorldMapFrame:Show()
    equal(addon.DungeonMap.dungeon.id, "deadmines", "inside instance")
    equal(addon.DungeonMap.index, 2, "correct named floor")
    state.inInstance = false
    Wow.fire("PLAYER_ENTERING_WORLD")
    check(not addon.DungeonMap.dungeon and env.WorldMapFrame:IsShown(), "outdoors restored")
end)

test("an ambiguous instance ID asks for its wing only until one can be identified", function()
    local addon, env, state = load({inInstance=true, instanceID=189})
    env.WorldMapFrame:Show()
    check(not addon.DungeonMap.dungeon, "never guesses a wing")
    state.menu:Find("Scarlet Monastery - Library"):Click()
    equal(addon.DungeonMap.dungeon.id, "sm-library", "player's choice")
    env.WorldMapFrame:Hide()
    state.subzone = "Cathedral"
    env.WorldMapFrame:Show()
    equal(addon.DungeonMap.dungeon.id, "sm-cathedral", "match on reopen")
end)

test("Forever-only floors draw client minimap tiles and Dalaran's unmapped floor draws its recorded route", function()
    local addon, env = load()
    env.WorldMapFrame:Show()
    addon.DungeonMap:Open(dungeonNamed(addon, "hall-of-thanes"))
    local frame = addon.DungeonMap.frame
    check(#frame.tiles >= 30 and #frame.tiles[1].texCoord == 8, "client minimap mosaic")
    addon.DungeonMap:Open(dungeonNamed(addon, "city-of-dalaran"), nil, 2)
    check(#frame.lines > 0 and frame.lines[1]:IsShown(), "documented fallback")
    check(frame.dropdown:GetText():find("route sketch", 1, true), "sketch identified")
    env.WorldMapFrame:SetMapID(1436)
    check(not addon.DungeonMap.dungeon and not frame:IsShown(), "stock map navigation dismisses dungeon layer")
end)

test("unplaced bosses and dungeon quest starts are reachable from the floor itself", function()
    local addon, env, state = openDeadmines()
    local frame = addon.DungeonMap.frame
    addon.DungeonMap:Open(dungeonNamed(addon, "blackmaw-hold"))
    frame.dropdown:OpenMenu():Find("Boss loot"):Find("Impaan the Imprisoner"):Click()
    Wow.flushTimers()
    equal(state.menu.children[1].label, "Impaan the Imprisoner", "unplaced encounter opens loot")
    addon.DungeonMap:Open(dungeonNamed(addon, "deadmines"))
    local menu = frame.dropdown:OpenMenu()
    local d = addon.DungeonMap.dungeon
    local id = findEntry(d.quests, function(q) return addon.QuestStart(q) ~= nil end)
    local start = addon.QuestStart(id)
    menu:Find("Dungeon quests"):Find(addon.Quest(id).name):Click()
    equal(env.WorldMapFrame:GetMapID(), start.mapID, "quest start shown in the world map")
    check(not frame:IsShown(), "back outdoors")
    check(locate(env, function(e) return e == start end), "quest start pin even when normally filtered")
end)

test("class and sparse profession slots select relevant trainers and react to skill changes", function()
    local _, env, state = load({mapID=1453, class="MAGE", professionIndices={[4]=17}, professionSkills={[17]=171}})
    env.WorldMapFrame:Show()
    check(locate(env, function(e) return e.source.classToken == "MAGE" end), "mage trainers")
    check(not locate(env, function(e) return e.source.classToken == "WARRIOR" end), "other classes hidden")
    check(locate(env, function(e) return e.source.skillID == 171 end), "alchemy in a sparse profession slot")
    check(not locate(env, function(e) return e.source.skillID == 164 end), "blacksmiths hidden")
    state.professionSkills[17] = 164
    Wow.fire("SKILL_LINES_CHANGED")
    check(locate(env, function(e) return e.source.skillID == 164 end), "learned profession")
    check(not locate(env, function(e) return e.source.skillID == 171 end), "abandoned profession")
    Wow.trackingMenu():Find("Trainers"):Find("Other classes and professions"):Click()
    check(locate(env, function(e) return e.source.classToken == "WARRIOR" end), "optional native tracking override")
end)

test("a profession trainer shows NPC-specific recipe prices and skill requirements", function()
    local addon, env, state = load({mapID=1453, professionIndices={1}, professionSkills={171},
        professionRanks={[171]=25}})
    env.WorldMapFrame:Show()
    local pin = locate(env, function(e) return e.source.id == 5499 end)
    check(pin, "Lilyssia Nightbreeze")
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    if #pin.entries > 1 then state.menu:Find("Lilyssia Nightbreeze"):Click(); Wow.flushTimers() end
    local potion = assert(menuRow(state.menu, "Minor Mana Potion"))
    check(potion.label:find("100 copper", 1, true), "price at this NPC")
    potion.tooltip(env.GameTooltip)
    check(findEntry(env.GameTooltip.lines, function(line) return line == "Alchemy 25" end), "recipe skill required")
    local function cost(npcID)
        return findEntry(addon.Trainers:Lessons(npcID), function(lesson) return lesson.id == 2159 end).cost
    end
    equal(cost(4212), 250, "first leatherworker")
    equal(cost(1385), 550, "same recipe, different teacher")
end)

test("weapon masters teach only class-appropriate proficiencies by default", function()
    local addon, env = load({mapID=1455, class="PALADIN"})
    env.WorldMapFrame:Show()
    check(locate(env, function(e) return e.source.id == 11865 end), "Buliwyf teaches paladins")
    check(not locate(env, function(e) return e.source.id == 13084 end), "Bixi has no paladin proficiency")
    local lessons = addon.Trainers:Lessons(11867)
    local swords = findEntry(lessons, function(row) return row.id == 201 end)
    equal(swords.cost, 1000, "Woo Ping sword skill price")
    equal(swords.source, "Classic reference", "price provenance")
    check(not findEntry(lessons, function(row) return row.id == 5011 end), "paladin cannot learn crossbows")
    Wow.trackingMenu():Find("Trainers"):Find("Other classes and professions"):Click()
    check(locate(env, function(e) return e.source.id == 13084 end), "reference mode includes Bixi")
end)

test("observed trainer prices override references for that NPC and that character only", function()
    local addon, env, state = load({npcGUID="Creature-0-1-1-1-11867-000A", services={
        {name="One-Handed Swords", spell=201, cost=900}, {name="Private Lesson", cost=0},
    }})
    Wow.fire("TRAINER_SHOW")
    local function sword()
        return findEntry(addon.Trainers:Lessons(11867), function(lesson) return lesson.id == 201 end)
    end
    equal(sword().source, "Last visit", "personal price takes priority")
    equal(sword().cost, 900, "discounted local quote")
    state.services = {{name="Private Lesson", cost=0}}
    Wow.fire("TRAINER_UPDATE")
    equal(sword().cost, 900, "filtered trainer view never removes earlier observations")
    local row = findEntry(addon.Trainers:Lessons(11867), function(lesson) return lesson.name == "Private Lesson" end)
    equal(row.cost, 0, "free and unknown prices differ")
    local saved = env.AeternumTrainerDB
    local reload = load({savedTrainerData=saved})
    equal(findEntry(reload.Trainers:Lessons(11867), function(l) return l.id == 201 end).cost, 900, "after reload")
    local other = load()
    equal(findEntry(other.Trainers:Lessons(11867), function(l) return l.id == 201 end).cost, 1000, "other character")
end)

test("class skills have ranks, levels and prices before a first visit", function()
    local addon = load()
    local spell = findEntry(addon.Trainers:Lessons(328), function(l) return l.name == "Frostbolt" end)
    check(spell and spell.rank == "Rank 1" and spell.level > 0 and spell.cost == 100, "mage lesson")
    local druid = findEntry(addon.Trainers:Lessons(5504), function(l) return l.source == "Bundled trainer record" end)
    check(druid and druid.id and druid.cost ~= nil, "observed Forever class data wins over reference")
end)

test("non-dungeon pins pass right-click through even when recycled in combat", function()
    local _, env, state = load({mapID=1453})
    env.WorldMapFrame:Show()
    state.inCombat = true
    env.WorldMapFrame:SetMapID(1429)
    local pin = locate(env, function(e) return e.category ~= "dungeon" end)
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    check(env.WorldMapFrame.zoomedOut and not state.menu, "Blizzard's zoom-out handler")
end)

test("quest pins restyle in place and redraw only when the quest list changes", function()
    local _, env, state = load({level=1})
    env.WorldMapFrame:Show()
    local fn = function(e) return e.questID == 783 and e.role == "start" end
    local start = locate(env, fn)
    Wow.fire("QUEST_LOG_UPDATE"); Wow.flushTimers()
    equal(locate(env, fn), start, "same pin after an unrelated log update")
    state.log[783] = 1
    Wow.fire("QUEST_ACCEPTED", 783); Wow.flushTimers()
    check(not locate(env, fn), "accepted start removed")
    check(locate(env, function(e) return e.questID == 783 and e.role == "turnin" end), "turn-in drawn")
end)

test("unrecorded or missing prices are never reported as free", function()
    local addon = load({npcGUID="Creature-0-1-1-1-11867-000B", services={{name="Unknown cost"}}})
    Wow.fire("TRAINER_UPDATE")
    equal(findEntry(addon.Trainers:Lessons(11867), function(l) return l.name == "Unknown cost" end).cost, nil)
end)

test("continent entrance pins project into the parent map and route to their original zone", function()
    local addon, env, state = load({mapID=1415, playerMap=1436, playerX=.2, playerY=.2})
    env.Enum.UIMapType = {World=0, Continent=1}
    env.C_Map.GetMapInfo = function(id)
        if id == 1415 then return {mapType=1, name="Eastern Kingdoms"} end
        return {mapType=3, parentMapID=id == 1436 and 1415 or 0, name="Westfall"}
    end
    env.C_Map.GetMapRectOnMap = function(id, parent)
        equal(id, 1436); equal(parent, 1415)
        return .1, .5, .2, .6
    end
    env.WorldMapFrame:Show()
    local pin, door = locate(env, function(e) return e.source.id == "deadmines" end)
    equal(door.mapID, 1415, "displayed on continent")
    equal(door.point.mapID, 1436, "route in Westfall")
    check(math.abs(door.x - (.1 + door.point.x * .4)) < .00001, "projected coordinate")
    check(not locate(env, function(e) return e.source.id == "ragefire-chasm" end), "other continent excluded")
    equal(pin.icon:GetWidth(), 30, "continent entrance artwork")
    equal(pin:GetWidth(), 40, "continent entrance target")
    env.WorldMapFrame:ClickPin(pin, "RightButton", 19, 0)
    state.menu:Find("Show path to The Deadmines"):Click()
    equal(#addon.Navigation.points, 2, "Westfall approach")
end)

test("focusing a second map location restores the first pin's style and size", function()
    local addon, env = load({mapID=1453})
    env.WorldMapFrame:Show()
    local points = {}
    for _, pin in ipairs(pins(env)) do
        if pin.entry.category ~= "dungeon" then points[#points + 1] = pin end
    end
    local first, second = points[1], points[2]
    equal(first.icon:GetWidth(), 17, "regular map artwork")
    equal(first:GetWidth(), 17, "regular click target")
    addon.FocusLocation(first.entries[#first.entries])
    equal(first.icon:GetWidth(), 23)
    equal(first:GetWidth(), 23)
    addon.FocusLocation(second.entry)
    equal(first:GetWidth(), 17, "old pin restored")
    equal(first.entry, first.entries[1])
    equal(second:GetWidth(), 23)
    addon.FocusLocation(nil)
    equal(second:GetWidth(), 17)
end)

test("dungeon floors follow unambiguous localized rooms until the player chooses a floor", function()
    local addon, env, state = load({inInstance=true, instanceID=36, subzone="Mastraum"})
    env.WorldMapFrame:Show()
    equal(addon.DungeonMap.index, 1)
    state.subzone = "Crique du cuirassé"
    Wow.fire("ZONE_CHANGED_INDOORS")
    equal(addon.DungeonMap.index, 2, "localized room identifies next floor")
    addon.DungeonMap.frame.dropdown:OpenMenu():Find("Deadmines"):Click()
    Wow.fire("ZONE_CHANGED")
    equal(addon.DungeonMap.index, 1, "manual choice survives a room change")
end)

test("locale with missing legacy art draws the equivalent client minimap mosaic", function()
    local addon, env = load({inInstance=true, instanceID=36, locale="esMX"})
    env.WorldMapFrame:Show()
    local floor = addon.floorData.deadmines.floors[1]
    local texture = addon.DungeonMap.frame.tiles[1]
    equal(texture.texture, tonumber(floor.fallback:match("^%d+")))
    equal(#texture.texCoord, 8, "rotated client minimap fragment")
end)

test("a name-only trainer quote gains its spell ID and latest price without duplicate lessons", function()
    local addon, _, state = load({npcGUID="Creature-0-1-1-1-11867-000A",
        services={{name="One-Handed Swords", cost=950}}})
    Wow.fire("TRAINER_SHOW")
    state.services = {{name="One-Handed Swords", spell=201, cost=900}}
    Wow.fire("TRAINER_UPDATE")
    state.services = {{name="One-Handed Swords", status="used", cost=0}}
    Wow.fire("TRAINER_UPDATE")
    local count = 0
    for _, lesson in ipairs(addon.Trainers:Lessons(11867)) do
        if lesson.name == "One-Handed Swords" then
            equal(lesson.id, 201); equal(lesson.cost, 900)
            count = count + 1
        end
    end
    equal(count, 1, "one last-visit lesson")
end)

test("optional drop search opens the same map floor and loot as a boss pin", function()
    local addon, env, state = load()
    slash(env, "dungeons Cruel Barb")
    menuRow(state.menu, "Cruel Barb"):Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.dungeon.id, "deadmines", "selected dungeon")
    equal(addon.DungeonMap.index, 2, "boss floor")
    equal(state.menu.children[1].label, "Edwin VanCleef")
end)

test("every dungeon has an exterior door and recorded approaches reach the selected entrance", function()
    local addon, env, state = load({mapID=1449, playerMap=1449, playerX=.8, playerY=.8})
    local count, routes = 0, 0
    for _, d in ipairs(addon.Data.dungeons) do
        local doors = addon.DungeonEntrances(d)
        check(#doors > 0, d.name)
        for _, entry in ipairs(doors) do
            check(findEntry(addon.MapRecords(entry.mapID), function(e) return e == entry end), d.name)
            count = count + 1
            if entry.point.waypoints then routes = routes + 1 end
        end
    end
    equal(count, 41); equal(routes, 10)
    env.WorldMapFrame:Show()
    local pin = locate(env, function(e) return e.source.id == "shapers-terrace" end)
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    state.menu:Find("Show path to Shaper's Terrace"):Click()
    equal(addon.Navigation.points[1].label, "Stone staircase")
    equal(#addon.Navigation.points, 2)
    check(pin.tracked:IsShown(), "active door marked on the map")
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    local doorMenu = addon.DungeonMap.frame.dropdown:OpenMenu():Find("Entrances")
    doorMenu:Find("Stop directions"):Click()
    doorMenu:Find("Show on zone map"):Click()
    equal(env.WorldMapFrame.panX, .482); equal(env.WorldMapFrame.panY, .057)
    check(not addon.DungeonMap.dungeon and not env.AeternumRouteDB, "back at the actual portal")
end)

test("directions survive a reload and an unrelated instance, then finish on entry to the destination", function()
    local addon, env = load({playerMap=1436, playerX=.05, playerY=.05})
    local dungeon = dungeonNamed(addon, "deadmines")
    check(addon.Navigation:Start(dungeon.name, dungeon.entrances[1], dungeon.id))
    local saved = env.AeternumRouteDB
    check(not addon.Navigation:Start("Unknown portal", {mapID=1436}), "invalid replacement rejected")
    equal(env.AeternumRouteDB, saved, "previous route intact")
    local nextAddon, client, state = load({savedRoute=saved, inInstance=true, instanceID=189})
    equal(nextAddon.Navigation:GetTarget(), dungeon.name)
    equal(nextAddon.Navigation:GetStatus(), "Guidance is paused inside an instance.")
    state.inInstance, state.playerMap, state.playerX, state.playerY = false, 1436, .05, .05
    Wow.fire("PLAYER_ENTERING_WORLD")
    check(nextAddon.Navigation.overlay:IsShown() and client.AeternumRouteDB, "route resumed outdoors")
    state.inInstance, state.instanceID, state.subzone = true, 36, "Ironclad Cove"
    Wow.fire("PLAYER_ENTERING_WORLD")
    check(not nextAddon.Navigation:IsActive() and not client.AeternumRouteDB, "destination reached")
    check(nextAddon.Navigation:GetStatus():find("Arrived", 1, true))
    local other = load()
    check(not other.Navigation:IsActive(), "another character has no route")
    local corrupt, clean = load({savedRoute={mapID=1436, x=.1, y=.2, name="Old", waypoints=true}})
    check(not corrupt.Navigation:IsActive() and not clean.AeternumRouteDB, "invalid saved route discarded")
end)

test("alternate wing routes restore distinct boss positions and group an arena's loot by combatant", function()
    local addon, env, state = load()
    for key, expected in pairs({maraudon=9, stratholme=19, ["dm-north"]=7}) do
        local ids, count = {}, 0
        for _, floor in ipairs(addon.floorData[key].floors) do
            equal(#floor.toMap, 6)
            for _, stop in ipairs(floor.bosses) do
                check(not ids[stop[1]], "duplicate alternate-route stop")
                ids[stop[1]], count = true, count + 1
            end
        end
        equal(count, expected, key)
    end
    env.WorldMapFrame:Show()
    addon.DungeonMap:Open(dungeonNamed(addon, "blackrock-depths"))
    local arena = findEntry(addon.DungeonMap.frame.pins, function(p)
        return p.stop and p.stop.label == "Ring of Law"
    end)
    equal(#arena.members, 6, "one skull for all possible opponents")
    arena:Click()
    state.menu:Find("Gorosh the Dervish"):Click()
    Wow.flushTimers()
    equal(state.menu.children[1].label, "Gorosh the Dervish")
    check(menuRow(state.menu, "Savage Gladiator Chain")
        or menuRow(state.menu:Find("Guide-listed drops"), "Savage Gladiator Chain"), "selected boss's own loot")
end)

test("Forever-specific named drops fill previously empty boss menus", function()
    local addon, env, state = load()
    env.WorldMapFrame:Show()
    local dungeon = dungeonNamed(addon, "alcaz-prison")
    addon.DungeonMap:Open(dungeon)
    for boss, id in pairs({["Katerina the Cleaner"]=276738, Blazeroar=276744}) do
        addon.DungeonMap.frame.dropdown:OpenMenu():Find("Boss loot"):Find(boss):Click()
        Wow.flushTimers()
        local parent = boss == "Katerina the Cleaner" and state.menu:Find("Encounter rolls") or state.menu
        check(menuRow(parent, addon.Data.items[id]), boss)
        equal(state.menu.children[1].label, boss)
    end
end)

test("Rhahk'Zor separates his recorded gear, other corpse drops, and encounter rolls", function()
    local addon, _, state = openDeadmines({professionIndices={1, 2}, professionSkills={164, 197},
        professionRanks={[164]=80, [197]=75}})
    local boss = assert(findEntry(addon.DungeonMap.dungeon.bosses, function(b) return b.id == 644 end))
    addon.UI:Boss(addon.DungeonMap.frame, boss)
    local menu = state.menu
    for _, id in ipairs({5187, 872, 273289}) do check(menuRow(menu, addon.Data.items[id])) end
    local other = menu:Find("Other recorded drops")
    for _, id in ipairs({251340, 251341, 253912}) do check(menuRow(other, addon.Data.items[id])) end
    check(menuRow(menu:Find("Encounter rolls"), addon.Data.items[253902]))
    for _, id in ipairs({14166, 251362, 251364, 253906}) do
        check(not findEntry(boss.loot, function(item) return id == item end), "unsupported Rhahk'Zor drop")
    end
    check(not findEntry(addon.DungeonMap.dungeon.bosses, function(b) return b.id == 641 end))
    local point = assert(findEntry(addon.floorData["ragefire-chasm"].floors[1].bosses, function(p)
        return p[1] == 11517
    end))
    check(point.pull and point[2] == .5654 and point[3] == .3816, "Oggleflint's recorded pull area")
end)

test("Rhahk'Zor shows trained weapons and learnable plans from a cold item cache", function()
    local addon, _, state = openDeadmines({class="HUNTER", level=18, skillRanks={[172]=1, [414]=1}})
    local boss = findEntry(addon.DungeonMap.dungeon.bosses, function(b) return b.id == 644 end)
    addon.UI:Boss(addon.DungeonMap.frame, boss)
    check(menuRow(state.menu, "Rockslicer") and menuRow(state.menu, "Ogre Loincloth"))
    check(not menuRow(state.menu, "Rhahk'Zor's Hammer"))
    check(not menuRow(state.menu, "Other recorded drops") and not menuRow(state.menu, "Encounter rolls"))
    check(not state.requested[251341] and not state.requested[5187], "ineligible items never requested")

    local original = state.menuProxy
    state.professionIndices = {[4]=17}
    state.professionSkills = {[17]=164}
    state.professionRanks = {[164]=79}
    Wow.fire("SKILL_LINES_CHANGED")
    Wow.flushTimers()
    equal(original, state.menuProxy, "rank below the threshold leaves the menu in place")
    state.professionRanks[164] = 80
    Wow.fire("SKILL_LINES_CHANGED")
    Wow.flushTimers()
    local other = state.menu:Find("Other recorded drops")
    check(menuRow(other, "Guard's Chain Shirt") and state.requested[251341])
    check(not menuRow(other, "Gown") and not menuRow(state.menu, "Encounter rolls"))
    check(not addon.LootFilter()(14147), "hunter can learn mail plans before learning to wear mail")
    state.knownSpells = {[1252238]=true, [1252237]=true}
    Wow.fire("SPELLS_CHANGED")
    Wow.flushTimers()
    check(not menuRow(state.menu, "Other recorded drops"), "both plans learned")
end)

test("professions, specializations and class books use the character's actual requirements", function()
    local addon, _, state = load({class="MAGE", professionIndices={1}, professionSkills={164},
        professionRanks={[164]=300}})
    local usable = addon.LootFilter()
    check(usable(251341) and not usable(274049), "blacksmith plans and engineering schematic")
    check(not usable(11612), "Dark Iron Plate needs Armorsmithing")
    check(usable(18600), "mage can learn Arcane Brilliance")
    check(usable(282712) and not usable(22400), "quest libram and paladin relic")
    state.knownSpells = {[9788]=true, [23028]=true}
    usable = addon.LootFilter()
    check(usable(11612) and not usable(18600), "specialization and learned class spell")

    local paladin = load({class="PALADIN"}).LootFilter()
    check(paladin(22400) and not paladin(22395) and not paladin(18600))
    local druid = load({class="DRUID"}).LootFilter()
    check(druid(22397) and not druid(22400))
    local shaman = load({class="SHAMAN"}).LootFilter()
    check(shaman(22395) and not shaman(22397))
end)

test("armor, off-hand weapons and ammunition follow learned proficiencies", function()
    local addon, _, state = load({class="WARRIOR", skillRanks={[173]=45, [226]=30}})
    local usable = addon.LootFilter()
    check(usable(5193) and usable(273289), "cloak and cloth")
    check(not usable(14147) and not usable(280075), "unlearned mail and plate")
    check(not usable(18392), "off-hand-only dagger needs dual wield")
    check(usable(2662) and usable(9399) and not usable(2663) and not usable(13377), "crossbow ammunition")
    state.knownSpells = {[674]=true, [750]=true, [8737]=true, [266]=true}
    usable = addon.LootFilter()
    check(usable(18392) and usable(14147) and usable(280075), "trained passive skills")
    check(usable(2663) and usable(13377), "gun proficiency")
    check(not usable(13175) and not usable(99999999), "unknown requirements stay hidden")
end)

test("unavailable skill details never admit restricted loot or hide ordinary shared gear", function()
    local addon, env = load({class="MAGE", skillRanks={[202]=125}})
    env.GetProfessions = nil
    addon.Trainers:Invalidate()
    check(addon.LootFilter()(274049), "profession rank available through the native Skills tab")
    local unreadable = {}
    env.C_SkillInfo.GetSkillLineInfoByID = function() return unreadable end
    env.issecretvalue = function(value) return value == unreadable end
    env.C_SpellBook = nil
    local usable = addon.LootFilter()
    check(not usable(274049) and not usable(5187) and not usable(18600))
    check(usable(5193) and usable(273289), "shared gear remains available")
end)

test("loot search follows the same profession changes as an open boss menu", function()
    local addon, _, state = load({class="PRIEST", professionIndices={1}, professionSkills={202},
        professionRanks={[202]=124}})
    local query = "9-60 Battery Pack"
    equal(#addon.Entries(nil, true, query), 0)
    addon.UI:Search(query)
    check(menuRow(state.menu, "No matching"))
    state.professionRanks[202] = 125
    Wow.fire("SKILL_LINES_CHANGED")
    Wow.flushTimers()
    check(menuRow(state.menu, query), "newly eligible schematic appears in the open search")
    state.professionIndices = {}
    Wow.fire("SKILL_LINES_CHANGED")
    Wow.flushTimers()
    check(menuRow(state.menu, "No matching") and not menuRow(state.menu, query))
    check(#addon.Entries(nil, true, "Rhahk'Zor") > 0, "bosses stay searchable")
    local owner = addon.UI.map
    addon.UI:Boss(owner, {name="Boss", loot={251341, 253902}, lootSections={other=1, encounter=2}})
    check(menuRow(state.menu, "No usable drops") and #state.menu.children == 2, "no empty sections")
    addon.UI:Boss(owner, {name="Boss", loot={}})
    check(menuRow(state.menu, "No documented drops"), "undocumented boss remains distinct")
end)

test("the indoor player arrow uses the current floor and hides when the client restricts position", function()
    local addon, env, state = load({inInstance=true, instanceID=36, subzone="Ironclad Cove",
        playerNorth=-101.09, playerWest=-766.99})
    env.WorldMapFrame:Show()
    local map, frame = addon.DungeonMap, addon.DungeonMap.frame
    local arrow = frame.playerArrow
    check(arrow:IsVisible() and frame.positionUpdates:IsVisible())
    check(math.abs(arrow.points[1][4] / 1002 - .5) < .001, "east-west placement")
    check(math.abs(-arrow.points[1][5] / 668 - .5) < .001, "north-south placement")
    frame:Fire("OnMouseWheel", 2)
    check(math.abs(arrow:GetWidth() * frame.art.scale - 22) < .01, "screen size held while zooming")
    frame.dropdown:OpenMenu():Find("Deadmines"):Click()
    check(not arrow:IsShown() and not frame.positionUpdates:IsShown(), "viewing another floor")
    map:SetFloor(2)
    state.positionInstance = 189
    frame.positionUpdates:Fire("OnUpdate", .25)
    check(not arrow:IsShown(), "mismatched instance")
    state.positionInstance, state.playerNorth = 36, {}
    env.issecretvalue = function(value) return value == state.playerNorth end
    frame.positionUpdates:Fire("OnUpdate", .25)
    check(not arrow:IsShown(), "unreadable coordinates")
end)

test("only successful encounters or client lockouts dim the appropriate boss skull", function()
    local addon, env, state = load({inInstance=true, instanceID=36, subzone="Ironclad Cove"})
    env.WorldMapFrame:Show()
    local function skull(id)
        return findEntry(addon.DungeonMap.frame.pins, function(p) return p.boss and p.boss.id == id end)
    end
    Wow.fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 1, 5, 0)
    equal(skull(639).alpha, 1, "wipe leaves boss up")
    Wow.fire("ENCOUNTER_END", 2747, "Edwin VanCleef", 1, 5, 1)
    check(skull(639).complete and not skull(647).complete)
    skull(639):Fire("OnEnter")
    check(findEntry(env.GameTooltip.lines, function(text) return text == "Encounter complete" end))
    Wow.fire("BOSS_KILL", 2744, "Captain Greenskin")
    check(skull(647).complete)
    state.lockedEncounters = {[2747]=true}
    Wow.fire("PLAYER_ENTERING_WORLD")
    check(skull(639).complete and not skull(647).complete, "new visit consults the current lockout")
end)

test("dungeon keys report bag ownership and alternate doors remain individually selectable", function()
    local addon, env = load({inventory={[11000]=1}})
    env.WorldMapFrame:Show()
    addon.DungeonMap:Open(dungeonNamed(addon, "blackrock-depths"))
    local keys = addon.DungeonMap.frame.dropdown:OpenMenu():Find("Dungeon keys")
    check(menuRow(keys, addon.Data.items[11000]).label:find("In bags", 1, true))
    check(not menuRow(keys, addon.Data.items[11140]).label:find("In bags", 1, true))
    addon.DungeonMap:Open(dungeonNamed(addon, "uldaman"))
    local doors = addon.DungeonMap.frame.dropdown:OpenMenu():Find("Entrances")
    equal(#doors.children, 2)
    check(doors.children[1].label ~= doors.children[2].label, "two doors in the same zone")
    doors.children[2]:Find("Show on zone map"):Click()
    equal(env.WorldMapFrame:GetMapID(), 1418)
    equal(env.WorldMapFrame.panX, .652)
end)

test("quest starts, turn-ins and dungeon quest links lead to the correct named contact", function()
    local addon, env, state = load({mapID=1429, log={[783]=1, [166]=2}, complete={[783]=true, [166]=true}})
    equal(addon.QuestLocation(783, "start").contact, "Deputy Willem")
    equal(addon.QuestLocation(783, "turnin").contact, "Marshal McBride")
    env.WorldMapFrame:Show()
    local pin = locate(env, function(e) return e.questID == 783 and e.role == "turnin" end)
    check(pin)
    local dungeon = dungeonNamed(addon, "deadmines")
    addon.DungeonMap:Open(dungeon)
    local turnin = addon.QuestLocation(166, "turnin", env.WorldMapFrame:GetMapID())
    addon.DungeonMap.frame.dropdown:OpenMenu():Find("Dungeon quests"):Find(addon.Quest(166).name):Click()
    equal(env.WorldMapFrame:GetMapID(), turnin.mapID)
    equal(env.WorldMapFrame.panX, turnin.x)
    equal(env.GameTooltip.lines[1], turnin.title)
    check(findEntry(env.GameTooltip.lines, function(line) return line == turnin.contact end))
    state.log[166], state.completed[166] = nil, true
    Wow.fire("QUEST_TURNED_IN", 166); Wow.flushTimers()
    check(not locate(env, function(e) return e == turnin end), "completed quest releases its highlighted pin")
end)

test("only the focused quest's unfinished objectives appear and defer to Blizzard's map pins and filter", function()
    local addon, env, state = load({mapID=1429, log={[7]=1, [33]=2}, watched={[33]=1}, superQuest=7,
        objectives={[7]={{text="Kobold Vermin slain: 0/10", finished=false}}}})
    env.WorldMapFrame:Show()
    local function site(id) return locate(env, function(e) return e.questID == id and e.role == "objective" end) end
    local pin, entry = site(7)
    equal(entry.title, "Kobold Vermin")
    equal(pin.icon.atlas, "Quest-In-Progress-Icon-yellow")
    check(not site(33), "one quest at a time")
    pin:OnMouseEnter()
    check(findEntry(env.GameTooltip.lines, function(v) return v == state.objectives[7][1].text end))
    state.nativePOI = {[1429]={{questID=7, mapID=1429, x=.4, y=.55, isQuestStart=false}}}
    Wow.fire("QUEST_POI_UPDATE"); Wow.flushTimers()
    check(not site(7), "Blizzard already has a pin")
    state.nativePOI = nil
    state.questPOI = false
    Wow.fire("CVAR_UPDATE", "questPOI"); Wow.flushTimers()
    check(not site(7), "stock map filter")
    state.questPOI = true
    state.objectives[7][1].finished = true
    Wow.fire("QUEST_LOG_UPDATE"); Wow.flushTimers()
    check(not site(7), "objective finished")
    state.superQuest = nil
    Wow.fire("SUPER_TRACKING_CHANGED"); Wow.flushTimers()
    check(site(33), "falls back to the first watched quest")
    addon.UI:Pick(env.WorldMapFrame, addon.QuestLocation(7, "turnin"))
    state.menu:Find("Focus quest"):Click()
    equal(state.superQuest, 7, "map action uses Blizzard quest focus")
    state.menu:Find("Track quest"):Click()
    equal(state.watched[7], 1)
end)

test("packed objective sites resolve to their quest, map and named source", function()
    local addon = load()
    local quests, count = 0, 0
    for id, packed in pairs(addon.Data.objectiveSites) do
        check(addon.Quest(id), "unknown quest " .. id)
        quests = quests + 1
        local unique = {}
        for site in packed:gmatch("([^;]+);") do
            local n, zone, x, y, target = site:match("^(%d+):(%d+):(%d+),(%d+)([noz]%d+)[AH]?$")
            check(n and tonumber(n) > 0 and tonumber(zone) > 0, site)
            check(tonumber(x) <= 10000 and tonumber(y) <= 10000, site)
            check(target == "z0" or addon.Data.questContacts[target], "no name for " .. target)
            check(not unique[site], "duplicate site")
            unique[site], count = true, count + 1
        end
    end
    equal(quests, 2097); equal(count, 5207)
end)

test("profession ranks gate quest offers and sort trainer lessons as the character learns", function()
    local addon, env, state = load({mapID=1453, level=8, professionIndices={1}, professionSkills={171},
        professionRanks={[171]=19}})
    equal(addon.Quests:State(1581), "locked", "requires Alchemy 20")
    local trainer = findEntry(addon.MapRecords(1453), function(e) return e.source.id == 5499 end)
    local function lessons() addon.UI:Trainer(env.WorldMapFrame, trainer); return state.menu end
    check(menuRow(lessons():Find("Later training"), "Minor Mana Potion"), "requires Alchemy 25")
    state.professionRanks[171] = 25
    Wow.fire("SKILL_LINES_CHANGED")
    equal(addon.Quests:State(1581), "available")
    check(menuRow(lessons(), "Minor Mana Potion"), "available at this rank")
    local spell = findEntry(addon.Trainers:Lessons(5499), function(l) return l.name == "Minor Mana Potion" end)
    state.knownSpells = {[spell.id]=true}
    Wow.fire("LEARNED_SPELL_IN_SKILL_LINE")
    check(menuRow(lessons():Find("Learned"), "Minor Mana Potion"))
    state.professionRanks[171], state.log[1581], state.complete[1581] = 1, 1, true
    Wow.fire("SKILL_LINES_CHANGED")
    equal(addon.Quests:State(1581), "ready", "accepted quest can still be turned in")
end)

test("crowded maps retain every location and separate nearby pins as the player zooms", function()
    local addon, env, state = load()
    local entries = {}
    for i = 1, 220 do
        local x, y = .1 + ((i - 1) % 40) * .005, .1 + math.floor((i - 1) / 40) * .01
        local point = {mapID=1429, x=x, y=y}
        entries[i] = {category="class", title="Trainer " .. i, subtitle="Mage Trainer", source={}, point=point,
            x=x, y=y, mapID=1429}
    end
    addon.Entries = function() return entries end
    env.WorldMapFrame:Show()
    local function count()
        local all, total = pins(env), 0
        for _, p in ipairs(all) do total = total + #p.entries end
        equal(total, #entries, "every record reachable from the map")
        return #all
    end
    local grouped = count()
    check(grouped < 100, "crowded overview")
    local pin = locate(env, function(e) return e == entries[220] end)
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    state.menu:Find("Trainer 220")
    state.viewWidth = .25
    env.WorldMapFrame.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    check(count() > grouped, "more detail at higher zoom")
end)

test("recorded alternate entrances survive the data format migration", function()
    require("dungeon_entrances")(load())
end)

test("a clicked door takes precedence over the viewed zone and the primary entrance", function()
    local addon, env, state = load({mapID=1428, playerMap=1428, playerX=.1, playerY=.1})
    env.WorldMapFrame:Show()
    local depths = dungeonNamed(addon, "blackrock-depths")
    addon.DungeonMap:Open(depths)
    local function doors() return addon.DungeonMap.frame.dropdown:OpenMenu():Find("Entrances").children end
    check(doors()[1].label:find("29.4, 38.3", 1, true), "viewing Burning Steppes")
    doors()[1]:Find("Directions to entrance"):Click()
    equal(env.AeternumRouteDB.mapID, 1428)
    env.WorldMapFrame:SetMapID(1418)
    local pin = locate(env, function(e) return e.source.id == "uldaman" and e.x == .652 end)
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    check(doors()[1].label:find("65.2, 43.5", 1, true), "back door clicked in Badlands")
    doors()[1]:Find("Show on zone map"):Click()
    equal(env.WorldMapFrame.panX, .652)
    local other = addon.DungeonEntrances(depths)[2]
    other.faction = "Horde"
    equal(#addon.DungeonEntrances(depths, other.point, 1428), 1, "ineligible door filtered before preference")
    state.faction = "Neutral"
    equal(addon.DungeonEntrances(depths, other.point, 1428)[1], other)
end)

test("mixed boss, item and dungeon names work in the slash shortcut and zone search", function()
    local addon, env, state = load()
    equal(#addon.Entries(nil, true, "  herod  SCARLET  "), 1)
    equal(addon.Entries(1436, false, "Edwin Deadmines")[1].source.id, "deadmines")
    slash(env, "  barb  vancleef ")
    assert(menuRow(state.menu, "Cruel Barb")):Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.index, 2)
    equal(state.menu.children[1].label, "Edwin VanCleef")
    env.WorldMapFrame:Hide()
    slash(env, "help")
    check(state.messages[#state.messages]:find("/aeternum", 1, true))
    state.inCombat = true
    slash(env, "VanCleef")
    check(not env.WorldMapFrame:IsShown() and state.messages[#state.messages]:find("combat", 1, true))
    equal(addon.Trim(nil), ""); equal(addon.Trim(99), "")
    env.strtrim = nil
    equal(addon.Trim("  Blackrock "), "Blackrock")
    addon.settings = nil
    check(addon.CategoryEnabled("dungeon"), "safe before saved variables load")
end)

test("a route finishes when the player bypasses an approach and leaves no saved directions", function()
    local addon, env, state = load({playerMap=1429, playerX=.5, playerY=.1})
    addon.Navigation:Start("Entrance", {mapID=1429, x=.5, y=.9,
        waypoints={{mapID=1429, x=.5, y=.3}, {mapID=1429, x=.5, y=.6}}})
    equal(addon.Navigation.step, 1)
    state.playerY = .6
    addon.Navigation:Update()
    equal(addon.Navigation.step, 3, "reaching a later recorded landmark advances the route")
    addon.Navigation:Stop()
    state.playerY = .1
    addon.Navigation:Start("Entrance", {mapID=1429, x=.5, y=.9, waypoints={{mapID=1429, x=.5, y=.3}}})
    state.playerY = .9
    addon.Navigation:Update()
    check(not addon.Navigation:IsActive() and not env.AeternumRouteDB, "arrival clears route")
end)

test("rectangular minimaps preserve bearings and distinguish the upcoming entrance", function()
    local addon, env = load({playerMap=1429, playerX=.5, playerY=.5})
    env.Minimap:SetSize(220, 140)
    addon.Navigation:Start("Northeast", {mapID=1429, x=.6, y=.35})
    local overlay = addon.Navigation.overlay
    local pos = overlay.arrow.points[1]
    check(math.abs(pos[4] - pos[5]) < .001, "equal world distances use equal pixel distances")
    addon.Navigation:Start("Nearby door", {mapID=1429, x=.5, y=.41,
        waypoints={{mapID=1429, x=.5, y=.46}}})
    check(overlay.marker:IsShown())
    check(overlay.dots[1]:IsShown() and overlay.dots[1].atlas == "waypoint-mappin-minimap-tracked")
end)

test("the open loot menu updates a cached item once and ignores late replies after closing", function()
    local addon, env, state = openDeadmines()
    local boss = findEntry(addon.DungeonMap.dungeon.bosses, function(b) return b.id == 639 end)
    addon.UI:Boss(addon.DungeonMap.frame, boss)
    local proxy = state.menuProxy
    local item = assert(menuRow(state.menu, "Cruel Barb"))
    state.cached[5191] = true
    Wow.fire("ITEM_DATA_LOAD_RESULT", 5191, true)
    Wow.fire("ITEM_DATA_LOAD_RESULT", 5191, true)
    Wow.flushTimers()
    equal(proxy.refreshes, 1)
    check(item.label:find("Cached 5191", 1, true) and item.label:find("|cff", 1, true))
    state.modified = true
    item:Click()
    check(state.modifiedClick:find("[Cached 5191]", 1, true))
    Wow.fire("ITEM_DATA_LOAD_RESULT", boss.loot[1], true)
    proxy.closed()
    Wow.flushTimers()
    equal(proxy.refreshes, 1, "a closed menu is never refreshed")
    check(not addon.UI.openLoot and not env.GameTooltip:IsVisible())
end)

test("missing floor textures clear incomplete artwork and keep boss controls available", function()
    local addon, env = load({mapID=1436, missingTextures={[449604]=true}})
    env.WorldMapFrame:Show()
    addon.DungeonMap:Open(dungeonNamed(addon, "deadmines"), nil, 2)
    local frame = addon.DungeonMap.frame
    check(frame.artNotice:IsShown())
    for _, texture in ipairs(frame.tiles) do check(not texture:IsShown()) end
    check(findEntry(frame.pins, function(pin) return pin:IsShown() and pin.boss.id == 639 end))
    addon.DungeonMap:SetFloor(1)
    check(not frame.artNotice:IsShown() and frame.tiles[1]:IsShown(), "normal floor recovers")
end)

test("generated Lua round-trips sparse tables, mixed keys, reserved names and large race masks", function()
    local _, literal = dofile(testDirectory .. "/../tools/lua_literal.lua")
    local sample = {[1]="first", [3]="third", [false]="flag", ["end"]=true, ["dm-east"]=8589934770}
    local decoded = assert(loadstring("return " .. literal(sample)))()
    for key, value in pairs(sample) do equal(decoded[key], value, tostring(key)) end
    for key, value in pairs(decoded) do equal(sample[key], value, tostring(key)) end
end)

test("all shipped floors open and every boss menu shows its eligible recorded drops in order", function()
    local addon, env, state = load()
    env.WorldMapFrame:Show()
    local map = addon.DungeonMap
    local floors, bosses = 0, 0
    local usable = addon.LootFilter()
    local allItems = {}
    for _, dungeon in ipairs(addon.Data.dungeons) do
        addon.UI:Pick(env.WorldMapFrame, {category="dungeon", source=dungeon})
        for i, floor in ipairs(addon.floorData[dungeon.id].floors) do
            map:SetFloor(i)
            check(not map.frame.artNotice:IsShown(), dungeon.name .. " / " .. floor.name)
            local members = 0
            for _, skull in ipairs(map.frame.pins) do
                if skull:IsShown() then members = members + #skull.members end
            end
            equal(members, #floor.bosses, dungeon.name .. " / " .. floor.name)
            floors = floors + 1
        end
        local list = map.frame.dropdown:OpenMenu():Find("Boss loot")
        for _, boss in ipairs(dungeon.bosses) do
            list:Find(boss.name):Click()
            Wow.flushTimers()
            equal(state.menu.children[1].label, boss.name)
            local ids = {}
            for _, row in ipairs(state.menu.children) do
                if row.action and #row.children == 0 then ids[#ids+1] = row end
                for _, child in ipairs(row.children) do ids[#ids+1] = child end
            end
            local count = 0
            for _, id in ipairs(boss.loot) do
                allItems[id] = true
                check(addon.lootRules[id] ~= nil, "missing requirement record for " .. id)
                if usable(id) then
                    count = count + 1
                    check(ids[count].label:find(addon.ItemName(id), 1, true), boss.name .. " " .. id)
                end
            end
            equal(#ids, count, boss.name)
            bosses = bosses + 1
        end
    end
    equal(floors, 71); equal(bosses, 302)
    local total, unverified, learnable = 0, 0, 0
    for id, rule in pairs(addon.lootRules) do
        check(allItems[id], "stale requirement record " .. id)
        total = total + 1
        if not rule then unverified = unverified + 1
        elseif rule.teaches then learnable = learnable + 1 end
    end
    equal(total, 1404); equal(unverified, 8); equal(learnable, 139)
end)

test("every trainer location opens its lesson list and every eligible reference pin survives grouping", function()
    local addon, env, state = load({level=60, faction="Neutral", savedVariables={questMode="all", otherTrainers=true}})
    env.WorldMapFrame:Show()
    local maps, trainers = {}, 0
    for id in pairs(addon.Data.questPins) do maps[id] = true end
    for _, trainer in ipairs(addon.Data.trainers) do maps[trainer.mapID] = true end
    for id in pairs(maps) do
        env.WorldMapFrame:SetMapID(id)
        local drawn = {}
        for _, pin in ipairs(pins(env)) do
            for _, entry in ipairs(pin.entries) do
                check(not drawn[entry], "duplicate pin on map " .. id)
                drawn[entry] = true
                if entry.category == "class" or entry.category == "profession" or entry.category == "weapon" then
                    addon.UI:Pick(pin, entry)
                    equal(state.menu.children[1].label, entry.title)
                    trainers = trainers + 1
                end
            end
        end
        for _, entry in ipairs(addon.Entries(id, false)) do check(drawn[entry], entry.title) end
    end
    equal(trainers, 562)
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
