local _, addon = ...

local Art = {}
Art.__index = Art
addon.AtlasArt = Art

local function ease(value)
    local t = math.max(0, math.min(1, value))
    return t * t * (3 - 2 * t)
end

local function tileSet(width, height, tileWidth, tileHeight, files)
    return {
        width = width, height = height, tileWidth = tileWidth, tileHeight = tileHeight, files = files,
        columns = math.ceil(width / tileWidth), rows = math.ceil(height / tileHeight), active = {}, missing = {},
    }
end

local function loadMap(id)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return false end
    local layers = C_Map.GetMapArtLayers(id)
    local layer = type(layers) == "table" and layers[1]
    if not layer then return false end
    local width, height = layer.layerWidth, layer.layerHeight
    local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
    local valid = addon.IsReadableNumber
    if not (valid(width) and width > 0 and valid(height) and height > 0
        and valid(tileWidth) and tileWidth > 0 and valid(tileHeight) and tileHeight > 0) then return false end
    local files = C_Map.GetMapArtLayerTextures(id, 1)
    if type(files) ~= "table" or not next(files) then return false end
    return tileSet(width, height, tileWidth, tileHeight, files)
end

local function exploredTiles(id, base)
    local overlays = {}
    local getTextures = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures
    if not getTextures then return overlays end
    local valid = addon.IsReadableNumber
    for _, info in ipairs(getTextures(id) or {}) do
        local w, h = info.textureWidth, info.textureHeight
        local x, y = info.offsetX, info.offsetY
        local files = info.fileDataIDs
        if not info.isShownByMouseOver and valid(w) and w > 0 and valid(h) and h > 0 and valid(x) and valid(y)
            and type(files) == "table" and next(files) then
            local overlay = tileSet(w, h, base.tileWidth, base.tileHeight, files)
            overlay.x, overlay.y = x, y
            overlay.layerOffset = info.isDrawOnTopLayer and 2 or 1
            overlays[#overlays + 1] = overlay
        end
    end
    return overlays
end

local function intersects(map, left, top, right, bottom)
    return map.left < right and map.right > left and map.top < bottom and map.bottom > top
end

local function focusedZone(maps, x, y, preferred)
    local id, bestDistance
    for _, map in ipairs(maps) do
        if map.kind == "zone" and x >= map.left and x <= map.right and y >= map.top and y <= map.bottom then
            if map.id == preferred then return preferred end
            local dx = (x - map.left) / (map.right - map.left) - .5
            local dy = (y - map.top) / (map.bottom - map.top) - .5
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then
                id, bestDistance = map.id, distance
            end
        end
    end
    return id
end

local function layerStyle(map, zoom, x, y, width, height, focus)
    -- Each map group has room for base art, explored terrain, and top-layer terrain.
    if map.kind == "world" then return -8, 1 end
    if map.kind == "continent" then return -5, ease((zoom - 1.1) / 1.4) end
    local dx = math.max(map.left - x, x - map.right, 0) / width
    local dy = math.max(map.top - y, y - map.bottom, 0) / height
    local proximity = ease(1 - 2 * math.sqrt(dx * dx + dy * dy))
    if map.kind == "city" then return 4, ease((zoom - 10) / 5) * proximity end
    local detail = ease((zoom - 2.7) / 3.3) * proximity
    if map.id == focus then return 1, detail end
    return -2, detail * .65
end

function Art.New(parent, maps)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel())
    local backdrop = frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(frame)
    backdrop:SetColorTexture(.21, .25, .22)
    return setmetatable({ frame = frame, parent = parent, maps = maps, data = {}, visible = {}, pool = {} }, Art)
end

function Art:HasWorldArt(mapID)
    self.data[mapID] = self.data[mapID] or loadMap(mapID)
    return not not self.data[mapID]
end

local function release(self, active, index)
    local tile = active[index]
    tile:Hide()
    tile:SetTexture(nil)
    self.pool[#self.pool + 1] = tile
    active[index] = nil
end

local function releaseTiles(self, data)
    for index in pairs(data.active) do release(self, data.active, index) end
end

local function trimTiles(self, data, firstCol, lastCol, firstRow, lastRow)
    for index in pairs(data.active) do
        local col = (index - 1) % data.columns + 1
        local row = math.floor((index - 1) / data.columns) + 1
        if col < firstCol or col > lastCol or row < firstRow or row > lastRow then
            release(self, data.active, index)
        end
    end
end

local function textureFraction(length, paddedSize, isOverlay)
    if isOverlay and length < paddedSize then
        -- The client pads the final exploration tile to a power of two, at least 16 px.
        paddedSize = 16
        while paddedSize < length do paddedSize = paddedSize * 2 end
    end
    return length / paddedSize
end

local function drawTiles(self, data, x, y, width, height, viewportWidth, viewportHeight, layer, alpha)
    local scaleX, scaleY = width / data.width, height / data.height
    local stepX, stepY = data.tileWidth * scaleX, data.tileHeight * scaleY
    local firstCol = math.max(1, math.floor(-x / stepX) + 1)
    local firstRow = math.max(1, math.floor(-y / stepY) + 1)
    local lastCol = math.min(data.columns, math.ceil((viewportWidth - x) / stepX))
    local lastRow = math.min(data.rows, math.ceil((viewportHeight - y) / stepY))
    trimTiles(self, data, firstCol, lastCol, firstRow, lastRow)

    for row = firstRow, lastRow do
        for col = firstCol, lastCol do
            local index = (row - 1) * data.columns + col
            local file = data.files[index]
            if not data.missing[index] and addon.IsReadableNumber(file) and file > 0 then
                local tile = data.active[index]
                local new = not tile
                local w = math.min(data.tileWidth, data.width - (col - 1) * data.tileWidth)
                local h = math.min(data.tileHeight, data.height - (row - 1) * data.tileHeight)
                if not tile then
                    tile = table.remove(self.pool) or self.frame:CreateTexture(nil, "ARTWORK")
                    data.active[index] = tile
                    if tile:SetTexture(file, nil, nil, "TRILINEAR") == false then
                        release(self, data.active, index)
                        data.missing[index] = true
                        tile = nil
                    else
                        tile:SetTexCoord(0, textureFraction(w, data.tileWidth, data.layerOffset),
                            0, textureFraction(h, data.tileHeight, data.layerOffset))
                        tile:Show()
                    end
                end
                if tile then
                    if new or layer ~= data.layer then tile:SetDrawLayer("ARTWORK", layer) end
                    if new or alpha ~= data.alpha then tile:SetAlpha(alpha) end
                    tile:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x + (col - 1) * stepX, -y - (row - 1) * stepY)
                    if new or scaleX ~= data.scaleX or scaleY ~= data.scaleY then
                        tile:SetSize(w * scaleX, h * scaleY)
                    end
                end
            end
        end
    end
    data.layer, data.alpha = layer, alpha
    data.scaleX, data.scaleY = scaleX, scaleY
end

function Art:Draw(left, top, viewWidth, viewHeight, zoom, focusedMapID)
    local viewportWidth, viewportHeight = self.parent:GetSize()
    if viewportWidth <= 0 or viewportHeight <= 0 or viewWidth <= 0 or viewHeight <= 0 then return end
    local right, bottom = left + viewWidth, top + viewHeight
    local centerX, centerY = left + viewWidth * .5, top + viewHeight * .5
    local scaleX, scaleY = viewportWidth / viewWidth, viewportHeight / viewHeight
    local focus = zoom > 2.7 and focusedZone(self.maps, centerX, centerY, focusedMapID)

    for _, map in ipairs(self.maps) do
        self.visible[map.id] = nil
        if intersects(map, left, top, right, bottom) then
            local layer, alpha = layerStyle(map, zoom, centerX, centerY, viewWidth, viewHeight, focus)
            if alpha > .01 then
                if self.data[map.id] == nil then self.data[map.id] = loadMap(map.id) end
                local data = self.data[map.id]
                if data then
                    self.visible[map.id] = true
                    local x, y = (map.left - left) * scaleX, (map.top - top) * scaleY
                    local width, height = (map.right - map.left) * scaleX, (map.bottom - map.top) * scaleY
                    drawTiles(self, data, x, y, width, height, viewportWidth, viewportHeight, layer, alpha)
                    if not data.overlays then data.overlays = exploredTiles(map.id, data) end
                    local sx, sy = width / data.width, height / data.height
                    for _, overlay in ipairs(data.overlays) do
                        drawTiles(self, overlay, x + overlay.x * sx, y + overlay.y * sy,
                            overlay.width * sx, overlay.height * sy,
                            viewportWidth, viewportHeight, layer + overlay.layerOffset, alpha)
                    end
                end
            end
        end
    end
    for id, data in pairs(self.data) do
        if data and not self.visible[id] then
            releaseTiles(self, data)
            if data.overlays then
                for _, overlay in ipairs(data.overlays) do releaseTiles(self, overlay) end
            end
        end
    end
end

function Art:ExplorationChanged()
    for _, data in pairs(self.data) do
        if data and data.overlays then
            for _, overlay in ipairs(data.overlays) do releaseTiles(self, overlay) end
            data.overlays = nil
        end
    end
end

function Art:Clear()
    self:ExplorationChanged()
    for _, data in pairs(self.data) do
        if data then releaseTiles(self, data) end
    end
    wipe(self.data)
    wipe(self.visible)
end
