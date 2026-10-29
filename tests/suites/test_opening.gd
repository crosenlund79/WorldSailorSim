extends RefCounted
## I027 Tier 4, the opening story: New Game from the title screen shows it
## over the new game's cabin, with the game paused under it; it is the
## approved script, a page at a time, on three stills; Continue and a click
## turn the page, the last page ends it aboard with nothing else asked; Esc
## and Skip end it at once; loading a save never shows it; Danish has every
## page; and the Captain is an experienced sailor (the First Voyage offer
## speaks to the player, after the story).

const APP_SCENE := preload("res://src/app/app.tscn")

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	_test_words()
	OpeningStory.enabled = true
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _test_read_through()
	await _test_skip_and_load()
	OpeningStory.enabled = false
	app.queue_free()
	await t.frames(2)
	t.get_tree().paused = false
	GameSession.end_session()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _test_words() -> void:
	var pages := OpeningStory.pages()
	var english: Array = pages.map(func(p: Dictionary) -> String: return p.text)
	t.check(pages.size() == 8 and english[0] == "For years, the sea had been calling."
		and String(english.back()).ends_with("The next horizon is yours to discover."),
		"[opening] the approved script in %d pages, from the sea calling to the next horizon" % pages.size())
	t.check(String(english[2]).begins_with("You were no stranger to sailing.") and String(english[4]).contains("the experience to know"),
		"[opening] the Captain is an experienced sailor, not a beginner")
	var pictures := {}
	for page in pages:
		pictures[page.picture] = true
		t.check(ResourceLoader.exists(page.picture), "[opening] its picture exists: %s" % page.picture)
	t.check(pictures.size() == 3, "[opening] three stills: the desk at dusk, the boat at dawn, the open sea")
	SettingsManager.set_language(&"da")
	var danish: Array = OpeningStory.pages().map(func(p: Dictionary) -> String: return p.text)
	var translated := range(english.size()).all(func(i: int) -> bool: return not String(danish[i]).is_empty() and danish[i] != english[i])
	t.check(translated, "[opening] every page in Danish (%s …)" % String(danish[0]))
	SettingsManager.set_language(&"en")


func _start_from_title() -> OpeningStory:
	var menu := app.router.current_screen as MainMenu
	await t.click(menu.find_child("NewGameButton", true, false) as Button)
	await t.click(app.modals.get_top().find_child("StartButton", true, false) as Button)
	await _settle()
	return app.modals.get_top() as OpeningStory


func _test_read_through() -> void:
	var story := await _start_from_title()
	t.check(story != null and story.page_index == 0, "[opening] New Game opens with the story")
	t.check(GameSession.is_active() and app.router.current_screen is BoatArea
		and (app.router.current_screen as BoatArea).area_id == SessionState.AREA_INTERIOR,
		"[opening] the new game waits under it, in the cabin")
	t.check(t.get_tree().paused, "[opening] the game is paused while it is told")
	var time_before := GameSession.get_game_time()
	await t.screenshot("opening_01_desk")
	var continue_button := story.find_child("ContinueButton", true, false) as Button
	t.check(continue_button.has_focus(), "[opening] Continue has the keyboard (Enter or Space turns the page)")
	await t.click(continue_button)
	t.check(story.page_index == 1, "[opening] Continue turns the page")
	await t.click_at(story.get_global_rect().get_center())
	t.check(story.page_index == 2, "[opening] so does a click on the picture")
	while story.page_index < OpeningStory.pages().size() - 1:
		await t.click(continue_button)
		if story.page_index == 3:
			await t.frames(30)
			await t.screenshot("opening_02_harbour")
	await t.frames(40)
	await t.screenshot("opening_03_horizon")
	t.check(continue_button.text == "Begin" and (story.find_child("Logo", true, false) as Control).visible,
		"[opening] the last page shows the name and offers to begin")
	var ended := [false, true]
	story.finished.connect(func(skipped: bool) -> void:
		ended[0] = true
		ended[1] = skipped)
	await t.click(continue_button)
	await t.wait_until(func() -> bool: return app.modals.is_empty(), 3.0)
	await t.frames(2)
	t.check(ended[0] and not ended[1], "[opening] read to the end, it ends by itself")
	t.check(app.modals.is_empty() and not t.get_tree().paused and app.is_in_gameplay()
		and (app.router.current_screen as BoatArea).area_id == SessionState.AREA_INTERIOR,
		"[opening] it ends aboard, in the cabin, free to play: no contract, no quest")
	t.check(GameSession.get_game_time() - time_before < 60.0, "[opening] the game's clock stood still under it")
	await t.screenshot("opening_04_aboard")
	SaveManager.save_to_slot(2, GameSession.get_state_snapshot())


func _test_skip_and_load() -> void:
	app.show_main_menu()
	await _settle()
	var story := await _start_from_title()
	t.check(story != null, "[opening] a second New Game tells it again")
	var ended := [false, false]
	story.finished.connect(func(skipped: bool) -> void:
		ended[0] = true
		ended[1] = skipped)
	await t.press_action(&"pause")  # Esc
	await t.wait_until(func() -> bool: return app.modals.is_empty(), 3.0)
	t.check(ended[0] and ended[1] and app.is_in_gameplay() and not t.get_tree().paused, "[opening] Esc skips it, straight to the cabin")
	app.show_main_menu()
	await _settle()
	story = await _start_from_title()
	await t.click(story.find_child("SkipButton", true, false) as Button)
	await t.wait_until(func() -> bool: return app.modals.is_empty(), 3.0)
	t.check(app.modals.is_empty() and app.is_in_gameplay(), "[opening] so does Skip")
	# A saved game is never told the story again.
	app.load_slot(2)
	await _settle()
	await t.frames(10)
	t.check(app.is_in_gameplay() and not app.modals.get_top() is OpeningStory, "[opening] loading a save never shows it")
	app.show_main_menu()
	await _settle()
	var menu := app.router.current_screen as MainMenu
	await t.click(menu.find_child("ContinueButton", true, false) as Button)
	await _settle()
	await t.frames(10)
	t.check(app.is_in_gameplay() and not app.modals.get_top() is OpeningStory, "[opening] nor does Continue")
	SaveManager.delete_slot(2)
