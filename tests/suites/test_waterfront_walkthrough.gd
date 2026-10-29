extends RefCounted
## I026, A World You Can Touch: the new things reached in ordinary play, the
## way a player reaches them - no screen opened by code, no Captain placed by
## hand. From the main menu (New Game, Start), the Captain walks with the
## movement keys (steered along a path through the cells the real collision
## leaves free) and uses E:
##   cabin -> companionway -> deck -> the pontoon's walkway -> the quay;
##   the quay: storefronts and townsfolk walking; the café (order, sit, a
##   coffee), the chandlery (Electronics: buy and fit Modern Cruiser with a
##   click);
##   back down the walkway to the deck: the cockpit instruments show the new
##   package, I opens them close up, and under way the HUD shows them.
## Course planning is the only shortcut: the route is planned in code (the
## chart table's own planning has its own suites).

const APP_SCENE := preload("res://src/app/app.tscn")
const W := preload("res://tests/helpers/walkability.gd")
const MOVES: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
const QUAY_GRID := 10.0

var t: Node
var app: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	WeatherFixtures.use([])
	t.use_calm_wind()
	app = APP_SCENE.instantiate()
	t.add_child(app)
	app.router.fade_duration = 0.05
	await _settle()
	await _new_game_from_the_menu()
	var deck := await _up_on_deck()
	var front := await _up_the_walkway(deck)
	if front:
		await _the_quay(front)
		await _the_cafe(front)
		await _the_chandlery(front)
		deck = await _down_the_walkway(front)
		if deck:
			await _the_instruments(deck)
	_release()
	Simulation.auto_advance = true
	app.queue_free()
	await t.frames(2)
	GameSession.end_session()
	t.use_calm_wind()


func _settle() -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


func _button(root: Node, button_name: String) -> Button:
	return root.find_child(button_name, true, false) as Button if root else null


# --- Walking like a player -----------------------------------------------------

func _release() -> void:
	for action in MOVES:
		Input.action_release(action)


## Holds the movement keys towards `direction` (analogue strengths).
func _steer(direction: Vector2) -> void:
	var d := direction.normalized()
	Input.action_press(&"move_right", maxf(d.x, 0.0)) if d.x > 0.05 else Input.action_release(&"move_right")
	Input.action_press(&"move_left", maxf(-d.x, 0.0)) if d.x < -0.05 else Input.action_release(&"move_left")
	Input.action_press(&"move_down", maxf(d.y, 0.0)) if d.y > 0.05 else Input.action_release(&"move_down")
	Input.action_press(&"move_up", maxf(-d.y, 0.0)) if d.y < -0.05 else Input.action_release(&"move_up")


## Free cells for the player's collision circle on the quay (as BoatArea's
## W.walkable_cells does aboard).
func _quay_cells(front: HarbourFront, from: Vector2) -> Array[Vector2]:
	var space := front.get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = W.PLAYER_RADIUS
	query.shape = circle
	query.collision_mask = front.player.collision_mask
	query.exclude = [front.player.get_rid()]
	var free := func(q: Vector2) -> bool:
		query.transform = Transform2D(0.0, front.to_global(q))
		return space.intersect_shape(query, 1).is_empty()
	# The nearest free grid cell (between the café's tables the snapped
	# position itself can touch a table).
	var start := from.snapped(Vector2(QUAY_GRID, QUAY_GRID))
	var best := Vector2.INF
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var q := start + Vector2(dx, dy) * QUAY_GRID
			if free.call(q) and (best == Vector2.INF or q.distance_to(from) < best.distance_to(from)):
				best = q
	if best != Vector2.INF:
		start = best
	var cells: Array[Vector2] = []
	var seen := {start: true}
	var queue: Array[Vector2] = [start]
	var bounds := Rect2(front.layout.left - 40.0, -40.0, front.layout.right - front.layout.left + 80.0, QuayLayout.EDGE_Y + 140.0)
	while not queue.is_empty():
		var p: Vector2 = queue.pop_back()
		cells.append(p)
		for step in [Vector2(QUAY_GRID, 0), Vector2(-QUAY_GRID, 0), Vector2(0, QUAY_GRID), Vector2(0, -QUAY_GRID)]:
			var q: Vector2 = p + step
			if seen.has(q) or not bounds.has_point(q):
				continue
			seen[q] = true
			if free.call(q):
				queue.append(q)
	return cells


## The shortest grid path through `cells` from the cell nearest `from` to one
## from which `station` is in reach.
func _path(cells: Array[Vector2], grid: float, from: Vector2, station: Interactable) -> Array[Vector2]:
	var free := {}
	for c in cells:
		free[c] = true
	var start := W.nearest(cells, from)
	var parent := {start: start}
	var queue: Array[Vector2] = [start]
	var head := 0
	while head < queue.size():
		var p: Vector2 = queue[head]
		head += 1
		if W.distance_to_station(station, p) <= W.USE_DISTANCE:
			var path: Array[Vector2] = [p]
			while parent[path[0]] != path[0]:
				path.push_front(parent[path[0]])
			return path
		for step in [Vector2(grid, 0), Vector2(-grid, 0), Vector2(0, grid), Vector2(0, -grid)]:
			var q: Vector2 = p + step
			if free.has(q) and not parent.has(q):
				parent[q] = p
				queue.append(q)
	return []


## Walks `player` along `path` with the movement keys, then turns towards
## `station` until it is focused. Returns whether it is.
func _walk(player: Node2D, path: Array[Vector2], station: Interactable) -> bool:
	for i in range(0, path.size(), 2):
		var waypoint := path[i] if i + 2 < path.size() else path[-1]
		var frames := 0
		while player.position.distance_to(waypoint) > 7.0 and frames < 150:
			_steer(waypoint - player.position)
			await t.physics_frames(1)
			frames += 1
	var turn := 0
	while player.get_focused_interactable() != station and turn < 20:
		_steer(station.global_position - player.global_position)
		await t.physics_frames(1)
		turn += 1
	_release()
	await t.physics_frames(3)
	return player.get_focused_interactable() == station


func _walk_aboard(area: BoatArea, station: Interactable) -> bool:
	var cells := W.walkable_cells(area, area.player.position.snapped(Vector2(W.GRID, W.GRID)))
	var path := _path(cells, W.GRID, area.player.position, station)
	return not path.is_empty() and await _walk(area.player, path, station)


func _walk_on_quay(front: HarbourFront, station: Interactable) -> bool:
	var path := _path(_quay_cells(front, front.player.position), QUAY_GRID, front.player.position, station)
	return not path.is_empty() and await _walk(front.player, path, station)


func _station(area: Node, id: StringName) -> Interactable:
	for node in area.find_children("*", "Interactable", true, false):
		if (node as Interactable).interaction_id == id and (node as Interactable).enabled:
			return node
	return null


# --- The walk ------------------------------------------------------------------

func _new_game_from_the_menu() -> void:
	t.check(app.router.current_screen is MainMenu, "[play] the game starts on the main menu")
	await t.click(_button(app.router.current_screen, "NewGameButton"))
	await t.click(_button(app.modals.get_top(), "StartButton"))
	await _settle()
	var cabin := app.router.current_screen as BoatArea
	t.check(cabin != null and cabin.area_id == SessionState.AREA_INTERIOR and GameSession.is_moored_in_harbour(),
		"[play] New Game: in the cabin, moored in harbour (%s)" % GameSession.get_location_id())


func _up_on_deck() -> BoatArea:
	var cabin := app.router.current_screen as BoatArea
	var steps := _station(cabin, &"companionway")
	var reached := steps != null and await _walk_aboard(cabin, steps)
	t.check(reached, "[play] walked to the companionway (prompt '%s')" % app.hud.get_prompt())
	await t.press_action(&"interact")
	await _settle()
	var deck := app.router.current_screen as BoatArea
	t.check(deck != null and deck.area_id == SessionState.AREA_EXTERIOR, "[play] E: on deck")
	return deck


func _up_the_walkway(deck: BoatArea) -> HarbourFront:
	if deck == null:
		return null
	var walkway := deck.get_walkway()
	t.check(walkway != null and walkway.enabled and walkway.is_visible_in_tree(), "[play] the pontoon's walkway to the quay is there")
	var reached := walkway != null and await _walk_aboard(deck, walkway)
	t.check(reached and app.hud.get_prompt() != "", "[play] walked down the gangplank and along the pontoon to it (prompt '%s')" % app.hud.get_prompt())
	await t.screenshot("i026_play_01_walkway")
	await t.press_action(&"interact")
	await _settle()
	var front := app.router.current_screen as HarbourFront
	t.check(front != null and front.port_id == GameSession.get_location_id(), "[play] E: up on the quay of %s" % GameSession.get_location_id())
	return front


func _the_quay(front: HarbourFront) -> void:
	var businesses := front.get_layout().get_businesses()
	var drawn := businesses.filter(func(b: StringName) -> bool: return front.get_storefront(b) != null and front.get_station(b) != null)
	t.check(drawn.size() == businesses.size() and businesses.size() >= 5 and QuayLayout.CAFE in businesses,
		"[play] a storefront and a door for each business on this quay (%s)" % [businesses])
	await t.screenshot("i026_play_02_quay")
	# The townsfolk walk while the Captain watches.
	Simulation.auto_advance = true
	var people: Array = front.life.get_people()
	var before := people.map(func(p: Node2D) -> Vector2: return p.position)
	await t.get_tree().create_timer(3.0).timeout
	var moved := 0
	for i in people.size():
		if is_instance_valid(people[i]) and (people[i] as Node2D).position.distance_to(before[i]) > 20.0:
			moved += 1
	t.check(people.size() >= 1 and moved >= 1, "[play] townsfolk about and walking (%d of %d moved)" % [moved, people.size()])


func _the_cafe(front: HarbourFront) -> void:
	var door := front.get_station(QuayLayout.CAFE)
	var reached := await _walk_on_quay(front, door)
	t.check(reached, "[play] walked to the café's door ('%s')" % app.hud.get_prompt())
	var funds := GameSession.get_funds()
	await t.press_action(&"interact")
	await t.frames(4)
	var menu: Node = app.modals.get_top()
	if not t.check(menu is CafeMenu, "[play] E: the café's counter (open at this hour: %s)" % BusinessHours.status_text(QuayLayout.CAFE, front.port_id, GameSession.get_game_time())):
		app.modals.clear()
		return
	await t.click(_button(menu, "OrderButton"))
	await t.frames(6)
	t.check(GameSession.get_funds() == funds - GameSession.cafe_coffee_price() and front.is_seated(),
		"[play] a coffee for %s, the Captain seated on the terrace" % GameSession.format_money(GameSession.cafe_coffee_price()))
	await t.screenshot("i026_play_03_cafe")
	await t.press_key(KEY_DOWN)
	await t.physics_frames(3)
	t.check(not front.is_seated() and _quay_cells(front, front.player.position).size() > 1000,
		"[play] a movement key (Down): up again, out on the open terrace (%s)" % front.player.position)


func _the_chandlery(front: HarbourFront) -> void:
	var door := front.get_station(QuayLayout.CHANDLERY)
	if not t.check(door != null, "[play] a chandlery on this quay"):
		return
	var reached := await _walk_on_quay(front, door)
	t.check(reached, "[play] walked along the quay to the chandlery ('%s')" % app.hud.get_prompt())
	await t.press_action(&"interact")
	await t.frames(4)
	var menu: Node = app.modals.get_top()
	if not t.check(menu is ChandleryMenu, "[play] E: the chandlery's counter"):
		app.modals.clear()
		return
	var row: Node = menu.find_child("Row_instruments_%s" % InstrumentPackage.MODERN, true, false)
	var buy: Button = row.find_children("*", "Button", true, false).back() as Button if row else null
	t.check(buy != null and not buy.disabled, "[play] Electronics: Modern Cruiser for sale (%s)" % (buy.text if buy else "?"))
	if buy:
		# Scrolled down to Electronics, as a player would.
		var scroll := buy.get_parent()
		while scroll and not scroll is ScrollContainer:
			scroll = scroll.get_parent()
		if scroll:
			(scroll as ScrollContainer).ensure_control_visible(buy)
			await t.frames(3)
		await t.click(buy)
		await t.frames(4)
		if app.modals.get_top() is ConfirmDialog:
			await t.click(_button(app.modals.get_top(), "ConfirmButton"))
			await t.frames(4)
	t.check(GameSession.owns_instrument_package(InstrumentPackage.MODERN) and GameSession.get_instrument_package().id == InstrumentPackage.MODERN,
		"[play] bought and fitted with a click")
	await t.screenshot("i026_play_04_chandlery")
	await t.press_action(&"pause")
	await t.frames(3)
	t.check(app.modals.is_empty(), "[play] Esc: back on the quay")


func _down_the_walkway(front: HarbourFront) -> BoatArea:
	var walkway := front.get_station(HarbourFront.WALKWAY)
	var reached := await _walk_on_quay(front, walkway)
	t.check(reached, "[play] walked back to the walkway's head ('%s')" % app.hud.get_prompt())
	await t.press_action(&"interact")
	await _settle()
	var deck := app.router.current_screen as BoatArea
	t.check(deck != null and deck.area_id == SessionState.AREA_EXTERIOR, "[play] E: back aboard, on the pontoon by the boat")
	return deck


func _the_instruments(deck: BoatArea) -> void:
	var cockpit := deck.find_children("*", "CockpitInstruments", true, false)
	t.check(not cockpit.is_empty(), "[play] the cockpit instruments are on deck")
	await t.press_action(&"instruments")
	await t.frames(4)
	var view := app.modals.get_top() as InstrumentView
	t.check(view != null and view.package.id == InstrumentPackage.MODERN, "[play] I: the instruments close up, the new Modern Cruiser")
	await t.screenshot("i026_play_05_instruments")
	await t.press_action(&"pause")
	await t.frames(3)
	GameSession.plan_route_to(&"kiel")
	GameSession.depart()
	await _settle()
	await t.frames(6)
	t.check(app.hud.instrument_cluster.is_visible_in_tree() and app.hud.instrument_cluster.get_units().size() == 3,
		"[play] under way the HUD shows the three displays")
	await t.screenshot("i026_play_06_underway")
	GameSession.start_new_session(&"")
	await t.frames(2)
