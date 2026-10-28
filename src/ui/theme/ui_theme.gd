extends Node
## Marine Electronics (Operation Real Horizon): one interface, two moods,
## styled after a yacht's multifunction displays (no particular product).
##
##   Day   - Sunlit display: charcoal-navy glass, clear white figures,
##           functional cyan, muted marine amber for warnings.
##   Night - Night mode: the same layout dimmed for dark adaptation.
##
## Shape language: hairline borders, 2-4 px corners, flat keys; headings in
## Barlow Condensed (instrument lettering), body text in Barlow.
##
## The project theme (assets/ui/next_harbor_theme.tres, set in project.godot)
## keeps its type variations (HudPanel, SectionPanel, MutedLabel, ...) so no
## screen needs to change how it asks for a style. This autoload rebuilds that
## same Theme object's colours and style boxes from role tokens (PALETTES) and
## recolours them in place as the light changes: the style boxes are created
## once, and a day/night blend only changes their colours (a few dozen
## objects, at most a few times a second while dusk or dawn lasts), and the
## whole recolouring is announced as one theme change (The Well-Run Ship).
##
## The mood follows the game's own daylight at the boat (Daylight: night below
## -6° sun elevation, day above +4°, blended in between), never the computer's
## clock. Settings can pin it: Automatic, Always day, Always night
## (SettingsManager.ui_light; settings.cfg, not the save).
##
## Procedural drawings in the UI (dials, badges, warnings) read colours with
## color(role) and redraw on palette_changed.

signal palette_changed

const MODE_AUTO := &"auto"
const MODE_DAY := &"day"
const MODE_NIGHT := &"night"
const MODES: Array[StringName] = [MODE_AUTO, MODE_DAY, MODE_NIGHT]

## Sun elevations (degrees) between which day blends into night.
const NIGHT_BELOW := -6.0
const DAY_ABOVE := 4.0
## How often (seconds) the automatic mood is re-evaluated, and the smallest
## blend change that is applied (so nothing is rebuilt every frame).
const CHECK_SECONDS := 0.25
const MIN_STEP := 0.02
## The fastest the interface changes mood: a whole day/night swing takes at
## least 1 / MAX_RATE real seconds.
const MAX_RATE := 0.25

## Role -> [day, night].
const PALETTES := {
	# Surfaces: charcoal-navy instrument glass (day: a sunlit display, night:
	# dimmed for dark adaptation).
	&"backdrop": [Color(0.04, 0.07, 0.09, 0.58), Color(0.01, 0.02, 0.03, 0.66)],
	&"surface": [Color("#202D35"), Color("#10181D")],
	&"surface_hud": [Color(0.106, 0.149, 0.176, 0.90), Color(0.051, 0.078, 0.094, 0.90)],
	&"surface_raised": [Color("#283842"), Color("#162027")],
	&"surface_sunken": [Color("#151E24"), Color("#0A1014")],
	&"sidebar": [Color(0.118, 0.165, 0.196, 0.96), Color(0.055, 0.086, 0.106, 0.96)],
	# Text: clear instrument typography.
	&"ink": [Color("#E4EAE8"), Color("#B7C4C6")],
	&"ink_soft": [Color("#9DB0B5"), Color("#7C8F94")],
	&"heading": [Color("#7FC3D0"), Color("#5AA8B8")],
	&"title": [Color("#F0F3F1"), Color("#C4D0D1")],
	# Lines and accents: precise hairlines, functional cyan.
	&"border": [Color("#3E525C"), Color("#2A3940")],
	&"border_soft": [Color(0.467, 0.533, 0.549, 0.30), Color(0.467, 0.533, 0.549, 0.22)],
	&"accent": [Color("#5AA8B8"), Color("#4A94A3")],
	&"rust": [Color("#D49A4B"), Color("#B9843F")],
	&"focus": [Color("#7FC3D0"), Color("#5AA8B8")],
	# Buttons: flat keys on the panel, cyan-edged when active.
	&"button": [Color("#2B3B45"), Color("#18232A")],
	&"button_hover": [Color("#35505C"), Color("#203540")],
	&"button_pressed": [Color("#1A3640"), Color("#0F242C")],
	&"button_text": [Color("#E4EAE8"), Color("#B7C4C6")],
	&"action": [Color("#5AA8B8"), Color("#3F8796")],
	&"action_hover": [Color("#73BACA"), Color("#4C99A8")],
	&"action_text": [Color("#0B171D"), Color("#050B0E")],
	&"disabled": [Color(0.16, 0.21, 0.24, 0.6), Color(0.09, 0.13, 0.15, 0.6)],
	&"disabled_text": [Color(0.62, 0.69, 0.71, 0.45), Color(0.50, 0.57, 0.59, 0.40)],
	# States: muted marine amber for warnings.
	&"warning": [Color("#E0A657"), Color("#C98F45")],
	&"warning_surface": [Color(0.20, 0.16, 0.11, 0.96), Color(0.12, 0.09, 0.06, 0.96)],
	&"success": [Color("#86C29A"), Color("#6AA47E")],
	&"caution": [Color("#D9BB66"), Color("#B9A055")],
	# Documents (the developer guides): code and links.
	&"code": [Color("#E2C38E"), Color("#C7AA7A")],
	&"link": [Color("#7FC3D0"), Color("#5AA8B8")],
	&"tooltip": [Color("#162127"), Color("#0A1115")],
	&"key": [Color("#3A5560"), Color("#22363F")],
	&"key_text": [Color("#E4EAE8"), Color("#B7C4C6")],
	&"track": [Color(0.467, 0.533, 0.549, 0.28), Color(0.467, 0.533, 0.549, 0.20)],
	&"shadow": [Color(0.0, 0.0, 0.0, 0.35), Color(0.0, 0.0, 0.0, 0.5)],
}

## The largest corner radius any style box gets (precise, not toy-like).
const MAX_RADIUS := 3

var theme: Theme
## 0 = day, 1 = night, as currently applied.
var blend := 0.0
var _mode: StringName = MODE_AUTO
var _check := 0.0
var _last_step_msec := 0
var _boxes: Array[Dictionary] = []
var _colors: Array[Array] = []
## Modal backdrops seen (weak), recoloured with the palette.
var _dims: Array[WeakRef] = []
## Controls given a role colour with tint(): [WeakRef, theme item, role].
var _tints: Array[Array] = []
var _font_heading: Font
var _font_body: Font
var _font_medium: Font
var _font_semibold: Font


func _ready() -> void:
	theme = ThemeDB.get_project_theme()
	if theme == null:
		theme = Theme.new()
	# Instrument headings: Barlow Condensed, slightly spaced. Body text stays Barlow.
	_font_heading = _condensed("res://assets/fonts/BarlowCondensed-SemiBold.ttf", 1)
	_font_body = load("res://assets/fonts/Barlow-Regular.ttf")
	_font_medium = load("res://assets/fonts/Barlow-Medium.ttf")
	_font_semibold = load("res://assets/fonts/Barlow-SemiBold.ttf")
	_build()
	_mode = SettingsManager.get_ui_light() if SettingsManager.has_method("get_ui_light") else MODE_AUTO
	if SettingsManager.has_signal("ui_light_changed"):
		SettingsManager.ui_light_changed.connect(set_mode)
	set_blend(_target_blend(), true)
	# Every modal's "Dim" backdrop takes the theme's backdrop colour.
	get_tree().node_added.connect(_on_node_added)


## A condensed instrument face with a little letter spacing (Barlow as the
## fallback for any glyph it lacks).
func _condensed(path: String, spacing: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = load(path)
	v.spacing_glyph = spacing
	v.fallbacks = [load("res://assets/fonts/Barlow-Regular.ttf")]
	return v


func _on_node_added(node: Node) -> void:
	if node is ColorRect and node.name == &"Dim" and node.get_parent() is ModalPanel:
		(node as ColorRect).color = color(&"backdrop")
		_dims.append(weakref(node))


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_SECONDS
	var target := _target_blend()
	if absf(target - blend) >= MIN_STEP or (target in [0.0, 1.0] and target != blend):
		# Never faster than MAX_RATE: in fast time, after a long sleep or on
		# loading a game at night the interface still eases over a few seconds.
		# Real time since the last step, so slow frames do not slow it down.
		var now := Time.get_ticks_msec()
		# (The first step of a change counts as one check.)
		var elapsed := (now - _last_step_msec) / 1000.0
		elapsed = clampf(elapsed, CHECK_SECONDS, 1.0) if elapsed < 2.0 else CHECK_SECONDS
		_last_step_msec = now
		set_blend(move_toward(blend, target, MAX_RATE * elapsed))


## Automatic, Always day or Always night.
func set_mode(mode: StringName) -> void:
	_mode = mode if mode in MODES else MODE_AUTO
	set_blend(_target_blend(), true)


func get_mode() -> StringName:
	return _mode


func is_night() -> bool:
	return blend >= 0.5


## The colour of `role` now (day/night blended).
func color(role: StringName) -> Color:
	var pair: Array = PALETTES.get(role, [Color.MAGENTA, Color.MAGENTA])
	return (pair[0] as Color).lerp(pair[1], blend)


## The colour of `role` in a given mood (tests, previews).
static func color_at(role: StringName, night_amount: float) -> Color:
	var pair: Array = PALETTES.get(role, [Color.MAGENTA, Color.MAGENTA])
	return (pair[0] as Color).lerp(pair[1], clampf(night_amount, 0.0, 1.0))


func _target_blend() -> float:
	match _mode:
		MODE_DAY:
			return 0.0
		MODE_NIGHT:
			return 1.0
	if not GameSession.is_active():
		return 0.0
	var elevation := Daylight.sun_elevation(GameSession.get_vessel_position(), GameSession.get_game_time())
	return 1.0 - smoothstep(NIGHT_BELOW, DAY_ABOVE, elevation)


## Applies a day/night blend (0..1) to every themed colour and style box.
func set_blend(value: float, force := false) -> void:
	value = clampf(value, 0.0, 1.0)
	if not force and is_equal_approx(value, blend):
		return
	blend = value
	# One theme change for the whole recolouring (The Well-Run Ship): every
	# colour or style box set on the project theme otherwise announces itself,
	# and each announcement refreshes every control in the game (hundreds of
	# whole-tree refreshes per step, seconds with the chart open).
	theme.set_block_signals(true)
	for spec in _boxes:
		var box: StyleBox = spec.box
		if box is StyleBoxFlat:
			var flat := box as StyleBoxFlat
			if spec.fill != &"":
				flat.bg_color = _with_alpha(color(spec.fill), spec.fill_alpha)
			if spec.border != &"":
				flat.border_color = _with_alpha(color(spec.border), spec.border_alpha)
			if spec.has("shadow"):
				flat.shadow_color = color(&"shadow")
		elif box is StyleBoxLine:
			(box as StyleBoxLine).color = color(spec.border)
	for c in _colors:
		theme.set_color(c[1], c[0], _with_alpha(color(c[2]), c[3]))
	theme.set_block_signals(false)
	theme.emit_changed()
	var alive: Array[WeakRef] = []
	for ref in _dims:
		var dim := ref.get_ref() as ColorRect
		if dim:
			dim.color = color(&"backdrop")
			alive.append(ref)
	_dims = alive
	var kept: Array[Array] = []
	for entry in _tints:
		var control := (entry[0] as WeakRef).get_ref() as Control
		if control and control.has_meta(&"ui_tint_" + String(entry[1])):
			control.add_theme_color_override(entry[1], color(control.get_meta(&"ui_tint_" + String(entry[1]))))
			kept.append(entry)
	_tints = kept
	palette_changed.emit()


## Adapter for screens that colour a single control by meaning (a holding
## that is poor, a level that needs work): gives `control`'s `item` colour
## the theme `role` ("success", "caution", "warning", "ink"...) and keeps it
## right through dawn and dusk. An empty role puts the theme's own colour back.
## Cheap to call every frame: it only changes anything when the role changes.
func tint(control: Control, role: StringName, item: StringName = &"font_color") -> void:
	var key := &"ui_tint_" + String(item)
	if role == &"":
		if control.has_meta(key):
			control.remove_meta(key)
			control.remove_theme_color_override(item)
		return
	if control.get_meta(key, &"") == role:
		return
	if not control.has_meta(key):
		_tints.append([weakref(control), item])
	control.set_meta(key, role)
	control.add_theme_color_override(item, color(role))


static func _with_alpha(c: Color, alpha: float) -> Color:
	return Color(c, c.a * alpha) if alpha >= 0.0 else c


# --- Building the theme -----------------------------------------------------------------------

## A rounded style box coloured by roles ("" = transparent / no border).
func _box(fill: StringName, border: StringName, border_w := 0, radius := 8, margin := Vector4(12, 8, 12, 8),
		shadow := 0, fill_alpha := -1.0, border_alpha := -1.0, draw_center := true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = draw_center and fill != &""
	# Instrument shape language: tight corners, hairline borders.
	box.set_corner_radius_all(mini(radius, MAX_RADIUS))
	box.set_border_width_all(mini(border_w, 1) if border_w > 0 and fill != &"" else border_w)
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w
	box.anti_aliasing = true
	var spec := {"box": box, "fill": fill, "border": border, "fill_alpha": fill_alpha, "border_alpha": border_alpha}
	if shadow > 0:
		box.shadow_size = mini(shadow, 6)
		box.shadow_offset = Vector2(0, 2)
		spec["shadow"] = true
	if fill == &"":
		box.bg_color = Color.TRANSPARENT
	_boxes.append(spec)
	return box


func _style(type: StringName, name: StringName, box: StyleBox) -> void:
	theme.set_stylebox(name, type, box)


func _col(type: StringName, name: StringName, role: StringName, alpha := -1.0) -> void:
	_colors.append([type, name, role, alpha])


func _button_states(type: StringName, fill: StringName, hover: StringName, text: StringName, margin := Vector4(16, 8, 16, 8)) -> void:
	_style(type, &"normal", _box(fill, &"border", 2, 8, margin, 2))
	_style(type, &"hover", _box(hover, &"accent", 2, 8, margin, 3))
	_style(type, &"pressed", _box(&"button_pressed", &"accent", 2, 8, margin))
	_style(type, &"hover_pressed", _box(&"button_pressed", &"accent", 2, 8, margin))
	_style(type, &"disabled", _box(&"disabled", &"border_soft", 1, 8, margin))
	_style(type, &"focus", _box(&"", &"focus", 3, 9, margin, 0, -1.0, -1.0, false))
	for state: StringName in [&"font_color", &"font_focus_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
		_col(type, state, text)
	_col(type, &"font_disabled_color", &"disabled_text")


func _build() -> void:
	_boxes.clear()
	_colors.clear()
	theme.default_font = _font_body
	# Buttons: raised parchment (day) / slate (night), brass edged.
	_button_states(&"Button", &"button", &"button_hover", &"button_text")
	_button_states(&"OptionButton", &"button", &"button_hover", &"button_text")
	_button_states(&"BigButton", &"action", &"action_hover", &"action_text", Vector4(24, 12, 24, 12))
	# The other items of a big menu (pause, title screen): the same size as the
	# one primary action, but quiet, so only one button calls out.
	theme.set_type_variation(&"MenuItem", &"BigButton")
	_button_states(&"MenuItem", &"button", &"button_hover", &"button_text", Vector4(24, 12, 24, 12))
	_col(&"Button", &"icon_normal_color", &"button_text")
	# Small map and tool controls (the chart's toolbar): quieter, compact.
	_button_states(&"MapButton", &"button", &"button_hover", &"button_text", Vector4(10, 3, 10, 3))
	theme.set_type_variation(&"MapButton", &"Button")
	theme.set_font_size(&"font_size", &"MapButton", 17)
	theme.set_type_variation(&"MapToggle", &"CheckButton")
	theme.set_font_size(&"font_size", &"MapToggle", 17)
	# A table of contents (the developer guides): quiet rows; the open one is
	# marked by a brass/amber rule on the left, like a bookmark.
	theme.set_type_variation(&"TocButton", &"Button")
	var toc_margin := Vector4(14, 6, 10, 6)
	_style(&"TocButton", &"normal", _box(&"", &"", 0, 4, toc_margin))
	_style(&"TocButton", &"hover", _box(&"surface_raised", &"", 0, 4, toc_margin))
	_style(&"TocButton", &"disabled", _box(&"", &"", 0, 4, toc_margin))
	_style(&"TocButton", &"focus", _box(&"", &"focus", 2, 4, toc_margin, 0, -1.0, -1.0, false))
	for state: StringName in [&"pressed", &"hover_pressed"]:
		var marked := _box(&"surface_raised", &"accent", 0, 4, toc_margin)
		marked.border_width_left = 4
		_style(&"TocButton", state, marked)
	for state: StringName in [&"font_color", &"font_focus_color", &"font_hover_color"]:
		_col(&"TocButton", state, &"ink")
	for state: StringName in [&"font_pressed_color", &"font_hover_pressed_color"]:
		_col(&"TocButton", state, &"heading")
	# Check boxes and switches: no box, text in ink.
	for type: StringName in [&"CheckBox", &"CheckButton"]:
		for state: StringName in [&"font_color", &"font_focus_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color"]:
			_col(type, state, &"ink")
		_col(type, &"font_disabled_color", &"disabled_text")
		_style(type, &"focus", _box(&"", &"focus", 2, 6, Vector4(4, 2, 4, 2), 0, -1.0, -1.0, false))
	# Text.
	_col(&"Label", &"font_color", &"ink")
	_col(&"MutedLabel", &"font_color", &"ink_soft")
	_col(&"HeaderLabel", &"font_color", &"heading")
	_col(&"TitleLabel", &"font_color", &"title")
	_col(&"DisplayHeader", &"font_color", &"heading")
	_col(&"DisplayName", &"font_color", &"ink")
	_col(&"DisplayTagline", &"font_color", &"ink_soft")
	_col(&"RichTextLabel", &"default_color", &"ink")
	_col(&"LineEdit", &"font_color", &"ink")
	_col(&"LineEdit", &"font_placeholder_color", &"ink_soft", 0.8)
	_col(&"LineEdit", &"caret_color", &"focus")
	_style(&"LineEdit", &"normal", _box(&"surface_sunken", &"border_soft", 1, 6, Vector4(10, 6, 10, 6)))
	_style(&"LineEdit", &"focus", _box(&"", &"focus", 2, 6, Vector4(10, 6, 10, 6), 0, -1.0, -1.0, false))
	_style(&"LineEdit", &"read_only", _box(&"disabled", &"border_soft", 1, 6, Vector4(10, 6, 10, 6)))
	# Headings: a little maritime handwriting; body stays Barlow.
	theme.set_font(&"font", &"HeaderLabel", _font_heading)
	theme.set_font_size(&"font_size", &"HeaderLabel", 27)
	theme.set_font(&"font", &"TitleLabel", _font_heading)
	theme.set_font_size(&"font_size", &"TitleLabel", 42)
	var display := _condensed("res://assets/fonts/BarlowCondensed-Medium.ttf", 1)
	for type: StringName in [&"DisplayHeader", &"DisplayName", &"DisplayTagline"]:
		theme.set_font(&"font", type, display)
	theme.set_font_size(&"font_size", &"DisplayTagline", 30)
	theme.set_font(&"font", &"Button", _font_medium)
	theme.set_font(&"font", &"OptionButton", _font_medium)
	# Keys (E, Q, Esc...): a small brass/amber plate.
	_col(&"KeyLabel", &"font_color", &"key_text")
	_style(&"KeyLabel", &"normal", _box(&"key", &"", 0, 5, Vector4(7, 1, 7, 1)))
	# Panels.
	_style(&"PanelContainer", &"panel", _box(&"surface", &"border", 2, 12, Vector4(20, 16, 20, 16), 8))
	_style(&"Panel", &"panel", _box(&"surface", &"border", 2, 12, Vector4(20, 16, 20, 16), 8))
	_style(&"HudPanel", &"panel", _box(&"surface_hud", &"border", 1, 10, Vector4(14, 8, 14, 8), 4))
	_style(&"SectionPanel", &"panel", _box(&"surface_raised", &"border_soft", 1, 8, Vector4(14, 10, 14, 10)))
	_style(&"SidebarPanel", &"panel", _box(&"sidebar", &"border", 2, 12, Vector4(20, 16, 20, 16), 8))
	_style(&"PromptPanel", &"panel", _box(&"surface_hud", &"accent", 2, 10, Vector4(14, 8, 14, 8), 4))
	_style(&"ToastPanel", &"panel", _box(&"surface_hud", &"border", 1, 10, Vector4(16, 8, 16, 8), 4))
	_style(&"WarningPanel", &"panel", _box(&"warning_surface", &"warning", 2, 10, Vector4(16, 10, 16, 10), 4))
	theme.set_type_variation(&"WarningPanel", &"PanelContainer")
	# The shortcut strip: a slim, quiet bar.
	_style(&"KeyBar", &"panel", _box(&"surface_hud", &"border_soft", 1, 8, Vector4(10, 3, 10, 3), 2, 0.85))
	theme.set_type_variation(&"KeyBar", &"PanelContainer")
	# Text that needs attention (low stores, a worn hull) or reports good news.
	_col(&"WarningLabel", &"font_color", &"warning")
	theme.set_type_variation(&"WarningLabel", &"Label")
	_col(&"SuccessLabel", &"font_color", &"success")
	theme.set_type_variation(&"SuccessLabel", &"Label")
	_style(&"TooltipPanel", &"panel", _box(&"tooltip", &"border", 1, 6, Vector4(10, 6, 10, 6), 3))
	_col(&"TooltipLabel", &"font_color", &"ink")
	_style(&"PopupMenu", &"panel", _box(&"surface_raised", &"border", 1, 8, Vector4(6, 6, 6, 6), 4))
	_style(&"PopupMenu", &"hover", _box(&"button_pressed", &"", 0, 5))
	_col(&"PopupMenu", &"font_color", &"ink")
	_col(&"PopupMenu", &"font_hover_color", &"ink")
	_col(&"PopupMenu", &"font_disabled_color", &"disabled_text")
	_style(&"AcceptDialog", &"panel", _box(&"surface", &"border", 2, 12, Vector4(20, 16, 20, 16), 8))
	# Tabs: an underlined tab on the page, quiet ones beside it.
	for type: StringName in [&"TabBar", &"TabContainer"]:
		_style(type, &"tab_selected", _box(&"surface_raised", &"accent", 0, 6, Vector4(14, 6, 14, 6)))
		(_boxes[-1].box as StyleBoxFlat).border_width_bottom = 3
		_style(type, &"tab_unselected", _box(&"", &"", 0, 6, Vector4(14, 6, 14, 6)))
		_style(type, &"tab_hovered", _box(&"button_hover", &"border_soft", 0, 6, Vector4(14, 6, 14, 6)))
		_style(type, &"tab_disabled", _box(&"", &"", 0, 6, Vector4(14, 6, 14, 6)))
		_style(type, &"tab_focus", _box(&"", &"focus", 2, 6, Vector4(14, 6, 14, 6), 0, -1.0, -1.0, false))
		_col(type, &"font_selected_color", &"ink")
		_col(type, &"font_hovered_color", &"ink")
		_col(type, &"font_unselected_color", &"ink_soft")
		_col(type, &"font_disabled_color", &"disabled_text")
	_style(&"TabContainer", &"panel", _box(&"", &"", 0, 0, Vector4(0, 10, 0, 0)))
	# Separators, scroll bars, sliders, progress.
	var line := StyleBoxLine.new()
	line.thickness = 1
	_boxes.append({"box": line, "fill": &"", "border": &"border_soft", "fill_alpha": -1.0, "border_alpha": -1.0})
	_style(&"HSeparator", &"separator", line)
	for type: StringName in [&"VScrollBar", &"HScrollBar"]:
		_style(type, &"scroll", _box(&"track", &"", 0, 4, Vector4(4, 4, 4, 4)))
		_style(type, &"grabber", _box(&"border", &"", 0, 4))
		_style(type, &"grabber_highlight", _box(&"accent", &"", 0, 4))
		_style(type, &"grabber_pressed", _box(&"rust", &"", 0, 4))
	_style(&"HSlider", &"slider", _box(&"track", &"", 0, 3, Vector4(0, 3, 0, 3)))
	_style(&"HSlider", &"grabber_area", _box(&"accent", &"", 0, 3, Vector4(0, 3, 0, 3)))
	_style(&"HSlider", &"grabber_area_highlight", _box(&"focus", &"", 0, 3, Vector4(0, 3, 0, 3)))
	_style(&"HSlider", &"focus", _box(&"", &"focus", 2, 6, Vector4(2, 2, 2, 2), 0, -1.0, -1.0, false))
	_style(&"ProgressBar", &"background", _box(&"track", &"", 0, 4, Vector4(0, 0, 0, 0)))
	_style(&"ProgressBar", &"fill", _box(&"accent", &"", 0, 4, Vector4(0, 0, 0, 0)))
	_col(&"ProgressBar", &"font_color", &"ink")
	_style(&"ItemList", &"panel", _box(&"surface_sunken", &"border_soft", 1, 8, Vector4(6, 6, 6, 6)))
	_col(&"ItemList", &"font_color", &"ink")
	_col(&"ItemList", &"font_selected_color", &"ink")
	_style(&"ItemList", &"selected", _box(&"button_pressed", &"", 0, 5))
	_style(&"ItemList", &"selected_focus", _box(&"button_pressed", &"focus", 1, 5))
