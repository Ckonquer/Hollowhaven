extends RefCounted
## Static combat helpers shared by the player, enemies, the stalker and the boss.
##   const Combat := preload("res://src/combat/combat.gd")      (or load() from other modules)
##   var hits: Array = Combat.melee(self, chest_pos, facing, 2.5, 110.0, 18.0, ["enemy"], 5.0)
##   var light: float = Combat.light_at(pos)          # 0 = pitch dark, 1 = fully lit
##   var mult: float = Combat.damage_mult_for_area("below")
##
## Target conventions (duck typed, all optional except health):
##   `health` property or child named "Health" (src/combat/health.gd)   -> damage is applied to it
##   knockback(dir: Vector3, force: float)                              -> pushed on hit
##   on_hit_blocked(attacker: Node, dir: Vector3)                        -> hit ignored (invulnerable/boss armour)
##   get_aim_point() -> Vector3 / hit_radius: float                     -> better targeting for big bodies
##   hit_color: Color                                                     -> colour of the impact particles
##   can_be_hit_by(attacker: Node) -> bool                               -> false = the hit is refused like a
##                                                                           blocked one (boss invulnerable/overhead)
## Light sources (group "light_source"): `light_radius: float`, `is_light_active() -> bool`,
## optional `light_strength: float` (0..1). The player's lantern counts even if the player script
## forgot to join the group (uses `lantern_on`).

const HitFx := preload("res://src/combat/hit_fx.gd")
const HorrorData := preload("res://data/horror_events.gd")

const LOS_MASK := 1 | 32                 # world + structures block attacks
const DEFAULT_TARGET_RADIUS := 0.45
const DEFAULT_AIM_HEIGHT := 0.8
const MAX_VERTICAL_REACH := 1.7
const LIGHT_CORE := 0.45                 # fraction of light_radius that is fully lit
const PLAYER_LANTERN_RADIUS := 6.5       # fallback when the player isn't a registered light source
const HITSTOP_LIGHT := 0.045
const HITSTOP_HEAVY := 0.06
## Areas whose threats scale with the horror intensity setting (underground: the Below and the Chapter Two
## underground areas, spec section 9). Surface, the Reach and interiors never scale.
const INTENSITY_SCALED_AREAS := ["below", "tobin_annex", "hushed_works"]

static var _light_nodes: Array = []
static var _light_frame: int = -1


## Sphere/arc melee query. Hits every node of `target_groups` whose aim point lies within `reach`
## (+ the target's hit radius) and inside the horizontal arc around `forward`, with a clear line of
## sight (world|structure). Applies damage through the target's health, knockback if supported,
## impact feedback and a tiny hitstop. Returns the nodes that actually took damage.
static func melee(attacker: Node3D, origin: Vector3, forward: Vector3, reach: float, arc_deg: float, damage: float, target_groups: Array, knockback: float) -> Array:
	var hits: Array = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or damage <= 0.0:
		return hits
	var fwd := Vector3(forward.x, 0.0, forward.z)
	if fwd.length_squared() < 0.0001 and attacker != null and is_instance_valid(attacker):
		var bz: Vector3 = -attacker.global_transform.basis.z
		fwd = Vector3(bz.x, 0.0, bz.z)
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var space: PhysicsDirectSpaceState3D = null
	if attacker != null and is_instance_valid(attacker) and attacker.is_inside_tree():
		space = attacker.get_world_3d().direct_space_state
	var seen := {}
	var heavy := false
	for g in target_groups:
		for n in tree.get_nodes_in_group(String(g)):
			if n == attacker or seen.has(n) or not (n is Node3D) or not is_instance_valid(n):
				continue
			seen[n] = true
			var t := n as Node3D
			if not t.is_inside_tree():
				continue
			var aim := aim_point(t)
			if not in_arc(origin, fwd, aim, reach + target_radius(t), arc_deg, MAX_VERTICAL_REACH):
				continue
			if space != null and not has_line_of_sight(space, origin, aim, [attacker, t]):
				continue
			var h := find_health(t)
			if h == null:
				continue
			var dir := Vector3(aim.x - origin.x, 0.0, aim.z - origin.z)
			dir = dir.normalized() if dir.length_squared() > 0.0001 else fwd
			if not can_hit(t, attacker):
				if t.has_method("on_hit_blocked"):
					t.on_hit_blocked(attacker, dir)
				continue
			var dealt: float = float(h.apply_damage(damage, attacker, dir))
			if dealt <= 0.0:
				if t.has_method("on_hit_blocked"):
					t.on_hit_blocked(attacker, dir)
				continue
			if knockback > 0.0 and t.has_method("knockback"):
				t.knockback(dir, knockback)
			hits.append(t)
			heavy = heavy or dealt >= 15.0
			var col: Variant = t.get("hit_color")
			HitFx.impact(aim - dir * 0.25, dealt, col if col is Color else HitFx.DEFAULT_IMPACT)
	if not hits.is_empty():
		Events.hitstop.emit(HITSTOP_HEAVY if heavy else HITSTOP_LIGHT)
	return hits


## Pure geometry: is `point` within `reach` of `origin` and inside the horizontal arc (degrees, full
## width) around `forward`? Targets that overlap the attacker (closer than 0.6 m) always count.
static func in_arc(origin: Vector3, forward: Vector3, point: Vector3, reach: float, arc_deg: float, max_dy: float = MAX_VERTICAL_REACH) -> bool:
	if absf(point.y - origin.y) > max_dy:
		return false
	var flat := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	var dist := flat.length()
	if dist > reach:
		return false
	if dist < 0.6 or arc_deg >= 359.0:
		return true
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 0.0001:
		return true
	var ang := rad_to_deg(f.normalized().angle_to(flat / dist))
	return ang <= arc_deg * 0.5


## Ray test against world|structure between two points, ignoring the given nodes' bodies.
static func has_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude_nodes: Array = [], mask: int = LOS_MASK) -> bool:
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var ex: Array[RID] = []
	for e in exclude_nodes:
		if e is CollisionObject3D and is_instance_valid(e):
			ex.append((e as CollisionObject3D).get_rid())
	q.exclude = ex
	q.collide_with_areas = false
	return space.intersect_ray(q).is_empty()


## False when the target refuses hits from `attacker` right now (optional `can_be_hit_by(source) -> bool`,
## e.g. a boss while invulnerable or out of reach overhead). Melee and projectiles respect it.
static func can_hit(t: Object, attacker: Object) -> bool:
	if t == null or not is_instance_valid(t) or not t.has_method("can_be_hit_by"):
		return true
	var src: Variant = attacker if attacker != null and is_instance_valid(attacker) else null
	return truthy(t.call("can_be_hit_by", src))


## Where attacks and line-of-sight checks aim at a node.
static func aim_point(t: Node3D) -> Vector3:
	if t.has_method("get_aim_point"):
		var p: Variant = t.get_aim_point()
		if p is Vector3:
			return p
	return t.global_position + Vector3.UP * DEFAULT_AIM_HEIGHT


static func target_radius(t: Object) -> float:
	var r: Variant = t.get("hit_radius")
	if r is float or r is int:
		return float(r)
	return DEFAULT_TARGET_RADIUS


## The health component of a node (property `health` or child "Health"), or null.
static func find_health(node: Object) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	var h: Variant = node.get("health")
	if h is Node and is_instance_valid(h) and (h as Node).has_method("apply_damage"):
		return h
	if node is Node:
		var c := (node as Node).get_node_or_null("Health")
		if c != null and c.has_method("apply_damage"):
			return c
	return null


# --- Light ------------------------------------------------------------------------------------

## 0..1 brightness at a position from every active light source (soft-combined). Cheap enough to
## call a few times per second per enemy (the group lookup is cached per frame).
static func light_at(pos: Vector3) -> float:
	var dark := 1.0
	for n in _sources():
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		if n.has_method("is_light_active") and not truthy(n.is_light_active()):
			continue
		var r: Variant = n.get("light_radius")
		if not (r is float or r is int):
			continue
		var strength := 1.0
		var s: Variant = n.get("light_strength")
		if s is float or s is int:
			strength = clampf(float(s), 0.0, 1.0)
		var l := light_falloff((n as Node3D).global_position.distance_to(pos), float(r)) * strength
		dark *= 1.0 - clampf(l, 0.0, 1.0)
	var p: Node = _player_lantern()
	if p != null:
		dark *= 1.0 - light_falloff((p as Node3D).global_position.distance_to(pos), PLAYER_LANTERN_RADIUS)
	return clampf(1.0 - dark, 0.0, 1.0)


## Light contribution of one source: 1 inside the core, then a linear fade to 0 at the radius.
static func light_falloff(dist: float, radius: float) -> float:
	if radius <= 0.0 or dist >= radius:
		return 0.0
	var core := radius * LIGHT_CORE
	if dist <= core:
		return 1.0
	return 1.0 - (dist - core) / (radius - core)


## Forces the next light_at() to re-read group "light_source" (tests; sources added this frame).
static func invalidate_light_cache() -> void:
	_light_frame = -1


static func _sources() -> Array:
	var frame := Engine.get_process_frames()
	if frame != _light_frame:
		_light_frame = frame
		var tree := Engine.get_main_loop() as SceneTree
		_light_nodes = tree.get_nodes_in_group("light_source") if tree != null else []
	return _light_nodes


## The player node when its lantern is raised but it is not a registered light source.
static func _player_lantern() -> Node:
	var p: Node = Game.player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree() or p.is_in_group("light_source"):
		return null
	if truthy(p.get("lantern_on")):
		return p
	return null


## Safe truth test for duck-typed properties (Object.get() returns null for missing ones, and
## bool(null) is not a valid constructor).
static func truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return false


# --- Horror intensity scaling ---------------------------------------------------------------------

static func current_intensity() -> int:
	return clampi(int(Settings.get_value("horror_intensity")), 0, 2)


static func intensity_damage_mult(level: int) -> float:
	var d: Dictionary = HorrorData.INTENSITY.get(clampi(level, 0, 2), {})
	return float(d.get("damage_mult", 1.0))


## Damage multiplier for threats of an area: underground threats (INTENSITY_SCALED_AREAS: the Below, Tobin's
## annex, the Hushed Works) scale with the horror intensity setting (Gentle 0.6, Standard 1.0, Intense 1.15);
## surface, Reach and interior enemies never do. `area` defaults to the current area.
static func damage_mult_for_area(area: String = "") -> float:
	var a := area if area != "" else Game.area_id
	if not INTENSITY_SCALED_AREAS.has(a):
		return 1.0
	return intensity_damage_mult(current_intensity())
