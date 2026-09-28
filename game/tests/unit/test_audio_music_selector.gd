extends "res://tests/test_case.gd"
## Music selector core (src/audio/music_selector.gd) and catalogue (data/music.gd): pure logic driven
## with fake contexts and simulated time. Availability is set explicitly, so these tests behave the
## same with or without the new compositions on disk. (Scheduling only: nothing here is a listening
## test.)

const MusicData := preload("res://data/music.gd")
const Selector := preload("res://src/audio/music_selector.gd")

const NEW_CUES := ["m03", "m04", "m06", "m07", "m08", "m09", "m10", "m11", "m12", "m15", "m16", "m17", "m18",
	"m19", "m20", "m21", "m22", "m23", "m24", "m25", "m26", "m27"]
const LAYERS := ["m13_layer2", "m13_layer3", "m26_borrowed_welcome_l2", "m26_borrowed_welcome_l3"]


func _sel(seed_value: int = 1, tuning: Dictionary = {}, avail: Dictionary = {}, untimed: Array = []) -> RefCounted:
	var s: RefCounted = Selector.new()
	s.setup(_catalogue(untimed), seed_value, tuning)
	s.set_available(avail)
	return s


## The real catalogue, optionally with some cues' tempo removed (bpm 0 = unknown tempo) so the
## unknown-tempo paths stay covered now that every new cue carries tempo metadata.
func _catalogue(untimed: Array = []) -> Dictionary:
	var cat: Dictionary = MusicData.catalogue()
	if untimed.is_empty():
		return cat
	cat = cat.duplicate()
	var cues: Dictionary = (cat["cues"] as Dictionary).duplicate(true)
	for id in untimed:
		if cues.has(id):
			cues[id]["bpm"] = 0.0
			cues[id]["bars"] = 0
	cat["cues"] = cues
	return cat


func _ctx(area: String, zone: String, extra: Dictionary = {}) -> Dictionary:
	var c := {"mode": "playing", "area": area, "zone": zone, "night": false}
	c.merge(extra, true)
	return c


func _none_new() -> Dictionary:
	var a := {}
	for c in NEW_CUES:
		a[c] = false
	for l in LAYERS:
		a[l] = false
	return a


## Runs `seconds` of updates; returns [[time, decision], ...] for every non-"none" decision.
func _run(s: RefCounted, ctx: Dictionary, seconds: float, dt: float = 0.2, t0: float = 0.0) -> Array:
	var out: Array = []
	var n := int(round(seconds / dt))
	for i in n:
		var d: Dictionary = s.update(ctx, dt)
		if String(d["action"]) != "none":
			out.append([t0 + float(i + 1) * dt, d])
	return out


func _cues_of(pl: String) -> Array:
	return (MusicData.PLAYLISTS[pl] as Dictionary)["cues"]


# --- catalogue ---------------------------------------------------------------------------------------

func test_catalogue_has_27_cues_and_consistent_tables() -> void:
	var ids := MusicData.cue_ids()
	assert_eq(ids.size(), 27, "27 cues")
	for i in 27:
		assert_eq(String(ids[i]), "m%02d" % (i + 1), "cue ids m01..m27")
	var kinds := ["explore", "safe", "combat", "boss", "ending", "horror"]
	for id in MusicData.CUES:
		var c: Dictionary = MusicData.CUES[id]
		for k in ["title", "kind", "track", "file", "loop", "bpm", "bpb", "bars_per_phrase"]:
			assert_true(c.has(k), "%s has %s" % [id, k])
		assert_true(kinds.has(String(c["kind"])), "%s kind %s" % [id, c["kind"]])
		var track := String(c["track"])
		var us := track.rfind("_")
		assert_false(us > 0 and track.substr(us + 1).is_valid_int(), "%s track '%s' must not end in _<n> (would be a variant)" % [id, track])
		assert_true(String(c["file"]).begins_with("res://assets/audio/music/"), "%s file path" % id)
	for id in ["m01", "m02", "m05", "m13", "m14"]:
		assert_true(bool((MusicData.CUES[id] as Dictionary).get("retained", false)), "%s is a retained Chapter One piece" % id)
	assert_eq(String(MusicData.CUES["m01"]["track"]), "music_title")
	assert_eq(String(MusicData.CUES["m02"]["track"]), "music_haven")
	assert_eq(String(MusicData.CUES["m05"]["track"]), "music_night")
	assert_eq(String(MusicData.CUES["m13"]["track"]), "music_boss")
	assert_eq(String(MusicData.CUES["m14"]["track"]), "music_ending")
	for pl in MusicData.PLAYLISTS:
		for c in _cues_of(String(pl)):
			assert_true(MusicData.CUES.has(c), "playlist %s cue %s exists" % [pl, c])
		for f in ((MusicData.PLAYLISTS[pl] as Dictionary).get("fallback", []) as Array):
			var fs := String(f)
			assert_true(fs == "" or fs == "keep" or MusicData.CUES.has(fs), "playlist %s fallback %s" % [pl, fs])
			if MusicData.CUES.has(fs):
				assert_true(bool((MusicData.CUES[fs] as Dictionary).get("retained", false)) or fs == "m10", "fallback %s is a retained piece" % fs)
	for id in MusicData.CONTEXTS:
		var c: Dictionary = MusicData.CONTEXTS[id]
		for key in ["playlist", "night_playlist", "late_playlist", "signature"]:
			var pl := String(c.get(key, ""))
			assert_true(pl == "" or MusicData.PLAYLISTS.has(pl), "context %s %s '%s' exists" % [id, key, pl])
		assert_true(c.has("priority") and c.has("kind"), "context %s has priority and kind" % id)
	for a in MusicData.AREAS:
		var ad: Dictionary = MusicData.AREAS[a]
		assert_true(MusicData.CONTEXTS.has(String(ad["default"])), "area %s default context" % a)
		for z in (ad["zones"] as Dictionary):
			assert_true(MusicData.CONTEXTS.has(String(ad["zones"][z])), "zone %s context" % z)
	for b in MusicData.BOSSES:
		assert_eq(String(MusicData.CONTEXTS[MusicData.BOSSES[b]]["kind"]), "boss", "boss %s maps to a boss context" % b)
	for a in MusicData.AREA_COMBAT:
		assert_eq(String(MusicData.CONTEXTS[MusicData.AREA_COMBAT[a]]["kind"]), "combat")
	# spec 4.8 playlists
	assert_eq(_cues_of("haven_day"), ["m02", "m03", "m04"])
	assert_eq(_cues_of("haven_night"), ["m05", "m06"])
	assert_eq(_cues_of("woods"), ["m07", "m08"])
	assert_eq(_cues_of("reach"), ["m15", "m16"])
	var p := MusicData.CONTEXTS
	assert_true(int(p["restoration"]["priority"]) > int(p["boss_matron"]["priority"]), "ending > boss")
	assert_true(int(p["boss_matron"]["priority"]) > int(p["silence"]["priority"]), "boss > horror suppression")
	assert_true(int(p["silence"]["priority"]) > int(p["combat1"]["priority"]), "horror suppression > combat")
	assert_true(int(p["combat1"]["priority"]) > int(p["haven"]["priority"]), "combat > safe refuge")
	# the Music Box preview (P46: in the data table too) sits between ordinary combat and the safe refuges
	assert_true(int(p["combat1"]["priority"]) > int(p["musicbox"]["priority"]), "combat > music box preview")
	assert_true(int(p["musicbox"]["priority"]) > int(p["haven"]["priority"]), "music box preview > safe refuge")
	for a in MusicData.AREAS:
		var ad: Dictionary = MusicData.AREAS[a]
		assert_true(String(ad["default"]) != "musicbox" and not (ad["zones"] as Dictionary).values().has("musicbox"),
			"the preview is never an area / zone base (%s)" % a)
	assert_true(int(p["haven"]["priority"]) > int(p["woods"]["priority"]), "safe refuge > exploration")
	assert_true(int(p["woods"]["priority"]) > int(p["silk"]["priority"]), "exploration > ambience only")


func test_retained_tracks_match_their_metadata() -> void:
	for id in ["m01", "m02", "m05", "m13", "m14"]:
		var c: Dictionary = MusicData.CUES[id]
		var track := String(c["track"])
		if not Audio.has_sound(track, true):
			fail("retained %s (%s) is missing" % [id, track])
			continue
		var s: AudioStream = Audio.get_stream(track)
		assert_not_null(s, "%s loads" % track)
		if s == null:
			continue
		var expect := float(c["bars"]) * float(c["bpb"]) * 60.0 / float(c["bpm"])
		assert_almost(s.get_length(), expect, 0.01, "%s length = bars*bpb*60/bpm" % track)
		assert_almost(float(c["len_s"]), expect, 0.01, "%s len_s" % id)


func test_new_composition_files_when_present() -> void:
	# The new OGGs are composed in parallel: check the ones that exist (and are imported), skip the rest.
	var present := 0
	var missing: Array = []
	for id in MusicData.cue_ids():
		var c: Dictionary = MusicData.CUES[id]
		if bool(c.get("retained", false)):
			continue
		var track := String(c["track"])
		if not Audio.has_sound(track, true):
			missing.append(id)
			continue
		present += 1
		var s: AudioStream = Audio.get_stream(track)
		assert_not_null(s, "%s loads" % track)
		if s == null:
			continue
		assert_true(s.get_length() > 20.0, "%s is a real piece (%.1f s)" % [track, s.get_length()])
		var lp: Variant = s.get("loop")
		if lp is bool:
			assert_eq(bool(lp), bool(c["loop"]), "%s loop flag matches the catalogue" % track)
		for l in (c.get("layers", []) as Array):
			if Audio.has_sound(String(l), true):
				var ls: AudioStream = Audio.get_stream(String(l))
				if ls != null:
					# stems loop on their own players: any length difference drifts by that much on every
					# pass, so they must match the base loop to a few milliseconds (ideally to the sample)
					assert_almost(ls.get_length(), s.get_length(), 0.003, "%s is as long as its base %s (sample-synchronised)" % [l, track])
	print("    new music files present: %d, not there yet: %s" % [present, str(missing)])
	assert_true(true)


# --- base contexts --------------------------------------------------------------------------------------

func test_base_context_per_area_zone_and_time() -> void:
	var cases := [
		["surface", "haven", false, "haven", _cues_of("haven_day")],
		["surface", "haven", true, "haven", _cues_of("haven_night")],
		["surface", "", false, "woods", _cues_of("woods")],
		["surface", "meadow", false, "woods", _cues_of("woods")],
		["surface", "pond", false, "pond", ["m09"]],
		["below", "mine", false, "mine", ["m11"]],
		["below", "ruins", false, "ruins", ["m12"]],
		["tobin_annex", "ta_entry", false, "annex", ["m11"]],
		["hallowmere_reach", "hr_commons", false, "reach", ["m15", "m16"]],
		["hallowmere_reach", "hr_orchard", false, "orchard", ["m17"]],
		["hallowmere_reach", "hr_quarry", false, "quarry", ["m18"]],
		["hallowmere_reach", "hr_candleyard", false, "candleyard", ["m19"]],
		["hallowmere_reach", "hr_manor_grounds", false, "manor_grounds", ["m20", "m16"]],
		["moonveil_manor", "mm_hall", false, "manor", ["m20"]],
		["hushed_works", "hw_rails", false, "works", ["m23"]],
		["hushed_works", "hw_refuge", false, "refuge", ["m24"]],
	]
	for cs in cases:
		var s := _sel(11)
		var d: Dictionary = s.update(_ctx(String(cs[0]), String(cs[1]), {"night": cs[2]}), 0.2)
		var label := "%s/%s night=%s" % [cs[0], cs[1], cs[2]]
		assert_eq(String(d["action"]), "play", label + " starts music on arrival")
		assert_eq(String(d["context"]), String(cs[3]), label + " context")
		assert_true((cs[4] as Array).has(String(d["cue"])), "%s plays %s (from %s)" % [label, d["cue"], str(cs[4])])
		assert_eq(String(d["track"]), String(MusicData.CUES[String(d["cue"])]["track"]), label + " track name")
		assert_almost(float(d["fade"]), 4.0, 0.001, label + " arrival fade")
	# ambience-only places start nothing
	for cs2 in [["below", "silk"], ["below", "boss"], ["echo_trial", "trial"]]:
		var s2 := _sel(3)
		var d2: Dictionary = s2.update(_ctx(String(cs2[0]), String(cs2[1])), 0.2)
		assert_eq(String(d2["action"]), "none", "%s/%s has no music" % cs2)
		assert_eq(String(s2.state()["cue"]), "", "%s/%s silent" % cs2)
	# the title needs its request; boot/unknown modes never touch the music
	var t := _sel(5)
	assert_eq(String(t.update({"mode": "title", "area": ""}, 0.2)["action"]), "none", "title without request: hold")
	t.request("title", 3.0, "")
	var td: Dictionary = t.update({"mode": "title", "area": ""}, 0.2)
	assert_eq(String(td["cue"]), "m01", "title theme")
	assert_almost(float(td["fade"]), 3.0, 0.001, "title fade from the request")
	var b := _sel(5)
	assert_eq(String(b.update(_ctx("surface", "haven", {"mode": "boot"}), 0.2)["action"]), "none", "boot: idle")
	var u := _sel(5)
	assert_eq(String(u.update(_ctx("arena", ""), 0.2)["action"]), "none", "unknown area: music held")


# --- combat --------------------------------------------------------------------------------------------

func test_combat_hysteresis_enter_and_release() -> void:
	# Woods pieces without tempo: combat enters immediately (bar alignment is covered below).
	var s := _sel(21, {}, {}, ["m07", "m08"])
	var c := _ctx("surface", "")
	assert_eq(String(s.update(c, 0.25)["context"]), "woods")
	# a 0.5 s blip is ignored
	c["threat"] = true
	var blip := _run(s, c, 0.5, 0.25)
	c["threat"] = false
	blip.append_array(_run(s, c, 0.5, 0.25))
	assert_eq(blip.size(), 0, "0.5 s of threat changes nothing: %s" % str(blip))
	assert_false(bool(s.combat), "no combat after a blip")
	# 1 s of sustained threat enters
	c["threat"] = true
	var on := _run(s, c, 1.0, 0.25)
	assert_eq(on.size(), 1, "one decision on entering combat")
	if on.size() == 1:
		var d: Dictionary = on[0][1]
		assert_eq(String(d["action"]), "play")
		assert_eq(String(d["cue"]), "m10", "Chapter One combat piece")
		assert_eq(String(d["context"]), "combat1")
		assert_almost(float(on[0][0]), 1.0, 0.001, "entered after 1 s")
		assert_true(float(d["fade"]) <= 1.5, "fast but controlled entry (%.1f s)" % float(d["fade"]))
	# release 4-8 s after the threat genuinely cleared
	c["threat"] = false
	var off := _run(s, c, 3.9, 0.1)
	assert_eq(off.size(), 0, "combat lingers for at least 4 s: %s" % str(off))
	var back := _run(s, c, 4.5, 0.1, 3.9)
	assert_true(back.size() >= 1, "combat released within 8 s")
	if back.size() >= 1:
		var t_back: float = back[0][0]
		print("    combat released %.1f s after the threat cleared" % t_back)
		var d2: Dictionary = back[0][1]
		assert_true(t_back >= 4.0 - 0.001 and t_back <= 8.0 + 0.11, "released after %.1f s (4-8)" % t_back)
		assert_eq(String(d2["context"]), "woods", "back to the regional mood")
		assert_true(_cues_of("woods").has(String(d2["cue"])), "a woods piece")
		assert_almost(float(d2["fade"]), 3.0, 0.001, "combat exit fade")
	assert_false(bool(s.combat))
	# a threat that keeps flickering on and off never re-enters (each spell < 1 s)
	var flick := []
	for i in 20:
		c["threat"] = i % 3 != 2
		flick.append_array(_run(s, c, 0.3, 0.1))
	for f in flick:
		assert_ne(String(f[1]["context"]), "combat1", "flickering threat under 1 s never enters combat")


## P06 (integration pass 2, kept): the Quarry Warden is an elite, not one of the four bosses. data/music.gd BOSSES
## does not map it, so the selector treats it as an unknown boss: a Warden fight in the quarry plays the Reach's
## ordinary combat music (m22, following the threat), never a boss context.
func test_the_quarry_warden_fight_uses_ordinary_combat_music() -> void:
	assert_false(MusicData.BOSSES.has("quarry_warden"), "no boss mapping for the Warden")
	var s := _sel(4)
	s.update(_ctx("hallowmere_reach", "hr_quarry"), 0.2)
	# the quarry's own piece (m18) hands over on a beat boundary, so allow one beat past the 1 s combat entry
	var on := _run(s, _ctx("hallowmere_reach", "hr_quarry", {"threat": true, "boss": "quarry_warden"}), 2.4, 0.2)
	assert_eq(on.size(), 1, "one change: into ordinary combat")
	if on.size() == 1:
		assert_eq(String(on[0][1]["context"]), "combat2", "the Reach's combat context")
		assert_eq(String(on[0][1]["cue"]), "m22", "Harvest Trouble follows the threat")
	var calm := _run(s, _ctx("hallowmere_reach", "hr_quarry", {"boss": "quarry_warden"}), 3.0, 0.2)
	for e in calm:
		assert_ne(String(MusicData.CONTEXTS.get(String((e[1] as Dictionary).get("context", "")), {}).get("kind", "")), "boss",
			"an unknown boss id never selects boss music")


func test_combat_music_per_chapter() -> void:
	var s := _sel(2)
	var c := _ctx("hallowmere_reach", "hr_commons", {"threat": true})
	s.update(_ctx("hallowmere_reach", "hr_commons"), 0.2)
	var on := _run(s, c, 1.2, 0.2)
	assert_eq(on.size(), 1)
	if on.size() == 1:
		assert_eq(String(on[0][1]["cue"]), "m22", "Chapter Two areas use Harvest Trouble")
	var a := _sel(2)
	a.update(_ctx("tobin_annex", "ta_entry"), 0.2)
	var on2 := _run(a, _ctx("tobin_annex", "ta_entry", {"threat": true}), 1.2, 0.2)
	assert_eq(on2.size(), 1, "combat in the annex")
	if on2.size() == 1:
		assert_eq(String(on2[0][1]["cue"]), "m10", "Tobin's annex (Chapter One content) uses Thorns in the Path")


# --- priorities -------------------------------------------------------------------------------------------

func test_boss_outranks_combat_and_ending_outranks_all() -> void:
	var s := _sel(4)
	var c := _ctx("below", "ruins")
	s.update(c, 0.2)
	c["threat"] = true
	var on := _run(s, c, 1.2, 0.2)
	assert_eq(String(on[0][1]["cue"]) if on.size() > 0 else "", "m10", "ordinary combat first")
	c["boss"] = "weaver_matron"
	var d: Dictionary = s.update(c, 0.2)
	assert_eq(String(d["cue"]), "m13", "the boss outranks combat")
	assert_eq(String(d["context"]), "boss_matron")
	assert_eq(float(d["wait_s"]), 0.0, "boss starts now")
	c["horror_state"] = "encounter"
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "horror suppression does not silence a boss")
	s.request("restoration", 1.5, "below")
	var e: Dictionary = s.update(c, 0.2)
	assert_eq(String(e["cue"]), "m14", "the authored ending outranks everything")
	assert_almost(float(e["fade"]), 1.5, 0.001)
	s.request("restoration", 0.1, "below")
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "asking again never restarts it")
	s.release("restoration", 3.0)
	var r: Dictionary = s.update(c, 0.2)
	assert_eq(String(r["cue"]), "m13", "back to the boss once the scene ends")
	assert_almost(float(r["fade"]), 3.0, 0.001, "release fade")
	c["boss"] = ""
	var after: Dictionary = s.update(c, 0.2)
	assert_eq(String(after["context"]), "silence", "boss over, horror encounter: silence (fade out)")
	assert_eq(String(after["action"]), "stop")
	c["horror_state"] = "calm"
	var back := _run(s, c, 1.0, 0.2)
	assert_eq(String(back[0][1]["cue"]) if back.size() > 0 else "", "m10", "threat still there: combat after the suppression")


func test_horror_suppression_fades_out_then_music_returns() -> void:
	var s := _sel(8)
	var c := _ctx("below", "mine")
	assert_eq(String(s.update(c, 0.2)["cue"]), "m11", "The Last Shift in the mine")
	c["horror_state"] = "anticipation"
	var d: Dictionary = s.update(c, 0.2)
	assert_eq(String(d["action"]), "stop", "anticipation fades the music out")
	assert_eq(String(d["context"]), "silence")
	assert_almost(float(d["fade"]), 4.0, 0.001)
	assert_eq(_run(s, c, 20.0).size(), 0, "silence holds while the tension lasts")
	c["horror_state"] = "calm"
	var back := _run(s, c, 12.0, 0.2)
	assert_eq(back.size(), 1, "the music returns once")
	if back.size() == 1:
		assert_true(float(back[0][0]) >= 5.0 and float(back[0][0]) <= 10.5, "after a 5-10 s quiet (%.1f)" % float(back[0][0]))
		assert_eq(String(back[0][1]["cue"]), "m11")
	# authored silence (director: horror_event "authored:<id>", music_context_changed("silence"))
	c["silence"] = true
	assert_eq(String(s.update(c, 0.2)["action"]), "stop", "authored silence")
	c["silence"] = false
	# the ruins (quiet track) too
	var r := _sel(8)
	var rc := _ctx("below", "ruins")
	r.update(rc, 0.2)
	rc["horror_state"] = "encounter"
	assert_eq(String(r.update(rc, 0.2)["action"]), "stop", "encounter fades the ruins music out")
	rc["threat"] = true
	assert_eq(_run(r, rc, 3.0).size(), 0, "a horror encounter is not scored with combat music")


# --- hysteresis -----------------------------------------------------------------------------------------

func test_boundary_oscillation_never_switches() -> void:
	var avail := {"m03": false, "m04": false}
	var s := _sel(6, {}, avail)
	var c := _ctx("surface", "haven")
	var first: Dictionary = s.update(c, 0.2)
	assert_eq(String(first["cue"]), "m02")
	var t := 0.2
	var decisions: Array = []
	for i in 60:            # 60 s gathering at the Haven's edge: 1 s out, 1 s in
		c["zone"] = "" if i % 2 == 0 else "haven"
		decisions.append_array(_run(s, c, 1.0, 0.2, t))
		t += 1.0
	assert_eq(decisions.size(), 0, "no music change while hovering over the border: %s" % str(decisions))
	assert_eq(String(s.state()["base"]), "haven")
	# leaving for good: the woods take over after the zone held, on a phrase boundary of the Haven theme
	c["zone"] = ""
	var leave := _run(s, c, 40.0, 0.2, t)
	assert_true(leave.size() >= 1, "the woods take over")
	if leave.size() >= 1:
		var tt: float = leave[0][0]
		var d: Dictionary = leave[0][1]
		assert_eq(String(d["context"]), "woods")
		assert_true(tt >= t + 10.0 - 0.001, "only after 10 s of stable entry (%.1f)" % (tt - t))
		var pos := fposmod(tt - 0.2 + float(d["wait_s"]), 87.2727)     # piece started at t=0.2 (after the first update)
		print("    border: woods took over at %.1f s (%.1f s after leaving), %.2f s into the Haven theme" % [tt, tt - t, pos])
		assert_true(pos < 0.05 or pos > 87.2727 - 0.05 or absf(pos - 21.818) < 0.05 or absf(pos - 43.636) < 0.05 \
			or absf(pos - 65.454) < 0.05, "switch lands on a phrase boundary (%.2f s into the piece)" % pos)
		assert_true(float(d["fade"]) >= 3.0 and float(d["fade"]) <= 6.0, "gentle exploration crossfade")


func test_minimum_dwell_between_region_switches() -> void:
	var s := _sel(9, {}, {"m03": false, "m04": false})
	var c := _ctx("surface", "")
	s.update(c, 0.2)                       # woods (arrival, t = 0.2)
	c["zone"] = "haven"
	_run(s, c, 14.8, 0.2, 0.2)
	assert_eq(String(s.state()["base"]), "woods", "zone held 10 s but the woods only just started: dwell")
	_run(s, c, 5.4, 0.2, 15.0)
	assert_eq(String(s.state()["base"]), "haven", "switches once the minimum dwell passed")
	c["zone"] = ""
	_run(s, c, 12.0, 0.2, 20.4)
	assert_eq(String(s.state()["base"]), "haven", "and cannot switch back before another dwell")
	_run(s, c, 9.0, 0.2, 32.4)
	assert_eq(String(s.state()["base"]), "woods", "then it may")


func test_menus_and_pause_never_restart_music() -> void:
	var s := _sel(12)
	var c := _ctx("surface", "haven")
	var first: Dictionary = s.update(c, 0.2)
	c["paused"] = true
	var during: Array = []
	for i in 30:
		c["zone"] = "" if i % 2 == 0 else "pond"
		c["night"] = i > 15
		c["threat"] = i > 20
		during.append_array(_run(s, c, 1.0))
	assert_eq(during.size(), 0, "nothing changes while a menu pauses the game")
	c["paused"] = false
	c["zone"] = "haven"
	c["night"] = false
	c["threat"] = false
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "closing the menu does not restart the piece")
	assert_eq(String(s.state()["cue"]), String(first["cue"]))
	c["muted"] = true
	c["zone"] = ""
	assert_eq(_run(s, c, 30.0).size(), 0, "a muted music bus: nothing is loaded or changed")


# --- shuffle bags & RNG ---------------------------------------------------------------------------------

func test_shuffle_bag_rounds_no_repeats_deterministic() -> void:
	var a := _sel(7)
	var seq: Array = []
	for i in 30:
		seq.append(a.draw("haven_day"))
	for r in 10:
		var round_cues: Array = seq.slice(r * 3, r * 3 + 3)
		round_cues.sort()
		assert_eq(round_cues, ["m02", "m03", "m04"], "round %d plays every piece once" % r)
	for i in 29:
		assert_ne(seq[i], seq[i + 1], "no immediate repeat (also across refills) at %d" % i)
	var b := _sel(7)
	var seq_b: Array = []
	for i in 30:
		seq_b.append(b.draw("haven_day"))
	assert_eq(seq_b, seq, "same seed, same order")
	var c := _sel(8)
	var seq_c: Array = []
	for i in 30:
		seq_c.append(c.draw("haven_day"))
	assert_ne(seq_c, seq, "another seed, another order")
	var n := _sel(7)
	var night: Array = []
	for i in 12:
		night.append(n.draw("haven_night"))
	for i in 11:
		assert_ne(night[i], night[i + 1], "two-piece bag alternates")
	# piece to piece in a real rotation: a rest between pieces, never the same piece twice running
	var s := _sel(31, {"rest_scale": 0.05})
	var ctx := _ctx("surface", "haven", {"audio_track": ""})
	var played: Array = []
	for i in 400:
		var d: Dictionary = s.update(ctx, 0.2)
		if String(d["action"]) == "play":
			played.append(String(d["cue"]))
			ctx["audio_track"] = String(d["track"])
		elif String(d["action"]) == "stop":
			ctx["audio_track"] = ""
		elif i % 40 == 39:
			ctx["audio_track"] = ""        # the non-looping piece reached its end
	assert_true(played.size() >= 5, "the Haven rotates pieces (%s)" % str(played))
	for i in played.size() - 1:
		assert_ne(played[i], played[i + 1], "rotation never repeats a piece back to back")
	var distinct := {}
	for p in played:
		distinct[p] = true
	assert_true(distinct.size() >= 2, "more than one piece is heard (%s)" % str(played))


func test_global_rng_is_untouched() -> void:
	seed(4242)
	var expected := [randi(), randi(), randi()]
	seed(4242)
	var s := _sel(99, {"rest_scale": 0.05})
	var c := _ctx("surface", "haven", {"audio_track": ""})
	for i in 600:
		c["zone"] = "" if (i / 120) % 2 == 0 else "haven"
		c["threat"] = (i / 50) % 4 == 1
		c["night"] = i > 300
		var d: Dictionary = s.update(c, 0.25)
		c["audio_track"] = String(d["track"]) if String(d["action"]) == "play" else ("" if i % 30 == 0 else String(c["audio_track"]))
	for i in 50:
		s.draw("haven_day")
		s.draw("reach")
	var got := [randi(), randi(), randi()]
	assert_eq(got, expected, "music selection never consumes the global RNG")


# --- phrase timing ------------------------------------------------------------------------------------

func test_phrase_math() -> void:
	var m02: Dictionary = MusicData.CUES["m02"]
	assert_almost(Selector.beat_wait(m02, "phrase", 5.0), 21.8182 - 5.0, 0.001, "4/4 88 bpm, 8-bar phrase")
	assert_almost(Selector.beat_wait(m02, "bar", 5.0), 2.7273 * 2.0 - 5.0, 0.001, "next bar")
	assert_almost(Selector.beat_wait(m02, "beat", 5.0), 0.68182 * 8.0 - 5.0, 0.001, "next beat")
	assert_almost(Selector.beat_wait(m02, "phrase", 21.8182), 0.0, 0.001, "on a boundary: now")
	assert_almost(Selector.beat_wait(m02, "phrase", 87.2727 + 5.0), 21.8182 - 5.0, 0.001, "second pass wraps")
	var m01: Dictionary = MusicData.CUES["m01"]      # 3/4 at 76
	assert_almost(Selector.beat_wait(m01, "phrase", 10.0), 18.9474 - 10.0, 0.001, "3/4 phrase")
	assert_almost(Selector.beat_wait(m01, "bar", 10.0), 2.3684 * 5.0 - 10.0, 0.001, "3/4 bar")
	var m05: Dictionary = MusicData.CUES["m05"]      # 8+8+4 bars
	assert_almost(Selector.beat_wait(m05, "phrase", 70.0), 10.0, 0.001, "short last phrase ends at the loop point")
	var m13: Dictionary = MusicData.CUES["m13"]      # 2+8+8+8+4
	assert_almost(Selector.beat_wait(m13, "phrase", 3.0), 1.0, 0.001, "irregular phrase starts")
	var m25: Dictionary = MusicData.CUES["m25"]      # 7/8 + 4/4: deliberately no tempo metadata
	assert_eq(Selector.beat_wait(m25, "phrase", 5.0), -1.0, "unknown tempo")
	assert_almost(Selector.beat_wait(m25, "phrase", 5.0, 0.0, 120.0, 4), 11.0, 0.001, "stream bpm metadata")
	assert_almost(Selector.beat_wait(m25, "phrase", 99.0, 100.0, 120.0, 4), 1.0, 0.001, "end of the piece is a boundary")
	var m03: Dictionary = MusicData.CUES["m03"]      # 96 bpm 4/4, 8-bar phrases = 20 s
	assert_almost(Selector.beat_wait(m03, "phrase", 5.0), 15.0, 0.001, "new cue tempo metadata")


func test_day_night_switch_waits_for_the_phrase() -> void:
	var s := _sel(14, {}, {"m03": false, "m04": false})
	var c := _ctx("surface", "haven", {"pos_s": 0.0})
	assert_eq(String(s.update(c, 0.2)["cue"]), "m02")
	c["night"] = true
	c["pos_s"] = 5.0
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "night fell mid-phrase: wait")
	c["pos_s"] = 15.0
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "still waiting")
	c["pos_s"] = 21.7
	var d: Dictionary = s.update(c, 0.2)
	assert_eq(String(d["action"]), "play", "switches on the phrase boundary")
	assert_true(["m05", "m06"].has(String(d["cue"])), "a night piece")
	assert_almost(float(d["wait_s"]), 0.118, 0.01, "scheduled on the boundary itself")


func test_day_night_switch_waits_for_the_end_when_tempo_unknown() -> void:
	var s := _sel(15, {"rest_scale": 0.1}, {"m02": false, "m04": false}, ["m03"])
	var c := _ctx("surface", "haven")
	var d: Dictionary = s.update(c, 0.2)
	assert_eq(String(d["cue"]), "m03", "Wood, Wool & Windows (tempo unknown)")
	c["audio_track"] = String(d["track"])
	c["night"] = true
	assert_eq(_run(s, c, 60.0).size(), 0, "the day piece plays on to its end")
	c["audio_track"] = ""                 # it ended
	var next := _run(s, c, 6.0)
	assert_true(next.size() >= 1, "then, after a short rest, the night rotation")
	if next.size() >= 1:
		assert_true(float(next[0][0]) >= 1.5 - 0.001, "after a rest (%.1f s)" % float(next[0][0]))
		assert_true(["m05", "m06"].has(String(next[0][1]["cue"])))


func test_looping_piece_plays_its_passes_then_rests() -> void:
	var s := _sel(16, {}, {"m03": false, "m04": false})
	var c := _ctx("surface", "haven", {"track_len_s": 87.2727})
	s.update(c, 0.2)
	var ds := _run(s, c, 240.0, 0.2, 0.2)
	assert_true(ds.size() >= 1, "the looping Haven theme ends its turn")
	if ds.size() >= 1:
		assert_eq(String(ds[0][1]["action"]), "stop")
		assert_almost(float(ds[0][0]), 0.2 + 2.0 * 87.2727 - 8.0, 0.25, "two passes, fading out over the last 8 s")
		assert_almost(float(ds[0][1]["fade"]), 8.0, 0.001)
	if ds.size() >= 2:
		var gap := float(ds[1][0]) - float(ds[0][0])
		print("    Haven theme: stop at %.1f s, next piece %.1f s later" % [float(ds[0][0]), gap])
		assert_true(gap >= 8.0 + 15.0 - 0.3 and gap <= 8.0 + 40.0 + 0.3, "fade + a 15-40 s rest (%.1f)" % gap)
		assert_eq(String(ds[1][1]["cue"]), "m02", "only one piece available: it returns")


func test_signature_then_rotation_with_cooldown() -> void:
	var s := _sel(17, {"rest_scale": 0.05})
	var c := _ctx("hallowmere_reach", "hr_orchard", {"audio_track": ""})
	var d: Dictionary = s.update(c, 0.2)
	assert_eq(String(d["cue"]), "m17", "Pumpkin Patch Parade greets the orchard")
	c["audio_track"] = String(d["track"])
	s.update(c, 0.2)
	c["audio_track"] = ""
	var next := _run(s, c, 5.0)
	assert_true(next.size() >= 1, "the rotation continues")
	if next.size() >= 1:
		assert_true(["m16", "m15"].has(String(next[0][1]["cue"])), "then the varied rotation, not the same piece again")
	# leave and come straight back: no second dramatic arrival within the cooldown
	var s2 := _sel(18, {"region_enter_s": 1.0, "min_dwell_s": 1.0})
	var c2 := _ctx("surface", "pond")
	assert_eq(String(s2.update(c2, 0.2)["cue"]), "m09", "Ripples at Mirror Pond on the first visit")
	c2["zone"] = ""
	_run(s2, c2, 3.0)
	c2["zone"] = "pond"
	var again := _run(s2, c2, 5.0)
	for a in again:
		assert_ne(String(a[1]["cue"]), "m09", "no retrigger at the pond border within the cooldown")


# --- bosses -------------------------------------------------------------------------------------------------

func test_boss_phase_layers() -> void:
	var s := _sel(19)
	var c := _ctx("below", "boss", {"boss": "weaver_matron", "boss_phase": 1})
	var d: Dictionary = s.update(c, 0.2)
	assert_eq(String(d["cue"]), "m13")
	assert_eq(d["layers"], [], "phase 1: the base piece")
	c["boss_phase"] = 2
	var l2: Dictionary = s.update(c, 0.2)
	assert_eq(String(l2["action"]), "layers", "phase 2 adds a stem without restarting")
	assert_eq(l2["layers"], ["m13_layer2"])
	c["boss_phase"] = 3
	assert_eq(s.update(c, 0.2)["layers"], ["m13_layer2", "m13_layer3"], "phase 3: both stems")
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "stable phase: nothing to do")
	var m := _sel(19, {}, {"m13_layer3": false})
	m.update(c, 0.2)
	assert_eq(m.state()["layers"], ["m13_layer2"], "a missing stem is simply left out")
	var ch := _sel(20)
	var cc := _ctx("hushed_works", "hw_vault", {"boss": "borrowed_choir", "boss_phase": 3})
	var dc: Dictionary = ch.update(cc, 0.2)
	assert_eq(String(dc["cue"]), "m26", "The Borrowed Welcome")
	assert_eq(dc["layers"], ["m26_borrowed_welcome_l2", "m26_borrowed_welcome_l3"], "phase C: all three layers")
	# after the boss the music settles before the area's mood returns
	cc["boss"] = ""
	var after: Dictionary = ch.update(cc, 0.2)
	assert_eq(String(after["action"]), "stop", "recovery: the boss piece fades")
	var back := _run(ch, cc, 11.0)
	assert_eq(String(back[0][1]["cue"]) if back.size() > 0 else "", "m23", "then Under the Bellhouse")


# --- missing files ------------------------------------------------------------------------------------------

func test_missing_cues_fall_back_gracefully() -> void:
	var none := _none_new()
	var expect := [
		[_ctx("surface", "haven"), "m02"], [_ctx("surface", "haven", {"night": true}), "m05"],
		[_ctx("surface", ""), "m02"], [_ctx("surface", "pond"), "m02"], [_ctx("hallowmere_reach", "hr_commons"), "m02"],
		[_ctx("hallowmere_reach", "hr_orchard"), "m02"], [_ctx("hushed_works", "hw_refuge"), "m02"],
		[_ctx("hushed_works", "hw_crossing", {"boss": "crossing_matron"}), "m13"],
		[_ctx("moonveil_manor", "mm_gallery", {"boss": "count_velour"}), "m13"],
		[_ctx("hushed_works", "hw_vault", {"boss": "borrowed_choir"}), "m13"],
	]
	for e in expect:
		var s := _sel(23, {}, none)
		var d: Dictionary = s.update(e[0], 0.2)
		assert_eq(String(d["cue"]), String(e[1]), "fallback for %s/%s" % [e[0]["area"], e[0]["zone"]])
	for place in [["below", "mine"], ["below", "ruins"], ["hushed_works", "hw_rails"], ["moonveil_manor", "mm_hall"], ["tobin_annex", "ta_entry"]]:
		var q := _sel(23, {}, none)
		var dq: Dictionary = q.update(_ctx(String(place[0]), String(place[1])), 0.2)
		assert_eq(String(dq["action"]), "none", "%s/%s: silence while its piece is missing (never an error)" % place)
	# arriving there from music: it fades like Chapter One's Below arrival (stop_music(2.0)), not over the 6 s mine fade
	var arr := _sel(23, {}, none)
	arr.update(_ctx("surface", ""), 0.2)
	arr.reset_area()
	var dstop: Dictionary = arr.update(_ctx("below", "mine"), 0.2)
	assert_eq(String(dstop["action"]), "stop", "the surface piece fades on arrival in the Below")
	assert_almost(float(dstop["fade"]), 2.0, 0.001, "legacy arrival stop fade")
	# missing combat piece: the regional music simply continues
	var w := _sel(24, {}, none)
	var wc := _ctx("surface", "")
	w.update(wc, 0.2)
	wc["threat"] = true
	assert_eq(_run(w, wc, 5.0).size(), 0, "no combat piece: nothing stops or restarts")
	assert_eq(String(w.state()["effective"]), "woods")
	var r := _sel(24, {}, none)
	var rc := _ctx("hallowmere_reach", "hr_pools")
	r.update(rc, 0.2)
	rc["threat"] = true
	assert_eq(_run(r, rc, 5.0).size(), 0, "Chapter Two combat falls back to Chapter One's, then keeps the music")
	# celebration without its file: the retained ending reprise
	var e2 := _sel(25, {}, none)
	e2.update(_ctx("surface", "haven"), 0.2)
	e2.request("celebration", 2.0, "surface")
	assert_eq(String(e2.update(_ctx("surface", "haven"), 0.2)["cue"]), "m14")
	# one missing piece: the next in the playlist
	var p := _sel(26, {}, {"m03": false})
	for i in 20:
		assert_ne(p.draw("haven_day"), "m03", "a missing piece is skipped")
	# a piece that fails to load at play time is skipped from then on; the music keeps playing
	var f := _sel(27, {}, {"m02": false, "m04": false})
	var fc := _ctx("surface", "haven")
	assert_eq(String(f.update(fc, 0.2)["cue"]), "m03")
	f.play_failed("m03")
	var fd: Dictionary = f.update(fc, 0.2)
	assert_eq(String(fd["action"]), "none", "nothing else to play in the Haven day list: silence, no error")
	var g := _sel(27, {}, {"m04": false})
	var gd: Dictionary = g.update(fc, 0.2)
	var first := String(gd["cue"])
	g.play_failed(first)
	var gd2: Dictionary = g.update(fc, 0.2)
	assert_ne(String(gd2["cue"]), first, "the next piece is chosen instead")
	for i in 10:
		assert_ne(g.draw("haven_day"), first, "and the failed one is never drawn again")


# --- authored requests, foreign tracks ----------------------------------------------------------------------

func test_title_and_restoration_requests() -> void:
	var s := _sel(28)
	var t := {"mode": "title", "area": ""}
	s.request("title", 3.0, "")
	assert_eq(String(s.update(t, 0.2)["cue"]), "m01")
	s.release("title", 0.9)
	var st: Dictionary = s.update(t, 0.2)
	assert_eq(String(st["action"]), "stop", "the title fades out before loading")
	assert_almost(float(st["fade"]), 0.9, 0.001)
	assert_eq(String(s.update({"mode": "loading", "area": "surface"}, 0.2)["action"]), "none", "silence while loading")
	var h := _ctx("surface", "haven")
	var arr: Dictionary = s.update(h, 0.2)
	assert_eq(String(arr["context"]), "haven", "arrival: the Haven")
	assert_almost(float(arr["fade"]), 4.0, 0.001)
	# the restoration (a cutscene): requested, kept through the ending, released, then the Haven again
	h["mode"] = "cutscene"
	s.request("restoration", 1.5, "surface")
	var r: Dictionary = s.update(h, 0.2)
	assert_eq(String(r["cue"]), "m14", "The Heart Comes Home")
	s.request("restoration", 2.0, "surface")          # the ending screen asks again
	assert_eq(_run(s, h, 30.0).size(), 0, "no restart during the ending")
	s.release("restoration", 3.0)
	var rel: Dictionary = s.update(h, 0.2)
	assert_eq(String(rel["action"]), "stop", "released during the cutscene: it fades")
	h["mode"] = "playing"
	h["night"] = true
	var home: Dictionary = s.update(h, 0.2)
	assert_eq(String(home["context"]), "haven")
	assert_true(["m05", "m06"].has(String(home["cue"])), "back to the Haven's night music (not always the day theme)")
	# quitting to the title leaves the music for the title's own crossfade
	var q: Dictionary = s.update({"mode": "title", "area": ""}, 0.2)
	assert_eq(String(q["action"]), "none", "the title's crossfade replaces it")
	# requests never outlive their area or the game
	var x := _sel(29)
	x.request("boss_matron", 1.5, "below")
	assert_eq(String(x.update(_ctx("surface", "haven"), 0.2)["context"]), "haven", "a request from another area is dropped")
	x.request("boss_matron", 1.5, "surface")
	x.update(_ctx("surface", "haven", {"mode": "boot"}), 0.2)
	assert_false(bool(x.has_request("boss_matron")), "requests end outside a running game")


func test_once_context_returns_to_the_rotation() -> void:
	var s := _sel(30, {"rest_scale": 0.05})
	var c := _ctx("surface", "haven", {"audio_track": ""})
	var d: Dictionary = s.update(c, 0.2)
	c["audio_track"] = String(d["track"])
	s.request("celebration", 2.0, "surface")
	var cel: Dictionary = s.update(c, 0.2)
	assert_eq(String(cel["cue"]), "m27", "Every Road Leads Home")
	c["audio_track"] = String(cel["track"])
	assert_eq(_run(s, c, 5.0).size(), 0)
	c["audio_track"] = ""                  # the piece ended
	var back := _run(s, c, 5.0)
	assert_true(back.size() >= 1 and String(back[0][1]["context"]) == "haven", "then the Haven rotation")
	assert_false(bool(s.has_request("celebration")), "played once")
	# without its own file the celebration falls back to the (looping) ending reprise: still one pass only
	var f := _sel(30, {"rest_scale": 0.05}, {"m27": false})
	var fc := _ctx("surface", "haven", {"audio_track": "", "track_len_s": 90.0})
	f.update(fc, 0.2)
	f.request("celebration", 2.0, "surface")
	var fb: Dictionary = f.update(fc, 0.2)
	assert_eq(String(fb["cue"]), "m14", "The Heart Comes Home stands in")
	fc["audio_track"] = String(fb["track"])
	var first: Dictionary = {}
	var t_first := 0.0
	for i in 600:                           # up to 120 s
		var fd: Dictionary = f.update(fc, 0.2)
		if String(fd["action"]) != "none":
			first = fd
			t_first = float(i + 1) * 0.2
			break
	assert_eq(String(first.get("action", "")), "stop", "the looping stand-in does not play forever")
	assert_almost(t_first, 90.0 - 8.0, 0.3, "one pass, fading over its last 8 s")
	assert_false(bool(f.has_request("celebration")), "the request is over")
	fc["audio_track"] = ""                  # Audio reports the stop
	var home: Array = _run(f, fc, 15.0)
	assert_true(home.size() >= 1 and String(home[0][1]["context"]) == "haven", "then the Haven again")


func test_foreign_track_is_left_alone_but_bosses_override() -> void:
	var s := _sel(32)
	var c := _ctx("surface", "haven")
	var d: Dictionary = s.update(c, 0.2)
	c["audio_track"] = String(d["track"])
	s.update(c, 0.2)
	c["audio_track"] = "music_ending"        # someone else played a track
	assert_eq(String(s.update(c, 0.2)["action"]), "none")
	assert_eq(String(s.state()["external"]), "music_ending", "noticed as foreign")
	c["zone"] = ""
	assert_eq(_run(s, c, 40.0).size(), 0, "base changes leave it alone")
	c["boss"] = "weaver_matron"
	var b: Dictionary = s.update(c, 0.2)
	assert_eq(String(b["cue"]), "m13", "a boss still takes over")
	# a foreign track that belongs to the context is adopted (no restart)
	var a := _sel(33)
	var ac := _ctx("surface", "haven", {"night": true})
	var ad: Dictionary = a.update(ac, 0.2)
	ac["audio_track"] = "music_night"      # m05, or m06 replaced by the familiar night theme from outside
	a.update(ac, 0.2)
	assert_eq(String(a.state()["external"]), "", "a Haven night piece is adopted, not fought")
	assert_eq(String(a.state()["track"]), "music_night")
	# ... and a foreign track that stops hands the music back after a short quiet
	var f := _sel(34, {"rest_scale": 0.1})
	var fc := _ctx("surface", "haven")
	var fd: Dictionary = f.update(fc, 0.2)
	fc["audio_track"] = "music_boss"
	f.update(fc, 0.2)
	fc["audio_track"] = ""
	var back := _run(f, fc, 3.0)
	assert_true(back.size() >= 1 and String(back[0][1]["context"]) == "haven", "the director resumes")
	assert_true(String(fd["cue"]) != "", "started")
	# authored horror silence also silences a foreign track (fades it out once, no tug of war)
	var h := _sel(36)
	var hc := _ctx("below", "mine")
	h.update(hc, 0.2)
	hc["audio_track"] = "music_ending"
	h.update(hc, 0.2)
	assert_eq(String(h.state()["external"]), "music_ending")
	hc["silence"] = true
	var hs: Dictionary = h.update(hc, 0.2)
	assert_eq(String(hs["action"]), "stop", "the foreign track fades out for the silence")
	hc["audio_track"] = ""
	var quiet := _run(h, hc, 10.0)
	assert_eq(quiet.size(), 0, "then silence holds: %s" % str(quiet))
	var notes := 0
	for e in h.get_debug_log():
		if String((e as Dictionary)["reason"]).begins_with("foreign track"):
			notes += 1
	assert_true(notes <= 3, "noticed and overridden once, not on every update (%d notes)" % notes)
	# a boss whose context was already chosen still replaces a foreign track
	var k := _sel(37)
	var kc := _ctx("below", "boss", {"boss": "weaver_matron"})
	assert_eq(String(k.update(kc, 0.2)["cue"]), "m13")
	kc["audio_track"] = "music_title"             # someone played over the boss piece
	var kd: Dictionary = k.update(kc, 0.2)
	assert_eq(String(kd["action"]), "play", "the boss takes its music back")
	assert_eq(String(kd["cue"]), "m13")


func test_debug_log_keeps_the_last_50_decisions() -> void:
	var s := _sel(35, {"rest_scale": 0.02})
	var c := _ctx("surface", "haven", {"audio_track": ""})
	for i in 2000:
		c["threat"] = (i / 20) % 3 == 1
		var d: Dictionary = s.update(c, 0.2)
		if String(d["action"]) == "play":
			c["audio_track"] = String(d["track"])
		elif i % 25 == 0:
			c["audio_track"] = ""
	var entries: Array = s.get_debug_log()
	assert_true(entries.size() > 10 and entries.size() <= 50, "bounded log (%d)" % entries.size())
	for e in entries:
		for k in ["t", "action", "context", "cue", "track", "fade", "wait_s", "reason"]:
			assert_true((e as Dictionary).has(k), "entry has %s" % k)
	entries.clear()
	assert_true(s.get_debug_log().size() > 10, "callers get a copy")


## With tempo metadata (all new cues have it), combat enters on the next bar of the exploration piece:
## after the 1 s threat hysteresis and within one bar of it.
func test_combat_entry_lands_on_a_bar_with_known_tempo() -> void:
	var s := _sel(22)
	var c := _ctx("surface", "", {"pos_s": 0.0})
	var d0: Dictionary = s.update(c, 0.25)
	assert_eq(String(d0["context"]), "woods")
	var cue: Dictionary = MusicData.CUES.get(String(d0["cue"]), {})
	var bpm := float(cue.get("bpm", 0.0))
	assert_true(bpm > 0.0, "woods piece %s carries tempo metadata" % String(d0["cue"]))
	var bar_s := 60.0 / maxf(bpm, 1.0) * float(cue.get("bpb", 4))
	c["threat"] = true
	var t := 0.25
	var entered := -1.0
	while t < 1.0 + bar_s + 0.5:
		c["pos_s"] = t
		var d: Dictionary = s.update(c, 0.1)
		t += 0.1
		if String(d["action"]) == "play" and String(d["context"]) == "combat1":
			entered = t + float(d["wait_s"])
			break
	assert_true(entered >= 1.0 - 0.11, "not before the 1 s hysteresis (%.2f)" % entered)
	assert_true(entered <= 1.25 + bar_s + 0.11, "within one bar after it (%.2f, bar %.2f s)" % [entered, bar_s])
