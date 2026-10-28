#!/usr/bin/env python3
"""Little Captain's Hat: extract the player-facing text for translation.

Writes locale/messages.pot (gettext template) from:
  - Loc.t("...") / Loc.t("...", "context") / Loc.n("...", "...", n) calls,
  - plain sentence-like string literals in game scripts (labels, buttons,
    notices: Godot translates a control's text when it matches a message),
  - text, tooltip_text and placeholder_text in scenes,
  - the name/text/title/description fields of the data files.
Developer-only text is skipped: logs, warnings, keys, paths, dev tools.

Usage: python3 tools/i18n/extract.py [--check]   (--check: report only)
"""
import glob
import json
import os
import re
import sys

ROOT = os.environ.get("LCH_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKIP_DIRS = ("src/dev/",)
SKIP_LINE = re.compile(r"SessionLog\.write|push_warning|push_error|print\(|printerr|assert\(|\.has_method\(|get_node|"
                       r"preload\(|load\(|res://|user://|StringName\(|\.connect\(|set_meta|get_meta|ProjectSettings|"
                       r"Input\.|InputMap|is_action|_log\(|errors\.append|_fail\(|RegEx|\.name\s*=\s*\"")
_TOKEN = re.compile(r'([&^]?)"((?:[^"\\]|\\.)*)"')


def literals(code):
    """The plain string literals of a line (not &"StringName" or ^"NodePath")."""
    for m in _TOKEN.finditer(code):
        if m.group(1) == "" and not (m.start() > 0 and (code[m.start() - 1].isalnum() or code[m.start() - 1] == "_")):
            yield m.group(2)
LOC_T = re.compile(r'Loc\.t\(\s*"((?:[^"\\]|\\.)*)"(?:\s*,\s*"((?:[^"\\]|\\.)*)")?\s*\)')
LOC_FORMAT = re.compile(r'Loc\.format\(\s*"((?:[^"\\]|\\.)*)"')
LOC_N = re.compile(r'Loc\.(?:n|format_plural)\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"(?:\s*,[^,)]*(?:\([^)]*\))?[^,)]*,\s*"((?:[^"\\]|\\.)*)")?')
DATA_KEYS = ("name", "game_title", "text", "title", "description", "label", "display_name", "short", "story", "hint", "flavour", "message",
             "body", "choice", "outcome", "question", "log")
# Lists of player-facing strings (I022 pastimes), and maps whose values are.
LIST_KEYS = ("captions", "choices", "done")
MAP_KEYS = ("weather_names",)


def sentence_like(text):
    """A player-facing phrase: at least one word of 2+ letters, not an id/key/path."""
    if not re.search(r"[A-Za-z]{2,}", text):
        return False
    if re.fullmatch(r"[a-z0-9_./:\-|>%]+", text):  # ids, keys, paths, format keys
        return False
    if re.fullmatch(r"[A-Z0-9_]+", text):  # constants
        return False
    if text.startswith(("res://", "user://", "#", "ui_", "move_")):
        return False
    if " " not in text and re.fullmatch(r"[A-Z][a-z0-9]+(?:[A-Z][A-Za-z0-9]*)+", text):  # NodeNames
        return False
    if re.search(r"\.(png|tres|tscn|gd|json|ogg|wav|cfg|csv|md)\b", text):
        return False
    if re.search(r'\{\s*"', text):  # json-ish (a "{action}" key placeholder is fine, I022)
        return False
    return True


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def collect():
    entries = {}  # (context, msgid) -> {"plural": str|None, "refs": set}

    def add(msgid, ref, context="", plural=None):
        if not msgid.strip():
            return
        key = (context, msgid)
        e = entries.setdefault(key, {"plural": plural, "refs": set()})
        e["refs"].add(ref)
        if plural:
            e["plural"] = plural

    for path in sorted(glob.glob(os.path.join(ROOT, "src/**/*.gd"), recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel.startswith(SKIP_DIRS):
            continue
        source = open(path, encoding="utf-8").read()
        # Loc.t / Loc.n calls, also across lines.
        for m in LOC_T.finditer(source):
            add(unescape(m.group(1)), f"{rel}:{source.count(chr(10), 0, m.start()) + 1}", unescape(m.group(2) or ""))
        for m in LOC_FORMAT.finditer(source):
            add(unescape(m.group(1)), f"{rel}:{source.count(chr(10), 0, m.start()) + 1}")
        for m in LOC_N.finditer(source):
            add(unescape(m.group(1)), f"{rel}:{source.count(chr(10), 0, m.start()) + 1}", unescape(m.group(3) or ""), unescape(m.group(2)))
        for number, line in enumerate(source.split("\n"), 1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            code = line.split(" #")[0] if '"' not in line.split(" #")[-1] else line
            if line.rstrip().endswith("# i18n"):  # every text on the line is shown (a table of labels)
                for raw in literals(code):
                    if re.search(r"[A-Za-z]{2,}", raw):
                        add(unescape(raw), f"{rel}:{number}")
                continue
            if SKIP_LINE.search(code) or "Loc." in code:
                continue
            for raw in literals(code):
                text = unescape(raw)
                if sentence_like(text) and " " in text.strip() or (sentence_like(text) and text[:1].isupper() and len(text) > 2):
                    add(text, f"{rel}:{number}")
    for path in sorted(glob.glob(os.path.join(ROOT, "src/**/*.tscn"), recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel.startswith(SKIP_DIRS):
            continue
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            m = re.match(r'^(text|tooltip_text|placeholder_text|title) = "((?:[^"\\]|\\.)*)"', line)
            if m and sentence_like(unescape(m.group(2))):
                add(unescape(m.group(2)), f"{rel}:{number}")

    def walk(node, rel):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in DATA_KEYS and isinstance(v, str) and sentence_like(v):
                    add(v, rel)
                elif k in LIST_KEYS and isinstance(v, list):
                    for item in v:
                        if isinstance(item, str) and sentence_like(item):
                            add(item, rel)
                elif k in MAP_KEYS and isinstance(v, dict):
                    for item in v.values():
                        if isinstance(item, str) and sentence_like(item):
                            add(item, rel)
                elif isinstance(v, (dict, list)):
                    walk(v, rel)
        elif isinstance(node, list):
            for v in node:
                walk(v, rel)

    for path in sorted(glob.glob(os.path.join(ROOT, "data/**/*.json"), recursive=True)):
        rel = os.path.relpath(path, ROOT)
        try:
            walk(json.load(open(path, encoding="utf-8")), rel)
        except Exception:
            pass
    for path in sorted(glob.glob(os.path.join(ROOT, "data/**/*.tres"), recursive=True)):
        rel = os.path.relpath(path, ROOT)
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            m = re.match(r'^(display_name|name|description|text|title|label) = "((?:[^"\\]|\\.)*)"', line)
            if m and sentence_like(unescape(m.group(2))):
                # Harbour names have their own context ("place"): PortData.display_name.
                place = "place" if m.group(1) == "display_name" and "/ports/" in rel else ""
                add(unescape(m.group(2)), f"{rel}:{number}", place)
    # Messages asked for by value (Loc.month, WindField.compass_name, ...).
    for name in ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                 "November", "December", "Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]:
        add(name, "src/core/loc.gd", "month")
    for name in ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sun", "Mon", "Tue", "Wed",
                 "Thu", "Fri", "Sat"]:
        add(name, "src/core/loc.gd", "weekday")
    for name in ["common", "uncommon", "rare", "very rare"]:  # FishingCatalog.rarity_name
        add(name, "src/fishing/fishing_catalog.gd")
    for name in ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]:
        add(name, "src/weather/wind_field.gd", "compass")
    return entries


def po_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def write_pot(entries, path):
    out = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', '"Project-Id-Version: Little Captain\'s Hat\\n"', ""]
    for (context, msgid), e in sorted(entries.items(), key=lambda kv: (sorted(kv[1]["refs"])[0], kv[0][1])):
        refs = sorted(e["refs"])
        out.append("#: " + " ".join(refs[:4]))
        if context:
            out.append(f'msgctxt "{po_escape(context)}"')
        out.append(f'msgid "{po_escape(msgid)}"')
        if e["plural"]:
            out.append(f'msgid_plural "{po_escape(e["plural"])}"')
            out.append('msgstr[0] ""')
            out.append('msgstr[1] ""')
        else:
            out.append('msgstr ""')
        out.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))


if __name__ == "__main__":
    entries = collect()
    if "--check" not in sys.argv:
        os.makedirs(os.path.join(ROOT, "locale"), exist_ok=True)
        write_pot(entries, os.path.join(ROOT, "locale/messages.pot"))
    print(f"{len(entries)} messages")
