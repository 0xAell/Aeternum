-- Headless tests: luajit tests/run.lua (from the repository root).
package.path = "tests/?.lua;" .. package.path
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

local function openDeadmines()
    local addon, env, state = load({mapID=1436})
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

test("shared entrances retain the chosen wing for both buttons", function()
    local addon, env, state = load({mapID=1420, playerMap=1420, playerX=.2, playerY=.2})
    env.WorldMapFrame:Show()
    local pin = locate(env, function(entry) return entry.source.id == "sm-armory" end)
    equal(#pin.entries, 4, "one pin")
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    state.menu:Find("Show path to Scarlet Monastery - Library"):Click()
    equal(addon.Navigation:GetTarget(), "Scarlet Monastery - Library entrance", "wing route")
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    state.menu:Find("Scarlet Monastery - Cathedral"):Click()
    Wow.flushTimers()
    equal(addon.DungeonMap.dungeon.id, "sm-cathedral", "chosen wing opens on the map")
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
    check(stops >= 210 and sketches == 1, "recorded boss stops and one fallback sketch")
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
    local menu = frame.dropdown:OpenMenu()
    menu:Find("Boss loot"):Find("Miner Johnson"):Click()
    Wow.flushTimers()
    equal(state.menu.children[1].label, "Miner Johnson", "encounter list opens loot")
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
    local addon, env, state = load({mapID=1453, professionIndices={1}, professionSkills={171}})
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
    env.WorldMapFrame:ClickPin(pin, "RightButton")
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
    addon.FocusLocation(first.entries[#first.entries])
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

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
