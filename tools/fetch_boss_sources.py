"""Download or verify the exact public inputs listed in the Forever boss audit."""
import argparse
import csv
import hashlib
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
PINS = {
    "eg-link-output-wowf": ("JIVESCORP", "c1bf99bc2835bbe1b2dad82fb99f994c0cfffe33"),
    "DropTables": ("valcheffnet", "c68b7472291bd790b4b9089ac8753cd9e7d51945"),
    "AllTheThings": ("ATTWoWAddon", "789b0feb395396c181999063b691f854167595c6"),
    "EzWoW-DungeonRouteGuide": ("ezwow-addons", "b81ba9ce16c494d02a7fc518e716cc34da19592c"),
}


def verify(cache, download=False):
    def check(row):
        repo, name, expected = row["dataset"], row["path"], row["sha256"]
        path = cache / repo / name
        if not path.exists() and download:
            owner, sha = PINS[repo]
            url = f"https://raw.githubusercontent.com/{owner}/{repo}/{sha}/{quote(name)}"
            data = subprocess.check_output(["curl", "-fsSL", "--retry", "3", "--max-time", "120", url])
            if hashlib.sha256(data).hexdigest() != expected:
                raise ValueError(f"Downloaded file differs from the pinned input: {name}")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Input differs from the pinned snapshot: {path}")
    with (ROOT / "docs/boss-audit/inputs.tsv").open() as f, ThreadPoolExecutor(max_workers=4) as pool:
        records = list(csv.DictReader(f, delimiter="\t"))
        list(pool.map(check, records))
    return {cache / row["dataset"] / row["path"] for row in records}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("cache", type=Path)
    ap.add_argument("--check", action="store_true", help="Verify local files without downloading")
    args = ap.parse_args()
    verify(args.cache, download=not args.check)
