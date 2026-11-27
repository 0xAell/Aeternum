local _, addon = ...
local UI = {}
addon.UI = UI

local function menuAt(owner, title, fill)
    MenuUtil.CreateContextMenu(owner, function(_, menu)
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

function UI:Loot(menu, boss)
    if #boss.loot == 0 then menu:CreateTitle("No recorded drops") end
    for _, id in ipairs(boss.loot) do
        addon.RequestItem(id)
        local name = addon.ItemName(id)
        local color = addon.ItemQualityColor(id)
        local text = color and ("|cff%02x%02x%02x%s|r"):format(color[1]*255, color[2]*255, color[3]*255, name) or name
        local icon = addon.ItemIcon(id)
        if icon then text = ("|T%d:16:16|t %s"):format(icon, text) end
        local row = menu:CreateButton(text, function() showLink("item", id, name) end)
        row:SetTooltip(function(tooltip) tooltip:SetItemByID(id) end)
    end
end

function UI:Boss(owner, boss)
    menuAt(owner, boss.name, function(menu) self:Loot(menu, boss) end)
end

local function price(lesson)
    if lesson.cost == nil then return "Price unknown" end
    if lesson.cost == 0 then return "Free" end
    if lesson.petPoints then return (TRAINING_POINTS_ABBREV or "%s training points"):format(lesson.cost) end
    return GetMoneyString(lesson.cost, true)
end

function UI:Trainer(owner, entry)
    menuAt(owner, entry.title, function(menu)
        local lessons = addon.Trainers:Lessons(entry.source.id)
        menu:CreateTitle(entry.subtitle)
        if #lessons == 0 then menu:CreateTitle("Visit this trainer to record their lessons.") end
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
                tooltip:AddLine(lesson.source .. " · " .. costText, 1, .82, 0)
            end)
        end
        menu:CreateDivider()
        menu:CreateButton("Directions to trainer", function() addon.Navigation:Start(entry.title, entry.point) end)
    end)
end

function UI:Route(menu, entry)
    local option = menu:CreateButton("Show path to " .. entry.title, function()
        addon.Navigation:Start(entry.title .. " entrance", entry.point)
        local overlay = addon.Navigation.overlay
        if not overlay or not overlay:IsVisible() then DEFAULT_CHAT_FRAME:AddMessage(addon.Navigation:GetStatus()) end
    end)
    option:SetTooltip(function(tooltip)
        tooltip:SetText(entry.title)
        tooltip:AddLine(entry.point.waypoints and "Follows recorded approach points on the minimap."
            or "Shows a direct bearing to this entrance on the minimap.", 1, 1, 1, true)
    end)
end

function UI:Directions(owner, entries)
    menuAt(owner, "Dungeon entrance", function(menu)
        for _, entry in ipairs(entries) do
            if entry.category == "dungeon" then self:Route(menu, entry) end
        end
        if addon.Navigation:IsActive() then
            menu:CreateButton("Stop directions", function() addon.Navigation:Stop() end)
        end
    end)
end

function UI:QuestStart(id)
    local start = addon.QuestStart(id)
    if not start then return end
    addon.DungeonMap:Close()
    self.map:SetMapID(start.mapID)
    addon.FocusLocation(start)
end

function UI:QuestMenu(menu, dungeon)
    for _, id in ipairs(dungeon.quests) do
        local quest = addon.Quest(id)
        local row = menu:CreateButton(quest.name, function() self:QuestStart(id) end)
        row:SetTooltip(function(tooltip)
            local start = addon.QuestStart(id)
            tooltip:SetText(quest.name)
            tooltip:AddLine(addon.Quests:Style(addon.Quests:State(id), "start").label)
            tooltip:AddLine(start and ("Start · " .. addon.ZoneName(start.mapID)) or "Start location unknown")
        end)
    end
end

function UI:Pick(owner, entry)
    if entry.category == "dungeon" then
        addon.DungeonMap:Open(entry.source, entry.bossIndex)
        if entry.bossIndex then self:Boss(addon.DungeonMap.frame, entry.source.bosses[entry.bossIndex]) end
    elseif entry.category == "quest" then
        menuAt(owner, entry.title, function(menu)
            local _, _, text = addon.Presentation(entry)
            menu:CreateTitle(text)
            menu:CreateButton("Directions to this location", function()
                addon.Navigation:Start(entry.title, entry.point)
            end)
        end)
    else
        self:Trainer(owner, entry)
    end
end

function UI:PickLocation(owner, entries)
    if #entries == 1 then self:Pick(owner, entries[1]) return end
    menuAt(owner, "At this location", function(menu)
        for _, entry in ipairs(entries) do
            local name = entry.title
            if entry.questID then name = name .. (entry.role == "turnin" and " (turn-in)" or " (start)") end
            menu:CreateButton(name, function()
                C_Timer.After(0, function() if self.map:IsShown() then self:Pick(self.map, entry) end end)
            end)
        end
    end)
end

function UI:Search(query)
    menuAt(self.map, "Dungeons", function(menu)
        local entries = addon.Entries(self.map:GetMapID(), true, query)
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
            if addon.Navigation:IsActive() then
                menu:CreateButton("Stop directions", function() addon.Navigation:Stop() end)
            end
        end)
    end
    map:HookScript("OnShow", function() addon.DungeonMap:OpenInstance() end)
    map:HookScript("OnHide", function() addon.DungeonMap:Close() end)
end
