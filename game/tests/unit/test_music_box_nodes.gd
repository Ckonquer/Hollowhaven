extends "res://tests/test_case.gd"
## Music Box end to end (MP 18.3): a music director node driving Audio (tiny fades) previews a discovered song
## over the Haven, a boss / ordinary combat takes over and ends it, Stop brings the Haven back; the Music Box
## structure spins while its preview plays and stops it when Krystal leaves the house, faints or dismantles
## it; the panel (instanced directly) lists discovered songs by title with their place, plays / stops /
## favourites them and works with the sound muted; without a director the legacy fallback still plays.

const MusicData := preload("res://data/music.gd")
const MusicBox := preload("res://src/audio/music_box.gd")
const Director := preload("res://src/audio/music_director.gd")
const BoxScript := preload("res://src/building/structures/music_box.gd")
const PanelScript := preload("res://src/ui/panels/music_box_panel.gd")
const UiUtil := preload("res://src/ui/ui_util.gd")


class FakeUi extends Node:
	var opened: Array = []

	func has_panel(n: String) -> bool:
		return n == "music_box"

	func open(n: String, a: Dictionary = {}) -> void:
		opened.append([n, a])


var _d: Node = null
var _was_enabled := true
var _saved: Dictionary = {}
var _cues: Array = []
var _captions: Array = []
var _nodes: Array = []
var _ui_was: Node = null
var _listening_was := false


func before_each() -> void:
	fresh_state()
	UiUtil.allow_settings_save = false
	_saved = {}
	for k in ["master_volume", "music_volume"]:
		_saved[k] = Settings.get_value(k)
		Settings.set_value(k, 1.0)
	_was_enabled = Audio.music_director_active()
	Audio.set_music_director_enabled(false)
	Audio.stop_all()
	_cues = []
	_captions = []
	_nodes = []
	_ui_was = Game.ui
	_listening_was = MusicBox.is_listening()
	Events.music_cue_changed.connect(_on_cue)
	Events.caption.connect(_on_caption)
	await wait_frames(2)


func after_each() -> void:
	MusicBox.director_override = null
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	if _d != null and is_instance_valid(_d):
		_d.queue_free()
	_d = null
	if Events.music_cue_changed.is_connected(_on_cue):
		Events.music_cue_changed.disconnect(_on_cue)
	if Events.caption.is_connected(_on_caption):
		Events.caption.disconnect(_on_caption)
	Game.ui = _ui_was
	if not _listening_was:
		MusicBox.shutdown()
	Audio.stop_all()
	await wait_seconds(0.05)
	Audio.set_music_director_enabled(_was_enabled)
	for k in _saved:
		Settings.set_value(k, _saved[k])
	GameState.active = false


func _on_cue(cue: String) -> void:
	_cues.append(cue)


## Waits until `cond` holds (or max_s passed): music decisions land on beats / after short rests.
func _until(cond: Callable, max_s: float) -> void:
	var t := 0.0
	while t < max_s and not bool(cond.call()):
		await wait_seconds(0.05)
		t += 0.05


func _on_caption(text: String) -> void:
	_captions.append(text)


func _director(ctx: Dictionary) -> Node:
	var t := {"rest_scale": 0.01, "region_enter_s": 0.2, "min_dwell_s": 0.2, "combat_enter_s": 0.1,
		"combat_release_s": [0.2, 0.3]}
	var d: Node = Director.new()
	d.setup({"fade_scale": 0.01, "tick_s": 0.05, "ctx": ctx, "tuning": t, "seed": 3})
	add_child(d)
	_d = d
	MusicBox.director_override = d
	return d


func _home_ctx() -> Dictionary:
	return {"mode": "playing", "area": "surface", "zone": "haven", "night": false}


func _track(cue: String) -> String:
	return String(MusicData.CUES[cue]["track"])


func _have(cue: String) -> bool:
	return Audio.has_sound(_track(cue), true)


func _haven_tracks() -> Array:
	var out: Array = []
	for c in (MusicData.PLAYLISTS["haven_day"]["cues"] as Array):
		if _have(String(c)):
			out.append(_track(String(c)))
	return out


func _box() -> Node3D:
	var b: Node3D = BoxScript.new()
	b.setup({"uid": "mb_test", "id": "music_box"})
	add_child(b)
	_nodes.append(b)
	b.where_override = {"area": "surface", "zone": "haven", "pos": Vector3.ZERO, "mode": "playing"}
	return b


func _texts(n: Node, out: Array) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _has(texts: Array, fragment: String) -> bool:
	for t in texts:
		if String(t).contains(fragment):
			return true
	return false


# --- director + Audio ---------------------------------------------------------------------------------------------

func test_preview_over_the_haven_then_boss_and_combat_take_over() -> void:
	var d := _director(_home_ctx())
	await wait_seconds(0.3)
	var haven := _haven_tracks()
	assert_true(haven.has(Audio.current_music()), "the Haven plays (%s)" % Audio.current_music())
	var box := _box()
	assert_true(MusicBox.preview("m01", box), "the starter tune can be previewed")
	assert_eq(Audio.current_music(), "music_title", "it plays at once")
	assert_eq(MusicBox.preview_cue(), "m01")
	assert_true(_cues.has("m01"), "music_cue_changed(m01)")
	assert_true(box.is_previewing() and box.is_processing(), "the box's dancer turns")
	assert_true(_has(_captions, "A Little Light"), "a caption names the song (for play without sound)")
	await wait_seconds(0.3)
	assert_eq(Audio.current_music(), "music_title", "the Haven rotation leaves it alone")
	# a boss outranks it and ends it
	Events.boss_health_changed.emit("weaver_matron", 200.0, 240.0)
	assert_eq(Audio.current_music(), "music_boss", "the boss piece starts at once")
	assert_eq(MusicBox.preview_cue(), "", "the preview is over")
	Events.boss_health_changed.emit("weaver_matron", -1.0, 240.0)
	await _until(func() -> bool: return haven.has(Audio.current_music()), 3.0)
	await wait_seconds(0.6)                     # the box's twice-a-second check
	assert_true(haven.has(Audio.current_music()), "then the Haven, not the preview (%s)" % Audio.current_music())
	assert_false(box.is_previewing(), "the dancer stopped once the preview ended")
	# Stop
	assert_true(MusicBox.preview("m01", box))
	assert_eq(Audio.current_music(), "music_title")
	MusicBox.stop_preview()
	assert_eq(MusicBox.preview_cue(), "")
	await _until(func() -> bool: return haven.has(Audio.current_music()), 3.0)
	assert_true(haven.has(Audio.current_music()), "Stop: the Haven returns (%s)" % Audio.current_music())
	# ordinary combat
	if _have("m10"):
		assert_true(MusicBox.preview("m01", box))
		Events.combat_state_changed.emit(true)
		for i in 30:                               # enters on the next beat (m01: 0.79 s); generous under load
			await wait_seconds(0.1)
			if Audio.current_music() == _track("m10"):
				break
		assert_eq(Audio.current_music(), _track("m10"), "combat music outranks the preview (log %s)" % str(d.get_debug_log().slice(-8)))
		assert_eq(MusicBox.preview_cue(), "")
		Events.combat_state_changed.emit(false)
		await wait_seconds(1.0)
	assert_true(d.state().has("preview"), "state() reports the preview")
	var notes := 0
	for e in d.get_debug_log():
		if String((e as Dictionary)["reason"]).contains("music box"):
			notes += 1
	assert_true(notes >= 2, "the decision log explains previews (%d notes)" % notes)


func test_favourites_reach_the_director_context() -> void:
	var d := _director(_home_ctx())
	MusicBox.note_heard("m17", "hallowmere_reach", "hr_orchard")
	MusicBox.set_favourite("m17", true)
	await wait_seconds(0.2)
	assert_eq(d.last_context.get("favourites"), ["m17"], "gathered from the save")
	assert_eq(d.selector.favourites, ["m17"], "handed to the selector")
	assert_eq(d.selector.usable_favourites(), ["m17"] if _have("m17") else [], "used when its file exists")
	MusicBox.set_favourite("m17", false)
	await wait_seconds(0.2)
	assert_eq(d.selector.favourites, [], "un-favouriting reaches it too")


# --- the structure --------------------------------------------------------------------------------------------------

func test_box_stops_its_preview_when_krystal_leaves_the_house() -> void:
	_director(_home_ctx())
	await wait_seconds(0.2)
	var box := _box()
	var spinner: Node3D = box.parts.get("spinner")
	assert_not_null(spinner, "the model has its dancer")
	assert_true(MusicBox.preview("m01", box))
	var r0 := spinner.rotation.y
	await wait_seconds(0.3)
	assert_true(spinner.rotation.y > r0, "the dancer turns while it plays")
	assert_true(box.check_preview(), "at home: it plays on")
	box.where_override["zone"] = "meadow"
	box.where_override["pos"] = Vector3(6, 0, 3)
	assert_true(box.check_preview(), "just outside the Haven zone but next to the box: still home")
	box.where_override["pos"] = Vector3(30, 0, 0)
	await wait_seconds(0.7)                        # the throttled check (twice a second) notices
	assert_eq(MusicBox.preview_cue(), "", "leaving the house stops the preview")
	assert_false(box.is_previewing())
	assert_false(box.is_processing(), "and the box stops processing")
	assert_true(_has(_captions, "winds down"), "a caption says so")
	# another area / fainting
	box.where_override = {"area": "surface", "zone": "haven", "pos": Vector3.ZERO, "mode": "playing"}
	assert_true(MusicBox.preview("m01", box))
	box.where_override["mode"] = "dead"
	assert_false(box.check_preview(), "fainting stops it")
	assert_eq(MusicBox.preview_cue(), "")
	box.where_override = {"area": "hallowmere_reach", "zone": "", "pos": Vector3.ZERO, "mode": "playing"}
	assert_true(MusicBox.preview("m01", box))
	assert_false(box.check_preview(), "another area stops it")
	# a preview started from another box is not this box's business
	box.where_override = {"area": "surface", "zone": "haven", "pos": Vector3.ZERO, "mode": "playing"}
	var other := _box()
	assert_true(MusicBox.preview("m01", box))
	assert_true(MusicBox.preview("m01", other))
	assert_false(box.check_preview(), "the first box lets go")
	assert_true(other.check_preview())
	# dismantling the playing box stops it
	other.play_remove_and_free()
	assert_eq(MusicBox.preview_cue(), "", "a dismantled box stops its song")


func test_outpost_box_plays_while_she_stays_beside_it() -> void:
	_director({"mode": "playing", "area": "hallowmere_reach", "zone": "hr_commons", "night": false})
	await wait_seconds(0.2)
	GameState.structures["mb_out"] = {"id": "music_box", "area": "hallowmere_reach", "pos": [0.0, 0.0, 0.0], "rot": 0.0, "data": {}}
	var box: Node3D = BoxScript.new()
	box.setup({"uid": "mb_out", "id": "music_box"})
	add_child(box)
	_nodes.append(box)
	assert_eq(box.home_area(), "hallowmere_reach", "the box knows where it stands (its saved record)")
	box.where_override = {"area": "hallowmere_reach", "zone": "hr_commons", "pos": Vector3(3, 0, 2), "mode": "playing"}
	assert_true(MusicBox.preview("m01", box), "a preview at the Reach outpost")
	assert_eq(Audio.current_music(), "music_title", "it plays over the Reach's own music")
	await wait_seconds(0.7)                        # past the twice-a-second house check
	assert_eq(MusicBox.preview_cue(), "m01", "beside the outpost box it plays on")
	assert_true(box.is_previewing())
	assert_false(_has(_captions, "winds down"), "no 'winds down behind you' while she stands beside it")
	box.where_override["pos"] = Vector3(30, 0, 0)
	await wait_seconds(0.7)
	assert_eq(MusicBox.preview_cue(), "", "walking away from the outpost stops it")
	assert_false(box.is_previewing())


func test_a_preview_is_refused_while_higher_music_is_on() -> void:
	_director(_home_ctx())
	await wait_seconds(0.3)
	var box := _box()
	var p := _panel(box)
	await wait_frames(3)
	# a boss fight is on
	Events.boss_health_changed.emit("weaver_matron", 200.0, 240.0)
	assert_eq(Audio.current_music(), "music_boss", "setup: the boss piece plays")
	_captions.clear()
	assert_false(MusicBox.preview("m01", box), "no preview over a boss")
	assert_eq(MusicBox.preview_cue(), "")
	assert_eq(Audio.current_music(), "music_boss", "the boss music is untouched")
	assert_false(box.is_previewing(), "the dancer stays still")
	assert_false(_has(_captions, "A Little Light"), "no caption claims the song plays: %s" % str(_captions))
	((p.row("m01") as Dictionary)["play"] as Button).emit_signal("pressed")
	assert_true(_has(_texts(p, []), PanelScript.FAILED_TEXT), "the panel says it can't play right now")
	assert_true(_has(_texts(p, []), PanelScript.QUIET_TEXT), "and nothing is 'Now playing'")
	Events.boss_health_changed.emit("weaver_matron", -1.0, 240.0)
	# an authored horror silence
	Events.music_context_changed.emit("silence")
	assert_false(MusicBox.preview("m01", box), "no preview during a horror silence")
	assert_false(box.is_previewing())
	Events.music_context_changed.emit("")
	await wait_seconds(0.2)
	# once the moment has passed it plays, and the panel's note goes away
	((p.row("m01") as Dictionary)["play"] as Button).emit_signal("pressed")
	assert_eq(MusicBox.preview_cue(), "m01", "afterwards the preview plays")
	assert_true(box.is_previewing())
	var t := _texts(p, [])
	assert_true(_has(t, "Now playing: A Little Light"), "the Now playing line: %s" % str(t))
	assert_false(_has(t, PanelScript.FAILED_TEXT), "the 'can't play' note is gone")
	MusicBox.stop_preview()


func test_box_opens_the_panel_or_winds_without_one() -> void:
	var box := _box()
	Game.ui = null
	assert_eq(String(box.get_interaction(null)["text"]), "Wind the music box", "no panel yet: the old wind-up")
	box.interact(null)
	assert_true(box.is_playing() and box.is_processing(), "it spins a while")
	assert_true(_has(_captions, "music box plays a little tune"), "caption for play without sound")
	box.interact(null)
	await wait_frames(2)
	assert_false(box.is_playing(), "let it rest")
	var ui := FakeUi.new()
	add_child(ui)
	_nodes.append(ui)
	Game.ui = ui
	assert_eq(String(box.get_interaction(null)["text"]), "Open the music box")
	box.interact(null)
	assert_eq(ui.opened.size(), 1, "opens the Music Box panel")
	assert_true(ui.opened.size() == 1 and String(ui.opened[0][0]) == "music_box")
	assert_true(ui.opened.size() == 1 and (ui.opened[0][1] as Dictionary).get("source") == box, "with the box as the source")
	assert_true(MusicBox.is_listening(), "a box wires the discovery listener (idempotent)")


# --- the panel ---------------------------------------------------------------------------------------------------------

func _panel(source: Node) -> Control:
	var p: Control = PanelScript.new()
	p.setup({"uid": "mb_test", "source": source})
	add_child(p)
	_nodes.append(p)
	return p


func test_panel_lists_plays_stops_and_favourites() -> void:
	_director(_home_ctx())
	await wait_seconds(0.2)
	MusicBox.note_heard("m02", "surface", "haven")
	MusicBox.note_heard("m05", "surface", "haven")
	MusicBox.note_heard("m17", "hallowmere_reach", "hr_orchard")
	var box := _box()
	var p := _panel(box)
	await wait_frames(3)
	var t := _texts(p, [])
	for want in ["A Little Light", "Home in the Clearing", "Lanterns After Dark", "Pumpkin Patch Parade"]:
		assert_true(_has(t, want), "lists %s: %s" % [want, str(t)])
	for place in ["Krystal's Haven", "Krystal's Haven, after dark", "Pumpkintide Orchard", "The music box's own tune"]:
		assert_true(_has(t, place), "with where it belongs: %s" % place)
	for never in ["Firefly Wishes", "The Thread Above", "Thorns in the Path", "Eyes That Stay Shut"]:
		assert_false(_has(t, never), "%s is not listed" % never)
	assert_true(_has(t, "4 of %d songs found" % MusicBox.eligible_cues().size()), "count: %s" % str(t))
	assert_true(_has(t, "The music box is quiet."))
	var stop: Button = p.find_child("Stop", true, false)
	assert_true(stop != null and stop.disabled, "Stop disabled while nothing plays")
	# Play
	var row: Dictionary = p.row("m17")
	var play17: Button = row.get("play")
	assert_not_null(play17)
	var cue := "m17" if _have("m17") else "m01"
	var play_btn: Button = (p.row(cue) as Dictionary)["play"]
	play_btn.emit_signal("pressed")
	assert_eq(MusicBox.preview_cue(), cue, "Play previews the song")
	assert_eq(Audio.current_music(), _track(cue), "and it sounds")
	assert_true(box.is_previewing(), "from this box")
	t = _texts(p, [])
	assert_true(_has(t, "Now playing: %s" % MusicBox.title(cue)), "the Now playing line: %s" % str(t))
	assert_eq(play_btn.text, "Playing")
	assert_false(stop.disabled)
	# Favourite
	var fav: CheckButton = (p.row("m02") as Dictionary)["fav"]
	fav.button_pressed = true
	assert_true(MusicBox.is_favourite("m02"), "the toggle saves a favourite")
	assert_true(_has(_texts(p, []), "1 favourite"), "and the panel says so")
	fav.button_pressed = false
	assert_false(MusicBox.is_favourite("m02"))
	# Stop
	stop.emit_signal("pressed")
	assert_eq(MusicBox.preview_cue(), "", "Stop")
	assert_true(_has(_texts(p, []), "The music box is quiet."))
	assert_true(stop.disabled)
	# a song heard while the panel is open appears on the next poll
	MusicBox.note_heard("m09", "surface", "pond")
	await wait_seconds(0.7)
	t = _texts(p, [])
	assert_true(_has(t, "Ripples at Mirror Pond") and _has(t, "Mirror Pond"), "new song listed: %s" % str(t))
	# the box is dismantled while the panel is open: the panel closes itself
	var closed := [false]
	p.close_requested.connect(func() -> void: closed[0] = true)
	box.queue_free()
	await wait_seconds(0.7)
	assert_true(bool(closed[0]), "the panel asks to close when its box is gone")


func test_panel_steps_aside_when_krystal_is_hurt() -> void:
	var p := _panel(_box())
	await wait_frames(2)
	var closed := [false]
	p.close_requested.connect(func() -> void: closed[0] = true)
	Events.player_damaged.emit(8.0, null)
	assert_true(bool(closed[0]), "a hit closes the Music Box panel (it holds Krystal still, like the Friends menu)")


func test_panel_and_preview_work_with_the_sound_off() -> void:
	_director(_home_ctx())
	await wait_seconds(0.2)
	Settings.set_value("music_volume", 0.0)
	await wait_frames(2)
	assert_true(MusicBox.music_muted(), "music bus muted at volume 0")
	var box := _box()
	var p := _panel(box)
	await wait_frames(3)
	assert_true(_has(_texts(p, []), "The sound is off"), "the panel says the sound is off")
	var mute_l: Label = null
	for l in p.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("The sound is off"):
			mute_l = l
	assert_true(mute_l != null and mute_l.visible, "visible")
	(p.row("m01") as Dictionary)["play"].emit_signal("pressed")
	assert_eq(MusicBox.preview_cue(), "m01", "the box still 'plays' (text, caption, dancer)")
	assert_true(_has(_texts(p, []), "Now playing: A Little Light"), "named on screen")
	assert_true(_has(_captions, "A Little Light"), "and in a caption")
	assert_true(box.is_previewing())
	(p.find_child("Stop", true, false) as Button).emit_signal("pressed")
	assert_eq(MusicBox.preview_cue(), "")
	Settings.set_value("music_volume", 1.0)
	await wait_seconds(0.7)
	assert_false(mute_l.visible, "the note goes once the sound is back")


func test_without_a_director_the_legacy_fallback_plays_and_stops() -> void:
	MusicBox.director_override = null
	assert_false(Audio.music_director_active(), "setup: director off")
	var box := _box()
	assert_true(MusicBox.preview("m01", box), "plays through Audio.request_music's fallback")
	assert_eq(Audio.current_music(), "music_title")
	assert_eq(MusicBox.preview_cue(), "m01")
	MusicBox.stop_preview(0.01)
	assert_eq(MusicBox.preview_cue(), "")
	assert_eq(Audio.current_music(), "", "stopped")
	assert_false(MusicBox.preview("m03"), "an undiscovered song never plays")
