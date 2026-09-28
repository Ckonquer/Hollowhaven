extends "res://src/world/area_base.gd"
## PLACEHOLDER base for the Chapter Two areas (wave A3 "flow & areas"). Every new area id of
## docs/CHAPTER_TWO_SPEC.md §1 loads a tiny, cheap stand-in built on this script so the game flow
## (travel, spawns, saving, respawn, the Lantern Road) works end to end before wave C replaces each one
## with its real content. Keep these small: flat collidable floors, rectangular "rooms" that are the
## zones, a few unshadowed lights, a label saying PLACEHOLDER, exits back to where Krystal came from.
## Wave C: replace the area script in scenes/<area>.tscn; keep every spawn id, zone id and exit target.
##
## API used by the area scripts (all build calls happen inside _ready()):
##   build_environment(opts)                          WorldEnvironment + light(s)
##   add_ground(rect: Rect2 (x, z), y, color)          solid floor slab (layer 1) with its top at y
##   add_walls(rect, y, height)                        invisible perimeter walls (layer 1)
##   add_room(id, rect, y, safe, color)               a zone (rectangle) with a coloured floor tile
##   place_spawn(id, pos: Vector3, yaw)               register_spawn + Marker3D "Spawn_<id>"
##   add_safe_spot(center, radius)                    extra safe circle that is NOT a zone (arches...)
##   add_exit(params, pos, yaw) / add_rest_point(params, pos, yaw)
## Overrides: get_zone_at (room rectangle, else nearest room, else the circle zones), is_safe_zone,
## height_at, validate_position (inside `bounds`, then the area_base ray checks).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const AreaExit := preload("res://src/world/areas_ch2/area_exit.gd")
const RestPoint := preload("res://src/world/areas_ch2/rest_point.gd")

const SPAWN_LIFT := 0.08       # spawns stand this far above the floor (like the surface)

var placeholder := true
var rooms: Array = []          # [{id, rect: Rect2 (x, z), y: float, safe: bool}]
var safe_spots: Array = []     # [{center: Vector3, radius: float}] safe circles that are not zones
var bounds := Rect2()          # playable XZ rectangle (empty = unbounded)
var floor_y := 0.0
var exits: Dictionary = {}     # name -> exit node
var ambience := ""             # ambience loop started on arrival (existing sound names only)
var _room_ids: Dictionary = {}
var _mats: Dictionary = {}


# --- Building helpers ------------------------------------------------------------------------------

## opts: bg (Color), ambient (Color), ambient_energy, sun (bool), sun_color, sun_energy, sun_pitch (deg),
## lamps: [[Vector3, Color, energy, range], ...] (unshadowed omni lights), fog (bool), fog_color.
func build_environment(opts: Dictionary) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = opts.get("bg", Color("2a2433"))
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = opts.get("ambient", Color("8a7fa0"))
	env.ambient_light_energy = float(opts.get("ambient_energy", 0.6))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if bool(opts.get("fog", false)):
		env.fog_enabled = true
		env.fog_light_color = opts.get("fog_color", Color("3a3048"))
		env.fog_density = float(opts.get("fog_density", 0.01))
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)
	if bool(opts.get("sun", false)):
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.light_color = opts.get("sun_color", Color("ffd6a0"))
		sun.light_energy = float(opts.get("sun_energy", 1.0))
		sun.shadow_enabled = false
		sun.rotation_degrees = Vector3(float(opts.get("sun_pitch", -50.0)), float(opts.get("sun_yaw", 35.0)), 0.0)
		add_child(sun)
	for l in opts.get("lamps", []):
		var o := OmniLight3D.new()
		o.position = l[0]
		o.light_color = l[1]
		o.light_energy = float(l[2])
		o.omni_range = float(l[3])
		o.shadow_enabled = false
		add_child(o)


func _mat(color: Color) -> Material:
	var key := color.to_html()
	if not _mats.has(key):
		_mats[key] = Mat.toon(color, {"noise": 0.1, "noise_scale": 1.5, "rim": 0.15})
	return _mats[key]


## A solid floor slab covering `rect` (x, z) with its top at `y`.
func add_ground(rect: Rect2, y: float, color: Color, surface: String = "stone") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", surface)
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, 2.0, rect.size.y)
	cs.shape = box
	var c := rect.get_center()
	cs.position = Vector3(c.x, y - 1.0, c.y)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = rect.size
	mi.mesh = pm
	mi.material_override = _mat(color)
	mi.position = Vector3(c.x, y, c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return body


## Invisible walls around `rect` so nobody walks off the placeholder floor.
func add_walls(rect: Rect2, y: float, height: float = 8.0) -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var c := rect.get_center()
	var sides := [
		[Vector3(c.x, y + height * 0.5, rect.position.y - 0.5), Vector3(rect.size.x + 2.0, height, 1.0)],
		[Vector3(c.x, y + height * 0.5, rect.end.y + 0.5), Vector3(rect.size.x + 2.0, height, 1.0)],
		[Vector3(rect.position.x - 0.5, y + height * 0.5, c.y), Vector3(1.0, height, rect.size.y + 2.0)],
		[Vector3(rect.end.x + 0.5, y + height * 0.5, c.y), Vector3(1.0, height, rect.size.y + 2.0)],
	]
	for s in sides:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = s[1]
		cs.shape = box
		cs.position = s[0]
		body.add_child(cs)


## A rectangular room = zone `id` (safe or not) with a coloured floor tile (visual only; the floor
## itself comes from add_ground).
func add_room(id: String, rect: Rect2, y: float, safe: bool, color: Color) -> void:
	rooms.append({"id": id, "rect": rect, "y": y, "safe": safe})
	_room_ids[id] = true
	var c := rect.get_center()
	add_zone(id, Vector3(c.x, y, c.y), rect.size.length() * 0.5, safe)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = rect.size - Vector2(0.6, 0.6)
	mi.mesh = pm
	mi.material_override = _mat(color)
	mi.position = Vector3(c.x, y + 0.02, c.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	add_label(id + (" (safe)" if safe else ""), Vector3(c.x, y + 3.2, c.y), 48)


func place_spawn(id: String, pos: Vector3, yaw: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, pos.y + SPAWN_LIFT, pos.z))
	register_spawn(id, xf)
	var markers := get_node_or_null("SpawnPoints")
	if markers == null:
		markers = Node3D.new()
		markers.name = "SpawnPoints"
		add_child(markers)
	var m := Marker3D.new()
	m.name = "Spawn_" + id
	markers.add_child(m)
	m.transform = xf


func add_safe_spot(center: Vector3, radius: float) -> void:
	safe_spots.append({"center": center, "radius": radius})


func add_label(text: String, pos: Vector3, size: int = 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(1, 0.95, 0.85, 0.9)
	l.outline_size = 8
	l.position = pos
	add_child(l)
	return l


## An exit (door, stair, hatch) - see area_exit.gd for params. Stands at `pos`, facing `yaw`.
func add_exit(exit_name: String, params: Dictionary, pos: Vector3, yaw: float) -> Node3D:
	var e: Node3D = AreaExit.new()
	e.setup(params)
	add_child(e)
	e.position = pos
	e.rotation.y = yaw
	e.name = "Exit_" + exit_name
	exits[exit_name] = e
	return e


## A placeholder checkpoint (rest = respawn point + save), with a small safe circle around it.
func add_rest_point(spawn_id: String, pos: Vector3, yaw: float, safe_radius: float = 4.0) -> Node3D:
	var r: Node3D = RestPoint.new()
	r.setup({"area": area_id, "spawn": spawn_id})
	add_child(r)
	r.position = pos
	r.rotation.y = yaw
	add_safe_spot(pos, safe_radius)
	return r


# --- Queries -----------------------------------------------------------------------------------------

func room_at(pos: Vector3) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	for r in rooms:
		if (r["rect"] as Rect2).has_point(p):
			return r
	return {}


## Room rectangle containing pos, else the nearest room (so indoors is never "no zone"), else the
## circular zones (smallest containing wins, area_base rule).
func get_zone_at(pos: Vector3) -> String:
	if not rooms.is_empty():
		var r := room_at(pos)
		if not r.is_empty():
			return String(r["id"])
		var best := ""
		var best_d := INF
		for rr in rooms:
			var d := (rr["rect"] as Rect2).get_center().distance_to(Vector2(pos.x, pos.z))
			if d < best_d:
				best_d = d
				best = String(rr["id"])
		return best
	return super.get_zone_at(pos)


func is_safe_zone(pos: Vector3) -> bool:
	var r := room_at(pos)
	if not r.is_empty() and bool(r["safe"]):
		return true
	for s in safe_spots:
		var c: Vector3 = s["center"]
		if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s["radius"]):
			return true
	for z in zones:
		if _room_ids.has(String(z["id"])) or not bool(z["safe"]):
			continue
		var zc: Vector3 = z["center"]
		if Vector2(pos.x - zc.x, pos.z - zc.z).length() <= float(z["radius"]):
			return true
	return false


func height_at(x: float, z: float) -> float:
	var r := room_at(Vector3(x, 0.0, z))
	if not r.is_empty():
		return float(r["y"])
	return floor_y


func is_inside_bounds(pos: Vector3, margin: float = 0.0) -> bool:
	if bounds.size == Vector2.ZERO:
		return true
	return bounds.grow(-margin).has_point(Vector2(pos.x, pos.z))


func validate_position(pos: Vector3) -> Variant:
	if not is_inside_bounds(pos, 0.5):
		return null
	return super.validate_position(pos)


func on_player_spawned(_player: Node3D) -> void:
	if ambience != "" and Audio.has_method("play_ambience") and Audio.has_sound(ambience):
		Audio.play_ambience(ambience, 3.0)
