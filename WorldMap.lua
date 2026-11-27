local _, addon = ...
local POINT, ENTRANCE = "AeternumMapPinTemplate", "AeternumEntrancePinTemplate"
local LIMIT = 150
local provider, focus, marked
local pins = {}
AeternumMapPinMixin = {}

function pins:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1, 1.2)
    self.icon = self:CreateTexture(nil, "ARTWORK")
    self.icon:SetAllPoints()
end

function pins:UpdateStyle()
    local icon, _, _, dim = addon.Presentation(self.entry)
    addon.SetIcon(self.icon, icon, dim)
end

function pins:OnAcquired(entries)
    self.entries, self.entry = entries, entries[1]
    self:SetSize(17, 17)
    self:UpdateStyle()
    self:SetPosition(self.entry.x, self.entry.y)
end

function pins:OnReleased()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    if self == focus then focus = nil end
    if self == marked then marked = nil end
    self.entries, self.entry = nil, nil
    MapCanvasPinMixin.OnReleased(self)
end

function pins:OnMouseEnter()
    local entry = self.entry
    if not entry then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.title)
    local _, _, text = addon.Presentation(entry)
    GameTooltip:AddLine(text)
    if #self.entries > 1 then GameTooltip:AddLine(("%d at this location"):format(#self.entries)) end
    if entry.category == "dungeon" then
        GameTooltip:AddLine("Click for floor map · Right-click for directions", 1, .82, 0)
    elseif entry.category ~= "quest" then
        GameTooltip:AddLine("Click for lessons and prices", 1, .82, 0)
    else
        local requirement = addon.Quests:Requirement(entry.questID)
        if requirement then GameTooltip:AddLine(requirement) end
    end
    GameTooltip:Show()
end

function pins:OnMouseLeave()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- Each template has a fixed mouse policy in XML. Acquiring a pooled pin
-- in combat never needs to change protected passthrough settings.
function pins:CheckMouseButtonPassthrough() end

function pins:OnMouseClickAction(button)
    if not self.entry then return end
    if button == "LeftButton" then
        addon.UI:PickLocation(self, self.entries)
    elseif button == "RightButton" and self.entry.category == "dungeon" then
        addon.UI:Directions(self, self.entries)
    end
end

local methods = {}
function methods:RemoveAllData()
    local map = self:GetMap()
    for _, template in ipairs({POINT, ENTRANCE}) do
        if map:GetNumActivePinsByTemplate(template) > 0 then map:RemoveAllPinsByTemplate(template) end
    end
    self.drawn = nil
end

function methods:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    if not map:IsShown() then return end
    self.drawn = addon.Entries(map:GetMapID(), false, "")
    local positions, groups = {}, {}
    for _, entry in ipairs(self.drawn) do
        local key = ("%.3f:%.3f"):format(entry.x, entry.y)
        local group = positions[key]
        if group then
            group[#group + 1] = entry
        elseif #groups < LIMIT then
            group = {entry}
            groups[#groups + 1], positions[key] = group, group
        end
    end
    for _, group in ipairs(groups) do
        local template = group[1].category == "dungeon" and ENTRANCE or POINT
        map:AcquirePin(template, group)
    end
end

function methods:OnMapChanged()
    addon.DungeonMap:Close()
    self:RefreshAllData()
end
methods.OnHide = methods.RemoveAllData

function addon.RefreshMap()
    if provider then provider:RefreshAllData() end
end

function addon.RefreshQuestStates()
    if not provider then return end
    local map = provider:GetMap()
    if not map:IsShown() then return end
    local entries = addon.Entries(map:GetMapID(), false, "")
    local before = provider.drawn or {}
    if #entries ~= #before then provider:RefreshAllData() return end
    for i, entry in ipairs(entries) do
        if before[i] ~= entry then provider:RefreshAllData() return end
    end
    for pin in map:EnumeratePinsByTemplate(POINT) do pin:UpdateStyle() end
end

function addon.FocusLocation(entry)
    local map = provider:GetMap()
    if focus then map:RemovePin(focus) end
    if marked then
        marked:OnMouseLeave()
        marked.entry = marked.entries[1]
        marked:UpdateStyle()
        marked:SetSize(17, 17)
        marked = nil
    end
    if not entry or entry.mapID ~= map:GetMapID() then return end
    for pin in map:EnumeratePinsByTemplate(POINT) do
        for _, other in ipairs(pin.entries) do
            if other == entry then
                marked = pin
                pin.entry = entry
                pin:UpdateStyle()
                pin:SetSize(23, 23)
                pin:OnMouseEnter()
                return
            end
        end
    end
    focus = map:AcquirePin(POINT, {entry})
    focus:SetSize(23, 23)
    focus:OnMouseEnter()
end

-- Keep the client's zoom levels when it supplies them. Older zone art has
-- only a fit-to-window level; the extra stops reuse that same texture layer.
local function enableZoom(scroll)
    local levels = scroll.zoomLevels
    if not levels or #levels ~= 1 then return end
    local first = levels[1]
    if not first.scale or first.scale <= 0 then return end
    for _, factor in ipairs({1.5, 2, 3, 4}) do
        levels[#levels + 1] = {scale=first.scale * factor, layerIndex=first.layerIndex}
    end
end

function addon.AttachMap()
    if provider then return true end
    if not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin or not addon.settings then
        return false
    end
    local map = WorldMapFrame
    Mixin(AeternumMapPinMixin, MapCanvasPinMixin, pins)
    addon.UI:Attach(map)
    local scroll = map.ScrollContainer
    if scroll and scroll.CreateZoomLevels then
        hooksecurefunc(scroll, "CreateZoomLevels", enableZoom)
        enableZoom(scroll)
        map:SetMouseWheelZoomMode(MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL)
    end
    provider = CreateFromMixins(MapCanvasDataProviderMixin, methods)
    map:AddDataProvider(provider)
    return true
end
