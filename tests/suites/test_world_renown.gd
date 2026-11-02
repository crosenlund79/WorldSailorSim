extends RefCounted
## I028 Tier 6: Sails & Sights (one issue per month, frozen, never twice after
## a reload), the rankings (deterministic, stable ties, the Captain's goals
## awarded once), the yacht directory (last public reports, unknown and stale
## marked) kept apart from AIS (live, within range only), a meeting on the
## quay, a prestigious invitation becoming a real booking, and the end-to-end
## scenario: Freya Voss, Maya Wildshore and Northern Promise bound for
## Greenland, consistent across every view.

var t: Node
const DAY := 86400.0
const HOUR := 3600.0


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	_test_freya_scenario()
	_test_invitation()
	Simulation.auto_advance = true
	t.use_calm_wind()
	GameSession.end_session()


func _norm(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _moor_at(port_id: StringName) -> void:
	var state := GameSession.get_state_snapshot()
	state.location_id = port_id
	state.vessel_status = SessionState.STATUS_MOORED
	state.vessel_position = PortCatalog.get_default().get_port(port_id).get_geo_position()
	state.voyage = null
	state.planned_route = null
	state.anchor = AnchorState.new()
	GameSession.replace_state(state)


func _test_freya_scenario() -> void:
	GameSession.start_new_session(&"")
	t.set_wind(250.0, 12.0)
	_moor_at(&"lerwick")  # the expedition's first stop after Bergen
	GameSession.advance_world(true)
	var news: Array[String] = []
	var on_news := func(text: String) -> void: news.append(text)
	GameSession.world_news.connect(on_news)
	var met := false
	var ais_at_meeting: Array[Dictionary] = []
	for day in 45:
		Simulation.advance(DAY)
		GameSession.advance_world(true)
		if not met and GameSession.get_world().encounters.has("northern_promise"):
			met = true
			ais_at_meeting = GameSession.get_notable_ais_contacts()
	GameSession.world_news.disconnect(on_news)
	var world := GameSession.get_world()
	var now := GameSession.get_game_time()
	# The ledger: announced, then sailed stop by stop with both explorers aboard.
	var announced := world.events.filter(func(e: Dictionary) -> bool: return e.kind == "expedition_announced" and e.expedition == "greenland_promise")
	t.check(announced.size() == 1 and "freya_voss" in (announced[0].who as Array) and "maya_wildshore" in (announced[0].who as Array),
		"[freya] the Greenland expedition is announced once, Freya Voss and Maya Wildshore named")
	var legs := world.events.filter(func(e: Dictionary) -> bool: return e.get("expedition", "") == "greenland_promise" and e.kind in ["arrive", "expedition_complete"])
	var ports := legs.map(func(e: Dictionary) -> String: return String(e.port))
	t.check(ports.size() >= 2 and ports.has("lerwick"), "[freya] Northern Promise has sailed the expedition's stops: %s" % str(ports))
	var stops: Array = WorldChronicle._expedition("greenland_promise").stops
	var in_order := true
	var last := 0
	for p: String in ports:
		var i := stops.find(p)
		if i < last:
			in_order = false
		last = maxi(last, i)
	t.check(in_order, "[freya] the stops come in the expedition's order, none skipped back")
	# The meeting on the quay in Lerwick, when Northern Promise came in.
	t.check(met and news.any(func(n: String) -> bool: return "Northern Promise" in n and "Freya Voss" in n),
		"[freya] a coffee on the quay in Lerwick with Freya Voss and Maya Wildshore")
	var meeting := world.events.filter(func(e: Dictionary) -> bool: return e.kind == "meeting" and e.yacht == "northern_promise")
	t.check(meeting.size() >= 1 and String(meeting[0].port) == "lerwick" and WorldChronicle.CAPTAIN in (meeting[0].who as Array),
		"[freya] the meeting is in the world's history, in Lerwick")
	# AIS at the meeting: Northern Promise right here; it is the live view.
	var np := ais_at_meeting.filter(func(c: Dictionary) -> bool: return c.yacht == "northern_promise")
	t.check(np.size() == 1 and float(np[0].range_nm) < 1.0 and String(np[0].skipper) == "Freya Voss" and String(np[0].class) == "B",
		"[ais] at the meeting, AIS shows Northern Promise alongside (class B, Freya Voss)")
	var far := AisReceiver.notable_contacts_at(world, PortCatalog.get_default().get_port(&"copenhagen").get_geo_position(), now, 0.0, 0.0)
	t.check(not far.any(func(c: Dictionary) -> bool: return c.yacht == "northern_promise"), "[ais] from Copenhagen, AIS cannot hear it: no worldwide tracking")
	# The directory: the last public report, consistent with the ledger and the network.
	var entry: Dictionary = GameSession.get_yacht_directory("northern")[0]
	var report: Dictionary = entry.report
	var truth := WorldChronicle.yacht_position(world, "northern_promise", now)
	t.check(entry.name == "Northern Promise" and entry.skipper == "Freya Voss" and not entry.unknown and float(report.t) <= now,
		"[directory] Northern Promise is listed with Freya Voss and a public report")
	var same_time := world.events.filter(func(e: Dictionary) -> bool: return e.get("yacht", "") == "northern_promise" and float(e.t) == float(report.t))
	var reported_event := same_time.filter(func(e: Dictionary) -> bool: return e.kind == report.kind and String(e.get("port", "")) == String(report.port))
	t.check(reported_event.size() >= 1 and not TravellerNetwork.post_for(reported_event[0]).is_empty(),
		"[directory] the report is the yacht's own latest post on the network (%s)" % str(same_time.map(func(e: Dictionary) -> String: return String(e.kind))))
	t.check(GameSession.get_yacht_directory("Freya")[0].id == "northern_promise" and GameSession.get_yacht_directory("zzzz").is_empty(),
		"[directory] searchable by skipper; nothing matches nonsense")
	var stale_flagged := GameSession.get_yacht_directory().all(func(e: Dictionary) -> bool:
		return e.unknown or bool(e.stale) == (float(e.age_days) > YachtDirectory.STALE_DAYS))
	t.check(stale_flagged, "[directory] every report older than %d days is flagged stale; yachts that never posted are unknown" % int(YachtDirectory.STALE_DAYS))
	t.check(String(truth.status) in ["in_port", "under_way"], "[directory] the live position (%s) is AIS's to show, not the directory's" % truth.status)
	# The network: the announcement is posted by Freya Voss, with a picture.
	var posts := GameSession.get_network_posts(500)
	var post := posts.filter(func(p: Dictionary) -> bool: return p.kind == "expedition_announced" and p.yacht == "northern_promise")
	t.check(post.size() == 1 and post[0].author == "freya_voss" and String(post[0].image) != "" and "Greenland" in String(post[0].text),
		"[network] Freya Voss announces the expedition on the network, with a picture")
	# Sails & Sights: the month's issue tells of it; frozen and never twice.
	var issues := GameSession.get_magazine_issues()
	t.check(issues.size() >= 1, "[magazine] %d issue(s) of Sails & Sights after 45 days" % issues.size())
	var all_stories: Array = []
	for issue: Dictionary in issues:
		all_stories.append_array(issue.stories)
	t.check(all_stories.any(func(s: Dictionary) -> bool: return String(s.kind).begins_with("expedition") and "freya_voss" in (s.who as Array)),
		"[magazine] the expedition is in the magazine")
	var errors: Array[String] = []
	var reloaded := SessionState.from_dict(JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict(), "", true, true)), errors)
	var before := _norm(reloaded.world.issues)
	GameSession.replace_state(reloaded)
	GameSession.advance_world(true)
	t.check(_norm(GameSession.get_world().issues) == before, "[magazine] after a reload, the archive is unchanged and no issue is published twice")
	var ids := GameSession.get_world().issues.map(func(i: Dictionary) -> String: return String(i.id))
	var unique := {}
	for id: String in ids:
		unique[id] = true
	t.check(unique.size() == ids.size(), "[magazine] one issue per month: %s" % str(ids))
	# Rankings: Freya among them; deterministic; ties broken by id.
	var rows := GameSession.get_rankings()
	var freya := rows.filter(func(r: Dictionary) -> bool: return r.id == "freya_voss")
	t.check(freya.size() == 1 and int(freya[0].rank) <= 10, "[rankings] Freya Voss is among the best-known (no. %d)" % int(freya[0].rank))
	var stable := true
	for i in range(1, rows.size()):
		var a: Dictionary = rows[i - 1]
		var b: Dictionary = rows[i]
		if int(a.renown) < int(b.renown) or (int(a.renown) == int(b.renown) and String(a.id) > String(b.id)):
			stable = false
	t.check(stable and _norm(rows) == _norm(GameSession.get_rankings()), "[rankings] ordered by renown, ties by id, the same when asked again")


func _test_invitation() -> void:
	# Qualify the Captain for Freya Voss's invitation, moored in Lerwick.
	GameSession.start_new_session(&"")
	t.set_wind(250.0, 12.0)
	_moor_at(&"lerwick")
	GameSession.advance_world(true)
	var greenland: Dictionary = GameSession.invitation_data().filter(func(d: Dictionary) -> bool: return d.id == "greenland_scouts")[0]
	t.check(GameSession.invitation_problem(greenland) != "", "[invitation] not yet: %s" % GameSession.invitation_problem(greenland))
	t.check(GameSession.get_invitations().is_empty(), "[invitation] no invitation without the qualifications")
	GameSession._state.progress.lifetime_renown += 900
	GameSession._state.passages.totals.reviews = 4
	GameSession._state.passages.totals.stars = 19
	GameSession._state.captains_log.record_voyage({"from": "bergen", "to": "lerwick", "departed": 100.0, "ended": 90000.0, "nm": 190.0, "vessel": "",
		"outcome": "arrived", "worst_hazard": 1, "damage": 0.0, "complete": true})
	var standing := GameSession.get_captain_standing()
	t.check(GameSession.invitation_problem(greenland) == "", "[invitation] qualified: rank %d, 4 reviews of 4.8 stars, 190 nm" % int(standing.rank))
	var invitations := GameSession.get_invitations()
	var invite := invitations.filter(func(i: Dictionary) -> bool: return i.id == "greenland_scouts")
	t.check(invite.size() == 1 and String(invite[0].to) != "lerwick" and "Freya Voss" in String(invite[0].text),
		"[invitation] Freya Voss and Maya Wildshore ask to sail to %s" % (invite[0].to if not invite.is_empty() else "?"))
	t.check(GameSession.get_invitations().size() == invitations.size(), "[invitation] asked once")
	var funds := GameSession.get_funds()
	var result := GameSession.accept_invitation("greenland_scouts")
	var booking: Dictionary = result.get("booking", {})
	t.check(result.ok and not booking.is_empty() and GameSession.get_funds() > funds, "[invitation] accepted: a real booking, the deposit paid (%s)" % result.get("error", ""))
	var traveller := GameSession.get_passage_book().get_traveller(String(booking.get("traveller", "")))
	t.check(Travellers.display_name(traveller) == "Freya Voss & Maya Wildshore" and int(booking.get("size", 0)) == 2,
		"[invitation] booked as Freya Voss & Maya Wildshore, two guests (%s)" % Travellers.display_name(traveller))
	t.check(not GameSession.accept_invitation("greenland_scouts").ok, "[invitation] cannot be accepted twice")
	var award := GameSession._state.progress.is_completed(&"world:invitation")
	t.check(award, "[invitation] the invitation achievement is earned")
	# The rank goals are awarded once, and survive a reload without a second award.
	GameSession.advance_world(true)
	GameSession._check_rank_goals()
	var renown := GameSession._state.progress.lifetime_renown
	var errors: Array[String] = []
	GameSession.replace_state(SessionState.from_dict(JSON.parse_string(JSON.stringify(GameSession.get_state_snapshot().to_dict(), "", true, true)), errors))
	GameSession._check_rank_goals()
	t.check(GameSession._state.progress.is_completed(&"world:top_100") and GameSession._state.progress.lifetime_renown == renown,
		"[rankings] among the hundred, awarded once; nothing again after a reload")
	# Sail them there: the booking settles like any other passage.
	var offer := GameSession.get_passage_book().get_offer(String(booking.offer))
	Simulation.advance(maxf(float(offer.depart_after) - GameSession.get_game_time(), 0.0) + 60.0)
	t.check(GameSession.get_passage_book().aboard().size() == 1, "[invitation] Freya and Maya came aboard")
	GameSession.plan_route_to(StringName(String((offer.stops as Array).back())))
	t.check(GameSession.depart() == "", "[invitation] cast off with the explorers aboard")
	var until := GameSession.get_game_time() + 6.0 * DAY
	while GameSession.is_underway() and GameSession.get_game_time() < until:
		Simulation.advance(2.0 * HOUR)
	var records := GameSession.get_passage_book().records.filter(func(r: Dictionary) -> bool: return r.get("booking", "") == booking.id)
	t.check(records.size() == 1 and int(records[0].stars) >= 4, "[invitation] the passage is settled in the voyage ledger, %d stars" % (int(records[0].stars) if not records.is_empty() else 0))
