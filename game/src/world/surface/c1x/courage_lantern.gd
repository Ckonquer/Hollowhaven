extends RefCounted
## Brave Little Steps (MP 6.4, MP 7; optional goal opt_brave_little_steps; spec 7.1 "Mochi's courage lantern"):
## a small, always-lit, safe lantern beside the OUTSIDE mine threshold (the legacy mine_threshold spot, in the
## surface area; nobody has to enter the mine to earn the courage that lets Mochi enter it). With the Comfort
## Ribbon tied on (Friends panel) and Mochi beside Krystal (following, or waiting right here after refusing
## the mine), resting by the lantern plays "Mochi checks its ribbon. Then it takes one very brave little step."
## and sets c1x_mochi_courage (companion.gd brave_step); the optional log pays the goal's reward itself.
## The original refusal is untouched until then. Placed by src/world/surface/annexes.gd (ANNEX_SCRIPTS):
##   CourageLantern.build(area)            CourageLantern.grass_clearings() -> [[Vector2, radius]]
## The node (group "interactable", "courage_lantern", "light_source"): get_interaction(player) / interact(player).

const Layout := preload("res://data/world_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

## Beside the threshold, 2.3 m to the east of the approach axis of the mine mouth (the side away from the
## mine_exit spawn and Tobin's side door), inside the legacy mine-mouth vegetation clearing, 8.9 m from the
## tunnel: it never blocks the path in, the spawn, or the spot where Mochi waits.
const SIDE_OFFSET := 2.3
const MOCHI_RADIUS := 7.0          # Mochi must be this close to the lantern
const DANGER_RADIUS := 16.0        # an enemy hunting Krystal this close: not "safe" right now
const LIGHT_RADIUS := 3.2
const NODE_NAME := "CourageLantern"


## The lantern's ground position (x, z) from the layout hints (pure: also used before the grass is built).
static func site() -> Vector2:
	var th: Vector2 = Layout.SPAWN_HINTS.get("mine_threshold", Vector2(50, -66))
	var facing := Vector2(-6, 10).normalized()          # surface_layout.gd MINE_FACING (the tunnel faces this way)
	var east := Vector2(-facing.y, facing.x) * -1.0      # perpendicular, toward +x
	if east.x < 0.0:
		east = -east
	return th + east * SIDE_OFFSET


static func grass_clearings() -> Array:
	return [[site(), 1.0]]


static func build(area: Node3D) -> Node3D:
	if area == null or area.get_node_or_null(NODE_NAME) != null:
		return null
	var s := site()
	var n := Lantern.new()
	n.name = NODE_NAME
	area.add_child(n)
	var y := 0.0
	if area.has_method("height_at"):
		y = float(area.height_at(s.x, s.y))
	n.global_position = Vector3(s.x, y - 0.02, s.y)
	return n


class Lantern extends Node3D:
	var light_radius: float = LIGHT_RADIUS
	var light_strength: float = 0.7
	var light: OmniLight3D
	var _flame: Node3D
	var _t: float = 0.0
	var _enemies: Array = []           # the enemy group, re-read at most every ENEMY_REFRESH_MS (get_interaction
	var _enemies_ms: int = -100000     # is polled ~12 times a second while Krystal stands at the lantern)
	const ENEMY_REFRESH_MS := 500

	func _ready() -> void:
		add_to_group("interactable")
		add_to_group("courage_lantern")
		add_to_group("light_source")
		var wood := Mat.outlined(Mat.toon(Palette.WOOD_DARK), 0.012)
		var metal := Mat.outlined(Mat.toon(Color("5a4a3e")), 0.01)
		Kit.add(self, Kit.cylinder(0.07, 0.09, 1.3, wood, 10), Vector3(0, 0.65, 0))
		Kit.add(self, Kit.cylinder(0.2, 0.24, 0.1, wood, 12), Vector3(0, 0.05, 0))
		Kit.add(self, Kit.box(Vector3(0.42, 0.05, 0.08), wood), Vector3(0.14, 1.28, 0))
		var hook := Node3D.new()
		add_child(hook)
		hook.position = Vector3(0.3, 1.02, 0)
		Kit.add(hook, Kit.cylinder(0.1, 0.12, 0.05, metal, 10), Vector3(0, 0.2, 0))
		Kit.add(hook, Kit.cylinder(0.12, 0.1, 0.05, metal, 10), Vector3(0, -0.06, 0))
		Kit.add(hook, Kit.box(Vector3(0.2, 0.24, 0.2), Mat.transparent(Color(1.0, 0.86, 0.6, 0.35), true)), Vector3(0, 0.07, 0))
		_flame = Kit.add(hook, Kit.sphere(0.055, Mat.glow(Palette.LANTERN_GLOW, 2.4), 8, 10), Vector3(0, 0.06, 0))
		# A pink ribbon bow on the post: the lantern "for" a Comfort Ribbon.
		var rib := Mat.outlined(Mat.toon(Color("f4a0ab")), 0.008)
		for sgn in [-1.0, 1.0]:
			Kit.add(self, Kit.sphere(0.05, rib, 8, 10), Vector3(0.05 * sgn, 0.95, 0.08), Vector3(0, 0, 20.0 * sgn), Vector3(1.0, 0.62, 0.4))
		Kit.add(self, Kit.sphere(0.022, rib, 6, 8), Vector3(0, 0.95, 0.09))
		light = OmniLight3D.new()
		light.name = "Light"
		light.light_color = Palette.LANTERN_GLOW
		light.omni_range = 4.0
		light.light_energy = 1.1
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 36.0
		light.distance_fade_length = 8.0
		light.position = Vector3(0.3, 1.1, 0)
		add_child(light)
		var post := StaticBody3D.new()
		post.name = "Post"
		post.collision_layer = 1
		post.collision_mask = 0
		var pcs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.12
		cyl.height = 1.3
		pcs.shape = cyl
		pcs.position = Vector3(0, 0.65, 0)
		post.add_child(pcs)
		add_child(post)
		var ib := StaticBody3D.new()
		ib.name = "Interact"
		ib.collision_layer = 16
		ib.collision_mask = 0
		var ics := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 0.55
		ics.shape = sph
		ics.position = Vector3(0.15, 0.95, 0)
		ib.add_child(ics)
		add_child(ib)
		_t = randf() * 10.0

	func is_light_active() -> bool:
		return true

	func _process(delta: float) -> void:
		_t += delta
		if light != null:
			var steady := bool(Settings.get_value("reduce_flashing"))
			var wob := 1.0 if steady else 1.0 + sin(_t * 6.1) * 0.03 + sin(_t * 11.3) * 0.02
			light.light_energy = 1.1 * wob
		if _flame != null:
			_flame.scale = Vector3(1.0, 1.15 + sin(_t * 8.0) * 0.05, 1.0)

	func _mochi() -> Node3D:
		var m: Variant = Game.companion_nodes.get("mochi")
		return m if m is Node3D and is_instance_valid(m) and (m as Node3D).is_inside_tree() else null

	func _mochi_near() -> Node3D:
		var m := _mochi()
		if m == null or m.global_position.distance_to(global_position) > MOCHI_RADIUS:
			return null
		var md := String(m.get("mode"))
		if md != "follow" and md != "wait":
			return null
		return m

	func _danger() -> bool:
		var p: Node3D = Game.player if Game.player != null and is_instance_valid(Game.player) else null
		var center := p.global_position if p != null else global_position
		var now := Time.get_ticks_msec()
		if now - _enemies_ms > ENEMY_REFRESH_MS and is_inside_tree():
			_enemies_ms = now
			_enemies = get_tree().get_nodes_in_group("enemy")
		for e in _enemies:
			if not is_instance_valid(e):
				continue
			if e is Node3D and e.has_method("is_threatening") and bool(e.is_threatening()) \
					and (e as Node3D).global_position.distance_to(center) < DANGER_RADIUS:
				return true
		return false

	func get_interaction(_player: Node = null) -> Dictionary:
		var text := "Rest by the lantern with Mochi"
		if bool(GameState.get_flag("c1x_mochi_courage")):
			return {"text": "Mochi's brave lantern", "enabled": false, "reason": "Mochi is brave enough now"}
		if not GameState.is_befriended("mochi"):
			return {"text": "A small, warm lantern", "enabled": false, "reason": "It glows softly by the mine"}
		if String(GameState.companion("mochi").get("ribbon", "")) != "comfort_ribbon":
			return {"text": text, "enabled": false, "reason": "Mochi needs something comforting first: a Comfort Ribbon"}
		if _mochi_near() == null:
			return {"text": text, "enabled": false, "reason": "Walk here together with Mochi"}
		if _danger():
			return {"text": text, "enabled": false, "reason": "It isn't safe here right now"}
		return {"text": text, "enabled": true}

	func interact(_player: Node = null) -> void:
		if not bool(get_interaction(_player).get("enabled", false)):
			return
		var m := _mochi_near()
		if m != null and m.has_method("brave_step"):
			m.call("brave_step", global_position)
