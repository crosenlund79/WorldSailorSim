class_name CareerTelemetry
extends RefCounted
## Career telemetry (Between Horizons, I027 Tier 4; Part VII): timestamped,
## reproducible records of a career, taken from the real game - nothing
## invented, nothing new to keep track of. A snapshot reads what the game
## already records: the career's books (CareerLedger: every euro by source,
## fuel, miles and each voyage's figures), the boat and its care, the
## inventory, the Captain's Log, achievements and renown, and Dreams of the
## Sea. A Recorder takes one on the game's own events (an arrival, a boat
## bought, a dream fulfilled) and when asked, and writes them as JSON lines
## and a flat CSV. Local files only; nothing is sent anywhere. Used by the
## career playtesting harness (tests/career/career_sim.gd); the passenger
## figures (fares, refunds, satisfaction) arrive with I028.

const VERSION := 1
## The CSV's columns (flat; the JSON lines hold everything).
const CSV_COLUMNS := ["reason", "game_time", "day", "funds", "income", "expenses", "vessel", "owned_boats", "instruments", "fuel_l",
	"fuel_tank_l", "condition", "food_days", "water_days", "voyages", "nm_total", "nm_sail", "nm_engine", "fuel_burned_l",
	"harbours", "longest_nm", "renown", "achievements", "dreams_fulfilled"]


## Everything a career record holds now (an empty dictionary without a game).
## `start_time` makes "day" count from the career's start.
static func snapshot(reason := "", start_time := 0.0) -> Dictionary:
	if not GameSession.is_active():
		return {}
	var ledger := GameSession.get_ledger()
	var log := GameSession.get_captains_log()
	var progress := GameSession.get_objective_progress()
	var provisions := GameSession.get_provisions()
	var vessel_id := GameSession.get_vessel_id()
	var income := 0
	var expenses := 0
	for source: String in ledger.totals:
		var v := int(ledger.totals[source])
		if v > 0:
			income += v
		else:
			expenses -= v
	var owned: Array[String] = []
	var list_value := 0
	for id in GameSession.get_owned_vessels():
		owned.append(String(id))
		var definition := VesselCatalog.get_default().get_vessel(id)
		list_value += definition.price if definition else 0
	var care := GameSession.get_boat_care()
	var now := GameSession.get_game_time()
	var condition := GameSession.get_condition()
	var fulfilled: Array[String] = []
	for dream in Dreams.all():
		if GameSession.get_dream_status(StringName(dream.id)) == GameSession.DREAM_FULFILLED:
			fulfilled.append(String(dream.id))
	var achievements := AchievementCatalog.get_default().count_unlocked(progress)
	var last_voyage: Dictionary = ledger.voyages.back() if not ledger.voyages.is_empty() else {}
	return {
		"version": VERSION, "reason": reason, "build": GameVersion.build_label(true),
		"time": {"game_time": now, "day": snappedf((now - start_time) / 86400.0, 0.01), "date": Simulation.format_game_time(now, false),
			"location": String(GameSession.get_location_id()), "underway": GameSession.is_underway()},
		"finances": {"funds": GameSession.get_funds(), "income": income, "expenses": expenses, "by_source": ledger.totals.duplicate(),
			# Net worth: money plus the boats at their list prices - an estimate (there is no boat sale yet).
			"net_worth_estimate": GameSession.get_funds() + list_value},
		"boat": {"vessel": String(vessel_id), "owned": owned, "instruments": GameSession.get_instrument_package().id,
			"fuel_l": snappedf(GameSession.get_fuel_l(), 0.1), "fuel_tank_l": GameSession.get_fuel_tank_l(),
			"condition": snappedf(condition, 0.1),
			"care": {"hull": String(BoatCare.area_level(BoatCare.AREA_HULL, care, condition, now)),
				"rig": String(BoatCare.area_level(BoatCare.AREA_RIG, care, condition, now)),
				"engine": String(BoatCare.area_level(BoatCare.AREA_ENGINE, care, condition, now))},
			"sleeping_places": Accommodation.sleeping_places(vessel_id), "private_guest_cabins": Accommodation.private_guest_cabins(vessel_id),
			"safe_guests": Accommodation.safe_guest_count(vessel_id), "overnight_guests": Accommodation.overnight_guest_count(vessel_id),
			"dues_per_night_here": GameSession.get_harbour_dues_per_night() if GameSession.is_moored_in_harbour() else 0,
			"fuel_burn_lph": Economy.burn_lph(vessel_id)},
		"inventory": {"food_days": snappedf(provisions.food_days, 0.1), "water_days": snappedf(provisions.water_days, 0.1),
			"lures": GameSession.get_fishing().lures.duplicate(), "hat": String(GameSession.get_hat_status())},
		"voyages": {"completed": log.voyages_completed, "nm_total": snappedf(log.total_nm, 0.1), "nm_sail": snappedf(ledger.nm_sail, 0.1),
			"nm_engine": snappedf(ledger.nm_engine, 0.1), "fuel_bought_l": snappedf(ledger.fuel_bought_l, 0.1),
			"fuel_burned_l": snappedf(ledger.fuel_burned_l, 0.1), "harbours": log.get_distinct_harbours(),
			"longest_nm": snappedf(log.get_longest_nm(), 0.1), "last": last_voyage.duplicate(true)},
		"progression": {"renown": progress.lifetime_renown, "achievements": achievements.x, "achievements_total": achievements.y,
			"dreams_fulfilled": fulfilled, "dreams_pursued": GameSession.get_pursued_dreams().map(func(id: StringName) -> String: return String(id))},
	}


## One flat CSV row for `record` (CSV_COLUMNS).
static func csv_row(record: Dictionary) -> String:
	var f: Dictionary = record.get("finances", {})
	var b: Dictionary = record.get("boat", {})
	var i: Dictionary = record.get("inventory", {})
	var v: Dictionary = record.get("voyages", {})
	var p: Dictionary = record.get("progression", {})
	var t: Dictionary = record.get("time", {})
	var values := [record.get("reason", ""), t.get("game_time", 0.0), t.get("day", 0.0), f.get("funds", 0), f.get("income", 0),
		f.get("expenses", 0), b.get("vessel", ""), "|".join(b.get("owned", [])), b.get("instruments", ""), b.get("fuel_l", 0.0),
		b.get("fuel_tank_l", 0.0), b.get("condition", 0.0), i.get("food_days", 0.0), i.get("water_days", 0.0), v.get("completed", 0),
		v.get("nm_total", 0.0), v.get("nm_sail", 0.0), v.get("nm_engine", 0.0), v.get("fuel_burned_l", 0.0), v.get("harbours", 0),
		v.get("longest_nm", 0.0), p.get("renown", 0), p.get("achievements", 0), "|".join(p.get("dreams_fulfilled", []))]
	return ",".join(values.map(func(x: Variant) -> String: return str(x).replace(",", ";")))


## Records snapshots on the game's own events and when asked (mark).
class Recorder:
	extends RefCounted
	var records: Array[Dictionary] = []
	var start_time := 0.0
	var _hooks: Array = []

	## Starts listening: an arrival, a boat bought or changed, a dream.
	func start() -> void:
		start_time = GameSession.get_game_time()
		_hook(GameSession.voyage_arrived, func(_port: StringName) -> void: mark("arrival"))
		_hook(GameSession.fleet_changed, func() -> void: mark("fleet"))
		_hook(GameSession.dreams_changed, func() -> void: mark("dreams"))
		mark("start")

	func stop() -> void:
		for hook: Array in _hooks:
			if (hook[0] as Signal).is_connected(hook[1]):
				(hook[0] as Signal).disconnect(hook[1])
		_hooks.clear()

	func mark(reason: String) -> void:
		var record := CareerTelemetry.snapshot(reason, start_time)
		if not record.is_empty():
			records.append(record)

	func to_jsonl() -> String:
		return "\n".join(records.map(func(r: Dictionary) -> String: return JSON.stringify(r))) + "\n"

	func to_csv() -> String:
		var rows := PackedStringArray([",".join(CareerTelemetry.CSV_COLUMNS)])
		for record in records:
			rows.append(CareerTelemetry.csv_row(record))
		return "\n".join(rows) + "\n"

	## Writes `<base>.jsonl` and `<base>.csv`. Returns true when both were written.
	func write(base: String) -> bool:
		var ok := true
		for pair: Array in [[".jsonl", to_jsonl()], [".csv", to_csv()]]:
			var file := FileAccess.open(base + String(pair[0]), FileAccess.WRITE)
			if file == null:
				ok = false
				continue
			file.store_string(String(pair[1]))
			file.close()
		return ok

	func _hook(sig: Signal, callable: Callable) -> void:
		sig.connect(callable)
		_hooks.append([sig, callable])
