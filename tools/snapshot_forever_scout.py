"""Write only NPC and item IDs from Forever Scout's own credited dungeon reports."""
import argparse
import hashlib
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
URL = "https://guide.wow4ever.se/en/instances/"


class BossTable(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows = {}
        self.boss = self.item = None
        self.in_boss = self.heading = self.row = self.credit = False
        self.depth = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "li" and re.fullmatch(r"boss-\d+", attrs.get("id", "")):
            self.in_boss = True
            self.depth = 0
            self.boss = None
        if not self.in_boss:
            return
        if tag == "li":
            self.depth += 1
        elif tag == "h3":
            self.heading = True
        elif tag == "tr":
            self.row, self.credit, self.item = True, False, None
        elif tag == "a":
            kind, _, ident = attrs.get("data-tip", "").partition(":")
            if ident.isdigit():
                if self.heading and kind == "npc":
                    self.boss = int(ident)
                    self.rows.setdefault(self.boss, set())
                if self.row and kind == "item":
                    self.item = int(ident)
        elif tag == "details" and self.row and "data-credit" in attrs:
            self.credit = True

    def handle_endtag(self, tag):
        if not self.in_boss:
            return
        if tag == "li":
            self.depth -= 1
            if not self.depth:
                self.in_boss = self.heading = self.row = False
        elif tag == "h3":
            self.heading = False
        elif tag == "tr":
            if self.row and self.credit and self.boss and self.item:
                self.rows[self.boss].add(self.item)
            self.row = False


def snapshot(cache, slug):
    path = cache / (slug + ".html")
    if not path.exists():
        html = subprocess.check_output(["curl", "-fsSL", "--max-time", "35", "--retry", "2", URL + slug])
        path.write_bytes(html)
    html = path.read_bytes()
    table = BossTable()
    table.feed(html.decode())
    return slug, hashlib.sha256(html).hexdigest(), table.rows


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path, help="Directory for the public HTML snapshots")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.cache.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    slugs = set(re.findall(r'^    \["([^"]+)"\] =', (ROOT / "FloorData.lua").read_text(), re.M))
    aliases = {"drowned-city":"the-drowned-city", "hall-of-thanes":"the-hall-of-thanes",
               "shapers-terrace":"the-shapers-terrace", "stockade":"stormwind-stockade",
               "lbrs":"blackrock-spire", "ubrs":"blackrock-spire"}
    for slug in sorted(slugs):
        if slug.startswith("dm-"):
            aliases[slug] = "dire-maul"
        if slug.startswith("sm-"):
            aliases[slug] = "scarlet-monastery"
    pages = sorted({aliases.get(s, s) for s in slugs})
    assert pages, "No dungeon slugs found"
    with ThreadPoolExecutor(max_workers=3) as pool:
        records = list(pool.map(lambda slug: snapshot(args.cache, slug), pages))
    with args.output.open("w") as out:
        out.write("page\thtml_sha256\tnpc\tcredited_item_ids\n")
        for slug, digest, rows in records:
            for npc, items in sorted(rows.items()) or [(0, set())]:
                out.write(f"{slug}\t{digest}\t{npc}\t{','.join(map(str, sorted(items)))}\n")
