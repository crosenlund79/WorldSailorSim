class_name SettingsMenu
extends ModalPanel
## Shared settings dialog, used from the main menu and the pause menu.
##
## Changes preview immediately (volumes, window mode, UI scale). "Apply"
## writes them to disk; leaving with unapplied changes asks before reverting
## to the last saved values.

const BUS_LABELS := {&"Master": "Master", &"Music": "Music", &"Ambience": "Ambience", &"Wind": "Wind", &"SFX": "Sound Effects", &"UI": "UI Sounds"}
## The Wind row's test: a few seconds of the breeze, on the Wind bus (I022).
const WIND_TEST := preload("res://assets/audio/weather/wind_breeze.wav")
const WINDOW_MODE_LABELS := {
	SettingsManager.WINDOW_WINDOWED: "Windowed",
	SettingsManager.WINDOW_FULLSCREEN: "Fullscreen",
	SettingsManager.WINDOW_BORDERLESS: "Borderless fullscreen",
}
## Visual Identity V01: compare the illustrated prototype with the old art.
const ART_STYLE_LABELS := {
	SettingsManager.ART_ILLUSTRATED: "Illustrated (prototype)",
	SettingsManager.ART_CLASSIC: "Classic",
}

## Temporary test sounds used by the "Test" buttons to verify bus routing.
@export var music_test_stream: AudioStream
@export var ambience_test_stream: AudioStream
@export var sfx_test_stream: AudioStream
@export var ui_test_stream: AudioStream

var _saved: Dictionary
var _volume_sliders := {}
var _volume_labels := {}
var _art_style: OptionButton
var _course_view: CheckBox
var _reduce_flashing: CheckBox
var _flash: HSlider
var _reduce_motion: CheckBox
var _tips: CheckBox
var _ui_light: OptionButton
var _language: OptionButton

@onready var _audio_grid: GridContainer = %AudioGrid
@onready var _window_mode: OptionButton = %WindowMode
@onready var _vsync: CheckButton = %VSync
@onready var _ui_scale: HSlider = %UiScale
@onready var _ui_scale_value: Label = %UiScaleValue
@onready var _status: Label = %Status
@onready var _back: Button = %BackButton


func _ready() -> void:
	_saved = SettingsManager.snapshot()
	_build_audio_rows()
	for mode: StringName in SettingsManager.WINDOW_MODES:
		_window_mode.add_item(WINDOW_MODE_LABELS[mode])
	_window_mode.item_selected.connect(_on_window_mode_selected)
	_vsync.toggled.connect(func(on: bool) -> void:
		SettingsManager.set_vsync(on)
		_refresh_status())
	_ui_scale.min_value = SettingsManager.UI_SCALE_MIN * 100.0
	_ui_scale.max_value = SettingsManager.UI_SCALE_MAX * 100.0
	_ui_scale.step = SettingsManager.UI_SCALE_STEP * 100.0
	_ui_scale.drag_ended.connect(func(_changed: bool) -> void: _apply_ui_scale())
	_ui_scale.value_changed.connect(_on_ui_scale_value_changed)
	_build_art_style_row()
	_build_course_view_row()
	_build_accessibility_rows()
	var logs := Button.new()
	logs.name = "LogsButton"
	logs.text = "Diagnostic logs…"
	logs.tooltip_text = Loc.t("Opens the folder with the technical session logs (for bug reports): %s") % SessionLog.get_folder()
	logs.pressed.connect(func() -> void:
		if DisplayServer.get_name() != "headless":
			OS.shell_open(SessionLog.get_folder()))
	%DefaultsButton.add_sibling(logs)
	%DefaultsButton.pressed.connect(_on_defaults_pressed)
	%ApplyButton.pressed.connect(_on_apply_pressed)
	_back.pressed.connect(handle_back)
	# Steady Hands: the sections scroll when the screen is too short for them
	# (title, status and buttons always stay in view).
	var box := $Center/Panel/VBox
	FitScroll.wrap([box.get_node(^"AudioSection"), box.get_node(^"DisplaySection")] as Array[Control], $Center/Panel)
	_sync_controls()


func focus_default() -> void:
	(_volume_sliders[&"Master"] as Control).grab_focus()


func handle_back() -> void:
	if not _has_unapplied_changes():
		close()
		return
	var discard: bool = await stack.confirm(Loc.t("Discard changes?"),
		Loc.t("Some settings have not been applied. Leaving now restores the previous settings."),
		"Discard", Loc.t("Keep editing"))
	if discard:
		SettingsManager.restore_snapshot(_saved)
		close()


func _build_audio_rows() -> void:
	for bus: StringName in SettingsManager.AUDIO_BUSES:
		var name_label := Label.new()
		name_label.text = BUS_LABELS[bus]
		name_label.custom_minimum_size.x = 190
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size = Vector2(380, 32)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 70
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var test := Button.new()
		test.text = "Test"
		test.tooltip_text = Loc.t("Play a temporary test sound on the %s bus") % BUS_LABELS[bus]
		test.pressed.connect(_play_test_sound.bind(bus))
		for control: Control in [name_label, slider, value_label, test]:
			_audio_grid.add_child(control)
		_volume_sliders[bus] = slider
		_volume_labels[bus] = value_label


## "Artwork": the illustrated prototype (every boat and the harbours) or the
## classic placeholder art. Added below the interface scale.
func _build_art_style_row() -> void:
	var grid := _ui_scale.get_parent().get_parent() as GridContainer
	var label := Label.new()
	label.name = "ArtStyleLabel"
	label.text = "Artwork"
	grid.add_child(label)
	_art_style = OptionButton.new()
	_art_style.name = "ArtStyle"
	_art_style.tooltip_text = "The illustrated look is a prototype on every boat and in harbour; Classic shows the earlier art."
	for style: StringName in SettingsManager.ART_STYLES:
		_art_style.add_item(ART_STYLE_LABELS[style])
	_art_style.item_selected.connect(func(index: int) -> void:
		SettingsManager.set_art_style(SettingsManager.ART_STYLES[index])
		_refresh_status())
	grid.add_child(_art_style)


## "Sailing view": the boat faces its course underway (Iteration 12).
func _build_course_view_row() -> void:
	var grid := _ui_scale.get_parent().get_parent() as GridContainer
	var label := Label.new()
	label.name = "CourseViewLabel"
	label.text = "Sailing view"
	grid.add_child(label)
	_course_view = CheckBox.new()
	_course_view.name = "CourseView"
	_course_view.text = "Boat faces its course"
	_course_view.tooltip_text = "Underway the deck turns so the bow points along the course, north up. Off: the boat always points right."
	_course_view.toggled.connect(func(pressed: bool) -> void:
		SettingsManager.set_course_view(pressed)
		_refresh_status())
	grid.add_child(_course_view)


## Accessibility (Iteration 17): gentler highlights, and how bright
## lightning may flash (0 %: thunder only, no flash).
func _build_accessibility_rows() -> void:
	var grid := _ui_scale.get_parent().get_parent() as GridContainer
	var label := Label.new()
	label.name = "ReduceFlashingLabel"
	label.text = "Flashing"
	grid.add_child(label)
	_reduce_flashing = CheckBox.new()
	_reduce_flashing.name = "ReduceFlashing"
	_reduce_flashing.text = "Reduce flashing"
	_reduce_flashing.tooltip_text = "Lightning shows as one soft glow, and highlights pulse once gently instead of blinking."
	_reduce_flashing.toggled.connect(func(pressed: bool) -> void:
		SettingsManager.set_reduce_flashing(pressed)
		_refresh_status())
	grid.add_child(_reduce_flashing)
	var flash_label := Label.new()
	flash_label.name = "FlashIntensityLabel"
	flash_label.text = "Lightning flash"
	grid.add_child(flash_label)
	_flash = HSlider.new()
	_flash.name = "FlashIntensity"
	_flash.min_value = 0
	_flash.max_value = 100
	_flash.step = 10
	_flash.custom_minimum_size = Vector2(240, 32)
	_flash.tooltip_text = "How bright lightning flashes are (0 %: thunder only)."
	_flash.value_changed.connect(func(value: float) -> void:
		SettingsManager.set_flash_intensity(int(value))
		_refresh_status())
	grid.add_child(_flash)
	var motion_label := Label.new()
	motion_label.name = "ReduceMotionLabel"
	motion_label.text = "Motion"
	grid.add_child(motion_label)
	_reduce_motion = CheckBox.new()
	_reduce_motion.name = "ReduceMotion"
	_reduce_motion.text = "Reduce motion"
	_reduce_motion.tooltip_text = "Small decorative animations stay still (a landed fish's tail flick and bobbing)."
	_reduce_motion.toggled.connect(func(pressed: bool) -> void:
		SettingsManager.set_reduce_motion(pressed)
		_refresh_status())
	grid.add_child(_reduce_motion)
	# I022, the Captain's Academy: the contextual tips on or off.
	var tips_label := Label.new()
	tips_label.name = "TipsLabel"
	tips_label.text = "Tips"
	grid.add_child(tips_label)
	_tips = CheckBox.new()
	_tips.name = "Tips"
	_tips.text = "Show tips as you play"
	_tips.tooltip_text = "Short tips the first time you meet something new. The Captain's Handbook (F1) has everything either way."
	_tips.toggled.connect(func(pressed: bool) -> void:
		SettingsManager.set_tips_enabled(pressed)
		_refresh_status())
	grid.add_child(_tips)
	# Captain's Chartroom: the interface's day and night look.
	var light_label := Label.new()
	light_label.name = "UiLightLabel"
	light_label.text = "Interface light"
	grid.add_child(light_label)
	_ui_light = OptionButton.new()
	_ui_light.name = "UiLight"
	for text in ["Automatic (follows the day)", "Always day", "Always night"]:
		_ui_light.add_item(text)
	_ui_light.tooltip_text = "By day a sunlit instrument display, by night the same displays dimmed for dark eyes. Automatic follows the sun where the boat is."
	_ui_light.item_selected.connect(func(index: int) -> void:
		SettingsManager.set_ui_light(SettingsManager.UI_LIGHTS[index])
		_refresh_status())
	grid.add_child(_ui_light)
	# I019: the game's language, switched at once.
	var language_label := Label.new()
	language_label.name = "LanguageLabel"
	language_label.text = "Language"
	grid.add_child(language_label)
	_language = OptionButton.new()
	_language.name = "Language"
	_language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # each language in its own words
	for language: Array in Loc.LANGUAGES:
		_language.add_item(language[1])
	_language.item_selected.connect(func(index: int) -> void:
		SettingsManager.set_language(Loc.LANGUAGES[index][0])
		_retranslate()
		_refresh_status())
	grid.add_child(_language)


func _sync_controls() -> void:
	for bus: StringName in SettingsManager.AUDIO_BUSES:
		var percent := SettingsManager.get_volume(bus)
		(_volume_sliders[bus] as HSlider).set_value_no_signal(percent)
		_update_volume_label(bus, percent)
	_window_mode.select(SettingsManager.WINDOW_MODES.find(SettingsManager.get_window_mode()))
	_vsync.set_pressed_no_signal(SettingsManager.get_vsync())
	_ui_scale.set_value_no_signal(roundf(SettingsManager.get_ui_scale() * 100.0))
	_ui_scale_value.text = "%d%%" % roundi(_ui_scale.value)
	_art_style.select(SettingsManager.ART_STYLES.find(SettingsManager.get_art_style()))
	_course_view.set_pressed_no_signal(SettingsManager.get_course_view())
	_reduce_flashing.set_pressed_no_signal(SettingsManager.get_reduce_flashing())
	_flash.set_value_no_signal(SettingsManager.get_flash_intensity())
	_reduce_motion.set_pressed_no_signal(SettingsManager.get_reduce_motion())
	_tips.set_pressed_no_signal(SettingsManager.get_tips_enabled())
	_ui_light.select(SettingsManager.UI_LIGHTS.find(SettingsManager.get_ui_light()))
	_language.select(SettingsManager.LANGUAGES.find(SettingsManager.get_language()))
	_retranslate()
	_refresh_status()


## The texts built from sentences, again in the current language (a
## control's own text Godot translates by itself).
func _retranslate() -> void:
	var logs := find_child("LogsButton", true, false) as Button
	if logs:
		logs.tooltip_text = Loc.t("Opens the folder with the technical session logs (for bug reports): %s") % SessionLog.get_folder()
	for bus: StringName in SettingsManager.AUDIO_BUSES:
		_update_volume_label(bus, SettingsManager.get_volume(bus))


func _on_volume_changed(value: float, bus: StringName) -> void:
	SettingsManager.set_volume(bus, int(value))
	_update_volume_label(bus, int(value))
	_refresh_status()


func _update_volume_label(bus: StringName, percent: int) -> void:
	(_volume_labels[bus] as Label).text = "Muted" if percent == 0 else "%d%%" % percent


func _on_window_mode_selected(index: int) -> void:
	SettingsManager.set_window_mode(SettingsManager.WINDOW_MODES[index])
	_refresh_status()


## The scale is applied when the slider is released (or changed by keyboard),
## because rescaling the menu under the mouse while dragging is disorienting.
func _on_ui_scale_value_changed(value: float) -> void:
	_ui_scale_value.text = "%d%%" % roundi(value)
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_apply_ui_scale()


func _apply_ui_scale() -> void:
	SettingsManager.set_ui_scale(_ui_scale.value / 100.0)
	_refresh_status()


func _on_defaults_pressed() -> void:
	SettingsManager.restore_defaults()
	_sync_controls()


func _on_apply_pressed() -> void:
	if SettingsManager.save() == OK:
		_saved = SettingsManager.snapshot()
		_refresh_status()
		notify(Loc.t("Settings saved."))
	else:
		notify(Loc.t("Settings could not be saved."))


func _has_unapplied_changes() -> bool:
	return SettingsManager.snapshot() != _saved


func _refresh_status() -> void:
	_status.text = "Unapplied changes — press Apply to keep them." if _has_unapplied_changes() else ""


func _play_test_sound(bus: StringName) -> void:
	match bus:
		&"Music":
			# The soundtrack is already the test while it plays.
			if not MusicDirector.is_playing():
				AudioManager.play_music(music_test_stream, false)
		&"Ambience":
			AudioManager.play_one_shot(ambience_test_stream, AudioManager.BUS_AMBIENCE)
		&"Wind":
			AudioManager.play_one_shot(WIND_TEST, &"Wind")
		&"SFX":
			AudioManager.play_sfx(sfx_test_stream)
		&"UI":
			AudioManager.play_ui(ui_test_stream)
		_:
			AudioManager.play_one_shot(sfx_test_stream, &"Master")
