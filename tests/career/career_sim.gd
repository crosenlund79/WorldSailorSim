extends Node
## Career playtesting, Mode A (Between Horizons, Part VII; I027 Tier 2): fast
## economy careers on the real game rules. Each career is a new game on a
## seed, played by a simple policy through GameSession and Simulation only -
## remote work, provisions, fuel, harbour dues and real voyages between real
## harbours in the real (seeded) weather - with no money, voyage or
## achievement that the game would not give. The career's own books
## (CareerLedger) and daily snapshots are written as JSON, one file per
## career, plus a summary CSV; since I027 Tier 4 each career's telemetry
## (CareerTelemetry: JSON lines and a CSV) is written beside it.
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
## refill, and the provisions (days) that trigger a top-up. I027 Tier 3:
## "care" has the boatyard do every service it advises (recommended or
## needed) where there is one; "buy" is a boat to buy and move aboard once
## the money covers it and "reserve" besides, at a harbour with a boatyard.
const POLICIES := {
	"frugal": {"work_hours": 4, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.35, "provision_below": 6.0, "hop_nm": [20.0, 70.0]},
	"cruiser": {"work_hours": 3, "stay_days": 1, "motor_upwind": true, "refuel_below": 0.7, "provision_below": 10.0, "hop_nm": [25.0, 90.0]},
	"worker": {"work_hours": 8, "stay_days": 3, "motor_upwind": false, "refuel_below": 0.5, "provision_below": 8.0, "hop_nm": [20.0, 60.0]},
	"keeper": {"work_hours": 4, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.35, "provision_below": 6.0, "hop_nm": [20.0, 70.0],
		"care": true},
	"upgrader": {"work_hours": 6, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.35, "provision_below": 6.0, "hop_nm": [20.0, 70.0],
		"care": true, "buy": "starling_33", "reserve": 3000},
}
## I028 (Passages, People & Reputation): the eight career archetypes. New
## keys: "passengers" publishes each next hop as a passage and accepts the
## requests that come (price factor "price"), "writing" writes a two-hour
## session a harbour day, "invitations" accepts prestigious invitations,
## "companion" starts with that pet, "level" overrides the difficulty.
const I028_POLICIES := {
	"frugal_coastal": {"work_hours": 4, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.3, "provision_below": 5.0, "hop_nm": [15.0, 50.0]},
	"professional_skipper": {"work_hours": 2, "stay_days": 1, "motor_upwind": true, "refuel_below": 0.5, "provision_below": 8.0, "hop_nm": [30.0, 110.0],
		"passengers": true, "price": 1.0, "care": true},
	"independent_explorer": {"work_hours": 3, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.5, "provision_below": 12.0, "hop_nm": [80.0, 240.0]},
	"comfortable_cruiser": {"work_hours": 3, "stay_days": 2, "motor_upwind": true, "refuel_below": 0.8, "provision_below": 12.0, "hop_nm": [20.0, 60.0],
		"care": true},
	"hobbyist_traveller": {"work_hours": 3, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.4, "provision_below": 8.0, "hop_nm": [25.0, 90.0],
		"writing": true},
	"difficult_luck": {"work_hours": 4, "stay_days": 1, "motor_upwind": false, "refuel_below": 0.3, "provision_below": 5.0, "hop_nm": [40.0, 140.0],
		"level": "seasoned"},
	"pet_lover": {"work_hours": 4, "stay_days": 2, "motor_upwind": false, "refuel_below": 0.4, "provision_below": 8.0, "hop_nm": [20.0, 70.0],
		"companion": "dog", "passengers": true, "price": 0.9},
	"prestige_hunter": {"work_hours": 2, "stay_days": 2, "motor_upwind": true, "refuel_below": 0.6, "provision_below": 10.0, "hop_nm": [60.0, 200.0],
		"passengers": true, "price": 1.15, "writing": true, "invitations": true, "care": true},
}
## Estimated human hours at which each career's state is recorded (I028 Section 9).
const HORIZONS := [5.0, 10.0, 20.0, 40.0, 80.0, 100.0]
const HUMAN_MIN_PER_PASSAGE := 3.0
const HUMAN_MIN_PER_ANSWER := 0.5
const HUMAN_MIN_PER_WRITING := 2.0
const CARE_SERVICES: Array[StringName] = [BoatCare.SERVICE_REPAIR, BoatCare.SERVICE_RIG, BoatCare.SERVICE_ENGINE]
const CARE_AREAS := {BoatCare.SERVICE_REPAIR: BoatCare.AREA_HULL, BoatCare.SERVICE_RIG: BoatCare.AREA_RIG, BoatCare.SERVICE_ENGINE: BoatCare.AREA_ENGINE}

var out := "user://career_sim"
var seeds: Array[int] = [1, 2, 3]
var days := 60.0
var policies: Array[String] = ["frugal", "cruiser", "worker"]
var level: StringName = Difficulty.STANDARD
## I028: stop a career at this many estimated human hours (0: by --days only).
var max_hours := 0.0


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
		elif a.begins_with("--hours="):
			max_hours = float(a.trim_prefix("--hours="))
		elif a.begins_with("--level="):
			level = StringName(a.trim_prefix("--level="))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	Simulation.auto_advance = false
	var rows: Array[String] = ["policy,seed,level,build,wall_s,game_days,voyages,nm_sail,nm_engine,fuel_l,start_funds,end_funds,min_funds,income_total,expense_total,low_money_days,human_hours_est,stranded,services,bought_day,end_vessel,passengers,passenger_income,works,writing_income,dreams,renown,rank"]
	for policy in policies:
		for s in seeds:
			var result := _career(policy, s)
			# I027 Tier 4: the career's telemetry (CareerTelemetry), from the same play.
			(result.recorder as CareerTelemetry.Recorder).write("%s/career_%s_%d_telemetry" % [out, policy, s])
			result.erase("recorder")
			var f := FileAccess.open("%s/career_%s_%d.json" % [out, policy, s], FileAccess.WRITE)
			f.store_string(JSON.stringify(result, "  "))
			f.close()
			rows.append("%s,%d,%s,%s,%.1f,%.1f,%d,%.1f,%.1f,%.1f,%d,%d,%d,%d,%d,%d,%.1f,%s,%d,%.1f,%s,%d,%d,%d,%d,%d,%d,%d" % [policy, s, result.level, result.build, result.wall_s,
				result.game_days, result.voyages, result.nm_sail, result.nm_engine, result.fuel_l, result.start_funds, result.end_funds,
				result.min_funds, result.income_total, result.expense_total, result.low_money_days, result.human_hours_est, result.stranded,
					result.services, result.bought_day, result.end_vessel, result.passengers, result.passenger_income, result.works,
					result.writing_income, result.dreams_fulfilled.size(), result.renown, result.rank])
			print("CAREER %s seed %d: %.0f days, %d voyages, €%d -> €%d (wall %.0f s)" % [policy, s, result.game_days, result.voyages,
				result.start_funds, result.end_funds, result.wall_s])
	var csv := FileAccess.open("%s/summary.csv" % out, FileAccess.WRITE)
	csv.store_string("\n".join(rows) + "\n")
	csv.close()
	print("CAREER SIM DONE")
	get_tree().quit()


func _career(policy_name: String, seed_value: int) -> Dictionary:
	var policy: Dictionary = POLICIES[policy_name] if POLICIES.has(policy_name) else I028_POLICIES[policy_name]
	var wall := Time.get_ticks_msec()
	var career_level := StringName(policy.get("level", level))
	GameSession.start_new_session(StringName(policy.get("companion", "")), career_level)
	var state := GameSession.get_state_snapshot()
	state.wind_seed = seed_value
	GameSession.replace_state(state)
	GameSession.set_motor_upwind(bool(policy.motor_upwind))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [policy_name, seed_value])
	var start_time := GameSession.get_game_time()
	var start_funds := GameSession.get_funds()
	var min_funds := start_funds
	var recorder := CareerTelemetry.Recorder.new()
	recorder.start()
	var snapshots: Array = []
	var stops := 0
	var work_sessions := 0
	var underway_hours := 0.0
	var low_money_days := 0
	var stranded := false
	var voyages := 0
	var services := 0
	var bought_day := -1.0
	var extra_minutes := 0.0  # I028: human minutes for passages, answers and writing
	var horizons: Array = []
	while (GameSession.get_game_time() - start_time) / 86400.0 < days and (max_hours <= 0.0 or _human(stops, work_sessions, extra_minutes, underway_hours) < max_hours):
		# In harbour: work, stores, fuel, the nights.
		stops += 1
		while horizons.size() < HORIZONS.size() and float(_human(stops, work_sessions, extra_minutes, underway_hours)) >= float(HORIZONS[horizons.size()]):
			horizons.append(_horizon(float(HORIZONS[horizons.size()]), start_time, float(_human(stops, work_sessions, extra_minutes, underway_hours))))
		var target := _next_port(rng, policy.hop_nm)
		var offer_id := ""
		if bool(policy.get("passengers", false)) and target != &"" and GameSession.plan_route_to(target) == "":
			var published := GameSession.publish_passage([target], GameSession.get_game_time() + float(policy.stay_days) * 86400.0 - 4.0 * 3600.0,
				Marketplace.going_rate(GameSession.get_vessel_id()) * float(policy.get("price", 1.0)))
			if published.ok:
				offer_id = String(published.offer.id)
				extra_minutes += HUMAN_MIN_PER_PASSAGE
		for d in int(policy.stay_days):
			if bool(policy.get("invitations", false)):
				for invitation: Dictionary in GameSession.get_invitations():
					if offer_id != "":
						GameSession.cancel_passage_offer(offer_id)
					var accepted := GameSession.accept_invitation(String(invitation.id))
					if accepted.ok:
						target = StringName(String(invitation.to))
						offer_id = String(accepted.booking.offer)
					extra_minutes += HUMAN_MIN_PER_PASSAGE
			if offer_id != "":
				for request: Dictionary in GameSession.get_passage_requests():
					if String(request.offer) == offer_id:
						GameSession.answer_passage_request(String(request.id), true)
						extra_minutes += HUMAN_MIN_PER_ANSWER
			if bool(policy.get("writing", false)):
				extra_minutes += _write()
			if int(policy.work_hours) > 0 and GameSession.can_work_remotely():
				Simulation.work(int(policy.work_hours))
				work_sessions += 1
			if GameSession.get_provisions().food_days < float(policy.provision_below) or GameSession.get_provisions().water_days < float(policy.provision_below):
				GameSession.buy_provisions()
			if GameSession.get_fuel_l() < float(policy.refuel_below) * GameSession.get_fuel_tank_l():
				GameSession.buy_fuel()
			if bool(policy.get("care", false)) and d == 0:
				services += _care()
			if policy.has("buy") and bought_day < 0.0 and _buy(StringName(policy.buy), int(policy.get("reserve", 0))):
				bought_day = (GameSession.get_game_time() - start_time) / 86400.0
			Simulation.advance(maxf(86400.0 - fposmod(GameSession.get_game_time() - start_time, 86400.0), 3600.0))
			snapshots.append(_snapshot(start_time))
			recorder.mark("day")
			min_funds = mini(min_funds, GameSession.get_funds())
			low_money_days += 1 if GameSession.get_funds() < 200 else 0
		# The next harbour (with the passengers, once they are aboard).
		if target == &"":
			stranded = true
			break
		if offer_id != "":
			var offer := GameSession.get_passage_book().get_offer(offer_id)
			if not offer.is_empty() and GameSession.get_passage_book().bookings_for_offer(offer_id).is_empty():
				GameSession.cancel_passage_offer(offer_id)
			elif not offer.is_empty() and GameSession.get_game_time() < float(offer.depart_after):
				Simulation.advance(float(offer.depart_after) - GameSession.get_game_time() + 60.0)
		var error := GameSession.plan_route_to(target)
		if error != "" or GameSession.depart() != "":
			if offer_id != "":
				GameSession.cancel_passage_offer(offer_id)
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
	recorder.mark("end")
	recorder.stop()
	var ledger := GameSession.get_ledger()
	var income := 0
	var expense := 0
	for source: String in ledger.totals:
		var v := int(ledger.totals[source])
		if v > 0:
			income += v
		else:
			expense -= v
	var human_hours: float = _human(stops, work_sessions, extra_minutes, underway_hours)
	horizons.append(_horizon(human_hours, start_time, human_hours))
	var book := GameSession.get_passage_book()
	var standing := GameSession.get_captain_standing()
	var writing := GameSession.get_writing()
	return {
		"policy": policy_name, "seed": seed_value, "level": String(career_level),
		"passengers": int(book.totals.passengers), "passenger_income": int(book.totals.fares) + int(book.totals.tips) - int(book.totals.refunds),
		"works": (writing.get("works", []) as Array).size(), "writing_income": int(ledger.totals.get("writing", 0)),
		"renown": int(standing.get("renown", 0)), "rank": int(standing.get("rank", 0)), "horizons": horizons,
		"rating": book.rating().x, "reviews": int(book.rating().y), "issues": GameSession.get_world().issues.size(),
		"encounters": GameSession.get_world().encounters.size(), "invitations": GameSession.get_invitations(true).size(), "build": GameVersion.build_label(true),
		"policy_settings": policy, "wall_s": (Time.get_ticks_msec() - wall) / 1000.0,
		"game_days": (GameSession.get_game_time() - start_time) / 86400.0, "voyages": voyages, "stops": stops,
		"nm_sail": ledger.nm_sail, "nm_engine": ledger.nm_engine, "fuel_l": ledger.fuel_burned_l,
		"start_funds": start_funds, "end_funds": GameSession.get_funds(), "min_funds": min_funds,
		"income_total": income, "expense_total": expense, "totals": ledger.totals, "low_money_days": low_money_days,
		"human_hours_est": human_hours, "human_time_model": "estimate: %.0f min per harbour stop, %.0f min per work session, %.0f s per game hour under way (20x)" % [
			HUMAN_MIN_PER_STOP, HUMAN_MIN_PER_WORK, HUMAN_S_PER_GAME_HOUR_UNDERWAY],
		"stranded": stranded, "voyage_log": ledger.voyages, "snapshots": snapshots,
		"services": services, "bought_day": bought_day, "end_vessel": String(GameSession.get_vessel_id()),
		"dreams_fulfilled": GameSession.get_state_snapshot().dreams.fulfilled.keys(), "recorder": recorder,
	}


## The human-time estimate (the model above, plus I028's passages, answers and writing).
func _human(stops: int, work_sessions: int, extra_minutes: float, underway_hours: float) -> float:
	return (stops * HUMAN_MIN_PER_STOP + work_sessions * HUMAN_MIN_PER_WORK + extra_minutes) / 60.0 + underway_hours * HUMAN_S_PER_GAME_HOUR_UNDERWAY / 3600.0


## A career's state at an estimated-human-hours horizon (I028 Section 9).
func _horizon(hours: float, start_time: float, actual: float) -> Dictionary:
	var ledger := GameSession.get_ledger()
	var book := GameSession.get_passage_book()
	var standing := GameSession.get_captain_standing()
	return {"horizon_h": hours, "human_h": snappedf(actual, 0.1), "game_days": snappedf((GameSession.get_game_time() - start_time) / 86400.0, 0.1),
		"funds": GameSession.get_funds(), "totals": ledger.totals.duplicate(), "nm": snappedf(ledger.nm_sail + ledger.nm_engine, 1.0),
		"fuel_l": snappedf(ledger.fuel_burned_l, 1.0), "voyages": GameSession.get_captains_log().voyages_completed,
		"harbours": GameSession.get_captains_log().get_visited_ids().size(), "passengers": int(book.totals.passengers),
		"rating": snappedf(book.rating().x, 0.01), "dreams": GameSession.get_state_snapshot().dreams.fulfilled.size(),
		"works": (GameSession.get_writing().get("works", []) as Array).size(), "renown": int(standing.get("renown", 0)),
		"rank": int(standing.get("rank", 0)), "vessel": String(GameSession.get_vessel_id())}


## A writing session in harbour: a work begun when there is none (the
## longest form the Captain is ready for, about the newest topic), and two
## hours on it with the angle that suits its topic. Returns human minutes.
func _write() -> float:
	var writing := GameSession.get_writing()
	if (writing.get("project", {}) as Dictionary).is_empty():
		var topics := GameSession.writing_topics()
		if topics.is_empty():
			return 0.0
		var works := (writing.get("works", []) as Array).filter(func(w: Dictionary) -> bool: return not w.get("legacy", false)).size()
		var forms := TravelWriting.forms().duplicate()
		forms.reverse()
		for f: Dictionary in forms:
			if TravelWriting.form_problem(f, GameSession.get_captains_log(), works) == "":
				GameSession.start_writing(String(f.id), String(topics[0].id))
				break
		writing = GameSession.get_writing()
	var project: Dictionary = writing.get("project", {})
	if project.is_empty():
		return 0.0
	GameSession.work_on_writing(String(project.topic.get("angle", "places")), TravelWriting.session_hours() * 60.0)
	Simulation.spend_time_aboard(TravelWriting.session_hours() * 60.0)
	return HUMAN_MIN_PER_WRITING


func _snapshot(start_time: float) -> Dictionary:
	return {"day": snappedf((GameSession.get_game_time() - start_time) / 86400.0, 0.01), "funds": GameSession.get_funds(),
		"fuel_l": snappedf(GameSession.get_fuel_l(), 0.1), "location": String(GameSession.get_location_id()),
		"food_days": snappedf(GameSession.get_provisions().food_days, 0.1)}


## The boatyard's advised services here (recommended or needed), each paid and
## its time spent ashore; a haul-out when the bottom wants one. Returns how
## many were done.
func _care() -> int:
	var done := 0
	var care := GameSession.get_boat_care()
	var now := GameSession.get_game_time()
	for service in CARE_SERVICES:
		var level := BoatCare.area_level(CARE_AREAS[service], care, GameSession.get_condition(), now)
		if level in [BoatCare.LEVEL_RECOMMENDED, BoatCare.LEVEL_NEEDED] and GameSession.service_refusal(service) == "":
			var result := GameSession.perform_service(service)
			if String(result.error) == "":
				Simulation.spend_time_ashore(float(result.minutes))
				done += 1
	var fouling := BoatCare._level(BoatCare.fouling(GameSession.get_boat_care(), GameSession.get_game_time()), BoatCare.FOULING_COSMETIC,
		BoatCare.FOULING_RECOMMENDED, BoatCare.FOULING_NEEDED)
	if fouling in [BoatCare.LEVEL_RECOMMENDED, BoatCare.LEVEL_NEEDED] and GameSession.service_refusal(BoatCare.SERVICE_HAUL_OUT) == "":
		var hauled := GameSession.haul_out()
		if String(hauled.error) == "":
			Simulation.spend_time_ashore(float(hauled.minutes))
			done += 1
	return done


## Buys `vessel_id` and moves aboard when the money covers it and `reserve`
## besides, where there is a boatyard. True when it did.
func _buy(vessel_id: StringName, reserve: int) -> bool:
	var vessel := VesselCatalog.get_default().get_vessel(vessel_id)
	if vessel == null or GameSession.owns_vessel(vessel_id) or GameSession.get_funds() < vessel.price + reserve or not GameSession.can_change_vessel():
		return false
	return GameSession.buy_vessel(vessel_id) == "" and GameSession.switch_vessel(vessel_id) == ""


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
