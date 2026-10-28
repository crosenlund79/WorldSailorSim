#!/usr/bin/env python3
"""Little Captain's Hat: the Harbourmaster's Inspection, a content-integrity check.

Reads the game's own data files (no Godot, no network; Python 3 only, Windows and
Linux) and checks that the content hangs together: harbours, harbour looks and
special harbours, fish, boats, cabin things, companions, the Danish translation and
the asset files they refer to.

Each finding is one of:
  FAIL  a confirmed defect (a missing file, a broken reference, a bad value): the
        check exits 1
  WARN  probably worth a look, but the game works (e.g. a texture larger than usual)
  INFO  reported for review only (e.g. unused assets; nothing is ever deleted)

Usage:
  python tools/qa/check_game_content.py                 # summary + findings
  python tools/qa/check_game_content.py --verbose       # also every passing check
  python tools/qa/check_game_content.py --json out.json # machine-readable report

Exit code: 0 when nothing FAILs, 1 otherwise. On Windows use `py` or `python`.

What it does not do: play the game. Routes, mooring and reachability are checked by
the Godot test suites (tests/suites/test_harbours.gd, test_wider_world.gd, ...); this
tool checks what can be checked from the files alone, in a second.
"""
import csv
import importlib.util
import json
import os
import re
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# Textures larger than this (either side, in px) or heavier than this (bytes) are
# reported as WARN: the game's largest intended images are the chart rasters.
TEXTURE_MAX_PX = 4096
TEXTURE_MAX_BYTES = 8 * 1024 * 1024
# Folders whose files are read by tools, or are kept on purpose without being used,
# so "unused" means nothing there: Visuals/ holds the Captain's own original drawings
# (kept unchanged; they can be switched back in through data, see
# DEV_GUIDES/COMPANION_ANIMATION.md), art_replacements/ the Sprite Workshop.
UNUSED_IGNORE = ("assets/branding/", "art_replacements/", "docs/", "tests/", "tools/", ".godot/", "addons/", "Visuals/")
# Files the game reads only when they exist, by design (reported as INFO, never FAIL).
OPTIONAL_FILES = {
    "res://build_info.json": "written by tools/write_build_info.py before an export; a run from the project reads .git instead",
    "res://data/navigation/depth/depth.bin": "an optional global depth model (none in this build); DepthService falls back to its game estimate",
    "res://data/navigation/world/land.json": "the generator's source (git-ignored); the chart reads the shipped land.res and uses this only if that is missing",
}
# Large on purpose: chart rasters read as data, not drawn as textures.
EXPECTED_LARGE = ("data/navigation/",)


# --- Report --------------------------------------------------------------------------------

class Report:
    def __init__(self):
        self.findings = []  # {"level", "system", "check", "file", "entry", "message"}
        self.checks = []    # {"system", "check", "count", "result"}
        self.counts = {}    # system -> {"what": n}

    def add(self, level, system, check, file, entry, message):
        self.findings.append({"level": level, "system": system, "check": check, "file": file,
                              "entry": str(entry) if entry is not None else "", "message": message})

    def fail(self, *a):
        self.add("FAIL", *a)

    def warn(self, *a):
        self.add("WARN", *a)

    def info(self, *a):
        self.add("INFO", *a)

    def done(self, system, check, count):
        levels = [f["level"] for f in self.findings if f["system"] == system and f["check"] == check]
        result = "FAIL" if "FAIL" in levels else ("WARN" if "WARN" in levels else "PASS")
        self.checks.append({"system": system, "check": check, "count": count, "result": result})

    def count(self, system, what, n):
        self.counts.setdefault(system, {})[what] = n


R = Report()


# --- Helpers --------------------------------------------------------------------------------

def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def res_to_path(res):
    return os.path.join(ROOT, res[len("res://"):]) if res.startswith("res://") else os.path.join(ROOT, res)


def _ignored_files():
    """Files present here but ignored by git: they are not in the repository (nor in a
    ZIP download of it), so the game cannot count on them. Empty outside a git checkout."""
    import subprocess
    try:
        out = subprocess.run(["git", "ls-files", "--others", "--ignored", "--exclude-standard"], cwd=ROOT,
                             capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return set()
    return {line.strip() for line in out.stdout.splitlines() if line.strip()} if out.returncode == 0 else set()


IGNORED = _ignored_files()


def res_exists(res):
    path = res_to_path(res)
    return os.path.exists(path) and rel(path) not in IGNORED


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def tres_value(text, key):
    """The value of `key = ...` in a .tres [resource] section, as text (quotes removed)."""
    m = re.search(r'^%s = (.*)$' % re.escape(key), text, re.M)
    if not m:
        return None
    v = m.group(1).strip()
    if v.startswith('&"') or v.startswith('"'):
        return v[v.index('"') + 1:v.rindex('"')]
    return v


def ext_paths(text):
    """Every res:// path a .tres/.tscn mentions (ext_resource and plain strings)."""
    return set(re.findall(r'"(res://[^"]+)"', text))


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    old = sys.argv
    sys.argv = [path]
    try:
        spec.loader.exec_module(module)
    finally:
        sys.argv = old
    return module


def gd_const_list(text, name):
    """The string items of `const NAME := [...]` / `Array[...] = [...]` in a GDScript file."""
    m = re.search(r'const %s\b[^=]*=\s*\[(.*?)\]\s*$' % re.escape(name), text, re.S | re.M)
    if not m:
        return None
    return re.findall(r'&?"([^"]+)"', m.group(1))


# --- Localization (loaded first: other systems check their names against it) -------------

I18N = load_module("i18n_check", os.path.join(ROOT, "tools", "i18n", "check.py"))
PO_PATH = os.path.join(ROOT, "locale", "da.po")
POT_PATH = os.path.join(ROOT, "locale", "messages.pot")
PO = I18N.parse(PO_PATH)


def danish(text, context=""):
    """The Danish translation of an English message, or None when there is none."""
    e = PO.get((context, text))
    if e is None or not any(e["str"]):
        return None
    return e["str"][0]


def check_localization():
    system = "localization"
    pot = I18N.parse(POT_PATH)
    po_file = rel(PO_PATH)
    # The template is up to date with the code and data (otherwise new text is not
    # offered for translation at all).
    extract = load_module("i18n_extract", os.path.join(ROOT, "tools", "i18n", "extract.py"))
    live = extract.collect()
    stale = [k for k in live if k not in pot]
    for context, msgid in stale[:50]:
        R.fail(system, "template up to date", rel(POT_PATH), msgid, "in the code or data but not in messages.pot: run tools/i18n/extract.py")
    R.done(system, "template up to date", len(live))
    # Every message translated, placeholders and spacing kept.
    for (context, msgid), e in pot.items():
        t = PO.get((context, msgid))
        label = "[%s] %s" % (context, msgid) if context else msgid
        if t is None:
            R.fail(system, "every message translated", po_file, label, "no Danish entry")
            continue
        if not any(t["str"]) or "" in t["str"]:
            R.fail(system, "every message translated", po_file, label, "empty Danish entry")
            continue
        src = msgid
        if I18N.PLACEHOLDER.findall(src) != I18N.PLACEHOLDER.findall(t["str"][0]):
            R.fail(system, "placeholders kept", po_file, label, "placeholders differ: %r" % t["str"][0])
        if I18N.edges(src) != I18N.edges(t["str"][0]):
            R.fail(system, "placeholders kept", po_file, label, "leading/trailing spaces or line breaks differ")
    R.done(system, "every message translated", len(pot))
    R.done(system, "placeholders kept", len(pot))
    # The same message twice in da.po (the parser keeps the last one silently).
    seen, dupes = set(), []
    context = None
    for line in open(PO_PATH, encoding="utf-8"):
        if line.startswith("msgctxt "):
            context = line[8:].strip().strip('"')
        elif line.startswith("msgid ") and line.strip() != 'msgid ""':
            key = (context or "", line[6:].strip())
            if key in seen:
                dupes.append(key)
            seen.add(key)
            context = None
        elif not line.strip():
            context = None
    for key in dupes:
        R.fail(system, "no duplicate entries", po_file, key[1], "the same msgid%s appears twice" % (" (context %s)" % key[0] if key[0] else ""))
    R.done(system, "no duplicate entries", len(seen))
    # Danish entries no longer used by the game (kept for review; harmless).
    obsolete = [k for k in PO if k not in pot]
    if obsolete:
        R.info(system, "unused translations", po_file, "%d entries" % len(obsolete),
               "Danish entries for text the game no longer has (e.g. %r); harmless, can be pruned" % obsolete[0][1])
    R.done(system, "unused translations", len(PO))
    R.count(system, "messages", len(pot))
    R.count(system, "danish_entries", len(PO))


# --- Harbours -----------------------------------------------------------------------------

PORT_DIR = os.path.join(ROOT, "data", "navigation", "ports")
FACILITY_DIR = os.path.join(ROOT, "data", "harbours", "facilities")
FACILITY_KEYS = {"grocery", "boatyard", "go_ashore", "haul_out"}


def load_ports():
    """{id: {"name", "country", "lat", "lon", "region", "description", "file"}} from the port files."""
    ports = {}
    for name in sorted(os.listdir(PORT_DIR)):
        if not name.endswith(".tres"):
            continue
        path = os.path.join(PORT_DIR, name)
        text = read(path)
        ports[name[:-5]] = {"id": tres_value(text, "id"), "name": tres_value(text, "display_name"),
                            "country": tres_value(text, "country"), "lat": tres_value(text, "latitude"),
                            "lon": tres_value(text, "longitude"), "region": tres_value(text, "region"),
                            "description": tres_value(text, "description"), "file": rel(path)}
    return ports


PORTS = {}


def check_harbours():
    global PORTS
    system = "harbours"
    PORTS = load_ports()
    csv_path = os.path.join(ROOT, "tools", "navigation", "harbours.csv")
    rows = list(csv.DictReader(open(csv_path, encoding="utf-8")))
    ids = [r["id"] for r in rows]
    # The list, the port files and the catalogue agree.
    for i in sorted({i for i in ids if ids.count(i) > 1}):
        R.fail(system, "unique ids", rel(csv_path), i, "listed more than once")
    for i in ids:
        if not re.fullmatch(r"[a-z][a-z0-9_]*", i):
            R.fail(system, "unique ids", rel(csv_path), i, "not a valid id (lower case, digits, _)")
        if i not in PORTS:
            R.fail(system, "files match the list", rel(csv_path), i, "no data/navigation/ports/%s.tres (run build_harbours.py)" % i)
    for i, p in PORTS.items():
        if i not in ids:
            R.fail(system, "files match the list", p["file"], i, "a port file for a harbour not in harbours.csv")
        if p["id"] != i:
            R.fail(system, "files match the list", p["file"], i, "its id is %r, not the file name" % p["id"])
    catalog_path = os.path.join(ROOT, "data", "navigation", "port_catalog.tres")
    listed = {os.path.basename(p)[:-5] for p in re.findall(r'path="res://data/navigation/ports/([^"]+)"', read(catalog_path))}
    for i in sorted(set(ids) ^ listed):
        R.fail(system, "files match the list", rel(catalog_path), i, "in the catalogue or the list but not both")
    R.done(system, "unique ids", len(ids))
    R.done(system, "files match the list", len(PORTS))
    # Names: one harbour per name and country (two harbours with the same shown name
    # in one country would be indistinguishable on the chart).
    seen = {}
    for i, p in PORTS.items():
        key = (p["name"], p["country"])
        if key in seen:
            R.fail(system, "unique names", p["file"], i, "same name and country as %s (%s, %s)" % (seen[key], *key))
        seen[key] = i
        if not p["name"]:
            R.fail(system, "unique names", p["file"], i, "no display name")
    R.done(system, "unique names", len(PORTS))
    # Positions and sea areas.
    regions_text = read(os.path.join(ROOT, "tests", "suites", "test_harbours.gd"))
    regions = set(gd_const_list(regions_text, "REGIONS") or [])
    for i, p in PORTS.items():
        try:
            lat, lon = float(p["lat"]), float(p["lon"])
            if not (-72.0 <= lat <= 80.0 and -180.0 <= lon <= 180.0) or (lat == 0.0 and lon == 0.0):
                R.fail(system, "valid positions", p["file"], i, "position %s, %s is outside the chart" % (lat, lon))
        except (TypeError, ValueError):
            R.fail(system, "valid positions", p["file"], i, "no position")
        if p["region"] not in regions:
            R.fail(system, "known sea areas", p["file"], i, "sea area %r is not in test_harbours.gd REGIONS" % p["region"])
        if not p["description"]:
            R.warn(system, "a sentence about each", p["file"], i, "no description")
    R.done(system, "valid positions", len(PORTS))
    R.done(system, "known sea areas", len(PORTS))
    R.done(system, "a sentence about each", len(PORTS))
    # Facilities: only for real harbours, only known fields.
    n = 0
    for name in sorted(os.listdir(FACILITY_DIR)):
        if not name.endswith(".tres"):
            continue
        n += 1
        path = os.path.join(FACILITY_DIR, name)
        if name[:-5] not in PORTS:
            R.fail(system, "facilities", rel(path), name[:-5], "facilities for a harbour that does not exist")
        text = read(path)
        body = text.split("[resource]", 1)[-1]
        for key, value in re.findall(r"^(\w+) = (.*)$", body, re.M):
            if key == "script":
                continue
            if key not in FACILITY_KEYS:
                R.fail(system, "facilities", rel(path), name[:-5], "unknown facility %r" % key)
            elif value not in ("true", "false"):
                R.fail(system, "facilities", rel(path), name[:-5], "%s = %s is not true or false" % (key, value))
    R.done(system, "facilities", n)
    # Harbours named in other data exist (trades' harbour lists, shore events).
    refs = 0
    for path in [os.path.join(ROOT, "src", "harbour", "shore_events.gd")]:
        text = read(path)
        m = re.search(r"const BY_HARBOUR := \{(.*?)\n\}", text, re.S)
        for port in re.findall(r'^\t&?"(\w+)":', m.group(1), re.M) if m else []:
            refs += 1
            if port not in PORTS:
                R.fail(system, "references to harbours", rel(path), port, "Go Ashore events for a harbour that does not exist")
    R.done(system, "references to harbours", refs)
    R.count(system, "harbours", len(PORTS))
    R.count(system, "facility_files", n)
    # Names and sentences are offered in Danish.
    for i, p in PORTS.items():
        if p["name"] and danish(p["name"], "place") is None:
            R.fail(system, "names in Danish", p["file"], i, "no Danish entry for the name %r" % p["name"])
        if p["description"] and danish(p["description"]) is None:
            R.fail(system, "names in Danish", p["file"], i, "no Danish entry for the description")
    R.done(system, "names in Danish", len(PORTS))


# --- Harbour looks and special harbours ---------------------------------------------------

def check_looks():
    system = "harbour looks"
    path = os.path.join(ROOT, "data", "harbours", "harbour_looks.json")
    data = load_json(path)
    looks, harbours, special = data.get("looks", {}), data.get("harbours", {}), data.get("special", {})
    for look, entry in looks.items():
        tex = entry.get("texture", "")
        if not tex or not res_exists(tex):
            R.fail(system, "every look has its picture", rel(path), look, "picture %r is missing" % tex)
        if danish(entry.get("title", "")) is None:
            R.fail(system, "every look has its picture", rel(path), look, "no Danish entry for %r" % entry.get("title"))
    R.done(system, "every look has its picture", len(looks))
    for port in PORTS:
        if port not in harbours:
            R.fail(system, "every harbour has a look", rel(path), port, "no look (the plain quay would show)")
    for port, look in harbours.items():
        if port not in PORTS:
            R.fail(system, "every harbour has a look", rel(path), port, "a look for a harbour that does not exist")
        elif look not in looks:
            R.fail(system, "every harbour has a look", rel(path), port, "unknown look %r" % look)
    R.done(system, "every harbour has a look", len(harbours))
    # Special harbours are exactly those with their own art (data/harbours/<id>.tres
    # with a landmark whose picture exists).
    own = set()
    art_dir = os.path.join(ROOT, "data", "harbours")
    for name in sorted(os.listdir(art_dir)):
        if not name.endswith(".tres"):
            continue
        apath = os.path.join(art_dir, name)
        text = read(apath)
        if 'script_class="HarbourArt"' not in text:
            continue
        port = tres_value(text, "port_id")
        if port != name[:-5]:
            R.fail(system, "special harbours have their own art", rel(apath), name[:-5], "port_id %r does not match the file" % port)
        if port not in PORTS:
            R.fail(system, "special harbours have their own art", rel(apath), port, "art for a harbour that does not exist")
        for res in ext_paths(text):
            if not res_exists(res):
                R.fail(system, "special harbours have their own art", rel(apath), port, "missing file %s" % res)
        if "landmarks = " in text and "SubResource" in text.split("landmarks = ", 1)[1]:
            own.add(port)
            title = re.search(r'^title = "([^"]*)"', text, re.M)
            if title and danish(title.group(1)) is None:
                R.fail(system, "special harbours have their own art", rel(apath), port, "no Danish entry for the title %r" % title.group(1))
    for port in sorted(own - set(special)):
        R.fail(system, "special harbours have their own art", rel(path), port, "has its own illustration but is not in special (no star on the chart)")
    for port in sorted(set(special) - own):
        R.fail(system, "special harbours have their own art", rel(path), port, "marked special but has no illustration of its own")
    for port, entry in special.items():
        if danish(entry.get("text", "")) is None:
            R.fail(system, "special harbours have their own art", rel(path), port, "no Danish entry for why it is special")
    R.done(system, "special harbours have their own art", len(special))
    R.count(system, "looks", len(looks))
    R.count(system, "special_harbours", len(special))


# --- Fish ------------------------------------------------------------------------------------

FISH_LAYERS = ("body", "tail", "lid", "thumb")


def check_fish():
    system = "fish"
    path = os.path.join(ROOT, "data", "fishing", "fishing.json")
    data = load_json(path)
    art = load_json(os.path.join(ROOT, "data", "fishing", "fish_art.json")).get("art", {})
    rarities = set(data.get("rarities", {}))
    lures = {l.get("id") if isinstance(l, dict) else l for l in data.get("lures", [])}
    regions = {p["region"] for p in PORTS.values()}
    species = data.get("species", [])
    ids = [s.get("id") for s in species]
    for i in sorted({i for i in ids if ids.count(i) > 1}):
        R.fail(system, "unique ids", rel(path), i, "listed more than once")
    R.done(system, "unique ids", len(ids))
    for s in species:
        i = s.get("id")
        kg = s.get("kg", [])
        if not (isinstance(kg, list) and len(kg) == 2 and 0 < kg[0] < kg[1]):
            R.fail(system, "sizes, rarities and prices", rel(path), i, "kg %r is not [min, max] with 0 < min < max" % (kg,))
        if s.get("rarity") not in rarities:
            R.fail(system, "sizes, rarities and prices", rel(path), i, "unknown rarity %r" % s.get("rarity"))
        price = s.get("price_per_kg")
        shark = s.get("kind") == "shark"
        if not isinstance(price, (int, float)) or price < 0 or (price == 0 and not shark):
            R.fail(system, "sizes, rarities and prices", rel(path), i, "price_per_kg %r (only sharks, never sold, may be 0)" % price)
        if not 0 < float(s.get("strength", 0)) <= 1:
            R.fail(system, "sizes, rarities and prices", rel(path), i, "strength %r is not in (0, 1]" % s.get("strength"))
        bad = [r for r in s.get("regions", []) if r not in regions]
        if not s.get("regions") or bad:
            R.fail(system, "where they live", rel(path), i, "regions %r: none, or not a sea area of any harbour" % (bad or s.get("regions")))
        for lure in s.get("lures", {}):
            if lure not in lures:
                R.fail(system, "where they live", rel(path), i, "unknown lure %r" % lure)
        if danish(s.get("name", "")) is None:
            R.fail(system, "names in Danish", rel(path), i, "no Danish entry for %r" % s.get("name"))
        if i not in art:
            R.fail(system, "pictures", rel(path), i, "no entry in data/fishing/fish_art.json (no picture)")
        for layer in FISH_LAYERS:
            if not os.path.exists(os.path.join(ROOT, "assets", "fishing", i, layer + ".png")):
                R.fail(system, "pictures", "assets/fishing/%s/" % i, i, "missing %s.png" % layer)
    for junk in data.get("junk", []):
        j = junk.get("id")
        if not os.path.exists(os.path.join(ROOT, "assets", "fishing", j, "art.png")):
            R.fail(system, "pictures", "assets/fishing/%s/" % j, j, "missing art.png")
        if danish(junk.get("name", "")) is None:
            R.fail(system, "names in Danish", rel(path), j, "no Danish entry for %r" % junk.get("name"))
    for region in sorted(regions):
        if not any(region in s.get("regions", []) for s in species if s.get("kind") != "shark"):
            R.warn(system, "where they live", rel(path), region, "no fish to catch in this sea area")
    R.done(system, "sizes, rarities and prices", len(species))
    R.done(system, "where they live", len(species))
    R.done(system, "names in Danish", len(species))
    R.done(system, "pictures", len(species) + len(data.get("junk", [])))
    R.count(system, "species", len(species))
    R.count(system, "junk", len(data.get("junk", [])))


# --- Boats and cabin things -------------------------------------------------------------------

VESSEL_FIELDS = ("performance", "deck_scene", "cabin_scene", "deck_visual_scene", "visual_profile", "illustrated_visual_profile")


def check_vessels():
    system = "boats"
    cat_path = os.path.join(ROOT, "data", "vessels", "vessel_catalog.tres")
    text = read(cat_path)
    paths = [p for p in re.findall(r'path="(res://data/vessels/[^"]+\.tres)"', text)]
    ids = []
    for res in paths:
        if not res_exists(res):
            R.fail(system, "every boat complete", rel(cat_path), res, "missing boat definition")
            continue
        vtext = read(res_to_path(res))
        vid = tres_value(vtext, "id")
        ids.append(vid)
        for field in VESSEL_FIELDS:
            if tres_value(vtext, field) is None:
                R.fail(system, "every boat complete", res[6:], vid, "no %s" % field)
        for ref in ext_paths(vtext):
            if not res_exists(ref):
                R.fail(system, "every boat complete", res[6:], vid, "missing file %s" % ref)
            elif ref.endswith((".tscn", ".tres")):
                for inner in ext_paths(read(res_to_path(ref))):
                    if not res_exists(inner):
                        R.fail(system, "every boat complete", ref[6:], vid, "missing file %s" % inner)
        name = tres_value(vtext, "display_name")
        if not name or danish(name) is None:
            R.warn(system, "every boat complete", res[6:], vid, "no Danish entry for the name %r (boat names may stay as they are)" % name)
        cabin = tres_value(vtext, "cabin_scene")
        cabin_res = re.search(r'path="([^"]+)" id="%s"' % re.escape(cabin.split('"')[1]) if cabin and '"' in cabin else "x^", vtext)
        if cabin_res and res_exists(cabin_res.group(1)):
            ctext = read(res_to_path(cabin_res.group(1)))
            for spot in ("settee", "nav_station", "v_berth", "cabin_floor", "companionway", "seating"):
                if not re.search(r'\[node name="%s" [^\]]*parent="Layout/CompanionSpots"' % spot, ctext):
                    R.fail(system, "every boat complete", cabin_res.group(1)[6:], vid, "no companion spot %r in the cabin" % spot)
    for i in sorted({i for i in ids if ids.count(i) > 1}):
        R.fail(system, "every boat complete", rel(cat_path), i, "listed more than once")
    R.done(system, "every boat complete", len(paths))
    R.count(system, "boats", len(paths))


def check_cabin_things():
    system = "cabin things"
    path = os.path.join(ROOT, "data", "harbours", "trades", "trades.json")
    data = load_json(path)
    decor = data.get("decor", [])
    drawn = read(os.path.join(ROOT, "src", "aboard", "cabin_decor.gd"))
    ids = [d.get("id") for d in decor]
    for i in sorted({i for i in ids if ids.count(i) > 1}):
        R.fail(system, "catalogue", rel(path), i, "listed more than once")
    for d in decor:
        i = d.get("id")
        if not isinstance(d.get("price"), int) or d["price"] <= 0:
            R.fail(system, "catalogue", rel(path), i, "price %r is not a positive whole number" % d.get("price"))
        if d.get("place") not in ("floor", "wall", "shelf"):
            R.fail(system, "catalogue", rel(path), i, "place %r is not floor, wall or shelf" % d.get("place"))
        if '"%s":' % i not in drawn:
            R.fail(system, "catalogue", "src/aboard/cabin_decor.gd", i, "no drawing for it (it would be invisible)")
        for key in ("name", "text"):
            if danish(d.get(key, "")) is None:
                R.fail(system, "catalogue", rel(path), i, "no Danish entry for its %s" % key)
    R.done(system, "catalogue", len(decor))
    # The rest of the trades: sail cloths, upgrades.
    for cloth in data.get("sail_cloths", []):
        if danish(cloth.get("name", "")) is None:
            R.fail(system, "catalogue", rel(path), cloth.get("id"), "no Danish entry for the sail cloth's name")
    # Owned things start empty in a new game (HomeState); a save names them by id.
    home = read(os.path.join(ROOT, "src", "core", "home_state.gd"))
    if not re.search(r"var owned_decor\s*:\s*Array\[String\]\s*=\s*\[\]", home):
        R.warn(system, "nothing owned at the start", "src/core/home_state.gd", "owned_decor", "could not confirm that a new game owns no cabin things")
    R.done(system, "nothing owned at the start", 1)
    R.count(system, "cabin_things", len(decor))
    R.count(system, "sail_cloths", len(data.get("sail_cloths", [])))


# --- Companions ---------------------------------------------------------------------------------

def check_companions():
    system = "companions"
    state = read(os.path.join(ROOT, "src", "companion", "companion_state.gd"))
    kinds = re.findall(r'const KIND_\w+ := &"(\w+)"', state)
    for kind in kinds:
        vpath = os.path.join(ROOT, "data", "companions", "%s_visuals.tres" % kind)
        if not os.path.exists(vpath):
            R.fail(system, "every kind complete", "data/companions/", kind, "no %s_visuals.tres" % kind)
            continue
        for res in ext_paths(read(vpath)):
            if not res_exists(res):
                R.fail(system, "every kind complete", rel(vpath), kind, "missing file %s" % res)
    ship = read(os.path.join(ROOT, "src", "companion", "ship_companion.gd"))
    for res in re.findall(r'preload\("(res://[^"]+)"\)', ship):
        if not res_exists(res):
            R.fail(system, "every kind complete", "src/companion/ship_companion.gd", res, "missing sound or file")
    R.done(system, "every kind complete", len(kinds))
    # Petting remarks: every line translated, and the name placeholder kept.
    remarks_path = os.path.join(ROOT, "src", "companion", "companion_remarks.gd")
    remarks = read(remarks_path)
    lines = re.findall(r'^\t+"((?:[^"\\]|\\.)+)",?$', remarks, re.M)
    lines += re.findall(r'\[\s*"((?:[^"\\]|\\.)+)"\s*\]', remarks)
    lines += re.findall(r'Loc\.t\("((?:[^"\\]|\\.)+)"\)', remarks)
    for line in sorted(set(lines)):
        if danish(line) is None:
            R.fail(system, "petting remarks in Danish", rel(remarks_path), line, "no Danish entry")
    R.done(system, "petting remarks in Danish", len(set(lines)))
    # Name and gender: the game has none yet (the remarks are ready for them).
    if not re.search(r"^var name\b|^@export var name\b", state, re.M):
        R.info(system, "names and genders", "src/companion/companion_state.gd", "name, gender",
               "the companion has no name or gender yet (only its kind); CompanionRemarks uses them when they are added")
    R.done(system, "names and genders", 1)
    R.count(system, "kinds", len(kinds))
    R.count(system, "petting_lines", len(set(lines)))


# --- Assets ------------------------------------------------------------------------------------

SCAN_EXT = (".tres", ".tscn", ".gd", ".json", ".cfg", ".godot")


def project_files():
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for f in files:
            yield os.path.join(base, f)


def check_assets():
    system = "assets"
    texts = {}
    for path in project_files():
        r = rel(path)
        if r.endswith(SCAN_EXT) and not r.startswith(("docs/", "tests/scratch/")):
            try:
                texts[r] = read(path)
            except UnicodeDecodeError:
                pass
    # Broken res:// paths in game files (code may build paths at run time; only
    # complete literal paths are checked).
    checked = 0
    for r, text in texts.items():
        # Tools write files; test suites name missing files on purpose (fallback tests).
        if r.startswith(("tools/", "art_replacements/", "tests/")):
            continue
        for res in set(re.findall(r'"(res://[^"%*{}]+\.[a-z0-9]+)"', text)):
            checked += 1
            if res_exists(res):
                continue
            if res in OPTIONAL_FILES:
                R.info(system, "no broken paths", r, res, "optional by design: " + OPTIONAL_FILES[res])
            else:
                R.fail(system, "no broken paths", r, res, "refers to a file that does not exist")
    R.done(system, "no broken paths", checked)
    # Textures: size and weight.
    pngs = [p for p in project_files() if p.endswith(".png") and not rel(p).startswith(("docs/", "tests/", ".godot/"))]
    for p in pngs:
        size = png_size(p)
        if size and max(size) > TEXTURE_MAX_PX:
            if rel(p).startswith(EXPECTED_LARGE):
                R.info(system, "texture sizes", rel(p), "%dx%d" % size, "a chart raster (data), large on purpose")
            else:
                R.warn(system, "texture sizes", rel(p), "%dx%d" % size, "larger than %d px on a side" % TEXTURE_MAX_PX)
        if os.path.getsize(p) > TEXTURE_MAX_BYTES:
            R.warn(system, "texture sizes", rel(p), "%.1f MB" % (os.path.getsize(p) / 1e6), "heavier than %d MB" % (TEXTURE_MAX_BYTES // 1e6))
    R.done(system, "texture sizes", len(pngs))
    # Unused images (for review only; never deleted). An image counts as used when a
    # game file names it, or names a folder that holds it (art read by id from a folder,
    # e.g. ART_DIR := "res://assets/fishing", a vessel profile's art folder).
    named = set()
    for r, t in texts.items():
        if not r.startswith(("tools/", "tests/")):
            named.update(x.rstrip("/") for x in re.findall(r'"(res://[^"%*{}]+)"', t))
    unused = []
    for p in pngs:
        r = rel(p)
        if r.startswith(UNUSED_IGNORE):
            continue
        parts = r.split("/")
        candidates = {"res://" + r} | {"res://" + "/".join(parts[:k]) for k in range(2, len(parts))}
        if not candidates & named:
            unused.append(r)
    for r in unused:
        R.info(system, "unused images", r, os.path.basename(r), "no game file refers to it (review; not deleted)")
    R.done(system, "unused images", len(pngs))
    R.count(system, "images", len(pngs))
    R.count(system, "paths_checked", checked)


# --- Main ----------------------------------------------------------------------------------------

def main():
    # A Windows console may not have every letter (e.g. "Kuşadası"): never crash on one.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="replace")
    args = sys.argv[1:]
    verbose = "--verbose" in args
    out = args[args.index("--json") + 1] if "--json" in args else None
    for check in (check_localization, check_harbours, check_looks, check_fish, check_vessels, check_cabin_things,
                  check_companions, check_assets):
        try:
            check()
        except Exception as error:  # a check that cannot run is itself a defect to look at
            R.fail(check.__name__[6:], "could run", "tools/qa/check_game_content.py", check.__name__, "%s: %s" % (type(error).__name__, error))
    fails = [f for f in R.findings if f["level"] == "FAIL"]
    warns = [f for f in R.findings if f["level"] == "WARN"]
    infos = [f for f in R.findings if f["level"] == "INFO"]
    for c in R.checks:
        if verbose or c["result"] != "PASS":
            print("%-4s  %-15s %s (%d checked)" % (c["result"], c["system"], c["check"], c["count"]))
    for f in fails + warns + (infos if verbose else infos[:5]):
        print("  %s %s: %s [%s] %s" % (f["level"], f["system"], f["file"], f["entry"], f["message"]))
    if len(infos) > 5 and not verbose:
        print("  ... %d more INFO lines (--verbose or --json to see all)" % (len(infos) - 5))
    passed = sum(1 for c in R.checks if c["result"] == "PASS")
    print("Harbourmaster's Inspection: %d checks, %d PASS, %d with warnings, %d FAIL; %d FAIL, %d WARN, %d INFO findings" % (
        len(R.checks), passed, sum(1 for c in R.checks if c["result"] == "WARN"), sum(1 for c in R.checks if c["result"] == "FAIL"),
        len(fails), len(warns), len(infos)))
    print("Counts: " + "; ".join("%s %s" % (s, ", ".join("%s %d" % kv for kv in c.items())) for s, c in R.counts.items()))
    if out:
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            json.dump({"result": "FAIL" if fails else ("WARN" if warns else "PASS"), "checks": R.checks, "counts": R.counts,
                       "findings": R.findings}, f, indent=1, ensure_ascii=False)
            f.write("\n")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
