class_name TrophyMenu
extends SimplePanel
## The trophy board (Iteration 13): the five most notable catches, ranked by
## FishingCatalog.score (rarity, then size within the species, plus a little
## for a new species or a personal best at the time), and the captain's
## fishing record. Iteration 18: each catch on a plaque with its picture,
## rarity and specimen grade; only kept fish are trophies (released fish and
## sharks never are). I027 playtest: each plaque says whether the fish is
## still in the cool box or only on record now (sold or eaten).

const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var _list: Label
var _plaques: VBoxContainer
var _record: Label


func _ready() -> void:
	_build("Trophy board", 700.0)
	_label("Info", "Your five most notable catches ever, kept on the board after the fish are sold or eaten: rare fish rank above common ones, and a big fish above a small one of its kind.",
		&"MutedLabel")
	_plaques = VBoxContainer.new()
	_plaques.name = "Plaques"
	_plaques.add_theme_constant_override(&"separation", 6)
	_box.add_child(_plaques)
	_list = _label("List", "")
	_list.visible = false
	_box.add_child(HSeparator.new())
	_record = _label("Record", "", &"MutedLabel")
	_button("CloseButton", "Close", close)
	refresh()


func refresh() -> void:
	_list.text = describe_trophies()
	_record.text = describe_record()
	for child in _plaques.get_children():
		child.queue_free()
	var catalog := FishingCatalog.get_default()
	var fishing := GameSession.get_fishing()
	if fishing.trophies.is_empty():
		var none := Label.new()
		none.text = describe_trophies()
		_plaques.add_child(none)
	var lines := describe_trophies().split("\n")
	for i in fishing.trophies.size():
		var fish: Dictionary = fishing.trophies[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var picture := TextureRect.new()
		picture.texture = FishArt.thumbnail(String(fish.species))
		picture.custom_minimum_size = Vector2(96, 48)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(picture)
		var words := VBoxContainer.new()
		words.add_theme_constant_override(&"separation", 2)
		row.add_child(words)
		var text := Label.new()
		text.text = lines[i] if i < lines.size() else ""
		words.add_child(text)
		var badge := CatchBadge.new()
		words.add_child(badge)
		badge.set_catch(catalog.rarity_of(fish.species), catalog.grade(fish.species, float(fish.kg)))
		# I027 playtest: the board is the record of the catch, not the cool box.
		var where := Label.new()
		where.theme_type_variation = &"MutedLabel"
		where.text = Loc.t("In the cool box now") if fishing.find_in_hold(int(fish.uid)) >= 0 else Loc.t("On record: sold or eaten since")
		words.add_child(where)
		_plaques.add_child(row)


static func describe_trophies() -> String:
	var catalog := FishingCatalog.get_default()
	var fishing := GameSession.get_fishing()
	if fishing.trophies.is_empty():
		return Loc.t("No catches yet. The rod is on the stern rail.")
	var lines := PackedStringArray()
	for i in fishing.trophies.size():
		var fish: Dictionary = fishing.trophies[i]
		var day := Time.get_datetime_dict_from_unix_time(int(fish.caught_at))
		lines.append(Loc.format("%d.  %s, %.1f kg  ·  %s  ·  %d %s%s", [i + 1, catalog.get_species_name(fish.species), float(fish.kg),
			catalog.rarity_name(fish.species), day.day, Loc.month_short(day.month),
			(", " + String(fish.where)) if String(fish.get("where", "")) != "" else ""]))
	return "\n".join(lines)


static func describe_record() -> String:
	var catalog := FishingCatalog.get_default()
	var fishing := GameSession.get_fishing()
	var species := PackedStringArray()
	for id: String in fishing.records:
		var best := float(fishing.records[id].best_kg)
		species.append("%s %d%s" % [catalog.get_species_name(id), int(fishing.records[id].count), (Loc.format(" (best %.1f kg)", best)) if best > 0.0 else ""])
	return Loc.t("Caught %d fish of %d species  ·  released %d  ·  sold %d%s.%s") % [fishing.total_caught, fishing.records.size(),
		fishing.released, fishing.sold, (Loc.n("  ·  %d shark swam free", "  ·  %d sharks swam free", fishing.sharks_released) % fishing.sharks_released) if fishing.sharks_released > 0 else "", ("\n" + ", ".join(species)) if not species.is_empty() else ""]
