extends RefCounted
## Settings persistence and validation, bus volumes, and the audio manager.


func run(t: Node) -> void:
	var path: String = t.TEST_SETTINGS_PATH
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_volume(&"Music"), SettingsManager.DEFAULT_VOLUMES[&"Music"], "missing file gives default volumes")
	t.check_eq(SettingsManager.get_window_mode(), SettingsManager.DEFAULT_WINDOW_MODE, "missing file gives default window mode")

	# Buses exist and volumes reach them immediately.
	for bus: StringName in SettingsManager.AUDIO_BUSES:
		t.check(AudioServer.get_bus_index(bus) >= 0, "audio bus exists: %s" % bus)
	for bus: StringName in [&"Music", &"Ambience", &"SFX", &"UI"]:
		t.check_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)), &"Master", "%s routes to Master" % bus)
	SettingsManager.set_volume(&"SFX", 50)
	var sfx := AudioServer.get_bus_index(&"SFX")
	t.check(absf(AudioServer.get_bus_volume_db(sfx) - linear_to_db(0.5)) < 0.01, "50%% sets the SFX bus to %.1f dB" % linear_to_db(0.5))
	t.check(not AudioServer.is_bus_mute(sfx), "non-zero volume is not muted")
	SettingsManager.set_volume(&"SFX", 0)
	t.check(AudioServer.is_bus_mute(sfx), "0% mutes the bus")
	SettingsManager.set_volume(&"SFX", 140)
	t.check_eq(SettingsManager.get_volume(&"SFX"), 100, "volume is clamped to 100%")

	# Persistence round trip.
	SettingsManager.set_volume(&"Music", 25)
	SettingsManager.set_volume(&"UI", 0)
	SettingsManager.set_vsync(false)
	SettingsManager.set_window_mode(SettingsManager.WINDOW_BORDERLESS)
	SettingsManager.set_ui_scale(1.2)
	t.check_eq(SettingsManager.save(), OK, "settings save to disk")
	SettingsManager.restore_defaults()
	t.check_eq(SettingsManager.get_volume(&"Music"), 70, "restore defaults resets volumes")
	t.check_eq(SettingsManager.get_vsync(), true, "restore defaults resets VSync")
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_volume(&"Music"), 25, "music volume survives a reload")
	t.check_eq(SettingsManager.get_volume(&"UI"), 0, "muted UI volume survives a reload")
	t.check_eq(SettingsManager.get_vsync(), false, "VSync survives a reload")
	# The wind's own volume (I022): 100 % by default (the earlier balance), kept across a restart.
	t.check_eq(SettingsManager.DEFAULT_VOLUMES[&"Wind"], 100, "the wind's default keeps the earlier sound balance (0 dB)")
	SettingsManager.set_volume(&"Wind", 35)
	t.check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Wind")) - linear_to_db(0.35)) < 0.01, "the Wind slider sets the Wind bus at once")
	SettingsManager.save()
	SettingsManager.restore_defaults()
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_volume(&"Wind"), 35, "the wind volume survives a restart")
	t.check_eq(SettingsManager.get_window_mode(), SettingsManager.WINDOW_BORDERLESS, "window mode survives a reload")
	t.check(is_equal_approx(SettingsManager.get_ui_scale(), 1.2), "UI scale survives a reload")

	# Snapshots let the menu revert previews.
	var snapshot := SettingsManager.snapshot()
	SettingsManager.set_volume(&"Master", 5)
	SettingsManager.restore_snapshot(snapshot)
	t.check_eq(SettingsManager.get_volume(&"Master"), snapshot.volumes[&"Master"], "snapshot restores previewed values")

	# Invalid values fall back to defaults or are clamped.
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('[audio]\nmaster="loud"\nmusic=250\n[display]\nwindow_mode="cinema"\nvsync=3\n[interface]\nui_scale=9.0\n')
	file.close()
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_volume(&"Master"), 80, "non-numeric volume falls back to default")
	t.check_eq(SettingsManager.get_volume(&"Music"), 100, "out-of-range volume is clamped")
	t.check_eq(SettingsManager.get_window_mode(), SettingsManager.WINDOW_WINDOWED, "unknown window mode falls back")
	t.check_eq(SettingsManager.get_vsync(), true, "non-boolean VSync falls back")
	t.check_eq(SettingsManager.get_ui_scale(), SettingsManager.UI_SCALE_MAX, "UI scale is clamped")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("this is [not a config")
	file.close()
	SettingsManager.load_settings()
	t.check_eq(SettingsManager.get_volume(&"Ambience"), 70, "unreadable settings file gives defaults")
	SettingsManager.restore_defaults()
	DirAccess.remove_absolute(path)

	# Display modes can only be verified with a real window (not headless).
	if DisplayServer.get_name() != "headless":
		var expected := {
			SettingsManager.WINDOW_FULLSCREEN: DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
			SettingsManager.WINDOW_BORDERLESS: DisplayServer.WINDOW_MODE_FULLSCREEN,
			SettingsManager.WINDOW_WINDOWED: DisplayServer.WINDOW_MODE_WINDOWED,
		}
		for mode: StringName in expected:
			SettingsManager.set_window_mode(mode)
			await t.frames(10)
			t.check_eq(DisplayServer.window_get_mode(), expected[mode], "window mode '%s' is applied" % mode)
		# Some drivers (e.g. software GL under Xvfb) refuse swap control and
		# always report VSync as disabled; only test where it can work.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED:
			SettingsManager.set_vsync(false)
			t.check_eq(DisplayServer.window_get_vsync_mode(), DisplayServer.VSYNC_DISABLED, "VSync off is applied")
			SettingsManager.set_vsync(true)
			t.check_eq(DisplayServer.window_get_vsync_mode(), DisplayServer.VSYNC_ENABLED, "VSync on is applied")
		else:
			print("  SKIP VSync checks: this display driver does not support VSync control")
		var size := DisplayServer.window_get_size()
		t.check(size.x <= SettingsManager.WINDOWED_SIZE.x and size.y <= SettingsManager.WINDOWED_SIZE.y,
			"returning to windowed mode restores a sensible window size (%s)" % size)
	else:
		print("  (skipped window mode checks: headless display)")

	# Audio manager: fixed player pool, correct buses, ambience replacement.
	var blip: AudioStream = load("res://assets/audio/placeholder/test_sfx_blip.wav")
	var deck: AudioStream = load("res://assets/audio/placeholder/placeholder_ambience_deck.wav")
	var cabin: AudioStream = load("res://assets/audio/placeholder/placeholder_ambience_cabin.wav")
	var players_before := AudioManager.get_child_count()
	for i in 30:
		AudioManager.play_sfx(blip)
	AudioManager.play_ui(blip)
	t.check_eq(AudioManager.get_child_count(), players_before, "one-shots reuse a fixed player pool")
	var buses := {}
	for child in AudioManager.get_children():
		buses[(child as AudioStreamPlayer).bus] = true
	t.check(buses.has(&"Music") and buses.has(&"Ambience") and buses.has(&"SFX") and buses.has(&"UI"),
		"audio players are routed to Music, Ambience, SFX and UI buses")
	AudioManager.play_ambience(deck)
	t.check(AudioManager.get_ambience_stream() == deck, "ambience starts")
	AudioManager.play_ambience(cabin)
	t.check(AudioManager.get_ambience_stream() == cabin, "ambience is replaced")
	AudioManager.stop_ambience()
	t.check(AudioManager.get_ambience_stream() == null, "ambience stops")
	AudioManager.play_music(load("res://assets/audio/placeholder/test_music_arpeggio.wav"), false)
	t.check(AudioManager.is_music_playing(), "music plays")
	AudioManager.stop_music()
	t.check(not AudioManager.is_music_playing(), "music stops")
