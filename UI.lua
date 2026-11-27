local _, addon = ...
local UI = {}
addon.UI = UI

local MUTED = { .8, .8, .8 }
local HINT = { 1, .82, 0 }
local newList = addon.CreateGuideList

local function label(parent, template)
    local line = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    line:SetJustifyH("LEFT")
    return line
end

local function singleLine(line)
    line:SetWordWrap(false)
    line:SetMaxLines(1)
    return line
end

local function button(parent, title, width, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 23)
    control:SetText(title)
    control:SetScript("OnClick", callback)
    return control
end

local function hideOwnedTooltip(owner)
    if GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
    end
end

local function startGuidance(name, point)
    addon.Navigation:Start(name, point)
    if not addon.Navigation:IsActive() then
        DEFAULT_CHAT_FRAME:AddMessage(addon.Navigation:GetStatus())
    end
end

-- Presentation ---------------------------------------------------------------

local function describeRecord(entry)
    if entry.itemID then
        return entry.title, entry.subtitle, addon.ItemQualityColor(entry.itemID), addon.ItemIcon(entry.itemID)
    end
    local icon, color, subtitle, dim = addon.Presentation(entry)
    return entry.title, subtitle, color, icon, dim
end

local function describeItem(itemID)
    return addon.ItemName(itemID), nil, addon.ItemQualityColor(itemID), addon.ItemIcon(itemID)
end

local questSubtitles = {}

local function describeQuest(questID)
    local quest = addon.Quest(questID)
    local state = addon.Quests:State(questID)
    local role = (state == "active" or state == "ready") and "turnin" or "start"
    local style = addon.Quests:Style(state, role)
    local cached = questSubtitles[questID]
    if not cached or cached.style ~= style then
        local parts = {}
        if quest.level then
            parts[#parts + 1] = "Level " .. quest.level
        end
        parts[#parts + 1] = style.label
        local start = addon.QuestStart(questID)
        parts[#parts + 1] = start and ("Starts in " .. addon.ZoneName(start.mapID)) or "No start location recorded"
        cached = { style = style, text = table.concat(parts, " · ") }
        questSubtitles[questID] = cached
    end
    local icon, dim = addon.Quests:Icon(state, role)
    return quest.name, cached.text, style.color, icon, dim
end

local function recordTooltip(row, entry)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if entry.itemID then
        GameTooltip:SetItemByID(entry.itemID)
        GameTooltip:AddLine(entry.subtitle, MUTED[1], MUTED[2], MUTED[3], true)
    else
        local _, _, subtitle = addon.Presentation(entry)
        GameTooltip:SetText(entry.title)
        GameTooltip:AddLine(subtitle, MUTED[1], MUTED[2], MUTED[3])
    end
    if entry.questID then
        local requirement = addon.Quests:Requirement(entry.questID)
        if requirement then
            GameTooltip:AddLine(requirement, MUTED[1], MUTED[2], MUTED[3])
        end
    end
    if entry.x then
        GameTooltip:AddLine("Right-click for directions", HINT[1], HINT[2], HINT[3])
    elseif entry.bossIndex then
        GameTooltip:AddLine("View boss loot", HINT[1], HINT[2], HINT[3])
    end
    GameTooltip:Show()
end

local function itemTooltip(row, itemID)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

local function openItem(itemID)
    local link, itemString = addon.ItemLink(itemID)
    -- SetItemRef reads a hyperlink from the text on modified clicks.
    link = link or ("|H%s|h[%s]|h"):format(itemString, addon.ItemName(itemID))
    if IsModifiedClick() and HandleModifiedItemClick(link) then
        return
    end
    SetItemRef(itemString, link, "LeftButton")
end

local function questTooltip(row, questID)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(addon.Quest(questID).name)
    local requirement = addon.Quests:Requirement(questID)
    if requirement then
        GameTooltip:AddLine(requirement, MUTED[1], MUTED[2], MUTED[3])
    end
    if addon.QuestStart(questID) then
        GameTooltip:AddLine("Click to show where it starts", HINT[1], HINT[2], HINT[3])
    end
    GameTooltip:Show()
end

-- Dungeon detail -------------------------------------------------------------

local function dungeonFacts(dungeon)
    local facts = {}
    facts[#facts + 1] = addon.DungeonLevel(dungeon)
    if dungeon.size then
        facts[#facts + 1] = dungeon.size .. " players"
    end
    if #dungeon.keys > 0 then
        local names = {}
        for _, itemID in ipairs(dungeon.keys) do
            names[#names + 1] = addon.ItemName(itemID)
        end
        facts[#facts + 1] = (#names > 1 and "Keys: " or "Key: ") .. table.concat(names, ", ")
    end
    return table.concat(facts, " · ")
end

local function entranceName(point)
    return ("%s · %.1f, %.1f"):format(addon.ZoneName(point.mapID), point.x * 100, point.y * 100)
end

local function createDetail(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    frame.minTabWidth = 54
    frame.tabs = {}
    local previous
    for _, spec in ipairs({ {"map", "Map"}, {"loot", "Loot"}, {"quests", "Quests"} }) do
        local key = spec[1]
        local tab = CreateFrame("Button", nil, frame, "PanelTopTabButtonTemplate")
        tab:SetText(spec[2])
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 5, 0)
        else
            tab:SetPoint("TOPLEFT", 3, 0)
        end
        tab:SetScript("OnClick", function() UI:ShowTab(key) end)
        frame.tabs[key], previous = tab, tab
    end
    frame.back = button(frame, "Back", 60, function() UI:Show(nil, true) end)
    frame.back:SetPoint("TOPRIGHT", -1, -2)

    local info = CreateFrame("Frame", nil, frame)
    info:SetPoint("TOPLEFT", 4, -32)
    info:SetPoint("TOPRIGHT", -4, -32)
    info:SetHeight(19)
    info:EnableMouse(true)
    frame.facts = singleLine(label(info))
    frame.facts:SetAllPoints()
    info:SetScript("OnEnter", function(self)
        local dungeon = frame.dungeon
        if not dungeon then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(dungeon.name)
        GameTooltip:AddLine(dungeonFacts(dungeon), 1, 1, 1, true)
        if dungeon.note then GameTooltip:AddLine(dungeon.note, 1, .82, 0, true) end
        GameTooltip:Show()
    end)
    info:SetScript("OnLeave", hideOwnedTooltip)

    frame.floorMap = addon.DungeonMap.Create(frame)
    frame.floorMap:Hide()
    frame.floorMap:SetPoint("TOPLEFT", 2, -54)
    frame.floorMap:SetPoint("BOTTOMRIGHT", -2, 30)

    frame.boss = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    frame.boss:SetPoint("TOPLEFT", 1, -54)
    frame.boss:SetPoint("TOPRIGHT", -1, -54)
    frame.boss:SetupMenu(function(_, menu)
        menu:SetScrollMode(240)
        for i, boss in ipairs(frame.dungeon and frame.dungeon.bosses or {}) do
            menu:CreateRadio(boss.name, function() return frame.bossIndex == i end, function() UI:SetBoss(i) end)
        end
    end)
    frame.loot = newList(frame, 25, describeItem, { click = openItem, enter = itemTooltip })
    frame.loot:SetPoint("TOPLEFT", frame.boss, "BOTTOMLEFT", 0, -5)
    frame.loot:SetPoint("BOTTOMRIGHT", -1, 31)
    frame.quests = newList(frame, 34, describeQuest, {
        click = function(questID) UI:ShowQuestStart(questID) end,
        enter = questTooltip,
    })
    frame.quests:SetPoint("TOPLEFT", 1, -54)
    frame.quests:SetPoint("BOTTOMRIGHT", -1, 31)
    frame.empty = label(frame, "GameFontDisableSmall")

    frame.route = button(frame, "Guide me", 78, function()
        local entrance = frame.entrances[frame.entranceIndex]
        if entrance then startGuidance(frame.dungeon.name .. " entrance", entrance) end
    end)
    frame.route:SetPoint("BOTTOMRIGHT")
    frame.entranceText = singleLine(label(frame))
    frame.entranceText:SetPoint("LEFT", frame, "BOTTOMLEFT", 3, 12)
    frame.entranceText:SetPoint("RIGHT", frame.route, "LEFT", -5, 0)
    frame.entranceMenu = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    frame.entranceMenu:SetPoint("BOTTOMLEFT")
    frame.entranceMenu:SetPoint("BOTTOMRIGHT", frame.route, "BOTTOMLEFT", -4, 0)
    frame.entranceMenu:SetupMenu(function(_, menu)
        for i, entrance in ipairs(frame.entrances or {}) do
            menu:CreateRadio(entranceName(entrance), function() return frame.entranceIndex == i end,
                function() UI:SetEntrance(i) end)
        end
    end)
    return frame
end

function UI:SetEntrance(index)
    local frame = self.detail
    local entrance = frame.entrances[index]
    frame.entranceIndex = index
    frame.route:SetEnabled(entrance ~= nil)
    local multiple = #frame.entrances > 1
    frame.entranceMenu:SetShown(multiple)
    frame.entranceText:SetShown(not multiple)
    if multiple then
        frame.entranceMenu:OverrideText(entranceName(entrance))
    else
        frame.entranceText:SetText(entrance and (entrance.label or entranceName(entrance)) or "Entrance not recorded")
    end
end

function UI:SetBoss(index)
    local frame = self.detail
    local boss = frame.dungeon.bosses[index]
    frame.bossIndex = index
    frame.boss:OverrideText(boss and boss.name or "No bosses recorded")
    frame.boss:SetEnabled(#frame.dungeon.bosses > 1)
    local loot = boss and boss.loot or {}
    for _, itemID in ipairs(loot) do addon.RequestItem(itemID) end
    frame.loot:SetEntries(loot)
    frame.empty:SetShown(#loot == 0)
end

function UI:ShowTab(tab)
    local frame = self.detail
    frame.tab = tab
    for key, control in pairs(frame.tabs) do
        if key == tab then PanelTemplates_SelectTab(control) else PanelTemplates_DeselectTab(control) end
    end
    if tab == "map" then frame.floorMap:SetDungeon(frame.dungeon) end
    frame.floorMap:SetShown(tab == "map")
    frame.boss:SetShown(tab == "loot")
    frame.loot:SetShown(tab == "loot")
    frame.quests:SetShown(tab == "quests")
    frame.empty:Hide()
    if tab ~= "map" then
        local loot = tab == "loot"
        local list = loot and frame.loot or frame.quests
        frame.empty:ClearAllPoints()
        frame.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -5)
        frame.empty:SetText(loot and "No loot recorded for this boss." or "No quests recorded for this dungeon.")
        if loot then
            self:SetBoss(frame.bossIndex)
        else
            frame.quests:SetEntries(frame.dungeon.quests)
            frame.empty:SetShown(#frame.dungeon.quests == 0)
        end
    end
end

function UI:OpenDungeon(entry)
    self:EnsureWindow()
    if not self.detail then self.detail = createDetail(self.content) end
    local frame, dungeon = self.detail, entry.source
    if not frame:IsShown() then self.fromBrowse = self:IsBrowsing() end
    self.sidebar:Hide()
    frame.floorMap:Hide()
    frame.dungeon, frame.bossIndex, frame.entrances = dungeon, entry.bossIndex or 1, {}
    local faction, mapID = UnitFactionGroup("player"), self.map:GetMapID()
    local preferred, index = entry.point, 1
    for _, entrance in ipairs(dungeon.entrances) do
        if addon.FactionAllowed(entrance, faction) then
            frame.entrances[#frame.entrances + 1] = entrance
            if not preferred and entrance.mapID == mapID then preferred = entrance end
            if entrance == preferred then index = #frame.entrances end
        end
    end
    self.window.TitleText:SetText(dungeon.name)
    frame.back:SetText(self.fromBrowse and "Back" or "Browse")
    frame.facts:SetText(dungeonFacts(dungeon))
    frame:Show()
    if not self:IsOpen() then self:Layer() end
    self.window:Show()
    self:SetEntrance(index)
    self:ShowTab(not entry.bossIndex and addon.DungeonMap.HasFloors(dungeon) and "map" or "loot")
    if entry.itemID then frame.loot:Reveal(entry.itemID) end
    addon.RefreshMap()
end

function UI:ShowQuestStart(questID)
    local start = addon.QuestStart(questID)
    if not start then return end
    self:Show(false)
    self.sidebar.search:SetText("")
    if self.map:GetMapID() ~= start.mapID then self.map:SetMapID(start.mapID) end
    self:Select(start)
end

function UI:OnItemInfo(itemID)
    if self:IsBrowsing() and self:IsAtlas() then
        local list = self.sidebar.list
        for _, row in ipairs(list.rows) do
            if row.entry and row.entry.itemID == itemID then list:Refresh() break end
        end
        return
    end
    local frame = self.detail
    if not frame or not frame:IsVisible() then return end
    if frame.tab == "loot" then
        for _, id in ipairs(frame.loot:GetEntries()) do
            if id == itemID then frame.loot:Refresh() break end
        end
    end
    for _, id in ipairs(frame.dungeon.keys) do
        if id == itemID then frame.facts:SetText(dungeonFacts(frame.dungeon)) break end
    end
end

function UI:Select(entry)
    if entry.category == "dungeon" then self:OpenDungeon(entry) end
    self.selected = entry.x and entry or nil
    self:UpdateSelection()
    addon.HighlightPin(self.selected)
end

function UI:Guide(entry)
    entry = entry or self.selected
    if entry and entry.point then
        local name = entry.category == "dungeon" and (entry.title .. " entrance") or entry.title
        startGuidance(name, entry.point)
    end
end

-- Both dropdowns edit the same preferences. The client owns their lifetime and focus.
local function addFilters(menu)
    menu:CreateCheckbox("Show pins on map", function() return addon.settings.showMapPins end, function()
        addon.settings.showMapPins = not addon.settings.showMapPins
        addon.RefreshMap(true)
    end)
    menu:CreateDivider()
    for _, category in ipairs(addon.categories) do
        local id = category.id
        menu:CreateCheckbox(category.label, function() return addon.CategoryEnabled(id) end, function()
            addon.settings.filters[id] = not addon.CategoryEnabled(id)
            addon.RefreshMap()
        end)
    end
    menu:CreateDivider()
    menu:CreateCheckbox("All quest locations", function() return addon.settings.questMode == "all" end, function()
        addon.settings.questMode = addon.settings.questMode == "all" and "available" or "all"
        addon.RefreshMap()
    end)
    local low = menu:CreateCheckbox("Low-level quests", function() return addon.settings.lowLevelQuests end, function()
        addon.settings.lowLevelQuests = not addon.settings.lowLevelQuests
        addon.RefreshMap()
    end)
    low:SetEnabled(addon.settings.questMode ~= "all")
end

local function createBrowser(content)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetAllPoints()
    panel.atlas = false
    panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    panel.search:SetHeight(22)
    panel.search:SetMaxLetters(70)
    panel.search.Instructions:SetText("Search this map")
    panel.search:HookScript("OnTextChanged", function()
        if not UI:IsBrowsing() or panel.changingScope then return end
        if panel.atlas then
            local mapID = UI.map:GetMapID()
            UI:UpdateEntries(addon.Entries(mapID, true, panel.search:GetText()), mapID, 0)
        else
            addon.RefreshMap()
        end
    end)
    panel.filter = CreateFrame("DropdownButton", nil, panel, "WowStyle1FilterDropdownTemplate")
    panel.filter:SetPoint("TOPRIGHT", -4, -4)
    panel.filter:SetupMenu(function(_, menu) addFilters(menu) end)
    panel.list = newList(panel, 32, describeRecord, {
        click = function(entry, mouseButton)
            if mouseButton == "RightButton" then
                UI:Guide(entry)
            elseif entry.itemID and IsModifiedClick() then
                openItem(entry.itemID)
            else
                UI:Select(entry)
            end
        end,
        enter = function(row, entry)
            recordTooltip(row, entry)
            addon.HighlightPin(entry)
        end,
        leave = function() addon.HighlightPin(UI.selected) end,
    })
    panel.list:SetPoint("TOPLEFT", 0, -33)
    panel.list:SetPoint("BOTTOMRIGHT", 0, 49)
    panel.selection = singleLine(label(panel, "GameFontDisableSmall"))
    panel.selection:SetPoint("BOTTOMLEFT", 3, 28)
    panel.selection:SetPoint("BOTTOMRIGHT", -3, 28)
    panel.mode = button(panel, "All dungeons", 105, function() UI:Show(not panel.atlas) end)
    panel.mode:SetPoint("BOTTOMLEFT")
    panel.guide = button(panel, "Guide", 72, function() UI:Guide() end)
    panel.guide:SetPoint("BOTTOMRIGHT")
    return panel
end

function UI:UpdateSelection()
    local panel, entry = self.sidebar, self.selected
    if not panel then return end
    panel.selection:SetText(entry and ("%s · %.1f, %.1f"):format(entry.title, entry.x * 100, entry.y * 100)
        or panel.summary or "")
    panel.guide:SetShown(entry ~= nil)
    panel.list:SetSelection(entry)
end

function UI:EnsureWindow()
    if self.window then return end
    local window = CreateFrame("Frame", "AeternumGuideFrame", UIParent, "BasicFrameTemplateWithInset")
    self.window = window
    window:Hide()
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:SetDontSavePosition(true)
    window:EnableMouse(true)
    window.TitleText:ClearAllPoints()
    window.TitleText:SetPoint("TOPLEFT", 12, -5)
    window.TitleText:SetPoint("TOPRIGHT", -30, -5)
    window.TitleText:SetWordWrap(false)
    window.CloseButton:SetScript("OnClick", function() self:Hide() end)
    local title = CreateFrame("Frame", nil, window)
    title:SetPoint("TOPLEFT", 3, -1)
    title:SetPoint("TOPRIGHT", -27, -1)
    title:SetHeight(19)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() window:StartMoving() end)
    title:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

    self.content = CreateFrame("Frame", nil, window)
    self.tracking = CreateFrame("Frame", nil, window)
    self.tracking:SetPoint("BOTTOMLEFT", 10, 8)
    self.tracking:SetPoint("BOTTOMRIGHT", -10, 8)
    self.tracking:SetHeight(23)
    self.stop = button(self.tracking, "Stop", 52, function() addon.Navigation:Stop() end)
    self.stop:SetPoint("RIGHT")
    self.status = singleLine(label(self.tracking))
    self.status:SetPoint("LEFT", 2, 0)
    self.status:SetPoint("RIGHT", self.stop, "LEFT", -6, 0)
    self.sidebar = createBrowser(self.content)
    self.sidebar:Hide()
    self:OnNavigation(addon.Navigation:GetStatus())
    if RegisterGameMenuEscHandler then
        RegisterGameMenuEscHandler(GameMenuEscPriority.AddOn, function()
            if not self:IsOpen() then return false end
            if self.detail and self.detail:IsShown() and self.fromBrowse then self:Show(nil, true) else self:Hide() end
            return true
        end)
    else
        table.insert(UISpecialFrames, "AeternumGuideFrame")
    end
    -- The fallback Escape handler and external Hide calls take the same path as Close.
    window:HookScript("OnHide", function()
        window:StopMovingOrSizing()
        self.selected, self.fromBrowse = nil, nil
        self.sidebar:Hide()
        if self.detail then self.detail:Hide() end
        addon.RefreshMap()
    end)
end

function UI:OnNavigation(status)
    if not self.window then return end
    local active = addon.Navigation:IsActive()
    self.status:SetText(active and status or "")
    if active ~= self.trackingActive then
        self.trackingActive = active
        self.tracking:SetShown(active)
        self.content:ClearAllPoints()
        self.content:SetPoint("TOPLEFT", self.window, "TOPLEFT", 10, -27)
        self.content:SetPoint("BOTTOMRIGHT", self.window, "BOTTOMRIGHT", -10, active and 36 or 8)
    end
end

-- Only our own window is anchored. All measurements below are in UIParent units.
function UI:Layer()
    if not self.window then return end
    local map, window = self.map, self.window
    local canvas = map.ScrollContainer or map
    local scale = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetSize()
    local width = math.min(328, screenWidth - 20)
    local left, right = map:GetLeft(), map:GetRight()
    local outsideRight = right and screenWidth - right * scale >= width + 8
    local outsideLeft = left and left * scale >= width + 8
    local height = (outsideRight or outsideLeft) and 382 or 334
    window:SetSize(math.max(1, width), math.max(1, math.min(height, screenHeight - 40)))
    window:ClearAllPoints()
    if outsideRight then
        window:SetPoint("TOPLEFT", map, "TOPRIGHT", 5, -2)
    elseif outsideLeft then
        window:SetPoint("TOPRIGHT", map, "TOPLEFT", -5, -2)
    else
        window:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -8, -40)
    end
    local strata = map:GetFrameStrata()
    window:SetFrameStrata((strata == "FULLSCREEN" or strata == "FULLSCREEN_DIALOG") and "FULLSCREEN_DIALOG" or "DIALOG")
    window:SetFrameLevel(map:GetFrameLevel() + 10)
end

function UI:Attach(map)
    self.map = map
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root)
            local menu = root:CreateButton("Aeternum")
            menu:CreateButton("Browse this map", function() self:Show(false) end)
            menu:CreateButton("Dungeon guide", function() self:Show(true) end)
            menu:CreateDivider()
            addFilters(menu)
            if addon.Navigation:IsActive() then
                menu:CreateDivider()
                menu:CreateButton("Stop guidance", function() addon.Navigation:Stop() end)
            end
        end)
    end
    map:HookScript("OnHide", function() self:Hide() end)
    map:HookScript("OnSizeChanged", function() if self:IsOpen() then self:Layer() end end)
    addon.Navigation:AddListener(function(status) self:OnNavigation(status) end)
end

function UI:Show(atlas, keepScroll)
    self:EnsureWindow()
    local panel = self.sidebar
    if self.detail then self.detail:Hide() end
    if atlas ~= nil and atlas ~= panel.atlas then
        panel.changingScope = true
        local old = panel.search:GetText()
        panel.atlas = atlas
        panel.search:SetText(panel.otherSearch or "")
        panel.otherSearch = old
        panel.changingScope = false
        self.selected = nil
    end
    panel.filter:SetShown(not panel.atlas)
    panel.search:ClearAllPoints()
    panel.search:SetPoint("TOPLEFT", 5, -3)
    if panel.atlas then
        panel.search:SetPoint("TOPRIGHT", -5, -3)
    else
        panel.search:SetPoint("TOPRIGHT", panel.filter, "TOPLEFT", -9, 1)
    end
    panel.search.Instructions:SetText(panel.atlas and "Dungeon, boss or item" or "Search this map")
    panel.mode:SetText(panel.atlas and "Current map" or "All dungeons")
    self.fromBrowse = nil
    if not self:IsOpen() then self:Layer() end
    self.window:Show()
    panel:Show()
    addon.RefreshMap(keepScroll)
end

function UI:Hide()
    if self.window then self.window:Hide() end
end

function UI:IsOpen()
    return self.window ~= nil and self.window:IsShown()
end

function UI:IsBrowsing()
    return self:IsOpen() and self.sidebar:IsShown()
end

function UI:IsAtlas() return self.sidebar and self.sidebar.atlas end
function UI:GetSearch() return self.sidebar.search:GetText() end

function UI:UpdateEntries(entries, mapID, hidden, keepScroll)
    local panel = self.sidebar
    self.window.TitleText:SetText(panel.atlas and "Dungeon guide" or addon.ZoneName(mapID))
    local count = #entries
    panel.summary = count == 0 and "No results" or ("%d %s"):format(count, count == 1 and "result" or "results")
    if hidden > 0 and not panel.atlas then panel.summary = ("%s · %d off map"):format(panel.summary, hidden) end
    if self.selected then
        local selected = self.selected
        self.selected = nil
        for _, entry in ipairs(entries) do
            if entry == selected then
                self.selected = entry
                break
            end
        end
    end
    panel.list:SetEntries(entries, keepScroll)
    self:UpdateSelection()
end

function UI:RefreshStates()
    if self:IsBrowsing() then self.sidebar.list:Refresh() end
    if self:IsOpen() and self.detail and self.detail:IsShown() and self.detail.tab == "quests" then
        self.detail.quests:Refresh()
    end
end
