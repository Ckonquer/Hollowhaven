extends Node3D
## Landmark set pieces of Hollowhaven Woods (everything hand-placed, deterministic):
## Krystal's Haven (Ward Stone, campfire, sign, fences, seats, hidden restoration lanterns & garlands),
## Berry Glade mushroom ring, Pebble Quarry props, Moonlit Ruin (arches, columns, Lumi's alcove,
## moonpetals), The Old Oak (giant tree with a swing), Mirror Pond jetty, the Hollow Mine entrance and
## the enemy spawners (only if res://src/enemies/enemy_spawner.gd exists).

const Layout := preload("res://data/world_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")
const WardStone := preload("res://src/world/surface/ward_stone.gd")
const Campfire := preload("res://src/world/surface/campfire.gd")
const MineEntrance := preload("res://src/world/surface/mine_entrance.gd")

const SPAWNER_SCRIPT := "res://src/enemies/enemy_spawner.gd"
const FONT_PATH := "res://assets/fonts/Fredoka-Variable.ttf"

var terrain: RefCounted
var ward_stone: Node3D
var campfire: Node3D
var mine_entrance: Node3D
var restore_group: Node3D          # lanterns + garlands shown when the ward is restored
var restore_lights: Array = []
var restore_items: Array = []      # [node, target_scale]
var moonpetal_material: StandardMaterial3D
var spawners: Array = []
var _body: StaticBody3D            # shared static collision for landmark props
var build_times: Dictionary = {}


func _ready() -> void:
	name = "Landmarks"
	_body = StaticBody3D.new()
	_body.name = "LandmarkCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	add_child(_body)
	var steps := [_build_haven, _build_glade, _build_quarry, _build_ruin, _build_old_oak, _build_pond, _build_mine, _build_spawners]
	var names := ["haven", "glade", "quarry", "ruin", "old_oak", "pond", "mine", "spawners"]
	for i in steps.size():
		var t0 := Time.get_ticks_usec()
		(steps[i] as Callable).call()
		build_times[names[i]] = float(Time.get_ticks_usec() - t0) / 1000.0


func _y(p: Vector2) -> float:
	return terrain.height_at(p.x, p.y)


func _v3(p: Vector2, dy: float = 0.0) -> Vector3:
	return Vector3(p.x, _y(p) + dy, p.y)


func _box_col(xf: Transform3D, size: Vector3, surface: String = "stone") -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = xf
	if surface != "stone":
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", surface)
		add_child(body)
		body.add_child(cs)
	else:
		_body.add_child(cs)


func _cyl_col(pos: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	cs.shape = c
	cs.position = pos + Vector3(0, height * 0.5, 0)
	_body.add_child(cs)


# --- Krystal's Haven -------------------------------------------------------------------------------------

func _build_haven() -> void:
	var g := Node3D.new()
	g.name = "Haven"
	add_child(g)
	ward_stone = WardStone.new()
	g.add_child(ward_stone)
	ward_stone.position = _v3(SL.WARD_STONE, -0.05)
	campfire = Campfire.new()
	g.add_child(campfire)
	campfire.position = _v3(SL.CAMPFIRE, 0.0)
	# Log seats around the fire
	var bark := NodeVisuals.bark_material()
	for a_deg in [205.0, 320.0, 95.0]:
		var a := deg_to_rad(a_deg)
		var p := SL.CAMPFIRE + Vector2(cos(a), sin(a)) * 2.35
		var seat := Props.instance(Props.fallen_log(int(a_deg) % 3), bark)
		seat.position = _v3(p, -0.12)
		seat.rotation.y = -a + PI * 0.5
		seat.scale = Vector3(0.52, 0.85, 0.85)
		g.add_child(seat)
		_box_col(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), _v3(p, 0.2)), Vector3(1.7, 0.5, 0.5), "wood")
	# The sign
	_build_sign(g)
	# Fences in short runs around the clearing edge, leaving the path exits open.
	var exits: Array = []
	for id in SL.PATHS:
		var curve: PackedVector2Array = terrain.path_curves.get(id, PackedVector2Array())
		for c in curve:
			var r := c.length()
			if r > 17.5 and r < 21.0:
				exits.append(atan2(c.y, c.x))
				break
	var fence_mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.25, "noise": 0.1}), 0.018)
	var fence_mesh := Props.fence_segment()
	var fr := 19.2
	var seg_ang := 2.0 / fr
	var runs := 0
	var a0 := -PI
	while a0 < PI:
		var mid := a0 + seg_ang * 0.5
		var blocked := false
		for e in exits:
			if absf(wrapf(mid - float(e), -PI, PI)) < 0.22:
				blocked = true
		var p := Vector2(cos(mid), sin(mid)) * fr
		if terrain.stream_distance(p.x, p.y) < 4.5 or terrain.path_at(p.x, p.y) > 0.05:
			blocked = true
		# gentle rhythm: 3 on, 2 off
		if runs % 5 >= 3:
			blocked = true
		runs += 1
		if not blocked:
			var fp := Vector2(cos(mid), sin(mid)) * fr
			var mi := Props.instance(fence_mesh, fence_mat, 110.0)
			mi.position = _v3(fp, -0.03)
			mi.rotation.y = -mid + PI * 0.5
			g.add_child(mi)
			_box_col(Transform3D(Basis(Vector3.UP, -mid + PI * 0.5), _v3(fp, 0.5)), Vector3(2.0, 1.0, 0.2), "wood")
		a0 += seg_ang
	_build_restoration_decor(g)


func _build_sign(parent: Node3D) -> void:
	var p := SL.SIGN
	var yaw := atan2(-(0.0 - p.x), -(4.0 - p.y))    # face toward the Haven centre
	var root := Node3D.new()
	root.name = "HavenSign"
	parent.add_child(root)
	root.position = _v3(p, -0.05)
	root.rotation.y = yaw + PI
	var m := NodeVisuals.Merger.new()
	for sx in [-0.85, 0.85]:
		m.add(NodeVisuals._box(Vector3(0.16, 2.2, 0.16)), Transform3D(Basis(), Vector3(float(sx), 1.1, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._box(Vector3(2.3, 0.8, 0.12)), Transform3D(Basis(Vector3.BACK, deg_to_rad(-1.5)), Vector3(0, 1.72, 0.02)), Palette.WOOD)
	m.add(NodeVisuals._box(Vector3(2.45, 0.1, 0.18)), Transform3D(Basis(), Vector3(0, 2.16, 0.02)), Palette.WOOD_DARK)
	m.add(Kit.blob_mesh(0.14, 9500, 0.2, 0.5, 1), Transform3D(Basis(), Vector3(-1.0, 2.25, 0.05)), Palette.FLOWER_RED)
	m.add(Kit.blob_mesh(0.12, 9501, 0.2, 0.5, 1), Transform3D(Basis(), Vector3(-0.8, 2.25, 0.1)), Palette.FLOWER_YELLOW)
	m.add(Kit.blob_mesh(0.18, 9502, 0.3, 0.5, 1), Transform3D(Basis(), Vector3(-0.9, 2.2, -0.05)), Palette.FOLIAGE)
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.12, "noise_scale": 2.5}), 0.02)
	root.add_child(mi)
	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	for side in [0, 1]:
		var lbl := Label3D.new()
		lbl.text = "Krystal's Haven"
		if font != null:
			lbl.font = font
		# 72 px * 0.0042 = ~2.05 m of text on the 2.3 m board (88 px overflowed its edges).
		lbl.font_size = 72
		lbl.pixel_size = 0.0042
		lbl.modulate = Color("4a2e20")
		lbl.outline_modulate = Color("f7ecd6")
		lbl.outline_size = 8
		lbl.double_sided = false
		# Painted letters: lit like the board, so the sign does not glow in the dark at night.
		lbl.shaded = true
		lbl.position = Vector3(0, 1.74, 0.1 if side == 0 else -0.1)
		lbl.rotation.y = 0.0 if side == 0 else PI
		root.add_child(lbl)
	_box_col(Transform3D(Basis(Vector3.UP, yaw + PI), _v3(p, 1.1)), Vector3(2.2, 2.2, 0.25), "wood")


## Lantern posts + garlands around the clearing, hidden until the Ward is restored.
func _build_restoration_decor(parent: Node3D) -> void:
	restore_group = Node3D.new()
	restore_group.name = "RestorationDecor"
	parent.add_child(restore_group)
	var wood := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.12}), 0.02)
	var glass_mat := Mat.glow(Palette.LANTERN_GLOW, 2.4)
	var post_mesh := Props.lantern_post()
	var n := 8
	var posts: Array = []
	for i in n:
		var a := TAU * float(i) / float(n) + 0.2
		var p := Vector2(cos(a), sin(a)) * 13.5
		if terrain.path_at(p.x, p.y) > 0.3:
			p = Vector2(cos(a + 0.12), sin(a + 0.12)) * 13.5
		var post := Node3D.new()
		post.position = _v3(p, -0.02)
		post.rotation.y = -a - PI * 0.5
		restore_group.add_child(post)
		var pm := Props.instance(post_mesh, wood, 140.0)
		post.add_child(pm)
		var glass := MeshInstance3D.new()
		glass.mesh = Props.lantern_glass()
		glass.material_override = glass_mat
		glass.position = Vector3(0.38, Props.LANTERN_Y, 0)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post.add_child(glass)
		var l := OmniLight3D.new()
		l.light_color = Palette.LANTERN_GLOW
		l.light_energy = 1.3
		l.omni_range = 6.5
		l.shadow_enabled = false
		l.position = Vector3(0.38, Props.LANTERN_Y, 0)
		post.add_child(l)
		restore_lights.append(l)
		restore_items.append([post, Vector3.ONE])
		posts.append(post)
	# Garlands between neighbouring posts (bunting in Haven colours).
	var cols := [Palette.CLOTH_RED, Palette.K_SCARF, Palette.TEAL, Palette.BLOSSOM, Palette.CLOTH_CREAM]
	# No outline pass: flat two-sided flags would be covered by the inverted hull.
	var gmat := Mat.toon(Color.WHITE, {"vertex_color": true, "wind": 0.04, "wind_height": 0.4, "rim": 0.3})
	for i in n:
		var a: Node3D = posts[i]
		var b: Node3D = posts[(i + 1) % n]
		var pa: Vector3 = a.position + Vector3(0, 2.15, 0)
		var pb: Vector3 = b.position + Vector3(0, 2.15, 0)
		var d := pb - pa
		var span := Vector2(d.x, d.z).length()
		var gm := Props.instance(Props.garland(span, cols), gmat, 120.0, false)
		var holder := Node3D.new()
		holder.position = (pa + pb) * 0.5
		holder.rotation.y = atan2(-d.z, d.x)
		holder.rotation.z = atan2(d.y, span)
		restore_group.add_child(holder)
		holder.add_child(gm)
		restore_items.append([holder, Vector3.ONE])
	set_restored_instant(bool(GameState.get_flag("ward_restored")))


func set_restored_instant(on: bool) -> void:
	if restore_group == null:
		return
	restore_group.visible = on
	for it in restore_items:
		(it[0] as Node3D).scale = it[1] if on else Vector3.ONE * 0.01


# --- Berry Glade -------------------------------------------------------------------------------------------

func _build_glade() -> void:
	var c: Vector2 = Layout.SPAWN_HINTS["companion_wild_mochi"]
	var mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.45}), 0.012)
	var xfs: Array = []
	for i in 12:
		var a := TAU * float(i) / 12.0 + 0.15
		var p := c + Vector2(cos(a), sin(a)) * 2.5
		var s := 0.9 + float((i * 7) % 5) * 0.12
		xfs.append(Transform3D(Basis(Vector3.UP, a).scaled(Vector3(s, s, s)), _v3(p, -0.02)))
	var mm := Props.multimesh(Props.mushroom_cluster(1), mat, xfs, "FairyRing", 90.0)
	add_child(mm)


# --- Pebble Quarry ------------------------------------------------------------------------------------------

func _build_quarry() -> void:
	var q: Vector2 = Layout.LANDMARKS["quarry"]["pos"]
	var g := Node3D.new()
	g.name = "Quarry"
	add_child(g)
	var stone_mat := NodeVisuals.rock_material(0.025)
	# Cut stone blocks, stacked
	var blocks: Array = [[Vector2(-5.5, 6.0), Vector3(1.0, 0.7, 0.8), 0.0], [Vector2(-4.4, 6.3), Vector3(0.9, 0.7, 0.8), 0.0],
		[Vector2(-5.0, 6.1), Vector3(0.9, 0.6, 0.7), 0.7], [Vector2(-3.2, 5.0), Vector3(0.7, 0.5, 0.6), 0.0]]
	for i in blocks.size():
		var bd: Array = blocks[i]
		var p: Vector2 = q + (bd[0] as Vector2)
		var sz: Vector3 = bd[1]
		var mi := Props.instance(Props.stone_block(60 + i, sz, Color("c9c1b2"), 0.1), stone_mat, 120.0)
		mi.position = _v3(p, float(bd[2]) - 0.03)
		mi.rotation.y = float(i) * 0.4
		g.add_child(mi)
		_box_col(Transform3D(Basis(Vector3.UP, float(i) * 0.4), _v3(p, float(bd[2]) + sz.y * 0.5)), sz * 0.9)
	# A wooden ladder leaning on the first terrace + a pickaxe stuck in a rock
	var wood := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.1}), 0.018)
	var lad := NodeVisuals.Merger.new()
	for sx in [-0.3, 0.3]:
		lad.add(NodeVisuals._box(Vector3(0.08, 2.6, 0.08)), Transform3D(Basis(), Vector3(float(sx), 1.3, 0)), Palette.WOOD_DARK)
	for i in 6:
		lad.add(NodeVisuals._box(Vector3(0.6, 0.06, 0.07)), Transform3D(Basis(), Vector3(0, 0.3 + float(i) * 0.42, 0)), Palette.WOOD)
	var qdir := SL.QUARRY_TERRACE_DIR.normalized()
	var lp := q + qdir * 9.0 + Vector2(-qdir.y, qdir.x) * 3.0
	var ladder := Props.instance(lad.commit(), wood, 120.0)
	ladder.position = _v3(lp, 0.0)
	ladder.rotation = Vector3(deg_to_rad(-18.0), atan2(qdir.x, qdir.y) + PI, 0)
	g.add_child(ladder)
	var pick := NodeVisuals.Merger.new()
	pick.add(NodeVisuals._cyl(0.035, 0.04, 1.0, 6), Transform3D(Basis(Vector3.BACK, deg_to_rad(20.0)), Vector3(0, 0.5, 0)), Palette.WOOD)
	pick.add(NodeVisuals._cyl(0.03, 0.05, 0.7, 6), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)) * Basis(Vector3.BACK, deg_to_rad(20.0)), Vector3(-0.17, 0.95, 0)), Palette.STONE_DARK)
	var pk := Props.instance(pick.commit(), wood, 80.0)
	pk.position = _v3(q + Vector2(-2.0, 7.2), 0.55)
	g.add_child(pk)
	var prock := Props.instance(NodeVisuals.boulder_mesh(1, Palette.STONE, 0.4), stone_mat, 120.0)
	prock.position = _v3(q + Vector2(-2.0, 7.2), -0.25)
	prock.scale = Vector3.ONE * 0.75
	g.add_child(prock)
	_cyl_col(_v3(q + Vector2(-2.0, 7.2), -0.2), 0.65, 0.9)


# --- Moonlit Ruin ----------------------------------------------------------------------------------------------

func _build_ruin() -> void:
	var rc: Vector2 = Layout.LANDMARKS["ruin"]["pos"]
	var lumi: Vector2 = Layout.SPAWN_HINTS["companion_wild_lumi"]
	var g := Node3D.new()
	g.name = "Ruin"
	add_child(g)
	var tint := Color("c2bba8")
	var stone_mat := NodeVisuals.rock_material(0.028)
	var ivy_mat := Mat.outlined(Mat.toon(Color("6a9e4a"), {"noise": 0.2, "noise_scale": 2.0, "rim": 0.25}), 0.016)
	var floor_y := _y(rc)
	# Flagstone floor (flat slabs set into the ground)
	var fl := NodeVisuals.Merger.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7070
	for i in 46:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 6.5
		var p := rc + Vector2(cos(a), sin(a)) * r
		var sz := Vector3(rng.randf_range(0.8, 1.3), 0.12, rng.randf_range(0.7, 1.1))
		fl.add(NodeVisuals._box(sz), Transform3D(Basis(Vector3.UP, rng.randf() * 0.5), Vector3(p.x, _y(p) + 0.02, p.y)), tint.darkened(rng.randf() * 0.18))
	var flm := Props.instance(fl.commit(), NodeVisuals.rock_material(0.0), 140.0, false)
	g.add_child(flm)
	# Broken columns around the courtyard (some fallen)
	var n := 9
	for i in n:
		var a := TAU * float(i) / float(n) + 0.3
		var p := rc + Vector2(cos(a), sin(a)) * 6.8
		if p.distance_to(lumi) < 3.8 or p.distance_to(rc + Vector2(0, 6.5)) < 2.2:
			continue
		var hgt: float = [3.4, 1.2, 2.6, 0.8, 3.0, 1.8, 2.2, 0.6, 2.9][i]
		var col := NodeVisuals.Merger.new()
		col.add(NodeVisuals._box(Vector3(0.9, 0.3, 0.9)), Transform3D(Basis(), Vector3(0, 0.15, 0)), tint.darkened(0.15))
		col.add(NodeVisuals._cyl(0.34, 0.38, hgt, 10), Transform3D(Basis(), Vector3(0, 0.3 + hgt * 0.5, 0)), tint)
		if hgt > 2.5:
			col.add(NodeVisuals._box(Vector3(0.95, 0.28, 0.95)), Transform3D(Basis(), Vector3(0, 0.3 + hgt + 0.14, 0)), tint.darkened(0.08))
			col.add(Kit.blob_mesh(0.42, 7085 + i, 0.35, 0.35, 1), Transform3D(Basis(), Vector3(0.1, 0.3 + hgt + 0.3, 0.05)), Palette.MOSS)
		else:
			col.add(Kit.blob_mesh(0.36, 7080 + i, 0.3, 0.6, 1), Transform3D(Basis(), Vector3(0, 0.3 + hgt, 0)), tint.darkened(0.1))
			col.add(Kit.blob_mesh(0.3, 7095 + i, 0.35, 0.4, 1), Transform3D(Basis(), Vector3(0.0, 0.3 + hgt + 0.18, 0.0)), Palette.MOSS)
		var cm := Props.instance(col.commit(), stone_mat, 150.0)
		cm.position = Vector3(p.x, _y(p) - 0.05, p.y)
		cm.rotation.y = a
		g.add_child(cm)
		_cyl_col(Vector3(p.x, _y(p), p.y), 0.42, hgt + 0.5)
		if i % 3 == 0:
			var ivy := _ivy_cluster(hgt, 0.4)
			ivy.material_override = ivy_mat
			ivy.position = cm.position
			ivy.rotation.y = a + 0.6
			g.add_child(ivy)
		if hgt < 1.3:
			# a fallen drum lying next to a short stump
			var drum := Props.instance(NodeVisuals._cyl(0.34, 0.36, 1.6, 10), Mat.outlined(Mat.toon(tint, {"noise": 0.12}), 0.028), 120.0)
			var dp := p + Vector2(cos(a + 0.8), sin(a + 0.8)) * 1.5
			drum.position = Vector3(dp.x, _y(dp) + 0.3, dp.y)
			drum.rotation = Vector3(0, a, deg_to_rad(90.0))
			g.add_child(drum)
			_box_col(Transform3D(Basis(Vector3.UP, a), Vector3(dp.x, _y(dp) + 0.3, dp.y)), Vector3(1.6, 0.6, 0.6))
	# Two arches: the entrance (south, the path passes through) and a broken one to the west.
	_arch(g, rc + Vector2(0, 6.8), 0.0, tint, false)
	_arch(g, rc + Vector2(-6.9, -1.0), PI * 0.5, tint, true)
	# Lumi's alcove: a curved half-wall with a moon relief, open toward the courtyard.
	var al := NodeVisuals.Merger.new()
	var seg := 9
	for i in seg:
		var a := lerpf(PI * 1.1, PI * 1.9, float(i) / float(seg - 1))
		var p := Vector2(cos(a), sin(a)) * 2.7
		var hgt := 2.9 - absf(float(i) - 4.0) * 0.18 + (0.5 if i == 4 else 0.0)
		al.add(NodeVisuals._box(Vector3(1.05, hgt, 0.6)), Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(p.x, hgt * 0.5, p.y)), tint.darkened(0.05 + float(i % 2) * 0.06))
		_box_col(Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(lumi.x + p.x, floor_y + hgt * 0.5, lumi.y + p.y)), Vector3(1.05, hgt, 0.6))
	al.add(NodeVisuals._box(Vector3(2.6, 0.25, 1.6)), Transform3D(Basis(), Vector3(0, 0.05, -1.4)), tint.darkened(0.12))
	var alm := Props.instance(al.commit(), stone_mat, 160.0)
	alm.position = Vector3(lumi.x, floor_y - 0.05, lumi.y)
	g.add_child(alm)
	moonpetal_material = StandardMaterial3D.new()
	moonpetal_material.albedo_color = Color("e8f2ff")
	moonpetal_material.emission_enabled = true
	moonpetal_material.emission = Palette.RUIN_LIGHT.lerp(Color("cfe0ff"), 0.6)
	moonpetal_material.emission_energy_multiplier = 0.3
	var moon := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.34
	tor.outer_radius = 0.46
	tor.rings = 24
	tor.ring_segments = 6
	moon.mesh = tor
	moon.material_override = moonpetal_material
	moon.position = Vector3(lumi.x, floor_y + 2.1, lumi.y - 2.35)
	moon.rotation = Vector3(deg_to_rad(90.0), 0, 0)
	g.add_child(moon)
	var moon_fill := MeshInstance3D.new()
	moon_fill.mesh = NodeVisuals._sph(0.3, 8, 12)
	moon_fill.material_override = moonpetal_material
	moon_fill.scale = Vector3(1, 1, 0.3)
	moon_fill.position = Vector3(lumi.x + 0.08, floor_y + 2.1, lumi.y - 2.38)
	g.add_child(moon_fill)
	# Ivy trailing down the alcove wall
	for i in 3:
		var a := lerpf(PI * 1.2, PI * 1.8, float(i) / 2.0)
		var ivy := _ivy_cluster(2.8, 0.55)
		ivy.material_override = ivy_mat
		ivy.position = Vector3(lumi.x + cos(a) * 2.35, floor_y, lumi.y + sin(a) * 2.35)
		ivy.rotation.y = -a - PI * 0.5
		g.add_child(ivy)
	# Moonpetals: small pale flowers that glow softly at night.
	var mp := NodeVisuals.Merger.new()
	for i in 5:
		var a := TAU * float(i) / 5.0
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(-25.0))
		mp.add(Kit.blob_mesh(0.05, 7200 + i, 0.1, 0.35, 1), Transform3D(b, Vector3(0, 0.22, 0) + b * Vector3(0, 0, -0.05)), Color.WHITE)
	mp.add(NodeVisuals._cyl(0.01, 0.012, 0.22, 4), Transform3D(Basis(), Vector3(0, 0.11, 0)), Color("9fcf9a"))
	var mp_mesh := mp.commit()
	var xfs: Array = []
	rng.seed = 7171
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.0, 9.5)
		var p := rc + Vector2(cos(a), sin(a)) * r
		if terrain.path_at(p.x, p.y) > 0.3:
			continue
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), _v3(p, 0.0)))
	for i in 14:
		var a := rng.randf_range(PI * 1.15, PI * 1.85)
		var p := lumi + Vector2(cos(a), sin(a)) * rng.randf_range(0.6, 2.0)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, floor_y + 0.08, p.y)))
	g.add_child(Props.multimesh(mp_mesh, moonpetal_material, xfs, "Moonpetals", 90.0, false))


## A trail of small leaf clumps hanging down a wall/column from `top` (local), offset outward by `out`.
func _ivy_cluster(top: float, out: float) -> MeshInstance3D:
	var key := "ivy|%.2f|%.2f" % [top, out]
	var m := NodeVisuals.Merger.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var n := int(top * 3.0) + 3
	for i in n:
		var t := float(i) / float(n)
		var p := Vector3(rng.randf_range(-0.25, 0.25), top - t * top * 0.85, out + rng.randf_range(-0.05, 0.08))
		var r := lerpf(0.2, 0.1, t) * rng.randf_range(0.8, 1.2)
		m.add(NodeVisuals.ublob(i, 0.35, 0.7, 1), NodeVisuals.sxf(r, p), Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	return mi


func _arch(parent: Node3D, p: Vector2, yaw: float, tint: Color, broken: bool) -> void:
	var m := NodeVisuals.Merger.new()
	var span := 3.2
	var hgt := 3.2
	for sx in [-1.0, 1.0]:
		var ph: float = hgt if not (broken and sx > 0.0) else 1.6
		m.add(NodeVisuals._box(Vector3(0.75, ph, 0.75)), Transform3D(Basis(), Vector3(float(sx) * span * 0.5, ph * 0.5, 0)), tint.darkened(0.06))
	var segs := 7
	for i in segs:
		var t := float(i) / float(segs - 1)
		if broken and t > 0.45:
			continue
		var a := PI * (1.0 - t)
		var x := cos(a) * span * 0.5
		var y := hgt + sin(a) * 1.0
		m.add(NodeVisuals._box(Vector3(0.62, 0.5, 0.72)), Transform3D(Basis(Vector3.BACK, a - PI * 0.5), Vector3(x, y, 0)), tint.lightened(0.03 * float(i % 2)))
	var mi := Props.instance(m.commit(), NodeVisuals.rock_material(0.028), 160.0)
	mi.position = _v3(p, -0.05)
	mi.rotation.y = yaw
	parent.add_child(mi)
	var bs := Basis(Vector3.UP, yaw)
	for sx in [-1.0, 1.0]:
		var ph: float = hgt if not (broken and sx > 0.0) else 1.6
		var off: Vector3 = bs * Vector3(float(sx) * span * 0.5, 0, 0)
		_box_col(Transform3D(bs, _v3(p, ph * 0.5) + off), Vector3(0.75, ph, 0.75))
	if broken:
		var rub := Props.instance(NodeVisuals.boulder_mesh(2, tint, 0.5), NodeVisuals.rock_material(0.028), 120.0)
		var rp: Vector3 = _v3(p, -0.2) + bs * Vector3(1.4, 0, 1.0)
		rub.position = rp
		rub.scale = Vector3.ONE * 0.6
		parent.add_child(rub)


## Moonpetals glow a little brighter at night (called by the area with the sky's daylight 0..1).
func set_daylight(daylight: float) -> void:
	if moonpetal_material != null:
		moonpetal_material.emission_energy_multiplier = lerpf(1.6, 0.25, daylight)


# --- The Old Oak -----------------------------------------------------------------------------------------------

func _build_old_oak() -> void:
	var p: Vector2 = Layout.LANDMARKS["old_oak"]["pos"]
	var root := Node3D.new()
	root.name = "OldOak"
	add_child(root)
	root.position = _v3(p, -0.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6060
	var tr := NodeVisuals.Merger.new()
	var th := 6.5
	var bark_fn := func(q: Vector3, _n: Vector3) -> Color:
		return Palette.BARK_DARK.lerp(Palette.BARK, clampf(q.y / th, 0.0, 1.0))
	tr.add(NodeVisuals._cyl(0.85, 1.35, th, 14, 4), Transform3D(Basis(), Vector3(0, th * 0.5, 0)), bark_fn)
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf() * 0.4
		var b := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, deg_to_rad(-68.0))
		tr.add(NodeVisuals._cyl(0.18, 0.55, 2.4, 8), Transform3D(b, Vector3(cos(a) * 1.3, 0.35, sin(a) * 1.3)), Palette.BARK_DARK)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.5
		var b := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, deg_to_rad(-52.0))
		var start := Vector3(0, th - 1.2 + float(i) * 0.35, 0)
		tr.add(NodeVisuals._cyl(0.2, 0.5, 4.2, 8), Transform3D(b, start + b * Vector3(0, 2.1, 0)), Palette.BARK)
	# The hollow
	tr.add(NodeVisuals._sph(0.45, 6, 10), Transform3D(Basis().scaled(Vector3(0.9, 1.4, 0.5)), Vector3(0, 1.4, 1.22)), Color("2a1c18"))
	var trunk := Props.instance(tr.commit(), NodeVisuals.bark_material())
	root.add_child(trunk)
	var cr := NodeVisuals.Merger.new()
	var cy := th + 2.6
	var lo := Palette.FOLIAGE_DARK
	var hi := Palette.FOLIAGE_LIGHT
	for i in 13:
		var a := TAU * float(i) / 9.0 + rng.randf() * 0.5
		var ring: float = 0.0 if i == 0 else (3.6 if i < 9 else 1.8)
		var lift: float = 0.0 if i < 9 else 2.2
		var yy: float = cy + lift + rng.randf_range(-0.6, 0.6)
		var rr: float = 3.4 if i == 0 else rng.randf_range(2.2, 2.9)
		var center := Vector3(cos(a) * ring, yy, sin(a) * ring)
		var autumn := i == 6 or i == 11
		var fn := func(q: Vector3, nn: Vector3) -> Color:
			var t := clampf((q.y - (cy - 3.0)) / 7.0, 0.0, 1.0)
			var c := lo.lerp(hi, t)
			if autumn:
				c = c.lerp(Palette.FOLIAGE_AUTUMN, 0.4)
			return c.lerp(Palette.MEADOW_GOLD, clampf(nn.y, 0.0, 1.0) * 0.1 * t)
		cr.add(NodeVisuals.ublob(i, 0.22, 0.86, 2), NodeVisuals.sxf(rr, center), fn)
	var crown := Props.instance(cr.commit(), NodeVisuals.foliage_material(0.05, 14.0, 0.045, 0.25))
	root.add_child(crown)
	# Rope swing hanging from the second big branch
	var sw := NodeVisuals.Merger.new()
	var ba := TAU / 4.0 + 0.5
	var bdir := Vector3(cos(ba), 0.0, sin(ba))
	var hang := 3.0
	var top_y := th - 1.2 + 0.35 + (hang / 0.79) * 0.62
	var rope_len := top_y - 0.9
	var side_dir := Vector3(-bdir.z, 0.0, bdir.x)
	for rx in [-0.35, 0.35]:
		sw.add(NodeVisuals._cyl(0.02, 0.02, rope_len, 4), Transform3D(Basis(), bdir * hang + side_dir * float(rx) + Vector3(0, 0.9 + rope_len * 0.5, 0)), Color("d9c9a0"))
	sw.add(NodeVisuals._box(Vector3(0.95, 0.07, 0.35)), Transform3D(Basis(Vector3.UP, -ba + PI * 0.5), bdir * hang + Vector3(0, 0.9, 0)), Palette.WOOD)
	var swing := Props.instance(sw.commit(), Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true}), 0.012), 100.0)
	root.add_child(swing)
	# Glowcaps at the roots (decor)
	for i in 3:
		var gv: Node3D = NodeVisuals.build("glowcap", i)
		var a := 0.6 + float(i) * 1.9
		gv.position = Vector3(cos(a) * 1.9, 0.05, sin(a) * 1.9)
		root.add_child(gv)
	_cyl_col(root.position, 1.35, 6.0)


# --- Mirror Pond --------------------------------------------------------------------------------------------------

func _build_pond() -> void:
	var c: Vector2 = terrain.pond_center
	var a := deg_to_rad(95.0)          # south shore
	var edge: float = terrain.pond_edge(a)
	var shore := c + Vector2(cos(a), sin(a)) * (edge + 1.6)
	var dir := (c - shore).normalized()
	var yaw := atan2(dir.x, dir.y)
	var level: float = terrain.pond_level
	var deck_y := level + 0.45
	var m := NodeVisuals.Merger.new()
	var length := 5.0
	for i in 12:
		var z := 0.2 + float(i) * (length / 12.0)
		m.add(NodeVisuals._box(Vector3(1.6, 0.08, 0.36)), Transform3D(Basis(), Vector3(0, deck_y, z)), Palette.WOOD if i % 3 != 0 else Palette.WOOD_LIGHT)
	for i in 3:
		for sx in [-0.72, 0.72]:
			var z := 0.6 + float(i) * 2.0
			m.add(NodeVisuals._cyl(0.08, 0.09, 1.6, 7), Transform3D(Basis(), Vector3(float(sx), deck_y - 0.6, z)), Palette.WOOD_DARK)
	var mi := Props.instance(m.commit(), Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.1}), 0.018), 140.0)
	mi.position = Vector3(shore.x, 0, shore.y)
	mi.rotation.y = yaw
	add_child(mi)
	var bs := Basis(Vector3.UP, yaw)
	var mid := Vector3(shore.x, deck_y - 0.12, shore.y) + bs * Vector3(0, 0, length * 0.5)
	_box_col(Transform3D(bs, mid), Vector3(1.6, 0.25, length + 0.4), "wood")
	var ramp_start := Vector3(shore.x, _y(shore), shore.y) - bs * Vector3(0, 0, 1.2)
	var ramp_end := Vector3(shore.x, deck_y, shore.y) + bs * Vector3(0, 0, 0.3)
	var rd := ramp_end - ramp_start
	var rb := bs * Basis(Vector3.RIGHT, -atan2(rd.y, Vector2(rd.x, rd.z).length()))
	_box_col(Transform3D(rb, (ramp_start + ramp_end) * 0.5 - rb.y * 0.1), Vector3(1.6, 0.2, rd.length()), "wood")


# --- Hollow Mine ----------------------------------------------------------------------------------------------------

func _build_mine() -> void:
	var f := SL.MINE_FACING.normalized()
	var p := SL.MINE_MOUTH + f * 0.4
	mine_entrance = MineEntrance.new()
	mine_entrance.terrain = terrain
	mine_entrance.position = Vector3(p.x, terrain.mine_floor, p.y)
	mine_entrance.rotation.y = atan2(f.x, f.y)
	add_child(mine_entrance)


# --- Enemy spawners --------------------------------------------------------------------------------------------------

func _build_spawners(script_path: String = SPAWNER_SCRIPT) -> void:
	var script: Script = load(script_path) if ResourceLoader.exists(script_path) else null
	if script == null or not script.can_instantiate():
		# Without the enemy module nothing could ever set "ruin_cleared" and the "lumi" quest step
		# would stall forever: treat the ruin as already cleared so progression never softlocks.
		push_warning("Landmarks: enemy spawner unavailable; marking the ruin as cleared")
		if not GameState.get_flag("ruin_cleared"):
			GameState.set_flag("ruin_cleared", true)
		return
	var defs: Array = [
		[Vector2(-10.0, -61.5), {"enemy": "brambling", "count": 3, "radius": 4.0, "respawn_minutes": -1, "spawner_id": "ruin_bramblings", "quest_flag_on_clear": "ruin_cleared"}],
		[Vector2(-62.0, -46.0), {"enemy": "brambling", "count": 3, "radius": 6.0, "respawn_minutes": 720, "spawner_id": "thicket_bramblings"}],
		[Vector2(77.0, 3.0), {"enemy": "brambling", "count": 2, "radius": 5.0, "respawn_minutes": 720, "spawner_id": "quarry_bramblings"}],
	]
	for d in defs:
		var pos: Vector2 = d[0]
		if pos.length() < Layout.HAVEN_RADIUS + 10.0:
			continue
		var sp: Node3D = script.new()
		if sp.has_method("setup"):
			sp.setup(d[1])
		sp.name = "Spawner_" + String(d[1]["spawner_id"])
		sp.position = _v3(pos, 0.1)
		add_child(sp)
		spawners.append(sp)
