extends "res://tests/test_case.gd"
## MusicDirector node (src/audio/music_director.gd) and the Audio music additions it relies on:
## playback position, try_play_music, synchronised layers, finished non-looping pieces, cache
## eviction, the request/release wrappers used by the migrated call sites, the threat monitor's line
## of sight rule, and a director driven end to end with tiny fades (asserting Audio.current_music()).
## New .ogg compositions may or may not be imported yet: expectations are computed from what exists.

const MusicData := preload("res://data/music.gd")
const Director := preload("res://src/audio/music_director.gd")


class FakeEnemy extends Node3D:
	var threatening := true

	func is_threatening() -> bool:
		return threatening


class FakeSky extends Node:
	var is_night := false


class FakeArea extends Node:
	var sky: Node = null


class FakeGame extends Node:
	var area: Node = null


var _d: Node = null
var _was_enabled := true
var _saved: Dictionary = {}
var _cues: Array = []


func before_each() -> void:
	_saved = {}
	for k in ["master_volume", "music_volume"]:
		_saved[k] = Settings.get_value(k)
		Settings.set_value(k, 1.0)
	_was_enabled = Audio.music_director_active()
	Audio.set_music_director_enabled(false)
	Audio.stop_all()
	_cues = []
	if not Events.music_cue_changed.is_connected(_on_cue):
		Events.music_cue_changed.connect(_on_cue)
	await wait_frames(2)


func after_each() -> void:
	if _d != null and is_instance_valid(_d):
		_d.queue_free()
	_d = null
	if Events.music_cue_changed.is_connected(_on_cue):
		Events.music_cue_changed.disconnect(_on_cue)
	get_tree().paused = false
	var ad := Audio.music_director()
	if ad != null:
		ad.set("ctx_override", {})
		ad.set("fade_scale", 1.0)
	Audio.stop_all()
	await wait_seconds(0.05)
	Audio.set_music_director_enabled(_was_enabled)
	for k in _saved:
		Settings.set_value(k, _saved[k])


func _on_cue(cue: String) -> void:
	_cues.append(cue)


func _director(ctx: Dictionary, tuning: Dictionary = {}, seed_value: int = 3) -> Node:
	var t := {"rest_scale": 0.01, "region_enter_s": 0.2, "min_dwell_s": 0.2, "combat_enter_s": 0.1,
		"combat_release_s": [0.2, 0.3]}
	t.merge(tuning, true)
	var d: Node = Director.new()
	var params := {"fade_scale": 0.01, "tick_s": 0.05, "ctx": ctx, "tuning": t}
	if seed_value >= 0:
		params["seed"] = seed_value
	d.setup(params)
	add_child(d)
	_d = d
	return d


func _have(cue: String) -> bool:
	return Audio.has_sound(String(MusicData.CUES[cue]["track"]), true)


## Tracks a playlist can sound right now (its available cues, else its retained fallback, else "").
func _tracks(pl: String) -> Array:
	var p: Dictionary = MusicData.PLAYLISTS[pl]
	var out: Array = []
	for c in (p["cues"] as Array):
		if _have(String(c)):
			out.append(String(MusicData.CUES[c]["track"]))
	if out.is_empty():
		for f in (p.get("fallback", []) as Array):
			var fs := String(f)
			if fs == "" or fs == "keep":
				out.append(fs)
				break
			if _have(fs):
				out.append(String(MusicData.CUES[fs]["track"]))
				break
	return out


# --- Audio additions ------------------------------------------------------------------------------------

func test_audio_owns_one_director() -> void:
	var d := Audio.music_director()
	assert_not_null(d, "Audio creates the director")
	if d == null:
		return
	assert_eq(d.get_parent(), Audio, "child of the Audio autoload (outlives scenes)")
	assert_eq(d.process_mode, Node.PROCESS_MODE_ALWAYS, "keeps deciding while menus pause the tree")
	Audio.set_music_director_enabled(true)
	assert_true(Audio.music_director_active())
	Audio.set_music_director_enabled(false)
	assert_false(Audio.music_director_active())
	assert_eq(Audio._music_layers.players.size(), Audio.MUSIC_LAYERS, "bounded layer voices")
	for p in Audio._music_layers.players:
		assert_eq(String((p as AudioStreamPlayer).bus), "Music", "layers play on the Music bus")


func test_music_position_length_and_try_play() -> void:
	assert_eq(Audio.music_position(), -1.0, "nothing playing")
	assert_null(Audio.music_stream())
	Audio.play_music("music_haven", 0.01)
	await wait_seconds(0.5)
	var p := Audio.music_position()
	assert_true(p > 0.05 and p < 5.0, "position advances (%.3f)" % p)
	assert_almost(Audio.music_length(), 87.273, 0.05, "pass length")
	assert_not_null(Audio.music_stream())
	assert_false(Audio.try_play_music("definitely_not_music", 0.01), "missing track refused")
	assert_eq(Audio.current_music(), "music_haven", "... and the current music keeps playing")
	assert_true(Audio.try_play_music("music_haven", 0.01), "the same track is already playing")
	assert_true(Audio.music_position() >= p, "no restart")
	Audio.play_music("definitely_not_music", 0.01)
	assert_eq(Audio.current_music(), "", "play_music keeps its old contract (missing = stop)")


func test_layers_follow_the_base_track() -> void:
	Audio.play_music("music_boss", 0.01)
	await wait_seconds(0.4)
	var base_mix := float(Audio._music_mix_position())
	Audio.set_music_layers(["music_night"], 0.01)          # any existing loop stands in for a stem
	assert_eq(Audio.current_music_layers(), ["music_night"])
	var lp: AudioStreamPlayer = Audio._music_layers.players[0]
	assert_almost(lp.get_playback_position(), Audio.music_position(), 0.15, "the stem starts where the base track is")
	# lined up with the MIXER position of the base (both are mixed from the next step on), not the
	# latency-compensated audible one, which would start the stem one output latency late
	assert_almost(lp.get_playback_position(), base_mix, 0.03, "stem start = base mix position")
	Audio.set_music_layers(["music_night", "definitely_missing"], 0.01)
	assert_eq(Audio.current_music_layers(), ["music_night"], "a missing stem is skipped")
	await wait_seconds(0.2)
	assert_true(lp.playing, "stem playing")
	Audio.play_music("music_title", 0.01)                  # a new base track drops its stems
	await wait_seconds(0.3)
	assert_eq(Audio.current_music_layers(), [])
	assert_null(lp.stream, "stem released")
	Audio.play_music("music_boss", 0.01)
	await wait_seconds(0.1)
	Audio.set_music_layers(["music_night"], 0.01)
	Audio.stop_music(0.01)
	await wait_seconds(0.3)
	assert_eq(Audio.current_music_layers(), [], "stopping the music stops the stems")
	Audio.set_music_layers(["music_night"], 0.01)
	assert_eq(Audio.current_music_layers(), [], "no stems without a base track")


func test_finished_piece_releases_its_deck() -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(44100 / 4 * 2)                              # 0.25 s of silence
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	Audio._music.play("test_tone", wav, 0.01, 0.0)
	assert_eq(Audio.current_music(), "test_tone")
	await wait_seconds(1.0)
	assert_eq(Audio.current_music(), "", "a non-looping piece that ended reports silence")
	assert_eq(Audio.music_position(), -1.0)


func test_music_cache_is_evicted() -> void:
	Audio.get_stream("amb_mine")
	Audio.play_music("music_title", 0.01)
	await wait_seconds(0.1)
	Audio.play_music("music_haven", 0.01)
	await wait_seconds(0.4)
	assert_false(Audio._cache.has("music_title"), "a faded-out track leaves the cache")
	assert_true(Audio._cache.has("music_haven"), "the playing one stays")
	assert_true(Audio._cache.has("amb_mine"), "only music is evicted")
	Audio.prefetch_music("music_night")
	Audio.play_music("music_night", 0.01)
	assert_eq(Audio.current_music(), "music_night", "a prefetched track plays")
	assert_true(Audio._prefetching.is_empty(), "prefetch collected")


func test_unplayed_prefetches_do_not_pile_up() -> void:
	Audio.prefetch_music("music_ending")
	var first: Array = Audio._prefetching.keys()
	for i in 150:                                          # let the background load finish (<= 3 s)
		if first.is_empty() or ResourceLoader.load_threaded_get_status(String(first[0])) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			break
		await wait_seconds(0.02)
	Audio.prefetch_music("music_title")                    # the plan changed: the first one is not needed
	for p in first:
		assert_false(Audio._prefetching.has(p), "a finished, unplayed prefetch is collected (%s)" % p)
	assert_true(Audio._prefetching.size() <= 1, "at most the latest one is pending (%s)" % str(Audio._prefetching.keys()))
	Audio.stop_all()
	assert_true(Audio._prefetching.is_empty(), "stop_all (quit, back to the title) takes back the rest")


func test_unimported_files_are_not_indexed() -> void:
	# The new compositions arrive as plain .ogg files before anyone runs the importer: such a file
	# cannot load, so it must not count as a sound (the director then uses the fallbacks).
	var checked := 0
	for id in MusicData.cue_ids():
		var c: Dictionary = MusicData.CUES[id]
		var files: Array = [String(c["file"])]
		var names: Array = [String(c["track"])]
		files.append_array(c.get("layer_files", []))
		names.append_array(c.get("layers", []))
		for i in files.size():
			var f := String(files[i])
			if not FileAccess.file_exists(f):
				continue
			checked += 1
			var imported := FileAccess.file_exists(f + ".import")
			assert_eq(Audio.has_sound(String(names[i]), true), imported,
				"%s: on disk, %s -> %s" % [f.get_file(), "imported" if imported else "not imported", "a sound" if imported else "ignored"])
	assert_true(checked >= 5, "the retained pieces at least (%d files checked)" % checked)


func test_request_release_wrappers() -> void:
	# without an active director: exactly the old calls (legacy fallback)
	Audio.request_music("boss_matron", "music_boss", 0.01)
	assert_eq(Audio.current_music(), "music_boss", "fallback track")
	Audio.release_music("boss_matron", 0.01)
	assert_eq(Audio.current_music(), "", "fallback stop")
	Audio.request_music("title", "music_title", 0.01)
	Audio.release_music("", 0.01)
	assert_eq(Audio.current_music(), "", "release('') = stop_music without a director")
	# with the director: requests go to it (outside a running game it leaves the music alone)
	if Game.mode == "boot":
		Audio.set_music_director_enabled(true)
		Audio.request_music("boss_matron", "music_boss", 0.01)
		assert_eq(Audio.current_music(), "", "no direct play while the director owns the music")
		Audio.set_music_director_enabled(false)


# --- the director, end to end ---------------------------------------------------------------------------

func test_director_follows_areas_bosses_and_authored_scenes() -> void:
	var d := _director({"mode": "playing", "area": "surface", "zone": "haven", "night": false})
	await wait_seconds(0.3)
	var haven: Array = _tracks("haven_day")
	assert_true(haven.has(Audio.current_music()), "the Haven rotation plays (%s of %s)" % [Audio.current_music(), str(haven)])
	# Krystal goes down the mine: arrival changes are immediate
	d.ctx_override["area"] = "below"
	d.ctx_override["zone"] = "mine"
	await wait_seconds(0.3)
	var mine_track := String(_tracks("mine")[0])
	assert_eq(Audio.current_music(), mine_track, "the mine: The Last Shift, or silence until it exists")
	# the legacy Weaver shows its health bar -> boss music in the same frame
	Events.boss_health_changed.emit("weaver_matron", 200.0, 240.0)
	assert_eq(Audio.current_music(), "music_boss", "boss piece starts at once")
	assert_eq(String(_cues.back()) if not _cues.is_empty() else "", "m13", "music_cue_changed(m13)")
	Events.boss_health_changed.emit("weaver_matron", 180.0, 240.0)          # hits never restart it
	Events.boss_phase_changed.emit("weaver_matron", 2)
	await wait_frames(2)
	var want2: Array = ["m13_layer2"] if Audio.has_sound("m13_layer2", true) else []
	assert_eq(Audio.current_music_layers(), want2, "phase 2 stem (when composed)")
	Events.boss_phase_changed.emit("weaver_matron", 3)
	await wait_frames(2)
	var want3: Array = want2.duplicate()
	if Audio.has_sound("m13_layer3", true):
		want3.append("m13_layer3")
	assert_eq(Audio.current_music_layers(), want3, "phase 3 stems")
	assert_eq(Audio.current_music(), "music_boss", "phases never restart the base piece")
	Events.boss_health_changed.emit("weaver_matron", -1.0, 240.0)
	await wait_seconds(0.6)
	assert_eq(Audio.current_music(), mine_track, "after the fight the area's mood returns")
	assert_eq(Audio.current_music_layers(), [], "stems gone")
	# an authored ending outranks everything and is not restarted by a second request
	d.request("restoration", 0.5)
	assert_eq(Audio.current_music(), "music_ending", "The Heart Comes Home")
	d.request("restoration", 0.5)
	d.release("restoration", 0.5)
	await wait_seconds(0.3)
	assert_eq(Audio.current_music(), mine_track, "released")
	# the title
	d.ctx_override = {"mode": "title", "area": "", "zone": ""}
	d.request("title", 0.5)
	assert_eq(Audio.current_music(), "music_title")
	d.release("title", 0.5)
	await wait_seconds(0.2)
	assert_eq(Audio.current_music(), "", "the title fades before loading")
	assert_true(_cues.has("m01") and _cues.has("m14"), "cue events: %s" % str(_cues))
	var entries: Array = d.get_debug_log()
	assert_true(entries.size() >= 5 and entries.size() <= 50, "decision log (%d)" % entries.size())
	for e in entries:
		assert_true((e as Dictionary).has("action") and (e as Dictionary).has("reason"), "log entries explain themselves")


func test_director_context_inputs() -> void:
	var d := _director({"mode": "boot"})
	# day/night follows the area's sky when it has one (the surface ambience turns on sky.is_night)
	var g := FakeGame.new()
	var area := FakeArea.new()
	var sky := FakeSky.new()
	area.sky = sky
	g.area = area
	sky.is_night = true
	assert_true(bool(d._is_night(g)), "sky says night")
	sky.is_night = false
	assert_false(bool(d._is_night(g)), "sky says day")
	g.area = null
	assert_eq(bool(d._is_night(g)), bool(GameState.is_night()), "no sky: the game clock")
	sky.free()
	area.free()
	g.free()
	# the post-Chapter-Two Haven rotation follows the real completion flag
	var f := "chapter_two_complete"
	var had := GameState.flags.has(f)
	var prev: Variant = GameState.flags.get(f)
	GameState.flags[f] = false
	assert_false(bool(d.gather_context()["late"]), "before the ending")
	GameState.flags[f] = true
	assert_true(bool(d.gather_context()["late"]), "after Chapter Two: the late Haven playlist")
	if had:
		GameState.flags[f] = prev
	else:
		GameState.flags.erase(f)
	# an elite's encounter (no music of its own) never hides a boss
	Events.boss_encounter_changed.emit("weaver_matron", true)
	Events.boss_encounter_changed.emit("knotted_elder", true)
	assert_eq(String(d.gather_context()["boss"]), "weaver_matron", "the boss keeps its music")
	Events.boss_encounter_changed.emit("weaver_matron", false)
	assert_eq(String(d.gather_context()["boss"]), "", "elites are ordinary combat")
	Events.boss_encounter_changed.emit("knotted_elder", false)


## Authored silences (data/music.gd AUTHORED_SILENCE): the short Chapter Two moments get a shorter hush, the rest of
## the authored moments keep the default, and ordinary horror events ask for none.
func test_authored_silence_lengths() -> void:
	assert_almost(MusicData.authored_silence_seconds("authored:ta_echo"), 12.0, 0.001, "Tobin's annex echo")
	assert_almost(MusicData.authored_silence_seconds("authored:empty_waltz"), 15.0, 0.001, "the Empty Waltz")
	assert_almost(MusicData.authored_silence_seconds("authored:boss"), 0.0, 0.001, "bosses bring their own music")
	for id in ["authored:hw_knock", "authored:hw_wrong_door", "authored:hw_porch", "authored:threshold"]:
		assert_almost(MusicData.authored_silence_seconds(String(id)), MusicData.AUTHORED_SILENCE_DEFAULT, 0.001, String(id) + " keeps the default")
	assert_almost(MusicData.authored_silence_seconds("dir_creak"), 0.0, 0.001, "director events rely on the horror state")
	# The two moments really emit these ids.
	var annex: String = FileAccess.get_file_as_string("res://src/world/areas_ch2/tobin_annex_world.gd")
	assert_true(annex.contains("\"authored:ta_echo\""), "the annex emits authored:ta_echo")
	var waltz: Script = load("res://src/world/manor/waltz_moment.gd")
	assert_eq(String(waltz.get_script_constant_map().get("SILENCE_EVENT", "")), "authored:empty_waltz", "the waltz emits authored:empty_waltz")


func test_director_skips_cues_that_fail_to_load() -> void:
	if _have("m07") or _have("m08"):
		return      # the woods pieces exist now: nothing to simulate
	# pretend the woods pieces were there (e.g. an .ogg that is on disk but cannot load yet)
	var d: Node = Director.new()
	d.setup({"seed": 5, "fade_scale": 0.01, "tick_s": 0.05, "available": {"m07": true, "m08": true},
		"ctx": {"mode": "playing", "area": "surface", "zone": "", "night": false}})
	add_child(d)
	_d = d
	await wait_seconds(0.6)
	assert_eq(Audio.current_music(), "music_haven", "unloadable cues are skipped, the retained fallback plays")
	var notes := 0
	for e in d.get_debug_log():
		if String((e as Dictionary)["reason"]).begins_with("could not play"):
			notes += 1
	assert_eq(notes, 2, "each failing cue is tried once and noted")


func test_director_combat_from_events_and_release() -> void:
	var d := _director({"mode": "playing", "area": "surface", "zone": "", "night": false})
	await wait_seconds(0.3)
	var woods: Array = _tracks("woods")
	assert_true(woods.has(Audio.current_music()), "the woods (%s)" % Audio.current_music())
	Events.combat_state_changed.emit(true)          # e.g. an arena script
	await wait_seconds(1.0)
	var combat_track := String(MusicData.CUES["m10"]["track"])
	if _have("m10"):
		assert_eq(Audio.current_music(), combat_track, "Thorns in the Path")
	else:
		assert_true(woods.has(Audio.current_music()), "no combat piece yet: the woods continue")
	assert_true(bool(d.state()["combat"]), "combat state")
	Events.combat_state_changed.emit(false)
	await wait_seconds(1.0)
	assert_false(bool(d.state()["combat"]), "released")
	assert_true(woods.has(Audio.current_music()), "back to the woods (%s)" % Audio.current_music())


func test_director_menus_never_restart_the_music() -> void:
	var d := _director({"mode": "playing", "area": "surface", "zone": "haven", "night": false})
	await wait_seconds(0.3)
	var before := Audio.current_music()
	assert_ne(before, "")
	get_tree().paused = true
	d.ctx_override["zone"] = ""
	d.ctx_override["night"] = true
	await wait_seconds(0.8)
	assert_eq(Audio.current_music(), before, "paused: nothing changes")
	var pos := Audio.music_position()
	get_tree().paused = false
	d.ctx_override["zone"] = "haven"
	d.ctx_override["night"] = false
	await wait_seconds(0.3)
	assert_eq(Audio.current_music(), before, "unpausing does not restart it")
	assert_true(Audio.music_position() > pos, "it played on through the menu")


func test_director_leaves_the_global_rng_alone() -> void:
	seed(77)
	var expected := randi()
	seed(77)
	var d := _director({"mode": "playing", "area": "surface", "zone": "haven", "night": false}, {}, -1)
	await wait_seconds(0.3)
	d.ctx_override["zone"] = ""
	await wait_seconds(0.5)
	assert_eq(randi(), expected, "the director (clock-seeded) never draws from the global RNG")


func test_threat_needs_sight_or_engagement() -> void:
	var d := _director({"mode": "boot"})
	var root := Node3D.new()
	add_child(root)
	var player := Node3D.new()
	root.add_child(player)
	var enemy := FakeEnemy.new()
	enemy.add_to_group("enemy")
	root.add_child(enemy)
	enemy.position = Vector3(0, 0, -10)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 6, 0.6)
	cs.shape = box
	wall.add_child(cs)
	root.add_child(wall)
	wall.position = Vector3(0, 1, -5)
	await wait_physics(3)
	assert_false(d.scan_threat(player), "a stuck enemy behind a wall does not pin combat")
	wall.position = Vector3(40, 1, -5)
	await wait_physics(3)
	assert_true(d.scan_threat(player), "an enemy in sight within 20 m is a threat")
	wall.position = Vector3(0, 1, -5)
	await wait_physics(3)
	assert_false(d.scan_threat(player), "wall back")
	d.note_engaged()
	assert_true(d.scan_threat(player), "recent damage counts without line of sight")
	enemy.position = Vector3(0, 0, -25)
	assert_false(d.scan_threat(player), "too far away")
	enemy.position = Vector3(0, 0, -10)
	enemy.threatening = false
	assert_false(d.scan_threat(player), "not threatening")
	enemy.threatening = true
	enemy.add_to_group("stalker")
	assert_false(d.scan_threat(player), "the horror stalker is not ordinary combat")
	root.queue_free()
	await wait_frames(1)


## CH2-008: a boss that ends (defeated or fled) with nobody else threatening hands straight back to the area: no
## ordinary combat was latched underneath the fight, no combat cue plays after it, and the engagement grace the
## fight earned is gone (an enemy still around behind a wall no longer counts without sight).
func test_director_boss_end_leaves_no_combat_behind() -> void:
	var d := _director({"mode": "playing", "area": "moonveil_manor", "zone": "", "night": false},
		{"combat_release_s": [3.0, 3.0]})
	var root := Node3D.new()
	add_child(root)
	var player := Node3D.new()
	root.add_child(player)
	var enemy := FakeEnemy.new()
	enemy.add_to_group("enemy")
	root.add_child(enemy)
	enemy.position = Vector3(0, 0, -10)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 6, 0.6)
	cs.shape = box
	wall.add_child(cs)
	root.add_child(wall)
	wall.position = Vector3(0, 1, -5)
	await wait_seconds(0.3)
	# the Count's fight: he is the threat, and blows are traded
	Events.boss_encounter_changed.emit("count_velour", true)
	d.ctx_override["threat"] = true
	d.note_engaged()
	await wait_seconds(0.6)
	assert_eq(String(d.state()["effective"]), "velour", "the boss context plays")
	assert_false(bool(d.state()["combat"]), "no ordinary combat latched under the boss")
	await wait_physics(2)
	assert_true(d.scan_threat(player), "during the fight the engagement grace counts")
	# defeated: nothing threatens her any more
	_cues.clear()
	d.ctx_override["threat"] = false
	Events.boss_encounter_changed.emit("count_velour", false)
	assert_false(d.scan_threat(player), "the fight's engagement grace ended with the boss")
	await wait_seconds(0.8)
	assert_false(bool(d.state()["combat"]), "combat never latched after the boss")
	for c in _cues:
		var kind := String((MusicData.CUES.get(String(c), {}) as Dictionary).get("kind", ""))
		assert_ne(kind, "combat", "no combat cue after the boss (%s)" % str(_cues))
	assert_ne(String(d.state()["effective"]), "combat2", "not serving the combat context")
	root.queue_free()
	await wait_frames(1)


# --- migrated call sites (the Audio-owned director) --------------------------------------------------------

func test_migrated_call_sites_keep_their_behaviour() -> void:
	var ad := Audio.music_director()
	if ad == null:
		fail("no director")
		return
	Audio.set_music_director_enabled(true)
	ad.set("fade_scale", 0.01)
	# title_screen.gd: _ready / _fade_to_black
	ad.set("ctx_override", {"mode": "title", "area": "", "zone": ""})
	Audio.request_music("title", "music_title", 3.0)
	assert_eq(Audio.current_music(), "music_title", "title theme")
	Audio.release_music("title", 0.9)
	await wait_seconds(0.1)
	assert_eq(Audio.current_music(), "", "fades out before loading")
	# surface_world.play_restoration -> ending_screen.play -> ui_root.show_ending
	ad.set("ctx_override", {"mode": "cutscene", "area": "surface", "zone": "haven", "night": false})
	Audio.request_music("restoration", "music_ending", 1.5)
	assert_eq(Audio.current_music(), "music_ending", "restoration")
	Audio.request_music("restoration", "music_ending", 2.0)
	assert_eq(Audio.current_music(), "music_ending", "the ending screen does not restart it")
	Audio.release_music("restoration", 3.0)
	await wait_seconds(0.1)
	ad.set("ctx_override", {"mode": "playing", "area": "surface", "zone": "haven", "night": false})
	await wait_seconds(0.5)
	assert_true(_tracks("haven_day").has(Audio.current_music()), "then the Haven (%s)" % Audio.current_music())
	# below_world / weaver_boss: arrival, fight start (twice), defeat (released twice)
	ad.set("ctx_override", {"mode": "playing", "area": "below", "zone": "boss", "night": false})
	Audio.release_music("", 2.0)                     # below arrival: the director decides
	await wait_seconds(0.4)
	assert_eq(Audio.current_music(), "", "the silk/boss rooms have no music of their own")
	Audio.request_music("boss_matron", "music_boss", 2.0)
	assert_eq(Audio.current_music(), "music_boss", "fight starts")
	Audio.request_music("boss_matron", "music_boss", 1.5)
	Audio.release_music("boss_matron", 5.0)
	Audio.release_music("boss_matron", 4.0)
	await wait_seconds(0.2)
	assert_eq(Audio.current_music(), "", "defeat: the boss piece fades")
	Audio.request_music("boss_matron", "music_boss", 2.0)
	assert_eq(Audio.current_music(), "music_boss", "a retry starts it again")
	Audio.release_music("boss_matron", 1.5)          # death
	await wait_seconds(0.2)
	assert_eq(Audio.current_music(), "")
