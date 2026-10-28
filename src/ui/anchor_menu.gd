class_name AnchorMenu
extends SimplePanel
## The anchor at the windlass (Iteration 13).
##
## Not anchored: the anchorage here in the wind now (good / fair / poor /
## unsuitable, and why), the chain to let out (3, 5 or 7 times the depth) and
## "Drop anchor". Setting it is a short interaction: a marker swings across a
## bar and "Set it now" catches it; nearer the middle sets the anchor better.
## Anchored: how it is holding, more or less chain, setting it again, the
## alarm, and raising it to sail on.
##
## The Magic Anchor (0.105b), when aboard: "Magic Anchor" opens its
## deployment - the shared circular timing dial (MagicAnchorDeployment): good
## turns let it down, a miss costs a few game minutes, too many misses and it
## has not bitten (try again or cancel; the boat stays unanchored). Success
## anchors through GameSession like the normal anchor, with a short brass
## flourish.
##
## Depths are GAME ESTIMATES (see AnchorSite, DepthService); the panel says so. GameSession does every change; the App
## spends the time each job takes (`time_requested`).

signal time_requested(minutes: float)

## Game minutes for letting go and setting, adjusting, and weighing anchor.
const DROP_MINUTES := 15.0
const ADJUST_MINUTES := 10.0
const RAISE_MINUTES := 10.0
## How fast the setting marker swings (cycles per real second).
const SET_SPEED := 0.55
## How well the anchor holds, as theme roles (Captain's Chartroom) for the
## holding text: right by day and by night.
const HOLDING_ROLES := {AnchorState.HOLDING_WELL: &"success", AnchorState.HOLDING_FAIR: &"",
	AnchorState.HOLDING_POOR: &"caution", AnchorState.HOLDING_DRAGGING: &"warning"}

var _site: Label
var _holding: Label
var _scope: OptionButton
var _set_box: VBoxContainer
var _set_bar: Control
var _set_button: Button
var _drop: Button
var _reset: Button
var _ack: Button
var _raise: Button
var _limits: Label
var _magic: Button
var _magic_box: VBoxContainer
var _magic_dial: ReelDial
var _magic_feedback: Label
var _magic_retry: Button
var _magic_cancel: Button
var _deployment: MagicAnchorDeployment
## Seconds left of the brass flourish after a Magic Anchor bites.
var _flourish := 0.0
## The setting interaction: running, for dropping or re-setting.
var _setting := false
var _setting_for_drop := true
var _marker := 0.0
var _time := 0.0


func _ready() -> void:
	_build("Anchor", 700.0)
	_site = _label("Site", "")
	_holding = _label("Holding", "", &"HeaderLabel")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	_box.add_child(row)
	var chain := Label.new()
	chain.text = "Chain to let out"
	row.add_child(chain)
	_scope = OptionButton.new()
	_scope.name = "Scope"
	for scope in AnchorState.SCOPES:
		_scope.add_item(Loc.t("%d × the depth%s") % [scope, {3: Loc.t(" (short)"), 5: Loc.t(" (usual)"), 7: Loc.t(" (long, holds best)")}[scope]])
	_scope.select(1)
	_scope.item_selected.connect(_on_scope_selected)
	row.add_child(_scope)
	_set_box = VBoxContainer.new()
	_set_box.name = "Setting"
	_set_box.visible = false
	_box.add_child(_set_box)
	var hint := Label.new()
	hint.text = "Setting the anchor: back down gently. Press \"Set it now\" (or E) as the marker crosses the green middle."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(620, 0)
	_set_box.add_child(hint)
	_set_bar = Control.new()
	_set_bar.name = "SetBar"
	_set_bar.custom_minimum_size = Vector2(620, 30)
	_set_bar.draw.connect(_draw_set_bar)
	_set_box.add_child(_set_bar)
	_set_button = Button.new()
	_set_button.name = "SetButton"
	_set_button.text = "Set it now"
	_set_button.custom_minimum_size = Vector2(200, 40)
	_set_button.pressed.connect(func() -> void: catch_set())
	_set_box.add_child(_set_button)
	_build_magic_box()
	_limits = _label("Limits", Loc.t("Depths are GAME ESTIMATES, for play, not navigation. The normal anchor reaches %d-%d m; shelter is judged from the open water upwind, and the bottom is taken to be ordinary mixed ground everywhere.") % [
		roundi(AnchorSite.MIN_DEPTH_M), roundi(AnchorSite.NORMAL_MAX_DEPTH_M)], &"MutedLabel")
	_button("CloseButton", "Close", close)
	_ack = _button("AckButton", "Alarm seen", _on_ack)
	_reset = _button("ResetButton", "Set it again", func() -> void: start_setting(false))
	_raise = _button("RaiseButton", "Raise anchor", _on_raise)
	_magic = _button("MagicButton", GameSession.MAGIC_ANCHOR_NAME, start_magic, 180.0)
	_magic.tooltip_text = GameSession.MAGIC_ANCHOR_TEXT
	_drop = _button("DropButton", "Drop anchor", func() -> void: start_setting(true), 200.0)
	GameSession.anchor_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	var anchored := GameSession.is_anchored()
	var refusal := GameSession.anchoring_refusal()
	if anchored:
		var anchor := GameSession.get_anchor()
		var site := GameSession.evaluate_anchorage()
		var wind := Simulation.get_weather_at_vessel()
		_site.text = Loc.t("At anchor on %d × the depth of chain, %s. %s") % [anchor.scope, String(site.get("shelter", "")),
			Hud.describe_wind(wind) + "."]
		if anchor.dragged_nm > 0.0:
			_site.text += Loc.format("  Dragged %.2f nm so far.", anchor.dragged_nm)
		_holding.text = AnchorSite.holding_text(anchor.holding) + (Loc.t("  ·  ALARM") if anchor.alarm else "")
		UiTheme.tint(_holding, HOLDING_ROLES.get(anchor.holding, &""))
		_scope.select(AnchorState.SCOPES.find(anchor.scope))
	else:
		var site := GameSession.evaluate_anchorage() if GameSession.is_underway() else {}
		_site.text = refusal if refusal != "" else String(site.reason)
		_holding.text = {AnchorSite.CLASS_GOOD: "A good anchorage", AnchorSite.CLASS_FAIR: "A fair anchorage",
			AnchorSite.CLASS_POOR: "An exposed anchorage"}.get(StringName(site.get("class", "")), "No anchorage here")
		UiTheme.tint(_holding, &"caution" if refusal != "" or site.get("class", "") == AnchorSite.CLASS_POOR else &"")
	var busy := _setting or is_deploying_magic()
	_drop.visible = not anchored
	_drop.disabled = refusal != "" or busy
	_magic.visible = not anchored and GameSession.has_magic_anchor()
	_magic.disabled = busy or GameSession.anchoring_refusal(AnchorState.KIND_MAGIC) != ""
	_magic.tooltip_text = GameSession.anchoring_refusal(AnchorState.KIND_MAGIC) if _magic.disabled and not busy else GameSession.MAGIC_ANCHOR_TEXT
	if anchored and GameSession.get_anchor().kind == AnchorState.KIND_MAGIC:
		_site.text = Loc.t("The %s holds. %s") % [GameSession.MAGIC_ANCHOR_NAME, _site.text]
	if anchored and GameSession.get_anchor().depth_m > 0.0:
		_site.text += Loc.t("  Depth here %s (GAME ESTIMATE).") % DepthService.describe_depth(GameSession.get_anchor().depth_m)
	_raise.visible = anchored
	_raise.disabled = busy
	_reset.visible = anchored
	_reset.disabled = busy
	_ack.visible = anchored and GameSession.get_anchor().alarm
	_scope.disabled = busy or (not anchored and refusal != "" and not _magic.visible)


func focus_default() -> void:
	if _drop.visible and not _drop.disabled:
		_drop.grab_focus()
	elif _magic.visible and not _magic.disabled:
		_magic.grab_focus()
	elif _raise.visible:
		_raise.grab_focus()
	else:
		(find_child("CloseButton", true, false) as Button).grab_focus()


func get_scope() -> int:
	return AnchorState.SCOPES[maxi(_scope.selected, 0)]


func set_scope(scope: int) -> void:
	_scope.select(AnchorState.SCOPES.find(scope))
	_on_scope_selected(_scope.selected)


## More or less chain at anchor works out the holding again (a few minutes).
func _on_scope_selected(index: int) -> void:
	if not GameSession.is_anchored() or AnchorState.SCOPES[index] == GameSession.get_anchor().scope:
		return
	var holding := GameSession.adjust_anchor(AnchorState.SCOPES[index])
	AudioManager.play_sfx(FishingSounds.chain(), FishingSounds.DB)
	SessionLog.write("anchor", {"action": "scope", "scope": AnchorState.SCOPES[index], "holding": String(holding)})
	time_requested.emit(ADJUST_MINUTES)
	notify(Loc.t("%d × the depth of chain out: %s.") % [AnchorState.SCOPES[index], AnchorSite.holding_text(holding).to_lower()])
	refresh()


## Begins the setting interaction (for dropping, or setting it again).
func start_setting(for_drop: bool) -> void:
	if for_drop and GameSession.anchoring_refusal() != "":
		notify(GameSession.anchoring_refusal())
		return
	_setting = true
	_setting_for_drop = for_drop
	_marker = 0.0
	_set_box.visible = true
	_set_button.grab_focus()
	if for_drop:
		AudioManager.play_sfx(FishingSounds.chain(), FishingSounds.DB)
	refresh()


func is_setting() -> bool:
	return _setting


## Where the marker is now (0..1 across the bar).
func get_marker() -> float:
	return 0.5 - 0.5 * cos(_marker * TAU)


## How well a catch at `marker` sets the anchor (1 in the middle).
static func set_quality_at(marker: float) -> float:
	return clampf(1.0 - absf(marker - 0.5) * 2.0, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	if _flourish > 0.0:
		_flourish = maxf(_flourish - delta, 0.0)
		_magic_dial.queue_redraw()
		_magic_box.visible = _flourish > 0.0
	if _setting:
		_marker += delta * SET_SPEED
		_set_bar.queue_redraw()
		if Input.is_action_just_pressed(&"interact"):
			catch_set()
	elif is_deploying_magic() and (stack == null or stack.get_top() == self):
		step_magic(delta)
		if Input.is_action_just_pressed(&"interact"):
			press_magic()


## Catches the marker now (or at `at`, tests): drops or re-sets the anchor.
func catch_set(at := -1.0) -> Dictionary:
	if not _setting:
		return {}
	var quality := set_quality_at(get_marker() if at < 0.0 else at)
	_setting = false
	_set_box.visible = false
	var result := {}
	if _setting_for_drop:
		result = GameSession.drop_anchor(get_scope(), quality)
		SessionLog.write("anchor", {"action": "drop", "scope": get_scope(), "set": snappedf(quality, 0.01), "error": result.error,
			"holding": String(result.holding), "class": String(result.site.get("class", ""))})
		if result.error != "":
			notify(result.error)
		else:
			time_requested.emit(DROP_MINUTES)
			notify(Loc.t("The anchor is down and %s: %s.") % [Loc.t("well set") if quality >= 0.7 else ("set" if quality >= 0.35 else Loc.t("barely set")),
				AnchorSite.holding_text(result.holding).to_lower()])
	else:
		var holding := GameSession.adjust_anchor(get_scope(), quality)
		result = {"error": "", "holding": holding}
		SessionLog.write("anchor", {"action": "reset", "scope": get_scope(), "set": snappedf(quality, 0.01), "holding": String(holding)})
		time_requested.emit(ADJUST_MINUTES)
		notify(Loc.t("Set again: %s.") % AnchorSite.holding_text(holding).to_lower())
	result["set_quality"] = quality
	refresh()
	return result


func _on_ack() -> void:
	GameSession.acknowledge_anchor_alarm()
	SessionLog.write("anchor", {"action": "acknowledge"})
	refresh()


func _on_raise() -> void:
	var error := GameSession.raise_anchor()
	if error != "":
		notify(error)
		return
	AudioManager.play_sfx(FishingSounds.chain(), FishingSounds.DB)
	SessionLog.write("anchor", {"action": "raise"})
	time_requested.emit(RAISE_MINUTES)
	notify(Loc.t("Anchor up. The voyage continues."))
	refresh()


func get_site_text() -> String:
	return _site.text


func get_holding_text() -> String:
	return _holding.text


func _draw_set_bar() -> void:
	var size := _set_bar.size
	# A linear gauge: a sunken track with fine ticks, the good zone in green,
	# its middle brighter, and a white marker with a cyan edge.
	var track := Rect2(Vector2(0, 8), Vector2(size.x, size.y - 16))
	_set_bar.draw_rect(track, UiTheme.color(&"surface_sunken"))
	var success := UiTheme.color(&"success")
	_set_bar.draw_rect(Rect2(Vector2(size.x * 0.35, 8), Vector2(size.x * 0.3, size.y - 16)), Color(success, 0.35))
	_set_bar.draw_rect(Rect2(Vector2(size.x * 0.45, 8), Vector2(size.x * 0.1, size.y - 16)), Color(success, 0.85))
	var tick := Color(UiTheme.color(&"ink_soft"), 0.6)
	for i in 21:
		var tx := roundf(size.x * i / 20.0)
		var major := i % 5 == 0
		_set_bar.draw_line(Vector2(tx, 8), Vector2(tx, 8 + (6.0 if major else 3.0)), tick, 1.0)
	_set_bar.draw_rect(track.grow(-0.5), UiTheme.color(&"border"), false, 1.0)
	var x := get_marker() * size.x
	_set_bar.draw_rect(Rect2(Vector2(x - 2, 0), Vector2(4, size.y)), UiTheme.color(&"title"))
	_set_bar.draw_rect(Rect2(Vector2(x - 3, 0), Vector2(6, size.y)), UiTheme.color(&"accent"), false, 1.0)


# --- The Magic Anchor (0.105b) ----------------------------------------------------------

func _build_magic_box() -> void:
	_magic_box = VBoxContainer.new()
	_magic_box.name = "MagicDeploy"
	_magic_box.visible = false
	_magic_box.add_theme_constant_override(&"separation", 6)
	_box.add_child(_magic_box)
	var hint := Label.new()
	hint.name = "MagicHint"
	hint.text = "The brass flukes unfold and feel for the seabed far below. Press E (or click the dial) as the needle crosses the green arc."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(620, 0)
	_magic_box.add_child(hint)
	_magic_dial = ReelDial.new()
	_magic_dial.name = "MagicDial"
	_magic_dial.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_magic_dial.pressed.connect(func() -> void: press_magic())
	_magic_dial.draw.connect(_draw_flourish)
	_magic_box.add_child(_magic_dial)
	_magic_feedback = Label.new()
	_magic_feedback.name = "MagicFeedback"
	_magic_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_magic_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_magic_feedback.custom_minimum_size = Vector2(620, 0)
	_magic_box.add_child(_magic_feedback)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	_magic_box.add_child(row)
	_magic_retry = Button.new()
	_magic_retry.name = "MagicRetry"
	_magic_retry.text = "Try again"
	_magic_retry.custom_minimum_size = Vector2(150, 40)
	_magic_retry.pressed.connect(func() -> void: retry_magic())
	row.add_child(_magic_retry)
	_magic_cancel = Button.new()
	_magic_cancel.name = "MagicCancel"
	_magic_cancel.text = "Cancel"
	_magic_cancel.custom_minimum_size = Vector2(150, 40)
	_magic_cancel.pressed.connect(func() -> void: cancel_magic())
	row.add_child(_magic_cancel)


func is_deploying_magic() -> bool:
	return _deployment != null


func get_deployment() -> MagicAnchorDeployment:
	return _deployment


## "Magic Anchor": opens the deployment dial (checks by the wind now).
func start_magic() -> void:
	var refusal := GameSession.anchoring_refusal(AnchorState.KIND_MAGIC)
	if refusal != "":
		notify(refusal)
		return
	if _setting or is_deploying_magic():
		return
	_deployment = MagicAnchorDeployment.new(GameSession.magic_anchor_checks(), hash(GameSession.get_game_time()))
	_show_magic_attempt()
	AudioManager.play_sfx(FishingSounds.chain(), FishingSounds.DB)
	SessionLog.write("anchor", {"action": "magic_start", "checks": _deployment.check.checks_needed, "arc": _deployment.check.arc_deg})
	refresh()


func _show_magic_attempt() -> void:
	_flourish = 0.0
	_magic_dial.timing = _deployment.check
	_magic_box.visible = true
	_magic_retry.visible = false
	_magic_cancel.visible = true
	var n := _deployment.check.checks_needed
	_magic_feedback.text = (Loc.t("%d good turn to set it down.") % n if n == 1 else Loc.t("%d good turns to set it down in this wind.") % n)
	_magic_cancel.grab_focus()


## Advances the needle (every frame; tests call it directly).
func step_magic(delta: float) -> void:
	if not is_deploying_magic() or _deployment.is_over():
		return
	_deployment.check.step(delta)
	if _deployment.failed():
		_magic_failed(Loc.t("The flukes found nothing to hold before the line went slack."))


## The captain presses (key, a click on the dial).
func press_magic() -> StringName:
	if not is_deploying_magic() or _deployment.is_over():
		return TimingCheck.PRESS_NONE
	var outcome := _deployment.check.press()
	if outcome == TimingCheck.PRESS_NONE:
		return outcome
	_magic_dial.flash(outcome)
	match outcome:
		TimingCheck.PRESS_PERFECT:
			_magic_feedback.text = "Perfect!"
			AudioManager.play_sfx(FishingSounds.chain(), FishingSounds.DB)
		TimingCheck.PRESS_HIT:
			_magic_feedback.text = "Good!"
			AudioManager.play_sfx(FishingSounds.chain(), FishingSounds.DB)
		TimingCheck.PRESS_MISS:
			# Hauling back a little and paying out again takes time.
			time_requested.emit(MagicAnchorDeployment.MISS_MINUTES)
			var left := _deployment.check.get_line_control()
			_magic_feedback.text = Loc.n("Missed - it skips over the bottom (%d min). %d try left.",
				"Missed - it skips over the bottom (%d min). %d tries left.", left) % [roundi(MagicAnchorDeployment.MISS_MINUTES), left]
	SessionLog.write("anchor", {"action": "magic_press", "outcome": String(outcome)})
	if _deployment.succeeded():
		_magic_bit()
	elif _deployment.failed():
		_magic_failed(Loc.t("Too many misses: the Magic Anchor has not bitten."))
	elif outcome != TimingCheck.PRESS_MISS:
		_magic_feedback.text += Loc.t("  %d more to go.") % (_deployment.check.checks_needed - _deployment.check.hits)
	return outcome


func _magic_failed(why: String) -> void:
	_magic_feedback.text = Loc.t("%s The boat is not anchored and drifts with the weather. Try again, or cancel.") % why
	_magic_retry.visible = true
	_magic_retry.grab_focus()
	SessionLog.write("anchor", {"action": "magic_failed", "attempts": _deployment.attempts})
	AudioManager.play_sfx(FishingSounds.snap(), FishingSounds.DB)


## After a failed attempt: a fresh dial (same rules; the wind now decides the checks).
func retry_magic() -> void:
	if not is_deploying_magic() or not _deployment.failed():
		return
	var refusal := GameSession.anchoring_refusal(AnchorState.KIND_MAGIC)
	if refusal != "":
		cancel_magic()
		notify(refusal)
		return
	_deployment.start(GameSession.magic_anchor_checks(), hash(GameSession.get_game_time()))
	_show_magic_attempt()


## Cancel: nothing is let go; the boat stays as it was (unanchored).
func cancel_magic() -> void:
	if not is_deploying_magic():
		return
	SessionLog.write("anchor", {"action": "magic_cancel", "attempts": _deployment.attempts})
	_deployment = null
	_magic_box.visible = false
	refresh()
	focus_default()


func _magic_bit() -> void:
	var deployment := _deployment
	var result := GameSession.drop_magic_anchor(get_scope(), deployment.set_quality(), deployment.check.perfects)
	SessionLog.write("anchor", {"action": "magic_drop", "scope": get_scope(), "set": snappedf(deployment.set_quality(), 0.01),
		"perfects": deployment.check.perfects, "error": result.error, "holding": String(result.holding),
		"offshore": bool(result.site.get("offshore", false))})
	_deployment = null
	if result.error != "":
		_magic_box.visible = false
		notify(result.error)
		refresh()
		return
	_magic_feedback.text = "It bites!"
	_magic_retry.visible = false
	_magic_cancel.visible = false
	_flourish = FLOURISH_SECONDS
	AudioManager.play_sfx(FishingSounds.chain(), FishingSounds.DB)
	time_requested.emit(DROP_MINUTES)
	var text := Loc.t("The %s is down and holding: %s.") % [GameSession.MAGIC_ANCHOR_NAME, AnchorSite.holding_text(result.holding).to_lower()]
	if bool(result.site.get("offshore", false)):
		text += Loc.t(" Out here it holds the boat's position - it is no shelter from the weather.")
	notify(text)
	refresh()


const FLOURISH_SECONDS := 1.2


## A short cyan pulse round the dial as the Magic Anchor bites.
func _draw_flourish() -> void:
	if _flourish <= 0.0:
		return
	var t := 1.0 - _flourish / FLOURISH_SECONDS
	var strength := (1.0 - t) * (0.5 if SettingsManager.get_reduce_flashing() else 0.9)
	var radius := minf(_magic_dial.size.x, _magic_dial.size.y - 70.0) / 2.0 - 12.0
	var center := Vector2(_magic_dial.size.x / 2.0, radius + 12.0)
	_magic_dial.draw_arc(center, radius + 20.0 + 16.0 * t, 0.0, TAU, 96, Color(UiTheme.color(&"accent"), strength), 3.0, true)
	_magic_dial.draw_arc(center, radius + 8.0 + 8.0 * t, 0.0, TAU, 96, Color(UiTheme.color(&"accent"), strength * 0.6), 1.5, true)
