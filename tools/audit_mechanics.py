"""Match dungeon boss spells to Forever observations, independent references and client spell data."""
import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
from collections import defaultdict
from pathlib import Path

from fetch_boss_sources import verify_client_exports
from import_classic_training import EXPECTED_SHA256, extract

ROOT = Path(__file__).resolve().parents[1]
HASHES = {
    "Abilities.lua": "1dcca7b0bb2f46c4e1655c541af86f414b9a23b4ed4e492d25eea3f813f0fb78",
    "Tips.lua": "45aaee43a316811ddf0f11cff6a65a1b9d41432aa50bffc80e847df6b28f43e0",
}
# These spells have no English tooltip string. Verify their exact summon or
# resurrection effect against the client before including the encounter summary.
TEXTLESS_SPELL_NOTES = {
    5141: (28, 643),  # Eject Sneed summons NPC 643 (Sneed).
    5200: (28, 636),  # VanCleef's Allies summons NPC 636 (Defias Blackguard).
    9232: (67, 0),    # Scarlet Resurrection.
}
# These guide assignments lack a matching recorded cast. The build's spell descriptions
# support the instructions for the aura. Keep them in a separate reference list in-game.
GUIDE_SPELLS = {
    14686: {16838, 17105, 22743, 429688},  # Lady Falther'ess
    14695: {7964, 11972, 16496, 21390},  # Lord Blackwood
    246931: {1303458},  # Mana Wraith: Reflection Field
    253201: {1294313},  # Titanosaur: Terrifying Roar
    257016: {3583, 1271761},  # Katerina: Deadly Poison and Grievous Garrote
    260468: {1291712},  # Braxton: Head Smash
    261809: {1290463, 1290464, 1291274, 1291380},  # Nanaya: Slam, Screech and crystal attacks
    261812: {6535, 8078, 12553, 1310513},  # Thunderhoof
    261813: {3604, 1310365},  # Venomridge
    261974: {1310251, 1310267, 1310512},  # Cinder
    262081: {15588, 1310513},  # Bolt
    262127: {1287872, 1287876, 1287886},  # Direhorn Matriarch
    262297: {1310354, 1310514},  # Snowtalon
    272561: {1312869, 1312870},  # Vitrix
}
# A magic category on a damage spell does not imply an aura players can remove.
# Only name positive/negative Magic auras whose effect and target are established.
HELPFUL_MAGIC = {184, 2601, 6077, 6742, 7948, 8362, 8365, 9616, 12040, 12544, 12550,
                 13787, 15041, 15044, 15507, 16170, 17139, 18100, 21049, 22128, 22187,
                 22710, 27688, 27689, 1303264}
HARMFUL_MAGIC = {122, 246, 770, 865, 2767, 7964, 8988, 9034, 10893, 11639, 12528,
                 12674, 12742, 12747, 13323, 13747, 14032, 14907, 15531, 15532, 15654,
                 16838, 17146, 18327, 18376, 19974, 20800, 1240688, 1303350, 1303598, 1310354}


def verify(path, expected):
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f"Wrong source revision or client build: {path}")


def table(path, delimiter=","):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter=delimiter))


def spell_notes(doc, db2, spell_ids):
    text_ids = {int(row["ID"]) for row in table(db2 / "Spell.csv")
                if row["Description_lang"].strip() or row["AuraDescription_lang"].strip()}
    with (db2 / "SpellEffect.csv").open(encoding="utf-8-sig", newline="") as stream:
        valid_effects = {int(row["SpellID"]) for row in csv.DictReader(stream)
                         if row["DifficultyID"] == "0" and TEXTLESS_SPELL_NOTES.get(int(row["SpellID"])) ==
                         (int(row["Effect"]), int(row["EffectMiscValue_0"]))}
    notes = {}
    for row in table(doc / "mechanics-spell-notes.tsv", "\t"):
        spell_id, summary = int(row["spell_id"]), row["summary"].strip()
        if (spell_id not in spell_ids or spell_id in notes or not summary or
                re.search(r"[$|\x00-\x1f]", summary)):
            raise ValueError(f"Invalid or duplicate spell tooltip summary: {spell_id}")
        if spell_id not in text_ids and spell_id not in valid_effects:
            raise ValueError(f"Spell tooltip summary has no client text or reviewed effect: {spell_id}")
        notes[spell_id] = summary
    return notes


def classic_spells(database, roster):
    """Explicit spell lists and EventAI cast actions, never a spell inferred from an NPC name."""
    verify(database, EXPECTED_SHA256)
    schema = {"creature_template": ("Entry", "SpellList"), "creature_spell_list": ("Id", "SpellId"),
              "creature_template_spells": ("entry", *(f"spell{i}" for i in range(1, 11))),
              "creature_ai_scripts": ("creature_id", *(f"action{i}_{field}" for i in (1, 2, 3)
                                                      for field in ("type", "param1")))}
    lists, links, spells = defaultdict(set), {}, defaultdict(set)
    for source, fields in extract(database, schema):
        key, *values = map(int, fields)
        if source == "creature_spell_list":
            if values[0] > 0:
                lists[key].add(values[0])
        elif key in roster:
            if source == "creature_template":
                links[key] = values[0]
            elif source == "creature_template_spells":
                spells[key].update(v for v in values if v > 0)
            else:
                spells[key].update(spell for action, spell in zip(values[::2], values[1::2]) if action == 11 and spell > 0)
    for npc, list_id in links.items():
        if list_id:
            spells[npc].update(lists[list_id])
    return spells


def observations(cache, inputs, roster, names):
    casts = defaultdict(set)
    builds = defaultdict(set)
    for row in inputs:
        if row["dataset"] != "eg-link-output-wowf" or not row["path"].endswith("/creatures.json"):
            continue
        path = cache / row["dataset"] / row["path"]
        verify(path, row["sha256"])
        for npc, data in json.loads(path.read_bytes())["creatures"].items():
            npc = int(npc)
            if npc not in roster:
                continue
            combat = data.get("combatLog", {})
            maps = {p.get("map") for p in combat.get("positions", [])}
            if maps != {int(roster[npc]["expected_map"])}:
                continue  # Cast counts are aggregated per NPC in this build, not per pull.
            for spell, cast in combat.get("casts", {}).items():
                spell = int(spell)
                if cast.get("starts", 0) + cast.get("successes", 0) > 0 and names.get(spell) == cast.get("name"):
                    casts[npc].add(spell)
                    builds[npc].add(path.parent.name)
    return casts, builds


def aura(spell, category):
    dispel, mechanic = category
    control = {1: "charm", 5: "fear", 10: "sleep"}.get(mechanic)
    kind = {2: "curse", 3: "disease", 4: "poison", 9: "enrage"}.get(dispel)
    if dispel == 1:
        if spell in HELPFUL_MAGIC:
            kind = "magicBuff"
        elif control or spell in HARMFUL_MAGIC:
            kind = "magic"
    if mechanic == 15:
        kind = "bleed"
    return kind, control


def ids(numbers):
    return ",".join(map(str, sorted(numbers)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for arg in ("cache", "journal", "db2", "classic", "output"):
        ap.add_argument(arg, type=Path)
    args = ap.parse_args()
    doc = ROOT / "docs/boss-audit"
    helper = str(ROOT / "tools/boss_audit_sources.lua")
    lua_bin = os.environ.get("LUA", "luajit")
    bosses = subprocess.check_output([lua_bin, helper, "roster", str(ROOT / "Data.lua"), str(ROOT / "FloorData.lua")],
                                     text=True)
    roster = {}
    for line in bosses.splitlines():
        row = line.split("\t")
        if row[0] == "boss":
            roster[int(row[4])] = {"dungeon": row[1], "expected_map": row[3], "name": row[5]}
    inputs = table(doc / "inputs.tsv", "\t")
    field_guides = {}
    for row in table(doc / "mechanics-guides.tsv", "\t"):
        for npc in map(int, row["boss_npc_ids"].split(",")):
            if npc not in roster or npc in field_guides:
                raise ValueError(f"Unknown or duplicate boss in field guide index: {npc}")
            field_guides[npc] = row["guide_url"]
    encounters = {}
    for row in table(doc / "mechanics-database.tsv", "\t"):
        npc = int(row["npc"])
        if npc not in roster or npc in encounters:
            raise ValueError(f"Unknown or duplicate NPC in encounter index: {npc}")
        encounters[npc] = (row["encounter_url"], {int(i) for i in row["single_npc_spell_ids"].split(",") if i})
    for name, digest in HASHES.items():
        verify(args.journal / name, digest)
    verify_client_exports(args.db2)
    names = {int(r["ID"]): r["Name_lang"] for r in table(args.db2 / "SpellName.csv")}
    categories = {int(r["SpellID"]): (int(r["DispelType"]), int(r["Mechanic"]))
                  for r in table(args.db2 / "SpellCategories.csv") if r["DifficultyID"] == "0"}
    icons = {int(r["SpellID"]): int(r["SpellIconFileDataID"]) for r in table(args.db2 / "SpellMisc.csv")
             if r["DifficultyID"] == "0"}
    live, builds = observations(args.cache, inputs, roster, names)
    classic = classic_spells(args.classic, roster)
    journal = {int(n): set(map(int, re.findall(r"\d+", spells))) for n, spells in
               re.findall(r"\[(\d+)\]\s*=\s*\{([^}]*)\}", (args.journal / "Abilities.lua").read_text())}
    tips = {int(n) for n in re.findall(r"\[(\d+)\]\s*=", (args.journal / "Tips.lua").read_text())}
    source = next(r for r in inputs if r["dataset"] == "EzWoW-DungeonRouteGuide" and r["path"].endswith("/DungeonData.lua"))
    route = args.cache / source["dataset"] / source["path"]
    verify(route, source["sha256"])
    routes = subprocess.check_output([lua_bin, helper, "ez-mechanics", str(route)], text=True)
    guide = {int(line.split("\t")[2]) for line in routes.splitlines()}

    args.output.mkdir(exist_ok=True, parents=True)
    lua = ["-- Generated from Forever combat logs and spell references. See docs/boss-audit/mechanics.md.",
           "local _, addon = ...", "", "addon.bossCasts = {"]
    used = set()
    with (args.output / "mechanics.tsv").open("w", newline="", encoding="utf-8") as stream:
        rows = csv.writer(stream, delimiter="\t", lineterminator="\n")
        rows.writerow(["dungeon", "npc", "boss", "observed_in_builds", "observed_spell_ids", "reference_spell_ids",
                       "journal_spell_ids", "classic_spell_ids", "ezwow_note", "naowh_note", "field_guide", "azeroth_db"])
        for npc, boss in sorted(roster.items(), key=lambda pair: (pair[1]["dungeon"], pair[0])):
            observed = live[npc]
            guide_spells = journal.get(npc, set())
            reviewed = GUIDE_SPELLS.get(npc, set())
            if not reviewed <= guide_spells:
                raise ValueError(f"Recheck journal references for {npc}")
            encounter_url, encounter_spells = encounters.get(npc, ("", set()))
            # A group encounter can include adds. The Vault guide explicitly assigns these
            # two spells to Doomgrip, and his own Classic spell list corroborates both.
            if npc == 9476:
                encounter_spells = {11971, 15504}
            matched = (guide_spells & classic[npc]) | (encounter_spells & (guide_spells | classic[npc]))
            reference = ((matched | reviewed) & names.keys()) - observed
            rows.writerow([boss["dungeon"], npc, boss["name"], ",".join(sorted(builds[npc])), ids(observed), ids(reference),
                           ids(guide_spells), ids(classic[npc]), int(npc in guide), int(npc in tips),
                           field_guides.get(npc, ""), encounter_url])
            if observed or reference:
                sections = [f"{key}={{{ids(spells)}}}" for key, spells in (("live", observed), ("reference", reference))
                            if spells]
                lua.append(f"    [{npc}] = {{" + ", ".join(sections) + "},")
                used.update(observed | reference)
    notes = spell_notes(doc, args.db2, used)
    lua.extend(["}", "", "-- Spell name, icon, aura type, crowd-control mechanic, and optional tooltip summary.",
                "addon.castSpells = {"])
    for spell in sorted(used):
        kind, control = aura(spell, categories.get(spell, (0, 0)))
        values = [json.dumps(names[spell], ensure_ascii=False), str(icons.get(spell, 0))]
        if kind or control:
            values.append(json.dumps(kind) if kind else "nil")
        if control:
            values.append(json.dumps(control))
        prefix = f"    [{spell}] = {{" + ", ".join(values)
        if spell in notes:
            field = "description = " + json.dumps(notes[spell], ensure_ascii=False)
            if len(prefix) + len(field) + 4 > 120:
                lua.extend([prefix + ",", "        " + field + ",", "    },"])
            else:
                lua.append(prefix + ", " + field + "},")
        else:
            lua.append(prefix + "},")
    lua.append("}")
    (args.output / "BossCasts.lua").write_text("\n".join(lua) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
