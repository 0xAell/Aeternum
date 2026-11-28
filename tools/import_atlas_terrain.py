"""Index the outdoor minimap textures in the pinned Forever build's WDT files."""

import argparse
import hashlib
from pathlib import Path
import struct

from import_overview_bounds import ASSIGNMENT_HASH, read_export

BUILD = "1.60.1.71139"
GRID_SIZE = 64
TILE_SIZE = 1600 / 3
TILES = GRID_SIZE * GRID_SIZE
KALIMDOR = (1414, 1, 782779, "1120509b2ac42a94310bf05f915b5e67ed233be854089a3545829e064b614b44")
EASTERN_KINGDOMS = (1415, 0, 775971, "160452dec4c2b0ae4cbe7468ce52fee91ac7ec521d2cb0f28e955def0d087137")


def terrain_tiles(path, file_id, expected_hash):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError(f"Use Forever {BUILD} WDT file {file_id} for {path}")

    chunks = {}
    offset = 0
    while offset < len(data):
        tag, length = struct.unpack_from("<4sI", data, offset)
        start = offset + 8
        offset = start + length
        chunks[tag[::-1]] = data[start:offset]

    terrain = chunks[b"MAIN"]
    files = chunks[b"MAID"]
    if len(terrain) != TILES * 8 or len(files) != TILES * 32:
        raise ValueError(f"{path} does not contain a 64 × 64 WDT tile grid")

    # MAIN's first field indicates terrain occupancy. The last file ID in
    # each MAID record is the game's minimap texture for the same tile.
    tiles = {}
    for index in range(TILES):
        flags, _ = struct.unpack_from("<II", terrain, index * 8)
        texture, = struct.unpack_from("<I", files, index * 32 + 28)
        if flags & 1 and texture:
            tiles[index] = texture
    return tiles


def continent_grid(assignment):
    # Tile (0, 0) begins at the northwestern grid corner. World X increases
    # northward and World Y increases westward. Tile columns and rows increase
    # eastward and southward, as do the continent artwork's normalized axes.
    south, east, north, west = (float(assignment[f"Region_{i}"]) for i in (0, 1, 3, 4))
    left, top, right, bottom = (
        float(assignment[field]) for field in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1")
    )
    step_x = TILE_SIZE * (right - left) / (west - east)
    step_y = TILE_SIZE * (bottom - top) / (north - south)
    corner = GRID_SIZE / 2 * TILE_SIZE
    return left + (west - corner) * step_x / TILE_SIZE, top + (north - corner) * step_y / TILE_SIZE, step_x, step_y


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("assignment", type=Path, help="pinned UiMapAssignment CSV")
    parser.add_argument("output", type=Path, help="generated AtlasTerrainData.lua")
    parser.add_argument("--kalimdor", required=True, type=Path, help=f"Kalimdor WDT (FileDataID {KALIMDOR[2]})")
    parser.add_argument("--eastern-kingdoms", required=True, type=Path,
                        help=f"Azeroth WDT (FileDataID {EASTERN_KINGDOMS[2]})")
    args = parser.parse_args()

    assignments = {
        (int(row["UiMapID"]), int(row["MapID"])): row
        for row in read_export(args.assignment, ASSIGNMENT_HASH)
        if row["OrderIndex"] == "0"
    }
    lines = [
        f"-- Generated from Forever {BUILD} UiMapAssignment and continent WDT files. See DATA_SOURCES.md.",
        "local _, addon = ...",
        "",
        "-- Grid positions are relative to the continent's art. The texture key is row * 64 + column.",
        "addon.atlasTerrain = {",
    ]
    for path, continent in ((args.kalimdor, KALIMDOR), (args.eastern_kingdoms, EASTERN_KINGDOMS)):
        ui_map_id, map_id, file_id, expected_hash = continent
        left, top, step_x, step_y = continent_grid(assignments[ui_map_id, map_id])
        tiles = terrain_tiles(path, file_id, expected_hash)
        lines.extend((
            f"    [{ui_map_id}] = {{",
            f"        left={left:.12f}, top={top:.12f}, stepX={step_x:.12f}, stepY={step_y:.12f},",
            "        tiles = {",
        ))
        pairs = [f"[{index}]={texture}," for index, texture in tiles.items()]
        for i in range(0, len(pairs), 6):
            lines.append("            " + " ".join(pairs[i:i + 6]))
        lines.extend(("        },", "    },"))
        print(f"{ui_map_id}: {len(tiles)} terrain textures")
    lines.extend(("}", ""))
    args.output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
