<img align="right" src="https://raw.githubusercontent.com/0xAell/Aeternum/main/artwork/aeternum-curseforge.png" width="80" height="80" alt="A brass dungeon arch with a winding trail">

# Aeternum

Press **M**. Aeternum adds dungeon floors, boss loot, trainers, quests and entrance directions to the World of Warcraft: Forever map. It uses Blizzard’s artwork, menus and tooltips. The data ships with the addon and works offline.

## On the map

| Where | What to do |
| --- | --- |
| Zone or continent | Click a dungeon entrance to see the floors. Right-click for minimap directions to a specific wing or door. Nearby locations share a pin while zoomed out. Scroll in to separate them or click to choose. |
| Inside a dungeon | Press **M**. The map follows recognized rooms and floor IDs. An arrow shows your position when the client supplies coordinates for that floor. Click the floor name to change floors, check keys in your bags, or find an outdoor entrance. Scroll to zoom and drag to pan. **Back**, **Escape**, or right-clicking empty floor space returns to the zone map. |
| Boss skull | Click for drops your character can use. Hover an item for its tooltip, Shift-click to link it, or Ctrl-click to preview it. If bosses share a spot, choose one. **Boss loot** also lists bosses whose positions are unknown. |
| Trainer | Your class, faction, professions and eligible weapon skills determine which trainers appear. Click a trainer to see lessons and prices. **Later training** and **Learned** hold lessons with unmet requirements and skills you already know. Hover a lesson for its requirements and price source. |
| Quest | Exclamation marks show available starts. Question marks turn gold when you can hand the quest in. Hover for the NPC or object and your live progress. Click to track the quest or get directions. **Dungeon quests** takes you to the giver before acceptance and the turn-in afterward. |

Boss menus and loot search use your class and trained weapon and armor proficiencies. Recipes appear when you have the profession, rank and specialization to learn them. Learning a recipe removes it from the list. Higher-level gear stays visible if you already use that equipment type. Other recorded drops, encounter rolls and guide-listed drops appear in submenus when they contain a match.

The quest you focus in the game can show objective locations for its unfinished steps. Without a focus, Aeternum uses your first watched quest. Blizzard’s own objective marker takes precedence. The map’s existing tracking menu controls quest objectives, low-level quests and additional trainers.

Directions survive a UI reload on the same character. They pause on another continent or inside an unrelated instance and end when you reach the destination. Use **Stop directions** on the map to cancel.

A price from your character’s last trainer visit takes precedence. Otherwise the map uses the NPC’s bundled Forever record, then a labeled **Classic** reference where available. An unknown price is displayed as **Price unknown**. Visits are saved per character.

## Coverage

- 34 dungeon and wing entries, 71 floors and 302 boss and encounter entries. Of 1,404 audited items, 1,396 have verified Forever requirements for character loot lists. There are 277 map pins before grouping encounters that share a location. Guide estimates are labeled on hover. Dalaran’s Underbelly uses a labeled route sketch. [Boss and loot audit](https://github.com/0xAell/Aeternum/tree/main/docs/boss-audit)
- 41 outdoor entrance records across all 34 entries. Ten have a recorded approach waypoint, covering the Deadmines, Ragefire Chasm, the four Scarlet Monastery wings, Alcaz Prison, Blackmaw Hold, Krol’dok Stronghold and Shaper’s Terrace. Other doors show a direct bearing. Dire Maul East and West have multiple selectable portals.
- 562 trainer locations, including eight weapon masters. Quest data covers 5,323 quests, 11,100 start and turn-in records, and 5,207 representative objective sites for 2,097 quests. Availability uses level, race, class, profession rank, quest chains and progress. Reputation and specialization can also affect offers in game.

## Install

Download `Aeternum-<version>.zip` from a release or the **Aeternum** CI artifact and extract it into `World of Warcraft/_forever_/Interface/AddOns/`. The resulting path should be `Interface/AddOns/Aeternum/Aeternum.toc`. Reload the interface or start the game. Aeternum requires no other addons.

## Optional commands

| Command | Action |
| --- | --- |
| `/aeternum` | Open the world map |
| `/aeternum <search words>` | Search by dungeon, boss or drop. Words can appear in any order, as in `/aeternum Herod Scarlet`. |
| `/aeternum dungeons [name]` | Find a dungeon, boss or drop on the map. For example, `/aeternum dungeons Cruel Barb` opens a result for Edwin VanCleef. |
| `/aeternum help` | Show the available map commands |
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
