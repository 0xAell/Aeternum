<div align="center">

<img src="https://raw.githubusercontent.com/0xAell/Aeternum/main/artwork/aeternum-curseforge.png" width="112" height="112" alt="Aeternum icon showing a golden dungeon arch over a winding map trail" />

# Aeternum

**Dungeon maps, usable boss loot, trainers, quests, and minimap directions built straight into the World of Warcraft: Forever map.**

[![Latest Release](https://img.shields.io/github/v/release/0xAell/Aeternum?style=flat-square&color=b8860b&label=release)](https://github.com/0xAell/Aeternum/releases/latest)
[![CurseForge](https://img.shields.io/badge/CurseForge-Aeternum-f16436?style=flat-square&logo=curseforge&logoColor=white)](https://www.curseforge.com/wow/addons/aeternum)
[![WoW Forever 1.60.1](https://img.shields.io/badge/WoW%20Forever-1.60.1-134b5f?style=flat-square)](https://github.com/0xAell/Aeternum/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/0xAell/Aeternum/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/0xAell/Aeternum/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/github/license/0xAell/Aeternum?style=flat-square&color=4c6b50)](LICENSE)

[Install](#install) · [Features](#features) · [Controls & Commands](#controls--commands) · [Player Guide](docs/map-guide.md) · [Data & Credits](DATA_SOURCES.md)

</div>

---

Press **M** and everything you need is already on the map. Aeternum adds dungeon floors, character-aware boss loot, offline trainer catalogues, quest pins, and minimap directions directly to Blizzard's world map. It uses native menus, tooltips, and map art, ships with its full database offline, and needs no setup or other addons.

## Features

### Dungeon floors and boss loot
Click any entrance on the Azeroth, continent, or zone map to browse all 34 dungeons and wings across 71 floors. Inside an instance, pressing **M** opens your current floor automatically and shows your position wherever the client reports coordinates.

- Click a boss skull (or open **Boss loot** in the floor menu for unplaced bosses) to see gear your class and trained proficiencies can use, plus recipes you have the profession, rank, and specialization to learn. Already-learned recipes drop off the list.
- Hover items for standard WoW tooltips, **Shift-click** to link in chat, **Ctrl-click** to preview in the dressing room, and check which **Dungeon keys** are already in your bags. Defeated bosses dim as you clear the run.
- Verified boss drops appear directly in the main menu, while other recorded corpse drops, encounter rolls, and guide-listed drops stay separated in submenus so you can see what has live player evidence.

### Entrances and minimap directions
Hover over a zone to see its recommended levels, on the Azeroth, continent, and zone maps, including unexplored terrain.

All 41 outdoor entrances appear on world, continent, and zone maps, including multi-door dungeons like Dire Maul, Uldaman, and Blackrock Mountain.

- Right-click any entrance (or click a trainer or quest pin) for a minimap bearing to the door.
- Ten trickier entrances (The Deadmines, Ragefire Chasm, all four Scarlet Monastery wings, Alcaz Prison, Blackmaw Hold, Krol'dok Stronghold, and Shaper's Terrace) include mapped approach waypoints.
- Directions survive `/reload`, pause automatically on another continent or inside an unrelated instance, and clear once you arrive.

### Offline trainer catalogues
Trainers filter automatically to your class, faction, learned professions, and eligible weapon skills. Toggle **Other classes and professions** in Blizzard's map tracking menu whenever you want to see everyone.

- Click a trainer to check spells, recipes, ranks, requirements, and prices before making the trip, sorted into what you can train now, **Later training**, and **Learned**.
- 522 of 561 trainers have offline catalogues ready before your first visit, and talking to any trainer updates their lessons and prices for your character.

### Quests and live objectives
Exclamation marks show quests you can pick up, and question marks turn gold when you're ready to hand in, factoring in your level, race, class, profession rank, quest chains, and live quest log.

- Open **Dungeon quests** from any floor menu to locate the quest giver before accepting or the turn-in afterward.
- For your focused (or first watched) quest, Aeternum marks recorded locations for unfinished objectives whenever Blizzard doesn't already place a marker.

## Install

### CurseForge (recommended)
Install directly from the **[CurseForge project page](https://www.curseforge.com/wow/addons/aeternum)** or search for **Aeternum** in the CurseForge app.

### Manual install from GitHub
1. Download `Aeternum-<version>.zip` from the **[latest release](https://github.com/0xAell/Aeternum/releases/latest)** under **Assets**.
2. Extract it into your WoW Forever `AddOns` folder so the path looks like:
   ```text
   World of Warcraft/_forever_/Interface/AddOns/Aeternum/Aeternum.toc
   ```
3. Launch the game (or run `/reload` if you're already logged in) and press **M**.

> [!TIP]
> **Quick check in game:** Open Westfall on the world map and click **The Deadmines** near Moonbrook to browse its floors and boss drops, or right-click the entrance for minimap directions down through Moonbrook.

## Controls & Commands

### On the map

| Action | Result |
| --- | --- |
| **Left-click** a dungeon entrance | Open its floor map and boss pins |
| **Right-click** a dungeon entrance | Start or stop minimap directions to a wing or door |
| **Left-click** a boss skull | View usable boss drops (or pick a boss when several share a spot) |
| **Left-click** a trainer or quest pin | Browse lessons and prices, track a quest, or start directions |
| **Scroll / drag** on a dungeon floor | Zoom in and pan around the floor |
| **Back** button or **Right-click** empty floor | Return to the outdoor zone map (**Escape** closes the map) |
| **Map tracking menu** (magnifying glass) | Toggle entrances, trainers, low-level quests, or all quest locations |

### Slash commands

| Command | What it does |
| --- | --- |
| `/aeternum` | Open the world map |
| `/aeternum <search>` | Search dungeons, bosses, or usable drops in any word order (e.g. `/aeternum herod scarlet`) |
| `/aeternum dungeons [name]` | Browse dungeons or jump straight to a matching boss or item (e.g. `/aeternum dungeons Cruel Barb`) |
| `/aeternum stop` | Stop active minimap directions |
| `/aeternum reset` | Reset Aeternum's map filters to defaults |
| `/aeternum help` | Show available commands in chat |

For the full walkthrough of map filters, floor tracking, and tooltip indicators, see the **[Player Guide](docs/map-guide.md)**.

## Database Coverage

| Area | Coverage | Audit & details |
| --- | --- | --- |
| **Dungeons & floors** | 34 dungeons & wings · 71 floors · 41 outdoor entrances (10 with approach waypoints) | [Player Guide](docs/map-guide.md) |
| **Bosses & loot** | 302 boss & encounter entries · 277 floor pins · 1,404 audited items (1,396 with verified requirements) | [Boss & Loot Audit](docs/boss-audit/README.md) |
| **Trainers** | 561 trainers (562 map locations, 8 weapon masters) · 522 offline catalogues · 1,743 spells & recipes | [Trainer Coverage](docs/trainer-data/README.md) |
| **Quests** | 5,323 quests · 11,100 start & turn-in pins · 5,207 objective sites across 2,097 quests | [Data Sources](DATA_SOURCES.md) |

## Feedback & Contributing

Spotted a misplaced boss pin, a missing drop, or an outdated trainer price? **[Open an issue](https://github.com/0xAell/Aeternum/issues)** with the dungeon, floor, and NPC or item name. An in-game screenshot always helps.

To contribute code or rebuild the bundled datasets locally, see **[CONTRIBUTING.md](CONTRIBUTING.md)** for the `luacheck`, LuaJIT test suite, data verification, and packaging commands.

---

<div align="center">

[Data Sources & Credits](DATA_SOURCES.md) · [Contributing](CONTRIBUTING.md) · [GPL-3.0 License](LICENSE)

</div>
