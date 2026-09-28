extends Node3D
## Autumn vegetation and renewable ground resources of Hallowmere Reach.
## plan(terrain, footprints) is PURE and deterministic. Every harvestable gets a STABLE id derived from its
## candidate slot, never from how many candidates were accepted before it:
##   hr_tree_<n>   n = cell of a 7 m jittered grid (fixed RNG calls per cell)
##   hr_rock_<n>   n = cell of a 12 m jittered grid
##   hr_stick_<n>, hr_stone_<n>, hr_fiber_<n>   n = index in a fixed candidate stream (ring 0..199 around
##                 the Commons, then 200.. scattered)
## So adding / moving a district footprint or a set piece can only add or remove individual ids: it never
## renumbers the others, and a saved GameState.depleted entry always means the same tree or stone.
## _ready() instantiates the plan: resource nodes (common/resource_node.gd, renewable like the Woods),
## the dense autumn forest belt behind the walls (MultiMesh + collision where reachable), bushes,
## mushrooms, fallen leaves, wild pumpkins, logs, rocks and autumn flower fields.
##   var v = ReachVegetation.new(); v.terrain = t; v.plan_data = ReachVegetation.plan(t, footprints); add_child(v)

const Reach := preload("res://data/hallowmere_layout.gd")
const Flora := preload("res://src/world/reach/reach_flora.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const ResourceNode := preload("res://src/world/common/resource_node.gd")
const Props := preload("res://src/world/surface/props.gd")
const Fields := preload("res://src/world/surface/flora.gd")

const TREE_SPACING := 7.0
const ROCK_SPACING := 12.0
const RING_CANDIDATES := 200
const SCATTER_CANDIDATES := 1400
## [kind, id prefix, seed, ring target, total target]
const SMALLS := [["sticks", "hr_stick", 71711, 10, 36], ["stones", "hr_stone", 72722, 10, 34], ["fibers", "hr_fiber", 73733, 12, 46]]
const COMMONS_RING := [17.0, 30.0]
const ROCK_TINT := Color("b7aa9c")
const STONE_TINT := Color("b9ab9c")
## Autumn flower colours (marigold, deep red, plum, cream, rust, lavender).
const PETALS := [Color("f0a23a"), Color("c8453a"), Color("8e5aa0"), Color("f5e6c8"), Color("c96a3a"), Color("b9a0d8")]

var terrain: RefCounted
var plan_data: Dictionary = {}
var resource_nodes: Dictionary = {}          # id -> node
var flower_nodes: Array = []
var build_times: Dictionary = {}


## Occupancy grid so placements never overlap.
class Occ:
	var cells := {}
	const CELL := 4.0

	func is_free(p: Vector2, r: float) -> bool:
		var cx := int(floor(p.x / CELL))
		var cz := int(floor(p.y / CELL))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var key := Vector2i(cx + dx, cz + dz)
				if cells.has(key):
					for e in cells[key]:
						var ev: Vector3 = e
						if Vector2(ev.x, ev.y).distance_to(p) < r + ev.z:
							return false
		return true

	func add(p: Vector2, r: float) -> void:
		var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(Vector3(p.x, p.y, r))


# --- Planning (pure) ----------------------------------------------------------------------------------

static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _lm(id: String) -> Vector2:
	return Reach.LANDMARKS[id]["pos"]


static func edge(p: Vector2) -> float:
	var ax := absf(p.x) / Reach.HALF_X
	var az := absf(p.y) / Reach.HALF_Z
	return maxf(maxf(ax, az), sqrt(ax * ax + az * az) * 0.86)


## Circles kept clear of trees, rocks and bushes: [centre, radius]. `footprints` = district footprints.
static func big_exclusions(footprints: Array = []) -> Array:
	var ex: Array = []
	for id in Reach.PLAZAS:
		var pl: Array = Reach.PLAZAS[id]
		ex.append([pl[0], float(pl[1]) + 1.5])
	ex.append([Vector2(0, 60), 25.0])                          # the whole festival ground
	ex.append([Reach.CONSERVATORY["center"], 17.0])
	ex.append([Reach.BELLHOUSE["pond"], 14.5])
	ex.append([Reach.BELLHOUSE["forecourt"], 8.5])
	ex.append([Reach.POINTS["mirror_waygate"], 7.0])
	ex.append([Reach.COMMONS["pumpkin_arch"], 5.0])
	ex.append([Reach.COMMONS["lot_sign"], 2.0])
	ex.append([Reach.CONSERVATORY["practice_seam"], 4.0])
	ex.append([Reach.POINTS["refuge_hatch"], 5.0])
	ex.append([Reach.POINTS["manor_door"], 5.0])
	for id in Reach.ARCHES:
		ex.append([Reach.ARCHES[id]["pos"], 6.0])
	for id in Reach.SPAWNS:
		ex.append([Reach.SPAWNS[id]["pos"], 3.5])
	for c in Reach.BROOK_CROSSINGS:
		ex.append([c["pos"], 6.5])
	for f in footprints:
		ex.append([f[0], float(f[1])])
	return ex


## Circles kept clear of sticks, stones and fiber tufts.
static func small_exclusions(footprints: Array = []) -> Array:
	var ex: Array = [[Vector2(0, 60), 15.5], [Reach.CONSERVATORY["center"], 15.0], [Reach.BELLHOUSE["pond"], 13.0],
		[Reach.BELLHOUSE["forecourt"], 7.0], [Reach.PLAZAS["outpost"][0], 9.5], [Reach.PLAZAS["arrival"][0], 7.5],
		[Reach.COMMONS["pumpkin_arch"], 3.5], [Reach.CROSSROADS, 5.5], [Reach.CONSERVATORY["practice_seam"], 3.0],
		[Reach.POINTS["refuge_hatch"], 3.0], [Reach.COMMONS["lot_sign"], 1.5], [Reach.POINTS["mirror_waygate"], 4.5]]
	for id in Reach.ARCHES:
		ex.append([Reach.ARCHES[id]["pos"], 4.0])
	for id in Reach.SPAWNS:
		ex.append([Reach.SPAWNS[id]["pos"], 2.0])
	for c in Reach.BROOK_CROSSINGS:
		ex.append([c["pos"], 4.5])
	for s in Reach.COMMONS["stalls"]:
		ex.append([s[0], 2.8])
	for f in footprints:
		ex.append([f[0], float(f[1])])
	return ex


static func _clear_of(t: RefCounted, p: Vector2, r: float, ex: Array, occ: Occ, opts: Dictionary = {}) -> bool:
	if edge(p) > float(opts.get("edge", 0.955)):
		return false
	var path_r := r + float(opts.get("path_margin", 0.7))
	if t.path_at(p.x, p.y) > 0.02:
		return false
	for a in 4:
		var q := p + Vector2(cos(a * PI * 0.5), sin(a * PI * 0.5)) * path_r
		if t.path_at(q.x, q.y) > 0.08:
			return false
	if t.stream_distance(p.x, p.y) < float(opts.get("stream", 4.2)) + r * 0.6:
		return false
	if t.pond_distance(p.x, p.y) < float(opts.get("pond", 2.0)) + r:
		return false
	if t.is_water(p.x, p.y):
		return false
	if t.rock_at(p.x, p.y) > float(opts.get("rock", 0.35)):
		return false
	for e in ex:
		if p.distance_to(e[0]) < float(e[1]) + r:
			return false
	return occ.is_free(p, r)


static func _tree_density(p: Vector2, n: float) -> float:
	var d := 0.05 + n * 0.62
	d += 0.55 * _smooth(0.78, 0.93, edge(p))                       # the forest thickens toward the walls
	d *= 0.1 + 0.9 * _smooth(26.0, 40.0, p.distance_to(Vector2(0, 60)))
	d *= 0.2 + 0.8 * _smooth(18.0, 30.0, p.distance_to(Vector2(0, 6)))
	d *= 0.3 + 0.7 * _smooth(9.0, 20.0, p.distance_to(Reach.CROSSROADS))
	d *= 0.4 + 0.6 * _smooth(16.0, 28.0, p.distance_to(Vector2(72, -80)))
	for id in ["hr_orchard", "hr_pools", "hr_candleyard", "hr_quarry", "hr_manor_grounds"]:
		var r := float(Reach.LANDMARKS[id]["radius"])
		d *= 0.3 + 0.7 * _smooth(r * 0.6, r + 5.0, p.distance_to(_lm(id)))
	# Sight lines: from the arrival north over the festival to the Conservatory, and up to the manor.
	if absf(p.x) < 13.0 and p.y > -4.0 and p.y < 104.0:
		d *= 0.15
	if p.y < 0.0 and p.y > -48.0 and absf(p.x - p.y * -0.2) < 11.0:
		d *= 0.35
	return clampf(d, 0.0, 0.9)


static func _species(p: Vector2, roll: float) -> String:
	var mix := {"amber": 0.3, "copper": 0.27, "ember": 0.16, "gold": 0.15, "pine": 0.12}
	if p.distance_to(Vector2(0, 60)) < 50.0 or p.distance_to(Vector2(0, 6)) < 34.0:
		mix = {"amber": 0.36, "copper": 0.38, "ember": 0.08, "gold": 0.18, "pine": 0.0}
	elif p.distance_to(_lm("hr_candleyard")) < 42.0:
		mix = {"amber": 0.1, "copper": 0.05, "ember": 0.35, "gold": 0.05, "pine": 0.45}
	elif p.distance_to(_lm("hr_manor_grounds")) < 46.0 or p.y < -86.0:
		mix = {"amber": 0.05, "copper": 0.12, "ember": 0.45, "gold": 0.03, "pine": 0.35}
	elif p.distance_to(_lm("hr_pools")) < 36.0:
		mix = {"amber": 0.22, "copper": 0.08, "ember": 0.05, "gold": 0.5, "pine": 0.15}
	elif p.distance_to(_lm("hr_quarry")) < 46.0 or p.x > 96.0:
		mix = {"amber": 0.2, "copper": 0.38, "ember": 0.07, "gold": 0.0, "pine": 0.35}
	elif p.distance_to(_lm("hr_orchard")) < 46.0:
		mix = {"amber": 0.48, "copper": 0.18, "ember": 0.04, "gold": 0.3, "pine": 0.0}
	var acc := 0.0
	for sp in Flora.SPECIES:
		acc += float(mix.get(sp, 0.0))
		if roll <= acc:
			return String(sp)
	return "amber"


static func plan(t: RefCounted, footprints: Array = []) -> Dictionary:
	var out := {"trees": [], "rocks": [], "sticks": [], "stones": [], "fibers": [], "decor_trees": [],
		"decor_bushes": [], "mushrooms": [], "leaves": [], "pumpkins": [], "logs": [], "decor_rocks": [], "flowers": []}
	var occ := Occ.new()
	var ex := big_exclusions(footprints)
	var dn := FastNoiseLite.new()
	dn.seed = 919
	dn.frequency = 0.03
	var y := func(p: Vector2) -> Vector3:
		return Vector3(p.x, t.height_at(p.x, p.y), p.y)
	# Harvestable trees (jittered grid; every cell consumes the same RNG calls; id = cell index).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151515
	var cx := int(266.0 / TREE_SPACING) + 1
	var cz := int(206.0 / TREE_SPACING) + 1
	for j in cz:
		for i in cx:
			var cell := j * cx + i
			var p := Vector2(-133.0 + float(i) * TREE_SPACING + rng.randf_range(0.4, TREE_SPACING - 0.4),
				-103.0 + float(j) * TREE_SPACING + rng.randf_range(0.4, TREE_SPACING - 0.4))
			var roll := rng.randf()
			var sroll := rng.randf()
			var seed_v := rng.randi() % 3
			var yaw := rng.randf() * 360.0
			var sc := rng.randf_range(0.85, 1.2)
			if roll > _tree_density(p, dn.get_noise_2d(p.x, p.y) * 0.5 + 0.5):
				continue
			if not _clear_of(t, p, 2.1, ex, occ):
				continue
			occ.add(p, 2.1)
			out["trees"].append({"id": "hr_tree_%d" % cell, "pos": y.call(p), "species": _species(p, sroll), "seed": seed_v, "yaw": yaw, "scale": sc})
	# Harvestable boulders (stone): scattered, more on the quarry side, the pools' edges and the hills.
	rng.seed = 5252525
	var rx := int(264.0 / ROCK_SPACING) + 1
	var rz := int(204.0 / ROCK_SPACING) + 1
	for j in rz:
		for i in rx:
			var cell := j * rx + i
			var p := Vector2(-132.0 + float(i) * ROCK_SPACING + rng.randf_range(1.0, ROCK_SPACING - 1.0),
				-102.0 + float(j) * ROCK_SPACING + rng.randf_range(1.0, ROCK_SPACING - 1.0))
			var roll := rng.randf()
			var seed_v := rng.randi() % 3
			var yaw := rng.randf() * 360.0
			var sc := rng.randf_range(0.75, 1.05)
			var d := 0.14
			d += 0.35 * (1.0 - _smooth(30.0, 48.0, p.distance_to(_lm("hr_quarry"))))
			d += 0.35 * (1.0 - _smooth(18.0, 32.0, p.distance_to(_lm("hr_pools"))))
			d += 0.2 * _smooth(0.75, 0.9, edge(p))
			if roll > d:
				continue
			if not _clear_of(t, p, 1.5, ex, occ, {"rock": 0.5}):
				continue
			occ.add(p, 1.5)
			out["rocks"].append({"id": "hr_rock_%d" % cell, "pos": y.call(p), "seed": seed_v, "yaw": yaw, "scale": sc})
	# Sticks, stones and fiber tufts: a guaranteed ring around the Commons (an under-equipped arrival can
	# always gather), then a sprinkle everywhere.
	var sex := small_exclusions(footprints)
	for sd in SMALLS:
		rng.seed = int(sd[2])
		var list: Array = out[sd[0]]
		var ring_ok := 0
		for n in RING_CANDIDATES:
			var a := rng.randf() * TAU
			var r := rng.randf_range(COMMONS_RING[0], COMMONS_RING[1])
			var yaw := rng.randf() * 360.0
			if ring_ok >= int(sd[3]):
				continue
			var p := Vector2(0, 60) + Vector2(cos(a), sin(a)) * r
			if not _clear_of(t, p, 0.6, sex, occ, {"edge": 0.93, "path_margin": 0.2, "stream": 3.4, "pond": 1.0, "rock": 0.3}):
				continue
			occ.add(p, 0.6)
			list.append({"id": "%s_%d" % [sd[1], n], "pos": y.call(p), "seed": n, "yaw": yaw})
			ring_ok += 1
		for n in range(RING_CANDIDATES, RING_CANDIDATES + SCATTER_CANDIDATES):
			var p := Vector2(rng.randf_range(-128.0, 128.0), rng.randf_range(-98.0, 98.0))
			var yaw := rng.randf() * 360.0
			if list.size() >= int(sd[4]):
				continue
			if p.distance_to(Vector2(0, 60)) < COMMONS_RING[1]:
				continue
			if not _clear_of(t, p, 0.6, sex, occ, {"edge": 0.92, "path_margin": 0.2, "stream": 3.4, "pond": 1.0, "rock": 0.3}):
				continue
			occ.add(p, 0.6)
			list.append({"id": "%s_%d" % [sd[1], n], "pos": y.call(p), "seed": n, "yaw": yaw})
	_plan_forest_belt(t, out, occ)
	_plan_decor(t, out, occ, ex, rng)
	_plan_flowers(t, out, footprints)
	return out


## Dense autumn forest on the soft boundary hills (decor MultiMesh; reachable trunks collide).
static func _plan_forest_belt(t: RefCounted, out: Dictionary, occ: Occ) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5353535
	var sp := 5.4
	var nx := int(320.0 / sp) + 1
	var nz := int(256.0 / sp) + 1
	for j in nz:
		for i in nx:
			var p := Vector2(-160.0 + float(i) * sp + rng.randf_range(0.3, sp - 0.3), -128.0 + float(j) * sp + rng.randf_range(0.3, sp - 0.3))
			var roll := rng.randf()
			var sroll := rng.randf()
			var variant := rng.randi() % 3
			var yaw := rng.randf() * TAU
			var sc := rng.randf_range(0.95, 1.4)
			var e := edge(p)
			if e < 0.93 or e > 1.22 or roll > 0.82:
				continue
			if t.stream_distance(p.x, p.y) < 5.0 or p.distance_to(Reach.POINTS["mirror_waygate"]) < 8.0:
				continue
			if not occ.is_free(p, 1.8):
				continue
			occ.add(p, 1.8)
			var species := "pine"
			if sroll > 0.45:
				species = ["ember", "copper", "amber", "gold"][int(sroll * 97.0) % 4]
			out["decor_trees"].append([species, variant, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), Vector3(p.x, t.height_at(p.x, p.y) - 0.1, p.y)), e < 1.0])


static func _ground_xf(t: RefCounted, p: Vector2, yaw: float, s: float, dy: float = 0.0) -> Transform3D:
	var n: Vector3 = t.normal_at(p.x, p.y)
	var b := Basis(Vector3.UP, yaw)
	if n.dot(Vector3.UP) < 0.9999:
		var axis := Vector3.UP.cross(n).normalized()
		b = Basis(axis, Vector3.UP.angle_to(n)) * b
	return Transform3D(b.scaled(Vector3(s, s, s)), Vector3(p.x, t.height_at(p.x, p.y) + dy, p.y))


static func _plan_decor(t: RefCounted, out: Dictionary, occ: Occ, ex: Array, rng: RandomNumberGenerator) -> void:
	rng.seed = 5454545
	var trees: Array = out["trees"]
	for k in trees.size():
		var tp: Vector3 = trees[k]["pos"]
		var r1 := rng.randf()
		var r2 := rng.randf()
		var a := rng.randf() * TAU
		var a2 := rng.randf() * TAU
		var a3 := rng.randf() * TAU
		var v := rng.randi() % 4
		var c := Vector2(tp.x, tp.z)
		if r1 < 0.45:
			# just outside the tree's own 2.1 m occupancy (+ the bush's 0.9 m), under the edge of its crown
			var p := c + Vector2(cos(a), sin(a)) * rng.randf_range(3.1, 4.2)
			if _clear_of(t, p, 0.9, ex, occ):
				occ.add(p, 0.9)
				out["decor_bushes"].append([v % 3, _ground_xf(t, p, a, rng.randf_range(0.7, 1.1))])
		if r2 < 0.3:
			var p2 := c + Vector2(cos(a2), sin(a2)) * rng.randf_range(1.0, 1.8)
			if t.path_at(p2.x, p2.y) < 0.05 and not t.is_water(p2.x, p2.y):
				out["mushrooms"].append([v, _ground_xf(t, p2, a2, rng.randf_range(0.8, 1.3))])
		# fallen leaves under every crown
		for m in 2:
			var p3 := c + Vector2(cos(a3 + float(m) * 2.4), sin(a3 + float(m) * 2.4)) * (0.9 + float(m) * 1.1)
			if t.path_at(p3.x, p3.y) < 0.3 and not t.is_water(p3.x, p3.y):
				out["leaves"].append([(k + m) % 3, _ground_xf(t, p3, a3 + float(m), rng.randf_range(0.9, 1.5), 0.01)])
	# Leaves drifting along the road edges and on the festival ground.
	rng.seed = 5555555
	for id in Reach.PATHS:
		var curve: PackedVector2Array = t.path_curves.get(id, PackedVector2Array())
		var half: float = float(Reach.PATH_WIDTHS.get(id, 1.5))
		for i in range(0, curve.size(), 5):
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var roll := rng.randf()
			var a := rng.randf() * TAU
			if roll > 0.6 or i + 1 >= curve.size():
				continue
			var d := (curve[i + 1] - curve[i]).normalized()
			var p := curve[i] + Vector2(-d.y, d.x) * side * (half + rng.randf_range(0.3, 1.4))
			if not t.is_water(p.x, p.y):
				out["leaves"].append([i % 3, _ground_xf(t, p, a, rng.randf_range(0.8, 1.3), 0.01)])
	for i in 70:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 24.0
		var p := Vector2(0, 60) + Vector2(cos(a), sin(a)) * r
		out["leaves"].append([i % 3, _ground_xf(t, p, a, rng.randf_range(0.8, 1.4), 0.012)])
	# Wild pumpkins in little clusters along the roads and field edges (never on the road).
	rng.seed = 5656565
	var pk := 0
	var tries := 0
	while pk < 60 and tries < 900:
		tries += 1
		var p := Vector2(rng.randf_range(-120.0, 120.0), rng.randf_range(-92.0, 96.0))
		var v := rng.randi() % 4
		var s := rng.randf_range(0.7, 1.35)
		var yaw := rng.randf() * TAU
		var near_road: bool = t.path_at(p.x, p.y) < 0.02 and (t.path_at(p.x + 3.0, p.y) > 0.1 or t.path_at(p.x - 3.0, p.y) > 0.1 or t.path_at(p.x, p.y + 3.0) > 0.1 or t.path_at(p.x, p.y - 3.0) > 0.1)
		if not near_road or not _clear_of(t, p, 0.5, ex, occ, {"path_margin": 0.1, "edge": 0.9}):
			continue
		occ.add(p, 0.5)
		out["pumpkins"].append([v, _ground_xf(t, p, yaw, s, -0.04)])
		pk += 1
	# Fallen logs.
	rng.seed = 5757575
	var logs := 0
	var lt := 0
	while logs < 9 and lt < 400:
		lt += 1
		var p := Vector2(rng.randf_range(-120.0, 120.0), rng.randf_range(-95.0, 95.0))
		var yaw := rng.randf() * TAU
		if not _clear_of(t, p, 1.9, ex, occ, {"edge": 0.9}):
			continue
		occ.add(p, 1.9)
		out["logs"].append([logs % 3, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, t.height_at(p.x, p.y) - 0.06, p.y))])
		logs += 1
	# Decorative big rocks: scattered, and a few crags on the hills.
	rng.seed = 5858585
	var dr := 0
	var drt := 0
	while dr < 34 and drt < 900:
		drt += 1
		var p := Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-120.0, 120.0))
		var sc := rng.randf_range(0.9, 2.2)
		var v := rng.randi() % 3
		var yaw := rng.randf() * TAU
		var e := edge(p)
		if e < 0.55 or e > 1.15:
			continue
		if not _clear_of(t, p, sc * 1.1, ex, occ, {"edge": 1.15, "rock": 0.9}):
			continue
		occ.add(p, sc * 1.1)
		out["decor_rocks"].append([v, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3(p.x, t.height_at(p.x, p.y) - 0.3, p.y)), e < 0.99])
		dr += 1


static func _plan_flowers(t: RefCounted, out: Dictionary, footprints: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5959595
	var fn := FastNoiseLite.new()
	fn.seed = 4321
	fn.frequency = 0.12
	var keep_out: Array = [[Reach.CONSERVATORY["center"], 7.5], [Reach.BELLHOUSE["pond"], 13.0], [Reach.PLAZAS["outpost"][0], 8.5]]
	for s in Reach.COMMONS["stalls"]:
		keep_out.append([s[0], 2.6])
	keep_out.append_array(footprints)
	var ok := func(p: Vector2) -> bool:
		if t.path_at(p.x, p.y) > 0.1 or t.stream_distance(p.x, p.y) < 3.0 or t.is_water(p.x, p.y) or t.rock_at(p.x, p.y) > 0.3:
			return false
		if t.pond_distance(p.x, p.y) < 1.0:
			return false
		for e in keep_out:
			if p.distance_to(e[0]) < float(e[1]):
				return false
		return edge(p) < 0.92
	# [centre, r0, r1, count, palette indices, kinds]
	var fields: Array = [
		[Vector2(0, 60), 14.0, 30.0, 520, [0, 1, 3, 4], [0, 2]],
		[Vector2(0, 6), 9.0, 21.0, 380, [0, 2, 3, 5], [0, 1]],
		[Reach.CROSSROADS, 3.0, 12.0, 160, [0, 1, 4], [0, 2]],
		[Vector2(0, 98), 5.0, 14.0, 140, [0, 3, 1], [0, 1]],
		[Vector2(-44, 30), 4.0, 16.0, 220, [0, 3, 4], [0, 2]],
		[Vector2(40, 20), 4.0, 18.0, 240, [1, 2, 5], [1, 2]],
		[Vector2(40, -30), 4.0, 16.0, 200, [2, 5, 3], [0, 2]],
	]
	var colors: Array = PETALS
	for fd in fields:
		var c: Vector2 = fd[0]
		var r0: float = fd[1]
		var r1: float = fd[2]
		var pal: Array = fd[4]
		var kinds: Array = fd[5]
		for i in int(fd[3]):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf_range(r0 * r0 / (r1 * r1), 1.0)) * r1
			var p := c + Vector2(cos(a), sin(a)) * r
			var cr := rng.randf()
			var kr := rng.randi() % kinds.size()
			var yaw := rng.randf() * TAU
			var sc := rng.randf_range(0.75, 1.25)
			if fn.get_noise_2d(p.x, p.y) < -0.2:
				continue
			if not ok.call(p):
				continue
			var ci := int(pal[int(floor(cr * pal.size())) % pal.size()])
			out["flowers"].append([Vector3(p.x, t.height_at(p.x, p.y), p.y), yaw, sc, colors[ci], 0.0, int(kinds[kr])])
	for i in 900:
		var p := Vector2(rng.randf_range(-125.0, 125.0), rng.randf_range(-96.0, 96.0))
		var ci := rng.randi() % colors.size()
		var yaw := rng.randf() * TAU
		var sc := rng.randf_range(0.7, 1.1)
		var kind := rng.randi() % 3
		if fn.get_noise_2d(p.x, p.y) < 0.2 or not ok.call(p):
			continue
		out["flowers"].append([Vector3(p.x, t.height_at(p.x, p.y), p.y), yaw, sc, colors[ci], 0.0, kind])


## Every harvestable id of a plan (tests, census).
static func ids(p: Dictionary) -> Array:
	var out: Array = []
	for k in ["trees", "rocks", "sticks", "stones", "fibers"]:
		for d in p.get(k, []):
			out.append(String(d["id"]))
	return out


## Clears the terrain grass mask under small props (call before the grass texture is created).
static func clear_grass_for(t: RefCounted, p: Dictionary) -> void:
	for k in ["sticks", "stones"]:
		for d in p.get(k, []):
			t.clear_grass(d["pos"].x, d["pos"].z, 1.3)
	for d in p.get("fibers", []):
		t.clear_grass(d["pos"].x, d["pos"].z, 1.1)
	for d in p.get("rocks", []):
		t.clear_grass(d["pos"].x, d["pos"].z, 1.6)


# --- Building --------------------------------------------------------------------------------------------

func _ready() -> void:
	name = "Vegetation"
	if plan_data.is_empty():
		plan_data = plan(terrain)
	var t0 := Time.get_ticks_usec()
	_build_resource_nodes()
	var t1 := Time.get_ticks_usec()
	_build_forest_belt()
	var t2 := Time.get_ticks_usec()
	_build_decor()
	var t3 := Time.get_ticks_usec()
	_build_flowers()
	var t4 := Time.get_ticks_usec()
	build_times = {"nodes": (t1 - t0) / 1000.0, "forest": (t2 - t1) / 1000.0, "decor": (t3 - t2) / 1000.0, "flowers": (t4 - t3) / 1000.0}


func _add_node(parent: Node3D, params: Dictionary, pos: Vector3) -> Node3D:
	var n: Node3D = ResourceNode.new()
	n.setup(params)
	n.position = pos
	parent.add_child(n)
	n.name = String(params["node_id"])
	resource_nodes[String(params["node_id"])] = n
	return n


func _group(node_name: String) -> Node3D:
	var g := Node3D.new()
	g.name = node_name
	add_child(g)
	return g


func _build_resource_nodes() -> void:
	var gt := _group("Trees")
	for d in plan_data["trees"]:
		var sp := String(d["species"])
		_add_node(gt, {"node_id": d["id"], "kind": "tree", "visual": Flora.tree_visual(sp, int(d["seed"])), "seed": d["seed"],
			"yaw": d["yaw"], "scale": d["scale"], "name": String(Flora.TREE_NAMES.get(sp, "Tree"))}, d["pos"])
	var gr := _group("Rocks")
	for d in plan_data["rocks"]:
		_add_node(gr, {"node_id": d["id"], "kind": "rock", "seed": d["seed"], "yaw": d["yaw"], "scale": d["scale"], "tint": ROCK_TINT}, d["pos"] - Vector3(0, 0.12, 0))
	var gs := _group("Forage")
	for d in plan_data["sticks"]:
		_add_node(gs, {"node_id": d["id"], "kind": "stick", "visual": Flora.stick_visual(int(d["seed"])), "yaw": d["yaw"]}, d["pos"])
	for d in plan_data["stones"]:
		_add_node(gs, {"node_id": d["id"], "kind": "stone", "seed": d["seed"], "yaw": d["yaw"], "tint": STONE_TINT}, d["pos"])
	for d in plan_data["fibers"]:
		_add_node(gs, {"node_id": d["id"], "kind": "grass", "visual": Flora.tuft_visual(int(d["seed"])), "yaw": d["yaw"]}, d["pos"])


func _build_forest_belt() -> void:
	var g := _group("ForestBelt")
	var by_key: Dictionary = {}
	var body := StaticBody3D.new()
	body.name = "ForestCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	g.add_child(body)
	for d in plan_data["decor_trees"]:
		var sp: String = d[0]
		var variant: int = d[1]
		var xf: Transform3D = d[2]
		var sector := int(floor((atan2(xf.origin.z, xf.origin.x) + PI) / TAU * 8.0)) % 8
		var key := "%s|%d|%d" % [sp, variant, sector]
		if not by_key.has(key):
			by_key[key] = []
		by_key[key].append(xf)
		if bool(d[3]):
			var parts := Flora.tree_parts(sp, variant)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = (float(parts["trunk_radius"]) + 0.05) * xf.basis.get_scale().x
			cyl.height = 3.0
			cs.shape = cyl
			cs.position = xf.origin + Vector3(0, 1.5, 0)
			body.add_child(cs)
	for key in by_key:
		var bits: PackedStringArray = String(key).split("|")
		var sp := bits[0]
		var parts := Flora.tree_parts(sp, int(bits[1]))
		var xfs: Array = by_key[key]
		var nm := String(key).replace("|", "_")
		g.add_child(Props.multimesh(parts["trunk"], NodeVisuals.bark_material(), xfs, "Trunks_" + nm, 0.0, false))
		g.add_child(Props.multimesh(parts["crown"], Flora.crown_material(sp), xfs, "Crowns_" + nm))


func _build_decor() -> void:
	var g := _group("Decor")
	var bush_lists: Array = [[], [], []]
	for d in plan_data["decor_bushes"]:
		bush_lists[int(d[0])].append(d[1])
	var bush_mat := NodeVisuals.foliage_material(0.03, 1.4, 0.022, 0.18)
	for v in 3:
		if not bush_lists[v].is_empty():
			g.add_child(Props.multimesh(Flora.bush_mesh(v), bush_mat, bush_lists[v], "Bushes%d" % v, 120.0))
	var mush_lists: Array = [[], [], [], []]
	for d in plan_data["mushrooms"]:
		mush_lists[int(d[0])].append(d[1])
	var mush_mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.45}), 0.012)
	for v in 4:
		if not mush_lists[v].is_empty():
			g.add_child(Props.multimesh(Props.mushroom_cluster(v), mush_mat, mush_lists[v], "Mushrooms%d" % v, 60.0, false))
	var leaf_lists: Array = [[], [], []]
	for d in plan_data["leaves"]:
		leaf_lists[int(d[0])].append(d[1])
	var leaf_mat := Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.1, "noise": 0.05})
	for v in 3:
		if not leaf_lists[v].is_empty():
			g.add_child(Props.multimesh(Flora.leaf_patch_mesh(v), leaf_mat, leaf_lists[v], "FallenLeaves%d" % v, 55.0, false))
	var pk_lists: Array = [[], [], [], []]
	for d in plan_data["pumpkins"]:
		pk_lists[int(d[0])].append(d[1])
	var pk_mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.35, "specular": 0.3}), 0.014)
	for v in 4:
		if not pk_lists[v].is_empty():
			g.add_child(Props.multimesh(Flora.pumpkin_mesh(v), pk_mat, pk_lists[v], "WildPumpkins%d" % v, 90.0))
	var log_body := StaticBody3D.new()
	log_body.name = "LogCollision"
	log_body.collision_layer = 1
	log_body.collision_mask = 0
	log_body.set_meta("surface", "wood")
	g.add_child(log_body)
	for d in plan_data["logs"]:
		var xf: Transform3D = d[1]
		var mi := Props.instance(Props.fallen_log(int(d[0])), NodeVisuals.bark_material(), 140.0)
		mi.transform = xf
		g.add_child(mi)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.33
		cap.height = 3.2
		cs.shape = cap
		cs.transform = Transform3D(xf.basis * Basis(Vector3.BACK, deg_to_rad(90.0)), xf.origin + Vector3(0, 0.3, 0))
		log_body.add_child(cs)
	var rock_lists: Array = [[], [], []]
	var rock_body := StaticBody3D.new()
	rock_body.name = "RockCollision"
	rock_body.collision_layer = 1
	rock_body.collision_mask = 0
	rock_body.set_meta("surface", "stone")
	g.add_child(rock_body)
	for d in plan_data["decor_rocks"]:
		var v := int(d[0])
		var xf: Transform3D = d[1]
		rock_lists[v].append(xf)
		if bool(d[2]):
			var mesh := NodeVisuals.boulder_mesh(v, ROCK_TINT, 0.5)
			var cs := CollisionShape3D.new()
			cs.shape = NodeVisuals._convex_for(mesh, "boulder|%d|%s|%.2f" % [v, ROCK_TINT.to_html(), 0.5])
			cs.transform = xf
			rock_body.add_child(cs)
	for v in 3:
		if not rock_lists[v].is_empty():
			g.add_child(Props.multimesh(NodeVisuals.boulder_mesh(v, ROCK_TINT, 0.5), NodeVisuals.rock_material(), rock_lists[v], "BigRocks%d" % v))


func _build_flowers() -> void:
	var g := _group("Flowers")
	var mat := Fields.make_material(false)
	mat.set_shader_parameter("terrain_origin", Vector2(-160.0, -128.0))
	mat.set_shader_parameter("terrain_samples", Vector2(321.0, 257.0))
	var chunks: Dictionary = {}
	for f in plan_data["flowers"]:
		var p: Vector3 = f[0]
		var key := Vector2i(int(floor(p.x / 40.0)), int(floor(p.z / 40.0)))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(f)
	for key in chunks:
		flower_nodes.append_array(Fields.build_fields(g, chunks[key], mat, "Field_%d_%d" % [key.x, key.y], 100.0))
