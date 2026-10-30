extends RefCounted
## Regions and Harbours 2026: Captain Haddock's tools. The one rule (the
## Captain's name is exactly "Haddock", any case, trimmed); the name kept
## with the game (saved, loaded, an older save without it, renamed) and never
## in the settings. The exported build itself is checked by
## tests/haddock_probe.tscn (see its header): this suite runs in the editor,
## where the developers' own access is always on.

var t: Node


func run(runner: Node) -> void:
	t = runner
	var cases := {"Haddock": true, "haddock": true, "HADDOCK": true, "  Haddock ": true, "\tHaddock\n": true,
		"Captain Haddock": false, "Haddock123": false, "Haddocks": false, "Had dock": false, "": false, "Archibald": false}
	var wrong: Array[String] = []
	for name: String in cases:
		if DevTools.captain_unlocks(name) != cases[name]:
			wrong.append(name.c_escape())
	t.check(wrong.is_empty(), "[haddock] only 'Haddock' (any case, trimmed) opens the Captain's Tools (%s)" % [wrong])
	GameSession.start_new_session()
	t.check_eq(GameSession.get_captain_name(), "", "[haddock] a new game's Captain has no name until one is given")
	t.check(not DevTools.is_captain_unlocked(), "[haddock] no name: not unlocked")
	GameSession.set_captain_name("  Haddock ")
	t.check_eq(GameSession.get_captain_name(), "Haddock", "[haddock] the name is kept trimmed")
	t.check(DevTools.is_captain_unlocked(), "[haddock] named Haddock: unlocked")
	var saved := GameSession.get_state_snapshot().to_dict()
	t.check_eq(saved.get("captain_name"), "Haddock", "[haddock] the save holds the name")
	var errors: Array[String] = []
	var loaded := SessionState.from_dict(saved, errors)
	t.check(errors.is_empty() and loaded.captain_name == "Haddock", "[haddock] loading restores it")
	var older := saved.duplicate(true)
	older.erase("captain_name")
	var old_state := SessionState.from_dict(older, errors)
	t.check(errors.is_empty() and old_state.captain_name == "", "[haddock] an older save without a name loads, with none")
	older["captain_name"] = 42
	t.check_eq(SessionState.from_dict(older, errors).captain_name, "", "[haddock] a malformed name is ignored")
	GameSession.replace_state(old_state)
	t.check(not DevTools.is_captain_unlocked(), "[haddock] another save, another Captain: decided again")
	GameSession.set_captain_name("Captain Haddock")
	t.check(not DevTools.is_captain_unlocked(), "[haddock] renamed 'Captain Haddock': not unlocked")
	GameSession.set_captain_name("haddock")
	t.check(DevTools.is_captain_unlocked(), "[haddock] renamed 'haddock': unlocked")
	t.check_eq(SessionState.CAPTAIN_NAME_MAX, 40, "[haddock] names up to 40 characters")
	GameSession.set_captain_name("x".repeat(80))
	t.check_eq(GameSession.get_captain_name().length(), 40, "[haddock]   longer ones are cut there")
	t.check(not FileAccess.get_file_as_string(SettingsManager.settings_path).to_lower().contains("captain_name"),
		"[haddock] the name is never a global setting")
	t.check_eq(SaveManager.SAVE_VERSION, 12, "[haddock] the save format is unchanged (12)")
	GameSession.end_session()
