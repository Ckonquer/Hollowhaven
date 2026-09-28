extends RefCounted
## Loader for the Hallowmere Reach districts (docs/CHAPTER_TWO_SPEC.md §10). Each district script lives at
## res://src/world/reach/districts/<id>.gd (other modules) and may define:
##   static func footprints() -> Array          [[Vector2 centre, float radius], ...] kept clear of generic
##                                              vegetation and grass
##   static func shape_terrain(terrain) -> void heightfield edits strictly inside its own landmark circle,
##                                              before meshes / collision are built (deterministic)
##   static func build(area: Node3D) -> void    called after the base region exists
## Every script is safe-loaded: a missing or broken file is skipped (a warning, never a crash) and the base
## region stays complete. Call order used by reach_world.gd:
##   load_all() -> footprints() -> terrain.generate_base() -> shape_all(terrain) -> terrain.finish()
##   -> (vegetation, grass, meshes, set pieces) -> build_all(area)
## shape_all() enforces the "strictly inside its own landmark radius" rule: each district runs with the
## terrain's shaping limit set to its landmark circle, and afterwards every height / water / path sample
## outside that circle is restored from a snapshot taken just before the call.
##
## Load time (R110): the district scripts (and everything they preload: controllers, builders, data) are compiled
## on loader threads, like quarry.gd's warm_up(): warm_up(entries) first loads the shared enemy factory on the
## MAIN thread (district scripts / builders preload it and quarry.gd loads it on the main thread, so no worker may
## be compiling it then), then requests every district script that is not cached with
## ResourceLoader.load_threaded_request. load_all() calls warm_up() itself and then collects each result in ORDER
## (waiting only while a loader thread is still busy), with a plain load() fallback when a request could not be
## made or returned no script. Measured (cold, headless): the engine compiles GDScript one script at a time, so
## requesting and collecting at once inside load_all() saves little (~750-800 ms either way); the real gain comes
## from calling warm_up() EARLIER (e.g. Game's area prefetch at the start of the travel fade): after a 1 s
## head start load_all() waited 1.5 ms in total and no frame took longer than ~17 ms meanwhile.

const Reach := preload("res://data/hallowmere_layout.gd")
const TerrainScript := preload("res://src/world/reach/reach_terrain.gd")
## Loaded on the main thread before any district script is requested on a loader thread (see header).
const FACTORY_PATH := "res://src/enemies/enemy_factory.gd"

const ORDER := ["orchard", "pools", "candleyard", "quarry", "manor_grounds"]
const DISTRICTS := {
	"orchard": {"path": "res://src/world/reach/districts/orchard.gd", "landmark": "hr_orchard"},
	"pools": {"path": "res://src/world/reach/districts/pools.gd", "landmark": "hr_pools"},
	"candleyard": {"path": "res://src/world/reach/districts/candleyard.gd", "landmark": "hr_candleyard"},
	"quarry": {"path": "res://src/world/reach/districts/quarry.gd", "landmark": "hr_quarry"},
	"manor_grounds": {"path": "res://src/world/reach/districts/manor_grounds.gd", "landmark": "hr_manor_grounds"},
}


## The default table: [{id, path, landmark}] in ORDER.
static func default_entries() -> Array:
	var out: Array = []
	for id in ORDER:
		var d: Dictionary = DISTRICTS[id]
		out.append({"id": String(id), "path": String(d["path"]), "landmark": String(d["landmark"])})
	return out


## Milliseconds the MAIN thread spent on each district script in the last load_all() (waiting for its loader
## thread, or compiling it itself on the plain-load fallback).
static var load_ms: Dictionary = {}
## How each district script arrived in the last load_all(): "thread" (compiled on a loader thread), "cached"
## (already loaded) or "sync" (plain load on the main thread: the fallback).
static var load_mode: Dictionary = {}
## Paths warm_up() requested on loader threads that load_all() has not collected yet (path -> true).
static var _requests: Dictionary = {}


## Starts compiling the district scripts on loader threads (no-op for a script that is cached, already
## requested or missing). The shared enemy factory is loaded on the main thread first (see header). Returns
## the number of new requests. entries = [] means default_entries().
static func warm_up(entries: Array = []) -> int:
	var list: Array = entries if not entries.is_empty() else default_entries()
	_load_shared_on_main_thread()
	var n := 0
	for e in list:
		if not (e is Dictionary):
			continue
		var path := String((e as Dictionary).get("path", ""))
		if path == "" or _requests.has(path) or ResourceLoader.has_cached(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path, "", false) == OK:
			_requests[path] = true
			n += 1
	return n


## True while warm_up() requests are waiting to be collected by load_all() (tests / QA).
static func has_pending_requests() -> bool:
	return not _requests.is_empty()


static func _load_shared_on_main_thread() -> void:
	if ResourceLoader.has_cached(FACTORY_PATH) or not ResourceLoader.exists(FACTORY_PATH):
		return
	load(FACTORY_PATH)


## One district script: the loader thread's result when warm_up() requested it, else a plain (cached or
## synchronous) load. Returns [script_or_null, mode].
static func _collect(path: String) -> Array:
	if _requests.has(path):
		_requests.erase(path)
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var r: Variant = ResourceLoader.load_threaded_get(path)
			if r is Script:
				return [r, "thread"]
	var mode := "cached" if ResourceLoader.has_cached(path) else "sync"
	return [load(path), mode]


## Loads every district script that exists and compiles: [{id, landmark, script, methods, path}] (order kept).
## The scripts compile on loader threads (warm_up) and are collected here in order.
static func load_all(entries: Array) -> Array:
	var out: Array = []
	load_ms = {}
	load_mode = {}
	if entries.is_empty():
		return out
	warm_up(entries)
	for e in entries:
		if not (e is Dictionary):
			continue
		var path := String((e as Dictionary).get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var id := String((e as Dictionary).get("id", path.get_file().get_basename()))
		var t0 := Time.get_ticks_usec()
		var got := _collect(path)
		var s: Variant = got[0]
		load_ms[id] = float(Time.get_ticks_usec() - t0) / 1000.0
		load_mode[id] = String(got[1])
		if not (s is Script) or not (s as Script).can_instantiate():
			push_warning("ReachDistricts: %s failed to load; the base region is built without it" % path)
			continue
		var names: Dictionary = {}
		for m in (s as Script).get_script_method_list():
			names[String(m.get("name", ""))] = true
		out.append({"id": id, "landmark": String((e as Dictionary).get("landmark", "")),
			"script": s, "methods": names, "path": path})
	return out


static func _has(d: Dictionary, method: String) -> bool:
	return (d["methods"] as Dictionary).has(method)


## Every footprint of every loaded district, validated: [[Vector2, float], ...].
static func footprints(loaded: Array) -> Array:
	var out: Array = []
	for d in loaded:
		if not _has(d, "footprints"):
			continue
		var list: Variant = (d["script"] as Script).call("footprints")
		if not (list is Array):
			push_warning("ReachDistricts: %s footprints() did not return an Array" % d["path"])
			continue
		for f in list:
			if f is Array and (f as Array).size() >= 2 and f[0] is Vector2 and (f[1] is float or f[1] is int):
				out.append([f[0], maxf(float(f[1]), 0.0)])
	return out


static func landmark_circle(landmark: String) -> Vector3:
	var l: Dictionary = Reach.LANDMARKS.get(landmark, {})
	if l.is_empty():
		return Vector3(0.0, 0.0, 0.0)
	var p: Vector2 = l["pos"]
	return Vector3(p.x, p.y, float(l["radius"]))


## Runs every district's shape_terrain(terrain) inside its landmark circle (see header).
static func shape_all(terrain: RefCounted, loaded: Array) -> void:
	for d in loaded:
		if not _has(d, "shape_terrain"):
			continue
		var circle := landmark_circle(String(d["landmark"]))
		if circle.z <= 0.0:
			push_warning("ReachDistricts: %s has no landmark circle; shape_terrain skipped" % d["path"])
			continue
		shape_one(terrain, d["script"], circle)


## One district's shaping with the snapshot/restore guard. circle = Vector3(cx, cz, radius).
static func shape_one(terrain: RefCounted, script: Script, circle: Vector3) -> void:
	var h0: PackedFloat32Array = terrain.h.duplicate()
	var w0: PackedFloat32Array = terrain.water.duplicate()
	var p0: PackedFloat32Array = terrain.path_w.duplicate()
	terrain.limit = circle
	script.call("shape_terrain", terrain)
	terrain.limit = Vector3(0.0, 0.0, -1.0)
	# Keep the district's result only inside its circle.
	var h1: PackedFloat32Array = terrain.h
	var w1: PackedFloat32Array = terrain.water
	var p1: PackedFloat32Array = terrain.path_w
	if h1.size() != h0.size() or w1.size() != w0.size() or p1.size() != p0.size():
		push_warning("ReachDistricts: shape_terrain resized the terrain arrays; its edits are discarded")
		terrain.h = h0
		terrain.water = w0
		terrain.path_w = p0
		return
	var nx: int = TerrainScript.NX
	var nz: int = TerrainScript.NZ
	var hx: float = TerrainScript.HALF_X
	var hz: float = TerrainScript.HALF_Z
	var c := Vector2(circle.x, circle.y)
	var r := circle.z
	var i0 := clampi(int(floor(c.x - r + hx)), 0, nx - 1)
	var i1 := clampi(int(ceil(c.x + r + hx)), 0, nx - 1)
	var j0 := clampi(int(floor(c.y - r + hz)), 0, nz - 1)
	var j1 := clampi(int(ceil(c.y + r + hz)), 0, nz - 1)
	for j in range(j0, j1 + 1):
		var z := float(j) - hz
		for i in range(i0, i1 + 1):
			var x := float(i) - hx
			if Vector2(x - c.x, z - c.y).length() > r:
				continue
			var k := j * nx + i
			var hv: float = h1[k]
			if is_nan(hv) or is_inf(hv):
				continue
			h0[k] = hv
			w0[k] = w1[k]
			p0[k] = clampf(p1[k], 0.0, 1.0)
	terrain.h = h0
	terrain.water = w0
	terrain.path_w = p0


## Calls every district's build(area) after the base region exists.
static func build_all(area: Node3D, loaded: Array) -> Array:
	var built: Array = []
	for d in loaded:
		if not _has(d, "build"):
			continue
		(d["script"] as Script).call("build", area)
		built.append(String(d["id"]))
	return built
