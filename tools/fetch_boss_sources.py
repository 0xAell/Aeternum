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
CLIENT_BUILD = "1.60.1.71139"
CLIENT_EXPORTS = {
    "SpellName.csv": "02128e7f52b8741d2bd144f273cad5e29da384636096087f567db8734a939934",
    "SpellCategories.csv": "3581bb0723f3064f7cc986cd9f55eda45e19f0baf926ed8710b1a6918cd72887",
    "SpellMisc.csv": "f57f7cd3c95d829ae90fe450b8068545beece192a112693da4ce81ee29034690",
    "Spell.csv": "cc8e495092e5030ccfc2719dd052948cb7e6debca79584260abd560582b855fc",
    "SpellEffect.csv": "970158fb0ea34695b1d59837a8a612d72b76592f941324372095e1566ea461f2",
}


def verify_file(path, expected, url, download):
    if not path.exists() and download:
        data = subprocess.check_output(["curl", "-fsSL", "--retry", "3", "--max-time", "120", url])
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"Downloaded file differs from the pinned input: {url}")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise ValueError(f"Input differs from the pinned snapshot: {path}")


def verify_client_exports(cache, download=False):
    def check(entry):
        name, expected = entry
        path = cache / name
        url = f"https://wago.tools/db2/{path.stem}/csv?build={CLIENT_BUILD}"
        verify_file(path, expected, url, download)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(check, CLIENT_EXPORTS.items()))


def verify(cache, download=False):
    def check(row):
        repo, name, expected = row["dataset"], row["path"], row["sha256"]
        owner, sha = PINS[repo]
        url = f"https://raw.githubusercontent.com/{owner}/{repo}/{sha}/{quote(name)}"
        verify_file(cache / repo / name, expected, url, download)
    with (ROOT / "docs/boss-audit/inputs.tsv").open() as f, ThreadPoolExecutor(max_workers=4) as pool:
        records = list(csv.DictReader(f, delimiter="\t"))
        list(pool.map(check, records))
    return {cache / row["dataset"] / row["path"] for row in records}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("cache", type=Path)
    ap.add_argument("--db2", type=Path, help="Download or check the pinned English client spell exports here")
    ap.add_argument("--check", action="store_true", help="Verify local files without downloading")
    args = ap.parse_args()
    verify(args.cache, download=not args.check)
    if args.db2:
        verify_client_exports(args.db2, download=not args.check)
