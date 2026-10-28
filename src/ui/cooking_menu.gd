class_name CookingMenu
extends SimplePanel
## The galley (Iteration 13): choose a dish, see what it takes (fish from the
## cool box, groceries from the stores) and what it gives, then cook it. The
## pan sizzles and steams for a moment, the cooking time passes (App) and the
## result says what the meal did. GameSession.cook() is the one transaction;
## nothing changes when a dish is refused.
##
## The rule for the stove is simple: in harbour and at a holding anchor
## always; underway only in moderate conditions (GameSession.cooking_refusal).
##
## Revision 0.102b: **Make coffee**, a small ritual beside the dishes. The pot
## steams for a moment, a few minutes pass (App) and a warm line says how it
## was; GameSession.make_coffee() is the transaction.

## The App spends the cooking time (game minutes) when a dish is done.
signal cooked(result: Dictionary)
## Coffee is made: the App spends its few minutes.
signal coffee_made(result: Dictionary)

## Real seconds the little cooking animation runs before the meal is served.
const COOK_SECONDS := 1.6

const Instrument := preload("res://src/ui/instrument_draw.gd")

var _recipes: ItemList
var _detail: Label
var _rule: Label
var _cook_button: Button
var _coffee_button: Button
## Brewing (real seconds left), and whether the stove shows the pot.
var _brewing := 0.0
var _pot := false
var _outcome: Label
var _pan: Control
var _cooking := 0.0
var _time := 0.0
var _last_result := {}
## Until when (this panel's clock) the served dish still steams.
var _steam_until := -1.0


func _ready() -> void:
	_build("Galley", 700.0)
	_rule = _label("Rule", "", &"MutedLabel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 16)
	_box.add_child(row)
	_recipes = ItemList.new()
	_recipes.name = "Recipes"
	_recipes.custom_minimum_size = Vector2(300, 210)
	_recipes.item_selected.connect(_on_recipe_selected)
	row.add_child(_recipes)
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_pan = Control.new()
	_pan.name = "Pan"
	_pan.custom_minimum_size = Vector2(320, 90)
	_pan.draw.connect(_draw_pan)
	right.add_child(_pan)
	_detail = Label.new()
	_detail.name = "Detail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(320, 0)
	right.add_child(_detail)
	_outcome = _label("Outcome", "", &"HeaderLabel")
	_outcome.visible = false
	_button("CloseButton", "Close", close)
	_coffee_button = _button("CoffeeButton", "Make coffee", _on_coffee, 170.0)
	_cook_button = _button("CookButton", "Cook", _on_cook, 200.0)
	for recipe in Recipes.LIST:
		_recipes.add_item(String(recipe.name))
	_recipes.select(_best_index())
	refresh()


## The first dish that can be cooked now (fish dishes first when there is fish).
func _best_index() -> int:
	var order := [2, 3, 4, 0, 1] if not GameSession.get_fishing().hold.is_empty() else [0, 1, 2, 3, 4]
	for i: int in order:
		if GameSession.recipe_refusal(Recipes.LIST[i].id) == "":
			return i
	return 0


func _on_recipe_selected(_index: int) -> void:
	if _brewing <= 0.0:
		_pot = false  # back to the pan for a dish
	_refresh_detail()


func refresh() -> void:
	var refusal := GameSession.cooking_refusal()
	var fishing := GameSession.get_fishing()
	_rule.text = refusal if refusal != "" else Loc.t("Fish in the cool box: %d  ·  Food in the stores: %s") % [fishing.hold.size(),
		Provisions.format_days(GameSession.get_food_days())]
	UiTheme.tint(_rule, &"warning" if refusal != "" else &"")
	for i in Recipes.LIST.size():
		var ok := GameSession.recipe_refusal(Recipes.LIST[i].id) == ""
		_recipes.set_item_custom_fg_color(i, UiTheme.color(&"ink") if ok else UiTheme.color(&"disabled_text"))
	_refresh_detail()


func get_selected_recipe() -> Dictionary:
	var selected := _recipes.get_selected_items()
	return Recipes.LIST[selected[0]] if not selected.is_empty() else Recipes.LIST[0]


func select_recipe(id: String) -> void:
	for i in Recipes.LIST.size():
		if Recipes.LIST[i].id == id:
			_recipes.select(i)
	_refresh_detail()


func _refresh_detail() -> void:
	if _pot:
		# Coffee: no recipe to read, just the pot.
		_detail.text = Loc.t("A pot of coffee on the little stove.\n\nNeeds nothing special.\nTakes %d minutes.\nJust for the pleasure of it.") % int(GameSession.COFFEE_MINUTES)
		_cook_button.disabled = _cooking > 0.0 or _brewing > 0.0 or GameSession.recipe_refusal(get_selected_recipe().id) != "" \
			or GameSession.cooking_refusal() != ""
		_cook_button.text = Loc.t("Cook %s") % Loc.t(String(get_selected_recipe().name)).to_lower()
		_coffee_button.disabled = _brewing > 0.0 or GameSession.coffee_refusal() != ""
		return
	var recipe := get_selected_recipe()
	var needs := PackedStringArray()
	if int(recipe.fish) > 0:
		needs.append(Loc.t("%d fish from the cool box (the oldest first)") % int(recipe.fish))
	if float(recipe.groceries) > 0.0:
		needs.append(Loc.t("%s of groceries") % Provisions.format_days(float(recipe.groceries)))
	var gives := Loc.t("Well fed for %d hours: the stores last a little longer.") % roundi(float(recipe.well_fed_hours))
	if int(recipe.fish) > 0:
		gives = Loc.t("Turns the catch into food for the stores (up to %s). ") % Provisions.format_days(Recipes.MAX_FISH_DAYS) + gives
	var refusal := GameSession.recipe_refusal(recipe.id)
	_detail.text = Loc.t("%s\n\nNeeds: %s.\nTakes %d minutes.\n%s%s") % [Loc.t(String(recipe.text)), ", ".join(needs) if not needs.is_empty() else Loc.t("nothing special"),
		int(recipe.minutes), gives, ("\n\n" + refusal) if refusal != "" else ""]
	_cook_button.disabled = _cooking > 0.0 or _brewing > 0.0 or refusal != "" or GameSession.cooking_refusal() != ""
	_coffee_button.disabled = _cooking > 0.0 or _brewing > 0.0 or GameSession.coffee_refusal() != ""
	_coffee_button.tooltip_text = GameSession.coffee_refusal()
	_cook_button.text = Loc.t("Cook %s") % Loc.t(String(recipe.name)).to_lower()


func focus_default() -> void:
	_recipes.grab_focus()


func _on_cook() -> void:
	var recipe := get_selected_recipe()
	var refusal := GameSession.cooking_refusal()
	if refusal == "":
		refusal = GameSession.recipe_refusal(recipe.id)
	if refusal != "":
		SessionLog.write("cooking", {"recipe": recipe.id, "error": refusal})
		notify(refusal)
		return
	SessionLog.write("cooking_started", {"recipe": recipe.id})
	_pot = false
	_cooking = COOK_SECONDS
	_cook_button.disabled = true
	_outcome.visible = false
	AudioManager.play_sfx(FishingSounds.sizzle(), FishingSounds.DB)


func _process(delta: float) -> void:
	_time += delta
	if _cooking > 0.0:
		_cooking = maxf(_cooking - delta, 0.0)
		if _cooking <= 0.0:
			serve()
	if _brewing > 0.0:
		_brewing = maxf(_brewing - delta, 0.0)
		if _brewing <= 0.0:
			pour_coffee()
	_pan.queue_redraw()


func _on_coffee() -> void:
	var refusal := GameSession.coffee_refusal()
	if refusal != "":
		SessionLog.write("coffee", {"error": refusal})
		notify(refusal)
		return
	_pot = true
	_brewing = BREW_SECONDS
	_outcome.visible = false
	refresh()

## Real seconds the pot steams before the coffee is poured.
const BREW_SECONDS := 1.4


func is_brewing() -> bool:
	return _brewing > 0.0


## Pours the coffee now (the animation's end; tests call it directly).
func pour_coffee() -> Dictionary:
	_brewing = 0.0
	_pot = true
	var result := GameSession.make_coffee()
	_last_result = result
	SessionLog.write("coffee", {"error": result.error, "context": result.context, "award": not (result.award as Dictionary).is_empty()})
	if result.error != "":
		notify(result.error)
		refresh()
		return result
	coffee_made.emit(result)
	var lines := [Loc.t("Coffee is ready."), String(result.text)]
	if not (result.award as Dictionary).is_empty():
		lines.append(Loc.t("Written in the Captain's Log: %s.") % String(result.award.title))
	_outcome.text = "\n".join(lines)
	_outcome.visible = true
	_steam_until = _time + 8.0
	refresh()
	return result


func is_cooking() -> bool:
	return _cooking > 0.0


## Serves the dish now (the animation's end; tests call it directly).
func serve() -> Dictionary:
	_cooking = 0.0
	var recipe := get_selected_recipe()
	var result := GameSession.cook(recipe.id)
	_last_result = result
	SessionLog.write("cooking", {"recipe": recipe.id, "error": result.error, "minutes": result.minutes,
		"food_added": snappedf(float(result.food_added), 0.01), "fish": result.fish.size(), "evening": result.evening})
	if result.error != "":
		notify(result.error)
		refresh()
		return result
	cooked.emit(result)
	var lines := [Loc.t("%s is ready.") % String(recipe.name)]
	if float(result.food_added) > 0.0:
		lines.append(Loc.t("The catch adds %s of food to the stores.") % Provisions.format_days(float(result.food_added)))
	lines.append(Loc.t("Well fed until %s.") % Simulation.format_game_time(float(result.well_fed_until)))
	if result.evening:
		lines.append(Loc.t("A quiet evening at anchor. Fresh fish for supper."))
	_outcome.text = "\n".join(lines)
	_outcome.visible = true
	_steam_until = _time + 6.0
	refresh()
	return result


func get_last_result() -> Dictionary:
	return _last_result


func get_outcome_text() -> String:
	return _outcome.text if _outcome.visible else ""


## The pan on the stove: it sizzles while cooking and steams afterwards.
## A line pictogram (Real Horizon): white strokes on a sunken strip, gas
## flames in instrument cyan, steam as faint white.
func _draw_pan() -> void:
	_draw_stove()
	if _pot:
		_draw_pot()
		return
	var c := Vector2(_pan.size.x / 2.0, _pan.size.y - 26.0)
	var ink := UiTheme.color(&"ink")
	var flame := _cooking > 0.0
	if flame:
		_draw_flames(c, 5, -40.0, 20.0, 5.0)
	# The pan: a shallow outline, the food a quiet fill, a long handle.
	var food := UiTheme.color(&"ink_soft") if int(get_selected_recipe().fish) == 0 else UiTheme.color(&"ink")
	_pan.draw_rect(Rect2(c + Vector2(-44, -7), Vector2(88, 5)), Color(food, 0.45))
	_pan.draw_polyline(PackedVector2Array([c + Vector2(-56, -8), c + Vector2(-52, 10), c + Vector2(52, 10), c + Vector2(56, -8)]), ink, 2.0, true)
	_pan.draw_line(c + Vector2(56, -2), c + Vector2(110, -10), ink, 2.0, true)
	_pan.draw_circle(c + Vector2(104, -9), 2.0, UiTheme.color(&"accent"))
	var steam := 1.0 if flame else clampf((_steam_until - _time) / 2.0, 0.0, 1.0)
	if steam > 0.0:
		for k in 5:
			var phase := fmod(_time * 0.7 + k / 5.0, 1.0)
			var p := c + Vector2(-30 + k * 15 + 6.0 * sin(_time * 2.0 + k), -14 - phase * 46.0)
			_pan.draw_arc(p, 3.0 + phase * 6.0, 0.0, TAU, 16, Color(UiTheme.color(&"ink"), 0.35 * (1.0 - phase) * steam), 1.0, true)


## The cooktop: a sunken strip with a hairline edge and fine burner marks.
func _draw_stove() -> void:
	var c := Vector2(_pan.size.x / 2.0, _pan.size.y - 26.0)
	var top := Rect2(c + Vector2(-90, 14), Vector2(180, 10))
	_pan.draw_rect(top, UiTheme.color(&"surface_sunken"))
	_pan.draw_line(top.position, Vector2(top.end.x, top.position.y), UiTheme.color(&"border"), 1.0)
	for k in 9:
		var x := top.position.x + 10.0 + k * 20.0
		_pan.draw_line(Vector2(x, top.position.y + 3.0), Vector2(x, top.end.y - 3.0), Color(UiTheme.color(&"ink_soft"), 0.35), 1.0)


func _draw_flames(c: Vector2, count: int, first_x: float, step: float, half: float) -> void:
	var cyan := UiTheme.color(&"accent")
	for k in count:
		var x := first_x + k * step
		var h := 6.0 + 3.0 * sin(_time * 18.0 + k)
		_pan.draw_colored_polygon(PackedVector2Array([c + Vector2(x - half, 14), c + Vector2(x, 14 - h), c + Vector2(x + half, 14)]),
			Color(cyan, 0.85))


## The coffee pot on the stove (and a mug beside it once poured), steaming.
func _draw_pot() -> void:
	var c := Vector2(_pan.size.x / 2.0, _pan.size.y - 26.0)
	var ink := UiTheme.color(&"ink")
	var brewing := _brewing > 0.0
	if brewing:
		_draw_flames(c, 4, -46.0, 14.0, 4.0)
	# The pot: a tapered body, a lid knob, a spout and a handle.
	var pot := c + Vector2(-28, 0)
	var body := PackedVector2Array([pot + Vector2(-22, 12), pot + Vector2(22, 12), pot + Vector2(16, -30), pot + Vector2(-16, -30)])
	_pan.draw_colored_polygon(body, UiTheme.color(&"surface_raised"))
	Instrument.outline(_pan, body, ink, 2.0)
	_pan.draw_rect(Rect2(pot + Vector2(-18, -36), Vector2(36, 6)), ink, false, 1.5)
	_pan.draw_circle(pot + Vector2(0, -40), 3.0, ink)
	_pan.draw_line(pot + Vector2(18, -18), pot + Vector2(34, -30), ink, 2.0, true)
	_pan.draw_arc(pot + Vector2(-24, -10), 11.0, PI * 0.5, PI * 1.5, 10, ink, 2.0, true)
	_pan.draw_line(pot + Vector2(-18, -6), pot + Vector2(18, -6), UiTheme.color(&"accent"), 1.0, true)
	var poured := not brewing and _outcome.visible
	if poured:
		# A mug beside the pot.
		var mug := c + Vector2(44, 2)
		_pan.draw_rect(Rect2(mug + Vector2(-14, -16), Vector2(28, 28)), ink, false, 2.0)
		_pan.draw_rect(Rect2(mug + Vector2(-11, -12), Vector2(22, 4)), UiTheme.color(&"accent"))
		_pan.draw_arc(mug + Vector2(16, -2), 7.0, -PI * 0.5, PI * 0.5, 8, ink, 2.0, true)
	var steam := 1.0 if brewing else clampf((_steam_until - _time) / 2.0, 0.0, 1.0)
	if steam > 0.0:
		var from := (c + Vector2(44, -18)) if poured else (pot + Vector2(34, -32))
		for k in 4:
			var phase := fmod(_time * 0.6 + k / 4.0, 1.0)
			var p := from + Vector2(5.0 * sin(_time * 2.0 + k * 1.7), -phase * 40.0)
			_pan.draw_arc(p, 3.0 + phase * 5.0, 0.0, TAU, 16, Color(ink, 0.38 * (1.0 - phase) * steam), 1.0, true)
