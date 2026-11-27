# Aeternum

A world map and dungeon companion for World of Warcraft: Forever 1.60.1.
It runs on its bundled database and the game's own interface and artwork, with
no other addons required.

- **Map pins** for dungeon entrances, class trainers, profession trainers, and
  quest givers and turn-ins, with search and category filters.
- **Quests that fit your character.** Quest pins follow your level, race, class,
  quest log, and completed quests: `!` marks a quest you can pick up, grey if it
  is low level; `?` marks a turn-in for a quest in your log, gold once it is
  ready.
- **Dungeon panel** with floor maps, every boss's loot (with item quality,
  tooltips, and chat links), dungeon keys, and the dungeon's quests.
- **Minimap guidance** to any pin: an arrow on the minimap points the way, with
  recorded approach points for the Deadmines and Ragefire Chasm.

## Install

Download `Aeternum-<version>.zip` from the latest CI run or release and unzip it
into `World of Warcraft/_forever_/Interface/AddOns/`. The result must be
`Interface/AddOns/Aeternum/Aeternum.toc`. (A GitHub source download unzips as
`Aeternum-main`; rename that folder to `Aeternum`.)

## Use it in game

1. Open the world map with **M** and click **Aeternum**, or type `/aeternum`.
2. Search, or tick the categories to show. **All quests** shows every recorded
   quest location as a reference; **Low-level quests** hides grey quests.
3. Click a row or pin to select it, then **Guide** (or right-click it) to point
   the minimap arrow there. **Stop** or `/aeternum stop` ends guidance.
4. Click a dungeon pin, or find one under **All dungeons**, to open its panel.
   Browse floors, step through bosses to see their loot, and open **Quests** to
   see the dungeon's quests; click one to show where it starts. Hover an item for
   its tooltip; shift-click links it in chat and ctrl-click previews it.

| Command | Effect |
|---|---|
| `/aeternum` | Open the panel on the world map |
| `/aeternum stop` | Stop minimap guidance |
| `/aeternum pins` | Toggle keeping pins on the map while the panel is closed |
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
requirements are not modelled. Seasonal event quests are hidden unless **All
quests** is ticked. Guidance without approach points uses a direct bearing: it
can point across terrain and does not account for walls, tunnels, or elevation.

## Development

You need LuaJIT (or Lua 5.1) and [luacheck](https://github.com/lunarmodules/luacheck).

```sh
luacheck .                 # lint
luajit tests/run.lua       # headless tests against a mock client
tools/check_data.sh        # confirm Data.lua matches a fresh import
tools/package.sh           # build dist/Aeternum-<version>.zip
```

The tests load the addon in TOC order inside `tests/wow.lua`, a small stand-in
for the client API, and drive the panel, pins, quest states, guidance, and
dungeon panel. CI runs all four steps on every push and pull request.

See [data sources and regeneration](DATA_SOURCES.md) for the pinned database,
attribution, and import command. Licensed under [GPL-3.0](LICENSE).
