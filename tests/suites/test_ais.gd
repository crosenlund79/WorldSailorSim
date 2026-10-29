extends RefCounted
## I027 Tier 4, AIS preparation: the receiver surface over the existing local
## traffic (AisReceiver) - contacts near Copenhagen within VHF reach only,
## nearest first, the same every time, fictional MMSIs, class A for ships and
## B for small craft; the CPA and TCPA arithmetic; no game, no contacts.

var t: Node


func run(runner: Node) -> void:
	t = runner
	GameSession.end_session()
	t.check(AisReceiver.contacts().is_empty(), "[ais] no game, no contacts")
	GameSession.start_new_session()
	SeaRouter.get_default()  # the sea chart, as in the game (no chart loaded: no traffic)
	# Out in the Sound off Copenhagen (as the traffic suite looks), until there is traffic.
	var here := PortCatalog.get_default().get_port(&"copenhagen").get_geo_position() + Vector2(0.3, 0.2)
	var found: Array[Dictionary] = []
	var time := GameSession.get_game_time()
	for k in 48:
		found = AisReceiver.contacts_at(here, time + k * 1800.0, 3, 0.0, 0.0, 100.0)
		if found.size() >= 2:
			time += k * 1800.0
			break
	var again := AisReceiver.contacts_at(here, time, 3, 0.0, 0.0, 100.0)
	var near_first := true
	for i in range(1, found.size()):
		near_first = near_first and float(found[i - 1].range_nm) <= float(found[i].range_nm)
	t.check(found.size() >= 2 and found.all(func(c: Dictionary) -> bool: return float(c.range_nm) <= AisReceiver.RANGE_NM) and near_first,
		"[ais] off Copenhagen: %d contacts, all within VHF reach (%.0f nm, even when asked for 100), nearest first" % [found.size(), AisReceiver.RANGE_NM])
	t.check(JSON.stringify(found) == JSON.stringify(again), "[ais] the same place and time always give the same contacts")
	var mmsis_ok := found.all(func(c: Dictionary) -> bool: return int(c.mmsi) >= AisReceiver.MMSI_BASE and int(c.mmsi) < 1000000000)
	var classes_ok := found.all(func(c: Dictionary) -> bool:
		return c["class"] == (AisReceiver.CLASS_A if StringName(c.kind) in AisReceiver.CLASS_A_KINDS else AisReceiver.CLASS_B))
	t.check(mmsis_ok and classes_ok and found.all(func(c: Dictionary) -> bool: return String(c.name) != "" and c.has("cog") and c.has("sog_kn")),
		"[ais] each with a fictional MMSI, a name, a class (A ships, B small craft), course and speed over ground")
	# CPA / TCPA: a ship 6 nm due north heading south at 12 kn, the boat still.
	var head_on := AisReceiver.approach(Vector2(0, 6), 0.0, 0.0, 180.0, 12.0)
	var crossing := AisReceiver.approach(Vector2(-3, 3), 90.0, 6.0, 90.0, 6.0)
	var passed := AisReceiver.approach(Vector2(0, -2), 0.0, 0.0, 180.0, 10.0)
	t.check(head_on.x < 0.01 and absf(head_on.y - 30.0) < 0.01 and absf(crossing.x - Vector2(-3, 3).length()) < 0.01
		and passed.y < 0.0 and absf(passed.x - 2.0) < 0.01,
		"[ais] CPA and TCPA: head-on 0 nm in 30 min; a ship keeping pace stays as far; one already past is past")
	GameSession.end_session()
