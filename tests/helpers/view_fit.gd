class_name ViewFit
extends RefCounted
## Test helper (I026): opens each focused view at the window sizes, UI scales
## and languages the game promises (1280 x 720 and 1024 x 768, 100 % and
## 130 %, English and Danish) and lists the ones whose panel - with its
## FocusFrame's margin when it has one - does not fit on the screen.

const SETUPS: Array = [[Vector2i(1280, 720), &"en", 1.0], [Vector2i(1280, 720), &"da", 1.3],
	[Vector2i(1024, 768), &"da", 1.0], [Vector2i(1024, 768), &"en", 1.3]]


## `openers`: {name: Callable that opens the view}. Returns the problems
## ("1024x768 da 100%: logbook off screen (rect)"); the settings and the
## window are restored.
static func problems(t: Node, app: Node, openers: Dictionary) -> Array[String]:
	var root := t.get_tree().root
	var original := root.size
	var out: Array[String] = []
	for setup: Array in SETUPS:
		root.size = setup[0]
		SettingsManager.set_language(setup[1])
		SettingsManager.set_ui_scale(setup[2])
		await t.frames(3)
		var label := "%dx%d %s %d%%" % [setup[0].x, setup[0].y, setup[1], roundi(float(setup[2]) * 100.0)]
		var screen := app.get_viewport().get_visible_rect().grow(1.5)
		for view_name: String in openers:
			app.modals.clear()
			await t.frames(1)
			(openers[view_name] as Callable).call()
			await t.frames(4)
			var modal := app.modals.get_top() as Control
			var panel := modal.find_child("Panel", true, false) as Control if modal else null
			if panel == null:
				out.append("%s: %s did not open" % [label, view_name])
				continue
			# The open animation scales the panel from 94 %: measure it settled.
			panel.scale = Vector2.ONE
			var rect := panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)
			if modal.has_node(^"FocusFrame"):
				rect = rect.grow(FocusFrame.MARGIN)
			if not screen.encloses(rect):
				out.append("%s: %s off screen %s" % [label, view_name, rect])
		app.modals.clear()
	SettingsManager.set_ui_scale(1.0)
	SettingsManager.set_language(&"en")
	root.size = original
	await t.frames(2)
	return out
