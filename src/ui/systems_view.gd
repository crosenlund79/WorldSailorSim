class_name SystemsView
extends SimplePanel
## The boat's switch panel, brought close (I026, A World You Can Touch;
## framed as an electrical panel by FocusFrame): what the boat really keeps
## track of, in one place - the hull's condition, the care survey of hull,
## rig, engine and equipment (BoatCare), what the yard has fitted, the
## sailcloth, food and water aboard, and the fitted instruments. Read only:
## nothing here is a new chore or a new meter, and the services that change
## these stay where they are (the boatyard, the sail loft, the grocery).

const ROWS_NODE := &"Rows"


func _ready() -> void:
	var vessel := GameSession.get_vessel_definition()
	_build(Loc.t("Boat systems · %s") % (vessel.display_name if vessel else ""), 640.0)
	var grid := GridContainer.new()
	grid.name = ROWS_NODE
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 6)
	_box.add_child(grid)
	for row in rows():
		var key := Label.new()
		key.text = row[0]
		key.theme_type_variation = &"MutedLabel"
		grid.add_child(key)
		var value := Label.new()
		value.text = row[1]
		grid.add_child(value)
	_button("CloseButton", Loc.t("Close"), close)


## [label, value] pairs, from the game's own state only (the same words as
## the boatyard's care survey, BoatCare.describe_area).
static func rows() -> Array:
	var out: Array = []
	var care := GameSession.get_boat_care()
	var now := GameSession.get_game_time()
	if care:
		for area in BoatCare.AREAS:
			out.append([Loc.t(String(BoatCare.AREA_NAMES[area])), BoatCare.describe_area(area, care, GameSession.get_condition(), now)])
		var fitted: Array[String] = []
		for id in care.upgrades:
			fitted.append(Loc.t(String(BoatCare.get_upgrade(id).get("name", id))))
		if not fitted.is_empty():
			out.append([Loc.t("Fitted by the yard"), ", ".join(fitted)])
	var cloth := HarbourTrades.get_sail_cloth(GameSession.get_sail_cloth())
	if not cloth.is_empty():
		out.append([Loc.t("Sails"), Loc.t(String(cloth.get("name", "")))])
	var provisions := GameSession.get_provisions()
	out.append([Loc.t("Food aboard"), Loc.n("%d day", "%d days", int(provisions.food_days)) % int(provisions.food_days)])
	out.append([Loc.t("Water aboard"), Loc.n("%d day", "%d days", int(provisions.water_days)) % int(provisions.water_days)])
	if GameSession.has_method(&"get_instrument_package_name"):
		out.append([Loc.t("Instruments"), String(GameSession.call(&"get_instrument_package_name"))])
	return out


func focus_default() -> void:
	(find_child("CloseButton", true, false) as Button).grab_focus()
