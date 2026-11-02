extends RefCounted
## I028 (Passages, People & Reputation), Tiers 1-3: the passage trade played
## through the real game - offers built from the chart's routes, requests and
## competing skippers, bargaining, capacity leg by leg, passengers boarding
## and going ashore at different stops of one passage, the weather and the
## clock they sail in, settlement (deposit, balance, refunds, tips, reviews),
## a delayed passage, an alternative harbour agreed under way, and save/load
## with people aboard (no payment twice). Voyages are sailed by Simulation.

var t: Node
const HOUR := 3600.0


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	_test_rules()
	_test_offer_and_requests()
	_test_multi_leg_passage()
	_test_delayed_passage()
	_test_alternate_harbour()
	_test_save_mid_passage()
	_test_personalities()
	_test_dreams_and_rewards()
	Simulation.auto_advance = true
	t.use_calm_wind()
	GameSession.end_session()


func _new_game() -> void:
	GameSession.start_new_session(&"")
	t.set_wind(250.0, 12.0)  # a steady breeze: the boats sail as a player would


func _book() -> PassageBook:
	return GameSession.get_passage_book()


## Sails until the boat is in harbour again (calm: under engine).
func _sail_to_harbour(max_days := 10.0) -> void:
	var until := GameSession.get_game_time() + max_days * 86400.0
	while GameSession.is_underway() and GameSession.get_game_time() < until:
		Simulation.advance(2.0 * HOUR)


func _advance_moored(hours: float) -> void:
	Simulation.advance(hours * HOUR)


func _test_rules() -> void:
	t.check(Marketplace.skippers().size() >= 8, "[market] %d competing skippers" % Marketplace.skippers().size())
	t.check(Marketplace.going_rate(&"halcyon_40") > Marketplace.going_rate(&"arctic_wanderer_26"), "[market] a spacious yacht asks a higher rate than a simple one")
	var offer := {"leg_nm": [30.0, 40.0], "leg_s": [6.0 * HOUR, 30.0 * HOUR], "rate": 1.4}
	t.check(Marketplace.fare(offer, 0, 1, 1) == int(snappedf(maxf(30.0 * 1.4, Marketplace.MIN_FARE), 5.0)), "[market] a day leg: distance times rate (or the least fare)")
	t.check(Marketplace.fare(offer, 0, 2, 2) > Marketplace.fare(offer, 0, 2, 1) and Marketplace.nights(offer, 1, 2) >= 1,
		"[market] two people pay more; a 30-hour leg is a night aboard")
	var a := Travellers.make(42, "t1")
	var b := Travellers.make(42, "t1")
	t.check(a == b and a.has("budget") and a.has("weather") and a.has("allergies"), "[travellers] the same seed makes the same person, with traits")
	var allergic := a.duplicate(true)
	allergic.allergies = ["cat"]
	t.check(not Travellers.tolerates_pets(allergic, ["cat"]) and Travellers.tolerates_pets(allergic, ["dog"]), "[travellers] an allergy to cats rules out a boat with a cat")
	t.check(TransferAccess.band(&"copenhagen").rank == 0 and not TransferAccess.band(&"copenhagen").estimate and TransferAccess.band(&"lyo").estimate,
		"[transfer] Copenhagen: airport within the hour (curated); a small island harbour: an estimate")


func _test_offer_and_requests() -> void:
	_new_game()
	var none := GameSession.publish_passage([])
	t.check(not none.ok, "[offer] a passage needs somewhere to go (%s)" % none.error)
	GameSession.plan_route_to(&"svendborg")
	var stops := GameSession.passage_candidate_stops()
	t.check(not stops.is_empty(), "[offer] harbours along the planned course can be stops (%s)" % [stops.slice(0, 4)])
	var published := GameSession.publish_passage([stops[0], &"svendborg"])
	t.check(published.ok, "[offer] a passage from Copenhagen via %s to Svendborg is published (%s)" % [stops[0], published.error])
	if not published.ok:
		return
	var offer: Dictionary = published.offer
	t.check((offer.leg_nm as Array).size() == 2 and float(offer.leg_nm[0]) > 0.0 and float(offer.arrive[2]) > float(offer.depart[1]),
		"[offer] each leg is planned and timed on the chart (%.0f + %.0f nm)" % [float(offer.leg_nm[0]), float(offer.leg_nm[1])])
	t.check(not GameSession.publish_passage([&"svendborg"]).ok, "[offer] one published passage at a time")
	var made := _book().requests
	t.check(not made.is_empty(), "[requests] travellers answer the offer (%d)" % made.size())
	var shown_now := GameSession.get_passage_requests().size()
	_advance_moored(10.0)
	t.check(GameSession.get_passage_requests(true).size() >= shown_now, "[requests] requests arrive over the following hours")
	var lost := made.filter(func(r: Dictionary) -> bool: return r.status == PassageBook.REQUEST_LOST)
	print("    requests %d, lost to other skippers %d%s" % [made.size(), lost.size(), (": " + String(lost[0].note)) if not lost.is_empty() else ""])
	# Bargaining.
	var rid := GameSession.add_passage_request_for_testing(String(offer.id), 0, 2, 1, 7)
	var request := _book().get_request(rid)
	var asked := int(request.asked)
	var high := GameSession.answer_passage_request(rid, true, int(asked * 1.25))
	t.check(high.result == "countered", "[bargain] asking 25 %% more brings a counter-offer (%s)" % high.text)
	var again := GameSession.answer_passage_request(rid, true, int(asked * 1.3))
	t.check(again.result == "refused", "[bargain] pushing again after the counter-offer: they look elsewhere")
	var rid2 := GameSession.add_passage_request_for_testing(String(offer.id), 0, 2, 1, 8)
	var funds := GameSession.get_funds()
	var fair := GameSession.answer_passage_request(rid2, true, int(_book().get_request(rid2).asked * 1.05))
	t.check(fair.result == "booked" and GameSession.get_funds() > funds, "[bargain] a fair price within their means is booked, the deposit paid (%s)" % fair.text)
	var cancel_funds := GameSession.get_funds()
	var booking_id := String(_book().get_request(rid2).booking)
	t.check(GameSession.cancel_passage_booking(booking_id) == "" and GameSession.get_funds() < cancel_funds, "[contract] cancelling returns the deposit")
	t.check(GameSession.cancel_passage_offer(String(offer.id)) == "", "[offer] a passage that has not left can be withdrawn")


## Different passengers on different legs of one route: two board in
## Copenhagen, one leaves at the stop, one joins there; capacity per leg.
func _test_multi_leg_passage() -> void:
	_new_game()
	GameSession.plan_route_to(&"svendborg")
	var stop: StringName = GameSession.passage_candidate_stops()[0]
	var published := GameSession.publish_passage([stop, &"svendborg"])
	var offer: Dictionary = published.offer
	var oid := String(offer.id)
	for request: Dictionary in _book().requests:  # only our own passengers in this test
		if request.status == PassageBook.REQUEST_PENDING:
			GameSession.answer_passage_request(String(request.id), false)
	var whole := GameSession.add_passage_request_for_testing(oid, 0, 2, 1, 11)
	var first_leg := GameSession.add_passage_request_for_testing(oid, 0, 1, 1, 12)
	var second_leg := GameSession.add_passage_request_for_testing(oid, 1, 2, 1, 13)
	for rid in [whole, first_leg, second_leg]:
		GameSession.answer_passage_request(rid, true)
	var room := Accommodation.safe_guest_count(GameSession.get_vessel_id())
	var too_many := GameSession.add_passage_request_for_testing(oid, 0, 2, room, 14)
	var full := GameSession.answer_passage_request(too_many, true)
	t.check(full.result == "error" and "No room" in String(full.text), "[capacity] the first leg is full: %s" % full.text)
	# The long second leg is sailed through the night: a bed each (the settees).
	var beds := Accommodation.overnight_guest_count(GameSession.get_vessel_id())
	var over := GameSession.add_passage_request_for_testing(oid, 1, 2, 1, 15)
	var night := GameSession.answer_passage_request(over, true)
	t.check(night.result == "error" and beds == 2, "[capacity] the overnight leg has %d beds, both taken: %s" % [beds, night.text])
	var booked := _book().bookings_for_offer(oid).size()
	t.check(GameSession.depart() != "" or GameSession.get_game_time() >= float(offer.depart_after) - GameSession.BOARDING_LEAD_S,
		"[boarding] the boat waits for its passengers")
	_advance_moored((float(offer.depart_after) - GameSession.get_game_time()) / HOUR)
	t.check(_book().aboard().size() == 2, "[boarding] the two Copenhagen passengers came aboard (%d)" % _book().aboard().size())
	GameSession.plan_route_to(stop)
	var left := GameSession.depart()
	t.check(left == "", "[voyage] cast off with passengers (%s)" % left)
	_sail_to_harbour()
	t.check(GameSession.get_location_id() == stop, "[voyage] arrived at the stop, %s" % stop)
	var after_stop := _book()
	t.check(after_stop.records.size() == 1 and after_stop.records[0].disembark == String(stop), "[settle] the one-leg passenger went ashore at the stop, with a record")
	t.check((after_stop.records[0].legs as Array).size() == 1, "[ledger] their record holds the one leg they sailed")
	t.check(GameSession.get_planned_route() != null and GameSession.get_planned_route().destination_port_id == &"svendborg",
		"[voyage] the passage's next leg is plotted to Svendborg")
	var refusal := GameSession.depart()
	if refusal != "":
		_advance_moored(maxf((float(after_stop.get_offer(oid).depart[1]) - GameSession.get_game_time()) / HOUR, 0.1))
		refusal = GameSession.depart()
	t.check(refusal == "" and GameSession.get_passengers_aboard().size() >= 2, "[boarding] the passengers joining at %s came aboard; on to Svendborg" % stop)
	_sail_to_harbour()
	var done := _book()
	t.check(GameSession.get_location_id() == &"svendborg" and done.records.size() == booked - 0, "[settle] everyone ashore in Svendborg: %d records for %d bookings" % [done.records.size(), booked])
	var whole_record: Dictionary = done.records.filter(func(r: Dictionary) -> bool: return r.embark == "copenhagen" and r.disembark == "svendborg")[0]
	t.check((whole_record.legs as Array).size() == 2 and float(whole_record.nm) > float(done.records[0].nm), "[ledger] the whole-route passenger sailed both legs")
	t.check(done.get_offer(oid).status == PassageBook.STATUS_DONE, "[offer] the passage is done")
	var paid := 0
	for r: Dictionary in done.records:
		paid += int(r.paid)
	t.check(paid > 0 and int(done.totals.passengers) == booked and int(done.totals.reviews) == booked,
		"[settle] fares paid (%s in all), every passenger counted and reviewed once" % GameSession.format_money(paid))


func _test_delayed_passage() -> void:
	_new_game()
	GameSession.plan_route_to(&"helsingor")
	var offer: Dictionary = GameSession.publish_passage([&"helsingor"]).offer
	var rid := GameSession.add_passage_request_for_testing(String(offer.id), 0, 1, 1, 21, {"timing": "strict"})
	GameSession.answer_passage_request(rid, true)
	# The Captain lingers two days past the window before leaving.
	_advance_moored((float(offer.depart_before) - GameSession.get_game_time()) / HOUR + 48.0)
	GameSession.plan_route_to(&"helsingor")
	GameSession.depart()
	_sail_to_harbour()
	var record: Dictionary = _book().records.back() if not _book().records.is_empty() else {}
	t.check(not record.is_empty() and float(record.late_h) > 24.0 and int(record.refund) > 0,
		"[delay] two days late, without a reason of weather: a refund (%s, %.0f h late)" % [GameSession.format_money(int(record.get("refund", 0))), float(record.get("late_h", 0.0))])
	t.check(int(record.get("satisfaction", 100)) < GuestReactions.START, "[delay] a strict traveller is unhappy (%d)" % int(record.get("satisfaction", 0)))


func _test_alternate_harbour() -> void:
	_new_game()
	GameSession.plan_route_to(&"svendborg")
	var offer: Dictionary = GameSession.publish_passage([&"svendborg"]).offer
	var rid := GameSession.add_passage_request_for_testing(String(offer.id), 0, 1, 1, 31, {"timing": "relaxed", "detour": "enjoys"})
	GameSession.answer_passage_request(rid, true)
	_advance_moored((float(offer.depart_after) - GameSession.get_game_time()) / HOUR)
	GameSession.plan_route_to(&"svendborg")
	GameSession.depart()
	Simulation.advance(2.0 * HOUR)
	var booking: Dictionary = _book().aboard()[0]
	var original_fare := int(booking.fare)
	var answer := GameSession.propose_alternate_harbour(String(booking.id), &"korsor")
	t.check(answer.ok, "[alternate] a relaxed traveller accepts Korsør instead of Svendborg: %s" % answer.text)
	GameSession.change_course(&"korsor", [] as Array[Vector2])
	_sail_to_harbour()
	var record: Dictionary = _book().records.back() if not _book().records.is_empty() else {}
	t.check(not record.is_empty() and record.disembark == "korsor" and record.booked_disembark == "svendborg" and int(record.paid) < original_fare,
		"[alternate] ashore in Korsør, booked for Svendborg: paid %s of %s" % [GameSession.format_money(int(record.get("paid", 0))), GameSession.format_money(original_fare)])
	t.check((record.diversions as Array).size() == 1 and record.diversions[0].accepted, "[ledger] the agreed diversion is on the record")


func _test_save_mid_passage() -> void:
	_new_game()
	GameSession.plan_route_to(&"gothenburg")
	var offer: Dictionary = GameSession.publish_passage([&"gothenburg"]).offer
	var rid := GameSession.add_passage_request_for_testing(String(offer.id), 0, 1, 2, 41)
	GameSession.answer_passage_request(rid, true)
	_advance_moored((float(offer.depart_after) - GameSession.get_game_time()) / HOUR)
	GameSession.plan_route_to(&"gothenburg")
	GameSession.depart()
	Simulation.advance(4.0 * HOUR)
	var data := GameSession.get_state_snapshot().to_dict()
	var errors: Array[String] = []
	var restored := SessionState.from_dict(JSON.parse_string(JSON.stringify(data)), errors)
	t.check(errors.is_empty() and restored.passages.aboard().size() == 1 and JSON.stringify(restored.passages.to_dict()) == JSON.stringify(PassageBook.from_dict(JSON.parse_string(JSON.stringify(data.passages))).to_dict()),
		"[save] the passage trade survives save and load, passengers aboard")
	GameSession.replace_state(restored)
	var funds := GameSession.get_funds()
	_sail_to_harbour()
	var after := _book()
	t.check(after.records.size() == 1 and GameSession.get_funds() - funds == int(after.records[0].paid) - int(after.records[0].deposit) + int(after.records[0].tip),
		"[save] settled once after the reload: balance and tip, the deposit not paid again")
	var reloaded := SessionState.from_dict(GameSession.get_state_snapshot().to_dict(), errors)
	t.check(reloaded.passages.records.size() == 1 and int(reloaded.passages.totals.bookings) == 1, "[save] the record is kept, never doubled")
	t.check(SaveManager.SAVE_VERSION == 12, "[save] the save format is unchanged (12)")


## Tier 2: the same events, felt through different traits; allergies and pets.
func _test_personalities() -> void:
	var anxious := {"id": "t1", "weather": "anxious", "motivation": "reach", "pets": "neutral", "timing": "normal"}
	var hardy := {"id": "t2", "weather": "hardy", "motivation": "adventure", "pets": "likes", "timing": "relaxed"}
	var a := {"id": "b1", "satisfaction": 70.0, "events": []}
	var h := {"id": "b2", "satisfaction": 70.0, "events": []}
	var now := 1000.0
	GuestReactions.on_weather(a, anxious, 2, now)
	GuestReactions.on_weather(h, hardy, 2, now)
	t.check(float(a.satisfaction) < 70.0 and float(h.satisfaction) > 70.0, "[people] a gale: the anxious passenger suffers (%.0f), the hardy one enjoys it (%.0f)" % [float(a.satisfaction), float(h.satisfaction)])
	var before := float(a.satisfaction)
	GuestReactions.on_caution(a, anxious, now + 60.0)
	t.check(float(a.satisfaction) > before and a.get("excused", false), "[people] waiting out the weather: the anxious passenger is grateful, and the delay is excused")
	GuestReactions.on_weather(a, anxious, 2, now + 120.0)
	t.check(float(a.satisfaction) == before + 8.0, "[people] the same reaction is not counted twice within hours")
	var photo := {"id": "t3", "motivation": "photo", "background": "photographer"}
	var plain := {"id": "t4", "motivation": "reach", "background": "nurse"}
	var p := {"id": "b3", "satisfaction": 70.0, "events": []}
	var q := {"id": "b4", "satisfaction": 70.0, "events": []}
	GuestReactions.on_scenic(p, photo, now)
	GuestReactions.on_scenic(q, plain, now)
	t.check(float(p.satisfaction) > float(q.satisfaction), "[people] a scenic harbour means more to the photographer")
	var late := {"id": "b5", "satisfaction": 70.0, "events": [], "excused": true}
	var late2 := {"id": "b6", "satisfaction": 70.0, "events": []}
	GuestReactions.on_arrival_time(late, {"timing": "strict"}, 20.0, now)
	GuestReactions.on_arrival_time(late2, {"timing": "relaxed"}, 20.0, now)
	t.check(float(late.satisfaction) > 50.0 and float(late2.satisfaction) > 65.0, "[people] late for good reason, or for a relaxed traveller: little harm")
	var contract := {"id": "b7", "fare": 300, "paid": 90, "booked_nm": 60.0, "sailed_nm": 60.0, "promised": 0.0, "excused": true, "satisfaction": 80.0}
	t.check(int(Settlement.settle(contract, {"reviews": "fair"}, 3.0 * 86400.0).refund) == 0, "[contract] safe seamanship is never punished: no refund for an excused delay")
	_new_game()
	var state := GameSession.get_state_snapshot()
	state.companions.append(CompanionState.create(CompanionState.KIND_CAT, state.game_time, "Mosse"))
	GameSession.replace_state(state)
	GameSession.plan_route_to(&"helsingor")
	var offer: Dictionary = GameSession.publish_passage([&"helsingor"]).offer
	var rid := GameSession.add_passage_request_for_testing(String(offer.id), 0, 1, 1, 51, {"pets": "allergic", "allergies": ["cat"]})
	var refused := GameSession.answer_passage_request(rid, true)
	t.check(refused.result == "error" and "allergic" in String(refused.text), "[pets] a cat aboard: an allergic traveller cannot be booked (%s)" % refused.text)
	var lover := GameSession.add_passage_request_for_testing(String(offer.id), 0, 1, 1, 52, {"pets": "likes"})
	GameSession.answer_passage_request(lover, true)
	Simulation.advance((float(offer.depart_after) - GameSession.get_game_time()) / HOUR * HOUR)
	var aboard := GameSession.get_passengers_aboard()
	var chat := GameSession.chat_with_passenger(String(aboard[0].booking.id)) if not aboard.is_empty() else ""
	t.check(chat != "", "[people] a word with a passenger aboard: “%s”" % chat)


## Tier 4: passengers' dreams judged by the legs they sailed; the Captain's
## own dreams from the passage trade; letters, keepsakes, achievements.
func _test_dreams_and_rewards() -> void:
	var crossing := {"kind": PassengerDreams.KIND_CROSSING, "met": false}
	var european_leg := {"legs_sailed": [{"from": "lisbon", "to": "funchal", "departed": 0.0, "arrived": 50.0 * HOUR}]}
	var whole_way := {"legs_sailed": [{"from": "lisbon", "to": "las_palmas", "departed": 0.0, "arrived": 60.0 * HOUR},
		{"from": "mindelo", "to": "castries", "departed": 70.0 * HOUR, "arrived": 400.0 * HOUR}]}
	t.check(not PassengerDreams.is_met(crossing, european_leg) and PassengerDreams.is_met(crossing, whole_way),
		"[dreams] one leg towards the Caribbean is not an Atlantic crossing; Cape Verde to St Lucia aboard is")
	var night := {"kind": PassengerDreams.KIND_NIGHT}
	t.check(not PassengerDreams.is_met(night, {"legs_sailed": [{"departed": 0.0, "arrived": 4.0 * HOUR, "to": "x", "from": "y"}]})
		and PassengerDreams.is_met(night, {"legs_sailed": [{"departed": 0.0, "arrived": 20.0 * HOUR, "to": "x", "from": "y"}]}),
		"[dreams] a first night at sea needs a leg sailed through the night")
	var reach := {"kind": PassengerDreams.KIND_REACH, "port": "aeroskobing"}
	t.check(PassengerDreams.is_met(reach, {"disembark": "aeroskobing", "legs_sailed": [{"from": "svendborg", "to": "aeroskobing", "departed": 0.0, "arrived": 3.0 * HOUR}]})
		and not PassengerDreams.is_met(reach, {"disembark": "marstal", "legs_sailed": [{"from": "svendborg", "to": "marstal", "departed": 0.0, "arrived": 3.0 * HOUR}]}),
		"[dreams] a childhood island means arriving there, not near it")
	var atlantic := Dreams.get_dream(&"atlantic_crossing")
	var progress := ObjectiveProgress.new()
	t.check(not Dreams.is_met(atlantic, null, [], {"progress": progress}), "[dreams] the Captain's Atlantic crossing: not before it is sailed")
	progress.mark(&"dreamfact:atlantic_crossing", 1.0)
	t.check(Dreams.is_met(atlantic, null, [], {"progress": progress}), "[dreams] marked when a voyage from Europe or Africa reaches the Caribbean or America")
	# Real play: a passenger who dreams of a night at sea, on the overnight leg.
	_new_game()
	GameSession.set_dream_pursued(&"dream_for_another", true)
	GameSession.plan_route_to(&"svendborg")
	var offer: Dictionary = GameSession.publish_passage([&"svendborg"]).offer
	var rid := GameSession.add_passage_request_for_testing(String(offer.id), 0, 1, 1, 61,
		{"dream": {"kind": PassengerDreams.KIND_NIGHT, "met": false}, "reviews": "generous", "weather": "hardy", "comfort": "simple"})
	GameSession.answer_passage_request(rid, true)
	Simulation.advance((float(offer.depart_after) - GameSession.get_game_time()) / HOUR * HOUR)
	GameSession.plan_route_to(&"svendborg")
	GameSession.depart()
	_sail_to_harbour()
	var book := _book()
	var record: Dictionary = book.records.back() if not book.records.is_empty() else {}
	t.check(not record.is_empty() and record.dream.get("met", false) and int(book.totals.dreams) == 1,
		"[dreams] the night at sea came true for the passenger: on the record, counted once")
	t.check(GameSession.get_objective_progress().is_completed(&"passengers:dream") and GameSession.get_objective_progress().is_completed(&"passengers:first"),
		"[rewards] achievements: first passengers, someone else's dream")
	t.check(GameSession.get_dream_status(&"dream_for_another") == GameSession.DREAM_FULFILLED and GameSession.get_dream_status(&"first_guests") == GameSession.DREAM_FULFILLED,
		"[dreams] the Captain's own dreams of the trade came true with it")
	t.check(GameSession.get_dream_status(&"night_with_guests") == GameSession.DREAM_FULFILLED, "[dreams] a night under sail with guests: from the sailed leg")
	var letters := GameSession.get_passenger_letters()
	t.check(not letters.is_empty() and letters[0].kind == "letter", "[rewards] a thank-you letter: “%s”" % (String(letters[0].text) if not letters.is_empty() else ""))
	var catalog := AchievementCatalog.get_default()
	t.check(catalog != null and catalog.get_errors().is_empty() if catalog.has_method(&"get_errors") else catalog != null,
		"[rewards] the achievement collection loads with the passenger achievements")
