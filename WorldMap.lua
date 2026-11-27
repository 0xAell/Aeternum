local name, addon = ...

local template = "AeternumMapPinTemplate"
local pinLimit = 100
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

function pins:OnAcquired(entries)
    local entry = entries[1]
    self.entry = entry
    self.entries = entries
    self:SetSize(18, 18)
    local category = addon.categoryByID[entry.category]
    local red, green, blue = unpack(category.color)
    self.field:SetColorTexture(red, green, blue, .96)
    self.letter:SetText(category.letter)
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
    if entry then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.title)
        GameTooltip:AddLine(entry.subtitle, .84, .85, .9)
        for index = 2, math.min(4, #self.entries) do
            GameTooltip:AddLine(self.entries[index].title, .75, .78, .83)
        end
        if #self.entries > 4 then
            GameTooltip:AddLine(("+%d more at this location"):format(#self.entries - 4), .75, .78, .83)
        end
        if entry.category == "dungeon" then
            GameTooltip:AddLine("Click for floors, bosses, and directions", 1, .82, .45)
        end
        GameTooltip:Show()
    end
end

function pins:OnMouseLeave()
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

function pins:OnMouseClickAction(button)
    if button == "LeftButton" and self.entry then
        addon.UI:Select(self.entry)
    end
end

local providerMethods = {}

function providerMethods:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(template)
end

function providerMethods:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    if not map:IsShown() or not addon.UI:IsOpen() then
        return
    end
    local mapID = map:GetMapID()
    local query = addon.UI:GetSearch()
    local mapQuery = addon.UI:IsAtlas() and "" or query
    local entries = addon.Entries(mapID, false, mapQuery)
    local byPosition = {}
    local locations = {}
    for _, entry in ipairs(entries) do
        local position = ("%0.3f:%0.3f"):format(entry.x, entry.y)
        local group = byPosition[position]
        if group then
            group[#group + 1] = entry
        elseif #locations < pinLimit then
            group = { entry }
            locations[#locations + 1] = group
            byPosition[position] = group
        end
    end
    for _, group in ipairs(locations) do
        map:AcquirePin(template, group)
    end
    if addon.UI:IsAtlas() then
        entries = addon.Entries(mapID, true, query)
    end
    addon.UI:UpdateEntries(entries, mapID)
end

providerMethods.OnShow = providerMethods.RefreshAllData
providerMethods.OnHide = providerMethods.RemoveAllData

function addon.RefreshMap()
    if provider then
        provider:RefreshAllData()
    end
end

function addon.HighlightPin(entry)
    if not provider then
        return
    end
    for pin in provider:GetMap():EnumeratePinsByTemplate(template) do
        local size = 18
        for _, candidate in ipairs(pin.entries or {}) do
            if candidate == entry then
                size = 24
                break
            end
        end
        pin:SetSize(size, size)
    end
end

local function attach()
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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" and loaded == name then
        addon.LoadSettings()
    elseif event == "ADDON_LOADED" and loaded ~= "Blizzard_WorldMap" then
        return
    end
    attach()
end)

SLASH_AETERNUM1 = "/aeternum"
SlashCmdList.AETERNUM = function(message)
    if strtrim(message):lower() == "stop" then
        addon.Navigation:Stop()
        return
    end
    if not attach() and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_WorldMap")
    end
    if attach() then
        if not WorldMapFrame:IsShown() then
            ShowUIPanel(WorldMapFrame)
        end
        addon.UI:Show()
    else
        print("Aeternum: the world map is unavailable.")
    end
end
