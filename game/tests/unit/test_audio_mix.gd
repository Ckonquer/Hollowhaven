extends "res://tests/test_case.gd"
## Measures what the engine actually mixes. An AudioEffectCapture on a bus records the real mixed
## samples (this works with the headless dummy driver too; the bus peak *meters* miss short
## transients, so they are not used). Checks: every loop has a sensible level, the surface
## ambience sits under the music at the default slider settings, stacking loud sounds never pushes
## the master past its limiter, the major stinger swells instead of jumping, and one-shots arrive at
## their designed levels. Prints a balance table as evidence.

const BUSES := ["Master", "Music", "Ambience", "SFX", "UI"]

var _saved: Dictionary = {}
var _caps: Dictionary = {}           # bus -> AudioEffectCapture


func before_each() -> void:
	_saved = {}
	for k in ["master_volume", "music_volume", "ambience_volume", "sfx_volume", "ui_volume"]:
		_saved[k] = Settings.get_value(k)
		Settings.set_value(k, 1.0)
	Audio.stop_all()
	Audio.min_retrigger_ms = 0
	_caps = {}
	for b in BUSES:
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 4.0
		var idx := AudioServer.get_bus_index(b)
		AudioServer.add_bus_effect(idx, cap)       # appended: after the master limiter on Master
		_caps[b] = cap
	await wait_seconds(0.1)


func after_each() -> void:
	Audio.stop_all()
	Audio.min_retrigger_ms = 35
	for b in _caps:
		var idx := AudioServer.get_bus_index(String(b))
		for i in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
			if AudioServer.get_bus_effect(idx, i) == _caps[b]:
				AudioServer.remove_bus_effect(idx, i)
	_caps = {}
	for k in _saved:
		Settings.set_value(k, _saved[k])
	await wait_seconds(0.05)


func _clear(bus: String) -> void:
	(_caps[bus] as AudioEffectCapture).clear_buffer()


## Records `seconds` of the bus (mixed samples, pre bus-fader; the sliders are at 100% here).
## Returns {"peak": dBFS, "rms": dBFS, "t_peak": seconds from the start of the recording}.
func _record(bus: String, seconds: float) -> Dictionary:
	var cap: AudioEffectCapture = _caps[bus]
	var want := int(seconds * AudioServer.get_mix_rate())
	var got := 0
	var mx := 0.0
	var sumsq := 0.0
	var at := 0
	var t0 := Time.get_ticks_msec()
	while got < want and Time.get_ticks_msec() - t0 < int(seconds * 1000.0) + 3000:
		await get_tree().process_frame
		var k := mini(cap.get_frames_available(), want - got)
		if k <= 0:
			continue
		var buf := cap.get_buffer(k)
		for i in buf.size():
			var f: Vector2 = buf[i]
			var a := maxf(absf(f.x), absf(f.y))
			if a > mx:
				mx = a
				at = got + i
			sumsq += (f.x * f.x + f.y * f.y) * 0.5
		got += buf.size()
	var rms := sqrt(sumsq / float(maxi(got, 1)))
	return {"peak": linear_to_db(maxf(mx, 1e-9)), "rms": linear_to_db(maxf(rms, 1e-9)),
		"t_peak": float(at) / AudioServer.get_mix_rate(), "frames": got}


func test_music_levels_on_the_music_bus() -> void:
	for m in ["music_title", "music_haven", "music_night", "music_boss", "music_ending"]:
		Audio.play_music(m, 0.01)
		await wait_seconds(0.1)
		_clear("Music")
		var r := await _record("Music", 3.0)
		print("  mix %-16s peak %6.1f dBFS  rms %6.1f dBFS" % [m, r["peak"], r["rms"]])
		assert_true(int(r["frames"]) > 44100, "%s: recorded audio" % m)
		assert_true(float(r["rms"]) > -34.0 and float(r["rms"]) < -14.0, "%s RMS in range (%.1f)" % [m, r["rms"]])
		assert_true(float(r["peak"]) < -1.0, "%s leaves headroom (peak %.1f)" % [m, r["peak"]])
		Audio.stop_music(0.0)
		await wait_seconds(0.05)


## Average RMS of a looping channel from two 4 s windows (start, and seeked to mid-loop).
func _loop_rms(bus: String, deck, _label: String) -> Dictionary:
	var p: AudioStreamPlayer = deck.players[deck.active]
	var windows: Array = []
	for at in [0.0, p.stream.get_length() * 0.5]:
		p.seek(at)
		await wait_seconds(0.05)
		_clear(bus)
		windows.append(await _record(bus, 4.0))
	var pw := 0.0
	var pk := -200.0
	for w in windows:
		pw += pow(10.0, float(w["rms"]) / 10.0) * 0.5
		pk = maxf(pk, float(w["peak"]))
	return {"rms": 10.0 * log(pw) / log(10.0), "peak": pk}


func test_ambience_sits_under_the_music_at_default_settings() -> void:
	var amb := {}
	for a in ["amb_forest_day", "amb_forest_night", "amb_stream", "amb_mine", "amb_ruins", "amb_silk", "amb_boss"]:
		Audio.play_ambience(a, 0.01, 0)
		await wait_seconds(0.1)
		var r := await _loop_rms("Ambience", Audio._amb[0], a)
		amb[a] = r
		print("  mix %-16s peak %6.1f dBFS  rms %6.1f dBFS" % [a, r["peak"], r["rms"]])
		assert_true(float(r["rms"]) > -36.0 and float(r["rms"]) < -20.0, "%s RMS in range (%.1f)" % [a, r["rms"]])
		assert_true(float(r["peak"]) < -3.0, "%s stays soft (peak %.1f)" % [a, r["peak"]])
		Audio.stop_ambience(0.0)
		await wait_seconds(0.05)
	var music_db := linear_to_db(float(Settings.DEFAULTS["music_volume"]))
	var amb_db := linear_to_db(float(Settings.DEFAULTS["ambience_volume"]))
	# [music, beds it plays over]: at the default sliders every bed sits at least 3 dB under its music
	for pair in [["music_haven", ["amb_forest_day", "amb_forest_night", "amb_stream"]], ["music_night", ["amb_forest_night"]],
			["music_boss", ["amb_boss"]]]:
		Audio.play_music(String(pair[0]), 0.01)
		await wait_seconds(0.1)
		var mus := await _loop_rms("Music", Audio._music, String(pair[0]))
		Audio.stop_music(0.0)
		for a in pair[1]:
			var diff := (float(mus["rms"]) + music_db) - (float(amb[a]["rms"]) + amb_db)
			print("  mix default sliders: %s is %.1f dB under %s" % [a, diff, pair[0]])
			assert_true(diff >= 3.0, "%s sits >= 3 dB under %s at default sliders (%.1f dB)" % [a, pair[0], diff])


func test_master_limiter_holds_under_a_pile_of_loud_sounds() -> void:
	Audio.play_music("music_boss", 0.01)
	Audio.play_ambience("amb_boss", 0.01)
	await wait_seconds(0.1)
	_clear("Master")
	for s in ["stinger_major", "ward_restore", "weaver_drop", "tree_fall", "rock_break", "hit_hard", "hit_hard",
			"chop", "brazier_light", "gate_unlock", "weaver_shriek", "splash"]:
		Audio.play_sfx(s, 6.0, 0.0)
	var r := await _record("Master", 2.0)
	print("  mix master under stress: peak %.2f dBFS  rms %.1f dBFS" % [r["peak"], r["rms"]])
	assert_true(float(r["peak"]) <= -0.9, "master stays under the limiter ceiling (%.2f dBFS)" % r["peak"])
	assert_true(float(r["peak"]) > -12.0, "and the pile really is loud (%.2f dBFS)" % r["peak"])


func test_major_stinger_swells_rather_than_jumps() -> void:
	_clear("SFX")
	Audio.play_sfx("stinger_major", 0.0, 0.0)
	var r := await _record("SFX", 3.0)
	print("  mix stinger_major: peak %.1f dBFS after %.2f s" % [r["peak"], r["t_peak"]])
	assert_true(float(r["t_peak"]) >= 0.3, "loudest moment comes after a swell (%.2f s)" % r["t_peak"])
	assert_true(float(r["peak"]) <= -3.0, "peak <= -3 dBFS at full volume (%.1f)" % r["peak"])


func test_one_shots_arrive_at_their_designed_levels() -> void:
	# [bus, name, call volume_db, expected peak window]
	var cases := [
		["SFX", "step_grass", -9.0, -20.0, -14.0],     # walking footstep as the player calls it
		["SFX", "chop", -2.0, -9.0, -4.5],
		["SFX", "pickup", -3.0, -13.0, -9.0],
		["UI", "ui_click", 0.0, -15.0, -11.0],
		["UI", "ui_hover", -12.0, -29.0, -25.0],       # hover as the UI kit calls it: faint
		["UI", "ui_notify", -8.0, -23.0, -19.0],
	]
	for c in cases:
		var bus: String = c[0]
		_clear(bus)
		if bus == "UI":
			Audio.play_ui(String(c[1]), float(c[2]))
		else:
			Audio.play_sfx(String(c[1]), float(c[2]), 0.0)
		var r := await _record(bus, 0.6)
		print("  mix %-10s @%5.1f dB -> peak %6.1f dBFS" % [c[1], c[2], r["peak"]])
		assert_true(float(r["peak"]) >= float(c[3]) and float(r["peak"]) <= float(c[4]),
			"%s peak %.1f in [%.1f, %.1f]" % [c[1], r["peak"], c[3], c[4]])
		Audio.stop_all()
		await wait_seconds(0.05)
