local _, addon = ...
local Terrain = {}
Terrain.__index = Terrain
addon.AtlasTerrain = Terrain

local GRID_SIZE = 64
local PRELOAD_ZOOM, DETAIL_ZOOM = 7, 8

function Terrain.New(parent, maps, artFrame)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(artFrame:GetFrameLevel() + 1)
    local water = frame:CreateTexture(nil, "BACKGROUND")
    water:SetAllPoints(frame)
    water:SetColorTexture(.17, .31, .39)
    local continents = {}
    for _, map in ipairs(maps) do
        if map.kind == "continent" and addon.atlasTerrain[map.id] then continents[#continents + 1] = map end
    end
    frame:Hide()
    return setmetatable({parent=parent, frame=frame, continents=continents, active={}, pool={}, missing={}}, Terrain)
end

local function release(self, index)
    local tile = self.active[index]
    tile:Hide()
    tile:SetTexture(nil)
    self.pool[#self.pool + 1] = tile
    self.active[index] = nil
end

function Terrain:Clear()
    self.frame:Hide()
    self.frame:SetScript("OnUpdate", nil)
    for index in pairs(self.active) do release(self, index) end
    self.continent = nil
end

local function visibleTiles(viewStart, viewSize, gridStart, step)
    return math.max(0, math.floor((viewStart - gridStart) / step)),
        math.min(GRID_SIZE - 1, math.ceil((viewStart + viewSize - gridStart) / step) - 1)
end

local function acquire(self, index, file)
    local tile = self.active[index]
    if tile then return tile end
    tile = table.remove(self.pool)
    if not tile then
        tile = self.frame:CreateTexture(nil, "ARTWORK")
        if tile.SetSnapToPixelGrid then tile:SetSnapToPixelGrid(false) end
        if tile.SetTexelSnappingBias then tile:SetTexelSnappingBias(0) end
    end
    if tile:SetTexture(file, nil, nil, "TRILINEAR") == false then
        tile:Hide()
        tile:SetTexture(nil)
        self.pool[#self.pool + 1] = tile
        self.missing[file] = true
        return
    end
    self.active[index] = tile
    return tile
end

local function visibleArea(record, left, top, width, height)
    return math.max(0, math.min(left + width, record.right) - math.max(left, record.left))
        * math.max(0, math.min(top + height, record.bottom) - math.max(top, record.top))
end

local function continentFor(self, focus, left, top, width, height)
    while focus and focus.kind ~= "continent" do focus = focus.parent end
    if focus and addon.atlasTerrain[focus.id] and visibleArea(focus, left, top, width, height) > 0 then
        return focus
    end
    -- Keep the same terrain when the camera drifts out across the coast.
    if self.continent and visibleArea(self.continent, left, top, width, height) > 0 then
        return self.continent
    end
    local best, area = nil, 0
    for _, continent in ipairs(self.continents) do
        local visible = visibleArea(continent, left, top, width, height)
        if visible > area then best, area = continent, visible end
    end
    return best
end

local function reveal(self, elapsed)
    self.wait = self.wait + elapsed
    if self.wait < 2 then
        for _, tile in pairs(self.active) do
            if not tile:IsObjectLoaded() then return end
        end
    end
    self.frame:SetAlpha(1)
    self.frame:SetScript("OnUpdate", nil)
end

function Terrain:Draw(left, top, width, height, zoom, focus)
    local viewportWidth, viewportHeight = self.parent:GetSize()
    if zoom < PRELOAD_ZOOM or width <= 0 or height <= 0 or viewportWidth <= 0 or viewportHeight <= 0 then
        self:Clear()
        return
    end
    local continent = continentFor(self, focus, left, top, width, height)
    if not continent then self:Clear(); return end
    if self.continent ~= continent then
        self:Clear()
        self.continent = continent
    end

    local grid = addon.atlasTerrain[continent.id]
    local gridLeft = continent.left + grid.left * continent.width
    local gridTop = continent.top + grid.top * continent.height
    local stepX, stepY = grid.stepX * continent.width, grid.stepY * continent.height
    local firstColumn, lastColumn = visibleTiles(left, width, gridLeft, stepX)
    local firstRow, lastRow = visibleTiles(top, height, gridTop, stepY)
    for index in pairs(self.active) do
        local col, row = index % GRID_SIZE, math.floor(index / GRID_SIZE)
        if col < firstColumn or col > lastColumn or row < firstRow or row > lastRow then release(self, index) end
    end

    local scaleX, scaleY = viewportWidth / width, viewportHeight / height
    local pixels = self.parent:GetEffectiveScale()
    local round = math.floor
    for row = firstRow, lastRow do
        local tileTop, tileBottom = gridTop + row * stepY, gridTop + (row + 1) * stepY
        local y0, y1 = math.max(tileTop, top), math.min(tileBottom, top + height)
        local py0 = round((y0 - top) * scaleY * pixels + .5) / pixels
        local py1 = round((y1 - top) * scaleY * pixels + .5) / pixels
        for col = firstColumn, lastColumn do
            local index = row * GRID_SIZE + col
            local file = grid.tiles[index]
            local tileLeft, tileRight = gridLeft + col * stepX, gridLeft + (col + 1) * stepX
            local x0, x1 = math.max(tileLeft, left), math.min(tileRight, left + width)
            -- Both neighbors derive their size from the same snapped edge so that zoom
            -- never leaves a thin strip of the background between terrain tiles.
            local px0 = round((x0 - left) * scaleX * pixels + .5) / pixels
            local px1 = round((x1 - left) * scaleX * pixels + .5) / pixels
            if file and not self.missing[file] and px1 > px0 and py1 > py0 then
                local tile = acquire(self, index, file)
                if tile then
                    tile:SetPoint("TOPLEFT", self.frame, "TOPLEFT", px0, -py0)
                    tile:SetSize(px1 - px0, py1 - py0)
                    tile:SetTexCoord((x0 - tileLeft) / stepX, (x1 - tileLeft) / stepX,
                        (y0 - tileTop) / stepY, (y1 - tileTop) / stepY)
                    tile:Show()
                end
            end
        end
    end
    if zoom < DETAIL_ZOOM then
        self.frame:Hide()
        self.frame:SetScript("OnUpdate", nil)
    elseif not self.frame:IsShown() then
        -- Keep the painted map fully visible until the new tiles have loaded.
        self.wait = 0
        self.frame:SetAlpha(0)
        self.frame:SetScript("OnUpdate", function(_, elapsed) reveal(self, elapsed) end)
        self.frame:Show()
        reveal(self, 0)
    end
end
