# Aeternum

Press **M**. Aeternum adds dungeon floors, boss loot, trainers, quests and entrance directions to the World of Warcraft: Forever map. It uses Blizzard’s artwork, menus and tooltips. The data ships with the addon and works offline.

## On the map

| Where | What to do |
| --- | --- |
| Zone or continent | Click a dungeon entrance to see its floor. Right-click the entrance and choose **Show path to…** for minimap directions. Shared entrances let you choose the wing. |
| Inside a dungeon | Press **M** to see the current floor. Recognized rooms select their floor automatically. Use the floor name to pick another floor or wing. Scroll to zoom and drag to pan. **Back**, **Escape**, or right-clicking empty floor space returns to the zone map. |
| Boss skull | Click for that boss’s drops. Hover an item for its tooltip, Shift-click to link it, or Ctrl-click to preview it. The floor menu’s **Boss loot** list also includes bosses whose positions are unknown. |
| Trainer | Click to see the recipes, class ranks or weapon skills that NPC teaches. Prices appear beside each lesson. Hover for level, skill and price source. Your class, learned professions, faction and eligible weapon proficiencies determine which trainers appear. |
| Quest | Exclamation marks show available starts. Question marks show active turn-ins and turn gold when ready. A dungeon’s **Dungeon quests** menu can show a quest’s starting location on the zone map. |

The mouse wheel zooms outdoor maps, including zones whose art normally has only one zoom level. For other professions or low-level quests, use the map’s existing tracking menu. **Stop directions** is available there and on dungeon entrances while a route is active.

A price from your character’s last trainer visit takes precedence. Otherwise the map uses the NPC’s bundled Forever record, then a labeled **Classic** reference where available. An unknown price is displayed as **Price unknown**. Visits are saved per character.

## Coverage

- 34 dungeon and wing entries, 71 floors, 287 bosses and 1,335 distinct loot items. There are recorded positions for 213 bosses. Dalaran’s Underbelly uses a labeled route sketch.
- 34 outdoor entrance records, including shared wings and alternate approaches. Alcaz Prison, Blackmaw Hold, Krol’dok Stronghold and Shaper’s Terrace open on entry or through dungeon search while their outdoor entrances are unverified.
- The Deadmines and Ragefire Chasm have recorded outdoor approach points. Other routes show a direct bearing to the selected entrance. Guidance pauses inside instances and across continents.
- 562 trainer locations, including eight weapon masters. Quest data covers 5,323 quests and 11,100 start and turn-in records. Quest availability checks level, race, class, prerequisites, exclusivity and quest progress. Profession requirements appear in tooltips. Reputation and specialization can affect availability in game.

## Install

Download `Aeternum-<version>.zip` from a release or the **Aeternum** CI artifact and extract it into `World of Warcraft/_forever_/Interface/AddOns/`. The resulting path should be `Interface/AddOns/Aeternum/Aeternum.toc`. Reload the interface or start the game. Aeternum requires no other addons.

## Optional commands

| Command | Action |
| --- | --- |
| `/aeternum` | Open the world map |
| `/aeternum dungeons [name]` | Find a dungeon, boss or drop on the map. For example, `/aeternum dungeons Cruel Barb` opens a result for Edwin VanCleef. |
| `/aeternum stop` | End minimap directions |
| `/aeternum reset` | Reset map filters |

## Development

Run these from the repository root with LuaJIT or Lua 5.1, luacheck, Python 3, Git, curl and zip.

```sh
luacheck .
luajit tests/run.lua
tools/check_data.sh
tools/package.sh
```

The headless tests exercise the map, stock menu interactions, trainer observations, quest states and minimap directions. CI also regenerates the bundled databases and builds the installable ZIP. See the [Forever interface source](https://github.com/Gethe/wow-ui-source/tree/d9c22e32cb240afb82bb2ecefbb78ef935333f59) and [data sources and regeneration](DATA_SOURCES.md).

Aeternum is licensed under [GPL-3.0](LICENSE).
