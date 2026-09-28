extends Node3D
## Thimblebrook Pools (Hallowmere Reach district, module C2; MP §9 / §16): the quiet one. A little brook from a
## spring stone to the reeds, widening into three shallow, sparkling pools (ankle-deep: the water surface is a
## visual layer over the region's ground - no swimming and no drowning), reeds, lily pads, stepping stones with
## colliders across the brook, a weeping willow, moonpetals (hr_moonpetal_0..5) and a sugarcap bank
## (hr_sugarcap_0..4), all renewable through the shared resource_node.
## The chime trail (optional): exactly one reed chime at a time carries a glint (and, with high_visibility_cues,
## a bold ring). Walking up to it rings it (sparkle + caption, so it works with the sound muted) and passes the
## glint to the next one - no timing, no jumping, any pace. The last chime reveals a lost festival pouch under the
## willow; taking it grants Data.REWARD_CHIMES once (GameState.grant_once; the bundle comes from data/sources.gd
## when the integrator has added it, else Data.CHIME_REWARD_FALLBACK).
## The optional reed-creature encounter of MP §9 is intentionally NOT built (no cheap non-combat version that
## adds more than it costs; the pools stay a calm gathering stop).

const Data := preload("res://data/reach_west.gd")
const Art := preload("res://src/world/reach/west/west_art.gd")
const B := preload("res://src/world/reach/west/west_build.gd")
const WestInteractable := preload("res://src/world/reach/west/west_interactable.gd")
const Fx := preload("res://src/world/common/fx.gd")
const Mat := preload("res://src/art/mat.gd")
const NV := preload("res://src/world/common/node_visuals.gd")

const TICK := 0.2

var area: Node3D = null
var player_override: Node3D = null
var build_ms: int = 0
var nodes: Dictionary = {}
var chimes: Array = []               # [{"root": Node3D, "glint": MeshInstance3D, "ring": MeshInstance3D}]
var chime_index: int = 0             # the chime that currently glints (session progress)
var trail_state: String = "active"   # active | found (pouch showing) | done (pouch taken)
var pouch: Node3D = null
var interactables: Dictionary = {}
var solids: StaticBody3D = null

var _t: float = 0.0
var _bob: Tween


func setup(p_area: Node3D) -> void:
	area = p_area


func build() -> void:
	var t0 := Time.get_ticks_usec()
	name = "District_Pools"
	solids = B.solid_body(self, "PoolsSolids", "stone")
	var holder := Node3D.new()
	holder.name = "Harvest"
	add_child(holder)
	for e in Data.nodes_in(Data.POOLS):
		nodes[String(e["id"])] = B.harvest_node(holder, area, e)
	_build_water()
	_build_banks()
	_build_chimes()
	_restore_trail()
	build_ms = int((Time.get_ticks_usec() - t0) / 1000)


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	var pp: Variant = player_position()
	if pp is Vector3:
		check_chimes(pp)


func player_position() -> Variant:
	if player_override != null and is_instance_valid(player_override):
		return player_override.global_position
	var pl: Node3D = Game.player
	if pl != null and is_instance_valid(pl) and pl.is_inside_tree() and Game.area == area:
		return pl.global_position
	return null


# --- Water ------------------------------------------------------------------------------------------------

func _build_water() -> void:
	var brook := MeshInstance3D.new()
	brook.name = "Brook"
	brook.mesh = B.draped_strip(area, Data.BROOK, Data.BROOK_WIDTH, Data.WATER_LIFT, 0.8)
	brook.material_override = Art.flow_material()
	brook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(brook)
	var bank := MeshInstance3D.new()
	bank.name = "BrookBank"
	bank.mesh = B.draped_strip(area, Data.BROOK, Data.BROOK_WIDTH + 1.0, 0.02, 0.8)
	bank.material_override = Art.tinted(Color("b9a882"), 0.0, 0.1)
	bank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bank)
	var i := 0
	for pd in Data.POOL_DISCS:
		var c: Vector2 = pd[0]
		var r := float(pd[1])
		var rim := MeshInstance3D.new()
		rim.name = "PoolRim_%d" % i
		rim.mesh = B.draped_disc(area, c, r + 0.7, 0.025)
		rim.material_override = Art.tinted(Color("c9b78c"), 0.0, 0.1)
		rim.position = B.ground(area, c)
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rim)
		var w := MeshInstance3D.new()
		w.name = "Pool_%d" % i
		w.mesh = B.draped_disc(area, c, r, Data.WATER_LIFT + 0.01)
		w.material_override = Art.pool_material()
		w.position = B.ground(area, c)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
		i += 1
	# Stepping stones across the brook (solid: tops at STONE_TOP above the ground).
	var sx: Array = []
	var k := 0
	for sp in Data.STEPPING_STONES:
		var p: Vector2 = sp
		var g := B.ground(area, p)
		sx.append(Transform3D(Basis(Vector3.UP, float(k) * 1.3).scaled(Vector3(1.0, 0.5, 0.9)), g + Vector3(0, Data.STONE_TOP * 0.35, 0)))
		B.cylinder(solids, g - Vector3(0, 0.1, 0), 0.46, Data.STONE_TOP + 0.1)
		k += 1
	B.multi(self, Art.stepping_stone(0), Art.prop_material(), sx, "SteppingStones", 90.0)
	# Glints over the water (soft twinkle), lily pads in the pools.
	var rng := B.rng_for("pools_water")
	var gx: Array = []
	var lx: Array = []
	for pd2 in Data.POOL_DISCS:
		var c2: Vector2 = pd2[0]
		var r2 := float(pd2[1])
		for n in 7:
			var a := rng.randf() * TAU
			var rr := sqrt(rng.randf()) * r2 * 0.85
			var q := c2 + Vector2(cos(a), sin(a)) * rr
			gx.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), B.ground(area, q, Data.WATER_LIFT + rng.randf_range(0.12, 0.45))))
		for n2 in 4:
			var a2 := rng.randf() * TAU
			var q2 := c2 + Vector2(cos(a2), sin(a2)) * rng.randf_range(0.4, r2 * 0.8)
			lx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), B.ground(area, q2, Data.WATER_LIFT + 0.02)))
	for bp in Data.BROOK:
		var q3: Vector2 = bp
		gx.append(Transform3D(Basis(), B.ground(area, q3, Data.WATER_LIFT + rng.randf_range(0.1, 0.3))))
	B.multi(self, Art.glint(), Art.glint_material(), gx, "Glints", 70.0, false)
	B.multi(self, Art.lily_pad(0), Art.soft_material(), lx, "LilyPads", 60.0, false)


# --- Banks: reeds, willow, spring stone, log -----------------------------------------------------------------

func _build_banks() -> void:
	var prop := Art.prop_material()
	B.mesh_at(self, Art.spring_stone(), NV.rock_material(0.025), Transform3D(Basis(), B.ground(area, Data.SPRING_STONE, -0.1)), "SpringStone")
	B.cylinder(solids, B.ground(area, Data.SPRING_STONE, -0.2), 0.95, 1.2)
	B.mesh_at(self, Art.willow(), prop, Transform3D(Basis(Vector3.UP, 0.7), B.ground(area, Data.WILLOW)), "Willow", 160.0)
	B.cylinder(solids, B.ground(area, Data.WILLOW), 0.45, 2.6)
	B.mesh_at(self, Art.mossy_log(), NV.bark_material(), Transform3D(Basis(Vector3.UP, 0.2), B.ground(area, Data.MOSSY_LOG)), "MossyLog")
	B.box(solids, B.ground(area, Data.MOSSY_LOG, 0.3), Vector3(3.2, 0.6, 0.6), Basis(Vector3.UP, 0.2))
	var rng := B.rng_for("pools_reeds")
	var rx: Array = []
	var tries := 0
	while rx.size() < 64 and tries < 600:
		tries += 1
		var p := Vector2.ZERO
		if rng.randf() < 0.5:
			var i := rng.randi() % (Data.BROOK.size() - 1)
			var a: Vector2 = Data.BROOK[i]
			var b: Vector2 = Data.BROOK[i + 1]
			var t := rng.randf()
			var dir := (b - a).normalized()
			var side := Vector2(-dir.y, dir.x) * (Data.BROOK_WIDTH * 0.5 + rng.randf_range(0.2, 1.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			p = a.lerp(b, t) + side
		else:
			var pd: Array = Data.POOL_DISCS[rng.randi() % Data.POOL_DISCS.size()]
			var ang := rng.randf() * TAU
			p = (pd[0] as Vector2) + Vector2(cos(ang), sin(ang)) * (float(pd[1]) + rng.randf_range(-0.3, 0.8))
		if not reed_ok(p):
			continue
		rx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), B.ground(area, p)))
	B.multi(self, Art.reed_clump(0), Art.sway_material(0.07, 1.4), rx, "Reeds", 80.0, false)


## Reeds never grow on the stepping stones, chimes, harvest nodes, the pouch, the willow or the way in.
func reed_ok(p: Vector2) -> bool:
	if p.distance_to(Data.center_of(Data.POOLS)) > Data.radius_of(Data.POOLS) - 0.5:
		return false
	for s in Data.STEPPING_STONES:
		if p.distance_to(s) < 1.4:
			return false
	for c in Data.CHIMES:
		if p.distance_to(c) < 1.8:
			return false
	for e in Data.nodes_in(Data.POOLS):
		if p.distance_to(e["pos"]) < 1.3:
			return false
	for e2 in Data.POOLS_ENTRIES:
		if p.distance_to(e2) < 2.5:
			return false
	if p.distance_to(Data.POUCH) < 2.2 or p.distance_to(Data.WILLOW) < 2.0 or p.distance_to(Data.SPRING_STONE) < 1.6:
		return false
	return p.distance_to(Data.MOSSY_LOG) >= 2.2


# --- The chime trail -------------------------------------------------------------------------------------------

func _build_chimes() -> void:
	var prop := Art.prop_material()
	var i := 0
	for cp in Data.CHIMES:
		var p: Vector2 = cp
		var root := Node3D.new()
		root.name = "Chime_%d" % i
		root.position = B.ground(area, p)
		root.rotation.y = float(i) * 1.1
		add_child(root)
		var post := MeshInstance3D.new()
		post.mesh = Art.chime_post()
		post.material_override = prop
		root.add_child(post)
		var rib := MeshInstance3D.new()
		rib.mesh = Art.ribbon_strip(0.45)
		rib.material_override = Art.ribbon_material(Art.RIBBON_CREAM if i % 2 == 0 else Art.RIBBON_GOLD)
		rib.position = Vector3(0, 1.2, 0.04)
		rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rib)
		var gl := MeshInstance3D.new()
		gl.name = "Glint"
		gl.mesh = Art.glint()
		gl.material_override = Mat.glow(Color("fff4c8"), 3.0)
		gl.position = Vector3(0.22, 1.95, 0)
		gl.scale = Vector3.ONE * 2.6
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gl)
		var ring := MeshInstance3D.new()
		ring.name = "CueRing"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9
		tm.outer_radius = 1.04
		tm.rings = 24
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = Mat.glow(Color("fff1b8"), 1.6)
		ring.position = Vector3(0, 0.06, 0)
		ring.scale = Vector3(1, 0.35, 1)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		B.cylinder(solids, root.position, 0.07, 1.7)
		chimes.append({"root": root, "glint": gl, "ring": ring})
		i += 1
	pouch = Node3D.new()
	pouch.name = "LostPouch"
	pouch.position = B.ground(area, Data.POUCH)
	add_child(pouch)
	var pm := MeshInstance3D.new()
	pm.mesh = Art.pouch()
	pm.material_override = prop
	pouch.add_child(pm)
	var it: Node3D = WestInteractable.new()
	it.setup({"id": "chime_pouch", "text": "Open the lost festival pouch", "size": Vector3(1.2, 1.2, 1.2), "offset": Vector3(0, 0.5, 0),
		"handler": Callable(self, "take_pouch"), "marker": true, "marker_radius": 0.6})
	pouch.add_child(it)
	interactables["chime_pouch"] = it
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func _restore_trail() -> void:
	if GameState.has_reward(Data.REWARD_CHIMES) or _flag(Data.FLAG_CHIMES_DONE):
		trail_state = "done"
	elif _flag(Data.FLAG_CHIMES_FOUND):
		trail_state = "found"
	else:
		trail_state = "active"
		chime_index = 0
	_apply_trail()


func _apply_trail() -> void:
	set_process(trail_state == "active")      # the only per-frame work here is the chime proximity check
	var cues := bool(Settings.get_value("high_visibility_cues"))
	for i in chimes.size():
		var c: Dictionary = chimes[i]
		var on := trail_state == "active" and i == chime_index
		(c["glint"] as Node3D).visible = on
		(c["ring"] as Node3D).visible = on and cues
	if pouch != null:
		pouch.visible = trail_state == "found"
		(interactables["chime_pouch"] as Node3D).set_active(trail_state == "found")
	if _bob != null and _bob.is_valid():
		_bob.kill()
	_bob = null
	if trail_state == "active" and chime_index < chimes.size() and is_inside_tree():
		var g: Node3D = chimes[chime_index]["glint"]
		g.position.y = 1.95
		_bob = create_tween().set_loops()
		_bob.tween_property(g, "position:y", 2.2, 0.9).set_trans(Tween.TRANS_SINE)
		_bob.tween_property(g, "position:y", 1.95, 0.9).set_trans(Tween.TRANS_SINE)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_apply_trail()


## Rings the glinting chime when she is close enough and passes the glint on. Returns the index that rang (-1).
func check_chimes(player_pos: Vector3) -> int:
	if trail_state != "active" or chime_index >= chimes.size():
		return -1
	var root: Node3D = chimes[chime_index]["root"]
	var d := Vector2(player_pos.x - root.position.x, player_pos.z - root.position.z).length()
	if d > Data.CHIME_REACH:
		return -1
	var rang := chime_index
	if is_inside_tree():
		Fx.burst(self, root.position + Vector3(0.2, 1.8, 0), "sparkle", 0.9)
		Audio.play_3d("ui_notify", root.position + Vector3.UP * 1.6, -8.0)
	chime_index += 1
	if chime_index >= chimes.size():
		trail_state = "found"
		GameState.set_flag(Data.FLAG_CHIMES_FOUND, true)
		Events.caption.emit("[The last chime rings, and something glints under the willow]")
		if is_inside_tree():
			Fx.burst(self, pouch.position + Vector3.UP * 0.5, "sparkle", 1.4)
	else:
		Events.caption.emit("[A tiny chime rings, and the next one glints]")
	_apply_trail()
	return rang


## Takes the lost festival pouch (once per save through the reward ledger). True when it paid now.
func take_pouch(_player: Node = null) -> bool:
	if trail_state != "found":
		return false
	var bundle: Dictionary = ItemDB.reward_bundle(Data.REWARD_CHIMES)
	if bundle.is_empty():
		bundle = Data.CHIME_REWARD_FALLBACK
	var ok := GameState.grant_once(Data.REWARD_CHIMES, bundle.get("items", {}), bundle.get("flags", []),
		"A lost festival pouch: moonpetals, sugarcaps and festival candy.")
	GameState.set_flag(Data.FLAG_CHIMES_DONE, true)
	trail_state = "done"
	if is_inside_tree():
		Audio.play_3d("pickup", pouch.position, -2.0)
	_apply_trail()
	return ok


func _flag(f: String) -> bool:
	var v: Variant = GameState.get_flag(f)
	return v is bool and v
