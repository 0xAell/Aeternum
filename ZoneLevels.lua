local _, addon = ...

-- Outdoor questing recommendations for Forever. Sources and exceptions are in DATA_SOURCES.md.
local zones = {
    [1411]={1,10},  -- Durotar
    [1412]={1,10},  -- Mulgore
    [1413]={10,25}, -- The Barrens
    [1416]={27,39}, -- Alterac Mountains
    [1417]={30,40}, -- Arathi Highlands
    [1418]={36,45}, -- Badlands
    [1419]={46,55}, -- Blasted Lands
    [1420]={1,12},  -- Tirisfal Glades
    [1421]={10,20}, -- Silverpine Forest
    [1422]={46,57}, -- Western Plaguelands
    [1423]={54,59}, -- Eastern Plaguelands
    [1424]={20,31}, -- Hillsbrad Foothills
    [1425]={41,49}, -- The Hinterlands
    [1426]={1,12},  -- Dun Morogh
    [1427]={43,48}, -- Searing Gorge
    [1428]={50,59}, -- Burning Steppes
    [1429]={1,10},  -- Elwynn Forest
    [1430]={50,60}, -- Deadwind Pass
    [1431]={19,30}, -- Duskwood
    [1432]={10,18}, -- Loch Modan
    [1433]={15,25}, -- Redridge Mountains
    [1434]={30,44}, -- Stranglethorn Vale
    [1435]={36,43}, -- Swamp of Sorrows
    [1436]={9,18},  -- Westfall
    [1437]={20,30}, -- Wetlands
    [1438]={1,11},  -- Teldrassil
    [1439]={11,19}, -- Darkshore
    [1440]={19,30}, -- Ashenvale
    [1441]={24,35}, -- Thousand Needles
    [1442]={15,25}, -- Stonetalon Mountains
    [1443]={30,39}, -- Desolace
    [1444]={40,50}, -- Feralas
    [1445]={36,43}, -- Dustwallow Marsh
    [1446]={40,50}, -- Tanaris
    [1447]={42,55}, -- Azshara
    [1448]={47,54}, -- Felwood
    [1449]={48,55}, -- Un'Goro Crater
    [1450]={55,60}, -- Moonglade, general zone quests
    [1451]={55,59}, -- Silithus
    [1452]={55,60}, -- Winterspring
    [2482]={55,60}, -- Mount Hyjal
    [2521]={1,12},  -- Zephras Isle
    [2548]={36,44}, -- Riverglades
    [2652]={38,45}, -- Shen'dralas
}

local function mapBounds(child, parent)
    local left, right, top, bottom = C_Map.GetMapRectOnMap(child, parent)
    if addon.IsReadableNumber(left) and addon.IsReadableNumber(right) and right > left
        and addon.IsReadableNumber(top) and addon.IsReadableNumber(bottom) and bottom > top then
        return left, right, top, bottom
    end
    local bounds = addon.overviewBounds[parent] and addon.overviewBounds[parent][child]
    if bounds then return unpack(bounds) end
end

local function zoneUnderCursor(mapID, x, y, areaName)
    local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if mapID == 947 and info and (info.mapID == 1414 or info.mapID == 1415) then
        -- On Azeroth the native highlight is a continent. Ask its map for the
        -- precise zone so neighboring rectangles and open water stay distinct.
        local continent = info.mapID
        local left, right, top, bottom = mapBounds(continent, mapID)
        if not left then return end
        x, y = (x - left) / (right - left), (y - top) / (bottom - top)
        if x < 0 or x > 1 or y < 0 or y > 1 then return end
        info = C_Map.GetMapInfoAtPosition(continent, x, y)
    elseif zones[mapID] and (not info or info.mapID == mapID) then
        info = info or C_Map.GetMapInfo(mapID)
        -- Unexplored areas have no subzone label. Ask the continent which land is
        -- under the cursor, including cities and water around the zone's borders.
        -- Zephras Isle has its own terrain and no continent map.
        if not areaName and mapID ~= 2521 then
            local mapInfo = info and info.parentMapID and info or C_Map.GetMapInfo(mapID)
            local parent = mapInfo and mapInfo.parentMapID
            if not parent then return end
            local left, right, top, bottom = mapBounds(mapID, parent)
            if not left then return end
            info = C_Map.GetMapInfoAtPosition(parent, left + x * (right - left), top + y * (bottom - top))
        end
    end
    if info and zones[info.mapID] then return info end
end

local function rangeFor(mapID)
    local low, high = C_Map.GetMapLevels(mapID)
    if not (addon.IsReadableNumber(low) and addon.IsReadableNumber(high) and low > 0 and high >= low) then
        local fallback = zones[mapID]
        if not fallback then return end
        low, high = unpack(fallback)
    end
    local range = low == high and tostring(low) or ("%d–%d"):format(low, high)
    return range, low, high
end

function addon.MapLevelRange(mapID)
    local range = rangeFor(mapID)
    if range then return ("%s %s"):format(LEVEL, range) end
end

local function applyRange(text, info, includeName, playerLevel)
    local range, low, high = rangeFor(info.mapID)
    if includeName then
        text:SetText(("%s (%s)"):format(info.name, range))
    else
        text:SetText(("%s %s"):format(LEVEL, range))
    end
    local color = QuestDifficultyColors.difficult
    if addon.IsReadableNumber(playerLevel) then
        if playerLevel < low then color = GetQuestDifficultyColor(low)
        elseif playerLevel > high then color = GetQuestDifficultyColor(high - 2) end
    end
    text:SetTextColor(color.r, color.g, color.b)
end

local attached = setmetatable({}, {__mode="k"})
local function attachLabel(provider)
    local label = provider.Label
    if not (label and label.labelInfoByType and label.GetHighestPriorityLabelInfo and label.Name)
        or attached[label] then return end
    attached[label] = true
    local map = provider:GetMap()
    local text = label:CreateFontString(nil, "OVERLAY", "SubZoneTextFont")
    text:SetPoint("TOP", label.Name, "BOTTOM", 0, -10)
    text:Hide()
    local lastMap, lastX, lastY, lastName, lastLevel
    local renderedZone, renderedWithName, renderedLevel
    -- Blizzard continues to own its label, priority rules, and map input.
    label:HookScript("OnUpdate", function()
        local active = label:GetHighestPriorityLabelInfo()
        local area = label.labelInfoByType[MAP_AREA_LABEL_TYPE.AREA_NAME]
        local mapID = map:GetMapID()
        if not addon.IsReadableNumber(mapID) or not (zones[mapID] or mapID == 947 or mapID == 1414 or mapID == 1415)
            or not map:IsCanvasMouseFocus() or addon.DungeonMap.dungeon or (active and active ~= area)
            or (active and active.description) then
            text:Hide()
            lastMap = nil
            return
        end
        local x, y
        if InputUtil.IsGamepadUIEnabled()
            and (map:HasGamepadCursorInput() or not map:IsCanvasMouseFocusOrPinFocus()) then
            x, y = map:GetNormalizedGamepadCursorPosition()
        else
            x, y = map:GetNormalizedCursorPosition()
        end
        local name, level = area and area.name, UnitLevel("player")
        if not addon.IsReadableNumber(x) or not addon.IsReadableNumber(y) or x < 0 or y < 0 or x > 1 or y > 1
            or (issecretvalue and (issecretvalue(name) or issecretvalue(level))) then
            text:Hide()
            lastMap = nil
            return
        end
        if mapID == lastMap and x == lastX and y == lastY and name == lastName and level == lastLevel then return end
        lastMap, lastX, lastY, lastName, lastLevel = mapID, x, y, name, level
        local info = zoneUnderCursor(mapID, x, y, name)
        if info and info.name and not (name and name:find(info.name, 1, true) and name:find("%(%d")) then
            local includeName = name ~= info.name
            if info.mapID ~= renderedZone or includeName ~= renderedWithName or level ~= renderedLevel then
                applyRange(text, info, includeName, level)
                renderedZone, renderedWithName, renderedLevel = info.mapID, includeName, level
            end
            text:Show()
        else
            text:Hide()
        end
    end)
end

function addon.AttachZoneLevels(map)
    for provider in pairs(map.dataProviders) do attachLabel(provider) end
    hooksecurefunc(map, "AddDataProvider", function(_, provider) attachLabel(provider) end)
end
