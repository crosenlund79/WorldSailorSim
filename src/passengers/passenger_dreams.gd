class_name PassengerDreams
extends RefCounted
## Passengers' own dreams (I028 Tier 4): some travellers come aboard with a
## personal ambition that suits the passage they book - a first night at sea,
## returning to a childhood island, photographing a special place, island
## hopping, crossing an ocean under sail. A dream is judged only from the
## legs the passenger actually sailed aboard (the booking's legs_sailed, the
## voyage ledger's facts): a traveller who sailed one European leg towards
## the Caribbean has not crossed the Atlantic with the Captain.

const KIND_NIGHT := "night_at_sea"
const KIND_REACH := "reach"
const KIND_SCENIC := "scenic"
const KIND_ISLANDS := "island_hopping"
const KIND_CROSSING := "crossing"
## An ocean crossing: from these sea areas to those, in one leg aboard.
const ATLANTIC_EAST := ["iberia_atlantic", "atlantic_islands", "biscay", "channel", "british_isles", "west_africa", "mediterranean"]
const ATLANTIC_WEST := ["caribbean", "central_america", "north_america", "south_atlantic"]
const NIGHT_LEG_S := 10.0 * 3600.0
const TEXTS := {
	KIND_NIGHT: "has always wanted to spend a night at sea",
	KIND_REACH: "dreams of returning to %s, the island of their childhood",
	KIND_SCENIC: "hopes to photograph a truly special place",
	KIND_ISLANDS: "dreams of hopping between islands by sail",
	KIND_CROSSING: "has dreamed for years of crossing the Atlantic under sail",
}
const TITLES := {
	KIND_NIGHT: "A first night at sea",
	KIND_REACH: "Back to a childhood island",
	KIND_SCENIC: "A photograph of a lifetime",
	KIND_ISLANDS: "Island hopping",
	KIND_CROSSING: "An Atlantic crossing",
}


static func _port(id: Variant) -> PortData:
	return PortCatalog.get_default().get_port(StringName(id))


static func _scenic(id: Variant) -> bool:
	return not (CruisingRegions.get_default().get_destination(StringName(id)).get("scenic", []) as Array).is_empty() \
		or HarbourLooks.get_default().is_special(StringName(id))


## A dream that suits legs [from, to) of an offer, or {} (most travellers have none).
static func assign(rng: RandomNumberGenerator, offer: Dictionary, from: int, to: int) -> Dictionary:
	if rng.randf() > 0.45:
		return {}
	var stops: Array = offer.stops
	var options: Array[Dictionary] = []
	for i in range(from, to):
		var a := _port(stops[i])
		var b := _port(stops[i + 1])
		if a and b and a.region in ATLANTIC_EAST and b.region in ATLANTIC_WEST:
			options.append({"kind": KIND_CROSSING})
		if float(offer.leg_s[i]) >= NIGHT_LEG_S:
			options.append({"kind": KIND_NIGHT})
	var destination := _port(stops[to])
	if destination and destination.island:
		options.append({"kind": KIND_REACH, "port": String(destination.id)})
	var islands := 0
	for i in range(from + 1, to + 1):
		var port := _port(stops[i])
		islands += 1 if port and port.island else 0
		if _scenic(stops[i]) and options.filter(func(o: Dictionary) -> bool: return o.kind == KIND_SCENIC).is_empty():
			options.append({"kind": KIND_SCENIC})
	if islands >= 2:
		options.append({"kind": KIND_ISLANDS, "count": 2})
	if options.is_empty():
		return {}
	var dream: Dictionary = options[rng.randi() % options.size()].duplicate()
	dream.met = false
	return dream


## The dream in words ("has always wanted to spend a night at sea").
static func describe(dream: Dictionary) -> String:
	var text := Loc.t(String(TEXTS.get(dream.get("kind", ""), "")))
	if dream.get("kind", "") == KIND_REACH:
		text = text % PortCatalog.get_default().get_display_name(StringName(dream.get("port", "")))
	return text


static func title(dream: Dictionary) -> String:
	return Loc.t(String(TITLES.get(dream.get("kind", ""), "")))


## True when the legs the passenger sailed aboard fulfil their dream.
static func is_met(dream: Dictionary, booking: Dictionary) -> bool:
	var legs: Array = booking.get("legs_sailed", [])
	match String(dream.get("kind", "")):
		KIND_NIGHT:
			return legs.any(func(l: Dictionary) -> bool: return float(l.arrived) - float(l.departed) >= NIGHT_LEG_S)
		KIND_REACH:
			return not legs.is_empty() and String(legs.back().to) == String(dream.get("port", "")) \
				and String(booking.get("disembark", "")) == String(dream.get("port", ""))
		KIND_SCENIC:
			return legs.any(func(l: Dictionary) -> bool: return _scenic(l.to))
		KIND_ISLANDS:
			var seen := {}
			for l: Dictionary in legs:
				var port := _port(l.to)
				if port and port.island:
					seen[l.to] = true
			return seen.size() >= int(dream.get("count", 2))
		KIND_CROSSING:
			return legs.any(func(l: Dictionary) -> bool:
				var a := _port(l.from)
				var b := _port(l.to)
				return a != null and b != null and a.region in ATLANTIC_EAST and b.region in ATLANTIC_WEST)
	return false
