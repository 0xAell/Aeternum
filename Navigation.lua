local _, addon = ...

local Navigation = { status = "Choose a dungeon entrance to start guidance." }
addon.Navigation = Navigation

local UPDATE_INTERVAL = 0.12
local STEP_RADIUS = 28
local ENTRANCE_RADIUS = 18
local BREADCRUMB_COUNT = 4
local MIN_ARROW_OFFSET = 16
local axesCache = {}

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function isNumber(value)
    return readable(value) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end

local function isMapPoint(point)
    return type(point) == "table" and isNumber(point.mapID) and point.mapID > 0
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
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local position = CreateVector2D(x, y)
    if not position then return end
    local continent, vector = C_Map.GetWorldPosFromMapPos(mapID, position)
    if not isNumber(continent) then return end
    local worldX, worldY = pointXY(vector)
    if worldX then return continent, worldX, worldY end
end

local function playerPoint()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not isNumber(mapID) or mapID <= 0 then return end
    local x, y = pointXY(C_Map.GetPlayerMapPosition(mapID, "player"))
    if not x then return end
    return worldPoint(mapID, x, y)
end

local function magnitude(x, y)
    return math.sqrt(x * x + y * y)
end

local function coordinatesFor(point)
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
    return { continent = continent, x = x, y = y, axes = axes, label = point.label }
end

local function facingRotation()
    local getCVarBool = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    local rotate = getCVarBool and getCVarBool("rotateMinimap")
    local ignore = C_Minimap and C_Minimap.IsRotateMinimapIgnored
    if not readable(rotate) or not rotate or (ignore and ignore()) then return 1, 0 end
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

local function setLine(line, overlay, x1, y1, x2, y2)
    line:SetStartPoint("CENTER", overlay, x1, y1)
    line:SetEndPoint("CENTER", overlay, x2, y2)
end

local function makeOverlay()
    local overlay = CreateFrame("Frame", nil, Minimap)
    overlay:SetAllPoints(Minimap)
    overlay:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    overlay:EnableMouse(false)
    overlay.arrow, overlay.outline, overlay.dots = {}, {}, {}
    for index = 1, 3 do
        local outline = overlay:CreateLine(nil, "OVERLAY", nil, 1)
        outline:SetThickness(5)
        outline:SetColorTexture(0.04, 0.09, 0.12, 0.96)
        overlay.outline[index] = outline

        local arrow = overlay:CreateLine(nil, "OVERLAY", nil, 2)
        arrow:SetThickness(2.5)
        arrow:SetColorTexture(0.35, 0.91, 0.91, 1)
        overlay.arrow[index] = arrow
    end
    for index = 1, BREADCRUMB_COUNT do
        local dot = overlay:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(0.35, 0.91, 0.91, 0.68)
        dot:SetSize(4, 4)
        overlay.dots[index] = dot
    end
    overlay.arrowLayers = { overlay.outline, overlay.arrow }
    return overlay
end

local function notify(self)
    if type(self.onChange) == "function" then
        self.onChange(self.status, self:IsActive())
    end
end

function Navigation:Draw(playerX, playerY, cosine, sine)
    if not Minimap or not Minimap.CreateLine or not Minimap:IsVisible() then return end
    local width, height = Minimap:GetSize()
    if not isNumber(width) or not isNumber(height) or width <= 30 or height <= 30 then
        if self.overlay then self.overlay:Hide() end
        return
    end
    self.overlay = self.overlay or makeOverlay()
    local overlay = self.overlay
    local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
    local hasRadius = isNumber(radius) and radius > 0
    -- Use a uniform radius so arrow bearings stay accurate on non-square minimaps.
    local edgeRadius = math.min(width, height) / 2 - 12
    local east, north = screenDirection(self.points[self.step], playerX, playerY, cosine, sine)
    local distance = magnitude(east, north)
    if distance <= 0 then
        overlay:Hide()
        return
    end
    local dirX, dirY = east / distance, north / distance
    local fraction = hasRadius and math.min(distance / radius, 1) or 1
    local tipOffset = math.min(edgeRadius, math.max(MIN_ARROW_OFFSET, edgeRadius * fraction))
    local x, y = dirX * tipOffset, dirY * tipOffset
    local wingX, wingY = x - dirX * 7, y - dirY * 7
    local tailX, tailY = x - dirX * 14, y - dirY * 14
    for _, lines in ipairs(overlay.arrowLayers) do
        setLine(lines[1], overlay, tailX, tailY, x, y)
        setLine(lines[2], overlay, wingX - dirY * 4, wingY + dirX * 4, x, y)
        setLine(lines[3], overlay, wingX + dirY * 4, wingY - dirX * 4, x, y)
    end

    -- Show only known approach points and the entrance itself, never interpolated segments.
    for index, dot in ipairs(overlay.dots) do
        local nextPoint = self.step + index
        local point = nextPoint <= #self.points and self.points[nextPoint]
        if hasRadius and point then
            local dotEast, dotNorth = screenDirection(point, playerX, playerY, cosine, sine)
            if magnitude(dotEast, dotNorth) < radius then
                dot:ClearAllPoints()
                dot:SetPoint("CENTER", overlay, "CENTER",
                    dotEast / radius * edgeRadius, dotNorth / radius * edgeRadius)
                if nextPoint == #self.points then
                    dot:SetColorTexture(1, 0.82, 0.38, 0.92)
                else
                    dot:SetColorTexture(0.35, 0.91, 0.91, 0.68)
                end
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

function Navigation:GetStatus()
    return self.status
end

function Navigation:IsActive()
    return self.points ~= nil
end

function Navigation:Stop(message)
    self.points, self.step, self.target, self.elapsed = nil, nil, nil, 0
    self.status = message or "Choose a dungeon entrance to start guidance."
    if self.worker then self.worker:Hide() end
    if self.overlay then self.overlay:Hide() end
    notify(self)
end

function Navigation:Pause(message)
    self.status = message
    if self.overlay then self.overlay:Hide() end
    notify(self)
end

function Navigation:Update()
    if not self.points then return end
    local insideInstance = IsInInstance and IsInInstance()
    if insideInstance then
        self:Pause("Entrance guidance is paused inside an instance.")
        return
    end
    local continent, playerX, playerY = playerPoint()
    if not continent then
        self:Pause("Waiting for a readable player map position.")
        return
    end
    local total = #self.points
    local last = self.points[total]
    if continent ~= last.continent then
        self:Pause("Travel to the entrance’s continent to resume guidance.")
        return
    end

    -- Always recognize arrival at the portal even if an earlier approach point was bypassed.
    local lastDistance = magnitude(last.x - playerX, last.y - playerY)
    if lastDistance <= ENTRANCE_RADIUS then
        local arrived = "Near " .. self.target .. " entrance."
        self:Stop(arrived)
        if type(print) == "function" then
            print("Aeternum: " .. arrived)
        end
        return
    end

    if not self.step then
        -- Pick the nearest point along the route (including the entrance itself) so players
        -- past an outdoor approach waypoint are never sent backwards.
        self.step = total
        local closest = lastDistance
        for index = 1, total - 1 do
            local point = self.points[index]
            local distance = magnitude(point.x - playerX, point.y - playerY)
            if distance < closest then
                self.step, closest = index, distance
            end
        end
    end

    -- Advance past any approach point along or ahead of the current step once within reach.
    for index = total - 1, self.step, -1 do
        local candidate = self.points[index]
        if magnitude(candidate.x - playerX, candidate.y - playerY) <= STEP_RADIUS then
            self.step = index + 1
            break
        end
    end

    local point = self.points[self.step]
    local distance = self.step == total and lastDistance or magnitude(point.x - playerX, point.y - playerY)

    local cosine, sine = facingRotation()
    if not cosine then
        self:Pause("Waiting for minimap orientation.")
        return
    end
    if self.step == total then
        self.status = ("Entrance bearing  •  %.0f yd"):format(distance)
    else
        self.status = ("%s  •  %.0f yd"):format(point.label or ("Approach point " .. self.step), distance)
    end
    self:Draw(playerX, playerY, cosine, sine)
    notify(self)
end

function Navigation:Start(dungeon, entrance)
    entrance = entrance or dungeon and dungeon.entrances and dungeon.entrances[1]
    if not isMapPoint(entrance) then
        self:Stop("This dungeon has no entrance coordinates.")
        return false
    end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetBestMapForUnit
        and C_Map.GetPlayerMapPosition and CreateVector2D) then
        self:Stop("This client does not provide the map APIs for guidance.")
        return false
    end

    local points = {}
    local goal = coordinatesFor(entrance)
    if not goal then
        self:Stop("A minimap position is unavailable for this entrance.")
        return false
    end
    for _, waypoint in ipairs(entrance.waypoints or {}) do
        local point = isMapPoint(waypoint) and coordinatesFor(waypoint)
        if point and point.continent == goal.continent then
            points[#points + 1] = point
        end
    end
    points[#points + 1] = goal
    self.points, self.step, self.elapsed = points, nil, 0
    self.target = dungeon and dungeon.name or "the dungeon"

    if not self.worker then
        self.worker = CreateFrame("Frame")
        self.worker:SetScript("OnUpdate", function(_, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= UPDATE_INTERVAL then
                self.elapsed = 0
                self:Update()
            end
        end)
    end
    self.worker:Show()
    self:Update()
    return true
end
