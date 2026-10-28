class_name CabinHomeMenu
extends TradePanel
## "Make it home" (I020): which of the Captain's cabin things are shown
## aboard this boat. Opened in the cabin (action wheel); the panel stands to
## the side without dimming, so the cabin itself is the preview: a thing
## appears or is put away at once, in the place found for it (CabinDecor),
## never over a station, the galley, the chart table, a berth or the
## companion's spots. Every boat keeps its own choice; things not yet bought
## say where to find them (the chandlery).


## Room kept between the panel and the screen's edge.
const SAFE_MARGIN := 24.0


func _ready() -> void:
	_build_trade("Make it home", Loc.t("The small things that make the %s yours. Each appears in the cabin at once; put it away any time.") %
		GameSession.get_vessel_definition().display_name, 620.0)
	# A preview, not a pause: the cabin stays in view beside the panel.
	var dim := get_node_or_null(^"Dim") as Control
	if dim:
		dim.visible = false
	# A column on the right, as wide as the panel needs plus the safe margin
	# (explicit anchors: a preset applied now would use the not yet sized
	# modal and leave the panel partly off screen).
	for child in get_children():
		if child is CenterContainer:
			var column := child as Control
			column.anchor_left = 1.0
			column.anchor_right = 1.0
			column.anchor_top = 0.0
			column.anchor_bottom = 1.0
			column.offset_right = -SAFE_MARGIN
			column.offset_top = 0.0
			column.offset_bottom = 0.0
			# Its width follows the panel's real width (known once it is styled).
			column.minimum_size_changed.connect(_fit_column.bind(column))
			_fit_column.call_deferred(column)
	for item: Dictionary in HarbourTrades.get_decor():
		_row(String(item.id), Loc.t(String(item.name)), Loc.t(String(item.text)), _toggle.bind(String(item.id)))
	refresh()


func _fit_column(column: Control) -> void:
	column.offset_left = -(column.get_combined_minimum_size().x + SAFE_MARGIN)


func refresh() -> void:
	super.refresh()
	if _rows.is_empty():
		return
	var shown := GameSession.get_cabin_decor()
	for item: Dictionary in HarbourTrades.get_decor():
		var id := String(item.id)
		var button := _rows[id] as Button
		if not GameSession.get_home().owns_decor(id):
			button.text = Loc.t("At the chandlery (%s)") % GameSession.format_money(int(item.price))
			button.disabled = true
		else:
			button.text = "Put away" if id in shown else "Show it"
			button.disabled = false


func _toggle(id: String) -> void:
	var shown := not id in GameSession.get_cabin_decor()
	var error := GameSession.set_cabin_decor(id, shown)
	if error != "":
		notify(error)
	SessionLog.write("decor_shown", {"item": id, "shown": shown, "vessel": String(GameSession.get_vessel_id())})
	refresh()
