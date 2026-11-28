local _, addon = ...
local POINT, ENTRANCE = "AeternumMapPinTemplate", "AeternumEntrancePinTemplate"
local POINT_SIZE, ENTRANCE_SIZE, ENTRANCE_TARGET = 17, 30, 40
local OVERVIEW_SCALE, CLOSE_ZONE_WIDTH = .25, .6
local CELL_SIZE = 20
local provider, focus, marked, highlighted, highlightedQuestState
local pins = {}
AeternumMapPinMixin = {}

local function sizePin(pin, focused)
    local entrance = pin.entry.category == "dungeon"
    local compact = entrance and pin.compactEntrances
    local growth = focused and 6 or 0
    local iconSize = ((entrance and ENTRANCE_SIZE or POINT_SIZE) + growth) * (compact and OVERVIEW_SCALE or 1)
    local targetSize = entrance and not compact and (ENTRANCE_TARGET + growth) or iconSize
    pin.icon:SetSize(iconSize, iconSize)
    pin:SetSize(targetSize, targetSize)
    local badgeSize = compact and 5 or 10
    pin.tracked:SetSize(badgeSize, badgeSize)
    pin.tracked:SetPoint("BOTTOMRIGHT", pin.icon, "BOTTOMRIGHT", compact and 0 or 3, compact and 0 or -2)
    if pin.hoverGlow and not entrance then pin.hoverGlow:Hide() end
end

function pins:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1, 1.2)
    self.icon = self:CreateTexture(nil, "ARTWORK")
    self.icon:SetPoint("CENTER")
    self.tracked = self:CreateTexture(nil, "OVERLAY")
    self.tracked:SetAtlas("waypoint-mappin-minimap-tracked")
end

function pins:UpdateStyle()
    local best, bestScore, tracked = self.entries[1], -1, false
    for _, entry in ipairs(self.entries) do
        local dungeon = entry.category == "dungeon" and entry.source.id or nil
        local active = addon.Navigation:IsDestination(entry.point, dungeon)
        local score = 0
        if entry.category == "dungeon" then score = 10
        elseif entry.category ~= "quest" then score = 5
        elseif entry.role == "objective" then score = 3
        elseif entry.role == "turnin" then
            local state = addon.Quests:State(entry.questID)
            score = state == "ready" and 4 or (state == "active" and 2 or 0)
        end
        if active then tracked = true; score = score + 1 end
        if score > bestScore then best, bestScore = entry, score end
    end
    if self ~= marked and self.entry ~= best then
        self.entry = best
        self:SetPosition(best.x, best.y)
    end
    local icon, _, _, dim = addon.Presentation(self.entry)
    addon.SetIcon(self.icon, icon, dim)
    self.tracked:SetShown(tracked)
end

function pins:OnAcquired(entries, compactEntrances)
    self.entries, self.entry = entries, entries[1]
    self.compactEntrances = compactEntrances ~= false
    self:UpdateStyle()
    sizePin(self, false)
    self:SetPosition(self.entry.x, self.entry.y)
end

function pins:OnReleased()
    self:OnMouseLeave()
    if self == focus then focus = nil end
    if self == marked then marked = nil end
    self.entries, self.entry = nil, nil
    MapCanvasPinMixin.OnReleased(self)
end

local function showTooltip(pin)
    local entry = pin.entry
    if not entry then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.title)
    local _, _, text = addon.Presentation(entry)
    GameTooltip:AddLine(text)
    if #pin.entries > 1 then GameTooltip:AddLine(("%d map entries · Click to choose"):format(#pin.entries)) end
    if pin.tracked:IsShown() then GameTooltip:AddLine(addon.Navigation:GetStatus(), .7, .85, 1, true) end
    if entry.category == "dungeon" then
        if entry.point.hint then GameTooltip:AddLine(entry.point.hint, .9, .9, .9, true) end
        if #entry.source.keys > 0 then
            local names = {}
            for _, id in ipairs(entry.source.keys) do names[#names + 1] = addon.ItemName(id) end
            GameTooltip:AddLine("Keys · " .. table.concat(names, ", "), .85, .85, .85, true)
        end
        GameTooltip:AddLine("Click for floor map · Right-click for directions", 1, .82, 0)
    elseif entry.category ~= "quest" then
        GameTooltip:AddLine("Click for lessons and prices", 1, .82, 0)
    else
        if entry.role == "objective" and entry.subtitle ~= text then GameTooltip:AddLine(entry.subtitle) end
        if entry.contact then GameTooltip:AddLine(entry.contact, 1, 1, 1) end
        local requirement = addon.Quests:Requirement(entry.questID)
        if requirement then GameTooltip:AddLine(requirement) end
        addon.Quests:AddObjectives(GameTooltip, entry.questID, text)
    end
    GameTooltip:Show()
end

function pins:OnMouseEnter()
    if self.entry and self.entry.category == "dungeon" then
        if not self.hoverGlow then
            local glow = self:CreateTexture(nil, "BACKGROUND")
            glow:SetAtlas("UI-QuestPoi-OuterGlow")
            glow:SetPoint("TOPLEFT", self.icon, "TOPLEFT", -4, 4)
            glow:SetPoint("BOTTOMRIGHT", self.icon, "BOTTOMRIGHT", 4, -4)
            self.hoverGlow = glow
        end
        self.hoverGlow:Show()
    end
    showTooltip(self)
end

function pins:OnMouseLeave()
    if self.hoverGlow then self.hoverGlow:Hide() end
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

-- Each template has a fixed mouse policy in XML. Acquiring a pooled pin
-- in combat never needs to change protected passthrough settings.
function pins:CheckMouseButtonPassthrough() end

function pins:OnMouseClickAction(button)
    if not self.entry then return end
    if button == "LeftButton" then
        addon.UI:PickLocation(self, self.entries)
    elseif button == "RightButton" and self.entries[1].category == "dungeon" then
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

-- The share of the map in view, from the scroll container's read-only math. GetViewRect
-- would cache its result on Blizzard's scroll container from add-on code.
local function viewWidth(scroll)
    if not (scroll.CalculateViewRect and scroll.GetCanvasScale) then return 1 end
    local scale = scroll:GetCanvasScale()
    if not addon.IsReadableNumber(scale) or scale <= 0 then return 1 end
    local width = scroll:CalculateViewRect(scale):GetWidth()
    return addon.IsReadableNumber(width) and width > 0 and width or 1
end

local function layoutSize(map)
    local mapID, scroll = map:GetMapID(), map.ScrollContainer
    local width, height = scroll:GetSize()
    width = addon.IsReadableNumber(width) and width or 0
    height = addon.IsReadableNumber(height) and height or 0
    local range = mapID and viewWidth(scroll) or 1
    local scale = math.max(1, math.floor(2 / range + .5) / 2)
    local types = Enum and Enum.UIMapType
    local info = mapID and types and types.Zone and C_Map.GetMapInfo(mapID)
    local compact = not (info and info.mapType == types.Zone and range <= CLOSE_ZONE_WIDTH)
    local columns = math.max(1, math.floor(width * scale / CELL_SIZE))
    local rows = math.max(1, math.floor(height * scale / CELL_SIZE))
    return columns, rows, compact
end

function methods:Layout(entries)
    local map = self:GetMap()
    self:RemoveAllData()
    self.drawn = entries
    self.columns, self.rows, self.compactEntrances = layoutSize(map)
    local positions, groups = {}, {}
    local cells, entrances = {}, {}
    -- Group entrances whose click targets overlap at the current zoom.
    local entranceSpan = (self.compactEntrances and ENTRANCE_SIZE * OVERVIEW_SCALE or ENTRANCE_TARGET) / CELL_SIZE
    for _, entry in ipairs(entries) do
        local position = ("%.4f:%.4f"):format(entry.x, entry.y)
        local group = positions[position]
        if not group then
            local cell
            if entry.category == "dungeon" then
                for _, other in ipairs(entrances) do
                    local dx = math.abs(entry.x - other[1].x) * self.columns
                    local dy = math.abs(entry.y - other[1].y) * self.rows
                    if dx < entranceSpan and dy < entranceSpan then group = other; break end
                end
            else
                local kind = entry.category == "quest" and "q" or "t"
                cell = ("%s%d:%d"):format(kind, math.floor(entry.x * self.columns), math.floor(entry.y * self.rows))
                group = cells[cell]
            end
            if not group then
                group = {}
                groups[#groups + 1] = group
                if cell then
                    cells[cell] = group
                else
                    entrances[#entrances + 1] = group
                end
            end
            positions[position] = group
        end
        group[#group + 1] = entry
    end
    for _, group in ipairs(groups) do
        local template = group[1].category == "dungeon" and ENTRANCE or POINT
        map:AcquirePin(template, group, self.compactEntrances)
    end
    if highlighted then addon.FocusLocation(highlighted, true) end
end

function methods:RefreshAllData()
    local map = self:GetMap()
    if not map:IsShown() then self:RemoveAllData() return end
    self:Layout(addon.Entries(map:GetMapID(), false, ""))
end

function methods:OnCanvasScaleChanged()
    if self.layoutPending or not self.drawn then return end
    self.layoutPending = true
    C_Timer.After(.1, function()
        self.layoutPending = nil
        local map = self:GetMap()
        if not map:IsShown() or not self.drawn then return end
        local cols, rows, compact = layoutSize(map)
        if cols ~= self.columns or rows ~= self.rows or compact ~= self.compactEntrances then
            self:Layout(self.drawn)
        end
    end)
end
methods.OnCanvasSizeChanged = methods.OnCanvasScaleChanged

function methods:OnMapChanged()
    highlighted = nil
    addon.DungeonMap:Close()
    self:RefreshAllData()
    local waiting = addon.UI.waitingLocation
    if waiting and waiting.mapID == self:GetMap():GetMapID() then
        addon.UI.waitingLocation = nil
        addon.FocusLocation(waiting)
    end
end
function methods:OnHide()
    highlighted = nil
    addon.UI.waitingLocation = nil
    self:RemoveAllData()
end

function addon.RefreshMap()
    if provider then provider:RefreshAllData() end
end

local function refreshPin(pin)
    pin:UpdateStyle()
    if GameTooltip and GameTooltip:IsOwned(pin) then showTooltip(pin) end
end

function addon.UpdateRoutePins()
    if not provider or not provider:GetMap():IsShown() then return end
    for _, template in ipairs({POINT, ENTRANCE}) do
        for pin in provider:GetMap():EnumeratePinsByTemplate(template) do refreshPin(pin) end
    end
end

function addon.RefreshQuestStates()
    if not provider then return end
    local map = provider:GetMap()
    if not map:IsShown() then return end
    if highlighted and highlighted.questID and addon.Quests:State(highlighted.questID) ~= highlightedQuestState then
        addon.FocusLocation(nil)
    end
    local entries = addon.Entries(map:GetMapID(), false, "")
    local before = provider.drawn or {}
    if #entries ~= #before then provider:Layout(entries) return end
    for i, entry in ipairs(entries) do
        if before[i] ~= entry then provider:Layout(entries) return end
    end
    for pin in map:EnumeratePinsByTemplate(POINT) do refreshPin(pin) end
end

-- Marks entry on the map. quiet re-applies an existing focus after a redraw without
-- reopening its tooltip.
function addon.FocusLocation(entry, quiet)
    if not provider then return end
    local map = provider:GetMap()
    if focus then map:RemovePin(focus) end
    if marked then
        local old = marked
        marked = nil
        old:OnMouseLeave()
        old.entry = old.entries[1]
        old:SetPosition(old.entry.x, old.entry.y)
        old:UpdateStyle()
        sizePin(old, false)
    end
    highlighted = entry
    highlightedQuestState = entry and entry.questID and addon.Quests:State(entry.questID)
    if not entry or entry.mapID ~= map:GetMapID() then highlighted = nil return end
    local template = entry.category == "dungeon" and ENTRANCE or POINT
    for _, kind in ipairs({POINT, ENTRANCE}) do
        for pin in map:EnumeratePinsByTemplate(kind) do
            for _, other in ipairs(pin.entries) do
                if other == entry then
                    marked = pin
                    pin.entry = entry
                    pin:SetPosition(entry.x, entry.y)
                    pin:UpdateStyle()
                    sizePin(pin, true)
                    if not quiet then showTooltip(pin) end
                    return
                end
            end
        end
    end
    focus = map:AcquirePin(template, {entry}, provider.compactEntrances)
    sizePin(focus, true)
    if not quiet then showTooltip(focus) end
end

-- The map's zoom levels and wheel mode stay Blizzard's. Values the add-on writes into
-- them would be read by every Blizzard pin as it scales, and pins acquired that way in
-- combat fail their protected SetPassThroughButtons call.
function addon.AttachMap()
    if provider then return true end
    if not WorldMapFrame or not MapCanvasDataProviderMixin or not MapCanvasPinMixin or not addon.settings then
        return false
    end
    Mixin(AeternumMapPinMixin, MapCanvasPinMixin, pins)
    addon.UI:Attach(WorldMapFrame)
    provider = CreateFromMixins(MapCanvasDataProviderMixin, methods)
    WorldMapFrame:AddDataProvider(provider)
    return true
end
