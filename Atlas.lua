local _, addon = ...
local Atlas = {}
addon.Atlas = Atlas
local zoom = addon.MapZoom
local WORLD = 947
local ASPECT = 1002 / 668
local MAX_ZOOM = 40
local continents = {1414, 1415}
local capitals = {[1453]=true, [1454]=true, [1455]=true, [1456]=true, [1457]=true, [1458]=true}

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- All artwork, entrances and cursor movement use the same Azeroth coordinates.
-- The shipped rectangles also cover map relationships the client cannot project.
local function bounds(child, parent)
    local l, r, t, b
    if C_Map.GetMapRectOnMap then l, r, t, b = C_Map.GetMapRectOnMap(child, parent) end
    if addon.IsReadableNumber(l) and addon.IsReadableNumber(r) and r > l
        and addon.IsReadableNumber(t) and addon.IsReadableNumber(b) and b > t then
        return l, r, t, b
    end
    local row = addon.overviewBounds[parent] and addon.overviewBounds[parent][child]
    if row then return unpack(row) end
end

local function addMap(maps, byID, id, kind, parent)
    if byID[id] then return end
    local l, r, t, b = 0, 1, 0, 1
    if parent then
        local pl, pr, pt, pb = bounds(id, parent.id)
        if not pl then return end
        l, r = parent.left + pl * parent.width, parent.left + pr * parent.width
        t, b = parent.top + pt * parent.height, parent.top + pb * parent.height
    end
    local record = {
        id=id, kind=kind, parent=parent, left=l, right=r, top=t, bottom=b, width=r-l, height=b-t,
    }
    maps[#maps + 1], byID[id] = record, record
    return record
end

local function children(parent, mapType)
    local ids, seen = {}, {}
    local results = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(parent.id, mapType, false) or {}
    for _, info in ipairs(results) do
        if info.mapType == mapType then seen[info.mapID] = true end
    end
    for id in pairs(addon.overviewBounds[parent.id] or {}) do
        local info = C_Map.GetMapInfo(id)
        if info and info.mapType == mapType then seen[id] = true end
    end
    for id in pairs(seen) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function geography()
    local maps, byID = {}, {}
    local world = addMap(maps, byID, WORLD, "world")
    local types = Enum.UIMapType
    local extent = {left=0, right=1, top=0, bottom=1}
    for _, id in ipairs(continents) do
        local continent = addMap(maps, byID, id, "continent", world)
        if continent then
            extent.left = math.min(extent.left, continent.left)
            extent.right = math.max(extent.right, continent.right)
            extent.top = math.min(extent.top, continent.top)
            extent.bottom = math.max(extent.bottom, continent.bottom)
            for _, zoneID in ipairs(children(continent, types.Zone)) do
                addMap(maps, byID, zoneID, capitals[zoneID] and "city" or "zone", continent)
            end
        end
    end
    for _, id in ipairs(children(world, types.Zone)) do
        addMap(maps, byID, id, capitals[id] and "city" or "zone", world)
    end
    return maps, byID, extent
end

local function canBrowse(map)
    return map and map:IsShown() and not InCombatLockdown() and not InputUtil.IsGamepadUIEnabled()
        and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures and C_Map.GetMapInfoAtPosition
end

local function cursor(frame)
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    return x / scale - (frame:GetLeft() or 0), (frame:GetTop() or 0) - y / scale
end

local function viewSize(frame)
    local w, h = frame:GetSize()
    local fittedWidth = math.min(w, h * ASPECT)
    if fittedWidth <= 0 then return end
    local scale = frame.camera.zoom * fittedWidth
    return w / scale, h * ASPECT / scale
end

local function clampAxis(value, low, high, size)
    if size >= high - low then return (low + high) / 2 end
    return clamp(value, low + size / 2, high - size / 2)
end

local function regionAt(frame, x, y)
    local record
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        local info = C_Map.GetMapInfoAtPosition(WORLD, x, y)
        record = info and frame.byID[info.mapID]
    else
        for _, id in ipairs(continents) do
            local continent = frame.byID[id]
            if continent and x >= continent.left and x <= continent.right
                and y >= continent.top and y <= continent.bottom then
                record = continent
                break
            end
        end
    end
    if record and record.kind == "continent" then
        local nx, ny = (x - record.left) / record.width, (y - record.top) / record.height
        if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
            local info = C_Map.GetMapInfoAtPosition(record.id, nx, ny)
            if info and frame.byID[info.mapID] then return frame.byID[info.mapID] end
        end
    end
    return record or frame.byID[WORLD]
end

local function playerPoint(frame)
    local id = C_Map.GetBestMapForUnit("player")
    local record = addon.IsReadableNumber(id) and frame.byID[id]
    local pos = record and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(id, "player")
    if (issecretvalue and issecretvalue(pos)) or not pos then return end
    local x, y = pos:GetXY()
    if not addon.IsReadableNumber(x) or not addon.IsReadableNumber(y) or x < 0 or y < 0 or x > 1 or y > 1 then
        return
    end
    return record, x, y
end

local function drawPlayer(frame)
    local arrow = frame.playerArrow
    local width, height = viewSize(frame)
    if not width or IsInInstance() then arrow:Hide(); return end
    local record, x, y = playerPoint(frame)
    if not record then arrow:Hide(); return end
    x = .5 + (record.left + record.width * x - frame.camera.x) / width
    y = .5 + (record.top + record.height * y - frame.camera.y) / height
    if x < 0 or x > 1 or y < 0 or y > 1 then arrow:Hide(); return end
    arrow:SetPoint("CENTER", frame, "TOPLEFT", x * frame:GetWidth(), -y * frame:GetHeight())
    local facing = GetPlayerFacing and GetPlayerFacing()
    arrow:SetRotation(addon.IsReadableNumber(facing) and facing or 0)
    arrow:Show()
end

local function draw(frame)
    local width, height = viewSize(frame)
    if not width then return end
    local strata = Atlas.map:GetFrameStrata()
    local layer = (strata == "FULLSCREEN" or strata == "FULLSCREEN_DIALOG") and "FULLSCREEN_DIALOG" or "DIALOG"
    if frame:GetFrameStrata() ~= layer then frame:SetFrameStrata(layer) end
    local camera, extent = frame.camera, frame.extent
    -- At world fit the native parchment stays centered. At closer zoom the
    -- view can extend to continent coastlines beyond the original world art.
    local margin = clamp(camera.zoom - 1, 0, 1)
    camera.x = clampAxis(camera.x, extent.left * margin, 1 + (extent.right - 1) * margin, width)
    camera.y = clampAxis(camera.y, extent.top * margin, 1 + (extent.bottom - 1) * margin, height)
    local left, top = camera.x - width / 2, camera.y - height / 2
    local region = camera.zoom >= 2 and regionAt(frame, camera.x, camera.y) or frame.byID[WORLD]
    frame.art:Draw(left, top, width, height, camera.zoom, region.id)
    if addon.settings.atlasTerrain then
        frame.terrain:Draw(left, top, width, height, camera.zoom, region.id)
    else
        frame.terrain:Clear()
    end
    frame.markers:Draw(left, top, width, height, camera.zoom)
    drawPlayer(frame)
    if frame.region ~= region.id then
        frame.region = region.id
        local label = addon.ZoneName(region.id)
        local range = addon.MapLevelRange(region.id)
        frame.location:SetText(range and (label .. " · " .. range) or label)
    end
end

local function moveZoom(frame, nextZoom)
    local camera = frame.camera
    local beforeWidth, beforeHeight = viewSize(frame)
    if not beforeWidth then return end
    camera.zoom = nextZoom
    -- In the new view, preserve the same world point below the mouse.
    local afterWidth, afterHeight = viewSize(frame)
    camera.x = camera.x + (beforeWidth - afterWidth) * (frame.anchorX - .5)
    camera.y = camera.y + (beforeHeight - afterHeight) * (frame.anchorY - .5)
end

local function anchorZoom(frame, x, y)
    frame.anchorX = clamp(x / frame:GetWidth(), 0, 1)
    frame.anchorY = clamp(y / frame:GetHeight(), 0, 1)
end

local function stopMotion(frame)
    wipe(frame.zoomMotion)
    frame.dragX, frame.dragY = nil, nil
    frame:SetScript("OnUpdate", nil)
end

local function update(frame, elapsed)
    local moved
    if frame.dragX then
        local x, y = cursor(frame)
        local width, height = viewSize(frame)
        if width then
            local camera = frame.camera
            local dx, dy = x - frame.dragX, y - frame.dragY
            camera.x = camera.x - dx * width / frame:GetWidth()
            camera.y = camera.y - dy * height / frame:GetHeight()
            anchorZoom(frame, x, y)
            frame.dragX, frame.dragY = x, y
            moved = dx ~= 0 or dy ~= 0
        end
    end
    local nextZoom = zoom.Advance(frame.zoomMotion, frame.camera.zoom, elapsed)
    if nextZoom then moveZoom(frame, nextZoom) end
    if moved or nextZoom then draw(frame) end
    if not frame.dragX and not frame.zoomMotion.target then frame:SetScript("OnUpdate", nil) end
end

local function wheel(frame, delta)
    local w, h = frame:GetSize()
    if w <= 0 or h <= 0 then return end
    if zoom.Queue(frame.zoomMotion, frame.camera.zoom, delta, MAX_ZOOM) then
        anchorZoom(frame, cursor(frame))
        frame:SetScript("OnUpdate", update)
    end
end

local function centerOn(frame, record, x, y)
    stopMotion(frame)
    frame.camera.zoom = clamp(math.min(1 / record.width, 1 / record.height) * .92, 1, MAX_ZOOM)
    frame.camera.x = record.left + record.width * (x or .5)
    frame.camera.y = record.top + record.height * (y or .5)
    draw(frame)
end

local function recenter(frame)
    local record, x, y = playerPoint(frame)
    centerOn(frame, record or frame.byID[WORLD], x, y)
end

local function createOverlay(map)
    local frame = CreateFrame("Frame", nil, map)
    frame:Hide()
    frame:SetAllPoints(map.ScrollContainer)
    frame:SetFrameLevel(map.ScrollContainer:GetFrameLevel() + 2)
    frame:SetClipsChildren(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:RegisterForDrag("LeftButton")
    frame.maps, frame.byID, frame.extent = geography()
    frame.camera = {zoom=1, x=.5, y=.5}
    frame.zoomMotion = {}
    frame.art = addon.AtlasArt.New(frame, frame.maps)
    frame.terrain = addon.AtlasTerrain.New(frame, frame.byID, frame.art.frame)
    frame.markers = addon.AtlasPins.New(frame, frame.maps, frame.byID)
    local positionUpdates = CreateFrame("Frame", nil, frame)
    positionUpdates:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame.playerArrow = positionUpdates:CreateTexture(nil, "OVERLAY")
    frame.playerArrow:SetSize(22, 22)
    frame.playerArrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    frame.playerArrow:Hide()
    local sincePosition = 0
    positionUpdates:SetScript("OnUpdate", function(_, elapsed)
        sincePosition = sincePosition + elapsed
        if sincePosition >= .2 then
            sincePosition = 0
            drawPlayer(frame)
        end
    end)

    local footer = CreateFrame("Frame", nil, frame)
    footer:SetFrameLevel(frame:GetFrameLevel() + 2)
    footer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    footer:SetSize(330, 22)
    local background = footer:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(.06, .04, .025, .86)
    frame.location = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.location:SetPoint("CENTER")
    frame.location:SetWidth(318)

    frame:SetScript("OnMouseWheel", wheel)
    frame:SetScript("OnDragStart", function()
        frame.dragX, frame.dragY = cursor(frame)
        frame:SetScript("OnUpdate", update)
    end)
    frame:SetScript("OnDragStop", function()
        frame.dragX, frame.dragY = nil, nil
        if not frame.zoomMotion.target then frame:SetScript("OnUpdate", nil) end
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Atlas:Close()
        elseif button == "MiddleButton" then recenter(frame) end
    end)
    frame:SetScript("OnSizeChanged", function() if frame:IsShown() then draw(frame) end end)
    frame:SetScript("OnHide", function()
        stopMotion(frame)
        frame.terrain:Clear()
        frame.art:Clear()
        frame.markers:Clear()
    end)
    return frame
end

function Atlas:Attach(map)
    self.map = map
end

function Atlas:Available()
    return not not (canBrowse(self.map) and not addon.DungeonMap.dungeon)
end

function Atlas:Open()
    if not self:Available() then return end
    local map = self.map
    self.frame = self.frame or createOverlay(map)
    local frame = self.frame
    if not frame.art:HasWorldArt(WORLD) then return end
    self.active = true
    frame:Show()
    local record = frame.byID[map:GetMapID()]
    centerOn(frame, record or frame.byID[WORLD])
end

function Atlas:Close()
    self.active = nil
    if self.frame then self.frame:Hide() end
end

function Atlas:Suspend()
    if self.active then self.frame:Hide() end
end

function Atlas:Resume()
    if not self.active then return end
    if not self:Available() then self:Close(); return end
    self.frame:Show()
    draw(self.frame)
end

function Atlas:Refresh()
    if self.active and self.frame:IsShown() then draw(self.frame) end
end

function Atlas:ExplorationChanged()
    if not self.active or not self.frame:IsShown() then return end
    self.frame.art:ExplorationChanged()
    draw(self.frame)
end
