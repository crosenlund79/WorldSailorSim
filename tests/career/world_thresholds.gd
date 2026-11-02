extends SceneTree
## I028 career verification: the renown it takes to be #1, #10, #50 and #100
## in the world's rankings as the world's own history unfolds (WorldChronicle,
## the real rules), sampled every 25 game days for --days (default 1200) on
## --seeds. The Captain's renown does not change the world's, so a career's
## measured renown curve can be placed against these thresholds afterwards
## (tools/qa/summarize_i028_careers.py). Writes CSV to --out.
##   godot --headless --path . -s res://tests/career/world_thresholds.gd -- --out=FILE [--days=1200] [--seeds=1,2,3]

func _initialize() -> void:
	var out := "user://world_thresholds.csv"
	var days := 1200
	var seeds: Array[int] = [1, 2, 3]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--days="):
			days = int(a.trim_prefix("--days="))
		elif a.begins_with("--seeds="):
			seeds.clear()
			for v in a.trim_prefix("--seeds=").split(",", false):
				seeds.append(int(v))
	var rows: Array[String] = ["seed,day,first,tenth,fiftieth,hundredth,people"]
	var start := 1777593600.0  # 1 May 2026, the game's first day
	for seed in seeds:
		var world := WorldState.new()
		WorldChronicle.advance(world, start, seed)
		for day in range(0, days + 1, 25):
			var now := start + day * 86400.0
			WorldChronicle.advance(world, now, seed)
			var ranks := WorldChronicle.rankings(world, now, -1000000).filter(func(r: Dictionary) -> bool: return r.id != WorldChronicle.CAPTAIN)
			rows.append("%d,%d,%d,%d,%d,%d,%d" % [seed, day, int(ranks[0].renown), int(ranks[9].renown), int(ranks[49].renown), int(ranks[99].renown), ranks.size()])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(rows) + "\n")
	f.close()
	print("WORLD THRESHOLDS DONE: ", out)
	quit()
