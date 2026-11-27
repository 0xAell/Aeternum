-- SPDX-License-Identifier: GPL-3.0-only
-- Headless Lua 5.1 test suite for Aeternum (run with `luajit tests/run.lua` or `lua tests/run.lua`).

_G.unpack = _G.unpack or table.unpack
local loadstring = loadstring or load

local passed, failed = 0, 0
local failures = {}

local function check(condition, message)
    if not condition then
        error(message or "assertion failed", 2)
    end
end

local function checkEqual(actual, expected, label)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(label or "mismatch", tostring(expected), tostring(actual)), 2)
    end
end

local function checkNear(actual, expected, tolerance, label)
    if type(actual) ~= "number" or math.abs(actual - expected) > (tolerance or 1e-4) then
        error(("%s: expected ~%s, got %s"):format(label or "mismatch", tostring(expected), tostring(actual)), 2)
    end
end

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        failures[#failures + 1] = { name = name, err = tostring(err) }
    end
end

-- ============================================================================
-- Minimal WoW API Harness (WoW Forever 1.60.1 / MapCanvas / Widgets)
-- ============================================================================

local printedMessages = {}
local realPrint = print
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    printedMessages[#printedMessages + 1] = table.concat(parts, " ")
end

local mockState = {
    inCombat = false,
    inInstance = false,
    faction = "Alliance",
    rotateMinimap = false,
    playerFacing = 0,
    playerMapID = 1436,
    playerPos = { x = 0.40, y = 0.60 },
    viewRadius = 150,
    secretValues = setmetatable({}, { __mode = "k" }),
    itemNames = {},
    itemLinks = {},
    itemQualities = {},
    itemCached = {},
    itemRequests = {},
    nativeArt = {},
    failTextureAt = nil,
    texturesLoaded = true,
    timers = {},
    showUIPanelCalls = 0,
    modifiedClickHandled = false,
    modifiedClicks = {},
    itemRefs = {},
    unknownEvents = {},
    mapNames = {
        [1420] = "Tirisfal Glades",
        [1427] = "Searing Gorge",
        [1436] = "Westfall",
        [1453] = "Stormwind City",
        [1454] = "Orgrimmar",
        [1455] = "Ironforge",
    },
}

_G.issecretvalue = function(v)
    return v ~= nil and mockState.secretValues[v] == true
end

_G.canaccesstable = function(t)
    return type(t) == "table" and not mockState.secretValues[t]
end

_G.strtrim = function(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

_G.InCombatLockdown = function()
    return mockState.inCombat
end

_G.IsInInstance = function()
    return mockState.inInstance
end

_G.UnitFactionGroup = function()
    return mockState.faction
end

_G.GetPlayerFacing = function()
    return mockState.playerFacing
end

_G.CreateVector2D = function(x, y)
    return { x = x, y = y }
end

_G.Mixin = function(target, ...)
    for i = 1, select("#", ...) do
        local src = select(i, ...)
        for k, v in pairs(src) do
            target[k] = v
        end
    end
    return target
end

_G.CreateFromMixins = function(...)
    return Mixin({}, ...)
end

_G.ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 },
    [1] = { r = 1.00, g = 1.00, b = 1.00 },
    [2] = { r = 0.12, g = 1.00, b = 0.00 },
    [3] = { r = 0.00, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 },
}

_G.C_CVar = {
    GetCVarBool = function(key)
        if key == "rotateMinimap" then
            return mockState.rotateMinimap
        end
        return false
    end,
}

_G.C_Minimap = {
    GetViewRadius = function()
        return mockState.viewRadius
    end,
    IsRotateMinimapIgnored = function()
        return false
    end,
}

-- Realistic WoW world coordinates: continent 0 = Eastern Kingdoms (mapID 1420, 1427, 1436, 1453),
-- continent 1 = Kalimdor (mapID 1454). World X points North, World Y points West (rotated axes).
local mapContinents = {
    [1420] = 0,
    [1427] = 0,
    [1436] = 0,
    [1453] = 0,
    [1454] = 1,
    [1455] = 0,
}

_G.C_Map = {
    GetMapInfo = function(mapID)
        local name = mockState.mapNames[mapID]
        return name and { name = name, mapID = mapID } or nil
    end,
    GetBestMapForUnit = function()
        return mockState.playerMapID
    end,
    GetPlayerMapPosition = function()
        return mockState.playerPos
    end,
    GetWorldPosFromMapPos = function(mapID, pos)
        local continent = mapContinents[mapID]
        if not continent then
            return nil
        end
        -- Realistic WoW zone scale: 3500 yd E-W, 2333 yd N-S. Positive map X -> East (-worldY), negative map Y -> North (+worldX).
        local worldX = (0.5 - pos.y) * 2333
        local worldY = (0.5 - pos.x) * 3500
        return continent, { x = worldX, y = worldY }
    end,
    GetMapArtLayers = function(mapID)
        local art = mockState.nativeArt[mapID]
        return art and { art.layer } or nil
    end,
    GetMapArtLayerTextures = function(mapID)
        local art = mockState.nativeArt[mapID]
        return art and art.textures or nil
    end,
}

_G.C_Item = {
    GetItemNameByID = function(itemID)
        return mockState.itemNames[itemID]
    end,
    GetItemInfo = function(itemID)
        local name = mockState.itemNames[itemID]
        if not name then
            return nil
        end
        return name, mockState.itemLinks[itemID], mockState.itemQualities[itemID]
    end,
    GetItemQualityByID = function(itemID)
        return mockState.itemQualities[itemID]
    end,
    IsItemDataCachedByID = function(itemID)
        return mockState.itemCached[itemID] == true
    end,
    RequestLoadItemDataByID = function(itemID)
        mockState.itemRequests[itemID] = (mockState.itemRequests[itemID] or 0) + 1
    end,
}

_G.C_Timer = {
    NewTimer = function(delay, callback)
        local timer = {
            delay = delay,
            callback = callback,
            cancelled = false,
            Cancel = function(self)
                self.cancelled = true
            end,
        }
        mockState.timers[#mockState.timers + 1] = timer
        return timer
    end,
}

_G.HandleModifiedItemClick = function(link)
    mockState.modifiedClicks[#mockState.modifiedClicks + 1] = link
    return mockState.modifiedClickHandled
end

_G.SetItemRef = function(link, text, button)
    mockState.itemRefs[#mockState.itemRefs + 1] = { link = link, text = text, button = button }
end

-- Widget factory
local allEventFrames = {}

local function newWidget(kind, parent)
    local w = {
        _kind = kind,
        _parent = parent,
        _shown = true,
        _enabled = true,
        _width = 200,
        _height = 200,
        _frameLevel = 1,
        _scripts = {},
        _events = {},
        _children = {},
        _textures = {},
        _fontStrings = {},
        _lines = {},
        _text = "",
        _checked = false,
        _verticalScroll = 0,
        _points = {},
    }
    if parent and parent._children then
        parent._children[#parent._children + 1] = w
    end

    function w:Show()
        local was = self._shown
        self._shown = true
        if not was then
            self:_fire("OnShow")
        end
    end
    function w:Hide()
        local was = self._shown
        self._shown = false
        if was then
            self:_fire("OnHide")
        end
    end
    function w:SetShown(v)
        if v then self:Show() else self:Hide() end
    end
    function w:IsShown() return self._shown end
    function w:IsVisible()
        if not self._shown then return false end
        if self._parent and self._parent.IsVisible then
            return self._parent:IsVisible()
        end
        return true
    end
    function w:SetEnabled(v) self._enabled = not not v end
    function w:IsEnabled() return self._enabled end
    function w:SetSize(width, height)
        local changed = (width ~= self._width) or (height ~= self._height)
        self._width, self._height = width, height
        if changed then
            self:_fire("OnSizeChanged", width, height)
        end
    end
    function w:GetSize() return self._width, self._height end
    function w:SetWidth(width)
        local changed = width ~= self._width
        self._width = width
        if changed then self:_fire("OnSizeChanged", width, self._height) end
    end
    function w:GetWidth() return self._width end
    function w:SetHeight(height)
        local changed = height ~= self._height
        self._height = height
        if changed then self:_fire("OnSizeChanged", self._width, height) end
    end
    function w:GetHeight() return self._height end
    function w:SetPoint(...) self._points[#self._points + 1] = { ... } end
    function w:SetAllPoints() end
    function w:ClearAllPoints() self._points = {} end
    function w:SetFrameStrata(s) self._strata = s end
    function w:SetFrameLevel(l) self._frameLevel = l end
    function w:GetFrameLevel() return self._frameLevel end
    function w:SetClampedToScreen(v) self._clamped = v end
    function w:EnableMouse(v) self._mouse = v end
    function w:SetText(t)
        local prev = self._text
        self._text = t or ""
        if self._kind == "EditBox" and self._text ~= prev then
            self:_fire("OnTextChanged", false)
        end
    end
    function w:GetText() return self._text end
    function w:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
    function w:SetJustifyH(j) self._justifyH = j end
    function w:SetWordWrap(v) self._wordWrap = v end
    function w:SetMaxLines(n) self._maxLines = n end
    function w:SetAutoFocus(v) self._autoFocus = v end
    function w:SetMaxLetters(n) self._maxLetters = n end
    function w:ClearFocus() self._focused = false end
    function w:SetChecked(v) self._checked = not not v end
    function w:GetChecked() return self._checked end
    function w:SetScrollChild(child) self._scrollChild = child end
    function w:UpdateScrollChildRect() self._rectUpdated = (self._rectUpdated or 0) + 1 end
    function w:GetVerticalScroll() return self._verticalScroll end
    function w:SetVerticalScroll(offset)
        self._verticalScroll = offset
        self:_fire("OnVerticalScroll", offset)
    end
    function w:SetScript(name, fn)
        self._scripts[name] = fn and { fn } or {}
    end
    function w:HookScript(name, fn)
        self._scripts[name] = self._scripts[name] or {}
        self._scripts[name][#self._scripts[name] + 1] = fn
    end
    function w:_fire(name, ...)
        local list = self._scripts[name]
        if not list then return end
        for _, fn in ipairs(list) do
            fn(self, ...)
        end
    end
    function w:Click(button)
        self:_fire("OnClick", button or "LeftButton")
    end
    function w:RegisterEvent(event)
        if mockState.unknownEvents[event] then
            error("Attempt to register unknown event \"" .. tostring(event) .. "\"")
        end
        self._events[event] = true
        allEventFrames[self] = true
    end
    function w:CreateTexture()
        local tex = newWidget("Texture", self)
        function tex:SetColorTexture(r, g, b, a)
            self._color = { r, g, b, a }
        end
        function tex:SetTexture(id)
            if id ~= nil and mockState.failTextureAt and mockState.failTextureAt == id then
                return false
            end
            self._texture = id
            return true
        end
        function tex:SetTexCoord(...) self._texCoord = { ... } end
        function tex:IsObjectLoaded() return mockState.texturesLoaded end
        self._textures[#self._textures + 1] = tex
        return tex
    end
    function w:CreateFontString()
        local fs = newWidget("FontString", self)
        self._fontStrings[#self._fontStrings + 1] = fs
        return fs
    end
    function w:CreateLine()
        local line = newWidget("Line", self)
        function line:SetThickness(t) self._thickness = t end
        function line:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
        function line:SetStartPoint(point, rel, x, y) self._start = { x, y } end
        function line:SetEndPoint(point, rel, x, y) self._end = { x, y } end
        self._lines[#self._lines + 1] = line
        return line
    end
    return w
end

_G.CreateFrame = function(kind, _, parent)
    return newWidget(kind, parent)
end

_G.UIParent = newWidget("Frame")
_G.UIParent:SetSize(1280, 720)

_G.Minimap = newWidget("Frame", UIParent)
_G.Minimap:SetSize(140, 140)

_G.GameTooltip = {
    owner = nil,
    shown = false,
    lines = {},
    hyperlink = nil,
    SetOwner = function(self, owner)
        self.owner = owner
        self.lines = {}
        self.hyperlink = nil
    end,
    IsOwned = function(self, owner)
        return self.owner == owner
    end,
    SetText = function(self, text)
        self.lines[#self.lines + 1] = text
    end,
    AddLine = function(self, text)
        self.lines[#self.lines + 1] = text
    end,
    SetHyperlink = function(self, link)
        self.hyperlink = link
    end,
    Show = function(self) self.shown = true end,
    Hide = function(self)
        self.shown = false
        self.owner = nil
    end,
}

_G.MapCanvasDataProviderMixin = {
    OnAdded = function(self, map) self.owningMap = map end,
    GetMap = function(self) return self.owningMap end,
}

_G.MapCanvasPinMixin = {
    UseFrameLevelType = function() end,
    SetPosition = function(self, x, y) self._posX, self._posY = x, y end,
    OnReleased = function(self) self:Hide() end,
}

_G.WorldMapFrame = newWidget("Frame", UIParent)
_G.WorldMapFrame:SetSize(1000, 700)
_G.WorldMapFrame._shown = false
_G.WorldMapFrame._mapID = 1436
_G.WorldMapFrame._providers = {}
_G.WorldMapFrame._pins = {}

function _G.WorldMapFrame:GetMapID() return self._mapID end
function _G.WorldMapFrame:SetMapID(mapID)
    self._mapID = mapID
    for _, p in ipairs(self._providers) do
        if p.RefreshAllData then p:RefreshAllData() end
    end
end
function _G.WorldMapFrame:AddDataProvider(p)
    p:OnAdded(self)
    self._providers[#self._providers + 1] = p
end
function _G.WorldMapFrame:AcquirePin(tmpl, ...)
    local pin = newWidget("Frame", self)
    Mixin(pin, AeternumMapPinMixin)
    pin._template = tmpl
    if pin.OnLoad then pin:OnLoad() end
    if pin.OnAcquired then pin:OnAcquired(...) end
    self._pins[#self._pins + 1] = pin
    return pin
end
function _G.WorldMapFrame:RemovePin(pin)
    for i, existing in ipairs(self._pins) do
        if existing == pin then
            table.remove(self._pins, i)
            if pin.OnReleased then pin:OnReleased() end
            return
        end
    end
end
function _G.WorldMapFrame:RemoveAllPinsByTemplate(tmpl)
    local kept = {}
    for _, pin in ipairs(self._pins) do
        if pin._template == tmpl then
            if pin.OnReleased then pin:OnReleased() end
        else
            kept[#kept + 1] = pin
        end
    end
    self._pins = kept
end
function _G.WorldMapFrame:EnumeratePinsByTemplate(tmpl)
    local i = 0
    local list = self._pins
    return function()
        while i < #list do
            i = i + 1
            if list[i]._template == tmpl then
                return list[i]
            end
        end
    end
end

_G.ShowUIPanel = function(frame)
    mockState.showUIPanelCalls = mockState.showUIPanelCalls + 1
    frame:Show()
end

_G.SlashCmdList = {}

local function fireEvent(event, ...)
    for frame in pairs(allEventFrames) do
        if frame._events[event] then
            frame:_fire("OnEvent", event, ...)
        end
    end
end

-- ============================================================================
-- Load Addon in Exact TOC Order & Check Global Hygiene
-- ============================================================================

local globalsBefore = {}
for k in pairs(_G) do globalsBefore[k] = true end

local tocFiles = {}
do
    local fh = assert(io.open("Aeternum.toc", "r"), "Run tests from repository root")
    for line in fh:lines() do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^#") then
            tocFiles[#tocFiles + 1] = trimmed
        end
    end
    fh:close()
end

local addon = {}
for _, filename in ipairs(tocFiles) do
    if filename:match("%.lua$") then
        local chunk, err = loadfile(filename)
        assert(chunk, "Failed to compile " .. filename .. ": " .. tostring(err))
        chunk("Aeternum", addon)
    end
end

local expectedGlobals = {
    AeternumDB = true,
    AeternumMapPinMixin = true,
    SLASH_AETERNUM1 = true,
}

test("TOC loads cleanly with no accidental global leaks", function()
    local leaked = {}
    for k in pairs(_G) do
        if not globalsBefore[k] and not expectedGlobals[k] then
            leaked[#leaked + 1] = k
        end
    end
    checkEqual(#leaked, 0, "unexpected globals: " .. table.concat(leaked, ", "))
    check(type(addon.Data) == "table", "addon.Data missing")
    check(type(addon.Navigation) == "table", "addon.Navigation missing")
    check(type(addon.DungeonMap) == "table", "addon.DungeonMap missing")
    check(type(addon.UI) == "table", "addon.UI missing")
end)

test("WorldMap.xml references expected template and mixin", function()
    local fh = assert(io.open("WorldMap.xml", "r"))
    local xml = fh:read("*a")
    fh:close()
    check(xml:find('name="AeternumMapPinTemplate"', 1, true), "missing template name")
    check(xml:find('mixin="AeternumMapPinMixin"', 1, true), "missing mixin name")
end)

-- ============================================================================
-- Core.lua Tests
-- ============================================================================

test("Core: Trim handles nil, non-string, and whitespace with or without strtrim", function()
    checkEqual(addon.Trim("  hello world  "), "hello world")
    checkEqual(addon.Trim("   "), "")
    checkEqual(addon.Trim(nil), "")
    checkEqual(addon.Trim(42), "")
    local saved = _G.strtrim
    _G.strtrim = nil
    checkEqual(addon.Trim("\t foo bar \n"), "foo bar")
    _G.strtrim = saved
end)

test("Core: CategoryEnabled is safe before LoadSettings and honors saved filters", function()
    addon.settings = nil
    checkEqual(addon.CategoryEnabled("dungeon"), true)
    addon.LoadSettings()
    AeternumDB.filters.quest = false
    checkEqual(addon.CategoryEnabled("quest"), false)
    checkEqual(addon.CategoryEnabled("dungeon"), true)
    AeternumDB.filters.quest = true
end)

test("Core: FactionAllowed keeps faction-tagged entries for Neutral/nil factions", function()
    local ally = { faction = "Alliance" }
    local horde = { faction = "Horde" }
    local neutral = {}
    checkEqual(addon.FactionAllowed(ally, "Alliance"), true)
    checkEqual(addon.FactionAllowed(horde, "Alliance"), false)
    checkEqual(addon.FactionAllowed(ally, "Horde"), false)
    checkEqual(addon.FactionAllowed(horde, "Horde"), true)
    checkEqual(addon.FactionAllowed(neutral, "Alliance"), true)
    checkEqual(addon.FactionAllowed(ally, "Neutral"), true)
    checkEqual(addon.FactionAllowed(horde, "Neutral"), true)
    checkEqual(addon.FactionAllowed(ally, nil), true)
    checkEqual(addon.FactionAllowed(horde, nil), true)
end)

test("Core: multi-word and boss-name search finds matching dungeons in Atlas and zone maps", function()
    local vancleefAtlas = addon.Entries(1436, true, "vancleef")
    checkEqual(#vancleefAtlas, 1, "vancleef atlas match count")
    checkEqual(vancleefAtlas[1].source.id, "deadmines")

    local herodMulti = addon.Entries(1420, true, "scarlet herod")
    checkEqual(#herodMulti, 1, "scarlet herod match count")
    checkEqual(herodMulti[1].source.id, "sm-armory")

    local vancleefZone = addon.Entries(1436, false, "  edwin   vancleef  ")
    check(#vancleefZone >= 1, "should match Deadmines on Westfall map")
    checkEqual(vancleefZone[1].source.id, "deadmines")
end)

test("Core: ItemName, ItemLink, ItemColor, and ItemCached handle cached and uncached items", function()
    mockState.itemNames = {}
    mockState.itemLinks = {}
    mockState.itemQualities = {}
    mockState.itemCached = {}

    checkEqual(addon.ItemName(nil), "Item ")
    checkEqual(addon.ItemLink(nil), nil)
    checkEqual(addon.ItemColor(nil), nil)
    checkEqual(addon.ItemCached(nil), true)

    -- Uncached item falls back to bundled Data.items
    local sampleID, sampleName = next(addon.Data.items)
    check(sampleID and sampleName, "bundled Data.items should not be empty")
    checkEqual(addon.ItemCached(sampleID), false)
    checkEqual(addon.ItemName(sampleID), sampleName)
    checkEqual(addon.ItemLink(sampleID), ("|Hitem:%d|h[%s]|h"):format(sampleID, sampleName))
    checkEqual(addon.ItemColor(sampleID), nil)

    -- Cached item uses client hyperlink and quality color (including quality 0)
    mockState.itemCached[sampleID] = true
    mockState.itemNames[sampleID] = "Client " .. sampleName
    mockState.itemLinks[sampleID] = ("|cff0070dd|Hitem:%d|h[Client %s]|h|r"):format(sampleID, sampleName)
    mockState.itemQualities[sampleID] = 3
    checkEqual(addon.ItemCached(sampleID), true)
    checkEqual(addon.ItemName(sampleID), "Client " .. sampleName)
    checkEqual(addon.ItemLink(sampleID), mockState.itemLinks[sampleID])
    local rareColor = addon.ItemColor(sampleID)
    check(rareColor ~= nil, "rare color should exist")
    checkNear(rareColor[3], 0.87, 1e-3, "rare blue channel")

    mockState.itemQualities[sampleID] = 0
    local poorColor = addon.ItemColor(sampleID)
    check(poorColor ~= nil, "poor quality (0) color must not be treated as falsy")
    checkNear(poorColor[1], 0.62, 1e-3, "poor gray channel")
end)

-- ============================================================================
-- Navigation.lua Tests
-- ============================================================================

local function findDungeon(id)
    for _, d in ipairs(addon.Data.dungeons) do
        if d.id == id then return d end
    end
    error("dungeon not found: " .. id)
end

test("Navigation: starts on waypoint, advances smoothly, and completes at entrance", function()
    local deadmines = findDungeon("deadmines")
    local entrance = deadmines.entrances[1]
    local wp = entrance.waypoints[1]

    mockState.inInstance = false
    mockState.rotateMinimap = false
    mockState.playerFacing = 0
    mockState.playerMapID = entrance.mapID
    mockState.viewRadius = 150
    Minimap:SetSize(140, 140)
    printedMessages = {}

    local statusChanges = 0
    addon.Navigation.onChange = function() statusChanges = statusChanges + 1 end

    -- Start far away north of Moonbrook road waypoint (clearly closer to waypoint than entrance)
    mockState.playerPos = { x = wp.x, y = wp.y - 0.08 }
    checkEqual(addon.Navigation:Start(deadmines, entrance), true)
    checkEqual(addon.Navigation:IsActive(), true)
    checkEqual(addon.Navigation.step, 1, "should target approach waypoint first")
    check(addon.Navigation:GetStatus():find("Moonbrook road", 1, true), "status should name approach point")
    check(statusChanges >= 1, "onChange should fire on start")

    -- Move within STEP_RADIUS (28 yd) of waypoint -> advances to step 2 (entrance)
    mockState.playerPos = { x = wp.x, y = wp.y - 0.005 }
    addon.Navigation:Update()
    checkEqual(addon.Navigation.step, 2, "should advance to entrance")
    check(addon.Navigation:GetStatus():find("Entrance bearing", 1, true), "status should switch to entrance bearing")

    -- Arrive within ENTRANCE_RADIUS (18 yd) of entrance -> auto-stops & notifies chat
    mockState.playerPos = { x = entrance.x + 0.002, y = entrance.y }
    addon.Navigation:Update()
    checkEqual(addon.Navigation:IsActive(), false)
    check(addon.Navigation:GetStatus():find("Near The Deadmines entrance", 1, true), "arrival status")
    check(#printedMessages >= 1 and printedMessages[#printedMessages]:find("Near The Deadmines entrance", 1, true), "chat arrival notice")
end)

test("Navigation: starting past waypoint does not send player backwards, and bypassing completes arrival", function()
    local deadmines = findDungeon("deadmines")
    local entrance = deadmines.entrances[1]
    local wp = entrance.waypoints[1]

    mockState.playerMapID = entrance.mapID
    -- Place player between waypoint and entrance, closer to entrance (outside 18 yd arrival radius)
    local dx, dy = entrance.x - wp.x, entrance.y - wp.y
    local dist = math.sqrt((dx * 3500) ^ 2 + (dy * 2333) ^ 2)
    check(dist > 45, "Deadmines waypoint and entrance should be separated by >45 yd")
    mockState.playerPos = { x = entrance.x - dx * 0.4, y = entrance.y - dy * 0.4 }
    addon.Navigation:Start(deadmines, entrance)
    checkEqual(addon.Navigation.step, 2, "must target entrance directly instead of backtracking to waypoint")

    -- Restart north of waypoint (step 1), then move straight to entrance bypassing waypoint
    mockState.playerPos = { x = wp.x, y = wp.y - 0.08 }
    addon.Navigation:Start(deadmines, entrance)
    checkEqual(addon.Navigation.step, 1)
    mockState.playerPos = { x = entrance.x, y = entrance.y + 0.002 }
    addon.Navigation:Update()
    checkEqual(addon.Navigation:IsActive(), false, "arriving directly at entrance must stop guidance even from step 1")
end)

test("Navigation: non-square minimap preserves true bearing, clamps min offset, and shows gold entrance breadcrumb", function()
    local deadmines = findDungeon("deadmines")
    local entrance = deadmines.entrances[1]
    local wp = entrance.waypoints[1]

    mockState.playerMapID = entrance.mapID
    mockState.rotateMinimap = false
    mockState.viewRadius = 500
    Minimap:SetSize(260, 140) -- non-square minimap, edgeRadius = min(260,140)/2 - 12 = 58

    -- Put player 45 degrees NW of waypoint (target is SE: +100 yd East, -100 yd North), clearly closer to wp than entrance
    mockState.playerPos = { x = wp.x - 100 / 3500, y = wp.y - 100 / 2333 }
    addon.Navigation:Start(deadmines, entrance)
    checkEqual(addon.Navigation.step, 1)
    local tip = addon.Navigation.overlay.arrow[1]._end
    checkNear(tip[1], -tip[2], 1e-3, "45-degree SE bearing must stay exact 45 degrees on non-square minimap")

    -- Entrance (step 2) is within 500 yd viewRadius, so dot 1 should be shown in gold
    local dot1 = addon.Navigation.overlay.dots[1]
    checkEqual(dot1:IsShown(), true, "entrance breadcrumb dot should be shown")
    checkNear(dot1._color[1], 1.0, 1e-2, "entrance breadcrumb gold R")
    checkNear(dot1._color[2], 0.82, 1e-2, "entrance breadcrumb gold G")

    -- Test minimum arrow offset when very close to entrance (20 yd West of entrance, outside 18 yd arrival, 500 yd viewRadius)
    mockState.playerPos = { x = entrance.x - 20 / 3500, y = entrance.y }
    addon.Navigation:Start(deadmines, entrance)
    checkEqual(addon.Navigation:IsActive(), true)
    local closeTip = addon.Navigation.overlay.arrow[1]._end
    local closeTail = addon.Navigation.overlay.arrow[1]._start
    local tipDist = math.sqrt(closeTip[1] ^ 2 + closeTip[2] ^ 2)
    check(tipDist >= 15.99, "arrow tip should clamp to >= 16px so tail does not flip behind player")
    check(closeTail[1] > 0, "arrow tail should remain in front of minimap center")

    -- Test rotateMinimap: player faces West (pi/2 CCW from North), target due West -> points UP (+Y)
    mockState.rotateMinimap = true
    mockState.playerFacing = math.pi / 2
    mockState.playerPos = { x = entrance.x + 60 / 3500, y = entrance.y } -- entrance is due West of player
    addon.Navigation:Update()
    local rotTip = addon.Navigation.overlay.arrow[1]._end
    checkNear(rotTip[1], 0, 1e-2, "rotated east component should be ~0")
    check(rotTip[2] > 15, "rotated north component should point up")

    addon.Navigation:Stop()
    Minimap:SetSize(140, 140)
    mockState.rotateMinimap = false
end)

test("Navigation: pauses safely for instance, wrong continent, secret values, and missing entrances", function()
    local deadmines = findDungeon("deadmines")
    local entrance = deadmines.entrances[1]
    mockState.playerMapID = entrance.mapID
    mockState.playerPos = { x = entrance.x + 0.05, y = entrance.y }
    addon.Navigation:Start(deadmines, entrance)

    mockState.inInstance = true
    addon.Navigation:Update()
    check(addon.Navigation:GetStatus():find("paused inside an instance", 1, true))
    checkEqual(addon.Navigation.overlay:IsShown(), false)
    mockState.inInstance = false

    mockState.playerMapID = 1454 -- Kalimdor (continent 1) vs EK (continent 0)
    addon.Navigation:Update()
    check(addon.Navigation:GetStatus():find("continent", 1, true))

    -- Secret value guard
    local secretPos = { x = 0.5, y = 0.5 }
    mockState.secretValues[secretPos] = true
    mockState.playerMapID = entrance.mapID
    mockState.playerPos = secretPos
    addon.Navigation:Update()
    check(addon.Navigation:GetStatus():find("readable player map position", 1, true))
    mockState.secretValues[secretPos] = nil

    -- Missing entrance coordinates (alcaz-prison)
    local alcaz = findDungeon("alcaz-prison")
    checkEqual(addon.Navigation:Start(alcaz), false)
    check(addon.Navigation:GetStatus():find("no entrance coordinates", 1, true))
end)

-- ============================================================================
-- DungeonMap.lua Tests
-- ============================================================================

test("DungeonMap: zero-size layout waits quietly, resize draws all 12 tiles, partial failure hides all tiles", function()
    local host = CreateFrame("Frame", nil, UIParent)
    local dm = addon.DungeonMap.Create(host)
    -- Locate internal widgets by role rather than brittle child indices
    local view, prevBtn, nextBtn, worldMapBtn
    for _, child in ipairs(dm._children) do
        if child.tiles then
            view = child
        elseif child._kind == "Button" then
            if child:GetText() == "<" then prevBtn = child
            elseif child:GetText() == ">" then nextBtn = child
            elseif child:GetText() == "World Map" then worldMapBtn = child end
        end
    end
    check(view and prevBtn and nextBtn and worldMapBtn, "DungeonMap internal controls should exist")
    local titleFS = dm._fontStrings[1]
    local captionFS = dm._fontStrings[2]
    local emptyFS = view._fontStrings[1]

    local deadmines = findDungeon("deadmines")
    view._width, view._height = 0, 0
    dm:SetDungeon(deadmines)
    checkEqual(emptyFS:IsShown(), false, "must not flash unavailable error before layout bounds arrive")
    checkEqual(titleFS:GetText(), "Floor 1 / 2")
    checkEqual(prevBtn:IsEnabled(), false)
    checkEqual(nextBtn:IsEnabled(), true)

    -- Simulate layout sizing
    mockState.texturesLoaded = true
    view:SetSize(400, 300)
    checkEqual(#view.tiles, 12, "reference floor draws 12 tiles")
    for i = 1, 12 do
        checkEqual(view.tiles[i]:IsShown(), true, "tile " .. i .. " should be shown")
    end
    checkEqual(captionFS:GetText(), "Legacy client reference")
    checkEqual(emptyFS:IsShown(), false)

    -- Next floor button
    nextBtn:Click()
    checkEqual(titleFS:GetText(), "Floor 2 / 2")
    checkEqual(prevBtn:IsEnabled(), true)
    checkEqual(nextBtn:IsEnabled(), false)

    -- Mid-loop texture failure hides ALL tiles (including 1..4) and shows unavailable
    mockState.failTextureAt = 449610 -- tile #5 on Deadmines floor 2
    view:SetSize(401, 300)
    for i = 1, 12 do
        checkEqual(view.tiles[i]:IsShown(), false, "tile " .. i .. " must be hidden after mid-loop failure")
        checkEqual(view.tiles[i]._texture, nil, "tile " .. i .. " texture must be cleared")
    end
    checkEqual(emptyFS:IsShown(), true)
    checkEqual(emptyFS:GetText(), "Client floor map unavailable.")
    mockState.failTextureAt = nil

    -- Pending load timer gets cancelled on Hide
    mockState.texturesLoaded = false
    mockState.timers = {}
    view:SetSize(400, 300)
    checkEqual(#mockState.timers, 1, "should schedule async tile check timer")
    checkEqual(mockState.timers[1].cancelled, false)
    dm:Hide()
    checkEqual(mockState.timers[1].cancelled, true, "OnHide must cancel pending loadTimer")
    mockState.texturesLoaded = true

    -- World Map button respects InCombatLockdown
    local nativeDungeon = {
        id = "test-native",
        name = "Test Native",
        floors = { { mapID = 1436, name = "Upper Hall" } },
    }
    mockState.nativeArt[1436] = {
        layer = { layerWidth = 512, layerHeight = 512, tileWidth = 256, tileHeight = 256 },
        textures = { 101, 102, 103, 104 },
    }
    dm:Show()
    dm:SetDungeon(nativeDungeon)
    checkEqual(worldMapBtn:IsShown(), true)
    checkEqual(titleFS:GetText(), "Upper Hall")

    local beforeShows = mockState.showUIPanelCalls
    mockState.inCombat = true
    printedMessages = {}
    worldMapBtn:Click()
    checkEqual(mockState.showUIPanelCalls, beforeShows, "must not call ShowUIPanel in combat")
    check(#printedMessages >= 1 and printedMessages[#printedMessages]:find("combat", 1, true))

    mockState.inCombat = false
    worldMapBtn:Click()
    checkEqual(mockState.showUIPanelCalls, beforeShows + 1, "should call ShowUIPanel out of combat")
    mockState.nativeArt[1436] = nil
end)

-- ============================================================================
-- WorldMap.lua + UI.lua Integration Tests
-- ============================================================================

test("WorldMap + UI: attach, combat-safe slash command, search query, and stop/help commands", function()
    fireEvent("ADDON_LOADED", "Aeternum")
    fireEvent("PLAYER_LOGIN")
    check(addon.UI.sidebar ~= nil, "sidebar should attach on PLAYER_LOGIN")

    -- Combat lockdown prevents ShowUIPanel when WorldMapFrame is hidden
    WorldMapFrame:Hide()
    mockState.inCombat = true
    local beforeShows = mockState.showUIPanelCalls
    printedMessages = {}
    SlashCmdList.AETERNUM("")
    checkEqual(mockState.showUIPanelCalls, beforeShows, "/aeternum must not call ShowUIPanel during combat")
    check(#printedMessages >= 1 and printedMessages[#printedMessages]:find("combat", 1, true))

    -- /aeternum help and /aeternum stop
    printedMessages = {}
    SlashCmdList.AETERNUM("help")
    check(printedMessages[#printedMessages]:find("/aeternum", 1, true))

    printedMessages = {}
    SlashCmdList.AETERNUM("stop")
    check(printedMessages[#printedMessages]:find("not active", 1, true))

    -- Out of combat: /aeternum vancleef opens map, sidebar, and filters
    mockState.inCombat = false
    WorldMapFrame._mapID = 1436
    SlashCmdList.AETERNUM("  vancleef  ")
    checkEqual(WorldMapFrame:IsShown(), true)
    checkEqual(addon.UI:IsOpen(), true)
    checkEqual(addon.UI:GetSearch(), "vancleef")
    checkEqual(addon.UI.sidebar.clearSearch:IsShown(), true)

    -- Clear button resets search
    addon.UI.sidebar.clearSearch:Click()
    checkEqual(addon.UI:GetSearch(), "")
    checkEqual(addon.UI.sidebar.clearSearch:IsShown(), false)
end)

test("WorldMap: stacked Scarlet Monastery pin cycles all 4 wings on right-click and opens cycled wing on left-click", function()
    mockState.faction = "Horde"
    WorldMapFrame:Show()
    addon.UI:SetSearch("")
    addon.UI:SetAtlas(false)
    WorldMapFrame:SetMapID(1420) -- Tirisfal Glades

    local smPin
    for pin in WorldMapFrame:EnumeratePinsByTemplate("AeternumMapPinTemplate") do
        if pin.entries and #pin.entries >= 4 and pin.entries[1].category == "dungeon" then
            smPin = pin
            break
        end
    end
    check(smPin ~= nil, "expected stacked Scarlet Monastery pin on Tirisfal Glades")
    checkEqual(#smPin.entries, 4, "all 4 Scarlet Monastery wings share the entrance location")

    local firstTitle = smPin.entry.title
    smPin:OnMouseEnter()
    local sawCycleHint = false
    for _, line in ipairs(GameTooltip.lines) do
        if line:find("Right-click to cycle (1/4)", 1, true) then
            sawCycleHint = true
        end
    end
    check(sawCycleHint, "tooltip should show cycle indicator (1/4)")

    -- Right-click to cycle to wing 2
    smPin:OnMouseClickAction("RightButton")
    checkEqual(smPin.activeIndex, 2)
    check(smPin.entry.title ~= firstTitle, "active entry should advance to wing 2")
    local secondDungeon = smPin.entry.source

    -- Left-click opens wing 2 specifically
    smPin:OnMouseClickAction("LeftButton")
    check(addon.UI.detail and addon.UI.detail:IsShown(), "left-click should open detail frame")
    checkEqual(addon.UI.detail.dungeon, secondDungeon, "detail frame should open the cycled wing")

    -- Cycle remaining steps wraps cleanly back to 1
    smPin:OnMouseClickAction("RightButton")
    checkEqual(smPin.activeIndex, 3)
    smPin:OnMouseClickAction("RightButton")
    checkEqual(smPin.activeIndex, 4)
    smPin:OnMouseClickAction("RightButton")
    checkEqual(smPin.activeIndex, 1)
end)

test("WorldMap: dense Stormwind map caps pins at 100, reports count, and HighlightPin creates/cleans temporary focusPin", function()
    mockState.faction = "Alliance"
    addon.UI:SetAtlas(false)
    addon.UI:SetSearch("")
    WorldMapFrame:SetMapID(1453) -- Stormwind City (134 unique pin positions)

    local pinCount = 0
    local pinnedEntries = {}
    for pin in WorldMapFrame:EnumeratePinsByTemplate("AeternumMapPinTemplate") do
        pinCount = pinCount + 1
        for _, e in ipairs(pin.entries or {}) do
            pinnedEntries[e] = true
        end
    end
    checkEqual(pinCount, 100, "Stormwind should cap regular pins at 100")
    check(addon.UI.sidebar.selection:GetText():find("100 map pins", 1, true), "footer should report truncated map pin count")

    -- Find an entry omitted by pinLimit
    local allEntries = addon.Entries(1453, false, "")
    local omitted
    for _, e in ipairs(allEntries) do
        if e.x and e.y and e.category ~= "dungeon" and not pinnedEntries[e] then
            omitted = e
            break
        end
    end
    check(omitted ~= nil, "expected at least one omitted entry on Stormwind")

    addon.UI:Select(omitted)
    local afterFocus = 0
    local focusFound
    for pin in WorldMapFrame:EnumeratePinsByTemplate("AeternumMapPinTemplate") do
        afterFocus = afterFocus + 1
        if pin.entry == omitted then focusFound = pin end
    end
    checkEqual(afterFocus, 101, "selecting omitted entry should acquire temporary focus pin")
    check(focusFound and focusFound.highlighted and focusFound:GetWidth() == 24, "focus pin should be highlighted at 24x24")

    -- Selecting a regular pinned entry removes the temporary focus pin
    local regular
    for _, e in ipairs(allEntries) do
        if e.x and e.y and e.category ~= "dungeon" and pinnedEntries[e] then
            regular = e
            break
        end
    end
    addon.UI:Select(regular)
    local afterRegular = 0
    for _ in WorldMapFrame:EnumeratePinsByTemplate("AeternumMapPinTemplate") do
        afterRegular = afterRegular + 1
    end
    checkEqual(afterRegular, 100, "temporary focus pin must be removed when selecting another entry")
end)

test("UI: negative scroll clamp, loot tooltip/hyperlink/async refresh without loop, 0-entrance guard, and Show zone", function()
    -- Test negative scroll clamp on sidebar list
    addon.UI.sidebar.list:SetVerticalScroll(-120)
    check(true, "negative vertical scroll should not crash")

    -- Prepare an uncached loot item and a cached loot item on Deadmines boss #1
    local deadmines = findDungeon("deadmines")
    local boss1 = deadmines.bosses[1]
    local item1 = boss1.loot[1]
    local item2 = boss1.loot[2]
    mockState.itemCached = {}
    mockState.itemNames = {}
    mockState.itemLinks = {}
    mockState.itemQualities = {}
    mockState.itemRequests = {}
    mockState.itemCached[item2] = true
    mockState.itemNames[item2] = "Cached Test Item"

    -- Open Deadmines via Atlas mode
    addon.UI:SetAtlas(true)
    addon.UI:SetSearch("")
    local atlasEntries = addon.Entries(1453, true, "deadmines")
    addon.UI:Select(atlasEntries[1])

    local detail = addon.UI.detail
    check(detail and detail:IsShown())
    checkEqual(mockState.itemRequests[item1], 1, "uncached item should be requested once")
    checkEqual(mockState.itemRequests[item2], nil, "already-cached item should not be requested")

    -- Simulate a scrollable loot viewport, scroll down, then async ITEM_DATA_LOAD_RESULT arrives for item1
    detail.loot:SetHeight(20)
    detail.loot:SetVerticalScroll(23)
    mockState.itemCached[item1] = true
    mockState.itemNames[item1] = "Loaded Client Loot"
    mockState.itemLinks[item1] = "|cff0070dd|Hitem:" .. item1 .. "|h[Loaded Client Loot]|h|r"
    mockState.itemQualities[item1] = 3
    fireEvent("ITEM_DATA_LOAD_RESULT", item1, true)
    checkEqual(mockState.itemRequests[item1], 1, "async refresh must not re-request item (no infinite loop)")
    checkEqual(detail.loot:GetVerticalScroll(), 23, "async refresh should preserve scroll offset")
    detail.loot:SetHeight(200)

    -- Hover and click first visible loot row
    local firstLootRow = detail.loot._scrollChild._children[1]
    check(firstLootRow and firstLootRow.entry, "loot row should exist")
    firstLootRow:_fire("OnEnter")
    checkEqual(GameTooltip.hyperlink, "item:" .. firstLootRow.entry.itemID)
    firstLootRow:_fire("OnLeave")
    checkEqual(GameTooltip.shown, false)

    -- Shift-click handled via HandleModifiedItemClick
    mockState.modifiedClickHandled = true
    mockState.modifiedClicks = {}
    mockState.itemRefs = {}
    firstLootRow:Click("LeftButton")
    checkEqual(#mockState.modifiedClicks, 1)
    check(mockState.modifiedClicks[1]:find("|Hitem:", 1, true), "modified click must receive valid item hyperlink")
    checkEqual(#mockState.itemRefs, 0, "should not also call SetItemRef when HandleModifiedItemClick handled it")

    -- Normal click calls SetItemRef with hyperlink
    mockState.modifiedClickHandled = false
    firstLootRow:Click("LeftButton")
    checkEqual(#mockState.itemRefs, 1)
    checkEqual(mockState.itemRefs[1].link, "item:" .. firstLootRow.entry.itemID)
    check(mockState.itemRefs[1].text:find("|Hitem:", 1, true), "SetItemRef must receive valid item hyperlink")

    -- Stop button sync with Navigation
    addon.Navigation:Stop()
    checkEqual(detail.stop:IsEnabled(), false, "Stop button disabled when guidance inactive")
    mockState.playerMapID = deadmines.entrances[1].mapID
    mockState.playerPos = { x = 0.50, y = 0.50 }
    detail.route:Click()
    checkEqual(detail.stop:IsEnabled(), true, "Stop button enabled when guidance active")
    addon.Navigation:Stop()
    checkEqual(detail.stop:IsEnabled(), false, "Stop button auto-disabled via Navigation.onChange")

    -- Show zone button respects combat lockdown, then switches map & exits atlas out of combat
    mockState.inCombat = true
    local prevMap = WorldMapFrame:GetMapID()
    detail.showZone:Click()
    checkEqual(WorldMapFrame:GetMapID(), prevMap, "Show zone must not switch map in combat")

    mockState.inCombat = false
    detail.showZone:Click()
    checkEqual(WorldMapFrame:GetMapID(), deadmines.entrances[1].mapID, "Show zone switches map to entrance zone")
    checkEqual(addon.UI:IsAtlas(), false, "Show zone exits atlas mode")
    checkEqual(detail:IsShown(), false, "Show zone closes detail window")

    -- 0-entrance dungeon (alcaz-prison) safely disables buttons and nextEntrance click doesn't NaN
    addon.UI:SetAtlas(true)
    local alcazEntries = addon.Entries(1436, true, "alcaz")
    addon.UI:Select(alcazEntries[1])
    checkEqual(detail.route:IsEnabled(), false)
    checkEqual(detail.showZone:IsEnabled(), false)
    checkEqual(detail.nextEntrance:IsEnabled(), false)
    detail.nextEntrance:Click()
    checkEqual(detail.entranceIndex, 0, "nextEntrance on 0 entrances must not produce NaN")
end)

-- ============================================================================
-- tools/import_norgannon.lua Tests
-- ============================================================================

test("tools/import_norgannon.lua: valid Lua 5.1 syntax and safe serializer logic", function()
    local chunk, err = loadfile("tools/import_norgannon.lua")
    check(chunk ~= nil, "tools/import_norgannon.lua syntax error: " .. tostring(err))

    local fh = assert(io.open("tools/import_norgannon.lua", "r"))
    local src = fh:read("*a")
    fh:close()

    -- Extract keys + reservedKeywords + isSequence + literal and execute them directly
    local keysCode = assert(src:match("(local function keys%b().-\nend)"))
    local literalBlock = assert(src:match("(local reservedKeywords = %b{}.-local function literal%b().-\nend)"))
    local helperChunk = assert(loadstring(keysCode .. "\n" .. literalBlock .. "\nreturn keys, literal"))
    local keysFn, literalFn = helperChunk()

    -- Mixed key types must sort without crashing
    local sorted = keysFn({ [2] = "b", [1] = "a", ["z"] = 1, ["a"] = 2 })
    checkEqual(#sorted, 4)

    -- Round-trip booleans, reserved keywords, hyphenated keys, dense and sparse arrays
    local cases = {
        true,
        false,
        { 10, 20, 30 },
        { [1] = "a", [3] = "b" },
        { [1] = "a", [3] = "b", [5] = "c" },
        { ["end"] = true, ["dm-east"] = 42, normal = "ok" },
    }
    for idx, sample in ipairs(cases) do
        local encoded = literalFn(sample)
        local decoded = assert(loadstring("return " .. encoded), "invalid generated Lua: " .. encoded)()
        if type(sample) == "table" then
            for k, v in pairs(sample) do
                checkEqual(decoded[k], v, "round-trip case " .. idx .. " key " .. tostring(k))
            end
            for k, v in pairs(decoded) do
                checkEqual(sample[k], v, "round-trip extra key in case " .. idx .. " key " .. tostring(k))
            end
        else
            checkEqual(decoded, sample, "round-trip scalar case " .. idx)
        end
    end
end)

-- ============================================================================
-- Summary
-- ============================================================================

_G.print = realPrint
for _, item in ipairs(failures) do
    print("FAIL: " .. item.name .. "\n  " .. item.err)
end
print(("Aeternum tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
    os.exit(1)
end
