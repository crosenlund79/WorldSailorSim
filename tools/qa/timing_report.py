"""Summarises a timing log written by tools/qa/timing_mark.sh (JSON lines).

Usage: python3 tools/qa/timing_report.py docs/iterations/i027/playtest_fix_timing.jsonl

Prints a Markdown table of the stages (each "<name>_begin" paired with its
"<name>_end"), using the monotonic clock when both marks share a boot (else
the wall clock), and the total from the first mark to the last. Only what the
log measured is reported: nothing is estimated.
"""
import json
import sys


def main(path):
    marks = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
    begins = {}
    rows = []
    for m in marks:
        event = m["event"]
        if event.endswith("_begin"):
            begins[event[: -len("_begin")]] = m
        elif event.endswith("_end"):
            name = event[: -len("_end")]
            b = begins.pop(name, None)
            if b is None:
                continue
            same_boot = b.get("boot") == m.get("boot")
            seconds = (m["monotonic_s"] - b["monotonic_s"]) if same_boot else (m["epoch"] - b["epoch"])
            rows.append((name, b["iso"], m["iso"], seconds, m.get("note", "")))
    first, last = marks[0], marks[-1]
    total = (last["monotonic_s"] - first["monotonic_s"]) if first.get("boot") == last.get("boot") else (last["epoch"] - first["epoch"])
    print("| Stage | Began | Ended | Duration | Note |")
    print("|---|---|---|---|---|")
    for name, b, e, s, note in rows:
        print(f"| {name} | {b[11:19]} | {e[11:19]} | {fmt(s)} | {note} |")
    print()
    print(f"Total, first mark to last: {fmt(total)} ({first['iso']} to {last['iso']})")
    open_stages = ", ".join(sorted(begins)) or "none"
    print(f"Stages begun but not ended: {open_stages}")


def fmt(seconds):
    seconds = int(round(seconds))
    return f"{seconds // 60} min {seconds % 60:02d} s"


if __name__ == "__main__":
    main(sys.argv[1])
