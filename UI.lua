local _, addon = ...
local UI = {}
addon.UI = UI

local PANEL_WIDTH = 268
local TEXT = { .94, .88, .75 }
local MUTED = { .72, .76, .83 }
local HINT = { 1, .82, .45 }
local DISABLED = { .45, .45, .45 }
local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }

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

local function setCheckEnabled(check, enabled)
    check:SetEnabled(enabled)
    check.label:SetTextColor(unpack(enabled and check.color or DISABLED))
end

local function hideOwnedTooltip(owner)
    if GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
    end
end

-- The strata the given number of steps above a frame's own.
local function strataAbove(frame, steps)
    local current = frame:GetFrameStrata()
    for index, name in ipairs(STRATA) do
        if name == current then
            return STRATA[math.min(index + steps, #STRATA)]
        end
    end
    return STRATA[4 + steps]
end

-- A square letter badge in a category colour, matching the map pins.
local function badge(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    local outline = frame:CreateTexture(nil, "BACKGROUND")
    outline:SetAllPoints()
    outline:SetColorTexture(.06, .07, .1, .95)
    frame.field = frame:CreateTexture(nil, "ARTWORK")
    frame.field:SetPoint("TOPLEFT", 1, -1)
    frame.field:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.letter = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.letter:SetPoint("CENTER", 0, 1)
    frame.letter:SetTextColor(.08, .09, .12)
    return frame
end

local function setBadge(frame, letter, color)
    frame.field:SetColorTexture(color[1], color[2], color[3], .96)
    frame.letter:SetText(letter)
end

-- A virtual list: only the visible rows exist, scrolled with the mouse wheel or
-- a slim scroll bar. describe(entry) returns title, subtitle, title colour, icon,
-- badge letter, and badge colour; handlers may hold click(entry, mouseButton),
-- enter(row, entry) and leave(row, entry).
local function newList(parent, rowHeight, describe, handlers)
    local list = CreateFrame("Frame", nil, parent)
    list:EnableMouseWheel(true)
    list.rows = {}
    local entries, offset = {}, 0

    local bar = CreateFrame("Slider", nil, list)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPRIGHT", 0, -2)
    bar:SetPoint("BOTTOMRIGHT", 0, 2)
    bar:SetValueStep(1)
    bar:SetObeyStepOnDrag(true)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, .05)
    local thumb = bar:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(.84, .66, .37, .55)
    thumb:SetSize(6, 28)
    bar:SetThumbTexture(thumb)
    list.bar = bar

    local function visibleRows()
        return math.max(1, math.floor(list:GetHeight() / rowHeight))
    end

    local function maxOffset()
        return math.max(0, #entries - visibleRows())
    end

    local function createRow(index)
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
        row:SetPoint("RIGHT", bar, "LEFT", -4, 0)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(.84, .66, .37, .14)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowHeight - 6, rowHeight - 6)
        row.icon:SetPoint("LEFT", 3, 0)
        row.badge = badge(row, 16)
        row.badge:SetPoint("LEFT", 4, 0)
        row.title = singleLine(label(row, "GameFontNormal"))
        row.subtitle = singleLine(label(row))
        row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
        row.subtitle:SetPoint("RIGHT", -4, 0)
        row:SetScript("OnClick", function(self, mouseButton)
            if handlers.click and self.entry ~= nil then
                handlers.click(self.entry, mouseButton)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if handlers.enter and self.entry ~= nil then
                handlers.enter(self, self.entry)
            end
        end)
        row:SetScript("OnLeave", function(self)
            hideOwnedTooltip(self)
            if handlers.leave and self.entry ~= nil then
                handlers.leave(self, self.entry)
            end
        end)
        return row
    end

    local function fill(row, entry)
        local title, subtitle, color, icon, letter, letterColor = describe(entry)
        row.entry = entry
        row.icon:SetTexture(icon)
        row.icon:SetShown(icon ~= nil)
        row.badge:SetShown(letter ~= nil)
        if letter then
            setBadge(row.badge, letter, letterColor)
        end
        local indent = (icon or letter) and (rowHeight > 26 and 26 or rowHeight) or 5
        row.title:ClearAllPoints()
        if subtitle then
            row.title:SetPoint("TOPLEFT", indent, -3)
        else
            row.title:SetPoint("LEFT", indent, 0)
        end
        row.title:SetPoint("RIGHT", -4, 0)
        row.title:SetText(title)
        row.title:SetTextColor(unpack(color or TEXT))
        row.subtitle:SetText(subtitle or "")
        row.subtitle:SetShown(subtitle ~= nil)
    end

    local function draw()
        local count = visibleRows()
        for index = 1, math.max(count, #list.rows) do
            local row = list.rows[index]
            local entry = index <= count and entries[offset + index]
            if entry ~= nil and entry ~= false then
                if not row then
                    row = createRow(index)
                    list.rows[index] = row
                end
                fill(row, entry)
                row:Show()
            elseif row then
                row.entry = nil
                row:Hide()
            end
        end
        bar:SetShown(maxOffset() > 0)
    end

    -- Narrowing the range clamps the slider's value and fires OnValueChanged,
    -- which must not move the list.
    local updating = false
    local function updateBar()
        updating = true
        bar:SetMinMaxValues(0, maxOffset())
        bar:SetValue(offset)
        updating = false
    end

    bar:SetScript("OnValueChanged", function(_, value)
        if updating then
            return
        end
        local target = math.min(math.max(0, math.floor(value + .5)), maxOffset())
        if target ~= offset then
            offset = target
            draw()
        end
    end)
    list:SetScript("OnMouseWheel", function(_, delta)
        bar:SetValue(offset - delta * 3)
    end)
    list:SetScript("OnSizeChanged", function()
        offset = math.min(offset, maxOffset())
        updateBar()
        draw()
    end)

    -- keepScroll holds the position, as far as the new entries allow.
    function list:SetEntries(values, keepScroll)
        entries = values
        offset = keepScroll and math.min(offset, maxOffset()) or 0
        updateBar()
        draw()
    end

    function list:GetEntries()
        return entries
    end

    function list:GetOffset()
        return offset
    end

    function list:SetOffset(value)
        bar:SetValue(value)
    end

    -- Redraws the visible rows in place.
    list.Refresh = draw

    return list
end

-- Presentation ---------------------------------------------------------------

local function describeRecord(entry)
    local letter, color, subtitle = addon.Presentation(entry)
    local titleColor = entry.category == "quest" and color or nil
    return entry.title, subtitle, titleColor, nil, letter, color
end

local function describeItem(itemID)
    return addon.ItemName(itemID), nil, addon.ItemQualityColor(itemID), addon.ItemIcon(itemID)
end

local questSubtitles = {}

local function describeQuest(questID)
    local quest = addon.Quest(questID)
    local style = addon.Quests:Style(addon.Quests:State(questID), "start")
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
    return quest.name, cached.text, style.color
end

local function recordTooltip(row, entry)
    local _, _, subtitle = addon.Presentation(entry)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.title)
    GameTooltip:AddLine(subtitle, MUTED[1], MUTED[2], MUTED[3])
    if entry.questID then
        local requirement = addon.Quests:Requirement(entry.questID)
        if requirement then
            GameTooltip:AddLine(requirement, MUTED[1], MUTED[2], MUTED[3])
        end
    end
    if entry.x then
        GameTooltip:AddLine("Right-click to guide the minimap arrow here", HINT[1], HINT[2], HINT[3])
    end
    GameTooltip:Show()
end

local function itemTooltip(row, itemID)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:AddLine("Shift-click to link · Ctrl-click to preview", .6, .64, .71)
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

local function createDetail(map)
    local frame = CreateFrame("Frame", "AeternumDungeonFrame", UIParent)
    frame:SetPoint("CENTER", map.ScrollContainer or map, "CENTER", 0, 0)
    frame:SetClampedToScreen(true)
    surface(frame)
    frame:Hide()
    -- Escape closes this panel first and leaves the map open. Blizzard closes
    -- its windows at a later priority (CloseAllWindows at AddOnPost).
    if RegisterGameMenuEscHandler then
        RegisterGameMenuEscHandler(GameMenuEscPriority.AddOn, function()
            if frame:IsShown() then
                frame:Hide()
                return true
            end
            return false
        end)
    else
        table.insert(UISpecialFrames, "AeternumDungeonFrame")
    end

    frame.title = singleLine(label(frame, "GameFontNormalLarge"))
    frame.title:SetPoint("TOPLEFT", 17, -14)
    frame.title:SetPoint("RIGHT", -36, 0)
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

    frame.loot = newList(frame, 24, describeItem, { click = openItem, enter = itemTooltip })
    frame.loot:SetPoint("TOPLEFT", frame.bossBack, "BOTTOMLEFT", 0, -8)
    frame.loot:SetPoint("BOTTOMRIGHT", -17, 72)

    frame.quests = newList(frame, 34, describeQuest, {
        click = function(questID) UI:ShowQuestStart(questID) end,
        enter = questTooltip,
    })
    frame.quests:SetPoint("TOPLEFT", frame.lootTab, "BOTTOMLEFT", 0, -8)
    frame.quests:SetPoint("BOTTOMRIGHT", -17, 72)

    frame.empty = label(frame)

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
    frame.routeStatus = singleLine(label(frame))
    frame.routeStatus:SetPoint("BOTTOMLEFT", 16, 10)
    frame.routeStatus:SetPoint("RIGHT", -14, 0)
    frame.routeStatus:SetTextColor(unpack(MUTED))
    return frame
end

local function sizeDetail(frame)
    frame:SetSize(math.min(750, UIParent:GetWidth() - 38), math.min(510, UIParent:GetHeight() - 34))
    frame.floorMap:SetWidth(math.floor((frame:GetWidth() - 52) * .58))
end

function UI:SetEntrance(index)
    local frame = self.detail
    frame.entranceIndex = index
    local entrance = frame.entrances[index]
    frame.route:SetEnabled(entrance ~= nil)
    frame.nextEntrance:SetShown(#frame.entrances > 1)
    if entrance then
        local zone = addon.ZoneName(entrance.mapID)
        frame.entranceText:SetText(entrance.label and (entrance.label .. " · " .. zone) or zone)
    else
        frame.entranceText:SetText("Entrance location not recorded")
    end
end

function UI:ChangeBoss(delta)
    local frame = self.detail
    local bosses = frame.dungeon.bosses
    frame.bossIndex = (frame.bossIndex - 1 + delta) % #bosses + 1
    local boss = bosses[frame.bossIndex]
    hideOwnedTooltip(frame)
    frame.bossTitle:SetText(("%s (%d/%d)"):format(boss.name, frame.bossIndex, #bosses))
    frame.bossBack:SetEnabled(#bosses > 1)
    frame.bossNext:SetEnabled(#bosses > 1)
    for _, itemID in ipairs(boss.loot) do
        addon.RequestItem(itemID)
    end
    frame.loot:SetEntries(boss.loot)
    self:UpdateEmpty()
end

function UI:UpdateEmpty()
    local frame = self.detail
    local loot = frame.tab == "loot"
    local list = loot and frame.loot or frame.quests
    frame.empty:ClearAllPoints()
    frame.empty:SetPoint("TOPLEFT", list, "TOPLEFT", 5, -5)
    frame.empty:SetText(loot and "No loot recorded for this boss." or "No quests recorded for this dungeon.")
    frame.empty:SetShown(#list:GetEntries() == 0)
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
        self:OnNavigation(addon.Navigation:GetStatus())
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
    sizeDetail(frame)
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
    if entry.category == "dungeon" then
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
    setCheckEnabled(panel.lowLevel, settings.questMode ~= "all")
end

local function setAtlas(panel, atlas)
    panel.atlas = atlas
    panel.mode:SetText(atlas and "Current map" or "All dungeons")
    for _, check in ipairs(panel.options) do
        check:SetShown(not atlas)
    end
    panel.heading:ClearAllPoints()
    panel.heading:SetPoint("TOPLEFT", 11, atlas and -68 or -132)
    panel.heading:SetPoint("RIGHT", -10, 0)
end

-- Places the sidebar beside the map when the screen has room, otherwise inside
-- the right edge of the map canvas, and keeps both panels above the map, whose
-- strata changes when it is maximised.
function UI:Layer()
    local map, panel = self.map, self.sidebar
    local canvas = map.ScrollContainer or map
    local scale = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right = map:GetRight()
    local room = right and UIParent:GetWidth() - right * scale or 0
    local outside = room >= PANEL_WIDTH + 8
    if self.docked ~= outside then
        self.docked = outside
        panel:ClearAllPoints()
        if outside then
            panel:SetPoint("TOPLEFT", map, "TOPRIGHT", 4, 0)
            panel:SetPoint("BOTTOMLEFT", map, "BOTTOMRIGHT", 4, 0)
        else
            panel:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -6, -34)
            panel:SetPoint("BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -6, 34)
        end
    end
    panel:SetFrameStrata(strataAbove(map, 1))
    self.toggle:SetFrameStrata(strataAbove(map, 1))
    if self.detail then
        self.detail:SetFrameStrata(strataAbove(map, 2))
    end
end

function UI:Attach(map)
    self.map = map
    local panel = CreateFrame("Frame", nil, UIParent)
    self.sidebar = panel
    panel:SetWidth(PANEL_WIDTH)
    panel:SetClampedToScreen(true)
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

    panel.search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    panel.search:SetPoint("TOPLEFT", 16, -38)
    panel.search:SetPoint("TOPRIGHT", -11, -38)
    panel.search:SetHeight(20)
    panel.search:SetMaxLetters(70)
    panel.search.Instructions:SetText("Search names and places")
    panel.search:HookScript("OnTextChanged", function() addon.RefreshMap() end)

    panel.checks, panel.options = {}, {}
    for index, category in ipairs(addon.categories) do
        local check = checkbox(panel, category.label, category.color, function(control)
            addon.settings.filters[category.id] = not not control:GetChecked()
            addon.RefreshMap()
        end)
        check.category = category.id
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        check:SetPoint("TOPLEFT", 8 + column * 121, -63 - row * 20)
        panel.checks[#panel.checks + 1] = check
        panel.options[#panel.options + 1] = check
    end
    panel.allQuests = checkbox(panel, "All quests", MUTED, function(control)
        addon.settings.questMode = control:GetChecked() and "all" or "available"
        UI:SyncSettings()
        addon.RefreshMap()
    end)
    panel.allQuests:SetPoint("TOPLEFT", 8, -105)
    panel.lowLevel = checkbox(panel, "Low-level quests", MUTED, function(control)
        addon.settings.lowLevelQuests = not not control:GetChecked()
        addon.RefreshMap()
    end)
    panel.lowLevel:SetPoint("TOPLEFT", 129, -105)
    panel.options[#panel.options + 1] = panel.allQuests
    panel.options[#panel.options + 1] = panel.lowLevel

    panel.heading = singleLine(label(panel, "GameFontNormal"))
    panel.list = newList(panel, 34, describeRecord, {
        click = function(entry, mouseButton)
            if mouseButton == "RightButton" then
                UI:Guide(entry)
            else
                UI:Select(entry)
            end
        end,
        enter = function(row, entry)
            recordTooltip(row, entry)
            addon.HighlightPin(entry)
        end,
        leave = function()
            addon.HighlightPin(UI.selected)
        end,
    })
    panel.list:SetPoint("TOPLEFT", panel.heading, "BOTTOMLEFT", -3, -6)
    panel.list:SetPoint("BOTTOMRIGHT", -6, 62)

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

    self.toggle = button(map, "Aeternum", 91, function() UI:Toggle() end)
    self.toggle:SetPoint("TOPRIGHT", map.ScrollContainer or map, "TOPRIGHT", -6, -6)

    -- The sidebar sits outside the map's frame, so it follows the map's visibility.
    -- The map refreshes its data providers in its own OnShow, before this hook,
    -- so the pins are drawn again once the panel is back.
    map:HookScript("OnShow", function()
        if addon.settings.panelOpen then
            UI:Layer()
            panel:Show()
            addon.RefreshMap()
        end
    end)
    map:HookScript("OnHide", function()
        panel:Hide()
        if self.detail then
            self.detail:Hide()
        end
    end)
    map:HookScript("OnSizeChanged", function() UI:Layer() end)

    addon.Navigation:AddListener(function(status) UI:OnNavigation(status) end)
    self:OnNavigation(addon.Navigation:GetStatus())
    setAtlas(panel, false)
    self:SyncSettings()
    self:UpdateSelection()
    self:Layer()
    if addon.settings.panelOpen and map:IsShown() then
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
    self:Layer()
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
    local summary = #entries == 0 and "Nothing matches here" or ("%d results"):format(#entries)
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
