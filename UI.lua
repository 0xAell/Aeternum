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

local function newList(parent, rowHeight, open)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    local rows = {}
    local entries = {}

    local function createRow()
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(rowHeight)
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(.84, .66, .37, .14)
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
        row:SetScript("OnClick", function(self)
            open(self.entry)
        end)
        return row
    end

    local function drawRows()
        local first = math.floor(scroll:GetVerticalScroll() / rowHeight) + 1
        local visible = math.ceil(scroll:GetHeight() / rowHeight) + 2
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
            row:Show()
        end
        for slot = count + 1, #rows do
            rows[slot].entry = nil
            rows[slot]:Hide()
        end
    end

    scroll:HookScript("OnVerticalScroll", drawRows)
    scroll:HookScript("OnSizeChanged", function(self, width)
        child:SetWidth(math.max(1, width))
        drawRows()
    end)

    function scroll:SetEntries(values)
        entries = values
        child:SetWidth(math.max(1, self:GetWidth()))
        child:SetHeight(math.max(1, #entries * rowHeight))
        self:SetVerticalScroll(0)
        drawRows()
    end

    return scroll
end

local function showItem(entry)
    local link = "item:" .. entry.itemID
    if type(SetItemRef) == "function" then
        SetItemRef(link, entry.title, "LeftButton")
    else
        GameTooltip:SetOwner(UI.detail, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end
end

local function resizedDetail(frame)
    frame:SetSize(math.min(750, UIParent:GetWidth() - 38), math.min(510, UIParent:GetHeight() - 34))
    frame.floorMap:SetWidth(math.floor((frame:GetWidth() - 52) * .58))
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
    frame.levels = label(frame)
    frame.levels:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:HookScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then
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

    frame.loot = newList(frame, 23, showItem)
    frame.loot:SetPoint("TOPLEFT", frame.bossBack, "BOTTOMLEFT", 0, -8)
    frame.loot:SetPoint("BOTTOMRIGHT", -36, 72)
    frame.noLoot = label(frame)
    frame.noLoot:SetPoint("TOPLEFT", frame.loot)
    frame.noLoot:SetText("No loot records in this seed.")

    frame.route = button(frame, "Guide me", 96, function()
        local entrance = frame.entrances[frame.entranceIndex]
        if entrance then
            addon.Navigation:Start(frame.dungeon, entrance)
            frame.routeStatus:SetText(addon.Navigation:GetStatus() or "")
        end
    end)
    frame.route:SetPoint("BOTTOMLEFT", 15, 27)
    frame.stop = button(frame, "Stop", 52, function()
        addon.Navigation:Stop()
        frame.routeStatus:SetText(addon.Navigation:GetStatus() or "")
    end)
    frame.stop:SetPoint("LEFT", frame.route, "RIGHT", 6, 0)
    frame.nextEntrance = button(frame, "Next entrance", 111, function()
        UI:SetEntrance(frame.entranceIndex % #frame.entrances + 1)
    end)
    frame.nextEntrance:SetPoint("LEFT", frame.stop, "RIGHT", 6, 0)
    frame.entranceText = label(frame)
    frame.entranceText:SetPoint("LEFT", frame.nextEntrance, "RIGHT", 8, 0)
    frame.entranceText:SetPoint("RIGHT", -14, 0)
    frame.entranceText:SetWordWrap(false)
    frame.entranceText:SetMaxLines(1)
    frame.routeStatus = label(frame)
    frame.routeStatus:SetPoint("BOTTOMLEFT", 16, 10)
    frame.routeStatus:SetPoint("RIGHT", -14, 0)
    frame.routeStatus:SetTextColor(.72, .76, .83)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, seconds)
        elapsed = elapsed + seconds
        if elapsed >= .25 then
            elapsed = 0
            self.routeStatus:SetText(addon.Navigation:GetStatus() or "")
        end
    end)
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
    local bosses = frame.dungeon.bosses or {}
    local entries = {}
    local boss
    if #bosses > 0 then
        frame.bossIndex = (frame.bossIndex - 1 + delta) % #bosses + 1
        boss = bosses[frame.bossIndex]
        for _, itemID in ipairs(boss.loot or {}) do
            entries[#entries + 1] = { title = addon.ItemName(itemID), itemID = itemID }
        end
        table.sort(entries, function(a, b) return a.title < b.title end)
    end
    if GameTooltip:IsOwned(frame) then
        GameTooltip:Hide()
    end
    frame.bossTitle:SetText(boss and ("%s (%d/%d)"):format(boss.name, frame.bossIndex, #bosses) or "No boss records")
    frame.bossBack:SetEnabled(#bosses > 1)
    frame.bossNext:SetEnabled(#bosses > 1)
    frame.noLoot:SetShown(#entries == 0)
    frame.loot:SetEntries(entries)
end

function UI:Select(entry)
    if entry.category ~= "dungeon" then
        if entry.x and entry.y then
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
    local faction = UnitFactionGroup("player")
    local selectedIndex = 1
    for _, entrance in ipairs(dungeon.entrances or {}) do
        if addon.FactionAllowed(entrance, faction) then
            frame.entrances[#frame.entrances + 1] = entrance
            if entrance == entry.point then
                selectedIndex = #frame.entrances
            end
        end
    end
    frame.title:SetText(dungeon.name)
    frame.levels:SetText(addon.DungeonLevel(dungeon) or "")
    frame.bossIndex = 1
    resizedDetail(frame)
    frame:Show()
    frame.floorMap:SetDungeon(dungeon)
    self:ChangeBoss(0)
    self:SetEntrance(selectedIndex)
    frame.routeStatus:SetText(addon.Navigation:GetStatus() or "")
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
        panel.atlas = not panel.atlas
        panel.mode:SetText(panel.atlas and "Current map" or "All dungeons")
        for _, check in ipairs(panel.checks) do
            check:SetShown(not panel.atlas)
        end
        panel.heading:ClearAllPoints()
        panel.heading:SetPoint("TOPLEFT", 11, panel.atlas and -66 or -108)
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
    panel.search:SetScript("OnTextChanged", addon.RefreshMap)
    local prompt = label(panel.search)
    prompt:SetPoint("LEFT", 1, 0)
    prompt:SetTextColor(.6, .64, .71)
    prompt:SetText("Search")
    panel.search:HookScript("OnTextChanged", function(edit)
        prompt:SetShown(edit:GetText() == "")
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
end

function UI:Show()
    self.sidebar:Show()
    addon.RefreshMap()
end

function UI:IsOpen()
    return self.sidebar:IsShown()
end

function UI:IsAtlas()
    return self.sidebar.atlas
end

function UI:GetSearch()
    return self.sidebar.search:GetText()
end

function UI:UpdateEntries(entries, mapID)
    local panel = self.sidebar
    panel.heading:SetText(panel.atlas and "Dungeon atlas" or addon.ZoneName(mapID))
    panel.selection:SetText(#entries == 0 and "No matching records" or ("%d results"):format(#entries))
    panel.list:SetEntries(entries)
end
