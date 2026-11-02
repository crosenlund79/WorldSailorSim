class_name TravellerNetwork
extends RefCounted
## The Traveller Network (I028 Tier 5): the sailing world's quiet social feed
## on the laptop. It holds no history of its own. Every post is read from the
## world's one event ledger (WorldState.events, written by WorldChronicle), so
## a post can never contradict the yacht directory, the magazine or the
## rankings: a traveller posts from where the ledger has them, when it has
## them there. Which events become posts, their wording and their picture are
## seeded by the event's own sequence number, so the feed reads the same after
## a reload, and a post, once in the past, never changes.
##
## Sparse on purpose: some departures, most arrivals, every expedition, book
## and Captain's event. About a third of posts are text only; the rest use one
## of the reusable atmospheric pictures in assets/network (people are always
## blurred silhouettes), chosen by motif to suit the place.

const MANIFEST := "res://assets/network/manifest.json"
const IMAGE_DIR := "res://assets/network/"
const TEXT_ONLY_SHARE := 0.35
const ARCTIC := ["north_atlantic"]
const ARCTIC_PORTS := ["nuuk", "reykjavik", "torshavn", "tromso", "longyearbyen", "lofoten", "svolvaer", "hammerfest"]
const WARM := ["caribbean", "pacific", "indian_ocean", "southeast_asia", "central_america", "atlantic_islands", "west_africa", "south_atlantic"]

static var _by_motif: Dictionary


static func _images() -> Dictionary:
	if _by_motif.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		var list: Array = (parsed as Dictionary).get("images", []) if parsed is Dictionary else []
		for item: Variant in list:
			if item is Dictionary:
				var motif := String((item as Dictionary).get("motif", ""))
				if not _by_motif.has(motif):
					_by_motif[motif] = []
				(_by_motif[motif] as Array).append(String((item as Dictionary).id))
	return _by_motif


static func image_path(id: String) -> String:
	return IMAGE_DIR + id + ".png" if id != "" else ""


## The posts up to `now`, newest first: [{"seq", "t", "author", "author_name",
## "kind", "text", "image" (id or ""), "port", "yacht"}]. `only` limits it to
## these authors (the people the Captain follows), [] for everyone.
static func posts(world: WorldState, now: float, limit := 30, only: Array = []) -> Array:
	var out: Array = []
	for i in range(world.events.size() - 1, -1, -1):
		var e: Dictionary = world.events[i]
		if float(e.t) > now:
			continue
		var post := post_for(e)
		if post.is_empty():
			continue
		if not only.is_empty() and not String(post.author) in only:
			continue
		out.append(post)
		if out.size() >= limit:
			break
	return out


## The post an event makes, or {} when it makes none (deterministic per event).
static func post_for(e: Dictionary) -> Dictionary:
	if e.get("minor", false):
		return {}
	var kind := String(e.get("kind", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("post|%d|%s" % [int(e.get("seq", 0)), kind])
	var roll := rng.randf()
	var who: Array = e.get("who", [])
	if who.is_empty():
		return {}
	var author := String(who[0])
	var text := ""
	var motif := ""
	var port := String(e.get("port", ""))
	var place := _place(port)
	var vessel := String(WorldChronicle.yacht(String(e.get("yacht", ""))).get("name", ""))
	match kind:
		"depart":
			if roll > 0.4:
				return {}
			text = [Loc.t("Lines off in %s. Bound for %s on %s.") % [place, _place(String(e.get("to", ""))), vessel],
				Loc.t("Leaving %s with the morning breeze. Next stop %s.") % [place, _place(String(e.get("to", "")))],
				Loc.t("Provisioned, rested and ready: %s sails for %s today.") % [vessel, _place(String(e.get("to", "")))]][rng.randi() % 3]
			motif = ["sail", "pontoon", "sails"][rng.randi() % 3]
		"arrive":
			if roll > 0.7:
				return {}
			text = [Loc.t("Safely in %s after %d nm. Coffee first, then sleep.") % [place, int(e.get("nm", 0))],
				Loc.t("%s is moored in %s. What a passage.") % [vessel, place],
				Loc.t("Arrived in %s. The harbour smells of tar and fresh bread.") % place,
				Loc.t("%d nm behind us and %s ahead of us for a few days.") % [int(e.get("nm", 0)), place]][rng.randi() % 4]
			motif = _motif_for_port(port, rng)
		"expedition_announced":
			text = Loc.t("Announcing: %s. %s leaves from %s, bound for %s.") % [_expedition_title(String(e.get("expedition", ""))), vessel, place,
				_place(String(e.get("to", "")))]
			motif = "harbour"
		"expedition_complete":
			text = Loc.t("We made it. %s has reached %s, the end of %s. Thank you all for following.") % [vessel, place,
				_expedition_title(String(e.get("expedition", "")))]
			motif = _motif_for_port(port, rng)
		"book":
			text = [Loc.t("My new book is out today. Written in harbours and night watches."),
				Loc.t("A small book of photographs from the last season is published. Thank you, everyone who sailed with me."),
				Loc.t("Finished at last: a new collection of stories from the sea.")][rng.randi() % 3]
			motif = "cafe"
		"captain_book":
			text = Loc.t("Published: “%s”.") % String(e.get("title", ""))
			motif = "cafe"
		"captain_passage":
			text = Loc.t("Arrived in %s after %d nm.") % [place, int(e.get("nm", 0))]
			motif = _motif_for_port(port, rng)
		"captain_dream":
			text = Loc.t("A passenger's dream came true aboard today.")
			motif = "sail"
		_:
			return {}
	var image := ""
	if rng.randf() >= TEXT_ONLY_SHARE or kind in ["expedition_announced", "expedition_complete"]:
		var choices: Array = _images().get(motif, _images().get("harbour", []))
		if not choices.is_empty():
			image = String(choices[rng.randi() % choices.size()])
	return {"seq": int(e.get("seq", 0)), "t": float(e.t), "author": author, "author_name": String(WorldChronicle.traveller(author).get("name", author)),
		"kind": kind, "text": text, "image": image, "port": port, "yacht": String(e.get("yacht", ""))}


static func _place(port_id: String) -> String:
	if port_id == "":
		return Loc.t("the open sea")
	return PortCatalog.get_default().get_display_name(StringName(port_id))


static func _expedition_title(id: String) -> String:
	for e: Dictionary in WorldChronicle.data().get("expeditions", []):
		if e.id == id:
			return Loc.t(String(e.get("title", "")))
	return ""


static func _motif_for_port(port_id: String, rng: RandomNumberGenerator) -> String:
	var port := PortCatalog.get_default().get_port(StringName(port_id))
	var region := String(port.region) if port else ""
	if port_id in ARCTIC_PORTS or region in ARCTIC:
		return ["ice", "fjord", "whale", "aurora"][rng.randi() % 4]
	if region in WARM:
		return ["palms", "sail", "whale"][rng.randi() % 3]
	if region == "scandinavia":
		return ["fjord", "harbour", "lighthouse", "cafe"][rng.randi() % 4]
	return ["harbour", "cafe", "pontoon", "lighthouse"][rng.randi() % 4]
