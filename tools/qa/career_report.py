#!/usr/bin/env python3
"""Career playtesting report (Between Horizons, Part VII; I027).

Reads the JSON careers written by tests/career/career_sim.tscn and writes:
  summary.csv            one row per career (the three clocks kept apart)
  report.md              per-batch, per-policy medians, ranges and failures
  money_over_time.png    median money by in-game day, one line per policy

Usage: python3 tools/qa/career_report.py OUT_DIR BATCH_DIR [BATCH_DIR ...]
Each BATCH_DIR is named after its batch (e.g. std, relaxed). No numbers are
invented: every figure comes from a career's own books.
"""
import csv
import glob
import json
import os
import statistics as st
import sys

from PIL import Image, ImageDraw, ImageFont

# Reference categorical order (dataviz palette, light mode), ink tokens.
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"]
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
GRID = "#e4e3df"


def load(batch_dirs):
    careers = []
    for d in batch_dirs:
        batch = os.path.basename(os.path.normpath(d))
        for f in sorted(glob.glob(os.path.join(d, "career_*.json"))):
            c = json.load(open(f))
            c["batch"] = batch
            careers.append(c)
    return careers


def median_series(careers, max_day):
    """Median money at each whole in-game day (last snapshot at or before it)."""
    out = []
    for day in range(0, max_day + 1):
        vals = []
        for c in careers:
            v = c["start_funds"]
            for s in c["snapshots"]:
                if s["day"] <= day:
                    v = s["funds"]
            vals.append(v)
        out.append(st.median(vals))
    return out


def font(size):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def chart(groups, path, max_day=90):
    W, H, L, R, T, B = 1200, 640, 90, 210, 70, 70
    img = Image.new("RGB", (W, H), SURFACE)
    d = ImageDraw.Draw(img)
    series = {k: median_series(v, max_day) for k, v in groups.items()}
    lo = min(min(s) for s in series.values())
    hi = max(max(s) for s in series.values())
    lo = int(lo // 2000 * 2000)
    hi = int((hi // 2000 + 1) * 2000)
    x = lambda day: L + (W - L - R) * day / max_day
    y = lambda v: T + (H - T - B) * (1 - (v - lo) / (hi - lo))
    d.text((L, 22), "Median money over 90 in-game days, by career policy", fill=INK, font=font(20))
    for v in range(lo, hi + 1, 2000):
        d.line([(L, y(v)), (W - R, y(v))], fill=GRID, width=1)
        d.text((L - 10, y(v)), f"€{v:,}", fill=INK_2, font=font(13), anchor="rm")
    for day in range(0, max_day + 1, 15):
        d.text((x(day), H - B + 14), str(day), fill=INK_2, font=font(13), anchor="mt")
    d.text(((L + W - R) / 2, H - 24), "in-game day", fill=INK_2, font=font(13), anchor="mm")
    for i, (name, s) in enumerate(series.items()):
        colour = SERIES[i % len(SERIES)]
        pts = [(x(day), y(v)) for day, v in enumerate(s)]
        d.line(pts, fill=colour, width=2)
        ex, ey = pts[-1]
        d.ellipse([ex - 4, ey - 4, ex + 4, ey + 4], fill=colour, outline=SURFACE, width=2)
        d.text((ex + 10, ey), f"{name}  €{int(s[-1]):,}", fill=INK, font=font(14), anchor="lm")
    # Legend (always, for two or more series).
    lx, ly = L, T - 26
    for i, name in enumerate(series):
        colour = SERIES[i % len(SERIES)]
        d.line([(lx, ly + 8), (lx + 22, ly + 8)], fill=colour, width=3)
        d.text((lx + 28, ly + 8), name, fill=INK_2, font=font(13), anchor="lm")
        lx += 40 + d.textlength(name, font=font(13))
    img.save(path)


def main():
    out, dirs = sys.argv[1], sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    careers = load(dirs)
    with open(os.path.join(out, "summary.csv"), "w", newline="") as f:
        w = csv.writer(f)
        keys = ["batch", "policy", "seed", "level", "build", "wall_s", "game_days", "human_hours_est", "voyages", "nm_sail", "nm_engine",
                "fuel_l", "start_funds", "end_funds", "min_funds", "income_total", "expense_total", "low_money_days", "stranded"]
        w.writerow(keys)
        for c in careers:
            w.writerow([round(c[k], 2) if isinstance(c[k], float) else c[k] for k in keys])
    groups = {}
    for c in careers:
        groups.setdefault((c["batch"], c["policy"]), []).append(c)
    lines = ["| Batch | Policy | Careers | End money: median (range) | Lowest money | Voyages | nm sail / engine | Fuel (L) | Est. human hours | Wall s | Stranded |",
             "|---|---|---|---|---|---|---|---|---|---|---|"]
    sources = sorted({s for c in careers for s in c["totals"]})
    for (batch, policy), g in groups.items():
        med = lambda k: st.median([c[k] for c in g])
        lines.append(f"| {batch} | {policy} | {len(g)} | €{int(med('end_funds')):,} (€{min(c['end_funds'] for c in g):,}–€{max(c['end_funds'] for c in g):,}) | "
                     f"€{min(c['min_funds'] for c in g):,} | {int(med('voyages'))} | {int(med('nm_sail'))} / {int(med('nm_engine'))} | {int(med('fuel_l'))} | "
                     f"{med('human_hours_est'):.1f} | {med('wall_s'):.0f} | {sum(1 for c in g if c['stranded'])} |")
    lines += ["", "Income (+) and costs (-) by source, median over the careers, euros:", "",
              "| Batch | Policy | " + " | ".join(sources) + " |", "|---|---|" + "---|" * len(sources)]
    for (batch, policy), g in groups.items():
        vals = [int(st.median([c["totals"].get(s, 0) for c in g])) for s in sources]
        lines.append(f"| {batch} | {policy} | " + " | ".join(f"{v:+,}" for v in vals) + " |")
    open(os.path.join(out, "report.md"), "w").write("\n".join(lines) + "\n")
    std = {p: g for (b, p), g in groups.items() if b == "std"}
    if std:
        chart(std, os.path.join(out, "money_over_time.png"))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
