extends RefCounted
## Visual Identity V01, Checkpoint E: the diagnostic session log. One JSON
## Lines file per session with meaningful events (start, saves and loads, the
## hat, achievements, money, voyages, errors), bounded in size and number of
## files, flushed at once, free of personal data and with no effect on the
## simulation.

const DIR := "user://test_diagnostics_suite"

var t: Node


func run(runner: Node) -> void:
	t = runner
	Simulation.auto_advance = false
	var previous_dir: String = SessionLog.log_dir
	_clean()
	SessionLog.log_dir = DIR
	SessionLog.restart()
	_test_start_line()
	_test_game_events()
	_test_errors_are_recorded()
	_test_no_personal_data()
	_test_simulation_unaffected()
	_test_bounded()
	_clean()
	SessionLog.log_dir = previous_dir
	SessionLog.restart()
	GameSession.end_session()
	t.use_calm_wind()


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for file in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(file))


func _entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for line in FileAccess.get_file_as_string(SessionLog.get_log_path()).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		result.append(parsed if parsed is Dictionary else {"event": "INVALID", "line": line})
	return result


func _events() -> Array[String]:
	var names: Array[String] = []
	for e in _entries():
		names.append(String(e.event))
	return names


func _test_start_line() -> void:
	var path := SessionLog.get_log_path()
	t.check(path.ends_with(".jsonl") and FileAccess.file_exists(path), "[log] one JSON Lines file per session in the diagnostics folder")
	var first := _entries()[0]
	t.check(first.event == "session_start" and first.version == GameVersion.DISPLAY and GameVersion.DISPLAY == "0.109a" and first.has("commit") and first.save_format == 12
		and String(first.engine).begins_with("4.7"), "[log] it starts with the game version, commit, save format and engine")
	t.check(String(first.t).ends_with("Z"), "[log] times are UTC")
	t.check(SessionLog.get_folder().ends_with("test_diagnostics_suite"), "[log] the folder can be located (%s)" % SessionLog.get_folder())


func _test_game_events() -> void:
	GameSession.start_new_session()
	t.set_wind(270.0, 48.0)
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	GameSession.use_hat_hook()
	for i in 60:
		Simulation.advance(60.0)
		if GameSession.get_hat_status() == HatState.LOST:
			break
	GameSession.buy_hat()
	SaveManager.save_to_slot(3, GameSession.get_state_snapshot())
	SaveManager.load_from_slot(3)
	SaveManager.load_from_slot(2)
	SaveManager.delete_slot(3)
	var events := _events()
	for expected in ["game_started", "hat", "hat_warning", "hat_lost", "achievement_unlocked", "hat_bought", "funds", "save", "load"]:
		t.check(expected in events, "[log] records %s" % expected)
	var lost: Dictionary = _entries().filter(func(e: Dictionary) -> bool: return e.event == "hat_lost")[0]
	t.check(lost.has("game") and float(lost.wind_kn) == 48.0 and lost.lost_count == 1, "[log] a hat loss with game time and wind: %s" % JSON.stringify(lost))
	var loads := _entries().filter(func(e: Dictionary) -> bool: return e.event == "load")
	t.check(loads.size() == 2 and loads[0].result == "ok" and loads[1].result == "failed", "[log] loads are recorded with their result")
	var invalid := events.filter(func(e: String) -> bool: return e == "INVALID")
	t.check(invalid.is_empty(), "[log] every line is valid JSON")
	var per_frame := events.filter(func(e: String) -> bool: return e == "hat").size()
	t.check(per_frame <= 3, "[log] nothing is logged per frame or per check (%d hat lines for 3 changes)" % per_frame)


func _test_errors_are_recorded() -> void:
	push_error("diagnostic log self-test: this error is expected")
	var errors := _entries().filter(func(e: Dictionary) -> bool: return e.event == "error")
	t.check(not errors.is_empty() and String(errors[errors.size() - 1].message).contains("this error is expected"),
		"[log] errors reported by scripts or the engine are recorded")


func _test_no_personal_data() -> void:
	var text := FileAccess.get_file_as_string(SessionLog.get_log_path())
	var home := OS.get_environment("HOME") if not OS.get_environment("HOME").is_empty() else OS.get_environment("USERPROFILE")
	var user := OS.get_environment("USER") if not OS.get_environment("USER").is_empty() else OS.get_environment("USERNAME")
	t.check((home.is_empty() or not text.contains(home)) and (user.length() < 3 or not text.contains("/" + user)),
		"[log] no home folder or user name is written")


func _run_hat() -> float:
	GameSession.start_new_session()
	t.set_wind(270.0, 48.0)
	GameSession.enter_boat_area(SessionState.AREA_EXTERIOR, &"start")
	GameSession.use_hat_hook()
	Simulation.advance(3600.0)
	return GameSession.get_hat().history[0].time if not GameSession.get_hat().history.is_empty() else -1.0


func _test_simulation_unaffected() -> void:
	var with_log := _run_hat()
	SessionLog.enabled = false
	var without := _run_hat()
	SessionLog.enabled = true
	t.check(with_log > 0.0 and with_log == without, "[log] the game plays exactly the same with or without the log")


func _test_bounded() -> void:
	for i in 12:
		var f := FileAccess.open(DIR.path_join("session_2000-01-01T00-00-%02d_000.jsonl" % i), FileAccess.WRITE)
		f.store_line("{}")
		f.close()
	SessionLog.restart()
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))
	t.check_eq(files.size(), SessionLog.KEEP_FILES, "[log] only the newest %d session files are kept" % SessionLog.KEEP_FILES)
	t.check(not files.has("session_2000-01-01T00-00-00_000.jsonl"), "[log] the oldest are removed first")
	for i in SessionLog.MAX_LINES + 50:
		SessionLog.write("test_line", {"i": i})
	var lines := FileAccess.get_file_as_string(SessionLog.get_log_path()).split("\n", false)
	t.check(lines.size() <= SessionLog.MAX_LINES and String(lines[lines.size() - 1]).contains("log_truncated"),
		"[log] a session file stops at %d lines with a note (%d lines)" % [SessionLog.MAX_LINES, lines.size()])
	t.check(FileAccess.get_file_as_bytes(SessionLog.get_log_path()).size() < SessionLog.MAX_BYTES, "[log] and stays under 1 MB")
