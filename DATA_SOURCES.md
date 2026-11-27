# Bundled data

Aeternum ships three generated Lua files. The game reads them locally. The import tools and their pinned sources are only needed to regenerate the files.

## Dungeon, quest and trainer records

`Data.lua` projects the English NorgannonDB snapshot compiled by Maro on 2026-11-22 for Forever 1.60.1, interface 16001. It supplies the original non-raid roster, entrance coordinates, trainers, quests and available trainer lessons. The boss and loot records in the release use the reviewed tables described below. [Pinned database](https://github.com/zmarotrix/NorgannonDB/tree/d3d144a8b2d32ae7fb6a0390141f35b3aa55d216)

- NorgannonDB combines Questie/QuestieDB and CMaNGOS Classic-DB data under GPL-3.0 with data from pfQuest by Eric Mauser (Shagu) under MIT. NorgannonDB Collector contributors provide in-game observations. [Upstream notices](licenses/NorgannonDB-NOTICE.md) · [pfQuest MIT license](licenses/pfQuest-MIT.txt)
- Dungeon, boss and loot records include research by **Exehn, author of DungeonJournal (ForeverDungeonJournal 1.7.4)**. NorgannonDB documents permission received on 2026-10-19 on condition of credit. [Upstream notice](licenses/NorgannonDB-NOTICE.md)
- The Deadmines approach leads through Moonbrook. The Ragefire Chasm waypoint marks the descent toward the Cleft of Shadow. The Scarlet Monastery wings use the recorded entrance to the grounds, then their individual portals. The Scarlet Monastery and Dire Maul portal positions come from Checkov23’s projection of named Classic area triggers onto Forever zone maps. [Deadmines guide](https://mmonster.co/wow-forever/guides/dungeons/the-deadmines#where-is-the-deadmines-entrance-and-how-to-get-there) · [Ragefire Chasm guide](https://wow.gg/guides/ragefire-chasm#where-to-find-the-ragefire-chasm-entrance) · [Pinned wing portal data](https://github.com/Checkov23/ForeverDungeonRoutes/blob/86fce2408d45e3240d7a798d5a0fc182a7c9e0f2/ForeverDungeonRoutes/Data/Entrances.lua)
- Four Forever dungeons use community-reported portals and outdoor landmarks. Alcaz goes through the prison building to its cellar, Blackmaw follows the furbolg tunnel, Krol’dok passes the meeting stone west toward the cave, and Shaper’s Terrace goes up the stone staircase. [Alcaz building](https://wowbocho.com/forever/dungeon/alcaz-prison/?ui=en) · [Alcaz cellar](https://mmonster.co/wow-forever/guides/dungeons/alcaz-prison) · [Blackmaw tunnel](https://wowbocho.com/forever/dungeon/blackmaw-hold/?ui=en) · [Krol’dok cave and meeting stone](https://wowbocho.com/forever/dungeon/kroldok/?ui=en) · [Shaper’s doorway](https://wowbocho.com/forever/dungeon/shapers-terrace/?ui=en) · [Shaper’s staircase](https://mmonster.co/wow-forever/guides/dungeons/shapers-terrace)
- The boss audit checks NPC, encounter and item IDs against Forever player records from EG Link, Everloot, Drop Tables and Forever Scout, plus the Camelot edition of All The Things and EzWoW. NorgannonDB’s NPC and item indexes count as one source. The runtime distinguishes items looted from a specific NPC, encounter rolls and guide references. [Boss-by-boss audit](https://github.com/0xAell/Aeternum/tree/main/docs/boss-audit) · [Boss data credits and licenses](licenses/ForeverBossData-NOTICE.md)
- The 53 world map IDs were checked against the Forever client’s UiMap table. The game projects recorded doors through its own map hierarchy and map rectangles for continent views. [Forever 1.60.1.71139 UiMap export](https://wago.tools/db2/UiMap/csv?build=1.60.1.71139)

The map decodes quest records on demand. `questPins[uiMapID]` packs the quest ID, start or turn-in, faction, coordinates and a named NPC or object reference. Coordinates are stored in ten-thousandths. `quests[questID]` packs the name, level range, race and class masks, prerequisites, exclusive and blocking quests, required profession and rank, repeatability and seasonal status. A dungeon record includes its level range, group size, keys and quest IDs. Trainer locations carry an NPC ID and a class token or profession skill-line ID where applicable.

`objectiveSites[questID]` stores representative spawns and exploration sites by client objective index and faction. The importer takes up to three source locations per objective and zone. It omits items with more than twelve recorded drop sources and skips ambiguous multi-objective ordering. Only the selected quest’s sites are decoded during play. Completion comes from the character’s live quest log. [Pinned objectives schema](https://github.com/zmarotrix/NorgannonDB/blob/d3d144a8b2d32ae7fb6a0390141f35b3aa55d216/SPEC.md)

## Floor art and boss locations

`FloorData.lua` uses Checkov23’s Forever Dungeon Routes catalogue to match 34 dungeon and wing entries to their instance IDs and 71 floors. The importer takes floor grids, Blizzard texture and world coordinates, localized rooms, encounter IDs, and stops from every route variant. Bosses match within their own dungeon. Named group encounters include their individual opponents where recorded. All 302 reviewed boss and encounter entries can be opened from the floor menu. The position review compares projected route stops with Forever combat-log pulls and flags estimates. [Pinned floor metadata](https://github.com/Checkov23/ForeverDungeonRoutes/tree/86fce2408d45e3240d7a798d5a0fc182a7c9e0f2/ForeverDungeonRoutes/Data) · [Forever Dungeon Routes MIT license](licenses/ForeverDungeonRoutes-MIT.txt)

The texture IDs refer to files already in the game. Floors with alternate minimap mosaics can use them when legacy tiles are unavailable. The Underbelly uses recorded route segments for a labeled sketch. Unambiguous room names and recognized Blizzard floor map IDs can identify the current floor. The player arrow uses the floor’s coordinate transform only when the client supplies a readable position in that instance. Current encounter events and lockouts supply completion status.

## Lessons and prices

- `Data.lessons` describes spells and requirements from the Forever snapshot. `Data.offers` preserves each NPC’s recipe or class lesson and that NPC’s recorded price in copper. A blank cost means the source has no price. [NorgannonDB](https://github.com/zmarotrix/NorgannonDB/tree/d3d144a8b2d32ae7fb6a0390141f35b3aa55d216)
- `ClassicTraining.lua` supplements those offers from CMaNGOS Classic-DB. The importer joins trainer NPCs to their personal and shared trainer catalogues and resolves trainer spells to the spells learned. Identical catalogues are stored once. The pinned projection includes 1,743 spells and 465 NPCs. Rows taken from this source carry a **Classic** label because Forever can change lessons or prices. [Pinned database](https://github.com/cmangos/classic-db/tree/64adf9f62008df8d530e5d88e3c89aa85e42dc38) · [Source license](https://github.com/cmangos/classic-db/blob/64adf9f62008df8d530e5d88e3c89aa85e42dc38/LICENSE.md) · [Copyright notice](licenses/CMaNGOS-COPYRIGHT.md)
- Class restrictions for the 14 weapon proficiency spells in `Trainers.lua` come from the Forever client’s `SkillLineAbility.ClassMask`. The character’s class and learned professions come from the game. [Forever 1.60.1.71139 SkillLineAbility export](https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.71139)
- A trainer visit stores visible lessons and prices under the trainer’s NPC ID in per-character `AeternumTrainerDB`. An observed price takes priority over the bundled Forever entry and the Classic reference. Visiting with a filtered trainer window preserves other previously recorded lessons. [Forever trainer interface](https://github.com/Gethe/wow-ui-source/blob/d9c22e32cb240afb82bb2ecefbb78ef935333f59/Interface/AddOns/Blizzard_TrainerUI/Mainline/Blizzard_TrainerUI.lua)

## Character loot requirements

The item snapshot covers every item in the boss audit. It records the item class, subclass, equip slot, allowed character classes, required skill and rank, required spell, quest starter and spell taught. Values come from Forever build 1.60.1.71139 with Blizzard’s server-published hotfixes applied. Eight guide-listed items have an equipment type but lack confirmed item requirements. Their rows have blank requirement fields and the menus omit them. [Item snapshot](docs/boss-audit/item-requirements.tsv) · [Forever Item](https://wago.tools/db2/Item/csv?build=1.60.1.71139) · [Forever ItemSparse](https://wago.tools/db2/ItemSparse/csv?build=1.60.1.71139)

The learning check joins each item to its `LearnSpell` effect. This identifies the exact rank of a class book or recipe to compare with the character’s spellbook. The game supplies trained weapon and armor proficiencies, professions and ranks when the map opens. [Forever ItemXItemEffect](https://wago.tools/db2/ItemXItemEffect/csv?build=1.60.1.71139) · [Forever ItemEffect](https://wago.tools/db2/ItemEffect/csv?build=1.60.1.71139) · [Forever skill-line and spell data](https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.71139) · [Forever character sheet](https://github.com/Gethe/wow-ui-source/blob/d9c22e32cb240afb82bb2ecefbb78ef935333f59/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua)

## Regenerate

From the repository root, run `tools/check_data.sh`. It downloads the pinned inputs, verifies the Classic SQL archive’s SHA-256, rebuilds all four databases and compares their output with the committed files. Git, curl, Python 3 and LuaJIT are required by default. Set `LUA=lua5.1` to use Lua 5.1.

To reuse existing inputs, pass a NorgannonDB checkout, a Forever Dungeon Routes checkout and the compressed Classic SQL snapshot in that order. These commands regenerate the committed files with those inputs.

```sh
luajit tools/import_norgannon.lua /path/to/NorgannonDB Data.lua /path/to/ForeverDungeonRoutes/ForeverDungeonRoutes/Data/Entrances.lua
luajit tools/import_floors.lua /path/to/ForeverDungeonRoutes Data.lua FloorData.lua
python3 tools/import_classic_training.py /path/to/ClassicDB_1_12_1_z2815.sql.gz Data.lua ClassicTraining.lua
python3 tools/import_loot_requirements.py build LootData.lua
```

To refresh the numeric item snapshot, save the four linked build 71139 CSVs in a directory as `Item.csv`, `ItemSparse.csv`, `ItemXItemEffect.csv` and `ItemEffect.csv`. The extractor checks their hashes and reads the same build’s version 9 game-data cache. Review the snapshot diff before rebuilding because available hotfixes vary by client. [DB2 definitions](https://github.com/wowdev/WoWDBDefs/tree/master/definitions) · [Hotfix record format](https://github.com/fitzforge/polestar/blob/c0e768df4df867532f6334c1ed5464a8bc544021/rust/crates/forge-gamedata/src/hotfix.rs)

```sh
python3 tools/import_loot_requirements.py snapshot /path/to/csv /path/to/DBCache.bin docs/boss-audit/item-requirements.tsv
```
