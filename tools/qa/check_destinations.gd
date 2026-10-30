extends SceneTree
## Checks the researched cruising destinations (tools/navigation/cruising_destinations.csv)
## against the game's own charts before and after they are imported (Regions and
## Harbours 2026): a harbour needs a harbour approach from open water
## (SeaRouter.find_port_approach, as test_harbours) and land close by; an
## anchorage must pass the anchoring rule (GameSession.anchorage_spot), or the
## nearest spot that does is reported with its distance.
##   godot --headless --path . -s tools/qa/check_destinations.gd [-- --csv=path]
## Prints one line per destination ("ok" / "FAIL ...") and a summary.

const CSV := "res://tools/navigation/cruising_destinations.csv"


func _initialize() -> void:
	var path := CSV
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--csv="):
			path = a.substr(6)
	var file := FileAccess.open(path, FileAccess.READ)
	var header := file.get_csv_line()
	var router := SeaRouter.get_default()
	# GameSession is an autoload, not a compiled identifier in a -s script: its
	# static anchoring rule is called through the script.
	var session: GDScript = load("res://src/core/game_session.gd")
	var failed := 0
	var total := 0
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.size() < header.size():
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = values[i]
		total += 1
		var geo := Vector2(float(row.longitude), float(row.latitude))
		var line := ""
		if row.kind == "anchorage":
			var spot: Dictionary = session.anchorage_spot(geo)
			if spot.ok:
				line = "ok anchorage %s (%s m, land %.2f nm)" % [row.id, snappedf(float(spot.depth_m), 0.1), float(spot.land_nm)]
			else:
				var near: Vector2 = session.nearest_anchorage_spot(geo, 2.0)
				line = "FAIL anchorage %s: %s; nearest good spot %s" % [row.id, spot.reason,
					"none within 2 nm" if near == Vector2.INF else "%.2f nm at %.5f,%.5f" % [GeoMath.distance_nm(geo, near), near.y, near.x]]
		else:
			var port := PortData.new()
			port.id = StringName("check_" + String(row.id))
			port.latitude = geo.y
			port.longitude = geo.x
			var approach := router.find_port_approach(port)
			var region := router.grid.region_id_at(geo)
			line = ("ok harbour %s [%s]" % [row.id, region]) if not approach.is_empty() else ("FAIL harbour %s [%s]: no approach from open water" % [row.id, region])
		if line.begins_with("FAIL"):
			failed += 1
		print(line)
	print("SUMMARY %d destinations, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
