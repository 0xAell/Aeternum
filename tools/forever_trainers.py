"""Snapshot public Forever trainer observations, or build the offline addon database."""
import argparse
import csv
import hashlib
import html
import json
import os
import re
import subprocess
from collections import defaultdict
from io import StringIO
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SNAP = ROOT / "docs/trainer-data"
BUILDS = (70790, 70840, 70862, 70888, 70938, 70959, 71037, 71091, 71139)
BETA = (70009, 70124, 70170, 70205, 70235, 70245, 70291, 70334, 70338, 70374, 70425, 70450, 70532)
PREVIEW = (70205, 70291, 70334, 70338, 70374, 70425, 70450, 70532)
TABLES = {
    "SpellName": "02128e7f52b8741d2bd144f273cad5e29da384636096087f567db8734a939934",
    "Spell": "cc8e495092e5030ccfc2719dd052948cb7e6debca79584260abd560582b855fc",
    "SpellEffect": "970158fb0ea34695b1d59837a8a612d72b76592f941324372095e1566ea461f2",
    "SkillLineAbility": "ecdc96fca011a72281802b0a10e6e36dbcc9c072c2dfae93b5ceaa9f31aa74e7",
}
SKILLS = {"Poisons": 40, "First Aid": 129, "Blacksmithing": 164, "Leatherworking": 165, "Alchemy": 171,
          "Herbalism": 182, "Cooking": 185, "Mining": 186, "Tailoring": 197, "Engineering": 202,
          "Enchanting": 333, "Fishing": 356, "Skinning": 393, "요리": 185, "연금술": 171, "약초채집": 182, "낚시": 356}
SPELL_FIELDS = ("spell", "name", "rank", "race", "faction", "requires", "service_ids")
OFFER_FIELDS = ("npc", "spell", "level", "skill", "skill_rank", "copper", "price_basis", "source")
SOURCES = {"EG": 1, "Zephras": 2, "both": 3, "EG-beta": 4, "Zephras-undated": 5, "Zephras-beta": 6, "both-beta": 7}
PRICES = {"": "", "reported": 9, "guide": 10, **{str(i): i for i in range(4, 9)}}


def db2(folder, name):
    path = folder / (name + ".csv")
    if hashlib.sha256(path.read_bytes()).hexdigest() != TABLES[name]:
        raise ValueError(f"Unexpected build 71139 {name} export")
    with path.open(encoding="utf-8-sig") as stream:
        yield from csv.DictReader(stream)


def mapped_trainers():
    section = (ROOT / "Data.lua").read_text().split("    trainers = {\n", 1)[1].split("\n    },", 1)[0]
    roles = {}
    for line in section.splitlines():
        npc = int(re.search(r"\bid=(\d+)", line)[1])
        kind = re.search(r'\bkind="([^"]+)"', line)[1]
        token, skill = re.search(r'\bclassToken="([^"]+)"', line), re.search(r"\bskillID=(\d+)", line)
        roles[npc] = (kind, token[1] if token else "", skill[1] if skill else "")
    return roles


def prior_catalogues():
    norg = (ROOT / "Data.lua").read_text().split("    offers = {\n", 1)[1].split("\n    },", 1)[0]
    classic = (ROOT / "ClassicTraining.lua").read_text().split("}, trainers = {\n", 1)[1]
    return {int(n) for n in re.findall(r"^\s*\[(\d+)\]\s*=", norg + "\n" + classic, re.M)}


def verify_group(folder, paths, expected):
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(path.relative_to(folder).as_posix().encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    if digest.hexdigest() != expected:
        raise ValueError(f"Trainer source files differ from the pinned revision in {folder}")


def read_eg(folder, mapped, beta=False):
    if beta:
        inputs = [(b, "wow_classic_beta", folder / f"beta-{b}.json") for b in BETA]
        inputs.extend((b, "wowf", folder / f"preview-{b}.json") for b in PREVIEW)
        expected = "805c13a1b9bee40ed68d032828972847e068ffa35d32e023989d3dad76feb367"
    else:
        inputs = [(b, "wowf", folder / f"trainers-{b}.json") for b in BUILDS]
        expected = "16aa65d0aab513a26015a4107705ed7a65573147987bfc0178debaa64ae36829"
    verify_group(folder, (path for _, _, path in inputs), expected)
    offers = {}
    for build, product, path in sorted(inputs):
        doc = json.loads(path.read_text())
        meta = doc["meta"]
        if meta["product"] != product or meta["clientBuild"] != f"1.60.1.{build}":
            raise ValueError(f"Wrong trainer snapshot for build {build}")
        for npc, trainer in doc["trainers"].items():
            if int(npc) not in mapped:
                continue
            for key, service in trainer["services"].items():
                spell = int(key)
                if spell != service["spellId"]:
                    raise ValueError("Mismatched trainer service ID")
                row = offers.setdefault((int(npc), spell), {"prices": {}})
                # A learned service reports level zero. Keep the latest positive requirement.
                if service["level"] > 0:
                    row["level"] = service["level"]
                if service.get("skill") and service["skillRank"] > 0:
                    row["requirement"] = (SKILLS[service["skill"]], service["skillRank"])
                # Each standing has a separate quote. Bartering belongs to a different price schedule.
                for standing, copper in service.get("costs", {}).items():
                    if standing in ("4", "5", "6", "7", "8") and copper > 0:
                        row["prices"][int(standing)] = copper
    return offers


def plain(markup):
    return html.unescape(re.sub(r"<[^>]+>", "", markup)).strip()


def zephras_services(page):
    table = re.search(r'<table id="teaches-table"[^>]*>.*?<tbody>(.*?)</tbody>', page, re.S)
    if not table:
        return
    # A creature's sightings and a trainer service are dated separately. If the
    # page only knows a prelaunch NPC build, treat its undated menu as beta.
    npc_build = re.search(r"Seen on build.{0,140}?1\.60\.1\.(\d+)", page, re.S)
    undated = "beta" if npc_build and int(npc_build[1]) < BUILDS[0] else "undated"
    for attrs, body in re.findall(r'<tr([^>]*)>(.*?)</tr>', table[1], re.S):
        ref = re.search(r'data-tip="spell:(\d+)"', body)
        if not ref:
            continue
        _, needs, price, *seen = re.findall(r'<td>(.*?)</td>', body, re.S)
        build = re.search(r"1\.60\.1\.(\d+)", plain(seen[0])) if seen else None
        period = ("live" if int(build[1]) >= BUILDS[0] else "beta") if build else undated
        cost = re.search(r'data-cost="(\d+)"', attrs)
        row = {}
        if cost and int(cost[1]) > 0 and plain(price):
            row["price"] = int(cost[1])
        for part in plain(needs).split(" · "):
            if part in ("Nothing", ""):
                continue
            match = re.fullmatch(r"(.+) (\d+)", part)
            if not match:
                raise ValueError(f"Unrecognized trainer requirement {part}")
            field, number = match[1], int(match[2])
            if field == "Level":
                row["level"] = number
            else:
                row["requirement"] = (SKILLS[field], number)
        yield int(ref[1]), row, period


def guide_records(folder):
    guide = folder / "WhatsTraining"
    classes = "Druid Hunter Mage Paladin Priest Rogue Shaman Warlock Warrior".split()
    inputs = [guide / "Classes" / "Camelot" / f"{name}.lua" for name in classes]
    inputs.extend((guide / "Crafting/Recipes/Camelot").glob("*.lua"))
    verify_group(guide, inputs, "7c2ae54140eee41e62a13a021f798ace49faf2a8a859dc74f82ccf239fe706c6")
    result = subprocess.run([os.environ.get("LUA", "luajit"), str(ROOT / "tools/trainer_guide.lua"),
                             str(guide)], check=True, capture_output=True, text=True)
    return {int(r["spell"]): r for r in csv.DictReader(StringIO(result.stdout), delimiter="\t")}


def price_quote(eg, zephras, guide):
    prices = eg.get("prices", {})
    listed = int(guide["cost"]) if guide.get("cost") else None
    if 4 in prices:
        return prices[4], "4"
    if listed is not None and listed in prices.values():
        return listed, "guide"
    if prices:
        standing = min(prices)
        return prices[standing], str(standing)
    if "price" in zephras:
        return zephras["price"], "reported"
    if listed is not None:
        return listed, "guide"
    return None, None


def write_tsv(name, fields, rows):
    with (SNAP / name).open("w", encoding="utf-8", newline="") as stream:
        out = csv.writer(stream, delimiter="\t", lineterminator="\n")
        out.writerow(fields)
        out.writerows(rows)


def snapshot(folder):
    mapped = mapped_trainers()
    guide = guide_records(folder)
    eg = read_eg(folder, mapped)
    direct_ids = {spell for _, spell in eg} | guide.keys()
    # Beast Training and other player skills can themselves teach an ability to a second unit.
    direct_ids.update(int(r["Spell"]) for r in db2(folder, "SkillLineAbility"))
    names = {int(r["ID"]): r["Name_lang"].strip() for r in db2(folder, "SpellName")}
    ranks = {int(r["ID"]): r["NameSubtext_lang"].strip() for r in db2(folder, "Spell")}
    taught = defaultdict(set)
    for effect in db2(folder, "SpellEffect"):
        if effect["Effect"] == "36" and int(effect["EffectTriggerSpell"]) > 0:
            taught[int(effect["SpellID"])].add(int(effect["EffectTriggerSpell"]))
    zephras, undated, zephras_beta, aliases = {}, {}, {}, defaultdict(set)
    periods = {"live": zephras, "undated": undated, "beta": zephras_beta}
    for npc in sorted(mapped):
        page = (folder / f"zephras-{npc}.html").read_text()
        if not ("NPC ID" in page and f"/npc/{npc}/" in page) and "Page not found — WoW Forever — Zephras" not in page:
            raise ValueError(f"No valid Zephras response for NPC {npc}")
        for service, row, period in zephras_services(page):
            spell = service
            if service not in direct_ids and service in taught:
                if len(taught[service]) != 1:
                    continue
                spell, = taught[service]
                aliases[spell].add(service)
            if spell in names:
                periods[period][npc, spell] = row
    current = eg.keys() | zephras.keys()
    roles = {(mapped[npc], spell) for npc, spell in current}
    recent = current | undated.keys()
    missing = mapped.keys() - prior_catalogues() - {npc for npc, _ in recent}
    eg_beta = read_eg(folder, missing, beta=True)
    earlier = {pair for pair in eg_beta.keys() | zephras_beta.keys()
               if pair[0] in missing and (mapped[pair[0]], pair[1]) in roles}
    offers, spells = [], {}
    for pair in sorted(recent | earlier):
        npc, spell = pair
        record, ref = eg.get(pair, {}), guide.get(spell, {})
        other = zephras.get(pair, undated.get(pair, {}))
        source = "Zephras" if pair in zephras else "Zephras-undated"
        if pair in eg:
            source = "both" if pair in zephras or pair in undated else "EG"
        old = {}
        if pair in earlier:
            old = {**zephras_beta.get(pair, {}), **eg_beta.get(pair, {})}
            source = "both-beta" if pair in eg_beta and pair in zephras_beta else (
                "EG-beta" if pair in eg_beta else "Zephras-beta")
        level = record.get("level") or other.get("level") or ref.get("level") or old.get("level")
        required = record.get("requirement") or other.get("requirement")
        if not required and ref.get("skill") and ref.get("rank"):
            required = (int(ref["skill"]), int(ref["rank"]))
        if not required:
            required = old.get("requirement")
        cost, basis = price_quote(record, other, ref)
        offers.append((npc, spell, int(level) if level and int(level) > 0 else None,
                       *(required or (None, None)), cost, basis, source))
        # The current Assassination tree grants Mutilate 399956. The guide refers
        # to an obsolete ID on its two trained ranks. See docs/trainer-data/README.md.
        requires = [399956 if n == "1310706" else int(n) for n in (ref.get("requires") or "").split(",") if n]
        spells[spell] = (spell, names[spell], ranks.get(spell, ""), ref.get("race"), ref.get("faction"),
                         ",".join(map(str, requires)), ",".join(str(s) for s in sorted(aliases[spell])))
    # Starting spells and talents can be prerequisites without being sold by any mapped trainer.
    prerequisites = {int(n) for row in spells.values() for n in (row[5] or "").split(",") if n}
    for spell in prerequisites - spells.keys():
        spells[spell] = (spell, names[spell], ranks.get(spell, ""), None, None, None, None)
    SNAP.mkdir(parents=True, exist_ok=True)
    write_tsv("offers.tsv", OFFER_FIELDS, offers)
    write_tsv("spells.tsv", SPELL_FIELDS, (spells[s] for s in sorted(spells)))


def quote(value):
    if "\n" in value or "\r" in value:
        raise ValueError("Multiline trainer record")
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(output):
    aliases, spells, by_npc = {}, {}, defaultdict(dict)
    prerequisites = set()
    with (SNAP / "spells.tsv").open() as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            spell = int(row["spell"])
            fields = [row[key] for key in SPELL_FIELDS[1:-1]]
            if spell in spells or not fields[0] or any("|" in s for s in fields):
                raise ValueError(f"Invalid spell definition {spell}")
            spells[spell] = "|".join(fields)
            prerequisites.update(int(n) for n in row["requires"].split(",") if n)
            for service in filter(None, row["service_ids"].split(",")):
                if int(service) in aliases:
                    raise ValueError(f"Ambiguous service ID {service}")
                aliases[int(service)] = spell
    if prerequisites - spells.keys() or aliases.keys() & spells.keys():
        raise ValueError("Unresolved prerequisite or ambiguous teaching spell")
    mapped = mapped_trainers()
    with (SNAP / "offers.tsv").open() as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            npc, spell = int(row["npc"]), int(row["spell"])
            if npc not in mapped or spell not in spells or spell in by_npc[npc]:
                raise ValueError(f"Invalid trainer assignment {npc}/{spell}")
            if bool(row["copper"]) != bool(row["price_basis"]) or bool(row["skill"]) != bool(row["skill_rank"]):
                raise ValueError(f"Incomplete price or skill requirement for {npc}/{spell}")
            numbers = [int(row[k]) if row[k] else "" for k in OFFER_FIELDS[1:6]]
            by_npc[npc][spell] = ":".join(map(str, [*numbers, PRICES[row["price_basis"]], SOURCES[row["source"]]]))
    with output.open("w", encoding="utf-8") as out:
        out.write("-- Forever trainer observations. Generated by tools/forever_trainers.py. See DATA_SOURCES.md.\n")
        out.write("local _, addon = ...\naddon.foreverTraining = { spells = {\n")
        for spell, details in sorted(spells.items()):
            out.write(f"    [{spell}]={quote(details)},\n")
        out.write("}, serviceSpells = {\n")
        for service, spell in sorted(aliases.items()):
            out.write(f"    [{service}]={spell},\n")
        out.write("}, offers = {\n")
        for npc, services in sorted(by_npc.items()):
            packed = ";".join(services[s] for s in sorted(services))
            out.write(f"    [{npc}]={quote(packed)},\n")
        out.write("}}\n")
    taught = {spell for services in by_npc.values() for spell in services}
    print(f"Forever trainer catalogues: {len(by_npc)} NPCs, {len(taught)} spells, "
          f"{sum(len(v) for v in by_npc.values())} trainer offers")


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    modes = cli.add_subparsers(dest="mode", required=True)
    modes.add_parser("snapshot").add_argument("sources", type=Path)
    modes.add_parser("build").add_argument("output", type=Path)
    args = cli.parse_args()
    if args.mode == "snapshot":
        snapshot(args.sources)
    else:
        build(args.output)
