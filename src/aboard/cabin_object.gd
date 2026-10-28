class_name CabinObject
extends Node2D
## The things a sailor uses below (I026, A World You Can Touch), each a small
## object drawn where it belongs, with its own Interactable (E) that opens
## its focused view:
##   LOGBOOK  - the Captain's Log, a bound book on the chart table
##   VHF      - the radio set at the nav station (calls, the last broadcast)
##   SYSTEMS  - the switch panel: what the boat really keeps track of
##   CHEST    - the sea chest at the foot of the berth ("Make it home")
##   POSTCARD - the newest postcard, propped on the saloon table (only once
##              there is one), opening the scrapbook at it
## Placed from each cabin's own furniture (Layout/Collision fixtures), so
## every boat gets them without hand-placed markers; a cabin without the
## piece of furniture simply lacks that object. Art only besides the
## Interactable: no collision, so they never block the Captain or the
## companions. BoatArea emits cabin_object_requested(kind) when one is used.

const LOGBOOK := &"logbook"
const VHF := &"vhf"
const SYSTEMS := &"systems"
const CHEST := &"keepsakes"
const POSTCARD := &"postcard"
const KINDS: Array[StringName] = [LOGBOOK, VHF, SYSTEMS, CHEST, POSTCARD]
## Where each goes: the fixtures to look for, in order, and how far along
## the fixture's long side (0..1).
const PLACES := {
	LOGBOOK: [["NavTable", "NavDesk"], 0.28],
	VHF: [["NavTable", "NavDesk"], 0.78],
	SYSTEMS: [["EngineBox", "GalleySide", "CompanionwaySteps"], 0.5],
	CHEST: [["VBerth", "OwnerBerth", "GuestBerth"], 0.5],
	POSTCARD: [["SaloonTable", "Table", "Desk"], 0.2],
}
const REACH := 34.0
const POSTCARD_CHECK_SECONDS := 2.0
const INK := Color(0.12, 0.13, 0.14, 0.6)
const SHADOW := Color(0.04, 0.05, 0.06, 0.28)

var kind: StringName = LOGBOOK
var interactable: Interactable
## The VHF's lamp: lit while a call waits.
var call_waiting := false
var _time := 0.0


## Puts every cabin object in `area` (cabins only). Returns them.
static func place_all(area: Node2D) -> Array[CabinObject]:
	var out: Array[CabinObject] = []
	for k in KINDS:
		var placed := place(area, k)
		if placed:
			out.append(placed)
	return out


static func place(area: Node2D, object_kind: StringName) -> CabinObject:
	var rule: Array = PLACES[object_kind]
	var rect := Rect2()
	for fixture_name: String in rule[0]:
		var fixture := area.get_node_or_null(NodePath("Layout/Collision/" + fixture_name)) as BoatFixture
		if fixture:
			rect = _rect_of(area, fixture)
			break
	if rect.size == Vector2.ZERO:
		return null
	var object := CabinObject.new()
	object.name = "CabinObject_%s" % object_kind
	object.kind = object_kind
	object.position = _spot(rect, float(rule[1]), object_kind, area)
	object.z_index = 3
	area.add_child(object)
	return object


static func _rect_of(area: Node2D, fixture: BoatFixture) -> Rect2:
	var points := fixture.transform * fixture.get_points()
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect


## A spot on the fixture: `along` its long side; across, towards the cabin's
## middle (where the Captain stands), a hand's width in from the edge.
static func _spot(rect: Rect2, along: float, object_kind: StringName, area: Node2D) -> Vector2:
	var at := rect.get_center()
	var long_x := rect.size.x >= rect.size.y
	if long_x:
		at.x = rect.position.x + rect.size.x * along
	else:
		at.y = rect.position.y + rect.size.y * along
	var toward := -rect.get_center()  # the cabin's middle is about the origin
	var inset := 12.0
	if object_kind == CHEST:
		inset = 22.0
	if long_x:
		at.y = rect.get_center().y + signf(toward.y) * maxf(rect.size.y * 0.5 - inset, 0.0)
	else:
		at.x = rect.get_center().x + signf(toward.x) * maxf(rect.size.x * 0.5 - inset, 0.0)
	return at


func _ready() -> void:
	interactable = Interactable.new()
	interactable.name = "Use"
	interactable.interaction_id = kind
	interactable.prompt = prompt_for(kind)
	interactable.highlight_target = ^""
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = REACH
	shape.shape = circle
	interactable.add_child(shape)
	add_child(interactable)
	interactable.set_highlight_outline_global(_outline_global())
	refresh()


static func prompt_for(object_kind: StringName) -> String:
	match object_kind:
		LOGBOOK:
			return Loc.t("Read the logbook")
		VHF:
			return Loc.t("Use the VHF radio")
		SYSTEMS:
			return Loc.t("Check the boat's systems")
		CHEST:
			return Loc.t("Open the sea chest")
	return Loc.t("Look at the postcard")


## Shows what the object depends on (the postcard only with a postcard).
func refresh() -> void:
	if kind == POSTCARD:
		var has_card := GameSession.is_active() and not GameSession.get_pastimes().postcards.is_empty()
		visible = has_card
		if interactable:
			interactable.enabled = has_card
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	match kind:
		VHF:
			if call_waiting:
				queue_redraw()
		POSTCARD:
			# A postcard made on the laptop appears on the table (checked now
			# and then, not every frame).
			if _time >= POSTCARD_CHECK_SECONDS:
				_time = 0.0
				refresh()
		_:
			set_process(false)


func size_of() -> Vector2:
	match kind:
		LOGBOOK:
			return Vector2(30, 21)
		VHF:
			return Vector2(22, 12)
		SYSTEMS:
			return Vector2(36, 24)
		CHEST:
			return Vector2(56, 34)
	return Vector2(16, 11)


func _outline_global() -> PackedVector2Array:
	var points := PackedVector2Array()
	var s := size_of()
	for p in HighlightResolver.rounded_rect(Rect2(-s * 0.5, s).grow(3.0), 3.0):
		points.append(to_global(p))
	return points


func _draw() -> void:
	var s := size_of()
	var r := Rect2(-s * 0.5, s)
	draw_rect(Rect2(r.position + Vector2(1.5, 2.0), r.size), SHADOW)
	match kind:
		LOGBOOK:
			# A green cloth-bound book, closed, a ribbon out of the bottom.
			draw_rect(r, Color("#2F4A3F"))
			draw_rect(Rect2(r.position + Vector2(2, 0), Vector2(r.size.x - 2, r.size.y)), Color("#3A5C4E"))
			draw_rect(Rect2(Vector2(r.end.x - 1.6, r.position.y + 1), Vector2(1.6, r.size.y - 2)), Color(0.9, 0.87, 0.78))
			draw_rect(Rect2(r.position + Vector2(9, 6), Vector2(12, 5)), Color(0.78, 0.68, 0.42, 0.85))
			draw_line(Vector2(r.position.x + 22, r.end.y), Vector2(r.position.x + 22, r.end.y + 5), Color("#9E3B32"), 1.6)
		VHF:
			# A graphite set, a green channel window, the handset on its hook.
			draw_rect(r, Color("#22282C"))
			draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(r.size.x * 0.55, r.size.y - 4)), Color("#5FA88C"))
			draw_rect(Rect2(Vector2(r.end.x - 6, r.position.y + 2), Vector2(4, r.size.y - 4)), Color("#3A4246"))
			var lit := call_waiting and fmod(_time, 1.0) < 0.55
			draw_circle(Vector2(r.position.x + r.size.x * 0.7, r.position.y + 3.0), 1.4, Color("#E0A848") if lit else Color("#6A5A3A"))
		SYSTEMS:
			# The switch panel: breakers in two rows, a small meter.
			draw_rect(r, Color("#C9CCC6"))
			for row in 2:
				for col in 6:
					draw_rect(Rect2(r.position + Vector2(3 + col * 5.0, 4 + row * 9.0), Vector2(3, 6)), Color("#3A4044"))
			draw_circle(Vector2(r.end.x - 4.5, r.position.y + 6.0), 3.0, Color("#E6E8E4"))
		CHEST:
			# A small teak sea chest with rope beckets and brass corners.
			draw_rect(r, Color("#7A5636"))
			draw_rect(r.grow(-3.0), Color("#8C6642"))
			draw_line(Vector2(r.position.x + 3, r.get_center().y), Vector2(r.end.x - 3, r.get_center().y), Color(0.32, 0.22, 0.14, 0.7), 1.2)
			for c in [r.position, Vector2(r.end.x - 4, r.position.y), r.end - Vector2(4, 4), Vector2(r.position.x, r.end.y - 4)]:
				draw_rect(Rect2(c, Vector2(4, 4)), Color("#B89A56"))
			for x in [r.position.x - 2.0, r.end.x]:
				draw_rect(Rect2(Vector2(x, r.get_center().y - 4.0), Vector2(2.0, 8.0)), Color("#C8B48A"))
		_:
			# A postcard, a little askew, its picture side up.
			draw_set_transform(Vector2.ZERO, -0.12, Vector2.ONE)
			draw_rect(r, Color(0.93, 0.92, 0.88))
			draw_rect(Rect2(r.position + Vector2(1.2, 1.2), Vector2(r.size.x * 0.6, r.size.y - 2.4)), Color("#6C93A4"))
			draw_rect(Rect2(r.position + Vector2(1.2, r.size.y * 0.55), Vector2(r.size.x * 0.6, r.size.y * 0.45 - 1.2)), Color("#4B6E7C"))
			draw_rect(Rect2(Vector2(r.end.x - 4, r.position.y + 1.5), Vector2(3, 3.5)), Color("#A0503F"))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(r, INK, false, 0.8)
