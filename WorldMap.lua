local _, addon = ...

local TEMPLATE = "AeternumMapPinTemplate"
local PIN_LIMIT = 150
local PIN_SIZE, SELECTED_PIN_SIZE = 18, 24
local TOOLTIP_ROWS = 4
local provider
local pins = {}

-- XML resolves this mixin when MapCanvas creates the first pin.
AeternumMapPinMixin = {}

function pins:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    local outline = self:CreateTexture(nil, "BACKGROUND")
    outline:SetAllPoints()
    outline:SetColorTexture(.06, .07, .1, .95)
    local field = self:CreateTexture(nil, "ARTWORK")
    field:SetPoint("TOPLEFT", 1, -1)
    field:SetPoint("BOTTOMRIGHT", -1, 1)
    self.field = field
    self.letter = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.letter:SetPoint("CENTER", 0, 1)
    self.letter:SetTextColor(.08, .09, .12)
end

function pins:UpdateStyle()
    local letter, color = addon.Presentation(self.entry)
    local red, green, blue = unpack(color)
    self.field:SetColorTexture(red, green, blue, .96)
    self.letter:SetText(letter)
end

function pins:OnAcquired(entries)
    local entry = entries[1]
    self.entry = entry
    self.entries = entries
    self:SetSize(PIN_SIZE, PIN_SIZE)
    self:UpdateStyle()
    self:SetPosition(entry.x, entry.y)
end

function pins:OnReleased()
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
    self.entry = nil
    self.entries = nil
    MapCanvasPinMixin.OnReleased(self)
end

function pins:OnMouseEnter()
    local entry = self.entry
    if not entry then
        return
    end
    local _, _, subtitle = addon.Presentation(entry)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.title)
    GameTooltip:AddLine(subtitle, .84, .85, .9)
    if entry.questID then
        local requirement = addon.Quests:Requirement(entry.questID)
        if requirement then
            GameTooltip:AddLine(requirement, .75, .78, .83)
        end
    end
    for index = 2, math.min(TOOLTIP_ROWS, #self.entries) do
        local other = self.entries[index]
        local _, color = addon.Presentation(other)
        GameTooltip:AddLine(other.title, color[1], color[2], color[3])
    end
    if #self.entries > TOOLTIP_ROWS then
        GameTooltip:AddLine(("+%d more at this location"):format(#self.entries - TOOLTIP_ROWS), .75, .78, .83)
    end
    if entry.category == "dungeon" then
        GameTooltip:AddLine("Click for floors, bosses, loot, and quests", 1, .82, .45)
    end
    GameTooltip:AddLine("Right-click to guide the minimap arrow here", 1, .82, .45)
    GameTooltip:Show()
end

function pins:OnMouseLeave()
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

function pins:OnMouseClickAction(button)
    if not self.entry then
        return
    end
    if button == "RightButton" then
        addon.UI:Guide(self.entry)
    elseif button == "LeftButton" then
        addon.UI:Select(self.entry)
    end
end

-- Older map canvases call OnClick rather than OnMouseClickAction; each calls only one.
pins.OnClick = pins.OnMouseClickAction

local providerMethods = {}

function providerMethods:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

local function showPins()
    return addon.UI:IsOpen() or addon.settings.pinsWithPanelClosed
end

-- Groups records that share a location so each spot gets one pin, and counts
-- the locations left off past the pin limit.
local function locations(entries)
    local byPosition, result, hidden = {}, {}, 0
    for _, entry in ipairs(entries) do
        local position = ("%0.3f:%0.3f"):format(entry.x, entry.y)
        local group = byPosition[position]
        if group then
            group[#group + 1] = entry
        elseif #result < PIN_LIMIT then
            group = { entry }
            result[#result + 1] = group
            byPosition[position] = group
        else
            byPosition[position] = {}
            hidden = hidden + 1
        end
    end
    return result, hidden
end

local function pinEntries(map)
    local query = addon.UI:IsOpen() and not addon.UI:IsAtlas() and addon.UI:GetSearch() or ""
    return addon.Entries(map:GetMapID(), false, query)
end

local function sameEntries(a, b)
    if not a or not b or #a ~= #b then
        return false
    end
    for index = 1, #a do
        if a[index] ~= b[index] then
            return false
        end
    end
    return true
end

local function refresh(self, keepScroll)
    self:RemoveAllData()
    self.drawn = nil
    local map = self:GetMap()
    if not map:IsShown() or not showPins() then
        return
    end
    addon.UI:Layer()
    local mapID = map:GetMapID()
    local entries = pinEntries(map)
    local groups, hidden = locations(entries)
    for _, group in ipairs(groups) do
        map:AcquirePin(TEMPLATE, group)
    end
    self.drawn = entries
    if addon.UI:IsOpen() then
        local listed = entries
        if addon.UI:IsAtlas() then
            listed = addon.Entries(mapID, true, addon.UI:GetSearch())
        end
        addon.UI:UpdateEntries(listed, mapID, hidden, keepScroll)
    end
    addon.HighlightPin(addon.UI.selected)
end

function providerMethods:RefreshAllData()
    refresh(self, false)
end

providerMethods.OnShow = providerMethods.RefreshAllData
providerMethods.OnHide = providerMethods.RemoveAllData

function addon.RefreshMap()
    if provider then
        provider:RefreshAllData()
    end
end

-- After quest progress. Quest log events are frequent, so pins and rows are
-- restyled in place while the same records stay visible; otherwise the map is
-- redrawn without moving the list.
function addon.RefreshQuestStates()
    local map = provider and provider:GetMap()
    if map and map:IsShown() and showPins() then
        if not sameEntries(pinEntries(map), provider.drawn) then
            refresh(provider, true)
            return
        end
        for pin in map:EnumeratePinsByTemplate(TEMPLATE) do
            pin:UpdateStyle()
        end
    end
    addon.UI:RefreshStates()
end

function addon.HighlightPin(entry)
    if not provider then
        return
    end
    for pin in provider:GetMap():EnumeratePinsByTemplate(TEMPLATE) do
        local size = PIN_SIZE
        for _, candidate in ipairs(pin.entries or {}) do
            if candidate == entry then
                size = SELECTED_PIN_SIZE
                break
            end
        end
        pin:SetSize(size, size)
    end
end

-- Adds the sidebar and pins once both the saved settings and the world map exist.
function addon.AttachMap()
    if provider then
        return true
    end
    if not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin or not addon.settings then
        return false
    end
    Mixin(AeternumMapPinMixin, MapCanvasPinMixin, pins)
    addon.UI:Attach(WorldMapFrame)
    provider = CreateFromMixins(MapCanvasDataProviderMixin, providerMethods)
    WorldMapFrame:AddDataProvider(provider)
    return true
end
