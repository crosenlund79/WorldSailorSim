class_name AboardBadge
extends VBoxContainer
## The HUD's quiet aboard indicators (Iteration 13), under the hat badge, so
## nothing depends on hearing a sound:
##   - "Fish on! Reel in  R" while a fish waits on the line (pulsing);
##   - "Line out · trolling" while fishing (amber when too fast to troll);
##   - "At anchor · Holding well / Fair holding / Poor holding" and, red,
##     "Anchor dragging! Go to the windlass";
##   - "Well fed" after a warm meal.
## It only reads GameSession (presentation only, nothing is saved).

## Theme roles for the lines (Captain's Chartroom: right by day and by night).
const CALM := &""
const AMBER := &"caution"
const RED := &"warning"

var _rows := {}
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 6)
	for id in ["bite", "anchor", "line", "fed"]:
		var panel := PanelContainer.new()
		panel.name = id.capitalize()
		panel.theme_type_variation = &"HudPanel"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		panel.add_child(row)
		var label := Label.new()
		label.name = "Text"
		row.add_child(label)
		var key := Label.new()
		key.name = "Key"
		key.theme_type_variation = &"KeyLabel"
		key.text = "R"
		row.add_child(key)
		panel.hide()
		add_child(panel)
		_rows[id] = panel


func _process(delta: float) -> void:
	_time += delta
	refresh()


## The indicators now: {id: [text, colour, key shown]} for the visible ones.
static func lines_for_game() -> Dictionary:
	var lines := {}
	if not GameSession.is_active():
		return lines
	if not GameSession.get_pending_bite().is_empty():
		lines.bite = [Loc.t("Fish on! Reel in"), AMBER, true]
	if GameSession.is_anchored():
		var anchor := GameSession.get_anchor()
		if anchor.holding == AnchorState.HOLDING_DRAGGING:
			lines.anchor = [Loc.t("Anchor dragging! Go to the windlass"), RED, false]
		else:
			var settled := ""
			if GameSession.is_settled_at_anchor():
				# Life at anchor (0.102b): the badge says how the stay feels.
				settled = {AnchorLife.PHASE_EVENING: Loc.t("  ·  a quiet evening"), AnchorLife.PHASE_NIGHT: Loc.t("  ·  a calm night"),
					AnchorLife.PHASE_MORNING: Loc.t("  ·  a still morning")}.get(GameSession.get_day_phase(), "")
			lines.anchor = [Loc.t("At anchor  ·  %s%s") % [AnchorSite.holding_text(anchor.holding), settled],
				AMBER if anchor.holding == AnchorState.HOLDING_POOR else CALM, false]
	if GameSession.is_line_out():
		if GameSession.get_fishing_mode() == FishingState.MODE_TROLLING:
			var too_fast := GameSession.get_vessel_speed_kn() > FishingCatalog.get_default().max_trolling_kn
			lines.line = [Loc.t("Line out  ·  too fast to troll") if too_fast else Loc.t("Line out  ·  trolling"), AMBER if too_fast else CALM, false]
		else:
			lines.line = [Loc.t("Line out"), CALM, false]
	if GameSession.is_well_fed():
		lines.fed = [Loc.t("Well fed"), CALM, false]
	return lines


func refresh() -> void:
	var lines := lines_for_game()
	for id: String in _rows:
		var panel := _rows[id] as PanelContainer
		panel.visible = lines.has(id)
		if not panel.visible:
			continue
		var label := panel.find_child("Text", true, false) as Label
		label.text = lines[id][0]
		UiTheme.tint(label, lines[id][1])
		(panel.find_child("Key", true, false) as Label).visible = lines[id][2]
		var urgent: bool = id == "bite" or lines[id][1] == RED
		# A gentle cool pulse (the panel's text colour still says how urgent).
		panel.modulate = Color(0.86 + 0.14 * cos(_time * 8.0), 1.0, 1.0) if urgent else Color.WHITE


## The visible indicators' texts (tests, screenshots).
func get_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for id: String in _rows:
		var panel := _rows[id] as PanelContainer
		if panel.visible:
			texts.append((panel.find_child("Text", true, false) as Label).text)
	return texts
