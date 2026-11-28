local _, addon = ...
local Hover = {}
addon.BossHover = Hover

local PADDING, GAP, SCROLLBAR = 14, 14, 24
local MAX_WIDTH, MAX_HEIGHT = 650, 590

local function trackPointer(panel, elapsed)
    local pin = Hover.pin
    if not pin or not pin:IsVisible() then Hover:Hide(); return end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    -- Bounds also cover mouse-enabled scroll and loot rows within the guide.
    if pin:IsMouseOver() or (x >= panel.left and x <= panel.left + panel:GetWidth()
        and y <= panel.top and y >= panel.top - panel:GetHeight()) then
        panel.outsideTime = 0
    else
        panel.outsideTime = panel.outsideTime + elapsed
        if panel.outsideTime >= .28 then Hover:Hide() end
    end
end

local function scrollBy(scroll, delta)
    local offset = scroll:GetVerticalScroll() - delta * 46
    scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), offset)))
end

local function ensurePanel()
    if Hover.panel then return Hover.panel end
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:Hide()
    panel:SetFrameStrata("TOOLTIP")
    panel:SetBackdrop({
        bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize=15, insets={left=4, right=4, top=4, bottom=4},
    })
    panel:SetBackdropColor(.065, .059, .045, .98)
    panel:SetBackdropBorderColor(.56, .47, .34)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnUpdate", trackPointer)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", PADDING, -12)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(true)
    panel.more = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.more:SetPoint("BOTTOMLEFT", PADDING, 10)
    panel.more:SetText("Scroll for more")
    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:EnableMouseWheel(true)
    panel.scroll:SetScript("OnMouseWheel", scrollBy)
    panel:SetScript("OnMouseWheel", function(_, delta) scrollBy(panel.scroll, delta) end)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(1, 1)
    panel.scroll:SetScrollChild(panel.content)
    panel.rows = {}
    Hover.panel = panel
    return panel
end

local function textRows()
    return {AddLine=function(self, text, r, g, b)
        self[#self + 1] = {text=text, r=r, g=g, b=b}
    end}
end

local function detailsRows(pin, boss, usable)
    local left, right = textRows(), textRows()
    addon.UI:AddBossDetails(left, boss)
    if boss == pin.members[1] then
        if pin.complete then left:AddLine("Encounter complete", .55, .8, .55) end
        if pin.stop.pull then
            left:AddLine("Recorded pull location", .75, .75, .75)
        elseif pin.stop.approximate then
            left:AddLine("Approximate location", .75, .75, .75)
        end
    end
    addon.Tactics:AddGuide(left, boss, true)
    addon.Tactics:AddCasts(left, boss)
    addon.UI:AddBossLoot(right, boss, usable, function(id) right[#right + 1] = {item=id} end)
    return left, right
end

local function tipEnter(row)
    if not row.item then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.item)
    GameTooltip:Show()
end

local function tipLeave(row)
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function setRow(panel, index, x, y, width, data)
    local row = panel.rows[index]
    if not row then
        row = CreateFrame("Button", nil, panel.content)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnEnter", tipEnter)
        row:SetScript("OnLeave", tipLeave)
        row:SetScript("OnClick", function(self) if self.item then addon.UI:OpenItem(self.item) end end)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", 0, -1)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(true)
        panel.rows[index] = row
    end
    if row.item ~= data.item and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    row.item = data.item
    row:EnableMouse(data.item ~= nil)
    row.text:SetWidth(width)
    row.text:SetText(data.item and addon.UI.ItemLabel(data.item) or data.text)
    row.text:SetTextColor(data.r or 1, data.g or 1, data.b or 1)
    local height = data.text == " " and 5 or math.max(14, math.ceil(row.text:GetStringHeight()) + 3)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", x, -y)
    row:SetSize(width, height)
    row:Show()
    return height
end

local function drawRows(panel, rows, x, y, width, count, requested)
    for _, row in ipairs(rows) do
        count = count + 1
        y = y + setRow(panel, count, x, y, width, row)
        if row.item and not requested[row.item] and not addon.ItemCached(row.item) then
            requested[row.item] = true
            addon.RequestItem(row.item)
        end
    end
    return y, count
end

local function screenSpace(pin)
    local w, h, uiScale = UIParent:GetWidth(), UIParent:GetHeight(), UIParent:GetEffectiveScale()
    local scale = pin:GetEffectiveScale() / uiScale
    local x, y = GetCursorPosition()
    local left, right, top = pin:GetLeft(), pin:GetRight(), pin:GetTop()
    left, right, top = (left and left * scale or x / uiScale),
        (right and right * scale or x / uiScale), (top and top * scale or y / uiScale)
    local toRight = w - right >= MAX_WIDTH + 12 or (left < MAX_WIDTH + 12 and w - right >= left)
    local room = toRight and w - right or left
    local width = math.min(MAX_WIDTH, math.max(180, room - 14))
    x = toRight and right + 5 or left - width - 5
    return math.max(7, math.min(w - width - 7, x)), top, width, h
end

function Hover:Draw(pin, offset)
    local panel = ensurePanel()
    local x, top, width, screenHeight = screenSpace(pin)
    panel.title:SetWidth(width - PADDING * 2)
    local main = pin.members[1].name
    local title = #pin.members > 1 and (pin.label or "Bosses at this location") or main
    panel.title:SetText(title)
    panel:SetWidth(width)

    local contentWidth = width - PADDING - SCROLLBAR
    local dual = contentWidth >= 425
    local leftWidth = dual and math.floor((contentWidth - GAP) * .58) or contentWidth
    local rightWidth = dual and contentWidth - GAP - leftWidth or contentWidth
    local rightX = dual and leftWidth + GAP or 0
    local body, count, usable = 0, 0, addon.LootFilter()
    for i, boss in ipairs(pin.members) do
        if i > 1 then body = body + GAP end
        if title ~= boss.name then
            count = count + 1
            body = body + setRow(panel, count, 0, body, contentWidth, {text=boss.name, r=1, g=.82, b=0})
        end
        local left, right = detailsRows(pin, boss, usable)
        local leftBottom, rightBottom
        leftBottom, count = drawRows(panel, left, 0, body, leftWidth, count, self.requested)
        rightBottom, count = drawRows(panel, right, rightX, dual and body or leftBottom + GAP,
            rightWidth, count, self.requested)
        body = math.max(leftBottom, rightBottom)
    end
    for i = count + 1, #panel.rows do
        local row = panel.rows[i]
        if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        row:Hide()
        row.item = nil
    end

    local header = math.max(42, math.ceil(panel.title:GetStringHeight()) + 23)
    local maximum = math.min(MAX_HEIGHT, math.floor(screenHeight * .74))
    local more = header + body + 13 > maximum
    local footer = more and 29 or 13
    panel.more:SetShown(more)
    panel.scroll:ClearAllPoints()
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -header)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SCROLLBAR, footer)
    panel.content:SetSize(contentWidth, body)
    local height = math.min(maximum, header + body + footer)
    panel:SetHeight(height)
    panel.left = x
    panel.top = math.min(screenHeight - 7, math.max(height + 7, top + math.min(116, height * .38)))
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", panel.left, panel.top)
    panel:Show()
    panel.scroll:UpdateScrollChildRect()
    panel.scroll:SetVerticalScroll(math.min(offset or 0, panel.scroll:GetVerticalScrollRange()))
end

function Hover:Show(pin)
    if self.pin == pin then return end
    if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
    self.pin, self.requested = pin, {}
    ensurePanel().outsideTime = 0
    self:Draw(pin)
end

function Hover:Hide()
    if not self.pin then return end
    self.pin, self.requested, self.pending = nil, nil, nil
    for _, row in ipairs(self.panel.rows) do
        if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    end
    self.panel:Hide()
    self.panel:ClearAllPoints()
end

function Hover:Refresh()
    if not self.pin or self.pending then return end
    local token = {}
    self.pending = token
    C_Timer.After(0, function()
        if self.pending ~= token then return end
        self.pending = nil
        if self.pin and self.pin:IsVisible() then self:Draw(self.pin, self.panel.scroll:GetVerticalScroll()) end
    end)
end

function Hover:ItemLoaded(id, success)
    if success and self.requested and self.requested[id] then self:Refresh() end
end
