class_name LaptopView
extends ModalPanel
## The Captain's laptop, opened (I024, The Company We Keep). Using the work
## station at the cabin table brings the laptop up close: the cabin dims and
## the illustrated laptop - graphite lid, bezel, keyboard below - fills the
## view, and everything happens ON its screen. It is the one home of the
## renown and publications: the achievement collection, postcards and travel
## updates, a voyage history, and (as before) remote work and the little
## game.
##
## Four apps in a row of tabs along the top of the screen: Home, Publications,
## Achievements, Voyage history. The existing dialogs (PostcardMenu,
## ScrapbookMenu, PublishMenu, WorkMenu, GameDevMenu) are reused unchanged,
## shown on the screen (SimplePanel.embedded) - their rules, time, renown and
## saves are theirs, so nothing is counted twice. Esc closes an opened task,
## then the laptop; the × closes it at once. Mouse and keyboard (Tab, Enter,
## arrows) work throughout. No browser, no operating system: a few honest
## screens.

## Asks App to do what takes game time or a transaction (it closes the laptop
## for that and may open it again afterwards).
signal postcard_requested
signal work_requested(hours: int)
signal game_work_requested(task_id: String, choice: int)
signal publish_confirmed

const APP_HOME := &"home"
const APP_PUBLICATIONS := &"publications"
const APP_ACHIEVEMENTS := &"achievements"
const APP_HISTORY := &"history"
## I027 Tier 4: Dreams of the Sea, the Captain's own ambitions (Dreams).
const APP_DREAMS := &"dreams"
const APPS: Array[StringName] = [APP_HOME, APP_PUBLICATIONS, APP_ACHIEVEMENTS, APP_DREAMS, APP_HISTORY]
const APP_TITLES := {APP_HOME: "Home", APP_PUBLICATIONS: "Publications", APP_ACHIEVEMENTS: "Achievements", APP_DREAMS: "Dreams",
	APP_HISTORY: "Voyage history"}

## The laptop's drawing (scene units = pixels of the view).
const BODY := Color("#2E3539")
const BODY_LIGHT := Color("#4B5459")
const BEZEL := Color("#111619")
const KEYBOARD := Color("#3A4247")
const KEY := Color("#262C30")
const BADGE_SIZE := 64.0
const GREY_SHADER := preload("res://src/ui/laptop/greyed_badge.gdshader")

var app: StringName = APP_HOME
## The open task on the screen (an embedded dialog), or null.
var task: SimplePanel
## Achievements: the chosen category ("" = all) and the selected achievement.
var category := ""
var selected := ""

var _frame: Control
var _screen: PanelContainer
var _tabs := {}
var _content: Control
var _scroll: ScrollContainer
var _clock: Label
var _detail: VBoxContainer


func _init(start_app: StringName = APP_HOME) -> void:
	app = start_app if start_app in APPS else APP_HOME


func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.03, 0.05, 0.06, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_frame = Control.new()
	_frame.name = "Laptop"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.draw.connect(_draw_laptop)
	_frame.resized.connect(_layout)
	add_child(_frame)
	_screen = PanelContainer.new()
	_screen.name = "Screen"
	_screen.clip_contents = true
	var glass := StyleBoxFlat.new()
	glass.bg_color = UiTheme.color(&"surface_sunken")
	glass.set_content_margin_all(18)
	_screen.add_theme_stylebox_override(&"panel", glass)
	_frame.add_child(_screen)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_screen.add_child(column)
	column.add_child(_build_bar())
	column.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.name = "AppArea"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_layout.call_deferred()
	show_app(app)
	# Opening: the laptop comes up close.
	_frame.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_frame, "modulate:a", 1.0, 0.18)


func _build_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for id in APPS:
		var tab := Button.new()
		tab.name = "Tab_%s" % id
		tab.text = Loc.t(APP_TITLES[id])
		tab.toggle_mode = true
		tab.button_group = group
		tab.theme_type_variation = &"TocButton"
		tab.pressed.connect(show_app.bind(id))
		bar.add_child(tab)
		_tabs[id] = tab
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_clock = Label.new()
	_clock.name = "Status"
	_clock.theme_type_variation = &"MutedLabel"
	_clock.text = _status_text()
	bar.add_child(_clock)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.tooltip_text = Loc.t("Close the laptop (Esc)")
	close_button.custom_minimum_size = Vector2(44, 0)
	close_button.pressed.connect(close)
	bar.add_child(close_button)
	return bar


## "Harbour Wi-Fi · 14:20" or "Offline at sea · 14:20".
static func _status_text() -> String:
	var connection := Loc.t("Harbour Wi-Fi") if GameSession.can_work_remotely() else Loc.t("Offline at sea") if GameSession.is_underway() else Loc.t("No connection")
	return "%s  ·  %s" % [connection, Simulation.format_game_time(GameSession.get_game_time(), false)]


# --- The laptop itself ---------------------------------------------------------------

## The lid's outer rectangle and the keyboard below it, fitted to the view.
func get_lid_rect() -> Rect2:
	var view := _frame.size
	var width := minf(view.x * 0.94, (view.y * 0.86) * 1.68)
	var height := width / 1.68
	return Rect2(Vector2((view.x - width) * 0.5, maxf(view.y * 0.02, (view.y - height * 1.09) * 0.5)), Vector2(width, height))


## The screen inside the bezel (where the apps are).
func get_screen_rect() -> Rect2:
	var lid := get_lid_rect()
	var bezel := clampf(lid.size.x * 0.018, 12.0, 26.0)
	return Rect2(lid.position + Vector2(bezel, bezel * 1.3), lid.size - Vector2(bezel * 2.0, bezel * 2.3))


func _layout() -> void:
	if _screen == null:
		return
	var screen := get_screen_rect()
	_screen.position = screen.position
	_screen.size = screen.size
	_frame.queue_redraw()


func _draw_laptop() -> void:
	var lid := get_lid_rect()
	var r := lid.size.x * 0.012
	# The keyboard deck below, in perspective (wider towards the viewer).
	var hinge := lid.end.y
	var deck_h := lid.size.y * 0.085
	var deck := PackedVector2Array([Vector2(lid.position.x - lid.size.x * 0.01, hinge), Vector2(lid.end.x + lid.size.x * 0.01, hinge),
		Vector2(lid.end.x + lid.size.x * 0.05, hinge + deck_h), Vector2(lid.position.x - lid.size.x * 0.05, hinge + deck_h)])
	_frame.draw_colored_polygon(PackedVector2Array([deck[3] + Vector2(10, 14), deck[2] + Vector2(10, 14), deck[1] + Vector2(10, 4), deck[0] + Vector2(10, 4)]),
		Color(0, 0, 0, 0.25))
	_frame.draw_colored_polygon(deck, KEYBOARD)
	# The top rows of keys, foreshortened, and the trackpad's edge.
	for row in 3:
		var y0 := hinge + deck_h * (0.12 + row * 0.24)
		var y1 := y0 + deck_h * 0.17
		var spread := lerpf(1.0, 1.04, (y0 - hinge) / deck_h)
		var left := lid.position.x + lid.size.x * (0.08 - (spread - 1.0) * 0.5)
		var span := lid.size.x * 0.84 * spread
		for col in 15:
			var x0 := left + span * col / 15.0
			_frame.draw_rect(Rect2(Vector2(x0 + 2.0, y0), Vector2(span / 15.0 - 4.0, y1 - y0)), KEY)
	_frame.draw_line(deck[3], deck[2], BODY_LIGHT, 2.0)
	# The lid: graphite body, black bezel, the camera.
	var body := StyleBoxFlat.new()
	body.bg_color = BODY
	body.set_corner_radius_all(int(r * 1.6))
	body.border_color = BODY_LIGHT
	body.set_border_width_all(2)
	body.shadow_color = Color(0, 0, 0, 0.35)
	body.shadow_size = 18
	body.shadow_offset = Vector2(8, 10)
	_frame.draw_style_box(body, lid)
	var bezel := StyleBoxFlat.new()
	bezel.bg_color = BEZEL
	bezel.set_corner_radius_all(int(r))
	_frame.draw_style_box(bezel, lid.grow(-4.0))
	var screen := get_screen_rect()
	_frame.draw_circle(Vector2(lid.get_center().x, (lid.position.y + screen.position.y) * 0.5 + 2.0), 3.0, Color("#1E2427"))
	_frame.draw_circle(Vector2(lid.get_center().x, (lid.position.y + screen.position.y) * 0.5 + 2.0), 1.2, Color("#3B5560"))
	# A faint reflection across the glass, upper left.
	_frame.draw_colored_polygon(PackedVector2Array([screen.position, screen.position + Vector2(screen.size.x * 0.32, 0),
		screen.position + Vector2(screen.size.x * 0.12, screen.size.y), screen.position + Vector2(0, screen.size.y)]), Color(1, 1, 1, 0.025))


# --- Apps ----------------------------------------------------------------------------

func show_app(id: StringName) -> void:
	_close_task()
	app = id
	for key: StringName in _tabs:
		(_tabs[key] as Button).set_pressed_no_signal(key == id)
	if _content:
		_content.queue_free()
	match id:
		APP_PUBLICATIONS:
			_content = _build_publications()
		APP_ACHIEVEMENTS:
			_content = _build_achievements()
		APP_HISTORY:
			_content = _build_history()
		APP_DREAMS:
			_content = _build_dreams()
		_:
			_content = _build_home()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_scroll.scroll_vertical = 0
	if _clock:
		_clock.text = _status_text()


func get_content() -> Control:
	return _content


## Opens an existing dialog on the screen (embedded). Its "closed" brings the
## app back.
func open_task(panel: SimplePanel) -> SimplePanel:
	_close_task()
	panel.embedded = true
	panel.name = "Task"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.notification_requested.connect(notify)
	panel.closed.connect(func() -> void:
		if task == panel:
			show_app(app)
	, CONNECT_ONE_SHOT)
	if _content:
		_content.queue_free()
		_content = null
	task = panel
	_scroll.add_child(panel)
	_scroll.scroll_vertical = 0
	panel.custom_minimum_size.y = maxf(_scroll.size.y - 4.0, 0.0)
	panel.focus_default.call_deferred()
	return panel


func _close_task() -> void:
	if task and is_instance_valid(task):
		task.queue_free()
	task = null


func handle_back() -> void:
	if task:
		show_app(app)
	else:
		close()


func focus_default() -> void:
	(_tabs[app] as Button).grab_focus()


# Home: who the Captain is in public, at a glance.
func _build_home() -> Control:
	var page := _page("Home")
	var vessel := VesselCatalog.get_default().get_vessel(GameSession.get_vessel_id())
	var location := GameSession.get_location()
	var where := Loc.t("in %s") % location.display_name if location else Loc.t("at sea, %s") % AchievementCatalog.format_position(GameSession.get_vessel_position())
	_text(page, &"Subtitle", "%s  ·  %s" % [vessel.display_name if vessel else "", where], &"MutedLabel")
	var progress := GameSession.get_objective_progress()
	var collection := AchievementCatalog.get_default()
	var counts := collection.count_unlocked(progress)
	var tiles := HBoxContainer.new()
	tiles.name = "Tiles"
	tiles.add_theme_constant_override("separation", 12)
	page.add_child(tiles)
	_tile(tiles, "Renown", str(progress.lifetime_renown), Loc.t("%d not yet published") % progress.unpublished_renown)
	_tile(tiles, "Achievements", Loc.t("%d of %d") % [counts.x, counts.y], Loc.t("unlocked"))
	_tile(tiles, "Publications", str(GameSession.get_pastimes().postcards.size() + progress.publications),
		Loc.t("%d postcards, %d travel updates") % [GameSession.get_pastimes().postcards.size(), progress.publications])
	_heading(page, "Recent achievements")
	var recent := collection.collection(progress).filter(func(e: Dictionary) -> bool: return not e.unlock.is_empty()).slice(0, 3)
	if recent.is_empty():
		_text(page, &"NoAchievements", "None yet. Your first passage will be one.", &"MutedLabel")
	for entry: Dictionary in recent:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		page.add_child(row)
		row.add_child(_badge(entry.achievement, true, 40.0))
		_text(row, &"Recent_%s" % entry.achievement.id, "%s  ·  %s" % [Loc.t(entry.achievement.title), AchievementCatalog.describe_when(entry.unlock)])
	_heading(page, "Recent postcards")
	var cards := GameSession.get_pastimes().postcards
	if cards.is_empty():
		_text(page, &"NoPostcards", "No postcards yet: make one under Publications.", &"MutedLabel")
	for i in range(cards.size() - 1, maxi(cards.size() - 4, -1), -1):
		var card: Dictionary = cards[i]
		_text(page, StringName("Card_%d" % i), "%s  ·  %s  ·  %s" % [Pastimes.kind_name(card.kind), String(card.get("place", "")),
			Simulation.format_game_time(float(card.time), false)], &"MutedLabel")
	_heading(page, "Aboard")
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 12)
	page.add_child(actions)
	var work := _action(actions, "WorkButton", "Remote work…", func() -> void: open_work())
	if not GameSession.can_work_remotely():
		work.disabled = true
		work.tooltip_text = Loc.t("Remote work needs a steady connection: moor in a harbour first.")
	_action(actions, "GameButton", Loc.t("Your little game…"), func() -> void: open_game())
	return page


func open_work() -> WorkMenu:
	var menu := WorkMenu.new()
	menu.work_requested.connect(work_requested.emit)
	menu.publish_requested.connect(func() -> void: open_publish())
	return open_task(menu) as WorkMenu


func open_game() -> GameDevMenu:
	var menu := GameDevMenu.new()
	menu.work_requested.connect(func(task_id: String, choice: int) -> void: game_work_requested.emit(task_id, choice))
	return open_task(menu) as GameDevMenu


# Publications: postcards and travel updates (the existing composer).
func _build_publications() -> Control:
	var page := _page("Publications")
	_text(page, &"Info", "Postcards from the Sea and travel updates are how the world hears of your voyages. A postcard of a new subject earns renown once; a travel update turns your unpublished renown into income.", &"MutedLabel")
	var progress := GameSession.get_objective_progress()
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 12)
	page.add_child(actions)
	_action(actions, "PostcardButton", "Make a postcard…", func() -> void: open_postcards())
	_action(actions, "ScrapbookButton", Loc.t("Scrapbook (%d)") % GameSession.get_pastimes().postcards.size(), func() -> void: open_task(ScrapbookMenu.new()))
	var publish := _action(actions, "PublishButton", Loc.t("Travel update… (%d renown)") % progress.unpublished_renown, func() -> void: open_publish())
	publish.disabled = progress.unpublished_renown <= 0
	_heading(page, "Published so far")
	_text(page, &"Totals", Loc.t("%d postcards in the scrapbook. %d travel updates, %d renown shared, %s earned.") % [
		GameSession.get_pastimes().postcards.size(), progress.publications, progress.published_renown,
		GameSession.format_money(progress.published_euros)])
	return page


func open_postcards() -> PostcardMenu:
	var menu := PostcardMenu.new()
	menu.make_requested.connect(postcard_requested.emit)
	menu.scrapbook_requested.connect(func() -> void: open_task(ScrapbookMenu.new()))
	return open_task(menu) as PostcardMenu


func open_publish() -> PublishMenu:
	var menu := PublishMenu.new()
	menu.publish_confirmed.connect(publish_confirmed.emit)
	return open_task(menu) as PublishMenu


# Achievements: the collection, unlocked first (most recent), then locked.
func _build_achievements() -> Control:
	var page := _page("Achievements")
	var catalog := AchievementCatalog.get_default()
	var progress := GameSession.get_objective_progress()
	var counts := catalog.count_unlocked(progress)
	_text(page, &"Count", Loc.t("%d of %d unlocked. Unlocked achievements come first, the most recent at the top.") % [counts.x, counts.y], &"MutedLabel")
	var filters := HFlowContainer.new()
	filters.name = "Filters"
	filters.add_theme_constant_override("h_separation", 6)
	filters.add_theme_constant_override("v_separation", 6)
	page.add_child(filters)
	var group := ButtonGroup.new()
	var choices: Array[Dictionary] = [{"id": "", "title": "All"}]
	choices.append_array(catalog.get_categories())
	for c: Dictionary in choices:
		var chip := Button.new()
		chip.name = "Filter_%s" % (c.id if c.id != "" else "all")
		chip.text = Loc.t(c.title)
		chip.toggle_mode = true
		chip.button_group = group
		chip.theme_type_variation = &"TocButton"
		chip.set_pressed_no_signal(c.id == category)
		chip.pressed.connect(set_category.bind(String(c.id)))
		filters.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 4 if _screen.size.x > 1100.0 else 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grid)
	var entries := catalog.collection(progress, category)
	if selected == "" or not entries.any(func(e: Dictionary) -> bool: return e.achievement.id == selected):
		selected = String(entries[0].achievement.id) if not entries.is_empty() else ""
	for entry: Dictionary in entries:
		grid.add_child(_achievement_tile(entry))
	var side := PanelContainer.new()
	side.theme_type_variation = &"SectionPanel"
	side.custom_minimum_size = Vector2(320, 0)
	row.add_child(side)
	_detail = VBoxContainer.new()
	_detail.name = "Detail"
	_detail.add_theme_constant_override("separation", 8)
	side.add_child(_detail)
	_fill_detail(entries)
	return page


## The collection in the order shown (for tests): [achievement id].
func get_shown_ids() -> Array[String]:
	var ids: Array[String] = []
	var grid := _content.find_child(&"Grid", true, false) if _content else null
	if grid:
		for tile in grid.get_children():
			ids.append(String(tile.get_meta(&"achievement")))
	return ids


func set_category(id: String) -> void:
	category = id
	selected = ""
	show_app(APP_ACHIEVEMENTS)


func select_achievement(id: String) -> void:
	selected = id
	var progress := GameSession.get_objective_progress()
	_fill_detail(AchievementCatalog.get_default().collection(progress, category))
	var grid := _content.find_child(&"Grid", true, false) if _content else null
	if grid:
		for tile: Button in grid.get_children():
			tile.set_pressed_no_signal(String(tile.get_meta(&"achievement")) == id)


func _achievement_tile(entry: Dictionary) -> Button:
	var achievement: Dictionary = entry.achievement
	var unlocked := not (entry.unlock as Dictionary).is_empty()
	var tile := Button.new()
	tile.name = "Achievement_%s" % achievement.id
	tile.set_meta(&"achievement", achievement.id)
	tile.set_meta(&"unlocked", unlocked)
	tile.toggle_mode = true
	tile.set_pressed_no_signal(achievement.id == selected)
	tile.custom_minimum_size = Vector2(150, 132)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = AchievementCatalog.shown_text(achievement, unlocked)
	tile.pressed.connect(select_achievement.bind(String(achievement.id)))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	tile.add_child(box)
	var badge := _badge(achievement, unlocked, BADGE_SIZE)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(badge)
	var title := Label.new()
	title.text = AchievementCatalog.shown_title(achievement, unlocked)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(130, 0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.theme_type_variation = &"" if unlocked else &"MutedLabel"
	box.add_child(title)
	return tile


## A badge picture: the full illustration when unlocked; locked, greyed and
## dimmed with a small padlock over it (so it reads as locked without colour).
func _badge(achievement: Dictionary, unlocked: bool, size: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var picture := TextureRect.new()
	picture.name = "Badge"
	picture.texture = AchievementCatalog.icon_of(achievement, unlocked)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(picture)
	if not unlocked:
		var material := ShaderMaterial.new()
		material.shader = _grey_shader()
		picture.material = material
		var lock := Control.new()
		lock.name = "Lock"
		lock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.draw.connect(func() -> void: _draw_lock(lock, size))
		holder.add_child(lock)
	elif picture.texture == null:
		picture.texture = null
	return holder


static func _grey_shader() -> Shader:
	return GREY_SHADER


static func _draw_lock(canvas: Control, size: float) -> void:
	var s := size * 0.22
	var at := Vector2(size - s * 1.05, size - s * 1.15)
	canvas.draw_circle(at + Vector2(s * 0.5, s * 0.55), s * 0.78, Color(0.07, 0.1, 0.12, 0.85))
	canvas.draw_arc(at + Vector2(s * 0.5, s * 0.38), s * 0.24, PI, TAU, 10, Color(0.85, 0.89, 0.88), 1.6)
	canvas.draw_rect(Rect2(at + Vector2(s * 0.18, s * 0.4), Vector2(s * 0.64, s * 0.5)), Color(0.85, 0.89, 0.88))


func _fill_detail(entries: Array[Dictionary]) -> void:
	if _detail == null:
		return
	for child in _detail.get_children():
		_detail.remove_child(child)  # its names are free for the new detail at once
		child.queue_free()
	var found := entries.filter(func(e: Dictionary) -> bool: return e.achievement.id == selected)
	if found.is_empty():
		_text(_detail, &"Empty", "Choose an achievement to see it here.", &"MutedLabel")
		return
	var entry: Dictionary = found[0]
	var achievement: Dictionary = entry.achievement
	var unlock: Dictionary = entry.unlock
	var unlocked := not unlock.is_empty()
	var badge := _badge(achievement, unlocked, 112.0)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail.add_child(badge)
	var title := _text(_detail, &"Title", AchievementCatalog.shown_title(achievement, unlocked), &"HeaderLabel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var catalog := AchievementCatalog.get_default()
	var reward := int(unlock.get("reward", achievement.reward)) if unlocked else int(achievement.reward)
	var meta := catalog.get_category_title(achievement.category)
	if reward > 0 and (unlocked or not achievement.secret):
		meta += "  ·  " + Loc.t("%d renown") % reward
	_text(_detail, &"Category", meta, &"MutedLabel")
	_text(_detail, &"Text", AchievementCatalog.shown_text(achievement, unlocked))
	if not unlocked:
		_text(_detail, &"Status", "Not yet unlocked.", &"MutedLabel")
		return
	_text(_detail, &"When", Loc.t("Unlocked: %s") % AchievementCatalog.describe_when(unlock))
	if float(unlock.time) >= 0.0 or not (unlock.at as Dictionary).is_empty():
		_text(_detail, &"Where", AchievementCatalog.describe_where(unlock))
	var boat := AchievementCatalog.describe_boat(unlock)
	if boat != "":
		_text(_detail, &"Boat", Loc.t("Aboard the %s") % boat, &"MutedLabel")


# Voyage history: what the log knows, nothing invented.
## Dreams of the Sea (I027 Tier 4): every dream, the ones pursued first, then
## the open ones, the fulfilled ones and those for later; a dream is pursued
## or set aside here. Nothing is a quest: no order, no reward.
func _build_dreams() -> Control:
	var page := _page("Dreams of the Sea")
	_text(page, &"Intro", "The voyages you once only read about. Choose up to three to pursue; each comes true by itself, in any order.", &"MutedLabel")
	var order := {GameSession.DREAM_PURSUING: 0, GameSession.DREAM_OPEN: 1, GameSession.DREAM_FULFILLED: 2, GameSession.DREAM_LATER: 3}
	var dreams := Dreams.all().duplicate()
	dreams.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(order[GameSession.get_dream_status(StringName(a.id))]) < int(order[GameSession.get_dream_status(StringName(b.id))]))
	var log := GameSession.get_captains_log()
	for dream: Dictionary in dreams:
		var id := StringName(dream.id)
		var status := GameSession.get_dream_status(id)
		var card := PanelContainer.new()
		card.name = "Dream_%s" % id
		card.theme_type_variation = &"SectionPanel"
		card.modulate = Color(1, 1, 1, 0.6) if status == GameSession.DREAM_LATER else Color.WHITE
		page.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(box)
		_text(box, &"Title", Loc.t(String(dream.title)), &"HeaderLabel")
		_text(box, &"Text", Loc.t(String(dream.text)))
		_text(box, &"Status", _dream_status_text(dream, status, log), &"MutedLabel")
		if status == GameSession.DREAM_OPEN or status == GameSession.DREAM_PURSUING:
			var button := _action(row, "PursueButton", "Set aside" if status == GameSession.DREAM_PURSUING else "Pursue this dream",
				_toggle_dream.bind(id, status != GameSession.DREAM_PURSUING))
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return page


func _dream_status_text(dream: Dictionary, status: StringName, log: CaptainsLog) -> String:
	match status:
		GameSession.DREAM_FULFILLED:
			var record := GameSession.get_dream_record(StringName(dream.id))
			var port := PortCatalog.get_default().get_display_name(StringName(str(record.get("port", ""))))
			return Loc.t("Came true in %s, %s.") % [port, Simulation.format_game_time(float(record.get("time", 0.0)), false)] if port != "" \
				else Loc.t("Came true.")
		GameSession.DREAM_LATER:
			return Loc.t("Later in your life afloat.")
	var progress := Dreams.progress_text(dream, log)
	var lead := Loc.t("Pursuing.") if status == GameSession.DREAM_PURSUING else Loc.t("Not pursued yet.")
	return lead + ("  " + progress if progress != "" else "")


func _toggle_dream(id: StringName, pursue: bool) -> void:
	var error := GameSession.set_dream_pursued(id, pursue)
	if error != "":
		notify(error)
	show_app(APP_DREAMS)


func _build_history() -> Control:
	var page := _page("Voyage history")
	var log := GameSession.get_captains_log()
	var progress := GameSession.get_objective_progress()
	var grid := GridContainer.new()
	grid.name = "Records"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	page.add_child(grid)
	var rows := [
		[Loc.t("Voyages completed"), str(log.voyages_completed)],
		[Loc.t("Distance sailed"), Loc.format("%.0f nm", log.total_nm)],
		[Loc.t("Harbours visited"), str(log.get_distinct_harbours())],
		[Loc.t("Longest passage"), Loc.format("%.0f nm", log.get_longest_nm()) if log.get_longest_nm() > 0.0 else Loc.t("none yet")],
		[Loc.t("Best hour under sail"), _record_text(progress.get_record(GameSession.RECORD_BEST_HOUR), "%.1f kn")],
		[Loc.t("Best 24 hours under sail"), _record_text(progress.get_record(GameSession.RECORD_BEST_DAY), "%.0f nm")],
		[Loc.t("Travel updates"), Loc.t("%d, %s earned") % [progress.publications, GameSession.format_money(progress.published_euros)]],
	]
	for row: Array in rows:
		_text(grid, &"Key", row[0], &"MutedLabel")
		_text(grid, &"Value", row[1])
	_text(page, &"SpeedNote", "Speeds are averages under sail alone, over a whole hour or day without the engine, as the log measured them.", &"MutedLabel")
	# I025: who sails along, and where each came aboard (from its own record).
	var companions := GameSession.get_companions()
	if not companions.is_empty():
		_heading(page, "Aboard")
		for i in companions.size():
			_text(page, StringName("Companion_%d" % i), _companion_history(companions[i]), &"MutedLabel")
	_heading(page, "Recent passages")
	var voyages: Array = log.voyages
	if voyages.is_empty():
		_text(page, &"NoPassages", "No passages yet.", &"MutedLabel")
	for i in range(voyages.size() - 1, maxi(voyages.size() - 7, -1), -1):
		_text(page, StringName("Passage_%d" % i), CaptainsLogMenu.describe_passage(voyages[i]), &"MutedLabel")
	# Earlier honours: renown records of goals retired from the collection.
	var objectives := ObjectiveCatalog.get_default()
	var earlier: Array[String] = []
	for objective in objectives.objectives:
		if objective.retired and progress.is_completed(StringName(objective.id)):
			earlier.append(Loc.t(objective.title))
	if not earlier.is_empty():
		_heading(page, "Earlier honours")
		_text(page, &"Earlier", ", ".join(earlier), &"MutedLabel")
	return page


## "Welcomed Biscuit aboard in Helsingør, 3 June." - or, for a companion
## without an adoption record, that it has sailed along from the start.
static func _companion_history(companion: CompanionState) -> String:
	if not companion.has_adoption_record():
		return Loc.t("%s: aboard from the start.") % CompanionRemarks.subject(CompanionRemarks.identity(companion))
	var port := PortCatalog.get_default().get_display_name(StringName(companion.adopted_port)) if companion.adopted_port != "" else ""
	return "%s  ·  %s" % [CompanionRemarks.welcomed_line(companion, port), Simulation.format_game_time(companion.adopted_at, false)]


static func _record_text(record: Dictionary, format: String) -> String:
	if record.is_empty():
		return Loc.t("not yet measured")
	var vessel := VesselCatalog.get_default().get_vessel(StringName(str(record.get("vessel", ""))))
	return "%s  ·  %s  ·  %s" % [Loc.format(format, float(record.value)), vessel.display_name if vessel else "",
		Simulation.format_game_time(float(record.time), false)]


# --- Helpers -------------------------------------------------------------------------

func _page(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "App_%s" % title.replace(" ", "")
	page.add_theme_constant_override("separation", 10)
	_text(page, &"AppTitle", title, &"HeaderLabel")
	return page


func _heading(parent: Control, title: String) -> Label:
	var label := _text(parent, &"Heading", title)
	label.add_theme_color_override(&"font_color", UiTheme.color(&"heading"))
	return label


func _text(parent: Control, node_name: StringName, text: String, variation: StringName = &"") -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = Loc.t(text) if not text.is_empty() else text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(120, 0)
	parent.add_child(label)
	return label


func _tile(parent: Control, title: String, value: String, note: String) -> void:
	var tile := PanelContainer.new()
	tile.name = "Tile_%s" % title
	tile.theme_type_variation = &"SectionPanel"
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(tile)
	var box := VBoxContainer.new()
	tile.add_child(box)
	_text(box, &"Title", title, &"MutedLabel")
	_text(box, &"Value", value, &"HeaderLabel")
	_text(box, &"Note", note, &"MutedLabel")


func _action(parent: Control, node_name: String, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = Loc.t(text)
	button.custom_minimum_size = Vector2(200, 0)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
