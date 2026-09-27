extends Node3D
## Vegetation and ground resources of Hollowhaven Woods.
## plan(terrain) is PURE and deterministic (fixed seeds, fixed candidate order): it returns every
## placement with a STABLE id ("tree_12", "rock_4", "stick_3" ...). _ready() instantiates the plan:
## harvestable resource nodes (common/resource_node.gd), decorative forest belts (MultiMesh + collision),
## bushes, mushrooms, fallen logs, rocks, brambles and flower fields.
##   var v = Vegetation.new(); v.terrain = terrain; v.plan_data = Vegetation.plan(terrain); add_child(v)

const Layout := preload("res://data/world_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const ResourceNode := preload("res://src/world/common/resource_node.gd")
const Props := preload("res://src/world/surface/props.gd")
const Flora := preload("res://src/world/surface/flora.gd")

const TREE_NAMES := {"oak": "Oak Tree", "pine": "Pine Tree", "blossom": "Blossom Tree", "birch": "Birch Tree"}
const HAVEN_RING := [16.0, 34.0]            # sticks/stones/tufts guaranteed in this ring around the Haven

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


static func edge_dist(p: Vector2) -> float:
	return maxf(maxf(absf(p.x), absf(p.y)), p.length() * 0.86)


static func _lm(id: String) -> Vector2:
	return Layout.LANDMARKS[id]["pos"]


## Circles where big things (trees, rocks, bushes) must not go: [centre, radius].
static func big_exclusions() -> Array:
	var ex: Array = [
		[Vector2.ZERO, 19.5],
		[_lm("quarry"), 12.5],
		[_lm("ruin"), 13.5],
		[SL.MINE_MOUTH + SL.MINE_FACING.normalized() * 6.0, 10.5],
		[SL.MINE_MOUTH, 7.0],
		[_lm("glade") + Vector2(-5, 2), 6.5],
		[_lm("meadow"), 12.0],
		[_lm("old_oak"), 9.0],
		[_lm("thicket"), 5.5],
		[SL.SIGN, 2.5],
	]
	for id in Layout.SPAWN_HINTS:
		ex.append([Layout.SPAWN_HINTS[id], 3.5])
	for c in Layout.STREAM_CROSSINGS:
		ex.append([c, 6.5])
	return ex


static func _clear_of(t: RefCounted, p: Vector2, r: float, ex: Array, occ: Occ, opts: Dictionary = {}) -> bool:
	if edge_dist(p) > float(opts.get("edge", 96.0)):
		return false
	var path_r := r + float(opts.get("path_margin", 0.7))
	if t.path_at(p.x, p.y) > 0.02:
		return false
	for a in 4:
		var q := p + Vector2(cos(a * PI * 0.5), sin(a * PI * 0.5)) * path_r
		if t.path_at(q.x, q.y) > 0.08:
			return false
	if t.stream_distance(p.x, p.y) < float(opts.get("stream", 4.4)) + r * 0.6:
		return false
	if t.pond_distance(p.x, p.y) < float(opts.get("pond", 2.2)) + r:
		return false
	if t.rock_at(p.x, p.y) > float(opts.get("rock", 0.35)):
		return false
	for e in ex:
		if p.distance_to(e[0]) < float(e[1]) + r:
			return false
	return occ.is_free(p, r)


static func _tree_density(p: Vector2, n: float) -> float:
	var d := 0.08 + n * 0.62
	var r := p.length()
	if r < 46.0:
		d = maxf(d, 0.62 * (1.0 - _smooth(30.0, 46.0, r)))
	d *= 0.2 + 0.8 * _smooth(14.0, 30.0, p.distance_to(_lm("meadow")))
	d *= 0.3 + 0.7 * _smooth(18.0, 28.0, p.distance_to(_lm("quarry")))
	d *= 0.55 + 0.45 * _smooth(16.0, 24.0, p.distance_to(Vector2(46, 52)))
	d += 0.35 * (1.0 - _smooth(12.0, 24.0, p.distance_to(_lm("thicket"))))
	d += 0.15 * (1.0 - _smooth(14.0, 26.0, p.distance_to(_lm("glade"))))
	d += 0.2 * (1.0 - _smooth(12.0, 22.0, p.distance_to(_lm("ruin"))))
	return clampf(d, 0.0, 0.92)


static func _species(p: Vector2, roll: float) -> String:
	var mix := {"oak": 0.45, "birch": 0.2, "blossom": 0.15, "pine": 0.2}
	if p.length() < 48.0:
		mix = {"oak": 0.4, "birch": 0.28, "blossom": 0.27, "pine": 0.05}
	if p.y < -40.0:
		mix = {"oak": 0.3, "birch": 0.25, "blossom": 0.0, "pine": 0.45}
	if p.x < -35.0 and absf(p.y) < 32.0:
		mix = {"oak": 0.5, "birch": 0.12, "blossom": 0.38, "pine": 0.0}
	if p.distance_to(_lm("thicket")) < 26.0:
		mix = {"oak": 0.6, "birch": 0.0, "blossom": 0.0, "pine": 0.4}
	if p.distance_to(Vector2(46, 52)) < 30.0:
		mix = {"oak": 0.3, "birch": 0.4, "blossom": 0.3, "pine": 0.0}
	if p.x > 45.0 and p.y > -40.0 and p.y < 20.0:
		mix = {"oak": 0.25, "birch": 0.45, "blossom": 0.0, "pine": 0.3}
	var acc := 0.0
	for sp in ["oak", "birch", "blossom", "pine"]:
		acc += float(mix[sp])
		if roll <= acc:
			return sp
	return "oak"


static func plan(t: RefCounted) -> Dictionary:
	var out := {"trees": [], "rocks": [], "ores": [], "bushes": [], "tufts": [], "sticks": [], "stones": [],
		"decor_trees": [], "decor_bushes": [], "mushrooms": [], "logs": [], "decor_rocks": [], "brambles": [], "flowers": [], "restore_flowers": []}
	var occ := Occ.new()
	var ex := big_exclusions()
	var dn := FastNoiseLite.new()
	dn.seed = 99
	dn.frequency = 0.035
	var h := func(p: Vector2) -> Vector3:
		return Vector3(p.x, t.height_at(p.x, p.y), p.y)
	# Ore veins: at the foot of the quarry terraces (fixed, readable).
	var q := _lm("quarry")
	var qdir := SL.QUARRY_TERRACE_DIR.normalized()
	var base_a := atan2(qdir.y, qdir.x)
	for i in 7:
		var a := base_a + lerpf(-1.25, 1.25, float(i) / 6.0)
		var r := 10.2 + float(i % 2) * 1.6
		var p := q + Vector2(cos(a), sin(a)) * r
		occ.add(p, 1.3)
		out["ores"].append({"id": "ore_%d" % i, "pos": h.call(p), "yaw": rad_to_deg(-a) + 90.0, "seed": i})
	# Harvestable trees (jittered grid, fixed seed; every candidate consumes the same RNG calls).
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var spacing := 6.5
	var cells := int(196.0 / spacing) + 1
	var tid := 0
	for j in cells:
		for i in cells:
			var p := Vector2(-98.0 + float(i) * spacing + rng.randf_range(0.4, spacing - 0.4), -98.0 + float(j) * spacing + rng.randf_range(0.4, spacing - 0.4))
			var roll := rng.randf()
			var sroll := rng.randf()
			var seed_v := rng.randi() % 3
			var yaw := rng.randf() * 360.0
			var sc := rng.randf_range(0.85, 1.18)
			if roll > _tree_density(p, dn.get_noise_2d(p.x, p.y) * 0.5 + 0.5):
				continue
			if not _clear_of(t, p, 2.1, ex, occ, {"edge": 95.0}):
				continue
			occ.add(p, 2.1)
			var sp := _species(p, sroll)
			out["trees"].append({"id": "tree_%d" % tid, "pos": h.call(p), "species": sp, "seed": seed_v, "yaw": yaw, "scale": sc})
			tid += 1
	# Harvestable boulders.
	rng.seed = 515151
	var rid := 0
	var rspacing := 13.0
	var rcells := int(196.0 / rspacing) + 1
	for j in rcells:
		for i in rcells:
			var p := Vector2(-98.0 + float(i) * rspacing + rng.randf_range(1.0, rspacing - 1.0), -98.0 + float(j) * rspacing + rng.randf_range(1.0, rspacing - 1.0))
			var roll := rng.randf()
			var seed_v := rng.randi() % 3
			var yaw := rng.randf() * 360.0
			var sc := rng.randf_range(0.75, 1.05)
			var d := 0.17
			d += 0.55 * (1.0 - _smooth(14.0, 30.0, p.distance_to(q)))
			d += 0.15 * (1.0 - _smooth(8.0, 30.0, p.distance_to(SL.MINE_MOUTH)))
			if p.length() < 40.0:
				d += 0.12
			if roll > d:
				continue
			if not _clear_of(t, p, 1.5, ex, occ, {"edge": 94.0, "rock": 0.5}):
				continue
			occ.add(p, 1.5)
			out["rocks"].append({"id": "rock_%d" % rid, "pos": h.call(p), "seed": seed_v, "yaw": yaw, "scale": sc})
			rid += 1
	# Quarry boulders ring (a few extra, deterministic).
	for i in 5:
		var a := base_a + PI + lerpf(-1.0, 1.0, float(i) / 4.0)
		var p := q + Vector2(cos(a), sin(a)) * 9.5
		if _clear_of(t, p, 1.4, [], occ, {"edge": 94.0, "rock": 0.6}):
			occ.add(p, 1.4)
			out["rocks"].append({"id": "rock_q%d" % i, "pos": h.call(p), "seed": i, "yaw": float(i) * 70.0, "scale": 0.9})
	# Berry bushes: the glade, around the Haven, meadow edges and the pond.
	rng.seed = 616161
	var bid := 0
	var bush_sets: Array = [[_lm("glade"), 7.0, 17.0, 11], [Vector2.ZERO, 20.0, 30.0, 4], [_lm("meadow"), 15.0, 24.0, 3], [Vector2(46, 52), 15.0, 20.0, 2]]
	for bs in bush_sets:
		var c: Vector2 = bs[0]
		var placed := 0
		var tries := 0
		while placed < int(bs[3]) and tries < 200:
			tries += 1
			var a := rng.randf() * TAU
			var r := rng.randf_range(float(bs[1]), float(bs[2]))
			var p := c + Vector2(cos(a), sin(a)) * r
			var seed_v := rng.randi() % 3
			if not _clear_of(t, p, 1.1, ex if c != Vector2.ZERO else ex.slice(1), occ, {"edge": 94.0}):
				continue
			occ.add(p, 1.1)
			out["bushes"].append({"id": "bush_%d" % bid, "pos": h.call(p), "seed": seed_v, "yaw": rng.randf() * 360.0})
			bid += 1
			placed += 1
	# Sticks, stones and grass tufts: guaranteed near the Haven, plus a sprinkle everywhere.
	var small_ex: Array = [[Vector2.ZERO, 15.5], [SL.SIGN, 1.5]]
	for id in Layout.SPAWN_HINTS:
		small_ex.append([Layout.SPAWN_HINTS[id], 2.0])
	for c in Layout.STREAM_CROSSINGS:
		small_ex.append([c, 4.0])
	var smalls := [["sticks", "stick", 20, 26, 717171], ["stones", "stone", 20, 26, 727272], ["tufts", "tuft", 16, 24, 737373]]
	for sd in smalls:
		rng.seed = int(sd[4])
		var list: Array = out[sd[0]]
		var n_near := int(sd[2])
		var n_far := int(sd[3])
		var tries := 0
		while list.size() < n_near and tries < 800:
			tries += 1
			var a := rng.randf() * TAU
			var r := rng.randf_range(HAVEN_RING[0], HAVEN_RING[1])
			var p := Vector2(cos(a), sin(a)) * r
			if not _clear_of(t, p, 0.6, small_ex, occ, {"edge": 90.0, "path_margin": 0.2, "stream": 3.6, "pond": 1.0, "rock": 0.3}):
				continue
			occ.add(p, 0.6)
			list.append({"id": "%s_%d" % [sd[1], list.size()], "pos": h.call(p), "seed": list.size(), "yaw": rng.randf() * 360.0})
		tries = 0
		var target := n_near + n_far
		while list.size() < target and tries < 1500:
			tries += 1
			var p := Vector2(rng.randf_range(-92.0, 92.0), rng.randf_range(-92.0, 92.0))
			if p.length() < 34.0:
				continue
			if not _clear_of(t, p, 0.6, small_ex, occ, {"edge": 92.0, "path_margin": 0.2, "stream": 3.6, "pond": 1.0, "rock": 0.3}):
				continue
			occ.add(p, 0.6)
			list.append({"id": "%s_%d" % [sd[1], list.size()], "pos": h.call(p), "seed": list.size(), "yaw": rng.randf() * 360.0})
	# Decorative forest belt on the hills (and just inside the boundary).
	rng.seed = 818181
	var dspacing := 5.2
	var dcells := int(256.0 / dspacing) + 1
	for j in dcells:
		for i in dcells:
			var p := Vector2(-128.0 + float(i) * dspacing + rng.randf_range(0.3, dspacing - 0.3), -128.0 + float(j) * dspacing + rng.randf_range(0.3, dspacing - 0.3))
			var roll := rng.randf()
			var sroll := rng.randf()
			var variant := rng.randi() % 2
			var yaw := rng.randf() * TAU
			var sc := rng.randf_range(0.95, 1.35)
			var e := edge_dist(p)
			if e < 95.5 or e > 131.0:
				continue
			if roll > 0.8:
				continue
			if t.stream_distance(p.x, p.y) < 4.5 or t.rock_at(p.x, p.y) > 0.55:
				continue
			if not occ.is_free(p, 1.8):
				continue
			occ.add(p, 1.8)
			var sp := "pine" if p.y < -60.0 or (p.x > 60.0 and p.y < 0.0) or sroll < 0.3 else _species(p, sroll)
			if sp == "blossom" and sroll > 0.2:
				sp = "oak"
			out["decor_trees"].append([sp, variant, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc, sc)), h.call(p) - Vector3(0, 0.1, 0)), e < 107.0])
	# Mine highland: a few pines on top of the cliff (decor, keeps the mine silhouette).
	# Plain bushes, mushrooms and fallen logs near trees.
	rng.seed = 919191
	var trees: Array = out["trees"]
	for k in trees.size():
		var tp: Vector3 = trees[k]["pos"]
		var r1 := rng.randf()
		var r2 := rng.randf()
		var a := rng.randf() * TAU
		var a2 := rng.randf() * TAU
		var v := rng.randi() % 4
		if r1 < 0.45:
			var p := Vector2(tp.x, tp.z) + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 3.2)
			if _clear_of(t, p, 0.9, ex, occ, {"edge": 97.0}):
				occ.add(p, 0.9)
				out["decor_bushes"].append([v % 3, Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * rng.randf_range(0.7, 1.1)), h.call(p))])
		if r2 < 0.35:
			var p2 := Vector2(tp.x, tp.z) + Vector2(cos(a2), sin(a2)) * rng.randf_range(1.0, 1.8)
			if t.path_at(p2.x, p2.y) < 0.05:
				out["mushrooms"].append([v, Transform3D(Basis(Vector3.UP, a2).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), h.call(p2))])
	rng.seed = 929292
	var logs := 0
	var ltries := 0
	while logs < 11 and ltries < 300:
		ltries += 1
		var p := Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-90.0, 90.0))
		var yaw := rng.randf() * TAU
		if p.length() < 24.0 or not _clear_of(t, p, 1.9, ex, occ, {"edge": 92.0}):
			continue
		occ.add(p, 1.9)
		out["logs"].append([logs % 3, Transform3D(Basis(Vector3.UP, yaw), h.call(p) - Vector3(0, 0.06, 0))])
		logs += 1
	# Decorative big rocks: along the mine cliff foot, quarry terraces and scattered.
	rng.seed = 939393
	var f := SL.MINE_FACING.normalized()
	var perp := Vector2(-f.y, f.x)
	for i in 14:
		var lat := lerpf(-24.0, 16.0, float(i) / 13.0) + rng.randf_range(-1.0, 1.0)
		if absf(lat) < 5.0:
			continue
		var p := SL.MINE_MOUTH + perp * lat + f * (0.011 * lat * lat * -1.0 + rng.randf_range(0.5, 2.0))
		out["decor_rocks"].append([rng.randi() % 3, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 2.2)), h.call(p) - Vector3(0, 0.4, 0)), true])
	# ...and up the cliff face itself (ledges) so it reads as rock, not a smooth slope.
	for i in 16:
		var lat := rng.randf_range(-26.0, 18.0)
		var up := rng.randf_range(1.5, 7.0)
		var p := SL.MINE_MOUTH + perp * lat + f * (-(up + 0.011 * lat * lat))
		if absf(lat) < 4.5 and up < 4.0:
			continue
		out["decor_rocks"].append([rng.randi() % 3, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.9)), h.call(p) - Vector3(0, 0.5, 0)), false])
	for i in 10:
		var a := base_a + rng.randf_range(-1.3, 1.3)
		var p := q + Vector2(cos(a), sin(a)) * rng.randf_range(15.0, 22.0)
		out["decor_rocks"].append([rng.randi() % 3, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.0, 1.8)), h.call(p) - Vector3(0, 0.3, 0)), true])
	var drt := 0
	while drt < 26:
		drt += 1
		var p := Vector2(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0))
		var sc := rng.randf_range(0.8, 1.8)
		if edge_dist(p) < 60.0 or not _clear_of(t, p, sc * 1.1, ex, occ, {"edge": 104.0, "rock": 0.8}):
			continue
		occ.add(p, sc * 1.1)
		out["decor_rocks"].append([rng.randi() % 3, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), h.call(p) - Vector3(0, 0.3, 0)), edge_dist(p) < 106.0])
	# Brambles around the Thornthicket.
	rng.seed = 949494
	var th := _lm("thicket")
	var bt := 0
	var brt := 0
	while bt < 26 and brt < 400:
		brt += 1
		var a := rng.randf() * TAU
		var p := th + Vector2(cos(a), sin(a)) * rng.randf_range(6.0, 19.0)
		if not _clear_of(t, p, 1.0, [[th, 5.5]], occ, {"edge": 96.0}):
			continue
		occ.add(p, 1.0)
		out["brambles"].append([bt % 3, Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), h.call(p))])
		bt += 1
	_plan_flowers(t, out)
	return out


static func _plan_flowers(t: RefCounted, out: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 959595
	var fn := FastNoiseLite.new()
	fn.seed = 321
	fn.frequency = 0.12
	var colors: Array = Flora.PETAL_COLORS
	var ok := func(p: Vector2) -> bool:
		if t.path_at(p.x, p.y) > 0.1 or t.stream_distance(p.x, p.y) < 3.4 or t.pond_distance(p.x, p.y) < 1.2 or t.rock_at(p.x, p.y) > 0.3:
			return false
		return edge_dist(p) < 100.0
	# [centre, r0, r1, count, palette indices, kinds]
	var fields: Array = [
		[_lm("meadow"), 0.0, 27.0, 2300, [0, 1, 2, 3, 4, 5], [0, 1, 2]],
		[Vector2.ZERO, 16.5, 23.0, 420, [0, 1, 5], [0, 2]],
		[_lm("glade"), 4.0, 20.0, 320, [2, 5, 0], [0, 1]],
		[Vector2(46, 52), 12.0, 20.0, 240, [3, 4, 0], [2, 0]],
		[_lm("old_oak"), 4.0, 12.0, 90, [0, 1], [0]],
		[_lm("ruin"), 6.0, 18.0, 120, [4, 3, 0], [2, 0]],
	]
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
			# clump by noise so fields have drifts of colour
			if fn.get_noise_2d(p.x, p.y) < -0.15 and r0 < 1.0:
				continue
			if not ok.call(p):
				continue
			var ci := int(pal[int(floor(cr * pal.size())) % pal.size()])
			var patch := int(floor(fn.get_noise_2d(p.x * 0.5, p.y * 0.5) * 3.0 + 3.0)) % pal.size()
			if rng.randf() < 0.6:
				ci = int(pal[patch])
			out["flowers"].append([Vector3(p.x, t.height_at(p.x, p.y), p.y), yaw, sc, colors[ci], 0.0, int(kinds[kr])])
	# Scatter
	for i in 700:
		var p := Vector2(rng.randf_range(-95.0, 95.0), rng.randf_range(-95.0, 95.0))
		var ci := rng.randi() % colors.size()
		var yaw := rng.randf() * TAU
		var sc := rng.randf_range(0.7, 1.1)
		var kind := rng.randi() % 3
		if fn.get_noise_2d(p.x, p.y) < 0.15 or not ok.call(p) or p.length() < 16.0:
			continue
		out["flowers"].append([Vector3(p.x, t.height_at(p.x, p.y), p.y), yaw, sc, colors[ci], 0.0, kind])
	# Restoration bloom (hidden until the Ward is restored): spreading out from the Ward Stone.
	var ws := SL.WARD_STONE
	for i in 1400:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 36.0
		var p := ws + Vector2(cos(a), sin(a)) * r
		var ci: int = [0, 1, 2, 5, 4][rng.randi() % 5]
		var yaw := rng.randf() * TAU
		var sc := rng.randf_range(0.85, 1.35)
		var kind := rng.randi() % 3
		if r < 3.2 or p.distance_to(SL.CAMPFIRE) < 2.6 or p.distance_to(Vector2(0, 7)) < 1.5:
			continue
		if t.stream_distance(p.x, p.y) < 3.2 or t.rock_at(p.x, p.y) > 0.3:
			continue
		out["restore_flowers"].append([Vector3(p.x, t.height_at(p.x, p.y), p.y), yaw, sc, colors[ci], r, kind])


# --- Building --------------------------------------------------------------------------------------------

func _ready() -> void:
	name = "Vegetation"
	if plan_data.is_empty():
		plan_data = plan(terrain)
	var t0 := Time.get_ticks_usec()
	_build_resource_nodes()
	var t1 := Time.get_ticks_usec()
	_build_decor_forest()
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
		_add_node(gt, {"node_id": d["id"], "kind": "tree", "visual": sp, "seed": d["seed"], "yaw": d["yaw"],
			"scale": d["scale"], "name": TREE_NAMES.get(sp, "Tree")}, d["pos"])
	var gr := _group("Rocks")
	for d in plan_data["rocks"]:
		_add_node(gr, {"node_id": d["id"], "kind": "rock", "seed": d["seed"], "yaw": d["yaw"], "scale": d["scale"]}, d["pos"] - Vector3(0, 0.12, 0))
	for d in plan_data["ores"]:
		_add_node(gr, {"node_id": d["id"], "kind": "ore", "seed": d["seed"], "yaw": d["yaw"]}, d["pos"] - Vector3(0, 0.1, 0))
	var gb := _group("BerryBushes")
	for d in plan_data["bushes"]:
		_add_node(gb, {"node_id": d["id"], "kind": "bush", "seed": d["seed"], "yaw": d["yaw"]}, d["pos"])
	var gs := _group("Forage")
	for d in plan_data["sticks"]:
		_add_node(gs, {"node_id": d["id"], "kind": "stick", "seed": d["seed"], "yaw": d["yaw"]}, d["pos"])
	for d in plan_data["stones"]:
		_add_node(gs, {"node_id": d["id"], "kind": "stone", "seed": d["seed"], "yaw": d["yaw"]}, d["pos"])
	for d in plan_data["tufts"]:
		_add_node(gs, {"node_id": d["id"], "kind": "grass", "seed": d["seed"], "yaw": d["yaw"]}, d["pos"])


## Clears the terrain grass mask under small props so the GPU grass never hides them. Call before
## the grass texture is created.
static func clear_grass_for(t: RefCounted, p: Dictionary) -> void:
	for d in p.get("sticks", []):
		t.clear_grass(d["pos"].x, d["pos"].z, 1.3)
	for d in p.get("stones", []):
		t.clear_grass(d["pos"].x, d["pos"].z, 1.3)
	for d in p.get("tufts", []):
		t.clear_grass(d["pos"].x, d["pos"].z, 1.1)
	for d in p.get("rocks", []):
		t.clear_grass(d["pos"].x, d["pos"].z, 1.6)
	for d in p.get("ores", []):
		t.clear_grass(d["pos"].x, d["pos"].z, 1.6)


func _build_decor_forest() -> void:
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
			var parts := NodeVisuals.tree_parts(sp, variant)
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
		var parts := NodeVisuals.tree_parts(sp, int(bits[1]))
		var xfs: Array = by_key[key]
		g.add_child(Props.multimesh(parts["trunk"], NodeVisuals.bark_material(), xfs, "Trunks_" + String(key).replace("|", "_"), 0.0, false))
		g.add_child(Props.multimesh(parts["crown"], NodeVisuals.crown_material(sp), xfs, "Crowns_" + String(key).replace("|", "_")))


func _build_decor() -> void:
	var g := _group("Decor")
	# Bushes
	var bush_lists: Array = [[], [], []]
	for d in plan_data["decor_bushes"]:
		bush_lists[int(d[0])].append(d[1])
	var bush_mat := NodeVisuals.foliage_material(0.03, 1.4, 0.022, 0.18)
	for v in 3:
		if not bush_lists[v].is_empty():
			g.add_child(Props.multimesh(NodeVisuals.bush_mesh(v, Palette.FOLIAGE_DARK, Palette.FOLIAGE_LIGHT), bush_mat, bush_lists[v], "Bushes%d" % v, 130.0))
	# Mushrooms
	var mush_lists: Array = [[], [], [], []]
	for d in plan_data["mushrooms"]:
		mush_lists[int(d[0])].append(d[1])
	var mush_mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.45}), 0.012)
	for v in 4:
		if not mush_lists[v].is_empty():
			g.add_child(Props.multimesh(Props.mushroom_cluster(v), mush_mat, mush_lists[v], "Mushrooms%d" % v, 60.0, false))
	# Fallen logs (with collision)
	var log_body := StaticBody3D.new()
	log_body.name = "LogCollision"
	log_body.collision_layer = 1
	log_body.collision_mask = 0
	log_body.set_meta("surface", "wood")
	g.add_child(log_body)
	for d in plan_data["logs"]:
		var xf: Transform3D = d[1]
		var mi := Props.instance(Props.fallen_log(int(d[0])), NodeVisuals.bark_material(), 150.0)
		mi.transform = xf
		g.add_child(mi)
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.33
		cap.height = 3.2
		cs.shape = cap
		cs.transform = Transform3D(xf.basis * Basis(Vector3.BACK, deg_to_rad(90.0)), xf.origin + Vector3(0, 0.3, 0))
		log_body.add_child(cs)
	# Decor rocks
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
			var mesh := NodeVisuals.boulder_mesh(v, Palette.STONE, 0.8)
			var cs := CollisionShape3D.new()
			cs.shape = NodeVisuals._convex_for(mesh, "boulder|%d|%s|%.2f" % [v, Palette.STONE.to_html(), 0.8])
			cs.transform = xf
			rock_body.add_child(cs)
	for v in 3:
		if not rock_lists[v].is_empty():
			g.add_child(Props.multimesh(NodeVisuals.boulder_mesh(v, Palette.STONE, 0.8), NodeVisuals.rock_material(), rock_lists[v], "BigRocks%d" % v))
	# Brambles
	var br_lists: Array = [[], [], []]
	for d in plan_data["brambles"]:
		br_lists[int(d[0])].append(d[1])
	var br_mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.2, "wind": 0.02, "wind_height": 1.2}), 0.015)
	for v in 3:
		if not br_lists[v].is_empty():
			g.add_child(Props.multimesh(Props.bramble(v), br_mat, br_lists[v], "Brambles%d" % v, 120.0))


func _build_flowers() -> void:
	var g := _group("Flowers")
	var mat := Flora.make_material(false)
	# Chunk flowers spatially so visibility ranges and culling work per area.
	var chunks: Dictionary = {}
	for f in plan_data["flowers"]:
		var p: Vector3 = f[0]
		var key := Vector2i(int(floor(p.x / 40.0)), int(floor(p.z / 40.0)))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(f)
	for key in chunks:
		flower_nodes.append_array(Flora.build_fields(g, chunks[key], mat, "Field_%d_%d" % [key.x, key.y], 110.0))


## The restoration flowers (hidden until play_restoration or when the Ward is already restored).
func build_restore_flowers(parent: Node3D) -> ShaderMaterial:
	var mat := Flora.make_material(true)
	Flora.build_fields(parent, plan_data["restore_flowers"], mat, "BloomFlowers", 160.0)
	return mat
