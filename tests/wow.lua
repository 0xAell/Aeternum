-- A small stand-in for the WoW client API, enough to load Aeternum and drive it.
-- Widget methods the addon calls must be listed here: an unknown method raises an
-- error, so a misspelt call fails the tests instead of passing silently.
local Wow = {}

local function noop() end

local function newClass(...)
    local class = {}
    for _, parent in ipairs({ ... }) do
        for key, value in pairs(parent) do
            class[key] = value
        end
    end
    return class
end

-- Lower-case keys are the addon's own fields and read as nil when unset, as on a
-- real frame. Capitalised keys are API methods and must exist.
local function strict(class, kind)
    return {
        __index = function(_, key)
            local method = class[key]
            if method == nil and type(key) == "string" and key:match("^%u") then
                error(("%s has no method %s"):format(kind, key), 2)
            end
            return method
        end,
    }
end

-- Regions ---------------------------------------------------------------------

local Region = {}

function Region:SetPoint(point, ...)
    self.points[#self.points + 1] = { point, ... }
end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints() self.points = { { "ALL" } } end
function Region:SetSize(width, height) self.width, self.height = width, height end
function Region:SetWidth(width) self.width = width end
function Region:SetHeight(height) self.height = height end
function Region:GetSize() return self.width, self.height end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:IsShown() return self.shown end
function Region:IsVisible()
    local region = self
    while region do
        if not region.shown then return false end
        region = region.parent
    end
    return true
end
function Region:GetParent() return self.parent end
function Region:Show()
    if not self.shown then
        self.shown = true
        if self.isFrame then self:Fire("OnShow") end
    end
end
function Region:Hide()
    if self.shown then
        self.shown = false
        if self.isFrame then self:Fire("OnHide") end
    end
end
function Region:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end

local Texture = newClass(Region)
function Texture:SetTexture(texture) self.texture = texture return true end
function Texture:SetColorTexture(...) self.color = { ... } end
function Texture:SetTexCoord(...) self.texCoord = { ... } end
function Texture:IsObjectLoaded() return true end

local Line = newClass(Texture)
function Line:SetThickness(value) self.thickness = value end
function Line:SetStartPoint(...) self.startPoint = { ... } end
function Line:SetEndPoint(...) self.endPoint = { ... } end

local FontString = newClass(Region)
function FontString:SetText(text) self.text = text end
function FontString:GetText() return self.text end
function FontString:SetTextColor(...) self.textColor = { ... } end
function FontString:SetJustifyH(value) self.justify = value end
function FontString:SetWordWrap() end
function FontString:SetMaxLines() end

-- Frames ----------------------------------------------------------------------

local Frame = newClass(Region)

function Frame:SetScript(event, handler) self.scripts[event] = handler end
function Frame:GetScript(event) return self.scripts[event] end
function Frame:HookScript(event, handler)
    local previous = self.scripts[event]
    self.scripts[event] = function(...)
        if previous then previous(...) end
        return handler(...)
    end
end
function Frame:Fire(event, ...)
    local handler = self.scripts[event]
    if handler then
        return handler(self, ...)
    end
end
function Frame:SetFrameStrata(value) self.strata = value end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:SetFrameLevel(value) self.level = value end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetClampedToScreen() end
function Frame:EnableMouse() end
function Frame:RegisterEvent(event)
    if not Wow.knownEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"", 2)
    end
    self.events[event] = true
end
function Frame:CreateTexture() return Wow.region(Texture, self) end
function Frame:CreateFontString() return Wow.region(FontString, self) end
function Frame:CreateLine() return Wow.region(Line, self) end

local Button = newClass(Frame)
function Button:SetText(text) self.text = text end
function Button:GetText() return self.text end
function Button:SetEnabled(enabled) self.enabled = not not enabled end
function Button:IsEnabled() return self.enabled ~= false end
function Button:RegisterForClicks(...) self.clicks = { ... } end
function Button:Click(button)
    if self:IsEnabled() then
        self:Fire("OnClick", button or "LeftButton")
    end
end

local CheckButton = newClass(Button)
function CheckButton:SetChecked(checked) self.checked = not not checked end
function CheckButton:GetChecked() return self.checked end
function CheckButton:Click(button)
    if self:IsEnabled() then
        self.checked = not self.checked
        self:Fire("OnClick", button or "LeftButton")
    end
end

local EditBox = newClass(Frame)
function EditBox:SetText(text)
    self.text = text
    self:Fire("OnTextChanged", true)
end
function EditBox:GetText() return self.text or "" end
function EditBox:SetAutoFocus() end
function EditBox:SetMaxLetters() end
function EditBox:ClearFocus() end

local ScrollFrame = newClass(Frame)
function ScrollFrame:SetScrollChild(child) self.child = child end
function ScrollFrame:GetVerticalScroll() return self.scroll or 0 end
function ScrollFrame:SetVerticalScroll(value)
    self.scroll = value
    self:Fire("OnVerticalScroll", value)
end

local MessageFrame = newClass(Frame)
function MessageFrame:AddMessage(text) Wow.state.messages[#Wow.state.messages + 1] = text end

local Tooltip = newClass(Frame)
function Tooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function Tooltip:IsOwned(owner) return self.shown and self.owner == owner end
function Tooltip:SetText(text) self.lines = { text } end
function Tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function Tooltip:SetItemByID(itemID) self.lines = { "item:" .. itemID } end
function Tooltip:SetHyperlink(link) self.lines = { link } end

local classes = {
    Frame = Frame, Button = Button, CheckButton = CheckButton, EditBox = EditBox,
    ScrollFrame = ScrollFrame,
}

function Wow.region(class, parent)
    local region = setmetatable({
        points = {}, scripts = {}, events = {}, shown = true, parent = parent,
        width = 300, height = 400, isFrame = class.Fire ~= nil,
    }, strict(class, "widget"))
    return region
end

-- Map canvas ------------------------------------------------------------------

local MapCanvas = newClass(Frame)
function MapCanvas:GetMapID() return self.mapID end
function MapCanvas:SetMapID(mapID)
    self.mapID = mapID
    for _, provider in ipairs(self.providers) do
        provider:OnMapChanged()
    end
end
function MapCanvas:AddDataProvider(provider)
    self.providers[#self.providers + 1] = provider
    provider:OnAdded(self)
end
function MapCanvas:AcquirePin(template, ...)
    local pool = self.pools[template]
    local pin = table.remove(pool.free)
    if not pin then
        pin = Wow.CreateFrame("Frame", nil, self, template)
    end
    pool.active[#pool.active + 1] = pin
    pin:OnAcquired(...)
    return pin
end
function MapCanvas:RemoveAllPinsByTemplate(template)
    local pool = self.pools[template]
    for _, pin in ipairs(pool.active) do
        pin:OnReleased()
        pool.free[#pool.free + 1] = pin
    end
    pool.active = {}
end
function MapCanvas:EnumeratePinsByTemplate(template)
    local index = 0
    local active = self.pools[template].active
    return function()
        index = index + 1
        return active[index]
    end
end
function MapCanvas:Show()
    Region.Show(self)
    for _, provider in ipairs(self.providers) do provider:OnShow() end
end
function MapCanvas:Hide()
    Region.Hide(self)
    for _, provider in ipairs(self.providers) do provider:OnHide() end
end

-- World model -----------------------------------------------------------------

-- Each map is a rectangle on a continent. As in the client, world X grows north
-- and world Y grows west, while map x grows east and map y grows south.
Wow.maps = {
    [1429] = { name = "Elwynn Forest", continent = 0, north = 0, west = 0, width = 3000, height = 2000 },
    [1436] = { name = "Westfall", continent = 0, north = -2000, west = 1000, width = 3500, height = 2300 },
    [1453] = { name = "Stormwind City", continent = 0, north = 500, west = 700, width = 1300, height = 900 },
    [1454] = { name = "Orgrimmar", continent = 1, north = 0, west = 0, width = 1700, height = 1100 },
}

local function mapFor(mapID)
    return Wow.maps[mapID]
        or { name = "Map " .. mapID, continent = 9, north = 0, west = 0, width = 1000, height = 1000 }
end

function Wow.worldPosition(mapID, x, y)
    local map = mapFor(mapID)
    return map.continent, map.north - y * map.height, map.west - x * map.width
end

-- Environment -----------------------------------------------------------------

Wow.knownEvents = {
    ADDON_LOADED = true, PLAYER_LOGIN = true, GET_ITEM_INFO_RECEIVED = true, QUEST_LOG_UPDATE = true,
    QUEST_ACCEPTED = true, QUEST_TURNED_IN = true, QUEST_REMOVED = true, PLAYER_LEVEL_UP = true,
}

local templates = {
    UIPanelButtonTemplate = true, UIPanelCloseButton = true, UICheckButtonTemplate = true,
    InputBoxTemplate = true, UIPanelScrollFrameTemplate = true,
}

function Wow.CreateFrame(kind, _, parent, template)
    local class = classes[kind] or error("unsupported frame type " .. tostring(kind))
    local frame = Wow.region(class, parent)
    Wow.state.frames[#Wow.state.frames + 1] = frame
    if template == "AeternumMapPinTemplate" then
        -- Mirrors WorldMap.xml: an 18x18 mouse-enabled frame with the pin mixin.
        local env = Wow.env
        for key, value in pairs(env.AeternumMapPinMixin) do
            frame[key] = value
        end
        frame:SetSize(18, 18)
        frame:OnLoad()
    elseif template and not templates[template] then
        error("unknown template " .. template)
    end
    return frame
end

function Wow.new(state)
    local env = setmetatable({}, { __index = _G })
    Wow.env = env
    Wow.state = state
    state.frames, state.messages, state.timers = {}, {}, {}
    state.completed, state.log, state.complete = state.completed or {}, state.log or {}, state.complete or {}
    state.cached = state.cached or {}

    env.CreateFrame = Wow.CreateFrame
    env.UIParent = Wow.region(Frame)
    env.UIParent:SetSize(1920, 1080)
    env.Minimap = Wow.region(Frame)
    env.Minimap:SetSize(140, 140)
    env.GameTooltip = Wow.region(Tooltip)
    env.GameTooltip:Hide()
    env.DEFAULT_CHAT_FRAME = Wow.region(MessageFrame)
    env.SlashCmdList = {}
    env.AeternumDB = state.savedVariables

    env.strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
    env.Mixin = function(object, ...)
        for _, mixin in ipairs({ ... }) do
            for key, value in pairs(mixin) do object[key] = value end
        end
        return object
    end
    env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
    env.CreateVector2D = function(x, y) return { x = x, y = y } end
    env.ShowUIPanel = function(frame) frame:Show() end
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() return state.inInstance or false end
    env.GetPlayerFacing = function() return state.facing or 0 end
    env.UnitFactionGroup = function() return state.faction or "Alliance" end
    env.UnitLevel = function() return state.level or 1 end
    env.UnitRace = function() return "Human", "Human", state.raceID or 1 end
    env.UnitClass = function() return "Warrior", state.class or "WARRIOR", 1 end
    env.GetQuestGreenRange = function() return 5 end
    env.IsModifiedClick = function() return state.modified or false end
    env.HandleModifiedItemClick = function(link)
        state.modifiedClick = link
        return true
    end
    env.SetItemRef = function(link, text) state.itemRef = { link, text } end
    env.ITEM_QUALITY_COLORS = { [4] = { r = .64, g = .21, b = .93 } }

    env.C_Timer = {
        After = function(_, callback) state.timers[#state.timers + 1] = callback end,
        NewTimer = function(_, callback)
            local timer = { Cancel = noop, callback = callback }
            return timer
        end,
    }
    env.C_CVar = { GetCVarBool = function(name) return name == "rotateMinimap" and state.rotate or false end }
    env.C_Minimap = { GetViewRadius = function() return 200 end }
    env.C_AddOns = { LoadAddOn = noop }
    env.C_Item = {
        GetItemNameByID = function(itemID) return state.cached[itemID] and ("Cached " .. itemID) or nil end,
        GetItemQualityByID = function(itemID) return state.cached[itemID] and 4 or nil end,
        GetItemIconByID = function(itemID) return 1000000 + itemID end,
        GetItemInfo = function(itemID)
            if state.cached[itemID] then
                return "Cached " .. itemID, "|Hitem:" .. itemID .. "|h[Cached " .. itemID .. "]|h"
            end
        end,
        RequestLoadItemDataByID = function(itemID)
            state.requested = state.requested or {}
            state.requested[itemID] = true
        end,
    }
    env.C_QuestLog = {
        IsQuestFlaggedCompleted = function(questID) return state.completed[questID] or false end,
        GetLogIndexForQuestID = function(questID) return state.log[questID] end,
        IsComplete = function(questID) return state.complete[questID] or false end,
    }
    env.C_Map = {
        GetMapInfo = function(mapID) return { name = mapFor(mapID).name } end,
        GetBestMapForUnit = function() return state.playerMap end,
        GetPlayerMapPosition = function()
            if state.playerX then return { x = state.playerX, y = state.playerY } end
        end,
        GetWorldPosFromMapPos = function(mapID, vector)
            local continent, worldX, worldY = Wow.worldPosition(mapID, vector.x, vector.y)
            return continent, { x = worldX, y = worldY }
        end,
    }

    env.MapCanvasDataProviderMixin = {
        OnAdded = function(self, map) self.owningMap = map end,
        GetMap = function(self) return self.owningMap end,
        OnMapChanged = function(self) self:RefreshAllData() end,
        OnShow = noop, OnHide = noop, RefreshAllData = noop, RemoveAllData = noop,
    }
    env.MapCanvasPinMixin = {
        OnReleased = noop,
        UseFrameLevelType = noop,
        SetPosition = function(self, x, y) self.x, self.y = x, y end,
    }
    local map = Wow.region(MapCanvas, env.UIParent)
    map.providers, map.pools = {}, setmetatable({}, {
        __index = function(pools, template)
            local pool = { active = {}, free = {} }
            pools[template] = pool
            return pool
        end,
    })
    map.mapID = state.mapID or 1429
    map.shown = false
    map.strata = state.mapStrata or "HIGH"
    env.WorldMapFrame = map
    return env
end

-- Runs queued C_Timer.After callbacks.
function Wow.flushTimers()
    local timers = Wow.state.timers
    Wow.state.timers = {}
    for _, callback in ipairs(timers) do
        callback()
    end
end

-- Fires an event at every frame registered for it.
function Wow.fire(event, ...)
    for _, frame in ipairs(Wow.state.frames) do
        if frame.events[event] then
            frame:Fire("OnEvent", event, ...)
        end
    end
end

return Wow
