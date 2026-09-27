extends Node
## Authored moments of The Below (restrained, fair, never harmful). Each fires once per playthrough
## (GameState flags), emits Events.horror_event("authored:<id>", {}) and asks the horror director to
## stay quiet for a while (Game.director.suppress) so scares never stack.
##   THRESHOLD   Timbered Tunnel: Lumi stares into a pitch-dark side passage, then stays close. A creak.
##   CROSSING    Hall of Faces: a pale shape crosses the far doorway (~25 m) in ~1.2 s; clues remain.
##   IMITATION   Drowned Shrine: a cold, lightless "Lumi" chimes by the wrong exit; folds away if approached.
##   SILK INTRO  Webbed Passage: a shape on the ceiling far ahead recoils from the lantern light.
##   NURSERY     Optional cave: silence. Nothing happens, on purpose.
##   RETURN      After the boss, the lift ride up (see below_world.gd ride_lift).
## Also tracks which room the player is in and forwards changes to the area (boss fight, ambience).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const PaleShape := preload("res://src/world/below/pale_shape.gd")
const FakeLumi := preload("res://src/world/below/fake_lumi.gd")
const Lamp := preload("res://src/world/below/below_lamp.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const HorrorData := preload("res://data/horror_events.gd")

const TICK := 0.1

var area: Node3D = null
var room: String = ""
var fake: Node3D = null
var silk_shape: Node3D = null
var silk_state: String = ""        # "" | watching | rattle | done
var in_silence: bool = false
var player_override: Node3D = null  # tests
var fired: Array = []               # ids fired this session (tests/QA)
var hold: bool = false              # QA screenshots: shapes stay put regardless of where the player is

var _t: float = 0.0
var _silk_t: float = 0.0
var _silk_seen_t: float = 0.0
var _hall_t: float = 0.0
var _silence_t: float = 0.0


func setup(p_area: Node3D) -> void:
	area = p_area


func _ready() -> void:
	name = "Moments"
	_build_crossing_clue()


# --- Helpers ---------------------------------------------------------------------------------------

func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _lumi() -> Node:
	var l: Variant = Game.companion_nodes.get("lumi", null)
	if l is Node and is_instance_valid(l):
		return l
	return null


static func arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))


static func intensity() -> Dictionary:
	var i := clampi(int(Settings.get_value("horror_intensity")), 0, 2)
	return HorrorData.INTENSITY[i]


func _suppress(seconds: float) -> void:
	var d: Variant = Game.director
	if d is Node and is_instance_valid(d) and d.has_method("suppress"):
		d.suppress(seconds)


func _authored(id: String, seconds: float) -> void:
	fired.append(id)
	Events.horror_event.emit("authored:" + id, {})
	_suppress(seconds)


func _camera_forward(p: Node3D) -> Vector3:
	var cam: Camera3D = null
	if p.has_method("get_camera"):
		var c: Variant = p.get_camera()
		if c is Camera3D:
			cam = c
	if cam == null and p.is_inside_tree():
		cam = p.get_viewport().get_camera_3d()
	if cam != null:
		return -cam.global_transform.basis.z
	if p.has_method("get_facing"):
		var f: Variant = p.get_facing()
		if f is Vector3:
			return f
	return -p.global_transform.basis.z


## True when `point` is inside the player camera's view (frustum only; the shapes are lit and far).
func _on_screen(p: Node3D, point: Vector3) -> bool:
	var cam: Camera3D = null
	if p.has_method("get_camera"):
		var c: Variant = p.get_camera()
		if c is Camera3D:
			cam = c
	if cam == null and p.is_inside_tree():
		cam = p.get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return false
	return cam.is_position_in_frustum(point)


func _lantern_on(p: Node3D) -> bool:
	var v: Variant = p.get("lantern_on")
	return v is bool and v


# --- Tick ----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	var dt := _t
	_t = 0.0
	if Game.mode == "cutscene" or Game.mode == "loading":
		return
	var p := _player()
	if p == null:
		return
	check(p, dt)


## One evaluation step at the player's position (public for tests).
func check(p: Node3D, dt: float) -> void:
	var pos := p.global_position
	var r := Layout.room_at(pos)
	if r != room:
		var old := room
		room = r
		_on_room_changed(old, r)
	# THE THRESHOLD
	if not GameState.get_flag("moment_threshold") and (r == "tunnel" or r == "side_passage") and pos.z < -15.5 and pos.z > -24.5:
		fire_threshold()
	# THE DISTANT CROSSING
	if not GameState.get_flag("moment_crossing") and r == "hall":
		_hall_t += dt
		var to_door := Layout.CROSSING_DOORWAY + Vector3(0, 1.2, 0) - (pos + Vector3(0, 1.4, 0))
		var dist := Vector2(to_door.x, to_door.z).length()
		if dist < 11.0:
			GameState.set_flag("moment_crossing", true)     # too close: the clue alone will do
		elif _camera_forward(p).normalized().dot(to_door.normalized()) > 0.85 or _hall_t > 4.0:
			fire_crossing()
	# THE IMITATION
	if not GameState.get_flag("imitation_seen") and r == "shrine" and pos.z < -77.3:
		start_imitation(p)
	if fake != null and is_instance_valid(fake) and not fake.get("folding"):
		var d2 := Vector2(pos.x - fake.global_position.x, pos.z - fake.global_position.z).length()
		if d2 < 4.0:
			fold_imitation()
		elif r != "shrine" and r != "wrong_way" and not hold:
			fake.vanish()
			fake = null
		elif fake.has_method("stare_at"):
			fake.stare_at(pos)
	# Into the Silk Hollows
	if not GameState.get_flag("reached_silk_hollows") and ((r == "descent_low" and pos.x > 76.0) or r == "webbed"):
		reach_silk_hollows()
	# SILK HOLLOWS INTRO
	if not GameState.get_flag("moment_silk_intro") and r == "webbed" and pos.x > 81.0:
		start_silk_intro()
	if silk_state != "" and silk_state != "done":
		_tick_silk(p, pos, dt)
	# THE NURSERY: silence while inside
	if in_silence:
		_silence_t += dt
		if _silence_t > 4.0:
			_silence_t = 0.0
			_suppress(10.0)


func _on_room_changed(old: String, new_room: String) -> void:
	var is_nursery := new_room == "nursery" or new_room == "nursery_way"
	if is_nursery and not in_silence:
		enter_nursery()
	elif not is_nursery and in_silence:
		# Keyed on the silence itself, not on `old`: a respawn or lift ride resets `room` to "", and the
		# ambience must still come back (and the director stop being held) when Krystal is elsewhere.
		leave_nursery()
	if area != null and area.has_method("on_room_changed"):
		area.on_room_changed(old, new_room)


# --- THE THRESHOLD ---------------------------------------------------------------------------------------

func fire_threshold() -> void:
	GameState.set_flag("moment_threshold", true)
	var lumi := _lumi()
	if lumi != null and lumi.has_method("notice_threat"):
		lumi.notice_threat(Layout.THRESHOLD_POINT)
	Audio.play_3d("dir_creak", Layout.THRESHOLD_POINT + Vector3(-1.5, 0.5, 0), -10.0, 0.04, 24.0)
	Events.caption.emit("[timbers creak, somewhere down the dark passage]")
	_authored("threshold", 35.0)


# --- THE DISTANT CROSSING ---------------------------------------------------------------------------------

func fire_crossing() -> void:
	GameState.set_flag("moment_crossing", true)
	var shape: Node3D = PaleShape.new()
	shape.setup({"variant": "shade" if arachno() else "spider"})
	shape.name = "CrossingShape"
	shape.scale = Vector3.ONE * 1.3
	area.add_child(shape)
	shape.cross(Vector3(45.0, -6.0, -54.6), Vector3(45.0, -6.0, -64.2), 3.1, true)
	var snd := "shade_drift" if arachno() else "weaver_skitter"
	Audio.play_3d(snd, Layout.CROSSING_DOORWAY + Vector3(2.5, 0.8, 0), -6.0, 0.03, 40.0)
	Events.caption.emit("[something drifts past the far doorway]" if arachno() else "[something skitters past the far doorway]")
	_authored("crossing", 45.0)


func _build_crossing_clue() -> void:
	if area == null:
		return
	# A miner's lantern, dropped and sputtering, in the doorway the shape crossed.
	var lamp: Node3D = Lamp.new()
	lamp.setup({"style": "dropped", "energy": 0.55, "range": 3.6, "idle": 0.25, "color": Color("ffb35c")})
	lamp.name = "DroppedLantern"
	lamp.position = Vector3(43.1, -6.0, -60.7)
	area.add_child.call_deferred(lamp)
	var it: Node3D = Interactable.new()
	it.setup({"text": "", "size": Vector3(1.2, 1.6, 1.2), "offset": Vector3(0, 0.8, 0), "text_func": Callable(self, "_clue_text"), "handler": Callable(self, "_inspect_clue"), "accent": false})
	it.name = "CrossingClue"
	it.position = Vector3(43.4, -6.0, -58.9)
	area.add_child.call_deferred(it)


func _clue_text() -> Dictionary:
	return {"text": "Inspect the torn root" if arachno() else "Inspect the strand", "enabled": true}


func _inspect_clue(_player: Node) -> void:
	GameState.set_flag("crossing_clue_seen", true)
	if arachno():
		Events.say.emit("", "A pale root, torn loose and dragged across the floor. The break is still wet. Whatever took it went toward the shrine.", 5.0)
	else:
		Events.say.emit("", "A single strand of silk, stretched low across the doorway. It's warm. Whatever left it went toward the shrine.", 5.0)


# --- THE IMITATION -------------------------------------------------------------------------------------------

func start_imitation(p: Node3D) -> void:
	GameState.set_flag("imitation_seen", true)
	fake = FakeLumi.new()
	fake.name = "Imitation"
	fake.position = Layout.FAKE_LUMI_POS
	area.add_child(fake)
	fake.stare_at(p.global_position)
	fake.set("_next_chime", 0.6)
	var lumi := _lumi()
	if lumi != null:
		get_tree().create_timer(1.4).timeout.connect(_lumi_hides)
	_authored("imitation", 60.0)


func _lumi_hides() -> void:
	var lumi := _lumi()
	if lumi == null:
		return
	if lumi.has_method("react"):
		lumi.react("scared")
	Events.caption.emit("[Lumi whimpers]")


func fold_imitation() -> void:
	if fake == null or not is_instance_valid(fake):
		return
	var hiss_db: float = float(intensity()["stinger_db"]) + 2.0
	var flash := not bool(Settings.get_value("reduce_flashing"))
	fake.fold(hiss_db, flash)
	fake = null
	GameState.set_flag("imitation_folded", true)


# --- Silk Hollows -----------------------------------------------------------------------------------------------

func reach_silk_hollows() -> void:
	GameState.set_flag("reached_silk_hollows", true)
	Audio.play_sfx("stinger_soft", float(intensity()["stinger_db"]) - 4.0, 0.0)
	Events.caption.emit("[roots creak somewhere above]" if arachno() else "[something shifts in the silk]")
	Events.horror_event.emit("authored:silk_hollows", {})


func start_silk_intro() -> void:
	GameState.set_flag("moment_silk_intro", true)
	silk_shape = PaleShape.new()
	silk_shape.setup({"variant": "shade" if arachno() else "spider"})
	silk_shape.name = "SilkIntroShape"
	area.add_child(silk_shape)
	silk_shape.cling(Layout.SILK_INTRO_POS, Vector3(-1, 0, 0))
	silk_state = "watching"
	_silk_t = 0.0
	_silk_seen_t = 0.0
	_suppress(40.0)


func _tick_silk(p: Node3D, pos: Vector3, dt: float) -> void:
	if silk_shape == null or not is_instance_valid(silk_shape):
		silk_state = "done"
		return
	_silk_t += dt
	var sp := silk_shape.global_position
	var dist := Vector2(pos.x - sp.x, pos.z - sp.z).length()
	var lit := _lantern_on(p)
	match silk_state:
		"watching":
			# Let Krystal actually see it before it shrinks from her light (or give up waiting after 5 s).
			if _on_screen(p, sp + Vector3.DOWN * 0.4):
				_silk_seen_t += dt
			if lit and dist < 20.0 and ((_silk_t > 1.2 and _silk_seen_t > 0.6) or _silk_t > 5.0):
				_silk_recoil(false)
			elif not lit and dist < 11.0:
				silk_state = "rattle"
				_silk_t = 0.0
				Audio.play_3d("shade_telegraph" if arachno() else "weaver_rattle", sp, float(intensity()["stinger_db"]) + 2.0, 0.02, 30.0)
				Events.caption.emit("[a dry whisper overhead]" if arachno() else "[a dry rattle overhead]")
			elif room != "webbed" and room != "descent_low" and _silk_t > 3.0 and not hold:
				_silk_recoil(true)
		"rattle":
			if lit:
				_silk_recoil(false)
			elif _silk_t > 2.5 or dist < 7.0:
				_silk_recoil(true)


func _silk_recoil(lantern_hint: bool) -> void:
	silk_state = "done"
	var sp := silk_shape.global_position
	Audio.play_3d("shade_drift" if arachno() else "weaver_skitter", sp, -4.0, 0.03, 35.0)
	Events.caption.emit("[it slips away into the dark above]")
	silk_shape.recoil(Layout.SILK_INTRO_HIDE, 0.7)
	silk_shape = null
	if lantern_hint:
		Events.hint.emit("silk_light_raise", "Raise your lantern ({lantern}). Things down here shrink from its light.")
	Events.hint.emit("silk_light", "It shrinks from your light.")
	_authored("silk_intro", 40.0)


# --- THE NURSERY ------------------------------------------------------------------------------------------------------

func enter_nursery() -> void:
	in_silence = true
	_silence_t = 0.0
	Audio.stop_ambience(2.5)
	_suppress(12.0)
	if not GameState.get_flag("moment_nursery"):
		GameState.set_flag("moment_nursery", true)
		Events.caption.emit("[complete silence]")
		_authored("nursery", 30.0)


func leave_nursery() -> void:
	in_silence = false
	if area != null and area.has_method("resume_ambience"):
		area.resume_ambience(Layout.zone_of_room(room))
