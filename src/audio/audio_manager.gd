extends Node
## Plays music, ambience, one-shot sound effects and UI feedback sounds on the
## correct audio buses. It owns no gameplay state and never decides *what* to
## play; scenes and menus ask it to play streams they provide.
##
## Players are created once and reused: one music player, one ambience player
## and a small round-robin pool for one-shots, so nothing is allocated per sound.
## Named loops (e.g. the engine) get one player each, created on first use;
## requesting a loop that is already playing only fades its volume, so it never
## restarts on a scene change.

const BUS_MUSIC := &"Music"
const BUS_AMBIENCE := &"Ambience"
const BUS_SFX := &"SFX"
const BUS_UI := &"UI"

const ONE_SHOT_POOL_SIZE := 8
## Volume treated as silent when fading loops in and out.
const SILENT_DB := -60.0

var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _music_loops := false
var _ambience_loops := false
var _music_tween: Tween
var _one_shots: Array[AudioStreamPlayer] = []
var _next_one_shot := 0
## Named loops: id -> {"player", "target_db", "tween", "stopping"}.
var _loops := {}


func _ready() -> void:
	# Menus and pause screens must keep their sound while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = _create_player("Music", BUS_MUSIC)
	_music.finished.connect(_on_music_finished)
	_ambience = _create_player("Ambience", BUS_AMBIENCE)
	_ambience.finished.connect(_on_ambience_finished)
	for i in ONE_SHOT_POOL_SIZE:
		_one_shots.append(_create_player("OneShot%d" % i, BUS_SFX))


## Stops every sound immediately (used before quitting).
func stop_all() -> void:
	_kill_music_tween()
	for id: StringName in _loops:
		_kill_loop_tween(_loops[id])
		_loops[id].stopping = false
		_loops[id].target_db = SILENT_DB
	_music_loops = false
	_ambience_loops = false
	for child in get_children():
		(child as AudioStreamPlayer).stop()


# --- Music -------------------------------------------------------------------

func play_music(stream: AudioStream, loop := true, fade_in := 0.0) -> void:
	if stream == null:
		return
	_kill_music_tween()
	_music_loops = loop
	_music.stream = stream
	_music.volume_db = -40.0 if fade_in > 0.0 else 0.0
	_music.play()
	if fade_in > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", 0.0, fade_in)


func stop_music(fade_out := 0.0) -> void:
	_kill_music_tween()
	_music_loops = false
	if fade_out <= 0.0 or not _music.playing:
		_music.stop()
		return
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -40.0, fade_out)
	_music_tween.tween_callback(_music.stop)


func is_music_playing() -> bool:
	return _music.playing


# --- Ambience ----------------------------------------------------------------

## Starts a looping ambience bed, replacing any current one. Requesting the
## stream that is already playing is a no-op so area changes do not restart it.
## `bus`: where it plays (I027 playtest: the deck's open-air wash is wind, so
## it plays on the Wind bus and follows the Wind volume; the cabin's bed stays
## on Ambience).
func play_ambience(stream: AudioStream, loop := true, bus: StringName = BUS_AMBIENCE) -> void:
	if stream == null:
		stop_ambience()
		return
	_ambience.bus = bus if AudioServer.get_bus_index(bus) >= 0 else BUS_AMBIENCE
	if _ambience.playing and _ambience.stream == stream:
		_ambience_loops = loop
		return
	_ambience_loops = loop
	_ambience.stream = stream
	_ambience.play()


func stop_ambience() -> void:
	_ambience_loops = false
	_ambience.stop()


func get_ambience_stream() -> AudioStream:
	return _ambience.stream if _ambience.playing else null


# --- Named loops ---------------------------------------------------------------

## Starts (or keeps) a seamless loop and fades it to `volume_db`. If the same
## stream is already playing under `id`, it is not restarted: only its volume
## is faded. Volume settings apply through the bus (SFX by default).
func play_loop(id: StringName, stream: AudioStream, volume_db := 0.0, fade := 0.0, bus := BUS_SFX) -> void:
	if stream == null:
		stop_loop(id, fade)
		return
	var loop: Dictionary = _loops.get(id, {})
	if loop.is_empty():
		var player := _create_player("Loop_%s" % id, bus)
		player.finished.connect(_on_loop_finished.bind(id))
		loop = {"player": player, "target_db": SILENT_DB, "tween": null, "stopping": false}
		_loops[id] = loop
	var player: AudioStreamPlayer = loop.player
	if not (player.playing and player.stream == stream):
		_kill_loop_tween(loop)
		player.bus = bus
		player.stream = stream
		player.volume_db = SILENT_DB if fade > 0.0 else volume_db
		player.play()
	loop.stopping = false
	_fade_loop(loop, volume_db, fade, false)


## Fades a loop out and stops it.
func stop_loop(id: StringName, fade := 0.0) -> void:
	var loop: Dictionary = _loops.get(id, {})
	if loop.is_empty() or (not loop.player.playing and not loop.stopping):
		return
	loop.stopping = true
	_fade_loop(loop, SILENT_DB, fade, true)


## True while the loop is playing and not fading out to stop.
func is_loop_playing(id: StringName) -> bool:
	var loop: Dictionary = _loops.get(id, {})
	return not loop.is_empty() and loop.player.playing and not loop.stopping


## The volume the loop is at or fading towards (SILENT_DB if not playing).
func get_loop_target_db(id: StringName) -> float:
	return _loops[id].target_db if is_loop_playing(id) else SILENT_DB


func get_loop_player(id: StringName) -> AudioStreamPlayer:
	return _loops[id].player if _loops.has(id) else null


# --- One-shots ---------------------------------------------------------------

func play_sfx(stream: AudioStream, volume_db := 0.0) -> void:
	play_one_shot(stream, BUS_SFX, volume_db)


func play_ui(stream: AudioStream, volume_db := 0.0) -> void:
	play_one_shot(stream, BUS_UI, volume_db)


## Plays a non-looping sound on any bus using the shared player pool. When all
## players are busy the oldest-started one is reused.
func play_one_shot(stream: AudioStream, bus: StringName, volume_db := 0.0) -> void:
	if stream == null:
		return
	var player := _take_one_shot_player()
	player.bus = bus
	player.stream = stream
	player.volume_db = volume_db
	player.play()


# --- Internals ---------------------------------------------------------------

func _take_one_shot_player() -> AudioStreamPlayer:
	for i in _one_shots.size():
		var index := (_next_one_shot + i) % _one_shots.size()
		if not _one_shots[index].playing:
			_next_one_shot = (index + 1) % _one_shots.size()
			return _one_shots[index]
	var player := _one_shots[_next_one_shot]
	_next_one_shot = (_next_one_shot + 1) % _one_shots.size()
	return player


func _create_player(player_name: String, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus
	add_child(player)
	return player


func _fade_loop(loop: Dictionary, volume_db: float, fade: float, stop_after: bool) -> void:
	_kill_loop_tween(loop)
	loop.target_db = volume_db
	var player: AudioStreamPlayer = loop.player
	if fade <= 0.0:
		player.volume_db = volume_db
		if stop_after:
			player.stop()
			loop.stopping = false
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", volume_db, fade)
	if stop_after:
		tween.tween_callback(func() -> void:
			player.stop()
			loop.stopping = false)
	loop.tween = tween


func _kill_loop_tween(loop: Dictionary) -> void:
	var tween: Tween = loop.tween
	if tween and tween.is_valid():
		tween.kill()
	loop.tween = null


func _on_loop_finished(id: StringName) -> void:
	# Streams imported without a loop point still loop.
	var loop: Dictionary = _loops[id]
	if not loop.stopping and loop.target_db > SILENT_DB:
		loop.player.play()


func _kill_music_tween() -> void:
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null


# Looping is done here rather than on the stream resource so any stream format
# can be used as a loop without editing its import settings.
func _on_music_finished() -> void:
	if _music_loops:
		_music.play()


func _on_ambience_finished() -> void:
	if _ambience_loops:
		_ambience.play()
