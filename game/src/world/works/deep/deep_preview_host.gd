extends "res://src/world/area_base.gd"
## Standalone host for Hushed Works rooms 9-14 (tests, and `--preview=` visual checks while the real Works
## area script is being built): a small stub of the hub's east end (room 7's east wall with the door at
## Layout.HUB_DOOR, spawn `refuge`) + the deep rooms on the shared Below builder, exactly as the Works
## area will call them: Builder.new(self, seed, rooms) -> RoomsDeep.build(self, builder) -> builder.finish().
## Implements the small area API rooms_deep.gd uses (add_safe_area(center, r, zone), checkpoints, zones by
## room box) so its safety/zone rules can be tested without the real area.

const Builder := preload("res://src/world/below/below_builder.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const RoomsDeep := preload("res://src/world/works/rooms_deep.gd")

## Stub hub box west of the door (never shipped as content: the real hub is works module A's room 7).
const STUB_HUB := {"hw_stub_hub": {"space": "refuge", "zone": "hw_refuge", "x0": 30.0, "x1": 40.0, "z0": -6.0, "z1": 6.0,
	"y": -18.0, "h": 6.0, "open": {"e": [[-1.6, 1.6, 3.4]]}}}
const REFUGE_POS := Vector3(34.0, -18.0, 0.0)

var builder: Builder
var safe_areas: Array = []
var checkpoints: Dictionary = {}
var build_ms: float = 0.0
var deep: Node3D = null
var with_environment: bool = true


func _ready() -> void:
	area_id = "hushed_works"
	var t0 := Time.get_ticks_usec()
	if with_environment:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("07060b")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("4a4458")
		env.ambient_light_energy = 0.55
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.name = "Environment"
		we.environment = env
		add_child(we)
	var rooms := STUB_HUB.duplicate(true)
	rooms.merge(Layout.ROOMS)
	builder = Builder.new(self, 4242, rooms)
	builder.begin("hw_stub_hub")
	builder.shell("hw_stub_hub", Color("6a7a5a"), Color("5a6a4a"), Color("3a4a32"))
	register_spawn("refuge", Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)), REFUGE_POS + Vector3(0, 0.05, 0)))
	add_zone("hw_refuge", REFUGE_POS, 7.0, true)
	RoomsDeep.build(self, builder)
	builder.finish()
	deep = get_node_or_null("WorksDeep")
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func add_safe_area(center: Vector3, radius: float, zone: String) -> void:
	for s in safe_areas:
		if (s["center"] as Vector3).distance_to(center) < 0.1:
			return
	safe_areas.append({"center": center, "radius": radius})
	add_zone(zone, center, radius, true)


func get_zone_at(pos: Vector3) -> String:
	var r := Layout.room_at(pos)
	if r == "":
		if Rect2(30.0, -6.0, 10.0, 12.0).has_point(Vector2(pos.x, pos.z)):
			return "hw_refuge"
		r = Layout.nearest_room(pos)
	return Layout.zone_of_room(r)


func get_room_at(pos: Vector3) -> String:
	return Layout.room_at(pos)


func is_safe_zone(pos: Vector3) -> bool:
	if Rect2(30.0, -6.0, 10.0, 12.0).has_point(Vector2(pos.x, pos.z)) and absf(pos.y + 18.0) < 3.0:
		return true
	for s in safe_areas:
		var c: Vector3 = s["center"]
		if absf(pos.y - c.y) < 3.0 and Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s["radius"]):
			return true
	return false
