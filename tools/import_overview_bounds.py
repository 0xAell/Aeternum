"""Generate Aeternum's overview bounds from the Forever 1.60.1.71139 map exports."""

import argparse
from collections import defaultdict
import csv
import hashlib
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MAP_HASH = "1f4aac70eaac015b1d2d0ea0faf6e3d7fb2cf7afdf45e5bb6772d9b80a72346b"
ASSIGNMENT_HASH = "79267e8be8034e47daab14350411b3acc0b1f64e86efc9d821a217497254ca0a"
# Forever lists capitals alongside the outdoor zone that depicts them, under the same continent.
CITY_SURROUNDINGS = {1453: 1429, 1454: 1411, 1455: 1426}  # Stormwind, Orgrimmar, Ironforge
READ_DOORS = """
local addon = {}
assert(loadfile(arg[1]))("Aeternum", addon)
for _, dungeon in ipairs(addon.Data.dungeons) do
    for _, door in ipairs(dungeon.entrances) do
        print(door.mapID)
    end
end
"""


def read_export(path, expected_hash):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
        raise ValueError(f"Use the pinned Forever 1.60.1.71139 export for {path.name}")
    with path.open(encoding="utf-8-sig", newline="") as source:
        return list(csv.DictReader(source))


def map_rect(zone, overview):
    # Map X runs from west to east and map Y runs from north to south.
    south, east, north, west = (float(overview[f"Region_{i}"]) for i in (0, 1, 3, 4))
    left, top, right, bottom = (float(overview[f]) for f in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1"))
    x1, x2 = (left + (right - left) * (west - float(zone[f"Region_{i}"])) / (west - east) for i in (4, 1))
    y1, y2 = (top + (bottom - top) * (north - float(zone[f"Region_{i}"])) / (north - south) for i in (3, 0))
    return x1, x2, y1, y2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ui_map", type=Path)
    parser.add_argument("assignment", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    maps = {int(row["ID"]): row for row in read_export(args.ui_map, MAP_HASH)}
    assignments = defaultdict(list)
    for row in read_export(args.assignment, ASSIGNMENT_HASH):
        assignments[int(row["UiMapID"])].append(row)
    door_ids = subprocess.check_output(
        [os.environ.get("LUA", "luajit"), "-", str(ROOT / "Data.lua")], input=READ_DOORS, text=True
    )
    targets = defaultdict(set)
    for map_id, info in maps.items():
        parent = int(info["ParentUiMapID"])
        if map_id in (1414, 1415) or (info["Type"] == "3" and parent in (1414, 1415)):
            targets[map_id].add(parent)
    for zone_id in set(map(int, door_ids.splitlines())):
        continent = int(maps[zone_id]["ParentUiMapID"])
        targets[zone_id].update((continent, int(maps[continent]["ParentUiMapID"])))
        if zone_id in CITY_SURROUNDINGS:
            targets[zone_id].add(CITY_SURROUNDINGS[zone_id])

    rectangles = defaultdict(dict)
    for map_id, parents in targets.items():
        zone, = assignments[map_id]
        for parent in parents:
            overview, = (row for row in assignments[parent] if row["MapID"] == zone["MapID"])
            rectangles[parent][map_id] = map_rect(zone, overview)

    lines = [
        "-- Generated from Forever 1.60.1.71139 UiMap and UiMapAssignment. See DATA_SOURCES.md.",
        "local _, addon = ...",
        "",
        "-- Display map ID, then child map ID. Rectangles are left, right, top, bottom.",
        "addon.overviewBounds = {",
    ]
    for overview_id, zones in sorted(rectangles.items()):
        lines.append(f"    [{overview_id}] = {{")
        for zone_id, rect in sorted(zones.items()):
            bounds = ", ".join(f"{value:.6f}" for value in rect)
            lines.append(f"        [{zone_id}] = {{{bounds}}},")
        lines.append("    },")
    lines.append("}")
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
