extends "res://tests/test_case.gd"
## The Hushed Works horror layer: the additive WORKS_EVENTS table (Chapter One events untouched), the director
## fed through area.director_config(), quiet in safe rooms / quiet zones / held puzzle rooms and busy only
## where allowed; stacking-safe hold/release; the moments tracker's puzzle holds; "Hask's Last Knock" (true
## signal = a real lantern, false = dark corridors without light, once per save, intensity-dependent patience)
## and "The Companion at the Wrong Door" (a lightless fake behind bars, Gentle clue, Intense waits longer,
## folds on approach, once per save).

const Layout := preload("res://data/works_layout.gd")
const HorrorData := preload("res://data/horror_events.gd")
const Director := preload("res://src/horror/director.gd")
const Core := preload("res://src/horror/director_core.gd")
const WORLD := "res://src/world/areas_ch2/hushed_works_world.gd"

const KINDS := ["sound", "wrong_sound", "glimpse", "flicker", "notice", "scratch", "silence", "spawn", "stalker_pass"]
const STATES := ["calm", "unease", "anticipation", "encounter", "recovery"]
const ANCHOR_KINDS := ["", "sound", "doorway", "ceiling", "floor", "spawn"]


## Records what the area / moments ask of a director.
class FakeDirector extends Node:
	var holds: Dictionary = {}
	var suppressed: Array = []

	func hold(id: String) -> void:
		holds[id] = true

	func release(id: String) -> void:
		holds.erase(id)

	func suppress(seconds: float, _replace: bool = false) -> void:
		suppressed.append(seconds)


var area: Node3D = null
var _probe: Node3D = null
var _nodes: Array = []
var _captions: Array = []
var _says: Array = []
var _authored: Array = []
var _saved: Dictionary = {}


func before_each() -> void:
	fresh_state()
	_saved = {"horror_intensity": Settings.get_value("horror_intensity"), "reduce_flashing": Settings.get_value("reduce_flashing"),
		"captions": Settings.get_value("captions")}
	_captions = []
	_says = []
	_authored = []
	Events.caption.connect(_on_caption)
	Events.say.connect(_on_say)
	Events.horror_event.connect(_on_horror)


func after_each() -> void:
	Events.caption.disconnect(_on_caption)
	Events.say.disconnect(_on_say)
	Events.horror_event.disconnect(_on_horror)
	for k in _saved:
		Settings.set_value(String(k), _saved[k])
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes = []
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	_probe = null
	await wait_frames(2)


func _on_caption(t: String) -> void:
	_captions.append(t)


func _on_say(_s: String, t: String, _d: float) -> void:
	_says.append(t)


func _on_horror(id: String, _d: Dictionary) -> void:
	_authored.append(id)


func _make_area(fake_director: Node = null) -> Node3D:
	var a: Node3D = load(WORLD).new()
	a.use_deep = false
	if fake_director != null:
		a.director_override = fake_director
	add_child(a)
	await wait_physics(2)
	return a


func _probe_at(p: Vector3) -> Node3D:
	if _probe == null:
		_probe = Node3D.new()
		add_child(_probe)
		_nodes.append(_probe)
	_probe.global_position = p
	return _probe


# --- Data --------------------------------------------------------------------------------------------------------------------

func test_works_events_are_additive_and_consistent() -> void:
	for id in HorrorData.WORKS_EVENTS:
		assert_true(String(id).begins_with("hw_"), "%s is namespaced" % id)
		assert_false(HorrorData.EVENTS.has(id), "%s is not in the Chapter One table" % id)
		var ev: Dictionary = HorrorData.WORKS_EVENTS[id]
		assert_true(KINDS.has(String(ev["kind"])), "%s kind" % id)
		for z in ev["zones"]:
			assert_true(HorrorData.WORKS_ZONES.has(z), "%s zone %s is a works zone" % [id, z])
			assert_false(HorrorData.WORKS_QUIET_ZONES.has(z), "%s never fires in the quiet zone %s" % [id, z])
		for st in ev["states"]:
			assert_true(STATES.has(st), "%s state %s" % [id, st])
		assert_true(ANCHOR_KINDS.has(String(ev["anchor"])), "%s anchor" % id)
		assert_true(float(ev["weight"]) > 0.0 and float(ev["cooldown"]) > 0.0, "%s weight/cooldown" % id)
		assert_true(HorrorData.INTENSITY.has(int(ev["min_intensity"])), "%s min intensity" % id)
		if String(ev.get("sound", "")) != "":
			assert_true(Audio.has_sound(String(ev["sound"])), "%s sound %s exists" % [id, ev["sound"]])
		if bool(ev.get("spider", false)):
			assert_true(Audio.has_sound(String(ev.get("alt_sound", ""))), "%s has an arachnophobia sound" % id)
			assert_ne(String(ev.get("alt_caption", "")), "", "%s has an arachnophobia caption" % id)
		if String(ev["kind"]) == "spawn":
			assert_false(ItemDB.enemy(String(ev["enemy"])).is_empty(), "%s spawns a real enemy id" % id)
			assert_true(bool(ev["major"]), "%s: ambushes are major (never at Gentle, one at a time)" % id)
			assert_true(int(ev["min_intensity"]) >= 1, "%s: never at Gentle" % id)
	for ev_id in HorrorData.EVENTS:
		for z in HorrorData.EVENTS[ev_id]["zones"]:
			assert_true(["mine", "ruins", "silk"].has(z), "Chapter One events keep their zones")
	# Rooms 1-8 get ambient cues only where allowed; the lockers (taught fight) and the eyes hall are quiet.
	for z in ["hw_landing", "hw_lockers", "hw_eyes", "hw_refuge"]:
		assert_true(HorrorData.WORKS_QUIET_ZONES.has(z), "%s is quiet" % z)
	assert_eq(HorrorData.WORKS_PUZZLE_HOLDS, {"hw_sluice": "ch2_line_water", "hw_bells": "ch2_line_bell", "hw_lightwell": "ch2_line_light"})


# --- Director -------------------------------------------------------------------------------------------------------------------

func _director_for(a: Node3D, seed_value: int) -> Node:
	var d: Node = Director.new()
	d.setup({"area": a, "seed": seed_value})
	a.add_child(d)
	d.enabled = false
	return d


func test_director_takes_the_area_tables() -> void:
	area = await _make_area()
	var d := _director_for(area, 3)
	# Works events only; an ambush whose enemy cannot be built yet is left out (it would hiss, spawn nothing and retry).
	var factory: Script = load("res://src/enemies/enemy_factory.gd")
	var want: Array = []
	for id in HorrorData.WORKS_EVENTS:
		var ev: Dictionary = HorrorData.WORKS_EVENTS[id]
		var enemy := String(ev.get("enemy", ""))
		if String(ev["kind"]) != "spawn" or (bool(factory.call("has_enemy", enemy)) and ResourceLoader.exists(String(factory.call("script_path", enemy)))):
			want.append(String(id))
	var got: Array = (d.core.events as Dictionary).keys()
	want.sort()
	got.sort()
	assert_eq(got, want, "Works events only, ambushes only for enemies that exist")
	assert_eq((d.core.events as Dictionary).has("hw_wisp_drift"), bool(area.enemy_available("borrowed_wisp")), "hw_wisp_drift waits for borrowed_wisp")
	assert_false(bool(area.enemy_available("no_such_enemy")))
	assert_true((d.core.events as Dictionary).has("hw_rail_hum"))
	assert_true((d.core.director_zones as Dictionary).has("hw_rails"))
	assert_false((d.core.director_zones as Dictionary).has("mine"), "no Chapter One zones")
	var legacy: Node = Director.new()
	legacy.setup({"seed": 3})
	_nodes.append(legacy)
	assert_true((legacy.core.events as Dictionary).has("distant_pickaxe"), "a director without area tables keeps Chapter One's")
	assert_eq((legacy.core.events as Dictionary).size(), HorrorData.EVENTS.size())
	var explicit: Node = Director.new()
	explicit.setup({"seed": 3, "events": {"x": {"kind": "sound", "zones": ["zz"]}}})
	_nodes.append(explicit)
	assert_eq((explicit.core.events as Dictionary).keys(), ["x"], "explicit params win")


func test_director_is_quiet_in_safe_and_quiet_zones_and_busy_in_the_rails() -> void:
	Settings.set_value("horror_intensity", 1)
	area = await _make_area()
	var player := Node3D.new()
	player.add_to_group("player")
	area.add_child(player)
	_nodes.append(player)
	var d := _director_for(area, 11)
	for place in [["refuge", Vector3(30.0, -18.0, 8.0)], ["landing", Vector3(-70.0, -6.0, 2.0)], ["lockers", Vector3(-47.0, -7.0, 0.0)], ["eyes", Vector3(-14.5, -13.0, 25.0)]]:
		player.global_position = place[1]
		var fired := 0
		var reason := ""
		for i in 240:
			var dec: Dictionary = d.tick_now(1.0)
			if String(dec.get("event_id", "")) != "":
				fired += 1
			reason = String(dec.get("reason", ""))
		assert_eq(fired, 0, "nothing happens in the %s" % place[0])
		assert_true(reason.contains("safe") or reason.contains("quiet"), "%s: %s" % [place[0], reason])
	# The rail hall: the director acts now and then (ambient cues; the room has lamps and anchors).
	player.global_position = Vector3(-20.0, -11.0, 0.0)
	var got: Array = []
	for i in 600:
		var dec: Dictionary = d.tick_now(1.0)
		if String(dec.get("event_id", "")) != "":
			got.append(String(dec["event_id"]))
	assert_true(got.size() >= 2, "a few cues in 10 minutes in the rail hall: %s" % str(got))
	for e in got:
		assert_true(HorrorData.WORKS_EVENTS.has(e), "%s is a Works event" % e)
		assert_true((HorrorData.WORKS_EVENTS[e]["zones"] as Array).has("hw_rails"), "%s allowed in the rails" % e)
	assert_true(got.size() <= 40, "never a barrage (%d)" % got.size())
	# A hold silences it completely; releasing lets it continue.
	d.hold("puzzle:test")
	d.hold("boss:test")
	var held := 0
	var reason2 := ""
	for i in 300:
		var dec: Dictionary = d.tick_now(1.0)
		if String(dec.get("event_id", "")) != "":
			held += 1
		reason2 = String(dec.get("reason", ""))
	assert_eq(held, 0, "held: nothing fires")
	assert_true(reason2.contains("held"), "the log says why: %s" % reason2)
	d.release("puzzle:test")
	assert_true(bool(d.is_held()), "one hold never releases another")
	d.release("boss:test")
	assert_false(bool(d.is_held()))
	var after := 0
	for i in 600:
		if String((d.tick_now(1.0) as Dictionary).get("event_id", "")) != "":
			after += 1
	assert_true(after >= 1, "cues resume after the holds end")


func test_moments_hold_unsolved_puzzle_rooms() -> void:
	var fake := FakeDirector.new()
	_nodes.append(fake)
	area = await _make_area(fake)
	var m: Node = area.moments
	m.check(_probe_at(Vector3(26.0, -20.0, -31.0)), 0.1)
	assert_true(fake.holds.has("puzzle:hw_sluice"), "the sluice holds the director while unsolved")
	m.check(_probe_at(Vector3(12.0, -16.0, 34.0)), 0.1)
	assert_false(fake.holds.has("puzzle:hw_sluice"), "released on leaving")
	assert_true(fake.holds.has("puzzle:hw_bells"), "the bells hold it")
	GameState.set_flag("ch2_line_bell", true)
	m.check(_probe, 0.1)
	assert_false(fake.holds.has("puzzle:hw_bells"), "released once the line is restored")
	m.check(_probe_at(Vector3(-20.0, -11.0, 0.0)), 0.1)
	assert_true(fake.holds.is_empty(), "no hold in the rail hall")
	m.check(_probe_at(Vector3(32.5, -20.0, 30.0)), 0.1)
	assert_true(fake.holds.has("puzzle:hw_lightwell"))
	# The area re-applies requested holds to a director that shows up later.
	var late := FakeDirector.new()
	_nodes.append(late)
	area.director_override = late
	area._sync_director_holds(0.5)
	assert_true(late.holds.has("puzzle:hw_lightwell"), "holds survive a director (re)start")


# --- Hask's Last Knock -----------------------------------------------------------------------------------------------------------

func _walk_then_stand(m: Node, seconds_still: float) -> void:
	for i in 12:
		m.check(_probe_at(Vector3(-28.0 + float(i) * 0.8, -11.0, 0.0)), 0.1)
	var t := 0.0
	while t < seconds_still:
		m.check(_probe, 0.1)
		t += 0.1


func test_hasks_last_knock_true_light_and_false_dark() -> void:
	Settings.set_value("horror_intensity", 1)
	var fake := FakeDirector.new()
	_nodes.append(fake)
	area = await _make_area(fake)
	var m: Node = area.moments
	_walk_then_stand(m, 1.5)
	assert_eq(String(m.knock_state), "armed", "Standard: not yet after 1.5 s still")
	_walk_then_stand(m, 0.0)
	var t := 0.0
	while t < 2.2 and String(m.knock_state) != "knocking":
		m.check(_probe, 0.1)
		t += 0.1
	assert_eq(String(m.knock_state), "knocking", "the rails answer once she has stood still")
	assert_true(bool(GameState.get_flag(Layout.MOMENT_KNOCK)), "flag set first")
	assert_true(_authored.has("authored:hw_knock"), "authored event")
	assert_true(fake.suppressed.has(45.0), "director suppressed")
	for i in 60:
		m.check(_probe, 0.1)
	assert_eq(String(m.knock_state), "done")
	var src: Array = m.knock_sources
	assert_eq(src.size(), 3, "three answers")
	assert_eq(src.map(func(s: Dictionary) -> bool: return bool(s["true"])), [false, false, true], "two false, then the true one")
	assert_eq(int(area.signal_lamp.pulses), 1, "the true lantern visibly swings and brightens")
	assert_true(_captions.size() >= 3, "each answer is captioned")
	# Source rule (MP §14): a real Light3D next to the true signal, none near the false ones.
	var lights: Array = area.find_children("*", "Light3D", true, false)
	var near_true := false
	for l in lights:
		var lp: Vector3 = (l as Light3D).global_position
		if lp.distance_to(Layout.KNOCK_TRUE) <= 2.0:
			near_true = true
		for fp in Layout.KNOCK_FALSE:
			assert_true(lp.distance_to(fp) > 4.0, "no light near the false signal at %s (%s)" % [str(fp), l.name])
	assert_true(near_true, "the true signal has a real light within 2 m")
	assert_true(area.signal_lamp.is_in_group("light_source"), "it counts as light for Combat.light_at")
	assert_false(area.signal_lamp.is_in_group("flicker_light"), "a true light never stutters for the director")
	for g in area.false_glints:
		assert_eq((g as Node).find_children("*", "Light3D", true, false).size(), 0, "a false glint casts no light")
	# Once per save: a fresh tracker never replays it.
	var m2: Node = load("res://src/world/works/works_moments.gd").new()
	m2.setup(area)
	area.add_child(m2)
	_nodes.append(m2)
	_walk_then_stand(m2, 5.0)
	assert_eq(String(m2.knock_state), "done", "already heard: stays done")
	assert_eq((m2.knock_sources as Array).size(), 0, "no second knock")


func test_knock_patience_and_captions_by_intensity() -> void:
	Settings.set_value("horror_intensity", 2)
	area = await _make_area(FakeDirector.new())
	_nodes.append(area.director_override)
	var m: Node = area.moments
	_walk_then_stand(m, 3.0)
	assert_eq(String(m.knock_state), "armed", "Intense waits longer (3 s is not enough)")
	_walk_then_stand(m, 3.7)
	assert_eq(String(m.knock_state), "knocking", "Intense answers after 3.5 s")
	area.queue_free()
	await wait_frames(2)
	fresh_state()
	_captions.clear()
	Settings.set_value("horror_intensity", 0)
	area = await _make_area(FakeDirector.new())
	_nodes.append(area.director_override)
	m = area.moments
	_walk_then_stand(m, 1.6)
	assert_eq(String(m.knock_state), "knocking", "Gentle answers after 1.5 s")
	for i in 60:
		m.check(_probe, 0.1)
	var explicit := false
	for c in _captions:
		if String(c).contains("nothing there holds a light"):
			explicit = true
	assert_true(explicit, "Gentle names which source has no light: %s" % str(_captions))
	var clue := false
	for s in _says:
		clue = clue or String(s).contains("lights the floor")
	assert_true(clue, "Gentle explains the rule afterwards")


# --- The Companion at the Wrong Door -------------------------------------------------------------------------------------------

func test_wrong_door_fake_is_lightless_behind_bars_and_folds() -> void:
	Settings.set_value("horror_intensity", 1)
	var fake_dir := FakeDirector.new()
	_nodes.append(fake_dir)
	area = await _make_area(fake_dir)
	var m: Node = area.moments
	m.check(_probe_at(Vector3(-14.5, -13.0, 13.0)), 0.1)
	assert_null(m.fake, "not at the hall's mouth yet")
	m.check(_probe_at(Vector3(-14.5, -13.0, 16.0)), 0.1)
	var f: Node3D = m.fake
	assert_not_null(f, "the fake appears")
	if f == null:
		return
	assert_true(bool(GameState.get_flag(Layout.MOMENT_WRONG_DOOR)), "flag set first")
	assert_true(_authored.has("authored:hw_wrong_door"))
	assert_true(fake_dir.suppressed.has(60.0))
	await wait_frames(1)
	assert_eq(f.find_children("*", "Light3D", true, false).size(), 0, "its light lights nothing (no Light3D)")
	assert_false(f.is_in_group("light_source"))
	assert_eq(area.room_at(f.global_position + Vector3.UP * 0.3), "", "it stands where nobody can go")
	# the grate: a player capsule cannot reach it
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	q.shape = cap
	q.collision_mask = 1 | 32
	q.transform = Transform3D(Basis.IDENTITY, Vector3(-11.0, -13.0 + 1.05, 21.5))
	q.motion = Vector3(4.0, 0.0, 0.0)
	var r := area.get_world_3d().direct_space_state.cast_motion(q)
	assert_true(float(r[0]) < 1.0, "the grate blocks the way to it")
	# a real light beside the grate does light the hall floor
	var lit_floor := false
	for l in area.find_children("*", "OmniLight3D", true, false):
		if (l as Node3D).global_position.distance_to(Vector3(-9.5, -11.0, 18.3)) < 1.5:
			lit_floor = true
	assert_true(lit_floor, "the real lamp beside the grate")
	# still at first (Standard 2.5 s), then it moves; approaching folds it away.
	assert_false(bool(f.get("active")), "perfectly still at first")
	for i in 27:
		m.check(_probe, 0.1)
	assert_true(bool(f.get("active")), "then its wrong movement starts")
	m.check(_probe_at(Vector3(-10.4, -13.0, 21.5)), 0.1)
	assert_true(bool(GameState.get_flag(Layout.MOMENT_WRONG_DOOR_FOLDED)), "approaching folds it")
	assert_null(m.fake)
	# Once per save.
	var m2: Node = load("res://src/world/works/works_moments.gd").new()
	m2.setup(area)
	area.add_child(m2)
	_nodes.append(m2)
	m2.check(_probe_at(Vector3(-14.5, -13.0, 20.0)), 0.1)
	assert_null(m2.fake, "never again in this save")


func test_wrong_door_intensity_variants() -> void:
	Settings.set_value("horror_intensity", 2)
	area = await _make_area(FakeDirector.new())
	_nodes.append(area.director_override)
	var m: Node = area.moments
	m.check(_probe_at(Vector3(-14.5, -13.0, 16.0)), 0.1)
	assert_eq(float(m.fake_still_left), float(Layout.FAKE_STILL_SECONDS[2]), "Intense: the illusion waits longest")
	for i in 40:
		m.check(_probe, 0.1)
	assert_false(bool(m.fake.get("active")), "still after 4 s at Intense")
	assert_eq(_says.size(), 0, "no explicit clue line at Intense")
	# Leaving the hall makes it vanish (it never follows).
	m.check(_probe_at(Vector3(-20.0, -11.0, 0.0)), 0.1)
	assert_null(m.fake, "gone once she leaves the hall")
	area.queue_free()
	await wait_frames(2)
	fresh_state()
	Settings.set_value("horror_intensity", 0)
	area = await _make_area(FakeDirector.new())
	_nodes.append(area.director_override)
	m = area.moments
	m.check(_probe_at(Vector3(-14.5, -13.0, 16.0)), 0.1)
	assert_eq(float(m.fake_still_left), float(Layout.FAKE_STILL_SECONDS[0]))
	var clue := false
	for s in _says:
		clue = clue or (String(s).contains("could never fit") and String(s).contains("floor"))
	assert_true(clue, "Gentle: explicit clue (bars + no light on the floor)")
