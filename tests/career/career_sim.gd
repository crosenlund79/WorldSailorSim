extends Node
## Career playtesting, Mode A (Between Horizons, Part VII; I027 Tier 2): fast
## economy careers on the real game rules. Each career is a new game on a
## seed, played by a simple policy through GameSession and Simulation only -
## remote work, provisions, fuel, harbour dues and real voyages between real
## harbours in the real (seeded) weather - with no money, voyage or
## achievement that the game would not give. The career's own books
## (CareerLedger) and daily snapshots are written as JSON, one file per
## career, plus a summary CSV.
##   godot --headless --path . res://tests/career/career_sim.tscn -- \
##     [--out=DIR] [--seeds=1,2,3] [--days=60] [--policies=frugal,cruiser,worker] [--level=standard]
##
## Three clocks are kept apart (Part VII, 78): the wall-clock time this run
## took, the in-game time that passed, and an ESTIMATE of a human player's
## active time (a labelled model, below) - never presented as playtesting.
## Uses the test save folder; never touches the player's files.

## Human-time model (an estimate, not a measurement): minutes per harbour
## stop (walking the quay, shops, planning), per remote-work session, and
## real seconds per game hour under way watched at 20× (3 s) - a player who
## used Long Passage would need less.
const HUMAN_MIN_PER_STOP := 8.0
const HUMAN_MIN_PER_WORK := 1.0
const HUMAN_S_PER_GAME_HOUR_UNDERWAY := 3.0

## The policies: hours of remote work a day in harbour, days in each
## harbour, whether to motor to windward, the fuel share that triggers a
## refill, and the provisions (days) that trigger a top-up.
const POLICIES := {
	"frugal": {"work_hours": 4, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.35, "provision_below": 6.0, "hop_nm": [20.0, 70.0]},
	"cruiser": {"work_hours": 3, "stay_days": 1, "motor_upwind": true, "refuel_below": 0.7, "provision_below": 10.0, "hop_nm": [25.0, 90.0]},
	"worker": {"work_hours": 8, "stay_days": 3, "motor_upwind": false, "refuel_below": 0.5, "provision_below": 8.0, "hop_nm": [20.0, 60.0]},
}

var out := "user://career_sim"
var seeds: Array[int] = [1, 2, 3]
var days := 60.0
var policies: Array[String] = ["frugal", "cruiser", "worker"]
var level: StringName = Difficulty.STANDARD


func _ready() -> void:
	SaveManager.save_dir = "user://test_saves"
	SettingsManager.settings_path = "user://test_settings.cfg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--seeds="):
			seeds.clear()
			for v in a.trim_prefix("--seeds=").split(",", false):
				seeds.append(int(v))
		elif a.begins_with("--days="):
			days = float(a.trim_prefix("--days="))
		elif a.begins_with("--policies="):
			policies.clear()
			for v in a.trim_prefix("--policies=").split(",", false):
				policies.append(v)
		elif a.begins_with("--level="):
			level = StringName(a.trim_prefix("--level="))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	var rows: Array[String] = ["policy,seed,level,build,wall_s,game_days,voyages,nm_sail,nm_engine,fuel_l,start_funds,end_funds,min_funds,income_total,expense_total,low_money_days,human_hours_est,stranded"]
	for policy in policies:
		for s in seeds:
			var result := _career(policy, s)
			var f := FileAccess.open("%s/career_%s_%d.json" % [out, policy, s], FileAccess.WRITE)
			f.store_string(JSON.stringify(result, "  "))
			rows.append("%s,%d,%s,%s,%.1f,%.1f,%d,%.1f,%.1f,%.1f,%d,%d,%d,%d,%d,%d,%.1f,%s" % [policy, s, level, result.build, result.wall_s,
				result.game_days, result.voyages, result.nm_sail, result.nm_engine, result.fuel_l, result.start_funds, result.end_funds,
				result.min_funds, result.income_total, result.expense_total, result.low_money_days, result.human_hours_est, result.stranded])
			print("CAREER %s seed %d: %.0f days, %d voyages, €%d -> €%d (wall %.0f s)" % [policy, s, result.game_days, result.voyages,
				result.start_funds, result.end_funds, result.wall_s])
	var csv := FileAccess.open("%s/summary.csv" % out, FileAccess.WRITE)
	csv.store_string("\n".join(rows) + "\n")
	csv.close()
	print("CAREER SIM DONE")
	get_tree().quit()


func _career(policy_name: String, seed_value: int) -> Dictionary:
	var policy: Dictionary = POLICIES[policy_name]
	var wall := Time.get_ticks_msec()
	GameSession.start_new_session(&"", level)
	var state := GameSession.get_state_snapshot()
	state.wind_seed = seed_value
	GameSession.replace_state(state)
	GameSession.set_motor_upwind(bool(policy.motor_upwind))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [policy_name, seed_value])
	var start_time := GameSession.get_game_time()
	var start_funds := GameSession.get_funds()
	var min_funds := start_funds
	var snapshots: Array = []
	var stops := 0
	var work_sessions := 0
	var underway_hours := 0.0
	var low_money_days := 0
	var stranded := false
	var voyages := 0
	while (GameSession.get_game_time() - start_time) / 86400.0 < days:
		# In harbour: work, stores, fuel, the nights.
		stops += 1
		for d in int(policy.stay_days):
			if int(policy.work_hours) > 0 and GameSession.can_work_remotely():
				Simulation.work(int(policy.work_hours))
				work_sessions += 1
			if GameSession.get_provisions().food_days < float(policy.provision_below) or GameSession.get_provisions().water_days < float(policy.provision_below):
				GameSession.buy_provisions()
			if GameSession.get_fuel_l() < float(policy.refuel_below) * GameSession.get_fuel_tank_l():
				GameSession.buy_fuel()
			Simulation.advance(maxf(86400.0 - fposmod(GameSession.get_game_time() - start_time, 86400.0), 3600.0))
			snapshots.append(_snapshot(start_time))
			min_funds = mini(min_funds, GameSession.get_funds())
			low_money_days += 1 if GameSession.get_funds() < 200 else 0
		# The next harbour.
		var target := _next_port(rng, policy.hop_nm)
		if target == &"":
			stranded = true
			break
		var error := GameSession.plan_route_to(target)
		if error != "" or GameSession.depart() != "":
			continue
		var departed := GameSession.get_game_time()
		var guard := 0
		while GameSession.is_underway() and guard < 400:
			Simulation.advance(3.0 * 3600.0)
			if GameSession.is_holding_at_anchorage():
				GameSession.sail_on_from_anchorage()
			if GameSession.is_anchored():
				GameSession.raise_anchor()
			guard += 1
		underway_hours += (GameSession.get_game_time() - departed) / 3600.0
		voyages += 1
		if GameSession.is_underway():
			stranded = true
			break
		snapshots.append(_snapshot(start_time))
		min_funds = mini(min_funds, GameSession.get_funds())
	var ledger := GameSession.get_ledger()
	var income := 0
	var expense := 0
	for source: String in ledger.totals:
		var v := int(ledger.totals[source])
		if v > 0:
			income += v
		else:
			expense -= v
	var human_hours := (stops * HUMAN_MIN_PER_STOP + work_sessions * HUMAN_MIN_PER_WORK) / 60.0 + underway_hours * HUMAN_S_PER_GAME_HOUR_UNDERWAY / 3600.0
	return {
		"policy": policy_name, "seed": seed_value, "level": String(level), "build": GameVersion.build_label(true),
		"policy_settings": policy, "wall_s": (Time.get_ticks_msec() - wall) / 1000.0,
		"game_days": (GameSession.get_game_time() - start_time) / 86400.0, "voyages": voyages, "stops": stops,
		"nm_sail": ledger.nm_sail, "nm_engine": ledger.nm_engine, "fuel_l": ledger.fuel_burned_l,
		"start_funds": start_funds, "end_funds": GameSession.get_funds(), "min_funds": min_funds,
		"income_total": income, "expense_total": expense, "totals": ledger.totals, "low_money_days": low_money_days,
		"human_hours_est": human_hours, "human_time_model": "estimate: %.0f min per harbour stop, %.0f min per work session, %.0f s per game hour under way (20x)" % [
			HUMAN_MIN_PER_STOP, HUMAN_MIN_PER_WORK, HUMAN_S_PER_GAME_HOUR_UNDERWAY],
		"stranded": stranded, "voyage_log": ledger.voyages, "snapshots": snapshots,
	}


func _snapshot(start_time: float) -> Dictionary:
	return {"day": snappedf((GameSession.get_game_time() - start_time) / 86400.0, 0.01), "funds": GameSession.get_funds(),
		"fuel_l": snappedf(GameSession.get_fuel_l(), 0.1), "location": String(GameSession.get_location_id()),
		"food_days": snappedf(GameSession.get_provisions().food_days, 0.1)}


## A harbour `hop_nm` away (min, max) by great-circle distance, at random
## on the career's own seed; widens the ring when there is none.
func _next_port(rng: RandomNumberGenerator, hop_nm: Array) -> StringName:
	var here := GameSession.get_vessel_position()
	var current := GameSession.get_location_id()
	for widen in [1.0, 1.5, 2.5]:
		var candidates: Array[StringName] = []
		for port: PortData in PortCatalog.get_default().ports:
			if port.id == current:
				continue
			var d := GeoMath.distance_nm(here, port.get_geo_position())
			if d >= float(hop_nm[0]) / widen and d <= float(hop_nm[1]) * widen:
				candidates.append(port.id)
		if not candidates.is_empty():
			return candidates[rng.randi_range(0, candidates.size() - 1)]
	return &""
