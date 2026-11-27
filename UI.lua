local _, addon = ...
local UI = {}
addon.UI = UI

local data = addon.Data
local TEXT = { .94, .88, .75 }
local MUTED = { .72, .76, .83 }

-- Widgets --------------------------------------------------------------------

local function surface(frame)
    local edge = frame:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(.42, .33, .21, .98)
    local fill = frame:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(.055, .067, .09, .97)
    frame:EnableMouse(true)
end

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

local function checkbox(parent, text, color, callback)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    local description = label(check)
    description:SetPoint("LEFT", check, "RIGHT", 2, 1)
    description:SetText(text)
    description:SetTextColor(unpack(color))
    check.label, check.color = description, color
    check:SetScript("OnClick", callback)
    return check
end

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

-- The strata steps above another frame's, so panels draw over the map whether it
-- is windowed or maximised.
local function strataAbove(frame, steps)
    local current = frame:GetFrameStrata()
    for index, name in ipairs(STRATA) do
        if name == current then
            return STRATA[math.min(index + steps, #STRATA)]
        end
    end
    return STRATA[4 + steps]
end

local function hideOwnedTooltip(owner)
    if GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
    end
end

-- A virtual scrolling list. describe(entry) returns title, subtitle, color, icon;
-- handlers holds optional click(entry, mouseButton) and enter(row, entry).
local function newList(parent, rowHeight, describe, handlers)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local rows = {}
    local entries = {}

    local function createRow()
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(rowHeight)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(.84, .66, .37, .14)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowHeight - 5, rowHeight - 5)
        row.icon:SetPoint("LEFT", 3, 0)
        row.title = singleLine(label(row, "GameFontNormal"))
        row.title:SetPoint("RIGHT", -5, 0)
        row.subtitle = singleLine(label(row))
        row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
        row.subtitle:SetPoint("RIGHT", -5, 0)
        row:SetScript("OnClick", function(self, mouseButton)
            if handlers.click then
                handlers.click(self.entry, mouseButton)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if handlers.enter then
                handlers.enter(self, self.entry)
            end
        end)
        row:SetScript("OnLeave", hideOwnedTooltip)
        return row
    end

    local function fill(row, entry)
        local title, subtitle, color, icon = describe(entry)
        row.entry = entry
        row.icon:SetTexture(icon)
        row.icon:SetShown(icon ~= nil)
        row.title:ClearAllPoints()
        if subtitle then
            row.title:SetPoint("TOPLEFT", icon and rowHeight or 5, -3)
        else
            row.title:SetPoint("LEFT", icon and rowHeight or 5, 0)
        end
        row.title:SetPoint("RIGHT", -5, 0)
        row.title:SetText(title)
        row.title:SetTextColor(unpack(color or TEXT))
        row.subtitle:SetText(subtitle or "")
        row.subtitle:SetShown(subtitle ~= nil)
    end

    local function drawRows()
        local first = math.floor(scroll:GetVerticalScroll() / rowHeight) + 1
        local visible = math.ceil(scroll:GetHeight() / rowHeight) + 2
        local count = math.max(0, math.min(visible, #entries - first + 1))
        for slot = 1, count do
            local index = first + slot - 1
            local row = rows[slot]
            if not row then
                row = createRow()
                rows[slot] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * rowHeight)
            fill(row, entries[index])
            row:Show()
        end
        for slot = count + 1, #rows do
            rows[slot].entry = nil
            rows[slot]:Hide()
        end
    end

    scroll:HookScript("OnVerticalScroll", drawRows)
    scroll:HookScript("OnSizeChanged", function(_, width)
        child:SetWidth(math.max(1, width))
        drawRows()
    end)

    -- keepScroll holds the scroll position, as far as the new entries allow.
    function scroll:SetEntries(values, keepScroll)
        entries = values
        child:SetWidth(math.max(1, self:GetWidth()))
        child:SetHeight(math.max(1, #entries * rowHeight))
        local limit = math.max(0, #entries * rowHeight - self:GetHeight())
        self:SetVerticalScroll(keepScroll and math.min(self:GetVerticalScroll(), limit) or 0)
        drawRows()
    end

    -- Redraws the visible rows in place, keeping the scroll position.
    scroll.Refresh = drawRows

    function scroll:GetEntries()
        return entries
    end

    return scroll
end

-- Presentation ---------------------------------------------------------------

local function describeRecord(entry)
    local _, color, subtitle = addon.Presentation(entry)
    if entry.category ~= "quest" then
        color = nil
    end
    return entry.title, subtitle, color
end

local function describeItem(itemID)
    return addon.ItemName(itemID), nil, addon.ItemQualityColor(itemID), addon.ItemIcon(itemID)
end

local function describeQuest(questID)
    local quest = data.quests[questID]
    local state = addon.Quests:State(questID)
    local style = addon.Quests:Style(state, "start")
    local parts = {}
    if quest.level then
        parts[#parts + 1] = "Level " .. quest.level
    end
    parts[#parts + 1] = style.label
    local start = addon.QuestStart(questID)
    parts[#parts + 1] = start and ("Starts in " .. addon.ZoneName(start.mapID)) or "No start location recorded"
    return quest.name, table.concat(parts, " · "), style.color
end

local function itemTooltip(row, itemID)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(itemID)
    else
        GameTooltip:SetHyperlink("item:" .. itemID)
    end
    GameTooltip:AddLine("Shift-click to link · Ctrl-click to preview", .6, .64, .71)
    GameTooltip:Show()
end

local function openItem(itemID)
    local link, itemString = addon.ItemLink(itemID)
    if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick
        and HandleModifiedItemClick(link) then
        return
    end
    if type(SetItemRef) == "function" then
        SetItemRef(itemString, link or addon.ItemName(itemID), "LeftButton")
    end
end

local function questTooltip(row, questID)
    local quest = data.quests[questID]
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(quest.name)
    local requirement = addon.Quests:Requirement(questID)
    if requirement then
        GameTooltip:AddLine(requirement, MUTED[1], MUTED[2], MUTED[3])
    end
    if addon.QuestStart(questID) then
        GameTooltip:AddLine("Click to show where it starts", 1, .82, .45)
    end
    GameTooltip:Show()
end

-- Dungeon detail -------------------------------------------------------------

local function resizedDetail(frame)
    frame:SetSize(math.min(750, UIParent:GetWidth() - 38), math.min(510, UIParent:GetHeight() - 34))
    frame.floorMap:SetWidth(math.floor((frame:GetWidth() - 52) * .58))
end

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

local function createDetail(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
    frame:SetClampedToScreen(true)
    surface(frame)
    frame:Hide()

    frame.title = label(frame, "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 17, -14)
    frame.title:SetPoint("RIGHT", -36, 0)
    singleLine(frame.title)
    frame.facts = singleLine(label(frame))
    frame.facts:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.facts:SetPoint("RIGHT", -17, 0)
    frame.note = singleLine(label(frame, "GameFontDisableSmall"))
    frame.note:SetPoint("TOPLEFT", frame.facts, "BOTTOMLEFT", 0, -3)
    frame.note:SetPoint("RIGHT", -17, 0)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:HookScript("OnHide", hideOwnedTooltip)

    frame.floorMap = addon.DungeonMap.Create(frame)
    frame.floorMap:SetPoint("TOPLEFT", 14, -72)
    frame.floorMap:SetPoint("BOTTOMLEFT", 14, 70)

    frame.lootTab = button(frame, "Loot", 70, function() UI:ShowTab("loot") end)
    frame.lootTab:SetPoint("TOPLEFT", frame.floorMap, "TOPRIGHT", 18, 0)
    frame.questTab = button(frame, "Quests", 70, function() UI:ShowTab("quests") end)
    frame.questTab:SetPoint("LEFT", frame.lootTab, "RIGHT", 4, 0)

    frame.bossBack = button(frame, "<", 27, function() UI:ChangeBoss(-1) end)
    frame.bossBack:SetPoint("TOPLEFT", frame.lootTab, "BOTTOMLEFT", 0, -8)
    frame.bossNext = button(frame, ">", 27, function() UI:ChangeBoss(1) end)
    frame.bossNext:SetPoint("TOP", frame.bossBack, "TOP")
    frame.bossNext:SetPoint("RIGHT", -17, 0)
    frame.bossTitle = singleLine(label(frame))
    frame.bossTitle:SetPoint("LEFT", frame.bossBack, "RIGHT", 6, 0)
    frame.bossTitle:SetPoint("RIGHT", frame.bossNext, "LEFT", -4, 0)

    frame.loot = newList(frame, 23, describeItem, {
        click = openItem,
        enter = itemTooltip,
    })
    frame.loot:SetPoint("TOPLEFT", frame.bossBack, "BOTTOMLEFT", 0, -8)
    frame.loot:SetPoint("BOTTOMRIGHT", -36, 72)

    frame.quests = newList(frame, 34, describeQuest, {
        click = function(questID) UI:ShowQuestStart(questID) end,
        enter = questTooltip,
    })
    frame.quests:SetPoint("TOPLEFT", frame.lootTab, "BOTTOMLEFT", 0, -8)
    frame.quests:SetPoint("BOTTOMRIGHT", -36, 72)

    frame.empty = label(frame)
    frame.empty:SetPoint("TOPLEFT", frame.loot)

    frame.route = button(frame, "Guide me", 96, function()
        local entrance = frame.entrances[frame.entranceIndex]
        if entrance then
            addon.Navigation:Start(frame.dungeon.name .. " entrance", entrance)
        end
    end)
    frame.route:SetPoint("BOTTOMLEFT", 15, 27)
    frame.stop = button(frame, "Stop", 52, function() addon.Navigation:Stop() end)
    frame.stop:SetPoint("LEFT", frame.route, "RIGHT", 6, 0)
    frame.nextEntrance = button(frame, "Next entrance", 111, function()
        UI:SetEntrance(frame.entranceIndex % #frame.entrances + 1)
    end)
    frame.nextEntrance:SetPoint("LEFT", frame.stop, "RIGHT", 6, 0)
    frame.entranceText = singleLine(label(frame))
    frame.entranceText:SetPoint("LEFT", frame.nextEntrance, "RIGHT", 8, 0)
    frame.entranceText:SetPoint("RIGHT", -14, 0)
    frame.routeStatus = label(frame)
    frame.routeStatus:SetPoint("BOTTOMLEFT", 16, 10)
    frame.routeStatus:SetPoint("RIGHT", -14, 0)
    frame.routeStatus:SetTextColor(unpack(MUTED))
    frame.routeStatus:SetText(addon.Navigation:GetStatus())
    resizedDetail(frame)
    return frame
end

function UI:SetEntrance(index)
    local frame = self.detail
    frame.entranceIndex = index
    local entrance = frame.entrances[index]
    frame.route:SetEnabled(entrance ~= nil)
    frame.nextEntrance:SetEnabled(#frame.entrances > 1)
    if entrance then
        local zone = addon.ZoneName(entrance.mapID)
        frame.entranceText:SetText(entrance.label and (entrance.label .. " · " .. zone) or zone)
    else
        frame.entranceText:SetText("Entrance coordinates unavailable")
    end
end

function UI:ChangeBoss(delta)
    local frame = self.detail
    local bosses = frame.dungeon.bosses
    local boss
    if #bosses > 0 then
        frame.bossIndex = (frame.bossIndex - 1 + delta) % #bosses + 1
        boss = bosses[frame.bossIndex]
    end
    hideOwnedTooltip(frame)
    frame.bossTitle:SetText(boss and ("%s (%d/%d)"):format(boss.name, frame.bossIndex, #bosses) or "No boss records")
    frame.bossBack:SetEnabled(#bosses > 1)
    frame.bossNext:SetEnabled(#bosses > 1)
    local loot = boss and boss.loot or {}
    for _, itemID in ipairs(loot) do
        addon.RequestItem(itemID)
    end
    frame.loot:SetEntries(loot)
    self:UpdateEmpty()
end

function UI:UpdateEmpty()
    local frame = self.detail
    if frame.tab == "loot" then
        frame.empty:SetText("No loot records for this boss.")
        frame.empty:SetShown(#frame.loot:GetEntries() == 0)
    else
        frame.empty:SetText("No quests recorded for this dungeon.")
        frame.empty:SetShown(#frame.quests:GetEntries() == 0)
    end
end

function UI:ShowTab(tab)
    local frame = self.detail
    local loot = tab == "loot"
    frame.tab = tab
    frame.lootTab:SetEnabled(not loot)
    frame.questTab:SetEnabled(loot)
    for _, widget in ipairs({ frame.bossBack, frame.bossNext, frame.bossTitle, frame.loot }) do
        widget:SetShown(loot)
    end
    frame.quests:SetShown(not loot)
    frame.empty:ClearAllPoints()
    frame.empty:SetPoint("TOPLEFT", loot and frame.loot or frame.quests)
    hideOwnedTooltip(frame)
    if loot then
        frame.loot:Refresh()
    else
        frame.quests:SetEntries(frame.dungeon.quests)
    end
    self:UpdateEmpty()
end

function UI:OpenDungeon(entry)
    if not self.detail then
        self.detail = createDetail(self.map)
    end
    local frame = self.detail
    local dungeon = entry.source
    frame.dungeon = dungeon
    frame.entrances = {}
    local faction = UnitFactionGroup("player")
    local selectedIndex = 1
    for _, entrance in ipairs(dungeon.entrances) do
        if addon.FactionAllowed(entrance, faction) then
            frame.entrances[#frame.entrances + 1] = entrance
            if entrance == entry.point then
                selectedIndex = #frame.entrances
            end
        end
    end
    frame.title:SetText(dungeon.name)
    frame.facts:SetText(dungeonFacts(dungeon))
    frame.note:SetText(dungeon.note or "")
    frame.bossIndex = 1
    resizedDetail(frame)
    self:Layer()
    frame:Show()
    frame.floorMap:SetDungeon(dungeon)
    self:ChangeBoss(0)
    self:ShowTab("loot")
    self:SetEntrance(selectedIndex)
end

function UI:ShowQuestStart(questID)
    local start = addon.QuestStart(questID)
    if not start then
        return
    end
    self.detail:Hide()
    if self.map:GetMapID() ~= start.mapID then
        self.map:SetMapID(start.mapID)
    end
    self:Select(start)
end

-- Called when the client finishes loading an item's data.
function UI:OnItemInfo(itemID)
    local frame = self.detail
    if not frame or not frame:IsShown() then
        return
    end
    local function contains(list)
        for _, candidate in ipairs(list) do
            if candidate == itemID then
                return true
            end
        end
    end
    if contains(frame.loot:GetEntries()) then
        frame.loot:Refresh()
    end
    if contains(frame.dungeon.keys) then
        frame.facts:SetText(dungeonFacts(frame.dungeon))
    end
end

-- Sidebar --------------------------------------------------------------------

local function guideName(entry)
    if entry.category == "dungeon" then
        return entry.title .. " entrance"
    end
    return entry.title
end

function UI:Select(entry)
    if entry.category == "dungeon" and entry.source and entry.source.bosses then
        self:OpenDungeon(entry)
    end
    self.selected = entry.x and entry or nil
    self:UpdateSelection()
    addon.HighlightPin(self.selected)
end

function UI:UpdateSelection()
    local panel = self.sidebar
    local entry = self.selected
    if entry then
        panel.selection:SetText(("%s · %.1f, %.1f"):format(entry.title, 100 * entry.x, 100 * entry.y))
    else
        panel.selection:SetText(panel.summary or "")
    end
    panel.guide:SetEnabled(entry ~= nil)
end

function UI:Guide(entry)
    entry = entry or self.selected
    if entry and entry.point then
        addon.Navigation:Start(guideName(entry), entry.point)
    end
end

function UI:SyncSettings()
    local panel = self.sidebar
    local settings = addon.settings
    for _, check in ipairs(panel.checks) do
        check:SetChecked(addon.CategoryEnabled(check.category))
    end
    panel.allQuests:SetChecked(settings.questMode == "all")
    panel.lowLevel:SetChecked(settings.lowLevelQuests)
    local enabled = settings.questMode ~= "all"
    panel.lowLevel:SetEnabled(enabled)
    panel.lowLevel.label:SetTextColor(unpack(enabled and panel.lowLevel.color or { .45, .45, .45 }))
end

-- Keeps the panels above the map, whose strata changes when it is maximised.
function UI:Layer()
    self.sidebar:SetFrameStrata(strataAbove(self.map, 1))
    self.toggle:SetFrameStrata(strataAbove(self.map, 1))
    if self.detail then
        self.detail:SetFrameStrata(strataAbove(self.map, 2))
    end
end

local function setAtlas(panel, atlas)
    panel.atlas = atlas
    panel.mode:SetText(atlas and "Current map" or "All dungeons")
    for _, check in ipairs(panel.options) do
        check:SetShown(not atlas)
    end
    panel.heading:ClearAllPoints()
    panel.heading:SetPoint("TOPLEFT", 11, atlas and -66 or -130)
end

function UI:Attach(map)
    self.map = map
    local panel = CreateFrame("Frame", nil, map)
    self.sidebar = panel
    panel:SetPoint("TOPLEFT", 13, -60)
    panel:SetPoint("BOTTOMLEFT", 13, 28)
    panel:SetWidth(268)
    surface(panel)
    panel:Hide()
    panel:HookScript("OnHide", function()
        if self.detail then
            self.detail:Hide()
        end
    end)

    local title = label(panel, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -11)
    title:SetText("Aeternum")
    panel.mode = button(panel, "All dungeons", 105, function()
        setAtlas(panel, not panel.atlas)
        addon.RefreshMap()
    end)
    panel.mode:SetPoint("TOPRIGHT", -9, -8)

    panel.search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.search:SetPoint("TOPLEFT", 16, -37)
    panel.search:SetPoint("TOPRIGHT", -13, -37)
    panel.search:SetHeight(22)
    panel.search:SetAutoFocus(false)
    panel.search:SetMaxLetters(70)
    panel.search:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    panel.search:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
    local prompt = label(panel.search)
    prompt:SetPoint("LEFT", 1, 0)
    prompt:SetTextColor(.6, .64, .71)
    prompt:SetText("Search")
    panel.search:SetScript("OnTextChanged", function(edit)
        prompt:SetShown(edit:GetText() == "")
        addon.RefreshMap()
    end)

    panel.checks, panel.options = {}, {}
    for index, category in ipairs(addon.categories) do
        local check = checkbox(panel, category.label, category.color, function(control)
            addon.settings.filters[category.id] = not not control:GetChecked()
            addon.RefreshMap()
        end)
        check.category = category.id
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        check:SetPoint("TOPLEFT", 8 + column * 121, -61 - row * 20)
        panel.checks[#panel.checks + 1] = check
        panel.options[#panel.options + 1] = check
    end
    panel.allQuests = checkbox(panel, "All quests", MUTED, function(control)
        addon.settings.questMode = control:GetChecked() and "all" or "available"
        UI:SyncSettings()
        addon.RefreshMap()
    end)
    panel.allQuests:SetPoint("TOPLEFT", 8, -103)
    panel.lowLevel = checkbox(panel, "Low-level quests", MUTED, function(control)
        addon.settings.lowLevelQuests = not not control:GetChecked()
        addon.RefreshMap()
    end)
    panel.lowLevel:SetPoint("TOPLEFT", 129, -103)
    panel.options[#panel.options + 1] = panel.allQuests
    panel.options[#panel.options + 1] = panel.lowLevel

    panel.heading = singleLine(label(panel, "GameFontNormal"))
    panel.heading:SetPoint("RIGHT", -10, 0)
    panel.list = newList(panel, 34, describeRecord, {
        click = function(entry, mouseButton)
            if mouseButton == "RightButton" then
                UI:Guide(entry)
            else
                UI:Select(entry)
            end
        end,
    })
    panel.list:SetPoint("TOPLEFT", panel.heading, "BOTTOMLEFT", -1, -7)
    panel.list:SetPoint("BOTTOMRIGHT", -30, 62)

    panel.guide = button(panel, "Guide", 58, function() UI:Guide() end)
    panel.guide:SetPoint("BOTTOMRIGHT", -9, 34)
    panel.selection = singleLine(label(panel))
    panel.selection:SetPoint("LEFT", panel, "BOTTOMLEFT", 11, 45)
    panel.selection:SetPoint("RIGHT", panel.guide, "LEFT", -6, 0)
    panel.selection:SetTextColor(unpack(TEXT))

    panel.stop = button(panel, "Stop", 58, function() addon.Navigation:Stop() end)
    panel.stop:SetPoint("BOTTOMRIGHT", -9, 8)
    panel.status = singleLine(label(panel))
    panel.status:SetPoint("LEFT", panel, "BOTTOMLEFT", 11, 19)
    panel.status:SetPoint("RIGHT", panel.stop, "LEFT", -6, 0)
    panel.status:SetTextColor(unpack(MUTED))

    addon.Navigation:AddListener(function(status) UI:OnNavigation(status) end)
    self:OnNavigation(addon.Navigation:GetStatus())
    setAtlas(panel, false)
    self:SyncSettings()
    self:UpdateSelection()

    self.toggle = button(map, "Aeternum", 91, function() UI:Toggle() end)
    self.toggle:SetPoint("TOPLEFT", map, "TOPLEFT", 13, -35)
    self:Layer()

    if addon.settings.panelOpen then
        panel:Show()
    end
end

function UI:OnNavigation(status)
    local active = addon.Navigation:IsActive()
    self.sidebar.status:SetText(status)
    self.sidebar.stop:SetEnabled(active)
    if self.detail then
        self.detail.routeStatus:SetText(status)
        self.detail.stop:SetEnabled(active)
    end
end

function UI:Show()
    addon.settings.panelOpen = true
    self.sidebar:Show()
    addon.RefreshMap()
end

function UI:Hide()
    addon.settings.panelOpen = false
    self.sidebar:Hide()
    addon.RefreshMap()
end

function UI:Toggle()
    if self.sidebar:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function UI:IsOpen()
    return self.sidebar ~= nil and self.sidebar:IsShown()
end

function UI:IsAtlas()
    return self.sidebar.atlas
end

function UI:GetSearch()
    return self.sidebar.search:GetText()
end

-- hidden counts the map locations left off past the pin limit.
function UI:UpdateEntries(entries, mapID, hidden, keepScroll)
    local panel = self.sidebar
    panel.heading:SetText(panel.atlas and "Dungeon atlas" or addon.ZoneName(mapID))
    local summary = #entries == 0 and "No matching records" or ("%d results"):format(#entries)
    if hidden and hidden > 0 then
        summary = ("%s · %d locations not drawn"):format(summary, hidden)
    end
    panel.summary = summary
    if self.selected and self.selected.mapID ~= mapID then
        self.selected = nil
    end
    self:UpdateSelection()
    panel.list:SetEntries(entries, keepScroll)
end

-- Redraws list rows whose quest states may have changed.
function UI:RefreshStates()
    if self.sidebar and self.sidebar:IsVisible() then
        self.sidebar.list:Refresh()
    end
    if self.detail and self.detail:IsVisible() and self.detail.tab == "quests" then
        self.detail.quests:Refresh()
    end
end
