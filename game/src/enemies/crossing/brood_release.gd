extends Node3D
## The Crossing Matron's ONE capped minion release (MP 13.2 / 8), owned and ticked by crossing_matron.gd
## (top_level child: freed with her). Shaking sacs (arachnophobia: pale seed pods - boss_hazards/egg_sac.gd,
## reused as is) stand on the deck in front of Krystal, never underfoot (crossing_rules.sac_spots), and after
## a generous warning each releases ONE small minion through EnemyFactory ("brood_skitter"; its own
## arachnophobia look is the Pale Sprout) - capped by intensity (crossing_rules.MINIONS: Gentle one slower
## minion, else two). Krystal can pop a sac early with any attack (no minion then). A sac never releases while
## she stands on it or while the boss says no (`release_allowed`: never during a pounce), and withers
## harmlessly if she camps on it. dismiss() scatters the minions (exposure, reset, defeat): freed, no drops.
##   var r = BroodRelease.new(); r.setup({"minion_parent": area, "home": centre, "radius": 12.0, "alt": false})
##   boss.add_child(r); r.begin(spots, warn, cap, params); r.tick(dt, krystal_or_null, allowed)

signal minion_spawned(minion: Node)

const EggSac := preload("res://src/enemies/boss_hazards/egg_sac.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const SAC_CLEAR_DIST := 2.5       # a sac waits while Krystal stands this close (never underfoot)
const SAC_MAX_DELAY := 4.0        # ...and withers after waiting this long past its warning

var minion_id: String = "brood_skitter"
var minion_parent: Node = null
var home := Vector3.ZERO
var radius: float = 12.0
var alt := false
var cap: int = 2
var params: Dictionary = {}
var sacs: Array = []
var minions: Array = []
var released_count: int = 0
var minion_override: Callable       # tests: func(pos: Vector3, params: Dictionary) -> Node


func setup(p: Dictionary) -> void:
	var mp: Variant = p.get("minion_parent")
	if mp is Node:
		minion_parent = mp
	var h: Variant = p.get("home")
	if h is Vector3:
		home = h
	radius = float(p.get("radius", radius))
	alt = bool(p.get("alt", alt))
	minion_id = String(p.get("minion_id", minion_id))


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	set_process(false)          # the boss ticks us
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


## Settings high_visibility_cues toggles live on the sacs standing now (egg_sac reads it only when built).
func _on_settings_changed(key: String) -> void:
	if key != "high_visibility_cues":
		return
	var on := bool(Settings.get_value("high_visibility_cues"))
	for s in sacs:
		if is_instance_valid(s):
			s.set_high_vis(on)


## Places a sac at every spot (at most `n_cap` sacs); returns them.
func begin(spots: Array, warn: float, n_cap: int, minion_params: Dictionary = {}) -> Array:
	cap = maxi(n_cap, 0)
	params = minion_params.duplicate()
	var out: Array = []
	for s in spots:
		if out.size() >= cap or not (s is Vector3):
			break
		var sac: Node3D = EggSac.new()
		sac.setup({"pos": s, "warn": warn, "alt": alt})
		sac.name = "EggSac"
		add_child(sac)
		sacs.append(sac)
		out.append(sac)
	return out


func sacs_pending() -> bool:
	for s in sacs:
		if is_instance_valid(s) and s.is_pending():
			return true
	return false


func alive_minions() -> int:
	var n := 0
	for m in minions:
		if _alive(m):
			n += 1
	return n


## `target` = Krystal (or null), `allowed` = false while a pounce is telegraphed / falling.
func tick(delta: float, target: Node3D, allowed: bool) -> void:
	var has_t := target != null and is_instance_valid(target)
	var tp := target.global_position if has_t else Vector3.INF
	var i := sacs.size() - 1
	while i >= 0:
		var s = sacs[i]
		if not is_instance_valid(s):
			sacs.remove_at(i)
			i -= 1
			continue
		s.tick(delta)
		if s.is_due():
			var near := has_t and Vector2(tp.x - s.pos.x, tp.z - s.pos.z).length() < SAC_CLEAR_DIST
			if s.t >= s.warn + SAC_MAX_DELAY:
				s.pop()
			elif allowed and not near:
				var m := spawn_minion(s.pos)
				s.mark_released()
				if m == null:
					Events.caption.emit("[the pod splits open, empty]" if alt else "[the sac splits open, empty]")
		if s.is_done():
			sacs.remove_at(i)
			s.queue_free()
		i -= 1


## One minion at `pos` if under the cap (guarded: a missing enemy script never crashes). Returns it or null.
func spawn_minion(pos: Vector3) -> Node:
	var k := minions.size() - 1
	while k >= 0:
		if not _alive(minions[k]):
			minions.remove_at(k)
		k -= 1
	if minions.size() >= cap or released_count >= cap:
		return null
	var p := params.duplicate()
	p["home"] = home
	p["wander_radius"] = radius
	p["alert"] = true
	p["no_drops"] = true
	var m: Node = null
	if minion_override.is_valid():
		m = minion_override.call(pos, p)
	elif Factory.can_spawn(minion_id) and minion_parent != null and is_instance_valid(minion_parent) and minion_parent.is_inside_tree():
		m = Factory.spawn(minion_id, minion_parent, Transform3D(Basis.IDENTITY, pos), p)
	if m == null:
		return null
	m.set_meta("matron_minion", true)
	minions.append(m)
	released_count += 1
	if m.has_method("pop_in"):
		m.call("pop_in")
	minion_spawned.emit(m)
	return m


## Minions scatter into the dark: freed, no drops, no kill events.
func dismiss() -> void:
	for m in minions:
		if _alive(m):
			if m is Node3D and (m as Node3D).is_inside_tree():
				HitFx.wisps((m as Node3D).global_position + Vector3.UP * 0.4, Color(0.8, 0.78, 0.9, 0.6), 8, 1.0)
			(m as Node).queue_free()
	minions.clear()


## Every sac gone at once (fx: they shrivel; else freed now).
func clear(fx: bool = true) -> void:
	for s in sacs:
		if is_instance_valid(s):
			if fx:
				s.clear()
			else:
				s.queue_free()
	if not fx:
		sacs.clear()


func set_alt(on: bool) -> void:
	alt = on
	for s in sacs:
		if is_instance_valid(s):
			s.set_alt(on)


static func _alive(m: Variant) -> bool:
	if m == null or not is_instance_valid(m) or (m as Node).is_queued_for_deletion():
		return false
	if (m as Node).has_method("is_dead") and bool((m as Node).call("is_dead")):
		return false
	return true
