extends Node
## The diagnostic session log (Visual Identity V01): a small technical record
## of what happened in one run of the game, to help investigate unexpected
## behaviour during test sessions. It is not the player's Captain's Log.
##
## One file per session, JSON Lines (one JSON object per line), in
## user://diagnostics/ (Windows: %APPDATA%\Little Captains Hat\diagnostics\).
## Every line has "t" (UTC wall clock), "event", and, while a game runs, "game"
## (game time). Only meaningful events are written, never per frame: session
## start (version, commit, engine, OS), screen changes, saving and loading,
## the captain's hat, achievements and renown, voyages, rescues, money and
## errors reported by the engine or scripts. No names, paths in the user's
## home or other personal data are written.
##
## Bounded: at most MAX_LINES lines or MAX_BYTES per file, and only the newest
## KEEP_FILES files are kept. Every line is flushed at once, so a crash or a
## freeze keeps everything written before it. Reading the game never changes
## it, so the simulation is unaffected.

const DEFAULT_DIR := "user://diagnostics"
const MAX_LINES := 5000
const MAX_BYTES := 1_000_000
const KEEP_FILES := 10

## Folder of the log files (tests point it elsewhere before restart()).
var log_dir := DEFAULT_DIR
var enabled := true

var _file: FileAccess
var _path := ""
var _lines := 0
var _bytes := 0
var _truncated := false
var _mutex := Mutex.new()
var _logger: _ErrorLogger


## Engine and script errors go to the log too (Godot 4.5+ Logger).
class _ErrorLogger extends Logger:
	var log: Node

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtrace: Array) -> void:
		if log == null or error_type == ERROR_TYPE_WARNING:
			return
		var message := rationale if not rationale.is_empty() else code
		# May run on any thread: no game state is read for these lines.
		log.write("error", {"message": message.left(400), "where": "%s:%d %s" % [file.get_file(), line, function]}, false)

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_cmdline_user_args().has("--no-session-log"):
		enabled = false
	restart()
	_logger = _ErrorLogger.new()
	_logger.log = self
	OS.add_logger(_logger)
	_connect_game()


func _exit_tree() -> void:
	if _logger:
		OS.remove_logger(_logger)
		_logger.log = null
	write("session_end", {})
	_close()


## Starts a new log file (the previous one, if any, is closed).
func restart() -> void:
	_close()
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(log_dir)
	_prune()
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	_path = log_dir.path_join("session_%s_%03d.jsonl" % [stamp, Time.get_ticks_msec() % 1000])
	_file = FileAccess.open(_path, FileAccess.WRITE)
	_lines = 0
	_bytes = 0
	_truncated = false
	if _file == null:
		push_warning("The diagnostic log could not be opened at %s." % _path)
		return
	write("session_start", {"game": GameVersion.DISPLAY_NAME, "version": GameVersion.DISPLAY, "commit": GameVersion.get_commit(),
		"save_format": SaveManager.SAVE_VERSION, "engine": Engine.get_version_info().string, "os": OS.get_name(),
		"debug": OS.is_debug_build(), "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))})


## This session's file (absolute path), or "" when logging is off.
func get_log_path() -> String:
	return ProjectSettings.globalize_path(_path) if not _path.is_empty() else ""


## The folder holding the logs (absolute path), for the player and tests.
func get_folder() -> String:
	return ProjectSettings.globalize_path(log_dir)


## Writes one event. `data` must be JSON-friendly (numbers, strings, bools,
## arrays, dictionaries). Thread-safe; never raises.
func write(event: String, data: Dictionary = {}, with_game_time := true) -> void:
	if not enabled:
		return
	_mutex.lock()
	if _file != null and not _truncated:
		var entry := {"t": Time.get_datetime_string_from_system(true) + "Z", "event": event}
		if with_game_time and GameSession.is_active():
			entry["game"] = Simulation.format_game_time(GameSession.get_game_time(), false)
		entry.merge(data)
		var line := JSON.stringify(entry)
		if _lines + 1 >= MAX_LINES or _bytes + line.length() + 1 >= MAX_BYTES:
			line = JSON.stringify({"t": entry.t, "event": "log_truncated", "lines": _lines})
			_truncated = true
		_file.store_line(line)
		_file.flush()
		_lines += 1
		_bytes += line.length() + 1
	_mutex.unlock()


func get_line_count() -> int:
	return _lines


func _close() -> void:
	_mutex.lock()
	if _file != null:
		_file.close()
		_file = null
	_mutex.unlock()


## Keeps only the newest KEEP_FILES - 1 logs, so the new one makes KEEP_FILES.
func _prune() -> void:
	var files := Array(DirAccess.get_files_at(log_dir)).filter(func(f: String) -> bool:
		return f.begins_with("session_") and f.ends_with(".jsonl"))
	files.sort()
	while files.size() >= KEEP_FILES:
		DirAccess.remove_absolute(log_dir.path_join(files.pop_front()))


# --- What is recorded -------------------------------------------------------------

func _connect_game() -> void:
	GameSession.session_started.connect(func() -> void: write("game_started", _game_summary()))
	GameSession.state_replaced.connect(func() -> void: write("game_loaded", _game_summary()))
	GameSession.session_ended.connect(func() -> void: write("game_ended", {}))
	GameSession.vessel_changed.connect(func(id: StringName) -> void: write("vessel_changed", {"vessel": String(id)}))
	GameSession.voyage_started.connect(func() -> void: write("voyage_started", {"to": String(GameSession.get_voyage_destination_id()),
		"nm": snappedf(GameSession.get_voyage_total_nm(), 0.1)}))
	GameSession.voyage_logged.connect(func(record: Dictionary, new_harbour: bool) -> void: write("voyage_logged", {
		"outcome": record.outcome, "from": record.from, "to": record.to, "nm": snappedf(float(record.nm), 0.1), "new_harbour": new_harbour}))
	GameSession.rescued.connect(func(info: Dictionary) -> void: write("rescued", {"fee": info.fee, "funds_after": info.funds_after}))
	GameSession.funds_changed.connect(func(funds: int) -> void: write("funds", {"funds": funds}))
	GameSession.renown_awarded.connect(func(awards: Array) -> void:
		for award: Dictionary in awards:
			write("achievement_unlocked" if award.get("secret", false) else "renown_awarded", {"id": award.id, "renown": award.reward}))
	GameSession.travel_update_published.connect(func(info: Dictionary) -> void: write("travel_update", {"renown": info.renown, "euros": info.euros}))
	GameSession.hat_changed.connect(func(status: StringName) -> void: write("hat", {"status": String(status), "area": String(GameSession.get_boat_area())}))
	GameSession.hat_warning.connect(func(_text: String) -> void: write("hat_warning", _hat_weather()))
	GameSession.hat_lost.connect(func(info: Dictionary) -> void: write("hat_lost", {"lost_count": info.lost_count, "serial": info.serial,
		"wind_kn": snappedf(float(info.wind_kn), 0.1), "gust_kn": snappedf(float(info.gust_kn), 0.1), "in_harbour": info.in_harbour,
		"open_water_nm": snappedf(float(info.open_water_nm), 0.1)}))
	# Iteration 13: life aboard (fishing, the galley, the anchor). One line per
	# event, never per frame.
	GameSession.fish_landed.connect(func(result: Dictionary) -> void: write("fish_landed", {"species": result.fish.species,
		"kg": result.fish.kg, "kept": result.kept, "new_species": result.new_species, "personal_best": result.personal_best,
		"exceptional": result.exceptional}))
	GameSession.meal_cooked.connect(func(result: Dictionary) -> void: write("meal", {"recipe": result.recipe, "minutes": result.minutes,
		"food_added": snappedf(float(result.food_added), 0.01), "fish": result.fish.size(), "evening": result.evening}))
	GameSession.anchor_changed.connect(func() -> void:
		var anchor := GameSession.get_anchor()
		write("anchor_state", {"active": anchor.active, "holding": String(anchor.holding), "scope": anchor.scope,
			"set": snappedf(anchor.set_quality, 0.01), "alarm": anchor.alarm, "dragged_nm": snappedf(anchor.dragged_nm, 0.001)}))
	# Iteration 14: chart recovery on load, boat care, the boatyard.
	GameSession.location_recovered.connect(func(info: Dictionary) -> void: write("location_recovered", info))
	# Revision 0.102b: life at anchor (one line per change or moment, never per frame).
	GameSession.anchor_life_changed.connect(func(settled: bool) -> void: write("anchor_ambience",
		{"active": settled, "phase": String(GameSession.get_day_phase()), "hour": snappedf(GameSession.get_local_hour(), 0.1)}))
	GameSession.anchor_moment.connect(func(kind: String, _text: String) -> void: write("anchor_moment", {"kind": kind}))
	GameSession.hat_bought.connect(func(info: Dictionary) -> void: write("hat_bought", {"price": info.price, "funds_after": info.funds_after,
		"serial": info.serial}))


func _game_summary() -> Dictionary:
	return {"vessel": String(GameSession.get_vessel_id()), "location": String(GameSession.get_location_id()),
		"status": String(GameSession.get_vessel_status()), "funds": GameSession.get_funds(), "hat": String(GameSession.get_hat_status())}


func _hat_weather() -> Dictionary:
	var here := Simulation.get_weather_at_vessel()
	return {"wind_kn": snappedf(here.speed_kn, 0.1), "gust_kn": snappedf(here.gust_kn, 0.1), "underway": GameSession.is_underway()}
