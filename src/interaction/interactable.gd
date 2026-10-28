class_name Interactable
extends Area2D
## Something the player can interact with when standing close to it.
##
## Its collision shape defines the interaction range. Interactables do not
## implement behaviour themselves: they emit `interacted`, and the scene that
## owns them decides what happens. Interactables that only need to show a
## short text can set `message` instead of needing any code.

signal interacted(interactable: Interactable, actor: Node)

## Physics layer 3 ("interactables") is the only layer interactables occupy.
const COLLISION_LAYER := 1 << 2

## Stable id the owning scene uses to route the interaction.
@export var interaction_id: StringName
## Verb shown in the prompt, e.g. "Open chart".
@export var prompt := "Interact"
## Optional text shown as a notification when used.
@export_multiline var message := ""
@export var enabled := true
## Which interactable wins when several are in reach (see InteractionSensor):
## stations, doors and the berth keep the default 0; the ship's companion
## uses -1, so it never takes the focus from a nearby station unless the
## player stands clearly closer to it.
@export var focus_priority := 0
## Node tinted while this interactable has focus.
@export var highlight_target: NodePath = ^".."

const HIGHLIGHT := Color(1.16, 1.2, 1.22)
## The focus highlight drawn around the object itself (Iteration 12): a warm
## glow and a fine cream outline that breathes gently.
const GLOW := Color(0.55, 0.82, 0.88, 0.28)
const OUTLINE := Color(0.86, 0.95, 0.97, 0.95)
const DEBUG_AREA := Color(0.4, 0.9, 1.0, 0.55)

## Developer view (F8 with the developer tools): every interaction area drawn.
static var debug_show_areas := false
## The inverse of the area's ambient light (BoatLighting, Iteration 17), so
## the focus highlight stays as bright at night as by day.
static var light_compensation := Color.WHITE

## The visible object's outline in this node's coordinates, set by the owning
## scene (see HighlightResolver); empty: a small soft outline of the area.
var highlight_outline := PackedVector2Array()

var _focused := false
var _time := 0.0


func _ready() -> void:
	collision_layer = COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func interact(actor: Node) -> void:
	if enabled:
		interacted.emit(self, actor)


func set_focused(focused: bool) -> void:
	if _focused == focused:
		return
	_focused = focused
	var target := get_node_or_null(highlight_target) as CanvasItem if not highlight_target.is_empty() else null
	if target:
		target.modulate = HIGHLIGHT if focused else Color.WHITE
	_time = 0.0
	set_process(focused or debug_show_areas)
	queue_redraw()


## Sets the object outline from global points (empty to use the area).
func set_highlight_outline_global(points: PackedVector2Array) -> void:
	highlight_outline = PackedVector2Array()
	for p in points:
		highlight_outline.append(to_local(p))
	queue_redraw()


## The outline drawn while focused, in this node's coordinates.
func get_highlight_points() -> PackedVector2Array:
	if highlight_outline.size() >= 3:
		return highlight_outline
	return HighlightResolver.rounded_rect(_area_rect().grow(-4.0), 10.0)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if not _focused and not debug_show_areas:
		set_process(false)


## Focused stations without a highlight target glow around their object.
## The interaction area itself is never drawn in normal play.
func _draw() -> void:
	if debug_show_areas:
		var area := _area_rect()
		draw_rect(area, DEBUG_AREA, false, 1.5)
	if not _focused or not highlight_target.is_empty():
		return
	var points := get_highlight_points()
	if points.size() < 3:
		return
	var closed := points.duplicate()
	closed.append(points[0])
	var breathe := 0.5 + 0.5 * sin(_time * 3.2)
	self_modulate = light_compensation
	draw_polyline(closed, Color(GLOW, GLOW.a * (0.7 + 0.5 * breathe)), 9.0, true)
	draw_polyline(closed, Color(OUTLINE, OUTLINE.a * (0.75 + 0.25 * breathe)), 2.2, true)


## The interaction area's bounds in this node's coordinates.
func _area_rect() -> Rect2:
	for child in get_children():
		var shape := child as CollisionShape2D
		if shape and shape.shape:
			var rect := shape.shape.get_rect()
			return Rect2(rect.position + shape.position, rect.size)
	return Rect2(-24, -24, 48, 48)


func is_focused() -> bool:
	return _focused


## Point used to rank interactables by distance from the player.
func get_interaction_position() -> Vector2:
	return global_position

