extends "res://src/world/area_base.gd"
## Hallowmere Reach (area "hallowmere_reach", docs/CHAPTER_TWO_SPEC.md §1, §7.2, §10; MP §9): a permanently
## autumnal ~280 x 220 m region. Every coordinate comes from data/hallowmere_layout.gd, so saves made on the
## wave A stand-in line up. Build order (all synchronous in _ready, behind the load fade):
##   1. district scripts safe-loaded (reach_districts.gd) and their footprints collected
##   2. terrain: base -> each district's shape_terrain (inside its landmark circle) -> finish
##   3. sky (plum twilight grade, amber sun), terrain meshes + collision, Thimblebrook + still water
##   4. vegetation plan (stable hr_* ids, clear of footprints / roads / plazas) and grass
##   5. set pieces: roads & signposts, road lights, Lanternwake Commons, the Conservatory, the Sunken
##      Bellhouse, the five Lantern Road arches, the mirror waygate home, the refuge hatch
##   6. spawns, zones (hr_* landmarks; safe: Commons, Conservatory, every arch, the arrival), boundary walls
##   7. each district's build(area), then a fallback manor door if no district registered one
##   8. the story module's festival dressing (safe-loaded, flag-derived), the built-structure grass mask
## Public API (area_base + surface-compatible): height_at(x, z), surface_at(pos), water_level_at(x, z),
## is_inside_bounds(pos, margin), validate_position(pos), get_zone_at(pos), is_safe_zone(pos),
## on_player_spawned(player); vars: terrain, sky, water, vegetation, commons, conservatory, bellhouse,
## road_lights, arches {id: node}, waygate, refuge_hatch, markers (hi-vis), story_dressing, exits {name: node},
## districts (loaded), district_nodes, build_times.
## For districts (spec §10): ground(p, dy), add_resource(params, pos), add_box_collider(xf, size, surface),
## register_exit(name, node), add_exit(name, params, pos, yaw) (placeholder-compatible), place_spawn(id, pos,
## yaw), add_safe_spot(center, radius), register_spawn, add_zone (sub-zones that never contain a landmark).
## Areas never touch the music (the director follows Game.area_id / zone_id); ambience uses existing sounds.

const Reach := preload("res://data/hallowmere_layout.gd")
const TerrainScript := preload("res://src/world/reach/reach_terrain.gd")
const Districts := preload("res://src/world/reach/reach_districts.gd")
const SkyScript := preload("res://src/world/surface/sky.gd")
const TerrainBody := preload("res://src/world/surface/terrain_body.gd")
const TERRAIN_SHADER := preload("res://shaders/surface_terrain.gdshader")
const WaterScript := preload("res://src/world/reach/reach_water.gd")
const VegetationScript := preload("res://src/world/reach/reach_vegetation.gd")
const GrassScript := preload("res://src/world/surface/grass.gd")
const RoadsScript := preload("res://src/world/reach/reach_roads.gd")
const RoadLightsScript := preload("res://src/world/reach/road_lights.gd")
const CommonsScript := preload("res://src/world/reach/commons.gd")
const ConservatoryScript := preload("res://src/world/reach/conservatory.gd")
const BellhouseScript := preload("res://src/world/reach/bellhouse.gd")
const HatchScript := preload("res://src/world/reach/reach_hatch.gd")
const MarkersScript := preload("res://src/world/reach/reach_markers.gd")
const ArchScript := preload("res://src/world/common/lantern_arch.gd")
const WaygateScript := preload("res://src/world/surface/waygate.gd")
const AreaExit := preload("res://src/world/areas_ch2/area_exit.gd")
const ResourceNode := preload("res://src/world/common/resource_node.gd")

const SPAWN_LIFT := 0.08
const ORIGIN := Vector2(-160.0, -128.0)
const SAMPLES := Vector2(321.0, 257.0)
## Sky grade: a plum cast over sky / fog / ambient, and an amber autumn sun (sky.gd tint, default no-op).
const SKY_TINT := Color(1.07, 0.87, 1.02, 0.6)
const SUN_TINT := Color(1.0, 0.72, 0.4, 0.35)
const REFUGE_FLAG := "ch2_refuge_shortcut"
## Story module C9's region dressing (optional; see _build_story_dressing).
const STORY_DRESSING := "res://src/world/story_ch2/reach_dressing.gd"

var placeholder := false
var terrain: RefCounted
var terrain_material: ShaderMaterial
var sky: Node
var water: Node3D
var vegetation: Node3D
var grass: Node3D
var roads: Node3D
var road_lights: Node3D
var commons: Node3D
var conservatory: Node3D
var bellhouse: Node3D
var arches: Dictionary = {}          # arch id -> lantern_arch node
var waygate: Node3D = null
var refuge_hatch: Node3D = null
var markers: Node3D = null         # reach_markers.gd (high-visibility wayfinding markers)
var exits: Dictionary = {}           # name -> exit node (manor_door, bellhouse_stair, refuge_hatch, ...)
var safe_spots: Array = []           # [{center: Vector3, radius: float}] safe circles that are not zones
var district_entries: Array = []     # [{id, path, landmark}] (tests may replace before add_child)
var districts: Array = []            # loaded district scripts (reach_districts.gd load_all)
var district_footprints: Array = []
var districts_built: Array = []
var district_nodes: Dictionary = {}  # resource nodes added by districts through add_resource
var build_times: Dictionary = {}
var story_dressing: Node = null      # story module C9's dressing root (null when that module is absent)
var story_dressing_path: String = STORY_DRESSING   # tests may point it elsewhere before add_child
var structure_mask: Image
var structure_mask_tex: ImageTexture
var _t_last := 0
var _tick := 0.0
var _audio_started := false
var _was_night := false
var _props_body: StaticBody3D


func _ready() -> void:
	area_id = Reach.AREA_ID
	_t_last = Time.get_ticks_usec()
	var t_start := _t_last
	if district_entries.is_empty():
		district_entries = Districts.default_entries()
	districts = Districts.load_all(district_entries)
	build_times["district_scripts"] = Districts.load_ms.duplicate()
	district_footprints = Districts.footprints(districts)
	_mark("districts_load")
	terrain = TerrainScript.new()
	terrain.generate_base()
	Districts.shape_all(terrain, districts)
	terrain.finish()
	_mark("terrain_gen")
	build_times["terrain_detail"] = terrain.times
	sky = SkyScript.new()
	sky.set("tint", SKY_TINT)
	sky.set("sun_tint", SUN_TINT)
	add_child(sky)
	var ground := Node3D.new()
	ground.name = "Terrain"
	add_child(ground)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	terrain_material.set_shader_parameter("splat_tex", ImageTexture.create_from_image(terrain.splat_image()))
	terrain_material.set_shader_parameter("terrain_origin", ORIGIN)
	terrain_material.set_shader_parameter("terrain_samples", SAMPLES)
	terrain_material.set_shader_parameter("path_color", Color("c9a06e"))
	terrain_material.set_shader_parameter("path_edge_color", Color("9a7350"))
	terrain_material.set_shader_parameter("sand_color", Color("d6c08f"))
	terrain_material.set_shader_parameter("wet_color", Color("8f7c5a"))
	terrain_material.set_shader_parameter("rock_color", Color("aa9d90"))
	terrain_material.set_shader_parameter("rock_dark", Color("7d726c"))
	terrain.build_meshes(ground, terrain_material)
	var body: StaticBody3D = terrain.build_collision(ground, TerrainBody)
	body.set("area", self)
	_mark("terrain_mesh")
	water = WaterScript.new()
	water.terrain = terrain
	add_child(water)
	_mark("water")
	var plan: Dictionary = VegetationScript.plan(terrain, district_footprints)
	_mark("veg_plan")
	VegetationScript.clear_grass_for(terrain, plan)
	_clear_set_piece_grass()
	vegetation = VegetationScript.new()
	vegetation.terrain = terrain
	vegetation.plan_data = plan
	add_child(vegetation)
	_mark("vegetation")
	build_times["veg_detail"] = vegetation.build_times
	grass = GrassScript.new()
	grass.terrain = terrain
	add_child(grass)
	grass.grass_material.set_shader_parameter("terrain_origin", ORIGIN)
	grass.grass_material.set_shader_parameter("terrain_samples", SAMPLES)
	grass.grass_material.set_shader_parameter("tip_warm", Color("e8b860"))
	_mark("grass")
	_props_body = StaticBody3D.new()
	_props_body.name = "DistrictProps"
	_props_body.collision_layer = 1
	_props_body.collision_mask = 0
	_props_body.set_meta("surface", "stone")
	add_child(_props_body)
	roads = RoadsScript.new()
	roads.terrain = terrain
	add_child(roads)
	road_lights = RoadLightsScript.new()
	road_lights.terrain = terrain
	add_child(road_lights)
	commons = CommonsScript.new()
	commons.terrain = terrain
	add_child(commons)
	_mark("commons")
	conservatory = ConservatoryScript.new()
	conservatory.terrain = terrain
	add_child(conservatory)
	conservatory.pedestal.road_lights = road_lights
	bellhouse = BellhouseScript.new()
	bellhouse.terrain = terrain
	add_child(bellhouse)
	register_exit("bellhouse_stair", bellhouse.descent)
	_mark("set_pieces")
	_build_arches()
	_build_waygate()
	_build_hatch()
	_build_markers()
	_register_spawns()
	_add_zones()
	_build_boundary()
	_mark("spawns")
	districts_built = Districts.build_all(self, districts)
	_ensure_manor_door()
	_mark("districts_build")
	story_dressing = _build_story_dressing()
	_mark("story_dressing")
	_setup_structure_mask()
	_update_daylight()
	build_times["total"] = float(Time.get_ticks_usec() - t_start) / 1000.0
	# the region's own share (district script loading / builds and the story dressing belong to other modules)
	build_times["base_total"] = float(build_times["total"]) - float(build_times.get("districts_load", 0.0)) \
		- float(build_times.get("districts_build", 0.0)) - float(build_times.get("story_dressing", 0.0))
	if OS.is_debug_build():
		print("ReachWorld: built in %.0f ms %s" % [build_times["total"], str(build_times)])


func _mark(label: String) -> void:
	var now := Time.get_ticks_usec()
	build_times[label] = float(now - _t_last) / 1000.0
	_t_last = now


## Grass off under set pieces (stall floors, the Conservatory floor, the forecourt) and district footprints.
func _clear_set_piece_grass() -> void:
	for s in Reach.COMMONS["stalls"]:
		terrain.clear_grass(s[0].x, s[0].y, 2.2)
	var cc: Vector2 = Reach.CONSERVATORY["center"]
	terrain.clear_grass(cc.x, cc.y, 7.2)
	var fc: Vector2 = Reach.BELLHOUSE["forecourt"]
	terrain.clear_grass(fc.x, fc.y, 6.0)
	terrain.clear_grass(Reach.POINTS["refuge_hatch"].x, Reach.POINTS["refuge_hatch"].y, 1.8)
	for f in district_footprints:
		terrain.clear_grass(f[0].x, f[0].y, float(f[1]))


# --- Arches, the waygate home, the refuge hatch --------------------------------------------------------------

func _build_arches() -> void:
	for id in Reach.ARCH_ORDER:
		var a: Dictionary = Reach.ARCHES[id]
		var p: Vector2 = a["pos"]
		var lm: Vector2 = Reach.LANDMARKS[String(a["landmark"])]["pos"]
		var arch: Node3D = ArchScript.new()
		arch.setup({"id": id, "area": area_id, "spawn": a["spawn"], "name": a["name"]})
		add_child(arch)
		arch.position = Vector3(p.x, height_at(p.x, p.y) - 0.03, p.y)
		arch.rotation.y = Reach.yaw_towards(p, lm)
		arches[String(id)] = arch
		add_safe_spot(Vector3(p.x, arch.position.y, p.y), Reach.ARCH_SAFE_RADIUS)


## The Reach side of the Lanternwake waygate, just behind the arrival point: always leads home. Its rune
## face looks north, toward the arrival and the festival.
func _build_waygate() -> void:
	var p: Vector2 = Reach.POINTS["mirror_waygate"]
	waygate = WaygateScript.new()
	waygate.setup({"side": "reach", "target_area": "surface", "target_spawn": "waygate"})
	add_child(waygate)
	waygate.position = Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y)
	waygate.rotation.y = PI


func _build_hatch() -> void:
	var p: Vector2 = Reach.POINTS["refuge_hatch"]
	refuge_hatch = HatchScript.new()
	refuge_hatch.setup({"text": "Climb down to the refuge", "target_area": "hushed_works", "target_spawn": "refuge",
		"requires_flag": REFUGE_FLAG, "locked_text": "A heavy iron hatch, bolted from below.", "style": "hatch"})
	add_child(refuge_hatch)
	refuge_hatch.position = Vector3(p.x, height_at(p.x, p.y) - 0.02, p.y)
	refuge_hatch.rotation.y = Reach.yaw_towards(p, Reach.SPAWNS["refuge_exit"]["pos"])
	refuge_hatch.name = "RefugeHatch"
	register_exit("refuge_hatch", refuge_hatch)


## High-visibility wayfinding (Settings high_visibility_cues): unlit arches, the waygate home, the revealed
## Bellhouse stair and the open refuge hatch each get a bold marker (reach_markers.gd).
func _build_markers() -> void:
	markers = MarkersScript.new()
	add_child(markers)
	for id in Reach.ARCH_ORDER:
		var arch: Node3D = arches.get(String(id))
		if arch == null:
			continue
		var flag := Reach.arch_flag(String(id))
		markers.add_marker("arch_" + String(id), arch.position + Vector3(0, 4.2, 0), func() -> bool: return not bool(GameState.get_flag(flag)))
	if waygate != null:
		markers.add_marker("waygate", waygate.position + Vector3(0, 4.8, 0))
	var sx: float = Reach.BELLHOUSE["stair_x"]
	var tz: float = Reach.BELLHOUSE["ramp_top_z"]
	markers.add_marker("bellhouse_stair", Vector3(sx, height_at(sx, tz + 1.5) + 2.4, tz), func() -> bool: return bool(GameState.get_flag("ch2_lamps_linked")))
	# at the stair bottom: the service gate while it is shut, then the way down in the tower passage
	var sb: float = float(bellhouse.get("bottom")) if bellhouse != null else height_at(sx, tz) - float(Reach.BELLHOUSE["depth"])
	markers.add_marker("service_gate", Vector3(sx, sb + 3.6, float(Reach.BELLHOUSE["gate_z"])), func() -> bool:
		return bool(GameState.get_flag("ch2_lamps_linked")) and not bool(GameState.get_flag("ch2_service_gate_open")))
	markers.add_marker("bellhouse_descent", Vector3(sx, sb + 1.6, float(Reach.BELLHOUSE["descent_z"]) - 0.5), func() -> bool:
		return bool(GameState.get_flag("ch2_lamps_linked")) and bool(GameState.get_flag("ch2_service_gate_open")))
	if refuge_hatch != null:
		markers.add_marker("refuge_hatch", refuge_hatch.position + Vector3(0, 2.0, 0), func() -> bool: return bool(GameState.get_flag(REFUGE_FLAG)))
	markers.refresh()


## The Chapter Two story module's festival dressing (src/world/story_ch2/reach_dressing.gd, module C9: road
## lanterns and the Lanternwake pole after the Choir; derived from flags, idempotent). Safe-loaded and built
## behind the load fade, so nothing pops in after arrival (its tracker only adds it when the region did not).
## A missing or broken script is skipped: the region is complete without it.
func _build_story_dressing() -> Node:
	if story_dressing_path == "" or not ResourceLoader.exists(story_dressing_path):
		return null
	var s: Variant = load(story_dressing_path)
	if not (s is Script) or not (s as Script).can_instantiate():
		return null
	var has_build := false
	for m in (s as Script).get_script_method_list():
		if String(m.get("name", "")) == "build":
			has_build = true
			break
	if not has_build:
		return null
	var node: Variant = (s as Script).call("build", self)
	return node as Node if node is Node else null


## The manor's front door is the manor district's; if none registered one (district missing or older), a
## plain door keeps the manor reachable (spec §1: reach manor door <-> manor manor_entry).
func _ensure_manor_door() -> void:
	if exits.has("manor_door") and is_instance_valid(exits["manor_door"]):
		return
	for n in find_children("*", "Node3D", true, false):
		if n.is_in_group("area_exit") and String(n.get("target_area")) == "moonveil_manor":
			exits["manor_door"] = n
			return
	var door: Vector2 = Reach.POINTS["manor_door"]
	var e: Node3D = AreaExit.new()
	e.setup({"text": "Enter Moonveil Manor", "target_area": "moonveil_manor", "target_spawn": "manor_entry", "style": "door"})
	add_child(e)
	e.position = Vector3(door.x, height_at(door.x, door.y), door.y)
	e.rotation.y = Reach.yaw_towards(door, Reach.SPAWNS["manor_door"]["pos"]) + PI
	e.name = "Exit_manor_door"
	exits["manor_door"] = e


# --- Spawns, zones, boundary ----------------------------------------------------------------------------------

func _register_spawns() -> void:
	for id in Reach.SPAWNS:
		var s: Dictionary = Reach.SPAWNS[id]
		var p: Vector2 = s["pos"]
		place_spawn(String(id), Vector3(p.x, height_at(p.x, p.y), p.y), Reach.yaw_towards(p, s["look"]))
	var arrival: Vector2 = Reach.POINTS["waygate_arrival"]
	add_safe_spot(Vector3(arrival.x, height_at(arrival.x, arrival.y), arrival.y), Reach.ARRIVAL_SAFE_RADIUS)


func _add_zones() -> void:
	for id in Reach.LANDMARKS:
		var l: Dictionary = Reach.LANDMARKS[id]
		var p: Vector2 = l["pos"]
		add_zone(String(id), Vector3(p.x, height_at(p.x, p.y), p.y), float(l["radius"]), bool(l["safe"]))


## Invisible walls on the rounded rectangle Reach.WALL_HALF_* (the hills and the forest rise behind them).
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var pts := boundary_points()
	for i in pts.size():
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % pts.size()]
		var mid := (p0 + p1) * 0.5
		var seg_len := p0.distance_to(p1) + 0.6
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(seg_len, 70.0, 1.0)
		cs.shape = sh
		var dir := (p1 - p0).normalized()
		cs.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(mid.x, height_at(mid.x, mid.y) + 25.0, mid.y))
		body.add_child(cs)


## The wall outline: straight sides and rounded corners (clockwise).
static func boundary_points() -> Array:
	var hx := Reach.WALL_HALF_X
	var hz := Reach.WALL_HALF_Z
	var r := Reach.WALL_CORNER
	var out: Array = []
	var corners := [[Vector2(hx - r, hz - r), 0.0], [Vector2(-hx + r, hz - r), PI * 0.5], [Vector2(-hx + r, -hz + r), PI], [Vector2(hx - r, -hz + r), PI * 1.5]]
	for c in corners:
		var cc: Vector2 = c[0]
		var a0: float = c[1]
		for k in 7:
			var a := a0 + PI * 0.5 * float(k) / 6.0
			out.append(cc + Vector2(cos(a), sin(a)) * r)
	var dense: Array = []
	for i in out.size():
		var a: Vector2 = out[i]
		var b: Vector2 = out[(i + 1) % out.size()]
		var n := maxi(1, int(ceil(a.distance_to(b) / 20.0)))
		for k in n:
			dense.append(a.lerp(b, float(k) / float(n)))
	return dense


# --- Queries ----------------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0


func water_level_at(x: float, z: float) -> float:
	return terrain.water_level_at(x, z) if terrain != null else -1000.0


func surface_at(pos: Vector3) -> String:
	return terrain.surface_at(pos.x, pos.z) if terrain != null else "grass"


func ground(p: Vector2, dy: float = 0.0) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y) + dy, p.y)


## Inside the rounded-rectangle walls, `margin` metres in.
func is_inside_bounds(pos: Vector3, margin: float = 0.0) -> bool:
	var r := Reach.WALL_CORNER
	var q := Vector2(absf(pos.x) - (Reach.WALL_HALF_X - margin - r), absf(pos.z) - (Reach.WALL_HALF_Z - margin - r))
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
	return outside <= 0.0


func is_safe_zone(pos: Vector3) -> bool:
	if super.is_safe_zone(pos):
		return true
	for s in safe_spots:
		var c: Vector3 = s["center"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s["radius"]):
			return true
	return false


## Saved positions must be on solid ground, inside the walls and not in water deeper than 0.6 m (the brook
## centre, the Bellhouse pond). A bridge deck or stepping stone above the brook is dry footing.
func validate_position(pos: Vector3) -> Variant:
	if not is_inside_bounds(pos, 1.0):
		return null
	var g: Variant = super.validate_position(pos)
	if not (g is Vector3):
		return null
	var gp: Vector3 = g
	if terrain != null and terrain.is_water(gp.x, gp.z):
		var on_crossing: bool = gp.y - 0.1 > float(terrain.height_at(gp.x, gp.z)) + 0.25
		var wl: float = terrain.water_level_at(gp.x, gp.z)
		if not on_crossing and wl - float(terrain.height_at(gp.x, gp.z)) > 0.6:
			return null
	return gp


# --- Helpers for districts and set pieces ------------------------------------------------------------------------

func place_spawn(id: String, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, pos.y + SPAWN_LIFT, pos.z))
	register_spawn(id, xf)
	var spawn_root := get_node_or_null("SpawnPoints")
	if spawn_root == null:
		spawn_root = Node3D.new()
		spawn_root.name = "SpawnPoints"
		add_child(spawn_root)
	var m := spawn_root.get_node_or_null("Spawn_" + id) as Marker3D
	if m == null:
		m = Marker3D.new()
		m.name = "Spawn_" + id
		spawn_root.add_child(m)
	m.transform = xf


func add_safe_spot(center: Vector3, radius: float) -> void:
	safe_spots.append({"center": center, "radius": radius})


func register_exit(exit_name: String, node: Node3D) -> void:
	if node != null:
		exits[exit_name] = node


## Same signature as the placeholder areas: an area_exit.gd door / stair / hatch at pos facing yaw.
func add_exit(exit_name: String, params: Dictionary, pos: Vector3, yaw: float) -> Node3D:
	var e: Node3D = AreaExit.new()
	e.setup(params)
	add_child(e)
	e.position = pos
	e.rotation.y = yaw
	e.name = "Exit_" + exit_name
	exits[exit_name] = e
	return e


## A district harvest node (resource_node.gd): params as ResourceNode.setup (node_id must be hr_<kind>_<n>).
func add_resource(params: Dictionary, pos: Vector3) -> Node3D:
	var holder := get_node_or_null("DistrictResources")
	if holder == null:
		holder = Node3D.new()
		holder.name = "DistrictResources"
		add_child(holder)
	var n: Node3D = ResourceNode.new()
	n.setup(params)
	n.position = pos
	holder.add_child(n)
	var id := String(params.get("node_id", ""))
	if id != "":
		n.name = id
		district_nodes[id] = n
	return n


func add_box_collider(xf: Transform3D, size: Vector3, surface: String = "stone") -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = xf
	if surface == "stone":
		_props_body.add_child(cs)
	else:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", surface)
		add_child(body)
		body.add_child(cs)
	return cs


## Every harvestable id in the region (base vegetation + practice seam + district nodes).
func resource_ids() -> Array:
	var out: Array = VegetationScript.ids(vegetation.plan_data) if vegetation != null else []
	out.append(Reach.PRACTICE_SEAM_ID)
	for id in district_nodes:
		out.append(String(id))
	return out


# --- Built structures hide grass and flowers (the optional Commons outpost) --------------------------------

func _setup_structure_mask() -> void:
	structure_mask = Image.create(TerrainScript.NX, TerrainScript.NZ, false, Image.FORMAT_R8)
	structure_mask_tex = ImageTexture.create_from_image(structure_mask)
	if grass != null:
		grass.grass_material.set_shader_parameter("occ_tex", structure_mask_tex)
	var mats: Array = []
	for mmi in vegetation.flower_nodes:
		if mmi is GeometryInstance3D and (mmi as GeometryInstance3D).material_override != null and not mats.has((mmi as GeometryInstance3D).material_override):
			mats.append((mmi as GeometryInstance3D).material_override)
	for m in mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("occ_tex", structure_mask_tex)
	if not Events.structure_placed.is_connected(_on_structures_changed):
		Events.structure_placed.connect(_on_structures_changed)
		Events.structure_removed.connect(_on_structures_changed)
	rebuild_structure_mask()


func _on_structures_changed(_uid: String, _sid: String) -> void:
	rebuild_structure_mask.call_deferred()


func rebuild_structure_mask() -> void:
	if structure_mask == null:
		return
	structure_mask.fill(Color(0, 0, 0))
	for uid in GameState.structures:
		var st: Dictionary = GameState.structures[uid]
		if String(st.get("area", "surface")) != area_id:
			continue
		var p: Variant = st.get("pos")
		if not (p is Array) or (p as Array).size() != 3:
			continue
		var def: Dictionary = ItemDB.structure(String(st.get("id", "")))
		var sz: Variant = def.get("size", Vector2i(1, 1))
		var ext := 1.0
		if sz is Vector2i:
			ext = float(maxi((sz as Vector2i).x, (sz as Vector2i).y))
		var r := ext * 0.5 + 0.35
		var cx := float(p[0]) + TerrainScript.HALF_X
		var cz := float(p[2]) + TerrainScript.HALF_Z
		for j in range(maxi(0, int(floor(cz - r - 1.0))), mini(TerrainScript.NZ, int(ceil(cz + r + 1.0)) + 1)):
			for i in range(maxi(0, int(floor(cx - r - 1.0))), mini(TerrainScript.NX, int(ceil(cx + r + 1.0)) + 1)):
				if Vector2(float(i) - cx, float(j) - cz).length() <= r + 0.5:
					structure_mask.set_pixel(i, j, Color(1, 0, 0))
	structure_mask_tex.update(structure_mask)


# --- Day, night and ambience (never music) --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	_update_daylight()
	if _audio_started and sky != null:
		var night := bool(sky.get("is_night"))
		if night != _was_night:
			_was_night = night
			Audio.play_ambience("amb_forest_night" if night else "amb_forest_day", 4.0)


func _update_daylight() -> void:
	var dl: float = float(sky.get("daylight")) if sky != null else 1.0
	if commons != null:
		commons.set_daylight(dl)
	if conservatory != null:
		conservatory.set_daylight(dl)


func on_player_spawned(_player: Node3D) -> void:
	_audio_started = true
	_was_night = bool(sky.get("is_night")) if sky != null else false
	Audio.play_ambience("amb_forest_night" if _was_night else "amb_forest_day", 4.0)
