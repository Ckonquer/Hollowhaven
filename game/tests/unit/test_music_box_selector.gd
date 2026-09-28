extends "res://tests/test_case.gd"
## Music Box in the music selector (src/audio/music_selector.gd, MP 18.3): the low-priority "musicbox" preview
## context (above the regional base, below combat / horror suppression / bosses / authored scenes, which END
## it), one-pass previews, Stop with a short recovery, unplayable cues, and the favourites weighting of the
## Haven rotation (bounded, deterministic per seed, never only favourites, Haven base only). Pure logic with
## simulated time; availability is explicit so it behaves the same with or without the files on disk.

const MusicData := preload("res://data/music.gd")
const Selector := preload("res://src/audio/music_selector.gd")

const FAST := {"rest_scale": 0.05, "combat_enter_s": 0.2, "combat_release_s": [0.4, 0.6], "region_enter_s": 0.4,
	"min_dwell_s": 0.4}


func _sel(seed_value: int = 1, tuning: Dictionary = {}, avail: Dictionary = {}) -> RefCounted:
	var s: RefCounted = Selector.new()
	var t := FAST.duplicate()
	t.merge(tuning, true)
	s.setup(MusicData.catalogue(), seed_value, t)
	s.set_available(avail)
	return s


func _ctx(area: String, zone: String, extra: Dictionary = {}) -> Dictionary:
	var c := {"mode": "playing", "area": area, "zone": zone, "night": false, "audio_track": ""}
	c.merge(extra, true)
	return c


## Runs `seconds` of updates, feeding what "Audio" plays back into the context; returns the non-"none"
## decisions as [[time, decision], ...].
func _run(s: RefCounted, ctx: Dictionary, seconds: float, dt: float = 0.2) -> Array:
	var out: Array = []
	for i in int(round(seconds / dt)):
		var d: Dictionary = s.update(ctx, dt)
		_feed(ctx, d)
		if String(d["action"]) != "none":
			out.append([float(i + 1) * dt, d])
	return out


func _feed(ctx: Dictionary, d: Dictionary) -> void:
	match String(d["action"]):
		"play":
			ctx["audio_track"] = String(d["track"])
		"stop":
			ctx["audio_track"] = ""


func _first(decisions: Array, action: String) -> Dictionary:
	for e in decisions:
		if String((e[1] as Dictionary)["action"]) == action:
			return e[1]
	return {}


func _cues(pl: String) -> Array:
	return (MusicData.PLAYLISTS[pl] as Dictionary)["cues"]


## A selector already playing the Haven day music.
func _at_home(seed_value: int = 5, extra: Dictionary = {}) -> Array:
	var s := _sel(seed_value)
	var c := _ctx("surface", "haven", extra)
	var d: Dictionary = s.update(c, 0.2)
	_feed(c, d)
	assert_eq(String(d["context"]), "haven", "setup: the Haven plays")
	return [s, c]


func _preview(s: RefCounted, c: Dictionary, cue: String) -> Dictionary:
	assert_true(bool(s.request_preview(cue, 1.5, String(c["area"]))), "preview %s accepted" % cue)
	var d: Dictionary = s.update(c, 0.2)
	_feed(c, d)
	return d


# --- priority ----------------------------------------------------------------------------------------------------

func test_preview_context_sits_between_the_base_and_everything_else() -> void:
	var s := _sel()
	var p: Dictionary = s.contexts[Selector.PREVIEW_CONTEXT]
	var pp := int(p["priority"])
	for base in ["haven", "refuge", "woods", "reach", "orchard", "mine", "silk"]:
		assert_true(pp > int(MusicData.CONTEXTS[base]["priority"]), "above the regional base %s" % base)
	for high in ["combat1", "combat2", "silence", "boss_matron", "velour", "crossing", "choir", "restoration", "celebration", "title"]:
		assert_true(pp < int(MusicData.CONTEXTS[high]["priority"]), "below %s" % high)
	assert_false(MusicData.CONTEXTS.has(Selector.PREVIEW_CONTEXT), "the shared catalogue is untouched")
	assert_eq(String(p["mode"]), "once", "one pass")


func test_preview_plays_at_once_then_the_haven_returns() -> void:
	var h := _at_home()
	var s: RefCounted = h[0]
	var c: Dictionary = h[1]
	var d := _preview(s, c, "m17")
	assert_eq(String(d["action"]), "play", "starts at once (no phrase wait)")
	assert_eq(String(d["cue"]), "m17")
	assert_eq(String(d["context"]), "musicbox")
	assert_almost(float(d["fade"]), 1.5, 0.001, "the preview's fade")
	assert_almost(float(d["wait_s"]), 0.0, 0.001)
	assert_eq(String(s.preview_cue()), "m17")
	assert_eq(_run(s, c, 6.0).size(), 0, "plays undisturbed")
	assert_true(bool(s.request_preview("m17", 1.5, "surface")), "asking again is fine...")
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "...and never restarts it")
	c["audio_track"] = ""            # the piece reached its end
	var back := _run(s, c, 4.0)
	assert_eq(String(s.preview_cue()), "", "one pass only")
	var p := _first(back, "play")
	assert_eq(String(p.get("context", "")), "haven", "then the Haven rotation")
	assert_true(_cues("haven_day").has(String(p.get("cue", ""))), "with a Haven piece (%s)" % str(p.get("cue", "")))


func test_stop_fades_out_and_the_haven_returns_after_a_rest() -> void:
	var h := _at_home()
	var s: RefCounted = h[0]
	var c: Dictionary = h[1]
	_preview(s, c, "m19")
	_run(s, c, 2.0)
	s.stop_preview(1.5)
	var st: Dictionary = s.update(c, 0.2)
	_feed(c, st)
	assert_eq(String(st["action"]), "stop", "Stop fades the preview out at once")
	assert_almost(float(st["fade"]), 1.5, 0.001)
	assert_eq(String(s.preview_cue()), "")
	var back := _run(s, c, 3.0)
	var p := _first(back, "play")
	assert_eq(String(p.get("context", "")), "haven", "the Haven music returns after a short rest")
	assert_true(back.size() > 0 and float(back[0][0]) >= 0.2, "not in the same instant")
	# stopping the piece that was already playing works the same way (no silent 'continues' trap)
	var h2 := _at_home(8)
	var s2: RefCounted = h2[0]
	var c2: Dictionary = h2[1]
	var home_cue := String(s2.current_cue())
	var same := _preview(s2, c2, home_cue)
	assert_eq(String(same["action"]), "none", "previewing the piece already playing never restarts it")
	assert_eq(String(s2.preview_cue()), home_cue)
	s2.stop_preview(1.5)
	assert_eq(String(s2.update(c2, 0.2)["action"]), "stop", "Stop still stops it")


func test_combat_boss_horror_authored_and_death_end_a_preview() -> void:
	# ordinary combat
	var h := _at_home(11)
	var s: RefCounted = h[0]
	var c: Dictionary = h[1]
	_preview(s, c, "m17")
	c["threat"] = true
	var fight := _run(s, c, 3.0)
	var cp := _first(fight, "play")
	assert_eq(String(cp.get("context", "")), "combat1", "combat overrides the preview")
	assert_eq(String(s.preview_cue()), "", "and ends it")
	c["threat"] = false
	var after := _run(s, c, 6.0)
	var ap := _first(after, "play")
	assert_eq(String(ap.get("context", "")), "haven", "after the fight: the Haven, not the preview again")
	# a boss
	h = _at_home(12)
	s = h[0]
	c = h[1]
	_preview(s, c, "m17")
	c["boss"] = "weaver_matron"
	var b: Dictionary = s.update(c, 0.2)
	assert_eq(String(b["cue"]), "m13", "a boss overrides the preview at once")
	assert_eq(String(s.preview_cue()), "")
	# horror suppression (authored silence and horror states)
	for key in ["silence", "horror_state"]:
		h = _at_home(13)
		s = h[0]
		c = h[1]
		_preview(s, c, "m17")
		if key == "silence":
			c["silence"] = true
		else:
			c["horror_state"] = "encounter"
		var hs: Dictionary = s.update(c, 0.2)
		assert_eq(String(hs["action"]), "stop", "%s fades the preview out" % key)
		assert_eq(String(hs["context"]), "silence")
		assert_eq(String(s.preview_cue()), "", "%s ends it" % key)
	# an authored scene
	h = _at_home(14)
	s = h[0]
	c = h[1]
	_preview(s, c, "m17")
	s.request("restoration", 1.5, "surface")
	assert_eq(String(s.update(c, 0.2)["cue"]), "m14", "authored music overrides the preview")
	assert_eq(String(s.preview_cue()), "")
	# fainting
	h = _at_home(15)
	s = h[0]
	c = h[1]
	_preview(s, c, "m17")
	c["mode"] = "dead"
	var dd: Dictionary = s.update(c, 0.2)
	assert_eq(String(dd["action"]), "stop", "the preview fades when Krystal faints")
	assert_eq(String(s.preview_cue()), "")
	# leaving the area
	h = _at_home(16)
	s = h[0]
	c = h[1]
	_preview(s, c, "m17")
	c["area"] = "hallowmere_reach"
	c["zone"] = "hr_commons"
	var lv: Dictionary = s.update(c, 0.2)
	assert_eq(String(s.preview_cue()), "", "a preview never follows her to another area")
	assert_eq(String(lv["context"]), "reach")


func test_preview_ranks_above_exploration_too_and_replaces_a_foreign_track() -> void:
	var s := _sel(21)
	var c := _ctx("surface", "")
	_feed(c, s.update(c, 0.2))
	assert_eq(String(s.state()["base"]), "woods")
	var d := _preview(s, c, "m03")
	assert_eq(String(d["cue"]), "m03", "a preview also plays over the woods' music (the box sits in the Haven)")
	# a track someone else started is replaced by Krystal's own choice
	var f := _sel(22)
	var fc := _ctx("surface", "haven")
	_feed(fc, f.update(fc, 0.2))
	f.update(fc, 0.2)
	fc["audio_track"] = "music_ending"
	f.update(fc, 0.2)
	assert_eq(String(f.state()["external"]), "music_ending")
	var fd := _preview(f, fc, "m17")
	assert_eq(String(fd["action"]), "play", "the preview replaces the foreign track")
	assert_eq(String(fd["cue"]), "m17")


func test_unknown_or_unplayable_cues_are_refused() -> void:
	var s := _sel(31, {}, {"m17": false})
	var c := _ctx("surface", "haven")
	_feed(c, s.update(c, 0.2))
	var before := String(s.current_cue())
	assert_false(bool(s.request_preview("m99_renamed", 1.5, "surface")), "unknown cue")
	assert_false(bool(s.request_preview("m17", 1.5, "surface")), "a cue without its file")
	for never in ["m13", "m21", "m26", "m10", "m22", "m12", "m23"]:
		assert_false(bool(s.request_preview(never, 1.5, "surface")), "%s (boss / combat / horror) never plays at the box's priority" % never)
	assert_eq(String(s.preview_cue()), "", "no preview request was left behind")
	assert_eq(String(s.update(c, 0.2)["action"]), "none", "nothing changes")
	assert_eq(String(s.current_cue()), before)
	# a file that fails to load when it is tried: the preview ends, the Haven piece goes on
	assert_true(bool(s.request_preview("m19", 1.5, "surface")))
	var d: Dictionary = s.update(c, 0.2)
	assert_eq(String(d["cue"]), "m19")
	s.play_failed("m19")
	assert_eq(String(s.preview_cue()), "", "a preview that could not play is over")
	assert_false(bool(s.request_preview("m19", 1.5, "surface")), "and is not offered again this session")


func test_switching_the_preview_to_another_song() -> void:
	var h := _at_home(41)
	var s: RefCounted = h[0]
	var c: Dictionary = h[1]
	_preview(s, c, "m17")
	_run(s, c, 1.0)
	var d := _preview(s, c, "m09")
	assert_eq(String(d["action"]), "play", "the next song starts at once")
	assert_eq(String(d["cue"]), "m09")
	assert_eq(String(s.preview_cue()), "m09")
	# after a finished preview, a new one starts too (no stuck state)
	c["audio_track"] = ""
	_run(s, c, 0.6)
	assert_eq(String(s.preview_cue()), "")
	var again := _preview(s, c, "m17")
	assert_eq(String(again["cue"]), "m17", "a new preview right after one finished")


# --- favourites --------------------------------------------------------------------------------------------------

func _draws(seed_value: int, favs: Array, n: int, pl: String = "haven_day") -> Array:
	var s := _sel(seed_value)
	s.set_favourites(favs)
	var out: Array = []
	for i in n:
		var cue := String(s.draw_favoured(pl))
		out.append(cue)
		s.set("_last_played", cue)      # what the rotation would have played
	return out


func _count(seq: Array, cue: String) -> int:
	var n := 0
	for c in seq:
		if String(c) == cue:
			n += 1
	return n


func test_favourites_weighting_is_bounded_and_deterministic() -> void:
	var a := _draws(7, ["m15", "m03"], 200)
	assert_eq(_draws(7, ["m15", "m03"], 200), a, "same seed and favourites: same order")
	assert_ne(_draws(8, ["m15", "m03"], 200), a, "another seed: another order")
	for i in a.size() - 1:
		assert_ne(a[i], a[i + 1], "never the same piece twice in a row (%d)" % i)
	# rounds of the 3 Haven pieces + 2 favourite entries (m03 once more, m15 as a guest)
	assert_true(_count(a, "m02") >= 36 and _count(a, "m04") >= 36, "the Haven's own pieces play every round: %d / %d" % [_count(a, "m02"), _count(a, "m04")])
	assert_true(_count(a, "m15") >= 30 and _count(a, "m15") <= 44, "a guest favourite at most once a round: %d" % _count(a, "m15"))
	assert_true(_count(a, "m03") > _count(a, "m02"), "a favourite Haven piece plays more often")
	assert_true(_count(a, "m03") <= 2 * _count(a, "m02") + 4, "but at most twice a round")
	# many favourites: still at most FAV_BONUS_PER_ROUND favourite entries per round
	var many := _draws(9, ["m15", "m16", "m17", "m18", "m19", "m07", "m08"], 250)
	var guests := 0
	for c in many:
		if not _cues("haven_day").has(String(c)):
			guests += 1
	assert_true(guests <= 250 * Selector.FAV_BONUS_PER_ROUND / (3 + Selector.FAV_BONUS_PER_ROUND) + 4, "favourites are never the main thing playing (%d guests of 250)" % guests)
	for base in _cues("haven_day"):
		assert_true(_count(many, String(base)) >= 45, "%s still plays every round (%d)" % [base, _count(many, String(base))])
	# night rotation too, and no favourites = exactly the plain shuffle bag
	var night := _draws(10, ["m17"], 60, "haven_night")
	assert_true(night.has("m17") and night.has("m05") and night.has("m06"), "night: %s" % str(night))
	var plain := _sel(11)
	var fav_none := _sel(11)
	for i in 30:
		assert_eq(fav_none.draw_favoured("haven_day"), plain.draw("haven_day"), "without favourites nothing changes")


func test_unknown_and_unplayable_favourites_are_ignored() -> void:
	var s := _sel(12, {}, {"m16": false})
	s.set_favourites(["m99", "m16", "m13", "m12", "m10", "m17", "m17"])
	assert_eq(s.usable_favourites(), ["m17"], "known, playable, safe/explore/ending, once")
	var seq: Array = []
	for i in 40:
		seq.append(String(s.draw_favoured("haven_day")))
	for c in seq:
		assert_true(_cues("haven_day").has(c) or c == "m17", "only the Haven and m17: %s" % c)
	# one playable piece that is also the only favourite: it simply repeats, the bag never grows
	var one := _sel(13, {}, {"m03": false, "m04": false})
	one.set_favourites(["m02"])
	for i in 30:
		assert_eq(String(one.draw_favoured("haven_day")), "m02")
		one.set("_last_played", "m02")
	var bags: Dictionary = one.get("_bags")
	assert_true((bags.get("haven_day" + Selector.FAV_BAG_SUFFIX, []) as Array).size() <= 2, "bounded bag: %s" % str(bags))


func test_favourites_join_the_haven_rotation_only_at_home() -> void:
	var s := _sel(31)
	var c := _ctx("surface", "haven", {"favourites": ["m15"]})
	var played: Array = []
	for i in 800:
		var d: Dictionary = s.update(c, 0.2)
		_feed(c, d)
		if String(d["action"]) == "play":
			played.append(String(d["cue"]))
		elif i % 40 == 39:
			c["audio_track"] = ""        # the non-looping piece reached its end
	assert_eq(s.favourites, ["m15"], "favourites arrive through the context")
	assert_true(played.has("m15"), "the favourite joins the Haven rotation (%s)" % str(played))
	var own := 0
	for p in played:
		if _cues("haven_day").has(p):
			own += 1
	assert_true(own > played.size() / 2, "mostly the Haven's own pieces (%s)" % str(played))
	for i in played.size() - 1:
		assert_ne(played[i], played[i + 1], "no piece twice in a row")
	# the woods rotation is not weighted
	var w := _sel(32)
	var wc := _ctx("surface", "", {"favourites": ["m15"]})
	var wp: Array = []
	for i in 800:
		var d: Dictionary = w.update(wc, 0.2)
		_feed(wc, d)
		if String(d["action"]) == "play":
			wp.append(String(d["cue"]))
		elif i % 40 == 39:
			wc["audio_track"] = ""
	assert_true(wp.size() >= 3, "the woods rotate (%s)" % str(wp))
	assert_false(wp.has("m15"), "favourites never play in the woods")
	# an authored "haven" request elsewhere (the Works' remembered fragment) stays the plain Haven playlist
	for sd in 20:
		var r := _sel(100 + sd)
		var rc := _ctx("hushed_works", "hw_porch", {"favourites": ["m15", "m17"]})
		_feed(rc, r.update(rc, 0.2))
		r.request("haven", 1.0, "hushed_works")
		var rd := _first(_run(r, rc, 60.0), "play")
		assert_eq(String(rd.get("context", "")), "haven", "the authored fragment plays")
		assert_true(_cues("haven_day").has(String(rd.get("cue", ""))), "authored Haven fragment: %s" % str(rd.get("cue", "")))


func test_global_rng_is_untouched_by_previews_and_favourites() -> void:
	seed(777)
	var expected := [randi(), randi(), randi()]
	seed(777)
	var s := _sel(41)
	var c := _ctx("surface", "haven", {"favourites": ["m15", "m03"]})
	for i in 400:
		if i % 97 == 10:
			s.request_preview("m17", 1.5, "surface")
		if i % 97 == 40:
			s.stop_preview(1.5)
		c["threat"] = (i / 60) % 5 == 3
		var d: Dictionary = s.update(c, 0.25)
		_feed(c, d)
		if i % 30 == 29:
			c["audio_track"] = ""
	for i in 50:
		s.draw_favoured("haven_day")
	assert_eq([randi(), randi(), randi()], expected, "music never consumes the global RNG")
