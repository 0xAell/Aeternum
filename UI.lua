local _, addon = ...
local UI = {}
addon.UI = UI

local function menuAt(owner, title, fill)
    return MenuUtil.CreateContextMenu(owner, function(_, menu)
        menu:SetScrollMode(320)
        menu:CreateTitle(title)
        fill(menu)
    end)
end

local function showLink(kind, id, name)
    local ref = kind .. ":" .. id
    local link = kind == "item" and addon.ItemLink(id) or nil
    link = link or ("|H%s|h[%s]|h"):format(ref, name)
    if IsModifiedClick() and HandleModifiedItemClick(link) then return end
    if SetItemRef then SetItemRef(ref, link, "LeftButton") end
end

function UI:OpenItem(id)
    showLink("item", id, addon.ItemName(id))
end

local function colorChannel(value)
    return math.floor(math.max(0, math.min(1, value or 0)) * 255 + .5)
end

local function itemLabel(id, bags, iconSize)
    local name = addon.ItemName(id)
    local color = addon.ItemQualityColor(id)
    local text = color and ("|cff%02x%02x%02x%s|r"):format(
        colorChannel(color[1]), colorChannel(color[2]), colorChannel(color[3]), name) or name
    local icon = addon.ItemIcon(id)
    if icon then
        iconSize = iconSize or 16
        text = ("|T%d:%d:%d|t %s"):format(icon, iconSize, iconSize, text)
    end
    local count = bags and C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, false)
    if addon.IsReadableNumber(count) and count > 0 then text = text .. "  |cff88cc88In bags|r" end
    return text
end

UI.ItemLabel = itemLabel

local function itemRow(menu, id, bags)
    local row = menu:CreateButton(itemLabel(id, bags), function() showLink("item", id, addon.ItemName(id)) end)
    row:SetTooltip(function(tooltip) tooltip:SetItemByID(id) end)
    return row
end

local lootSections = {
    {"other", "Other recorded drops", "Players looted these items from this NPC. They may also drop elsewhere."},
    {"encounter", "Encounter rolls", "Players rolled on these items during this encounter."},
    {"guide", "Guide-listed drops", "Forever dungeon guides list these items. A matching player drop is unverified."},
}

local function eachDrop(boss, usable, yield)
    local starts = {}
    for _, section in ipairs(lootSections) do
        local start = boss.lootSections and boss.lootSections[section[1]]
        if start then starts[start] = section end
    end
    local section, found
    for index, id in ipairs(boss.loot) do
        section = starts[index] or section
        if usable(id) then
            found = true
            yield(id, section)
        end
    end
    return found
end

local function emptyLoot(boss)
    return #boss.loot == 0 and "No documented drops" or "No usable drops found for your character"
end

function UI:AddBossLoot(tooltip, boss, usable, addItem)
    local previous
    tooltip:AddLine("Usable loot", 1, .82, 0)
    if not eachDrop(boss, usable, function(id, section)
        if section ~= previous then tooltip:AddLine(section[2], .74, .74, .74) end
        previous = section
        if addItem then addItem(id) else tooltip:AddLine(itemLabel(id), 1, 1, 1, true) end
    end) then
        tooltip:AddLine(emptyLoot(boss), .75, .75, .75, true)
    end
end

function UI:AddBossDetails(tooltip, boss)
    local details = addon.BossDetails:ForBoss(boss.id)
    local kind = boss.event and (boss.event .. " event") or "Boss"
    if details then
        if details.classification then
            kind = boss.event and (kind .. " · " .. details.classification) or details.classification
        end
        if details.creatureType then kind = kind .. " · " .. details.creatureType end
    end
    tooltip:AddLine(kind, .8, .8, .8, true)
    if details and details.phase then tooltip:AddLine(details.phase, .8, .8, .8, true) end
    if details and details.adds and #details.adds > 0 then
        tooltip:AddLine("Adds and nearby packs: " .. table.concat(details.adds, ", "), 1, .82, 0, true)
    end
end

function UI:BossTooltip(tooltip, boss)
    tooltip:SetText(boss.name .. " — Tactics & Loot")
    self:AddBossDetails(tooltip, boss)
    addon.Tactics:AddGuide(tooltip, boss, true)
    addon.Tactics:AddCasts(tooltip, boss)
    self:AddBossLoot(tooltip, boss, addon.LootFilter())
end

local function sectionMenu(menu, section)
    local parent = menu:CreateButton(section[2])
    parent:SetScrollMode(320)
    parent:SetTooltip(function(tooltip) tooltip:SetText(section[3], nil, nil, nil, nil, true) end)
    return parent
end

local function trackLootMenu(menu, rows, onSkillsChanged)
    if not menu then return end
    local loot = {menu=menu, rows=rows, onSkillsChanged=onSkillsChanged}
    UI.openLoot = loot
    menu:SetClosedCallback(function() if UI.openLoot == loot then UI.openLoot = nil end end)
end

function UI:Boss(owner, boss)
    local pending, visible = {}, {}
    local usable = addon.LootFilter()
    local openMenu = menuAt(owner, boss.name, function(menu)
        if boss.event then menu:CreateTitle(boss.event .. " event") end
        if boss.id and addon.Tactics and addon.Tactics:ForBoss(boss.id) then
            addon.Tactics:AddMenu(menu, boss, showLink)
            menu:CreateDivider()
        end
        local parent, previous = menu, nil
        if not eachDrop(boss, usable, function(id, section)
            if section ~= previous then parent = sectionMenu(menu, section) end
            previous = section
            visible[id] = true
            local row = itemRow(parent, id)
            if not addon.ItemCached(id) then pending[id] = row end
        end) then
            menu:CreateTitle(emptyLoot(boss))
        end
    end)
    if not openMenu then return end
    trackLootMenu(openMenu, pending, function()
        local now = addon.LootFilter()
        for _, id in ipairs(boss.loot) do
            if now(id) ~= (visible[id] == true) then
                self:Boss(owner, boss)
                return
            end
        end
    end)
    for id in pairs(pending) do addon.RequestItem(id) end
end

function UI:LootSkillsChanged()
    local loot = self.openLoot
    if not loot or loot.skillsPending then return end
    loot.skillsPending = true
    C_Timer.After(0, function()
        loot.skillsPending = nil
        if self.openLoot == loot then loot.onSkillsChanged() end
    end)
end

function UI:ItemLoaded(id, success)
    local loot = self.openLoot
    local row = loot and loot.rows and loot.rows[id]
    if not row or not success then return end
    loot.rows[id] = nil
    MenuUtil.SetElementText(row, itemLabel(id))
    if loot.refreshPending then return end
    loot.refreshPending = true
    C_Timer.After(0, function()
        loot.refreshPending = nil
        if self.openLoot == loot then loot.menu:ReinitializeAll() end
    end)
end

function UI:BossGroup(owner, members, label)
    local dungeon = addon.DungeonMap.dungeon
    menuAt(owner, label or "Bosses", function(menu)
        for _, boss in ipairs(members) do
            local row = menu:CreateButton(boss.name, function()
                C_Timer.After(0, function()
                    if addon.DungeonMap.dungeon == dungeon then self:Boss(addon.DungeonMap.frame, boss) end
                end)
            end)
            row:SetTooltip(function(tooltip) self:BossTooltip(tooltip, boss) end)
        end
    end)
end

function UI:Keys(menu, dungeon)
    for _, id in ipairs(dungeon.keys) do
        if not addon.ItemCached(id) then addon.RequestItem(id) end
        itemRow(menu, id, true)
    end
end

local function price(lesson)
    if lesson.cost == nil then return "Price unknown" end
    if lesson.cost == 0 then return "Free" end
    if lesson.petPoints then return (TRAINING_POINTS_ABBREV or "%s training points"):format(lesson.cost) end
    return GetMoneyString(lesson.cost, true)
end

local standings = {[4]="Neutral", [5]="Friendly", [6]="Honored", [7]="Revered", [8]="Exalted"}
local priceNotes = {
    [9]="Price shown to a recorded visitor. Their reputation is unknown.",
    [10]="Listed training price from What's Training. Your reputation can affect the price.",
    ["Classic reference"]="Price from the Classic trainer catalogue.",
    ["Bundled trainer record"]="Price from NorgannonDB's trainer catalogue.",
}

local function lessonRows(menu, lessons)
    for _, lesson in ipairs(lessons) do
        local name = lesson.name
        if lesson.rank and lesson.rank ~= "" then name = name .. " (" .. lesson.rank .. ")" end
        local costText = price(lesson)
        local text = name .. "   " .. costText
        local standing = standings[lesson.priceBasis]
        if standing and lesson.priceBasis ~= 4 then text = text .. "  |cff999999" .. standing .. "|r" end
        if lesson.source == "Classic reference" then text = text .. "  |cff999999Classic|r" end
        if lesson.beta then text = text .. "  |cff999999Beta|r" end
        local row = menu:CreateButton(text, function()
            if lesson.id then showLink("spell", lesson.id, lesson.name) end
        end)
        row:SetTooltip(function(tooltip)
            if lesson.id then tooltip:SetSpellByID(lesson.id) else tooltip:SetText(name) end
            if lesson.level and lesson.level > 1 then tooltip:AddLine("Level " .. lesson.level) end
            if lesson.skill and lesson.requirement and lesson.requirement > 0 then
                tooltip:AddLine(lesson.skill .. " " .. lesson.requirement)
            end
            if lesson.statusText then tooltip:AddLine(lesson.statusText, .85, .85, .85) end
            tooltip:AddLine(lesson.source .. " · " .. costText, 1, .82, 0)
            local note = priceNotes[lesson.priceBasis]
            if standing then note = "Price recorded at " .. standing .. " standing." end
            if note and lesson.cost ~= nil then tooltip:AddLine(note, .85, .85, .85, true) end
        end)
    end
end

local function stopDirections(menu)
    local row = menu:CreateButton("Stop directions", function() addon.Navigation:Stop() end)
    row:SetTooltip(function(tooltip) tooltip:SetText(addon.Navigation:GetStatus()) end)
end

function UI:Route(menu, entry, label)
    local dungeon = entry.category == "dungeon"
    local target = dungeon and (entry.title .. " entrance") or entry.title
    local option = menu:CreateButton(label or ("Show path to " .. entry.title), function()
        local ok, reason = addon.Navigation:Start(target, entry.point, dungeon and entry.source.id or nil)
        local overlay = addon.Navigation.overlay
        if not ok or not overlay or not overlay:IsVisible() then
            DEFAULT_CHAT_FRAME:AddMessage(reason or addon.Navigation:GetStatus())
        end
    end)
    option:SetTooltip(function(tooltip)
        tooltip:SetText(entry.title)
        tooltip:AddLine(entry.point.hint or (entry.point.waypoints and "Follow the approach points on your minimap."
            or "Follow the bearing on your minimap."), 1, 1, 1, true)
    end)
end

function UI:Trainer(owner, entry)
    menuAt(owner, entry.title, function(menu)
        menu:CreateTitle(entry.subtitle)
        if addon.Navigation:IsDestination(entry.point) then stopDirections(menu)
        else self:Route(menu, entry, "Directions to trainer") end
        local lessons = addon.Trainers:Lessons(entry.source.id)
        if #lessons == 0 then
            local npc = entry.source.id
            local recorded = addon.foreverTraining.offers[npc] or addon.Data.offers[npc]
                or addon.classicTraining.trainers[npc] or next((AeternumTrainerDB and AeternumTrainerDB[npc]) or {})
            menu:CreateTitle(recorded and "No recorded lessons for this character."
                or "Visit this trainer to record their lessons.")
            return
        end
        local groups = {current={}, later={}, learned={}}
        for _, lesson in ipairs(lessons) do
            local group, status = addon.Trainers:LessonState(lesson)
            lesson.statusText = status
            local list = groups[group or "current"]
            list[#list + 1] = lesson
        end
        menu:CreateDivider()
        if #groups.current == 0 then
            menu:CreateTitle("No training available right now")
        else
            lessonRows(menu, groups.current)
        end
        for _, section in ipairs({{"later", "Later training"}, {"learned", "Learned"}}) do
            local list = groups[section[1]]
            if #list > 0 then
                local sub = menu:CreateButton(section[2])
                sub:SetScrollMode(300)
                lessonRows(sub, list)
            end
        end
    end)
end

local function dungeonNameCounts(entries)
    local counts = {}
    for _, entry in ipairs(entries) do
        if entry.category == "dungeon" then counts[entry.title] = (counts[entry.title] or 0) + 1 end
    end
    return counts
end

local function doorLabel(entry, counts)
    if (counts[entry.title] or 0) < 2 or entry.category ~= "dungeon" then return entry.title end
    local point = entry.point
    local zone = entry.mapID ~= point.mapID and (addon.ZoneName(point.mapID) .. " ") or ""
    return ("%s · %s%.1f, %.1f"):format(entry.title, zone, point.x * 100, point.y * 100)
end

function UI:Directions(owner, entries)
    menuAt(owner, "Dungeon entrance", function(menu)
        local counts = dungeonNameCounts(entries)
        for _, entry in ipairs(entries) do
            if entry.category == "dungeon" and not addon.Navigation:IsDestination(entry.point, entry.source.id) then
                self:Route(menu, entry, "Show path to " .. doorLabel(entry, counts))
            end
        end
        if addon.Navigation:IsActive() then
            stopDirections(menu)
        end
    end)
end

-- Moving the world map from add-on code would taint its map ID and zoom for the rest of
-- the session (MapCanvasMixin:SetMapID reads the old ID first), and the game would then
-- block Blizzard's own pins in combat. A location on the open map is marked at once.
-- Otherwise the chat says where it is, and it is marked when the player opens that map.
function UI:ShowLocation(entry)
    addon.Atlas:Close()
    addon.DungeonMap:Close()
    if self.map:GetMapID() == entry.mapID then
        self.waitingLocation = nil
        addon.FocusLocation(entry)
        return
    end
    self.waitingLocation = entry
    local zone = addon.ZoneName(entry.mapID)
    local name = entry.contact and ("%s (%s)"):format(entry.contact, entry.title) or entry.title
    DEFAULT_CHAT_FRAME:AddMessage(("%s is in %s at %.1f, %.1f. Open %s on the map to see it."):format(
        name, zone, entry.x * 100, entry.y * 100, zone))
end

function UI:EntranceMenu(menu, dungeon)
    local doors = addon.DungeonEntrances(dungeon, addon.DungeonMap.entrance, self.map:GetMapID())
    if #doors == 0 then
        menu:CreateTitle("No entrance for this faction")
        return
    end
    for _, entry in ipairs(doors) do
        local section = menu
        if #doors > 1 then
            local label = entry.point.label or addon.ZoneName(entry.mapID)
            section = menu:CreateButton(("%s · %.1f, %.1f"):format(label, entry.x * 100, entry.y * 100))
        end
        section:CreateButton("Show on zone map", function() self:ShowLocation(entry) end)
        if addon.Navigation:IsDestination(entry.point, dungeon.id) then stopDirections(section)
        else self:Route(section, entry, "Directions to entrance") end
    end
end

function UI:QuestMenu(menu, dungeon)
    for _, id in ipairs(dungeon.quests) do
        local quest = addon.Quest(id)
        if quest then
            local state = addon.Quests:State(id)
            local role = (state == "active" or state == "ready") and "turnin" or "start"
            local function location() return addon.QuestLocation(id, role, self.map:GetMapID()) end
            local row = menu:CreateButton(quest.name, function()
                local entry = location()
                if entry then self:ShowLocation(entry) end
            end)
            row:SetEnabled(addon.HasQuestLocation(id, role))
            row:SetTooltip(function(tooltip)
                local entry = location()
                tooltip:SetText(quest.name)
                local status = addon.Quests:Style(state, role).label
                if quest.level then status = ("Level %d · %s"):format(quest.level, status) end
                tooltip:AddLine(status)
                local requirement = addon.Quests:Requirement(id)
                if requirement then tooltip:AddLine(requirement) end
                if entry then
                    tooltip:AddLine((entry.contact or entry.subtitle) .. " · " .. addon.ZoneName(entry.mapID))
                else
                    tooltip:AddLine(role == "turnin" and "Turn-in location unknown" or "Start location unknown")
                end
                addon.Quests:AddObjectives(tooltip, id)
            end)
        end
    end
end

local function questWatch(menu, id)
    local api = C_QuestLog
    if not (api.IsOnQuest(id) and api.GetQuestWatchType and api.AddQuestWatch and api.RemoveQuestWatch) then return end
    if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID then
        local current = C_SuperTrack.GetSuperTrackedQuestID()
        if (not issecretvalue or not issecretvalue(current)) and current ~= id then
            menu:CreateButton("Focus quest", function() C_SuperTrack.SetSuperTrackedQuestID(id) end)
        end
    end
    local watched = api.GetQuestWatchType(id) ~= nil
    menu:CreateButton(watched and "Untrack quest" or "Track quest", function()
        if api.GetQuestWatchType(id) ~= nil then api.RemoveQuestWatch(id)
        elseif not api.AddQuestWatch(id) then
            DEFAULT_CHAT_FRAME:AddMessage("Your quest tracker could not add this quest.")
        end
    end)
end

function UI:Pick(owner, entry)
    if entry.category == "dungeon" then
        addon.DungeonMap:Open(entry.source, entry.bossIndex, nil, entry.point)
        if entry.bossIndex then self:Boss(addon.DungeonMap.frame, entry.source.bosses[entry.bossIndex]) end
    elseif entry.category == "quest" then
        menuAt(owner, entry.title, function(menu)
            local _, _, text = addon.Presentation(entry)
            menu:CreateTitle(text)
            if entry.contact then menu:CreateTitle(entry.contact) end
            if entry.role == "objective" and entry.subtitle ~= text then menu:CreateTitle(entry.subtitle) end
            if addon.Navigation:IsDestination(entry.point) then stopDirections(menu)
            else self:Route(menu, entry, "Directions to this location") end
            questWatch(menu, entry.questID)
        end)
    else
        self:Trainer(owner, entry)
    end
end

function UI:PickLocation(owner, entries)
    if #entries == 1 then self:Pick(owner, entries[1]) return end
    local first = entries[1]
    local title = "At this location"
    for _, entry in ipairs(entries) do
        if entry.x ~= first.x or entry.y ~= first.y then title = "Nearby map locations" break end
    end
    menuAt(owner, title, function(menu)
        local counts = dungeonNameCounts(entries)
        for _, entry in ipairs(entries) do
            local name = doorLabel(entry, counts)
            if entry.questID then
                name = name .. (entry.role == "turnin" and " (turn-in)" or
                    (entry.role == "objective" and " (objective)" or " (start)"))
            end
            local row = menu:CreateButton(name, function()
                C_Timer.After(0, function() if self.map:IsShown() then self:Pick(self.map, entry) end end)
            end)
            row:SetTooltip(function(tooltip)
                tooltip:SetText(entry.title)
                tooltip:AddLine(entry.contact or entry.subtitle)
                local point = entry.point
                tooltip:AddLine(("%.1f, %.1f"):format(point.x*100, point.y*100))
            end)
        end
    end)
end

local function dungeonLabel(entry)
    local levels = addon.ColoredDungeonLevel(entry.source, true)
    return levels and ("%s  %s"):format(entry.title, levels) or entry.title
end

-- Every dungeon and wing by level, each range in the character's difficulty colour.
-- Choosing one opens its floors.
function UI:FillDungeonIndex(menu)
    for _, entry in ipairs(addon.DungeonsByLevel()) do
        local row = menu:CreateButton(dungeonLabel(entry), function()
            C_Timer.After(0, function() if self.map:IsShown() then self:Pick(self.map, entry) end end)
        end)
        row:SetTooltip(function(tooltip)
            local dungeon = entry.source
            tooltip:SetText(dungeon.name)
            tooltip:AddLine(addon.ColoredDungeonLevel(dungeon) or "Dungeon")
            if dungeon.size then
                local bosses = #dungeon.bosses == 1 and "1 boss" or ("%d bosses"):format(#dungeon.bosses)
                tooltip:AddLine(("%d players · %s"):format(dungeon.size, bosses), 1, 1, 1)
            end
            tooltip:AddLine("Click for floor map and boss loot", 1, .82, 0)
        end)
    end
end

function UI:Search(query, results)
    if not results and addon.Trim(query) == "" then
        menuAt(self.map, "Dungeons by level", function(menu)
            menu:SetScrollMode(460)
            self:FillDungeonIndex(menu)
        end)
        return
    end
    local entries = results or addon.Entries(self.map:GetMapID(), true, query)
    local openMenu = menuAt(self.map, "Dungeons", function(menu)
        if #entries == 0 then menu:CreateTitle("No matching dungeons, bosses or items") end
        for _, entry in ipairs(entries) do
            local label = entry.bossIndex and (entry.title .. " · " .. entry.subtitle) or dungeonLabel(entry)
            local row = menu:CreateButton(label, function()
                C_Timer.After(0, function() if self.map:IsShown() then self:Pick(self.map, entry) end end)
            end)
            if entry.bossIndex then
                row:SetTooltip(function(tooltip)
                    self:BossTooltip(tooltip, entry.source.bosses[entry.bossIndex])
                end)
            end
        end
    end)
    if query and query ~= "" then
        trackLootMenu(openMenu, nil, function()
            local now = addon.Entries(self.map:GetMapID(), true, query)
            if #entries ~= #now then
                self:Search(query, now)
                return
            end
            for i, entry in ipairs(now) do
                if entry.itemID ~= entries[i].itemID then
                    self:Search(query, now)
                    return
                end
            end
        end)
    end
end

function UI:Attach(map)
    self.map = map
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, menu)
            menu:CreateDivider()
            if addon.Atlas.active then
                menu:CreateButton("Return to world map", function() addon.Atlas:Close() end)
                menu:CreateCheckbox("Terrain at close zoom", function() return addon.settings.atlasTerrain end,
                    function()
                        addon.settings.atlasTerrain = not addon.settings.atlasTerrain
                        addon.Atlas:Refresh()
                    end)
            elseif addon.Atlas:Available() then
                local atlas = menu:CreateButton("Dungeon atlas", function() addon.Atlas:Open() end)
                atlas:SetTooltip(function(tooltip)
                    tooltip:SetText("Browse dungeon entrances across Azeroth")
                    tooltip:AddLine("Scroll to zoom. Drag to pan. Middle-click to find yourself.", 1, 1, 1, true)
                end)
            end
            local function category(parent, id, name)
                parent:CreateCheckbox(name, function() return addon.CategoryEnabled(id) end, function()
                    addon.settings.filters[id] = not addon.CategoryEnabled(id)
                    addon.RefreshMap()
                end)
            end
            local index = menu:CreateButton("Dungeons by level")
            index:SetScrollMode(460)
            self:FillDungeonIndex(index)
            category(menu, "dungeon", addon.categoryByID.dungeon.label)
            local trainers = menu:CreateButton("Trainers")
            for _, id in ipairs({"class", "profession", "weapon"}) do
                category(trainers, id, addon.categoryByID[id].label)
            end
            trainers:CreateCheckbox("Other classes and professions", function() return addon.settings.otherTrainers end,
                function() addon.settings.otherTrainers = not addon.settings.otherTrainers; addon.RefreshMap() end)
            local quests = menu:CreateButton("Quest locations")
            category(quests, "quest", "Quest givers and turn-ins")
            quests:CreateCheckbox("Low-level quests", function() return addon.settings.lowLevelQuests end,
                function() addon.settings.lowLevelQuests = not addon.settings.lowLevelQuests; addon.RefreshMap() end)
            quests:CreateCheckbox("All quest locations", function() return addon.settings.questMode == "all" end,
                function()
                    addon.settings.questMode = addon.settings.questMode == "all" and "available" or "all"
                    addon.RefreshMap()
                end)
            if addon.Navigation:IsActive() then stopDirections(menu) end
        end)
    end
    map:HookScript("OnShow", function() addon.DungeonMap:OpenInstance() end)
    map:HookScript("OnHide", function() addon.DungeonMap:Close() end)
end
