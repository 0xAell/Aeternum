local _, addon = ...
local AtlasPins = {}
AtlasPins.__index = AtlasPins
addon.AtlasPins = AtlasPins

local WORLD = 947
local OVERVIEW = {icon = 22, target = 16, badge = 8}
local REGION = {icon = 30, target = 21, badge = 9}
local ZONE = {icon = 38, target = 32, badge = 10}

local function entrances(byID)
    local points, overview = {}, {}
    for _, entry in ipairs(addon.MapRecords(WORLD)) do
        if entry.category == "dungeon" then overview[entry.point] = entry end
    end

    for _, dungeon in ipairs(addon.DungeonsByLevel()) do
        for _, entry in ipairs(addon.DungeonEntrances(dungeon.source)) do
            local map, fallback = byID[entry.mapID], overview[entry.point]
            local x, y
            if map then
                x = map.left + (map.right - map.left) * entry.x
                y = map.top + (map.bottom - map.top) * entry.y
            elseif fallback then
                x, y = fallback.x, fallback.y
            end
            if x then points[#points + 1] = {entry = entry, x = x, y = y} end
        end
    end
    return points
end

local function leave(pin)
    pin.glow:Hide()
    if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end

local function reset(pin)
    leave(pin)
    pin:Hide()
    pin.entry, pin.entries, pin.anchor = nil, nil, nil
end

local function newPin(parent)
    local pin = CreateFrame("Button", nil, parent)
    pin:SetFrameLevel(parent:GetFrameLevel() + 2)
    pin:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pin:EnableMouseWheel(true)
    pin:SetScript("OnMouseWheel", function(_, delta) parent:GetScript("OnMouseWheel")(parent, delta) end)
    pin:SetScript("OnEnter", function(self)
        if not self.entry then return end
        self.glow:Show()
        addon.ShowMapPinTooltip(self)
    end)
    pin:SetScript("OnLeave", leave)
    pin:SetScript("OnClick", function(self, button)
        if not self.entries then return end
        if button == "LeftButton" then addon.UI:PickLocation(self, self.entries)
        elseif button == "RightButton" then addon.UI:Directions(self, self.entries) end
    end)

    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("CENTER")
    pin.glow = pin:CreateTexture(nil, "BACKGROUND")
    pin.glow:SetAtlas("UI-QuestPoi-OuterGlow")
    pin.glow:SetPoint("TOPLEFT", pin.icon, "TOPLEFT", -4, 4)
    pin.glow:SetPoint("BOTTOMRIGHT", pin.icon, "BOTTOMRIGHT", 4, -4)
    pin.glow:Hide()
    pin.tracked = pin:CreateTexture(nil, "OVERLAY")
    pin.tracked:SetAtlas("waypoint-mappin-minimap-tracked")
    pin.tracked:SetPoint("BOTTOMRIGHT", pin.icon, "BOTTOMRIGHT")
    return pin
end

local function place(pin, group, style)
    local entry, tracked = group.entries[1], false
    for _, door in ipairs(group.entries) do
        if addon.Navigation:IsDestination(door.point, door.source.id) then
            entry, tracked = door, true
            break
        end
    end
    local contentsChanged = entry ~= pin.entry or tracked ~= pin.tracked:IsShown() or
        not pin.entries or #group.entries ~= #pin.entries
    if not contentsChanged then
        for i, door in ipairs(group.entries) do
            if door ~= pin.entries[i] then
                contentsChanged = true
                break
            end
        end
    end

    pin.anchor, pin.entry, pin.entries = group.anchor, entry, group.entries
    if contentsChanged then
        local icon, _, _, dim = addon.Presentation(entry)
        addon.SetIcon(pin.icon, icon, dim)
        pin.tracked:SetShown(tracked)
        if GameTooltip:IsOwned(pin) then addon.ShowMapPinTooltip(pin) end
    end
    if pin.style ~= style then
        pin.style = style
        pin.icon:SetSize(style.icon, style.icon)
        pin:SetSize(style.target, style.target)
        pin.tracked:SetSize(style.badge, style.badge)
    end
    pin:SetPoint("CENTER", pin:GetParent(), "TOPLEFT", group.x, -group.y)
    pin:Show()
end

function AtlasPins.New(parent, _, byID)
    parent.pins = {}
    return setmetatable({parent = parent, points = entrances(byID), active = {}}, AtlasPins)
end

local function drawGroups(points, width, height, left, top, viewWidth, viewHeight, gap)
    local groups, byAnchor = {}, {}
    local scaleX, scaleY = width / viewWidth, height / viewHeight
    local inset = gap / 2
    for _, point in ipairs(points) do
        local x, y = (point.x - left) * scaleX, (point.y - top) * scaleY
        if x >= inset and x <= width - inset and y >= inset and y <= height - inset then
            local group
            for _, other in ipairs(groups) do
                if math.abs(x - other.x) < gap and math.abs(y - other.y) < gap then
                    group = other
                    break
                end
            end
            if not group then
                group = {anchor = point, entries = {}, x = x, y = y}
                groups[#groups + 1], byAnchor[point] = group, group
            end
            group.entries[#group.entries + 1] = point.entry
        end
    end
    return groups, byAnchor
end

function AtlasPins:Draw(left, top, viewWidth, viewHeight, zoom)
    local width, height = self.parent:GetSize()
    if width <= 0 or height <= 0 or viewWidth <= 0 or viewHeight <= 0 or not addon.CategoryEnabled("dungeon") then
        self:Clear()
        return
    end

    local style = zoom >= 10 and ZONE or (zoom >= 3.5 and REGION or OVERVIEW)
    local groups, byAnchor = drawGroups(self.points, width, height, left, top, viewWidth, viewHeight, style.target)
    local free = {}
    for _, pin in ipairs(self.parent.pins) do
        if not pin.anchor or not byAnchor[pin.anchor] then
            if pin.anchor then
                self.active[pin.anchor] = nil
                reset(pin)
            end
            free[#free + 1] = pin
        end
    end

    for _, group in ipairs(groups) do
        local pin = self.active[group.anchor] or table.remove(free)
        if not pin then
            pin = newPin(self.parent)
            self.parent.pins[#self.parent.pins + 1] = pin
        end
        self.active[group.anchor] = pin
        place(pin, group, style)
    end
end

function AtlasPins:Clear()
    for _, pin in ipairs(self.parent.pins) do reset(pin) end
    wipe(self.active)
end
