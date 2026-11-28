# Aeternum player guide

Press **M** to open the world map. The map’s tracking menu controls quest objectives, low-level quests, and additional trainers.

## Dungeon entrances and directions

Click a dungeon entrance to browse its floors. Right-click for minimap directions to a specific wing or door. All entrances are available on the world map and their continent map. You can also open the Stockade from Elwynn Forest, Ragefire Chasm from Durotar, and the Hall of Thanes from Dun Morogh. Hover over a shared pin to see the dungeons it covers, then click to choose one.

To pick a dungeon for your level, open **Dungeons by level** in the map's tracking menu, type `/aeternum dungeons`, or choose **Aeternum** in the minimap's addon compartment. Every dungeon and wing is listed from the lowest level range to the highest. Each range uses the game's quest difficulty colors for your character: red or orange is above your level, yellow is your range, green is easy, and gray is trivial. Entrance tooltips color their level range the same way. Choose a dungeon to open its floors.

Ten of the 41 marked entrances have a recorded approach waypoint, covering the Deadmines, Ragefire Chasm, the four Scarlet Monastery wings, Alcaz Prison, Blackmaw Hold, Krol’dok Stronghold, and Shaper’s Terrace. Other doors show a direct bearing. Dire Maul East and West each have more than one selectable portal.

Directions survive a UI reload on the same character. They pause on another continent or inside an unrelated instance and end when you reach the destination. Choose **Stop directions** on the map to cancel.

## Dungeon floors and boss loot

Inside a dungeon, press **M** to see the floor. The map follows recognized rooms and floor IDs, and moves to a boss's floor when the fight starts. That helps where the game gives no room name or position. After a fight, the map opens on that boss's floor until a room name says otherwise. A floor you choose yourself stays put. A player arrow appears when the client supplies coordinates for that floor. Scroll to zoom and drag to pan. Choose **Back** or right-click empty floor space to return to the zone map. **Escape** closes the map.

Click the floor name to change floors, check which dungeon keys are in your bags, or find an outdoor entrance. Under **Entrances**, **Show on zone map** marks the door when you open its zone. If you’re viewing a different zone, the addon names the destination in chat.

Click a boss skull to see its drops. If bosses share a spot, choose one. The floor menu’s **Boss loot** list also includes bosses whose positions are unknown. Hover an item for its tooltip, Shift-click to link it, or Ctrl-click to preview it.

Item tooltips anywhere in the game, such as your bags, chat links, and the auction house, name the bosses that drop the item. Only recorded drops and encounter rolls count. Guide-listed items stay off the tooltip until a player drop confirms them.

Both boss menus and loot search use your class and trained weapon and armor proficiencies. Higher-level gear stays visible if you already use that equipment type. Recipes appear when you have the profession, rank, and specialization to learn them. Learning a recipe removes it from the list. Other recorded drops, encounter rolls, and guide-listed drops have separate submenus when they contain a match.

The atlas covers 34 dungeons and wings, 71 floors, and 302 boss and encounter entries. There are 277 map pins before grouping encounters that share a location. Hover a pin to see whether its position is a guide estimate. Dalaran’s Underbelly uses a labeled route sketch. Of 1,404 audited items, 1,396 have verified Forever requirements for character loot lists. [Boss and loot audit](boss-audit/README.md)

## Trainers

Your class, faction, professions, and eligible weapon skills determine which trainers appear. Click a trainer for lessons and prices. **Later training** holds lessons with unmet requirements. **Learned** holds skills you already know.

Hover a lesson for its requirements, where the record came from, and how its price was determined. A discounted quote shows the visitor’s reputation standing when known. **Beta** and **Classic** mark older references. Visiting the trainer confirms the lessons and updates prices for your character.

The map shows 562 locations for 561 trainers, including eight weapon masters. You can browse 522 catalogues offline. Visiting one of the remaining 39 trainers records their lessons. Recorded trainer windows supply 1,743 distinct spells and recipes. [Trainer records and coverage](trainer-data/README.md)

## Quests

Exclamation marks show available starts. Question marks turn gold when you can hand the quest in. Hover for the NPC or object and your progress. Click to track the quest or get directions. In the dungeon floor menu, **Dungeon quests** marks the giver before acceptance and the turn-in afterward. If the contact is in another zone, chat names it and the mark appears when you open that zone.

Aeternum shows recorded objective locations for unfinished steps of your focused quest. If you haven’t focused a quest, it uses your first watched quest. Blizzard’s own objective marker takes precedence.

The database covers 5,323 quests, 11,100 start and turn-in records, and 5,207 representative objective sites for 2,097 quests. Availability uses level, race, class, profession rank, quest chains, and progress. Reputation and specialization can also affect offers in game.

## Optional commands

| Command | Action |
| --- | --- |
| `/aeternum` | Open the world map. |
| `/aeternum <search words>` | Search by dungeon, boss, or drop. Words can appear in any order, as in `/aeternum Herod Scarlet`. |
| `/aeternum dungeons [name]` | Without a name, list every dungeon by level. With one, find a dungeon, boss, or drop on the map. For example, `/aeternum dungeons Cruel Barb` finds Edwin VanCleef for a character who can use the sword. |
| `/aeternum help` | Show the available map commands. |
| `/aeternum stop` | End minimap directions. |
| `/aeternum reset` | Reset map filters. |
