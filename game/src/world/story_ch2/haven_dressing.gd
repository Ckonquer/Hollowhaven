extends Node3D
## The Haven's Lanternwake keepsake (module C9, MP §9 / §17): once Chapter Two is complete, five small
## festival lanterns drift slowly around the Ward Stone. They float INSIDE the Ward Stone's blocked circle
## (data/world_layout.gd BUILD_AREA "Ward Stone", r = 3.5 m), where nothing can ever be built, above the ring
## stones and clear of the monolith: nothing is placed in Krystal's house or her buildable ground, nothing
## collides, nothing casts shadows. Before the ending this builds nothing at all.
## Entry point (surface annex contract, src/world/surface/annexes.gd ANNEX_SCRIPTS):
##   static func build(area: Node3D) -> Node3D   (idempotent; null when there is nothing to show)
## The activity tracker also calls it through story_ch2.ensure_dressing() when the surface loads, and the
## ending adds it at once (so it appears without a reload).

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const Layout := preload("res://data/world_layout.gd")
const FestivalLights := preload("res://src/world/story_ch2/festival_lights.gd")

const NODE_NAME := "StoryCh2HavenDressing"
const COUNT := 5
const RADIUS := 2.15            # metres from the stone's centre (monolith half-depth ~0.45, ring stones at 2.9)
const HEIGHT := 3.05            # above the stone's base (the cap sits at ~3.2-3.45, ring stones <= 1.5)
const SPIN := 0.12              # radians per second (a slow drift)
const BOB := 0.12

var ring: Node3D
var _t := 0.0


## Adds the keepsake to the surface area when Chapter Two is complete. Idempotent.
static func build(area: Node3D) -> Node3D:
	if area == null or not is_instance_valid(area):
		return null
	var old := area.get_node_or_null(NODE_NAME)
	if old != null:
		return old as Node3D
	if not Story.flag(Story.COMPLETE_FLAG):
		return null
	var node: Node3D = (load("res://src/world/story_ch2/haven_dressing.gd") as Script).new()
	node.name = NODE_NAME
	area.add_child(node)
	node.position = stone_base(area)
	return node


## Where the Ward Stone stands: its node (group "ward_stone") when the area has one, else the layout's
## blocked circle centre on the terrain.
static func stone_base(area: Node3D) -> Vector3:
	if area.is_inside_tree():
		for n in area.get_tree().get_nodes_in_group("ward_stone"):
			if n is Node3D and area.is_ancestor_of(n):
				return (n as Node3D).global_position
	var c := stone_center_2d()
	var y := 0.0
	if area.has_method("height_at"):
		y = float(area.height_at(c.x, c.y))
	return Vector3(c.x, y, c.y)


static func stone_center_2d() -> Vector2:
	for b in Layout.BUILD_AREA.get("blocked", []):
		if String((b as Dictionary).get("name", "")) == "Ward Stone":
			return (b as Dictionary)["center"]
	return Vector2(0, -6)


static func stone_blocked_radius() -> float:
	for b in Layout.BUILD_AREA.get("blocked", []):
		if String((b as Dictionary).get("name", "")) == "Ward Stone":
			return float((b as Dictionary)["radius"])
	return 3.5


## Local lantern positions (relative to the stone's base), deterministic.
static func lantern_points() -> Array:
	var out: Array = []
	for i in COUNT:
		var a := TAU * float(i) / float(COUNT) + 0.3
		out.append({"pos": Vector3(cos(a) * RADIUS, HEIGHT + 0.18 * sin(a * 2.0), sin(a) * RADIUS),
			"color": FestivalLights.color_for(i), "scale": 0.8, "yaw": a})
	return out


## Where the lanterns are right now (world space; they drift). The MultiMesh itself is the draw data.
func world_points() -> Array:
	var out: Array = []
	if ring == null:
		return out
	for p in lantern_points():
		out.append(ring.global_transform * (p["pos"] as Vector3))
	return out


func _ready() -> void:
	add_to_group("story_ch2_dressing")
	ring = FestivalLights.lanterns(lantern_points(), "KeepsakeLanterns", 70.0)
	add_child(ring)
	var l := FestivalLights.warm_light(0.55, 6.0)
	l.name = "KeepsakeGlow"
	l.position = Vector3(0, HEIGHT, 0)
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	if ring != null:
		ring.rotation.y = _t * SPIN
		ring.position.y = sin(_t * 0.7) * BOB
