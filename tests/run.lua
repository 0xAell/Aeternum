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

test("a normal map visit creates no guide, map pins or minimap overlay", function()
    local addon, env, state = load()
    local map = env.WorldMapFrame
    local frames = #state.frames
    map:Show()
    check(addon.settings and not addon.UI.window, "only the provider is attached")
    equal(#state.frames, frames, "no addon widgets created on open")
    equal(#pins(env), 0, "no map pins by default")
    check(not addon.Navigation.overlay, "no minimap overlay")
    slash(env)
    check(addon.UI:IsBrowsing(), "explicit browse opens the guide")
    equal(#pins(env), 0, "browsing alone keeps the map clear")
    equal(addon.UI.window.TitleText:GetText(), "Elwynn Forest", "zone title")
end)

test("unknown slash commands print help", function()
    local _, env, state = load()
    slash(env, "nonsense")
    check(#state.messages >= 4, "help printed")
end)

test("old open-state data never reopens the guide and filter choices survive", function()
    local addon, env = load({savedVariables = {panelOpen = true, filters = {quest = false}}})
    env.WorldMapFrame:Show()
    check(not addon.UI.window and not addon.CategoryEnabled("quest"), "old open flag is transient")
    slash(env)
    env.WorldMapFrame:Hide()
    env.WorldMapFrame:Show()
    check(not addon.UI:IsOpen() and not env.AeternumDB.panelOpen, "normal map visits stay quiet")
end)

test("category filters and search narrow the list", function()
    local addon, env = load()
    slash(env)
    local list = addon.UI.sidebar.list
    local all = #list:GetEntries()
    addon.UI.sidebar.filter:OpenMenu():Find("Quests"):Click()
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
    addon.UI.sidebar.search:SetText("the deadmines")
    local entries = addon.UI.sidebar.list:GetEntries()
    equal(#entries, 1, "search")
    equal(entries[1].title, "The Deadmines", "match")
end)

test("boss and item searches open the drop source and preserve the query on Back", function()
    local addon, env, state = load()
    slash(env, "dungeons")
    local panel = addon.UI.sidebar
    panel.search:SetText("  cRUel BarB  ")
    local hit = panel.list.rows[1].entry
    equal(hit.itemID, 5191, "Cruel Barb")
    equal(hit.subtitle, "Edwin VanCleef · The Deadmines", "drop source")
    check(not state.requested, "search uses the local catalogue")
    panel.list.rows[1]:Fire("OnEnter")
    equal(env.GameTooltip.lines[1], "item:5191", "game item tooltip in search results")
    state.modified = true
    panel.list.rows[1]:Click()
    check(state.modifiedClick:find("Hitem:5191", 1, true) and addon.UI:IsBrowsing(), "link from search")
    state.modified = false
    panel.list.rows[1]:Click()
    local detail = addon.UI.detail
    equal(detail.tab, "loot", "direct to loot")
    equal(detail.boss:GetText(), "Edwin VanCleef", "matching boss")
    check(findEntry(detail.loot.rows, function(row) return row.entry == 5191 and row.highlighted end),
        "matching item is visible and highlighted")
    Wow.pressEscape()
    equal(panel.search:GetText(), "  cRUel BarB  ", "atlas search restored")
    panel.search:SetText("vancleef")
    panel.list.rows[1]:Click()
    equal(detail.boss:GetText(), "Edwin VanCleef", "direct boss search")
    equal(detail.tab, "loot", "boss opens to loot")
    detail.back:Click()
    panel.search:SetText("Scarlet Leggings")
    local hits = panel.list:GetEntries()
    check(#hits >= 2 and hits[1].subtitle ~= hits[2].subtitle, "separate sources for a shared item")
    panel.search:SetText("[%")
    equal(#panel.list:GetEntries(), 0, "search punctuation is literal")
end)

test("Back keeps the atlas scroll position and the two pages keep their own searches", function()
    local addon, env = load()
    slash(env)
    local panel = addon.UI.sidebar
    panel.search:SetText("trainer")
    panel.mode:Click()
    equal(panel.search:GetText(), "", "new atlas search")
    panel.list:SetOffset(10)
    local expected = panel.list.rows[1].entry.title
    panel.list.rows[1]:Click()
    Wow.pressEscape()
    equal(panel.list:GetOffset(), 10, "list stays in place")
    equal(panel.list.rows[1].entry.title, expected, "same result visible")
    panel.search:SetText("West")
    panel.mode:Click()
    equal(panel.search:GetText(), "trainer", "zone search intact")
    panel.mode:Click()
    equal(panel.search:GetText(), "West", "atlas search intact")
    Wow.pressEscape()
    check(not addon.UI:IsOpen() and env.WorldMapFrame:IsShown(), "guide closes before the game map")
    Wow.pressEscape()
    check(not env.WorldMapFrame:IsShown(), "map handles the next Escape")
end)

test("typing in the atlas keeps map pins and their tooltips in place", function()
    local addon, env, state = load()
    slash(env, "pins")
    slash(env, "dungeons")
    local pinned = pins(env)[1]
    pinned:OnMouseEnter()
    local panel = addon.UI.sidebar
    panel.search:SetText("Cruel Barb")
    check(env.GameTooltip:IsOwned(pinned), "search did not release the hovered map pin")
    state.cached[5191] = true
    Wow.fire("GET_ITEM_INFO_RECEIVED", 5191, true)
    equal(panel.list.rows[1].title.textColor[1], .64, "a cached drop gains its quality colour")
    equal(#panel.list:GetEntries(), 1, "search kept")
end)

test("reset restores defaults", function()
    local addon, env = load({ savedVariables = { questMode = "all", filters = { dungeon = false } } })
    slash(env, "reset")
    equal(addon.settings.questMode, "available", "quest mode")
    check(addon.CategoryEnabled("dungeon"), "filters")
    check(Wow.trackingMenu():Find("Aeternum"):Find("Dungeon entrances").checked(), "menu reflects reset")
end)

test("pins can stay on the map with the panel closed", function()
    local addon, env = load()
    env.WorldMapFrame:Show()
    equal(#pins(env), 0, "hidden by default")
    slash(env, "pins")
    check(addon.settings.showMapPins, "setting saved")
    check(#pins(env) > 0, "pins shown")
end)

test("map tracking filters and quest progress work before the guide has ever opened", function()
    local addon, env, state = load({ level = 1 })
    env.WorldMapFrame:Show()
    local function showsQuest(role)
        for _, pin in ipairs(pins(env)) do
            if findEntry(pin.entries, function(entry) return entry.questID == 783 and entry.role == role end) then
                return true
            end
        end
    end
    Wow.trackingMenu():Find("Aeternum"):Find("Show pins on map"):Click()
    check(showsQuest("start"), "start visible")
    state.log[783] = 1
    Wow.fire("QUEST_ACCEPTED", 783)
    Wow.flushTimers()
    check(showsQuest("turnin") and not showsQuest("start"), "quest pins follow the character")
    Wow.trackingMenu():Find("Aeternum"):Find("Quests"):Click()
    check(not showsQuest("turnin") and not addon.UI.window, "filtered without opening a guide")
    Wow.trackingMenu():Find("Aeternum"):Find("Browse this map"):Click()
    check(not addon.UI.sidebar.filter:OpenMenu():Find("Quests").checked(), "same setting in the browse filter")
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
    addon.UI.sidebar.filter:OpenMenu():Find("Low-level quests"):Click()
    check(not questPin(addon, 1429, 783, "start"), "trivial hidden")
    addon.UI.sidebar.filter:OpenMenu():Find("All quest locations"):Click()
    equal(addon.settings.questMode, "all", "all quests")
    local low = addon.UI.sidebar.filter:OpenMenu():Find("Low-level quests")
    equal(low.enabled, false, "low-level option disabled in all mode")
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
    slash(env, "pins")
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

-- Guidance --------------------------------------------------------------------

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

test("any pin can be guided to from the sidebar and stopped", function()
    local addon, env, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .1, .1
    slash(env)
    local panel = addon.UI.sidebar
    check(not panel.guide:IsShown(), "guide hidden without a selection")
    local trainer = findEntry(panel.list:GetEntries(), function(entry) return entry.category == "class" end)
    addon.UI:Select(trainer)
    check(panel.selection:GetText():find(trainer.title, 1, true), "selection shown")
    panel.guide:Click()
    check(addon.Navigation:IsActive(), "guiding")
    check(addon.UI.status:GetText():find(trainer.title, 1, true), "sidebar status")
    check(addon.UI.tracking:IsVisible(), "route footer shown")
    addon.UI.stop:Click()
    check(not addon.Navigation:IsActive(), "stopped")
    check(not addon.UI.tracking:IsShown(), "route footer removed")
end)

test("a trainer pin starts guidance without opening a guide", function()
    local addon, env, state = load()
    state.playerMap, state.playerX, state.playerY = 1429, .1, .1
    slash(env, "pins")
    env.WorldMapFrame:Show()
    local pin = findEntry(pins(env), function(p) return p.entry.category == "class" and #p.entries == 1 end)
    check(pin, "single trainer pin")
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    check(addon.Navigation:IsActive() and not addon.UI.window, "guide started directly")
    slash(env, "stop")
    check(not addon.Navigation:IsActive(), "stopped by command")
end)

test("one Scarlet Monastery pin lets the player pick any of the four wings", function()
    local addon, env, state = load({ mapID = 1420 })
    slash(env, "pins")
    env.WorldMapFrame:Show()
    local pin = findEntry(pins(env), function(p) return p.entry.source.id == "sm-armory" end)
    equal(#pin.entries, 4, "one shared entrance")
    env.WorldMapFrame:ClickPin(pin, "LeftButton")
    check(not addon.UI.window, "choose a wing before opening the guide")
    state.menu:Find("Scarlet Monastery - Library"):Click()
    equal(addon.UI.detail.dungeon.id, "sm-library", "exact wing selected")
    Wow.pressEscape()
    check(not addon.UI:IsOpen() and env.WorldMapFrame:IsShown(), "a pin opens just one guide page")
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
    equal(addon.UI.window.TitleText:GetText(), "The Deadmines", "title")
    check(detail.facts:GetText():find("5 players", 1, true), "group size")
    local bosses = entry.source.bosses
    equal(detail.tab, "map", "floor shown first")
    check(not state.requested and not detail.loot:IsVisible(), "no loot fetched on the floor tab")
    detail.tabs.loot:Click()
    equal(detail.boss:GetText(), bosses[1].name, "first boss")
    detail.boss:OpenMenu():Find(bosses[#bosses].name):Click()
    equal(detail.boss:GetText(), bosses[#bosses].name, "direct boss selection")
    local loot = detail.loot:GetEntries()
    equal(loot, bosses[#bosses].loot, "loot keeps the source order")
    check(state.requested[loot[1]], "item data requested")
    check(detail.entranceText:GetText():find("Moonbrook", 1, true), "authored approach label")
    check(addon.UI.selected == entry, "entrance selected")
    detail.route:Click()
    check(addon.Navigation:GetTarget() == "The Deadmines entrance", "guiding to the entrance")
    equal(addon.UI.status:GetText(), addon.Navigation:GetStatus(), "shared route status")
end)

test("dungeon floor paging reuses client tiles and releases art on other tabs", function()
    local addon, env = load()
    local detail = openDeadmines(addon, env)
    local floor = detail.floorMap
    local view = findEntry(floor.children, function(child) return child.tiles ~= nil end)
    local nextPage = findEntry(floor.children, function(child)
        return child.normal and child.normal:find("NextPage", 1, true)
    end)
    equal(#view.tiles, 12, "client tile grid")
    equal(view.tiles[1].texture, 449591, "Deadmines first floor")
    nextPage:Click()
    equal(floor.floorIndex, 2, "second floor")
    equal(view.tiles[1].texture, 449603, "second floor art")
    check(not nextPage:IsEnabled(), "last floor")
    detail.tabs.quests:Click()
    for _, tile in ipairs(view.tiles) do
        check(not tile.texture and not tile:IsShown(), "hidden floor art released")
    end
    detail.tabs.map:Click()
    equal(view.tiles[1].texture, 449603, "same floor after returning")
end)

test("loot rows show item details and support modified clicks", function()
    local addon, env, state = load()
    local detail = openDeadmines(addon, env)
    detail.tabs.loot:Click()
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
    detail.tabs.quests:Click()
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
    equal(detail.entranceText:GetText(), "Entrance not recorded", "explained")
    equal(detail.tab, "loot", "opens to useful content without a floor")
end)

test("the busiest map draws every location in reference mode", function()
    local addon, env = load({ mapID = 1453 })
    addon.settings.questMode = "all"
    slash(env, "pins")
    slash(env)
    local locations = {}
    for _, entry in ipairs(addon.Entries(1453, false, "")) do
        locations[("%0.3f:%0.3f"):format(entry.x, entry.y)] = true
    end
    local count = 0
    for _ in pairs(locations) do count = count + 1 end
    equal(#pins(env), count, "one pin per location")
    check(not addon.UI.sidebar.summary:find("off map", 1, true), "nothing left off")
end)

test("a location past the map pin limit can still be previewed from the list", function()
    local addon, env = load()
    local entries = {}
    for i = 1, 151 do
        local x = i / 200
        entries[i] = { title = "Trainer " .. i, category = "class", subtitle = "Trainer", mapID = 1429,
            x = x, y = .5, point = {mapID = 1429, x = x, y = .5} }
    end
    addon.Entries = function() return entries end
    slash(env, "pins")
    slash(env)
    equal(#pins(env), 150, "normal layer capped")
    check(addon.UI.sidebar.summary:find("1 off map", 1, true), "omitted location accounted for")
    addon.HighlightPin(entries[151])
    equal(#pins(env), 151, "temporary pin for the requested location")
    addon.HighlightPin(entries[1])
    equal(#pins(env), 150, "previous preview released")
    addon.HighlightPin(nil)
    for _, pin in ipairs(pins(env)) do equal(pin:GetWidth(), 16, "regular pin size restored") end
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
    slash(env, "pins")
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

test("a selected location survives hover and clears when that quest is accepted", function()
    local addon, env, state = load({ level = 1 })
    slash(env)
    local start = questPin(addon, 1429, 783, "start")
    addon.UI:Select(start)
    equal(pins(env)[1].entry, start, "selection preview")
    local row = findEntry(addon.UI.sidebar.list.rows, function(r) return r.entry ~= start end)
    row:Fire("OnEnter")
    equal(#pins(env), 1, "single preview while hovering")
    equal(pins(env)[1].entry, row.entry, "hover preview")
    row:Fire("OnLeave")
    equal(pins(env)[1].entry, start, "selection restored")
    state.log[783] = 1
    Wow.fire("QUEST_LOG_UPDATE")
    Wow.flushTimers()
    check(not addon.UI.selected and not addon.UI.sidebar.guide:IsShown(), "clears the unavailable start")
    equal(#pins(env), 0, "no stale map pin")
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

test("dungeon and browse pages share one window above the maximised map", function()
    local addon, env = load({mapStrata = "FULLSCREEN", mapRight = 1900})
    slash(env)
    local window = addon.UI.window
    equal(window:GetFrameStrata(), "FULLSCREEN_DIALOG", "window above the map")
    local detail = openDeadmines(addon, env)
    equal(detail:GetParent(), addon.UI.sidebar:GetParent(), "one content area")
    check(window == addon.UI.window and not addon.UI.sidebar:IsShown(), "only the dungeon page is displayed")
end)

-- Layout and interaction ------------------------------------------------------

local function anchoredTo(frame, relative)
    for _, point in ipairs(frame.points) do
        if point[2] == relative then
            return point
        end
    end
end

test("guide docks on either side with room and stays bounded when maximised", function()
    for _, layout in ipairs({{0, 1100, "TOPLEFT", "TOPRIGHT"}, {500, 1900, "TOPRIGHT", "TOPLEFT"}}) do
        local addon, env = load({mapLeft = layout[1], mapRight = layout[2]})
        slash(env)
        local point = anchoredTo(addon.UI.window, env.WorldMapFrame)
        check(point and point[1] == layout[3] and point[3] == layout[4], "outside map")
    end
    local addon, env = load({mapRight = 1900})
    slash(env)
    check(anchoredTo(addon.UI.window, env.WorldMapFrame.ScrollContainer), "compact layout")
    equal(addon.UI.window:GetWidth(), 328, "bounded width")
    equal(addon.UI.window:GetHeight(), 334, "bounded height")
    equal(#env.WorldMapFrame.ScrollContainer.points, 0, "native viewport anchors intact")
end)

test("the title moves only the guide and display changes recalculate its dock", function()
    local addon, env, state = load({mapRight = 1300, mapScale = 1.5})
    slash(env)
    local window = addon.UI.window
    check(anchoredTo(window, env.WorldMapFrame.ScrollContainer), "scaled map has no outside space")
    local title = findEntry(state.frames, function(frame) return frame.dragButtons ~= nil end)
    check(window.movable and window.dontSavePosition and title:GetParent() == window, "session-only title drag")
    title:Fire("OnDragStart")
    check(window.moving and not env.WorldMapFrame.moving, "only the guide moves")
    title:Fire("OnDragStop")
    check(not window.moving, "released")
    env.UIParent:SetSize(2560, 1440)
    Wow.fire("DISPLAY_SIZE_CHANGED")
    check(anchoredTo(window, env.WorldMapFrame), "docks outside with more space")
    env.WorldMapFrame.scale = 2
    Wow.fire("UI_SCALE_CHANGED")
    check(anchoredTo(window, env.WorldMapFrame.ScrollContainer), "bounds reconsidered on scale change")
    equal(#env.WorldMapFrame.ScrollContainer.points, 0, "world map canvas untouched")
end)

test("the native tracking menu opens either page and preserves Blizzard's menu", function()
    local addon, env = load()
    env.WorldMapFrame:Show()
    local root = Wow.trackingMenu()
    equal(root.children[1].label, "Blizzard map filter", "existing menu entry retained")
    local menu = root:Find("Aeternum")
    menu:Find("Dungeon guide"):Click()
    check(addon.UI:IsAtlas() and addon.UI:IsBrowsing(), "atlas open")
    Wow.trackingMenu():Find("Aeternum"):Find("Browse this map"):Click()
    check(not addon.UI:IsAtlas() and addon.UI:IsBrowsing(), "zone open")
    check(not addon.UI.toggle, "no extra button on the canvas")
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

test("right-click on addon pins follows Blizzard's map zoom in and out of combat", function()
    local addon, env, state = load()
    slash(env, "pins")
    env.WorldMapFrame:Show()
    for _, combat in ipairs({false, true}) do
        state.inCombat = combat
        addon.RefreshMap()
        local pin = pins(env)[1]
        equal(pin.scalingLimits[2], 1, "steady pin size")
        check(pin.OnClick == env.MapCanvasPinMixin.OnClick, "native click dispatch")
        env.WorldMapFrame.zoomedOut = false
        env.WorldMapFrame:ClickPin(pin, "RightButton")
        check(env.WorldMapFrame.zoomedOut and not addon.Navigation:IsActive(), "native zoom")
    end
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
    equal(found.width, 22, "highlighted")
    equal(#pins(env), 1, "only the hovered location")
    check(env.GameTooltip:IsOwned(row), "row tooltip")
    row:Fire("OnLeave")
    equal(#pins(env), 0, "temporary pin removed")
end)

test("rows use the same game art as their pin", function()
    local addon, env = load({ level = 1 })
    slash(env)
    for _, row in ipairs(addon.UI.sidebar.list.rows) do
        if row.entry then
            local icon = addon.Presentation(row.entry)
            equal(row.icon.atlas or row.icon.texture, icon, "shared icon")
        end
    end
end)

test("old explicit pin choices migrate without opening a window", function()
    local addon, env = load({savedVariables = {panelOpen = true, pinsWithPanelClosed = true}})
    env.WorldMapFrame:Show()
    check(#pins(env) > 0 and not addon.UI.window, "pins only")
    equal(addon.settings.showMapPins, true, "old choice migrated")
    check(not addon.settings.panelOpen and not addon.settings.pinsWithPanelClosed, "obsolete fields cleared")
end)

test("a current off preference takes priority over an old on preference", function()
    local addon, env = load({savedVariables = {pinsWithPanelClosed = true, showMapPins = false}})
    env.WorldMapFrame:Show()
    check(not addon.settings.showMapPins and #pins(env) == 0, "keeps current preference")
end)

test("combat allows pins and an open map guide without toggling a protected map", function()
    local addon, env, state = load()
    state.inCombat = true
    slash(env)
    check(not env.WorldMapFrame:IsShown() and not addon.UI.window, "closed map left to the client")
    env.WorldMapFrame:Show()
    slash(env, "pins")
    slash(env)
    check(#pins(env) > 0 and addon.UI:IsBrowsing(), "already open map remains usable")
    env.WorldMapFrame:SetMapID(1453)
    check(#pins(env) > 0, "pins redrawn in combat")
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
    detail.tabs.loot:Click()
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
