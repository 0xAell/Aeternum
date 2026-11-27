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
    SetItemRef(ref, link, "LeftButton")
end

local function itemLabel(id, bags)
    local name = addon.ItemName(id)
    local color = addon.ItemQualityColor(id)
    local text = color and ("|cff%02x%02x%02x%s|r"):format(color[1]*255, color[2]*255, color[3]*255, name) or name
    local icon = addon.ItemIcon(id)
    if icon then text = ("|T%d:16:16|t %s"):format(icon, text) end
    local count = bags and C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, false)
    if addon.IsReadableNumber(count) and count > 0 then text = text .. "  |cff88cc88In bags|r" end
    return text
end

local function itemRows(menu, items, bags, pending, first, last)
    for index = first or 1, last or #items do
        local id = items[index]
        local row = menu:CreateButton(itemLabel(id, bags), function() showLink("item", id, addon.ItemName(id)) end)
        row:SetTooltip(function(tooltip) tooltip:SetItemByID(id) end)
        if pending and not addon.ItemCached(id) then
            pending[id] = row
        end
    end
end

local lootSections = {
    {"other", "Other recorded drops", "Players looted these items from this NPC. They may also drop elsewhere."},
    {"encounter", "Encounter rolls", "Players rolled on these items during this encounter."},
    {"guide", "Guide-listed drops", "Forever dungeon guides list these items. A matching player drop is unverified."},
}

function UI:Boss(owner, boss)
    local pending = {}
    local openMenu = menuAt(owner, boss.name, function(menu)
        if boss.event then menu:CreateTitle(boss.event .. " event") end
        if #boss.loot == 0 then menu:CreateTitle("No documented drops") end
        local parent, first = menu, 1
        for _, section in ipairs(lootSections) do
            local start = boss.lootSections and boss.lootSections[section[1]]
            if start then
                itemRows(parent, boss.loot, false, pending, first, start-1)
                parent, first = menu:CreateButton(section[2]), start
                parent:SetScrollMode(320)
                parent:SetTooltip(function(tooltip) tooltip:SetText(section[3], nil, nil, nil, nil, true) end)
            end
        end
        itemRows(parent, boss.loot, false, pending, first)
    end)
    if openMenu and next(pending) then
        local loot = {menu=openMenu, rows=pending}
        self.openLoot = loot
        openMenu:SetClosedCallback(function() if self.openLoot == loot then self.openLoot = nil end end)
        for id in pairs(pending) do addon.RequestItem(id) end
    end
end

function UI:ItemLoaded(id, success)
    local loot = self.openLoot
    local row = loot and loot.rows[id]
    if not row then return end
    loot.rows[id] = nil
    if not success then return end
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
            menu:CreateButton(boss.name, function()
                C_Timer.After(0, function()
                    if addon.DungeonMap.dungeon == dungeon then self:Boss(addon.DungeonMap.frame, boss) end
                end)
            end)
        end
    end)
end

function UI:Keys(menu, dungeon)
    itemRows(menu, dungeon.keys, true)
end

local function price(lesson)
    if lesson.cost == nil then return "Price unknown" end
    if lesson.cost == 0 then return "Free" end
    if lesson.petPoints then return (TRAINING_POINTS_ABBREV or "%s training points"):format(lesson.cost) end
    return GetMoneyString(lesson.cost, true)
end

local function lessonRows(menu, lessons)
    for _, lesson in ipairs(lessons) do
        local name = lesson.name
        if lesson.rank and lesson.rank ~= "" then name = name .. " (" .. lesson.rank .. ")" end
        local costText = price(lesson)
        local text = name .. "   " .. costText
        if lesson.source == "Classic reference" then text = text .. "  |cff999999Classic|r" end
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
        if #lessons == 0 then menu:CreateTitle("Visit this trainer to record their lessons.") return end
        local groups = {current={}, later={}, learned={}}
        for _, lesson in ipairs(lessons) do
            local group, status = addon.Trainers:LessonState(lesson)
            lesson.statusText = status
            local list = groups[group or "current"]
            list[#list + 1] = lesson
        end
        menu:CreateDivider()
        lessonRows(menu, groups.current)
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

function UI:Directions(owner, entries)
    menuAt(owner, "Dungeon entrance", function(menu)
        local counts = {}
        for _, entry in ipairs(entries) do
            if entry.category == "dungeon" then counts[entry.title] = (counts[entry.title] or 0) + 1 end
        end
        for _, entry in ipairs(entries) do
            if entry.category == "dungeon" and not addon.Navigation:IsDestination(entry.point, entry.source.id) then
                local label
                if counts[entry.title] > 1 then
                    local point = entry.point
                    label = ("Show path to %s · %.1f, %.1f"):format(entry.title, point.x * 100, point.y * 100)
                end
                self:Route(menu, entry, label)
            end
        end
        if addon.Navigation:IsActive() then
            stopDirections(menu)
        end
    end)
end

function UI:ShowLocation(entry)
    addon.DungeonMap:Close()
    self.map:SetMapID(entry.mapID)
    self.map:PanTo(entry.x, entry.y)
    addon.FocusLocation(entry)
end

function UI:EntranceMenu(menu, dungeon)
    local doors = addon.DungeonEntrances(dungeon, addon.DungeonMap.entrance, self.map:GetMapID())
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
            tooltip:AddLine(addon.Quests:Style(state, role).label)
            if entry then tooltip:AddLine((entry.contact or entry.subtitle) .. " · " .. addon.ZoneName(entry.mapID))
            else tooltip:AddLine(role == "turnin" and "Turn-in location unknown" or "Start location unknown") end
            addon.Quests:AddObjectives(tooltip, id)
        end)
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
        for _, entry in ipairs(entries) do
            local name = entry.title
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
                tooltip:AddLine(("%.1f, %.1f"):format(entry.x*100, entry.y*100))
            end)
        end
    end)
end

function UI:Search(query, results)
    menuAt(self.map, "Dungeons", function(menu)
        local entries = results or addon.Entries(self.map:GetMapID(), true, query)
        if #entries == 0 then menu:CreateTitle("No matching dungeons, bosses or items") end
        for _, entry in ipairs(entries) do
            local label = entry.bossIndex and (entry.title .. " · " .. entry.subtitle) or entry.title
            menu:CreateButton(label, function()
                C_Timer.After(0, function() if self.map:IsShown() then self:Pick(self.map, entry) end end)
            end)
        end
    end)
end

function UI:Attach(map)
    self.map = map
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, menu)
            menu:CreateDivider()
            local function category(parent, id, name)
                parent:CreateCheckbox(name, function() return addon.CategoryEnabled(id) end, function()
                    addon.settings.filters[id] = not addon.CategoryEnabled(id)
                    addon.RefreshMap()
                end)
            end
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
