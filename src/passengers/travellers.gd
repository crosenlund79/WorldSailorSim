class_name Travellers
extends RefCounted
## The people who travel with the Captain (I028 Tier 2): a traveller is made
## once from data/passengers/travellers.json on a seed (Travellers.make) and
## then kept in the save exactly as made (PassageBook.travellers), so the same
## person is the same person after a reload. A small set of traits that
## matter aboard - no needs meters:
##   comfort (simple/comfortable/spacious), privacy (shared_ok/prefers/requires),
##   weather (anxious/steady/hardy), timing (strict/normal/relaxed),
##   detour (dislikes/accepts/enjoys), pets (likes/neutral/allergic, with the
##   kinds), talk (chatty/quiet), reviews (generous/fair/critical),
## plus a group (solo, couple, friends, family), a budget per nautical mile
## and person, a background, a motivation and (Tier 4) a personal ambition.

const DATA_PATH := "res://data/passengers/travellers.json"
const PET_KINDS: Array[StringName] = [CompanionState.KIND_CAT, CompanionState.KIND_DOG, CompanionState.KIND_PARROT]

static var _data: Dictionary


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


## A new traveller (not yet kept anywhere), deterministic for `seed`.
## `max_size` caps the group (the berths left); `home` is where they live.
static func make(seed: int, id: String, max_size := 4, home := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d := data()
	var given: Array = d.get("given", ["Alex"])
	var family: Array = d.get("family", ["Sailor"])
	var first := String(given[rng.randi() % given.size()])
	var last := String(family[rng.randi() % family.size()])
	var group := _pick_group(rng, max_size)
	var names: Array = [first]
	for i in range(1, int(group.size)):
		names.append(String(given[(rng.randi() + i) % given.size()]))
	var background: Dictionary = _pick(rng, d.get("backgrounds", [{"id": "retired", "text": ""}]))
	var motivation: Dictionary = _pick(rng, d.get("motivations", [{"id": "see", "text": ""}]))
	var comfort: String = ["simple", "comfortable", "comfortable", "spacious"][rng.randi() % 4]
	var traveller := {
		"id": id, "given": first, "family": last, "names": names,
		"group": group.kind, "size": int(group.size),
		"background": String(background.id), "motivation": String(motivation.id),
		"comfort": comfort,
		"privacy": ["shared_ok", "shared_ok", "prefers", "requires"][rng.randi() % 4] if int(group.size) <= 2 else "prefers",
		"weather": ["anxious", "steady", "steady", "hardy"][rng.randi() % 4],
		"timing": ["strict", "normal", "normal", "relaxed"][rng.randi() % 4],
		"detour": ["dislikes", "accepts", "accepts", "enjoys"][rng.randi() % 4],
		"pets": ["likes", "neutral", "neutral", "likes", "allergic"][rng.randi() % 5],
		"allergies": [],
		"talk": ["chatty", "quiet"][rng.randi() % 2],
		"reviews": ["generous", "fair", "fair", "critical"][rng.randi() % 4],
		"home": home,
		"look": rng.randi() % 100000,
	}
	if traveller.pets == "allergic":
		traveller.allergies = [String(PET_KINDS[rng.randi() % 2])]  # cats or dogs
		if rng.randf() < 0.3:
			traveller.allergies.append(String(CompanionState.KIND_PARROT))
	# What they would pay per nautical mile and person: students and families
	# watch the euros, the comfortable pay for comfort.
	var budget: float = rng.randf_range(1.1, 1.9) * {"simple": 0.9, "comfortable": 1.0, "spacious": 1.35}[comfort]
	if traveller.background in ["student", "family"]:
		budget *= 0.8
	elif traveller.background in ["retired", "honeymoon"]:
		budget *= 1.15
	traveller["budget"] = snappedf(budget, 0.01)
	if traveller.background == "photographer":
		traveller.motivation = "photo"
	return traveller


static func _pick(rng: RandomNumberGenerator, list: Array) -> Dictionary:
	return list[rng.randi() % list.size()] if not list.is_empty() else {}


static func _pick_group(rng: RandomNumberGenerator, max_size: int) -> Dictionary:
	var groups: Array = data().get("groups", [{"kind": "solo", "size": 1, "weight": 1}]).filter(
		func(g: Dictionary) -> bool: return int(g.size) <= maxi(max_size, 1))
	var total := 0.0
	for g: Dictionary in groups:
		total += float(g.weight)
	var roll := rng.randf() * total
	for g: Dictionary in groups:
		roll -= float(g.weight)
		if roll <= 0.0:
			return g
	return groups[0]


## "Anna Berg", "Anna & Lars Berg", "Anna Berg and 2 friends", "the Berg family".
static func display_name(traveller: Dictionary) -> String:
	var first := String(traveller.get("given", ""))
	var last := String(traveller.get("family", ""))
	match String(traveller.get("group", "solo")):
		"couple":
			var names: Array = traveller.get("names", [first])
			return Loc.t("%s & %s %s") % [first, names[1] if names.size() > 1 else "", last]
		"friends":
			return Loc.t("%s %s and %d friends") % [first, last, int(traveller.get("size", 1)) - 1]
		"family":
			return Loc.t("the %s family") % last
	return "%s %s" % [first, last]


static func background_text(traveller: Dictionary) -> String:
	for b: Dictionary in data().get("backgrounds", []):
		if b.id == traveller.get("background", ""):
			return Loc.t(String(b.text))
	return ""


static func motivation_text(traveller: Dictionary) -> String:
	for m: Dictionary in data().get("motivations", []):
		if m.id == traveller.get("motivation", ""):
			return Loc.t(String(m.text))
	return ""


## True when none of `kinds` (the pets aboard) is one the traveller is allergic to.
static func tolerates_pets(traveller: Dictionary, kinds: Array) -> bool:
	for kind: Variant in kinds:
		if String(kind) in (traveller.get("allergies", []) as Array):
			return false
	return true


## The traits a Captain can read in a request, in plain words.
static func describe_traits(traveller: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append({"simple": Loc.t("happy with simple comforts"), "comfortable": Loc.t("likes a comfortable boat"),
		"spacious": Loc.t("expects a spacious yacht")}.get(traveller.get("comfort", ""), ""))
	match String(traveller.get("privacy", "")):
		"requires":
			parts.append(Loc.t("needs a private cabin"))
		"prefers":
			parts.append(Loc.t("prefers privacy"))
	match String(traveller.get("weather", "")):
		"anxious":
			parts.append(Loc.t("nervous in rough weather"))
		"hardy":
			parts.append(Loc.t("loves a lively sail"))
	match String(traveller.get("timing", "")):
		"strict":
			parts.append(Loc.t("must arrive on time"))
		"relaxed":
			parts.append(Loc.t("in no hurry"))
	if traveller.get("pets", "") == "likes":
		parts.append(Loc.t("loves animals"))
	elif traveller.get("pets", "") == "allergic":
		var kinds: Array[String] = []
		for kind: Variant in traveller.get("allergies", []):
			kinds.append(pet_plural(String(kind)))
		parts.append(Loc.t("allergic to %s") % ", ".join(kinds))
	return ", ".join(parts.filter(func(p: String) -> bool: return not p.is_empty()))


## "cats", "dogs", "birds" (an allergy or a liking is about the kind of animal).
static func pet_plural(kind: String) -> String:
	return {"cat": Loc.t("cats"), "dog": Loc.t("dogs"), "parrot": Loc.t("birds")}.get(kind, kind)
