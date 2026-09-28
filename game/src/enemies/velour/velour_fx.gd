extends Node3D
## Count Velour's floor shadows and small procedural pieces (MP 13.1), shared by count_velour.gd and
## velour/bat_swarm.gd. One node per boss (top_level, freed with it):
##   * DROP shadow  - a soft dark disc under the hovering figure; it shrinks as he rises, so his height reads
##                    at a glance (out of reach high up = small shadow, within reach = broad shadow);
##   * LANE shadow  - during the bow his shadow STRETCHES along the coming cape-dash lane (a long velvet silhouette
##                    with his bat-eared head at the far end), growing with the wind-up: the lane is shown by his
##                    own shadow as well as the shared ground mark (src/enemies/telegraph_fx.gd).
## Static helpers:
##   bat_node(scale, true_bat) -> Node3D   a little procedural bat (the TRUE bat wears his collar ruff, gold
##                                          neck ring and tiny crown: the recognisable shape of phase B)
##   flap(bat, t, amount)                  wing beat for a bat_node
##   disperse(parent, pos) -> Node3D       defeat: the enchantment scatters as bats + the borrowed mask falls and
##                                          fades (no gore). Frees itself; nothing is spawned when headless
##                                          (tests pass force = true).

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const CreatureFx := preload("res://src/enemies/creature_fx.gd")

const SHADOW := Color(0.1, 0.03, 0.1)
const Y_DROP := 0.035
const Y_LANE := 0.045
const LANE_WIDTH := 1.1

const BAT_FUR := Color("5a3570")          # plum, a step lighter than the Gallery's dark walls (CR-04)
const BAT_WING := Color("4a2a5c")
const BAT_BELLY := Color("c9a3d6")        # a pale lilac belly + wing edge: they read against dark walls AND the carpet
const BAT_EDGE := Color(0.9, 0.78, 1.0)
const BAT_SIZE := 1.5                     # every bat is built 1.5x (the old ones were specks); `scale` multiplies it
const COLLAR := Color("8a1f45")
const COLLAR_LINING := Color("e6a0b8")
const GOLD := Color("e2bd5e")
const MASK := Color("2a1830")

var drop_visible := false
var lane_visible := false
var lane_from := Vector3.ZERO
var lane_to := Vector3.ZERO
var lane_k: float = 0.0

var _drop: MeshInstance3D
var _lane: Node3D
var _lane_body: MeshInstance3D
var _lane_head: MeshInstance3D
var _lane_ears: Array = []
var _mat: StandardMaterial3D

static var _disc: CylinderMesh = null
static var _ear: PrismMesh = null


func _ready() -> void:
	top_level = true
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(SHADOW, 0.5)
	_mat.disable_receive_shadows = true
	_drop = _part(self, _disc_mesh())
	_lane = Node3D.new()
	_lane.name = "LaneShadow"
	add_child(_lane)
	_lane_body = _part(_lane, _disc_mesh())
	_lane_head = _part(_lane, _disc_mesh())
	for s in [-1.0, 1.0]:
		var e := _part(_lane, _ear_mesh())
		e.set_meta("side", float(s))
		_lane_ears.append(e)
	hide_all()


func hide_all() -> void:
	set_drop(Vector3.ZERO, 0.0, false)
	hide_lane()


## Drop shadow under the figure at floor point `floor_pos`, figure `height` metres above it.
func set_drop(floor_pos: Vector3, height: float, on: bool) -> void:
	drop_visible = on
	if _drop == null:
		return
	_drop.visible = on
	if not on:
		return
	var r := clampf(1.05 - height * 0.18, 0.35, 0.95)
	_drop.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1.0, r)), floor_pos + Vector3.UP * Y_DROP)


## His shadow stretched from `a` toward `b` (floor points); `k` 0..1 = wind-up progress (it grows along the lane).
func show_lane(a: Vector3, b: Vector3, k: float) -> void:
	lane_visible = true
	lane_from = a
	lane_to = b
	lane_k = clampf(k, 0.0, 1.0)
	if _lane == null:
		return
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var full := d.length()
	if full < 0.05:
		_lane.visible = false
		return
	var dir := d / full
	var l := full * lerpf(0.35, 1.0, lane_k)
	_lane.visible = true
	var yaw := atan2(-dir.x, -dir.z)
	_lane.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(a.x, a.y + Y_LANE, a.z))
	# Body: a long tapering velvet silhouette; head (with bat ears) at the far end of the stretch.
	_lane_body.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(LANE_WIDTH * 0.5, 1.0, l * 0.5)), Vector3(0, 0, -l * 0.5))
	var hr := 0.42
	_lane_head.transform = Transform3D(Basis.IDENTITY.scaled(Vector3(hr, 1.0, hr)), Vector3(0, 0.002, -l))
	for e in _lane_ears:
		var s: float = float((e as Node).get_meta("side", 1.0))
		(e as MeshInstance3D).transform = Transform3D(Basis(Vector3.UP, s * 0.5).scaled(Vector3(0.28, 1.0, 0.42)), Vector3(s * 0.28, 0.003, -l - 0.42))
	_mat.albedo_color = Color(SHADOW, lerpf(0.35, 0.62, lane_k))


func hide_lane() -> void:
	lane_visible = false
	lane_k = 0.0
	if _lane != null:
		_lane.visible = false


func _part(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	parent.add_child(mi)
	return mi


## Flat unit disc (radius 1, thin) shared by every shadow.
static func _disc_mesh() -> CylinderMesh:
	if _disc == null:
		_disc = CylinderMesh.new()
		_disc.top_radius = 1.0
		_disc.bottom_radius = 1.0
		_disc.height = 0.004
		_disc.radial_segments = 24
		_disc.rings = 1
	return _disc


static func _ear_mesh() -> PrismMesh:
	if _ear == null:
		_ear = PrismMesh.new()
		_ear.size = Vector3(1.0, 0.004, 1.0)
	return _ear


# --- Bats ------------------------------------------------------------------------------------------------------

## A small procedural bat (origin = body centre). `true_bat`: his collar ruff, gold neck ring and tiny crown
## (the recognisable returning bat of phase B). Wings are children tagged with meta "wing" (+1 / -1).
static func bat_node(scale: float = 1.0, true_bat: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "TrueBat" if true_bat else "Bat"
	# The body hangs under one "Look" node at BAT_SIZE (the wings are scaled the same), so `root.scale` keeps its
	# meaning for the swarm (decoys shrink by setting it) and the true bat stays the biggest.
	var look := Node3D.new()
	look.name = "Look"
	look.scale = Vector3.ONE * BAT_SIZE
	root.add_child(look)
	var fur: Material = _bat_fur()
	var wing: Material = _bat_wing()
	Kit.add(look, Kit.sphere(0.1, fur, 8, 10), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.1, 1.2))
	Kit.add(look, Kit.sphere(0.06, Mat.toon(BAT_BELLY, {"rim": 0.4}), 6, 8), Vector3(0, -0.02, -0.07), Vector3.ZERO, Vector3(1.0, 1.1, 0.6))
	var wings: Array = []
	for s in [-1.0, 1.0]:
		Kit.add(look, Kit.cone(0.035, 0.1, fur, 6), Vector3(float(s) * 0.05, 0.11, -0.02), Vector3(0, 0, float(s) * -18.0))
		var w := Node3D.new()
		w.name = "WingL" if s < 0.0 else "WingR"
		w.set_meta("wing", float(s))
		w.position = Vector3(float(s) * 0.07, 0.02, 0.0) * BAT_SIZE
		w.scale = Vector3.ONE * BAT_SIZE               # the wings stay direct children (flap() / tests read them)
		root.add_child(w)
		wings.append(w)
		Kit.add(w, Kit.sphere(0.16, wing, 6, 8), Vector3(float(s) * 0.15, 0.0, 0.02), Vector3.ZERO, Vector3(1.0, 0.12, 0.62))
	var eye := Mat.glow(Color("ffd27a") if true_bat else Color("ff8fb0"), 2.0)
	for s in [-1.0, 1.0]:
		Kit.add(look, Kit.sphere(0.024, eye, 4, 6), Vector3(float(s) * 0.035, 0.03, -0.1))
	if true_bat:
		var collar := Mat.outlined(Mat.toon(COLLAR, {"rim": 0.55}), 0.012)
		var lining := Mat.toon(COLLAR_LINING, {"rim": 0.4})
		var gold := Mat.toon(GOLD, {"rim": 0.6, "specular": 0.45})
		for s in [-1.0, 1.0]:
			Kit.add(look, Kit.sphere(0.13, collar, 8, 10), Vector3(float(s) * 0.09, 0.08, 0.06), Vector3(0, 0, float(s) * -20.0), Vector3(0.9, 1.3, 0.2))
			Kit.add(look, Kit.sphere(0.11, lining, 8, 10), Vector3(float(s) * 0.085, 0.075, 0.05), Vector3(0, 0, float(s) * -20.0), Vector3(0.75, 1.1, 0.12))
		Kit.add(look, Kit.torus(0.07, 0.1, gold), Vector3(0, -0.04, 0))
		Kit.add(look, Kit.cylinder(0.045, 0.04, 0.04, gold, 8), Vector3(0.0, 0.14, 0.0), Vector3(0, 0, -10))
		for k in 5:
			var a := TAU * float(k) / 5.0
			Kit.add(look, Kit.cone(0.012, 0.04, gold, 5), Vector3(cos(a) * 0.04, 0.18, sin(a) * 0.04), Vector3(0, 0, -10))
	root.set_meta("wings", wings)          # flap() reads this: no get_children() array per frame
	root.scale = Vector3.ONE * scale
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## Shared bat materials: plum fur with an ink outline and a pale lilac edge light (reads on dark walls), wings with
## the same edge light (cached: every bat shares them).
static func _bat_fur() -> Material:
	return CreatureFx.toon_outlined_edge(Mat.toon(BAT_FUR, {"rim": 0.7, "noise": 0.2}), 0.012, Color(0.17, 0.12, 0.16), BAT_EDGE, 0.55)


static func _bat_wing() -> Material:
	return CreatureFx.toon_outlined_edge(Mat.toon(BAT_WING, {"rim": 0.6}), 0.008, Color(0.17, 0.12, 0.16), BAT_EDGE, 0.5)


## Wing beat for a bat_node (t = seconds, amount 0..1).
static func flap(bat: Node3D, t: float, amount: float = 1.0) -> void:
	if not bat.has_meta("wings"):
		return
	for w in bat.get_meta("wings") as Array:
		var s := float((w as Node).get_meta("wing", 1.0))
		(w as Node3D).rotation = Vector3(0.0, 0.0, s * sin(t * 18.0) * 0.8 * amount)


## Defeat presentation: the enchantment scatters as bats and the borrowed mask drops and fades (no gore).
## Returns the FX node (null when headless or without a parent). It frees itself after ~2.4 s.
static func disperse(parent: Node, pos: Vector3, force: bool = false) -> Node3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	if DisplayServer.get_name() == "headless" and not force:
		return null
	var fx := DisperseFx.new()
	fx.name = "VelourDisperse"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 14:
		var b := bat_node(rng.randf_range(0.7, 1.1), false)
		fx.add_child(b)
		var a := TAU * float(i) / 14.0 + rng.randf_range(-0.2, 0.2)
		fx.dirs.append(Vector3(cos(a), rng.randf_range(0.5, 1.3), sin(a)).normalized() * rng.randf_range(3.0, 5.0))
		fx.bats.append(b)
	var mask := Node3D.new()
	mask.name = "BorrowedMask"
	fx.add_child(mask)
	var mm := Mat.outlined(Mat.toon(MASK, {"rim": 0.5}), 0.012)
	Kit.add(mask, Kit.sphere(0.2, mm, 8, 12), Vector3.ZERO, Vector3.ZERO, Vector3(1.45, 0.55, 0.35))
	for s in [-1.0, 1.0]:
		Kit.add(mask, Kit.sphere(0.12, mm, 8, 10), Vector3(float(s) * 0.27, 0.05, 0.0), Vector3(0, 0, float(s) * -25.0), Vector3(1.4, 0.6, 0.25))
	fx.mask = mask
	parent.add_child(fx)
	fx.global_position = pos
	return fx


## The defeat burst (inner class: only built through disperse()).
class DisperseFx extends Node3D:
	const LIFE := 2.4
	var bats: Array = []
	var dirs: Array = []
	var mask: Node3D = null
	var _t := 0.0

	func _ready() -> void:
		top_level = true

	func _process(delta: float) -> void:
		_t += delta
		var fade := clampf(1.0 - (_t - 1.2) / 1.2, 0.0, 1.0)
		for i in bats.size():
			var b := bats[i] as Node3D
			b.position += (dirs[i] as Vector3) * delta
			if b.has_meta("wings"):
				for w in b.get_meta("wings") as Array:
					(w as Node3D).rotation = Vector3(0.0, 0.0, float((w as Node).get_meta("wing", 1.0)) * sin((_t + float(i)) * 18.0) * 0.8)
			b.scale = Vector3.ONE * maxf(fade, 0.01) * 0.9
		if mask != null:
			var k := clampf(_t / 1.1, 0.0, 1.0)
			mask.position = Vector3(0.0, -k * k * 1.1, 0.0)
			mask.rotation = Vector3(k * 1.2, k * 0.8, k * 0.4)
			mask.scale = Vector3.ONE * maxf(fade, 0.01)
		if _t >= LIFE:
			queue_free()
