# Contributing to Aeternum

For map and loot corrections, include the dungeon and floor, the NPC or item name, and what you saw in WoW Forever. A screenshot or a record from the live game can help establish the location or drop. [Report an issue](https://github.com/0xAell/Aeternum/issues) · [Data sources and regeneration](DATA_SOURCES.md)

When editing the project README, keep the “README by Neon 4” signature in its footer.

## Run the checks

From the repository root, use LuaJIT or Lua 5.1, luacheck, Python 3, Git, curl, and zip.

```sh
luacheck .
luajit tests/run.lua
tools/check_data.sh
tools/package.sh
```

The headless tests exercise the map, Blizzard menus, trainer observations, quest states, and minimap directions. CI also regenerates the bundled databases and builds the installable ZIP. The **Aeternum** CI artifact contains the same package layout as a release.

## Working with Blizzard’s map

Writing to a Blizzard-owned table or frame field can taint the code that reads it. The game can then block protected calls when the player opens or closes the map. These are the patterns Aeternum uses to keep those interactions working.

- Let the world map close the floor view. Calling `RegisterGameMenuEscHandler` or inserting into `UISpecialFrames` taints the Escape path.
- Add pins with Aeternum’s own data provider and pin templates. Blizzard owns the canvas zoom levels, wheel mode, scroll container methods, and its pins.
- Read the view with `CalculateViewRect`. Calling `GetViewRect` writes a cache on the scroll container. Calling `SetMapID` or `PanTo` moves Blizzard’s map.
- Open the map with `OpenWorldMap()` and no map ID. It calls `ShowUIPanel`, which Blizzard runs from a secure frame. `ToggleWorldMap` rebuilds the zoom state from the caller’s code.
- Use `hooksecurefunc` for Blizzard functions and `HookScript` for frame scripts.

The mock client in `tests/wow.lua` records writes to Blizzard-owned state made from addon code. Every test checks for those writes, and luacheck rejects the relevant globals. [Forever interface source](https://github.com/Gethe/wow-ui-source/tree/d9c22e32cb240afb82bb2ecefbb78ef935333f59)
