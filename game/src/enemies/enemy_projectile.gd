extends Node3D
## FALLBACK enemy projectile (the Lantern Moth's glowing orb): enemy_base.fire_projectile() uses spec 9's shared
## pooled src/combat/projectile.gd whenever that script exists and loads; this local one only runs when it is
## missing or broken, so a moth can always shoot. Same contract, minimal implementation.
## Rules: parented to the area (never to the shooter, so it outlives a defeated shooter); a wall or structure
## (world|structure, layer 1|32) on the travelled segment pops it, so it never passes through walls; it can
## damage ONLY its target (Krystal) and at most once; damage goes through the target's health (dodge
## i-frames, armour and shields apply there) - a dodged orb drifts on and can no longer hit her; the number
## alive is capped (MAX_LIVE) and each one expires after `range` metres.
## Tests drive it with step(delta) (physics processing can be switched off).
##   setup({"target", "shooter", "damage", "speed", "range", "knockback", "homing", "color", "radius"})
##   launch(from, target)
## Signal finished(result): "hit" | "wall" | "expired".

signal finished(result: String)

const Combat := preload("res://src/combat/combat.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const MAX_LIVE := 6
const HIT_RADIUS := 0.5              # orb radius + margin; her aim point must come this close
const HOMING_PHASE := 0.5            # steering only during the first half of its range
const DEFAULT_COLOR := Color(1.0, 0.82, 0.46)

static var _live: Array = []

var shooter: Node = null
var target: Node3D = null
var damage: float = 8.0
var speed: float = 5.0
var max_range: float = 12.0
var knockback_force: float = 3.0
var homing: float = 0.5              # radians per second of steering toward the target
var color: Color = DEFAULT_COLOR
var radius: float = 0.2
var velocity := Vector3.ZERO
var travelled: float = 0.0
var result: String = ""
var dodged := false

var _visual: Node3D
var _t: float = 0.0


## True while fewer than MAX_LIVE enemy projectiles exist.
static func can_fire() -> bool:
	return live_count() < MAX_LIVE


static func live_count() -> int:
	for i in range(_live.size() - 1, -1, -1):
		var p: Variant = _live[i]
		if not is_instance_valid(p) or (p as Node).is_queued_for_deletion():
			_live.remove_at(i)
	return _live.size()


func setup(params: Dictionary) -> void:
	var s: Variant = params.get("shooter")
	if s is Node:
		shooter = s
	var t: Variant = params.get("target")
	if t is Node3D:
		target = t
	damage = float(params.get("damage", damage))
	speed = maxf(float(params.get("speed", speed)), 0.5)
	max_range = maxf(float(params.get("range", max_range)), 0.5)
	knockback_force = float(params.get("knockback", knockback_force))
	homing = maxf(float(params.get("homing", homing)), 0.0)
	radius = float(params.get("radius", radius))
	var c: Variant = params.get("color")
	if c is Color:
		color = c


func _ready() -> void:
	_live.append(self)
	_visual = Node3D.new()
	add_child(_visual)
	var core := Kit.sphere(radius, Mat.glow(color, 2.4), 10, 14)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(core)
	var halo := Kit.sphere(radius * 1.7, Mat.transparent(Color(color.r, color.g, color.b, 0.28), true), 10, 14)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(halo)


func _exit_tree() -> void:
	_live.erase(self)


## Places the orb and aims it at the target's aim point.
func launch(from: Vector3, tgt: Node3D) -> void:
	if tgt != null:
		target = tgt
	global_position = from
	var aim := Combat.aim_point(target) if target != null and is_instance_valid(target) else from + Vector3.FORWARD
	var d := aim - from
	velocity = (d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD) * speed


func _physics_process(delta: float) -> void:
	step(delta)


func _process(delta: float) -> void:
	_t += delta
	if _visual != null:
		var s := 1.0 + 0.08 * sin(_t * 9.0)
		_visual.scale = Vector3(s, s, s)


## One movement step: gentle homing, wall test on the travelled segment, target test, range limit.
func step(delta: float) -> void:
	if result != "" or delta <= 0.0:
		return
	var prev := global_position
	var has_target := target != null and is_instance_valid(target) and target.is_inside_tree()
	if has_target and homing > 0.0 and travelled < max_range * HOMING_PHASE and not dodged:
		var want := Combat.aim_point(target) - prev
		if want.length_squared() > 0.0001:
			var cur := velocity.normalized()
			var ang := cur.angle_to(want.normalized())
			var turn := minf(ang, homing * delta)
			if ang > 0.0001:
				velocity = cur.slerp(want.normalized(), turn / ang) * speed
	var next := prev + velocity * delta
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(prev, next, Combat.LOS_MASK)
		q.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			global_position = hit["position"]
			_finish("wall")
			return
	global_position = next
	travelled += velocity.length() * delta
	if has_target and not dodged:
		var aim := Combat.aim_point(target)
		if _segment_point_distance(prev, next, aim) <= HIT_RADIUS:
			_strike(prev, next)
			if result != "":
				return
	if travelled >= max_range:
		_finish("expired")


func _strike(prev: Vector3, next: Vector3) -> void:
	var h := Combat.find_health(target)
	if h == null:
		dodged = true
		return
	var d := Vector3(next.x - prev.x, 0.0, next.z - prev.z)
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var src: Node = shooter if shooter != null and is_instance_valid(shooter) else self
	var dealt := float(h.apply_damage(damage, src, d))
	if dealt <= 0.0:
		dodged = true                      # rolled through it: it drifts on and cannot hit her again
		if target.has_method("on_hit_blocked"):
			target.on_hit_blocked(src, d)
		return
	if knockback_force > 0.0 and target.has_method("knockback"):
		target.knockback(d, knockback_force)
	HitFx.impact(global_position, dealt, color)
	Events.hitstop.emit(Combat.HITSTOP_LIGHT)
	_finish("hit")


func _finish(r: String) -> void:
	if result != "":
		return
	result = r
	_live.erase(self)
	HitFx.burst(global_position, Color(color.r, color.g, color.b, 0.8), 8, 2.0, 0.6, -2.0, 0.4, 120.0)
	finished.emit(r)
	set_physics_process(false)
	queue_free()


static func _segment_point_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)
