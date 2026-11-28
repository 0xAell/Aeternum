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

local function loadLayer(id, index, layer)
    local files = C_Map.GetMapArtLayerTextures(id, index)
    if type(files) ~= "table" then return false end
    for _, file in pairs(files) do
        if addon.IsReadableNumber(file) and file > 0 then
            return tileSet(layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight, files)
        end
    end
    return false
end

local function loadMap(id)
    if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return false end
    local layers = C_Map.GetMapArtLayers(id)
    if type(layers) ~= "table" then return false end
    local base
    local valid = addon.IsReadableNumber
    for index, layer in ipairs(layers) do
        local width, height = layer.layerWidth, layer.layerHeight
        local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
        if valid(width) and width > 0 and valid(height) and height > 0
            and valid(tileWidth) and tileWidth > 0 and valid(tileHeight) and tileHeight > 0 then
            if not base then
                base = loadLayer(id, index, layer)
                if base then base.details = {} end
            elseif width >= base.width and height >= base.height
                and math.abs(width * base.height / (height * base.width) - 1) <= .01 then
                -- Both layers use the same geographic rectangle. Different aspect ratios
                -- cannot be registered reliably with the data the client exposes.
                local denser = width > base.width or height > base.height
                if denser or valid(layer.minScale) then
                    base.details[#base.details + 1] = {index=index, layer=layer, denser=denser}
                end
            end
        end
    end
    return base or false
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
    -- Each map group has slots for its base, two detail layers, and two exploration layers.
    if map.kind == "world" then return 0, 1 end
    if map.kind == "continent" then return 5, ease((zoom - 1.1) / 1.4) end
    local dx = math.max(map.left - x, x - map.right, 0) / width
    local dy = math.max(map.top - y, y - map.bottom, 0) / height
    local proximity = ease(1 - 2 * math.sqrt(dx * dx + dy * dy))
    if map.kind == "city" then return 21, ease((zoom - 10) / 5) * proximity end
    local detail = ease((zoom - 2.7) / 3.3) * proximity
    if map.id == focus then
        local edgeX = math.min(x - map.left, map.right - x) / width
        local edgeY = math.min(y - map.top, map.bottom - y) / height
        local emphasis = ease(6 * math.min(edgeX, edgeY))
        return 15, detail * (.65 + .35 * emphasis)
    end
    return 10, detail * .65
end

function Art.New(parent, maps)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    frame:SetFrameLevel(parent:GetFrameLevel())
    local backdrop = frame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints(frame)
    backdrop:SetColorTexture(.21, .25, .22)
    return setmetatable({
        frame=frame, parent=parent, maps=maps, background=backdrop, data={}, visible={}, pool={}, loading={},
    }, Art)
end

function Art:HasWorldArt(mapID)
    self.data[mapID] = self.data[mapID] or loadMap(mapID)
    local atlas = C_Map.GetMapArtBackgroundAtlas and C_Map.GetMapArtBackgroundAtlas(mapID)
    if type(atlas) == "string" and atlas ~= "" then self.background:SetAtlas(atlas) end
    return not not self.data[mapID]
end

local function drawOrder(tile, order)
    tile:SetDrawLayer(order < 16 and "BORDER" or "ARTWORK", order % 16 - 8)
end

local function applyAlpha(self, tile, alpha)
    if not self.loading[tile] then
        tile:SetAlpha(alpha)
        return
    end
    self.loading[tile].alpha = alpha
end

local function watchLoad(self, tile)
    if tile:IsObjectLoaded() then return end
    self.loading[tile] = {alpha=0, elapsed=0}
    tile:SetAlpha(0)
    if self.frame:GetScript("OnUpdate") then return end
    self.frame:SetScript("OnUpdate", function(frame, elapsed)
        for loading, state in pairs(self.loading) do
            state.elapsed = state.elapsed + elapsed
            if loading:IsObjectLoaded() then
                loading:SetAlpha(state.alpha)
                self.loading[loading] = nil
            elseif state.elapsed > 2 then
                -- The base tile still covers this region if detail is unavailable.
                self.loading[loading] = nil
                loading:Hide()
            end
        end
        if not next(self.loading) then frame:SetScript("OnUpdate", nil) end
    end)
end

local function release(self, active, index)
    local tile = active[index]
    tile:Hide()
    tile:SetTexture(nil)
    self.loading[tile] = nil
    self.pool[#self.pool + 1] = tile
    active[index] = nil
end

local function releaseTiles(self, data)
    for index in pairs(data.active) do release(self, data.active, index) end
end

local function releaseMapTiles(self, data)
    releaseTiles(self, data)
    for _, detail in ipairs(data.details) do
        if detail.tiles then releaseTiles(self, detail.tiles) end
    end
    for _, overlay in ipairs(data.overlays or {}) do releaseTiles(self, overlay) end
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
                        watchLoad(self, tile)
                    end
                end
                if tile then
                    local recovered = not tile:IsShown() and tile:IsObjectLoaded()
                    if recovered then tile:Show() end
                    if new or layer ~= data.layer then drawOrder(tile, layer) end
                    if new or recovered or alpha ~= data.alpha then applyAlpha(self, tile, alpha) end
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

local function detailOpacity(detail, localZoom, density)
    local minScale = detail.layer.minScale
    local at = addon.IsReadableNumber(minScale) and math.max(1, minScale) or 1
    local opacity = ease((localZoom / at - 1) / .25)
    if detail.denser then opacity = math.min(opacity, ease((density - .85) / .35)) end
    return opacity
end

local function detailLayers(id, data, localZoom, density)
    local lower, upper
    for _, detail in ipairs(data.details) do
        local opacity = detailOpacity(detail, localZoom, density)
        if opacity > .01 then
            if detail.tiles == nil then detail.tiles = loadLayer(id, detail.index, detail.layer) end
            if detail.tiles then
                detail.opacity = opacity
                lower, upper = upper, detail
            end
        end
    end
    return lower, upper
end

function Art:Draw(left, top, viewWidth, viewHeight, zoom, focusedMapID)
    local viewportWidth, viewportHeight = self.parent:GetSize()
    if viewportWidth <= 0 or viewportHeight <= 0 or viewWidth <= 0 or viewHeight <= 0 then return end
    local right, bottom = left + viewWidth, top + viewHeight
    local centerX, centerY = left + viewWidth * .5, top + viewHeight * .5
    local scaleX, scaleY = viewportWidth / viewWidth, viewportHeight / viewHeight
    local focus = zoom > 2.7 and focusedZone(self.maps, centerX, centerY, focusedMapID)
    local pixelScale = self.parent:GetEffectiveScale()

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
                    local localZoom = math.max(width / viewportWidth, height / viewportHeight)
                    local density = math.max(width / data.width, height / data.height) * pixelScale
                    local lower, upper = detailLayers(map.id, data, localZoom, density)
                    if lower then
                        drawTiles(self, lower.tiles, x, y, width, height, viewportWidth, viewportHeight,
                            layer + 1, alpha * lower.opacity)
                    end
                    if upper then
                        drawTiles(self, upper.tiles, x, y, width, height, viewportWidth, viewportHeight,
                            layer + 2, alpha * upper.opacity)
                    end
                    for _, detail in ipairs(data.details) do
                        if detail.tiles and detail ~= lower and detail ~= upper then
                            releaseTiles(self, detail.tiles)
                        end
                    end
                    if not data.overlays then data.overlays = exploredTiles(map.id, data) end
                    local sx, sy = width / data.width, height / data.height
                    for _, overlay in ipairs(data.overlays) do
                        drawTiles(self, overlay, x + overlay.x * sx, y + overlay.y * sy,
                            overlay.width * sx, overlay.height * sy,
                            viewportWidth, viewportHeight, layer + 2 + overlay.layerOffset, alpha)
                    end
                end
            end
        end
    end
    for id, data in pairs(self.data) do
        if data and not self.visible[id] then releaseMapTiles(self, data) end
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
    for _, data in pairs(self.data) do
        if data then releaseMapTiles(self, data) end
    end
    self.frame:SetScript("OnUpdate", nil)
    wipe(self.data)
    wipe(self.visible)
end
