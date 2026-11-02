#!/usr/bin/env python3
"""I028 career verification: summarise the career simulator's runs.

Reads docs/iterations/i028/career/batch*/career_<policy>_<seed>.json (written
by tests/career/career_sim.gd with --hours) and writes:
  - docs/iterations/i028/career/horizons.csv: one row per career and horizon
    (5/10/20/40/80/100 estimated human hours) - money, income by source,
    voyages, harbours, passengers, dreams, works, renown, rank;
  - docs/iterations/i028/career/summary.csv: one row per career (end state);
  - a medians table per archetype and horizon printed to stdout (Markdown).
Estimated human hours are the simulator's labelled model, not measurements.
"""
import csv
import glob
import json
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CAREER = os.path.join(ROOT, "docs/iterations/i028/career")
SOURCES = ["remote_work", "passenger_fare", "passenger_tip", "passenger_refund", "writing", "provisions", "fuel", "harbour_dues", "boatyard"]


def main() -> int:
    careers = []
    for path in sorted(glob.glob(os.path.join(CAREER, "batch*/career_*_[0-9].json"))):
        try:
            careers.append(json.load(open(path, encoding="utf-8")))
        except json.JSONDecodeError:
            print(f"skipped (incomplete): {os.path.relpath(path, ROOT)}", file=sys.stderr)
    if not careers:
        print("no careers found", file=sys.stderr)
        return 1
    all_sources = sorted({k for c in careers for h in c["horizons"] for k in h["totals"]})
    with open(os.path.join(CAREER, "horizons.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["policy", "seed", "horizon_h", "human_h", "game_days", "funds", "voyages", "harbours", "nm", "fuel_l", "passengers",
                    "rating", "dreams", "works", "renown", "rank", "vessel"] + all_sources)
        for c in careers:
            for h in c["horizons"]:
                w.writerow([c["policy"], c["seed"], h["horizon_h"], h["human_h"], h["game_days"], h["funds"], h["voyages"], h["harbours"], h["nm"],
                            h["fuel_l"], h["passengers"], h["rating"], h["dreams"], h["works"], h["renown"], h["rank"], h["vessel"]]
                           + [int(h["totals"].get(s, 0)) for s in all_sources])
    with open(os.path.join(CAREER, "summary.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        keys = ["policy", "seed", "level", "build", "wall_s", "game_days", "human_hours_est", "voyages", "nm_sail", "nm_engine", "fuel_l", "start_funds",
                "end_funds", "min_funds", "income_total", "expense_total", "low_money_days", "stranded", "services", "end_vessel", "passengers",
                "passenger_income", "rating", "reviews", "works", "writing_income", "renown", "rank", "issues", "encounters", "invitations"]
        w.writerow(keys + ["dreams"])
        for c in careers:
            w.writerow([c.get(k, "") for k in keys] + [len(c.get("dreams_fulfilled", []))])
    # Medians by archetype and horizon.
    policies = sorted({c["policy"] for c in careers})
    print("| Archetype | Horizon (est. h) | Game days | Funds € | Voyages | Harbours | Passengers | Dreams | Works | Renown | Rank |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for p in policies:
        mine = [c for c in careers if c["policy"] == p]
        for hz in [5.0, 10.0, 20.0, 40.0, 80.0, 100.0]:
            rows = [h for c in mine for h in c["horizons"] if float(h["horizon_h"]) == hz]
            if not rows:
                continue
            med = lambda k: statistics.median([float(r[k]) for r in rows])
            print(f"| {p} | {hz:.0f} | {med('game_days'):.0f} | {med('funds'):.0f} | {med('voyages'):.0f} | {med('harbours'):.0f} | "
                  f"{med('passengers'):.0f} | {med('dreams'):.0f} | {med('works'):.0f} | {med('renown'):.0f} | {med('rank'):.0f} |")
    print()
    print("| Archetype | Careers | Wall s (median) | Income at end: work / passengers / writing (median €) | Min funds (lowest) | Stranded |")
    print("|---|---|---|---|---|---|")
    for p in policies:
        mine = [c for c in careers if c["policy"] == p]
        work = statistics.median([int(c["totals"].get("remote_work", 0)) for c in mine])
        pas = statistics.median([int(c.get("passenger_income", 0)) for c in mine])
        wri = statistics.median([int(c.get("writing_income", 0)) for c in mine])
        print(f"| {p} | {len(mine)} | {statistics.median([c['wall_s'] for c in mine]):.0f} | {work:.0f} / {pas:.0f} / {wri:.0f} | "
              f"{min(c['min_funds'] for c in mine)} | {sum(1 for c in mine if c['stranded'])} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
