# Aeternum

A world map and dungeon companion for World of Warcraft: Forever 1.60.1.
It runs with the bundled database and the game’s own interface and artwork.

## Use it in game

1. Put the `Aeternum` folder in `World of Warcraft/_forever_/Interface/AddOns/`.
   `Aeternum.toc` should be directly inside that folder.
2. Restart WoW, open the world map with **M**, and click **Aeternum**. You can
   also open the panel with `/aeternum` (or `/aeternum <search>`).
3. Search (including multi-word queries and boss names) or filter the current
   map for dungeon entrances, class trainers, profession trainers, and quest
   starts and turn-ins. Select a row to highlight its location. Map pins at the
   same location share a tooltip; right-click a stacked pin to cycle entries.
4. Choose a dungeon pin or find a dungeon under **All dungeons**. Browse its
   reference floors, switch bosses to view their loot, hover items for tooltips,
   and click (or Shift/Ctrl-click) an item to inspect or link it in game.
5. Choose an entrance and click **Guide me** (or **Show zone** to jump the world
   map to its entrance). The minimap arrow points to the next recorded approach
   point or the entrance. Stop guidance with the **Stop** button or
   `/aeternum stop`.

## Seed coverage

- 34 dungeon and wing entries, 287 bosses, and 1,335 loot items.
- 34 entrance records across 30 dungeons and wings. Use **Next entrance** to
  switch between Uldaman's two Badlands entrances or the Searing Gorge and
  Burning Steppes approaches to Blackrock Mountain. Selecting a map pin uses
  its coordinates. **All dungeons** prefers the map you're viewing.
- The Deadmines and Ragefire Chasm have recorded approach
  points. The other mapped entrances show a direct bearing. It can point
  across terrain and does not account for walls, tunnels, or elevations.
- 25 classic dungeon and wing entries have client floor-map references. Older
  layouts are labeled as references. Some Forever dungeons lack equivalent
  client floor art.
- 554 trainer pins and 11,100 quest start and turn-in pins across 53 world maps.
  Quest availability still depends on the character and game state.

See [data sources and regeneration](DATA_SOURCES.md) for the pinned local
database, attribution, and import command. [GPL-3.0](LICENSE).
