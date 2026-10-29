class_name OpeningStory
extends ModalPanel
## The opening story (Between Horizons, I027 Tier 4): a short, quiet prologue
## shown once, when a new game begins from the title screen's New Game, and
## never on loading a save (old saves never replay it). Three illustrated
## stills - a desk by a city window at dusk, the boat waiting at a pontoon at
## dawn, the open sea (the title scene) - with the Captain's approved words a
## few lines at a time, cross-fading from page to page. The Captain is an
## experienced sailor leaving the office life behind, not a beginner.
##
## Click, Space, Enter or "Continue" turns the page; "Skip" or Esc ends it at
## once. It ends where the game begins: aboard, in the cabin (the application
## shows the boat under it; nothing else is asked of the Captain - the First
## Voyage offer, when there is one, comes after it).
##
## Pictures: assets/opening/*.png (tools/branding/paint_opening_scenes.py)
## and assets/ui/title_scene.png. Words: Loc (English and Danish).
## Drawn once per page; tweens only, no per-frame work.

## Emitted when the story ends (`skipped`: ended early with Skip or Esc).
signal finished(skipped: bool)

## Off in tests (the test runner), so the new-game flows stay as they were;
## the opening's own suite turns it on.
static var enabled := true

const DESK := "res://assets/opening/desk_at_dusk.png"
const HARBOUR := "res://assets/opening/harbour_dawn.png"
const SEA := "res://assets/ui/title_scene.png"
## Seconds: the picture's cross-fade, the words' fade, and the slow drift
## (a 3 % push-in over a page, barely noticed).
const PICTURE_FADE := 1.1
const TEXT_FADE := 0.6
const DRIFT := 14.0
const DRIFT_SCALE := 1.03
## The words sit in the lower part of the picture, on a soft dark band.
const TEXT_WIDTH := 1040.0
const TEXT_COLOUR := Color("#F0EEE8")
const SHADOW := Color(0.02, 0.04, 0.06, 0.8)
const INK := Color("#0A1115")

var page_index := -1
var _pages: Array[Dictionary] = []
var _back: TextureRect
var _front: TextureRect
var _words: Label
var _logo: TextureRect
var _continue: Button
var _ended := false
var _tweens: Array[Tween] = []


## The pages: a picture and its words (the approved script, paced).
static func pages() -> Array[Dictionary]:
	return [
		{"picture": DESK, "text": Loc.t("For years, the sea had been calling.")},
		{"picture": DESK, "text": Loc.t("Between meetings, deadlines and the familiar rhythm of another working week, you found yourself studying charts. Reading about distant harbours. Imagining the places you might one day sail.")},
		{"picture": DESK, "text": Loc.t("You were no stranger to sailing. But somehow, the voyages you'd dreamed about always seemed to belong to another life.")},
		{"picture": HARBOUR, "text": Loc.t("Until one day, you decided you'd waited long enough.\nYou left the nine-to-five behind.")},
		{"picture": HARBOUR, "text": Loc.t("Not with a fortune. Not with every answer. Just a little money, a boat, and the experience to know that the sea rarely follows anyone's plans.")},
		{"picture": HARBOUR, "text": Loc.t("There would be fuel to buy, repairs to make and bills to pay.\nPerhaps you could earn your living taking others to the places they'd always dreamed of seeing.")},
		{"picture": SEA, "text": Loc.t("And perhaps, somewhere along the way, you would find a way to reach your own.")},
		{"picture": SEA, "text": Loc.t("Your old life is behind you.\nThe next horizon is yours to discover."), "logo": true},
	]


func _ready() -> void:
	name = "OpeningStory"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_pages = pages()
	var ink := ColorRect.new()
	ink.name = "Ink"
	ink.color = INK
	ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ink)
	_back = _picture(&"Back")
	_front = _picture(&"Front")
	# A soft dark band under the words, so they read on any picture.
	var band := TextureRect.new()
	band.name = "Band"
	var gradient := Gradient.new()
	gradient.set_color(0, Color(INK, 0.0))
	gradient.set_color(1, Color(INK, 0.78))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.5, 0.0)
	fill.fill_to = Vector2(0.5, 1.0)
	fill.width = 4
	fill.height = 64
	band.texture = fill
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.anchor_top = 0.55
	band.offset_top = 0.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	column.anchor_top = 0.6
	column.offset_top = 0.0
	column.offset_bottom = -96.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 18)
	add_child(column)
	_logo = TextureRect.new()
	_logo.name = "Logo"
	_logo.texture = load(GameVersion.LOGO_SMALL_PATH)
	_logo.custom_minimum_size = Vector2(0, 92)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo.modulate.a = 0.0
	_logo.visible = false
	column.add_child(_logo)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(centre)
	_words = Label.new()
	_words.name = "Words"
	_words.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_words.add_theme_font_size_override(&"font_size", 30)
	_words.add_theme_constant_override(&"line_spacing", 6)
	_words.add_theme_color_override(&"font_color", TEXT_COLOUR)
	_words.add_theme_color_override(&"font_shadow_color", SHADOW)
	_words.add_theme_constant_override(&"shadow_offset_y", 2)
	_words.add_theme_constant_override(&"shadow_outline_size", 8)
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(_words)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buttons.grow_vertical = Control.GROW_DIRECTION_BEGIN
	buttons.offset_right = -36.0
	buttons.offset_bottom = -30.0
	buttons.add_theme_constant_override(&"separation", 12)
	add_child(buttons)
	var skip := Button.new()
	skip.name = "SkipButton"
	skip.text = "Skip"
	skip.flat = true
	skip.custom_minimum_size = Vector2(120, 0)
	skip.pressed.connect(func() -> void: end(true))
	buttons.add_child(skip)
	_continue = Button.new()
	_continue.name = "ContinueButton"
	_continue.text = "Continue"
	_continue.custom_minimum_size = Vector2(170, 0)
	_continue.pressed.connect(advance)
	buttons.add_child(_continue)
	modulate.a = 0.0
	_tween().tween_property(self, ^"modulate:a", 1.0, TEXT_FADE)
	advance()


func _picture(node_name: StringName) -> TextureRect:
	var picture := TextureRect.new()
	picture.name = node_name
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.modulate.a = 0.0
	add_child(picture)
	return picture


func focus_default() -> void:
	if _continue:
		_continue.grab_focus()


## Esc: the story ends at once.
func handle_back() -> void:
	end(true)


func _gui_input(event: InputEvent) -> void:
	# A click on the picture turns the page.
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		advance()


## The next page, or the end after the last.
func advance() -> void:
	if _ended:
		return
	page_index += 1
	if page_index >= _pages.size():
		end(false)
		return
	var page := _pages[page_index]
	var path := String(page.picture)
	if _front.texture == null or _front.texture.resource_path != path:
		_show_picture(load(path) as Texture2D)
	_words.modulate.a = 0.0
	_words.text = page.text
	_tween().tween_property(_words, ^"modulate:a", 1.0, TEXT_FADE).set_delay(0.15)
	var with_logo := bool(page.get("logo", false))
	_logo.visible = with_logo
	if with_logo:
		_tween().tween_property(_logo, ^"modulate:a", 1.0, PICTURE_FADE).set_delay(0.6)
	_continue.text = "Begin" if page_index == _pages.size() - 1 else "Continue"


## Cross-fades to `texture`: the old picture moves to the back.
func _show_picture(texture: Texture2D) -> void:
	_back.texture = _front.texture
	_back.modulate.a = 1.0 if _back.texture else 0.0
	_back.scale = _front.scale
	_back.pivot_offset = _front.pivot_offset
	_front.texture = texture
	_front.modulate.a = 0.0
	_front.pivot_offset = size * 0.5
	_front.scale = Vector2.ONE
	_tween().tween_property(_front, ^"modulate:a", 1.0, PICTURE_FADE)
	_tween().tween_property(_front, ^"scale", Vector2.ONE * DRIFT_SCALE, DRIFT).set_trans(Tween.TRANS_SINE)


## Ends the story (once): a short fade, then `finished` and the modal closes.
func end(skipped: bool) -> void:
	if _ended:
		return
	_ended = true
	for tween in _tweens:
		if tween.is_valid():
			tween.kill()
	_tweens.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := create_tween()
	fade.tween_property(self, ^"modulate:a", 0.0, TEXT_FADE)
	fade.tween_callback(func() -> void:
		finished.emit(skipped)
		close())


func is_ended() -> bool:
	return _ended


func _tween() -> Tween:
	var tween := create_tween()
	_tweens.append(tween)
	return tween
