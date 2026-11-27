# Forever trainer records

The map has 561 distinct trainer NPCs. In this snapshot, 210 have trainer windows recorded on live Forever builds, 24 more have an undated Zephras trainer window, and 14 more have a usable beta window. Earlier NorgannonDB and Classic references cover another 274. Altogether 522 trainers have a catalogue before the character visits. The other 39 need an in-game observation.

| Record | Offers | Evidence |
| --- | ---: | --- |
| Live Forever | 10,007 | The NPC and spell occur together in a live EG Link build or a dated live Zephras service row. Both collectors saw 771 of these offers. |
| Build unreported | 227 | Zephras recorded the trainer and spell together. The service row has no build and the NPC page covers a later or unknown build. |
| Beta | 423 | A prelaunch visit recorded the trainer and spell together. A live trainer of the same class, profession or weapon-trainer role also teaches the spell. |

Each row in [offers.tsv](offers.tsv) is one NPC and learned spell ID with its level, required skill and rank, copper price, price source and observation source. The 10,657 rows cover 1,743 distinct spells. [spells.tsv](spells.tsv) contains these spell names, ranks and character restrictions, plus 68 prerequisite spells and talents. The build packs offers by trainer so the addon only decodes the selected trainer’s rows.

## Sources

- EG Link contributors recorded trainer services across nine live Forever builds from 70790 through 71139. The observation identifies the trainer, learned spell, positive level or skill requirements where visible, and prices by standing. A service the player has already learned can report level zero. Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0. [Pinned exports](https://github.com/JIVESCORP/eg-link-output-wowf/tree/c1bf99bc2835bbe1b2dad82fb99f994c0cfffe33/data) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- Zephras Collector contributors record the services shown to players at a particular NPC. The snapshot checked the **Teaches** table for each mapped NPC. Where the service has no recorded build and the NPC was last seen on a prelaunch build, the extractor classifies it as beta. An undated row at an NPC seen on live can fill a catalogue, with the build uncertainty shown in the tooltip. For example, Aedi Thriceforged’s 23 recorded services include Sharpening Wheel at Blacksmithing 20 for 1 silver. [Aedi Thriceforged](https://zephras.com/forever/enUS/npc/251913/) · [Shari Stilwell](https://zephras.com/forever/enUS/npc/246152/)
- What’s Training? provides current class and profession requirements, listed prices and spell prerequisites. Its nine Camelot class files and twelve Camelot recipe files are used only after matching a trainer to a spell. [Pinned guide](https://github.com/fusionpit/WhatsTraining/tree/59763c2105428ccf99926919824c23d850bfbaa4) · [MIT license](../../licenses/WhatsTraining-MIT.txt)
- Blizzard’s Forever build 1.60.1.71139 supplies the English names, ranks and teaching effects. An unambiguous teaching service is resolved to the learned spell unless it is itself a player ability. The current Assassination talent tree also identifies Mutilate as spell 399956, which the two trained ranks require. The guide’s older prerequisite 1310706 is absent from this build. Zephras publishes the arrangement of its downloadable data under CC BY 4.0. [Spell names](https://wago.tools/db2/SpellName/csv?build=1.60.1.71139) · [Spell ranks](https://wago.tools/db2/Spell/csv?build=1.60.1.71139) · [Teaching effects](https://wago.tools/db2/SpellEffect/csv?build=1.60.1.71139) · [Skill lines](https://wago.tools/db2/SkillLineAbility/csv?build=1.60.1.71139) · [Forever talent export](https://zephras.com/data/forever/enUS/talents/1.60.1.71139.json) · [Zephras data credits](https://zephras.com/data/)

## Prices

A neutral EG Link quote takes precedence. If another recorded standing matches the guide’s listed price, the snapshot can display that amount as a guide price. Otherwise it retains the recorded amount together with its standing. A Zephras quote with unknown standing or a listed guide price can fill a missing price. Bartering quotes and historical beta prices are excluded. A missing amount stays unknown unless there is another price for the same NPC and spell in the bundled catalogues. The character’s own quote takes priority after a visit.

## Regeneration

Rebuild the shipped Lua file from the checked-in records with Python 3. This works offline.

```sh
python3 tools/forever_trainers.py build ForeverTraining.lua
```

To refresh the records, prepare an input directory with the following files. The extractor checks the EG Link, What’s Training? and client file hashes. Zephras pages can change, so review changes to the normalized tables before replacing the snapshot.

- Save the EG Link files at `data/PRODUCT/1.60.1.BUILD/trainers.json` as `trainers-BUILD.json` for live `wowf` builds, `preview-BUILD.json` for prelaunch `wowf` builds, and `beta-BUILD.json` for `wow_classic_beta`. The exact builds are listed at the top of [the extractor](../../tools/forever_trainers.py).
- Place the pinned What’s Training? checkout in `WhatsTraining/` and the four linked client exports alongside it as `SpellName.csv`, `Spell.csv`, `SpellEffect.csv` and `SkillLineAbility.csv`.
- Save each mapped trainer’s English Zephras NPC page as `zephras-NPCID.html`, including the site’s actual 404 page for a missing NPC. A connection error or another page is rejected.

```sh
python3 tools/forever_trainers.py snapshot /path/to/trainer-inputs
python3 tools/forever_trainers.py build ForeverTraining.lua
```
