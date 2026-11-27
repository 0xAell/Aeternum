local _, addon = ...

local function rowLabel(row, font)
    local text = row:CreateFontString(nil, "OVERLAY", font)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetMaxLines(1)
    return text
end

-- A fixed-height list reuses its visible rows. Blizzard's scrollbar handles
-- dragging, track clicks, and step buttons in the same units as the mouse wheel.
function addon.CreateGuideList(parent, rowHeight, describe, handlers)
    local list = CreateFrame("Frame", nil, parent)
    list:EnableMouseWheel(true)
    list.rows = {}
    local entries, offset = {}, 0
    local selected
    local bar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
    bar:SetPoint("TOPRIGHT", -2, 0)
    bar:SetPoint("BOTTOMRIGHT", -2, 1)
    list.bar = bar

    local function visibleRows()
        return math.max(1, math.floor(list:GetHeight() / rowHeight))
    end

    local function maxOffset()
        return math.max(0, #entries - visibleRows())
    end

    local function leave(row)
        if not row.hovered then return end
        row.hovered = false
        if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        if handlers.leave then handlers.leave() end
    end

    local function createRow(index)
        local row = CreateFrame("Button", nil, list)
        local top = -(index - 1) * rowHeight
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, top)
        row:SetPoint("TOPRIGHT", bar, "TOPLEFT", -5, top)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(math.min(20, rowHeight - 4), math.min(20, rowHeight - 4))
        row.icon:SetPoint("LEFT", 3, 0)
        row.title = rowLabel(row, "GameFontHighlight")
        row.subtitle = rowLabel(row, "GameFontDisableSmall")
        row.subtitle:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
        row.subtitle:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -1)
        row:SetScript("OnClick", function(self, mouseButton)
            if self.entry then handlers.click(self.entry, mouseButton) end
        end)
        row:SetScript("OnEnter", function(self)
            if self.entry and handlers.enter then
                self.hovered = true
                handlers.enter(self, self.entry)
            end
        end)
        row:SetScript("OnLeave", leave)
        row:SetScript("OnHide", leave)
        return row
    end

    local function draw()
        local count = visibleRows()
        for index = 1, math.max(count, #list.rows) do
            local row = list.rows[index]
            local entry = index <= count and entries[offset + index]
            if row and row.entry ~= entry then leave(row) end
            if entry then
                if not row then
                    row = createRow(index)
                    list.rows[index] = row
                end
                local title, subtitle, color, icon, dim = describe(entry)
                row.entry = entry
                addon.SetIcon(row.icon, icon, dim)
                row.icon:SetShown(icon ~= nil)
                row.title:ClearAllPoints()
                local indent = icon and 27 or 4
                if subtitle then
                    row.title:SetPoint("TOPLEFT", indent, -2)
                    row.title:SetPoint("TOPRIGHT", -2, -2)
                else
                    row.title:SetPoint("LEFT", indent, 0)
                    row.title:SetPoint("RIGHT", -2, 0)
                end
                row.title:SetText(title)
                if color then row.title:SetTextColor(unpack(color)) else row.title:SetTextColor(1, 1, 1) end
                row.subtitle:SetText(subtitle or "")
                row.subtitle:SetShown(subtitle ~= nil)
                if entry == selected then row:LockHighlight() else row:UnlockHighlight() end
                row:Show()
            elseif row then
                row.entry = nil
                row:Hide()
            end
        end
        bar:SetShown(maxOffset() > 0)
    end

    function list:SetOffset(value)
        local maximum = maxOffset()
        offset = math.min(math.max(0, math.floor(value + .5)), maximum)
        bar:SetScrollPercentage(maximum > 0 and offset / maximum or 0, true)
        draw()
    end

    local function resize(keepScroll)
        bar:SetVisibleExtentPercentage(math.min(1, visibleRows() / math.max(1, #entries)))
        bar:SetPanExtentPercentage(1 / math.max(1, maxOffset()))
        list:SetOffset(keepScroll and offset or 0)
    end

    bar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(_, percentage)
        local target = math.floor(percentage * maxOffset() + .5)
        if target ~= offset then
            offset = target
            draw()
        end
    end, list)
    list:SetScript("OnMouseWheel", function(_, delta) list:SetOffset(offset - delta * 3) end)
    list:SetScript("OnSizeChanged", function() resize(true) end)

    function list:SetEntries(values, keepScroll)
        entries = values
        if not keepScroll then selected = nil end
        resize(keepScroll)
    end
    function list:SetSelection(value)
        if selected == value then return end
        selected = value
        for _, row in ipairs(list.rows) do
            if value and row.entry == value then row:LockHighlight() else row:UnlockHighlight() end
        end
    end
    function list:Reveal(value)
        for index, entry in ipairs(entries) do
            if entry == value then
                selected = value
                list:SetOffset(index - 1)
                return
            end
        end
    end
    function list:GetEntries() return entries end
    function list:GetOffset() return offset end
    list.Refresh = draw
    return list
end
