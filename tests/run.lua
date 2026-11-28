-- Headless tests: luajit tests/run.lua (from the repository root).
local testDirectory = arg[0]:match("^(.*)/") or "."
package.path = testDirectory .. "/?.lua;" .. package.path
local Wow = require("wow")

local ADDON = "Aeternum"
local passed, failed = 0, 0

-- Every test also fails if add-on code wrote Blizzard-owned state while it ran: in the
-- client that taints Blizzard's code and the game blocks its protected calls.
local function test(name, body)
    Wow.state, Wow.env = nil, nil
    local ok, problem = xpcall(body, debug.traceback)
    if ok and Wow.state and Wow.env then
        local writes = Wow.addonMapWrites()
        if #writes > 0 then
            ok, problem = false, "add-on code wrote Blizzard-owned state: " .. table.concat(writes, ", ")
        end
    end
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
    -- The client's login sequence.
    Wow.fire("ADDON_LOADED", ADDON)
    Wow.fire("PLAYER_LOGIN")
    Wow.fire("PLAYER_ENTERING_WORLD", true, false)
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

test("the map's zoom levels and wheel mode stay as Blizzard wrote them", function()
    for _, levels in ipairs({{{scale=1, layerIndex=1}}, {{scale=.5, layerIndex=1}, {scale=2, layerIndex=2}}}) do
        local _, env = load({mapID=1436, zoomLevels=levels})
        local map = env.WorldMapFrame
        map:Show()
        map:SetMapID(1429)
        map:SetMapID(1436)
        map:Hide()
        map:Show()
        equal(table.concat(Wow.addonMapWrites(), ", "), "", "add-on writes to Blizzard map state")
    end
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
    local addon, env, state = load({mapID=1436, viewWidth=.5})
    local map = env.WorldMapFrame
    map:Show()
    local function isDeadmines(entry) return entry.source.id == "deadmines" end
    local pin, door = locate(env, isDeadmines)
    local function size(icon, target)
        equal(pin.icon:GetWidth(), icon); equal(pin.icon:GetHeight(), icon)
        equal(pin:GetWidth(), target); equal(pin:GetHeight(), target)
    end
    size(44, 48)
    equal(pin.icon.points[1][1], "CENTER")
    equal(pin.tracked.points[1][2], pin.icon, "route badge follows the artwork")
    addon.FocusLocation(door)
    size(50, 54)
    addon.FocusLocation(nil)
    size(44, 48)
    addon.settings.filters.dungeon = false
    addon.RefreshMap()
    addon.FocusLocation(door)
    pin = locate(env, isDeadmines)
    size(50, 54)
    addon.FocusLocation(nil)
    addon.settings.filters.dungeon = true
    addon.RefreshMap()
    equal(locate(env, isDeadmines), pin, "entrance frame reused")
    size(44, 48)
    map:ClickPin(pin, "LeftButton", 25, 0)
    check(not addon.DungeonMap.dungeon, "outside the target")
    map:ClickPin(pin, "RightButton", -23, 23)
    state.menu:Find("Show path to The Deadmines")
    map:ClickPin(pin, "LeftButton", 23, -23)
    equal(addon.DungeonMap.dungeon, door.source, "padding opens the floor map")
end)

test("a zone entrance grows again on close zoom and lights up only under the mouse", function()
    local addon, env, state = load({mapID=1436, viewWidth=.61})
    local map = env.WorldMapFrame
    map:Show()
    local function deadmines(entry) return entry.source.id == "deadmines" end
    local pin, entrance = locate(env, deadmines)
    equal(pin.icon:GetWidth(), 34, "zone artwork")
    equal(pin:GetWidth(), 22, "only the center takes clicks")
    addon.FocusLocation(entrance)
    equal(pin.icon:GetWidth(), 40, "focus enlarges the artwork")
    equal(pin:GetWidth(), 22, "focus leaves nearby zone clicks free")
    check(env.GameTooltip:IsOwned(pin))
    check(not pin.hoverGlow or not pin.hoverGlow:IsShown(), "focus does not simulate a mouseover")
    addon.FocusLocation(nil)
    pin:OnMouseEnter()
    check(pin.hoverGlow and pin.hoverGlow:IsShown() and env.GameTooltip:IsOwned(pin), "glow and tooltip")
    equal(pin.hoverGlow.atlas, "UI-QuestPoi-OuterGlow")
    equal(pin:GetWidth(), 22, "hover leaves click area alone")
    pin:OnMouseLeave()
    check(not pin.hoverGlow:IsShown() and not env.GameTooltip:IsShown(), "leave clears both")
    pin:OnMouseEnter()
    state.viewWidth = .59
    map.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    pin = locate(env, deadmines)
    equal(pin.icon:GetWidth(), 44, "close up even within the same layout grid size")
    equal(pin:GetWidth(), 48, "close-up click padding")
    check(not pin.hoverGlow or not pin.hoverGlow:IsShown(), "recycled pin starts unhighlighted")
    state.viewWidth = .61
    map.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    equal(locate(env, deadmines):GetWidth(), 22, "zooming out restores the tight click area")
end)

test("adjacent Razorfen entrances have distinct click targets in the zone overview", function()
    local addon, env, state = load({mapID=1413})
    local map = env.WorldMapFrame
    map.ScrollContainer:SetSize(400, 320)
    map:Show()
    local function kraul(e) return e.source.id == "razorfen-kraul" end
    local function downs(e) return e.source.id == "razorfen-downs" end
    local pin = locate(env, kraul)
    check(locate(env, downs) ~= pin, "compact entrances fit separately")
    map:ClickPin(pin, "RightButton", 3, 0)
    state.menu:Find("Show path to Razorfen Kraul")
    check(not menuRow(state.menu, "Show path to Razorfen Downs"), "only the door clicked is in the menu")
    map:ClickPin(pin, "LeftButton", -3, 0)
    equal(addon.DungeonMap.dungeon.id, "razorfen-kraul")
    addon.DungeonMap:Close()
    state.viewWidth = .25
    map.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    check(locate(env, kraul) ~= locate(env, downs), "each door gets its own target at higher zoom")
end)

test("native pin scale regroups close entrances and a tracked member keeps its group's anchor", function()
    local addon, env = load({mapID=1413, playerMap=1413})
    local map = env.WorldMapFrame
    map.ScrollContainer:SetSize(400, 320)
    map:Show()
    local function kraul(e) return e.source.id == "razorfen-kraul" end
    local function downs(e) return e.source.id == "razorfen-downs" end
    check(locate(env, kraul) ~= locate(env, downs))
    map:SetGlobalPinScale(1.5)
    Wow.flushTimers()
    local pin, door = locate(env, kraul)
    equal(pin, locate(env, downs), "the larger hitboxes overlap")
    equal(pin.scale, 3, "pooled pin adopts the current canvas and native pin scales immediately")
    local x, y = pin.x, pin.y
    addon.Navigation:Start(door.title, door.point, door.source.id)
    addon.UpdateRoutePins()
    check(pin.tracked:IsShown())
    equal(pin.x, x); equal(pin.y, y)
    map:SetGlobalPinScale(1)
    Wow.flushTimers()
    check(locate(env, kraul) ~= locate(env, downs), "the smaller targets separate")
end)

test("shared entrances retain the chosen wing for both buttons", function()
    local addon, env, state = load({mapID=1420, viewWidth=.5, playerMap=1420, playerX=.2, playerY=.2})
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
    env.WorldMapFrame.ScrollContainer:SetSize(400, 320)
    env.WorldMapFrame:Show()
    local west = locate(env, function(e) return e.source.id == "dm-west" end)
    env.WorldMapFrame:ClickPin(west, "RightButton")
    local second = assert(menuRow(state.menu, "60.3, 29.7"))
    second:Click()
    equal(env.AeternumRouteDB.y, .2968)
    state.viewWidth = .125
    env.WorldMapFrame.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    local function backDoor(e) return e.source.id == "dm-west" and e.y == .2968 end
    local function frontDoor(e) return e.source.id == "dm-west" and e.y == .3175 end
    equal(locate(env, backDoor), locate(env, frontDoor), "these targets still overlap on the letterboxed terrain")
    state.viewWidth = .10
    env.WorldMapFrame.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    local a, b = locate(env, backDoor), locate(env, frontDoor)
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
    local addon, env, state = openDeadmines()
    local floors, frame = addon.DungeonMap, addon.DungeonMap.frame
    equal(floors.dungeon.id, "deadmines", "map opened from pin")
    equal(frame:GetParent(), env.WorldMapFrame, "part of the map")
    equal(frame.points[1][2], env.WorldMapFrame.ScrollContainer, "fits existing canvas")
    equal(frame.tiles[1].texture, 449591, "native first-floor art")
    frame.dropdown:OpenMenu():Find("Ironclad Cove"):Click()
    equal(frame.tiles[1].texture, 449603, "second-floor art")
    check(not state.escapeTainted, "addon never registers an insecure Escape handler")
    frame:Fire("OnMouseUp", "RightButton")
    check(not floors.dungeon and env.WorldMapFrame:IsShown(), "right-click returns to zone")
    check(not frame.tiles[1].texture, "closed floor releases tiles")
    addon.DungeonMap:Open(dungeonNamed(addon, "deadmines"))
    Wow.pressEscape()
    check(not env.WorldMapFrame:IsShown() and not floors.dungeon, "Escape closes the map cleanly")
    check(not frame.tiles[1].texture, "closing via Escape releases tiles")
end)

test("closing the map mid-drag leaves the next floor still and releases its art", function()
    local addon, env = openDeadmines()
    local frame = addon.DungeonMap.frame
    frame:Fire("OnDragStart")
    check(frame:GetScript("OnUpdate"), "dragging the floor")
    env.WorldMapFrame:Hide()
    check(not frame:GetScript("OnUpdate"), "drag ends with the map")
    check(not frame.tiles[1].texture, "floor art released")
    env.WorldMapFrame:Show()
    env.WorldMapFrame:ClickPin(locate(env, function(entry) return entry.title == "The Deadmines" end), "LeftButton")
    check(frame:IsShown() and not frame:GetScript("OnUpdate"), "next floor opens still")
end)

test("floor views add no Escape handler, so Blizzard can still clear the target", function()
    local addon, env, state = openDeadmines()
    check(addon.DungeonMap.frame:IsShown(), "floor view open")
    addon.DungeonMap:Close()
    addon.DungeonMap:Open(dungeonNamed(addon, "deadmines"))
    check(not state.escapeTainted, "Blizzard's shared Escape list untouched")
    state.target = "Defias Pillager"
    Wow.pressEscape()
    check(not env.WorldMapFrame:IsShown(), "first Escape closes the map")
    equal(state.target, "Defias Pillager", "target kept while a window closed")
    Wow.pressEscape()
    equal(state.target, nil, "second Escape clears the target")
    equal(state.forbidden, nil, "ADDON_ACTION_FORBIDDEN")
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
    Wow.flushTimers()
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
    local function cloak(npcID)
        return findEntry(addon.Trainers:Lessons(npcID), function(lesson) return lesson.id == 2159 end)
    end
    equal(cloak(4212).cost, 225, "Telonis's Honored quote")
    equal(cloak(4212).priceBasis, 6)
    equal(cloak(1385).cost, 250, "Brawn's observed and guide-listed price")
end)

test("weapon masters teach only class-appropriate proficiencies by default", function()
    local addon, env = load({mapID=1455, class="PALADIN"})
    env.WorldMapFrame:Show()
    check(locate(env, function(e) return e.source.id == 11865 end), "Buliwyf teaches paladins")
    check(not locate(env, function(e) return e.source.id == 13084 end), "Bixi has no paladin proficiency")
    local lessons = addon.Trainers:Lessons(11867)
    local swords = findEntry(lessons, function(row) return row.id == 201 end)
    equal(swords.cost, 1000, "Woo Ping sword skill price")
    equal(swords.source, "EG Link trainer visit", "price provenance")
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

test("new Forever trainers open with their own recorded spells and recipes on a first visit to the map", function()
    local addon, env, state = load({mapID=2521, professionIndices={1}, professionSkills={164},
        professionRanks={[164]=34}, class="PALADIN", level=20})
    env.WorldMapFrame:Show()
    local entry = findEntry(addon.MapRecords(2521), function(e) return e.source and e.source.id == 251913 end)
    addon.UI:Pick(env.WorldMapFrame, assert(entry))
    check(menuRow(state.menu, "Sharpening Wheel"))
    local boots = menuRow(state.menu:Find("Later training"), "Glowing Copper Boots")
    check(boots and boots.label:find("100 copper", 1, true))
    boots.tooltip(env.GameTooltip)
    check(findEntry(env.GameTooltip.lines, function(line) return line == "Blacksmithing 35" end))
    check(findEntry(env.GameTooltip.lines, function(line) return line:find("Zephras", 1, true) end))
    check(findEntry(env.GameTooltip.lines, function(line) return line:find("build unreported", 1, true) end))
    check(next(env.AeternumTrainerDB) == nil, "browsing the map never writes a personal trainer visit")
    local shari = addon.Trainers:Lessons(246152)
    local hammer = assert(findEntry(shari, function(l) return l.id == 853 end))
    equal(hammer.source, "EG Link and Zephras trainer visits")
    equal(hammer.rank, "Rank 1"); equal(hammer.level, 8); equal(hammer.cost, 100)
    equal(#addon.Trainers:Lessons(248415), 5, "Tordrin's own five recorded hunter lessons")
    equal(#addon.Trainers:Lessons(246797), 0, "a class alone does not assign spells to Jessa")
end)

test("recorded trainer requirements follow racial spells, factions, talents and prior ranks", function()
    local addon, _, state = load({class="PRIEST", raceID=1, level=60})
    local function lesson(npc, id)
        return findEntry(addon.Trainers:Lessons(npc), function(l) return l.id == id end)
    end
    check(lesson(377, 19271), "Human priest can see Feedback")
    state.raceID = 3
    check(not lesson(377, 19271), "Dwarf priest cannot learn Feedback")
    check(not lesson(5958, 3567), "Horde-only teleport on an Alliance character")
    state.faction = "Horde"
    check(lesson(5958, 3567))
    local light = assert(lesson(246152, 639))
    local group, why = addon.Trainers:LessonState(light)
    equal(group, "later"); equal(why, "Requires Holy Light (Rank 1)")
    state.knownSpells = {[635]=true}
    equal(addon.Trainers:LessonState(light), nil, "learning the previous rank unlocks the lesson")
    local mutilate = assert(lesson(3170, 1241582))
    equal(addon.Trainers:LessonState(mutilate), "later")
    state.knownSpells[399956] = true
    equal(addon.Trainers:LessonState(mutilate), nil, "current Forever Mutilate talent ID")
end)

test("trainer teaching spells and old saved visits resolve to the same learned spell", function()
    local saved = {[251913]={["Apprentice Blacksmith|"]={id=2020, name="Apprentice Blacksmith", cost=7}}}
    local addon, _, state = load({savedTrainerData=saved, npcGUID="Creature-0-1-1-1-251913-00A",
        services={{name="Apprentice Blacksmith", spell=2020, cost=8}}})
    local function apprentice()
        local found = {}
        for _, row in ipairs(addon.Trainers:Lessons(251913)) do
            if row.id == 2018 or row.id == 2020 then found[#found+1] = row end
        end
        equal(#found, 1, "one learned profession")
        equal(found[1].id, 2018)
        equal(found[1].source, "Last visit")
        equal(found[1].priceBasis, nil)
        return found[1]
    end
    equal(apprentice().cost, 7, "legacy saved wrapper")
    Wow.fire("TRAINER_SHOW")
    equal(apprentice().cost, 8, "new personal quote wins over the downloaded record")
    state.knownSpells = {[2018]=true}
    equal(addon.Trainers:LessonState(apprentice()), "learned")
    check(findEntry(addon.Trainers:Lessons(5515), function(l) return l.id == 1853 end),
        "a hunter's Beast Training ability remains distinct from the attack it teaches a pet")
end)

test("a beta trainer marks its recipes and quotes a current guide price", function()
    local addon, env, state = load({mapID=2521, professionIndices={1}, professionSkills={197},
        professionRanks={[197]=30}})
    env.WorldMapFrame:Show()
    local entry = findEntry(addon.MapRecords(2521), function(e) return e.source and e.source.id == 251991 end)
    addon.UI:Pick(env.WorldMapFrame, assert(entry))
    local vest = assert(menuRow(state.menu, "Brown Linen Vest"))
    check(vest.label:find("Beta", 1, true) and vest.label:find("50 copper", 1, true))
    vest.tooltip(env.GameTooltip)
    check(findEntry(env.GameTooltip.lines, function(line) return line:find("beta trainer visit", 1, true) end))
    check(findEntry(env.GameTooltip.lines, function(line) return line:find("What's Training", 1, true) end))
    state.npcGUID = "Creature-0-1-1-1-251991-00A"
    state.services = {{name="Brown Linen Vest", spell=2385, status="used", cost=0, level=0}}
    Wow.fire("TRAINER_SHOW")
    local seen = assert(findEntry(addon.Trainers:Lessons(251991), function(l) return l.id == 2385 end))
    equal(seen.beta, nil); equal(seen.source, "Last visit"); equal(seen.cost, 50); equal(seen.priceBasis, 10)
end)

test("all downloaded assignments resolve at mapped trainers and beta lessons match a live trainer role", function()
    local addon = load()
    local src, npcs, spellIDs, pairsCount = addon.foreverTraining, 0, {}, 0
    local mapped, available = {}, 0
    local live, beta, betaRows = {}, {}, 0
    for _, trainer in ipairs(addon.Data.trainers) do
        mapped[trainer.id] = trainer.kind .. ":" .. (trainer.classToken or trainer.skillID or "")
    end
    for id in pairs(mapped) do
        if addon.Data.offers[id] or addon.classicTraining.trainers[id] or src.offers[id] then
            available = available + 1
        end
    end
    for npc, list in pairs(src.offers) do
        check(mapped[npc])
        npcs = npcs + 1
        local seen = {}
        for offer in list:gmatch("[^;]+") do
            local id = tonumber(offer:match("^(%d+):"))
            check(src.spells[id] and not seen[id] and not src.serviceSpells[id], "ambiguous trainer offer " .. offer)
            local basis, source = offer:match(":(%d*):(%d+)$")
            local roleSpell = mapped[npc] .. ":" .. id
            if source == "4" or source == "6" or source == "7" then
                check(not addon.Data.offers[npc] and not addon.classicTraining.trainers[npc])
                check(basis == "" or basis == "10", "beta prices must come from the live guide")
                beta[roleSpell], betaRows = true, betaRows + 1
            elseif source ~= "5" then
                live[roleSpell] = true
            end
            seen[id], spellIDs[id] = true, true
            pairsCount = pairsCount + 1
        end
    end
    local count = 0
    for _ in pairs(spellIDs) do count = count + 1 end
    for roleSpell in pairs(beta) do check(live[roleSpell], "no matching live offer for " .. roleSpell) end
    equal(betaRows, 423)
    equal(available, 522); equal(npcs, 248); equal(count, 1743); equal(pairsCount, 10657)
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

test("world and continent entrance pins keep tight hitboxes and route to their original zone", function()
    local addon, env, state = load({mapID=947, viewWidth=.25, playerMap=1436, playerX=.2, playerY=.2})
    local types = env.Enum.UIMapType
    local parents = {[1414]=947, [1415]=947, [1436]=1415, [1454]=1414}
    env.C_Map.GetMapInfo = function(id)
        local mapType = id == 947 and types.World or
            ((id == 1414 or id == 1415) and types.Continent or types.Zone)
        return {mapType=mapType, parentMapID=parents[id] or 0, name=tostring(id)}
    end
    env.C_Map.GetMapRectOnMap = function(id, parent)
        if id == 1454 and parent == 947 then return .55, .95, .2, .6 end
        return .1, .5, .2, .6
    end
    local map = env.WorldMapFrame
    map:Show()
    for _, overview in ipairs({{947, "deadmines"}, {1414, "ragefire-chasm"}, {1415, "deadmines"}}) do
        map:SetMapID(overview[1])
        local pin = locate(env, function(e) return e.source.id == overview[2] end)
        equal(pin.icon:GetWidth(), 22, "readable overview artwork even when zoomed")
        equal(pin:GetWidth(), 16, "tight horizontal target")
        equal(pin:GetHeight(), 16, "tight vertical target")
        map:ClickPin(pin, "LeftButton", 9, 0)
        check(not addon.DungeonMap.dungeon, "outside click misses entrance")
        map:ClickPin(pin, "RightButton", 0, -9)
        check(not state.menu, "outside click leaves the native right click free")
        map:ClickPin(pin, "LeftButton", 7, 7)
        equal(addon.DungeonMap.dungeon.id, overview[2], "inside click opens the dungeon")
        addon.DungeonMap:Close()
    end
    local pin, door = locate(env, function(e) return e.source.id == "deadmines" end)
    equal(door.mapID, 1415, "displayed on continent")
    equal(door.point.mapID, 1436, "route in Westfall")
    check(math.abs(door.x - (.1 + door.point.x * .4)) < .00001, "projected coordinate")
    check(not locate(env, function(e) return e.source.id == "ragefire-chasm" end), "other continent excluded")
    map:ClickPin(pin, "RightButton", 3, 0)
    state.menu:Find("Show path to The Deadmines"):Click()
    equal(#addon.Navigation.points, 2, "Westfall approach")
    check(pin.tracked:IsShown() and pin.tracked:GetWidth() < pin.icon:GetWidth(), "compact route badge fits the pin")
end)

local function entranceMenuLabel(addon, pin, entry)
    for _, other in ipairs(pin.entries) do
        if other ~= entry and other.category == "dungeon" and other.title == entry.title then
            local point = entry.point
            local zone = point.mapID ~= entry.mapID and addon.ZoneName(point.mapID) .. " " or ""
            return ("%s · %s%.1f, %.1f"):format(entry.title, zone, point.x * 100, point.y * 100)
        end
    end
    return entry.title
end

test("all dungeon entrances are selectable on unzoomed overviews even without client rectangles", function()
    local addon, env, state = load({mapID=947, playerMap=1420, playerX=.63, playerY=.62})
    local types = env.Enum.UIMapType
    local mapInfo = env.C_Map.GetMapInfo
    env.C_Map.GetMapInfo = function(id)
        if id == 947 then return {name="Azeroth", mapType=types.World} end
        if id == 1414 or id == 1415 then return {mapType=types.Continent, parentMapID=947} end
        if id == 1420 then return {name="Tirisfal Glades", mapType=types.Zone, parentMapID=1415} end
        return mapInfo(id)
    end
    env.C_Map.GetMapRectOnMap = function(id)
        if id == 1420 then return 0, 0, 0, 0 end
    end
    local kalimdorZones = {
        [1413]=true, [1440]=true, [1443]=true, [1444]=true, [1445]=true,
        [1446]=true, [1447]=true, [1449]=true, [1454]=true,
    }
    local original = {}
    for _, dungeon in ipairs(addon.Data.dungeons) do
        for _, door in ipairs(dungeon.entrances) do original[door] = dungeon end
    end
    local map = env.WorldMapFrame
    map:Show()
    for _, mapID in ipairs({947, 1414, 1415}) do
        map:SetMapID(mapID)
        local seen = {}
        for pin in map:EnumeratePinsByTemplate("AeternumEntrancePinTemplate") do
            equal(pin:GetWidth(), 16, "shared and single entrances keep a tight target")
            pin:OnMouseEnter()
            for _, entry in ipairs(pin.entries) do
                equal(entry.source, original[entry.point], "the original door is used for navigation")
                equal(entry.mapID, mapID)
                check(entry.x > 0 and entry.x < 1 and entry.y > 0 and entry.y < 1, "pin on map")
                check(not seen[entry.point], "each entrance appears once")
                seen[entry.point] = true
                check(findEntry(env.GameTooltip.lines, function(line) return line == entry.title end), entry.title)
            end
            pin:OnMouseLeave()
            map:ClickPin(pin, "LeftButton")
            if #pin.entries == 1 then
                equal(addon.DungeonMap.dungeon, pin.entries[1].source, "pin opens the dungeon")
                addon.DungeonMap:Close()
            else
                for _, entry in ipairs(pin.entries) do
                    state.menu:Find(entranceMenuLabel(addon, pin, entry))
                end
            end
        end
        for door, dungeon in pairs(original) do
            local continent = kalimdorZones[door.mapID] and 1414 or 1415
            equal(seen[door] == true, mapID == 947 or mapID == continent, dungeon.name .. " on map " .. mapID)
        end
    end

    local function lordaeron(entry) return entry.source.id == "ruins-of-lordaeron" end
    local _, eastern = locate(env, lordaeron)
    check(math.abs(eastern.x - .44976) < .00001 and math.abs(eastern.y - .24117) < .00001, "Tirisfal on the continent")
    map:SetMapID(947)
    local pin, world = locate(env, lordaeron)
    check(math.abs(world.x - .72575) < .00001 and math.abs(world.y - .27145) < .00001, "Tirisfal on Azeroth")
    map:ClickPin(pin, "RightButton")
    state.menu:Find("Show path to Ruins of Lordaeron"):Click()
    equal(env.AeternumRouteDB.mapID, 1420, "route still leads to the outdoor entrance")
    equal(env.AeternumRouteDB.x, world.point.x)
    equal(env.AeternumRouteDB.y, world.point.y)
end)

test("every zone and city exposes exactly its doors at both zoom levels and honors the map filter", function()
    local addon, env, state = load({mapID=1436, playerX=.2, playerY=.2})
    local map, expected = env.WorldMapFrame, {}
    local surrounding = {[1453]=1429, [1454]=1411, [1455]=1426}
    local function expect(id, point, dungeon)
        expected[id] = expected[id] or {}
        expected[id][point] = dungeon
    end
    for _, dungeon in ipairs(addon.Data.dungeons) do
        for _, point in ipairs(dungeon.entrances) do
            expect(point.mapID, point, dungeon)
            if surrounding[point.mapID] then expect(surrounding[point.mapID], point, dungeon) end
        end
    end
    map:Show()
    for id, doors in pairs(expected) do
        map:SetMapID(id)
        for _, side in ipairs({"Alliance", "Horde"}) do
            state.faction = side
            for _, width in ipairs({1, .45}) do
                state.viewWidth = width
                addon.RefreshMap()
                local seen = {}
                for pin in map:EnumeratePinsByTemplate("AeternumEntrancePinTemplate") do
                    local close = width < .6
                    equal(pin.icon:GetWidth(), close and 44 or 34)
                    equal(pin:GetWidth(), close and 48 or 22)
                    for _, entry in ipairs(pin.entries) do
                        if entry.category == "dungeon" then
                            equal(entry.source, doors[entry.point], "right door on map " .. id)
                            check(not seen[entry.point], "duplicate door")
                            seen[entry.point] = true
                        end
                    end
                end
                for point, dungeon in pairs(doors) do check(seen[point], side .. " / " .. dungeon.name) end
                Wow.trackingMenu():Find("Dungeon entrances"):Click()
                equal(map:GetNumActivePinsByTemplate("AeternumEntrancePinTemplate"), 0)
                Wow.trackingMenu():Find("Dungeon entrances"):Click()
                check(map:GetNumActivePinsByTemplate("AeternumEntrancePinTemplate") > 0)
            end
        end
    end
end)

test("both mouse buttons select each recorded entrance from its home map", function()
    local addon, env, state = load({playerX=.2, playerY=.2})
    local map = env.WorldMapFrame
    map:Show()
    for _, dungeon in ipairs(addon.Data.dungeons) do
        for _, door in ipairs(dungeon.entrances) do
            map:SetMapID(door.mapID)
            local pin, entry = locate(env, function(e) return e.point == door end)
            local label = entranceMenuLabel(addon, pin, entry)
            map:ClickPin(pin, "LeftButton")
            if #pin.entries > 1 then
                state.menu:Find(label):Click()
                Wow.flushTimers()
            end
            equal(addon.DungeonMap.dungeon, dungeon, label)
            equal(addon.DungeonMap.entrance, door, label)
            addon.DungeonMap:Close()
            map:ClickPin(pin, "RightButton")
            state.menu:Find("Show path to " .. label):Click()
            equal(env.AeternumRouteDB.mapID, door.mapID, label)
            equal(env.AeternumRouteDB.x, door.x, label)
            equal(env.AeternumRouteDB.y, door.y, label)
            addon.Navigation:Stop()
        end
    end
end)

test("capital entrances open from the surrounding zone and route to the real city door", function()
    local addon, env, state = load({playerMap=1429, playerX=.4, playerY=.5})
    local map = env.WorldMapFrame
    map:Show()
    for _, sample in ipairs({
        {1429, 1453, "stockade", .20834, .37467},
        {1411, 1454, "ragefire-chasm", .46447, .02},
        {1426, 1455, "hall-of-thanes", .58063, .29437},
    }) do
        local zone, city, id, x, y = unpack(sample)
        local function isDoor(entry) return entry.source.id == id end
        map:SetMapID(zone)
        local pin, projected = locate(env, isDoor)
        check(pin and math.abs(projected.x - x) < .00001 and math.abs(projected.y - y) < .00001, id)
        equal(projected.mapID, zone)
        equal(projected.point.mapID, city)
        equal(projected.subtitle:find("Beyond the map edge", 1, true) ~= nil, zone == 1411)
        map:ClickPin(pin, "LeftButton")
        equal(addon.DungeonMap.dungeon.id, id)
        addon.DungeonMap:Close()
        map:ClickPin(pin, "RightButton")
        state.menu:Find("Show path to " .. projected.title):Click()
        equal(env.AeternumRouteDB.mapID, city)
        equal(env.AeternumRouteDB.x, projected.point.x)
        equal(env.AeternumRouteDB.y, projected.point.y)
        addon.Navigation:Stop()
        map:SetMapID(city)
        local _, original = locate(env, isDoor)
        equal(original.point, projected.point)
        local count = 0
        for _, entry in ipairs(addon.MapRecords(city)) do if isDoor(entry) then count = count + 1 end end
        equal(count, 1, "only one entrance on the city map")
        map:SetMapID(1436)
        check(not locate(env, isDoor), "does not appear in Westfall")
    end
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
    equal(env.WorldMapFrame:GetMapID(), 1449, "the door is on the open map")
    equal(env.WorldMapFrame.panX, nil, "Blizzard's map is never panned")
    equal(env.GameTooltip.owner.entry.x, .482); equal(env.GameTooltip.owner.entry.y, .057)
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
    check(skull(639).complete and skull(647).complete, "a loading screen inside the same run keeps its kills")
    state.inInstance, state.dead = false, true
    Wow.fire("PLAYER_ENTERING_WORLD")
    state.inInstance, state.dead = true, false
    Wow.fire("PLAYER_ENTERING_WORLD")
    check(skull(639).complete and skull(647).complete, "dying, releasing and running back keeps the kills")
    state.inInstance = false
    Wow.fire("PLAYER_ENTERING_WORLD")
    state.inInstance = true
    Wow.fire("PLAYER_ENTERING_WORLD")
    check(skull(639).complete and not skull(647).complete, "leaving alive forgets kills; the lockout still counts")
end)

test("outdoor ghost travel after a living exit cannot bring back the previous run's boss kills", function()
    local addon, env, state = load({inInstance=true, instanceID=36, subzone="Ironclad Cove"})
    env.WorldMapFrame:Show()
    local function greenskin()
        return findEntry(addon.DungeonMap.frame.pins, function(p) return p.boss and p.boss.id == 647 end)
    end
    Wow.fire("BOSS_KILL", 2744, "Captain Greenskin")
    check(greenskin().complete)
    state.inInstance = false
    Wow.fire("PLAYER_ENTERING_WORLD")
    state.dead = true
    Wow.fire("PLAYER_ENTERING_WORLD")
    state.inInstance, state.dead = true, false
    Wow.fire("PLAYER_ENTERING_WORLD")
    check(not greenskin().complete, "the new visit should show Captain Greenskin alive")
end)

test("dungeon keys report bag ownership and alternate doors remain individually selectable", function()
    local addon, env, state = load({inventory={[11000]=1}})
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
    equal(env.WorldMapFrame:GetMapID(), 1429, "the add-on never moves Blizzard's map")
    check(state.messages[#state.messages]:find(addon.ZoneName(1418), 1, true), "chat names the door's zone")
    env.WorldMapFrame:SetMapID(1418)
    equal(env.GameTooltip.owner.entry.x, .652, "door marked when the player opens its map")
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
    check(turnin.mapID ~= 1429, "the turn-in is in another zone")
    addon.DungeonMap.frame.dropdown:OpenMenu():Find("Dungeon quests"):Find(addon.Quest(166).name):Click()
    equal(env.WorldMapFrame:GetMapID(), 1429, "the add-on never moves Blizzard's map")
    local note = state.messages[#state.messages]
    check(note:find(turnin.contact, 1, true) and note:find(addon.ZoneName(turnin.mapID), 1, true), "chat note")
    env.WorldMapFrame:SetMapID(turnin.mapID)
    equal(env.WorldMapFrame.panX, nil, "Blizzard's map is never panned")
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
    equal(env.WorldMapFrame:GetMapID(), 1418, "the back door is on the open map")
    equal(env.GameTooltip.owner.entry.x, .652)
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

test("an open boss loot row recovers when the client retries a failed item load", function()
    local addon, _, state = openDeadmines()
    local boss = findEntry(addon.DungeonMap.dungeon.bosses, function(b) return b.id == 639 end)
    addon.UI:Boss(addon.DungeonMap.frame, boss)
    local row = assert(menuRow(state.menu, "Cruel Barb"))
    local initial = row.label
    Wow.fire("ITEM_DATA_LOAD_RESULT", 5191, false)
    Wow.flushTimers()
    equal(row.label, initial)
    state.cached[5191] = true
    Wow.fire("ITEM_DATA_LOAD_RESULT", 5191, true)
    Wow.flushTimers()
    check(row.label:find("Cached 5191", 1, true), "the same row should display the newly loaded information")
    equal(state.menuProxy.refreshes, 1)
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
    equal(total, 1428); equal(unverified, 8); equal(learnable, 141)
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

test("grouped boss pins keep encounter labels even when only a later member carries the label", function()
    local addon, env, state = openDeadmines()
    local frame = addon.DungeonMap.frame
    local sneed = findEntry(frame.pins, function(p) return p:IsShown() and #p.members > 1 end)
    check(sneed and sneed.label == "Sneed's Shredder", "Deadmines Sneed group keeps encounter label")
    sneed:Fire("OnEnter")
    equal(env.GameTooltip.lines[1], "Sneed's Shredder", "hover title uses encounter label")
    sneed:Click()
    equal(state.menu.children[1].label, "Sneed's Shredder", "boss-group menu uses encounter label")
    addon.DungeonMap:Open(dungeonNamed(addon, "sm-cathedral"))
    local cathedral = findEntry(frame.pins, function(p) return p:IsShown() and #p.members > 1 end)
    equal(cathedral.label, "Scarlet Commander Mograine", "SM Cathedral group keeps encounter label")
    addon.DungeonMap:Open(dungeonNamed(addon, "ubrs"), nil, 3)
    local rend = findEntry(frame.pins, function(p) return p:IsShown() and #p.members > 1 end)
    equal(rend.label, "Warchief Rend Blackhand", "UBRS Rend group keeps encounter label")
end)

test("maximizing the map updates dungeon floor strata and manual boss jump pauses auto-follow", function()
    local addon, env, state = load({inInstance=true, instanceID=36, subzone="Mastraum"})
    env.WorldMapFrame:Show()
    local frame = addon.DungeonMap.frame
    equal(frame:GetFrameStrata(), "DIALOG", "minimized map strata")
    env.WorldMapFrame:SetFrameStrata("FULLSCREEN")
    frame:Fire("OnSizeChanged")
    equal(frame:GetFrameStrata(), "FULLSCREEN_DIALOG", "maximized map keeps dungeon floor above canvas")
    frame.dropdown:OpenMenu():Find("Boss loot"):Find("Edwin VanCleef"):Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.index, 2, "jumped to VanCleef's floor")
    state.subzone = "Mastraum"
    Wow.fire("ZONE_CHANGED_INDOORS")
    equal(addon.DungeonMap.index, 2, "auto-follow does not snap away from a manual boss jump")
end)

test("hovered quest and route pins refresh their open tooltip on in-place state updates", function()
    local addon, env, state = load({mapID=1429, playerMap=1429, playerX=.2, playerY=.2, log={[7]=1}, superQuest=7,
        objectives={[7]={{text="Kobold Vermin slain: 1/10", finished=false}}}})
    env.WorldMapFrame:Show()
    local pin = locate(env, function(e) return e.questID == 7 and e.role == "objective" end)
    pin:OnMouseEnter()
    check(findEntry(env.GameTooltip.lines, function(v) return v == "Kobold Vermin slain: 1/10" end))
    state.objectives[7][1].text = "Kobold Vermin slain: 4/10"
    Wow.fire("QUEST_LOG_UPDATE"); Wow.flushTimers()
    check(findEntry(env.GameTooltip.lines, function(v) return v == "Kobold Vermin slain: 4/10" end), "live count")
    -- Blank objective text falls back to quest title instead of an empty line.
    state.objectives[7][1].text = ""
    local sites = addon.Quests:ObjectiveSites(1429)
    equal(sites[1].detail, nil, "blank objective text ignored")
    -- Neutral faction retains faction-tagged objective sites.
    state.faction = "Neutral"
    check(#addon.Quests:ObjectiveSites(1429) > 0, "neutral faction keeps objective sites")
end)

test("continent pins show dungeon levels, keys request uncached data, and reset confirms in chat", function()
    local addon, env, state = load({mapID=1415})
    env.Enum.UIMapType = {World=0, Continent=1}
    env.C_Map.GetMapInfo = function(id)
        if id == 1415 then return {mapType=1, name="Eastern Kingdoms"} end
        return {mapType=3, parentMapID=id == 1436 and 1415 or 0, name="Westfall"}
    end
    env.C_Map.GetMapRectOnMap = function() return .1, .5, .2, .6 end
    env.WorldMapFrame:Show()
    local _, door = locate(env, function(e) return e.source.id == "deadmines" end)
    check(door.subtitle:find("Westfall", 1, true) and door.subtitle:find("Levels", 1, true), "continent level range")
    addon.DungeonMap:Open(dungeonNamed(addon, "blackrock-depths"))
    addon.DungeonMap.frame.dropdown:OpenMenu():Find("Dungeon keys")
    check(state.requested and state.requested[11000], "uncached dungeon keys requested")
    -- GET_ITEM_INFO_RECEIVED also updates an open boss loot menu. The menu lists only drops
    -- this character can use, so pick one of those that is not cached yet.
    local usable, boss, itemID = addon.LootFilter(), nil, nil
    for _, candidate in ipairs(addon.DungeonMap.dungeon.bosses) do
        for _, id in ipairs(candidate.loot) do
            if not boss and usable(id) and not state.cached[id] then boss, itemID = candidate, id end
        end
    end
    check(boss, "a boss with an uncached drop this character can use")
    addon.UI:Boss(addon.DungeonMap.frame, boss)
    state.cached[itemID] = true
    Wow.fire("GET_ITEM_INFO_RECEIVED", itemID, true)
    Wow.flushTimers()
    equal(state.menuProxy.refreshes, 1, "fallback item event refreshes loot menu")
    slash(env, "reset")
    check(state.messages[#state.messages]:find("reset", 1, true), "reset confirmation")
end)

test("observed trainer visits preserve prior requirements and resolve profession ranks by name", function()
    local addon, env, state = load({npcGUID="Creature-0-1-1-1-5499-000A",
        professionIndices={1}, professionSkills={171}, professionRanks={[171]=15},
        services={{name="Custom Elixir", cost=200, level=12, skill="Alchemy", need=30}}})
    Wow.fire("TRAINER_SHOW")
    -- Subsequent visit reports the service without level/skill metadata (e.g. already learned or partial info).
    state.services = {{name="Custom Elixir", cost=200}}
    Wow.fire("TRAINER_UPDATE")
    local lesson = findEntry(addon.Trainers:Lessons(5499), function(l) return l.name == "Custom Elixir" end)
    equal(lesson.level, 12, "level preserved across trainer visits")
    equal(lesson.skillID, 171, "profession skillID resolved from name")
    equal(lesson.requirement, 30, "skill requirement preserved")
    state.level = 60
    local group, status = addon.Trainers:LessonState(lesson)
    equal(group, "later", "observed-only recipe gated by profession rank")
    equal(status, "Alchemy 15 / 30")
    -- Safe nil/non-number item helpers and negative quality-color cache.
    equal(addon.ItemName(nil), "Item ")
    equal(addon.ItemLink(nil), nil)
    equal(addon.ItemQualityColor(nil), nil)
    local colorCalls = 0
    env.C_Item.GetItemQualityByID = function() return 99 end
    env.C_Item.GetItemQualityColor = function() colorCalls = colorCalls + 1; return nil end
    equal(addon.ItemQualityColor(5191), nil)
    equal(addon.ItemQualityColor(5191), nil)
    equal(colorCalls, 1, "missing quality color cached negatively")
end)


test("/aeternum opens the map through ShowUIPanel's secure path", function()
    local _, env = load()
    slash(env, "")
    check(env.WorldMapFrame:IsShown(), "map open")
    equal(table.concat(Wow.addonMapWrites(), ", "), "", "no Blizzard map state written")
end)

test("a location waiting for its zone is dropped when the map closes", function()
    local addon, env = load()
    env.WorldMapFrame:Show()
    addon.DungeonMap:Open(dungeonNamed(addon, "uldaman"))
    addon.DungeonMap.frame.dropdown:OpenMenu():Find("Entrances").children[2]:Find("Show on zone map"):Click()
    check(addon.UI.waitingLocation, "waiting for Badlands")
    env.WorldMapFrame:Hide()
    check(not addon.UI.waitingLocation, "dropped with the map")
    env.WorldMapFrame:Show()
    env.GameTooltip:Hide()
    env.WorldMapFrame:SetMapID(1418)
    check(not env.GameTooltip.shown, "nothing pops up on a later visit")
end)

test("skill-ups refresh once after a short delay and keep unchanged pins in place", function()
    local _, env = load({mapID=1453, class="MAGE"})
    local map = env.WorldMapFrame
    map:Show()
    local acquired, acquire = 0, map.AcquirePin
    map.AcquirePin = function(...) acquired = acquired + 1 return acquire(...) end
    for _ = 1, 3 do Wow.fire("SKILL_LINES_CHANGED") end
    equal(acquired, 0, "pins redrawn before the delay")
    Wow.flushTimers()
    equal(acquired, 0, "pins redrawn although no location changed")
end)

test("a focused location keeps its tooltip shut when the map redraws", function()
    local addon, env, state = load({mapID=1436})
    env.WorldMapFrame:Show()
    local entry = locate(env, function(e) return e.title == "The Deadmines" end).entry
    addon.UI:ShowLocation(entry)
    check(env.GameTooltip.shown, "focus shows the tooltip once")
    env.GameTooltip:Hide()
    state.viewWidth = .25
    env.WorldMapFrame.providers[1]:OnCanvasScaleChanged()
    Wow.flushTimers()
    check(not env.GameTooltip.shown, "redraw reopened the tooltip")
    check(env.WorldMapFrame:GetMapID() == 1436 and not env.WorldMapFrame.panX, "map left where it was")
end)

test("dungeon level ranges take the character's difficulty colour", function()
    for _, case in ipairs({{12, "ff1a1a"}, {20, "ffd100"}, {40, "808080"}}) do
        local _, env = load({mapID=1436, level=case[1]})
        env.WorldMapFrame:Show()
        locate(env, function(e) return e.title == "The Deadmines" end):OnMouseEnter()
        check(findEntry(env.GameTooltip.lines, function(line)
            return line == "Moonbrook entrance approach · |cff" .. case[2] .. "Levels 17–26|r"
        end), "level " .. case[1] .. " colours the range " .. case[2])
    end
end)

test("/aeternum dungeons lists every dungeon by level and opens the chosen floors", function()
    local addon, env, state = load({level=20})
    slash(env, "dungeons")
    check(env.WorldMapFrame:IsShown(), "map open")
    local menu = state.menu
    equal(menu.children[1].label, "Dungeons by level")
    equal(#menu.children - 1, #addon.Data.dungeons, "every dungeon and wing")
    local last = 0
    for _, entry in ipairs(addon.DungeonsByLevel()) do
        check(entry.source.levelMin >= last, "ordered by level")
        last = entry.source.levelMin
    end
    equal(menu.children[2].label:match("^(.-)  "), addon.DungeonsByLevel()[1].title, "lowest range first")
    local row = findEntry(menu.children, function(r) return r.label:find("^The Deadmines  ") end)
    equal(row.label, "The Deadmines  |cffffd10017–26|r")
    row.tooltip(env.GameTooltip)
    check(findEntry(env.GameTooltip.lines, function(line) return line == "5 players · 9 bosses" end),
        "group size and bosses")
    row:Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.dungeon.id, "deadmines", "floor view opened")
end)

test("the map's tracking menu offers the dungeon list", function()
    local addon, env = load({level=30})
    env.WorldMapFrame:Show()
    local index = Wow.trackingMenu():Find("Dungeons by level")
    equal(#index.children, #addon.Data.dungeons)
    index.children[1]:Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.dungeon, addon.DungeonsByLevel()[1].source, "lowest dungeon's floors")
end)

test("the addon compartment entry opens the dungeon list through the secure map path", function()
    local _, env, state = load()
    local named = 0
    for line in io.lines(ADDON .. ".toc") do
        local field, value = line:match("^## (AddonCompartmentFunc%w*): (%S+)")
        if field then
            equal(type(env[value]), "function", field .. " names a function the addon defines")
            named = named + 1
        end
    end
    equal(named, 3, "click, enter and leave handlers")
    env.Aeternum_OnAddonCompartmentEnter(ADDON, env.UIParent)
    equal(env.GameTooltip.lines[1], "Aeternum")
    env.Aeternum_OnAddonCompartmentLeave(ADDON, env.UIParent)
    check(not env.GameTooltip.shown, "tooltip hidden on leave")
    state.inCombat = true
    env.Aeternum_OnAddonCompartmentClick(ADDON, "LeftButton")
    check(not env.WorldMapFrame:IsShown(), "no map in combat")
    equal(state.messages[#state.messages], "Open the map after combat.")
    state.inCombat = false
    env.Aeternum_OnAddonCompartmentClick(ADDON, "LeftButton")
    check(env.WorldMapFrame:IsShown(), "map open")
    equal(state.menu.children[1].label, "Dungeons by level")
end)

test("item tooltips name the bosses that drop the item, from verified sources only", function()
    local addon, env = load()
    local tip = env.GameTooltip
    tip:SetItemByID(5191)
    equal(tip.lines[2], "|cffffd100Drops from|r Edwin VanCleef · The Deadmines", "Cruel Barb")
    local unverified, shared
    for _, dungeon in ipairs(addon.Data.dungeons) do
        for _, boss in ipairs(dungeon.bosses) do
            local start = boss.lootSections and boss.lootSections.guide
            if start and not unverified and not addon.ItemSources(boss.loot[start]) then
                unverified = boss.loot[start]
            end
            for _, id in ipairs(boss.loot) do
                local list = addon.ItemSources(id)
                if not shared and list and #list > 1 then shared = id end
            end
        end
    end
    check(unverified, "a guide-only item exists")
    tip:SetItemByID(unverified)
    equal(#tip.lines, 1, "no drop line for an item only a guide lists")
    if shared then
        tip:SetItemByID(shared)
        check(tip.lines[3]:find("^|cffffd100      or|r "), "further bosses listed")
    end
    env.ItemRefTooltip:SetItemByID(5191)
    equal(env.ItemRefTooltip.lines[2], "|cffffd100Drops from|r Edwin VanCleef · The Deadmines", "chat links")
    env.ShoppingTooltip1:SetItemByID(5191)
    equal(#env.ShoppingTooltip1.lines, 1, "comparison tooltips unchanged")
end)

test("a boss fight shows the player's floor when rooms and positions are unknown", function()
    local addon, env = load({inInstance=true, instanceID=36})
    local floors = addon.DungeonMap
    env.WorldMapFrame:Show()
    equal(floors.dungeon.id, "deadmines")
    equal(floors.index, 1, "no room name or position: first floor")
    Wow.fire("ENCOUNTER_START", 2747, "Edwin VanCleef", 1, 5)
    equal(floors.index, 2, "the floor view follows VanCleef's fight to Ironclad Cove")
    equal(floors.playerFloor, 2)
    env.WorldMapFrame:Hide()
    env.WorldMapFrame:Show()
    equal(floors.index, 2, "reopening the map without a room name keeps the fight's floor")
    floors.frame.dropdown:OpenMenu():Find("Deadmines"):Click()
    Wow.fire("ENCOUNTER_START", 2747, "Edwin VanCleef", 1, 5)
    equal(floors.index, 1, "a floor chosen by hand stays put")
end)

test("grouped trainer and quest pins list stacked entries and surface ready turn-ins", function()
    local _, env, state = load({mapID=1455, class="SHAMAN", raceID=3, level=10})
    env.WorldMapFrame:Show()
    local pin = locate(env, function(e) return e.source and e.source.id == 258098 end)
    check(pin and #pin.entries >= 2, "Eldrun Stormbreaker shares a pin with available Shaman quests")
    equal(pin.entry.source.id, 258098, "trainer wins over an available quest start")
    pin:OnMouseEnter()
    check(findEntry(env.GameTooltip.lines, function(line) return line:find("Call of Fire", 1, true) end),
        "stacked quest is named on hover")
    check(findEntry(env.GameTooltip.lines, function(line) return line:find("Click to choose", 1, true) end),
        "chooser prompt shown")
    check(not findEntry(env.GameTooltip.lines, function(line) return line == "Click for lessons and prices" end),
        "single-entry trainer prompt omitted when clicking opens a chooser")
    state.log[97168], state.complete[97168] = 1, true
    Wow.fire("QUEST_LOG_UPDATE")
    Wow.flushTimers()
    pin = locate(env, function(e) return e.questID == 97168 and e.role == "turnin" end)
    check(pin, "ready turn-in pin at trainer")
    equal(pin.entry.questID, 97168, "ready turn-in icon surfaces above the trainer")
    equal(pin.icon.texture, 132048, "Blizzard turn-in question mark")
    check(not pin.icon.desaturated, "ready turn-in is gold")
end)

test("weapon master relevance checks Forever training records as well as Classic references", function()
    local addon = load({class="PALADIN"})
    addon.foreverTraining.offers[999999] = "201::::1000:5:1"
    check(addon.Trainers:Relevant({id=999999, kind="weapon"}), "Forever-only compatible weapon master shown")
    addon.foreverTraining.offers[999998] = "266::::1000:5:1"
    check(not addon.Trainers:Relevant({id=999998, kind="weapon"}), "Forever-only incompatible weapon master hidden")
end)

test("shared encounters and live rare drops appear while generic green world drops stay withheld", function()
    local addon, env, state = load({class="WARRIOR", level=60, skillRanks={[55]=300, [413]=300, [414]=300, [293]=300},
        professionIndices={1}, professionSkills={171}, professionRanks={[171]=300}})
    env.WorldMapFrame:Show()

    -- Stratholme: Balnazzar (10813) carries his full encounter drop table.
    local strat = dungeonNamed(addon, "stratholme")
    local balnazzar = assert(findEntry(strat.bosses, function(b) return b.id == 10813 end))
    addon.UI:Boss(env.WorldMapFrame, balnazzar)
    local guide = state.menu:Find("Guide-listed drops")
    check(menuRow(guide, "Demonshear"), "Balnazzar 2H sword")
    check(menuRow(guide, "Star of Mystaria"), "Balnazzar neck")
    check(menuRow(guide, "Recipe: Flask of Distilled Wisdom"), "Balnazzar alchemy recipe")

    -- Sunken Temple: shared drakes (5719-5722) and Atal'ai minibosses (5712-5717).
    local st = dungeonNamed(addon, "sunken-temple")
    local morphaz = assert(findEntry(st.bosses, function(b) return b.id == 5719 end))
    addon.UI:Boss(env.WorldMapFrame, morphaz)
    check(menuRow(state.menu:Find("Encounter rolls"), "Drakestone"), "Morphaz live encounter roll")
    check(menuRow(state.menu:Find("Guide-listed drops"), "Drakeclaw Band"), "Morphaz drake ring")
    for _, npc in ipairs({5720, 5721, 5722}) do
        local drake = assert(findEntry(st.bosses, function(b) return b.id == npc end))
        check(findEntry(drake.loot, function(id) return id == 12463 end), "drake shared drop " .. npc)
    end
    local zolo = assert(findEntry(st.bosses, function(b) return b.id == 5712 end))
    addon.UI:Boss(env.WorldMapFrame, zolo)
    check(menuRow(state.menu, "Atal'ai Breastplate"), "Zolo live verified drop featured")

    -- Live repeated rare drops on Ruuzlu (7797) and Min'loth (260243).
    local zf = dungeonNamed(addon, "zulfarrak")
    local ruuzlu = assert(findEntry(zf.bosses, function(b) return b.id == 7797 end))
    addon.UI:Boss(env.WorldMapFrame, ruuzlu)
    check(menuRow(state.menu:Find("Other recorded drops"), "Embrace of the Lycan"), "Ruuzlu live rare drop")
    local drowned = dungeonNamed(addon, "drowned-city")
    local minloth = assert(findEntry(drowned.bosses, function(b) return b.id == 260243 end))
    addon.UI:Boss(env.WorldMapFrame, minloth)
    check(menuRow(state.menu:Find("Other recorded drops"), "Linken's Boots of Iron"), "Min'loth live rare drop")

    -- Random green BoE world drops remain withheld.
    local wc = dungeonNamed(addon, "wailing-caverns")
    local mutanus = assert(findEntry(wc.bosses, function(b) return b.id == 3654 end))
    check(not findEntry(mutanus.loot, function(id) return id == 6576 or id == 6581 end), "Mutanus world-drop greens")
    local pythas = assert(findEntry(wc.bosses, function(b) return b.id == 3670 end))
    check(not findEntry(pythas.loot, function(id) return id == 15506 end), "Pythas world-drop green")
    local gnome = dungeonNamed(addon, "gnomeregan")
    local thermaplugg = assert(findEntry(gnome.bosses, function(b) return b.id == 7800 end))
    check(not findEntry(thermaplugg.loot, function(id) return id == 9855 end), "Thermaplugg world-drop green")
end)

local function hoverClient()
    local addon, env, state = load({mapID=1415, level=18})
    local map = env.WorldMapFrame
    local label = env.CreateFrame("Frame", nil, map)
    label.Name, label.Description = label:CreateFontString(), label:CreateFontString()
    local area = {}
    label.labelInfoByType = {[3]=area}
    label.GetHighestPriorityLabelInfo = function() return state.priority or (area.name and area) end
    label:SetScript("OnUpdate", function(self) self.Name:SetText(area.name or "") end)
    env.MAP_AREA_LABEL_TYPE, env.LEVEL = {AREA_NAME=3}, "Level"
    env.QuestDifficultyColors = {difficult={r=1,g=.82,b=0}}
    env.GetQuestDifficultyColor = function(level)
        state.difficultyFor = level
        return {r=.5,g=.5,b=.5}
    end
    env.InputUtil = {IsGamepadUIEnabled=function() return state.gamepad end}
    map.IsCanvasMouseFocus = function() return not state.outside end
    map.HasGamepadCursorInput = function() return state.gamepad end
    map.IsCanvasMouseFocusOrPinFocus = map.IsCanvasMouseFocus
    map.GetNormalizedCursorPosition = function() return state.x or .5, state.y or .5 end
    map.GetNormalizedGamepadCursorPosition = function() return .3, .7 end
    env.C_Map.GetMapInfoAtPosition = function() return state.hover end
    env.C_Map.GetMapLevels = function() return state.low, state.high end
    env.C_Map.GetMapRectOnMap = function() return 0,0,0,0 end
    local provider = env.CreateFromMixins(env.MapCanvasDataProviderMixin)
    provider.Label = label
    map:AddDataProvider(provider)
    local text = label.children[3]
    local function hover(mapID, zoneID, zoneName, title)
        map.mapID = mapID
        state.hover = zoneID and {mapID=zoneID, name=zoneName} or nil
        area.name = title
        label:Fire("OnUpdate")
        return text:IsShown() and text:GetText()
    end
    return hover, state, env, addon, label
end

test("zone hover uses the map's localized name, zone recommendations and character difficulty", function()
    local hover, state, env, _, label = hoverClient()
    env.LEVEL = "Stufe"
    equal(hover(1415, 1436, "Westfall", "Westfall"), "Stufe 9–18")
    equal(label.Name:GetText(), "Westfall")
    equal(hover(1415, 1433, "Rotkammgebirge", "Rotkammgebirge"), "Stufe 15–25")
    state.level = 10
    equal(hover(1433, 1433, "Rotkammgebirge", "Seenhain"), "Rotkammgebirge (15–25)")
    equal(state.difficultyFor, 15)
    state.level = 60
    equal(hover(1433, 1433, "Rotkammgebirge", "Seenhain"), "Rotkammgebirge (15–25)")
    equal(state.difficultyFor, 23)
    state.low, state.high = 60, 60
    equal(hover(1414, 2482, "Hyjal", "Hyjal"), "Stufe 60")
    check(not hover(1414, 2482, "Hyjal", "Hyjal|cffffffff (60)|r"), "respects a native range")
end)

test("Azeroth resolves the zone from the continent terrain and respects map edges", function()
    local hover, state, env, addon = hoverClient()
    for _, sample in ipairs({{1415, 1436, "Westfall", "9–18"}, {1414, 1413, "The Barrens", "10–25"}}) do
        local continent, zone, name, levels = unpack(sample)
        local l,r,t,b = unpack(addon.overviewBounds[947][continent])
        state.x, state.y = l + .4*(r-l), t + .6*(b-t)
        env.C_Map.GetMapInfoAtPosition = function(id, x, y)
            if id == 947 then return {mapID=continent, name="Continent"} end
            equal(id, continent)
            check(math.abs(x-.4) < .00001 and math.abs(y-.6) < .00001, "cursor is in continent coordinates")
            return {mapID=zone, name=name}
        end
        equal(hover(947, nil, nil, "Continent"), name .. " (" .. levels .. ")")
    end
    state.x, state.y = .99, .99
    check(not hover(947, nil, nil, "Continent"), "outside continent bounds")
    env.C_Map.GetMapInfoAtPosition = function(id)
        if id == 947 then return {mapID=1415, name="Eastern Kingdoms"} end
        return {mapID=1415, name="Eastern Kingdoms"}
    end
    state.x, state.y = .69,.5
    check(not hover(947, nil, nil, "Eastern Kingdoms"), "no zone over ocean")
    state.x = .7
    env.C_Map.GetMapRectOnMap = function() return .4,.8,.3,.7 end
    env.C_Map.GetMapInfoAtPosition = function(id, x, y)
        if id == 947 then return {mapID=1415, name="Eastern Kingdoms"} end
        check(math.abs(x-.75) < .00001 and math.abs(y-.5) < .00001, "prefer live rectangle")
        return {mapID=2548, name="Riverglades"}
    end
    equal(hover(947, nil, nil, "Eastern Kingdoms"), "Riverglades (36–44)")
end)

test("unexplored zone maps use the continent terrain under the cursor", function()
    local hover, state, env, addon = hoverClient()
    local zone = {mapID=1428, parentMapID=1415, name="Burning Steppes"}
    local land = zone
    local left,right,top,bottom = unpack(addon.overviewBounds[1415][zone.mapID])
    env.C_Map.GetMapInfo = function(id)
        if id == zone.mapID then return zone end
        if id == 2521 then return {mapID=2521, name="Zephras Isle"} end
    end
    env.C_Map.GetMapInfoAtPosition = function(id, x, y)
        if id == zone.mapID or id == 2521 then return nil end
        equal(id, 1415)
        check(math.abs(x - (left + state.x*(right-left))) < .00001, "project longitude to the continent")
        check(math.abs(y - (top + state.y*(bottom-top))) < .00001, "project latitude to the continent")
        return land
    end
    state.x, state.y = .5, .6
    equal(hover(1428, nil, nil, nil), "Burning Steppes (50–59)")
    state.x, land = .6, {mapID=1427, name="Searing Gorge"}
    equal(hover(1428, nil, nil, nil), "Searing Gorge (43–48)")
    state.x, land = .7, {mapID=1453, name="Stormwind City"}
    check(not hover(1428, nil, nil, nil), "city has no questing range")
    state.x, land = .8, nil
    check(not hover(1428, nil, nil, nil), "no zone over open water")
    equal(hover(2521, nil, nil, nil), "Zephras Isle (1–12)")
end)

test("zone hover clears on pins, city maps, water, and dungeon floors without stealing the map label", function()
    local hover, state, _, addon, label = hoverClient()
    equal(hover(1414, 2652, "Shen'dralas", "Shen'dralas"), "Level 38–45")
    state.priority = {name="Dungeon"}
    check(not hover(1414, 2652, "Shen'dralas", "Shen'dralas"))
    state.priority = nil
    state.outside = true
    check(not hover(1414, 2652, "Shen'dralas", "Shen'dralas"))
    state.outside = nil
    equal(hover(1414, 2652, "Shen'dralas", "Shen'dralas"), "Level 38–45")
    label.labelInfoByType[3].description = "Native detail"
    check(not hover(1414, 2652, "Shen'dralas", "Shen'dralas"))
    label.labelInfoByType[3].description = nil
    addon.DungeonMap.dungeon = {}
    check(not hover(1414, 2652, "Shen'dralas", "Shen'dralas"))
    addon.DungeonMap.dungeon = nil
    check(not hover(1415, 1453, "Stormwind City", "Stormwind City"))
    check(not hover(1453, 1453, "Stormwind City", "Trade District"))
    check(not hover(1436, 1436, "Westfall", nil), "unidentified terrain")
    equal(hover(947, 2521, "Zephras Isle", "Zephras Isle"), "Level 1–12")
    state.gamepad = true
    equal(hover(1414, 2482, "Mount Hyjal", "Mount Hyjal"), "Level 55–60")
end)

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
