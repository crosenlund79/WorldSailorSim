class_name CaptainsLogMenu
extends SimplePanel
## The Captain's Log (L, or the pause menu): the player's statistics and
## renown, recent passages, notable moments, the harbours visited, the
## sailing objectives and the secret achievements found (secret ones reveal
## nothing until they are found).
## It only reads GameSession; nothing here changes the game. The panel has a
## fixed size; long lists scroll.

const PANEL_SIZE := Vector2(1080, 0)
const TABS_SIZE := Vector2(1020, 560)
const TAB_LOG := 0
const TAB_HARBOURS := 1
const TAB_OBJECTIVES := 2
const TAB_BOAT := 3
## Notable moments listed in the Log tab (the newest).
const MAX_MOMENTS := 10
## Theme variations: decorative headings and a secret achievement's name.
const HEADING := &"DisplayHeader"
const NAME := &"DisplayName"

## The player asked to publish a travel update (Log tab).
signal publish_requested

var _tabs: TabContainer


func _ready() -> void:
	_build("Captain's Log", PANEL_SIZE.x)
	# Instrument lettering (Barlow Condensed, the display variations) for the
	# log's title and section headings; every figure stays in Barlow.
	(_box.get_node("Title") as Label).theme_type_variation = HEADING
	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.custom_minimum_size = TABS_SIZE
	_box.add_child(_tabs)
	_tabs.add_child(_build_log_tab())
	_tabs.add_child(_build_harbours_tab())
	_tabs.add_child(_build_objectives_tab())
	_tabs.add_child(_build_boat_tab())
	_button("CloseButton", "Close", close)


func show_tab(index: int) -> void:
	_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


func get_current_tab_name() -> String:
	return _tabs.get_current_tab_control().name


func focus_default() -> void:
	_tabs.get_tab_bar().grab_focus()


# --- Log tab ---------------------------------------------------------------------

func _build_log_tab() -> Control:
	var list := _tab_page("Log")
	var log := GameSession.get_captains_log()
	var grid := GridContainer.new()
	grid.name = "Statistics"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	list.add_child(grid)
	var longest := log.longest
	var longest_text := "—"
	if not longest.is_empty():
		longest_text = Loc.t("%s nm  (%s)") % [_nm(longest.nm), _passage_name(longest)]
	var catalog := PortCatalog.get_default()
	var stats := [
		[Loc.t("Distance sailed"), Loc.t("%s nm") % _nm(GameSession.get_total_nm_sailed()), "DistanceValue"],
		[Loc.t("Voyages completed"), str(log.voyages_completed), "VoyagesValue"],
		[Loc.t("Harbours visited"), Loc.t("%d of %d") % [log.get_distinct_harbours(), catalog.ports.size()], "HarboursValue"],
		[Loc.t("Harbour arrivals"), str(log.arrivals), "ArrivalsValue"],
		[Loc.t("Longest passage"), longest_text, "LongestValue"],
		["Rescues", str(GameSession.get_rescue_count()), "RescuesValue"],
		["Renown", Loc.t("%d  (%d unpublished)") % [GameSession.get_lifetime_renown(), GameSession.get_unpublished_renown()], "RenownValue"],
	]
	for stat: Array in stats:
		var name_label := Label.new()
		name_label.text = stat[0]
		name_label.theme_type_variation = &"MutedLabel"
		grid.add_child(name_label)
		var value := Label.new()
		value.name = stat[2]
		value.text = stat[1]
		value.custom_minimum_size = Vector2(320, 0)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(value)
	var renown_row := HBoxContainer.new()
	renown_row.add_theme_constant_override("separation", 16)
	list.add_child(renown_row)
	var quote := GameSession.get_publish_quote()
	var publish := Button.new()
	publish.name = "PublishButton"
	publish.text = Loc.t("Publish travel update (%s)…") % GameSession.format_money(int(quote.euros)) if int(quote.euros) > 0 else Loc.t("Publish travel update…")
	publish.disabled = not String(quote.error).is_empty()
	publish.tooltip_text = quote.error
	publish.pressed.connect(publish_requested.emit)
	renown_row.add_child(publish)
	var hint := Label.new()
	hint.name = "PublishHint"
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.text = quote.error if not String(quote.error).is_empty() else \
		Loc.t("Turns your %d unpublished renown into income (%s per renown).") % [quote.renown, GameSession.format_money(int(quote.rate))]
	renown_row.add_child(hint)
	if GameSession.is_underway():
		_add_text(list, "UnderwayNote", Loc.t("Under way to %s: %s nm sailed on this voyage so far.") % [
			catalog.get_display_name(GameSession.get_voyage_destination_id()), _nm(GameSession.get_voyage_sailed_nm())], &"MutedLabel")
	_add_text(list, "RecentTitle", "Recent passages", HEADING)
	var passages := VBoxContainer.new()
	passages.name = "Passages"
	passages.add_theme_constant_override("separation", 6)
	list.add_child(passages)
	if log.voyages.is_empty():
		_add_text(passages, "NoPassages", "No passages yet. Plot a course at the chart table and set sail.", &"MutedLabel")
	for i in range(log.voyages.size() - 1, -1, -1):
		_add_text(passages, "Passage%d" % (log.voyages.size() - 1 - i), describe_passage(log.voyages[i]))
	# Short narrative notes (the captain's hat so far): separate from the
	# voyage records above, which they never change.
	# The hat's story and (Iteration 12) Go Ashore outings, newest first.
	var history: Array[Dictionary] = []
	history.append_array(GameSession.get_hat().history)
	history.append_array(GameSession.get_shore_moments())
	history.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
	if not history.is_empty():
		_add_text(list, "MomentsTitle", "Notable moments", HEADING)
		var moments := VBoxContainer.new()
		moments.name = "Moments"
		moments.add_theme_constant_override("separation", 6)
		list.add_child(moments)
		for i in range(history.size() - 1, maxi(history.size() - 1 - MAX_MOMENTS, -1), -1):
			var entry: Dictionary = history[i]
			_add_text(moments, "Moment%d" % (history.size() - 1 - i), "%s  ·  %s" % [
				Simulation.format_game_time(float(entry.time), false), entry.text])
	return list.get_parent()


## One line of the passage list.
static func describe_passage(record: Dictionary) -> String:
	var vessel := VesselCatalog.get_default().get_vessel(StringName(record.vessel))
	var vessel_name: String = vessel.display_name if vessel else String(record.vessel)
	var outcome := "arrived" if record.outcome == String(CaptainsLog.OUTCOME_ARRIVED) else Loc.t("lost at sea, crew rescued")
	return Loc.t("%s  ·  %s  ·  %s nm  ·  %s  ·  %s, %s") % [_passage_name(record), Simulation.format_duration(float(record.ended) - float(record.departed)),
		_nm(record.nm), vessel_name, outcome, Simulation.format_game_time(record.ended, false)]


static func _passage_name(record: Dictionary) -> String:
	var catalog := PortCatalog.get_default()
	var from := "at sea" if String(record.from).is_empty() else catalog.get_display_name(StringName(record.from))
	return "%s → %s" % [from, catalog.get_display_name(StringName(record.to))]


static func _nm(value: Variant) -> String:
	return Loc.decimal(float(value))


# --- Harbours tab -----------------------------------------------------------------

func _build_harbours_tab() -> Control:
	var list := _tab_page("Harbours")
	var log := GameSession.get_captains_log()
	var catalog := PortCatalog.get_default()
	_add_text(list, "HarbourSummary", Loc.t("You have visited %d of the %d harbours on the chart. A harbour counts once you arrive and moor there.") % [
		log.get_distinct_harbours(), catalog.ports.size()], &"MutedLabel")
	# Iteration 17: by country, collapsible, with All / Visited / Not visited.
	var filters := HBoxContainer.new()
	filters.name = "HarbourFilters"
	filters.add_theme_constant_override("separation", 6)
	list.add_child(filters)
	var group := ButtonGroup.new()
	for spec in [[FILTER_ALL, "All"], [FILTER_VISITED, "Visited"], [FILTER_NOT_VISITED, Loc.t("Not visited")]]:
		var button := Button.new()
		button.name = "Filter_%s" % spec[0]
		button.text = spec[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = spec[0] == harbour_filter
		button.pressed.connect(set_harbour_filter.bind(spec[0]))
		filters.add_child(button)
	var countries := VBoxContainer.new()
	countries.name = "Countries"
	countries.add_theme_constant_override("separation", 6)
	list.add_child(countries)
	_fill_harbours(countries)
	return list.get_parent()


const FILTER_ALL := &"all"
const FILTER_VISITED := &"visited"
const FILTER_NOT_VISITED := &"not_visited"
## The harbour list's filter (kept while the game runs).
static var harbour_filter := FILTER_ALL
## Countries opened or closed by the player (country -> open), for the run.
static var _country_open := {}


func set_harbour_filter(filter: StringName) -> void:
	harbour_filter = filter
	var countries := find_child("Countries", true, false) as VBoxContainer
	if countries:
		_fill_harbours(countries)


## One group per country (alphabetical): a header with the visit count that
## opens and closes it, then its harbours (visited ones with their first
## visit and arrivals). Countries with nothing to show under the filter are
## left out; an empty filter says so.
func _fill_harbours(countries: VBoxContainer) -> void:
	for child in countries.get_children():
		countries.remove_child(child)
		child.queue_free()
	var log := GameSession.get_captains_log()
	var by_country := {}
	for port in PortCatalog.get_default().ports:
		var country := port.country if not port.country.is_empty() else Loc.t("Other")
		if not by_country.has(country):
			by_country[country] = []
		by_country[country].append(port)
	var names := by_country.keys()
	names.sort()
	var shown := 0
	for country: String in names:
		var ports: Array = by_country[country]
		ports.sort_custom(func(a: PortData, b: PortData) -> bool: return a.display_name < b.display_name)
		var visited := 0
		var rows: Array[PortData] = []
		for port: PortData in ports:
			var has := log.has_visited(port.id)
			visited += 1 if has else 0
			if harbour_filter == FILTER_ALL or (harbour_filter == FILTER_VISITED) == has:
				rows.append(port)
		if rows.is_empty():
			continue
		shown += rows.size()
		var key := country.replace(" ", "_")
		var open: bool = _country_open.get(country, visited > 0 or harbour_filter != FILTER_ALL)
		var header := Button.new()
		header.name = "Country_%s" % key
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.text = Loc.t("%s %s  ·  %d of %d visited") % ["▾" if open else "▸", country, visited, ports.size()]
		countries.add_child(header)
		var box := VBoxContainer.new()
		box.name = "Harbours_%s" % key
		box.visible = open
		countries.add_child(box)
		header.pressed.connect(func() -> void:
			_country_open[country] = not box.visible
			box.visible = not box.visible
			header.text = "%s%s" % ["▾" if box.visible else "▸", header.text.substr(1)])
		for port in rows:
			_add_text(box, "Harbour_%s" % port.id, _describe_harbour(port, log), &"" if log.has_visited(port.id) else &"MutedLabel")
	if shown == 0:
		_add_text(countries, "NoHarbours", "No harbours visited yet: arrive and moor somewhere new." if harbour_filter == FILTER_VISITED
			else Loc.t("None: you have been everywhere on the chart."), &"MutedLabel")


static func _describe_harbour(port: PortData, log: CaptainsLog) -> String:
	var place := "%s, %s" % [port.display_name, port.country]
	if not log.has_visited(port.id):
		return Loc.t("%s  ·  not visited yet") % place
	var entry: Dictionary = log.visited[String(port.id)]
	var first: float = entry.first
	var when := Loc.t("before the log was kept") if first < 0.0 else Loc.t("first %s") % Simulation.format_game_time(first, false)
	var arrivals := int(entry.arrivals)
	var visits := Loc.t("start harbour") if arrivals == 0 and first >= 0.0 else Loc.n("%d arrival", "%d arrivals", arrivals) % arrivals
	return "%s  ·  %s  ·  %s" % [place, when, visits]


# --- Objectives tab -----------------------------------------------------------------

func _build_objectives_tab() -> Control:
	var list := _tab_page("Objectives")
	var catalog := ObjectiveCatalog.get_default()
	var progress := GameSession.get_objective_progress()
	var log := GameSession.get_captains_log()
	_add_text(list, "RenownSummary", Loc.t("Renown: %d earned in all, %d not yet published. Objectives are tracked automatically and pay renown when a voyage completes them.") % [
		progress.lifetime_renown, progress.unpublished_renown], &"MutedLabel")
	_add_text(list, "LaptopHint", "Your achievements, with when and where you earned them, are on the laptop at the cabin table.", &"MutedLabel")
	_add_text(list, "OpenTitle", "Objectives", HEADING)
	var open := VBoxContainer.new()
	open.name = "Open"
	open.add_theme_constant_override("separation", 10)
	list.add_child(open)
	var done := VBoxContainer.new()
	done.name = "Completed"
	done.add_theme_constant_override("separation", 10)
	var secrets: Array[Dictionary] = []
	for objective in catalog.objectives:
		if objective.secret:
			secrets.append(objective)
			continue
		var count := progress.get_count(StringName(objective.id))
		# I024: filler retired from the collection is no longer offered as a goal.
		if (count == 0 or objective.repeatable) and not objective.retired:
			_add_objective(open, objective, describe_progress(objective, log, count))
		if count > 0:
			var entry: Dictionary = progress.completed[objective.id]
			var when := Simulation.format_game_time(float(entry.first), false)
			var times := Loc.t("  ·  %d times") % count if count > 1 else ""
			_add_text(done, "Done_%s" % objective.id, Loc.t("%s  ·  %d renown  ·  first %s%s") % [objective.title, objective.reward, when, times])
	_add_text(list, "CompletedTitle", "Completed", HEADING)
	list.add_child(done)
	if done.get_child_count() == 0:
		_add_text(done, "NoneCompleted", "None yet.", &"MutedLabel")
	_build_secrets(list, secrets, progress)
	return list.get_parent()


## Secret achievements: the ones found with their title, description, date
## and renown; the others only as a count, so nothing gives them away.
func _build_secrets(list: VBoxContainer, secrets: Array[Dictionary], progress: ObjectiveProgress) -> void:
	if secrets.is_empty():
		return
	_add_text(list, "SecretsTitle", "Secret achievements", HEADING)
	var box := VBoxContainer.new()
	box.name = "Secrets"
	box.add_theme_constant_override("separation", 10)
	list.add_child(box)
	var hidden := 0
	for objective in secrets:
		if not progress.is_completed(StringName(objective.id)):
			hidden += 1
			continue
		var entry: Dictionary = progress.completed[objective.id]
		var found := VBoxContainer.new()
		found.name = "Secret_%s" % objective.id
		found.add_theme_constant_override("separation", 2)
		box.add_child(found)
		_add_text(found, "Title", objective.title, NAME)
		_add_text(found, "Detail", Loc.t("%s  ·  %d renown  ·  found %s") % [objective.text, objective.reward,
			Simulation.format_game_time(float(entry.first), false)], &"MutedLabel")
	if hidden > 0:
		_add_text(box, "SecretsHidden", Loc.t("%s still to discover. They are not described here: you will know one when you find it.") % (
			Loc.t("One secret achievement is") if hidden == 1 else Loc.t("%d secret achievements are") % hidden), &"MutedLabel")
	else:
		_add_text(box, "SecretsHidden", "You have found every secret achievement.", &"MutedLabel")


func _add_objective(parent: Control, objective: Dictionary, status: String) -> void:
	var box := VBoxContainer.new()
	box.name = "Objective_%s" % objective.id
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var repeat := "  (repeatable)" if objective.repeatable else ""
	_add_text(box, "Title", Loc.t("%s  ·  %d renown%s") % [objective.title, objective.reward, repeat])
	_add_text(box, "Detail", "%s  %s" % [objective.text, status], &"MutedLabel")


## The progress line for an objective in the list.
static func describe_progress(objective: Dictionary, log: CaptainsLog, count: int) -> String:
	if objective.repeatable and count > 0:
		return Loc.n("Completed %d time so far.", "Completed %d times so far.", count) % count
	var value := ObjectiveCatalog.get_progress(objective, log, GameSession.get_total_nm_sailed())
	match objective.type:
		ObjectiveCatalog.TYPE_TOTAL_DISTANCE:
			return Loc.t("Progress: %s of %s nm.") % [_nm(minf(value[0], value[1])), _nm(value[1])]
		ObjectiveCatalog.TYPE_VOYAGE_COUNT, ObjectiveCatalog.TYPE_VISIT_COUNT:
			return Loc.t("Progress: %d of %d.") % [mini(int(value[0]), int(value[1])), int(value[1])]
		ObjectiveCatalog.TYPE_PASSAGE_LENGTH:
			return Loc.t("Longest passage so far: %s nm.") % _nm(value[0])
	return Loc.t("Not yet achieved.")


# --- Helpers ----------------------------------------------------------------------

# --- Boat tab (Iteration 14) ------------------------------------------------------

## The active boat's condition by area, its equipment and the care history.
func _build_boat_tab() -> Control:
	var list := _tab_page("Boat")
	var vessel := GameSession.get_vessel_definition()
	var care := GameSession.get_boat_care()
	var overall := BoatCare.overall_level(care, GameSession.get_condition(), GameSession.get_game_time())
	var heading := _add_text(list, "BoatHeading", Loc.t("The %s: %s") % [vessel.display_name, BoatCare.LEVEL_NAMES[overall].to_lower()], HEADING)
	UiTheme.tint(heading, BoatCare.LEVEL_ROLES[overall])
	var view := BoatCareView.new()
	view.name = "Overview"
	list.add_child(view)
	_add_text(list, "CareNote", "Wear comes slowly with the miles: weed on the bottom with the days in the water, the rig with the wind, the engine with its hours. Boatyards look after it; a haul-out needs a yard that can lift boats.", &"MutedLabel")
	_add_text(list, "HistoryTitle", "Boatyard visits", HEADING)
	if care.history.is_empty():
		_add_text(list, "NoHistory", "No boatyard work yet.", &"MutedLabel")
	for i in range(care.history.size() - 1, -1, -1):
		var entry: Dictionary = care.history[i]
		_add_text(list, "History%d" % i, "%s · %s" % [Simulation.format_game_time(float(entry.get("time", 0.0)), false),
			BoatCare.history_text(entry)])
	return list.get_parent()


## A scrolling tab page named `title`; returns the list to fill.
func _tab_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	return list


func _add_text(parent: Control, node_name: String, text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(200, 0)
	parent.add_child(label)
	return label
