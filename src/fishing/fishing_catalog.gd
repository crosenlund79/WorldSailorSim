class_name FishingCatalog
extends RefCounted
## Fishing data (Iteration 13), from data/fishing/fishing.json: the lures,
## the fish and where they are met. A simplified gameplay model: the sea area
## of a position is the region of the nearest harbour in the catalogue (the
## same broad areas the chart uses), and "coastal" fish only bite within
## `coastal_nm` of land. Nothing here claims scientific accuracy.
##
## All choices are made with a random generator the caller seeds from the
## game (wind seed and time), so the same moment always gives the same bite.

const PATH := "res://data/fishing/fishing.json"

## What came up on the line (Iteration 18): a fish, a shark (always released)
## or junk (discarded).
const KIND_FISH := &"fish"
const KIND_SHARK := &"shark"
const KIND_JUNK := &"junk"
## The rarities in order (the data's own names), commonest first.
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare", "very_rare"]
## Specimen grades (Iteration 18) by the fish's weight within its species'
## range (0 = the smallest possible, 1 = the largest): below Bronze a fish is
## simply ordinary. Rarity plays no part: a common herring can be Gold.
const GRADE_NONE := &""
const GRADE_BRONZE := &"bronze"
const GRADE_SILVER := &"silver"
const GRADE_GOLD := &"gold"
const GRADES: Array[StringName] = [GRADE_NONE, GRADE_BRONZE, GRADE_SILVER, GRADE_GOLD]
const GRADE_FROM := {GRADE_BRONZE: 0.35, GRADE_SILVER: 0.6, GRADE_GOLD: 0.8}
## The reel-in challenge by rarity (Iteration 18): successful timing checks
## needed and the width of the target arc in degrees (narrower when rarer).
const REEL := {"common": [1, 72.0], "uncommon": [2, 60.0], "rare": [3, 50.0], "very_rare": [4, 42.0]}
## Junk comes up easily.
const JUNK_REEL := [1, 84.0]
## Each Perfect hit moves the fish's weight this share of the way toward the
## top of its species' range (so three Perfects add at most about a fifth of
## the remaining range; never beyond it).
const PERFECT_NUDGE := 0.07

static var _default: FishingCatalog

var bite_chance_per_check := 0.11
var check_interval_s := 300.0
var coastal_nm := 3.0
var max_trolling_kn := 7.0
var lures: Array[Dictionary] = []
var species: Array[Dictionary] = []
var rarities := {}
## Junk items (Iteration 18) and the share of bites that are junk.
var junk: Array[Dictionary] = []
var junk_chance := 0.0


static func get_default() -> FishingCatalog:
	if _default == null:
		_default = FishingCatalog.new()
		_default._load(PATH)
	return _default


func _load(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		push_error("Fishing data %s is missing or invalid." % path)
		return
	bite_chance_per_check = float(data.get("bite_chance_per_check", bite_chance_per_check))
	check_interval_s = float(data.get("check_interval_s", check_interval_s))
	coastal_nm = float(data.get("coastal_nm", coastal_nm))
	max_trolling_kn = float(data.get("max_trolling_kn", max_trolling_kn))
	for lure: Dictionary in data.get("lures", []):
		lures.append(lure)
	for fish: Dictionary in data.get("species", []):
		species.append(fish)
	rarities = data.get("rarities", {})
	for item: Dictionary in data.get("junk", []):
		junk.append(item)
	junk_chance = float(data.get("junk_chance", 0.0))


func get_lure(id: String) -> Dictionary:
	for lure in lures:
		if lure.id == id:
			return lure
	return {}


func get_species(id: String) -> Dictionary:
	for fish in species:
		if fish.id == id:
			return fish
	return {}


func get_species_name(id: String) -> String:
	var fish := get_species(id)
	if fish.is_empty() and not get_junk(id).is_empty():
		return Loc.t(String(get_junk(id).name))
	return Loc.t(String(fish.get("name", id.capitalize())))


func get_junk(id: String) -> Dictionary:
	for item in junk:
		if item.id == id:
			return item
	return {}


## Fish, shark or junk (Iteration 18).
func kind_of(id: String) -> StringName:
	if not get_junk(id).is_empty():
		return KIND_JUNK
	return KIND_SHARK if String(get_species(id).get("kind", "fish")) == "shark" else KIND_FISH


func is_shark(id: String) -> bool:
	return kind_of(id) == KIND_SHARK


## The species' rarity id ("common" ... "very_rare"; "" for junk).
func rarity_of(id: String) -> String:
	if kind_of(id) == KIND_JUNK:
		return ""
	return String(get_species(id).get("rarity", "common"))


## How a rarity is written for the player.
static func rarity_label(rarity: String) -> String:
	return rarity.replace("_", " ").capitalize() if rarity != "" else ""


## 0 (common) to 3 (very rare); -1 for none.
static func rarity_index(rarity: String) -> int:
	return RARITY_ORDER.find(rarity)


## Where `kg` lies in the species' weight range, 0..1.
func relative_size(species_id: String, kg: float) -> float:
	var fish := get_species(species_id)
	if fish.is_empty():
		return 0.0
	return clampf(inverse_lerp(float(fish.kg[0]), float(fish.kg[1]), kg), 0.0, 1.0)


## The specimen grade of a fish of `kg` (by weight only; see GRADE_FROM).
func grade(species_id: String, kg: float) -> StringName:
	if kind_of(species_id) == KIND_JUNK or get_species(species_id).is_empty():
		return GRADE_NONE
	var relative := relative_size(species_id, kg)
	for g in [GRADE_GOLD, GRADE_SILVER, GRADE_BRONZE]:
		if relative >= float(GRADE_FROM[g]) - 1e-9:
			return g
	return GRADE_NONE


static func grade_label(g: StringName) -> String:
	return String(g).capitalize() if g != GRADE_NONE else Loc.t("Ordinary")


## 0 (ordinary) to 3 (gold).
static func grade_rank(g: StringName) -> int:
	return maxi(GRADES.find(g), 0)


## The reel-in challenge for what is on the line: {"checks", "arc_deg"}.
func reel_profile(id: String) -> Dictionary:
	var entry: Array = JUNK_REEL if kind_of(id) == KIND_JUNK else REEL.get(rarity_of(id), REEL.common)
	return {"checks": int(entry[0]), "arc_deg": float(entry[1])}


## The landed weight: the weight the fish had when it bit, nudged toward the
## top of its range by Perfect hits (never beyond the range; species and
## rarity never change).
func landed_kg(species_id: String, kg: float, perfects: int) -> float:
	var fish := get_species(species_id)
	if fish.is_empty() or perfects <= 0:
		return kg
	var top := float(fish.kg[1])
	var nudged := kg + (top - kg) * (1.0 - pow(1.0 - PERFECT_NUDGE, perfects))
	return minf(snappedf(nudged, 0.01), top)


## A piece of junk for a bite (Iteration 18): {"species", "kg"} with the junk id.
func pick_junk(rng: RandomNumberGenerator) -> Dictionary:
	if junk.is_empty():
		return {}
	var item: Dictionary = junk[rng.randi_range(0, junk.size() - 1)]
	return {"species": String(item.id), "kg": 0.0}


func rarity_rank(id: String) -> int:
	var fish := get_species(id)
	return int(rarities.get(fish.get("rarity", "common"), {}).get("rank", 1))


func rarity_name(id: String) -> String:
	return Loc.t(String(get_species(id).get("rarity", "common")).replace("_", " "))


## The broad sea area of `geo`: the region of the nearest harbour.
static func region_at(geo: Vector2) -> String:
	var catalog := PortCatalog.get_default()
	var best: PortData = null
	var best_nm := INF
	for size in [3.0, 8.0, 40.0]:
		for port in catalog.ports_in_rect(Rect2(geo - Vector2(size, size), Vector2(size, size) * 2.0)):
			var nm := GeoMath.distance_nm(geo, port.get_geo_position())
			if nm < best_nm:
				best_nm = nm
				best = port
		if best:
			break
	return best.region if best else ""


func is_coastal(geo: Vector2) -> bool:
	return HatStory.open_water_nm(geo, coastal_nm) < coastal_nm


## The fish that can bite here: [{"species", "weight"}] (weights relative).
func candidates(geo: Vector2, mode: StringName, lure: String) -> Array[Dictionary]:
	var region := region_at(geo)
	var coastal := is_coastal(geo)
	var result: Array[Dictionary] = []
	for fish in species:
		if not region in fish.regions or (fish.get("coastal", false) and not coastal):
			continue
		var weight := float(rarities.get(fish.rarity, {}).get("weight", 1.0)) * float(fish.lures.get(lure, 0.5)) \
			* float(fish.modes.get(String(mode), 1.0))
		if weight > 0.0:
			result.append({"species": String(fish.id), "weight": weight})
	return result


## How well the lure and the way of fishing suit this water (about 0.4 to
## 1.3; 1 is an average fit): the candidates' weights against their rarity.
func suitability(geo: Vector2, mode: StringName, lure: String) -> float:
	var region := region_at(geo)
	var coastal := is_coastal(geo)
	var fitted := 0.0
	var plain := 0.0
	for fish in species:
		if not region in fish.regions or (fish.get("coastal", false) and not coastal):
			continue
		var rarity_weight := float(rarities.get(fish.rarity, {}).get("weight", 1.0))
		plain += rarity_weight
		fitted += rarity_weight * float(fish.lures.get(lure, 0.5)) * float(fish.modes.get(String(mode), 1.0))
	return fitted / plain if plain > 0.0 else 0.0


## The chance of a bite in one check (every check_interval_s of fishing).
## Trolling faster than max_trolling_kn gets no bites at all (the lure skips
## on the surface); strong wind makes bites rarer.
func bite_chance(geo: Vector2, mode: StringName, lure: String, speed_kn: float, wind_kn: float) -> float:
	if mode == FishingState.MODE_TROLLING and speed_kn > max_trolling_kn:
		return 0.0
	var chance := bite_chance_per_check * suitability(geo, mode, lure)
	if wind_kn > 22.0:
		chance *= 0.6
	return clampf(chance, 0.0, 0.6)


## A fish for this place and way of fishing: {"species", "kg"} or {}.
## I027 playtest: `in_harbour` (moored in a harbour) keeps the fish below the
## Silver grade - the big Silver and Gold specimens live in open water.
func pick(rng: RandomNumberGenerator, geo: Vector2, mode: StringName, lure: String, in_harbour := false) -> Dictionary:
	var options := candidates(geo, mode, lure)
	var total := 0.0
	for option in options:
		total += float(option.weight)
	if total <= 0.0:
		return {}
	var roll := rng.randf() * total
	for option in options:
		roll -= float(option.weight)
		if roll <= 0.0:
			var fish := get_species(option.species)
			var r := rng.randf()
			if in_harbour:
				r = minf(r, sqrt(float(GRADE_FROM[GRADE_SILVER])) - 0.01)
			# Most fish are modest; big ones are rarer.
			var kg := lerpf(float(fish.kg[0]), float(fish.kg[1]), r * r)
			return {"species": option.species, "kg": snappedf(kg, 0.01)}
	return {}


## How notable a catch is (the trophy board ranks by it): rarity (25 per
## rank, 25 for common to 100 for very rare) plus size within the species (up
## to 50 for the biggest possible).
func score(species_id: String, kg: float) -> float:
	var fish := get_species(species_id)
	if fish.is_empty():
		return 0.0
	var relative := inverse_lerp(float(fish.kg[0]), float(fish.kg[1]), kg)
	return rarity_rank(species_id) * 25.0 + 50.0 * clampf(relative, 0.0, 1.0)


## Exceptional: in the top fifth of the species' size range.
func is_exceptional(species_id: String, kg: float) -> bool:
	var fish := get_species(species_id)
	return not fish.is_empty() and kg >= lerpf(float(fish.kg[0]), float(fish.kg[1]), 0.8)


## What a fish fetches at a harbour grocery store (euros, at least 1).
func price(species_id: String, kg: float) -> int:
	return maxi(roundi(kg * float(get_species(species_id).get("price_per_kg", 4))), 1)


## How hard the fish pulls (0..1) in the fight.
func strength(species_id: String, kg: float) -> float:
	var fish := get_species(species_id)
	var relative := inverse_lerp(float(fish.kg[0]), float(fish.kg[1]), kg)
	return clampf(float(fish.get("strength", 0.5)) * (0.75 + 0.5 * relative), 0.1, 1.0)
