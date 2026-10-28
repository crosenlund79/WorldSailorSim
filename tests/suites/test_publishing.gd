extends RefCounted
## Iteration 006, Checkpoint C: social-media income. Publishing a travel
## update turns all unpublished renown into euros at the configured rate in
## one transaction, keeps lifetime renown, never pays without renown, needs a
## harbour, survives save/load, and leaves remote work and the grocery store
## working. Then the dialogs in the real application.

const APP_SCENE := preload("res://src/app/app.tscn")
const HOUR := 3600.0

var t: Node
var app: Node
var published: Array = []


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	t.use_calm_wind()
	WeatherFixtures.clear()
	GameSession.travel_update_published.connect(_on_published)
	_test_nothing_to_publish()
	_test_publish()
	_test_at_sea()
	_test_rate()
	_test_persistence()
	_test_other_income()
	GameSession.travel_update_published.disconnect(_on_published)
	GameSession.end_session()

	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	app.start_new_game()
	await _settle()
	await _test_dialogs()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _on_published(info: Dictionary) -> void:
	published.append(info)


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _new_game() -> void:
	WeatherFixtures.use([])
	GameSession.start_new_session()
	published.clear()


func _sail_to(port: StringName) -> void:
	t.check_eq(GameSession.plan_route_to(port), "", "(setup) course to %s" % port)
	t.check_eq(GameSession.depart(), "", "(setup) underway to %s" % port)
	var guard := 60
	while GameSession.is_underway() and guard > 0:
		guard -= 1
		Simulation.advance(24.0 * HOUR, true)


## Lifetime renown = published + unpublished, always.
func _balanced() -> bool:
	var p := GameSession.get_objective_progress()
	return p.lifetime_renown == p.published_renown + p.unpublished_renown


func _test_nothing_to_publish() -> void:
	_new_game()
	var quote := GameSession.get_publish_quote()
	t.check(quote.renown == 0 and quote.euros == 0 and String(quote.error).contains("No unpublished renown"),
		"[publish] a new game has nothing to publish: %s" % quote.error)
	var result := GameSession.publish_travel_update()
	t.check(not String(result.error).is_empty() and GameSession.get_funds() == 10000 and published.is_empty(),
		"[publish] publishing with no renown pays nothing")


func _test_publish() -> void:
	_new_game()
	_sail_to(&"kiel")
	t.check_eq(GameSession.get_unpublished_renown(), 100, "(setup) 100 unpublished renown in Kiel")
	var quote := GameSession.get_publish_quote()
	t.check(quote.renown == 100 and quote.rate == 2 and quote.euros == 200 and quote.funds == 10000 and quote.funds_after == 10200
		and String(quote.error).is_empty(), "[publish] the quote: 100 renown × €2 = €200, funds €10,000 → €10,200")
	var result := GameSession.publish_travel_update()
	t.check(String(result.error).is_empty() and result.renown == 100 and result.euros == 200 and result.funds_after == 10200,
		"[publish] publishing pays €200 for 100 renown")
	t.check(GameSession.get_funds() == 10200 and GameSession.get_unpublished_renown() == 0 and GameSession.get_lifetime_renown() == 100,
		"[publish] funds €10,200, unpublished 0, lifetime renown still 100")
	var progress := GameSession.get_objective_progress()
	t.check(progress.publications == 1 and progress.published_renown == 100 and progress.published_euros == 200 and published.size() == 1 and _balanced(),
		"[publish] one publication recorded (100 renown, €200); lifetime = published + unpublished")
	var again := GameSession.publish_travel_update()
	t.check(not String(again.error).is_empty() and GameSession.get_funds() == 10200 and published.size() == 1,
		"[publish] publishing again without new renown pays nothing")
	# New renown, published later: only the new part is paid.
	_sail_to(&"gothenburg")
	var earned := GameSession.get_unpublished_renown()
	t.check(earned > 0 and GameSession.get_lifetime_renown() == 100 + earned, "(setup) %d new renown in Gothenburg" % earned)
	var funds := GameSession.get_funds()
	GameSession.publish_travel_update()
	t.check(GameSession.get_funds() == funds + 2 * earned and GameSession.get_unpublished_renown() == 0 and GameSession.get_lifetime_renown() == 100 + earned
		and _balanced(), "[publish] the second update pays only the new %d renown (€%d); lifetime keeps growing" % [earned, 2 * earned])


func _test_at_sea() -> void:
	_new_game()
	_sail_to(&"kiel")
	GameSession.plan_route_to(&"copenhagen")
	GameSession.depart()
	Simulation.advance(2.0 * HOUR)
	var quote := GameSession.get_publish_quote()
	var result := GameSession.publish_travel_update()
	t.check(String(quote.error).contains("moor in a harbour") and not String(result.error).is_empty()
		and GameSession.get_funds() == 10000 and GameSession.get_unpublished_renown() == 100,
		"[publish] at sea nothing is published (no money, renown kept)")


func _test_rate() -> void:
	_new_game()
	_sail_to(&"kiel")
	var catalog := ObjectiveCatalog.get_default()
	var rate := catalog.euros_per_renown
	catalog.euros_per_renown = 3
	t.check_eq(GameSession.get_publish_quote().euros, 300, "[publish] the rate is configurable (at €3: €300)")
	GameSession.publish_travel_update()
	t.check_eq(GameSession.get_funds(), 10300, "[publish] and paid at that rate")
	catalog.euros_per_renown = rate


func _test_persistence() -> void:
	_new_game()
	_sail_to(&"kiel")
	GameSession.publish_travel_update()
	SaveManager.save_to_slot(2, GameSession.get_state_snapshot())
	var loaded := SaveManager.load_from_slot(2)
	t.check(loaded.is_ok(), "[publish] the save loads (%s)" % loaded.error)
	if loaded.is_ok():
		GameSession.replace_state(loaded.state)
		var progress := GameSession.get_objective_progress()
		t.check(GameSession.get_funds() == 10200 and progress.unpublished_renown == 0 and progress.lifetime_renown == 100
			and progress.publications == 1 and progress.published_euros == 200, "[publish] after loading: €10,200, nothing unpublished, the publication kept")
		var result := GameSession.publish_travel_update()
		t.check(not String(result.error).is_empty() and GameSession.get_funds() == 10200, "[publish] loading does not make the renown publishable again")
	SaveManager.delete_slot(2)


func _test_other_income() -> void:
	_new_game()
	_sail_to(&"kiel")
	GameSession.publish_travel_update()
	var work := Simulation.work(2)
	t.check(work.earned == 50 and GameSession.get_funds() == 10250, "[publish] remote work still pays (€50 for 2 h)")
	var price := GameSession.get_provisions_price()
	t.check(price > 0 and GameSession.buy_provisions() == "" and GameSession.get_funds() == 10250 - price,
		"[publish] the grocery store still sells provisions (€%d)" % price)
	t.check(GameSession.get_objective_progress().lifetime_renown == 100, "[publish] working and shopping do not change renown")


# --- Dialogs ---------------------------------------------------------------------------

func _test_dialogs() -> void:
	WeatherFixtures.use([])
	# No renown yet: the buttons say so.
	var log := app.open_captains_log() as CaptainsLogMenu
	await t.frames(3)
	var button: Button = log.find_child("PublishButton", true, false)
	t.check(button != null and button.disabled and (log.find_child("PublishHint", true, false) as Label).text.contains("No unpublished renown"),
		"[publish ui] with no renown the log's publish button is disabled and explains why")
	app.modals.clear()
	await t.frames(2)
	_sail_to(&"kiel")
	await _settle()
	for panel in app.toasts.get_children():
		app.toasts.remove_child(panel)
		panel.queue_free()
	log = app.open_captains_log() as CaptainsLogMenu
	await t.frames(3)
	button = log.find_child("PublishButton", true, false)
	t.check(not button.disabled and button.text == "Publish travel update (€200)…", "[publish ui] in harbour with 100 renown: '%s'" % button.text)
	button.pressed.emit()
	await t.frames(3)
	var dialog := app.modals.get_top() as PublishMenu
	t.check(dialog != null, "[publish ui] the button opens the confirmation")
	if dialog == null:
		return
	t.check((dialog.find_child("Renown", true, false) as Label).text.contains("Unpublished renown: 100")
		and (dialog.find_child("Earnings", true, false) as Label).text == "100 renown × €2 = €200"
		and (dialog.find_child("Funds", true, false) as Label).text == "Funds €10,000 → €10,200"
		and dialog.get_publish_button().text == "Publish for €200",
		"[publish ui] it shows renown, rate, earnings and funds before and after")
	await t.screenshot("112_publish_travel_update")
	# Cancel changes nothing.
	(dialog.find_child("CancelButton", true, false) as Button).pressed.emit()
	await t.frames(2)
	t.check(GameSession.get_funds() == 10000 and GameSession.get_unpublished_renown() == 100 and app.modals.get_top() is CaptainsLogMenu,
		"[publish ui] Cancel: nothing changes, back to the log")
	(app.modals.get_top().find_child("PublishButton", true, false) as Button).pressed.emit()
	await t.frames(2)
	(app.modals.get_top() as PublishMenu).get_publish_button().pressed.emit()
	await t.frames(3)
	t.check(app.modals.is_empty() and GameSession.get_funds() == 10200 and GameSession.get_unpublished_renown() == 0,
		"[publish ui] confirming publishes: €10,200, nothing unpublished")
	t.check(Array(app.toasts.get_messages()).has("Travel update published: 100 renown earned you €200. Funds: €10,200."),
		"[publish ui] the income is reported")
	log = app.open_captains_log() as CaptainsLogMenu
	await t.frames(3)
	t.check((log.find_child("RenownValue", true, false) as Label).text == "100  (0 unpublished)"
		and (log.find_child("PublishButton", true, false) as Button).disabled, "[publish ui] the log: lifetime 100, 0 unpublished, nothing to publish")
	await t.screenshot("113_log_after_publishing")
	app.modals.clear()
	await t.frames(2)
	# The work station (on the laptop since I024) offers it too.
	var work: WorkMenu = app.open_work_menu()
	await t.frames(3)
	var work_publish: Button = work.find_child("PublishButton", true, false) if work else null
	t.check(work_publish != null and work_publish.disabled, "[publish ui] the work dialog has 'Publish travel update…' (disabled: nothing to publish)")
	app.modals.clear()
	await t.frames(2)
