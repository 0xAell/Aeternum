local _, addon = ...

local IDLE = "No active directions."
local Navigation = { status = IDLE }
addon.Navigation = Navigation

local UPDATE_INTERVAL = 0.12
local STEP_RADIUS = 28
local ARRIVAL_RADIUS = 18
local BREADCRUMB_COUNT = 4
local sharedAxesCache = {}

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local isNumber = addon.IsReadableNumber

local function isMapPoint(point)
    return type(point) == "table" and isNumber(point.mapID) and point.mapID > 0 and point.mapID % 1 == 0
        and isNumber(point.x) and point.x >= 0 and point.x <= 1
        and isNumber(point.y) and point.y >= 0 and point.y <= 1
end

local function pointXY(vector)
    if not readable(vector) or type(vector) ~= "table" then return end
    if canaccesstable and not canaccesstable(vector) then return end
    if isNumber(vector.x) and isNumber(vector.y) then
        return vector.x, vector.y
    end
end

local function worldPoint(mapID, x, y)
    local continent, vector = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if not isNumber(continent) then return end
    local worldX, worldY = pointXY(vector)
    if worldX then return continent, worldX, worldY end
end

local function playerPoint()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not isNumber(mapID) or mapID <= 0 then return end
    local x, y = pointXY(C_Map.GetPlayerMapPosition(mapID, "player"))
    if not x then return end
    return worldPoint(mapID, x, y)
end

local function magnitude(x, y)
    return math.sqrt(x * x + y * y)
end

local function coordinatesFor(point, axesCache)
    local continent, x, y = worldPoint(point.mapID, point.x, point.y)
    if not continent then return end
    local axes = axesCache[point.mapID]
    if not axes then
        -- Positive map X points east and negative map Y points north.
        -- Sample both axes so the projection does not depend on the world's axis order.
        local center, centerX, centerY = worldPoint(point.mapID, 0.5, 0.5)
        local east, eastX, eastY = worldPoint(point.mapID, 0.75, 0.5)
        local north, northX, northY = worldPoint(point.mapID, 0.5, 0.25)
        if center ~= continent or east ~= continent or north ~= continent then return end
        eastX, eastY = eastX - centerX, eastY - centerY
        northX, northY = northX - centerX, northY - centerY
        local eastLength, northLength = magnitude(eastX, eastY), magnitude(northX, northY)
        if eastLength == 0 or northLength == 0 then return end
        axes = {
            eastX = eastX / eastLength, eastY = eastY / eastLength,
            northX = northX / northLength, northY = northY / northLength,
        }
        axesCache[point.mapID] = axes
    end
    local label = type(point.label) == "string" and point.label or nil
    return { continent = continent, x = x, y = y, axes = axes, label = label }
end

local function distanceBetween(a, x, y)
    return magnitude(a.x - x, a.y - y)
end

-- Start at the first approach point the player has not passed yet. A point counts
-- as passed when the player is already closer to the next point than it is.
local function firstStep(points, playerX, playerY)
    for index = 1, #points - 1 do
        local nextPoint = points[index + 1]
        local fromPoint = distanceBetween(nextPoint, points[index].x, points[index].y)
        if distanceBetween(nextPoint, playerX, playerY) >= fromPoint then
            return index
        end
    end
    return #points
end

local function facingRotation()
    local rotate = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("rotateMinimap")
    if not readable(rotate) then return end
    if not rotate then return 1, 0 end
    local ignored = C_Minimap and C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored()
    if not readable(ignored) then return end
    if ignored then return 1, 0 end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if isNumber(facing) then return math.cos(facing), math.sin(facing) end
end

local function screenDirection(point, playerX, playerY, cosine, sine)
    local x, y = point.x - playerX, point.y - playerY
    local axes = point.axes
    local east = x * axes.eastX + y * axes.eastY
    local north = x * axes.northX + y * axes.northY
    return east * cosine + north * sine, north * cosine - east * sine
end

local function makeOverlay()
    local overlay = CreateFrame("Frame", nil, Minimap)
    overlay:SetAllPoints(Minimap)
    overlay:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    overlay:EnableMouse(false)
    overlay.arrow = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    overlay.arrow:SetAtlas("Navigation-Tracked-Arrow")
    overlay.arrow:SetSize(18, 18)
    overlay.marker = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    overlay.marker:SetAtlas("waypoint-mappin-minimap-tracked")
    overlay.marker:SetSize(18, 18)
    overlay.dots = {}
    for index = 1, BREADCRUMB_COUNT do
        local dot = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
        dot:SetAtlas("waypoint-mappin-minimap-untracked")
        dot:SetSize(10, 10)
        dot:SetAlpha(.75)
        overlay.dots[index] = dot
    end
    return overlay
end

function Navigation:Draw(playerX, playerY, cosine, sine)
    if not Minimap or not Minimap:IsVisible() then return end
    local width, height = Minimap:GetSize()
    if not isNumber(width) or not isNumber(height) or width <= 30 or height <= 30 then
        if self.overlay then self.overlay:Hide() end
        return
    end
    self.overlay = self.overlay or makeOverlay()
    local overlay = self.overlay
    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    local hasRadius = isNumber(radius) and radius > 0
    local halfSize = math.min(width, height) / 2
    local east, north = screenDirection(self.points[self.step], playerX, playerY, cosine, sine)
    local distance = magnitude(east, north)
    if distance <= 0 then
        overlay:Hide()
        return
    end
    local inView = hasRadius and distance <= radius
    overlay.marker:SetShown(inView)
    overlay.arrow:SetShown(not inView)
    if inView then
        overlay.marker:SetPoint("CENTER", overlay, "CENTER", east / radius * halfSize, north / radius * halfSize)
    else
        overlay.arrow:SetPoint("CENTER", overlay, "CENTER",
            east / distance * (halfSize - 12), north / distance * (halfSize - 12))
        -- Blizzard's navigation atlas points up at zero radians.
        overlay.arrow:SetRotation(-math.atan2(east, north))
    end

    -- Show only known approach points, never interpolated sections through terrain.
    for index, dot in ipairs(overlay.dots) do
        local nextPoint = self.step + index
        local point = self.points[nextPoint]
        if hasRadius and point then
            local dotEast, dotNorth = screenDirection(point, playerX, playerY, cosine, sine)
            if magnitude(dotEast, dotNorth) < radius then
                local final = nextPoint == #self.points
                if dot.final ~= final then
                    dot.final = final
                    dot:SetAtlas(final and "waypoint-mappin-minimap-tracked" or "waypoint-mappin-minimap-untracked")
                end
                dot:SetPoint("CENTER", overlay, "CENTER",
                    dotEast / radius * halfSize, dotNorth / radius * halfSize)
                dot:Show()
            else
                dot:Hide()
            end
        else
            dot:Hide()
        end
    end
    overlay:Show()
end

function Navigation:SetStatus(message)
    self.status = message
end

function Navigation:GetStatus()
    return self.status
end

function Navigation:GetTarget()
    return self.target
end

function Navigation:IsActive()
    return self.points ~= nil
end

function Navigation:Stop(message)
    self.points, self.step, self.target, self.destination = nil, nil, nil, nil
    self.elapsed = 0
    AeternumRouteDB = nil
    if self.worker then self.worker:Hide() end
    if self.overlay then self.overlay:Hide() end
    self:SetStatus(message or IDLE)
    if addon.UpdateRoutePins then addon.UpdateRoutePins() end
end

function Navigation:IsDestination(point, dungeon)
    local dest = self.destination
    return dest and point and dest.dungeon == dungeon and dest.mapID == point.mapID
        and dest.x == point.x and dest.y == point.y
end

function Navigation:Pause(message)
    if self.overlay then self.overlay:Hide() end
    self:SetStatus(message)
end

function Navigation:Update()
    if not self.points then return end
    local insideInstance = IsInInstance and IsInInstance()
    if insideInstance then
        if self.destination and self.destination.dungeon and addon.DungeonMap:IsInside(self.destination.dungeon) then
            self:Stop(("Arrived at %s."):format(self.target))
        else
            self:Pause("Guidance is paused inside an instance.")
        end
        return
    end
    local continent, playerX, playerY = playerPoint()
    if not continent then
        self:Pause("Waiting for a readable player map position.")
        return
    end
    if continent ~= self.points[#self.points].continent then
        self:Pause(("Travel to %s’s continent to resume guidance."):format(self.target))
        return
    end

    if distanceBetween(self.points[#self.points], playerX, playerY) <= ARRIVAL_RADIUS then
        self:Stop(("Arrived near %s."):format(self.target))
        return
    end
    if not self.step then
        self.step = firstStep(self.points, playerX, playerY)
    end
    for index = #self.points - 1, self.step, -1 do
        if distanceBetween(self.points[index], playerX, playerY) <= STEP_RADIUS then
            self.step = index + 1
            break
        end
    end

    local point = self.points[self.step]
    local distance = distanceBetween(point, playerX, playerY)
    local cosine, sine = facingRotation()
    if not cosine then
        self:Pause("Waiting for minimap orientation.")
        return
    end
    if self.step == #self.points then
        self:SetStatus(("%s  •  %.0f yd"):format(self.target, distance))
    else
        self:SetStatus(("%s  •  %.0f yd"):format(point.label or ("Approach point " .. self.step), distance))
    end
    self:Draw(playerX, playerY, cosine, sine)
end

-- Guides the minimap arrow to destination, a map point { mapID, x, y } that may
-- list recorded approach waypoints. name labels the destination in the status.
local function makeRoute(name, destination, dungeon)
    if not isMapPoint(destination) then
        return nil, "This location has no map coordinates."
    end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetBestMapForUnit
        and C_Map.GetPlayerMapPosition and CreateVector2D) then
        return nil, "This client does not provide the map APIs for guidance."
    end

    local points = {}
    local goal = coordinatesFor(destination, sharedAxesCache)
    if not goal then
        return nil, "A minimap position is unavailable for this location."
    end
    local saved = {name=name, mapID=destination.mapID, x=destination.x, y=destination.y,
        dungeon=type(dungeon) == "string" and addon.floorData[dungeon] and dungeon or nil}
    for _, waypoint in ipairs(type(destination.waypoints) == "table" and destination.waypoints or {}) do
        local point = isMapPoint(waypoint) and coordinatesFor(waypoint, sharedAxesCache)
        if point and point.continent == goal.continent then
            points[#points + 1] = point
            saved.waypoints = saved.waypoints or {}
            saved.waypoints[#saved.waypoints + 1] = {mapID=waypoint.mapID, x=waypoint.x, y=waypoint.y,
                label=point.label}
        end
    end
    points[#points + 1] = goal
    return points, saved
end

function Navigation:Start(name, destination, dungeon)
    name = name or "the destination"
    local points, saved = makeRoute(name, destination, dungeon)
    if not points then
        if not self.points then self:SetStatus(saved) end
        return false, saved
    end
    self.target, self.points, self.step, self.destination = name, points, nil, saved
    AeternumRouteDB = saved
    self.elapsed = 0

    if not self.worker then
        self.worker = CreateFrame("Frame")
        self.worker:SetScript("OnUpdate", function(_, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed >= UPDATE_INTERVAL then
                self.elapsed = 0
                self:Update()
            end
        end)
    end
    self.worker:Show()
    self:Update()
    if addon.UpdateRoutePins then addon.UpdateRoutePins() end
    return true
end

function Navigation:Restore()
    local saved = AeternumRouteDB
    if self.points or saved == nil then return end
    if not isMapPoint(saved) or type(saved.name) ~= "string"
        or (saved.waypoints ~= nil and type(saved.waypoints) ~= "table") then
        AeternumRouteDB = nil
        return
    end
    self:Start(saved.name, saved, saved.dungeon)
end
