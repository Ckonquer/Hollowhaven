extends RefCounted
## Ashbell Quarry - Hallowmere Reach east district (module C3). The docs/CHAPTER_TWO_SPEC.md §10 district
## interface, loaded by src/world/reach/reach_districts.gd:
##   footprints() -> [[Vector2 centre, float radius]]   keep generic vegetation / grass off the quarry
##   shape_terrain(terrain)                              copper-red terraces, ramps, the upper shelf and its cliff
##                                                       (strictly inside the hr_quarry circle; deterministic)
##   build(area)                                         everything else (src/world/reach/east/quarry_builder.gd)
## Content (MP §9 / §11 step 6 / §12 / §16): lower iron terraces (renewable hr_iron_*, any pickaxe, slower with
## stone), the repairable mineral winch (flag ch2_winch_repaired) lowering the gangway to the upper shelf,
## renewable Moon Crystal seams there (hr_mooncrystal_*, Ironwood pickaxe or better), the Quarry Warden arena
## (pillars with crack/reset, spawner hr_sp_quarry_warden -> hr_warden_defeated), the Bellcap Sentry pocket
## (hr_sp_bellcaps), the quarry lamp (ch2_found_quarry_lamp / ch2_quarry_lamp_lit) and the quarry log
## (lore_ch2_quarry_log). Data: data/reach_east.gd. Music is automatic (zone hr_quarry); nothing here plays music.
## Extra (optional) hooks: district_root(area) -> the built root node (tests / QA), shape_report() -> Dictionary,
## builder_script() -> the builder (loaded once), warm_up(), enemy_ids(), collect_enemy_scripts(), and the QA
## timings builder_wait_ms / enemy_wait_ms.
##
## Load time: this entry script only preloads the data file and the small terrain shaper. The builder and its
## set-piece scripts (GDScript compiles each one's dependency interfaces again, ~0.25 s cold) are requested on a
## loader thread as soon as the region asks for footprints(), so they compile while the region generates its
## terrain; build() picks them up (or loads them synchronously when nothing was requested, e.g. in tests).
## The quarry's enemy scripts (the spawners' ids, resolved through EnemyFactory; ~0.2-0.3 s cold incl. enemy_base)
## are warmed the same way, so the spawners' first availability check after arrival never compiles them on the
## main thread during the fade-in.

const Q := preload("res://data/reach_east.gd")
const Shape := preload("res://src/world/reach/east/quarry_shape.gd")
const BUILDER_PATH := "res://src/world/reach/east/quarry_builder.gd"
const FACTORY_PATH := "res://src/enemies/enemy_factory.gd"

static var _requested := false
static var _enemy_requests: Array = []
## Milliseconds the last build() spent getting the builder script (0 when the loader thread was done; QA).
static var builder_wait_ms := 0.0
## Milliseconds the last build() spent collecting the warmed enemy scripts (QA).
static var enemy_wait_ms := 0.0


static func footprints() -> Array:
	warm_up()
	return [[Q.CENTER, Q.RADIUS]]


static func shape_terrain(terrain) -> void:
	if not (terrain is Object):
		push_warning("Ashbell Quarry: shape_terrain needs the terrain object")
		return
	Shape.apply(terrain)


static func build(area: Node3D) -> void:
	if area == null or not is_instance_valid(area):
		return
	var t0 := Time.get_ticks_usec()
	var b := builder_script()
	builder_wait_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if b == null:
		push_warning("Ashbell Quarry: the district builder failed to load; the quarry stays bare")
		collect_enemy_scripts()
		return
	b.call("build", area)
	collect_enemy_scripts()


## Starts compiling the builder (and the quarry's enemy scripts) on loader threads (each a no-op when it is
## loaded or already requested).
static func warm_up() -> void:
	# The enemy requests first: they resolve paths through EnemyFactory, loaded here on the main thread BEFORE any
	# worker (the builder's spawner script preloads it too) could be compiling it.
	_warm_enemy_scripts()
	if _requested or ResourceLoader.has_cached(BUILDER_PATH):
		return
	if ResourceLoader.load_threaded_request(BUILDER_PATH, "", false) == OK:
		_requested = true


static func _warm_enemy_scripts() -> void:
	if not _enemy_requests.is_empty() or not ResourceLoader.exists(FACTORY_PATH):
		return
	var f: Variant = load(FACTORY_PATH)
	if not (f is Script) or not (f as Script).can_instantiate():
		return
	for id in enemy_ids():
		var path := String((f as Script).call("script_path", id))
		if path == "" or _enemy_requests.has(path) or ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", false) == OK:
			_enemy_requests.append(path)


## The enemy ids the quarry's spawners use (data/reach_east.gd SPAWNERS).
static func enemy_ids() -> Array:
	var out: Array = []
	for sid in Q.SPAWNERS:
		var id := String(Q.SPAWNERS[sid]["enemy"])
		if not out.has(id):
			out.append(id)
	return out


## Finishes the enemy-script requests of warm_up() (waits only if a loader thread is still compiling one). The
## scripts stay in the engine's script cache afterwards, so EnemyFactory finds them without compiling.
static func collect_enemy_scripts() -> void:
	var t0 := Time.get_ticks_usec()
	for path in _enemy_requests:
		if ResourceLoader.load_threaded_get_status(String(path)) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_get(String(path))
	_enemy_requests.clear()
	enemy_wait_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## The builder script: the threaded request's result when there is one, else a normal (cached) load.
static func builder_script() -> Script:
	if _requested:
		_requested = false
		if ResourceLoader.load_threaded_get_status(BUILDER_PATH) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var r: Variant = ResourceLoader.load_threaded_get(BUILDER_PATH)
			if r is Script and (r as Script).can_instantiate():
				return r
	var s: Variant = load(BUILDER_PATH)
	if s is Script and (s as Script).can_instantiate():
		return s
	return null


## The district root built under `area` (null if build() has not run there).
static func district_root(area: Node) -> Node3D:
	if area == null:
		return null
	return area.get_node_or_null("AshbellQuarry") as Node3D


static func shape_report() -> Dictionary:
	return Shape.last_report
