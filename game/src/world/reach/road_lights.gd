extends Node3D
## "Lanterns on every road": festival lamp posts along the main road and the three branch roads
## (Reach.ROAD_LIGHT_ROADS). Dark until the lanterns are linked at the Conservatory (flag ch2_lamps_linked),
## then lit for good (MP §11 step 9: persistent safe-light routes; the quest layer's ch2_safe_light_routes counts
## too). The linking ceremony calls
## play_link(origin): three warm motes run from the pedestal along the roads (west = garden, east = quarry,
## north = manor) and every post lights as a mote passes it. Loaded saves show the lit state instantly.
## Lights: every second post carries a small unshadowed OmniLight with a distance fade.
##   posts: Array of {"node": Node3D, "glass": MeshInstance3D, "light": OmniLight3D|null, "road": String}

const Reach := preload("res://data/hallowmere_layout.gd")
const Mat := preload("res://src/art/mat.gd")
const Props := preload("res://src/world/reach/reach_props.gd")
const Fx := preload("res://src/world/common/fx.gd")

const LINKED_FLAG := "ch2_lamps_linked"
## Set by the quest layer when step ch2_lamps_linked completes (the committed "persistent safe-light routes").
const SAFE_ROUTES_FLAG := "ch2_safe_light_routes"
const GLOW := Color("ffc66e")
const MOTE_SPEED := 15.0
const MOTE_COLORS := {"west": Color("d8e07a"), "east": Color("ffae5a"), "north": Color("c9a0ff")}

var terrain: RefCounted
var posts: Array = []
var lit := false
var animating := false
var _lit_mat: Material
var _dark_mat: Material
var _motes: Array = []


func _ready() -> void:
	name = "RoadLights"
	_lit_mat = Mat.glow(GLOW, 2.2)
	_dark_mat = Mat.toon(Color("5a4a44"), {"rim": 0.3})
	_build_posts()
	set_lit_instant(should_be_lit())
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)


func _on_flag_set(flag: String, value: Variant) -> void:
	if (flag == LINKED_FLAG or flag == SAFE_ROUTES_FLAG) and bool(value):
		_light_if_idle.call_deferred()     # the ceremony (play_link, same frame) takes over if it runs


## The roads stay lit for good once the lanterns are linked (or the quest layer committed the safe routes).
static func should_be_lit() -> bool:
	return bool(GameState.get_flag(LINKED_FLAG)) or bool(GameState.get_flag(SAFE_ROUTES_FLAG))


func _light_if_idle() -> void:
	if not animating and not lit and should_be_lit():
		set_lit_instant(true)


## Where the posts go: along each road every ROAD_LIGHT_SPACING m, alternating sides, clear of arches,
## the crossroads, the brook crossings, the Conservatory and the spawns.
static func post_spots(t: RefCounted) -> Array:
	var out: Array = []
	var avoid: Array = [[Reach.CROSSROADS, 6.0], [Reach.CONSERVATORY["center"], 9.5]]
	for id in Reach.ARCHES:
		avoid.append([Reach.ARCHES[id]["pos"], 4.5])
	for id in Reach.SPAWNS:
		avoid.append([Reach.SPAWNS[id]["pos"], 2.5])
	for c in Reach.BROOK_CROSSINGS:
		avoid.append([c["pos"], 6.0])
	for road in Reach.ROAD_LIGHT_ROADS:
		var curve: PackedVector2Array = t.path_curves.get(road, PackedVector2Array())
		if curve.size() < 3:
			continue
		var half: float = float(Reach.PATH_WIDTHS.get(road, 1.5))
		var along := 0.0
		var next := Reach.ROAD_LIGHT_SPACING * 0.5
		var side := 1.0
		for i in range(1, curve.size() - 1):
			along += curve[i].distance_to(curve[i - 1])
			if along < next:
				continue
			var d := (curve[i + 1] - curve[i - 1]).normalized()
			var p := curve[i] + Vector2(-d.y, d.x) * side * (half + 0.95)
			var ok: bool = t.stream_distance(p.x, p.y) > 4.0 and not t.is_water(p.x, p.y)
			for a in avoid:
				if p.distance_to(a[0]) < float(a[1]):
					ok = false
			if not ok:
				continue
			out.append({"road": String(road), "pos": p, "face": curve[i]})
			next = along + Reach.ROAD_LIGHT_SPACING
			side = -side
	return out


func _build_posts() -> void:
	var wood := Props.wood_mat()
	var mesh := Props.road_post_mesh()
	var n := 0
	for s in post_spots(terrain):
		var p: Vector2 = s["pos"]
		var root := Node3D.new()
		root.name = "RoadLight_%d" % n
		add_child(root)
		root.position = Vector3(p.x, terrain.height_at(p.x, p.y) - 0.03, p.y)
		# the bracket (local +X) leans over the road
		var to_road: Vector2 = s["face"] - p
		root.rotation.y = atan2(-to_road.y, to_road.x)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = wood
		mi.visibility_range_end = 150.0
		root.add_child(mi)
		var glass := MeshInstance3D.new()
		glass.mesh = Props.lantern_glass_mesh()
		glass.material_override = _dark_mat
		glass.position = Props.GLASS_POS
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(glass)
		var light: OmniLight3D = null
		if n % 2 == 0:
			light = OmniLight3D.new()
			light.light_color = GLOW
			light.light_energy = 0.0
			light.omni_range = 6.0
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 38.0
			light.distance_fade_length = 10.0
			light.position = Props.GLASS_POS
			light.visible = false
			root.add_child(light)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("surface", "wood")
		root.add_child(body)
		Props.cyl_col(body, Vector3.ZERO, 0.12, 2.4)
		posts.append({"node": root, "glass": glass, "light": light, "road": String(s["road"])})
		n += 1


func _light_post(p: Dictionary, on: bool) -> void:
	var g: MeshInstance3D = p["glass"]
	g.material_override = _lit_mat if on else _dark_mat
	var l: Variant = p["light"]
	if l is OmniLight3D:
		(l as OmniLight3D).visible = on
		(l as OmniLight3D).light_energy = 0.9 if on else 0.0


func set_lit_instant(on: bool) -> void:
	lit = on
	for p in posts:
		_light_post(p, on)


func lit_count() -> int:
	var c := 0
	for p in posts:
		if (p["glass"] as MeshInstance3D).material_override == _lit_mat:
			c += 1
	return c


## The routes the three motes take from `origin` (the pedestal): {"west"|"east"|"north": PackedVector3Array}.
func mote_routes(origin: Vector3) -> Dictionary:
	var main: PackedVector2Array = terrain.path_curves.get("main_road", PackedVector2Array())
	var south := PackedVector2Array([Vector2(origin.x, origin.z), Vector2(0, 12.8)])
	var up := PackedVector2Array()
	for i in range(main.size() - 1, -1, -1):
		if main[i].y <= Reach.CROSSROADS.y + 0.05:
			up.append(main[i])
	var out := {}
	for dir in ["west", "east"]:
		var pts := south.duplicate()
		pts.append_array(up)
		pts.append_array(terrain.path_curves.get(dir + "_road", PackedVector2Array()))
		out[dir] = _lift(pts)
	var n := PackedVector2Array([Vector2(origin.x, origin.z), Vector2(0, -0.8)])
	n.append_array(terrain.path_curves.get("north_road", PackedVector2Array()))
	out["north"] = _lift(n)
	return out


func _lift(pts: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pts:
		out.append(Vector3(p.x, terrain.height_at(p.x, p.y) + 1.6, p.y))
	return out


static func _length(pts: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += pts[i].distance_to(pts[i - 1])
	return l


static func _point_at(pts: PackedVector3Array, dist: float) -> Vector3:
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		if acc + seg >= dist:
			return pts[i - 1].lerp(pts[i], (dist - acc) / maxf(seg, 0.0001))
		acc += seg
	return pts[pts.size() - 1] if pts.size() > 0 else Vector3.ZERO


static func _distance_along(pts: PackedVector3Array, p: Vector3) -> float:
	var best := 1e9
	var best_d := 0.0
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := pts[i].distance_to(pts[i - 1])
		var d := Vector2(pts[i].x - p.x, pts[i].z - p.z).length()
		if d < best:
			best = d
			best_d = acc + seg
		acc += seg
	return best_d


## The ceremony: three motes run along the roads and light every post they pass. Returns its duration
## (seconds). The flag is set by the caller BEFORE this runs; the end state never depends on the animation.
func play_link(origin: Vector3) -> float:
	if not is_inside_tree():
		set_lit_instant(true)
		return 0.0
	animating = true
	var routes := mote_routes(origin)
	var longest := 0.0
	for dir in routes:
		var pts: PackedVector3Array = routes[dir]
		if pts.size() < 2:
			continue
		var length := _length(pts)
		var secs := length / MOTE_SPEED
		longest = maxf(longest, secs)
		var mote := _make_mote(MOTE_COLORS.get(dir, GLOW))
		add_child(mote)
		mote.global_position = pts[0]
		_motes.append(mote)
		var tw := create_tween()
		var move := func(d: float) -> void:
			if is_instance_valid(mote):
				mote.global_position = _point_at(pts, d)
		tw.tween_method(move, 0.0, length, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void:
			if is_instance_valid(mote):
				Fx.burst(self, mote.global_position, "sparkle", 1.2)
				mote.queue_free())
		# posts on this mote's road (and the shared main road for the first two) light as it passes
		for p in posts:
			var road := String(p["road"])
			if road != dir + "_road" and not (road == "main_road" and dir == "west"):
				continue
			var at := _distance_along(pts, (p["node"] as Node3D).global_position)
			var delay := clampf(at / maxf(length, 0.01), 0.0, 1.0) * secs
			var post: Dictionary = p
			get_tree().create_timer(delay, false).timeout.connect(func() -> void:
				if is_instance_valid(self):
					_light_post(post, true))
	var end := func() -> void:
		if is_instance_valid(self):
			animating = false
			set_lit_instant(true)
	get_tree().create_timer(longest + 0.6, false).timeout.connect(end)
	return longest + 0.6


func _make_mote(c: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "LinkMote"
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.2
	sm.height = 0.4
	sm.radial_segments = 10
	sm.rings = 5
	s.mesh = sm
	s.material_override = Mat.glow(c, 3.0)
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = 1.8
	l.omni_range = 5.0
	l.shadow_enabled = false
	root.add_child(l)
	return root
