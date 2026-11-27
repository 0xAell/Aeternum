local _, addon = ...

local DungeonMap = {}
addon.DungeonMap = DungeonMap

-- FileDataIDs for reference art already in the client, ordered by tile.
-- Client file names were resolved using the wowdev community listfile.
-- Reference floors have no UiMapIDs or position transforms.
local referenceTiles = {
    BlackfathomDeeps = {
        [1] = { 447578, 447582, 447583, 447584, 447585, 447586, 447587, 447588, 447589, 447579, 447580, 447581 },
        [2] = { 447590, 447594, 447595, 447596, 447597, 447598, 447599, 447600, 447601, 447591, 447592, 447593 },
        [3] = { 447602, 447606, 447607, 447608, 447609, 447610, 447611, 447612, 447613, 447603, 447604, 447605 },
    },
    BlackrockDepths = {
        [1] = { 447638, 447642, 447643, 447644, 447645, 447646, 447647, 447648, 447649, 447639, 447640, 447641 },
        [2] = { 447650, 447654, 447655, 447656, 447657, 447658, 447659, 447660, 447661, 447651, 447652, 447653 },
    },
    BlackrockSpire = {
        [1] = { 447662, 447666, 447667, 447668, 447669, 447670, 447671, 447672, 447673, 447663, 447664, 447665 },
        [2] = { 447674, 447678, 447679, 447680, 447681, 447682, 447683, 447684, 447685, 447675, 447676, 447677 },
        [3] = { 447686, 447690, 447691, 447692, 447693, 447694, 447695, 447696, 447697, 447687, 447688, 447689 },
        [4] = { 447698, 447702, 447703, 447704, 447705, 447706, 447707, 447708, 447709, 447699, 447700, 447701 },
        [5] = { 447710, 447714, 447715, 447716, 447717, 447718, 447719, 447720, 447721, 447711, 447712, 447713 },
        [6] = { 447722, 447726, 447727, 447728, 447729, 447730, 447731, 447732, 447733, 447723, 447724, 447725 },
        [7] = { 447734, 447738, 447739, 447740, 447741, 447742, 447743, 447744, 447745, 447735, 447736, 447737 },
    },
    DireMaul = {
        [1] = { 449508, 449512, 449513, 449514, 449515, 449516, 449517, 449518, 449519, 449509, 449510, 449511 },
        [2] = { 449520, 449524, 449525, 449526, 449527, 449528, 449529, 449530, 449531, 449521, 449522, 449523 },
        [3] = { 449532, 449536, 449537, 449538, 449539, 449540, 449541, 449542, 449543, 449533, 449534, 449535 },
        [4] = { 449544, 449548, 449549, 449550, 449551, 449552, 449553, 449554, 449555, 449545, 449546, 449547 },
        [5] = { 449556, 449560, 449561, 449562, 449563, 449564, 449565, 449566, 449567, 449557, 449558, 449559 },
        [6] = { 449568, 449572, 449573, 449574, 449575, 449576, 449577, 449578, 449579, 449569, 449570, 449571 },
    },
    Gnomeregan = {
        [1] = { 449580, 449584, 449585, 449586, 449587, 449588, 449589, 449590, 449627, 449581, 449582, 449583 },
        [2] = { 449628, 449632, 449633, 449634, 449635, 449636, 449637, 449638, 449639, 449629, 449630, 449631 },
        [3] = { 449640, 449644, 449645, 449646, 449647, 449648, 449649, 449650, 449651, 449641, 449642, 449643 },
        [4] = { 449652, 449656, 449657, 449658, 449659, 449660, 449661, 449662, 449663, 449653, 449654, 449655 },
    },
    Maraudon = {
        [1] = { 449676, 449680, 449681, 449682, 449683, 449684, 449685, 449686, 449687, 449677, 449678, 449679 },
        [2] = { 449688, 449692, 449693, 449694, 449695, 449696, 449697, 449698, 449699, 449689, 449690, 449691 },
    },
    Ragefire = {
        [1] = { 449736, 449740, 449741, 449742, 449743, 449744, 449745, 449746, 449747, 449737, 449738, 449739 },
    },
    RazorfenDowns = {
        [1] = { 448094, 448098, 448099, 448100, 448101, 448102, 448103, 448104, 448105, 448095, 448096, 448097 },
    },
    RazorfenKraul = {
        [1] = { 448106, 448110, 448111, 448112, 448113, 448114, 448115, 448116, 448117, 448107, 448108, 448109 },
    },
    ScarletMonasteryOLD = {
        [1] = { 5333983, 5333984, 5333985, 5333986, 5333987, 5333988, 5333989, 5333990, 5333991, 5333992, 5333993, 5333994 },
        [2] = { 5333996, 5333997, 5333998, 5333999, 5334000, 5334001, 5334002, 5334003, 5334004, 5334005, 5334006, 5334007 },
        [3] = { 5334009, 5334010, 5334011, 5334012, 5334013, 5334014, 5334015, 5334016, 5334017, 5334018, 5334019, 5334020 },
        [4] = { 5334037, 5334038, 5334040, 5334041, 5334043, 5334044, 5334046, 5334047, 5334049, 5334050, 5334052, 5334053 },
    },
    ScholomanceOLD = {
        [1] = { 5332424, 5332428, 5332429, 5332430, 5332431, 5332432, 5332433, 5332434, 5332435, 5332425, 5332426, 5332427 },
        [2] = { 5332436, 5332440, 5332441, 5332442, 5332443, 5332444, 5332445, 5332446, 5332447, 5332437, 5332438, 5332439 },
        [3] = { 5332448, 5332452, 5332453, 5332454, 5332455, 5332456, 5332457, 5332458, 5332459, 5332449, 5332450, 5332451 },
        [4] = { 5332460, 5332464, 5332465, 5332466, 5332467, 5332468, 5332469, 5332470, 5332471, 5332461, 5332462, 5332463 },
    },
    ShadowfangKeep = {
        [1] = { 448226, 448230, 448231, 448232, 448233, 448234, 448235, 448236, 448237, 448227, 448228, 448229 },
        [2] = { 448238, 448242, 448243, 448244, 448245, 448246, 448247, 448248, 448249, 448239, 448240, 448241 },
        [3] = { 448250, 448254, 448255, 448256, 448257, 448258, 448259, 448260, 448261, 448251, 448252, 448253 },
        [4] = { 448262, 448266, 448267, 448268, 448269, 448270, 448271, 448272, 448273, 448263, 448264, 448265 },
        [5] = { 448274, 448278, 448279, 448280, 448281, 448282, 448283, 448284, 448285, 448275, 448276, 448277 },
        [6] = { 448286, 448290, 448291, 448292, 448293, 448294, 448295, 448296, 448297, 448287, 448288, 448289 },
        [7] = { 448298, 448302, 448303, 448304, 448305, 448306, 448307, 448308, 448309, 448299, 448300, 448301 },
    },
    Stratholme = {
        [1] = { 448322, 448326, 448327, 448328, 448329, 448330, 448331, 448332, 448333, 448323, 448324, 448325 },
        [2] = { 448334, 448338, 448339, 448340, 448341, 448342, 448343, 448344, 448345, 448335, 448336, 448337 },
    },
    TheDeadmines = {
        [1] = { 449591, 449595, 449596, 449597, 449598, 449599, 449600, 449601, 449602, 449592, 449593, 449594 },
        [2] = { 449603, 449607, 449608, 449609, 449610, 449611, 449612, 449613, 449614, 449604, 449605, 449606 },
    },
    TheStockade = {
        [1] = { 455959, 455963, 455964, 455965, 455966, 455967, 455968, 455969, 455970, 455960, 455961, 455962 },
    },
    TheTempleOfAtalHakkar = {
        [1] = { 452514, 452518, 452519, 452520, 452521, 452522, 452523, 452524, 452525, 452515, 452516, 452517 },
    },
    Uldaman = {
        [1] = { 448430, 448434, 448435, 448436, 448437, 448438, 448439, 448440, 448441, 448431, 448432, 448433 },
        [2] = { 448442, 448446, 448447, 448448, 448449, 448450, 448451, 448452, 448453, 448443, 448444, 448445 },
    },
    WailingCaverns = {
        [1] = { 448454, 448458, 448459, 448460, 448461, 448462, 448463, 448464, 448465, 448455, 448456, 448457 },
    },
    ZulFarrak = {
        [1] = { 449820, 449824, 449825, 449826, 449827, 449828, 449829, 449830, 449831, 449821, 449822, 449823 },
    },
}

local referenceMaps = {
    ["blackfathom-deeps"] = { referenceTiles.BlackfathomDeeps, 1, 3 },
    ["blackrock-depths"] = { referenceTiles.BlackrockDepths, 1, 2 },
    ["deadmines"] = { referenceTiles.TheDeadmines, 1, 2 },
    ["dm-east"] = { referenceTiles.DireMaul, 5, 6 },
    ["dm-north"] = { referenceTiles.DireMaul, 1, 1 },
    ["dm-west"] = { referenceTiles.DireMaul, 2, 4 },
    ["gnomeregan"] = { referenceTiles.Gnomeregan, 1, 4 },
    ["lbrs"] = { referenceTiles.BlackrockSpire, 1, 7 },
    ["maraudon"] = { referenceTiles.Maraudon, 1, 2 },
    ["ragefire-chasm"] = { referenceTiles.Ragefire, 1, 1 },
    ["razorfen-downs"] = { referenceTiles.RazorfenDowns, 1, 1 },
    ["razorfen-kraul"] = { referenceTiles.RazorfenKraul, 1, 1 },
    ["scholomance"] = { referenceTiles.ScholomanceOLD, 1, 4 },
    ["shadowfang-keep"] = { referenceTiles.ShadowfangKeep, 1, 7 },
    ["sm-armory"] = { referenceTiles.ScarletMonasteryOLD, 3, 3 },
    ["sm-cathedral"] = { referenceTiles.ScarletMonasteryOLD, 4, 4 },
    ["sm-graveyard"] = { referenceTiles.ScarletMonasteryOLD, 1, 1 },
    ["sm-library"] = { referenceTiles.ScarletMonasteryOLD, 2, 2 },
    ["stockade"] = { referenceTiles.TheStockade, 1, 1 },
    ["stratholme"] = { referenceTiles.Stratholme, 1, 2 },
    ["sunken-temple"] = { referenceTiles.TheTempleOfAtalHakkar, 1, 1 },
    ["ubrs"] = { referenceTiles.BlackrockSpire, 1, 7 },
    ["uldaman"] = { referenceTiles.Uldaman, 1, 2 },
    ["wailing-caverns"] = { referenceTiles.WailingCaverns, 1, 1 },
    ["zulfarrak"] = { referenceTiles.ZulFarrak, 1, 1 },
}

function DungeonMap.HasFloors(dungeon)
    return referenceMaps[dungeon.id] ~= nil
end

local function getFloors(dungeon)
    local reference = dungeon and referenceMaps[dungeon.id]
    local floors = {}
    if reference then
        local tiles, first, last = unpack(reference)
        for number = first, last do
            floors[#floors + 1] = tiles[number]
        end
    end
    return floors
end

local function hideTiles(tiles, first)
    for index = first, #tiles do
        tiles[index]:Hide()
        tiles[index]:SetTexture(nil)
    end
end

local function drawTiles(view, width, height, tileWidth, tileHeight, textures)
    local availableWidth, availableHeight = view:GetSize()
    if availableWidth <= 0 or availableHeight <= 0 then return false end

    local scale = math.min(availableWidth / width, availableHeight / height)
    local offsetX = (availableWidth - width * scale) / 2
    local offsetY = (availableHeight - height * scale) / 2
    local columns = math.ceil(width / tileWidth)
    local count = columns * math.ceil(height / tileHeight)

    for index = 1, count do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local x, y = column * tileWidth, row * tileHeight
        local visibleWidth = math.min(tileWidth, width - x)
        local visibleHeight = math.min(tileHeight, height - y)

        local tile = view.tiles[index]
        if not tile then
            tile = view:CreateTexture(nil, "ARTWORK")
            view.tiles[index] = tile
        end
        local fileID = textures[index]
        if type(fileID) ~= "number" or fileID <= 0 or tile:SetTexture(fileID) == false then
            return
        end

        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT", view, "TOPLEFT", offsetX + x * scale, -offsetY - y * scale)
        tile:SetSize(visibleWidth * scale, visibleHeight * scale)
        tile:SetTexCoord(0, visibleWidth / tileWidth, 0, visibleHeight / tileHeight)
        tile:Show()
    end
    hideTiles(view.tiles, count + 1)
    return count
end

-- Legacy floor art is a 4x3 grid of 256-pixel tiles covering 1002x668 pixels.
local function drawArt(view, tileIDs)
    return drawTiles(view, 1002, 668, 256, 256, tileIDs)
end

local function tilesLoaded(view, count)
    for index = 1, count do
        local tile = view.tiles[index]
        if not tile:IsObjectLoaded() then
            return false
        end
    end
    return true
end

function DungeonMap.Create(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel.floors = {}
    panel.floorIndex = 1

    local function pageButton(direction)
        local control = CreateFrame("Button", nil, panel)
        local art = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
        control:SetSize(26, 26)
        control:SetNormalTexture(art .. "Up")
        control:SetPushedTexture(art .. "Down")
        control:SetDisabledTexture(art .. "Disabled")
        return control
    end
    local previous = pageButton("Prev")
    previous:SetPoint("TOPLEFT")

    local nextFloor = pageButton("Next")
    nextFloor:SetPoint("TOPRIGHT")

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 30, -3)
    title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, -3)
    title:SetJustifyH("CENTER")

    local view = CreateFrame("Frame", nil, panel)
    view:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -23)
    view:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 17)
    view.tiles = {}

    local shade = view:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0.035, 0.045, 0.055, 0.9)

    local empty = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("LEFT", 12, 0)
    empty:SetPoint("RIGHT", -12, 0)
    empty:SetJustifyH("CENTER")

    local caption = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("BOTTOMLEFT", 1, 1)

    local function showUnavailable()
        hideTiles(view.tiles, 1)
        caption:SetText("")
        empty:SetText(panel.dungeon and "No floor map for this dungeon in the client." or "Select a dungeon to view its map.")
        empty:Show()
    end

    local function cancelLoad()
        if view.loadTimer then
            view.loadTimer:Cancel()
            view.loadTimer = nil
        end
    end

    local function render()
        cancelLoad()
        if not panel:IsVisible() then return end
        local count = #panel.floors
        local floor = panel.floors[panel.floorIndex]
        previous:SetShown(count > 1)
        nextFloor:SetShown(count > 1)
        previous:SetEnabled(panel.floorIndex > 1)
        nextFloor:SetEnabled(panel.floorIndex < count)
        title:SetText(count > 1 and ("Floor %d of %d"):format(panel.floorIndex, count) or "")

        local drawn = floor and drawArt(view, floor)
        if drawn then
            empty:Hide()
            caption:SetText("Legacy client reference")
            if not tilesLoaded(view, drawn) then
                -- Loading is asynchronous even when SetTexture reports success.
                view.loadTimer = C_Timer.NewTimer(5, function()
                    view.loadTimer = nil
                    if view:IsVisible() and not tilesLoaded(view, drawn) then
                        showUnavailable()
                    end
                end)
            end
        else
            showUnavailable()
        end
    end

    function panel:SetDungeon(dungeon)
        if self.dungeon == dungeon then return end
        self.dungeon = dungeon
        self.floors = getFloors(dungeon)
        self.floorIndex = 1
        view:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, #self.floors > 1 and -26 or 0)
        render()
    end

    previous:SetScript("OnClick", function()
        panel.floorIndex = math.max(1, panel.floorIndex - 1)
        render()
    end)
    nextFloor:SetScript("OnClick", function()
        panel.floorIndex = math.min(#panel.floors, panel.floorIndex + 1)
        render()
    end)
    view:SetScript("OnSizeChanged", render)
    panel:SetScript("OnShow", render)
    panel:SetScript("OnHide", function()
        cancelLoad()
        hideTiles(view.tiles, 1)
    end)
    render()
    return panel
end
