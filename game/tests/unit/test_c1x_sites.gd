extends "res://tests/test_case.gd"
## Module B7 (Chapter One optional surface content): every site in data/c1x_layout.gd is valid against the
## REAL legacy terrain and vegetation plan (pure: no scene is built here). Walkable dry ground, off the paths,
## > 18 m from the Haven, not on a landmark centre / spawn hint / stream crossing, no legacy vegetation node within
## a footprint + 2 m, ids unique and prefixed, spawners new and placed away from the Haven and the peaceful glade.

const L := preload("res://data/c1x_layout.gd")
const Layout := preload("res://data/world_layout.gd")
const Terrain := preload("res://src/world/surface/terrain.gd")
const Vegetation := preload("res://src/world/surface/vegetation.gd")
const EnemiesData := preload("res://data/enemies.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")

const CLEARANCE := 2.0            # legacy vegetation keeps footprint + this far away
const HAVEN_MIN := 18.0
const LEGACY_SPAWNERS := ["ruin_bramblings", "thicket_bramblings", "quarry_bramblings", "gallery_gloom", "hall_gloom"]
const THICKET_SPAWNER := Vector2(-62.0, -46.0)

static var _terrain: RefCounted = null
static var _plan: Dictionary = {}
static var _legacy: Array = []          # [[Vector2, label]]


func _setup() -> void:
	if _terrain != null:
		return
	_terrain = Terrain.new()
	_terrain.generate()
	_plan = Vegetation.plan(_terrain)
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		for e in _plan[k]:
			var p: Vector3 = e["pos"]
			_legacy.append([Vector2(p.x, p.z), String(e["id"])])
	for k in ["decor_trees", "decor_bushes", "mushrooms", "logs", "decor_rocks", "brambles"]:
		for e in _plan[k]:
			for v in e:
				if v is Transform3D:
					var o: Vector3 = (v as Transform3D).origin
					_legacy.append([Vector2(o.x, o.z), "%s@%.1f,%.1f" % [k, o.x, o.z]])


func _nearest_legacy(p: Vector2) -> Array:
	var best := INF
	var label := ""
	for e in _legacy:
		var d: float = p.distance_to(e[0])
		if d < best:
			best = d
			label = String(e[1])
	return [best, label]


## Height spread over the footprint ring (walkable, not a cliff).
func _slope_ok(p: Vector2, r: float, max_rise: float) -> bool:
	var h0: float = _terrain.height_at(p.x, p.y)
	for a in 8:
		var q := p + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * maxf(r, 0.5)
		if absf(float(_terrain.height_at(q.x, q.y)) - h0) > max_rise:
			return false
	return true


func _check_site(id: String, p: Vector2, r: float, opts: Dictionary = {}) -> void:
	assert_false(_terrain.is_water(p.x, p.y), "%s is dry" % id)
	assert_true(_terrain.stream_distance(p.x, p.y) > 4.0 + r, "%s away from the stream" % id)
	assert_true(_terrain.pond_distance(p.x, p.y) > 1.2, "%s not in Mirror Pond" % id)
	assert_true(Vegetation.edge_dist(p) < float(opts.get("edge", 92.0)), "%s inside the woods, not on the hills (edge %.1f)" % [id, Vegetation.edge_dist(p)])
	assert_true(p.length() > HAVEN_MIN + r, "%s is more than 18 m from the Haven (%.1f)" % [id, p.length()])
	# Never where Krystal may build: the legacy circle and every Chapter Two extra region (+ footprint + 2 m).
	assert_false(Common.in_build_area(p, r + CLEARANCE), "%s keeps out of every Haven build region" % id)
	assert_true(_slope_ok(p, r + 0.3, float(opts.get("rise", 0.6))), "%s stands on walkable ground" % id)
	assert_true(float(_terrain.path_at(p.x, p.y)) <= 0.02, "%s is off the dirt paths (%.2f)" % [id, _terrain.path_at(p.x, p.y)])
	var nl := _nearest_legacy(p)
	assert_true(float(nl[0]) > r + CLEARANCE, "%s: legacy %s is %.2f m away (needs > %.2f)" % [id, nl[1], nl[0], r + CLEARANCE])
	for lid in Layout.LANDMARKS:
		var c: Vector2 = Layout.LANDMARKS[lid]["pos"]
		assert_true(p.distance_to(c) > 4.0 + r, "%s is not on the %s landmark centre" % [id, lid])
	for sid in Layout.SPAWN_HINTS:
		assert_true(p.distance_to(Layout.SPAWN_HINTS[sid]) > 3.5 + r, "%s keeps clear of spawn %s" % [id, sid])
	for c in Layout.STREAM_CROSSINGS:
		assert_true(p.distance_to(c) > 6.5, "%s keeps clear of the crossing at %s" % [id, c])


func test_every_footprint_is_on_valid_ground() -> void:
	_setup()
	var n := 0
	for f in L.footprints():
		var opts := {}
		if String(f["kind"]) == "sticky_tree":
			opts = {"edge": 100.0, "rise": 1.1}      # the old tree stands on the first rise of the western hills
		_check_site(String(f["id"]), f["pos"], float(f["radius"]), opts)
		n += 1
	assert_true(n >= 20, "all footprints checked (%d)" % n)


func test_seasonal_pieces_line_the_paths_outside_the_build_area() -> void:
	_setup()
	var fps := L.seasonal_footprints()
	assert_true(fps.size() >= 8 and fps.size() <= 20, "a few seasonal pieces (%d)" % fps.size())
	for f in fps:
		var p: Vector2 = f["pos"]
		_check_site(String(f["id"]), p, float(f["radius"]))
		var bc: Vector2 = Layout.BUILD_AREA["center"]
		assert_true(p.distance_to(bc) > float(Layout.BUILD_AREA["radius"]) + L.SEASONAL_BUILD_MARGIN, "%s outside the Haven build area" % f["id"])
		for ex in Layout.BUILD_AREA.get("extra", []):
			if ex is Dictionary and (ex as Dictionary).has("center"):
				assert_true(p.distance_to(ex["center"]) > float(ex.get("radius", 0.0)) + L.SEASONAL_BUILD_MARGIN, "%s outside the extra build region" % f["id"])
		# Along a path: a dirt path within a few metres.
		var near_path := false
		for a in 16:
			for rr in [2.5, 3.5, 4.5]:
				var q := p + Vector2(cos(a * TAU / 16.0), sin(a * TAU / 16.0)) * float(rr)
				if float(_terrain.path_at(q.x, q.y)) > 0.5:
					near_path = true
		assert_true(near_path, "%s stands beside a path" % f["id"])


func test_ids_are_unique_new_and_prefixed() -> void:
	_setup()
	var ids := L.all_ids()
	var seen := {}
	for id in ids:
		assert_true(String(id).begins_with(L.PREFIX), "%s is prefixed c1x_" % id)
		assert_false(seen.has(id), "%s is unique" % id)
		seen[id] = true
	var legacy_ids := {}
	for e in _legacy:
		legacy_ids[String(e[1])] = true
	for id in ids:
		assert_false(legacy_ids.has(id), "%s is not a legacy id" % id)
	for s in L.spawners():
		var sid := String(s["id"])
		assert_true(sid.begins_with("c1x_sp_"), "spawner %s uses the c1x_sp_ namespace" % sid)
		assert_false(LEGACY_SPAWNERS.has(sid), "spawner %s is new" % sid)
		assert_true(EnemiesData.ENEMIES.has(String(s["enemy"])), "spawner %s spawns a catalogue enemy (%s)" % [sid, s["enemy"]])
	# Persistent node ids follow c1x_<kind>_<n> and carry the data kind's name.
	for s in L.SAP_STUMPS:
		assert_true(String(s["id"]).begins_with("c1x_resin_"), "%s is a resin stump id" % s["id"])
	for s in L.SUNFLAX:
		assert_true(String(s["id"]).begins_with("c1x_sunflax_"), "%s is a sunflax id" % s["id"])
	for s in L.ROSEBERRY:
		assert_true(String(s["id"]).begins_with("c1x_roseberry_"), "%s is a roseberry id" % s["id"])
	# Counts the catalogue asks for on the surface (data/sources.gd NODES min_count).
	assert_true(L.SAP_STUMPS.size() >= 4 and L.SAP_STUMPS.size() <= 6, "4-6 sap stumps")
	assert_true(L.SAP_STUMPS.size() >= int(ItemDB.node_kind(L.SAP_KIND)["min_count"].get("surface", 0)), "sap stumps meet min_count")
	assert_true(L.SUNFLAX.size() >= int(ItemDB.node_kind(L.SUNFLAX_KIND)["min_count"].get("surface", 0)), "sunflax meets min_count")
	assert_true(L.ROSEBERRY.size() >= int(ItemDB.node_kind(L.ROSEBERRY_KIND)["min_count"].get("surface", 0)), "roseberries meet min_count")


func test_meadow_patch_is_in_the_sunny_meadow() -> void:
	var m: Dictionary = Layout.LANDMARKS["meadow"]
	for s in L.SUNFLAX + L.ROSEBERRY:
		var p: Vector2 = s["pos"]
		assert_true(p.distance_to(m["pos"]) < float(m["radius"]), "%s grows in the Sunny Meadow" % s["id"])


func test_tailor_cache_sits_by_the_old_oak_with_a_ribbon_trail() -> void:
	_setup()
	var oak: Vector2 = Layout.LANDMARKS["old_oak"]["pos"]
	var cp: Vector2 = L.TAILOR_CACHE["pos"]
	assert_true(cp.distance_to(oak) < float(Layout.LANDMARKS["old_oak"]["radius"]) + 1.0, "the cache is at the Old Oak (%.1f m)" % cp.distance_to(oak))
	assert_true(cp.distance_to(oak) > 4.0, "the cache is outside the trunk and roots")
	assert_true(L.TAILOR_RIBBONS.size() >= 3, "a ribbon trail")
	# The trail starts beside the Old Oak path and each ribbon is a short hop closer to the cache.
	var first: Vector2 = L.TAILOR_RIBBONS[0]["pos"]
	var near_path := false
	for a in 16:
		var q := first + Vector2(cos(a * TAU / 16.0), sin(a * TAU / 16.0)) * 3.0
		if float(_terrain.path_at(q.x, q.y)) > 0.5:
			near_path = true
	assert_true(near_path, "the first ribbon is visible from the Old Oak path")
	var prev := INF
	for r in L.TAILOR_RIBBONS:
		var d: float = (r["pos"] as Vector2).distance_to(cp)
		assert_true(d < prev, "ribbon %s leads toward the cache" % r["id"])
		prev = d
	for i in range(1, L.TAILOR_RIBBONS.size()):
		var gap: float = (L.TAILOR_RIBBONS[i]["pos"] as Vector2).distance_to(L.TAILOR_RIBBONS[i - 1]["pos"])
		assert_true(gap < 7.0, "each ribbon can be seen from the previous one (%.1f m)" % gap)


func test_bramblewatch_is_on_the_thicket_outskirts() -> void:
	_setup()
	var th: Vector2 = Layout.LANDMARKS["thicket"]["pos"]
	for z in L.BRAMBLEWATCH_ZONES:
		var c: Vector2 = z[0]
		var r := float(z[1])
		for lid in Layout.LANDMARKS:
			assert_true(c.distance_to(Layout.LANDMARKS[lid]["pos"]) > r, "the Bramblewatch zone never contains the %s centre" % lid)
		# West / north-west of the thicket spawner and clear of the bramblings' reach (aggro 9 m + wander).
		var rel := c - THICKET_SPAWNER
		var ang := rad_to_deg(atan2(-rel.y, -rel.x))   # 0 = west, 90 = north
		assert_true(ang > -35.0 and ang < 85.0, "Bramblewatch piece at %s lies west / north-west of the thicket (%.0f deg)" % [c, ang])
		assert_true(c.distance_to(th) < 30.0, "on the thicket outskirts (%.1f m)" % c.distance_to(th))
	for s in [L.BRAMBLEBACK_SPAWNER, L.ELDER_SPAWNER]:
		var p: Vector2 = s["pos"]
		assert_true(p.distance_to(THICKET_SPAWNER) > 24.0, "%s keeps its fights apart from the thicket bramblings" % s["id"])
		_check_site(String(s["id"]), p, 1.0, {"rise": 0.9})
	var pack: Vector2 = L.BRAMBLEBACK_SPAWNER["pos"]
	var elder: Vector2 = L.ELDER_SPAWNER["pos"]
	var aggro := float(EnemiesData.ENEMIES["brambleback"]["aggro_radius"]) + float(L.BRAMBLEBACK_SPAWNER["radius"]) \
		+ float(EnemiesData.ENEMIES["knotted_elder"]["aggro_radius"]) + float(L.ELDER_SPAWNER["radius"])
	assert_true(pack.distance_to(elder) > aggro, "the Brambleback group and the Elder are separate fights (%.1f m)" % pack.distance_to(elder))
	# Each spawner lies in one of the pocket's zone circles.
	for s in [L.BRAMBLEBACK_SPAWNER, L.ELDER_SPAWNER]:
		var inside := false
		for z in L.BRAMBLEWATCH_ZONES:
			if (s["pos"] as Vector2).distance_to(z[0]) < float(z[1]):
				inside = true
		assert_true(inside, "%s is inside Bramblewatch" % s["id"])


func test_elder_arena_is_open_and_its_roots_never_touch_legacy_nodes() -> void:
	_setup()
	var c: Vector2 = L.ELDER_ARENA["centre"]
	assert_eq(c, L.ELDER_SPAWNER["pos"], "the Elder spawns in the arena's middle")
	var n := L.ROOT_SLOTS.size()
	assert_true(n >= 6, "enough root slots to read as a ring (%d)" % n)
	assert_true(int(L.ELDER_ARENA["max_raised"]) <= n - int(L.ELDER_ARENA["min_open"]), "roots always leave open slots")
	assert_true(int(L.ELDER_ARENA["min_open"]) >= 2, "at least two ways out")
	var width := float(L.ELDER_ARENA["root_depth"]) * 0.5
	for i in n:
		var ends: Array = L.root_slot_ends(i)
		for k in 5:
			var q: Vector2 = (ends[0] as Vector2).lerp(ends[1], float(k) / 4.0)
			var nl := _nearest_legacy(q)
			assert_true(float(nl[0]) > width + CLEARANCE, "root slot %d: legacy %s %.2f m away" % [i, nl[1], nl[0]])
			assert_false(_terrain.is_water(q.x, q.y), "root slot %d is dry" % i)
			assert_true(float(_terrain.path_at(q.x, q.y)) <= 0.02, "root slot %d is off the paths" % i)
		# Our own props keep a walkable gap to every root.
		for f in L.footprints():
			var fp: Vector2 = f["pos"]
			if fp.distance_to(c) > 20.0:
				continue
			var d := _seg_dist(fp, ends[0], ends[1])
			assert_true(d - float(f["radius"]) - width > 1.2, "root slot %d leaves a walkable gap to %s (%.2f m)" % [i, f["id"], d])
	# Neighbouring slots never close into a wall: natural gap between their nearest ends.
	for i in n:
		var a: Array = L.root_slot_ends(i)
		var b: Array = L.root_slot_ends((i + 1) % n)
		var gap := INF
		for pa in a:
			for pb in b:
				gap = minf(gap, (pa as Vector2).distance_to(pb))
		assert_true(gap > 3.0, "slots %d and %d leave a %.2f m gap" % [i, (i + 1) % n, gap])


func test_moth_pocket_at_the_pond_away_from_haven_and_glade() -> void:
	_setup()
	var p: Vector2 = L.MOTH_SPAWNER["pos"]
	var pond: Dictionary = Layout.LANDMARKS["pond"]
	var d_pond := p.distance_to(pond["pos"])
	assert_true(d_pond < float(pond["radius"]) + 4.0, "the pocket is at Mirror Pond's edge (%.1f m)" % d_pond)
	assert_true(_terrain.pond_distance(p.x, p.y) > 1.5, "the spawner stands on the shore, not in the water")
	_check_site(String(L.MOTH_SPAWNER["id"]), p, 1.0, {"rise": 0.8})
	var moth: Dictionary = EnemiesData.ENEMIES["lantern_moth"]
	var reach := float(moth["leash_radius"]) + float(L.MOTH_SPAWNER["radius"])
	var haven: Dictionary = Layout.LANDMARKS["haven"]
	var glade: Dictionary = Layout.LANDMARKS["glade"]
	assert_true(p.distance_to(haven["pos"]) > float(haven["radius"]) + reach, "moths can never reach the Haven")
	assert_true(p.distance_to(glade["pos"]) > float(glade["radius"]) + reach, "moths can never reach the peaceful Berry Glade")
	for b in L.MOTH_BLOOMS:
		assert_true((b as Vector2).distance_to(p) < 5.0, "bloom %s belongs to the pocket" % b)


func test_moth_hours_are_dusk_and_night() -> void:
	for h in [18.0, 19.5, 21.0, 23.9, 0.0, 2.0, 5.0]:
		assert_true(L.is_moth_time(float(h)), "moths awake at %.1f h" % h)
	for h in [5.5, 6.0, 9.0, 12.0, 15.0, 17.9]:
		assert_false(L.is_moth_time(float(h)), "moths asleep at %.1f h" % h)
	assert_true(L.is_moth_time(24.0 + 19.0), "hours wrap")


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
