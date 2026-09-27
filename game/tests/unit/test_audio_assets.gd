extends "res://tests/test_case.gd"
## Generated audio assets (tools/audio/generate_all.py): every sound name consumers may call exists
## and loads, variants exist where the design asks for them, loops are imported as forward loops,
## one-shots are mono and never loop.

const UI := ["ui_click", "ui_hover", "ui_open", "ui_close", "ui_error", "ui_craft", "ui_quest", "ui_notify",
	"ui_befriend", "ui_bond", "ui_save"]
const SFX := [
	"step_grass", "step_stone", "step_wood", "step_water", "jump", "land", "dodge", "swing", "hurt", "eat",
	"lantern_on", "lantern_off", "death",
	"chop", "tree_fall", "mine_hit", "rock_break", "pickup", "grass_pull", "berry_pick", "splash",
	"build_place", "build_remove", "build_invalid", "dig", "harvest_crop", "chest_open", "chest_close", "sleep",
	"hit_soft", "hit_hard", "enemy_hurt", "enemy_defeat", "brambling_chatter", "brambling_telegraph",
	"gloomling_hiss", "gloomling_telegraph", "gloomling_alert", "gloomling_flinch", "weaver_rattle",
	"weaver_skitter", "weaver_shriek", "weaver_drop", "shade_whisper", "shade_telegraph", "shade_drift",
	"shade_shriek", "brazier_light", "heartseed_pulse",
	"mochi_chirp", "mochi_happy", "mochi_scared", "pebble_clack", "pebble_happy", "pebble_grunt",
	"lumi_chime", "lumi_happy", "lumi_warn", "fake_lumi_chime",
	"ward_hum", "ward_restore", "door_creak", "gate_unlock", "lift_move", "checkpoint_light", "water_drip", "mine_cart",
	"dir_distant_pickaxe", "dir_creak", "dir_footsteps", "dir_pebbles", "dir_whisper", "dir_wrong_squeak",
	"dir_flicker", "dir_scratch", "dir_scratch_soft", "dir_web_rustle", "dir_root_creak", "stinger_soft", "stinger_major",
]
const AMBIENCE := ["amb_forest_day", "amb_forest_night", "amb_stream", "amb_mine", "amb_ruins", "amb_silk", "amb_boss"]
const MUSIC := ["music_title", "music_haven", "music_night", "music_boss", "music_ending"]

## Minimum variant counts for frequently repeated sounds.
const VARIANTS := {"step_grass": 4, "step_stone": 4, "step_wood": 4, "step_water": 4, "chop": 3, "mine_hit": 3,
	"pickup": 2, "hit_soft": 3, "hit_hard": 3, "enemy_hurt": 3, "swing": 3,
	"mochi_chirp": 3, "mochi_happy": 3, "mochi_scared": 3, "pebble_clack": 3, "pebble_happy": 3, "pebble_grunt": 3,
	"lumi_chime": 3, "lumi_happy": 3}


func _path_exists(dir: String, file_stem: String) -> bool:
	return ResourceLoader.exists("res://assets/audio/%s/%s.wav" % [dir, file_stem]) \
		or ResourceLoader.exists("res://assets/audio/%s/%s.ogg" % [dir, file_stem])


func _variant_count(dir: String, name: String) -> int:
	var n := 0
	if _path_exists(dir, name):
		n += 1
	for i in range(1, 9):
		if _path_exists(dir, "%s_%d" % [name, i]):
			n += 1
	return n


func _wav(dir: String, name: String) -> AudioStreamWAV:
	for stem in [name, name + "_1"]:
		var p := "res://assets/audio/%s/%s.wav" % [dir, stem]
		if ResourceLoader.exists(p):
			return load(p) as AudioStreamWAV
	return null


func test_every_required_name_exists_and_loads() -> void:
	var groups := {"ui": UI, "sfx": SFX, "ambience": AMBIENCE, "music": MUSIC}
	var total := 0
	for dir in groups:
		for n in groups[dir]:
			total += 1
			assert_true(Audio.has_sound(n, true), "has_sound('%s') (exact file)" % n)
			assert_true(_variant_count(dir, n) >= 1, "%s is in assets/audio/%s" % [n, dir])
			var s: AudioStream = Audio.get_stream(n)
			assert_not_null(s, "stream for %s loads" % n)
			if s != null:
				assert_true(s.get_length() > 0.02, "%s has audio (%.3fs)" % [n, s.get_length()])
	assert_eq(total, 11 + 80 + 7 + 5, "required name count matches docs/ARCHITECTURE.md")


func test_variants_exist_for_repeated_sounds() -> void:
	for n in VARIANTS:
		var c := _variant_count("sfx", n)
		assert_true(c >= int(VARIANTS[n]), "%s has %d variants (want >= %d)" % [n, c, VARIANTS[n]])


func test_every_indexed_file_loads() -> void:
	var names := Audio.sound_names()
	assert_true(names.size() >= 103, "index lists the generated sounds (%d)" % names.size())
	for n in names:
		assert_not_null(Audio.get_stream(String(n)), "loads: " + String(n))


func test_loops_are_forward_loops() -> void:
	for dir in ["ambience", "music"]:
		for n in (AMBIENCE if dir == "ambience" else MUSIC):
			var w := _wav(dir, n)
			assert_not_null(w, "%s is an AudioStreamWAV" % n)
			if w == null:
				continue
			assert_eq(w.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops forward" % n)
			assert_eq(w.loop_begin, 0, "%s loop starts at 0" % n)
			var frames := int(round(w.get_length() * float(w.mix_rate)))
			assert_true(w.loop_end > frames - 3 and w.loop_end <= frames, "%s loop covers the whole file (%d of %d)" % [n, w.loop_end, frames])
			assert_true(w.stereo, "%s is stereo" % n)
			assert_eq(w.mix_rate, 44100, "%s is 44.1 kHz" % n)


func test_loop_lengths_match_the_brief() -> void:
	for n in AMBIENCE:
		var w := _wav("ambience", n)
		if w != null:
			assert_true(w.get_length() >= 44.0 and w.get_length() <= 91.0, "%s is 45-90 s (%.1f)" % [n, w.get_length()])
	var ranges := {"music_title": [68.0, 92.0], "music_haven": [80.0, 95.0], "music_night": [50.0, 100.0],
		"music_boss": [55.0, 65.0], "music_ending": [74.0, 101.0]}
	for n in ranges:
		var w := _wav("music", n)
		if w != null:
			var r: Array = ranges[n]
			assert_true(w.get_length() >= float(r[0]) and w.get_length() <= float(r[1]), "%s length %.1f s" % [n, w.get_length()])


func test_one_shots_are_mono_and_do_not_loop() -> void:
	for pair in [["ui", UI], ["sfx", SFX]]:
		for n in pair[1]:
			var w := _wav(String(pair[0]), n)
			if w == null:
				fail("%s is not a WAV" % n)
				continue
			assert_eq(w.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s must not loop" % n)
			assert_false(w.stereo, "%s is mono" % n)
			assert_true(w.get_length() < 12.0, "%s is a short one-shot (%.1f s)" % [n, w.get_length()])


## Every .gd file under `dir` (recursive).
func _scripts_under(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		if String(f).ends_with(".gd"):
			out.append(dir.path_join(String(f)))
	for d in da.get_directories():
		_scripts_under(dir.path_join(String(d)), out)


func test_every_name_the_game_uses_resolves() -> void:
	# Integration guard: scans the other modules' scripts and data for sound names given to Audio
	# (literal first arguments, both arms of a ternary, data keys like "sound"/"hit_sound", and
	# music/ambience names) and checks that each one resolves to a real sound.
	var call_re := RegEx.create_from_string(
		"Audio\\.(?:play_3d|play_sfx|play_ui|play_music|play_ambience|has_sound|get_stream)\\(\\s*\"([a-z][a-z0-9_]*)\"(?:\\s+if\\s+[^\"]+?\\s+else\\s+\"([a-z][a-z0-9_]*)\")?")
	var key_re := RegEx.create_from_string(
		"\"(?:sound|alt_sound|hit_sound|break_sound|test_ui|test_sfx)\"\\s*:\\s*\"([a-z][a-z0-9_]*)\"")
	var loop_re := RegEx.create_from_string("\"((?:music|amb)_[a-z0-9_]+)\"")
	var snd_re := RegEx.create_from_string("return\\s+\"([a-z][a-z0-9_]*)\"\\s+if\\s+\\w+\\s+else\\s+\"([a-z][a-z0-9_]*)\"")
	var files: Array = []
	_scripts_under("res://src", files)
	_scripts_under("res://data", files)
	var used := {}                          # name -> "file:line" of first use
	for path in files:
		var text := FileAccess.get_file_as_string(String(path))
		var lines := text.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			var hits: Array = []
			for m in call_re.search_all(line):
				hits.append(m.get_string(1))
				if m.get_string(2) != "":
					hits.append(m.get_string(2))
			for m in key_re.search_all(line):
				hits.append(m.get_string(1))
			for m in loop_re.search_all(line):
				if not m.get_string(1).ends_with("_volume"):
					hits.append(m.get_string(1))
			if line.find("return") >= 0 and (line.find("weaver_") >= 0 or line.find("shade_") >= 0):
				for m in snd_re.search_all(line):
					hits.append(m.get_string(1))
					hits.append(m.get_string(2))
			for h in hits:
				if not used.has(h):
					used[h] = "%s:%d" % [String(path).get_file(), i + 1]
	assert_true(used.size() >= 40, "scan found the game's sound names (%d)" % used.size())
	for n in used:
		assert_true(Audio.has_sound(String(n)), "'%s' (%s) resolves to a sound" % [n, used[n]])
	var prev: Variant = Settings.get_value("arachnophobia")
	for arach in [false, true]:
		Settings.set_value("arachnophobia", arach)
		for n in used:
			assert_true(Audio.resolve(String(n)) != "", "'%s' resolves with arachnophobia %s" % [n, arach])
	Settings.set_value("arachnophobia", prev)


func test_long_files_are_compressed() -> void:
	# QOA keeps the export small; short one-shots stay uncompressed PCM for crisp transients.
	for n in MUSIC:
		var w := _wav("music", n)
		if w != null:
			assert_eq(w.format, AudioStreamWAV.FORMAT_QOA, "%s imported as QOA" % n)
	for n in AMBIENCE:
		var w := _wav("ambience", n)
		if w != null:
			assert_eq(w.format, AudioStreamWAV.FORMAT_QOA, "%s imported as QOA" % n)
	var click := _wav("ui", "ui_click")
	if click != null:
		assert_eq(click.format, AudioStreamWAV.FORMAT_16_BITS, "ui_click stays 16-bit PCM")
