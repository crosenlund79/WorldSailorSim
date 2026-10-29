extends Node2D
## I027 Tier 4, people that belong to the world: a character sheet drawn with
## the game's own drawing code (SailorDrawing with the hat, TownsfolkDrawing,
## GirlDrawing), large, for before/after comparison - the Captain through a
## walking cycle facing right, down, up-left (a diagonal) and standing, with
## the hat worn and carried; three townsfolk walking and one seated; the girl
## walking. With --frames=N it also saves N frames of the Captain and a
## townsperson walking side by side (for a short animated GIF).
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1600x900 res://tests/character_sheet_i027.tscn -- --out=DIR [--label=after] [--frames=24]

const SCALE := 3.0
const PHASES := 6

var out := "res://docs/screenshots/i027/tier4/characters"
var label := "after"
var frames := 0
var _frame := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--label="):
			label = a.trim_prefix("--label=")
		elif a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
	RenderingServer.set_default_clear_color(Color("#8E9294"))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	queue_redraw()
	await _save("%s_sheet" % label)
	for i in frames:
		_frame = i
		queue_redraw()
		await _save("%s_walk_%02d" % [label, i])
	get_tree().quit()


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("SHOT ", name)


## The walking cycle's phase and the arm swing at step `i` of `n`.
func _cycle(i: int, n: int) -> Vector2:
	var phase := TAU * i / n
	return Vector2(phase, sin(phase))


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, 1600, 900), Color("#9A9C98"))
	for x in range(0, 1600, 40):
		draw_line(Vector2(x, 0), Vector2(x, 900), Color(1, 1, 1, 0.04), 1.0)
	if _frame >= 0:
		_draw_walkers(font)
		return
	draw_string(font, Vector2(24, 34), "%s - the Captain: a walking cycle (right, down, up-left), standing, hat carried" % label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)
	var facings := [Vector2.RIGHT, Vector2.DOWN, Vector2(-1, -1).normalized()]
	for row in facings.size():
		for i in PHASES:
			var c := _cycle(i, PHASES)
			_captain(Vector2(110 + i * 150, 120 + row * 150), facings[row], c, 1.0, false)
	_captain(Vector2(110 + PHASES * 150, 120), Vector2.RIGHT, Vector2.ZERO, 0.0, false)
	_captain(Vector2(110 + PHASES * 150, 270), Vector2.DOWN, Vector2(0.8, sin(0.8)), 1.0, true)
	draw_string(font, Vector2(24, 560), "townsfolk walking (three looks), seated, and the girl", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)
	for k in 3:
		var look := TownsfolkDrawing.make_look([&"nordic", &"mediterranean", &"tropical"][k], 7 + k * 13)
		for i in 3:
			var c := _cycle(i * 2, PHASES)
			_person(Vector2(110 + (k * 3 + i) * 130, 650), Vector2.RIGHT, c, look, false)
	_person(Vector2(1300, 650), Vector2.DOWN, Vector2.ZERO, TownsfolkDrawing.make_look(&"atlantic", 3), true)
	for i in 3:
		var c := _cycle(i * 2, PHASES)
		_girl(Vector2(150 + i * 130, 800), Vector2.RIGHT, c)


func _draw_walkers(font: Font) -> void:
	var c := _cycle(_frame, maxi(frames, 1))
	draw_string(font, Vector2(24, 34), "%s - walking: the Captain and a townsperson (frame %d)" % [label, _frame], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.BLACK)
	_captain(Vector2(300, 300), Vector2.RIGHT, c, 1.0, false)
	_captain(Vector2(700, 300), Vector2(1, 1).normalized(), c, 1.0, false)
	_person(Vector2(1100, 300), Vector2.RIGHT, c, TownsfolkDrawing.make_look(&"nordic", 7), false)


func _captain(at: Vector2, facing: Vector2, c: Vector2, amount: float, carrying: bool) -> void:
	draw_set_transform(at, 0.0, Vector2.ONE * SCALE)
	_call_sailor(facing, c, amount, carrying)
	if not carrying:
		HatArt.get_default().draw_slot(self, HatArt.SLOT_WORN, Vector2.ZERO, facing.angle())
	else:
		var hand := SailorDrawing.hand_position(facing, 0.2, -1.0)
		HatArt.get_default().draw_slot(self, HatArt.SLOT_STORED, hand + facing.orthogonal() * -4.0, facing.angle() + PI * 0.5, 1.0, PlayerHat.CARRIED_SCALE)
	draw_set_transform(Vector2.ZERO)


## SailorDrawing before and after I027 (the walking phase became a parameter).
func _call_sailor(facing: Vector2, c: Vector2, amount: float, carrying: bool) -> void:
	var f: Callable = SailorDrawing.draw
	if f.get_argument_count() >= 7:
		f.callv([self, facing, c.y * amount, carrying, false, c.x, amount])
	else:
		f.callv([self, facing, c.y * amount, carrying, false])


func _person(at: Vector2, facing: Vector2, c: Vector2, look: Dictionary, seated: bool) -> void:
	draw_set_transform(at, 0.0, Vector2.ONE * SCALE)
	var f: Callable = TownsfolkDrawing.draw
	var amount := 0.0 if c == Vector2.ZERO or seated else 1.0
	if f.get_argument_count() >= 8:
		f.callv([self, facing, c.y, look, seated, TownsfolkDrawing.ITEM_NONE, c.x, amount])
	else:
		f.callv([self, facing, c.y, look, seated, TownsfolkDrawing.ITEM_NONE])
	draw_set_transform(Vector2.ZERO)


func _girl(at: Vector2, facing: Vector2, c: Vector2) -> void:
	draw_set_transform(at, 0.0, Vector2.ONE * SCALE)
	var f: Callable = GirlDrawing.draw
	if f.get_argument_count() >= 7:
		f.callv([self, facing, c.y, 0.0, false, c.x, 1.0])
	else:
		f.callv([self, facing, c.y, 0.0, false])
	draw_set_transform(Vector2.ZERO)
