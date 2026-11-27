local _, addon = ...
local DungeonMap = {}
addon.DungeonMap = DungeonMap
local WIDTH, HEIGHT = 1002, 668
local missingLegacyArt = {ruRU=true, esMX=true, itIT=true}
local byInstance = {}
for _, dungeon in ipairs(addon.Data.dungeons) do
    local id = addon.floorData[dungeon.id].instance
    byInstance[id] = byInstance[id] or {}
    table.insert(byInstance[id], dungeon)
end

local function clamp(x, low, high) return math.max(low, math.min(x, high)) end

local function cursor(frame)
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    return x / scale - (frame:GetLeft() or 0), (frame:GetTop() or 0) - y / scale
end

local function place(frame)
    local w, h = frame:GetSize()
    if w <= 0 or h <= 0 then return end
    local scale = math.min(w / WIDTH, h / HEIGHT) * frame.zoom
    local aw, ah = WIDTH * scale, HEIGHT * scale
    frame.x = aw <= w and (w - aw) / 2 or clamp(frame.x, w - aw, 0)
    frame.y = ah <= h and (h - ah) / 2 or clamp(frame.y, h - ah, 0)
    frame.art:SetScale(scale)
    frame.art:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.x / scale, -frame.y / scale)
    -- Keep skulls the size of a normal map icon at every zoom.
    for _, pin in ipairs(frame.pins) do pin:SetSize(20 / scale, 20 / scale) end
end

local function zoom(frame, delta)
    local old = frame.zoom
    frame.zoom = clamp(old * 1.35 ^ delta, 1, 4)
    if frame.zoom == old then return end
    local x, y = cursor(frame)
    frame.x, frame.y = x - (x - frame.x) * frame.zoom / old, y - (y - frame.y) * frame.zoom / old
    place(frame)
end

local function clearFloor(frame)
    for _, texture in ipairs(frame.tiles) do texture:Hide(); texture:SetTexture(nil) end
    for _, line in ipairs(frame.lines) do line:Hide() end
    for _, pin in ipairs(frame.pins) do
        if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
        pin:Hide()
        pin.boss = nil
    end
end

local function tile(frame, index, file, x, y, w, h, level, ...)
    local texture = frame.tiles[index]
    if not texture then
        texture = frame.art:CreateTexture(nil, "ARTWORK")
        frame.tiles[index] = texture
    end
    texture:SetDrawLayer("ARTWORK", clamp(level, -8, 7))
    local loaded = texture:SetTexture(file)
    texture:SetTexCoord(...)
    texture:SetSize(w, h)
    texture:SetPoint("TOPLEFT", frame.art, "TOPLEFT", x, -y)
    texture:Show()
    return loaded ~= false
end

local function mosaicTile(frame, i, part)
    tile(frame, i, part[1], part[2], part[3], part[4], part[5], part[14], unpack(part, 6, 13))
end

local function drawFloor(frame, floor)
    local useFallback = floor.fallback and missingLegacyArt[GetLocale()]
    if floor.tiles then
        if not useFallback then
            for i, file in ipairs(floor.tiles) do
                local x, y = (i - 1) % 4 * 256, math.floor((i - 1) / 4) * 256
                local w, h = math.min(256, WIDTH - x), math.min(256, HEIGHT - y)
                if not tile(frame, i, file, x, y, w, h, 0, 0, w / 256, 0, h / 256) and floor.fallback then
                    useFallback = true
                    break
                end
            end
        end
        if useFallback then
            for _, texture in ipairs(frame.tiles) do texture:Hide() end
            local index = 0
            for record in floor.fallback:gmatch("[^;]+") do
                local part = {}
                for value in record:gmatch("[^,]+") do part[#part + 1] = tonumber(value) end
                index = index + 1
                mosaicTile(frame, index, part)
            end
        end
    elseif floor.pieces then
        for i, part in ipairs(floor.pieces) do mosaicTile(frame, i, part) end
    else
        local index = 0
        for _, path in ipairs(floor.paths) do
            for i = 3, #path, 2 do
                index = index + 1
                local line = frame.lines[index] or frame.art:CreateLine(nil, "ARTWORK")
                frame.lines[index] = line
                line:SetThickness(3)
                line:SetColorTexture(.83, .72, .49, .85)
                line:SetStartPoint("TOPLEFT", frame.art, path[i - 2] * WIDTH, -path[i - 1] * HEIGHT)
                line:SetEndPoint("TOPLEFT", frame.art, path[i] * WIDTH, -path[i + 1] * HEIGHT)
                line:Show()
            end
        end
    end
end

local function bossPin(frame, index)
    local pin = frame.pins[index]
    if pin then return pin end
    pin = CreateFrame("Button", nil, frame.art)
    frame.pins[index] = pin
    pin:SetNormalTexture(137025) -- Blizzard's target-frame skull
    pin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.boss.name)
        GameTooltip:AddLine("Click for loot", 1, .82, 0)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    pin:SetScript("OnClick", function(self) addon.UI:Boss(self, self.boss) end)
    pin:EnableMouseWheel(true)
    pin:SetScript("OnMouseWheel", function(_, delta) zoom(frame, delta) end)
    return pin
end

function DungeonMap:SetFloor(index)
    local frame, dungeon = self.frame, self.dungeon
    local floor = addon.floorData[dungeon.id].floors[index]
    self.index = index
    frame.zoom, frame.x, frame.y = 1, 0, 0
    clearFloor(frame)
    drawFloor(frame, floor)
    local name = dungeon.name
    if floor.name ~= name then name = name .. " · " .. floor.name end
    if floor.paths then name = name .. " (route sketch)" end
    frame.dropdown:OverrideText(name)
    local lookup = {}
    for _, boss in ipairs(dungeon.bosses) do lookup[boss.id] = boss end
    for i, point in ipairs(floor.bosses) do
        local pin = bossPin(frame, i)
        pin.boss = lookup[point[1]]
        pin:SetPoint("CENTER", frame.art, "TOPLEFT", point[2] * WIDTH, -point[3] * HEIGHT)
        pin:Show()
    end
    place(frame)
end

local function floorMenu(_, menu)
    local dungeon = DungeonMap.dungeon
    if not dungeon then return end
    menu:SetScrollMode(310)
    menu:CreateTitle(dungeon.name)
    for i, floor in ipairs(addon.floorData[dungeon.id].floors) do
        menu:CreateRadio(floor.name, function() return i == DungeonMap.index end, function()
            DungeonMap.followInstance = nil
            DungeonMap:SetFloor(i)
        end)
    end
    local family = byInstance[addon.floorData[dungeon.id].instance]
    if #family > 1 then
        local wings = menu:CreateButton("Wings")
        for _, wing in ipairs(family) do
            wings:CreateButton(wing.name, function() DungeonMap:Open(wing) end)
        end
    end
    menu:CreateDivider()
    local bosses = menu:CreateButton("Boss loot")
    bosses:SetScrollMode(300)
    for _, boss in ipairs(dungeon.bosses) do
        bosses:CreateButton(boss.name, function()
            C_Timer.After(0, function()
                if DungeonMap.dungeon == dungeon then addon.UI:Boss(DungeonMap.frame, boss) end
            end)
        end)
    end
    if #dungeon.quests > 0 then addon.UI:QuestMenu(menu:CreateButton("Dungeon quests"), dungeon) end
    menu:CreateButton("Return to zone map", function() DungeonMap:Close() end)
end

function DungeonMap:EnsureFrame()
    if self.frame then return self.frame end
    local map = addon.UI.map
    local frame = CreateFrame("Frame", nil, map)
    self.frame = frame
    frame:Hide()
    frame:SetAllPoints(map.ScrollContainer)
    frame:SetFrameLevel(map.ScrollContainer:GetFrameLevel() + 1)
    frame:SetClipsChildren(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForDrag("LeftButton")
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.055, .048, .04, 1)
    frame.art = CreateFrame("Frame", nil, frame)
    frame.art:SetSize(WIDTH, HEIGHT)
    frame.art:EnableMouse(false)
    frame.tiles, frame.lines, frame.pins = {}, {}, {}
    frame.zoom, frame.x, frame.y = 1, 0, 0
    frame.back = CreateFrame("Button", nil, frame)
    frame.back:SetSize(28, 28)
    frame.back:SetPoint("TOPLEFT", 5, -4)
    frame.back:SetFrameLevel(frame.art:GetFrameLevel() + 3)
    frame.back:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    frame.back:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    frame.back:SetScript("OnClick", function() self:Close() end)
    frame.back:SetScript("OnEnter", function(button)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT"); GameTooltip:SetText("Return to zone map"); GameTooltip:Show()
    end)
    frame.back:SetScript("OnLeave", function(button) if GameTooltip:IsOwned(button) then GameTooltip:Hide() end end)
    frame.dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    frame.dropdown:SetWidth(276)
    frame.dropdown:SetFrameLevel(frame.back:GetFrameLevel())
    frame.dropdown:SetPoint("LEFT", frame.back, "RIGHT", 3, 0)
    frame.dropdown:SetupMenu(floorMenu)
    frame:SetScript("OnMouseWheel", zoom)
    frame:SetScript("OnDragStart", function()
        local x, y = cursor(frame)
        frame.dragX, frame.dragY = x - frame.x, y - frame.y
        frame:SetScript("OnUpdate", function()
            local cx, cy = cursor(frame)
            frame.x, frame.y = cx - frame.dragX, cy - frame.dragY
            place(frame)
        end)
    end)
    frame:SetScript("OnDragStop", function() frame:SetScript("OnUpdate", nil) end)
    frame:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then self:Close() end end)
    frame:SetScript("OnSizeChanged", place)
    frame:SetScript("OnHide", function()
        frame:SetScript("OnUpdate", nil)
        clearFloor(frame)
    end)
    if RegisterGameMenuEscHandler then
        RegisterGameMenuEscHandler(GameMenuEscPriority.AddOn, function()
            if not self.dungeon then return false end
            self:Close()
            return true
        end)
    end
    return frame
end

function DungeonMap:Open(dungeon, bossIndex, preferredFloor)
    local frame = self:EnsureFrame()
    local strata = addon.UI.map:GetFrameStrata()
    frame:SetFrameStrata((strata == "FULLSCREEN" or strata == "FULLSCREEN_DIALOG") and "FULLSCREEN_DIALOG" or "DIALOG")
    self.dungeon, self.followInstance = dungeon, nil
    local floors = addon.floorData[dungeon.id].floors
    local boss = bossIndex and dungeon.bosses[bossIndex]
    local index = preferredFloor or 1
    if boss then
        for i, floor in ipairs(floors) do
            for _, pin in ipairs(floor.bosses) do if pin[1] == boss.id then index = i end end
        end
    end
    frame:Show()
    self:SetFloor(index)
end

function DungeonMap:Close()
    self.dungeon, self.followInstance = nil, nil
    if self.frame then self.frame:Hide() end
end

function DungeonMap:OpenInstance()
    local map = addon.UI.map
    if not map or not map:IsShown() or not IsInInstance() or not GetInstanceInfo then return end
    local name, _, _, _, _, _, _, id = GetInstanceInfo()
    if issecretvalue and issecretvalue(id) then return end
    local wings = byInstance[id]
    if not wings then return end
    local area = GetSubZoneText and GetSubZoneText()
    if issecretvalue and issecretvalue(area) then area = nil end
    if issecretvalue and issecretvalue(name) then name = nil end
    local choice, index, matches, namedWing = nil, nil, 0, nil
    for _, wing in ipairs(wings) do
        if wing.name == name then namedWing = wing end
    end
    local match = area and area ~= "" and ("|" .. area .. "|")
    for _, wing in ipairs(wings) do
        if match and (not namedWing or namedWing == wing) then
            for i, floor in ipairs(addon.floorData[wing.id].floors) do
                if floor.zones:find(match, 1, true) then
                    choice, index, matches = wing, i, matches + 1
                end
            end
        end
    end
    if matches ~= 1 then choice, index = namedWing or (#wings == 1 and wings[1]), nil end
    if choice then
        if self.dungeon ~= choice or (index and self.index ~= index) then self:Open(choice, nil, index) end
        self.followInstance = true
        return
    end
    if self.followInstance then return end
    -- Several wings share one instance ID. Let the player pick if the client
    -- hasn't given a unique wing or floor name.
    MenuUtil.CreateContextMenu(map, function(_, menu)
        menu:CreateTitle("Choose a dungeon wing")
        for _, wing in ipairs(wings) do
            menu:CreateButton(wing.name, function() self:Open(wing); self.followInstance = true end)
        end
    end)
end
