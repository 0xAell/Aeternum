local _, addon = ...
local UI = {}
addon.UI = UI

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

local function button(parent, title, width, callback)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetSize(width, 23)
    control:SetText(title)
    control:SetScript("OnClick", callback)
    return control
end

local function newList(parent, rowHeight, open, options)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local rows = {}
    local entries = {}
    local selectedEntry
    local onEnter = options and options.onEnter
    local onLeave = options and options.onLeave

    local function createRow()
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(rowHeight)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(.84, .66, .37, .14)
        local selected = row:CreateTexture(nil, "BACKGROUND")
        selected:SetAllPoints()
        selected:SetColorTexture(.84, .66, .37, .22)
        selected:Hide()
        row.selected = selected
        row.title = label(row, "GameFontNormal")
        row.title:SetPoint("TOPLEFT", 5, -3)
        row.title:SetPoint("RIGHT", -5, 0)
        row.title:SetWordWrap(false)
        row.title:SetMaxLines(1)
        row.subtitle = label(row)
        row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
        row.subtitle:SetPoint("RIGHT", -5, 0)
        row.subtitle:SetWordWrap(false)
        row.subtitle:SetMaxLines(1)
        row:SetScript("OnClick", function(self, mouseButton)
            if self.entry then
                open(self.entry, mouseButton)
            end
        end)
        if onEnter then
            row:SetScript("OnEnter", function(self)
                if self.entry then
                    onEnter(self, self.entry)
                end
            end)
        end
        if onLeave then
            row:SetScript("OnLeave", function(self)
                onLeave(self, self.entry)
            end)
        end
        return row
    end

    local function drawRows()
        local scrollOffset = math.max(0, scroll:GetVerticalScroll() or 0)
        local viewportHeight = math.max(0, scroll:GetHeight() or 0)
        local first = math.max(1, math.floor(scrollOffset / rowHeight) + 1)
        local visible = math.ceil(viewportHeight / rowHeight) + 2
        local count = math.max(0, math.min(visible, #entries - first + 1))
        for slot = 1, count do
            local index = first + slot - 1
            local entry = entries[index]
            local row = rows[slot]
            if not row then
                row = createRow()
                rows[slot] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * rowHeight)
            row.entry = entry
            row.title:SetText(entry.title)
            row.title:SetTextColor(unpack(entry.color or { .94, .88, .75 }))
            row.subtitle:SetText(entry.subtitle or "")
            row.subtitle:SetShown(entry.subtitle ~= nil)
            row.selected:SetShown(selectedEntry ~= nil and entry == selectedEntry)
            row:Show()
        end
        for slot = count + 1, #rows do
            rows[slot].entry = nil
            rows[slot].selected:Hide()
            rows[slot]:Hide()
        end
    end

    scroll:HookScript("OnVerticalScroll", drawRows)
    scroll:HookScript("OnSizeChanged", function(self, width)
        child:SetWidth(math.max(1, width))
        drawRows()
    end)

    function scroll:SetSelected(entry)
        selectedEntry = entry
        drawRows()
    end

    function scroll:SetEntries(values, preserveScroll)
        entries = values or {}
        local contentHeight = math.max(1, #entries * rowHeight)
        child:SetWidth(math.max(1, self:GetWidth()))
        child:SetHeight(contentHeight)
        if self.UpdateScrollChildRect then
            self:UpdateScrollChildRect()
        end
        if preserveScroll then
            local viewportHeight = math.max(0, self:GetHeight() or 0)
            local maxScroll = math.max(0, contentHeight - viewportHeight)
            local current = math.max(0, self:GetVerticalScroll() or 0)
            self:SetVerticalScroll(math.min(current, maxScroll))
        else
            self:SetVerticalScroll(0)
        end
        drawRows()
    end

    return scroll
end

local function showItem(entry, mouseButton)
    if not entry or not entry.itemID then
        return
    end
    local link = "item:" .. entry.itemID
    local hyperlink = addon.ItemLink(entry.itemID, entry.title)
    if type(HandleModifiedItemClick) == "function" and hyperlink and HandleModifiedItemClick(hyperlink) then
        return
    end
    if type(SetItemRef) == "function" then
        SetItemRef(link, hyperlink or entry.title, mouseButton or "LeftButton")
    elseif GameTooltip then
        GameTooltip:SetOwner(UI.detail, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

local function previewItem(row, entry)
    if not GameTooltip or not entry or not entry.itemID then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. entry.itemID)
    GameTooltip:Show()
end

local function hidePreview(row)
    if GameTooltip and GameTooltip:IsOwned(row) then
        GameTooltip:Hide()
    end
end

local function resizedDetail(frame)
    local parentWidth = UIParent and UIParent:GetWidth() or 788
    local parentHeight = UIParent and UIParent:GetHeight() or 544
    local width = math.max(460, math.min(750, parentWidth - 38))
    local height = math.max(360, math.min(510, parentHeight - 34))
    frame:SetSize(width, height)
    frame.floorMap:SetWidth(math.floor((width - 52) * .58))
end

local function syncNavigationUI(frame)
    if not frame then
        return
    end
    frame.routeStatus:SetText(addon.Navigation:GetStatus() or "")
    frame.stop:SetEnabled(addon.Navigation:IsActive())
end

local function createDetail(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    surface(frame)
    frame:Hide()

    frame.title = label(frame, "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 17, -14)
    frame.title:SetPoint("RIGHT", -32, 0)
    frame.title:SetWordWrap(false)
    frame.title:SetMaxLines(1)
    frame.levels = label(frame)
    frame.levels:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.levels:SetPoint("RIGHT", -32, 0)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:HookScript("OnHide", function(self)
        if GameTooltip and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)

    frame.floorMap = addon.DungeonMap.Create(frame)
    frame.floorMap:SetPoint("TOPLEFT", 14, -62)
    frame.floorMap:SetPoint("BOTTOMLEFT", 14, 70)

    local heading = label(frame, "GameFontNormal")
    heading:SetText("Boss loot")
    heading:SetPoint("TOPLEFT", frame.floorMap, "TOPRIGHT", 18, -1)
    frame.bossBack = button(frame, "<", 27, function() UI:ChangeBoss(-1) end)
    frame.bossBack:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
    frame.bossNext = button(frame, ">", 27, function() UI:ChangeBoss(1) end)
    frame.bossNext:SetPoint("TOPRIGHT", -17, -82)
    frame.bossTitle = label(frame)
    frame.bossTitle:SetPoint("LEFT", frame.bossBack, "RIGHT", 6, 0)
    frame.bossTitle:SetPoint("RIGHT", frame.bossNext, "LEFT", -4, 0)
    frame.bossTitle:SetMaxLines(1)
    frame.bossTitle:SetWordWrap(false)

    frame.loot = newList(frame, 23, showItem, { onEnter = previewItem, onLeave = hidePreview })
    frame.loot:SetPoint("TOPLEFT", frame.bossBack, "BOTTOMLEFT", 0, -8)
    frame.loot:SetPoint("BOTTOMRIGHT", -36, 72)
    frame.noLoot = label(frame)
    frame.noLoot:SetPoint("TOPLEFT", frame.loot)
    frame.noLoot:SetText("No loot records in this seed.")

    frame.route = button(frame, "Guide me", 88, function()
        local entrance = frame.entrances[frame.entranceIndex]
        if entrance then
            addon.Navigation:Start(frame.dungeon, entrance)
            syncNavigationUI(frame)
        end
    end)
    frame.route:SetPoint("BOTTOMLEFT", 15, 27)
    frame.stop = button(frame, "Stop", 50, function()
        addon.Navigation:Stop()
        syncNavigationUI(frame)
    end)
    frame.stop:SetPoint("LEFT", frame.route, "RIGHT", 6, 0)
    frame.showZone = button(frame, "Show zone", 82, function()
        local entrance = frame.entrances[frame.entranceIndex]
        if not (entrance and entrance.mapID and UI.map and UI.map.SetMapID) then
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            if type(print) == "function" then
                print("Aeternum: cannot switch the world map during combat.")
            end
            return
        end
        if UI.sidebar and UI.sidebar.atlas then
            UI:SetAtlas(false)
        end
        UI.map:SetMapID(entrance.mapID)
        frame:Hide()
    end)
    frame.showZone:SetPoint("LEFT", frame.stop, "RIGHT", 6, 0)
    frame.nextEntrance = button(frame, "Next entrance", 104, function()
        if #frame.entrances > 1 then
            UI:SetEntrance(frame.entranceIndex % #frame.entrances + 1)
        end
    end)
    frame.nextEntrance:SetPoint("LEFT", frame.showZone, "RIGHT", 6, 0)
    frame.entranceText = label(frame)
    frame.entranceText:SetPoint("LEFT", frame.nextEntrance, "RIGHT", 8, 0)
    frame.entranceText:SetPoint("RIGHT", -14, 0)
    frame.entranceText:SetWordWrap(false)
    frame.entranceText:SetMaxLines(1)
    frame.routeStatus = label(frame)
    frame.routeStatus:SetPoint("BOTTOMLEFT", 16, 10)
    frame.routeStatus:SetPoint("RIGHT", -14, 0)
    frame.routeStatus:SetTextColor(.72, .76, .83)

    pcall(frame.RegisterEvent, frame, "ITEM_DATA_LOAD_RESULT")
    pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
    frame:SetScript("OnEvent", function(self, _, itemID, success)
        if self.pendingLootIDs and self.pendingLootIDs[itemID] then
            self.pendingLootIDs[itemID] = nil
            if success and self:IsShown() then
                UI:RefreshBossLoot()
            end
        end
    end)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, seconds)
        elapsed = elapsed + seconds
        if elapsed >= .25 then
            elapsed = 0
            syncNavigationUI(self)
        end
    end)
    resizedDetail(frame)
    return frame
end

function UI:SetEntrance(index)
    local frame = self.detail
    if not frame then
        return
    end
    local count = #frame.entrances
    frame.entranceIndex = count > 0 and math.max(1, math.min(count, index or 1)) or 0
    local entrance = frame.entrances[frame.entranceIndex]
    frame.route:SetEnabled(entrance ~= nil)
    frame.showZone:SetEnabled(not not (entrance ~= nil and type(entrance.mapID) == "number" and UI.map and type(UI.map.SetMapID) == "function"))
    frame.nextEntrance:SetEnabled(count > 1)
    if entrance then
        local zone = addon.ZoneName(entrance.mapID)
        local text = entrance.label and (entrance.label .. " · " .. zone) or zone
        if #frame.entrances > 1 then
            text = text .. " · " .. addon.FormatCoordinates(entrance)
        end
        frame.entranceText:SetText(text)
    else
        frame.entranceText:SetText("Entrance coordinates unavailable")
    end
end

local function buildLootEntries(boss, requestMissing)
    local entries = {}
    local pendingLootIDs = {}
    for _, itemID in ipairs(boss and boss.loot or {}) do
        if requestMissing and not addon.ItemCached(itemID) then
            pendingLootIDs[itemID] = true
            addon.RequestItemData(itemID)
        end
        entries[#entries + 1] = {
            title = addon.ItemName(itemID),
            color = addon.ItemColor(itemID),
            itemID = itemID,
        }
    end
    table.sort(entries, function(a, b)
        if a.title ~= b.title then
            return a.title < b.title
        end
        return (a.itemID or 0) < (b.itemID or 0)
    end)
    return entries, pendingLootIDs
end

function UI:RefreshBossLoot()
    local frame = self.detail
    if not frame or not frame.dungeon then
        return
    end
    local bosses = frame.dungeon.bosses or {}
    local boss = bosses[frame.bossIndex]
    if not boss then
        return
    end
    local entries = buildLootEntries(boss, false)
    frame.noLoot:SetShown(#entries == 0)
    frame.loot:SetEntries(entries, true)
end

function UI:ChangeBoss(delta)
    local frame = self.detail
    if not frame or not frame.dungeon then
        return
    end
    local bosses = frame.dungeon.bosses or {}
    local entries = {}
    local pendingLootIDs = {}
    local boss
    if #bosses > 0 then
        frame.bossIndex = (frame.bossIndex - 1 + delta) % #bosses + 1
        boss = bosses[frame.bossIndex]
        entries, pendingLootIDs = buildLootEntries(boss, true)
    end
    frame.pendingLootIDs = pendingLootIDs
    if GameTooltip and GameTooltip:IsOwned(frame) then
        GameTooltip:Hide()
    end
    frame.bossTitle:SetText(boss and ("%s (%d/%d)"):format(boss.name, frame.bossIndex, #bosses) or "No boss records")
    frame.bossBack:SetEnabled(#bosses > 1)
    frame.bossNext:SetEnabled(#bosses > 1)
    frame.noLoot:SetShown(#entries == 0)
    frame.loot:SetEntries(entries, false)
end

function UI:Select(entry)
    if not entry then
        return
    end
    if self.sidebar and self.sidebar.list then
        self.sidebar.list:SetSelected(entry)
    end
    if entry.category ~= "dungeon" then
        if entry.x and entry.y and self.sidebar then
            self.sidebar.selection:SetText(("%s · %.1f, %.1f"):format(entry.title, 100 * entry.x, 100 * entry.y))
            addon.HighlightPin(entry)
        end
        return
    end
    if not self.detail then
        self.detail = createDetail(self.map)
    end
    local frame = self.detail
    local dungeon = entry.source
    frame.dungeon = dungeon
    frame.entrances = {}
    local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    local selectedIndex = 1
    local preferred = entry.point
    local mapID = self.map:GetMapID()
    for _, entrance in ipairs(dungeon.entrances or {}) do
        if addon.FactionAllowed(entrance, faction) then
            frame.entrances[#frame.entrances + 1] = entrance
            if not preferred and entrance.mapID == mapID then
                preferred = entrance
            end
            if entrance == preferred then
                selectedIndex = #frame.entrances
            end
        end
    end
    frame.title:SetText(dungeon.name)
    frame.levels:SetText(addon.DungeonLevel(dungeon) or "")
    frame.bossIndex = 1
    resizedDetail(frame)
    frame.floorMap:SetDungeon(dungeon)
    frame:Show()
    self:ChangeBoss(0)
    self:SetEntrance(selectedIndex)
    syncNavigationUI(frame)
end

function UI:SetAtlas(enabled)
    local panel = self.sidebar
    if not panel then
        return
    end
    panel.atlas = not not enabled
    panel.mode:SetText(panel.atlas and "Current map" or "All dungeons")
    for _, check in ipairs(panel.checks) do
        check:SetShown(not panel.atlas)
    end
    panel.heading:ClearAllPoints()
    panel.heading:SetPoint("TOPLEFT", 11, panel.atlas and -66 or -108)
    addon.RefreshMap()
end

function UI:Attach(map)
    self.map = map
    local panel = CreateFrame("Frame", nil, map)
    self.sidebar = panel
    panel:SetPoint("TOPLEFT", 13, -60)
    panel:SetPoint("BOTTOMLEFT", 13, 28)
    panel:SetWidth(268)
    panel:SetFrameStrata("HIGH")
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
        self:SetAtlas(not panel.atlas)
    end)
    panel.mode:SetPoint("TOPRIGHT", -9, -8)

    panel.search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.search:SetPoint("TOPLEFT", 16, -37)
    panel.search:SetPoint("TOPRIGHT", -32, -37)
    panel.search:SetHeight(22)
    panel.search:SetAutoFocus(false)
    panel.search:SetMaxLetters(70)
    panel.search:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    panel.search:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
    panel.search:SetScript("OnTextChanged", addon.RefreshMap)

    local clearSearch = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clearSearch:SetSize(20, 20)
    clearSearch:SetPoint("LEFT", panel.search, "RIGHT", 2, 0)
    clearSearch:SetText("x")
    clearSearch:Hide()
    clearSearch:SetScript("OnClick", function()
        panel.search:SetText("")
        panel.search:ClearFocus()
    end)
    panel.clearSearch = clearSearch

    local prompt = label(panel.search)
    prompt:SetPoint("LEFT", 1, 0)
    prompt:SetTextColor(.6, .64, .71)
    prompt:SetText("Search")
    panel.search:HookScript("OnTextChanged", function(edit)
        local empty = edit:GetText() == ""
        prompt:SetShown(empty)
        clearSearch:SetShown(not empty)
    end)

    panel.checks = {}
    for index, category in ipairs(addon.categories) do
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        check:SetPoint("TOPLEFT", 8 + column * 121, -61 - row * 20)
        check:SetChecked(addon.CategoryEnabled(category.id))
        local description = label(check)
        description:SetPoint("LEFT", check, "RIGHT", 2, 1)
        description:SetText(category.label)
        description:SetTextColor(unpack(category.color))
        check:SetScript("OnClick", function(control)
            addon.LoadSettings()
            addon.settings.filters[category.id] = not not control:GetChecked()
            addon.RefreshMap()
        end)
        panel.checks[#panel.checks + 1] = check
    end

    panel.heading = label(panel, "GameFontNormal")
    panel.heading:SetPoint("TOPLEFT", 11, -108)
    panel.list = newList(panel, 34, function(entry) self:Select(entry) end)
    panel.list:SetPoint("TOPLEFT", panel.heading, "BOTTOMLEFT", -1, -7)
    panel.list:SetPoint("BOTTOMRIGHT", -30, 34)
    panel.selection = label(panel)
    panel.selection:SetPoint("BOTTOMLEFT", 11, 12)
    panel.selection:SetPoint("RIGHT", -10, 0)
    panel.selection:SetWordWrap(false)
    panel.selection:SetMaxLines(1)
    panel.selection:SetTextColor(.72, .76, .83)

    local toggle = button(map, "Aeternum", 91, function()
        if panel:IsShown() then
            panel:Hide()
            addon.RefreshMap()
        else
            self:Show()
        end
    end)
    toggle:SetPoint("TOPLEFT", map, "TOPLEFT", 13, -35)
    toggle:SetFrameStrata("HIGH")

    addon.Navigation.onChange = function()
        if self.detail and self.detail:IsShown() then
            syncNavigationUI(self.detail)
        end
    end
end

function UI:Show()
    if not self.sidebar then
        return
    end
    self.sidebar:Show()
    addon.RefreshMap()
end

function UI:IsOpen()
    return self.sidebar ~= nil and self.sidebar:IsShown() or false
end

function UI:IsAtlas()
    return self.sidebar ~= nil and self.sidebar.atlas or false
end

function UI:GetSearch()
    return self.sidebar and self.sidebar.search:GetText() or ""
end

function UI:SetSearch(query)
    if not self.sidebar then
        return
    end
    self.sidebar.search:SetText(query or "")
    addon.RefreshMap()
end

function UI:UpdateEntries(entries, mapID, pinnedCount, totalLocations)
    local panel = self.sidebar
    if not panel then
        return
    end
    panel.heading:SetText(panel.atlas and "Dungeon atlas" or addon.ZoneName(mapID))
    if #entries == 0 then
        panel.selection:SetText("No matching records")
    elseif not panel.atlas and pinnedCount and totalLocations and totalLocations > pinnedCount then
        panel.selection:SetText(("%d results (%d map pins)"):format(#entries, pinnedCount))
    else
        panel.selection:SetText(("%d results"):format(#entries))
    end
    panel.list:SetSelected(nil)
    panel.list:SetEntries(entries)
end
