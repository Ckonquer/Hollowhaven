extends Node3D
## The Ashbell mineral winch (MP §11 step 6 "repair the mineral winch"): a winch drum at the foot of the upper
## shelf's cliff, a timber crane on the shelf and a hinged plank gangway along the cliff. Broken, the jammed
## winch holds the gangway stiffly out above the bench (the way up is visible, not usable). Repairing it takes
## familiar materials only (data/reach_east.gd WINCH_COST: wood, stone, iron ore - never bars, so it can't wait
## on the furnace), all-or-nothing, and sets the persistent flag ch2_winch_repaired: the gangway lowers onto the
## L2 bench and stays walkable for good (resource route after the story; companions can walk it too).
## Interaction contract: group "interactable" + a layer-16 sphere at the drum; the drum frame, the deck, the crane
## base and the lowered gangway (with rails) are solid (layer 1).
##   setup({"hinge": Vector3, "dir": Vector3, "length": float, "width": float, "slope_deg": float,
##          "raised_deg": float, "deck_min": Vector2 (U, V), "deck_max": Vector2, "deck_y": float,
##          "crane": Vector3, "frame": Callable(uv: Vector2) -> Vector2 world XZ})  (world coordinates;
##   the node itself stands at the drum)
##   is_repaired(), missing_materials(), cost_text(), repair() -> bool, gangway_enabled(), gangway_solid(),
##   is_lowering(), set_lowered(on, animate)
## The gangway's collider (R112) switches on only when the plank has finished lowering (LOWER_SECONDS after the
## repair; at once on load / animate=false), so there is never an invisible walkway ahead of the moving plank.

signal repaired

const Q := preload("res://data/reach_east.gd")
const QV := preload("res://src/world/reach/east/quarry_visuals.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Fx := preload("res://src/world/common/fx.gd")

const LOWER_SECONDS := 2.6

var hinge := Vector3.ZERO           # world: gangway top centre (deck edge, walking surface height)
var dir := Vector3(0, 0, 1)         # world: horizontal unit vector from the hinge toward the foot
var length: float = 14.1
var width: float = 2.4
var slope_deg: float = 19.0
var raised_deg: float = 12.0
var deck_min := Vector2.ZERO
var deck_max := Vector2.ZERO
var deck_y: float = 0.0
var crane := Vector3.ZERO
var frame_fn: Callable

var _pivot: Node3D                  # animated gangway visual (hinge frame, rotates about its X axis)
var _gang_body: StaticBody3D        # lowered-pose collider (enabled only once repaired)
var _gear_broken: Node3D
var _gear_fixed: Node3D
var _chain_slack: Node3D
var _chain_taut: MeshInstance3D
var _chain_hold: MeshInstance3D     # boom tip -> gangway end
var _boom_tip := Vector3.ZERO       # local
var _angle: float = 0.0             # current tilt (deg, + = foot down)
var _busy := false
var _lowered := false               # logical pose: down (or on its way down) vs hoisted
var _repairing := false             # repair() is setting the flag itself (its own animated lowering follows)
var _hinted := false
var _tw: Tween
var _cue: MeshInstance3D            # Settings high_visibility_cues: a bold ring over the drum until repaired


func setup(p: Dictionary) -> void:
	hinge = p.get("hinge", hinge)
	dir = (p.get("dir", dir) as Vector3).normalized()
	length = float(p.get("length", length))
	width = float(p.get("width", width))
	slope_deg = float(p.get("slope_deg", slope_deg))
	raised_deg = float(p.get("raised_deg", raised_deg))
	deck_min = p.get("deck_min", deck_min)
	deck_max = p.get("deck_max", deck_max)
	deck_y = float(p.get("deck_y", deck_y))
	crane = p.get("crane", crane)
	if p.has("frame"):
		frame_fn = p["frame"]


func _ready() -> void:
	name = "MineralWinch"
	add_to_group("interactable")
	add_to_group("quarry_winch")
	_build()
	set_lowered(is_repaired(), false)
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


# --- State -------------------------------------------------------------------------------------------------

func is_repaired() -> bool:
	return bool(GameState.get_flag(Q.FLAG_WINCH))


## The way up is open: the gangway is down or on its way down (see gangway_solid() for its collider).
func gangway_enabled() -> bool:
	return _lowered


## The lowered gangway's collider is on (walkable right now): false while the plank is still lowering.
func gangway_solid() -> bool:
	return _gang_body != null and _gang_body.collision_layer != 0


## The plank is moving (the prompt is hidden meanwhile).
func is_lowering() -> bool:
	return _busy


## Items still missing for the repair: {item_id: missing count} (empty = everything is there).
static func missing_materials() -> Dictionary:
	var out := {}
	for c in Q.WINCH_COST:
		var have: int = GameState.count_item(String(c[0]))
		if have < int(c[1]):
			out[String(c[0])] = int(c[1]) - have
	return out


static func cost_text() -> String:
	var parts: Array = []
	for c in Q.WINCH_COST:
		parts.append("%d %s" % [int(c[1]), ItemDB.display_name(String(c[0]))])
	return ", ".join(parts)


static func missing_text(missing: Dictionary) -> String:
	var parts: Array = []
	for c in Q.WINCH_COST:
		var id := String(c[0])
		if missing.has(id):
			parts.append("%d more %s" % [int(missing[id]), ItemDB.display_name(id)])
	return "Needs " + ", ".join(parts)


# --- Interaction ------------------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if is_repaired():
		return {"text": Q.TEXT["winch_look"], "enabled": true}
	var text: String = Q.TEXT["winch_repair"] % cost_text()
	var missing := missing_materials()
	if missing.is_empty():
		return {"text": text, "enabled": true}
	return {"text": text, "enabled": false, "reason": missing_text(missing)}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if is_repaired():
		Events.say.emit("", Q.TEXT["winch_done"], 4.0)
		return
	repair()


## The interaction probe calls this; the first look explains what the winch needs (hint shown once).
func set_focused(on: bool) -> void:
	if on and not _hinted and not is_repaired():
		_hinted = true
		Events.hint.emit("hr_quarry_winch", Q.TEXT["winch_broken"])


## Takes the whole cost only if EVERY item is there (nothing is taken otherwise), sets ch2_winch_repaired and
## lowers the gangway. Returns true when this call repaired it.
func repair() -> bool:
	if is_repaired():
		return false
	var missing := missing_materials()
	if not missing.is_empty():
		Events.notify.emit(missing_text(missing) + " to repair the winch.", "warn")
		return false
	var taken: Array = []
	for c in Q.WINCH_COST:
		if GameState.take_item(String(c[0]), int(c[1])):
			taken.append(c)
		else:
			for t in taken:
				GameState.give_item(String(t[0]), int(t[1]))
			Events.notify.emit("The winch couldn't be repaired right now.", "warn")
			return false
	# the flag first (save-safe), without _on_flag_set snapping the gangway down: it lowers visibly below
	_repairing = true
	GameState.set_flag(Q.FLAG_WINCH, true)
	_repairing = false
	set_lowered(true, is_inside_tree())
	Events.notify.emit(Q.TEXT["winch_repaired"], "success")
	Events.caption.emit(Q.TEXT["winch_caption"])
	if GameState.has_method("request_quest_eval"):
		GameState.request_quest_eval()
	repaired.emit()
	return true


func _on_flag_set(flag: String, _value: Variant) -> void:
	if flag == Q.FLAG_WINCH and not _repairing and is_repaired() and not _lowered:
		set_lowered(true, false)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_update_cue()


func _update_cue() -> void:
	if _cue != null:
		_cue.visible = not is_repaired() and bool(Settings.get_value("high_visibility_cues"))


## Lowered = walkable gangway. Hoisting (on=false) or animate=false switches the collider at once; an animated
## lowering switches it on when the plank arrives (the tween's end), never while it is still moving.
func set_lowered(on: bool, animate: bool) -> void:
	_lowered = on
	var target := slope_deg if on else -raised_deg
	if not is_inside_tree() or absf(_angle - target) < 0.01:
		animate = false
	_set_solid(on and not animate)
	_gear_broken.visible = not on
	_gear_fixed.visible = on
	_chain_slack.visible = not on
	_chain_taut.visible = on
	_update_cue()
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_busy = false
	if not animate:
		_set_angle(target)
		return
	_busy = true
	if Audio.has_sound("lift_move"):
		Audio.play_3d("lift_move", to_global(_boom_tip), -2.0)
	Events.camera_shake.emit(0.1, 0.6)
	_tw = create_tween()
	_tw.tween_method(_set_angle, _angle, target, LOWER_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(func() -> void:
		_busy = false
		_set_solid(_lowered)
		if is_inside_tree():
			Fx.burst(get_parent(), to_global(_foot_local()), "dust", 1.4))


func _set_solid(on: bool) -> void:
	if _gang_body != null:
		_gang_body.collision_layer = 1 if on else 0


func _set_angle(deg: float) -> void:
	_angle = deg
	if _pivot != null:
		_pivot.transform = Transform3D(_hinge_basis() * Basis(Vector3.RIGHT, deg_to_rad(deg)), hinge - position)
	_update_hold_chain()


# --- Geometry ------------------------------------------------------------------------------------------

func _hinge_basis() -> Basis:
	var x := Vector3.UP.cross(dir).normalized()
	return Basis(x, Vector3.UP, dir)


func _foot_local() -> Vector3:
	var b := _hinge_basis() * Basis(Vector3.RIGHT, deg_to_rad(_angle))
	return (hinge - position) + b * Vector3(0, 0, length)


func _update_hold_chain() -> void:
	if _chain_hold == null:
		return
	var a := _boom_tip
	var b := _foot_local() + Vector3(0, 0.1, 0)
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	_chain_hold.transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


func _world(uv: Vector2, y: float) -> Vector3:
	var w: Vector2 = frame_fn.call(uv) if frame_fn.is_valid() else uv
	return Vector3(w.x, y, w.y)


func _build() -> void:
	var here := position
	var wood := NV.Merger.new()
	var metal := NV.Merger.new()
	var across := Vector3.UP.cross(dir).normalized()      # horizontal, perpendicular to the gangway
	var fwd := -across                                    # station faces the arena side
	# --- the winch drum (this node's origin) ---
	for s in [-1.0, 1.0]:
		var pp := dir * 0.0 + across * float(s) * 0.8
		QV.add_rod(wood, pp + Vector3(0, -0.2, 0), pp + Vector3(0, 1.75, 0), 0.11, Palette.WOOD_DARK)
		QV.add_rod(wood, pp + Vector3(0, 0.0, 0) + dir * 0.45, pp + Vector3(0, 1.1, 0), 0.06, Palette.WOOD)
		QV.add_rod(wood, pp + Vector3(0, 0.0, 0) - dir * 0.45, pp + Vector3(0, 1.1, 0), 0.06, Palette.WOOD)
	QV.add_rod(wood, across * -0.95 + Vector3(0, 1.72, 0), across * 0.95 + Vector3(0, 1.72, 0), 0.08, Palette.WOOD_DARK)
	QV.add_rod(wood, across * -0.72 + Vector3(0, 1.0, 0), across * 0.72 + Vector3(0, 1.0, 0), 0.3, Palette.WOOD)
	for k in 4:
		var ax := -0.5 + 0.33 * float(k)
		QV.add_rod(metal, across * ax + Vector3(0, 1.0, 0), across * (ax + 0.12) + Vector3(0, 1.0, 0), 0.32, Q.COL_IRON)
	# crank wheel on the near side (spokes + rim)
	var wc := across * -0.92 + Vector3(0, 1.0, 0)
	for k in 6:
		var a := TAU * float(k) / 6.0
		var spoke := (dir * cos(a) + Vector3.UP * sin(a)) * 0.55
		QV.add_rod(wood, wc, wc + spoke, 0.035, Palette.WOOD_DARK)
	for k in 12:
		var a0 := TAU * float(k) / 12.0
		var a1 := TAU * float(k + 1) / 12.0
		QV.add_rod(wood, wc + (dir * cos(a0) + Vector3.UP * sin(a0)) * 0.55, wc + (dir * cos(a1) + Vector3.UP * sin(a1)) * 0.55, 0.045, Palette.WOOD)
	# bell-shaped counterweight hanging from the crossbeam
	QV.add_rod(metal, across * 0.35 + Vector3(0, 1.72, 0), across * 0.35 + Vector3(0, 1.45, 0), 0.02, Q.COL_IRON)
	QV.add_bell(metal, Transform3D(Basis(), across * 0.35 + Vector3(0, 1.45, 0)), 0.75)
	# gear: broken (a wedge missing) / mended
	_gear_broken = _gear(true, across * 0.97 + Vector3(0, 1.0, 0), across)
	_gear_fixed = _gear(false, across * 0.97 + Vector3(0, 1.0, 0), across)
	# collision: the frame
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	solid.collision_layer = 1
	solid.collision_mask = 0
	solid.set_meta("surface", "wood")
	add_child(solid)
	_box_shape(solid, Transform3D(Basis(across, Vector3.UP, across.cross(Vector3.UP).normalized()), Vector3(0, 0.9, 0)), Vector3(2.0, 1.8, 1.0))
	# interaction sphere
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.2
	cs.shape = sph
	cs.position = Vector3(0, 1.0, 0) + fwd * 0.2
	ib.add_child(cs)
	add_child(ib)
	_cue = MeshInstance3D.new()
	_cue.name = "Cue"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.35
	tm.outer_radius = 0.5
	_cue.mesh = tm
	_cue.rotation_degrees = Vector3(90, 0, 0)
	_cue.position = Vector3(0, 2.6, 0)
	_cue.material_override = Mat.glow(Color("fff2c8"), 1.8)
	_cue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cue)
	# --- deck on the shelf lip (solid, braced into the cliff) ---
	var dw := NV.Merger.new()
	var dmin := deck_min
	var dmax := deck_max
	var c0 := _world(Vector2(dmin.x, dmin.y), deck_y) - here
	var c1 := _world(Vector2(dmax.x, dmin.y), deck_y) - here
	var c2 := _world(Vector2(dmin.x, dmax.y), deck_y) - here
	var du := (c1 - c0)
	var dv := (c2 - c0)
	var dcentre := c0 + du * 0.5 + dv * 0.5
	var dbasis := Basis(du.normalized(), Vector3.UP, du.normalized().cross(Vector3.UP).normalized())
	var n_planks := int(ceil(du.length() / 0.32))
	for k in n_planks:
		var t := (float(k) + 0.5) / float(n_planks)
		var pc := c0 + du * t + dv * 0.5 + Vector3(0, -0.08, 0)
		QV.add_box(dw, Transform3D(dbasis, pc), Vector3(0.3, 0.14, dv.length()), Palette.WOOD_LIGHT if k % 3 == 0 else Palette.WOOD)
	for e in [0.0, 1.0]:
		var a := c0 + dv * float(e)
		QV.add_rod(dw, a + Vector3(0, -0.2, 0), a + du + Vector3(0, -0.2, 0), 0.1, Palette.WOOD_DARK)
		# braces from the deck's front edge back into the cliff face
		QV.add_rod(dw, a + Vector3(0, -0.25, 0), a + du * 0.62 + Vector3(0, -2.4, 0), 0.09, Palette.WOOD_DARK)
	var deck_body := StaticBody3D.new()
	deck_body.name = "DeckSolid"
	deck_body.collision_layer = 1
	deck_body.collision_mask = 0
	deck_body.set_meta("surface", "wood")
	add_child(deck_body)
	_box_shape(deck_body, Transform3D(dbasis, dcentre + Vector3(0, -0.15, 0)), Vector3(du.length(), 0.3, dv.length()))
	# --- crane on the shelf (layout point ~(100, 0)) ---
	var cr := crane - here
	var boom_dir := (hinge - crane)
	boom_dir.y = 0.0
	boom_dir = boom_dir.normalized()
	var side := Vector3.UP.cross(boom_dir).normalized()
	for s in [-1.0, 1.0]:
		QV.add_rod(wood, cr + side * float(s) * 0.9 + Vector3(0, -0.2, 0), cr + Vector3(0, 4.3, 0), 0.13, Palette.WOOD_DARK)
	QV.add_rod(wood, cr - boom_dir * 0.9 + Vector3(0, -0.2, 0), cr + Vector3(0, 4.3, 0), 0.12, Palette.WOOD_DARK)
	var tip := cr + Vector3(0, 4.6, 0) + boom_dir * 4.4
	QV.add_rod(wood, cr + Vector3(0, 3.9, 0) - boom_dir * 0.8, tip, 0.12, Palette.WOOD)
	metal.add(NV._cyl(0.32, 0.32, 0.12, 12), Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)).orthonormalized() * Basis(Vector3.RIGHT, PI * 0.5), tip + Vector3(0, -0.1, 0)), Q.COL_IRON)
	QV.add_bell(metal, Transform3D(Basis(), cr + Vector3(0, 4.25, 0)), 0.9)
	QV.add_ribbon(wood, cr + Vector3(0, 4.0, 0.1), 0.0, 0.8, Q.COL_RIBBON_B)
	_boom_tip = tip + Vector3(0, -0.3, 0)
	var crane_body := StaticBody3D.new()
	crane_body.name = "CraneSolid"
	crane_body.collision_layer = 1
	crane_body.collision_mask = 0
	crane_body.set_meta("surface", "wood")
	add_child(crane_body)
	_box_shape(crane_body, Transform3D(Basis(), cr + Vector3(0, 1.2, 0)), Vector3(1.9, 2.4, 1.9))
	# the winch chain: drum -> boom tip (taut) or piled slack
	_chain_taut = _rod_instance(Vector3(0, 1.3, 0), _boom_tip, 0.035)
	_chain_slack = Node3D.new()
	_chain_slack.name = "ChainSlack"
	add_child(_chain_slack)
	var sl := NV.Merger.new()
	QV.add_rod(sl, Vector3(0, 1.3, 0), fwd * 0.5 + Vector3(0, 0.1, 0), 0.035, Q.COL_IRON)
	for k in 5:
		sl.add(NV._sph(0.09, 4, 6), Transform3D(Basis(), fwd * (0.55 + 0.12 * float(k)) + dir * (0.1 * float(k % 2)) + Vector3(0, 0.06, 0)), Q.COL_IRON)
	_chain_slack.add_child(NV._mi(sl.commit(), QV.metal_material(), "Slack"))
	_chain_hold = _rod_instance(_boom_tip, _boom_tip + Vector3(0, -1, 0), 0.03)
	# commit the static batches
	var wmi := NV._mi(wood.commit(), QV.wood_material(), "WinchWood")
	add_child(wmi)
	add_child(NV._mi(metal.commit(), QV.metal_material(), "WinchMetal"))
	add_child(NV._mi(dw.commit(), QV.wood_material(), "Deck"))
	# --- the gangway (animated visual) + its lowered-pose collider ---
	_pivot = Node3D.new()
	_pivot.name = "Gangway"
	add_child(_pivot)
	var gw := NV.Merger.new()
	var n := int(ceil(length / 0.34))
	for k in n:
		var z := (float(k) + 0.5) / float(n) * length
		QV.add_box(gw, Transform3D(Basis(), Vector3(0, -0.08, z)), Vector3(width, 0.14, 0.31), Palette.WOOD if k % 4 != 0 else Palette.WOOD_LIGHT)
	for s in [-1.0, 1.0]:
		var x := float(s) * (width * 0.5 - 0.06)
		QV.add_rod(gw, Vector3(x, -0.2, 0.0), Vector3(x, -0.2, length), 0.09, Palette.WOOD_DARK)
		QV.add_rod(gw, Vector3(x, 0.95, 0.0), Vector3(x, 0.95, length), 0.05, Palette.WOOD_DARK)
		var posts := int(ceil(length / 1.6))
		for k in posts + 1:
			var z := minf(float(k) * 1.6, length)
			QV.add_rod(gw, Vector3(x, -0.15, z), Vector3(x, 0.98, z), 0.045, Palette.WOOD_DARK)
		for k in 3:
			QV.add_ribbon(gw, Vector3(x, 0.93, 2.5 + float(k) * 4.5), 0.0, 0.5, Q.COL_RIBBON_A if k % 2 == 0 else Q.COL_RIBBON_B)
	_pivot.add_child(NV._mi(gw.commit(), QV.wood_material(), "Planks"))
	var lowered := Node3D.new()
	lowered.name = "GangwayLoweredFrame"
	add_child(lowered)
	lowered.transform = Transform3D(_hinge_basis() * Basis(Vector3.RIGHT, deg_to_rad(slope_deg)), hinge - here)
	_gang_body = StaticBody3D.new()
	_gang_body.name = "GangwaySolid"
	_gang_body.collision_layer = 0
	_gang_body.collision_mask = 0
	_gang_body.set_meta("surface", "wood")
	lowered.add_child(_gang_body)
	_box_shape(_gang_body, Transform3D(Basis(), Vector3(0, -0.16, length * 0.5 + 0.1)), Vector3(width, 0.32, length + 0.8))
	for s in [-1.0, 1.0]:
		_box_shape(_gang_body, Transform3D(Basis(), Vector3(float(s) * (width * 0.5 - 0.06), 0.5, length * 0.5)), Vector3(0.12, 1.0, length))
	_set_angle(-raised_deg)


func _gear(broken: bool, at: Vector3, axis: Vector3) -> Node3D:
	var m := NV.Merger.new()
	var up := Vector3.UP
	var ax := axis.normalized()
	var side := ax.cross(up).normalized()
	var disc := Basis(side, ax, side.cross(ax).normalized())
	var col := Palette.COPPER if not broken else Q.COL_ROCK_DARK
	m.add(NV._cyl(0.42, 0.42, 0.1, 16), Transform3D(disc, at), col)
	for k in 12:
		if broken and k in [2, 3, 4]:
			continue
		var a := TAU * float(k) / 12.0
		var off := (side * cos(a) + up * sin(a)) * 0.48
		QV.add_box(m, Transform3D(Basis(ax, a), at + off), Vector3(0.1, 0.1, 0.14), col)
	var mi := NV._mi(m.commit(), QV.metal_material(), "GearBroken" if broken else "GearFixed")
	add_child(mi)
	return mi


func _rod_instance(a: Vector3, b: Vector3, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = NV._cyl(r, r, 1.0, 6)
	mi.material_override = QV.metal_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var d := b - a
	var l := maxf(d.length(), 0.01)
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)
	return mi


static func _box_shape(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = xf.orthonormalized()
	body.add_child(cs)
