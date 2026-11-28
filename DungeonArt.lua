local _, addon = ...
local Art = {}
addon.DungeonArt = Art

-- FloorData's boss locations and player transform are registered to this canvas.
local WIDTH, HEIGHT, LEGACY_TILE = 1002, 668, 256
local MAX_TILES = 128
local REGISTRATION_TOLERANCE = .002
local samples = {{.25, .25}, {.75, .25}, {.25, .75}}

local function readableTable(value)
    return (not issecretvalue or not issecretvalue(value))
        and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function layerInfo(layers, index)
    local layer = layers[index]
    if not readableTable(layer) then return end
    local width, height = layer.layerWidth, layer.layerHeight
    local tileWidth, tileHeight = layer.tileWidth, layer.tileHeight
    local number = addon.IsReadableNumber
    if not (number(width) and number(height) and number(tileWidth) and number(tileHeight)
        and width >= WIDTH and height >= HEIGHT and tileWidth >= 1 and tileHeight >= 1
        and math.abs(width * HEIGHT - height * WIDTH) <= WIDTH) then return end
    local columns, rows = math.ceil(width / tileWidth), math.ceil(height / tileHeight)
    if columns * rows > MAX_TILES then return end
    return {index=index, width=width, height=height, tileWidth=tileWidth, tileHeight=tileHeight, columns=columns,
        count=columns * rows}
end

local function filesFor(mapID, layer)
    local tiles = C_Map.GetMapArtLayerTextures(mapID, layer.index)
    if not readableTable(tiles) then return end
    for i = 1, layer.count do
        local id = tiles[i]
        if not addon.IsReadableNumber(id) or id <= 0 or id % 1 ~= 0 then return end
    end
    return tiles
end

local function matchesLegacy(layer, files, floor)
    if not (files and layer.width == WIDTH and layer.height == HEIGHT
        and layer.tileWidth == LEGACY_TILE and layer.tileHeight == LEGACY_TILE
        and layer.count == #floor.tiles) then return false end
    for i, expected in ipairs(floor.tiles) do
        if files[i] ~= expected then return false end
    end
    return true
end

local function matchesSample(coefficients, north, west, x, y)
    local a, b, c, d, e, f = unpack(coefficients)
    return math.abs(a * north + b * west + c - x) <= REGISTRATION_TOLERANCE
        and math.abs(d * north + e * west + f - y) <= REGISTRATION_TOLERANCE
end

-- Current or localized art may have a different file ID family. Three
-- non-collinear samples prove that it still uses the audited floor transform.
local function matchesProjection(floor)
    if not (floor.toMap and CreateVector2D and C_Map.GetWorldPosFromMapPos) then return false end
    local sameAxes, swappedAxes = true, true
    local mapSpace
    for _, sample in ipairs(samples) do
        local x, y = unpack(sample)
        local space, world = C_Map.GetWorldPosFromMapPos(floor.mapID, CreateVector2D(x, y))
        if not (addon.IsReadableNumber(space) and readableTable(world)
            and addon.IsReadableNumber(world.x) and addon.IsReadableNumber(world.y))
            or (mapSpace and space ~= mapSpace) then return false end
        mapSpace = space
        sameAxes = sameAxes and matchesSample(floor.toMap, world.x, world.y, x, y)
        swappedAxes = swappedAxes and matchesSample(floor.toMap, world.y, world.x, x, y)
        if not sameAxes and not swappedAxes then return false end
    end
    return sameAxes or swappedAxes
end

local function render(frame, layer, files, drawTile)
    local scaleX, scaleY = WIDTH / layer.width, HEIGHT / layer.height
    for i = 1, layer.count do
        local x = ((i - 1) % layer.columns) * layer.tileWidth
        local y = math.floor((i - 1) / layer.columns) * layer.tileHeight
        local w = math.min(layer.tileWidth, layer.width - x)
        local h = math.min(layer.tileHeight, layer.height - y)
        if not drawTile(frame, i, files[i], x * scaleX, y * scaleY, w * scaleX, h * scaleY, 0,
            0, w / layer.tileWidth, 0, h / layer.tileHeight) then
            -- The caller can now redraw the bundled tiles or mosaic without
            -- leaving stale detail tiles outside its own grid.
            for index = 1, i do
                frame.tiles[index]:Hide()
                frame.tiles[index]:SetTexture(nil)
            end
            return false
        end
    end
    return true
end

function Art:Draw(frame, floor, drawTile)
    local mapID = floor.mapID
    if not (addon.IsReadableNumber(mapID) and mapID > 0 and mapID < 1000000 and floor.tiles and C_Map
        and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return false end
    local layers = C_Map.GetMapArtLayers(mapID)
    if not readableTable(layers) then return false end
    local base = layerInfo(layers, 1)
    local baseFiles = base and filesFor(mapID, base)
    local sameArt = base and matchesLegacy(base, baseFiles, floor)
    if not sameArt and not matchesProjection(floor) then return false end

    local candidates = {}
    for i = sameArt and 2 or 1, #layers do
        local layer = layerInfo(layers, i)
        if layer then candidates[#candidates + 1] = layer end
    end
    table.sort(candidates, function(a, b) return a.width > b.width end)
    for _, layer in ipairs(candidates) do
        local files = layer.index == 1 and baseFiles or filesFor(mapID, layer)
        if files and render(frame, layer, files, drawTile) then return true end
    end
    return false
end
