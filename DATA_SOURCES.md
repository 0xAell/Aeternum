# Bundled data

`Data.lua` is a compact, redistributable projection of the English WoW Forever
snapshot from [NorgannonDB](https://github.com/zmarotrix/NorgannonDB/tree/d3d144a8b2d32ae7fb6a0390141f35b3aa55d216), compiled by Maro. The snapshot was generated on
2026-11-22 for client 1.60.1 and interface 16001. The extracted data is GPL-3.0.
The addon reads the bundled file directly and has no runtime data dependency.

- NorgannonDB combines Questie/QuestieDB and CMaNGOS Classic-DB data under GPL-3.0
  with data from pfQuest by Eric Mauser (Shagu) under MIT. It also credits
  NorgannonDB Collector contributors for observations made in game. [Upstream notices](licenses/NorgannonDB-NOTICE.md) · [pfQuest MIT license](licenses/pfQuest-MIT.txt)
- The dungeon, boss, and loot records include research by **Exehn, author of
  DungeonJournal (ForeverDungeonJournal 1.7.4)**. NorgannonDB documents permission
  received 2026-10-19 to use this data on condition of credit. [Upstream notice](licenses/NorgannonDB-NOTICE.md)
- The Deadmines and Ragefire Chasm include one manually transcribed approach
  waypoint each. The Deadmines point leads toward Moonbrook's outdoor approach.
  The Ragefire Chasm point marks the descent toward the Cleft of Shadow before
  the portal. [Deadmines guide](https://mmonster.co/wow-forever/guides/dungeons/the-deadmines#where-is-the-deadmines-entrance-and-how-to-get-there) · [Ragefire Chasm guide](https://wow.gg/guides/ragefire-chasm#where-to-find-the-ragefire-chasm-entrance)

The import keeps non-raid dungeon entries with identified bosses and preserves
the upstream loot order. Each dungeon's or wing's primary entrance appears
first. When its map and coordinates match an entry in the upstream area's
entrance list, the import includes the other distinct entrances in that list.
When a dungeon has no valid primary, it uses the area's recorded entrances.

Trainer pins use reported NPC coordinates, trainer titles, and recorded class
or profession lessons. Quest pins show representative starts and turn-ins with map
coordinates, including known faction variants. They provide reference locations.
Availability can depend on level, class, race, prerequisites, or game state.
The two authored approaches cover the recorded waypoints. Other entrance guidance
uses a direct bearing.

All 53 world map IDs in the projection exist in the UiMap table from client
build 1.60.1.71139. [UiMap export](https://wago.tools/db2/UiMap/csv?build=1.60.1.71139)

## Regenerate

Run these commands from the repository root with Git and Lua 5.1 installed.

```sh
git clone https://github.com/zmarotrix/NorgannonDB.git ../aeternum-source-norgannondb
git -C ../aeternum-source-norgannondb checkout d3d144a8b2d32ae7fb6a0390141f35b3aa55d216
lua tools/import_norgannon.lua ../aeternum-source-norgannondb Data.lua
```
