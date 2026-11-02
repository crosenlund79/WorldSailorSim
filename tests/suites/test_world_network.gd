extends RefCounted
## I028 Tier 5: travel writing in place of the little game (the old game's
## progress migrated once; a work written in sessions and published from
## real history: modest income, renown, a world event), the world's one event
## ledger (deterministic, extended forward only, immutable past, a yacht in one
## place at a time, plausible passage times) and the Traveller Network read
## from it (posts only from the past, the same after a reload, pictures that
## exist, some text-only posts, following).

var t: Node
const DAY := 86400.0


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	_test_ledger_rules()
	_test_writing()
	_test_network()
	Simulation.auto_advance = true
	GameSession.end_session()


## JSON numbers come back as floats: compare what the save would hold.
func _norm(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


func _fresh_world(seed: int, days: float) -> WorldState:
	var w := WorldState.new()
	WorldChronicle.advance(w, 1000.0, seed)
	WorldChronicle.advance(w, 1000.0 + days * DAY, seed)
	return w


func _test_ledger_rules() -> void:
	var a := _fresh_world(7, 90.0)
	var b := _fresh_world(7, 90.0)
	t.check(a.events.size() > 40, "[world] 90 days of history: %d events" % a.events.size())
	t.check(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "[world] the same seed writes the same history")
	var c := _fresh_world(8, 90.0)
	t.check(JSON.stringify(a.events) != JSON.stringify(c.events), "[world] another seed, another history")
	# Stepping in small or large steps gives the same history (forward only).
	var stepped := WorldState.new()
	WorldChronicle.advance(stepped, 1000.0, 7)
	var now := 1000.0
	while now < 1000.0 + 90.0 * DAY:
		now = minf(now + 0.37 * DAY, 1000.0 + 90.0 * DAY)
		WorldChronicle.advance(stepped, now, 7)
	t.check(_norm(a.events) == _norm(stepped.events), "[world] small and large steps give the same history")
	# Each yacht: alternate departures and arrivals, from where it last was, never too fast.
	var problems: Array[String] = []
	var where := {}
	var under_way := {}
	for e: Dictionary in a.events:
		var y := String(e.get("yacht", ""))
		if y == "" or not e.kind in ["depart", "arrive", "expedition_complete"]:
			continue
		if e.kind == "depart":
			if under_way.has(y):
				problems.append("%s departs while under way" % y)
			if where.has(y) and String(where[y]) != String(e.from):
				problems.append("%s departs %s but was in %s" % [y, e.from, where[y]])
			var nm := GeoMath.distance_nm(PortCatalog.get_default().get_port(StringName(e.from)).get_geo_position(),
				PortCatalog.get_default().get_port(StringName(e.to)).get_geo_position())
			var speed := nm / maxf((float(e.eta) - float(e.t)) / 3600.0, 0.01)
			if speed > float(WorldChronicle.yacht(y).get("speed", 6.0)) + 0.01:
				problems.append("%s at %.1f kn" % [y, speed])
			under_way[y] = e
		else:
			if not under_way.has(y):
				problems.append("%s arrives without leaving" % y)
			elif String((under_way[y] as Dictionary).to) != String(e.port):
				problems.append("%s arrives in %s, bound for %s" % [y, e.port, (under_way[y] as Dictionary).to])
			under_way.erase(y)
			where[y] = String(e.port)
	t.check(problems.is_empty(), "[world] every yacht is in one place at a time, at plausible speeds %s" % str(problems.slice(0, 3)))
	var ordered := true
	for i in range(1, a.events.size()):
		if int(a.events[i].seq) <= int(a.events[i - 1].seq):
			ordered = false
	t.check(ordered, "[world] the ledger's sequence only grows")
	# The past is immutable: a reload and a further advance keep what was written.
	var before := _norm(a.events)
	var reloaded := WorldState.from_dict(JSON.parse_string(JSON.stringify(a.to_dict(), "", true, true)))  # as SaveManager writes
	WorldChronicle.advance(reloaded, 1000.0 + 140.0 * DAY, 7)
	t.check(_norm(reloaded.events.slice(0, a.events.size())) == before and reloaded.events.size() > a.events.size(),
		"[world] after a reload, history continues and the past is unchanged")
	# The Greenland expedition: announced, sailed stop by stop.
	var announced := a.events.filter(func(e: Dictionary) -> bool: return e.kind == "expedition_announced" and e.expedition == "greenland_promise")
	t.check(announced.size() == 1, "[world] Northern Promise's expedition is announced once")
	var legs := a.events.filter(func(e: Dictionary) -> bool: return e.get("expedition", "") == "greenland_promise" and e.kind == "depart")
	t.check(legs.size() >= 2 and "freya_voss" in (legs[0].who as Array) and "maya_wildshore" in (legs[0].who as Array),
		"[world] Freya Voss and Maya Wildshore sail the expedition together (%d legs so far)" % legs.size())
	var ranks := WorldChronicle.rankings(a, 1000.0 + 90.0 * DAY, 0)
	t.check(ranks.size() >= 200 and int(ranks[0].rank) == 1 and int(ranks[0].renown) >= int(ranks[1].renown),
		"[world] the rankings: %d people, ordered" % ranks.size())
	t.check(JSON.stringify(ranks) == JSON.stringify(WorldChronicle.rankings(b, 1000.0 + 90.0 * DAY, 0)), "[world] the same history ranks the same")


func _visit(port: String, nm: float, departed: float) -> void:
	GameSession._state.captains_log.record_voyage({"from": "copenhagen", "to": port, "departed": departed, "ended": departed + 3600.0 * 8.0,
		"nm": nm, "vessel": "", "outcome": "arrived", "worst_hazard": 2, "damage": 0.0, "complete": true})


func _test_writing() -> void:
	GameSession.start_new_session(&"")
	GameSession._state.pastimes.game.sessions = 6
	GameSession._state.pastimes.game.milestone = 2
	var w := GameSession.get_writing()
	t.check(w.migrated == true and int(w.xp) == 6 + 4, "[writing] the old game's progress becomes writing experience (%d)" % int(w.xp))
	GameSession.get_writing()
	t.check(int(GameSession.get_writing().xp) == 10, "[writing] migrated once only")
	t.check(GameSession.writing_topics().is_empty(), "[writing] nothing to write about before the first voyage")
	_visit("helsingor", 24.0, 100.0)
	_visit("gothenburg", 140.0, 50000.0)
	var topics := GameSession.writing_topics()
	t.check(topics.size() >= 3, "[writing] topics from real voyages: %s" % str(topics.map(func(x: Dictionary) -> String: return String(x.id))))
	t.check(GameSession.start_writing("novel", String(topics[0].id)) != "", "[writing] a novel needs more experience")
	var topic: Dictionary = topics.filter(func(x: Dictionary) -> bool: return x.kind == "weather")[0]
	t.check(GameSession.start_writing("essay", String(topic.id)) == "", "[writing] an essay about rough weather is begun")
	var funds := GameSession.get_funds()
	var first := GameSession.work_on_writing("sea", 60.0)
	t.check(not first.done and float(GameSession.get_writing().project.minutes) == 60.0, "[writing] an interrupted session keeps its share")
	GameSession.work_on_writing("sea", 60.0)
	var done := GameSession.work_on_writing("sea", 120.0)
	var work: Dictionary = done.published
	t.check(done.done and int(work.stars) == 5 and GameSession.get_funds() == funds + int(work.euros), "[writing] every angle right: five stars, %s" % work.get("title", ""))
	t.check(int(work.euros) <= 120, "[writing] a modest income (%d)" % int(work.euros))
	var world := GameSession.get_world()
	var events := world.events.filter(func(e: Dictionary) -> bool: return e.kind == "captain_book")
	t.check(events.size() == 1 and String(events[0].title) == String(work.title), "[writing] the published work is in the world's history")
	t.check(GameSession.work_on_writing("sea", 120.0).published.is_empty(), "[writing] nothing is published twice")
	var errors: Array[String] = []
	var reloaded := SessionState.from_dict(GameSession.get_state_snapshot().to_dict(), errors)
	t.check((reloaded.world.writing.works as Array).size() == 1 and reloaded.world.writing.migrated == true, "[writing] saved and loaded")


func _test_network() -> void:
	GameSession.advance_world(true)
	Simulation.advance(40.0 * DAY)
	GameSession.advance_world(true)
	var posts := GameSession.get_network_posts(60)
	t.check(posts.size() >= 8, "[network] the network has news after 40 days: %d posts" % posts.size())
	var now := GameSession.get_game_time()
	var future := posts.filter(func(p: Dictionary) -> bool: return float(p.t) > now)
	t.check(future.is_empty(), "[network] no post from the future")
	var pictures := posts.filter(func(p: Dictionary) -> bool: return String(p.image) != "")
	var missing := pictures.filter(func(p: Dictionary) -> bool: return not ResourceLoader.exists(TravellerNetwork.image_path(String(p.image))))
	t.check(pictures.size() > 0 and pictures.size() < posts.size() and missing.is_empty(),
		"[network] %d of %d posts have a picture, all present; the rest are text only" % [pictures.size(), posts.size()])
	t.check(Array(DirAccess.get_files_at("res://assets/network")).filter(func(f: String) -> bool: return f.ends_with(".png")).size() >= 20,
		"[network] at least twenty reusable pictures")
	var captain := GameSession.get_network_posts(400).filter(func(p: Dictionary) -> bool: return p.author == WorldChronicle.CAPTAIN and p.kind == "captain_book")
	t.check(captain.size() == 1, "[network] the Captain's published work is posted")
	var errors: Array[String] = []
	var snapshot := GameSession.get_state_snapshot()
	var reloaded := SessionState.from_dict(JSON.parse_string(JSON.stringify(snapshot.to_dict(), "", true, true)), errors)
	var again := TravellerNetwork.posts(reloaded.world, now, 60)
	t.check(JSON.stringify(again) == JSON.stringify(posts), "[network] the same posts after a reload")
	var author := ""
	for p: Dictionary in posts:
		if p.author != WorldChronicle.CAPTAIN and not WorldChronicle.population().has(String(p.author)):
			author = String(p.author)
			break
	GameSession.set_following(author, true)
	var followed := GameSession.get_network_posts(60, true)
	t.check(author != "" and not followed.is_empty() and followed.all(func(p: Dictionary) -> bool: return p.author == author),
		"[network] following %s shows only their posts" % author)
	GameSession.set_following(author, false)
	t.check(GameSession.get_network_posts(60, true).is_empty(), "[network] unfollowed again")
	var standing := GameSession.get_captain_standing()
	t.check(int(standing.rank) >= 1 and int(standing.of) >= 200, "[world] the Captain has a place in the rankings: %d of %d" % [int(standing.rank), int(standing.of)])
	# A new game after a long one: the world keeps its own clock (career finding:
	# a stale checkpoint from the earlier game froze the new game's world).
	GameSession.start_new_session(&"")
	Simulation.advance(3.0 * DAY)
	var fresh := GameSession.get_world()
	t.check(fresh.started_at > 0.0 and not fresh.events.is_empty() and int(GameSession.get_captain_standing().rank) > 100,
		"[world] a new game after a long one starts its own world (%d events, rank %d)" % [fresh.events.size(), int(GameSession.get_captain_standing().get("rank", 0))])
