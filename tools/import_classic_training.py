"""Build a compact Classic reference for NPCs in Aeternum's Forever trainer index."""
import gzip
import hashlib
import re
import sys
from pathlib import Path

EXPECTED_SHA256 = "4f92db520868ab4e566726f68b5b2e380ae781209beaf22237b4f7f04600d0c0"
ROW = re.compile(r"\((?:'(?:\\.|[^'\\])*'|[^'()]+)*\)")
FIELD = re.compile(r"'(?:\\.|[^'\\])*'|[^,]+")
COLUMNS = {
    "creature_template": ("Entry", "TrainerTemplateId"),
    "npc_trainer": ("entry", "spell", "spellcost", "reqskill", "reqskillvalue", "reqlevel"),
    "npc_trainer_template": ("entry", "spell", "spellcost", "reqskill", "reqskillvalue", "reqlevel"),
    "spell_template": ("Id", "SpellName", "Rank1", "Effect1", "Effect2", "Effect3",
                       "EffectTriggerSpell1", "EffectTriggerSpell2", "EffectTriggerSpell3"),
}


def extract(path, requested=COLUMNS):
    columns = {}
    with gzip.open(path, "rt", encoding="utf-8") as source:
        for line in source:
            schema = re.match(r'CREATE TABLE \x60(\w+)\x60', line)
            if schema and schema[1] in requested:
                table = schema[1]
                names = []
                for col in source:
                    if col.startswith(")"):
                        break
                    name = re.match(r'\s+\x60(\w+)\x60', col)
                    if name:
                        names.append(name[1])
                columns[table] = [names.index(name) for name in requested[table]]
            insert = re.match(r'INSERT INTO \x60(\w+)\x60 VALUES ', line)
            if insert and insert[1] in columns:
                table = insert[1]
                for match in ROW.finditer(line, insert.end()):
                    fields = FIELD.findall(match[0][1:-1])
                    yield table, [fields[i] for i in columns[table]]


def sql_text(value):
    if value == "NULL":
        return ""
    return re.sub(r"\\(.)", r"\1", value[1:-1])


def quote(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(sql, database, output):
    if hashlib.sha256(sql.read_bytes()).hexdigest() != EXPECTED_SHA256:
        raise ValueError("Unexpected Classic database snapshot")
    trainers = database.read_text().split("    trainers = {\n", 1)[1].split("\n    },", 1)[0]
    npc_ids = {int(value) for value in re.findall(r"\bid=(\d+)", trainers)}
    templates, personal, shared, spells = {}, {}, {}, {}
    for table, values in extract(sql):
        entry = int(values[0])
        if table == "creature_template":
            if entry in npc_ids:
                templates[entry] = int(values[1])
        elif table == "spell_template":
            effects = zip(values[3:6], values[6:9])
            learned = [int(trigger) for effect, trigger in effects if effect == "36" and int(trigger) > 0]
            spells[entry] = (sql_text(values[1]), sql_text(values[2]), learned)
        elif table == "npc_trainer_template" or entry in npc_ids:
            destination = shared if table == "npc_trainer_template" else personal
            destination.setdefault(entry, []).append(tuple(map(int, values[1:])))

    definitions, lists, by_npc = {}, {}, {}
    for npc in sorted(npc_ids):
        offers = {}
        for spell, cost, skill, requirement, level in shared.get(templates.get(npc), []) + personal.get(npc, []):
            if spell not in spells:
                continue
            for learned in spells[spell][2] or [spell]:
                if learned not in spells:
                    continue
                name, rank, _ = spells[learned]
                if not name or "|" in name or "|" in rank:
                    continue
                definitions[learned] = name + "|" + rank
                offers[learned] = f"{learned}:{cost}:{level}:{skill}:{requirement}"
        if offers:
            catalogue = ";".join(offers[s] for s in sorted(offers))
            by_npc[npc] = lists.setdefault(catalogue, len(lists) + 1)
    with output.open("w", encoding="utf-8") as out:
        out.write("-- Generated Classic trainer reference from CMaNGOS. See DATA_SOURCES.md.\nlocal _, addon = ...\n")
        out.write("addon.classicTraining = { spells = {\n")
        for spell, value in sorted(definitions.items()):
            out.write(f"    [{spell}] = {quote(value)},\n")
        out.write("}, catalogues = {\n")
        for catalogue in lists:
            out.write(f"    {quote(catalogue)},\n")
        out.write("}, trainers = {\n")
        for npc, index in sorted(by_npc.items()):
            out.write(f"    [{npc}] = {index},\n")
        out.write("}}\n")
    print(f"Classic reference: {len(definitions)} spells, {len(lists)} catalogues, {len(by_npc)} NPCs")


if __name__ == "__main__":
    build(*(Path(value) for value in sys.argv[1:]))
