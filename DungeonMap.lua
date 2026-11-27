local _, addon = ...
local DungeonMap = {}
addon.DungeonMap = DungeonMap
local WIDTH, HEIGHT = 1002, 668
local missingLegacyArt = {ruRU=true, esMX=true, itIT=true}
local byInstance = {}
local killed = {}
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
    frame.playerArrow:SetSize(22 / scale, 22 / scale)
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
        pin.boss, pin.members, pin.stop, pin.complete = nil, nil, nil, nil
    end
end

local function playerPosition()
    local self = DungeonMap
    local frame = self.frame
    local floor = self.dungeon and addon.floorData[self.dungeon.id].floors[self.index]
    local arrow = frame.playerArrow
    arrow:Hide()
    if not (UnitPosition and floor and floor.toMap and self.dungeon == self.playerDungeon
        and self.index == self.playerFloor) then return end
    local north, west, _, instance = UnitPosition("player")
    if not addon.IsReadableNumber(north) or not addon.IsReadableNumber(west)
        or not addon.IsReadableNumber(instance) or instance ~= self.playerInstance then return end
    local m = floor.toMap
    local x, y = m[1]*north + m[2]*west + m[3], m[4]*north + m[5]*west + m[6]
    if x < 0 or y < 0 or x > 1 or y > 1 then return end
    local facing = GetPlayerFacing()
    if not addon.IsReadableNumber(facing) then return end
    local n, w = math.cos(facing), math.sin(facing)
    arrow:SetPoint("CENTER", frame.art, "TOPLEFT", x * WIDTH, -y * HEIGHT)
    arrow:SetRotation(-math.atan2((m[1]*n + m[2]*w)*WIDTH, -(m[4]*n + m[5]*w)*HEIGHT))
    arrow:Show()
end

function DungeonMap:UpdatePlayer()
    if not self.frame then return end
    local active = self.dungeon ~= nil and self.playerDungeon == self.dungeon and self.playerFloor == self.index
    self.frame.positionUpdates:SetShown(active)
    playerPosition()
end

function DungeonMap:RefreshKills()
    if not self.dungeon then return end
    local instance = addon.floorData[self.dungeon.id].instance
    for _, pin in ipairs(self.frame.pins) do
        local complete = false
        if pin.stop and self.playerInstance == instance then
            for _, encounter in ipairs(pin.stop.encounters or {}) do
                local locked = C_RaidLocks and C_RaidLocks.IsEncounterComplete
                    and C_RaidLocks.IsEncounterComplete(instance, encounter, self.difficulty)
                if killed[encounter] or ((not issecretvalue or not issecretvalue(locked)) and locked) then
                    complete = true
                    break
                end
            end
        end
        pin.complete = complete
        pin:SetAlpha(complete and .5 or 1)
    end
end

function DungeonMap:RecordKill(encounter)
    if self.playerInstance and addon.IsReadableNumber(encounter) then
        killed[encounter] = true
        self:RefreshKills()
    end
end

function DungeonMap:NewVisit()
    wipe(killed)
    self.chosenWing = nil
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
    return tile(frame, i, part[1], part[2], part[3], part[4], part[5], part[14], unpack(part, 6, 13))
end

local function drawFloor(frame, floor)
    local useFallback = floor.fallback and missingLegacyArt[GetLocale()]
    if floor.tiles then
        if not useFallback then
            for i, file in ipairs(floor.tiles) do
                local x, y = (i - 1) % 4 * 256, math.floor((i - 1) / 4) * 256
                local w, h = math.min(256, WIDTH - x), math.min(256, HEIGHT - y)
                if not tile(frame, i, file, x, y, w, h, 0, 0, w / 256, 0, h / 256) then
                    if not floor.fallback then return false end
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
                if not mosaicTile(frame, index, part) then return false end
            end
        end
    elseif floor.pieces then
        for i, part in ipairs(floor.pieces) do
            if not mosaicTile(frame, i, part) then return false end
        end
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
    return true
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
        GameTooltip:SetText(#self.members > 1 and (self.stop.label or "Bosses") or self.boss.name)
        if #self.members > 1 then
            for _, member in ipairs(self.members) do GameTooltip:AddLine(member.name) end
        end
        if self.complete then GameTooltip:AddLine("Encounter complete", .55, .8, .55) end
        if self.stop.pull then
            GameTooltip:AddLine("Recorded pull location", .8, .8, .8)
        elseif self.stop.approximate then
            GameTooltip:AddLine("Approximate location", .8, .8, .8)
        end
        GameTooltip:AddLine("Click for loot", 1, .82, 0)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    pin:SetScript("OnClick", function(self)
        if #self.members == 1 then addon.UI:Boss(self, self.boss)
        else addon.UI:BossGroup(self, self.members, self.stop.label) end
    end)
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
    local drawn = drawFloor(frame, floor)
    if not drawn then
        for _, texture in ipairs(frame.tiles) do texture:Hide() end
    end
    frame.artNotice:SetShown(not drawn)
    local name = dungeon.name
    if floor.name ~= name then name = name .. " · " .. floor.name end
    if floor.paths then name = name .. " (route sketch)" end
    frame.dropdown:OverrideText(name)
    local lookup, locations, count = {}, {}, 0
    for _, boss in ipairs(dungeon.bosses) do lookup[boss.id] = boss end
    for _, point in ipairs(floor.bosses) do
        local key = ("%s:%s"):format(point[2], point[3])
        local pin = locations[key]
        if not pin then
            count = count + 1
            pin = bossPin(frame, count)
            locations[key] = pin
            pin.boss, pin.stop, pin.members = lookup[point[1]], point, {}
            pin:SetPoint("CENTER", frame.art, "TOPLEFT", point[2] * WIDTH, -point[3] * HEIGHT)
            pin:Show()
        end
        pin.members[#pin.members + 1] = lookup[point[1]]
    end
    place(frame)
    self:RefreshKills()
    self:UpdatePlayer()
end

local function bossFloor(dungeon, boss)
    for index, floor in ipairs(addon.floorData[dungeon.id].floors) do
        for _, point in ipairs(floor.bosses) do if point[1] == boss.id then return index end end
    end
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
                if DungeonMap.dungeon ~= dungeon then return end
                local index = bossFloor(dungeon, boss)
                if index and index ~= DungeonMap.index then DungeonMap:SetFloor(index) end
                addon.UI:Boss(DungeonMap.frame, boss)
            end)
        end)
    end
    if #dungeon.quests > 0 then addon.UI:QuestMenu(menu:CreateButton("Dungeon quests"), dungeon) end
    if #dungeon.keys > 0 then addon.UI:Keys(menu:CreateButton("Dungeon keys"), dungeon) end
    addon.UI:EntranceMenu(menu:CreateButton("Entrances"), dungeon)
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
    frame.artNotice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.artNotice:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    frame.artNotice:SetText("Floor artwork unavailable")
    frame.artNotice:Hide()
    frame.playerArrow = frame.art:CreateTexture(nil, "OVERLAY")
    frame.playerArrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    frame.playerArrow:Hide()
    frame.positionUpdates = CreateFrame("Frame", nil, frame)
    frame.positionUpdates:Hide()
    local elapsedPosition = 0
    frame.positionUpdates:SetScript("OnUpdate", function(_, elapsed)
        elapsedPosition = elapsedPosition + elapsed
        if elapsedPosition >= .2 then elapsedPosition = 0; playerPosition() end
    end)
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

function DungeonMap:Open(dungeon, bossIndex, preferredFloor, entrance)
    local frame = self:EnsureFrame()
    local strata = addon.UI.map:GetFrameStrata()
    frame:SetFrameStrata((strata == "FULLSCREEN" or strata == "FULLSCREEN_DIALOG") and "FULLSCREEN_DIALOG" or "DIALOG")
    self.dungeon, self.followInstance, self.entrance = dungeon, nil, entrance
    local boss = bossIndex and dungeon.bosses[bossIndex]
    local index = preferredFloor or (boss and bossFloor(dungeon, boss)) or 1
    frame:Show()
    self:SetFloor(index)
end

function DungeonMap:Close()
    self.dungeon, self.followInstance, self.entrance = nil, nil, nil
    if self.frame then self.frame:Hide() end
end

function DungeonMap:IsInside(key)
    return self.playerDungeon and self.playerDungeon.id == key
end

function DungeonMap:OpenInstance(onlyFollowing)
    self.playerInstance, self.playerDungeon, self.playerFloor = nil, nil, nil
    if not IsInInstance() or not GetInstanceInfo then self:UpdatePlayer(); return end
    local name, _, difficulty, _, _, _, _, id = GetInstanceInfo()
    if issecretvalue and issecretvalue(id) then self:UpdatePlayer(); return end
    local wings = byInstance[id]
    if not wings then self:UpdatePlayer(); return end
    self.playerInstance = id
    self.difficulty = addon.IsReadableNumber(difficulty) and difficulty or nil
    local area = GetSubZoneText and GetSubZoneText()
    if issecretvalue and issecretvalue(area) then area = nil end
    if issecretvalue and issecretvalue(name) then name = nil end
    local namedWing
    for _, wing in ipairs(wings) do
        if wing.name == name then namedWing = wing end
    end
    local match = area and area ~= "" and ("|" .. area .. "|")
    local mapID = C_Map.GetBestMapForUnit("player")
    if not addon.IsReadableNumber(mapID) then mapID = nil end
    local choice, index, matches = nil, nil, 0
    local mapWing, mapFloor, mapMatches = nil, nil, 0
    for _, wing in ipairs(wings) do
        if not namedWing or namedWing == wing then
            for i, floor in ipairs(addon.floorData[wing.id].floors) do
                if match and floor.zones:find(match, 1, true) then
                    choice, index, matches = wing, i, matches + 1
                end
                if mapID and floor.mapID == mapID then mapWing, mapFloor, mapMatches = wing, i, mapMatches + 1 end
            end
        end
    end
    if matches ~= 1 then
        local previous = self.chosenWing
        if previous and addon.floorData[previous.id].instance ~= id then previous = nil end
        if mapMatches == 1 then choice, index = mapWing, mapFloor
        else choice, index = namedWing or (#wings == 1 and wings[1]) or previous, nil end
    end
    if choice then
        self.playerDungeon = choice
        self.playerFloor = index or (#addon.floorData[choice.id].floors == 1 and 1 or nil)
    end
    self:UpdatePlayer()
    local map = addon.UI.map
    if not map or not map:IsShown() or (onlyFollowing and not self.followInstance) then return end
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
            menu:CreateButton(wing.name, function() self.chosenWing = wing; self:OpenInstance() end)
        end
    end)
end
