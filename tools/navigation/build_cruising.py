"""Builds the Detailed Cruising Regions' destinations (Regions and Harbours 2026).

Source: tools/navigation/cruising_destinations.csv, one row per destination in a
Detailed Cruising Region (data/cruising/regions.json): harbours ("harbour" =
full-service, "guest_harbour", "fishing_village") and natural anchorages
("anchorage"). Researched from cruising guides and harbour listings (the
"source" column), then checked against the game's own charts with
tools/qa/check_destinations.gd. Anchorages that the chart's anchoring rule
could not hold where researched were moved to the nearest spot it does
(research_position, adjusted_nm); candidates left out are listed with the
reason in cruising_destinations_omitted.csv.

Writes:
  - the harbours' rows in tools/navigation/harbours.csv (added or updated, never
    removed: ids are stable), so build_harbours.py makes their PortData;
  - data/harbours/facilities/<id>.tres for each harbour, from its class: a
    full-service harbour has every facility and a haul-out; a guest harbour and a
    fishing village have the grocery and the shore, and a boatyard only where the
    listing names repairs; gameplay abstractions, not claims about businesses;
  - data/cruising/destinations.json: every destination's metadata for the
    passenger work of I028 (class, services, overnight suitability, scenic tags,
    region membership, vessel notes) and the anchorages' names, positions and
    descriptions. Anchorages have no shore facilities and are not harbours.

Usage: python3 tools/navigation/build_cruising.py   (then build_harbours.py)
"""
import csv
import json
import os

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "..")
SOURCE = os.path.join(HERE, "cruising_destinations.csv")
HARBOURS = os.path.join(HERE, "harbours.csv")
FACILITIES = os.path.join(ROOT, "data", "harbours", "facilities")
OUT = os.path.join(ROOT, "data", "cruising", "destinations.json")
HARBOUR_FIELDS = ["id", "name", "country", "latitude", "longitude", "importance", "region", "island", "source", "description"]
CLASSES = ("harbour", "guest_harbour", "fishing_village", "anchorage")

FACILITY_TEMPLATE = """[gd_resource type="Resource" script_class="HarbourFacilities" format=3]

[ext_resource type="Script" path="res://src/harbour/harbour_facilities.gd" id="1_fac"]

[resource]
script = ExtResource("1_fac")
grocery = {grocery}
boatyard = {boatyard}
go_ashore = true
haul_out = {haul_out}
"""


def facilities(row):
    services = set(filter(None, row["services"].split(";")))
    full = row["kind"] == "harbour"
    boatyard = full or "repairs" in services
    return {"grocery": "true", "boatyard": "true" if boatyard else "false", "haul_out": "true" if full else "false"}


def main():
    rows = list(csv.DictReader(open(SOURCE, encoding="utf-8")))
    bad = [r["id"] for r in rows if r["kind"] not in CLASSES]
    if bad:
        raise SystemExit("Unknown destination class: %s" % bad)
    harbours = list(csv.DictReader(open(HARBOURS, encoding="utf-8")))
    by_id = {h["id"]: h for h in harbours}
    destinations = []
    added = 0
    for r in rows:
        entry = {"id": r["id"], "class": r["kind"], "country": r["country"], "cruising_region": r["cruising_region"],
                 "area": r["area"], "latitude": float(r["latitude"]), "longitude": float(r["longitude"]),
                 "island": r["island"] == "1", "overnight": r["overnight"] == "yes",
                 "scenic": [s for s in r["scenic"].split(";") if s],
                 "services": [] if r["kind"] == "anchorage" else [s for s in r["services"].split(";") if s],
                 "vessel_note": r["vessel_note"], "source": r["source"]}
        if r["kind"] == "anchorage":
            entry.update({"name": r["name"], "description": r["description"], "onward": r["onward"]})
            if r["research_position"]:
                lat, lon = r["research_position"].split(",")
                entry["research_position"] = [float(lat), float(lon)]
                entry["adjusted_nm"] = float(r["adjusted_nm"])
        else:
            row = {"id": r["id"], "name": r["name"], "country": r["country"], "latitude": r["latitude"],
                   "longitude": r["longitude"], "importance": r["importance"], "region": r["sea_area"], "island": r["island"],
                   "source": "%s (Regions and Harbours 2026)" % r["source"], "description": r["description"]}
            if r["id"] in by_id:
                by_id[r["id"]].update(row)
            else:
                harbours.append(row)
                by_id[r["id"]] = row
                added += 1
            with open(os.path.join(FACILITIES, "%s.tres" % r["id"]), "w", encoding="utf-8") as f:
                f.write(FACILITY_TEMPLATE.format(**facilities(r)))
        destinations.append(entry)
    writer = csv.DictWriter(open(HARBOURS, "w", encoding="utf-8", newline=""), HARBOUR_FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(harbours)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump({"note": "Destinations of the Detailed Cruising Regions, built from tools/navigation/cruising_destinations.csv "
                       "by tools/navigation/build_cruising.py. Harbours are also PortData (data/navigation/ports); "
                       "anchorages are not harbours and have no shore facilities.",
               "classes": list(CLASSES), "destinations": destinations},
              open(OUT, "w", encoding="utf-8"), indent="\t", ensure_ascii=False)
    print("%d destinations (%d harbours added to harbours.csv, %d anchorages)" % (
        len(destinations), added, sum(1 for d in destinations if d["class"] == "anchorage")))


if __name__ == "__main__":
    main()
