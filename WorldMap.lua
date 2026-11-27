local _, addon = ...

local TEMPLATE = "AeternumMapPinTemplate"
local PIN_LIMIT, PIN_SIZE, FOCUS_SIZE = 150, 16, 22
local provider, highlightedPin, previewPin
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
    self:SetSize(PIN_SIZE, PIN_SIZE)
    self:UpdateStyle()
    self:SetPosition(self.entry.x, self.entry.y)
end

function pins:OnReleased()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    if self == highlightedPin then highlightedPin = nil end
    if self == previewPin then previewPin = nil end
    self.entry, self.entries = nil, nil
    MapCanvasPinMixin.OnReleased(self)
end

function pins:OnMouseEnter()
    local entry = self.entry
    if not entry then return end
    local _, _, subtitle = addon.Presentation(entry)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.title)
    GameTooltip:AddLine(subtitle, 1, 1, 1)
    if entry.questID then
        local requirement = addon.Quests:Requirement(entry.questID)
        if requirement then GameTooltip:AddLine(requirement, .8, .8, .8, true) end
    end
    local action
    if #self.entries > 1 then
        action = ("Choose from %d at this location"):format(#self.entries)
    elseif entry.category == "dungeon" then
        action = "Open dungeon guide"
    else
        action = "Guide to this location"
    end
    GameTooltip:AddLine(action, 1, .82, 0)
    GameTooltip:Show()
end

function pins:OnMouseLeave()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- The template sets right-button passthrough once. Our pins never need the
-- canvas to change that protected frame setting when a pin is recycled in combat.
function pins:CheckMouseButtonPassthrough() end

local function pick(entry)
    if entry.category == "dungeon" then
        addon.UI:Select(entry)
    else
        addon.UI:Guide(entry)
    end
end

function pins:OnMouseClickAction(button)
    if button ~= "LeftButton" or not self.entry then return end
    if #self.entries == 1 then
        pick(self.entry)
        return
    end
    local entries = self.entries
    MenuUtil.CreateContextMenu(self, function(_, menu)
        menu:CreateTitle("At this location")
        menu:SetScrollMode(260)
        for _, entry in ipairs(entries) do
            local title = entry.title
            if entry.questID then
                title = title .. (entry.role == "turnin" and " (turn-in)" or " (start)")
            end
            menu:CreateButton(title, function() pick(entry) end)
        end
    end)
end

local providerMethods = {}

function providerMethods:RemoveAllData()
    local map = self:GetMap()
    if map:GetNumActivePinsByTemplate(TEMPLATE) > 0 then map:RemoveAllPinsByTemplate(TEMPLATE) end
    self.drawn = nil
end

local function drawLocations(map, entries)
    local groups, positions, hidden = {}, {}, 0
    for _, entry in ipairs(entries) do
        local position = ("%.3f:%.3f"):format(entry.x, entry.y)
        local group = positions[position]
        if group then
            group[#group + 1] = entry
        elseif group == nil then
            if #groups < PIN_LIMIT then
                group = { entry }
                groups[#groups + 1] = group
                positions[position] = group
            else
                positions[position] = false
                hidden = hidden + 1
            end
        end
    end
    for _, group in ipairs(groups) do map:AcquirePin(TEMPLATE, group) end
    return hidden
end

local function mapEntries(map)
    local ui = addon.UI
    local query = ui:IsBrowsing() and not ui:IsAtlas() and ui:GetSearch() or ""
    return addon.Entries(map:GetMapID(), false, query)
end

local function refresh(self, keepScroll)
    self:RemoveAllData()
    local map, ui = self:GetMap(), addon.UI
    if not map:IsShown() then return end
    local browsing = ui:IsBrowsing()
    local showPins = addon.settings.showMapPins
    if showPins or (browsing and not ui:IsAtlas()) then self.drawn = mapEntries(map) end
    local hidden = showPins and drawLocations(map, self.drawn) or 0
    if browsing then
        local listed = ui:IsAtlas() and addon.Entries(map:GetMapID(), true, ui:GetSearch()) or self.drawn
        ui:UpdateEntries(listed, map:GetMapID(), hidden, keepScroll)
    end
    addon.HighlightPin(ui.selected)
end

function providerMethods:RefreshAllData()
    refresh(self, false)
end
providerMethods.OnHide = providerMethods.RemoveAllData

function addon.RefreshMap(keepScroll)
    if provider then refresh(provider, keepScroll) end
end

local function sameEntries(a, b)
    if #a ~= #b then return false end
    for index, entry in ipairs(a) do
        if entry ~= b[index] then return false end
    end
    return true
end

function addon.RefreshQuestStates()
    local map = provider and provider:GetMap()
    if not map or not map:IsShown() then return end
    if provider.drawn and not sameEntries(mapEntries(map), provider.drawn) then
        refresh(provider, true)
    else
        for pin in map:EnumeratePinsByTemplate(TEMPLATE) do pin:UpdateStyle() end
    end
    addon.UI:RefreshStates()
end

function addon.HighlightPin(entry)
    if not provider then return end
    local map = provider:GetMap()
    if not map:IsShown() then return end
    if entry and entry.mapID ~= map:GetMapID() then entry = nil end
    if highlightedPin then
        if highlightedPin.entry == entry then return end
        if previewPin then
            map:RemovePin(previewPin)
        else
            highlightedPin.entry = highlightedPin.entries[1]
            highlightedPin:UpdateStyle()
            highlightedPin:SetSize(PIN_SIZE, PIN_SIZE)
            highlightedPin = nil
        end
    end
    if not entry or not entry.x or not entry.y then return end
    for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
        for _, candidate in ipairs(pin.entries) do
            if candidate == entry then
                pin.entry = entry
                pin:UpdateStyle()
                pin:SetSize(FOCUS_SIZE, FOCUS_SIZE)
                highlightedPin = pin
                return
            end
        end
    end
    previewPin = map:AcquirePin(TEMPLATE, {entry})
    previewPin:SetSize(FOCUS_SIZE, FOCUS_SIZE)
    highlightedPin = previewPin
end

function addon.AttachMap()
    if provider then return true end
    if not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin or not addon.settings then
        return false
    end
    Mixin(AeternumMapPinMixin, MapCanvasPinMixin, pins)
    addon.UI:Attach(WorldMapFrame)
    provider = CreateFromMixins(MapCanvasDataProviderMixin, providerMethods)
    WorldMapFrame:AddDataProvider(provider)
    return true
end
