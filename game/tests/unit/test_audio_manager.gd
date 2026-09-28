extends "res://tests/test_case.gd"
## Audio autoload behaviour: bus volumes, ducking, voice limits and pooling, name resolution
## (aliases + arachnophobia), music/ambience crossfades, pause behaviour and missing sounds.

var _saved: Dictionary = {}


func before_each() -> void:
	_saved = {}
	for k in ["master_volume", "music_volume", "ambience_volume", "sfx_volume", "ui_volume", "arachnophobia"]:
		_saved[k] = Settings.get_value(k)
	Audio.min_retrigger_ms = 35


func after_each() -> void:
	get_tree().paused = false
	for k in _saved:
		Settings.set_value(k, _saved[k])
	Audio.min_retrigger_ms = 35
	Audio.stop_all()
	await wait_seconds(0.05)          # let the AudioServer release stopped playbacks


func _bus_db(bus: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


func _music_gain_total_except_active() -> float:
	var d = Audio._music
	var s := 0.0
	for i in d.gains.size():
		if i != d.active:
			s += float(d.gains[i])
	return s


# --- buses & volumes ------------------------------------------------------------------------

func test_buses_exist_with_master_limiter() -> void:
	for b in ["Music", "Ambience", "SFX", "UI"]:
		var idx := AudioServer.get_bus_index(b)
		assert_true(idx > 0, "bus %s exists" % b)
		if idx > 0:
			assert_eq(AudioServer.get_bus_send(idx), &"Master", "%s sends to Master" % b)
	var master := AudioServer.get_bus_index("Master")
	var has_lim := false
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			has_lim = true
	assert_true(has_lim, "master has a limiter")


func test_volume_settings_apply_to_buses() -> void:
	var cases := {"music_volume": "Music", "ambience_volume": "Ambience", "sfx_volume": "SFX", "ui_volume": "UI",
		"master_volume": "Master"}
	for key in cases:
		var bus: String = cases[key]
		Settings.set_value(key, 0.5)
		assert_almost(_bus_db(bus), linear_to_db(0.5) + Audio.get_duck_db(bus), 0.05, "%s at 50%%" % bus)
		assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)), "%s not muted at 50%%" % bus)
		Settings.set_value(key, 0.0)
		assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)), "%s muted at 0" % bus)
		Settings.set_value(key, 1.0)
		assert_almost(_bus_db(bus), 0.0 + Audio.get_duck_db(bus), 0.05, "%s at 100%%" % bus)


func test_duck_lowers_bus_and_recovers() -> void:
	Settings.set_value("music_volume", 1.0)
	Audio.duck("Music", -10.0, 0.25, 0.05, 0.1)
	await wait_seconds(0.15)
	assert_almost(Audio.get_duck_db("Music"), -10.0, 0.6, "fully ducked during hold")
	assert_almost(_bus_db("Music"), -10.0, 0.6, "bus volume includes the duck")
	await wait_seconds(0.5)
	assert_almost(Audio.get_duck_db("Music"), 0.0, 0.01, "duck released")
	assert_almost(_bus_db("Music"), 0.0, 0.05, "bus back to its setting")


func test_overlapping_ducks_use_the_deepest() -> void:
	Audio.duck("SFX", -4.0, 0.3, 0.02, 0.05)
	Audio.duck("SFX", -9.0, 0.3, 0.02, 0.05)
	await wait_seconds(0.12)
	assert_almost(Audio.get_duck_db("SFX"), -9.0, 0.5, "deepest duck wins")
	await wait_seconds(0.5)
	assert_almost(Audio.get_duck_db("SFX"), 0.0, 0.01, "both released")


func test_duck_ambience_keeps_its_contract() -> void:
	Audio.duck_ambience(-18.0, 3.2)
	await wait_seconds(1.8)
	assert_true(Audio.get_duck_db("Ambience") < -15.0, "ambience ducked (%.1f)" % Audio.get_duck_db("Ambience"))


# --- name resolution -----------------------------------------------------------------------------

func test_arachnophobia_swaps_spider_sounds() -> void:
	Settings.set_value("arachnophobia", false)
	assert_eq(Audio.resolve("weaver_rattle"), "weaver_rattle")
	assert_eq(Audio.resolve("dir_web_rustle"), "dir_web_rustle")
	Settings.set_value("arachnophobia", true)
	assert_eq(Audio.resolve("weaver_rattle"), "shade_telegraph")
	assert_eq(Audio.resolve("weaver_skitter"), "shade_drift")
	assert_eq(Audio.resolve("weaver_shriek"), "shade_shriek")
	assert_eq(Audio.resolve("dir_scratch"), "dir_scratch_soft")
	assert_eq(Audio.resolve("dir_web_rustle"), "dir_root_creak")
	assert_eq(Audio.resolve("weaver_telegraph"), "shade_telegraph", "aliases are swapped too")
	assert_eq(Audio.resolve("shade_drift"), "shade_drift", "alternatives stay themselves")
	Settings.set_value("arachnophobia", false)
	assert_eq(Audio.resolve("weaver_rattle"), "weaver_rattle", "swap follows the setting back")


func test_companion_voice_names_always_resolve() -> void:
	# companion.gd plays "<voice>_<kind>" for these kinds
	for prefix in ["mochi", "pebble", "lumi"]:
		for kind in ["happy", "chirp", "chime", "scared", "grunt", "warn", "clack", "notice", "celebrate", "dizzy"]:
			var n := "%s_%s" % [prefix, kind]
			var r := Audio.resolve(n)
			assert_true(r.begins_with(prefix + "_"), "%s -> %s keeps the companion's own voice" % [n, r])
	assert_eq(Audio.resolve("pebble_scared"), "pebble_grunt")
	assert_eq(Audio.resolve("lumi_scared"), "lumi_warn")
	assert_eq(Audio.resolve("mochi_chime"), "mochi_chirp")
	assert_eq(Audio.resolve("mochi_happy"), "mochi_happy", "real names resolve to themselves")


func test_surface_and_enemy_aliases() -> void:
	for s in ["grass", "stone", "wood", "water"]:
		assert_eq(Audio.resolve("step_" + s), "step_" + s)
	assert_eq(Audio.resolve("step_dirt"), "step_grass")
	assert_eq(Audio.resolve("step_somethingnew"), "step_grass", "unknown surfaces fall back")
	assert_eq(Audio.resolve("brambling_hurt"), "enemy_hurt")
	assert_eq(Audio.resolve("gloomling_defeat"), "enemy_defeat")
	assert_eq(Audio.resolve("step_grass_2"), "step_grass_2", "a specific variant can be requested")
	# data/enemies.gd gives voice prefixes ("sound": "gloomling"): a bare prefix plays its default voice
	assert_eq(Audio.resolve("gloomling"), "gloomling_hiss")
	assert_eq(Audio.resolve("brambling"), "brambling_chatter")
	assert_eq(Audio.resolve("shade"), "shade_whisper")


func test_missing_sounds_never_crash() -> void:
	assert_false(Audio.has_sound("definitely_not_a_sound"))
	assert_eq(Audio.resolve("definitely_not_a_sound"), "")
	assert_null(Audio.get_stream("definitely_not_a_sound"))
	Audio.play_sfx("definitely_not_a_sound")
	Audio.play_ui("definitely_not_a_sound", -3.0)
	assert_null(Audio.play_3d("definitely_not_a_sound", Vector3.ZERO), "play_3d returns null")
	Audio.play_music("definitely_not_music", 0.1)
	assert_eq(Audio.current_music(), "", "missing music leaves nothing playing")
	Audio.play_ambience("definitely_not_ambience", 0.1, 1)
	assert_eq(Audio.current_ambience(1), "")
	Audio.play_sfx("")
	Audio.play_music("", 0.1)
	Audio.stop_ambience(0.1, 5)
	Audio.play_ambience("amb_mine", 0.1, 99)      # out-of-range layer is clamped
	assert_eq(Audio.current_ambience(1), "amb_mine")
	Audio.duck("NoSuchBus", -6.0, 1.0)
	await wait_frames(3)
	assert_true(true, "reached the end without errors")


# --- voices & pooling ------------------------------------------------------------------------------

func test_footsteps_are_voice_limited() -> void:
	Audio.min_retrigger_ms = 0
	for i in 12:
		Audio.play_sfx("step_grass", -6.0, 0.1)
	assert_true(Audio.active_voices("step_grass") <= 2, "at most 2 overlapping footsteps (got %d)" % Audio.active_voices("step_grass"))
	assert_true(Audio.active_voices("step_grass") >= 1, "footstep is playing")
	for i in 12:
		Audio.play_3d("step_stone", Vector3(float(i), 0, 0), -6.0, 0.1, 18.0)
	assert_true(Audio.active_voices("step_stone") <= 2, "positional footsteps limited too")


func test_identical_requests_in_the_same_moment_merge() -> void:
	Audio.min_retrigger_ms = 35
	var a: Node = Audio.play_3d("pickup", Vector3.ZERO)
	var b: Node = Audio.play_3d("pickup", Vector3.ZERO)
	assert_not_null(a, "first plays")
	assert_null(b, "second (same frame) is merged")
	await wait_seconds(0.06)
	assert_not_null(Audio.play_3d("pickup", Vector3.ZERO), "plays again after the window")


func test_positional_players_are_pooled() -> void:
	Audio.min_retrigger_ms = 0
	var root: Node = Audio._world_root
	var before := root.get_child_count()
	var names := ["chop", "mine_hit", "pickup", "hit_soft", "grass_pull", "splash", "dig", "land"]
	for i in 60:
		var n: Node = Audio.play_3d(names[i % names.size()], Vector3(i, 1, 0), -20.0)
		assert_not_null(n, "play_3d returns a node")
		if n != null:
			assert_true(n is AudioStreamPlayer3D, "node is an AudioStreamPlayer3D")
			assert_eq(String(n.get("bus")), "SFX", "positional sounds use the SFX bus")
	assert_eq(root.get_child_count(), before, "no node created per sound")
	# a consumer that frees a returned node must not break the pool
	var victim: Node = Audio.play_3d("chop", Vector3.ZERO, -20.0)
	if victim != null:
		victim.free()
	for i in 40:
		Audio.play_3d(names[i % names.size()], Vector3.ZERO, -20.0)
	await wait_frames(1)
	var valid := 0
	for v in Audio._voices_3d:
		if is_instance_valid(v["p"]):
			valid += 1
	assert_eq(valid, Audio._voices_3d.size(), "freed players were replaced")


func test_play_3d_sets_position_and_range() -> void:
	var n: Node = Audio.play_3d("water_drip", Vector3(3, 4, 5), 0.0, 0.0, 40.0)
	assert_not_null(n)
	if n != null:
		var p := n as AudioStreamPlayer3D
		assert_eq(p.global_position, Vector3(3, 4, 5), "placed at the requested position")
		assert_almost(p.max_distance, 40.0, 0.001, "max distance applied")
		assert_almost(p.pitch_scale, 1.0, 0.0001, "pitch_var 0 keeps the pitch")


# --- music & ambience ----------------------------------------------------------------------------------

func test_music_crossfades_without_fighting() -> void:
	var d = Audio._music
	Audio.play_music("music_title", 0.2)
	assert_eq(Audio.current_music(), "music_title")
	await wait_seconds(0.1)
	var title_deck: int = d.active
	var g_before: float = d.gains[title_deck]
	Audio.play_music("music_title", 0.2)            # same request again: no restart
	assert_eq(Audio.current_music(), "music_title")
	assert_eq(int(d.active), title_deck, "same deck keeps playing")
	assert_true(float(d.gains[title_deck]) >= g_before, "no restart from silence")
	Audio.play_music("music_haven", 0.2)            # real crossfade: title fades out on its own deck
	assert_eq(Audio.current_music(), "music_haven")
	var haven_deck: int = d.active
	assert_ne(haven_deck, title_deck, "crossfade uses another deck")
	await wait_seconds(0.05)
	Audio.play_music("music_night", 0.2)            # rapid third change takes the quiet deck
	assert_ne(int(d.active), haven_deck, "third track on a free deck")
	await wait_seconds(0.03)
	Audio.play_music("music_haven", 0.2)            # and back: haven resumes from its current level
	assert_eq(int(d.active), haven_deck, "haven deck resumed instead of restarting")
	assert_eq(Audio.current_music(), "music_haven")
	await wait_seconds(0.5)
	assert_almost(float(d.gains[d.active]), 1.0, 0.001, "active deck fully up")
	assert_almost(_music_gain_total_except_active(), 0.0, 0.001, "other decks faded out")
	var audible := 0
	for i in d.players.size():
		if d.names[i] != "":
			audible += 1
	assert_eq(audible, 1, "exactly one music deck left")


func test_stop_music_fades_to_silence() -> void:
	Audio.play_music("music_boss", 0.05)
	await wait_seconds(0.15)
	Audio.stop_music(0.1)
	assert_eq(Audio.current_music(), "")
	await wait_seconds(0.3)
	var d = Audio._music
	for i in d.players.size():
		assert_almost(float(d.gains[i]), 0.0, 0.0001, "deck %d silent" % i)
		assert_null(d.players[i].stream, "deck %d released its stream" % i)


func test_ambience_layers_are_independent() -> void:
	Audio.play_ambience("amb_mine", 0.1, 0)
	Audio.play_ambience("amb_stream", 0.1, 1)
	assert_eq(Audio.current_ambience(0), "amb_mine")
	assert_eq(Audio.current_ambience(1), "amb_stream")
	Audio.play_ambience("amb_ruins", 0.1, 0)
	assert_eq(Audio.current_ambience(0), "amb_ruins", "layer 0 crossfades")
	Audio.stop_ambience(0.1, 0)
	assert_eq(Audio.current_ambience(0), "")
	assert_eq(Audio.current_ambience(1), "amb_stream", "layer 1 untouched")
	Audio.stop_ambience(0.1)
	assert_eq(Audio.current_ambience(1), "", "-1 stops every layer")


# --- pause ----------------------------------------------------------------------------------------------

func _voice_for(pool: Array, sound: String) -> Dictionary:
	for v in pool:
		if String(v["name"]) == sound and int(v["end"]) > Time.get_ticks_msec():
			return v
	return {}


func test_pause_holds_world_sounds_but_not_ui_or_music() -> void:
	Audio.min_retrigger_ms = 0
	Audio.play_sfx("tree_fall", -20.0)
	var pos := Audio.play_3d("lift_move", Vector3.ZERO, -20.0)
	Audio.play_music("music_night", 0.05)
	await wait_frames(1)
	get_tree().paused = true          # lands before the 3D player's first physics tick: must still hold
	await wait_physics(3)
	await wait_frames(2)
	var world := _voice_for(Audio._sfx_voices, "tree_fall")
	assert_false(world.is_empty(), "world sfx voice found")
	if not world.is_empty():
		assert_true(bool(world["p"].stream_paused), "world sfx paused")
	if pos != null:
		assert_true(bool(pos.get("stream_paused")), "positional sfx paused")
	Audio.play_ui("ui_click")
	Audio.play_sfx("pickup")                      # requested during pause = menu context
	await wait_frames(1)
	var ui := _voice_for(Audio._ui_voices, "ui_click")
	var menu_sfx := _voice_for(Audio._ui_voices, "pickup")
	assert_false(ui.is_empty(), "ui voice playing")
	assert_false(menu_sfx.is_empty(), "sfx requested while paused uses a never-paused voice")
	if not ui.is_empty():
		assert_false(bool(ui["p"].stream_paused), "UI keeps playing while paused")
	if not menu_sfx.is_empty():
		assert_eq(String(menu_sfx["p"].bus), "SFX", "still on the SFX bus")
	var d = Audio._music
	assert_eq(d.players[d.active].process_mode, Node.PROCESS_MODE_INHERIT, "music deck inherits ALWAYS from the autoload")
	assert_eq(Audio.process_mode, Node.PROCESS_MODE_ALWAYS, "audio autoload always processes")
	await wait_seconds(0.3)
	assert_true(Audio.get_duck_db("Ambience") < -1.0, "ambience dips while paused")
	get_tree().paused = false
	await wait_frames(2)
	if not world.is_empty():
		assert_false(bool(world["p"].stream_paused), "world sfx resumes")
	if pos != null:
		assert_false(bool(pos.get("stream_paused")), "positional sfx resumes")


func test_area_exit_stops_positional_sounds() -> void:
	Audio.min_retrigger_ms = 0
	Audio.play_3d("lift_move", Vector3.ZERO, -20.0)
	assert_eq(Audio.active_voices("lift_move"), 1)
	Events.area_exiting.emit("test_area")
	await wait_seconds(0.45)
	assert_eq(Audio.active_voices("lift_move"), 0, "positional sound faded out on area exit")


func test_area_exit_drops_sounds_held_by_the_pause() -> void:
	# e.g. pause menu -> "return home": a stinger/lift sound held by the pause must not resume later
	Audio.min_retrigger_ms = 0
	Audio.play_sfx("tree_fall", -30.0)
	Audio.play_3d("lift_move", Vector3.ZERO, -30.0)
	await wait_frames(1)
	get_tree().paused = true
	await wait_physics(2)
	await wait_frames(1)
	assert_eq(Audio.active_voices("tree_fall"), 1, "world sound held while paused")
	Events.area_exiting.emit("test_area")          # Game.load_area emits this while still paused
	get_tree().paused = false
	await wait_frames(2)
	assert_eq(Audio.active_voices("tree_fall"), 0, "held non-positional sound dropped, not resumed")
	var v := _voice_for(Audio._sfx_voices, "tree_fall")
	assert_true(v.is_empty(), "no live voice left for it")
	for w in Audio._sfx_voices:
		if String(w["name"]) == "tree_fall":
			assert_false(bool(w["p"].playing), "its player is stopped, not merely paused")
	await wait_seconds(0.45)
	assert_eq(Audio.active_voices("lift_move"), 0, "positional one faded out too")


func test_back_to_title_stops_gameplay_ambience_and_held_sounds() -> void:
	var saved_mode: String = Game.mode
	Game.mode = "cutscene"                # any gameplay mode (not "playing": that advances the clock)
	await wait_frames(2)
	Audio.min_retrigger_ms = 0
	Audio.play_ambience("amb_mine", 0.05, 0)
	Audio.play_ambience("amb_stream", 0.05, 1)
	Audio.play_music("music_boss", 0.05)
	Audio.play_sfx("tree_fall", -30.0)
	await wait_frames(1)
	get_tree().paused = true
	await wait_frames(2)
	# what Game.goto_title() does from the pause menu: mode, unpause, change scene (no area_exiting)
	Game.mode = "title"
	get_tree().paused = false
	await wait_frames(2)
	assert_eq(Audio.current_ambience(0), "", "gameplay ambience fades out on the title")
	assert_eq(Audio.current_ambience(1), "", "every layer")
	assert_eq(Audio.active_voices("tree_fall"), 0, "held world sound does not resume over the title")
	assert_eq(Audio.current_music(), "music_boss", "music is left to the title screen (it crossfades)")
	Audio.play_ambience("amb_forest_day", 0.05, 0)       # the title may choose its own bed
	await wait_frames(3)
	assert_eq(Audio.current_ambience(0), "amb_forest_day", "ambience started on the title stays")
	Game.mode = saved_mode
	await wait_frames(2)


func test_every_sound_can_be_played() -> void:
	Audio.min_retrigger_ms = 0
	for n in Audio.sound_names():
		var s := String(n)
		if s.begins_with("music_") or s.begins_with("amb_"):
			continue
		if s.length() > 3 and s[0] == "m" and s.substr(1, 2).is_valid_int() and s[3] == "_":
			continue   # Chapter Two music cues (m03_... m27_...) are music, not one-shots
		if s.begins_with("ui_"):
			Audio.play_ui(s, -30.0)
		else:
			Audio.play_3d(s, Vector3.ZERO, -30.0)
	await wait_frames(2)
	Audio.stop_world_sounds(0.0, true)
	assert_true(true, "played every one-shot without errors")
