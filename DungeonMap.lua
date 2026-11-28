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
    if not scale or scale <= 0 then scale = 1 end
    return x / scale - (frame:GetLeft() or 0), (frame:GetTop() or 0) - y / scale
end

local function syncStrata(frame)
    local map = addon.UI.map
    if not map then return end
    local strata = map:GetFrameStrata()
    local target = (strata == "FULLSCREEN" or strata == "FULLSCREEN_DIALOG") and "FULLSCREEN_DIALOG" or "DIALOG"
    if frame:GetFrameStrata() ~= target then
        frame:SetFrameStrata(target)
    end
end

local function fitScale(w, h)
    return math.min(w / WIDTH, h / HEIGHT)
end

local function place(frame)
    syncStrata(frame)
    local w, h = frame:GetSize()
    if w <= 0 or h <= 0 then return end
    local scale = fitScale(w, h) * frame.zoom
    local aw, ah = WIDTH * scale, HEIGHT * scale
    frame.x = aw <= w and (w - aw) / 2 or clamp(frame.x, w - aw, 0)
    frame.y = ah <= h and (h - ah) / 2 or clamp(frame.y, h - ah, 0)
    frame.art:SetScale(scale)
    frame.art:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.x / scale, -frame.y / scale)
    -- Keep skulls the size of a normal map icon at every zoom.
    for _, pin in ipairs(frame.pins) do pin:SetSize(20 / scale, 20 / scale) end
    frame.playerArrow:SetSize(22 / scale, 22 / scale)
    addon.BossHover:Refresh()
end

local function fitFloor(frame)
    frame.zoom, frame.x, frame.y = 1, 0, 0
    place(frame)
end

local function anchorDrag(frame)
    local x, y = cursor(frame)
    frame.dragX, frame.dragY = x - frame.x, y - frame.y
end

local function resize(frame)
    local w, h = frame:GetSize()
    if w <= 0 or h <= 0 then return end
    local previousW, previousH = frame.viewWidth, frame.viewHeight
    if previousW > 0 and previousH > 0 then
        local ratio = fitScale(w, h) / fitScale(previousW, previousH)
        frame.x = w / 2 - (previousW / 2 - frame.x) * ratio
        frame.y = h / 2 - (previousH / 2 - frame.y) * ratio
    end
    frame.viewWidth, frame.viewHeight = w, h
    place(frame)
    if frame:GetScript("OnUpdate") then anchorDrag(frame) end
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
    addon.BossHover:Hide()
    for _, texture in ipairs(frame.tiles) do texture:Hide(); texture:SetTexture(nil) end
    for _, line in ipairs(frame.lines) do line:Hide() end
    for _, pin in ipairs(frame.pins) do
        if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
        pin:Hide()
        pin.boss, pin.stop, pin.label, pin.members, pin.encounters, pin.complete = nil, nil, nil, nil, nil, nil
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
    local facing = GetPlayerFacing and GetPlayerFacing()
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
            for _, encounter in ipairs(pin.encounters or pin.stop.encounters or {}) do
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
    addon.BossHover:Refresh()
end

function DungeonMap:RecordKill(encounter)
    if self.playerInstance and addon.IsReadableNumber(encounter) then
        killed[encounter] = true
        self:RefreshKills()
    end
end

-- Kills belong to one run of an instance. Dying, releasing and running back passes two
-- loading screens with the same bosses still dead, so those kills are kept. They are
-- forgotten on entering a different instance or after leaving it alive, because a living
-- group can reset the instance before going back in.
function DungeonMap:NewVisit()
    if not IsInInstance or not IsInInstance() then
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
        if issecretvalue and issecretvalue(dead) then dead = false end
        if not dead then self.leftAlive = true end
        return
    end
    local id = GetInstanceInfo and select(8, GetInstanceInfo())
    if not addon.IsReadableNumber(id) then id = nil end
    if id and id == self.killInstance and not self.leftAlive then return end
    wipe(killed)
    self.killInstance, self.leftAlive, self.chosenWing = id, nil, nil
    self.fightWing, self.fightFloor = nil, nil
end

-- A boss fight names its encounter even where the client gives neither a position nor a room
-- name inside an instance, so it shows which wing and floor the player is on. A floor view that
-- follows the player moves there; one the player chose by hand stays put.
function DungeonMap:EncounterStarted(encounter)
    if not addon.IsReadableNumber(encounter) or not self.playerInstance then return end
    for _, wing in ipairs(byInstance[self.playerInstance] or {}) do
        for index, floor in ipairs(addon.floorData[wing.id].floors) do
            for _, point in ipairs(floor.bosses) do
                for _, id in ipairs(point.encounters or {}) do
                    if id == encounter then
                        self.fightWing, self.fightFloor, self.chosenWing = wing, index, wing
                        self.playerDungeon, self.playerFloor = wing, index
                        self:UpdatePlayer()
                        local map = addon.UI.map
                        local moved = self.dungeon ~= wing or self.index ~= index
                        if map and map:IsShown() and self.followInstance and moved then
                            self:Open(wing, nil, index)
                            self.followInstance = true
                        end
                        return
                    end
                end
            end
        end
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
            for _, texture in ipairs(frame.tiles) do texture:Hide(); texture:SetTexture(nil) end
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
        if self.members and #self.members > 0 then addon.BossHover:Show(self) end
    end)
    pin:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
    pin:SetScript("OnClick", function(self, button)
        if button == "MiddleButton" then
            fitFloor(frame)
            return
        end
        addon.BossHover:Hide()
        if not self.members then return end
        if #self.members == 1 then addon.UI:Boss(self, self.boss)
        else addon.UI:BossGroup(self, self.members, self.label) end
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
    local lookup, locations, seenEncounters, count = {}, {}, {}, 0
    for _, boss in ipairs(dungeon.bosses) do lookup[boss.id] = boss end
    for _, point in ipairs(floor.bosses) do
        local member = lookup[point[1]]
        if member then
            local key = ("%s:%s"):format(point[2], point[3])
            local pin = locations[key]
            if not pin then
                count = count + 1
                pin = bossPin(frame, count)
                locations[key] = pin
                seenEncounters[key] = {}
                pin.boss, pin.stop, pin.label, pin.members, pin.encounters = member, point, point.label, {}, {}
                pin:SetPoint("CENTER", frame.art, "TOPLEFT", point[2] * WIDTH, -point[3] * HEIGHT)
                pin:Show()
            elseif not pin.label and point.label then
                pin.label = point.label
            end
            for _, encounter in ipairs(point.encounters or {}) do
                if not seenEncounters[key][encounter] then
                    seenEncounters[key][encounter] = true
                    pin.encounters[#pin.encounters + 1] = encounter
                end
            end
            pin.members[#pin.members + 1] = member
        end
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
            wings:CreateRadio(wing.name, function() return wing == dungeon end, function() DungeonMap:Open(wing) end)
        end
    end
    menu:CreateDivider()
    local bosses = menu:CreateButton("Boss loot")
    bosses:SetScrollMode(300)
    for _, boss in ipairs(dungeon.bosses) do
        local row = bosses:CreateButton(boss.name, function()
            C_Timer.After(0, function()
                if DungeonMap.dungeon ~= dungeon then return end
                local index = bossFloor(dungeon, boss)
                if index and index ~= DungeonMap.index then
                    DungeonMap.followInstance = nil
                    DungeonMap:SetFloor(index)
                end
                addon.UI:Boss(DungeonMap.frame, boss)
            end)
        end)
        row:SetTooltip(function(tooltip) addon.UI:BossTooltip(tooltip, boss) end)
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
    frame.viewWidth, frame.viewHeight = frame:GetSize()
    frame:SetScript("OnMouseWheel", zoom)
    frame:SetScript("OnDragStart", function()
        anchorDrag(frame)
        frame:SetScript("OnUpdate", function()
            local cx, cy = cursor(frame)
            frame.x, frame.y = cx - frame.dragX, cy - frame.dragY
            place(frame)
        end)
    end)
    frame:SetScript("OnDragStop", function() frame:SetScript("OnUpdate", nil) end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then self:Close()
        elseif button == "MiddleButton" then fitFloor(frame) end
    end)
    frame:SetScript("OnSizeChanged", resize)
    frame:SetScript("OnHide", function()
        frame:SetScript("OnUpdate", nil)
        clearFloor(frame)
    end)
    -- Do not call RegisterGameMenuEscHandler: sorting Blizzard's internal handler table
    -- from addon code taints subsequent Escape presses (ADDON_ACTION_FORBIDDEN).
    -- Escape closes WorldMapFrame natively, which triggers WorldMapFrame's OnHide -> Close().
    return frame
end

function DungeonMap:Open(dungeon, bossIndex, preferredFloor, entrance)
    local info = dungeon and addon.floorData[dungeon.id]
    if not info or not info.floors or #info.floors == 0 then return end
    addon.Atlas:Suspend()
    local frame = self:EnsureFrame()
    syncStrata(frame)
    self.dungeon, self.followInstance, self.entrance = dungeon, nil, entrance
    local boss = bossIndex and dungeon.bosses[bossIndex]
    local index = clamp(preferredFloor or (boss and bossFloor(dungeon, boss)) or 1, 1, #info.floors)
    frame:Show()
    self:SetFloor(index)
end

function DungeonMap:Close()
    local wasOpen = self.dungeon ~= nil
    self.dungeon, self.followInstance, self.entrance = nil, nil, nil
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        clearFloor(self.frame)
        self.frame:Hide()
    end
    if wasOpen then addon.Atlas:Resume() end
end

function DungeonMap:IsInside(key)
    return self.playerDungeon and self.playerDungeon.id == key
end

function DungeonMap:OpenInstance(onlyFollowing)
    self.playerInstance, self.playerDungeon, self.playerFloor = nil, nil, nil
    if not IsInInstance or not IsInInstance() or not GetInstanceInfo then self:UpdatePlayer(); return end
    local name, _, difficulty, _, _, _, _, id = GetInstanceInfo()
    if issecretvalue and issecretvalue(id) then self:UpdatePlayer(); return end
    local wings = byInstance[id]
    if not wings then self:UpdatePlayer(); return end
    self.playerInstance = id
    self.difficulty = addon.IsReadableNumber(difficulty) and difficulty or nil
    local area = GetSubZoneText and GetSubZoneText()
    if (issecretvalue and issecretvalue(area)) or type(area) ~= "string" then area = nil end
    if (issecretvalue and issecretvalue(name)) or type(name) ~= "string" then name = nil end
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
        -- Without a unique room or floor map, the last boss fight in this instance tells the floor.
        local fought = self.fightWing
        if fought and (addon.floorData[fought.id].instance ~= id or (namedWing and namedWing ~= fought)) then
            fought = nil
        end
        if mapMatches == 1 then choice, index = mapWing, mapFloor
        elseif fought then choice, index = fought, self.fightFloor
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
    if self.followInstance or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    -- Several wings share one instance ID. Let the player pick if the client
    -- hasn't given a unique wing or floor name.
    MenuUtil.CreateContextMenu(map, function(_, menu)
        menu:CreateTitle("Choose a dungeon wing")
        for _, wing in ipairs(wings) do
            menu:CreateButton(wing.name, function() self.chosenWing = wing; self:OpenInstance() end)
        end
    end)
end
