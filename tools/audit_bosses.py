"""Rebuild the Forever dungeon evidence tables from the pinned sources in docs/boss-audit."""
import argparse
import csv
import hashlib
import json
import math
import os
import re
import statistics
import subprocess
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from tempfile import TemporaryDirectory

from fetch_boss_sources import verify

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "docs/boss-audit"
LUA = os.environ.get("LUA", "luajit")
DIRECT = {"EG-corpse", "Everloot", "DropTables", "Scout"}
GUIDES = {"ATT", "EzWoW"}
GROUP_GUIDES = {"ATT-group", "EzWoW-group"}
EZ_SLUGS = {"dalaran":"city-of-dalaran", "excavation-site":"excavation-site-wetlands",
            "the-drowned-city":"drowned-city", "lower-blackrock-spire":"lbrs", "upper-blackrock-spire":"ubrs",
            "stratholme-main-gate":"stratholme", "stratholme-service-gate":"stratholme", "zul-farrak":"zulfarrak"}
# ATT uses journal instance IDs for older dungeons and map IDs for Forever additions.
ATT_MAP = {63:36, 64:33, 226:389, 227:48, 228:230, 229:229, 230:429, 231:90,
           232:349, 233:129, 234:47, 236:329, 237:109, 238:34, 239:70, 240:43, 241:209, 246:289, 316:189}
ROUTE_ALIASES = {261316:"Infurnus", 259281:"Handler Ashka", 258968:"Overseer Mugg",
                 250660:"The Butcher", 246016:"Mana Elemental", 9476:"The Vault"}
# Display these as single encounters. Their reference lists are encounter-level evidence.
GROUPS = {260243:3479, 263886:3511, 253214:3499, 260213:3478, 8440:457}
REPLACED = {260274:260243, 253218:253214, 8443:8440}
REVIEW = {
    641: ("omit", "Ordinary Deadmines mob. ATT places its gloves under zone drops. No boss encounter or guide stop."),
    4857: ("omit", "Elite guardians in the halls leading to Archaedas. Ancient Stone Keeper is the separate boss, NPC 7206."),
    260274: ("alias", "An alternate Min'loth NPC in ATT. Forever combat logs name NPC 260243 on encounter 3479."),
    253218: ("superseded", "The guide loot matches encounter 3499, Ravasaur Hunters. The documented encounter NPCs differ."),
    8443: ("alias", "ATT groups both Hakkar variants. Live combat records name NPC 8440 in the Sunken Temple."),
}
for npc in (14690, 14686, 14695, 14684):
    REVIEW[npc] = ("keep", "Scourge Invasion event boss. Availability in live Forever is unverified.")


def ints(text):
    return [int(x) for x in text.split(",") if x]


def join(values):
    return ",".join(map(str, sorted(values)))


def norm(name):
    return re.sub("[^a-z0-9]", "", name.lower())


def rows(mode, *args):
    out = subprocess.check_output([LUA, "tools/boss_audit_sources.lua", mode, *map(str, args)], cwd=ROOT)
    return [line.split("\t") for line in out.decode().splitlines()]


def read(path):
    return json.loads(path.read_bytes())


def table(path, headers, records):
    with path.open("w", encoding="utf-8", newline="") as out:
        for record in [headers, *records]:
            parts = [str(x) for x in record]
            assert all("\t" not in x and "\n" not in x for x in parts)
            out.write("\t".join(parts) + "\n")


@dataclass
class Boss:
    slug: str
    map: int
    npc: int
    name: str
    decision: str
    old: list = field(default_factory=list)
    roster: set = field(default_factory=set)
    encounters: set = field(default_factory=set)
    sources: dict = field(default_factory=lambda: defaultdict(set))
    note: str = ""


def audit(args):
    source, routes, output = args.sources, args.routes, args.out
    inputs = verify(source)
    for repo, commit in [(routes, "86fce2408d45e3240d7a798d5a0fc182a7c9e0f2"),
                         (args.norgannon, "d3d144a8b2d32ae7fb6a0390141f35b3aa55d216")]:
        assert subprocess.check_output(["git", "-C", repo, "rev-parse", "HEAD"], text=True).strip() == commit
    for name, sha in [("Data.lua", "9870ca72b5e8f140573874c9f1d6d80cc5226d15cfab66b2cc97d86e944c4448"),
                      ("FloorData.lua", "eb76f39450ac1fe4bfc511e9d694691ff0f0031dfb244bc555b2e9156a031961")]:
        assert hashlib.sha256((args.baseline / name).read_bytes()).hexdigest() == sha, name
    output.mkdir(parents=True, exist_ok=True)
    roster = rows("roster", args.baseline / "Data.lua", args.baseline / "FloorData.lua")
    bosses, oldpins, dung = {}, {}, {}
    for row in roster:
        if row[0] == "boss":
            _, slug, _, instance, npc, name, loot = row
            npc, instance = int(npc), int(instance)
            assert npc not in bosses
            decision, note = REVIEW.get(npc, ("keep", ""))
            b = Boss(slug, instance, npc, name, decision, old=ints(loot), note=note)
            b.roster.add("Norgannon")
            for item in b.old:
                b.sources[item].add("Norgannon")
            bosses[npc], dung[slug] = b, instance
        else:
            oldpins.setdefault(int(row[2]), set()).update(ints(row[8]))

    att = rows("att", source / "AllTheThings/db/Camelot/Categories/Instances.lua")
    ez = rows("ez", source / "EzWoW-DungeonRouteGuide/Data/DungeonData.lua")
    route = rows("routes", routes)
    locations = defaultdict(set)
    for _, instance, name, *rest in route:
        locations[int(instance), norm(name)].update(ints(rest[0]))
    scout = defaultdict(set)
    with (AUDIT / "forever-scout.tsv").open() as f:
        for s in csv.DictReader(f, delimiter="\t"):
            if int(s["npc"]):
                scout[int(s["npc"])].update(ints(s["credited_item_ids"]))
    builds = sorted(p.parent for p in inputs if p.name == "loot.json")
    assert len(builds) == 9, "Expected nine pinned live builds"
    logs, sightings, encounter_tables = defaultdict(set), defaultdict(dict), {}
    for build in builds:
        path = build / "encounters.json"
        encounter_tables[build] = read(path)["encounters"] if path in inputs else {}
        for ident, record in encounter_tables[build].items():
            if not record.get("kills") or not record.get("map"):
                continue
            inst, e = record["map"], int(ident)
            for npc in record.get("bosses", []):
                logs[inst, npc].add(e)
            for p in record.get("positions", []):
                if p.get("map") == inst and "x" in p and "y" in p:
                    sightings[inst, e].setdefault((p["x"], p["y"]), set()).add(build.name)

    att_roster = {(ATT_MAP.get(int(a[1]), int(a[1])), int(a[2])) for a in att
                  if a[0] in ("att", "att-group") and (a[3] or a[5])}
    for key, record in list(bosses.items()):
        record.encounters.update(oldpins.get(key, ()))
    candidates = []
    for _, slug, key, kind, outside, _, name, members, _ in ez:
        slug = EZ_SLUGS.get(slug, slug.replace("dire-maul-", "dm-").replace("scarlet-monastery-", "sm-"))
        npc, member_ids = int(key), ints(members)
        if outside or kind not in {"boss", "rare"} or npc != member_ids[0] or npc in bosses:
            continue
        if any(n in bosses and n not in REPLACED for n in member_ids):
            continue
        inst = dung[slug]
        evidence = {"EzWoW"}
        if npc == 250034:
            evidence.add("DungeonJournal")  # WoWCensus, Journal 2.0.10, identifies this rare by NPC ID.
        if (inst, npc) in att_roster:
            evidence.add("ATT")
        if (inst, norm(name)) in locations:
            evidence.add("FDR")
        if npc in scout:
            evidence.add("Scout")
        if (inst, npc) in logs:
            evidence.add("EG-encounter")
        decision = "add" if len(evidence) >= 2 else "candidate"
        bosses[npc] = Boss(slug, inst, npc, name, decision, roster=evidence)
    # These journal encounters lack a matching named NPC step in EzWoW.
    for slug, npc, name, encounter in [("city-of-dalaran", 246931, "Mana Wraith", 3312),
                                       ("drowned-city", 260213, "Deathless Guardians", 3478),
                                       ("stratholme", 11121, "Black Guard Swordsmith", 2795),
                                       ("stratholme", 11058, "Ezra Grimm", 2797),
                                       ("blackrock-depths", 9476, "Watchman Doomgrip", 2791),
                                       ("sunken-temple", 8440, "Avatar of Hakkar", 492)]:
        inst = dung[slug]
        assert any(a[0] in ("att", "att-group") and int(a[2]) == npc and
                   ATT_MAP.get(int(a[1]), int(a[1])) == inst for a in att)
        assert encounter in locations[inst, norm(ROUTE_ALIASES.get(npc, name))]
        bosses[npc] = Boss(slug, inst, npc, name, "add")

    npc_labels, observed_maps, names_on_map = defaultdict(set), defaultdict(set), defaultdict(set)
    for path in sorted(p for p in inputs if p.name == "creatures.json"):
        for ident, row in read(path)["creatures"].items():
            npc, combat = int(ident), row.get("combatLog", {})
            label = combat.get("name") or row.get("name")
            if not label:
                continue
            for pos in combat.get("positions", []):
                if pos.get("map") is not None:
                    inst = pos["map"]
                    observed_maps[npc].add(inst)
                    npc_labels[npc, inst].add(label)
                    names_on_map[inst, norm(label)].add(npc)

    identity_rows = []
    for b in bosses.values():
        named = (b.map, norm(ROUTE_ALIASES.get(b.npc, b.name)))
        if named in locations:
            b.roster.add("FDR")
            b.encounters.update(locations[named])
        b.encounters.update(logs.get((b.map, b.npc), ()))
        if (b.map, b.npc) in logs:
            b.roster.add("EG-encounter")
        if b.npc in scout:
            b.roster.add("Scout")
        labels = npc_labels[b.npc, b.map]
        alternatives = names_on_map[b.map, norm(b.name)] - {b.npc}
        identity_rows.append((b.slug, b.npc, b.name, b.map, " / ".join(sorted(labels)), join(observed_maps[b.npc]),
                             join(alternatives), join(logs.get((b.map, b.npc), set()))))
    table(output / "identities.tsv", ("dungeon","npc","name","expected_map","live_names_in_instance",
          "observed_combat_maps","same_name_other_ids_in_instance","live_encounters_for_npc"), identity_rows)
    for _, slug, key, kind, outside, loot, _, _, group_loot in ez:
        npc = int(key)
        slug = EZ_SLUGS.get(slug, slug.replace("dire-maul-", "dm-").replace("scarlet-monastery-", "sm-"))
        b = bosses.get(npc)
        if not b or b.slug != slug or outside or kind not in {"boss", "rare"}:
            continue
        b.roster.add("EzWoW")
        for item in ints(loot):
            b.sources[item].add("EzWoW")
        if npc in GROUPS:
            for item in ints(group_loot):
                b.sources[item].add("EzWoW-group")
    for a in att:
        b = bosses.get(int(a[2]))
        if not b or b.map != ATT_MAP.get(int(a[1]), int(a[1])):
            continue
        if a[0] == "att-drop":
            b.sources[int(a[3])].add("ATT-zone")
        else:
            b.roster.add("ATT")
            for item in ints(a[5]):
                if a[0] == "att":
                    b.sources[item].add("ATT")
                elif GROUPS.get(b.npc) == int(a[3]):
                    b.sources[item].add("ATT-group")

    by_enc = defaultdict(set)
    for b in bosses.values():
        if b.decision in ("keep", "add"):
            for encounter in b.encounters:
                by_enc[b.map, encounter].add(b.npc)
    drops = source / "DropTables/data"
    resets = {int(k):v["since"] for k, v in read(drops / "loot-resets.json")["mobs"].items()}
    safe_everloot_resets = set(resets)
    resets[261974] = "2026-11-10"  # Cinder is named in the same Blizzard hotfix as Snowtalon and Vitrix.
    for build in builds:
        data = read(build / "loot.json")
        start = data["meta"]["collectedOn"]["first"]
        assert data["meta"]["product"] == "wowf" and start >= "2026-11-04"
        for key, record in data["sources"].items():
            match = re.fullmatch(r"npc:(\d+)(?:\|quest)?(?:\|group)?", key)
            b = bosses.get(int(match[1])) if match else None
            if b and start >= resets.get(b.npc, ""):
                for item, v in record.get("items", {}).items():
                    if v.get("drops", 0) and v.get("quantity", 0):
                        b.sources[int(item)].add("EG-corpse")
        encounters = encounter_tables[build]
        for key, record in data.get("rolls", {}).items():
            match = re.fullmatch(r"encounter:(\d+)\|threshold:\d+", key)
            if not match or not record.get("kills"):
                continue
            logged = encounters.get(match[1], {})
            inst, eid = logged.get("map"), int(match[1])
            members = by_enc.get((inst, eid), set())
            if len(members) != 1:
                continue
            b = bosses[next(iter(members))]
            if b.npc not in logged.get("bosses", []) or start < resets.get(b.npc, ""):
                continue
            for item, v in record.get("items", {}).items():
                if v.get("drops", 0):
                    b.sources[int(item)].add("EG-roll")

    submissions = sorted(p for p in inputs if p.parent == drops / "submissions")
    for path in [drops / "imports/everloot.json", *submissions]:
        data = read(path)["result"]
        is_everloot = path.name == "everloot.json"
        for origin, s in data["sources"].items():
            if not is_everloot and origin != data["exporter"]:
                continue  # omit forwarded copies from peers
            for key, mob in s.get("mobs", {}).items():
                b = bosses.get(int(key))
                if not b or (b.npc in resets and not (is_everloot and b.npc in safe_everloot_resets)):
                    continue
                for bucket in mob.get("buckets", {}).values():
                    for item, obs in bucket.get("items", {}).items():
                        if obs.get("drops", 0) > 0:
                            b.sources[int(item)].add("Everloot" if is_everloot else "DropTables")
    for npc, items in scout.items():
        if npc in bosses and npc not in resets:
            for item in items:
                bosses[npc].sources[item].add("Scout")

    ids, classes, quality = {}, {}, {}
    for _, item, name, kind in rows("names", args.norgannon):
        ids[int(item)], classes[int(item)] = name, int(kind or -1)
    item_file = source / "AllTheThings/.contrib/.db/forever/.config/.wago/ItemSearchName.1.60.1.71139.csv"
    with item_file.open(encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            item = int(row["ID"])
            ids[item], quality[item] = row["Display_lang"], int(row["OverallQualityID"])

    loot_rows, roster_rows = [], []
    for b in bosses.values():
        keep = b.decision in ("keep", "add")
        for item in dict.fromkeys([*b.old, *sorted(b.sources)]):
            evidence = b.sources[item]
            direct, guides = evidence & DIRECT, evidence & GUIDES
            relevant = item in b.old or guides or evidence & GROUP_GUIDES or classes.get(item) == 9
            if not relevant and len(direct) >= 2:
                relevant = classes.get(item) in (2, 4) and quality.get(item, 2) >= 2
            group = "withheld"
            if keep and ids.get(item) and relevant:
                if direct:
                    group = "featured" if guides or evidence & GROUP_GUIDES else "other"
                elif "EG-roll" in evidence:
                    group = "encounter"
                elif guides or evidence & GROUP_GUIDES:
                    group = "guide"
            if not direct and not relevant and "EG-roll" not in evidence:
                continue
            loot_rows.append((b.slug, b.npc, item, ids.get(item, ""), group, join(evidence)))
        roster_rows.append((b.slug, b.npc, b.name, b.decision, join(b.roster), join(b.encounters),
                            ROUTE_ALIASES.get(b.npc, ""), b.note))
    table(output / "bosses.tsv", ("dungeon","npc","boss","decision","roster_sources","encounters","route_alias","notes"),
          roster_rows)
    table(output / "drops.tsv", ("dungeon","npc","item","item_name","display","sources"), loot_rows)
    for _, inst, name, eid in (x for x in route if x[0] == "journal"):
        if int(inst) in dung.values() and not any((int(inst), e) in by_enc for e in ints(eid)):
            candidates.append((inst, eid, name))
    table(output / "unmatched-encounters.tsv", ("instance","encounter","journal_name"), sorted(set(candidates)))
    return bosses, sightings


def world_position(matrix, offset, point):
    a, b, d, w = matrix
    x, y = point[0] - offset[0], point[1] - offset[1]
    det = a*w - b*d
    if det:
        return (w*x-b*y)/det, (a*y-d*x)/det


def vector(text):
    return tuple(map(float, text.split(",")))


def positions(args, bosses, sightings):
    ez = args.sources / "EzWoW-DungeonRouteGuide/Data"
    references = {}
    for _, _, key, instance, page, source, point, matrix, offset, approx in rows(
            "ez-positions", ez / "DungeonData.lua", ez / "MinimapData.lua"):
        pos = world_position(vector(matrix), vector(offset), vector(point))
        if pos:
            references[int(instance), int(key)] = (page, source, pos, approx)
    with TemporaryDirectory() as folder:
        data, floors = Path(folder) / "Data.lua", Path(folder) / "FloorData.lua"
        subprocess.run([LUA, "tools/import_norgannon.lua", args.norgannon, data,
                        args.routes / "ForeverDungeonRoutes/Data/Entrances.lua", args.out], check=True, cwd=ROOT)
        subprocess.run([LUA, "tools/import_floors.lua", args.routes, data, floors, "-"], check=True, cwd=ROOT)
        pins = rows("roster", data, floors)
    result, changes, present = [], [], set()
    for p in pins:
        if p[0] != "pin":
            continue
        _, slug, key, floor, name, ui_map, x, y, encounters, matrix = p
        b = bosses[int(key)]
        present.add(b.npc)
        points, builds = set(), set()
        for e in ints(encounters):
            for pos, clients in sightings.get((b.map, e), {}).items():
                points.add(pos)
                builds.update(clients)
        center, median, guide_dist = None, None, None
        ref = references.get((b.map, b.npc))
        if matrix:
            a, v, c, d, w, f = vector(matrix)
            center = world_position((a, v, d, w), (c, f), (float(x), float(y)))
        if center and ref:
            guide_dist = math.dist(center, ref[2])
        if points and center:
            median = statistics.median(math.dist(center, point) for point in points)
        action, new_x, new_y = "retain", x, y
        status = ("route only" if median is None else
                  "within 35 yd" if median <= 35 else "offset over 35 yd")
        if b.npc in (247206, 261993) and (median is None or median > 35):
            # Upstream explicitly says that these guide pins came from one addon.
            action, new_x, new_y = "hide", "", ""
        elif b.npc == 11517 and center and median is not None and median >= 75 and len(builds) >= 2:
            # Oggleflint has a single floor. Only move to a tight cluster of independent pull positions.
            location = tuple(statistics.median(p[i] for p in points) for i in (0, 1))
            if len(points) >= 3 and max(math.dist(location, p) for p in points) <= 25:
                north, west = location
                nx, ny = a*north + v*west + c, d*north + w*west + f
                assert 0 < nx < 1 and 0 < ny < 1
                action, new_x, new_y = "pull", f"{nx:.4f}", f"{ny:.4f}"
        elif median is None or median > 35:
            action = "estimate"
        if action != "retain":
            changes.append((slug, b.npc, floor, action, new_x, new_y))
        result.append((slug, b.npc, b.name, floor, name, ui_map, x, y, encounters, len(points), len(builds),
                       round(median, 1) if median is not None else "", ref[1] if ref else "",
                       round(guide_dist, 1) if guide_dist is not None else "", status, action, new_x, new_y))
    for b in bosses.values():
        if b.npc not in present:
            result.append((b.slug, b.npc, b.name, "", "", "", "", "", join(b.encounters), 0, 0, "", "", "",
                          "unplaced" if b.decision in ("add", "keep") else b.decision, "", "", ""))
    table(args.out / "pins.tsv", ("dungeon","npc","boss","floor","floor_name","ui_map","route_x","route_y","encounters",
          "distinct_pulls_xy","builds_with_positions","median_offset_yd","ez_reference","ez_offset_yd",
          "position_evidence","action","display_x","display_y"), sorted(result))
    table(args.out / "pin-review.tsv", ("dungeon","npc","floor","action","x","y"), sorted(changes))


def write_index(output, bosses):
    def load_table(name):
        with (output / name).open() as f:
            return list(csv.DictReader(f, delimiter="\t"))
    loot = defaultdict(list)
    for row in load_table("drops.tsv"):
        loot[int(row["npc"])].append(row)
    pins = defaultdict(list)
    for row in load_table("pins.tsv"):
        pins[int(row["npc"])].append(row)
    with (output / "by-dungeon.md").open("w") as f:
        f.write("# Bosses by dungeon\n\n")
        f.write("The first three counts are loot entries shown in game. The fourth counts old links "
                "withheld from the menu. The distance is the median horizontal difference between the original "
                "route pin and recorded encounter pulls. A pull does not establish which floor the boss stood on. "
                "[Individual item IDs and sources](drops.tsv) · [Pin coordinates and comparisons](pins.tsv)\n")
        for dungeon in sorted({b.slug for b in bosses.values()}):
            f.write(f"\n## {dungeon}\n\n")
            f.write("| Boss (NPC ID) | Roster | Corpse | Roll | Guide | Old links withheld | Map check |\n")
            f.write("| --- | --- | ---: | ---: | ---: | ---: | --- |\n")
            for b in bosses.values():
                if b.slug != dungeon:
                    continue
                observed, rolled, guide, withheld = 0, 0, 0, 0
                for d in loot[b.npc]:
                    group = d["display"]
                    observed += group in ("featured", "other")
                    rolled += group == "encounter"
                    guide += group == "guide"
                    withheld += group == "withheld" and "Norgannon" in d["sources"].split(",")
                checks = []
                for pin in pins[b.npc]:
                    label = pin["position_evidence"]
                    if pin["floor_name"]:
                        label = pin["floor_name"] + ", "
                        if pin["median_offset_yd"]:
                            label += f'{pin["median_offset_yd"]} yd across {pin["distinct_pulls_xy"]} pull positions'
                        else:
                            label += "guide only"
                        if pin["action"] in ("hide", "pull"):
                            label += ", pin hidden" if pin["action"] == "hide" else ", pin moved to observed pulls"
                    checks.append(label)
                f.write(f"| {b.name} ({b.npc}) | {b.decision} | {observed} | {rolled} | {guide} | {withheld} "
                        f"| {' / '.join(checks)} |\n")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("sources", "norgannon", "routes", "baseline"):
        ap.add_argument(name, type=lambda p: Path(p).resolve())
    ap.add_argument("--out", type=lambda p: Path(p).resolve(), default=AUDIT)
    args = ap.parse_args()
    bosses, sightings = audit(args)
    positions(args, bosses, sightings)
    write_index(args.out, bosses)
