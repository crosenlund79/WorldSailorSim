extends RefCounted
## I022, The Captain's Academy: the Handbook's data (every key in a text is a
## real binding, every page reachable, Danish complete), search, the progress
## in the settings, the first new game's offer (closable, once, never on a
## loaded game), the First Voyage ticked off by real actions, the tips (once,
## never over a window or a warning, off in Settings) and the Handbook window.

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_data()
	_test_keys_and_search()
	_test_settings()
	AcademyGuide.enabled = true
	Simulation.auto_advance = false
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_offer()
	await _test_first_voyage()
	await _test_tips()
	await _test_handbook()
	app.modals.clear()
	await t.frames(2)
	app.queue_free()
	await t.frames(2)
	AcademyGuide.enabled = false
	SaveManager.delete_slot(3)
	Simulation.auto_advance = true  # as the other suites leave it
	SettingsManager.set_academy({})
	SettingsManager.set_tips_enabled(true)


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


## Every text of the Academy, with what it is.
func _texts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for page: Dictionary in Academy.pages():
		out.append({"where": "page " + String(page.id), "text": String(page.text)})
	for step: Dictionary in Academy.steps():
		out.append({"where": "step " + String(step.id), "text": String(step.text)})
	var tips: Dictionary = Academy.data().tips
	for id: String in tips:
		out.append({"where": "tip " + id, "text": String(tips[id].text)})
	out.append({"where": "farewell", "text": String(Academy.data().first_voyage_done.text)})
	return out


func _test_data() -> void:
	var categories := Academy.categories().map(func(c: Dictionary) -> String: return String(c.id))
	var ids := Academy.pages().map(func(p: Dictionary) -> String: return String(p.id))
	t.check(Academy.pages().size() >= 20 and Academy.pages().all(func(p: Dictionary) -> bool: return categories.has(String(p.category))),
		"[handbook] %d pages, each in a chapter" % Academy.pages().size())
	var linked: Array = Academy.steps().map(func(s: Dictionary) -> String: return String(s.page))
	var tips: Dictionary = Academy.data().tips
	for id: String in tips:
		linked.append(String(tips[id].page))
	t.check(linked.all(func(page: String) -> bool: return ids.has(page)), "[handbook] every step and tip links to a page that exists")
	var wrong: Array[String] = []
	var regex := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for entry in _texts():
		for found in regex.search_all(entry.text):
			var name := found.get_string(1)
			if not (Academy.FIXED_KEYS.has(name) or name == "move" or InputMap.has_action(StringName(name))):
				wrong.append("%s: {%s}" % [entry.where, name])
	t.check(wrong.is_empty(), "[keys] every key in a text is a real binding or F1/F5/F9 (%s)" % [wrong])
	var plain := RegEx.create_from_string("\\b(press|Press|tryk|Tryk) [A-Z]\\b")
	var hardcoded := _texts().filter(func(e: Dictionary) -> bool: return plain.search(e.text) != null).map(func(e: Dictionary) -> String: return e.where)
	t.check(hardcoded.is_empty(), "[keys] no key letters written into the texts (%s)" % [hardcoded])
	t.check(Academy.steps().size() == 8, "[first voyage] eight steps from walking to letting time run")


func _test_keys_and_search() -> void:
	t.check(Academy.key("interact") == "E" and Academy.key("pause") == "Esc" and Academy.key("captains_log") == "L" and Academy.key("handbook") == "F1",
		"[keys] from the bindings: interact %s, menu %s, log %s, Handbook %s" % [Academy.key("interact"), Academy.key("pause"), Academy.key("captains_log"), Academy.key("handbook")])
	t.check(Academy.key("move").begins_with("WASD") and Academy.key("move").contains("↑"), "[keys] moving: %s" % Academy.key("move"))
	var filled := Academy.fill(String(Academy.page("controls").text))
	t.check(not filled.contains("{") and filled.contains("E ") and filled.contains("F1"), "[keys] the controls page filled in: %s" % filled.left(80))
	t.check(Academy.search("anchor").has("anchor") and Academy.search("anchor drags").size() >= 1 and Academy.search("zzzz").is_empty()
		and Academy.search("").size() == Academy.pages().size(), "[search] by words; nothing for nonsense; everything for an empty search")
	SettingsManager.set_language(&"da")
	var untranslated: Array[String] = []
	for entry in _texts():
		if Loc.t(entry.text) == entry.text or Academy.fill(entry.text).contains("{"):
			untranslated.append(entry.where)
	t.check(untranslated.is_empty(), "[dansk] every Academy text is in Danish with its keys filled in (%s)" % [untranslated])
	t.check(Academy.search("anker").has("anchor"), "[dansk] searching in Danish: \"anker\" finds the anchoring page")
	SettingsManager.set_language(&"en")


func _test_settings() -> void:
	SettingsManager.set_academy({"first_voyage": "active", "step": 3, "seen": ["bite"]})
	SettingsManager.set_tips_enabled(false)
	SettingsManager.save()
	SettingsManager.set_academy({"first_voyage": "nonsense", "step": -4, "seen": "x"})
	t.check(Academy.first_voyage_state() == Academy.NEVER_OFFERED and Academy.current_step() == 0, "[settings] odd progress is cleaned")
	SettingsManager.set_academy({"first_voyage": "active", "step": 3, "seen": ["bite"]})
	SettingsManager.set_tips_enabled(true)
	SettingsManager.load_settings()
	t.check(Academy.first_voyage_state() == Academy.ACTIVE and Academy.current_step() == 3 and Academy.is_tip_seen("bite"),
		"[settings] the progress is kept on this computer")
	SettingsManager.set_tips_enabled(false)
	SettingsManager.restore_defaults()
	t.check(SettingsManager.get_tips_enabled() and Academy.first_voyage_state() == Academy.ACTIVE,
		"[settings] Restore defaults turns tips back on but keeps the progress")
	SettingsManager.set_academy({})


# --- The offer --------------------------------------------------------------------------------------

func _test_offer() -> void:
	SettingsManager.set_academy({})
	app.start_new_game()
	await _settle()
	await t.wait_until(func() -> bool: return app.modals.get_top() is ConfirmDialog, 3.0)
	var dialog := app.modals.get_top() as ConfirmDialog
	t.check(dialog != null, "[offer] the first new game offers the First Voyage")
	if dialog == null:
		return
	await t.screenshot("i022_academy_offer")
	dialog.handle_back()
	await t.frames(3)
	t.check(app.modals.is_empty() and Academy.first_voyage_state() == Academy.SKIPPED, "[offer] Esc closes it: skipped, and remembered")
	app.start_new_game()
	await _settle()
	await t.frames(5)
	t.check(app.modals.is_empty(), "[offer] asked once only")
	t.check_eq(SaveManager.save_to_slot(3, GameSession.get_state_snapshot()), OK, "(setup) saved")
	SettingsManager.set_academy({})
	app.load_slot(3)
	await _settle()
	await t.frames(5)
	t.check(app.modals.is_empty() and Academy.first_voyage_state() == Academy.NEVER_OFFERED, "[offer] a game that is not new (loaded) is never interrupted by it")


# --- The First Voyage ---------------------------------------------------------------------------------

func _step() -> String:
	return String(Academy.steps()[mini(Academy.current_step(), Academy.steps().size() - 1)].id) \
		if Academy.first_voyage_state() == Academy.ACTIVE else Academy.first_voyage_state()


func _test_first_voyage() -> void:
	app.modals.clear()
	app._on_area_change_requested(&"interior", &"from_deck")
	await _settle()
	app.academy.begin_first_voyage()
	app.academy.update_card()
	var card: Control = app.academy.card
	t.check(card.visible and _step() == "walk" and app.academy.find_child("SkipButton", true, false).visible,
		"[first voyage] step 1 shows, always with Skip (%s)" % app.academy.find_child("Heading", true, false).text)
	await t.screenshot("i022_academy_first_voyage")
	var walk := InputEventAction.new()
	walk.action = &"move_up"
	walk.pressed = true
	app.academy._input(walk)
	app.academy.update_card()
	t.check(_step() == "wheel", "[first voyage] walking ticks off the first step")
	app.open_action_wheel()
	await t.frames(2)
	app.academy.update_card()
	t.check(_step() == "log" and not card.visible, "[first voyage] opening the wheel ticks it off; the card steps aside while it is open")
	app.modals.clear()
	app.toggle_captains_log()
	await t.frames(2)
	app.academy.update_card()
	app.modals.clear()
	await t.frames(2)
	app.academy.update_card()
	t.check(_step() == "deck" and card.visible, "[first voyage] the log, then the card is back")
	app._on_area_change_requested(&"exterior", &"start")
	await _settle()
	app.academy.update_card()
	t.check(_step() == "chart", "[first voyage] on deck")
	app.open_chart()
	await _settle()
	app.academy.update_card()
	t.check(_step() == "course" and card.visible, "[first voyage] the chart (the card shows there too)")
	await t.screenshot("i022_academy_chart_step")
	GameSession.plan_route_to(&"helsingor")
	app.academy.update_card()
	t.check(_step() == "sail", "[first voyage] a course planned")
	GameSession.depart()
	app.academy.update_card()
	t.check(_step() == "speed", "[first voyage] set sail")
	GameSession.set_time_scale(5)
	app.academy.update_card()
	t.check(Academy.first_voyage_state() == Academy.DONE and app.academy.shown_tip() == "!done", "[first voyage] time runs: done, with a farewell")
	GameSession.set_time_scale(1)
	app.academy.dismiss()
	t.check(not card.visible, "[first voyage] the farewell closes")
	# Skipping half-way.
	app.academy.begin_first_voyage()
	app.academy._queue.clear()
	app.academy.skip_first_voyage()
	app.academy.update_card()
	t.check(Academy.first_voyage_state() == Academy.SKIPPED and not card.visible, "[first voyage] Skip ends it at once")


# --- Tips ---------------------------------------------------------------------------------------------

func _test_tips() -> void:
	app.modals.clear()
	if not app.router.current_screen is BoatArea:
		app._show_current_boat_area()
	await _settle()
	SettingsManager.set_academy({"first_voyage": "done"})
	SettingsManager.set_tips_enabled(true)
	var guide: AcademyGuide = app.academy
	guide.dismiss()
	guide._queue.clear()
	guide._gap_left = 0.0
	guide.queue_tip("bite")
	app.open_pause_menu()
	await t.frames(2)
	guide.update_card()
	t.check(not guide.card.visible and guide.queued_tips().has("bite"), "[tips] never over an open window: it waits")
	app.modals.clear()
	app.hud.show_warning("Gale warning")
	guide.update_card()
	t.check(not guide.card.visible, "[tips] never over a warning")
	app.hud.hide_warning()
	guide.update_card()
	t.check(guide.card.visible and guide.shown_tip() == "bite" and Academy.is_tip_seen("bite") and guide.find_child("CloseButton", true, false).visible,
		"[tips] shown when the way is clear, with a close button (%s; voyage %s step %d, tip %s)" % [guide.find_child("Text", true, false).text,
		Academy.first_voyage_state(), Academy.current_step(), guide.shown_tip()])
	t.check((guide.find_child("Text", true, false) as Label).text.contains("R"), "[tips] with the real reel key")
	await t.screenshot("i022_academy_tip")
	(guide.find_child("CloseButton", true, false) as Button).pressed.emit()
	guide._queue.append("hat")
	guide.update_card()
	t.check(not guide.card.visible and guide.shown_tip().is_empty(), "[tips] closed, and the next tip waits a little (shown %s, queue %s)" % [
		guide.shown_tip(), guide.queued_tips()])
	guide.queue_tip("bite")
	t.check(not guide.queued_tips().has("bite"), "[tips] once only")
	SettingsManager.set_tips_enabled(false)
	guide.queue_tip("anchor")
	guide.update_card()
	t.check(not guide.card.visible, "[tips] off in Settings: none shown")
	SettingsManager.set_tips_enabled(true)
	guide._queue = ["anchor"] as Array[String]
	guide._gap_left = 0.0
	guide.update_card()
	(guide.find_child("MoreButton", true, false) as Button).pressed.emit()
	await t.frames(2)
	var book := app.modals.get_top() as HandbookMenu
	t.check(book != null and book.shown_page() == "anchor" and not guide.card.visible, "[tips] Read more opens its Handbook page")
	app.modals.clear()
	await t.frames(2)


# --- The Handbook -------------------------------------------------------------------------------------

func _test_handbook() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	app._unhandled_input(key)
	await t.frames(2)
	var book := app.modals.get_top() as HandbookMenu
	if not t.check(book != null and book.shown_page() == "controls", "[handbook] F1 opens it at Controls"):
		return
	book.search("fish")
	await t.frames(1)
	t.check(book.listed().has("fishing") and not book.listed().has("boats"), "[handbook] the search narrows the list (%s)" % [book.listed()])
	book.search("")
	book.show_page("postcards")
	await t.frames(1)
	t.check((book.find_child("PageText", true, false) as Label).text.contains("two hours"), "[handbook] the pastimes are in it")
	await t.screenshot("i022_handbook")
	app._unhandled_input(key)
	await t.frames(2)
	t.check(app.modals.is_empty(), "[handbook] F1 again closes it")
	app.open_pause_menu()
	await t.frames(2)
	var button := app.modals.get_top().find_child("HandbookButton", true, false) as Button
	if not t.check(button != null, "[handbook] the menu has Captain's Handbook"):
		return
	await t.click(button)
	await t.frames(2)
	book = app.modals.get_top() as HandbookMenu
	t.check(book != null, "[handbook] opened from the menu")
	await t.click(book.find_child("CloseButton", true, false))
	await t.frames(2)
	t.check(app.modals.get_top() is PauseMenu, "[handbook] Close goes back to the menu")
	app.modals.clear()
	await t.frames(2)
	app.open_pause_menu()
	await t.frames(2)
	app.modals.get_top().find_child("HandbookButton", true, false).pressed.emit()
	await t.frames(2)
	app.modals.get_top().find_child("FirstVoyageButton", true, false).pressed.emit()
	await t.frames(2)
	app.academy.update_card()
	t.check(app.modals.is_empty() and Academy.first_voyage_state() == Academy.ACTIVE and app.academy.card.visible,
		"[handbook] the First Voyage can be begun again from it")
	app.academy.skip_first_voyage()
