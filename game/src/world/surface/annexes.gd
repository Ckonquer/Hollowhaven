extends RefCounted
## Chapter Two additions to Hollowhaven Woods, built AFTER every legacy step of surface_world._ready()
## (surface_world calls Annexes.build(self) right after _build_boundary()). Nothing here touches the
## legacy terrain, vegetation plan, landmark order, spawn hints or zones (docs/ch2/maps/world_areas.md 6c):
## every addition is an explicit node with its own collider, a NEW spawn id and a small NEW zone.
##   1. The Lanternwake waygate (waygate.gd) at Layout.CH2_POINTS["waygate"]: north of the Moonlit Ruin
##      on its outer side, 21 m from the ruin centre (which stays unsafe), 25 m from the ruin_bramblings
##      spawner, 86 m from the Haven, and clear of every legacy vegetation node by its footprint + 2 m
##      (tests/unit/test_flow_ch2_areas.gd checks all of this). Spawn "waygate" stands WAYGATE_SPAWN_OFFSET
##      (5.8 m) south of it, facing home, far enough out that the arrival camera frames her in front of the arch
##      instead of sitting under its lintel (tests/unit/test_camera_spawn_clearance.gd); a small safe zone
##      "ch2_waygate" centred halfway between them (never containing a landmark centre) covers both, and the grass
##      is thinned around the gate and around that centre. It is a helper zone, not a map landmark
##      (mark_helper_zone): entering it is no discovery (CH2-010).
##   2. Optional annex scripts (ANNEX_SCRIPTS): each, if the file exists, is a script with
##      `static func build(area: Node3D) -> void` (Chapter One extras owned by other modules).
##   3. Chapter Two story dressings (STORY_SCRIPTS, same contract and the same safe loader, run after the eight
##      Chapter One slots): the Haven's Lanternwake keepsake (story_ch2/haven_dressing.gd), which builds nothing
##      until chapter_two_complete and so returns on every load of a finished save. Kept apart from the
##      ANNEX_SCRIPTS slots, whose count/order other suites pin; nothing here touches legacy vegetation.
##   4. Fallback spawns "annex_door" / "annex_hatch" (Tobin's side door, spec §1) if no annex script
##      registered them: the legacy mine-mouth spawns, so travel from tobin_annex always lands safely.

const Layout := preload("res://data/world_layout.gd")
const WaygateScript := preload("res://src/world/surface/waygate.gd")

const ANNEX_SCRIPTS := [
	"res://src/world/surface/c1x/tobin_door.gd",
	"res://src/world/surface/c1x/tailor_cache.gd",
	"res://src/world/surface/c1x/bramblewatch.gd",
	"res://src/world/surface/c1x/meadow_patch.gd",
	"res://src/world/surface/c1x/sap_stumps.gd",
	"res://src/world/surface/c1x/courage_lantern.gd",
	"res://src/world/surface/c1x/moth_pocket.gd",
	"res://src/world/surface/c1x/seasonal_decor.gd",
]
## Chapter Two story dressings built by the same loader after ANNEX_SCRIPTS (static build(area); idempotent).
const STORY_SCRIPTS := [
	"res://src/world/story_ch2/haven_dressing.gd",
]

const WAYGATE_SPAWN := "waygate"
const WAYGATE_ZONE := "ch2_waygate"
const WAYGATE_SPAWN_OFFSET := 5.8      # metres south of the gate (the zone centre sits at half of it)
const WAYGATE_SAFE_RADIUS := 4.5
## Zone-entry key read by Game.is_landmark_zone (Game.ZONE_LANDMARK_KEY): false = a helper zone, never a discovery.
const HELPER_ZONE_KEY := "landmark"
## Spawn id -> legacy spawn whose transform is used when no annex script registered it.
const FALLBACK_SPAWNS := {"annex_door": "mine_exit", "annex_hatch": "mine_threshold"}


static func build(area: Node3D) -> void:
	if area == null:
		return
	build_waygate(area)
	for path in all_scripts():
		_run_annex(area, String(path))
	_ensure_fallback_spawns(area)


## Every optional script the loader runs, in order: the Chapter One slots, then the story dressings.
static func all_scripts() -> Array:
	var out: Array = ANNEX_SCRIPTS.duplicate()
	out.append_array(STORY_SCRIPTS)
	return out


## Clears grass under annex footprints. surface_world calls this BEFORE Grass is built (after the
## vegetation plan, so legacy ids are unaffected). Annex scripts may expose
## `static func grass_clearings() -> Array` returning [[Vector2 centre, float radius], ...].
static func clear_grass(terrain: RefCounted) -> void:
	if terrain == null or not terrain.has_method("clear_grass"):
		return
	var wp := waygate_site()
	terrain.clear_grass(wp.x, wp.y, WAYGATE_SAFE_RADIUS)
	var zc := waygate_zone_centre()
	terrain.clear_grass(zc.x, zc.y, WAYGATE_SAFE_RADIUS)      # the arrival spot and the walk up to the arch
	for path in all_scripts():
		if not ResourceLoader.exists(String(path)):
			continue
		var s: Script = load(String(path))
		if s == null or not s.can_instantiate():
			continue
		var names: Array = []
		for m in s.get_script_method_list():
			names.append(String(m.get("name", "")))
		if not names.has("grass_clearings"):
			continue
		var list: Variant = s.call("grass_clearings")
		if list is Array:
			for c in list:
				if c is Array and c.size() >= 2 and c[0] is Vector2:
					terrain.clear_grass(c[0].x, c[0].y, float(c[1]))


static func waygate_site() -> Vector2:
	return Layout.CH2_POINTS["waygate"]


## Where the "waygate" spawn stands (XZ): WAYGATE_SPAWN_OFFSET south of the gate.
static func waygate_spawn_site() -> Vector2:
	return waygate_site() + Vector2(0.0, WAYGATE_SPAWN_OFFSET)


## Centre of the "ch2_waygate" safe zone (XZ): halfway between the gate and its spawn, so both stand inside it.
static func waygate_zone_centre() -> Vector2:
	return waygate_site() + Vector2(0.0, WAYGATE_SPAWN_OFFSET * 0.5)


static func _height(area: Node, p: Vector2) -> float:
	if area.has_method("height_at"):
		return float(area.height_at(p.x, p.y))
	return 0.0


static func build_waygate(area: Node3D) -> Node3D:
	var p := waygate_site()
	var gate: Node3D = WaygateScript.new()
	gate.setup({"side": "surface", "target_area": "hallowmere_reach", "target_spawn": "waygate_arrival"})
	area.add_child(gate)
	# The stones stand east-west; the arch opens toward the ruin and the Haven (south).
	gate.position = Vector3(p.x, _height(area, p) - 0.05, p.y)
	gate.rotation.y = 0.0
	var sp := waygate_spawn_site()
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(sp.x, _height(area, sp) + 0.08, sp.y))   # facing south, toward home
	_register(area, WAYGATE_SPAWN, xf)
	var zc := waygate_zone_centre()
	area.add_zone(WAYGATE_ZONE, Vector3(zc.x, _height(area, zc), zc.y), WAYGATE_SAFE_RADIUS, true)
	mark_helper_zone(area, WAYGATE_ZONE)
	return gate


## Marks zone `zone_id` of `area` as a helper zone (CH2-010): it still answers get_zone_at / is_safe_zone, but it is
## no map landmark, so entering it is never a discovery (Game.is_landmark_zone reads HELPER_ZONE_KEY = false on its
## `zones` entry). The waygate's 4.5 m safe circle is one: the landmarks are data/world_layout.gd LANDMARKS.
static func mark_helper_zone(area: Node, zone_id: String) -> void:
	var zs: Variant = area.get("zones") if area != null else null
	if not (zs is Array):
		return
	for e in zs:
		if e is Dictionary and String((e as Dictionary).get("id", "")) == zone_id:
			(e as Dictionary)[HELPER_ZONE_KEY] = false


static func _register(area: Node3D, spawn_id: String, xf: Transform3D) -> void:
	area.register_spawn(spawn_id, xf)
	var markers := area.get_node_or_null("SpawnPoints")
	if markers != null:
		var m := Marker3D.new()
		m.name = "Spawn_" + spawn_id
		markers.add_child(m)
		m.transform = xf


static func _run_annex(area: Node3D, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var s: Variant = load(path)
	if not (s is Script) or not (s as Script).can_instantiate():
		push_warning("Annexes: %s failed to load; skipped" % path)
		return
	if not (s as Script).has_method("build"):
		push_warning("Annexes: %s has no static build(area); skipped" % path)
		return
	(s as Script).call("build", area)


static func _ensure_fallback_spawns(area: Node3D) -> void:
	var spawns: Variant = area.get("spawns")
	if not (spawns is Dictionary):
		return
	for id in FALLBACK_SPAWNS:
		var legacy := String(FALLBACK_SPAWNS[id])
		if not (spawns as Dictionary).has(id) and (spawns as Dictionary).has(legacy):
			_register(area, String(id), (spawns as Dictionary)[legacy])
