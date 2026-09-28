extends "res://tests/test_case.gd"
## Music Box state (src/audio/music_box.gd, MP 18.3): which cues count as discovered (safe / explore / ending
## only, heard in play), the starter tune, favourites rules, where each piece belongs, the house-area rule,
## save / load through SaveSystem (GameState.extra["music_box"]) and tolerance of renamed cues and damaged
## sections (a save never fails because of them, and they are never dropped).

const MusicData := preload("res://data/music.gd")
const MusicBox := preload("res://src/audio/music_box.gd")
const Selector := preload("res://src/audio/music_selector.gd")

var _game_saved: Dictionary = {}
var _was_listening := false
var _director_was := true
var _notes: Array = []


func before_each() -> void:
	fresh_state()
	_director_was = Audio.music_director_active()
	Audio.set_music_director_enabled(false)      # no real music decisions while Game.mode is faked
	_game_saved = {"mode": Game.mode, "area_id": Game.area_id, "zone_id": Game.zone_id}
	_was_listening = MusicBox.is_listening()
	_notes = []
	if not Events.notify.is_connected(_on_notify):
		Events.notify.connect(_on_notify)


func after_each() -> void:
	for k in _game_saved:
		Game.set(k, _game_saved[k])
	if not _was_listening:
		MusicBox.shutdown()
	if Events.notify.is_connected(_on_notify):
		Events.notify.disconnect(_on_notify)
	GameState.active = false
	Audio.set_music_director_enabled(_director_was)


func _on_notify(text: String, _kind: String) -> void:
	_notes.append(text)


func _in_play(area: String = "surface", zone: String = "haven") -> void:
	GameState.active = true
	Game.mode = "playing"
	Game.area_id = area
	Game.zone_id = zone


func json_norm(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


# --- discovery --------------------------------------------------------------------------------------------------

func test_only_safe_explore_and_ending_cues_are_eligible() -> void:
	var eligible := 0
	for id in MusicData.CUES:
		var kind := String((MusicData.CUES[id] as Dictionary)["kind"])
		var want := ["safe", "explore", "ending"].has(kind)
		assert_eq(MusicBox.is_eligible(String(id)), want, "%s (%s)" % [id, kind])
		if want:
			eligible += 1
	assert_eq(MusicBox.eligible_cues().size(), eligible)
	for cue in ["m10", "m22", "m12", "m23", "m13", "m21", "m25", "m26"]:
		assert_false(MusicBox.note_heard(cue, "surface", "haven"), "%s (boss / combat / horror) is never discovered" % cue)
		assert_false(MusicBox.is_discovered(cue))
	assert_false(MusicBox.note_heard("m99", "surface", ""), "an unknown cue is ignored")
	assert_true(MusicBox.note_heard("m03", "surface", "haven"), "a Haven piece is discovered")
	assert_false(MusicBox.note_heard("m03", "hallowmere_reach", ""), "only once")
	assert_eq(MusicBox.heard_at("m03")["area"], "surface", "where it was first heard is kept")
	assert_eq(MusicBox.heard_at("m03")["zone"], "haven")
	assert_eq(MusicBox.discovered(), ["m01", "m03"], "starter tune + what was heard, catalogue order")


func test_starter_tune_is_always_there() -> void:
	assert_eq(MusicBox.discovered(), ["m01"], "a brand-new journey: the music box's own tune")
	assert_true(MusicBox.is_discovered("m01"))
	assert_false(MusicBox.note_heard("m01"), "nothing to record for it")
	assert_false(GameState.extra.has(MusicBox.STATE_KEY), "reading never writes the save")


func test_heard_in_play_through_events() -> void:
	MusicBox.init()
	assert_true(MusicBox.is_listening())
	GameState.active = true
	Game.mode = "title"
	Events.music_cue_changed.emit("m02")
	assert_false(MusicBox.is_discovered("m02"), "the title screen is not play")
	_in_play("surface", "haven")
	GameState.active = false
	Events.music_cue_changed.emit("m02")
	assert_false(MusicBox.is_discovered("m02"), "no journey loaded")
	_in_play("surface", "haven")
	Events.music_cue_changed.emit("")
	Events.music_cue_changed.emit("m13")
	Events.music_cue_changed.emit("m10")
	Events.music_cue_changed.emit("m12")
	assert_eq(MusicBox.discovered(), ["m01"], "stops, boss, combat and horror cues are not songs for the box")
	Events.music_cue_changed.emit("m02")
	assert_true(MusicBox.is_discovered("m02"), "heard at home")
	assert_eq(_notes.size(), 0, "no toast before a music box stands in the Haven")
	GameState.structures["sb_test"] = {"id": "music_box", "area": "surface", "pos": [0.0, 0.0, 0.0], "rot": 0.0, "data": {}}
	_in_play("hallowmere_reach", "hr_orchard")
	Events.music_cue_changed.emit("m17")
	assert_true(MusicBox.is_discovered("m17"))
	assert_eq(MusicBox.heard_at("m17")["zone"], "hr_orchard")
	assert_eq(_notes.size(), 1, "a new song is announced once a box exists")
	assert_true(_notes.size() == 1 and String(_notes[0]).contains("Pumpkin Patch Parade"), str(_notes))
	Events.music_cue_changed.emit("m17")
	assert_eq(_notes.size(), 1, "only the first time")
	Game.mode = "cutscene"
	Events.music_cue_changed.emit("m14")
	assert_true(MusicBox.is_discovered("m14"), "the restoration reprise (a cutscene) counts")
	assert_eq(_notes.size(), 1, "but no toast over a cutscene")


# --- favourites ---------------------------------------------------------------------------------------------------

func test_favourite_rules() -> void:
	assert_false(MusicBox.set_favourite("m04", true), "an undiscovered song can't be a favourite")
	assert_false(MusicBox.set_favourite("m13", true), "nor a boss piece")
	assert_true(MusicBox.set_favourite("m01", true), "the starter tune can")
	MusicBox.note_heard("m04", "surface", "haven")
	assert_true(MusicBox.toggle_favourite("m04"), "toggled on")
	assert_false(MusicBox.set_favourite("m04", true), "already a favourite")
	assert_eq(MusicBox.favourites(), ["m01", "m04"])
	assert_eq(MusicBox.favourites_view(), ["m01", "m04"], "the saved list")
	assert_false(MusicBox.toggle_favourite("m01"), "toggled off")
	assert_eq(MusicBox.favourites(), ["m04"])
	assert_false(MusicBox.is_favourite("m01"))
	assert_true(MusicBox.is_favourite("m04"))


# --- where each piece belongs ---------------------------------------------------------------------------------------

func test_home_of_each_piece_comes_from_the_catalogue() -> void:
	var cases := {
		"m02": ["haven", "surface", "haven", false], "m03": ["haven", "surface", "haven", false],
		"m05": ["haven", "surface", "haven", true], "m06": ["haven", "surface", "haven", true],
		"m07": ["woods", "surface", "", false], "m09": ["pond", "surface", "pond", false],
		"m11": ["mine", "below", "mine", false], "m15": ["reach", "hallowmere_reach", "", false],
		"m16": ["reach", "hallowmere_reach", "", false], "m17": ["orchard", "hallowmere_reach", "hr_orchard", false],
		"m18": ["quarry", "hallowmere_reach", "hr_quarry", false], "m19": ["candleyard", "hallowmere_reach", "hr_candleyard", false],
		"m20": ["manor", "moonveil_manor", "", false], "m24": ["refuge", "hushed_works", "hw_refuge", false],
		"m01": ["title", "", "", false], "m14": ["restoration", "", "", false], "m27": ["celebration", "", "", false],
	}
	for cue in cases:
		var h := MusicBox.home_of(String(cue))
		var want: Array = cases[cue]
		assert_eq([h["context"], h["area"], h["zone"], h["night"]], want, "home of %s" % cue)
	for cue in MusicBox.eligible_cues():
		assert_ne(String(MusicBox.home_of(String(cue))["context"]), "", "%s belongs somewhere" % cue)
	assert_eq(MusicBox.home_of("m99")["context"], "", "unknown cue: nowhere, no error")


func test_house_area_rule() -> void:
	var box := Vector3(10, 0, 4)
	assert_false(MusicBox.should_stop("surface", "haven", Vector3(40, 0, 40), box), "anywhere in the Haven zone")
	assert_false(MusicBox.should_stop("surface", "meadow", box + Vector3(6, 0, 6), box), "next to a box in an overlapping landmark")
	assert_true(MusicBox.should_stop("surface", "", box + Vector3(20, 0, 0), box), "walked away from home")
	assert_true(MusicBox.should_stop("surface", "pond", Vector3(46, 0, 52), box))
	assert_true(MusicBox.should_stop("hallowmere_reach", "haven", box, box), "another area")
	# a box at the Reach outpost (build_ops.gd allows one at the Commons): home is beside that box
	var out := Vector3(-16, 0, 54)
	assert_false(MusicBox.should_stop("hallowmere_reach", "hr_commons", out + Vector3(4, 0, 3), out, "hallowmere_reach"),
		"standing by the outpost box: it plays on")
	assert_true(MusicBox.should_stop("hallowmere_reach", "hr_commons", out + Vector3(30, 0, 0), out, "hallowmere_reach"),
		"walked away from the outpost")
	assert_true(MusicBox.should_stop("surface", "haven", Vector3.ZERO, out, "hallowmere_reach"), "back in the Haven: not that box's home")
	assert_true(MusicBox.should_stop("hallowmere_reach", "haven", out + Vector3(30, 0, 0), out, "hallowmere_reach"),
		"the Haven-zone rule belongs to the surface only")


# --- persistence ---------------------------------------------------------------------------------------------------

func test_save_and_load_keep_discoveries_and_favourites() -> void:
	MusicBox.note_heard("m03", "surface", "haven")
	MusicBox.note_heard("m17", "hallowmere_reach", "hr_orchard")
	MusicBox.set_favourite("m17", true)
	assert_true(SaveSystem.save_game(true), "saved")
	fresh_state()
	assert_eq(MusicBox.discovered(), ["m01"], "a new journey starts empty")
	assert_eq(MusicBox.favourites(), [])
	assert_true(SaveSystem.load_game(), "loaded")
	assert_eq(MusicBox.discovered(), ["m01", "m03", "m17"], "discoveries come back")
	assert_eq(MusicBox.favourites(), ["m17"], "favourites come back")
	assert_eq(MusicBox.heard_at("m17")["zone"], "hr_orchard")
	# and a plain JSON round trip of the state (numbers become floats) changes nothing
	GameState.from_dict(json_norm(GameState.to_dict()))
	assert_eq(MusicBox.discovered(), ["m01", "m03", "m17"])
	assert_true(MusicBox.is_favourite("m17"))


func test_renamed_cues_are_kept_but_never_used() -> void:
	GameState.extra[MusicBox.STATE_KEY] = {"discovered": {"m03": {"area": "surface", "zone": "haven", "at": 500.0},
		"m99_old_name": {"area": "surface", "zone": "haven", "at": 510.0}},
		"favourites": ["m99_old_name", "m03", 7], "future_key": {"a": 1}}
	assert_eq(MusicBox.discovered(), ["m01", "m03"], "a renamed cue is not listed")
	assert_eq(MusicBox.favourites(), ["m03"], "nor played as a favourite")
	assert_false(MusicBox.is_discovered("m99_old_name"))
	assert_false(MusicBox.preview("m99_old_name"), "nor previewed")
	assert_true(MusicBox.set_favourite("m99_old_name", false), "but it can be un-favourited")
	MusicBox.set_favourite("m99_old_name", true)
	assert_false(MusicBox.favourites_view().has("m99_old_name"), "and never re-added")
	assert_true(SaveSystem.save_game(true), "the save never fails because of it")
	fresh_state()
	assert_true(SaveSystem.load_game())
	var st: Dictionary = GameState.extra.get(MusicBox.STATE_KEY, {})
	assert_true((st.get("discovered", {}) as Dictionary).has("m99_old_name"), "kept in the save (it may come back)")
	assert_eq(st.get("future_key"), {"a": 1.0}, "unknown keys of the section are kept too")
	assert_eq(MusicBox.discovered(), ["m01", "m03"])
	# the selector ignores unknown and ineligible favourites
	var s: RefCounted = Selector.new()
	s.setup(MusicData.catalogue(), 3)
	s.set_favourites(["m99_old_name", "m13", "m12", "m10", 5])
	assert_eq(s.usable_favourites(), [], "no boss / horror / combat / unknown piece joins a rotation")


func test_damaged_sections_read_as_empty_and_repair_on_write() -> void:
	GameState.extra[MusicBox.STATE_KEY] = "garbage"
	assert_eq(MusicBox.discovered(), ["m01"])
	assert_eq(MusicBox.favourites(), [])
	assert_eq(MusicBox.favourites_view(), [])
	assert_false(MusicBox.is_favourite("m01"))
	assert_true(MusicBox.note_heard("m02", "surface", "haven"), "writes repair the section")
	assert_true(GameState.extra[MusicBox.STATE_KEY] is Dictionary)
	GameState.extra[MusicBox.STATE_KEY] = {"discovered": ["m03", 7, "m99"], "favourites": "x"}
	assert_eq(MusicBox.discovered(), ["m01"], "a list instead of a map reads as nothing...")
	assert_true(MusicBox.note_heard("m04", "surface", "haven"))
	assert_eq(MusicBox.discovered(), ["m01", "m03", "m04"], "...and its ids are kept when repaired")
	assert_true(MusicBox.set_favourite("m04", true))
	assert_eq(MusicBox.favourites(), ["m04"])
	assert_true(SaveSystem.save_game(true), "still saves")
