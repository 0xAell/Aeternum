-- Run from the repository root with Lua 5.1 or LuaJIT.
local function checkEntrances(addon)
    local dungeons = {}
    for _, dungeon in ipairs(addon.Data.dungeons) do dungeons[dungeon.id] = dungeon end

    local function checkDoors(id, mapID, expected)
        local doors = dungeons[id].entrances
        assert(#doors == #expected, id .. " entrance count")
        for index, xy in ipairs(expected) do
            local door = doors[index]
            assert(door.mapID == (xy[3] or mapID) and door.x == xy[1] and door.y == xy[2],
                ("%s entrance %d"):format(id, index))
        end
    end
    checkDoors("uldaman", 1418, {{.446, .121}, {.652, .435}})
    for _, id in ipairs({"blackrock-depths", "lbrs", "ubrs"}) do
        checkDoors(id, 1427, {{.348, .853}, {.294, .383, 1428}})
    end
    checkDoors("dm-east", 1444, {{.6486, .2943}, {.6720, .3485}, {.7651, .3586}})
    checkDoors("dm-north", 1444, {{.6292, .2491}})
    checkDoors("dm-west", 1444, {{.6031, .3175}, {.6032, .2968}})
    checkDoors("alcaz-prison", 1445, {{.755, .137}})
    assert(#dungeons.deadmines.entrances[1].waypoints == 1)
end

if ... == "dungeon_entrances" then return checkEntrances end
local addon = {}
assert(loadfile("Data.lua"))("Aeternum", addon)
checkEntrances(addon)
print("Dungeon entrance checks passed.")
