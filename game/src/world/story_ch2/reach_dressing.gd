extends RefCounted
## Hallowmere Reach story dressing (module C9; MP §9 "the final celebration should add useful lights, recipes
## and pleasant interactions to Commons", MP §11 steps 18 / 20). A lightweight layer the region adds on top of
## itself, entirely derived from flags (so it is right after any load):
##   stage 2  ch2_choir_defeated (step 18 "Lanterns on Every Road"): festival lanterns in four warm colours
##            float above the roads, and the Commons' central lantern pole becomes the Lanternwake lantern
##            (lanternwake_pole.gd attached to the region's "LanternPole"; a stand-alone festival pole at the
##            layout's pole spot while the region has none) - the place to "Celebrate" (after the homecoming)
##   stage 3  chapter_two_complete: the Lanternwake lantern is a lasting safe light; ringing its festival chimes
##            is a pleasant repeatable interaction
## (Stage 1, the steady safe-light road posts after ch2_lamps_linked, belongs to the region itself:
## src/world/reach/road_lights.gd. This layer adds nothing then.)
## Road lanterns float 4.6 m above the road centrelines (data/hallowmere_layout.gd PATHS when the region
## defines them, else straight roads between its points), one MultiMesh pair per 48 m cell ("RouteLanterns/
## Cell_<x>_<z>/Bodies|Caps", each with its own visibility range), no collision, no shadows; they
## skip every landmark circle, spawn, arch and the Commons' pumpkin arch, and never touch the outpost lot.
## Entry point (requested one-line call at the end of the Reach region's build):
##   static func build(area: Node3D) -> Node3D   (idempotent; always returns the dressing root)

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const FestivalLights := preload("res://src/world/story_ch2/festival_lights.gd")
const PoleScript := preload("res://src/world/story_ch2/lanternwake_pole.gd")

const NODE_NAME := "StoryCh2ReachDressing"
const POLE_NAME := "hr_lanternwake_pole"
## Roads that get festival lanterns (ids of Reach PATHS; missing ids are skipped).
const FESTIVAL_ROADS := ["arrival_road", "main_road", "west_road", "east_road", "north_road", "bellhouse_road",
	"quarry_bellhouse", "pools_road", "orchard_pools", "orchard_candleyard", "pools_candleyard"]
## Fallback roads (point / landmark ids) when the layout has no PATHS (the wave A placeholder region).
const ROUTES := [
	["waygate_arrival", "commons_arch"],
	["commons_arch", "conservatory_arch"],
	["conservatory_arch", "orchard_arch"],
	["conservatory_arch", "quarry_arch"],
	["hr_conservatory", "manor_arch"],
	["manor_arch", "bellhouse_stair"],
	["orchard_arch", "hr_pools"],
	["hr_pools", "hr_candleyard"],
]
const SPACING := 8.5            # metres between lanterns along a road
const HEIGHT := 4.6             # above the ground (above head height, arches and road-light posts)
const EDGE_MARGIN := 1.0        # stay this far outside every landmark circle
const SPAWN_CLEARANCE := 3.0
const ARCH_CLEARANCE := 5.0
const VIS_RANGE := 120.0
## Road lanterns are grouped into square cells this size (one MultiMesh pair each) so the visibility range
## culls by area instead of hiding every road lantern at once far from the region's middle.
const CELL := 48.0


## 0 nothing, 2 festival roads + the Commons lantern, 3 after the Lanternwake.
static func stage() -> int:
	if Story.flag(Story.COMPLETE_FLAG):
		return 3
	if Story.flag(Story.CHOIR_FLAG):
		return 2
	return 0


static func build(area: Node3D) -> Node3D:
	if area == null or not is_instance_valid(area):
		return null
	var old := area.get_node_or_null(NODE_NAME)
	if old != null:
		return old as Node3D
	var root := Node3D.new()
	root.name = NODE_NAME
	root.add_to_group("story_ch2_dressing")
	area.add_child(root)
	var st := stage()
	if st < 2:
		return root
	# The region is being built with the Choir gone: Krystal is arriving back in the Reach (step 18). The
	# activity tracker does the same on Events.area_loaded; whichever runs first counts, once.
	Story.note_area(Story.REACH_AREA)
	var hfn := func(x: float, z: float) -> float: return _height(area, x, z)
	root.add_child(FestivalLights.lanterns_chunked(route_points(st, hfn), "RouteLanterns", VIS_RANGE, CELL))
	var pole: Node3D = PoleScript.new()
	pole.name = POLE_NAME
	var region_pole := find_region_pole(area)
	if region_pole != null:
		pole.setup({"attach": true, "stage": st})
		root.add_child(pole)
		pole.global_position = region_pole.global_position
	else:
		var cands := pole_candidates()
		var cp := commons_pole()
		if cp != Vector2.INF:
			cands.push_front(cp)       # the layout's pole spot, free while the region has no pole of its own
		pole.setup({"candidates": cands, "stage": st})
		root.add_child(pole)
		var c: Vector2 = cands[0]
		pole.position = Vector3(c.x, _height(area, c.x, c.y), c.y)
	return root


## The region's own central Commons pole node (src/world/reach/commons.gd "LanternPole" at Reach.COMMONS
## "pole"), or null while the region has none (the placeholder region).
static func find_region_pole(area: Node) -> Node3D:
	var cp := commons_pole()
	if cp == Vector2.INF or area == null:
		return null
	var n := area.find_child("LanternPole", true, false)
	if n is Node3D and Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z).distance_to(cp) < 1.0:
		return n as Node3D
	return null


static func _height(area: Node, x: float, z: float) -> float:
	if area != null and area.has_method("height_at"):
		return float(area.height_at(x, z))
	return 0.0


static func _layout(key: String) -> Variant:
	return (Reach as Script).get_script_constant_map().get(key, null)


## The Commons' own central lantern pole (Reach.COMMONS["pole"]) when the region defines one, else INF.
static func commons_pole() -> Vector2:
	var commons: Variant = _layout("COMMONS")
	if commons is Dictionary and (commons as Dictionary).get("pole") is Vector2:
		return (commons as Dictionary)["pole"]
	return Vector2.INF


static func point(id: String) -> Vector2:
	if Reach.POINTS.has(id):
		return Reach.POINTS[id]
	if Reach.LANDMARKS.has(id):
		return Reach.LANDMARKS[id]["pos"]
	return Vector2.ZERO


## The road polylines lanterns follow: Reach PATHS when present, else the straight fallback ROUTES.
static func roads() -> Array:
	var out: Array = []
	var paths: Variant = _layout("PATHS")
	if paths is Dictionary and not (paths as Dictionary).is_empty():
		for id in FESTIVAL_ROADS:
			var pl: Variant = (paths as Dictionary).get(id)
			if pl is Array and (pl as Array).size() >= 2:
				out.append(pl)
		return out
	for r in ROUTES:
		out.append([point(String(r[0])), point(String(r[1]))])
	return out


## Points a lantern must keep clear of: [[Vector2, radius], ...] (spawns, arches, the pumpkin arch, the
## crossroads signpost).
static func keep_clear() -> Array:
	var out: Array = []
	for sid in Reach.SPAWNS:
		out.append([Reach.SPAWNS[sid]["pos"], SPAWN_CLEARANCE])
	for aid in Reach.ARCHES:
		out.append([Reach.ARCHES[aid]["pos"], ARCH_CLEARANCE])
	var commons: Variant = _layout("COMMONS")
	if commons is Dictionary and (commons as Dictionary).get("pumpkin_arch") is Vector2:
		out.append([(commons as Dictionary)["pumpkin_arch"], ARCH_CLEARANCE])
	var cross: Variant = _layout("CROSSROADS")
	if cross is Vector2:
		out.append([cross, ARCH_CLEARANCE])
	return out


## True when p is on open road: inside the region, outside every landmark circle (+ margin), clear of the
## keep_clear() points and never over the outpost build area.
static func is_open_road(p: Vector2, clear: Array = []) -> bool:
	if not Reach.is_inside(p, 6.0):
		return false
	for id in Reach.LANDMARKS:
		var l: Dictionary = Reach.LANDMARKS[id]
		if p.distance_to(l["pos"]) < float(l["radius"]) + EDGE_MARGIN:
			return false
	if p.distance_to(Reach.OUTPOST_BUILD_AREA["center"]) < float(Reach.OUTPOST_BUILD_AREA["radius"]) + 2.0:
		return false
	for c in clear:
		if p.distance_to(c[0]) < float(c[1]):
			return false
	return true


## Deterministic lantern points along the roads for a stage: [{"pos", "color", "scale", "yaw"}] ([] below 2).
## height_fn(x, z) -> ground height.
static func route_points(st: int, height_fn: Callable) -> Array:
	var out: Array = []
	if st < 2:
		return out
	var clear := keep_clear()
	var n := 0
	for road in roads():
		var pl: Array = road
		var carry := SPACING * 0.5          # distance along the road to the next lantern
		for i in range(pl.size() - 1):
			var a: Vector2 = pl[i]
			var b: Vector2 = pl[i + 1]
			var seg := b - a
			var length := seg.length()
			if length < 0.01:
				continue
			var d := carry
			while d <= length:
				var p := a + seg * (d / length)
				if is_open_road(p, clear):
					var y: float = float(height_fn.call(p.x, p.y)) + HEIGHT + 0.25 * sin(float(n) * 1.7)
					out.append({"pos": Vector3(p.x, y, p.y), "color": FestivalLights.color_for(n), "scale": 1.0, "yaw": float(n) * 0.9})
					n += 1
				d += SPACING
			carry = d - length
	return out


## Where a stand-alone Lanternwake lantern may stand when the region has no Commons pole of its own (the
## placeholder region): inside the Commons, off the main north-south road (|x| >= 5), >= 4 m from every spawn
## and arch, well outside the outpost build area. The lantern takes the first candidate its physics check
## finds clear once the region has settled.
static func pole_candidates() -> Array:
	return [Vector2(9, 54), Vector2(-7, 44), Vector2(11, 63), Vector2(-9, 70), Vector2(13, 49), Vector2(8, 42), Vector2(6, 46)]
