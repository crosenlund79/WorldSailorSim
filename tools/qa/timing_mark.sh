#!/bin/bash
# Appends one timing mark (JSON line) to docs/iterations/i027/playtest_fix_timing.jsonl:
#   tools/qa/timing_mark.sh <event> [note]
# Wall clock (ISO 8601 and epoch) and a monotonic clock (CLOCK_MONOTONIC via
# /proc/uptime; it resets if the machine restarts, which the "boot" field shows).
LOG="$(dirname "$0")/../../docs/iterations/i027/playtest_fix_timing.jsonl"
read -r up _ < /proc/uptime
boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
printf '{"event": "%s", "iso": "%s", "epoch": %s, "monotonic_s": %s, "boot": "%s", "note": "%s"}\n' \
	"$1" "$(date --iso-8601=seconds)" "$(date +%s.%N | cut -c1-14)" "$up" "${boot:0:8}" "${2:-}" >> "$LOG"
tail -1 "$LOG"
