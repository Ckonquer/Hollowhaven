extends Node3D
## A fixed mineral pillar in the Quarry Warden's arena (MP §12: bait the Warden's committed charge into a pillar
## to crack its shell open; at least two pillars and a recoverable reset so the arena is never unwinnable).
## API for the Warden enemy (a later wave) and the arena:
##   crack() -> bool       breaks an intact pillar (true if it WAS intact); a cracked pillar re-knits by itself
##                         after `regrow_seconds` (< 0 = never) - the recoverable reset
##   reset()               restores it at once (retry / victory / arena reset); no-op when intact
##   is_intact() -> bool
##   contains(pos, margin := 0.0) -> bool   XZ test against the pillar's radius (charge contact)
##   get_aim_point() -> Vector3             chest-height centre (aiming a charge at it)
##   pillar_id, hit_radius, signals cracked(pillar), restored(pillar); group "quarry_pillar"
## The pillar is solid (layer 1, "stone"); cracked, it stays as a knee-high stump (still an obstacle).
## Settings high_visibility_cues adds a bold ring marker around intact pillars (never colour alone: the ring
## disappears when the pillar is cracked).

signal cracked(pillar: Node3D)
signal restored(pillar: Node3D)

const Q := preload("res://data/reach_east.gd")
const QV := preload("res://src/world/reach/east/quarry_visuals.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Mat := preload("res://src/art/mat.gd")
const Fx := preload("res://src/world/common/fx.gd")

var pillar_id: String = "pillar"
var hit_radius: float = Q.PILLAR_RADIUS
var height: float = Q.PILLAR_HEIGHT
var regrow_seconds: float = Q.PILLAR_REGROW
var variant: int = 0

var _intact := true
var _regrow_left := -1.0
var _body: StaticBody3D
var _shape: CollisionShape3D
var _whole: Node3D
var _stump: Node3D
var _ring: MeshInstance3D

static var _meshes: Dictionary = {}


func setup(p: Dictionary) -> void:
	pillar_id = String(p.get("id", pillar_id))
	hit_radius = float(p.get("radius", hit_radius))
	height = float(p.get("height", height))
	regrow_seconds = float(p.get("regrow_seconds", regrow_seconds))
	variant = int(p.get("variant", variant))


func _ready() -> void:
	name = "Pillar_" + pillar_id
	add_to_group("quarry_pillar")
	_build()
	_apply(false)
	set_process(false)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func is_intact() -> bool:
	return _intact


func crack() -> bool:
	if not _intact:
		return false
	_intact = false
	_regrow_left = regrow_seconds
	_apply(true)
	set_process(regrow_seconds >= 0.0)
	cracked.emit(self)
	return true


func reset() -> void:
	_regrow_left = -1.0
	set_process(false)
	if _intact:
		return
	_intact = true
	_apply(true)
	restored.emit(self)


## Shortens the remaining re-knit time (the arena uses it when every pillar is cracked at once).
func hurry_regrow(seconds: float) -> void:
	if not _intact and _regrow_left > seconds:
		_regrow_left = seconds
		set_process(true)


func regrow_left() -> float:
	return _regrow_left


func contains(pos: Vector3, margin: float = 0.0) -> bool:
	var g := global_position if is_inside_tree() else position
	return Vector2(pos.x - g.x, pos.z - g.z).length() <= hit_radius + margin


func get_aim_point() -> Vector3:
	var g := global_position if is_inside_tree() else position
	return g + Vector3(0, minf(height, 1.4), 0)


func _process(delta: float) -> void:
	if _intact or _regrow_left < 0.0:
		set_process(false)
		return
	_regrow_left -= delta
	if _regrow_left <= 0.0:
		reset()
		Events.caption.emit(Q.TEXT["pillar_restored_caption"])


# --- Visuals / collision --------------------------------------------------------------------------------

func _build() -> void:
	var key := "p|%d|%.2f|%.2f" % [posmod(variant, 3), hit_radius, height]
	if not _meshes.has(key):
		_meshes[key] = _make_meshes(posmod(variant, 3))
	var parts: Array = _meshes[key]
	_whole = Node3D.new()
	_whole.name = "Whole"
	add_child(_whole)
	_whole.add_child(NV._mi(parts[0], QV.stone_material(), "Column"))
	_whole.add_child(NV._mi(parts[1], QV.crystal_material(), "Crystal"))
	_stump = Node3D.new()
	_stump.name = "Stump"
	add_child(_stump)
	_stump.add_child(NV._mi(parts[2], QV.stone_material(), "StumpRock"))
	_stump.add_child(NV._mi(parts[3], QV.crystal_material(), "Shards"))
	_body = StaticBody3D.new()
	_body.name = "Solid"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	_shape = CollisionShape3D.new()
	_body.add_child(_shape)
	add_child(_body)
	_ring = MeshInstance3D.new()
	_ring.name = "CueRing"
	var tm := TorusMesh.new()
	tm.inner_radius = hit_radius + 0.55
	tm.outer_radius = hit_radius + 0.8
	tm.rings = 24
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	_ring.position = Vector3(0, 0.06, 0)
	_ring.material_override = Mat.glow(Color("fff2c8"), 1.6)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _make_meshes(v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9500 + v
	var fn := func(p: Vector3, n: Vector3) -> Color:
		var c := Q.COL_ROCK_DARK.lerp(Q.COL_ROCK, clampf(p.y / height * 0.8 + 0.3, 0.0, 1.0))
		return c.lerp(Q.COL_ROCK_LIGHT, clampf((n.y - 0.6) * 2.0, 0.0, 1.0) * 0.5)
	var col := NV.Merger.new()
	var cry := NV.Merger.new()
	var stump := NV.Merger.new()
	var shards := NV.Merger.new()
	var r := hit_radius
	var segs := 4
	for i in segs:
		var t := float(i) / float(segs)
		var y := height * (t + 0.5 / float(segs))
		var rr := r * lerpf(1.08, 0.82, t) * rng.randf_range(0.95, 1.05)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		col.add(Kit.blob_mesh(1.0, 9510 + i + v * 5, 0.16, 1.0, 2), Transform3D(b * Basis.from_scale(Vector3(rr, height / float(segs) * 0.62, rr)), Vector3(0, y, 0)), fn)
		if i < 2:
			stump.add(Kit.blob_mesh(1.0, 9510 + i + v * 5, 0.16, 1.0, 2), Transform3D(b * Basis.from_scale(Vector3(rr * 1.02, height / float(segs) * 0.62, rr * 1.02)), Vector3(0, y * (Q.PILLAR_STUMP / (height * 0.5)), 0)), fn)
	# a pale crystal band spiralling up the column and a crown cluster
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf() * 0.3
		var y := height * (0.25 + 0.14 * float(i))
		var p := Vector3(cos(a) * r * 0.9, y, sin(a) * r * 0.9)
		var b := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, 1.1)
		cry.add(NV._cyl(0.07, 0.07, 0.5, 6), Transform3D(b, p), Q.COL_CRYSTAL.lerp(Q.COL_CRYSTAL_DEEP, 0.3))
	for i in 5:
		var tilt := 0.0 if i == 0 else 0.55
		var b := Basis(Vector3.UP, TAU * float(i) / 5.0) * Basis(Vector3.RIGHT, tilt)
		var h := 0.9 if i == 0 else 0.55
		cry.add(NV._cyl(0.11, 0.11, h, 6), Transform3D(b, Vector3(0, height, 0) + b * Vector3(0, h * 0.5, 0)), Q.COL_CRYSTAL)
		cry.add(NV._cyl(0.0, 0.11, 0.22, 6), Transform3D(b, Vector3(0, height, 0) + b * Vector3(0, h + 0.11, 0)), Color("ffffff"))
	# broken top: jagged shards pointing out of the stump
	for i in 6:
		var a := TAU * float(i) / 6.0
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, rng.randf_range(0.2, 0.7))
		var h := rng.randf_range(0.3, 0.6)
		shards.add(NV._cyl(0.0, 0.1, h, 5), Transform3D(b, Vector3(cos(a) * r * 0.45, Q.PILLAR_STUMP, sin(a) * r * 0.45) + b * Vector3(0, h * 0.5, 0)), Q.COL_CRYSTAL.lerp(Color("ffffff"), 0.3))
	return [col.commit(), cry.commit(), stump.commit(), shards.commit()]


func _apply(animate: bool) -> void:
	if _whole == null:
		return
	_whole.visible = _intact
	_stump.visible = not _intact
	var cyl := CylinderShape3D.new()
	cyl.radius = hit_radius
	cyl.height = height if _intact else Q.PILLAR_STUMP
	_shape.shape = cyl
	_shape.position = Vector3(0, cyl.height * 0.5, 0)
	_ring.visible = _intact and bool(Settings.get_value("high_visibility_cues"))
	if animate and is_inside_tree():
		var at := global_position + Vector3(0, height * 0.6, 0)
		if not _intact:
			Fx.burst(get_parent(), at, "crystal", 1.6)
			Fx.burst(get_parent(), at, "chips", 1.4)
			if Audio.has_sound("rock_break"):
				Audio.play_3d("rock_break", at, 0.0)
			Events.camera_shake.emit(0.25, 0.35)
			Events.caption.emit(Q.TEXT["pillar_caption"])
		else:
			Fx.burst(get_parent(), at, "sparkle", 1.2)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" and _ring != null:
		_ring.visible = _intact and bool(Settings.get_value("high_visibility_cues"))
