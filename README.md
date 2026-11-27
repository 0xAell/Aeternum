# Aeternum

A world map and dungeon companion for World of Warcraft: Forever 1.60.1.
It runs on its bundled database and the game's own interface and artwork, with
no other addons required.

Open **Aeternum** in the world map's tracking menu when you need it. Look up a
trainer in town, find the boss who drops an item, or follow a dungeon approach
on the minimap. A fresh installation opens the ordinary map with the guide closed
and its pins hidden. Upgrades keep your explicit pin and filter choices.

## Install

Download `Aeternum-<version>.zip` from the latest CI run or release and unzip it
into `World of Warcraft/_forever_/Interface/AddOns/`. The result must be
`Interface/AddOns/Aeternum/Aeternum.toc`. If you download a GitHub source archive,
rename its extracted folder to `Aeternum`.

## Use it in game

Press **M**, open the map's tracking dropdown, and choose **Aeternum**. The guide
docks beside a windowed map when space permits. On a maximised map, it opens in
a corner. Drag its title bar to move it out of your way.

- **Browse this map** lists dungeon entrances, trainers and quests. Hover a row
  to preview one location. Select a trainer or quest to keep its pin visible,
  or right-click a row with coordinates to start guidance.
- **Show pins on map** keeps the chosen categories visible after closing the
  guide. A left-click opens a dungeon, starts directions to a trainer or quest,
  or offers a choice when locations coincide. Right-click zooms the map as usual.
- **Dungeon guide** searches dungeon names, bosses and drops. Try
  **Cruel Barb** to open Edwin VanCleef's loot in the Deadmines. Use **Map** to
  browse floors, **Loot** to pick a boss, or **Quests** to find where a quest
  starts. Loot supports item tooltips, shift-click chat links and ctrl-click previews.
- **Guide me** follows the selected dungeon entrance. The minimap shows a
  directional arrow for a distant target and a waypoint at the target when it
  comes into view. Recorded approach points mark the way into the Deadmines and
  Ragefire Chasm. Use **Stop** to end guidance.

Quest pins follow your character's level, race, class and quest progress.
Available quests use the game's exclamation mark. Turn-ins use a question mark
that turns gold when ready. **Filter** includes low-level quests and an **All
quest locations** option for browsing the database.

**Back** or **Escape** returns from dungeon details to your search. Escape from
the list, or from a dungeon opened directly on the map, closes the guide.

| Command | Effect |
|---|---|
| `/aeternum` | Browse the current map |
| `/aeternum dungeons` | Search the dungeon guide |
| `/aeternum stop` | Stop minimap guidance |
| `/aeternum pins` | Toggle the map pin layer |
| `/aeternum reset` | Restore the default filters and options |

## What the data covers

- 34 dungeon and wing entries, 287 bosses, and 1,335 loot items.
- 30 entrance locations. Alcaz Prison, Blackmaw Hold, Krol'dok Stronghold, and
  Shaper's Terrace have no recorded entrance yet.
- 25 classic dungeon and wing entries have client floor-map references, labeled
  as legacy references. Some Forever dungeons lack equivalent floor art.
- 554 trainer pins and 11,100 quest start and turn-in pins across 53 world maps,
  with requirements for 5,323 quests.

Quest states use level, race, class, prerequisite, and exclusive-quest rules.
Profession requirements are shown in tooltips but not checked, and reputation
requirements are not modelled. **All quest locations** includes seasonal event
quests. Routes without recorded approach points use a direct bearing, which can
lead across walls or terrain.

## Footprint

The bundled data loads as compact strings (about 1.6 MB of Lua memory at
login). Opening the ordinary map with default settings creates no guide widgets
or pins. Location records decode when you browse a zone or enable its pins.
Lists reuse visible rows, and the loot page requests item details for the selected
boss. Quest-log updates restyle visible pins in place when the list of locations
stays the same.

## Development

You need LuaJIT (or Lua 5.1) and [luacheck](https://github.com/lunarmodules/luacheck).

```sh
luacheck .                 # lint
luajit tests/run.lua       # headless tests against a mock client
tools/check_data.sh        # confirm Data.lua matches a fresh import
tools/package.sh           # build dist/Aeternum-<version>.zip
```

The tests load the addon in TOC order inside `tests/wow.lua` and exercise the
guide, pins, quest states and minimap. The mock follows the client's map canvas
click handling, show order and Escape priorities. CI runs all four steps on pull
requests and pushes to `main`. [Forever interface source](https://github.com/Gethe/wow-ui-source/tree/forever)

See [data sources and regeneration](DATA_SOURCES.md) for the pinned database,
attribution, and import command. Licensed under [GPL-3.0](LICENSE).
