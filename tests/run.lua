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
    for pin in env.WorldMapFrame:EnumeratePinsByTemplate("AeternumMapPinTemplate") do
        result[#result + 1] = pin
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

-- Data ------------------------------------------------------------------------

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

-- Loading and the panel -------------------------------------------------------

test("loads, attaches to the world map, and opens with the slash command", function()
    local addon, env = load()
    check(addon.settings, "settings loaded")
    check(addon.UI.sidebar, "sidebar attached")
    check(not addon.UI:IsOpen(), "panel starts closed")
    equal(#pins(env), 0, "no pins while closed")
    slash(env)
    check(env.WorldMapFrame:IsShown(), "map shown")
    check(addon.UI:IsOpen(), "panel open")
    check(env.AeternumDB.panelOpen, "open state saved")
    local count = #pins(env)
    check(count > 0 and count <= 150, "pins drawn on Elwynn Forest: " .. count)
    equal(addon.UI.sidebar.heading:GetText(), "Elwynn Forest", "heading")
end)

test("unknown slash commands print help", function()
    local _, env, state = load()
    slash(env, "nonsense")
    check(#state.messages >= 4, "help printed")
end)

test("the panel reopens with the map when it was left open", function()
    local addon, env = load({ savedVariables = { panelOpen = true, filters = { quest = false } } })
    check(not addon.UI:IsOpen(), "hidden while the map is closed")
    env.WorldMapFrame:Show()
    check(addon.UI:IsOpen(), "panel restored with the map")
    env.WorldMapFrame:Hide()
    check(not addon.UI:IsOpen(), "hidden with the map")
    check(env.AeternumDB.panelOpen, "still remembered as open")
    check(not addon.UI.sidebar.checks[4]:GetChecked(), "quest filter restored")
end)

test("category filters and search narrow the list", function()
    local addon, env = load()
    slash(env)
    local list = addon.UI.sidebar.list
    local all = #list:GetEntries()
    addon.UI.sidebar.checks[4]:Click()
    equal(env.AeternumDB.filters.quest, false, "quest filter saved")
    local withoutQuests = #list:GetEntries()
    check(withoutQuests < all, "quests removed")
    check(not findEntry(list:GetEntries(), function(entry) return entry.category == "quest" end), "no quests")
    addon.UI.sidebar.search:SetText("mage")
    for _, entry in ipairs(list:GetEntries()) do
        check(entry.search:find("mage", 1, true), "search match")
    end
end)

test("the dungeon atlas lists every dungeon and filters by search", function()
    local addon, env = load()
    slash(env)
    addon.UI.sidebar.mode:Click()
    check(addon.UI:IsAtlas(), "atlas mode")
    equal(#addon.UI.sidebar.list:GetEntries(), 34, "dungeons")
    addon.UI.sidebar.search:SetText("dead")
    local entries = addon.UI.sidebar.list:GetEntries()
    equal(#entries, 1, "search")
    equal(entries[1].title, "The Deadmines", "match")
end)

test("reset restores defaults", function()
    local addon, env = load({ savedVariables = { questMode = "all", filters = { dungeon = false } } })
    slash(env, "reset")
    equal(addon.settings.questMode, "available", "quest mode")
    check(addon.CategoryEnabled("dungeon"), "filters")
    check(addon.UI.sidebar.checks[1]:GetChecked(), "checkbox synced")
end)

test("pins can stay on the map with the panel closed", function()
    local addon, env = load()
    env.WorldMapFrame:Show()
    equal(#pins(env), 0, "hidden by default")
    slash(env, "pins")
    check(addon.settings.pinsWithPanelClosed, "setting saved")
    check(#pins(env) > 0, "pins shown")
end)

-- Quests ----------------------------------------------------------------------

-- Northshire: A Threat Within (783) leads to Kobold Camp Cleanup (7).
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

test("quest log events refresh the map after a short delay", function()
    local addon, env, state = load({ level = 1 })
    slash(env)
    state.completed[783] = true
    Wow.fire("QUEST_TURNED_IN", 783)
    check(findEntry(addon.UI.sidebar.list:GetEntries(), function(entry) return entry.questID == 783 end),
        "unchanged until the refresh runs")
    Wow.flushTimers()
    check(not findEntry(addon.UI.sidebar.list:GetEntries(), function(entry)
        return entry.questID == 783 and entry.role == "start"
    end), "refreshed")
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

test("low-level quests can be hidden and all quests shown", function()
    local addon, env = load({ level = 20 })
    slash(env)
    check(questPin(addon, 1429, 783, "start"), "trivial shown by default")
    equal(addon.Quests:State(783), "trivial", "trivial")
    addon.UI.sidebar.lowLevel:Click()
    check(not questPin(addon, 1429, 783, "start"), "trivial hidden")
    addon.UI.sidebar.allQuests:Click()
    equal(addon.settings.questMode, "all", "all quests")
    check(not addon.UI.sidebar.lowLevel:IsEnabled(), "low-level option disabled in all mode")
    check(questPin(addon, 1429, 783, "start"), "all mode shows it")
    check(questPin(addon, 1429, 783, "turnin"), "all mode shows turn-ins")
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
    equal(found.letter:GetText(), "!", "start mark")
    found:OnMouseEnter()
    check(env.GameTooltip:IsOwned(found), "tooltip")
    check(env.GameTooltip.lines[2]:find("Available", 1, true), "state in tooltip")
end)

-- Guidance --------------------------------------------------------------------

test("the arrow points at the target on a fixed minimap", function()
    local addon, _, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .5, .5
    check(addon.Navigation:Start("North point", { mapID = 1429, x = .5, y = .45 }), "started")
    local overlay = addon.Navigation.overlay
    check(overlay and overlay:IsShown(), "arrow shown")
    local tip = overlay.arrow[1].endPoint
    check(math.abs(tip[3]) < .01 and tip[4] > 0, "north is up")
    check(addon.Navigation:GetStatus():find("North point", 1, true), "status names target")
end)

test("the arrow turns with a rotating minimap", function()
    local addon, _, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .5, .5
    state.rotate, state.facing = true, -math.pi / 2 -- facing east
    addon.Navigation:Start("North point", { mapID = 1429, x = .5, y = .45 })
    local tip = addon.Navigation.overlay.arrow[1].endPoint
    check(tip[3] < 0 and math.abs(tip[4]) < .01, "north is to the left when facing east")
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

test("any pin can be guided to from the sidebar and stopped", function()
    local addon, env, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .1, .1
    slash(env)
    local panel = addon.UI.sidebar
    check(not panel.guide:IsEnabled(), "guide disabled without a selection")
    local trainer = findEntry(panel.list:GetEntries(), function(entry) return entry.category == "class" end)
    addon.UI:Select(trainer)
    check(panel.selection:GetText():find(trainer.title, 1, true), "selection shown")
    panel.guide:Click()
    check(addon.Navigation:IsActive(), "guiding")
    check(panel.status:GetText():find(trainer.title, 1, true), "sidebar status")
    check(panel.stop:IsEnabled(), "stop enabled")
    panel.stop:Click()
    check(not addon.Navigation:IsActive(), "stopped")
    check(not panel.stop:IsEnabled(), "stop disabled")
end)

test("right-clicking a map pin starts guidance", function()
    local addon, env, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .1, .1
    slash(env)
    local pin = pins(env)[1]
    pin:OnMouseClickAction("RightButton")
    check(addon.Navigation:IsActive(), "guiding")
    slash(env, "stop")
    check(not addon.Navigation:IsActive(), "stopped by command")
end)

-- Dungeon panel ---------------------------------------------------------------

local function openDeadmines(addon, env)
    slash(env)
    env.WorldMapFrame:SetMapID(1436)
    local entry = findEntry(addon.UI.sidebar.list:GetEntries(), function(candidate)
        return candidate.title == "The Deadmines"
    end)
    check(entry, "Deadmines entrance on Westfall")
    addon.UI:Select(entry)
    return addon.UI.detail, entry
end

test("a dungeon opens with floors, bosses, loot, and its entrance", function()
    local addon, env, state = load()
    local detail, entry = openDeadmines(addon, env)
    check(detail:IsShown(), "detail shown")
    equal(detail.title:GetText(), "The Deadmines", "title")
    check(detail.facts:GetText():find("5 players", 1, true), "group size")
    local bosses = entry.source.bosses
    equal(detail.bossTitle:GetText(), ("%s (1/%d)"):format(bosses[1].name, #bosses), "first boss")
    detail.bossBack:Click()
    equal(detail.bossTitle:GetText(), ("%s (%d/%d)"):format(bosses[#bosses].name, #bosses, #bosses), "wraps")
    local loot = detail.loot:GetEntries()
    equal(loot, bosses[#bosses].loot, "loot keeps the source order")
    check(state.requested[loot[1]], "item data requested")
    check(detail.entranceText:GetText():find("Moonbrook", 1, true), "authored approach label")
    check(addon.UI.selected == entry, "entrance selected")
    detail.route:Click()
    check(addon.Navigation:GetTarget() == "The Deadmines entrance", "guiding to the entrance")
    check(detail.routeStatus:GetText() == addon.Navigation:GetStatus(), "detail status")
end)

test("loot rows show item details and support modified clicks", function()
    local addon, env, state = load()
    local detail = openDeadmines(addon, env)
    local itemID = detail.loot:GetEntries()[1]
    state.cached[itemID] = true
    addon.UI:OnItemInfo(itemID)
    local row
    for _, frame in ipairs(state.frames) do
        if frame.entry == itemID and frame.title then
            row = frame
        end
    end
    check(row, "loot row")
    equal(row.title:GetText(), "Cached " .. itemID, "client name")
    equal(row.title.textColor[1], .64, "quality colour")
    equal(row.icon.texture, 1000000 + itemID, "icon")
    row:Fire("OnEnter")
    equal(env.GameTooltip.lines[1], "item:" .. itemID, "item tooltip")
    row:Click()
    check(state.itemRef and state.itemRef[1] == "item:" .. itemID, "item opened")
    state.modified = true
    row:Click()
    check(state.modifiedClick and state.modifiedClick:find("Hitem:" .. itemID, 1, true), "linked")
end)

test("the quests tab lists dungeon quests and shows where they start", function()
    local addon, env = load({ level = 18 })
    local detail = openDeadmines(addon, env)
    detail.questTab:Click()
    check(detail.quests:IsShown() and not detail.loot:IsShown(), "quests tab")
    local quests = detail.quests:GetEntries()
    check(#quests > 0, "dungeon quests")
    local target
    for _, questID in ipairs(quests) do
        local start = addon.QuestStart(questID)
        if start and start.mapID ~= 1436 then
            target = questID
            break
        end
    end
    check(target, "a quest that starts on another map")
    addon.UI:ShowQuestStart(target)
    check(not detail:IsShown(), "detail closed")
    equal(env.WorldMapFrame:GetMapID(), addon.QuestStart(target).mapID, "map moved")
    equal(addon.UI.selected, addon.QuestStart(target), "start selected")
end)

test("dungeons without floor art or entrances still open", function()
    local addon, env = load()
    slash(env)
    addon.UI.sidebar.mode:Click()
    addon.UI.sidebar.search:SetText("Alcaz")
    local entry = addon.UI.sidebar.list:GetEntries()[1]
    addon.UI:Select(entry)
    local detail = addon.UI.detail
    check(detail:IsShown(), "shown")
    check(not detail.route:IsEnabled(), "no guidance without an entrance")
    equal(detail.entranceText:GetText(), "Entrance location not recorded", "explained")
end)

test("the busiest map draws every location in reference mode", function()
    local addon, env = load({ mapID = 1453 })
    addon.settings.questMode = "all"
    slash(env)
    local locations = {}
    for _, entry in ipairs(addon.Entries(1453, false, "")) do
        locations[("%0.3f:%0.3f"):format(entry.x, entry.y)] = true
    end
    local count = 0
    for _ in pairs(locations) do count = count + 1 end
    equal(#pins(env), count, "one pin per location")
    check(not addon.UI.sidebar.summary:find("not drawn", 1, true), "nothing left off")
end)

-- Regressions ---------------------------------------------------------------

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

test("quest events restyle in place without moving the list or dropping tooltips", function()
    local addon, env = load({ level = 1 })
    slash(env)
    local list = addon.UI.sidebar.list
    list:SetOffset(5)
    local before = pins(env)
    before[1]:OnMouseEnter()
    Wow.fire("QUEST_LOG_UPDATE")
    Wow.flushTimers()
    local after = pins(env)
    equal(after[1], before[1], "same pin objects")
    check(env.GameTooltip:IsOwned(before[1]), "tooltip kept")
    equal(list:GetOffset(), 5, "scroll kept")
end)

test("a quest event that changes the visible quests redraws but keeps the scroll", function()
    local addon, env, state = load({ level = 1 })
    slash(env)
    local list = addon.UI.sidebar.list
    list:SetOffset(2)
    state.log[783] = 1
    Wow.fire("QUEST_ACCEPTED", 783)
    Wow.flushTimers()
    check(findEntry(list:GetEntries(), function(entry)
        return entry.questID == 783 and entry.role == "turnin"
    end), "turn-in listed")
    equal(list:GetOffset(), 2, "scroll kept")
end)

test("the arrow tip sits at the target's true minimap distance", function()
    local addon, _, state = load()
    -- Elwynn is 2000 yards tall, so .05 of the map is 100 yards: half the 200-yard view radius.
    state.playerMap, state.playerX, state.playerY = 1429, .5, .5
    addon.Navigation:Start("North point", { mapID = 1429, x = .5, y = .45 })
    local tip = addon.Navigation.overlay.arrow[1].endPoint
    check(math.abs(tip[4] - 35) < .01, "35 pixels on a 140-pixel minimap, got " .. tip[4])
end)

test("panels sit above a maximised map", function()
    local addon, env = load({ mapStrata = "FULLSCREEN" })
    slash(env)
    equal(addon.UI.sidebar:GetFrameStrata(), "FULLSCREEN_DIALOG", "sidebar")
    openDeadmines(addon, env)
    equal(addon.UI.detail:GetFrameStrata(), "TOOLTIP", "detail")
end)

-- Layout and interaction ------------------------------------------------------

local function anchoredTo(frame, relative)
    for _, point in ipairs(frame.points) do
        if point[2] == relative then
            return point
        end
    end
end

test("the sidebar docks beside a windowed map and inside a maximised one", function()
    local addon, env = load({ mapRight = 1100 })
    slash(env)
    local point = anchoredTo(addon.UI.sidebar, env.WorldMapFrame)
    check(point and point[1] == "TOPLEFT" and point[3] == "TOPRIGHT", "beside the map")

    addon, env = load({ mapRight = 1900 })
    slash(env)
    point = anchoredTo(addon.UI.sidebar, env.WorldMapFrame.ScrollContainer)
    check(point and point[1] == "TOPRIGHT", "inside the canvas")
end)

test("the map button sits in the canvas's free top-right corner", function()
    local addon, env = load()
    local point = anchoredTo(addon.UI.toggle, env.WorldMapFrame.ScrollContainer)
    check(point and point[1] == "TOPRIGHT", "top right of the canvas")
    addon.UI.toggle:Click()
    check(addon.UI:IsOpen() or not env.WorldMapFrame:IsShown(), "toggles the panel")
end)

test("closing the map closes the dungeon panel even with the sidebar closed", function()
    local addon, env = load()
    slash(env, "pins")
    env.WorldMapFrame:Show()
    env.WorldMapFrame:SetMapID(1436)
    local entrance
    for _, pin in ipairs(pins(env)) do
        if pin.entry.category == "dungeon" then entrance = pin end
    end
    entrance:OnClick("LeftButton")
    check(addon.UI.detail:IsShown(), "opened from a pin")
    Wow.pressEscape()
    check(not addon.UI.detail:IsShown() and env.WorldMapFrame:IsShown(), "Escape closes the panel first")
    entrance:OnClick("LeftButton")
    env.WorldMapFrame:Hide()
    check(not addon.UI.detail:IsShown(), "closed with the map")
end)

test("pins keep a steady size and use the canvas's click path", function()
    local addon, env, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .1, .1
    slash(env)
    local pin = pins(env)[1]
    equal(pin.scalingLimits[2], 1, "scaling limits set")
    check(pin.OnClick == env.MapCanvasPinMixin.OnClick, "base OnClick kept")
    env.WorldMapFrame:ClickPin(pin, "RightButton")
    check(not env.WorldMapFrame.zoomedOut, "right-click reaches the pin")
    check(addon.Navigation:IsActive(), "right-click guides")
end)

test("lists draw only visible rows and scroll with the wheel", function()
    local addon, env = load()
    addon.settings.questMode = "all"
    slash(env)
    local list = addon.UI.sidebar.list
    local total = #list:GetEntries()
    check(total > #list.rows, "fewer rows than entries")
    check(list.bar:IsShown(), "scroll bar shown")
    local first = list.rows[1].entry
    list:Fire("OnMouseWheel", -1)
    equal(list:GetOffset(), 3, "three rows per notch")
    check(list.rows[1].entry ~= first, "rows refilled")
    list:Fire("OnMouseWheel", 1)
    list:Fire("OnMouseWheel", 1)
    equal(list:GetOffset(), 0, "clamped at the top")
end)

test("hovering a row highlights its pin", function()
    local addon, env = load()
    slash(env)
    local row = addon.UI.sidebar.list.rows[1]
    row:Fire("OnEnter")
    local found
    for _, pin in ipairs(pins(env)) do
        for _, entry in ipairs(pin.entries) do
            if entry == row.entry then found = pin end
        end
    end
    equal(found.width, 24, "highlighted")
    check(env.GameTooltip:IsOwned(row), "row tooltip")
    row:Fire("OnLeave")
    equal(found.width, 18, "restored")
end)

test("rows carry a badge matching their pin", function()
    local addon, env = load({ level = 1 })
    slash(env)
    for _, row in ipairs(addon.UI.sidebar.list.rows) do
        if row.entry then
            local letter = addon.Presentation(row.entry)
            equal(row.badge.letter:GetText(), letter, "badge letter")
        end
    end
end)

test("opening the map with the panel remembered draws pins and the list", function()
    local addon, env = load({ savedVariables = { panelOpen = true } })
    env.WorldMapFrame:Show()
    check(#pins(env) > 0, "pins drawn")
    check(#addon.UI.sidebar.list:GetEntries() > 0, "list filled")
    equal(addon.UI.sidebar.heading:GetText(), "Elwynn Forest", "heading for the open map")
end)

test("pins can be drawn in combat", function()
    local addon, env, state = load()
    state.inCombat = true
    slash(env)
    check(#pins(env) > 0, "pins drawn")
    env.WorldMapFrame:SetMapID(1453)
    check(addon.UI:IsOpen(), "no protected calls")
end)

test("a narrower list starts at the top", function()
    local addon, env = load()
    addon.settings.questMode = "all"
    slash(env)
    local list = addon.UI.sidebar.list
    list:SetOffset(60)
    equal(list:GetOffset(), 60, "scrolled down")
    -- 39 results: fewer than the old offset, so the scroll bar's range narrows past it.
    addon.UI.sidebar.search:SetText("turn-in · level 1")
    equal(#list:GetEntries(), 39, "narrower list")
    equal(list:GetOffset(), 0, "back at the top")
end)

test("modified clicks on uncached items pass a hyperlink", function()
    local addon, env, state = load()
    local detail = openDeadmines(addon, env)
    local itemID = detail.loot:GetEntries()[1]
    state.modified = true
    detail.loot.rows[1]:Click()
    check(state.modifiedClick:find("|Hitem:" .. itemID .. "|h[", 1, true), "hyperlink text")
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

print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
