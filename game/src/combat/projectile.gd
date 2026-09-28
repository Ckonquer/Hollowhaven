extends Node3D
## Shared pooled projectile (docs/CHAPTER_TWO_SPEC.md section 9): Krystal's wand sparks, companion bolts and
## enemy throws all use it. Readable (glowing orb + short tail, optional tiny light), straight flight, finite
## range, never passes through world or structures (every physics tick one ray over the travelled segment,
## mask world|structure), hits the first node of its target groups the segment touches, and respects the
## combat conventions (health -> apply_damage, can_be_hit_by, on_hit_blocked, knockback, hit_radius,
## get_aim_point, hit_color). Bounded: MAX_LIVE projectiles overall, optional per-shooter cap, finished
## projectiles are hidden and reused (pool), never freed per shot.
##
##   const Projectile := preload("res://src/combat/projectile.gd")
##   var p: Node3D = Projectile.fire({"shooter": self, "from": hand_pos, "target": enemy,   # or "dir": Vector3
##       "damage": 9.0, "speed": 16.0, "range": 14.0, "groups": ["enemy"], "color": Color("ffe08a")})
##   if p == null: ...   # refused (cap reached / nothing to parent to)
##
## fire() params (all optional except damage and from + dir/target/target_pos):
##   shooter: Node         credited as the damage source; its own body is ignored by the rays
##   from: Vector3         start point (world)
##   dir: Vector3          flight direction (normalised here) | target: Node3D (aims at Combat.aim_point) |
##                         target_pos: Vector3
##   damage: float         applied through the target's health (0 = harmless, e.g. a light pulse)
##   speed (16), range (14), radius (0.22), lifetime (range / speed + 0.1): flight limits
##   groups (["enemy"])    target groups ("player" for enemy throws; companions are never targets)
##   knockback (0)         force passed to target.knockback(dir, force) on a damaging hit
##   los_mask (1|32)       what stops the projectile (world | structure)
##   color, light (false)  look; light adds a small shadowless OmniLight (at most MAX_LIGHTS at once)
##   max_per_shooter (0)   refuse when this shooter already has that many in flight (0 = only MAX_LIVE)
##   parent                node to live under (default: Game.area, else the current scene)
##   on_hit: Callable      func(target: Node, dealt: float) after a hit (dealt 0 = blocked/refused)
##   hitstop (false)       emit Events.hitstop on a damaging hit
##   impact_fx (true)      HitFx impact / spark
##   kind ("")             free-form tag (e.g. "wand", "spore") for callers and tests

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Mat := preload("res://src/art/mat.gd")

const MAX_LIVE := 32
const POOL_MAX := 24
const MAX_LIGHTS := 4
const TARGET_REFRESH_FRAMES := 6          # the per-group target lists are shared and re-read at most this often
const DEFAULT_LOS_MASK := 1 | 32
const DEFAULT_HALF_HEIGHT := 0.55         # vertical half extent of a target's hit capsule around its aim point
const TAIL_LENGTH := 3.2

static var _live: Array = []
static var _pool: Array = []
static var _lights_live: int = 0
static var _group_cache: Dictionary = {}  # group -> Array of nodes
static var _group_frame: Dictionary = {}  # group -> physics frame of the last read
static var _meshes: Dictionary = {}       # "%.3f" radius -> SphereMesh

var active: bool = false
var shooter: Node = null
var shooter_id: int = 0
var kind: String = ""
var damage: float = 0.0
var speed: float = 16.0
var radius: float = 0.22
var groups: Array = ["enemy"]
var knockback: float = 0.0
var color: Color = Color("ffe08a")
var velocity := Vector3.ZERO
var range_left: float = 0.0
var life_left: float = 0.0
var travelled: float = 0.0
var on_hit: Callable = Callable()
var hitstop: bool = false
var impact_fx: bool = true
var result: String = ""                   # "" in flight, then "hit" | "blocked" | "wall" | "expired"
var hit_target: Node = null

var _orb: MeshInstance3D
var _tail: MeshInstance3D
var _light: OmniLight3D
var _light_on: bool = false
var _query: PhysicsRayQueryParameters3D
var _exclude: Array[RID] = []
var _last_s: float = 0.0                  # segment parameter of the last target found by _first_target


# =====================================================================================================
# Static API
# =====================================================================================================

## Launches a projectile (see the header for params). Returns it, or null when refused.
static func fire(params: Dictionary) -> Node3D:
	_prune()
	if _live.size() >= MAX_LIVE:
		return null
	var sh: Variant = params.get("shooter")
	var shooter_node: Node = sh if sh is Node and is_instance_valid(sh) else null
	var cap := int(params.get("max_per_shooter", 0))
	if cap > 0 and shooter_node != null and live_count(shooter_node) >= cap:
		return null
	var parent := _pick_parent(params, shooter_node)
	if parent == null:
		return null
	var from: Vector3 = params.get("from", Vector3.ZERO)
	var dir := _launch_dir(params, from)
	if dir.length_squared() < 0.0001:
		return null
	var p = _take_from_pool(parent)
	p._launch(params, shooter_node, from, dir)
	return p


## Projectiles in flight (optionally only those of one shooter).
static func live_count(of_shooter: Object = null) -> int:
	_prune()
	if of_shooter == null:
		return _live.size()
	var id := of_shooter.get_instance_id()
	var n := 0
	for p in _live:
		if int(p.shooter_id) == id:
			n += 1
	return n


static func pool_size() -> int:
	_prune()
	return _pool.size()


## Ends every projectile in flight (area changes are handled automatically: they are freed with the area).
static func stop_all() -> void:
	_prune()
	for p in _live.duplicate():
		p._finish("expired")


## Pure geometry: squared distance between segment [p1, q1] and segment [p2, q2], and the parameter (0..1)
## of the closest point on the first segment. Returns Vector2(dist2, s). No allocation.
static func segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector2:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.000001 and e <= 0.000001:
		return Vector2(r.dot(r), 0.0)
	if a <= 0.000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 0.000001:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return Vector2((c1 - c2).length_squared(), s)


static func _prune() -> void:
	for i in range(_live.size() - 1, -1, -1):
		var p: Variant = _live[i]
		if not is_instance_valid(p) or not (p as Node).is_inside_tree():
			_live.remove_at(i)
	for i in range(_pool.size() - 1, -1, -1):
		if not is_instance_valid(_pool[i]):
			_pool.remove_at(i)


static func _pick_parent(params: Dictionary, shooter_node: Node) -> Node:
	var p: Variant = params.get("parent")
	if p is Node and is_instance_valid(p) and (p as Node).is_inside_tree():
		return p
	if Game.area != null and is_instance_valid(Game.area) and Game.area.is_inside_tree():
		if shooter_node == null or not shooter_node.is_inside_tree() or Game.area.is_ancestor_of(shooter_node):
			return Game.area
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	if shooter_node != null and shooter_node.get_parent() != null:
		return shooter_node.get_parent()
	return null


static func _launch_dir(params: Dictionary, from: Vector3) -> Vector3:
	var t: Variant = params.get("target")
	if t is Node3D and is_instance_valid(t):
		return (Combat.aim_point(t) - from).normalized()
	var tp: Variant = params.get("target_pos")
	if tp is Vector3:
		return ((tp as Vector3) - from).normalized()
	var d: Variant = params.get("dir")
	if d is Vector3 and (d as Vector3).length_squared() > 0.0001:
		return (d as Vector3).normalized()
	return Vector3.ZERO


static func _take_from_pool(parent: Node) -> Node3D:
	var p = null
	while not _pool.is_empty():
		var c: Variant = _pool.pop_back()
		if is_instance_valid(c):
			p = c
			break
	if p == null:
		p = load("res://src/combat/projectile.gd").new()
		p.name = "Projectile"
		parent.add_child(p)
	elif p.get_parent() != parent:
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
		parent.add_child(p)
	return p


static func _targets(group: String) -> Array:
	var frame := Engine.get_physics_frames()
	if int(_group_frame.get(group, -1000)) + TARGET_REFRESH_FRAMES <= frame or not _group_cache.has(group):
		var tree := Engine.get_main_loop() as SceneTree
		_group_cache[group] = tree.get_nodes_in_group(group) if tree != null else []
		_group_frame[group] = frame
	return _group_cache[group]


## Forces the next target lookup to re-read the groups (tests; targets added this frame).
static func invalidate_targets() -> void:
	_group_frame.clear()


static func _sphere_mesh(r: float) -> SphereMesh:
	var key := "%.3f" % r
	if _meshes.has(key):
		return _meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	_meshes[key] = m
	return m


# =====================================================================================================
# Instance
# =====================================================================================================

func _ready() -> void:
	top_level = true
	if _orb != null:
		return
	_query = PhysicsRayQueryParameters3D.new()
	_query.collide_with_areas = false
	_query.hit_back_faces = true
	_orb = MeshInstance3D.new()
	_orb.name = "Orb"
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
	_tail = MeshInstance3D.new()
	_tail.name = "Tail"
	_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tail)
	if not active:
		visible = false
		set_physics_process(false)


func _launch(params: Dictionary, shooter_node: Node, from: Vector3, dir: Vector3) -> void:
	if _query == null:
		_ready()
	shooter = shooter_node
	shooter_id = shooter_node.get_instance_id() if shooter_node != null else 0
	kind = String(params.get("kind", ""))
	damage = maxf(float(params.get("damage", 0.0)), 0.0)
	speed = maxf(float(params.get("speed", 16.0)), 0.5)
	radius = clampf(float(params.get("radius", 0.22)), 0.03, 1.0)
	var rng := maxf(float(params.get("range", 14.0)), 0.2)
	range_left = rng
	life_left = float(params.get("lifetime", rng / speed + 0.1))
	if life_left <= 0.0:
		life_left = rng / speed + 0.1
	travelled = 0.0
	var g: Variant = params.get("groups", ["enemy"])
	groups = (g as Array).duplicate() if g is Array else ["enemy"]
	knockback = maxf(float(params.get("knockback", 0.0)), 0.0)
	var col: Variant = params.get("color", Color("ffe08a"))
	color = col if col is Color else Color("ffe08a")
	var oh: Variant = params.get("on_hit", Callable())
	on_hit = oh if oh is Callable else Callable()
	hitstop = bool(params.get("hitstop", false))
	impact_fx = bool(params.get("impact_fx", true))
	result = ""
	hit_target = null
	velocity = dir * speed
	_exclude.clear()
	if shooter_node is CollisionObject3D:
		_exclude.append((shooter_node as CollisionObject3D).get_rid())
	_query.exclude = _exclude
	_query.collision_mask = int(params.get("los_mask", DEFAULT_LOS_MASK))
	var mat := Mat.glow(color, 2.6)
	_orb.mesh = _sphere_mesh(radius)
	_orb.material_override = mat
	_tail.mesh = _sphere_mesh(radius * 0.6)
	_tail.material_override = Mat.glow(color.lerp(Color.WHITE, 0.25), 1.6)
	_tail.scale = Vector3(1.0, 1.0, TAIL_LENGTH)
	_tail.position = Vector3(0, 0, radius * TAIL_LENGTH * 0.45)
	global_position = from
	_face(dir)
	_set_light(bool(params.get("light", false)))
	active = true
	visible = true
	set_physics_process(true)
	if not _live.has(self):
		_live.append(self)


func _face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var up := Vector3.UP if absf(dir.normalized().dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	global_transform.basis = Basis.looking_at(dir, up)


func _set_light(on: bool) -> void:
	if on and not _light_on and _lights_live < MAX_LIGHTS:
		if _light == null:
			_light = OmniLight3D.new()
			_light.name = "Glow"
			_light.shadow_enabled = false
			_light.omni_range = 2.4
			_light.light_energy = 0.9
			add_child(_light)
		_light.light_color = color
		_light.visible = true
		_light_on = true
		_lights_live += 1
	elif not on and _light_on:
		_light.visible = false
		_light_on = false
		_lights_live = maxi(_lights_live - 1, 0)


func _physics_process(delta: float) -> void:
	if not active:
		set_physics_process(false)
		return
	step(delta)


## Advances the flight by `delta` seconds: world ray, then the first target along the segment. Public so
## tests can drive it deterministically.
func step(delta: float) -> void:
	if not active:
		return
	var from := global_position
	var move := velocity * delta
	var dist := move.length()
	if dist > range_left:
		move = move * (range_left / maxf(dist, 0.0001))
		dist = range_left
	var to := from + move
	var end := to
	var wall := false
	if is_inside_tree():
		var space := get_world_3d().direct_space_state
		if space != null and dist > 0.0001:
			_query.from = from
			_query.to = to
			var r := space.intersect_ray(_query)
			if not r.is_empty():
				end = r["position"]
				wall = true
	var t := _first_target(from, end)
	if t != null:
		var seg := end - from
		global_position = from + seg * clampf(_last_s, 0.0, 1.0)
		_hit(t)
		return
	global_position = end
	var moved := from.distance_to(end)
	travelled += moved
	range_left -= moved
	life_left -= delta
	if wall:
		if impact_fx:
			HitFx.spark(end)
		_finish("wall")
		return
	if range_left <= 0.001 or life_left <= 0.0:
		_finish("expired")


func _first_target(a: Vector3, b: Vector3) -> Node3D:
	var best: Node3D = null
	var best_s := 2.0
	var seg_len := a.distance_to(b)
	var mid := (a + b) * 0.5
	for g in groups:
		for n in _targets(String(g)):
			# shooter_id (not the shooter reference): an enemy freed mid-flight must not be compared as an object
			if not is_instance_valid(n) or not (n is Node3D) or (shooter_id != 0 and n.get_instance_id() == shooter_id):
				continue
			var t := n as Node3D
			if not t.is_inside_tree():
				continue
			var aim := Combat.aim_point(t)
			var r := radius + Combat.target_radius(t)
			var hh := DEFAULT_HALF_HEIGHT
			var hv: Variant = t.get("hit_half_height")
			if hv is float or hv is int:
				hh = float(hv)
			if aim.distance_to(mid) > seg_len * 0.5 + r + hh + 0.5:
				continue      # cheap distance cull first: the health lookup below only runs for nearby targets
			var h := Combat.find_health(t)
			if h != null and Combat.truthy(h.get("dead")):
				continue
			var d := segment_distance(a, b, aim - Vector3(0, hh, 0), aim + Vector3(0, hh, 0))
			if d.x <= r * r and d.y < best_s:
				best = t
				best_s = d.y
	_last_s = best_s
	return best


func _hit(t: Node3D) -> void:
	hit_target = t
	var dir := Vector3(velocity.x, 0.0, velocity.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var src: Node = shooter if shooter != null and is_instance_valid(shooter) else null
	var dealt := 0.0
	var h := Combat.find_health(t)
	if h != null and damage > 0.0 and Combat.can_hit(t, src):
		dealt = float(h.apply_damage(damage, src, dir))
	if dealt <= 0.0:
		if t.has_method("on_hit_blocked"):
			t.on_hit_blocked(src, dir)
		if impact_fx:
			HitFx.spark(global_position)
	else:
		if knockback > 0.0 and t.has_method("knockback"):
			t.knockback(dir, knockback)
		if impact_fx:
			var col: Variant = t.get("hit_color")
			HitFx.impact(global_position, dealt, col if col is Color else color)
		if hitstop:
			Events.hitstop.emit(Combat.HITSTOP_LIGHT)
	if on_hit.is_valid():
		on_hit.call(t, dealt)
	_finish("hit" if dealt > 0.0 else "blocked")


func _finish(why: String) -> void:
	if not active:
		return
	result = why
	active = false
	visible = false
	set_physics_process(false)
	_set_light(false)
	shooter = null
	on_hit = Callable()
	_live.erase(self)
	if _pool.size() < POOL_MAX:
		if not _pool.has(self):
			_pool.append(self)
	else:
		queue_free()


func _exit_tree() -> void:
	if active:
		active = false
		_set_light(false)
	_live.erase(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_live.erase(self)
		_pool.erase(self)
