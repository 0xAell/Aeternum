local name, addon = ...

local template = "AeternumMapPinTemplate"
local pinLimit = 100
local provider
local focusPin
local pins = {}

-- XML resolves this mixin when MapCanvas creates the first pin.
AeternumMapPinMixin = {}

local function applyPinStyle(pin, highlighted)
    local entry = pin.entry
    local category = entry and addon.categoryByID[entry.category]
    if category then
        local red, green, blue = unpack(category.color)
        pin.field:SetColorTexture(red, green, blue, .96)
        pin.letter:SetText(category.letter)
    end
    pin.highlighted = not not highlighted
    if pin.highlighted then
        pin.outline:SetColorTexture(1, .88, .42, 1)
        pin:SetSize(24, 24)
    else
        pin.outline:SetColorTexture(.06, .07, .1, .95)
        pin:SetSize(18, 18)
    end
end

function pins:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    local outline = self:CreateTexture(nil, "BACKGROUND")
    outline:SetAllPoints()
    outline:SetColorTexture(.06, .07, .1, .95)
    self.outline = outline
    local field = self:CreateTexture(nil, "ARTWORK")
    field:SetPoint("TOPLEFT", 1, -1)
    field:SetPoint("BOTTOMRIGHT", -1, 1)
    self.field = field
    self.letter = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.letter:SetPoint("CENTER", 0, 1)
    self.letter:SetTextColor(.08, .09, .12)
end

function pins:OnAcquired(entries)
    self.entries = entries
    self.activeIndex = 1
    self.entry = entries[1]
    applyPinStyle(self, false)
    self:SetPosition(self.entry.x, self.entry.y)
end

function pins:OnReleased()
    if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
    if focusPin == self then
        focusPin = nil
    end
    self.entry = nil
    self.entries = nil
    self.activeIndex = nil
    self.highlighted = nil
    MapCanvasPinMixin.OnReleased(self)
end

function pins:OnMouseEnter()
    local entry = self.entry
    if entry and GameTooltip then
        local count = #(self.entries or {})
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.title)
        GameTooltip:AddLine(entry.subtitle, .84, .85, .9)
        if count > 1 then
            local shown = 0
            for offset = 1, count - 1 do
                if shown >= 3 then
                    break
                end
                local index = (self.activeIndex - 1 + offset) % count + 1
                GameTooltip:AddLine(self.entries[index].title, .75, .78, .83)
                shown = shown + 1
            end
            if count - 1 > shown then
                GameTooltip:AddLine(("+%d more at this location"):format(count - 1 - shown), .75, .78, .83)
            end
            GameTooltip:AddLine(("Right-click to cycle (%d/%d)"):format(self.activeIndex, count), .62, .78, .92)
        end
        if entry.category == "dungeon" then
            GameTooltip:AddLine("Click for floors, bosses, and directions", 1, .82, .45)
        end
        GameTooltip:Show()
    end
end

function pins:OnMouseLeave()
    if GameTooltip and GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

function pins:OnMouseClickAction(button)
    if button == "RightButton" and self.entries and #self.entries > 1 then
        self.activeIndex = self.activeIndex % #self.entries + 1
        self.entry = self.entries[self.activeIndex]
        applyPinStyle(self, self.highlighted)
        self:OnMouseEnter()
    elseif button == "LeftButton" and self.entry then
        addon.UI:Select(self.entry)
    end
end

local providerMethods = {}

function providerMethods:RemoveAllData()
    focusPin = nil
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
    local totalLocations = 0
    for _, entry in ipairs(entries) do
        if entry.x and entry.y then
            local position = ("%0.3f:%0.3f"):format(entry.x, entry.y)
            local group = byPosition[position]
            if group then
                group[#group + 1] = entry
            elseif group == nil then
                totalLocations = totalLocations + 1
                if #locations < pinLimit then
                    group = { entry }
                    locations[#locations + 1] = group
                    byPosition[position] = group
                else
                    byPosition[position] = false
                end
            end
        end
    end
    for _, group in ipairs(locations) do
        map:AcquirePin(template, group)
    end
    if addon.UI:IsAtlas() then
        entries = addon.Entries(mapID, true, query)
    end
    addon.UI:UpdateEntries(entries, mapID, #locations, totalLocations)
end

providerMethods.OnShow = providerMethods.RefreshAllData
providerMethods.OnHide = providerMethods.RemoveAllData

function addon.RefreshMap()
    if provider then
        provider:RefreshAllData()
    end
end

function addon.HighlightPin(entry)
    if not provider or not entry then
        return
    end
    local map = provider:GetMap()
    if focusPin then
        if map.RemovePin then
            map:RemovePin(focusPin)
        else
            focusPin:Hide()
        end
        focusPin = nil
    end
    local matched = false
    for pin in map:EnumeratePinsByTemplate(template) do
        local isMatch = false
        for index, candidate in ipairs(pin.entries or {}) do
            if candidate == entry then
                pin.activeIndex = index
                pin.entry = candidate
                isMatch = true
                matched = true
                break
            end
        end
        applyPinStyle(pin, isMatch)
    end
    -- Entries omitted by pinLimit on dense city maps still get a temporary focus pin when selected.
    if not matched and entry.x and entry.y and entry.mapID == map:GetMapID() then
        focusPin = map:AcquirePin(template, { entry })
        if focusPin then
            applyPinStyle(focusPin, true)
        end
    end
end

local function attach()
    if provider then
        return true
    end
    addon.LoadSettings()
    if not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin then
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
    local trimmed = addon.Trim(message)
    local command = trimmed:lower()
    if command == "stop" then
        local wasActive = addon.Navigation:IsActive()
        addon.Navigation:Stop()
        print(wasActive and "Aeternum: entrance guidance stopped." or "Aeternum: entrance guidance is not active.")
        return
    elseif command == "help" then
        print("Aeternum commands: /aeternum [search text], /aeternum stop, /aeternum help")
        return
    end
    if not attach() and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_WorldMap")
    end
    if attach() then
        if not WorldMapFrame:IsShown() then
            if InCombatLockdown and InCombatLockdown() then
                print("Aeternum: cannot open the world map during combat.")
                return
            end
            ShowUIPanel(WorldMapFrame)
        end
        if trimmed ~= "" then
            addon.UI:SetSearch(trimmed)
        end
        addon.UI:Show()
    else
        print("Aeternum: the world map is unavailable.")
    end
end
