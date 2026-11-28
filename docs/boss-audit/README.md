# WoW Forever dungeon boss audit

For combat mechanics, the companion audit covers tank, healer and DPS tactics, class counters and the source of each recorded or referenced spell. [Boss mechanics](mechanics.md)

On November 27, 2026, we checked every one of Aeternum 0.5.2’s **287 roster entries and 1,554 boss–item links** across 34 dungeon and wing entries. The revised roster has 302 entries. It includes every named encounter in the pinned client-derived encounter list for those instances. Rare enemies, optional events and phases have different coverage. [Boss-by-boss results](by-dungeon.md) · [Roster decisions and source IDs](bosses.tsv) · [Item-by-item evidence](drops.tsv)

| What appears in Aeternum | Boss–item links | Evidence |
| --- | ---: | --- |
| Boss drops shown immediately | 510 | A player recorded the item on this NPC and a dungeon reference lists it for the boss or its encounter. |
| Other recorded drops | 84 | A player recorded the item on the NPC. These include shared recipes and repeated live rare equipment drops. |
| Encounter rolls | 29 | The game associated a group loot roll with a matching completed encounter. The individual corpse remains unverified. |
| Guide-listed drops | 1,067 | A Forever guide lists the item. The audit found no accepted direct or matching encounter record. |

181 of the 302 entries have at least one displayed item recorded on the NPC. Of the 594 displayed corpse links, 52 appear in at least three separately published player-recording datasets. Different recorders can observe the same kill. We withheld 322 of the original links, including generic uncommon BoE world drops with no guide support. The audit treats missing evidence as uncertainty and publishes no drop rates.

## The Deadmines

Rhahk’Zor is NPC **644**, encounter **2741**. The hammer (5187), Rockslicer (872) and Ogre Loincloth (273289) all have Forever corpse observations in EG Link and Forever Scout, plus agreement from All The Things and EzWoW. Everloot also records Rockslicer. The original entries for Buccaneer’s Bracers (14166), Protector’s Gloves plans (251362), Crusader’s Gloves plans (251364) and Filigreed Flame Gown pattern (253906) occur only in the original import among the sources checked. They are withheld from his menu. [Forever Scout’s credited reports](https://guide.wow4ever.se/en/instances/deadmines) · [EG Link build 70862](https://github.com/JIVESCORP/eg-link-output-wowf/blob/c1bf99bc2835bbe1b2dad82fb99f994c0cfffe33/data/wowf/1.60.1.70862/loot.json) · [ATT’s Deadmines catalogue](https://github.com/ATTWoWAddon/AllTheThings/blob/789b0feb395396c181999063b691f854167595c6/.contrib/.db/forever/dungeons%20%26%20raids/the%20deadmines.lua)

The recipes that *do* have player evidence are different. EG Link recorded Veteran’s Chain Shirt (251340) on the corpse, Forever Scout recorded Guard’s Chain Shirt (251341), and Everloot recorded Filigreed Shining Gown (253912). EG Link recorded Filigreed Pristine Gown (253902) as an encounter roll. Sneed and Sneed’s Shredder share one encounter and retain their separate corpse tables. Goblin Woodcarver is an ordinary mob with zone loot and was removed from the boss list. [Item-by-item evidence](drops.tsv) · [Everloot observations](https://github.com/valcheffnet/DropTables/blob/c68b7472291bd790b4b9089ac8753cd9e7d51945/data/imports/everloot.json)

## Boss positions and identities

The reviewed roster has 279 guide positions before corrections. For 161 we could project one or more in-instance EG Link pull positions onto the same coordinate system. Of these, 136 had a median horizontal difference of 35 yards or less. For 77 pins, EzWoW also provided a reference with a usable world transform. Aeternum shows 277 pins before shared encounters are grouped. The other 25 entries remain available from the floor menu. In-instance combat records generally lack a floor ID and height. Pulls can also reflect patrolling enemies, alternative spawns or where players initiated combat. [Original and displayed positions, distances and sample sizes](pins.tsv) · [EG Link position semantics](https://github.com/JIVESCORP/eg-link-output-wowf/blob/c1bf99bc2835bbe1b2dad82fb99f994c0cfffe33/DATASETS.md)

- Rhahk’Zor’s existing pin is **7.9 yards** from the recorded pulls at the median. Five distinct positions across three builds support keeping the pin in that area.
- Five pull positions across four builds form a compact group on Ragefire Chasm’s single floor. Their median distance from Oggleflint’s original pin was **162.7 yards**. The revised pin marks their median location at **56.54%, 38.16%** and is labeled as a recorded pull.
- King Op and Impaan have unverifiable guide placements. Impaan’s single recorded pull was 72.8 yards from the guide pin. Both remain in the boss menu without a fixed skull. Kresh and Lady Anacondra have dispersed pull positions and retain labeled estimates. [Route author’s placement notes](https://github.com/Checkov23/ForeverDungeonRoutes/blob/86fce2408d45e3240d7a798d5a0fc182a7c9e0f2/ForeverDungeonRoutes/Data/DefaultRoutes.lua)
- The Drowned City now includes Primeval Elemental and uses NPC **260243** for Min’loth’s logged encounter. ATT also names 260274 as a variant. Encounter-level guide lists for multi-NPC encounters stay distinct from loot observed on an individual NPC. The Shaper’s Terrace roster now includes Ravasaur Hunters, Cinder, Snowtalon and King Op. [The Drowned City catalogue](https://github.com/ATTWoWAddon/AllTheThings/blob/789b0feb395396c181999063b691f854167595c6/.contrib/.db/forever/dungeons%20%26%20raids/the%20drowned%20city.lua) · [EG Link encounters](https://github.com/JIVESCORP/eg-link-output-wowf/tree/c1bf99bc2835bbe1b2dad82fb99f994c0cfffe33/data/wowf)
- In the Sunken Temple, the combat log records Avatar of Hakkar as NPC **8440**. The old roster used 8443, a variant grouped with 8440 by ATT. The new menu uses the observed NPC and keeps its corpse records distinct from group references. Across the complete roster, 187 NPC IDs also have named combat sightings inside the expected instance. [NPC names, alternate IDs and observed instance IDs](identities.tsv)
- Uldaman’s regular Stone Keepers were removed from the boss menu. Ancient Stone Keeper retains its own entry. Four Scourge Invasion bosses retain an event label because their availability on live Forever remains unverified. Zin’aka is kept in the research table as a candidate. EzWoW describes it as an optional elite beyond Min’loth. [Uldaman guide](https://azeroth.wiki/forever/dungeons/uldaman) · [EzWoW dungeon data](https://github.com/ezwow-addons/EzWoW-DungeonRouteGuide/blob/b81ba9ce16c494d02a7fc518e716cc34da19592c/Data/DungeonData.lua)

## Reading the evidence

Each row in `drops.tsv` identifies the dungeon, NPC, item ID, display decision and supporting datasets. `withheld` includes unsupported original links, ordinary incidental drops such as food, and records for omitted NPCs. The curated menu includes recorded recipes, original named items, guide-listed items and relevant equipment observed by multiple recorders. A client item record confirms its name and ID only.

| Source tag | What was counted |
| --- | --- |
| EG-corpse, EG-roll | Efficient Games’ public Forever 1.60.1 data across nine live builds, 70790–71139. Corpse observations require a positive, attributable quantity. Skinning, containers and shared-only slots are excluded. Encounter rolls require the matching build’s encounter, map, NPC and an unambiguous roster entry. Both tags represent one recorder. |
| Everloot | Post-launch original corpus, preserved separately in the Drop Tables import. Only creature loot buckets are used. |
| DropTables | Direct submissions from the exporting install dated November 18–27. The date identifies the upload. Individual kills are undated. Repeated sightings count once as evidence. Forwarded copies and the combined shared database are excluded. |
| Scout | The named player-credit rows on Forever Scout’s dungeon pages. Its EG Link, OneForAll and Classic fallback rows are excluded. The capture stores NPC and item IDs and the digest of each public page. |
| ATT, EzWoW | Camelot and Forever dungeon catalogues. Directly listed items, encounter groups and ATT zone drops have separate tags. A group list cannot prove that each member dropped each item. Guide agreement can reflect common upstream research. |
| Norgannon, FDR | The shipped 0.5.2 baseline and Forever Dungeon Routes. Mirrored NPC and item indexes count once. FDR also supplies route floors and client-derived encounter IDs. Some of its positions and EzWoW’s positions share Classic ancestry. |

The audit applies the known loot-change cutoffs for Obsidian Sentinel, Vitrix, Snowtalon and Cinder. A build that straddles a relevant cutoff contributes no new EG loot evidence for that NPC. Undated reports for those bosses are excluded unless the upstream import applied the matching cutoff. Entries and rates from Classic, beta, other client products, and consolidated copies of the same logs cannot establish a live Forever drop. [Blizzard hotfixes](https://news.blizzard.com/en-us/article/24315281) · [Drop Tables reset list](https://github.com/valcheffnet/DropTables/blob/c68b7472291bd790b4b9089ac8753cd9e7d51945/data/loot-resets.json) · [Source credits and licenses](../../licenses/ForeverBossData-NOTICE.md)

## Reproduce

The normal addon build reads the committed evidence tables offline. To regenerate the audit, use Python 3.9+, LuaJIT or Lua 5.1, curl, the pinned NorgannonDB and Forever Dungeon Routes Git checkouts documented in the project data sources, and the two original Lua snapshots from Aeternum v0.5.2. The commands below write to a temporary directory. The historical Scout observation snapshot is committed separately because the public pages change. [Input checksums](inputs.tsv) · [Scout snapshot](forever-scout.tsv) · [Project data build](../../DATA_SOURCES.md)

```sh
audit_dir=$(mktemp -d)
mkdir "$audit_dir/baseline"
git archive v0.5.2 Data.lua FloorData.lua | tar -x -C "$audit_dir/baseline"
python3 tools/fetch_boss_sources.py "$audit_dir/sources"
python3 tools/audit_bosses.py "$audit_dir/sources" /path/to/NorgannonDB /path/to/ForeverDungeonRoutes "$audit_dir/baseline" --out "$audit_dir/result"
for report in bosses.tsv drops.tsv pins.tsv pin-review.tsv identities.tsv unmatched-encounters.tsv by-dungeon.md; do
    diff -q "docs/boss-audit/$report" "$audit_dir/result/$report"
done
```
