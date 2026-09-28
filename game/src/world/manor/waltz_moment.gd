extends Node3D
## "The Empty Waltz" (MP §14): in the Ballroom, pairs of empty cloaks hang from a clockwork rail like
## dancers. A music box on the stage plays the waltz while Krystal is in the room (its little dancer spins:
## the visual cue); after it stops (its own wind-down, or earlier when the manor's waltz cue m20 ends) the
## music director is asked for an authored silence (Events.horror_event "authored:empty_waltz": the waltz
## fades out and the room goes quiet - areas never touch the music themselves), and only THEN, after the
## intensity's delay, ONE pair turns and bows. Candle-light (her
## lantern, the candle by the rail, any real light >= WALTZ.reveal_light at the pair) shows the harmless
## supports: silver wires and little clockwork trolleys. Never damaging, no forced camera, captions for
## every sound, once per save (flag ch2_moment_empty_waltz set FIRST). Intensity (read when the waltz starts):
##   Gentle  - a longer preview: the pair sways in time well before the music stops; an explicit hint line.
##   Standard- a short preview sway; the bow follows ~4.5 s after the stop (once the waltz has faded).
##   Intense - no preview; the final movement comes late (delayed), still slow and readable.
## States: idle -> playing -> stopped -> turning -> done. Tests drive check(dt) with player_override.

signal state_changed(state: String)
signal wires_revealed

const Layout := preload("res://data/manor_layout.gd")
const Combat := preload("res://src/combat/combat.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const Interactable := preload("res://src/world/manor/manor_interactable.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const WALTZ_CUE := "m20"
const SILENCE_EVENT := "authored:empty_waltz"
const TURN_DEG := 150.0
const LORE_RAIL := "lore_ch2_manor_dancing_rail"
const BRASS := Color("d6ad55")
const SILVER := Color("e8ecff")
const COAT := Color("3d2a5a")
const GOWN := Color("b0486e")

var state: String = "idle"
var intensity: int = 1
var in_room_time: float = 0.0
var stop_timer: float = 0.0
var turn_t: float = 0.0
var music_ended: bool = false
var silence_requests: int = 0     # authored-silence requests sent to the music director (tests)
var player_override: Node3D = null
var rail_candle: Node3D = null
var rail_note: Node3D = null
var wire_visible: Array = [false, false, false]
var _last_cue: String = ""
var _pairs: Array = []
var _wires: Array = []            # per pair: [MeshInstance3D, ...]
var _dancer: Node3D
var _acc := 0.0
var _t := 0.0


func _ready() -> void:
	name = "EmptyWaltz"
	add_to_group("mm_waltz")
	_build()
	if bool(GameState.get_flag(Layout.FLAG_WALTZ)):
		state = "done"
		_pose(1.0)
	if not Events.music_cue_changed.is_connected(_on_cue):
		Events.music_cue_changed.connect(_on_cue)


func timing() -> Dictionary:
	return Layout.WALTZ["timing"].get(intensity, Layout.WALTZ["timing"][1])


func waltz_seconds() -> float:
	return float(Layout.WALTZ["waltz_seconds"].get(intensity, 22.0))


func moving_pair() -> Node3D:
	return _pairs[int(Layout.WALTZ["moving_pair"])] if not _pairs.is_empty() else null


func pair_yaw() -> float:
	var p := moving_pair()
	return p.rotation.y if p != null else 0.0


func _on_cue(cue: String) -> void:
	if _last_cue == WALTZ_CUE and cue != WALTZ_CUE:
		music_ended = true
	_last_cue = cue


func _player() -> Node3D:
	if player_override != null and is_instance_valid(player_override):
		return player_override
	if Game.player != null and is_instance_valid(Game.player) and Game.player.is_inside_tree():
		return Game.player
	return null


func _in_room(pos: Vector3) -> bool:
	return Layout.room_at(pos) == "ballroom"


func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


func _process(delta: float) -> void:
	_t += delta
	if _dancer != null and state == "playing":
		_dancer.rotation.y += delta * 2.4
	if state == "playing" and moving_pair() != null:
		var remaining := waltz_seconds() - in_room_time
		var prev := float(timing()["preview"])
		var sway := 0.0
		if prev > 0.0 and remaining <= prev:
			sway = sin(_t * 2.1) * deg_to_rad(9.0) * clampf((prev - remaining) / 2.0, 0.0, 1.0)
		moving_pair().rotation.y = sway
	if Game.mode == "loading" or Game.mode == "cutscene":
		return
	_acc += delta
	if _acc >= 0.1:
		check(_acc)
		_acc = 0.0


## One logic step (0.1 s ticks in play; tests call it with any dt).
func check(dt: float) -> void:
	var p := _player()
	var inside := p != null and _in_room(p.global_position)
	match state:
		"idle":
			if inside:
				intensity = clampi(int(Settings.get_value("horror_intensity")), 0, 2)
				in_room_time = 0.0
				_set_state("playing")
		"playing":
			if inside:
				in_room_time += dt
			if in_room_time >= waltz_seconds() or (music_ended and in_room_time >= float(Layout.WALTZ["min_seconds"])):
				stop_waltz()
		"stopped":
			if inside:
				stop_timer += dt
			if stop_timer >= float(timing()["delay"]):
				begin_turn()
		"turning":
			turn_t += dt
			var tt := float(timing()["turn"])
			_pose(clampf(turn_t / tt, 0.0, 1.0))
			if turn_t >= tt:
				_pose(1.0)
				_set_state("done")
	# Light only matters while someone can see the rail: no light queries (Combat.light_at walks the
	# light_source group) anywhere else in the house, even once the rail candle burns for good. The wires
	# keep their last state while she is away and update on the first tick after she comes back.
	if inside or state == "turning":
		_check_reveal()


## The music box winds down (the waltz stops).
func stop_waltz() -> void:
	if state != "playing" and state != "idle":
		return
	stop_timer = 0.0
	if moving_pair() != null:
		moving_pair().rotation.y = 0.0
	_set_state("stopped")
	silence_requests += 1
	# The music director fades the waltz out (authored silence); a following Mochi glances at the cloaks.
	var mp := moving_pair()
	var at := mp.global_position if mp != null and mp.is_inside_tree() else Vector3.ZERO
	Events.horror_event.emit(SILENCE_EVENT, {"pos": at + Vector3.UP * 1.2 if at != Vector3.ZERO else at})
	Audio.play_3d("dir_creak", Layout.MUSIC_BOX + Vector3.UP * 0.5, -16.0, 0.1, 20.0)
	Events.caption.emit("[the music box winds down; the waltz stops]")


## The final movement: one pair of empty cloaks turns and bows. Once per save.
func begin_turn() -> void:
	if state == "turning" or state == "done":
		return
	GameState.set_flag(Layout.FLAG_WALTZ, true)       # committed first: never replays
	turn_t = 0.0
	_set_state("turning")
	var mp := moving_pair()
	var at := mp.global_position if mp != null and mp.is_inside_tree() else Vector3.ZERO
	Audio.play_3d("dir_creak", at + Vector3.UP * 4.0, -12.0, 0.05, 25.0)
	Events.caption.emit("[cloth rustles: an empty pair of cloaks turns, as if to finish the dance]")
	if intensity == 0:
		Events.say.emit("", "Only the cloaks are dancing. Something holds them up... a little light would show what.", 6.0)


func _pose(t: float) -> void:
	var mp := moving_pair()
	if mp == null:
		return
	var e := t * t * (3.0 - 2.0 * t)
	mp.rotation.y = deg_to_rad(TURN_DEG) * e
	mp.position.y = -sin(e * PI) * 0.12
	for c in mp.get_children():
		if c is Node3D and String(c.name).begins_with("Cloak"):
			(c as Node3D).rotation.x = sin(e * PI) * 0.18 * (1.0 if String(c.name).ends_with("A") else -1.0)


## Light near a pair shows its wires; the first time after the bow it also explains them (once per save).
func _check_reveal() -> void:
	var any := false
	for i in _pairs.size():
		var pn: Node3D = _pairs[i]
		var at := pn.global_position if pn.is_inside_tree() else pn.position
		var on := Combat.light_at(at + Vector3.UP * 1.0) >= float(Layout.WALTZ["reveal_light"])
		if on != bool(wire_visible[i]):
			wire_visible[i] = on
			for w in _wires[i]:
				(w as Node3D).visible = on
		any = any or on
	if any and (state == "turning" or state == "done") and not bool(GameState.get_flag(Layout.FLAG_WALTZ_REVEALED)):
		GameState.set_flag(Layout.FLAG_WALTZ_REVEALED, true)
		GameState.discover_lore(LORE_RAIL)
		Events.caption.emit("[in the light: thin silver wires and a little clockwork trolley on the rail]")
		Events.say.emit("", "Silver wires, a brass rail, a clockwork trolley. Only a mechanical dance, for guests too shy to take the floor.", 6.0)
		wires_revealed.emit()


func wires_shown() -> bool:
	for v in wire_visible:
		if bool(v):
			return true
	return false


# --- Visuals ------------------------------------------------------------------------------------------------

func _build() -> void:
	var w: Dictionary = Layout.WALTZ
	var brass := Mat.outlined(Mat.toon(BRASS, {"rim": 0.5, "specular": 0.3}), 0.012)
	var rx := float(w["rail_x"])
	var ry := float(w["rail_y"])
	var z0 := float(w["rail_z0"])
	var z1 := float(w["rail_z1"])
	var rail := Kit.cylinder(0.06, 0.06, z1 - z0, brass, 8)
	Kit.add(self, rail, Vector3(rx, ry, (z0 + z1) * 0.5), Vector3(90, 0, 0))
	for z in [z0 + 0.3, (z0 + z1) * 0.5, z1 - 0.3]:
		Kit.add(self, Kit.box(Vector3(1.2, 0.08, 0.08), brass), Vector3(rx + 0.52, ry + 0.1, float(z)))
	var wire_mat := Mat.glow(SILVER, 1.2)
	for i in (w["pairs"] as Array).size():
		var pp: Vector3 = w["pairs"][i]
		var pair := Node3D.new()
		pair.name = "CloakPair%d" % i
		add_child(pair)
		pair.position = pp
		_pairs.append(pair)
		_build_cloak(pair, "CloakA", Vector3(0, 0, -0.3), COAT, 0.0)
		_build_cloak(pair, "CloakB", Vector3(0, 0, 0.3), GOWN, PI)
		# Clockwork trolley on the rail above the pair.
		var trolley := Node3D.new()
		trolley.name = "Trolley%d" % i
		add_child(trolley)
		trolley.position = Vector3(rx, ry - 0.18, pp.z)
		Kit.add(trolley, Kit.box(Vector3(0.3, 0.2, 0.42), brass), Vector3.ZERO)
		Kit.add(trolley, Kit.torus(0.06, 0.1, brass), Vector3(0.2, 0.05, 0), Vector3(0, 0, 90))
		# Wires: hidden in the dark, shown by light (_check_reveal).
		var ws: Array = []
		for c in [-0.3, 0.3]:
			for s in [-0.16, 0.16]:
				var top := Vector3(rx, ry - 0.28, pp.z + float(c) * 0.5)
				var bottom := Vector3(pp.x + float(s), 2.0, pp.z + float(c))
				var mid := (top + bottom) * 0.5
				var d := top - bottom
				var wm := Kit.cylinder(0.008, 0.008, d.length(), wire_mat, 4)
				add_child(wm)
				wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var up := d.normalized()
				var side := up.cross(Vector3.FORWARD)
				if side.length() < 0.01:
					side = up.cross(Vector3.RIGHT)
				side = side.normalized()
				wm.transform = Transform3D(Basis(side, up, side.cross(up)), mid)
				wm.visible = false
				ws.append(wm)
		_wires.append(ws)
	# The candle beside the rail (lit with the Lantern) and the note pinned to the rail.
	rail_candle = WardCandle.new()
	rail_candle.setup({"id": "rail", "kind": "rail", "lit": false, "pool_radius": 3.0, "height": 1.3,
		"prompt": "Light the candle by the cloaks"})
	rail_candle.name = "RailCandle"
	add_child(rail_candle)
	rail_candle.position = w["rail_candle"]
	rail_note = Interactable.new()
	rail_note.setup({"id": "rail_note", "text": "Read the note on the rail", "radius": 0.6, "offset": Vector3(0, 1.2, 0),
		"handler": Callable(self, "_read_note")})
	rail_note.name = "RailNote"
	add_child(rail_note)
	var cp: Vector3 = w["rail_candle"]
	rail_note.position = Vector3(cp.x + 1.3, 0.0, cp.z + 1.6)
	Kit.add(rail_note, Kit.cylinder(0.04, 0.06, 1.1, brass, 6), Vector3(0, 0.55, 0))
	Kit.add(rail_note, Kit.box(Vector3(0.3, 0.22, 0.02), Mat.toon(Color("f7ecd6"))), Vector3(0, 1.2, 0), Vector3(-20, -90, 0))
	Kit.static_collider(rail_note, _cyl(0.08, 1.1), Vector3(0, 0.55, 0), 1).name = "SolidBody"
	_build_music_box()


static func _cyl(r: float, h: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return s


func _read_note() -> void:
	var l := LoreDB.get_lore(LORE_RAIL)
	GameState.discover_lore(LORE_RAIL)
	Events.say.emit(String(l.get("title", "")), String(l.get("text", "")), 10.0)


func _build_cloak(pair: Node3D, cname: String, offset: Vector3, color: Color, yaw: float) -> void:
	var c := Node3D.new()
	c.name = cname
	pair.add_child(c)
	c.position = offset
	c.rotation.y = yaw
	var cloth := Mat.outlined(Mat.toon(color, {"rim": 0.45, "noise": 0.12}), 0.014)
	var lining := Mat.toon(color.lightened(0.25), {"rim": 0.3})
	var gold := Mat.toon(BRASS, {"rim": 0.5})
	var hollow := Mat.toon(Color("150d18"))
	Kit.add(c, Kit.cylinder(0.2, 0.46, 1.55, cloth, 14), Vector3(0, 1.1, 0))
	Kit.add(c, Kit.cylinder(0.17, 0.4, 1.4, lining, 12), Vector3(0, 1.08, 0.05))
	Kit.add(c, Kit.sphere(0.26, cloth, 10, 12), Vector3(0, 1.86, 0), Vector3.ZERO, Vector3(1.6, 0.6, 1.0))
	Kit.add(c, Kit.sphere(0.2, cloth, 10, 12), Vector3(0, 2.08, -0.04), Vector3.ZERO, Vector3(1.0, 1.1, 1.0))
	Kit.add(c, Kit.sphere(0.13, hollow, 8, 10), Vector3(0, 2.06, 0.1), Vector3.ZERO, Vector3(1.0, 1.1, 0.5))
	Kit.add(c, Kit.torus(0.12, 0.16, gold), Vector3(0, 1.9, 0.02))


func _build_music_box() -> void:
	var holder := Node3D.new()
	holder.name = "MusicBox"
	add_child(holder)
	holder.position = Layout.MUSIC_BOX
	var wood := Mat.outlined(Mat.toon(Color("7a3a2e"), {"rim": 0.3}), 0.012)
	var gold := Mat.toon(BRASS, {"rim": 0.5})
	var cloth := Mat.toon(Color("f0d6e2"))
	Kit.add(holder, Kit.cylinder(0.3, 0.36, 0.8, Mat.toon(Color("4a2a3a")), 12), Vector3(0, 0.4, 0))
	Kit.add(holder, Kit.box(Vector3(0.5, 0.22, 0.36), wood), Vector3(0, 0.92, 0))
	Kit.add(holder, Kit.box(Vector3(0.5, 0.3, 0.03), wood), Vector3(0, 1.16, -0.2), Vector3(-15, 0, 0))
	Kit.add(holder, Kit.box(Vector3(0.44, 0.02, 0.3), cloth), Vector3(0, 1.035, 0))
	Kit.add(holder, Kit.torus(0.04, 0.07, gold), Vector3(0.3, 0.92, 0), Vector3(0, 0, 90))
	_dancer = Node3D.new()
	_dancer.name = "Dancer"
	holder.add_child(_dancer)
	_dancer.position = Vector3(0, 1.05, 0)
	Kit.add(_dancer, Kit.cylinder(0.01, 0.01, 0.08, gold, 6), Vector3(0, 0.04, 0))
	Kit.add(_dancer, Kit.cone(0.07, 0.12, Mat.toon(GOWN), 10), Vector3(0, 0.13, 0))
	Kit.add(_dancer, Kit.sphere(0.03, Mat.toon(Color("f3e6c8")), 6, 8), Vector3(0, 0.22, 0))
	Kit.static_collider(holder, _cyl(0.36, 1.0), Vector3(0, 0.5, 0), 1).name = "SolidBody"
