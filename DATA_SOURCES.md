# Bundled data

Aeternum ships three generated Lua files. The game reads them locally. The import tools and their pinned sources are only needed to regenerate the files.

## Dungeon, quest and trainer records

`Data.lua` projects the English NorgannonDB snapshot compiled by Maro on 2026-11-22 for Forever 1.60.1, interface 16001. It contains non-raid dungeons with identified bosses, their drops in source order, entrance coordinates, trainers, quests and available trainer lessons. [Pinned database](https://github.com/zmarotrix/NorgannonDB/tree/d3d144a8b2d32ae7fb6a0390141f35b3aa55d216)

- NorgannonDB combines Questie/QuestieDB and CMaNGOS Classic-DB data under GPL-3.0 with data from pfQuest by Eric Mauser (Shagu) under MIT. NorgannonDB Collector contributors provide in-game observations. [Upstream notices](licenses/NorgannonDB-NOTICE.md) · [pfQuest MIT license](licenses/pfQuest-MIT.txt)
- Dungeon, boss and loot records include research by **Exehn, author of DungeonJournal (ForeverDungeonJournal 1.7.4)**. NorgannonDB documents permission received on 2026-10-19 on condition of credit. [Upstream notice](licenses/NorgannonDB-NOTICE.md)
- The Deadmines approach waypoint leads toward Moonbrook. The Ragefire Chasm waypoint marks the descent toward the Cleft of Shadow. Other recorded doors use a direct bearing. Area-level alternate entrances are associated with a wing only when the primary matches, or the wing has no primary. [Deadmines guide](https://mmonster.co/wow-forever/guides/dungeons/the-deadmines#where-is-the-deadmines-entrance-and-how-to-get-there) · [Ragefire Chasm guide](https://wow.gg/guides/ragefire-chasm#where-to-find-the-ragefire-chasm-entrance)
- The 53 world map IDs were checked against the Forever client’s UiMap table. The game projects recorded doors through its own map hierarchy and map rectangles for continent views. [Forever 1.60.1.71139 UiMap export](https://wago.tools/db2/UiMap/csv?build=1.60.1.71139)

The map decodes quest records on demand. `questPins[uiMapID]` packs the quest ID, start or turn-in, faction and normalized coordinates for each location. Coordinates are stored in ten-thousandths. `quests[questID]` packs the name, level range, race and class masks, prerequisites, exclusive and blocking quests, required profession and rank, repeatability and seasonal status. A dungeon record also includes its level range, group size, keys and quest IDs. Each trainer location carries a stable NPC ID and a class token or profession skill-line ID where applicable.

## Floor art and boss locations

`FloorData.lua` uses Checkov23’s Forever Dungeon Routes catalogue to match the 34 dungeon and wing entries to their instance IDs and 71 floors. The importer takes floor grids, Blizzard minimap tile positions and texture coordinates, localized floor and room names, and boss stops from the pinned metadata. A stop becomes a clickable skull only when its name matches a boss in the same dungeon. All 287 encounters remain accessible from the map’s boss list. [Pinned floor metadata](https://github.com/Checkov23/ForeverDungeonRoutes/tree/86fce2408d45e3240d7a798d5a0fc182a7c9e0f2/ForeverDungeonRoutes/Data) · [Forever Dungeon Routes MIT license](licenses/ForeverDungeonRoutes-MIT.txt)

The texture IDs refer to files already in the game. Floors with alternate minimap mosaics can use them when legacy tiles are unavailable. The Underbelly has recorded route segments and uses those for a labeled sketch. The ZIP contains no map images. Room names spanning several floors are excluded from automatic floor detection.

## Lessons and prices

- `Data.lessons` describes spells and requirements from the Forever snapshot. `Data.offers` preserves each NPC’s recipe or class lesson and that NPC’s recorded price in copper. A blank cost means the source has no price. [NorgannonDB](https://github.com/zmarotrix/NorgannonDB/tree/d3d144a8b2d32ae7fb6a0390141f35b3aa55d216)
- `ClassicTraining.lua` supplements those offers from CMaNGOS Classic-DB. The importer joins trainer NPCs to their personal and shared trainer catalogues and resolves trainer spells to the spells learned. Identical catalogues are stored once. The pinned projection includes 1,743 spells and 465 NPCs. Rows taken from this source carry a **Classic** label because Forever can change lessons or prices. [Pinned database](https://github.com/cmangos/classic-db/tree/64adf9f62008df8d530e5d88e3c89aa85e42dc38) · [Source license](https://github.com/cmangos/classic-db/blob/64adf9f62008df8d530e5d88e3c89aa85e42dc38/LICENSE.md) · [Copyright notice](licenses/CMaNGOS-COPYRIGHT.md)
- Class restrictions for the 14 weapon proficiency spells in `Trainers.lua` come from the Forever client’s `SkillLineAbility.ClassMask`. The character’s class and learned professions come from the game. [Forever 1.60.1.71139 SkillLineAbility export](https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.71139)
- A trainer visit stores visible lessons and prices under the trainer’s NPC ID in per-character `AeternumTrainerDB`. An observed price takes priority over the bundled Forever entry and the Classic reference. Visiting with a filtered trainer window preserves other previously recorded lessons. [Forever trainer interface](https://github.com/Gethe/wow-ui-source/blob/d9c22e32cb240afb82bb2ecefbb78ef935333f59/Interface/AddOns/Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua)

## Regenerate

From the repository root, run `tools/check_data.sh`. It downloads the pinned inputs, verifies the Classic SQL archive’s SHA-256, runs all three importers and compares their output with the committed databases. Git, curl, Python 3 and LuaJIT are required by default. Set `LUA=lua5.1` to use Lua 5.1.

To reuse existing inputs, pass a NorgannonDB checkout, a Forever Dungeon Routes checkout and the compressed Classic SQL snapshot in that order. These commands regenerate the committed files with those inputs.

```sh
luajit tools/import_norgannon.lua /path/to/NorgannonDB Data.lua
luajit tools/import_floors.lua /path/to/ForeverDungeonRoutes Data.lua FloorData.lua
python3 tools/import_classic_training.py /path/to/ClassicDB_1_12_1_z2815.sql.gz Data.lua ClassicTraining.lua
```
