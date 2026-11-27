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
    for index, existing in ipairs(self.points) do
        if existing[1] == point then
            self.points[index] = { point, ... }
            return
        end
    end
    self.points[#self.points + 1] = { point, ... }
end
function Region:ClearAllPoints() self.points = {} end
function Region:SetAllPoints(relative)
    relative = relative or self.parent
    self.points = { { "ALL", relative } }
    if relative then self.width, self.height = relative:GetSize() end
end
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
function Region:GetRight() return self.right end
function Region:GetLeft() return self.left end
function Region:GetTop() return self.top end
function Region:SetScale(scale) self.scale = scale end
function Region:GetEffectiveScale() return self.scale or 1 end
local function visibilityChanged(region, event)
    if region.isFrame then region:Fire(event) end
    for _, child in ipairs(region.children) do
        if child.shown then visibilityChanged(child, event) end
    end
end
function Region:Show()
    if not self.shown then
        self.shown = true
        if self:IsVisible() then visibilityChanged(self, "OnShow") end
    end
end
function Region:Hide()
    if self.shown then
        local wasVisible = self:IsVisible()
        self.shown = false
        if wasVisible then visibilityChanged(self, "OnHide") end
    end
end
function Region:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end

local Texture = newClass(Region)
function Texture:SetTexture(texture)
    self.texture, self.atlas = texture, nil
    return not (Wow.state.missingTextures and Wow.state.missingTextures[texture])
end
function Texture:SetAtlas(atlas) self.atlas, self.texture = atlas, nil end
function Texture:SetDesaturated(dim) self.desaturated = dim end
function Texture:SetAlpha(alpha) self.alpha = alpha end
function Texture:SetRotation(angle) self.rotation = angle end
function Texture:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
function Texture:SetBlendMode(mode) self.blend = mode end
function Texture:SetColorTexture(...) self.color = { ... } end
function Texture:SetTexCoord(...) self.texCoord = { ... } end
function Texture:IsObjectLoaded() return true end

local FontString = newClass(Region)
function FontString:SetText(text) self.text = text end
function FontString:GetText() return self.text end
function FontString:SetTextColor(...) self.textColor = { ... } end
function FontString:SetJustifyH(value) self.justify = value end
function FontString:SetWordWrap() end
function FontString:SetMaxLines() end

-- Frames ----------------------------------------------------------------------

local Frame = newClass(Region)
local Line = newClass(Texture)
function Line:SetThickness(n) self.thickness = n end
function Line:SetStartPoint(...) self.start = {...} end
function Line:SetEndPoint(...) self.finish = {...} end
function Frame:CreateLine() return Wow.region(Line, self) end
function Frame:SetClipsChildren(value) self.clipped = value end

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
function Frame:SetAlpha(value) self.alpha = value end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:SetFrameLevel(value) self.level = value end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetClampedToScreen() end
function Frame:SetMovable(movable) self.movable = movable end
function Frame:SetDontSavePosition(value) self.dontSavePosition = value end
function Frame:RegisterForDrag(...) self.dragButtons = { ... } end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:EnableMouse() end
function Frame:EnableMouseWheel() end
function Frame:SetScalingLimits(...) self.scalingLimits = { ... } end
-- Protected: like the client, it fails for add-on code in combat.
function Frame:SetPassThroughButtons(...)
    if Wow.state.inCombat then
        error("Interface action failed because of an AddOn", 2)
    end
    self.passThrough = { ... }
end
function Frame:RegisterEvent(event)
    if not Wow.knownEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"", 2)
    end
    self.events[event] = true
end
function Frame:CreateTexture() return Wow.region(Texture, self) end
function Frame:CreateFontString() return Wow.region(FontString, self) end

local Button = newClass(Frame)
function Button:SetText(text) self.text = text end
function Button:GetText() return self.text end
function Button:SetEnabled(enabled) self.enabled = not not enabled end
function Button:IsEnabled() return self.enabled ~= false end
function Button:RegisterForClicks(...) self.clicks = { ... } end
function Button:LockHighlight() self.highlighted = true end
function Button:UnlockHighlight() self.highlighted = false end
function Button:SetNormalTexture(texture) self.normal = texture end
function Button:SetHighlightTexture(texture, blend) self.highlight, self.highlightBlend = texture, blend end
function Button:SetPushedTexture(texture) self.pushed = texture end
function Button:SetDisabledTexture(texture) self.disabled = texture end
function Button:Click(button)
    if self:IsEnabled() then
        self:Fire("OnClick", button or "LeftButton")
    end
end

local Description = {}
Description.__index = Description
local function description(label, checked, action)
    return setmetatable({label = label, checked = checked, action = action, children = {}}, Description)
end
function Description:CreateCheckbox(label, checked, action)
    local child = description(label, checked, action)
    self.children[#self.children + 1] = child
    return child
end
Description.CreateRadio = Description.CreateCheckbox
function Description:CreateButton(label, action) return self:CreateCheckbox(label, nil, action) end
function Description:CreateTitle(label) return self:CreateButton(label) end
function Description:CreateDivider() return self:CreateButton("") end
function Description:SetEnabled(value) self.enabled = value end
function Description:SetTooltip(fn) self.tooltip = fn end
function Description:SetScrollMode(value) self.scrollHeight = value end
function Description:Find(text)
    for _, child in ipairs(self.children) do
        if child.label == text then return child end
    end
    error("Missing menu entry " .. text)
end
function Description:Click()
    if self.enabled ~= false then self.action() end
end

local Dropdown = newClass(Button)
function Dropdown:SetupMenu(generator) self.generator = generator end
function Dropdown:OverrideText(text) self:SetText(text) end
function Dropdown:OpenMenu()
    local menu = description()
    self.generator(self, menu)
    return menu
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

local MessageFrame = newClass(Frame)
function MessageFrame:AddMessage(text) Wow.state.messages[#Wow.state.messages + 1] = text end

local ScrollBar = newClass(Frame)
function ScrollBar:RegisterCallback(event, func, owner)
    self.scripts[event] = function(value) func(owner, value) end
end
function ScrollBar:SetScrollPercentage(value)
    self.value = value
    if self.scripts.OnScroll then self.scripts.OnScroll(value) end
end
function ScrollBar:SetVisibleExtentPercentage(value) self.visibleExtent = value end
function ScrollBar:SetPanExtentPercentage(value) self.panExtent = value end

local Tooltip = newClass(Frame)
function Tooltip:SetOwner(owner) self.owner, self.lines = owner, {} end
function Tooltip:IsOwned(owner) return self.shown and self.owner == owner end
function Tooltip:SetText(text) self.lines = { text } end
function Tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
function Tooltip:SetItemByID(itemID) self.lines = { "item:" .. itemID } end
function Tooltip:SetSpellByID(id) self.lines = { "spell:" .. id } end
function Tooltip:SetHyperlink(link) self.lines = { link } end

local classes = {
    Frame = Frame, Button = Button, DropdownButton = Dropdown, EditBox = EditBox, EventFrame = ScrollBar,
}

function Wow.region(class, parent)
    local region = setmetatable({
        points = {}, scripts = {}, events = {}, children = {}, shown = true, parent = parent,
        width = 300, height = 400, isFrame = class.Fire ~= nil,
    }, strict(class, "widget"))
    if parent then parent.children[#parent.children + 1] = region end
    return region
end

-- Map canvas ------------------------------------------------------------------

local MapCanvas = newClass(Frame)
-- Blizzard sets the wheel mode once at load; any later write comes from add-on code.
function MapCanvas:SetMouseWheelZoomMode(mode)
    self.ScrollContainer.mouseWheelZoomMode = mode
    Wow.state.wheelModeWritten = true
end
function MapCanvas:GetMapID() return self.mapID end
function MapCanvas:PanTo(x, y) self.panX, self.panY = x, y end
function MapCanvas:SetMapID(mapID)
    self.mapID = mapID
    self.ScrollContainer:CreateZoomLevels()
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
    pin:CheckMouseButtonPassthrough("RightButton")
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
function MapCanvas:RemovePin(pin)
    local pool = self.pools[pin.template]
    for i, active in ipairs(pool.active) do
        if active == pin then
            table.remove(pool.active, i)
            pin:OnReleased()
            pool.free[#pool.free + 1] = pin
            return
        end
    end
end
function MapCanvas:EnumeratePinsByTemplate(template)
    local index = 0
    local active = self.pools[template].active
    return function()
        index = index + 1
        return active[index]
    end
end
function MapCanvas:GetNumActivePinsByTemplate(template) return #self.pools[template].active end
function MapCanvas:GetViewRect()
    return {GetWidth=function() return Wow.state.viewWidth or 1 end}
end
-- As in WorldMapMixin: the map's own OnShow and OnHide notify the data providers,
-- scripts hooked by add-ons run afterwards, and shown children follow the map.
function MapCanvas:Show()
    if self.shown then return end
    self.shown = true
    for _, provider in ipairs(self.providers) do provider:RefreshAllData(true) end
    for _, provider in ipairs(self.providers) do provider:OnShow() end
    self:Fire("OnShow")
    for _, child in ipairs(self.children) do
        if child.shown then visibilityChanged(child, "OnShow") end
    end
end

-- A mouse click as the canvas routes it: passed through to the map, or to the pin.
function MapCanvas:ClickPin(pin, button, offsetX, offsetY)
    if math.abs(offsetX or 0) > pin:GetWidth() / 2 or math.abs(offsetY or 0) > pin:GetHeight() / 2 then return end
    for _, passed in ipairs(pin.passThrough or {}) do
        if passed == button then
            if button == "RightButton" then self.zoomedOut = true end
            return
        end
    end
    pin:OnClick(button)
end
function MapCanvas:Hide()
    if not self.shown then return end
    self.shown = false
    for _, provider in ipairs(self.providers) do provider:OnHide() end
    self:Fire("OnHide")
    -- Shown children become invisible with the map and get OnHide too.
    for _, child in ipairs(self.children) do
        if child.shown then visibilityChanged(child, "OnHide") end
    end
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
    UI_SCALE_CHANGED = true, DISPLAY_SIZE_CHANGED = true,
    TRAINER_SHOW = true, TRAINER_UPDATE = true, SKILL_LINES_CHANGED = true, PLAYER_ENTERING_WORLD = true,
    LEARNED_SPELL_IN_SKILL_LINE = true, ZONE_CHANGED_INDOORS = true, ZONE_CHANGED = true,
    BOSS_KILL = true, ENCOUNTER_END = true, TRAINER_SERVICE_INFO_NAME_UPDATE = true,
    QUEST_WATCH_LIST_CHANGED = true, SUPER_TRACKING_CHANGED = true, QUEST_POI_UPDATE = true, CVAR_UPDATE = true,
    ITEM_DATA_LOAD_RESULT = true, SPELLS_CHANGED = true,
}

local templates = { UIPanelButtonTemplate = true, PanelTopTabButtonTemplate = true, MinimalScrollBar = true,
    WowStyle1DropdownTemplate = true, WowStyle1FilterDropdownTemplate = true }

local pinXML = assert(io.open("WorldMap.xml", "r"))
local pinPolicy = {}
for template, attrs in pinXML:read("*a"):gmatch('<Frame name="([^"]+)"([^>]*)>') do
    pinPolicy[template] = {attrs:match('passThroughButtons="([^"]+)"')}
end
pinXML:close()

function Wow.CreateFrame(kind, _, parent, template)
    local class = classes[kind] or error("unsupported frame type " .. tostring(kind))
    local frame = Wow.region(class, parent)
    frame.template = template
    Wow.state.frames[#Wow.state.frames + 1] = frame
    if pinPolicy[template] then
        -- The XML applies passthrough at construction, before the pool acquires the frame.
        local env = Wow.env
        for key, value in pairs(env.AeternumMapPinMixin) do
            frame[key] = value
        end
        frame.passThrough = pinPolicy[template]
        frame:OnLoad()
    elseif template == "BasicFrameTemplateWithInset" then
        frame.TitleText = frame:CreateFontString()
        frame.CloseButton = Wow.CreateFrame("Button", nil, frame)
    elseif template == "SearchBoxTemplate" then
        frame.Instructions = frame:CreateFontString()
        frame.clearButton = Wow.CreateFrame("Button", nil, frame)
        frame.searchIcon = frame:CreateTexture()
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
    state.menuHooks = {}
    state.completed, state.log, state.complete = state.completed or {}, state.log or {}, state.complete or {}
    state.cached = state.cached or {}

    env.CreateFrame = Wow.CreateFrame
    env.BaseScrollBoxEvents = { OnScroll = "OnScroll" }
    env.Menu = { ModifyMenu = function(tag, callback) state.menuHooks[tag] = callback end }
    env.MenuUtil = {SetElementText = function(row, label) row.label = label end}
    env.MenuUtil.CreateContextMenu = function(owner, generator)
        if state.menuProxy and state.menuProxy.closed then state.menuProxy.closed() end
        state.menu = description()
        generator(owner, state.menu)
        local proxy = {refreshes=0}
        function proxy:SetClosedCallback(callback) self.closed = callback end
        function proxy:ReinitializeAll() self.refreshes = self.refreshes + 1 end
        state.menuProxy = proxy
        return proxy
    end
    env.PanelTemplates_SelectTab = function(tab) tab:SetEnabled(false) end
    env.PanelTemplates_DeselectTab = function(tab) tab:SetEnabled(true) end
    env.UIParent = Wow.region(Frame)
    env.UIParent:SetSize(1920, 1080)
    env.Minimap = Wow.region(Frame)
    env.Minimap:SetSize(140, 140)
    env.GameTooltip = Wow.region(Tooltip)
    env.GameTooltip:Hide()
    env.DEFAULT_CHAT_FRAME = Wow.region(MessageFrame)
    env.SlashCmdList = {}
    env.AeternumDB = state.savedVariables
    env.AeternumTrainerDB = state.savedTrainerData
    env.AeternumRouteDB = state.savedRoute
    env.GetProfessions = function() return unpack(state.professionIndices or {}, 1, 7) end
    env.GetProfessionInfo = function(index)
        local skill = (state.professionSkills or {})[index]
        return nil, nil, (state.professionRanks or {})[skill] or 1, 75, nil, nil, skill
    end
    local warriorSkills = {[43]=1, [160]=1, [172]=1, [173]=1, [413]=1, [414]=1}
    env.C_SkillInfo = {GetSkillLineInfoByID = function(id)
        local ranks = state.skillRanks or ((state.class or "WARRIOR") == "WARRIOR" and warriorSkills)
        if ranks and ranks[id] then return {skillID=id, rank=ranks[id]} end
    end}
    env.GetMoneyString = function(copper) return copper .. " copper" end
    env.GetCursorPosition = function() return state.cursorX or 150, state.cursorY or 150 end
    env.GetInstanceInfo = function() return state.instanceName, "party", nil, nil, nil, nil, nil, state.instanceID end
    env.GetSubZoneText = function() return state.subzone end
    env.GetLocale = function() return state.locale or "enUS" end
    env.UnitGUID = function(unit) if unit == "npc" then return state.npcGUID end end
    env.GetNumTrainerServices = function() return #(state.services or {}) end
    env.GetTrainerServiceInfo = function(i)
        local row = state.services[i]
        return row.name, row.status or "available", nil, row.level, row.rank
    end
    env.GetTrainerServiceCost = function(i) return state.services[i].cost end
    env.GetTrainerServiceSkillReq = function(i) return state.services[i].skill, state.services[i].need end
    env.Enum = {TooltipDataType = {Spell = 1}}
    env.C_TooltipInfo = {GetTrainerService = function(i)
        local row = state.services[i]
        if row.spell then return {type=1, id=row.spell} end
    end}
    env.MAP_CANVAS_MOUSE_WHEEL_ZOOM_BEHAVIOR_FULL = 2
    env.hooksecurefunc = function(owner, method, hook)
        local original = owner[method]
        owner[method] = function(...) original(...); hook(...) end
    end

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
    env.ToggleWorldMap = function()
        local map = env.WorldMapFrame
        if map:IsShown() then map:Hide() else map:Show() end
    end
    env.UISpecialFrames = {}
    -- As in Blizzard_GameMenuEsc: one shared list, re-sorted on every registration. A call
    -- from add-on code rewrites its slots insecurely, so each later Escape press runs
    -- tainted and Blizzard's protected fallbacks are forbidden.
    env.GameMenuEscPriority = { Dialog = 1, Menu = 2, Casting = 4, FrameworkPre = 5, Framework = 6,
        FrameworkPost = 7, AddOn = 8, AddOnPost = 9, AddOnPost2 = 10, World = 11 }
    state.escapeHandlers = {}
    local escapeOrder = 0
    env.RegisterGameMenuEscHandler = function(priority, handler)
        if state.blizzardLoaded then state.escapeTainted = true end
        escapeOrder = escapeOrder + 1
        table.insert(state.escapeHandlers, { priority, handler, escapeOrder })
        table.sort(state.escapeHandlers, function(a, b)
            if a[1] ~= b[1] then return a[1] < b[1] end
            return a[3] < b[3]
        end)
    end
    -- Protected: only an untainted Escape press may clear the target.
    env.ClearTarget = function()
        if state.escapeTainted then
            state.forbidden = state.forbidden or {}
            state.forbidden[#state.forbidden + 1] = "ClearTarget"
            return false
        end
        local hadTarget = state.target ~= nil
        state.target = nil
        return hadTarget
    end
    -- CloseAllWindows closes the map after the add-on bucket; clearing the target comes last.
    env.RegisterGameMenuEscHandler(env.GameMenuEscPriority.AddOnPost, function()
        if env.WorldMapFrame:IsShown() then
            env.WorldMapFrame:Hide()
            return true
        end
    end)
    env.RegisterGameMenuEscHandler(env.GameMenuEscPriority.World, function()
        return env.ClearTarget()
    end)
    env.InCombatLockdown = function() return state.inCombat or false end
    env.IsInInstance = function() return state.inInstance or false end
    env.GetPlayerFacing = function() return state.facing or 0 end
    env.UnitPosition = function()
        return state.playerNorth, state.playerWest, 0, state.positionInstance or state.instanceID
    end
    env.C_SpellBook = {IsSpellKnown=function(id) return (state.knownSpells or {})[id] or false end}
    env.C_RaidLocks = {IsEncounterComplete=function(_, id) return (state.lockedEncounters or {})[id] or false end}
    env.UnitFactionGroup = function() return state.faction or "Alliance" end
    env.UnitLevel = function() return state.level or 1 end
    env.UnitRace = function() return "Human", "Human", state.raceID or 1 end
    env.UnitClass = function() return "Warrior", state.class or "WARRIOR", 1 end
    env.UnitQuestTrivialLevelRange = function() return 5 end
    env.IsModifiedClick = function() return state.modified or false end
    env.HandleModifiedItemClick = function(link)
        state.modifiedClick = link
        return true
    end
    env.SetItemRef = function(link, text) state.itemRef = { link, text } end

    env.C_Timer = {
        After = function(_, callback) state.timers[#state.timers + 1] = callback end,
        NewTimer = function(_, callback)
            local timer = { Cancel = noop, callback = callback }
            return timer
        end,
    }
    env.C_CVar = { GetCVarBool = function(name)
        if name == "questPOI" then return state.questPOI ~= false end
        if name == "rotateMinimap" then return state.rotate or false end
    end }
    env.C_Minimap = {
        GetViewRadius = function() return 200 end,
        IsRotateMinimapIgnored = function() return false end,
    }
    env.C_AddOns = { LoadAddOn = noop }
    env.C_Item = {
        IsItemDataCachedByID = function(id) return state.cached[id] or false end,
        GetItemCount = function(id) return (state.inventory or {})[id] or 0 end,
        GetItemNameByID = function(itemID) return state.cached[itemID] and ("Cached " .. itemID) or nil end,
        GetItemQualityByID = function(itemID) return state.cached[itemID] and 4 or nil end,
        GetItemQualityColor = function(quality) return quality == 4 and .64 or 1, .21, .93, "ffa335ee" end,
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
    env.C_SuperTrack = {GetSuperTrackedQuestID = function() return state.superQuest end,
        SetSuperTrackedQuestID = function(id) state.superQuest = id end}
    local function watches()
        local ordered = {}
        for id in pairs(state.watched or {}) do ordered[#ordered + 1] = id end
        table.sort(ordered)
        return ordered
    end
    env.C_QuestLog = {
        GetNumQuestWatches = function() return #watches() end,
        GetQuestIDForQuestWatchIndex = function(i) return watches()[i] end,
        GetQuestsOnMap = function(id) return (state.nativePOI or {})[id] end,
        GetQuestObjectives = function(id) return (state.objectives or {})[id] end,
        GetQuestWatchType = function(id) return (state.watched or {})[id] end,
        AddQuestWatch = function(id)
            state.watched = state.watched or {}
            state.watched[id] = 1
            return true
        end,
        RemoveQuestWatch = function(id) state.watched[id] = nil; return true end,
        IsQuestFlaggedCompleted = function(questID) return state.completed[questID] or false end,
        IsOnQuest = function(questID) return state.log[questID] ~= nil end,
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
        -- As in Blizzard_MapCanvas: the canvas calls OnClick, which hands over to OnMouseClickAction.
        OnClick = function(self, ...)
            if self.OnMouseClickAction then self:OnMouseClickAction(...) end
        end,
        OnReleased = noop,
        UseFrameLevelType = noop,
        ShouldMouseButtonBePassthrough = function(_, button) return button == "RightButton" end,
        CheckMouseButtonPassthrough = function(self, ...)
            self:SetPassThroughButtons()
            local buttons = {}
            for _, button in ipairs({ ... }) do
                if self:ShouldMouseButtonBePassthrough(button) then buttons[#buttons + 1] = button end
            end
            self:SetPassThroughButtons(unpack(buttons))
        end,
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
    map.right = state.mapRight or 1100
    map.left, map.scale = state.mapLeft or 0, state.mapScale or 1
    map.ScrollContainer = Wow.region(Frame, map)
    map.ScrollContainer:SetSize(800, 540)
    -- Blizzard rebuilds the zoom levels for every map and remembers what it wrote, so a
    -- test can tell whether add-on code changed them afterwards.
    map.ScrollContainer.mouseWheelZoomMode = 2
    map.ScrollContainer.CreateZoomLevels = function(self)
        local levels, made = {}, {}
        for index, level in ipairs(state.zoomLevels or {{scale=1, layerIndex=1}}) do
            levels[index] = {scale=level.scale, layerIndex=level.layerIndex}
            made[index] = {entry=levels[index], scale=level.scale, layerIndex=level.layerIndex}
        end
        self.zoomLevels, self.blizzardZoomLevels = levels, made
    end
    map.ScrollContainer:CreateZoomLevels()
    map.strata = state.mapStrata or "HIGH"
    env.WorldMapFrame = map
    state.blizzardLoaded = true
    return env
end

function Wow.trackingMenu()
    local root = description()
    root:CreateButton("Blizzard map filter")
    Wow.state.menuHooks.MENU_WORLD_MAP_TRACKING(Wow.env.WorldMapFrame, root)
    return root
end

-- Blizzard-owned map canvas state that add-on code has written since Blizzard set it.
function Wow.addonMapWrites()
    local writes = {}
    local scroll = Wow.env.WorldMapFrame.ScrollContainer
    if Wow.state.wheelModeWritten then writes[#writes + 1] = "mouseWheelZoomMode" end
    local levels, made = scroll.zoomLevels, scroll.blizzardZoomLevels
    local changed = #levels ~= #made
    for index, level in ipairs(made) do
        local current = levels[index]
        if current ~= level.entry or current.scale ~= level.scale or current.layerIndex ~= level.layerIndex then
            changed = true
        end
    end
    if changed then writes[#writes + 1] = "zoomLevels" end
    return writes
end

-- Presses Escape: the first handler that reports it closed something wins.
function Wow.pressEscape()
    for _, entry in ipairs(Wow.state.escapeHandlers) do
        if entry[2]() then
            return
        end
    end
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
