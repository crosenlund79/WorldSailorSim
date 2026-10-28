class_name TestQuay
extends RefCounted
## Test helper (I026 stage 02): since the harbour's businesses moved up to
## the quay (HarbourFront), a test that wants the grocery store, the
## boatyard or a trade walks up the pontoon's walkway and uses its door, as
## a player does.


static func settle(t: Node, app: Node) -> void:
	await t.frames(2)
	await t.wait_until(func() -> bool: return not app.router.is_busy(), 5.0)
	await t.physics_frames(3)


## Up the walkway to the quay (from the deck; the deck is shown first when
## the Captain is below). Returns the quay, or null without one (at sea).
static func go_up(t: Node, app: Node) -> HarbourFront:
	if app.router.current_screen is HarbourFront:
		return app.router.current_screen
	var deck := app.router.current_screen as BoatArea
	if deck == null or deck.area_id != SessionState.AREA_EXTERIOR:
		app.modals.clear()
		GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"from_boatyard")
		app._show_current_boat_area()
		await settle(t, app)
		deck = app.router.current_screen as BoatArea
	if deck == null or deck.get_walkway() == null or not deck.get_walkway().enabled:
		return null
	deck.get_walkway().interact(deck.player)
	await settle(t, app)
	return app.router.current_screen as HarbourFront


## Walks to `place` on the quay (a business id, the hatch, the noticeboard,
## the lane, the travel lift) and presses E there. `any_hour`: the door is
## used whatever the clock says (for tests that are not about the hours).
## Returns whether the door was there and focused.
static func use_door(t: Node, app: Node, place: StringName, any_hour := true) -> bool:
	var front := await go_up(t, app)
	if front == null:
		return false
	var station := front.get_station(place)
	if station == null:
		return false
	front.player.position = station.position + Vector2(0, 6)
	await t.physics_frames(3)
	if front.player.get_focused_interactable() != station:
		return false
	BusinessHours.test_always_open = any_hour
	await t.press_action(&"interact")
	await t.frames(3)
	BusinessHours.test_always_open = false
	return true
