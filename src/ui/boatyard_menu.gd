class_name BoatyardMenu
extends ModalPanel
## The boatyard: browse the boats and move aboard another one. Opened from the
## boatyard station on deck, in harbour only (App checks; switching itself is
## GameSession.switch_vessel()). Since I022 a boat has a price: one you do not
## own yet is bought first (GameSession.buy_vessel, once, never below zero
## money); boats you own are yours for good, and moving between them is free
## and keeps everything else: the time, the harbour, the companion and the
## saved progress.
##
## The preview is the vessel's art-only deck scene (VesselVisual) in a
## SubViewport, so it shows exactly the art the game uses, sprites included,
## without any gameplay nodes. The comparison is computed from each boat's
## VesselProfile, so it always matches how the boats really sail.
##
## The panel has a fixed size (PANEL_SIZE, made smaller only when the window
## is too small for it), like the chart's sidebar: choosing another boat only
## changes the text inside it. Long details scroll in their own area, and the
## services and buttons stay where they are.
##
## Harbour services for the boat you are aboard: Boat care (Iteration 14:
## repairs, services, haul-outs and equipment, in BoatCareMenu) and the
## grocery store (provisions are bought there).

signal vessel_chosen(vessel_id: StringName)
## The player wants Boat care (App opens it on top of the boatyard).
signal care_requested
## The player wants the grocery store (App opens it on top of the boatyard).
signal grocery_requested
## The harbour trades at the yard (I020): the chandlery and the sailmaker.
signal chandlery_requested
signal sailmaker_requested

var _chandlery: Button
var _sailmaker: Button

## Conditions used for the comparison table.
const COMPARE_WIND_KN := 12.0
const COMPARE_ANGLES: Array[float] = [45.0, 90.0, 150.0]
const PREVIEW_SIZE := Vector2i(440, 220)
## The panel's fixed size, and the margin kept to the window edges.
const PANEL_SIZE := Vector2(1180, 860)
const WINDOW_MARGIN := 24.0

var selected: VesselDefinition

var _buttons := {}
var _compare_cells := {}

@onready var _list: VBoxContainer = %VesselList
@onready var _viewport: SubViewport = %PreviewViewport
@onready var _name: Label = %NameLabel
@onready var _hull: Label = %HullLabel
@onready var _description: Label = %Description
@onready var _specs: GridContainer = %Specs
@onready var _compare: GridContainer = %Comparison
@onready var _choose: Button = %ChooseButton
@onready var _panel: PanelContainer = %Panel
@onready var _condition: Label = %ConditionLabel
@onready var _service_status: Label = %ServiceStatus
@onready var _care: Button = %CareButton
@onready var _grocery: Button = %GroceryButton


func _ready() -> void:
	var group := ButtonGroup.new()
	var catalog := VesselCatalog.get_default()
	for vessel in catalog.vessels:
		var button := Button.new()
		button.name = String(vessel.id)
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(230, 64)
		button.text = vessel.display_name + "\n" + vessel.get_hull_type_name() + "  " + _ownership(vessel)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(select.bind(vessel.id))
		_list.add_child(button)
		_buttons[vessel.id] = button
	_build_comparison(catalog.vessels)
	_choose.pressed.connect(func() -> void: vessel_chosen.emit(selected.id))
	%CloseButton.pressed.connect(close)
	_care.pressed.connect(care_requested.emit)
	_grocery.pressed.connect(grocery_requested.emit)
	# I020: the yard's neighbours, beside Boat care.
	_sailmaker = _trade_button("SailmakerButton", "Sailmaker…", sailmaker_requested.emit)
	_chandlery = _trade_button("ChandleryButton", "Chandlery…", chandlery_requested.emit)
	# Steady Hands: the boats, details and comparison scroll when the screen
	# is too short (title, services and buttons always stay in view).
	var box := _panel.get_node(^"VBox")
	FitScroll.wrap([box.get_node(^"Body"), box.get_node(^"CompareTitle"), box.get_node(^"Comparison")] as Array[Control], _panel)
	resized.connect(_fit_panel)
	_fit_panel()
	select(GameSession.get_vessel_id())


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_update_services()


func _trade_button(node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = _care.custom_minimum_size
	button.pressed.connect(action)
	_care.add_sibling(button)
	return button


## Keeps the panel at PANEL_SIZE, or as large as the window allows.
func _fit_panel() -> void:
	var available := size - Vector2.ONE * WINDOW_MARGIN * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		available = PANEL_SIZE
	_panel.custom_minimum_size = Vector2(minf(PANEL_SIZE.x, available.x), minf(PANEL_SIZE.y, available.y))


## The panel's size on screen (tests compare it across selections).
func get_panel_rect() -> Rect2:
	return _panel.get_global_rect()


func _update_services() -> void:
	var provisions := GameSession.get_provisions()
	var vessel := GameSession.get_vessel_definition()
	_service_status.text = Loc.t("Your boat, the %s: hull %s  ·  %s  ·  food %s, water %s") % [vessel.display_name,
		VesselCondition.describe(GameSession.get_condition()), GameSession.format_money(GameSession.get_funds()),
		Provisions.format_days(provisions.food_days), Provisions.format_days(provisions.water_days)]
	var level := BoatCare.overall_level(GameSession.get_boat_care(), GameSession.get_condition(), GameSession.get_game_time())
	_care.disabled = not GameSession.is_moored_in_harbour()
	_care.text = "Boat care…" if level in [BoatCare.LEVEL_GOOD, BoatCare.LEVEL_COSMETIC] else Loc.t("Boat care (%s)…") % Loc.t(BoatCare.LEVEL_NAMES[level]).to_lower()
	_sailmaker.visible = GameSession.has_facility(HarbourFacilities.SAILMAKER)
	_chandlery.visible = GameSession.has_facility(HarbourFacilities.CHANDLERY)
	var store := GameSession.has_facility(HarbourFacilities.GROCERY)
	_grocery.disabled = not store or provisions.is_full(GameSession.get_passage_store_days())
	_grocery.visible = store
	_grocery.text = Loc.t("Grocery store (%s)…") % GameSession.format_money(GameSession.get_provisions_price()) \
		if not provisions.is_full() else Loc.t("Grocery store…")


## Refreshes the condition shown after work done in Boat care.
func refresh_condition() -> void:
	_update_services()
	if selected:
		select(selected.id)


func _input(event: InputEvent) -> void:
	# Up/Down browse the boats (before GUI focus navigation takes them).
	if not is_visible_in_tree() or event.is_echo():
		return
	var step := 0
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
		step = -1
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
		step = 1
	if step == 0:
		return
	var ids := VesselCatalog.get_default().get_ids()
	select(ids[wrapi(ids.find(selected.id) + step, 0, ids.size())])
	get_viewport().set_input_as_handled()


## Shows `vessel_id` in the preview and details.
func select(vessel_id: StringName) -> void:
	var vessel := VesselCatalog.get_default().get_vessel(vessel_id)
	if vessel == null:
		return
	selected = vessel
	for id: StringName in _buttons:
		(_buttons[id] as Button).set_pressed_no_signal(id == vessel_id)
	_name.text = vessel.display_name
	_hull.text = vessel.get_hull_type_name()
	_description.text = vessel.description
	_condition.text = Loc.t("Condition %s") % VesselCondition.describe(GameSession.get_vessel_condition(vessel_id))
	for child in _specs.get_children():
		_specs.remove_child(child)
		child.queue_free()
	for key: String in vessel.specs:
		_specs.add_child(_label(key, &"MutedLabel"))
		var value := _label(vessel.specs[key])
		# Wraps inside the fixed panel instead of widening it.
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_specs.add_child(value)
	for key: Array in _compare_cells:
		var cell := _compare_cells[key] as Label
		cell.modulate = Color.WHITE if key[0] == vessel_id else Color(1, 1, 1, 0.55)
	_specs.add_child(_label(Loc.t("Price"), &"MutedLabel"))
	_specs.add_child(_label(_ownership(vessel)))
	var current := vessel_id == GameSession.get_vessel_id()
	var owned := GameSession.owns_vessel(vessel_id)
	var affordable := owned or vessel.price <= GameSession.get_funds()
	_choose.disabled = current or not affordable
	if current:
		_choose.text = "This is your boat"
	elif owned:
		_choose.text = Loc.t("Move aboard the %s") % vessel.display_name
	elif affordable:
		_choose.text = Loc.t("Buy the %s (%s)…") % [vessel.display_name, GameSession.format_money(vessel.price)]
	else:
		_choose.text = Loc.t("%s needed to buy it") % GameSession.format_money(vessel.price)
	_show_preview(vessel)


## The comparison figures for one boat: [label, value text] rows.
static func compare_rows(vessel: VesselDefinition) -> Array:
	var profile := vessel.performance
	var rows := [[Loc.t("Top speed under sail"), Loc.format("%.1f kn", profile.max_sail_speed_kn)]]
	for angle in COMPARE_ANGLES:
		rows.append([Loc.t("%d kn wind at %d°") % [COMPARE_WIND_KN, angle],
			Loc.format("%.1f kn", profile.sail_speed_kn(COMPARE_WIND_KN, angle))])
	rows.append([Loc.t("Under engine"), Loc.format("%.1f kn", profile.engine_speed_kn)])
	return rows


func get_preview_root() -> Node:
	return _viewport.get_child(0) if _viewport.get_child_count() > 0 else null


func focus_default() -> void:
	if _choose.disabled:
		%CloseButton.grab_focus()
	else:
		_choose.grab_focus()


func _build_comparison(vessels: Array[VesselDefinition]) -> void:
	_compare.columns = vessels.size() + 1
	_compare.add_child(_label(""))
	for vessel in vessels:
		var head := _label(vessel.display_name, &"HeaderLabel")
		_compare_cells[[vessel.id, -1]] = head
		_compare.add_child(head)
	var rows := compare_rows(vessels[0]).size() if not vessels.is_empty() else 0
	for row in rows:
		_compare.add_child(_label(compare_rows(vessels[0])[row][0], &"MutedLabel"))
		for vessel in vessels:
			var cell := _label(compare_rows(vessel)[row][1])
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_compare_cells[[vessel.id, row]] = cell
			_compare.add_child(cell)


func _show_preview(vessel: VesselDefinition) -> void:
	for child in _viewport.get_children():
		_viewport.remove_child(child)
		child.queue_free()
	if vessel.deck_visual_scene == null:
		return
	var visual := vessel.deck_visual_scene.instantiate() as VesselVisual
	var root := Node2D.new()
	root.name = "Preview"
	root.add_child(visual)
	visual.apply(vessel.get_active_visual_profile())
	visual.set_condition(GameSession.get_vessel_condition(vessel.id), "%s/exterior" % vessel.id)
	var camera := Camera2D.new()
	var fit := minf(PREVIEW_SIZE.x / visual.canvas.size.x, PREVIEW_SIZE.y / visual.canvas.size.y) * 0.95
	camera.zoom = Vector2(fit, fit)
	camera.position = visual.canvas.get_center()
	root.add_child(camera)
	_viewport.add_child(root)
	camera.make_current()


## "(your boat)", "Yours" or the price.
static func _ownership(vessel: VesselDefinition) -> String:
	if vessel.id == GameSession.get_vessel_id():
		return Loc.t("(your boat)")
	return Loc.t("Yours") if GameSession.owns_vessel(vessel.id) else GameSession.format_money(vessel.price)


static func _label(text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label
