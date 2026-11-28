# Boss mechanics in WoW Forever

Aeternum has tank, healer and damage-dealer guidance for all **302 named boss and encounter entries across 34 dungeons and wings**. Each row in the audit identifies its NPC, instance, sources and exact spell IDs. Players can open **Tactics** on a skull or use the floor's **Boss loot** list for encounters without a fixed position. [Boss-by-boss evidence](mechanics.tsv)

| Evidence in this snapshot | Coverage |
| --- | ---: |
| Bosses with a cast recorded inside their Forever instance | 176 |
| Distinct recorded boss and spell combinations | 481 |
| Additional boss and spell combinations supported by references | 357 |
| Bosses with reference spells and no recorded cast | 100 |
| Bosses with role guidance and no qualifying spell IDs | 26 |

## How to read the records

**Recorded Forever casts** require a positive start or success count in EG Link, an exact NPC ID, a matching English client spell name and combat positions exclusively in the expected instance for that NPC in that build. The qualifying records span eight Forever builds from 1.60.1.70790 through 1.60.1.71139. EG Link aggregates observations per NPC and build. These records establish that a boss used an ability. Cooldowns, target selection, interrupts and immunities need separate evidence. [EG Link data and schema](https://github.com/JIVESCORP/eg-link-output-wowf/blob/c1bf99bc2835bbe1b2dad82fb99f994c0cfffe33/DATASETS.md) · [Input file hashes](inputs.tsv)

**Reference spells** use independent agreement on the same NPC and spell ID between the Forever dungeon journal, the Azeroth DB encounter catalogue or a Classic creature spell list. Selected unlogged spells have also been reviewed individually against Forever spell descriptions and encounter guidance. Shared multi-NPC encounter lists stay out of automatic matching. The runtime lists a spell once per boss and gives live observations priority. Several databases draw on common game data, so agreement between them still counts as a reference. [NaowhForever ability index](https://github.com/naowh-gaming/NaowhForever/blob/5576eaf956b8cbc8311759bf62cbafcd77a74310/NaowhForever_DungeonJournal/Data/Abilities.lua) · [Azeroth DB encounter pages and spell IDs](mechanics-database.tsv) · [ClassicDB snapshot](https://github.com/cmangos/classic-db/tree/64adf9f62008df8d530e5d88e3c89aa85e42dc38)

**Role and class guidance** also draws on route notes for 283 encounters, the journal's notes for 210 NPCs, 22 Method guides with 132 matched boss entries, Wowhead's Shaper's Terrace field guide and 209 NPC matches in the Azeroth DB catalogue. The audit records missing observations explicitly. For example, Katerina's healer should bring the Garrote target above 90% health and remove Deadly Poison from the tank. Withermaw's Intimidating Roar is a fear that Tremor Totem can break even though the client assigns it no Magic dispel type. [EzWoW route guide](https://github.com/ezwow-addons/EzWoW-DungeonRouteGuide/blob/b81ba9ce16c494d02a7fc518e716cc34da19592c/Data/DungeonData.lua) · [Journal notes](https://github.com/naowh-gaming/NaowhForever/blob/5576eaf956b8cbc8311759bf62cbafcd77a74310/NaowhForever_DungeonJournal/Data/Tips.lua) · [Indexed field guides](mechanics-guides.tsv) · [Alcaz Prison](https://www.method.gg/wow-forever/dungeons/alcaz-prison) · [Blackmaw Hold](https://www.method.gg/wow-forever/dungeons/blackmaw-hold)

The spell catalogue uses build **1.60.1.71139** for names, icon file IDs, mechanic categories and dispel types. A Magic damage spell alone does not justify a cleanse prompt. Known beneficial Magic auras appear as **Magic buff** for an offensive dispel. A Hunter sees Tranquilizing Shot only for an identified dispellable Enrage. The client provides localized spell names, icons and aura colors in game. Class actions check the learned spell or rank, including the current pet's own spellbook. [Spell names](https://wago.tools/db2/SpellName?build=1.60.1.71139) · [Dispel and mechanic categories](https://wago.tools/db2/SpellCategories?build=1.60.1.71139) · [Spell icons](https://wago.tools/db2/SpellMisc?build=1.60.1.71139)

The addon bundles **111 short English tooltip summaries** for when the client has no spell description. These describe effects documented in the same build's spell or aura text. For Eject Sneed, VanCleef's Allies and Scarlet Resurrection, the client records a summon or resurrection effect, and the encounter audit identifies its target. The summaries omit variable damage, duration and range. The rest of the spell index still provides names, icons and any verified effect tags. [Offline summaries](mechanics-spell-notes.tsv) · [Client spell and aura text](https://wago.tools/db2/Spell/csv?build=1.60.1.71139) · [Client spell effects](https://wago.tools/db2/SpellEffect/csv?build=1.60.1.71139)

## Reproduce the snapshot

Use the pinned journal's `NaowhForever_DungeonJournal/Data` directory, English CSV exports of `SpellName`, `SpellCategories`, `SpellMisc`, `Spell` and `SpellEffect`, and the compressed Classic world database at the linked revision. The generator checks their SHA-256 hashes and reads the checked-in encounter IDs, guide indexes and spell summaries. From the repository root, run the following with Python 3 and LuaJIT available.

```sh
python3 tools/fetch_boss_sources.py /tmp/forever-boss-inputs --db2 "$db2_dir"
python3 tools/audit_mechanics.py /tmp/forever-boss-inputs "$journal_data" "$db2_dir" "$classic_sql_gz" /tmp/forever-mechanics
cmp BossCasts.lua /tmp/forever-mechanics/BossCasts.lua
cmp docs/boss-audit/mechanics.tsv /tmp/forever-mechanics/mechanics.tsv
```

## Party boss callouts

`PartyCalloutData.lua` selects 40 encounters across 21 dungeon wings. It focuses on mechanics that can disable
or kill a player, cause another pack to join, undo the group's progress, or keep the boss immune. Each entry
has a short fallback that works with any party composition. Class variants use known spells for the sender
and class and level as an indication of what other party members can learn. Routine rotations and weak
mechanics stay in the map guide.

For example, the Captain Dreadrise callout prioritizes freeing players from Abyssal Bubbles and interrupting
Waterbolt Volley. Var'Taka's callout prioritizes the two healing Brinescale Priestesses and warns players to
leave the frontal after Harpoon. The Mage variant calls for Polymorph on one priestess.
[Dreadrise combat logs](https://maxdps.com/forever/bosses/captain-dreadrise) ·
[Priestess creature data](https://db.icy-veins.com/wow-forever/npcs/260096) ·
[Drowned City field guide](https://www.method.gg/wow-forever/dungeons/the-drowned-city) ·
[Forever client hotfixes](https://worldofwarcraft.blizzard.com/en-us/news/24315281)
