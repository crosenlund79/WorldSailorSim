class_name FishingMenu
extends SimplePanel
## The fishing rod (Iteration 13; Fishing 2.0 in Iteration 18). Three faces:
##   - the rod: where you are fishing, how one fishes here (from a still boat,
##     or trolling), the lure, the line out or in, waiting for a bite, which
##     catches to keep (rarity and size), what happens to bites in fast time,
##     and the cool box (each fish with its picture; release or sell);
##   - the reel-in, when something is on: the catch revealed (its picture,
##     name and rarity) and the timing dial (ReelTiming): press E or Space, or
##     click the dial, as the needle passes through the green arc;
##   - the catch: the fish again, its weight and specimen grade, and whether
##     it was kept or went back (and why).
## GameSession does every change; the App spends waiting time (wait_requested).

signal wait_requested(minutes: float)

## Waiting for a bite takes at most this long (game minutes).
const WAIT_MINUTES := 60.0
const RARITY_CHOICES := [["common", "Every fish"], ["uncommon", "Uncommon or rarer"], ["rare", "Rare or rarer"], ["very_rare", "Very rare only"]]
const GRADE_CHOICES := [[&"", "Any size"], [&"bronze", "Bronze or better"], [&"silver", "Silver or better"], [&"gold", "Gold only"]]
const POSTURE_CHOICES := [[FishingState.PASSAGE_ALL, "Stop for every bite"], [FishingState.PASSAGE_KEEPERS, "Stop only for fish worth keeping"]]

var _reel: ReelTiming
var _reel_bite := {}
var _reel_done := false
var _rod_box: VBoxContainer
var _reel_box: VBoxContainer
var _result_box: VBoxContainer
var _info: Label
var _lure: OptionButton
var _line_button: Button
var _wait_button: Button
var _keep_rarity: OptionButton
var _keep_grade: OptionButton
var _keep_text: Label
var _posture: OptionButton
var _hold_box: VBoxContainer
var _reel_title: Label
var _reel_name: Label
var _reel_badge: CatchBadge
var _reel_portrait: FishPortrait
var _dial: ReelDial
var _reel_feedback: Label
var _result_portrait: FishPortrait
var _result_name: Label
var _result_badge: CatchBadge
var _result_text: Label
var _release_button: Button
var _back_button: Button
var _close_button: Button
var _last_result := {}


func _ready() -> void:
	_build("Fishing rod", 780.0)
	_build_rod()
	_build_reel()
	_build_result()
	_close_button = _button("CloseButton", "Close", handle_back)
	GameSession.fishing_changed.connect(refresh)
	GameSession.fish_bite.connect(func(_bite: Dictionary) -> void: _start_reel_if_bite())
	refresh()
	_start_reel_if_bite()


func _build_rod() -> void:
	_rod_box = VBoxContainer.new()
	_rod_box.name = "Rod"
	_rod_box.add_theme_constant_override(&"separation", 10)
	_box.add_child(_rod_box)
	_info = Label.new()
	_info.name = "Info"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(700, 0)
	_rod_box.add_child(_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_rod_box.add_child(row)
	_lure = OptionButton.new()
	_lure.name = "Lure"
	_lure.custom_minimum_size = Vector2(260, 0)
	_lure.item_selected.connect(_on_lure_selected)
	row.add_child(_lure)
	_line_button = Button.new()
	_line_button.name = "LineButton"
	_line_button.custom_minimum_size = Vector2(170, 0)
	_line_button.pressed.connect(_on_line)
	row.add_child(_line_button)
	_wait_button = Button.new()
	_wait_button.name = "WaitButton"
	_wait_button.text = "Wait for a bite"
	_wait_button.tooltip_text = "Let time pass at the rod until a fish bites (at most an hour)."
	_wait_button.pressed.connect(func() -> void: wait_requested.emit(WAIT_MINUTES))
	row.add_child(_wait_button)
	# Keep preferences.
	var keep_row := HBoxContainer.new()
	keep_row.name = "KeepRow"
	keep_row.add_theme_constant_override(&"separation", 12)
	_rod_box.add_child(keep_row)
	var keep_label := Label.new()
	keep_label.text = "Keep:"
	keep_label.custom_minimum_size = Vector2(110, 0)
	keep_row.add_child(keep_label)
	_keep_rarity = _option("KeepRarity", RARITY_CHOICES, keep_row, func(i: int) -> void:
		GameSession.set_keep_preferences(RARITY_CHOICES[i][0], GameSession.get_fishing().keep_min_grade))
	_keep_grade = _option("KeepGrade", GRADE_CHOICES, keep_row, func(i: int) -> void:
		GameSession.set_keep_preferences(GameSession.get_fishing().keep_min_rarity, GRADE_CHOICES[i][0]))
	_keep_text = Label.new()
	_keep_text.name = "KeepText"
	_keep_text.theme_type_variation = &"MutedLabel"
	_keep_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keep_text.custom_minimum_size = Vector2(700, 0)
	_rod_box.add_child(_keep_text)
	var posture_row := HBoxContainer.new()
	posture_row.add_theme_constant_override(&"separation", 12)
	_rod_box.add_child(posture_row)
	var posture_label := Label.new()
	posture_label.text = "In fast time:"
	posture_label.custom_minimum_size = Vector2(110, 0)
	posture_row.add_child(posture_label)
	_posture = _option("Posture", POSTURE_CHOICES, posture_row, func(i: int) -> void:
		GameSession.set_passage_posture(POSTURE_CHOICES[i][0]))
	_posture.tooltip_text = "During Long Passage or at 20x: be stopped for every bite, or only when a fish of a rarity you keep bites (the others swim off; nothing is caught without you)."
	var hold_title := Label.new()
	hold_title.text = "Cool box"
	hold_title.theme_type_variation = &"MutedLabel"
	_rod_box.add_child(hold_title)
	_hold_box = VBoxContainer.new()
	_hold_box.name = "Hold"
	_hold_box.add_theme_constant_override(&"separation", 4)
	_rod_box.add_child(_hold_box)


func _option(node_name: String, choices: Array, parent: Node, on_select: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size = Vector2(250, 0)
	for choice: Array in choices:
		option.add_item(String(choice[1]))
	option.item_selected.connect(on_select)
	parent.add_child(option)
	return option


func _build_reel() -> void:
	_reel_box = VBoxContainer.new()
	_reel_box.name = "Reel"
	_reel_box.add_theme_constant_override(&"separation", 8)
	_reel_box.visible = false
	_box.add_child(_reel_box)
	_reel_title = Label.new()
	_reel_title.name = "ReelTitle"
	_reel_title.theme_type_variation = &"HeaderLabel"
	_reel_box.add_child(_reel_title)
	var who := HBoxContainer.new()
	who.add_theme_constant_override(&"separation", 14)
	_reel_box.add_child(who)
	_reel_name = Label.new()
	_reel_name.name = "ReelName"
	_reel_name.add_theme_font_size_override(&"font_size", 26)
	who.add_child(_reel_name)
	_reel_badge = CatchBadge.new()
	_reel_badge.name = "ReelBadge"
	who.add_child(_reel_badge)
	var stage := HBoxContainer.new()
	stage.add_theme_constant_override(&"separation", 16)
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	_reel_box.add_child(stage)
	_reel_portrait = FishPortrait.new()
	_reel_portrait.name = "ReelPortrait"
	_reel_portrait.custom_minimum_size = Vector2(420, 230)
	stage.add_child(_reel_portrait)
	_dial = ReelDial.new()
	_dial.name = "Dial"
	_dial.pressed.connect(press_reel)
	stage.add_child(_dial)
	_reel_feedback = Label.new()
	_reel_feedback.name = "ReelFeedback"
	_reel_feedback.theme_type_variation = &"HeaderLabel"
	_reel_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reel_box.add_child(_reel_feedback)
	var hint := Label.new()
	hint.name = "ReelHint"
	hint.text = "Press E or Space (or click the dial) as the needle passes the green arc; the gold middle is Perfect. Three misses and it gets away. Esc lets it go."
	hint.theme_type_variation = &"MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(700, 0)
	_reel_box.add_child(hint)


func _build_result() -> void:
	_result_box = VBoxContainer.new()
	_result_box.name = "Result"
	_result_box.add_theme_constant_override(&"separation", 8)
	_result_box.visible = false
	_box.add_child(_result_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 18)
	_result_box.add_child(top)
	_result_portrait = FishPortrait.new()
	_result_portrait.name = "ResultPortrait"
	_result_portrait.custom_minimum_size = Vector2(380, 200)
	top.add_child(_result_portrait)
	var words := VBoxContainer.new()
	words.add_theme_constant_override(&"separation", 8)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(words)
	_result_name = Label.new()
	_result_name.name = "ResultName"
	_result_name.add_theme_font_size_override(&"font_size", 28)
	words.add_child(_result_name)
	_result_badge = CatchBadge.new()
	_result_badge.name = "ResultBadge"
	words.add_child(_result_badge)
	_result_text = Label.new()
	_result_text.name = "ResultText"
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_text.custom_minimum_size = Vector2(320, 0)
	words.add_child(_result_text)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 12)
	_result_box.add_child(actions)
	_release_button = Button.new()
	_release_button.name = "ReleaseCatch"
	_release_button.text = "Release it"
	_release_button.tooltip_text = "Put it back in the sea (it leaves the cool box and the trophy board)."
	_release_button.pressed.connect(_on_release_last)
	actions.add_child(_release_button)
	_back_button = Button.new()
	_back_button.name = "BackToRod"
	_back_button.text = "Back to the rod"
	_back_button.pressed.connect(_show_face.bind(&"rod"))
	actions.add_child(_back_button)


func _show_face(face: StringName) -> void:
	_rod_box.visible = face == &"rod"
	_reel_box.visible = face == &"reel"
	_result_box.visible = face == &"result"
	_close_button.text = "Let it go" if face == &"reel" else "Close"
	# Large portraits animate only while they are shown.
	_reel_portrait.visible = face == &"reel"
	_result_portrait.visible = face == &"result"
	if face == &"rod":
		refresh()
	focus_default()


func refresh() -> void:
	if not is_inside_tree():
		return
	var fishing := GameSession.get_fishing()
	var catalog := FishingCatalog.get_default()
	var mode := GameSession.get_fishing_mode()
	var geo := GameSession.get_vessel_position()
	var region := FishingCatalog.region_at(geo).replace("_", " ")
	var how := Loc.format("Trolling behind the boat at %.1f kn", GameSession.get_vessel_speed_kn()) if mode == FishingState.MODE_TROLLING \
		else (Loc.t("Rod fishing from the anchored boat") if GameSession.is_anchored() else Loc.t("Rod fishing from the moored boat"))
	var fit := catalog.suitability(geo, mode, fishing.lure)
	var fit_text := Loc.t("promising for this lure") if fit >= 1.0 else (Loc.t("fair for this lure") if fit >= 0.7 else Loc.t("not ideal for this lure"))
	_info.text = Loc.t("%s. Waters: %s%s, %s.%s") % [how, region.capitalize(), Loc.t(" (near the coast)") if catalog.is_coastal(geo) else "",
		fit_text, Loc.t("  Line out.") if fishing.line_out else ""]
	_lure.clear()
	for i in catalog.lures.size():
		var lure: Dictionary = catalog.lures[i]
		_lure.add_item("%s (%d)" % [Loc.t(String(lure.name)), fishing.get_lure_count(lure.id)])
		if lure.id == fishing.lure:
			_lure.select(i)
	_lure.disabled = fishing.line_out
	_line_button.text = "Reel in the line" if fishing.line_out else "Let the line out"
	_wait_button.disabled = not fishing.line_out
	_keep_rarity.select(maxi(FishingCatalog.rarity_index(fishing.keep_min_rarity), 0))
	_keep_grade.select(FishingCatalog.grade_rank(fishing.keep_min_grade))
	_keep_text.text = describe_keep(fishing)
	_posture.select(maxi(FishingState.PASSAGE_POSTURES.find(fishing.passage_posture), 0))
	for child in _hold_box.get_children():
		child.queue_free()
	if fishing.hold.is_empty():
		var empty := Label.new()
		empty.text = "Empty."
		_hold_box.add_child(empty)
	var selling := GameSession.has_facility(HarbourFacilities.GROCERY)
	for fish in fishing.hold:
		_hold_box.add_child(_hold_row(fish, catalog, selling))


## What the keep preferences mean, in words.
static func describe_keep(fishing: FishingState) -> String:
	var rarity := Loc.t("every fish") if fishing.keep_min_rarity == "common" else \
		(Loc.t("%s fish or rarer") % FishingCatalog.rarity_label(fishing.keep_min_rarity).to_lower() if fishing.keep_min_rarity != "very_rare" else Loc.t("very rare fish only"))
	var size := Loc.t("of any size") if fishing.keep_min_grade == FishingCatalog.GRADE_NONE else \
		(Loc.t("that are %s specimens or better") % FishingCatalog.grade_label(fishing.keep_min_grade) if fishing.keep_min_grade != FishingCatalog.GRADE_GOLD else Loc.t("that are Gold specimens"))
	return Loc.t("You keep %s %s; the rest go straight back (no cool box, no trophy). Sizes are graded by weight within each species, so even a common fish can be Gold. Sharks always swim free.") % [rarity, size]


func _hold_row(fish: Dictionary, catalog: FishingCatalog, selling: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var picture := TextureRect.new()
	picture.texture = FishArt.thumbnail(fish.species)
	picture.custom_minimum_size = Vector2(80, 40)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(picture)
	var label := Label.new()
	label.text = Loc.format("%s, %.1f kg", [catalog.get_species_name(fish.species), float(fish.kg)])
	label.custom_minimum_size = Vector2(210, 0)
	row.add_child(label)
	var badge := CatchBadge.new()
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(badge)
	badge.set_catch(catalog.rarity_of(fish.species), catalog.grade(fish.species, float(fish.kg)))
	var release := Button.new()
	release.text = "Release"
	release.pressed.connect(func() -> void:
		if GameSession.release_fish(int(fish.uid)):
			SessionLog.write("fishing_fish", {"action": "released", "species": fish.species, "kg": fish.kg}))
	row.add_child(release)
	if selling:
		var sell := Button.new()
		sell.text = Loc.t("Sell (%s)") % GameSession.format_money(catalog.price(fish.species, float(fish.kg)))
		sell.pressed.connect(func() -> void:
			var result := GameSession.sell_fish(int(fish.uid))
			SessionLog.write("fishing_fish", {"action": "sold", "species": fish.species, "kg": fish.kg, "price": result.price, "error": result.error})
			notify(Loc.t("Sold for %s.") % GameSession.format_money(int(result.price)) if result.error == "" else String(result.error)))
		row.add_child(sell)
	return row


func focus_default() -> void:
	if _result_box.visible:
		_back_button.grab_focus()
	elif _rod_box.visible:
		_line_button.grab_focus()
	else:
		var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if focused:
			focused.release_focus()


func _on_lure_selected(index: int) -> void:
	GameSession.select_lure(FishingCatalog.get_default().lures[index].id)


func _on_line() -> void:
	var out := not GameSession.is_line_out()
	var error := GameSession.set_line(out, GameSession.get_fishing().lure)
	if error != "":
		notify(error)
	else:
		SessionLog.write("fishing_line", {"out": out, "mode": String(GameSession.get_fishing_mode()), "lure": GameSession.get_fishing().lure})
		AudioManager.play_sfx(FishingSounds.cast() if out else FishingSounds.reel(), FishingSounds.DB)


# --- The reel-in ----------------------------------------------------------------------

func _start_reel_if_bite() -> void:
	var bite := GameSession.get_pending_bite()
	if bite.is_empty() or (_reel != null and not _reel_done):
		return
	var catalog := FishingCatalog.get_default()
	var profile := catalog.reel_profile(bite.species)
	_reel = ReelTiming.new(int(profile.checks), float(profile.arc_deg), hash("%s|%s" % [bite.species, bite.time]))
	_reel_bite = bite
	_reel_done = false
	_dial.timing = _reel
	var kind := catalog.kind_of(bite.species)
	_reel_title.text = "Something heavy is on the line!" if kind == FishingCatalog.KIND_SHARK else \
		(Loc.t("Something's caught on the line...") if kind == FishingCatalog.KIND_JUNK else Loc.t("Fish on!"))
	_reel_name.text = catalog.get_species_name(bite.species)
	_reel_badge.set_catch(catalog.rarity_of(bite.species), &"", false)
	_reel_portrait.set_species(bite.species)
	_reel_feedback.text = Loc.n("%d good turn to land it.", "%d good turns to land it.", _reel.checks_needed) % _reel.checks_needed
	_show_face(&"reel")
	SessionLog.write("fishing_reel", {"species": bite.species, "kg": bite.kg, "checks": _reel.checks_needed, "arc": _reel.arc_deg})


func is_reeling() -> bool:
	return _reel != null and not _reel_done


func get_reel() -> ReelTiming:
	return _reel


func get_reel_portrait() -> FishPortrait:
	return _reel_portrait


func get_result_portrait() -> FishPortrait:
	return _result_portrait


func _input(event: InputEvent) -> void:
	if not is_reeling() or not is_inside_tree() or (stack and stack.get_top() != self):
		return
	if event.is_echo():
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		press_reel()
		get_viewport().set_input_as_handled()


## The captain presses (key, button or a click on the dial).
func press_reel() -> StringName:
	if not is_reeling():
		return ReelTiming.PRESS_NONE
	var outcome := _reel.press()
	if outcome == ReelTiming.PRESS_NONE:
		return outcome
	_dial.flash(outcome)
	match outcome:
		ReelTiming.PRESS_PERFECT:
			_reel_feedback.text = "Perfect!"
			AudioManager.play_sfx(FishingSounds.reel(), FishingSounds.DB)
		ReelTiming.PRESS_HIT:
			_reel_feedback.text = "Good!"
			AudioManager.play_sfx(FishingSounds.reel(), FishingSounds.DB)
		ReelTiming.PRESS_MISS:
			var left := _reel.get_line_control()
			_reel_feedback.text = Loc.n("Missed - the line slips. %d grip left.", "Missed - the line slips. %d grips left.", left) % left if left > 0 else Loc.t("Missed...")
	if not _reel.is_over() and outcome != ReelTiming.PRESS_MISS:
		var left := _reel.checks_needed - _reel.hits
		_reel_feedback.text += Loc.t("  %d more to go.") % left
	if _reel.is_over():
		_finish_reel()
	return outcome


func _process(delta: float) -> void:
	# Under another window (anything opened on top) the needle waits, as the
	# presses do.
	if not is_reeling() or (stack and stack.get_top() != self):
		return
	step_reel(delta)


## Advances the needle (every frame; tests call it directly).
func step_reel(delta: float) -> void:
	if not is_reeling():
		return
	_reel.step(delta)
	if _reel.is_over():
		_finish_reel()


## Esc or "Let it go" while reeling: the catch swims off.
func let_go() -> void:
	if not is_reeling():
		return
	_reel.result = ReelTiming.RESULT_ESCAPED
	_finish_reel()


func _finish_reel() -> void:
	if _reel_done:
		return
	_reel_done = true
	var landed := _reel.result == ReelTiming.RESULT_LANDED
	var result := GameSession.finish_fight(landed, false, _reel.perfects)
	_last_result = result
	SessionLog.write("fishing_result", {"result": String(_reel.result), "species": _reel_bite.get("species", ""),
		"kg": result.fish.get("kg", 0.0), "kept": result.kept, "released": result.released_reason, "perfects": _reel.perfects,
		"misses": _reel.misses})
	AudioManager.play_sfx(FishingSounds.splash() if landed else FishingSounds.snap(), FishingSounds.DB)
	if not landed:
		notify(String(result.text) if result.text != "" else Loc.t("It got away."))
		_show_face(&"rod")
		return
	_show_result(result)


func _show_result(result: Dictionary) -> void:
	var catalog := FishingCatalog.get_default()
	var species: String = result.fish.get("species", "")
	_result_portrait.set_species(species)
	_result_name.text = catalog.get_species_name(species)
	var junk := String(result.kind) == String(FishingCatalog.KIND_JUNK)
	_result_badge.visible = not junk
	_result_badge.set_catch(String(result.rarity), StringName(result.grade))
	var lines: Array[String] = []
	if junk:
		lines.append(String(result.text))
		lines.append(Loc.t("Not a fish, and worth nothing. It goes in the bin."))
	else:
		lines.append(Loc.format("%.1f kg  ·  %s specimen", [float(result.fish.kg), FishingCatalog.grade_label(StringName(result.grade))]))
		if _reel.perfects > 0:
			lines.append(Loc.n("%d Perfect hit: a little heavier for your care.", "%d Perfect hits: a little heavier for your care.", _reel.perfects) % _reel.perfects)
		match String(result.released_reason):
			"shark":
				lines.append(Loc.t("That's quite a catch. Better let this one swim free."))
			"preferences":
				lines.append(Loc.t("Not one to keep by your preferences: back it goes."))
			"cool_box_full":
				lines.append(Loc.t("The cool box is full, so it goes back."))
			_:
				lines.append(Loc.t("Into the cool box: cook it in the galley, release it, or sell it in harbour."))
		if result.new_species:
			lines.append(Loc.t("A new species for your log!"))
		elif result.personal_best:
			lines.append(Loc.t("A new personal best!"))
		if result.exceptional:
			lines.append(Loc.t("An exceptional fish."))
	_result_text.text = "\n".join(lines)
	_release_button.visible = bool(result.kept)
	_show_face(&"result")


func _on_release_last() -> void:
	var uid := int(_last_result.get("fish", {}).get("uid", -1))
	if uid >= 0 and GameSession.release_fish(uid):
		SessionLog.write("fishing_fish", {"action": "released", "species": _last_result.fish.species, "kg": _last_result.fish.kg})
		_last_result.kept = false
		_release_button.visible = false
		_result_text.text += Loc.t("\nYou let it go.")


func handle_back() -> void:
	if is_reeling():
		let_go()
		return
	close()


## After waiting at the rod (App): nothing yet, or why the wait ended (a bite
## starts the reel-in by itself).
func show_wait_result(result: Simulation.AdvanceResult) -> void:
	if result.bite or not is_inside_tree():
		return
	var waited := Simulation.format_duration(result.elapsed_seconds)
	match result.stopped_by:
		Simulation.STOP_WARNING:
			notify(Loc.t("After %s a weather warning came in. Check the conditions.") % waited)
		Simulation.STOP_ANCHOR:
			notify(Loc.t("After %s the anchor alarm went: %s.") % [waited, AnchorSite.holding_text(GameSession.get_anchor().holding).to_lower()])
		Simulation.STOP_ARRIVAL:
			notify(Loc.t("After %s the boat arrived.") % waited)
		_:
			notify(Loc.t("After %s at the rod: nothing yet.") % waited)
	refresh()


func get_last_result() -> Dictionary:
	return _last_result


func get_outcome_text() -> String:
	return _result_text.text if _result_box.visible else ""


func get_info_text() -> String:
	return _info.text
