extends Node3D
## The Candleyard (Hallowmere Reach district, module C2; MP §9 / §15 / §17): whimsical leaning memory stones with
## carved moons and stars (never graves, never gore), moonflowers, candles, an old Candle Tree, the
## groundskeepers' shed and tools inside a low broken lilac wall with five wide gates - very readable violet
## night light (emissive moonflowers + three unshadowed violet lamps that brighten at night) warmed by real candle
## light: amber teardrop flames with soft halos, candle-lit lantern globes on the gates and the Candle Tree, and
## warm light pools at night inside the light budget: one unshadowed omni over the Candle Tree ring and one at
## each lit gate (Data.CANDLE_LIGHTS, GATE_LIGHT_*), and warm glow decals under the other candle clusters
## (Data.CANDLE_POOLS: emission-only Decals, not lights). Nothing here casts shadows.
##   * Small optional loops: Hollow Drudges (hr_sp_candleyard_drudges) and Patchwalkers
##     (hr_sp_candleyard_patchwalkers) patrol stone clusters in the north half; spawners are guarded when the
##     enemy scripts are missing. The activities sit in the calmer south half.
##   * "A Candle for the Groundskeeper": two notes (lore_ch2_groundskeeper_1 / _2 -> flags
##     ch2_groundskeeper_note_1 / _2); once both are read she lights a candle at the fixed empty dish by the west
##     wall (from her own lantern, nothing consumed) -> ch2_groundskeeper_light_placed, and a calm moonflower nook
##     blooms behind it. The optional log pays the Ghost Lantern (rw_opt_groundskeeper).
##   * The hidden dress pattern: a pale ribbon peeks from under a loose stone behind the shed -> grants the
##     content bundle rw_ch2_candleyard_pattern (GameState.grant_once; flag ch2_candleyard_pattern).
##   * "A Hat Too Large": fluttering ribbons from the south-east gate lead to the Candle Tree, where a big witch
##     hat is caught on a low branch at arm's height (no jumping) -> ch2_witch_hat_found; the optional log pays
##     the Ribbon Witch hat pattern.
##   * A calm bench outside the east gate (a short rest: a little health back, a quiet line).
##   * Renewable moonpetals hr_moonpetal_6..8, roseberries hr_roseberry_6..8 and two marked sap stumps hr_resin_2/3
##     (outside the south gate) on its edges.
## Nothing here is spider-like (arachnophobia: not applicable).

const Data := preload("res://data/reach_west.gd")
const Art := preload("res://src/world/reach/west/west_art.gd")
const B := preload("res://src/world/reach/west/west_build.gd")
const WestInteractable := preload("res://src/world/reach/west/west_interactable.gd")
const Props := preload("res://src/world/surface/props.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Mat := preload("res://src/art/mat.gd")
const Fx := preload("res://src/world/common/fx.gd")
const LoreDB := preload("res://src/core/lore_db.gd")

const LIGHT_TICK := 1.0
const DAY_LIGHT_MULT := 0.45
const BENCH_HEAL := 15.0
const BENCH_COOLDOWN_MS := 20000
const FLAME_COLOR := Color("ffc46b")
const GLASS_WARM := Color("ffca7a")
const HALO_CANDLE := 0.34            # halo card size around a candle flame (m)
const HALO_LANTERN := 0.85           # ... around a lantern globe
const GATE_LIGHT_RANGE := 5.5
const GATE_LIGHT_ENERGY := 1.3
const POOL_ENERGY := 0.55            # glow decal emission at full night (x the pool's strength)
const POOL_HEIGHT := 2.4             # decal box height (projects onto the ground, grass and stone feet)

var area: Node3D = null
var build_ms: int = 0
var nodes: Dictionary = {}
var spawners: Dictionary = {}
var interactables: Dictionary = {}
var lights: Array = []                # [OmniLight3D, night energy] (the violet lamps)
var candle_lights: Array = []         # [OmniLight3D, night energy] (warm: the Candle Tree ring + lit gates; off by day)
var candle_pools: Array = []          # [Decal, night strength] (warm glow on the ground at candle clusters; off by day)
var solids: StaticBody3D = null
var gate_openings: Array = []         # [Vector2 centre, float width] of the wall gates (tests)
var instant: bool = false             # tests: skip the bloom / hat tweens

var _marker_candle: Node3D
var _nook_flowers: Node3D
var _nook_light: OmniLight3D
var _marker_pool: Decal
var _hat: Node3D
var _pattern_ribbon: Node3D
var _pattern_stone: Node3D
var _bench_ms: int = -100000
var _t: float = 0.0


func setup(p_area: Node3D) -> void:
	area = p_area


func build() -> void:
	var t0 := Time.get_ticks_usec()
	name = "District_Candleyard"
	solids = B.solid_body(self, "CandleyardSolids", "stone")
	var holder := Node3D.new()
	holder.name = "Harvest"
	add_child(holder)
	for e in Data.nodes_in(Data.CANDLEYARD):
		nodes[String(e["id"])] = B.harvest_node(holder, area, e)
	B.sap_stump_decor(self, solids, area, Data.CANDLEYARD)
	_build_wall()
	_build_paths()
	_build_tree()
	_build_stones()
	_build_flowers_and_candles()
	_build_lights()
	_build_shed()
	_build_groundskeeper()
	_build_hat()
	_build_bench()
	for id in Data.spawners_in(Data.CANDLEYARD):
		spawners[id] = B.spawner(self, area, String(id))
	_apply_state()
	update_lights()
	build_ms = int((Time.get_ticks_usec() - t0) / 1000)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIGHT_TICK:
		_t = 0.0
		update_lights()


## Violet lamps: full strength at night, softer by day (always readable, never dark). The warm candle pools fade
## in with the dark (the sky's night amount, or the clock's night) and are switched off by day.
func update_lights() -> void:
	var night_clock := GameState.is_night()
	var mult := 1.0 if night_clock else DAY_LIGHT_MULT
	for l in lights:
		(l[0] as OmniLight3D).light_energy = float(l[1]) * mult
	var warm := maxf(Art.night_amount(), 1.0 if night_clock else 0.0)
	for c in candle_lights:
		var o := c[0] as OmniLight3D
		o.light_energy = float(c[1]) * warm
		o.visible = warm > 0.02
	for pl in candle_pools:
		var d := pl[0] as Decal
		d.emission_energy = POOL_ENERGY * float(pl[1]) * warm
		d.visible = warm > 0.02
	if _marker_pool != null:
		_marker_pool.emission_energy = POOL_ENERGY * float(Data.MARKER_POOL[1]) * warm
		_marker_pool.visible = warm > 0.02 and is_light_placed()


# --- Wall, paths, tree, stones ----------------------------------------------------------------------------------

func _build_wall() -> void:
	var c := Data.CANDLEYARD_CENTER
	var r := Data.WALL_RADIUS
	var n := int(round(TAU * r / 1.6))
	var by_variant: Dictionary = {}
	for i in n:
		var ang := 360.0 * float(i) / float(n)
		if Data.in_wall_gate(wrapf(ang, -180.0, 180.0)):
			continue
		if posmod(hash("wall|%d" % i), 9) == 0:
			continue           # a fallen block (the wall is old and broken, not a fence)
		var a := deg_to_rad(ang)
		var p := c + Vector2(cos(a), sin(a)) * r
		var yaw := -atan2(cos(a), -sin(a))
		var v := i % 3
		if not by_variant.has(v):
			by_variant[v] = []
		var h := Data.WALL_HEIGHT * (0.8 + 0.2 * float(posmod(hash("wh|%d" % i), 3)) / 2.0)
		(by_variant[v] as Array).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, h / Data.WALL_HEIGHT, 1.0)), B.ground(area, p, -0.05)))
		B.box(solids, B.ground(area, p, h * 0.5 - 0.05), Vector3(1.55, h, 0.5), Basis(Vector3.UP, yaw))
	for v in by_variant:
		B.multi(self, Props.stone_block(int(v), Vector3(1.6, Data.WALL_HEIGHT, 0.5), Art.LILAC_STONE, 0.4), NV.rock_material(0.025), by_variant[v], "Wall_%d" % int(v), 110.0)
	for g in Data.WALL_GATES:
		gate_openings.append([Data.gate_point(float(g)), 2.0 * r * sin(deg_to_rad(Data.WALL_GATE_HALF_DEG))])
	# Iron lantern posts beside the south and south-east gates (they frame the way in, never block it).
	var prop := Art.prop_material()
	var glass: Array = []
	var posts: Array = []
	for g2 in [90.0, 51.0]:
		var gp := Data.gate_point(g2)
		var inward := (c - gp).normalized()
		var side := Vector2(-inward.y, inward.x)
		for s in [-1.0, 1.0]:
			var lp := gp + inward * 0.8 + side * float(s) * 3.4
			posts.append(Transform3D(Basis(), B.ground(area, lp)))
			glass.append(Transform3D(Basis(), B.ground(area, lp, 1.97)))
			B.cylinder(solids, B.ground(area, lp), 0.09, 1.9)
	B.multi(self, Art.iron_lantern_post(), prop, posts, "GateLanternPosts", 110.0)
	B.multi(self, Art.lantern_globe(), Art.glow(GLASS_WARM, 2.2), glass, "GateLanternGlass", 140.0, false)
	_halos(glass, HALO_LANTERN, "GateLanternHalos")
	for g3 in [90.0, 51.0]:
		var gp3 := Data.gate_point(g3)
		_add_warm_light(B.ground(area, gp3 + (c - gp3).normalized() * 0.8, 1.9), GATE_LIGHT_RANGE, GATE_LIGHT_ENERGY, "GateLight")


func _build_paths() -> void:
	var t := Data.CANDLE_TREE
	for pts in [[Data.gate_point(90.0), t + Vector2(0, 3.0)], [Data.gate_point(51.0)] + Data.HAT_RIBBONS + [t + Vector2(1.8, 1.8)],
			[Data.gate_point(-8.0), t + Vector2(3.0, -0.2)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = B.draped_strip(area, pts, 1.6, 0.03, 1.0)
		mi.material_override = Art.tinted(Color("b3a7c4"), 0.0, 0.1)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "GravelPath"
		add_child(mi)


func _build_tree() -> void:
	var t := Data.CANDLE_TREE
	B.mesh_at(self, Art.candle_tree(), NV.bark_material(), Transform3D(Basis(), B.ground(area, t, -0.1)), "CandleTree", 180.0)
	B.cylinder(solids, B.ground(area, t, -0.2), 0.8, 3.2)
	var cages: Array = []
	var glass: Array = []
	for off in [Vector3(1.6, 2.35, 1.2), Vector3(-1.7, 3.05, -0.4), Vector3(0.5, 3.6, -1.6), Vector3(-0.8, 3.9, 1.5)]:
		var p: Vector3 = B.ground(area, t) + (off as Vector3)
		cages.append(Transform3D(Basis(), p))
		glass.append(Transform3D(Basis(), p + Vector3(0, -0.19, 0)))
	B.multi(self, Art.hanging_lantern(), Art.prop_material(), cages, "TreeLanterns", 120.0)
	var globes: Array = []
	for g in glass:
		globes.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.8), (g as Transform3D).origin))
	B.multi(self, Art.lantern_globe(), Art.glow(GLASS_WARM, 2.4), globes, "TreeLanternGlass", 140.0, false)
	_halos(glass, HALO_LANTERN * 0.8, "TreeLanternHalos")


func _build_stones() -> void:
	var by_variant: Dictionary = {}
	var carvings: Dictionary = {}
	var i := 0
	for st in Data.LEANING_STONES:
		var p: Vector2 = st[0]
		var tilt := float(st[1])
		var yaw := atan2(Data.CANDLE_TREE.x - p.x, Data.CANDLE_TREE.y - p.y)   # carved face (+Z) toward the tree
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(-absf(tilt) * 0.5)) * Basis(Vector3.BACK, deg_to_rad(tilt))
		var xf := Transform3D(basis, B.ground(area, p, -0.08))
		var v := i % 3
		if not by_variant.has(v):
			by_variant[v] = []
		(by_variant[v] as Array).append(xf)
		var cv := i % 2
		if not carvings.has(cv):
			carvings[cv] = []
		(carvings[cv] as Array).append(xf)
		B.box(solids, xf * Vector3(0, 0.6, 0), Vector3(0.8, 1.2, 0.3), basis)
		i += 1
	for v in by_variant:
		B.multi(self, Art.leaning_stone(int(v)), Art.prop_material(), by_variant[v], "LeaningStones_%d" % int(v), 120.0)
	for cv in carvings:
		B.multi(self, Art.stone_carving(int(cv)), Art.glow(Color("d9c8ff"), 0.9), carvings[cv], "StoneCarvings_%d" % int(cv), 90.0, false)


func _build_flowers_and_candles() -> void:
	var rng := B.rng_for("candleyard_flowers")
	var leaves: Array = []
	var petals: Array = []
	var tries := 0
	while leaves.size() < 56 and tries < 700:
		tries += 1
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.5, Data.WALL_RADIUS - 1.2)
		var p := Data.CANDLEYARD_CENTER + Vector2(cos(a), sin(a)) * r
		if not decor_ok(p, 1.0):
			continue
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.3)), B.ground(area, p))
		leaves.append(xf)
		petals.append(xf)
	B.multi(self, Art.moonflower_leaves(0), Art.soft_material(), leaves, "Moonflowers", 70.0, false)
	B.multi(self, Art.moonflower_petals(0), Art.tinted(Art.MOONFLOWER, 0.55, 0.5), petals, "MoonflowerPetals", 80.0, false)
	# Candles: a few at the foot of every leaning stone and a ring around the Candle Tree.
	var bodies: Array = []
	var flames: Array = []
	var k := 0
	for st in Data.LEANING_STONES:
		var p: Vector2 = st[0]
		var to_tree := (Data.CANDLE_TREE - p).normalized()
		for j in 1 + k % 2:
			var q := p + to_tree * 0.45 + Vector2(-to_tree.y, to_tree.x) * (0.25 * float(j * 2 - 1) if k % 2 == 1 else 0.0)
			var hsc := 0.8 + 0.3 * float(posmod(hash("c|%d|%d" % [k, j]), 3))
			bodies.append(Transform3D(Basis.from_scale(Vector3(1, hsc, 1)), B.ground(area, q)))
			flames.append(Transform3D(Basis(), B.ground(area, q, 0.14 * hsc + 0.004)))
		k += 1
	for i in 10:
		var a2 := TAU * float(i) / 10.0 + 0.2
		var q2 := Data.CANDLE_TREE + Vector2(cos(a2), sin(a2)) * 1.35
		if q2.distance_to(Data.HAT["stand"]) < 1.0:
			continue
		bodies.append(Transform3D(Basis(), B.ground(area, q2)))
		flames.append(Transform3D(Basis(), B.ground(area, q2, 0.144)))
	B.multi(self, Art.candle(0), Art.soft_material(), bodies, "Candles", 60.0, false)
	B.multi(self, Art.flame(), Art.glow(FLAME_COLOR, 3.2), flames, "CandleFlames", 90.0, false)
	var halo_at: Array = []
	for f in flames:
		halo_at.append(Transform3D(Basis(), (f as Transform3D).origin + Vector3(0, 0.045, 0)))
	_halos(halo_at, HALO_CANDLE, "CandleHalos")


## Soft additive glow cards (billboards) around flames / lantern globes: faint by day, full at night.
func _halos(at: Array, size: float, node_name: String) -> void:
	var xs: Array = []
	for t in at:
		xs.append(Transform3D(Basis.from_scale(Vector3.ONE * size), (t as Transform3D).origin))
	B.multi(self, Art.halo_mesh(), Art.halo_material(), xs, node_name, 80.0, false)


func _add_warm_light(pos: Vector3, reach: float, energy: float, node_name: String) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.name = node_name
	o.light_color = Data.CANDLE_WARM
	o.omni_range = reach
	o.omni_attenuation = 1.4
	o.shadow_enabled = false
	o.light_specular = 0.2
	o.distance_fade_enabled = true
	o.distance_fade_begin = 55.0
	o.distance_fade_length = 15.0
	o.position = pos
	add_child(o)
	candle_lights.append([o, energy])
	return o


## Decor never lands on a route, an activity, a node, a stone or a gate.
func decor_ok(p: Vector2, clearance: float) -> bool:
	var keep: Array = [[Data.CANDLE_TREE, 1.8], [Data.SHED["pos"], 2.4], [Data.SHED["note"], 1.2], [Data.SHED["tools"], 1.0],
		[Data.SHED["barrow"], 1.2], [Data.PATTERN_SPOT, 1.0], [Data.NOTE_2, 1.2], [Data.MARKER, 1.2], [Data.NOOK, 1.0],
		[Data.HAT["stand"], 1.2], [Data.HAT["pos"], 1.0]]
	for st in Data.LEANING_STONES:
		keep.append([st[0], 0.9])
	for e in Data.nodes_in(Data.CANDLEYARD):
		keep.append([e["pos"], 1.2])
	for id in Data.spawners_in(Data.CANDLEYARD):
		keep.append([Data.SPAWNERS[id]["pos"], 1.0])
	for k in keep:
		if p.distance_to(k[0]) < float(k[1]) + clearance * 0.5:
			return false
	var pts: Array = [Data.gate_point(51.0)] + Data.HAT_RIBBONS + [Data.HAT["stand"]]
	for i in range(pts.size() - 1):
		if _dist_to_segment(p, pts[i], pts[i + 1]) < 1.3:
			return false
	if _dist_to_segment(p, Data.gate_point(90.0), Data.CANDLE_TREE) < 1.3:
		return false
	return _dist_to_segment(p, Data.gate_point(-8.0), Data.CANDLE_TREE) >= 1.3


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _build_lights() -> void:
	for l in Data.VIOLET_LIGHTS:
		var o := OmniLight3D.new()
		var p: Vector2 = l[0]
		o.name = "VioletLight"
		o.light_color = Art.VIOLET
		o.omni_range = float(l[2])
		o.shadow_enabled = false
		o.distance_fade_enabled = true
		o.distance_fade_begin = 70.0
		o.distance_fade_length = 20.0
		o.position = B.ground(area, p, float(l[1]))
		add_child(o)
		lights.append([o, float(l[3])])
	for w in Data.CANDLE_LIGHTS:
		_add_warm_light(B.ground(area, w[0], float(w[1])), float(w[2]), float(w[3]), "CandleLight")
	for pw in Data.CANDLE_POOLS:
		candle_pools.append([_glow_pool(pw[0], float(pw[1])), float(pw[2])])


## A warm glow decal (emission only: not a light) projected down onto the ground, grass and stone feet at p.
func _glow_pool(p: Vector2, radius: float) -> Decal:
	var d := Decal.new()
	d.name = "CandlePool"
	d.size = Vector3(radius * 2.0, POOL_HEIGHT, radius * 2.0)
	d.texture_emission = Art.pool_texture()
	d.modulate = Data.CANDLE_WARM
	d.emission_energy = 0.0
	d.upper_fade = 0.5
	d.lower_fade = 0.5
	d.distance_fade_enabled = true
	d.distance_fade_begin = 55.0
	d.distance_fade_length = 15.0
	d.position = B.ground(area, p, POOL_HEIGHT * 0.3)
	add_child(d)
	return d


# --- Shed, notes, marker, nook, pattern ------------------------------------------------------------------

func _build_shed() -> void:
	var prop := Art.prop_material()
	var sp: Vector2 = Data.SHED["pos"]
	var size: Vector2 = Data.SHED["size"]
	B.mesh_at(self, Art.shed(size), prop, Transform3D(Basis(), B.ground(area, sp, -0.05)), "GroundskeepersShed", 150.0)
	B.box(solids, B.ground(area, sp, 1.05), Vector3(size.x, 2.2, size.y))
	B.mesh_at(self, Art.garden_tools(), prop, Transform3D(Basis(), B.ground(area, Data.SHED["tools"])), "Tools")
	B.box(solids, B.ground(area, Data.SHED["tools"], 0.4), Vector3(1.0, 0.8, 0.4))
	B.mesh_at(self, Art.wheelbarrow(), prop, Transform3D(Basis(Vector3.UP, 0.6), B.ground(area, Data.SHED["barrow"])), "Wheelbarrow")
	B.box(solids, B.ground(area, Data.SHED["barrow"], 0.35), Vector3(1.2, 0.7, 0.6), Basis(Vector3.UP, 0.6))
	var np: Vector2 = Data.SHED["note"]
	B.mesh_at(self, Art.note_post(), prop, Transform3D(Basis(Vector3.UP, B.yaw_to(np, Data.CANDLE_TREE) + PI), B.ground(area, np)), "NoteBoard")
	B.cylinder(solids, B.ground(area, np), 0.07, 1.1)
	_note_interactable("groundskeeper_note_1", np, Data.LORE_GROUNDSKEEPER_1, Data.FLAG_NOTE_1, "Read the groundskeeper's note")
	# The hidden dress pattern: behind the shed, under a loose stone; a pale ribbon peeks out (the clue).
	var pp: Vector2 = Data.PATTERN_SPOT
	_pattern_stone = Node3D.new()
	_pattern_stone.name = "LooseStone"
	_pattern_stone.position = B.ground(area, pp)
	add_child(_pattern_stone)
	var stm := MeshInstance3D.new()
	stm.mesh = Art.seat_stone()
	stm.material_override = prop
	stm.scale = Vector3(0.55, 0.5, 0.55)
	_pattern_stone.add_child(stm)
	_pattern_ribbon = Node3D.new()
	_pattern_ribbon.name = "PaleRibbon"
	_pattern_ribbon.position = B.ground(area, pp + Vector2(-0.25, 0.1), 0.12)
	_pattern_ribbon.rotation_degrees = Vector3(0, 30, 70)
	add_child(_pattern_ribbon)
	var rm := MeshInstance3D.new()
	rm.mesh = Art.ribbon_strip(0.5)
	rm.material_override = Mat.toon(Color("eef0ff"), {"emission": Color("dfe6ff"), "emission_energy": 0.6, "wind": 0.08, "wind_height": 0.4, "rim": 0.5})
	_pattern_ribbon.add_child(rm)
	var it: Node3D = WestInteractable.new()
	it.setup({"id": "hidden_pattern", "text": "Lift the loose stone", "size": Vector3(1.0, 1.0, 1.0), "offset": Vector3(0, 0.4, 0),
		"handler": Callable(self, "take_pattern"), "marker": true, "marker_radius": 0.55})
	it.position = B.ground(area, pp)
	add_child(it)
	interactables["hidden_pattern"] = it


func _note_interactable(id: String, p: Vector2, lore_id: String, flag: String, text: String) -> void:
	var it: Node3D = WestInteractable.new()
	it.setup({"id": id, "size": Vector3(1.2, 1.5, 1.2), "offset": Vector3(0, 0.8, 0),
		"text_func": Callable(self, "_note_text").bind(text, flag), "handler": Callable(self, "read_note").bind(lore_id, flag),
		"marker": true, "marker_radius": 0.6})
	it.position = B.ground(area, p)
	add_child(it)
	interactables[id] = it


func _note_text(text: String, flag: String) -> Dictionary:
	if _flag(flag):
		return {"text": text + " again", "enabled": true}
	return {"text": text, "enabled": true}


## Reads a groundskeeper note (lore + its optional-goal flag). Re-reading is harmless.
func read_note(_player: Node = null, lore_id: String = "", flag: String = "") -> void:
	var l := lore_text(lore_id)
	GameState.discover_lore(lore_id)
	GameState.set_flag(flag, true)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l["title"]), String(l["text"]), 9.0)
	_apply_state()


static func lore_text(id: String) -> Dictionary:
	var l: Dictionary = LoreDB.get_lore(id)
	if String(l.get("text", "")) == "":
		return Data.LORE_FALLBACK.get(id, {"title": "", "text": ""})
	return l


func _build_groundskeeper() -> void:
	var prop := Art.prop_material()
	# Note 2: a little tin box at the foot of a leaning stone by the west wall.
	var n2: Vector2 = Data.NOTE_2
	B.mesh_at(self, Art.tin_box(), Art.prop_material(), Transform3D(Basis(Vector3.UP, 0.4), B.ground(area, n2, -0.01)), "TinBox")
	_note_interactable("groundskeeper_note_2", n2, Data.LORE_GROUNDSKEEPER_2, Data.FLAG_NOTE_2, "Read the note in the tin box")
	# The fixed empty marker: a stone plinth with an empty candle dish.
	var mp: Vector2 = Data.MARKER
	B.mesh_at(self, Art.marker_plinth(), prop, Transform3D(Basis(), B.ground(area, mp)), "EmptyMarker")
	B.cylinder(solids, B.ground(area, mp), 0.36, Art.MARKER_DISH_Y + 0.12)
	_marker_pool = _glow_pool(mp, float(Data.MARKER_POOL[0]))
	_marker_pool.name = "MarkerCandlePool"
	_marker_candle = Node3D.new()
	_marker_candle.name = "MarkerCandle"
	_marker_candle.position = B.ground(area, mp, Art.MARKER_DISH_Y + 0.012)
	add_child(_marker_candle)
	var cm := MeshInstance3D.new()
	cm.mesh = Art.candle(2)
	cm.material_override = Art.soft_material()
	cm.scale = Vector3.ONE * 1.4
	_marker_candle.add_child(cm)
	var fl := MeshInstance3D.new()
	fl.mesh = Art.flame()
	fl.material_override = Art.glow(FLAME_COLOR, 3.4)
	fl.position = Vector3(0, 0.26 * 1.4 + 0.005, 0)
	fl.scale = Vector3.ONE * 1.4
	_marker_candle.add_child(fl)
	var halo := MeshInstance3D.new()
	halo.mesh = Art.halo_mesh()
	halo.material_override = Art.halo_material()
	halo.position = fl.position + Vector3(0, 0.07, 0)
	halo.scale = Vector3.ONE * 0.55
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_candle.add_child(halo)
	var it: Node3D = WestInteractable.new()
	it.setup({"id": "groundskeeper_marker", "size": Vector3(1.4, 1.6, 1.4), "offset": Vector3(0, 0.8, 0),
		"text_func": Callable(self, "_marker_text"), "handler": Callable(self, "_on_marker"), "marker": true, "marker_radius": 0.8})
	it.position = B.ground(area, mp)
	add_child(it)
	interactables["groundskeeper_marker"] = it
	# The calm moonflower nook (closed buds until the light is placed).
	var nk: Vector2 = Data.NOOK
	B.mesh_at(self, Art.seat_stone(), prop, Transform3D(Basis(Vector3.UP, 0.5), B.ground(area, nk + Vector2(-0.6, 0.3))), "NookSeat")
	B.box(solids, B.ground(area, nk + Vector2(-0.6, 0.3), 0.22), Vector3(1.3, 0.44, 0.8), Basis(Vector3.UP, 0.5))
	_nook_flowers = Node3D.new()
	_nook_flowers.name = "NookFlowers"
	_nook_flowers.position = B.ground(area, nk)
	add_child(_nook_flowers)
	var rng := B.rng_for("nook")
	var lx: Array = []
	for i in 12:
		var a := TAU * float(i) / 12.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.7, 1.5)
		var p := nk + Vector2(cos(a), sin(a)) * r
		lx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), B.ground(area, p) - _nook_flowers.position))
	var leaves := Props.multimesh(Art.moonflower_leaves(1), Art.soft_material(), lx, "NookLeaves", 60.0, false)
	_nook_flowers.add_child(leaves)
	var petals := Props.multimesh(Art.moonflower_petals(1), Art.tinted(Art.MOONFLOWER, 0.9, 0.6), lx, "NookPetals", 70.0, false)
	petals.name = "NookPetals"
	_nook_flowers.add_child(petals)
	_nook_light = OmniLight3D.new()
	_nook_light.name = "NookLight"
	_nook_light.light_color = Color("e6dcff")
	_nook_light.light_energy = 0.8
	_nook_light.omni_range = 5.0
	_nook_light.shadow_enabled = false
	_nook_light.position = B.ground(area, nk, 1.2)
	add_child(_nook_light)


func notes_read() -> bool:
	return _flag(Data.FLAG_NOTE_1) and _flag(Data.FLAG_NOTE_2)


func is_light_placed() -> bool:
	return _flag(Data.FLAG_LIGHT_PLACED)


func _marker_text() -> Dictionary:
	if is_light_placed():
		return {}
	if notes_read():
		return {"text": "Light a candle for the groundskeeper", "enabled": true}
	return {"text": "Look at the empty candle dish", "enabled": true}


func _on_marker(_player: Node = null) -> void:
	if not notes_read():
		Events.say.emit("", "An empty candle dish on a little plinth. Someone meant to light it. Perhaps the groundskeeper's notes explain.", 5.0)
		return
	place_light()


## Lights the groundskeeper's candle (needs both notes). Sets ch2_groundskeeper_light_placed once. True if now.
func place_light() -> bool:
	if is_light_placed() or not notes_read():
		return false
	GameState.set_flag(Data.FLAG_LIGHT_PLACED, true)
	Events.caption.emit("[A soft hush, like a held breath let go]")
	Events.say.emit("", "The little flame settles. Behind the stones, moonflowers open one by one.", 5.0)
	if is_inside_tree():
		Audio.play_3d("checkpoint_light", _marker_candle.global_position, -4.0)
		Fx.burst(self, _marker_candle.global_position + Vector3.UP * 0.3, "sparkle", 1.0)
	_apply_state(not instant)
	return true


func has_pattern() -> bool:
	return GameState.has_reward(Data.REWARD_PATTERN)


## The hidden dress pattern (content bundle rw_ch2_candleyard_pattern, once through the ledger).
func take_pattern(_player: Node = null) -> bool:
	if has_pattern():
		return false
	var bundle: Dictionary = ItemDB.reward_bundle(Data.REWARD_PATTERN)
	var ok := GameState.grant_once(Data.REWARD_PATTERN, bundle.get("items", {}), bundle.get("flags", []),
		"Hidden under the stone: a folded dress pattern (Ghostlight Party). Sew it at the Loom.")
	if ok and is_inside_tree():
		Audio.play_3d("pickup", _pattern_stone.global_position, -2.0)
		Fx.burst(self, _pattern_stone.global_position + Vector3.UP * 0.3, "sparkle", 0.8)
	_apply_state()
	return ok


# --- The witch hat and its ribbons --------------------------------------------------------------------------

func _build_hat() -> void:
	var stakes: Array = []
	var rib_a: Array = []
	var rib_b: Array = []
	var i := 0
	for rp in Data.HAT_RIBBONS:
		var p: Vector2 = rp
		var side := Vector2(-(Data.HAT["pos"] as Vector2 - p).normalized().y, (Data.HAT["pos"] as Vector2 - p).normalized().x)
		var q := p + side * (0.9 if i % 2 == 0 else -0.9)       # beside the route, never on it
		var g := B.ground(area, q)
		var hsc := 1.0 + 0.15 * float(i % 3)
		stakes.append(Transform3D(Basis.from_scale(Vector3(1, hsc, 1)), g))
		var knot := g + Vector3(0, 1.1 * hsc, 0)
		# ribbons hang from the knot and flutter (the strip is flipped: its free ends point down)
		var xf := Transform3D(Basis(Vector3.UP, float(i) * 0.9) * Basis(Vector3.BACK, PI - 0.45), knot)
		(rib_a if i % 2 == 0 else rib_b).append(xf)
		B.cylinder(solids, g, 0.05, 1.1 * hsc)
		i += 1
	var branch_knot := B.ground(area, Data.HAT["pos"], float(Data.HAT["height"]) + 0.35) + Vector3(-0.3, 0, -0.2)
	rib_a.append(Transform3D(Basis(Vector3.BACK, PI - 0.35), branch_knot))
	B.multi(self, Art.stake(), Art.prop_material(), stakes, "RibbonStakes", 80.0)
	B.multi(self, Art.ribbon_strip(0.6), Art.ribbon_material(Art.RIBBON_PLUM), rib_a, "HatRibbonsPlum", 90.0, false)
	B.multi(self, Art.ribbon_strip(0.6), Art.ribbon_material(Art.ROSEBERRY), rib_b, "HatRibbonsRose", 90.0, false)
	_hat = Node3D.new()
	_hat.name = "WitchHat"
	_hat.position = B.ground(area, Data.HAT["pos"], float(Data.HAT["height"]))
	_hat.rotation_degrees = Vector3(18, 35, -24)
	add_child(_hat)
	var hm := MeshInstance3D.new()
	hm.mesh = Art.witch_hat()
	hm.material_override = Art.prop_material()
	_hat.add_child(hm)
	var it: Node3D = WestInteractable.new()
	it.setup({"id": "witch_hat", "text": "Rescue the stranded witch hat", "size": Vector3(1.4, 2.2, 1.4), "offset": Vector3(0, 1.1, 0),
		"handler": Callable(self, "rescue_hat"), "marker": true, "marker_radius": 0.7})
	it.position = B.ground(area, Data.HAT["pos"])
	add_child(it)
	interactables["witch_hat"] = it


func is_hat_found() -> bool:
	return _flag(Data.FLAG_HAT)


## Takes the hat down from the branch (sets ch2_witch_hat_found once; the optional log pays the pattern).
func rescue_hat(_player: Node = null) -> bool:
	if is_hat_found():
		return false
	GameState.set_flag(Data.FLAG_HAT, true)
	Events.caption.emit("[A soft flump as the hat drops into your arms]")
	if is_inside_tree() and not instant:
		var tw := create_tween()
		tw.tween_property(_hat, "position", _hat.position + Vector3(0.4, -0.9, 0.5), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_hat, "scale", Vector3.ONE * 0.05, 0.25)
		tw.tween_callback(_apply_state)
		Audio.play_3d("pickup", _hat.global_position, -2.0)
	else:
		_apply_state()
	return true


# --- Bench --------------------------------------------------------------------------------------------------

func _build_bench() -> void:
	var bp: Vector2 = Data.BENCH["pos"]
	var look: Vector2 = Data.BENCH["look"]
	var yaw := atan2(look.x - bp.x, look.y - bp.y)
	var basis := Basis(Vector3.UP, yaw)
	B.mesh_at(self, Art.bench(), Art.prop_material(), Transform3D(basis, B.ground(area, bp)), "CalmBench")
	B.box(solids, B.ground(area, bp, 0.45), Vector3(1.5, 0.9, 0.5), basis)
	var it: Node3D = WestInteractable.new()
	it.setup({"id": "bench", "text": "Sit a while", "size": Vector3(1.8, 1.4, 1.4), "offset": Vector3(0, 0.7, 0.3),
		"handler": Callable(self, "rest_on_bench")})
	it.transform = Transform3D(basis, B.ground(area, bp))
	add_child(it)
	interactables["bench"] = it


## A short, calm rest: a little health back and a quiet line (a small cooldown so it is not a heal fountain).
func rest_on_bench(_player: Node = null) -> bool:
	var now := Time.get_ticks_msec()
	if now - _bench_ms < BENCH_COOLDOWN_MS:
		Events.say.emit("", "The moonflowers nod. There is no hurry.", 3.0)
		return false
	_bench_ms = now
	GameState.set_flag(Data.FLAG_BENCH_RESTED, true)
	var pl: Node = Game.player
	if pl != null and is_instance_valid(pl) and pl.get("health") != null:
		var h: Node = pl.get("health")
		if h.has_method("heal"):
			h.heal(BENCH_HEAL)
	Events.say.emit("", "Krystal sits a while. The Candleyard is quiet from here, violet and kind.", 4.5)
	return true


# --- State -------------------------------------------------------------------------------------------------

func _apply_state(animate: bool = false) -> void:
	var placed := is_light_placed()
	if _marker_candle != null:
		_marker_candle.visible = placed
	if _nook_light != null:
		_nook_light.visible = placed
	if _marker_pool != null:
		_marker_pool.visible = placed and _marker_pool.emission_energy > 0.0
	if _nook_flowers != null:
		var petals: Node3D = _nook_flowers.get_node_or_null("NookPetals")
		if petals != null:
			if animate and placed and is_inside_tree():
				petals.visible = true
				petals.scale = Vector3.ONE * 0.2
				var tw := create_tween()
				tw.tween_property(petals, "scale", Vector3.ONE, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			else:
				petals.visible = placed
				petals.scale = Vector3.ONE
	var mk: Node3D = interactables.get("groundskeeper_marker")
	if mk != null:
		mk.set_active(not placed)
	var got := has_pattern()
	if _pattern_ribbon != null:
		_pattern_ribbon.visible = not got
	if _pattern_stone != null:
		_pattern_stone.position = B.ground(area, Data.PATTERN_SPOT + (Vector2(0.6, 0.3) if got else Vector2.ZERO))
	var pt: Node3D = interactables.get("hidden_pattern")
	if pt != null:
		pt.set_active(not got)
	var hat := is_hat_found()
	if _hat != null:
		_hat.visible = not hat
	var ht: Node3D = interactables.get("witch_hat")
	if ht != null:
		ht.set_active(not hat)


func _flag(f: String) -> bool:
	var v: Variant = GameState.get_flag(f)
	return v is bool and v
