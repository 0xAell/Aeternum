"""Extract the class and skill requirements of audited Forever boss items, build 71139."""
import argparse
import csv
import hashlib
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "docs/boss-audit/item-requirements.tsv"
FIELDS = ["item", "kind", "subclass", "slot", "classes", "skill", "rank", "ability", "quest", "teaches"]
ITEM, SPARSE, LINK, EFFECT = 0x50238EC2, 0x919BE54E, 0x00CB674F, 0x4002A5B1
EXPORT_HASHES = {
    "Item": "0f3a75bdd765a2138181e771f68a93be8a0f5124468164c40615b1e664582744",
    "ItemSparse": "04ef3ef49aed8f98b0ffe357f980b08afd6e32b62ef592afe03e620ab95e6648",
    "ItemXItemEffect": "34545365043a710f0fc9a312fc547dec0162ac5b9ee97d5c58be1ff918bb7fd8",
    "ItemEffect": "91cb8d9389de3088660965501c1ca720050abd48655e3369efb55565dcee5b99",
}
WEAPONS = {0: 44, 1: 172, 2: 45, 3: 46, 4: 54, 5: 160, 6: 229, 7: 43,
           8: 55, 10: 136, 13: 473, 15: 173, 16: 176, 18: 226, 19: 228}
ARMOR = {1: 415, 2: 414, 3: 413, 4: 293, 6: 433}
RELIC_CLASSES = {7: 2, 8: 1024, 9: 64}  # libram, idol, totem
PLAYABLE_CLASSES = 1503


def audited_ids():
    with (ROOT / "docs/boss-audit/drops.tsv").open() as source:
        return {int(row["item"]) for row in csv.DictReader(source, delimiter="\t") if row["display"] != "withheld"}


def db2(folder, name, fields):
    path = folder / (name + ".csv")
    if hashlib.sha256(path.read_bytes()).hexdigest() != EXPORT_HASHES[name]:
        raise ValueError(f"Unexpected {name} CSV. Use the pinned build 71139 export.")
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return {int(row["ID"]): tuple(int(row[f]) for f in fields) for row in csv.DictReader(stream)}


def hotfixes(path):
    raw = path.read_bytes()
    if len(raw) < 44 or struct.unpack_from("<4sII", raw) != (b"XFTH", 9, 71139):
        raise ValueError("Expected a version 9 Forever build 71139 DB cache")
    latest = {}
    offset = 44
    while offset < len(raw):
        magic, _, push, _, table, record, size, status = struct.unpack_from("<4siiIIIiB3x", raw, offset)
        offset += 32
        if magic != b"XFTH" or size < 0 or offset + size > len(raw):
            raise ValueError("Invalid hotfix record at offset %d" % (offset - 32))
        key = table, record
        if table in (ITEM, SPARSE, LINK, EFFECT) and (key not in latest or push >= latest[key][0]):
            latest[key] = push, status, raw[offset:offset + size]
        offset += size
    return latest


def decode(table, payload):
    if table == ITEM:
        kind, subtype, _, slot = struct.unpack_from("<iBBb", payload)
        return kind, subtype, slot
    if table == LINK:
        return struct.unpack("<ii", payload)
    if table == EFFECT:
        return payload[1], struct.unpack_from("<i", payload, 14)[0]
    # ItemSparse layout 6FCC3191: five localized strings followed by fixed-width fields.
    fixed = payload.split(b"\0", 5)[-1]
    if len(fixed) != 302:
        raise ValueError("Unexpected build 71139 ItemSparse record size")
    rank, skill, _, classes = struct.unpack_from("<HHHh", fixed, 276)
    return classes, skill, rank, struct.unpack_from("<I", fixed, 168)[0], struct.unpack_from("<i", fixed, 24)[0]


def snapshot(folder, cache, output):
    ids = audited_ids()
    tables = {
        ITEM: db2(folder, "Item", ["ClassID", "SubclassID", "InventoryType"]),
        SPARSE: db2(folder, "ItemSparse", ["AllowableClass", "RequiredSkill", "RequiredSkillRank",
                                          "RequiredAbility", "StartQuestID"]),
        LINK: db2(folder, "ItemXItemEffect", ["ItemEffectID", "ItemID"]),
        EFFECT: db2(folder, "ItemEffect", ["TriggerType", "SpellID"]),
    }
    for (table, record), (_, status, payload) in hotfixes(cache).items():
        if status == 1:
            tables[table][record] = decode(table, payload)
        elif status in (2, 4):
            tables[table].pop(record, None)
        elif status != 3:  # Removed hotfix restores the shipped row.
            raise ValueError("Unknown hotfix status %d" % status)
    teaches = {}
    for effect, item in tables[LINK].values():
        trigger, spell = tables[EFFECT].get(effect, (None, None))
        if item in ids and trigger == 6:  # LEARN_SPELL identifies the spell taught by this item.
            if item in teaches and teaches[item] != spell:
                raise ValueError("Multiple learning spells on item %d" % item)
            teaches[item] = spell
    with output.open("w", newline="") as out:
        writer = csv.writer(out, delimiter="\t", lineterminator="\n")
        writer.writerow(FIELDS)
        for item in sorted(ids):
            basic = tables[ITEM].get(item, (None,) * 3)
            details = tables[SPARSE].get(item, (None,) * 5)
            writer.writerow((item, *basic, *details, teaches.get(item, 0)))


def requirements(row):
    if not row["classes"] or not row["kind"]:
        return None
    kind, sub, slot, classes, skill, rank, ability, quest, teaches = (int(row[k]) for k in FIELDS[1:])
    classes &= PLAYABLE_CLASSES
    if kind == 4 and sub in RELIC_CLASSES:
        classes &= RELIC_CLASSES[sub]
    rule = {}
    if classes != PLAYABLE_CLASSES:
        rule["classes"] = classes
    if kind == 2:
        rule["proficiency"] = WEAPONS[sub]
        if slot == 22:  # Off-hand-only weapon
            rule["dualWield"] = True
    elif kind == 4 and sub in ARMOR and slot in (1, 3, 5, 6, 7, 8, 9, 10, 14, 20):
        if sub != 1:  # All Forever classes wear cloth.
            rule["proficiency"] = ARMOR[sub]
    elif kind in (6, 11):  # Ammunition and its containers
        if sub not in (2, 3):
            raise ValueError("Unknown ammunition subclass %d" % sub)
        if sub == 2:
            rule["arrows"] = True  # Bows and crossbows both use arrows.
        else:
            rule["proficiency"] = 46
    if skill:
        rule.update(skill=skill, rank=max(1, rank))
    if ability:
        rule["ability"] = ability
    if teaches:
        rule["teaches"] = teaches
    if quest:
        rule["startsQuest"] = quest
    return tuple(rule.items())


def generate(output):
    ids = set()
    groups = defaultdict(list)
    with SNAPSHOT.open() as source:
        for row in csv.DictReader(source, delimiter="\t"):
            item = int(row["item"])
            if item in ids:
                raise ValueError(f"Duplicate requirement record for {item}")
            ids.add(item)
            groups[requirements(row)].append(item)
    if ids != audited_ids():
        raise ValueError("Item requirements must cover every audited boss drop")
    lines = ["-- Generated by tools/import_loot_requirements.py for WoW Forever 1.60.1.71139.",
             "-- Each group shares its requirements. False means the Forever item details are unverified.",
             "local _, addon = ...", "local byItem = {}", "addon.lootRules = byItem", "",
             "local function items(rule, ids)", "    for _, id in ipairs(ids) do byItem[id] = rule end", "end", ""]
    for rule, items in groups.items():
        fields = [] if rule is None else [f"{k}={'true' if v is True else v}" for k, v in rule]
        label = "false" if rule is None else "{" + ", ".join(fields) + "}"
        lines.append("items(" + label + ", {")
        for i in range(0, len(items), 12):
            lines.append("    " + ", ".join(map(str, items[i:i + 12])) + ",")
        lines.append("})")
    output.write_text("\n".join(lines) + "\n")
    print(f"{len(ids)} items, {len(groups.get(None, []))} with unverified requirements")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_subparsers(dest="mode", required=True)
    extract = modes.add_parser("snapshot", help="extract a numeric snapshot from Forever client data")
    extract.add_argument("db2_folder", type=Path)
    extract.add_argument("hotfix_cache", type=Path)
    extract.add_argument("output", type=Path)
    build = modes.add_parser("build", help="compile the committed snapshot into the addon's Lua database")
    build.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.mode == "snapshot":
        snapshot(args.db2_folder, args.hotfix_cache, args.output)
    else:
        generate(args.output)
