local _, addon = ...
local Terrain = {}
Terrain.__index = Terrain
addon.AtlasTerrain = Terrain

local GRID_SIZE = 64
local DETAIL_START, DETAIL_FULL, DETAIL_ALPHA = 11, 23, .72

function Terrain.New(parent, byID, artFrame)
    return setmetatable({parent=parent, byID=byID, artFrame=artFrame, active={}, pool={}, missing={}}, Terrain)
end

local function release(self, index)
    local tile = self.active[index]
    tile:Hide()
    tile:SetTexture(nil)
    self.pool[#self.pool + 1] = tile
    self.active[index] = nil
end

function Terrain:Clear()
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
    tile = table.remove(self.pool) or self.artFrame:CreateTexture(nil, "ARTWORK", -4)
    if tile:SetTexture(file, nil, nil, "TRILINEAR") == false then
        tile:Hide()
        tile:SetTexture(nil)
        self.pool[#self.pool + 1] = tile
        self.missing[file] = true
        return
    end
    tile:SetDrawLayer("ARTWORK", -4)
    self.active[index] = tile
    return tile
end

local function continentFor(record)
    if record and record.kind == "city" then return end
    while record and record.kind ~= "continent" do
        record = record.parent
    end
    return record
end

function Terrain:Draw(left, top, width, height, zoom, focusID)
    local continent = continentFor(self.byID[focusID])
    local grid = continent and addon.atlasTerrain and addon.atlasTerrain[continent.id]
    local viewportWidth, viewportHeight = self.parent:GetSize()
    if zoom <= DETAIL_START or not grid or width <= 0 or height <= 0 or viewportWidth <= 0 or viewportHeight <= 0 then
        self:Clear()
        return
    end
    if self.continent ~= continent.id then
        self:Clear()
        self.continent = continent.id
    end

    local fade = math.min(1, (zoom - DETAIL_START) / (DETAIL_FULL - DETAIL_START))
    local alpha = DETAIL_ALPHA * fade * fade * (3 - 2 * fade)
    local gridLeft = continent.left + grid.left * continent.width
    local gridTop = continent.top + grid.top * continent.height
    local stepX, stepY = grid.stepX * continent.width, grid.stepY * continent.height
    -- The WDT grid can extend beyond the continent art. Preserve the parchment
    -- at the edge instead of spilling that grid into unrelated world areas.
    local clipLeft, clipTop = math.max(left, continent.left), math.max(top, continent.top)
    local clipRight = math.min(left + width, continent.left + continent.width)
    local clipBottom = math.min(top + height, continent.top + continent.height)
    if clipRight <= clipLeft or clipBottom <= clipTop then self:Clear(); return end
    local firstColumn, lastColumn = visibleTiles(clipLeft, clipRight - clipLeft, gridLeft, stepX)
    local firstRow, lastRow = visibleTiles(clipTop, clipBottom - clipTop, gridTop, stepY)
    for index in pairs(self.active) do
        local col, row = index % GRID_SIZE, math.floor(index / GRID_SIZE)
        if col < firstColumn or col > lastColumn or row < firstRow or row > lastRow then release(self, index) end
    end

    local scaleX, scaleY = viewportWidth / width, viewportHeight / height
    for row = firstRow, lastRow do
        local tileTop = gridTop + row * stepY
        local y0, y1 = math.max(tileTop, clipTop), math.min(tileTop + stepY, clipBottom)
        for col = firstColumn, lastColumn do
            local index = row * GRID_SIZE + col
            local file = grid.tiles[index]
            local tileLeft = gridLeft + col * stepX
            local x0, x1 = math.max(tileLeft, clipLeft), math.min(tileLeft + stepX, clipRight)
            if file and not self.missing[file] and x1 > x0 and y1 > y0 then
                local tile = acquire(self, index, file)
                if tile then
                    tile:SetPoint("TOPLEFT", self.artFrame, "TOPLEFT", (x0 - left) * scaleX, -(y0 - top) * scaleY)
                    tile:SetSize((x1 - x0) * scaleX, (y1 - y0) * scaleY)
                    tile:SetTexCoord((x0 - tileLeft) / stepX, (x1 - tileLeft) / stepX,
                        (y0 - tileTop) / stepY, (y1 - tileTop) / stepY)
                    tile:SetAlpha(alpha)
                    tile:Show()
                end
            end
        end
    end
end
