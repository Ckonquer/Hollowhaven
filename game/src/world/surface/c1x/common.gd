extends RefCounted
## Shared helpers for the Chapter One optional additions to Hollowhaven Woods (module B7: tailor_cache,
## bramblewatch, meadow_patch, sap_stumps, moth_pocket, seasonal_decor). Every annex script is a RefCounted with
## `static func build(area: Node3D) -> void` (src/world/surface/annexes.gd safe-loads them after every legacy step)
## and places explicit new nodes under one container "C1xAdditions" of the area. Positions and ids: data/c1x_layout.gd.
##
##   const Common := preload("res://src/world/surface/c1x/common.gd")
##   var parent := Common.sub_root(area, "Bramblewatch")
##   Common.place(parent, node, area, Vector2(x, z), yaw_deg)          # adds + puts it on the ground
##   Common.make_spawner(parent, area, L.ELDER_SPAWNER)                   # null when the enemy script is missing
##   Common.grant_content("rw_c1x_elder", "message")                      # data/sources.gd REWARDS "content" bundle
##   Common.harvest_node(L.SAP_KIND, "c1x_resin_0", visual, {...})        # resource node built from data NODES
##
## Meshes are merged, vertex-coloured and cached (static), materials come from Mat / NodeVisuals caches, so every
## copy of a prop shares its geometry and material.

const L := preload("res://data/c1x_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")

const ROOT_NAME := "C1xAdditions"
const SPAWNER_PATH := "res://src/enemies/enemy_spawner.gd"
const FACTORY_PATH := "res://src/enemies/enemy_factory.gd"
const LAYER_WORLD := 1
const LAYER_INTERACT := 16

## Named ribbon colours (tailor's trail, seasonal ribbons).
const RIBBON_COLORS := {"rose": Color("f27aa0"), "cream": Color("f6ead0"), "lavender": Color("b9a0e6"),
	"sunflower": Color("f2c14e"), "teal": Color("5cc0b5"), "pumpkin": Color("ef8a3c")}
const RESIN := Color("e3a13b")
const RESIN_DARK := Color("b8701f")
const PUMPKIN := Color("ef8a3c")
const PUMPKIN_DARK := Color("c9621f")
const ROSEBERRY := Color("f06a92")
const SUNFLAX_GOLD := Color("f5cf4a")
const SUNFLAX_STEM := Color("7faa4c")
const MOONBELL := Color("e9ecff")
const MOONBELL_GLOW := Color("bcd2ff")

static var _meshes: Dictionary = {}
static var _enemy_ok: Dictionary = {}


# --- Scene helpers -------------------------------------------------------------------------------------------

## The container for every c1x node of an area (created once).
static func root(area: Node3D) -> Node3D:
	var r := area.get_node_or_null(ROOT_NAME) as Node3D
	if r == null:
		r = Node3D.new()
		r.name = ROOT_NAME
		area.add_child(r)
	return r


## A named child container under root(area) (one per annex script).
static func sub_root(area: Node3D, child_name: String) -> Node3D:
	var r := root(area)
	var s := r.get_node_or_null(child_name) as Node3D
	if s == null:
		s = Node3D.new()
		s.name = child_name
		r.add_child(s)
	return s


static func height(area: Node, p: Vector2) -> float:
	if area != null and area.has_method("height_at"):
		return float(area.height_at(p.x, p.y))
	return 0.0


static func ground(area: Node, p: Vector2, dy: float = 0.0) -> Vector3:
	return Vector3(p.x, height(area, p) + dy, p.y)


## Adds `node` under `parent` and stands it on the ground at `p` (world XZ) with a yaw in degrees.
static func place(parent: Node3D, node: Node3D, area: Node, p: Vector2, yaw_deg: float = 0.0, dy: float = 0.0) -> Node3D:
	parent.add_child(node)
	node.global_position = ground(area, p, dy)
	node.rotation.y = deg_to_rad(yaw_deg)
	return node


static func play_3d(sound: String, pos: Vector3, volume_db: float = 0.0) -> void:
	if Audio.has_sound(sound):
		Audio.play_3d(sound, pos, volume_db)


## Krystal (Game.player) if she is in the tree.
static func player() -> Node3D:
	if Game.player != null and is_instance_valid(Game.player) and (Game.player as Node).is_inside_tree():
		return Game.player as Node3D
	return null


# --- Enemies (built in parallel by another module: never crash when a script is missing) --------------------

## True when EnemyFactory knows `enemy_id` AND its script exists and compiles.
static func enemy_available(enemy_id: String) -> bool:
	if _enemy_ok.has(enemy_id):
		return bool(_enemy_ok[enemy_id])
	var ok := false
	if ResourceLoader.exists(FACTORY_PATH) and ResourceLoader.exists(SPAWNER_PATH):
		var f: Variant = load(FACTORY_PATH)
		if f is Script:
			var scripts: Variant = (f as Script).get_script_constant_map().get("SCRIPTS", {})
			if scripts is Dictionary and (scripts as Dictionary).has(enemy_id):
				var path := String((scripts as Dictionary)[enemy_id])
				if ResourceLoader.exists(path):
					var s: Variant = load(path)
					ok = s is Script and (s as Script).can_instantiate()
	_enemy_ok[enemy_id] = ok
	return ok


## Forgets the availability cache (tests; a hot-reloaded enemy module).
static func reset_enemy_cache() -> void:
	_enemy_ok.clear()


## An EnemySpawner for a data/c1x_layout.gd spawner definition, or null when its enemy is unavailable.
## `force` skips the availability check (tests use a stand-in enemy id).
static func make_spawner(parent: Node3D, area: Node, def: Dictionary, force: bool = false) -> Node3D:
	var enemy := String(def.get("enemy", ""))
	if not force and not enemy_available(enemy):
		return null
	var script: Variant = load(SPAWNER_PATH) if ResourceLoader.exists(SPAWNER_PATH) else null
	if not (script is Script) or not (script as Script).can_instantiate():
		return null
	var sp: Node3D = (script as Script).new()
	sp.setup({"enemy": enemy, "count": int(def.get("count", 1)), "radius": float(def.get("radius", 3.0)),
		"respawn_minutes": float(def.get("respawn_minutes", 720.0)), "spawner_id": String(def.get("id", "")),
		"wander_radius": float(def.get("wander_radius", -1.0))})
	sp.name = "Spawner_" + String(def.get("id", enemy))
	var p: Vector2 = def.get("pos", Vector2.ZERO)
	parent.add_child(sp)
	sp.global_position = ground(area, p, 0.1)
	return sp


# --- Rewards --------------------------------------------------------------------------------------------------

## Grants a data/sources.gd REWARDS bundle owned by a content module ("by": "content") exactly once.
## Returns true only the first time. Log rewards (rw_<step>/rw_<goal>) are refused: the quest layer pays those.
static func grant_content(reward_id: String, message: String = "") -> bool:
	var bundle: Dictionary = ItemDB.reward_bundle(reward_id)
	if bundle.is_empty() or String(bundle.get("by", "")) != "content":
		push_warning("c1x: %s is not a content reward bundle" % reward_id)
		return false
	var items: Dictionary = bundle.get("items", {})
	var flags: Array = bundle.get("flags", [])
	return GameState.grant_once(reward_id, items, flags, message)


# --- Harvestable nodes from data/sources.gd NODES ------------------------------------------------------------

## Legacy base kind every c1x harvestable behaves like (bush = only the "Berries" child hides when harvested,
## the rest - stump, stubble, leaves - stays, keeps its collider and says it is regrowing).
const BASE_KIND := "bush"

## Builds (not yet in the tree) a harvestable for a data NODES kind. resource_node resolves tool, min_tier, hits,
## drops, respawn, name (arachnophobia alt_name) and verb from ItemDB.node_kind(kind) itself; `extra` may override
## setup keys (solid, hit_sound, fx, verb...). `regrow_text` replaces the "<name> (regrowing)" prompt.
static func harvest_node(kind: String, node_id: String, visual: Node3D, extra: Dictionary = {}, regrow_text: String = "") -> Node3D:
	if ItemDB.node_kind(kind).is_empty():
		push_warning("c1x: unknown node kind %s" % kind)
	var params := {"node_id": node_id, "kind": kind, "visual": visual, "solid": false}
	for k in extra:
		params[k] = extra[k]
	var n: Node3D = C1xNode.new()
	n.set("regrow_text", regrow_text)
	n.setup(params)
	n.name = node_id
	return n


## A resource_node for a data kind (sap_stump, sunflax_patch, roseberry_bush) that keeps that kind as its `kind`
## (Events.harvested, mastery "first harvest of each kind", get_harvest_info - so Mochi's berry/grass forage
## never targets a sap stump) and runs the unmodified resource_node harvest (gathering bonus yield included),
## but always behaves like a berry bush (BASE_KIND): only its "Berries" part hides while it refills.
class C1xNode extends "res://src/world/common/resource_node.gd":
	var event_kind: String = ""        # == kind: the data kind reported by Events.harvested
	var regrow_text: String = ""

	func _resolve_kind() -> void:
		super._resolve_kind()
		event_kind = kind
		if not KIND_DEFAULTS.has(kind):
			base_kind = "bush"

	func get_interaction(player: Node = null) -> Dictionary:
		if depleted and regrow_text != "":
			return {"text": regrow_text, "enabled": false}
		return super.get_interaction(player)


# --- Colliders ------------------------------------------------------------------------------------------------

static func solid_cylinder(parent: Node3D, radius: float, h: float, surface: String = "wood", offset: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = h
	cs.shape = c
	cs.position = offset + Vector3(0, h * 0.5, 0)
	body.add_child(cs)
	parent.add_child(body)
	return body


static func interact_sphere(parent: Node3D, radius: float, y: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Interact"
	body.collision_layer = LAYER_INTERACT
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	cs.shape = s
	cs.position = Vector3(0, y, 0)
	body.add_child(cs)
	parent.add_child(body)
	return body


# --- Materials ------------------------------------------------------------------------------------------------

## Vertex-coloured toon with an outline (props).
static func prop_material(outline: float = 0.016) -> Material:
	return Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.25}), outline)


## Vertex-coloured toon without an outline (flat ground details).
static func plain_material() -> Material:
	return Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.2})


## Glossy amber resin.
static func resin_material() -> Material:
	return Mat.outlined(Mat.toon(RESIN, {"rim": 0.6, "specular": 0.8, "emission": RESIN_DARK, "emission_energy": 0.25}), 0.008)


## Cloth that flutters (ribbon tails; no outline: the outline pass does not sway).
static func flutter_material() -> Material:
	return Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.35, "wind": 0.09, "wind_speed": 2.6, "wind_height": 0.45})


static func mi(mesh: Mesh, material: Material, node_name: String = "", vis_range: float = 70.0, shadows: bool = false) -> MeshInstance3D:
	var m := Props.instance(mesh, material, vis_range, shadows)
	if node_name != "":
		m.name = node_name
	return m


# --- Meshes (cached) ------------------------------------------------------------------------------------------

## Height along the branch where the ribbon is tied.
const KNOT_HEIGHT := 1.0


## Where the ribbon knot sits on branch `variant` (on the stick's axis).
static func branch_knot(variant: int) -> Vector3:
	var key := "branch|%d" % variant
	if not _meshes.has(key + "|knot"):
		branch_mesh(variant)
	return _meshes[key + "|knot"]


## A low crooked branch stuck in the ground (the "low branch" a ribbon is tied to), ~1.3 m.
static func branch_mesh(variant: int) -> ArrayMesh:
	var key := "branch|%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 91000 + variant
	var m := NodeVisuals.Merger.new()
	var lean := Basis(Vector3.BACK, deg_to_rad(rng.randf_range(8.0, 16.0)))
	_meshes[key + "|knot"] = lean * Vector3(0, KNOT_HEIGHT, 0)
	m.add(NodeVisuals._cyl(0.035, 0.075, 1.25, 7), Transform3D(lean, lean * Vector3(0, 0.62, 0)), Palette.BARK)
	var fork := Basis(Vector3.UP, rng.randf_range(0.4, 1.2)) * Basis(Vector3.BACK, deg_to_rad(-48.0))
	var fp := lean * Vector3(0, 0.95, 0)
	m.add(NodeVisuals._cyl(0.02, 0.035, 0.55, 6), Transform3D(fork, fp + fork * Vector3(0, 0.27, 0)), Palette.BARK)
	for i in 3:
		var a := TAU * float(i) / 3.0 + rng.randf()
		m.add(NodeVisuals.ublob(i + variant, 0.3, 0.6, 1), NodeVisuals.sxf(0.09, fp + fork * Vector3(0, 0.45, 0) + Vector3(cos(a) * 0.08, 0.02, sin(a) * 0.08)), Palette.FOLIAGE)
	m.add(Kit.blob_mesh(0.14, 91050 + variant, 0.3, 0.5, 1), Transform3D(Basis(), Vector3(0, 0.03, 0)), Palette.DIRT_DARK)
	var mesh := m.commit()
	_meshes[key] = mesh
	return mesh


## Ribbon bow (knot + two loops) around a stick, local origin = the knot.
static func bow_mesh(color: Color) -> ArrayMesh:
	var key := "bow|%s" % color.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._sph(0.05, 5, 8), Transform3D(Basis().scaled(Vector3(1.0, 0.8, 0.8)), Vector3.ZERO), color)
	for s in [-1.0, 1.0]:
		var b := Basis(Vector3.BACK, deg_to_rad(float(s) * 70.0)) * Basis.from_scale(Vector3(0.9, 1.5, 0.45))
		m.add(NodeVisuals._sph(0.07, 5, 8), Transform3D(b, Vector3(float(s) * 0.1, 0.02, 0)), color.lightened(0.08))
	var mesh := m.commit()
	_meshes[key] = mesh
	return mesh


## Two ribbon tails built UPWARD from the knot (the node is flipped so they hang; the toon wind sway grows
## with local height, i.e. toward the tips).
static func tails_mesh(color: Color) -> ArrayMesh:
	var key := "tails|%s" % color.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var m := NodeVisuals.Merger.new()
	var dark := color.darkened(0.12)
	for s in [-1.0, 1.0]:
		var x0 := float(s) * 0.025
		var x1 := float(s) * 0.09
		var w := 0.035
		var n := Vector3.BACK
		var a := Vector3(x0 - w, 0.0, 0)
		var b := Vector3(x0 + w, 0.0, 0)
		var c := Vector3(x1 - w, 0.42, 0)
		var d := Vector3(x1 + w, 0.42, 0)
		m.tri(a, c, b, n, color, dark, color, true)
		m.tri(b, c, d, n, color, dark, dark, true)
		# a small notch at the tail tip
		m.tri(c, Vector3(x1, 0.36, 0), d, n, dark, dark, dark, true)
	var mesh := m.commit()
	_meshes[key] = mesh
	return mesh


## A ribbon tied to a low branch: branch + bow + fluttering tails. Returns a Node3D (origin on the ground).
static func ribbon_marker(color: Color, variant: int, on_branch: bool = true) -> Node3D:
	var root_node := Node3D.new()
	var knot := Vector3(0.0, 1.0, 0.0)
	if on_branch:
		root_node.add_child(mi(branch_mesh(variant % 3), NodeVisuals.bark_material(), "Branch", 70.0, false))
		knot = branch_knot(variant % 3)
	else:
		root_node.add_child(mi(stake_mesh(), NodeVisuals.bark_material(), "Stake", 70.0, false))
		knot = Vector3(0.0, 1.0, 0.0)
	var bow := mi(bow_mesh(color), prop_material(0.008), "Bow", 70.0, false)
	bow.position = knot
	root_node.add_child(bow)
	var tails := mi(tails_mesh(color), flutter_material(), "Tails", 60.0, false)
	tails.position = knot + Vector3(0, -0.02, 0.01)
	tails.rotation = Vector3(PI, 0.0, 0.0)      # hang down; wind sway grows toward the tips
	root_node.add_child(tails)
	return root_node


## A straight garden stake (seasonal ribbons).
static func stake_mesh() -> ArrayMesh:
	if _meshes.has("stake"):
		return _meshes["stake"]
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._cyl(0.04, 0.05, 1.15, 6), Transform3D(Basis(), Vector3(0, 0.55, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._cyl(0.0, 0.045, 0.08, 6), Transform3D(Basis(), Vector3(0, 1.16, 0)), Palette.WOOD)
	var mesh := m.commit()
	_meshes["stake"] = mesh
	return mesh


## A ribbed storybook pumpkin (+ curly stem and a leaf), base at y = 0, ~0.5 m wide.
static func pumpkin_mesh(variant: int) -> ArrayMesh:
	var key := "pumpkin|%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 92000 + variant
	var m := NodeVisuals.Merger.new()
	var r := rng.randf_range(0.2, 0.27)
	var lobes := 8
	var col := func(p: Vector3, n: Vector3) -> Color:
		var t := clampf(p.y / (r * 1.6), 0.0, 1.0)
		return PUMPKIN_DARK.lerp(PUMPKIN, t).lerp(Color("ffb46a"), clampf(n.y, 0.0, 1.0) * 0.18)
	for i in lobes:
		var a := TAU * float(i) / float(lobes)
		var b := Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.62, 0.82, 0.5))   # local x = radial
		m.add(NodeVisuals._sph(r, 6, 10), Transform3D(b, Vector3(cos(a) * r * 0.5, r * 0.8, sin(a) * r * 0.5)), col)
	var stem_b := Basis(Vector3.BACK, deg_to_rad(rng.randf_range(-18.0, 18.0)))
	m.add(NodeVisuals._cyl(0.025, 0.04, 0.14, 6), Transform3D(stem_b, Vector3(0, r * 1.55 + 0.05, 0)), Color("6f7a3a"))
	var leaf_b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, deg_to_rad(-70.0))
	m.add(NodeVisuals._hemi(0.09, 0.03, 8), Transform3D(leaf_b * Basis.from_scale(Vector3(1.0, 1.0, 1.6)), Vector3(0.07, r * 1.55, 0.03)), Palette.FOLIAGE)
	var mesh := m.commit()
	_meshes[key] = mesh
	return mesh


## Sap stump visual for resource_node: "Stump" (solid wood + spout + bucket) and "Berries" (the resin that
## hides while it refills). Carries resource_node collider metadata.
static func sap_stump_visual(variant: int) -> Node3D:
	var key := "sap_stump|%d" % variant
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 93000 + variant
		var m := NodeVisuals.Merger.new()
		var r0 := rng.randf_range(0.36, 0.44)
		m.add_lumpy(NodeVisuals._cyl(r0 * 0.9, r0 * 1.05, 0.62, 12, 2), Transform3D(Basis(), Vector3(0, 0.31, 0)), Palette.BARK, 0.05, Vector3.ZERO, 93100 + variant)
		m.add(NodeVisuals._cyl(r0 * 0.86, r0 * 0.86, 0.04, 12), Transform3D(Basis(), Vector3(0, 0.63, 0)), Palette.WOOD_LIGHT)
		m.add(NodeVisuals._cyl(r0 * 0.5, r0 * 0.5, 0.02, 12), Transform3D(Basis(), Vector3(0, 0.655, 0)), Palette.WOOD)
		for i in 4:
			var a := TAU * float(i) / 4.0 + rng.randf() * 0.5
			m.add(NodeVisuals.ublob(i + variant, 0.25, 0.5, 1), NodeVisuals.sxf(r0 * 0.55, Vector3(cos(a) * r0 * 0.85, 0.08, sin(a) * r0 * 0.85)), Palette.BARK_DARK)
		# the spout (a carved wooden tap) and the little bucket hanging under it, on the +z side
		m.add(NodeVisuals._cyl(0.03, 0.035, 0.2, 6), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(80.0)), Vector3(0, 0.42, r0 + 0.07)), Palette.WOOD_LIGHT)
		m.add(NodeVisuals._cyl(0.1, 0.08, 0.16, 10), Transform3D(Basis(), Vector3(0, 0.19, r0 + 0.2)), Palette.WOOD)
		m.add(NodeVisuals._cyl(0.105, 0.105, 0.02, 10), Transform3D(Basis(), Vector3(0, 0.27, r0 + 0.2)), Palette.WOOD_DARK)
		m.add(NodeVisuals._cyl(0.084, 0.084, 0.02, 10), Transform3D(Basis(), Vector3(0, 0.12, r0 + 0.2)), Palette.WOOD_DARK)
		_meshes[key] = m.commit()
		# resin: drips down the bark, a bead on the spout and the bucket filled to the brim
		var rs := NodeVisuals.Merger.new()
		for i in 3:
			var a := PI * 0.5 + rng.randf_range(-0.9, 0.9)
			var y := rng.randf_range(0.3, 0.55)
			var p := Vector3(cos(a) * r0 * 0.98, y, sin(a) * r0 * 0.98)
			rs.add(NodeVisuals._sph(0.045, 5, 8), Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.7, 2.2, 1.0)), p), RESIN)
		rs.add(NodeVisuals._sph(0.035, 5, 8), Transform3D(Basis().scaled(Vector3(1, 1.4, 1)), Vector3(0, 0.36, r0 + 0.16)), RESIN)
		rs.add(NodeVisuals._cyl(0.088, 0.088, 0.03, 10), Transform3D(Basis(), Vector3(0, 0.255, r0 + 0.2)), RESIN)
		rs.add(NodeVisuals._sph(0.05, 5, 8), Transform3D(Basis().scaled(Vector3(1.2, 0.6, 1.2)), Vector3(0.03, 0.275, r0 + 0.19)), RESIN.lightened(0.2))
		_meshes[key + "|resin"] = rs.commit()
		_meshes[key + "|r0"] = r0
	var root_node := Node3D.new()
	root_node.add_child(mi(_meshes[key], prop_material(0.02), "Stump", 90.0, true))
	root_node.add_child(mi(_meshes[key + "|resin"], resin_material(), "Berries", 60.0, false))
	var r0v := float(_meshes[key + "|r0"])
	root_node.set_meta("solid", "cylinder")
	root_node.set_meta("solid_radius", r0v)
	root_node.set_meta("solid_height", 0.62)
	root_node.set_meta("interact_radius", 0.95)
	root_node.set_meta("interact_y", 0.45)
	root_node.set_meta("fx_height", 0.7)
	return root_node


## Wild sunflax clump: short green stubble ("Stems", stays) + tall stalks with golden flower heads ("Berries").
static func sunflax_visual(variant: int) -> Node3D:
	var key := "sunflax|%d" % variant
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 94000 + variant
		var stems := NodeVisuals.Merger.new()
		var tops := NodeVisuals.Merger.new()
		for i in 14:
			var a := rng.randf() * TAU
			var rr := rng.randf_range(0.0, 0.3)
			var base := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			var tilt := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, rng.randf_range(0.04, 0.22))
			stems.add(NodeVisuals._cyl(0.012, 0.018, 0.16, 4), Transform3D(tilt, base + Vector3(0, 0.08, 0)), SUNFLAX_STEM.darkened(0.1))
			var h := rng.randf_range(0.55, 0.9)
			tops.add(NodeVisuals._cyl(0.008, 0.012, h, 4), Transform3D(tilt, base + tilt * Vector3(0, 0.16 + h * 0.5, 0)), SUNFLAX_STEM)
			var tip := base + tilt * Vector3(0, 0.16 + h, 0)
			tops.add(NodeVisuals._sph(0.04, 4, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.6, 1.4)), tip), SUNFLAX_GOLD)
			if i % 3 == 0:
				tops.add(NodeVisuals._sph(0.025, 3, 5), Transform3D(Basis(), tip + Vector3(0, 0.035, 0)), Color("fff1b0"))
		_meshes[key] = stems.commit()
		_meshes[key + "|tops"] = tops.commit()
	var root_node := Node3D.new()
	var m_stem := Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.2})
	var m_top := Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.3, "wind": 0.05, "wind_height": 1.0})
	root_node.add_child(mi(_meshes[key], m_stem, "Stems", 55.0, false))
	root_node.add_child(mi(_meshes[key + "|tops"], m_top, "Berries", 70.0, false))
	root_node.set_meta("solid", "none")
	root_node.set_meta("interact_radius", 0.7)
	root_node.set_meta("interact_y", 0.45)
	root_node.set_meta("fx_height", 0.7)
	return root_node


## Roseberry bush: a rounder, rosier bush with pink berries ("Berries" hides when picked).
static func roseberry_visual(variant: int) -> Node3D:
	var v := posmod(variant, 3)
	var key := "roseberry|%d" % v
	if not _meshes.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 95000 + v
		var m := NodeVisuals.Merger.new()
		var centers: Array = [[Vector3(0, 0.55, 0), 0.72]]
		for i in 3:
			var a := TAU * float(i) / 3.0 + 0.3
			centers.append([Vector3(cos(a) * 0.55, 0.4, sin(a) * 0.55), 0.5])
		for i in 22:
			var c: Array = centers[i % centers.size()]
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
			var p: Vector3 = c[0] + Vector3(dir.x, dir.y * 0.85, dir.z) * float(c[1]) * 1.12
			var fn := func(_q: Vector3, n: Vector3) -> Color:
				return ROSEBERRY.lerp(Color("ffc2d6"), clampf(n.y, 0.0, 1.0) * 0.5)
			m.add(NodeVisuals._sph(0.075, 5, 8), Transform3D(Basis(), p), fn)
			if i % 4 == 0:
				m.add(NodeVisuals._sph(0.05, 4, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.5, 1.4)), p + Vector3(0.04, 0.06, 0.02)), Color("f7a8c4"))
		_meshes[key] = m.commit()
	var root_node := Node3D.new()
	var leaves := NodeVisuals.bush_mesh(v, Color("3f7446"), Color("7cb86a"))
	root_node.add_child(mi(leaves, NodeVisuals.foliage_material(0.03, 1.4, 0.022, 0.18), "Leaves", 110.0, true))
	var bm := Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.55, "specular": 0.6})
	root_node.add_child(mi(_meshes[key], Mat.outlined(bm, 0.012), "Berries", 80.0, false))
	root_node.set_meta("solid", "none")
	root_node.set_meta("interact_radius", 1.05)
	root_node.set_meta("interact_y", 0.55)
	root_node.set_meta("fx_height", 0.8)
	return root_node


## The Tailor's Cache: a cloth-wrapped little trunk tied with a rose ribbon. Returns {body: ArrayMesh, lid: ArrayMesh}.
static func cache_meshes() -> Dictionary:
	if _meshes.has("cache_body"):
		return {"body": _meshes["cache_body"], "lid": _meshes["cache_lid"]}
	var m := NodeVisuals.Merger.new()
	var w := 0.78
	var d := 0.5
	var h := 0.4
	m.add(NodeVisuals._box(Vector3(w, h, d)), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), Palette.WOOD)
	for sx in [-1.0, 1.0]:
		m.add(NodeVisuals._box(Vector3(0.06, h + 0.02, d + 0.03)), Transform3D(Basis(), Vector3(float(sx) * (w * 0.5 - 0.08), h * 0.5, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._box(Vector3(w + 0.02, 0.05, d + 0.02)), Transform3D(Basis(), Vector3(0, 0.025, 0)), Palette.WOOD_DARK)
	# cream cloth bundle peeking out, a rose ribbon band on the front and a brass clasp
	m.add(NodeVisuals._box(Vector3(0.1, 0.12, 0.02)), Transform3D(Basis(), Vector3(0, h - 0.06, d * 0.5 + 0.01)), Color("d9b25a"))
	m.add(NodeVisuals._box(Vector3(0.05, h + 0.01, d + 0.04)), Transform3D(Basis(), Vector3(0.14, h * 0.5, 0)), RIBBON_COLORS["rose"])
	# a few root knuckles hugging it (it sits between the Old Oak's roots)
	for i in 3:
		var a := -0.6 + float(i) * 1.1
		m.add(NodeVisuals.ublob(i + 40, 0.3, 0.45, 1), NodeVisuals.sxf(0.2, Vector3(cos(a) * 0.55, 0.06, -0.25 + sin(a) * 0.2)), Palette.BARK_DARK)
	_meshes["cache_body"] = m.commit()
	var lm := NodeVisuals.Merger.new()
	# lid built around the hinge at the back edge (local origin), extending toward +z
	lm.add(NodeVisuals._box(Vector3(w + 0.04, 0.08, d + 0.04)), Transform3D(Basis(), Vector3(0, 0.04, d * 0.5)), Palette.WOOD_LIGHT)
	# a low dome: a cylinder lying along X, squashed vertically
	lm.add(NodeVisuals._cyl(d * 0.5 + 0.02, d * 0.5 + 0.02, w + 0.04, 12), Transform3D(Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(1.0, 0.45, 1.0)), Vector3(0, 0.08, d * 0.5)), Palette.WOOD)
	lm.add(NodeVisuals._box(Vector3(0.05, 0.2, d + 0.06)), Transform3D(Basis(), Vector3(0.14, 0.1, d * 0.5)), RIBBON_COLORS["rose"])
	lm.add(NodeVisuals._sph(0.06, 5, 8), Transform3D(Basis().scaled(Vector3(1.3, 0.9, 0.7)), Vector3(0.14, 0.2, d * 0.5)), RIBBON_COLORS["rose"].lightened(0.1))
	_meshes["cache_lid"] = lm.commit()
	return {"body": _meshes["cache_body"], "lid": _meshes["cache_lid"]}


## Thorny root wall along local X (length L), base y = 0, ~height h.
static func root_wall_mesh(length: float, h: float) -> ArrayMesh:
	var key := "rootwall|%.2f|%.2f" % [length, h]
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 96000
	var m := NodeVisuals.Merger.new()
	var bark := func(p: Vector3, _n: Vector3) -> Color:
		return Palette.BARK_DARK.lerp(Color("8a6a4a"), clampf(p.y / h, 0.0, 1.0))
	var n := int(ceil(length / 0.55))
	for i in n:
		var x := lerpf(-length * 0.5 + 0.2, length * 0.5 - 0.2, float(i) / float(maxi(n - 1, 1)))
		var th := rng.randf_range(0.7, 1.0) * h
		var tilt := Basis(Vector3.BACK, rng.randf_range(-0.35, 0.35)) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		m.add_lumpy(NodeVisuals._cyl(0.04, rng.randf_range(0.13, 0.19), th, 7, 3), Transform3D(tilt, Vector3(x, th * 0.5 - 0.05, rng.randf_range(-0.12, 0.12))), bark, 0.06, Vector3(x, 0, 0), 96100 + i)
		for t in 3:
			var tp := Vector3(x, 0, 0) + tilt * Vector3(0, th * (0.3 + t * 0.22), 0)
			var tb := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, deg_to_rad(90.0))
			m.add(NodeVisuals._cyl(0.0, 0.028, 0.14, 4), Transform3D(tb, tp + tb * Vector3(0, 0.07, 0)), Color("d8c79a"))
	# a knotted base that bulges out of the soil
	for i in 3:
		var x := lerpf(-length * 0.35, length * 0.35, float(i) / 2.0)
		m.add(NodeVisuals.ublob(i + 7, 0.3, 0.45, 1), NodeVisuals.sxf(0.36, Vector3(x, 0.02, 0)), Palette.DIRT_DARK)
	var mesh := m.commit()
	_meshes[key] = mesh
	return mesh


## The telegraph: a cracked soil strip along local X with a warm, steady glow in the fissure (never flashes).
static func crack_meshes(length: float) -> Dictionary:
	var key := "crack|%.2f" % length
	if _meshes.has(key):
		return {"soil": _meshes[key], "glow": _meshes[key + "|glow"]}
	var rng := RandomNumberGenerator.new()
	rng.seed = 97000
	var soil := NodeVisuals.Merger.new()
	var glow := NodeVisuals.Merger.new()
	var n := int(ceil(length / 0.35))
	var prev := Vector3(-length * 0.5, 0.03, 0)
	for i in n + 1:
		var x := lerpf(-length * 0.5, length * 0.5, float(i) / float(n))
		var p := Vector3(x, 0.03, rng.randf_range(-0.14, 0.14))
		soil.add(NodeVisuals.ublob(i, 0.35, 0.18, 1), NodeVisuals.sxf(rng.randf_range(0.18, 0.28), Vector3(x, 0.0, rng.randf_range(-0.2, 0.2))), Palette.DIRT_DARK.darkened(0.15))
		if i > 0:
			var seg := p - prev
			var b := Basis(Vector3.UP, -atan2(seg.z, seg.x)) * Basis(Vector3.BACK, PI * 0.5)
			glow.add(NodeVisuals._cyl(0.03, 0.03, seg.length(), 4), Transform3D(b, (p + prev) * 0.5 + Vector3(0, 0.05, 0)), Color.WHITE)
		prev = p
	_meshes[key] = soil.commit()
	_meshes[key + "|glow"] = glow.commit()
	return {"soil": _meshes[key], "glow": _meshes[key + "|glow"]}


## An old watch post wrapped in brambles, with a faded pennant.
static func post_mesh() -> ArrayMesh:
	if _meshes.has("post"):
		return _meshes["post"]
	var m := NodeVisuals.Merger.new()
	var tilt := Basis(Vector3.BACK, deg_to_rad(6.0))
	m.add_lumpy(NodeVisuals._cyl(0.1, 0.14, 1.8, 7, 3), Transform3D(tilt, tilt * Vector3(0, 0.9, 0)), Palette.BARK_DARK, 0.03, Vector3.ZERO, 98000)
	m.add(NodeVisuals._cyl(0.0, 0.12, 0.16, 7), Transform3D(tilt, tilt * Vector3(0, 1.88, 0)), Palette.BARK_DARK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 98100
	for i in 9:
		var y := 0.2 + float(i) * 0.15
		var a := float(i) * 2.2
		var b := Basis(Vector3.UP, a) * Basis(Vector3.BACK, deg_to_rad(80.0))
		m.add(NodeVisuals._cyl(0.02, 0.03, 0.34, 5), Transform3D(b, tilt * Vector3(0, y, 0) + Vector3(cos(a) * 0.08, 0, sin(a) * 0.08)), Color("6a3f4a"))
		m.add(NodeVisuals._cyl(0.0, 0.018, 0.08, 4), Transform3D(Basis(Vector3.UP, a + 1.0) * Basis(Vector3.RIGHT, PI * 0.5), tilt * Vector3(0, y + 0.05, 0) + Vector3(cos(a) * 0.14, 0, sin(a) * 0.14)), Color("d8c79a"))
	for i in 3:
		m.add(NodeVisuals.ublob(i + 20, 0.4, 0.8, 1), NodeVisuals.sxf(rng.randf_range(0.14, 0.2), tilt * Vector3(0, 0.25 + float(i) * 0.45, 0) + Vector3(0.1, 0, 0.05)), Color("4d6b3a"))
	var p0 := tilt * Vector3(0, 1.6, 0)
	m.tri(p0, p0 + Vector3(0.42, -0.1, 0.05), p0 + Vector3(0, -0.28, 0), Vector3.BACK, Color("c8a0a8"), Color("b08890"), Color("c8a0a8"), true)
	var mesh := m.commit()
	_meshes["post"] = mesh
	return mesh


## "A sticky old tree": a gnarled old oak with amber resin running down its trunk. {bark, crown, resin}.
static func sticky_tree_meshes() -> Dictionary:
	if _meshes.has("sticky_bark"):
		return {"bark": _meshes["sticky_bark"], "crown": _meshes["sticky_crown"], "resin": _meshes["sticky_resin"]}
	var rng := RandomNumberGenerator.new()
	rng.seed = 99000
	var bark := NodeVisuals.Merger.new()
	var th := 4.4
	var bark_fn := func(q: Vector3, _n: Vector3) -> Color:
		return Palette.BARK_DARK.lerp(Palette.BARK, clampf(q.y / th, 0.0, 1.0) * 0.7)
	bark.add_lumpy(NodeVisuals._cyl(0.5, 0.78, th, 12, 5), Transform3D(Basis(), Vector3(0, th * 0.5, 0)), bark_fn, 0.12, Vector3.ZERO, 99001)
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf() * 0.4
		var b := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, deg_to_rad(-70.0))
		bark.add(NodeVisuals._cyl(0.1, 0.32, 1.5, 7), Transform3D(b, Vector3(cos(a) * 0.75, 0.22, sin(a) * 0.75)), Palette.BARK_DARK)
	var tips: Array = []
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.3 + rng.randf() * 0.3
		var b := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, deg_to_rad(-rng.randf_range(38.0, 58.0)))
		var start := Vector3(0, th - 0.6 + float(i) * 0.2, 0)
		var blen := rng.randf_range(2.0, 2.8)
		bark.add(NodeVisuals._cyl(0.08, 0.26, blen, 7), Transform3D(b, start + b * Vector3(0, blen * 0.5, 0)), bark_fn)
		tips.append(start + b * Vector3(0, blen, 0))
	var crown := NodeVisuals.Merger.new()
	var lo := Color("4b6b3c")
	var hi := Color("9a9a4a")
	var cfn := func(q: Vector3, _n: Vector3) -> Color:
		return lo.lerp(hi, clampf((q.y - th) / 3.0, 0.0, 1.0)).lerp(Palette.FOLIAGE_AUTUMN, 0.18)
	for i in tips.size():
		crown.add(NodeVisuals.ublob(i + 3, 0.28, 0.75, 2), NodeVisuals.sxf(rng.randf_range(1.2, 1.6), tips[i] + Vector3(0, 0.3, 0)), cfn)
	crown.add(NodeVisuals.ublob(9, 0.28, 0.8, 2), NodeVisuals.sxf(1.7, Vector3(0, th + 1.2, 0)), cfn)
	var resin := NodeVisuals.Merger.new()
	for i in 7:
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.6, 3.2)
		var rr := lerpf(0.78, 0.5, y / th) * 1.02
		resin.add(NodeVisuals._sph(0.08, 5, 8), Transform3D(Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(0.6, rng.randf_range(2.0, 3.4), 0.9)), Vector3(cos(a) * rr, y, sin(a) * rr)), RESIN)
	_meshes["sticky_bark"] = bark.commit()
	_meshes["sticky_crown"] = crown.commit()
	_meshes["sticky_resin"] = resin.commit()
	return {"bark": _meshes["sticky_bark"], "crown": _meshes["sticky_crown"], "resin": _meshes["sticky_resin"]}


## A pale moonbell flower (stem + drooping bell), base at y = 0.
static func moonbell_mesh() -> ArrayMesh:
	if _meshes.has("moonbell"):
		return _meshes["moonbell"]
	var m := NodeVisuals.Merger.new()
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		var off := Vector3(cos(a) * 0.12, 0, sin(a) * 0.12)
		var h := 0.42 + float(i) * 0.08
		m.add(NodeVisuals._cyl(0.012, 0.016, h, 4), Transform3D(Basis(), off + Vector3(0, h * 0.5, 0)), SUNFLAX_STEM)
		m.add(NodeVisuals._hemi(0.08, 0.1, 10), Transform3D(Basis(Vector3.RIGHT, PI), off + Vector3(0, h + 0.06, 0)), Color.WHITE)
		m.add(NodeVisuals._hemi(0.05, 0.04, 6), Transform3D(Basis(Vector3.RIGHT, -0.9), off + Vector3(0.05, 0.03, 0.02)), Palette.FOLIAGE)
	var mesh := m.commit()
	_meshes["moonbell"] = mesh
	return mesh


## Day / night materials for the moonbells (the night one glows softly; steady, never flashing).
static func moonbell_material(night: bool) -> Material:
	if night:
		return Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.6, "emission": MOONBELL_GLOW, "emission_energy": 0.9})
	return Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.35})


# --- Build-area guard ---------------------------------------------------------------------------------------

## True when p is inside (or within margin of) the Haven build area or one of its Chapter Two extra regions.
static func in_build_area(p: Vector2, margin: float = 0.0) -> bool:
	var ba: Dictionary = preload("res://data/world_layout.gd").BUILD_AREA
	if p.distance_to(ba["center"]) <= float(ba["radius"]) + margin:
		return true
	for ex in ba.get("extra", []):
		if ex is Dictionary and (ex as Dictionary).has("center"):
			if p.distance_to(ex["center"]) <= float(ex.get("radius", 0.0)) + margin:
				return true
	return false
