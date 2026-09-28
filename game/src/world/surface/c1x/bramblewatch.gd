extends RefCounted
## Bramblewatch (MP 7 "Bramblewatch", MP 12 Brambleback / Knotted Elder; spec 7.1; optional goal opt_bramblewatch).
## A NEW pocket on the Thornthicket outskirts, west / north-west of the legacy thicket_bramblings spawner, built
## from data/c1x_layout.gd:
##   * zone "c1x_bramblewatch" (two small circles, never containing a landmark centre). The first time Krystal
##     enters it the objective flag c1x_bramblewatch_found is set (Events.zone_entered from Game's zone poll).
##   * c1x_sp_bramblebacks: an authored Brambleback group (NEW spawner id, renewable like the thicket group).
##   * the Knotted Elder's arena: open ground (no walls, many ways out) around c1x_sp_knotted_elder. While the
##     Elder is engaged (and brings no roots of its own, see below), telegraphed temporary roots rise on some of
##     the arena's root slots: a cracked, glowing
##     strip shows for `telegraph` seconds first (steady, no flashing; a caption + a gentle shake through Events;
##     Settings timing_assist doubles it, at least 3 s),
##     then thorny roots stand for `duration` seconds and sink. At most max_raised slots rise, at least min_open
##     stay open, a slot is never raised on Krystal / a companion / the Elder, neighbouring slots leave > 3 m gaps
##     and every root can be cut (hand harvest, root_hits hits): no enclosure softlock.
##     The Elder's defeat (its spawner clears) grants the content bundle rw_c1x_elder ONCE (flag c1x_elder_defeated).
##   * decor: "a sticky old tree" dripping resin at the arena's western edge, old thorn-wrapped watch posts.
## Enemy scripts come from another module: spawners are only built when EnemyFactory knows the id and the script
## compiles (Common.make_spawner); without them the pocket, the zone flag and the decor still work.
## The Knotted Elder script (src/enemies/knotted_elder.gd, another module) brings its OWN telegraphed, cuttable
## roots around Krystal and grants rw_c1x_elder itself on defeat (the ledger keeps it once either way): an Elder with
## clear_roots() + live_roots() switches the arena's roots off (Arena.elder_owns_roots). The arena's roots are the
## fallback for an Elder without its own (a state named "roots" or an explicit arena.raise_roots() call also works:
## the spawner carries meta "c1x_arena", the arena is in group "c1x_elder_arena").
##   Bramblewatch.build(area)
##   Bramblewatch.grass_clearings() -> Array
##   Bramblewatch.make_bramblebacks(parent, area) / make_elder_spawner(parent, area) / elder_params(area)

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")


static func build(area: Node3D) -> void:
	if area == null:
		return
	var parent := Common.sub_root(area, "Bramblewatch")
	for z in L.BRAMBLEWATCH_ZONES:
		var c: Vector2 = z[0]
		if area.has_method("add_zone"):
			area.add_zone(L.BRAMBLEWATCH_ZONE, Common.ground(area, c), float(z[1]), false)
	var watch := Watch.new()
	watch.name = "Watch"
	parent.add_child(watch)
	make_bramblebacks(parent, area)
	var arena := Arena.new()
	arena.name = "ElderArena"
	Common.place(parent, arena, area, L.ELDER_ARENA["centre"], 0.0)
	arena.build_slots(area)
	var sp := make_elder_spawner(parent, area)
	if sp != null:
		arena.attach_spawner(sp)
	arena.repair_reward()
	_build_decor(parent, area)


## The renewable Brambleback group (c1x_sp_bramblebacks); it never pops in within view (layout out_of_view).
## Null while the brambleback enemy is not available.
static func make_bramblebacks(parent: Node3D, area: Node) -> Node3D:
	var sp := Common.make_spawner(parent, area, L.BRAMBLEBACK_SPAWNER)
	if sp != null:
		sp.setup(L.spawner_extras(L.BRAMBLEBACK_SPAWNER))
	return sp


## The Knotted Elder's spawner. The Elder fights in THIS arena: its centre (on the ground) and ELDER_ARENA
## radius reach the Elder through the spawner's enemy_params, so its own roots stay inside the arena the
## fallback roots use (its data arena_radius is only a fallback). Null while knotted_elder is not available.
static func make_elder_spawner(parent: Node3D, area: Node) -> Node3D:
	var sp := Common.make_spawner(parent, area, L.ELDER_SPAWNER)
	if sp != null:
		var extra := L.spawner_extras(L.ELDER_SPAWNER)
		extra["enemy_params"] = elder_params(area)
		sp.setup(extra)
	return sp


## Setup params the Knotted Elder gets from its spawner (arena_center / arena_radius, knotted_elder.gd setup).
static func elder_params(area: Node) -> Dictionary:
	return {"arena_center": Common.ground(area, L.ELDER_ARENA["centre"]), "arena_radius": float(L.ELDER_ARENA["radius"])}


static func grass_clearings() -> Array:
	var out: Array = [[L.STICKY_TREE["pos"], 1.8]]
	for p in L.WATCH_POSTS:
		out.append([p["pos"], 0.6])
	return out


static func _build_decor(parent: Node3D, area: Node3D) -> void:
	var tree := Node3D.new()
	tree.name = String(L.STICKY_TREE["id"])
	var m := Common.sticky_tree_meshes()
	tree.add_child(Common.mi(m["bark"], Common.NodeVisuals.bark_material(), "Bark", 160.0, true))
	tree.add_child(Common.mi(m["crown"], Common.NodeVisuals.foliage_material(0.05, 6.0, 0.035, 0.2), "Crown", 160.0, true))
	tree.add_child(Common.mi(m["resin"], Common.resin_material(), "Resin", 70.0, false))
	Common.solid_cylinder(tree, 0.72, 4.4, "wood")
	Common.place(parent, tree, area, L.STICKY_TREE["pos"], float(L.STICKY_TREE["yaw_deg"]), -0.15)
	for p in L.WATCH_POSTS:
		var post := Node3D.new()
		post.name = String(p["id"])
		post.add_child(Common.mi(Common.post_mesh(), Common.prop_material(0.018), "Post", 90.0, true))
		Common.solid_cylinder(post, 0.17, 1.8, "wood")
		Common.place(parent, post, area, p["pos"], float(p.get("yaw_deg", 0.0)), -0.05)


## Sets c1x_bramblewatch_found the first time Krystal enters the pocket's zone.
class Watch extends Node:
	const L := preload("res://data/c1x_layout.gd")

	func _ready() -> void:
		add_to_group("c1x_bramblewatch")
		if not Events.zone_entered.is_connected(_on_zone_entered):
			Events.zone_entered.connect(_on_zone_entered)

	func _on_zone_entered(zone_id: String) -> void:
		if zone_id == L.BRAMBLEWATCH_ZONE:
			mark_found()

	## True the first time.
	func mark_found() -> bool:
		if bool(GameState.get_flag(L.FLAG_BRAMBLEWATCH_FOUND)):
			return false
		GameState.set_flag(L.FLAG_BRAMBLEWATCH_FOUND, true)
		Events.notify.emit("Bramblewatch", "quest")
		Events.hint.emit("c1x_brambleback", "Bramblebacks scrape the dirt and lower their heads before a charge. Side-step, then hit the soft flank.")
		return true


## The Knotted Elder's open arena: root slots, their schedule while the Elder is engaged, the reward.
class Arena extends Node3D:
	const L := preload("res://data/c1x_layout.gd")
	const Common := preload("res://src/world/surface/c1x/common.gd")
	const TICK := 0.25
	const ENGAGE_MARGIN := 4.0          # Krystal within radius + this = in the fight
	const LEAVE_MARGIN := 12.0          # farther than radius + this: roots sink at once
	const ASSIST_TELEGRAPH_MULT := 2.0  # Settings timing_assist: longer telegraph...
	const ASSIST_TELEGRAPH_MIN := 3.0   # ...and never shorter than this (seconds)
	const MESSAGE := "The Knotted Elder sinks back into the roots. Bramblewatch is quiet, and it left resin behind."

	signal roots_raised(count: int)
	signal roots_cleared

	var radius: float = 10.0
	var walls: Array = []               # RootWall per slot (index = ROOT_SLOTS index)
	var spawner: Node3D = null
	var elder: Node = null
	var elder_driven := false           # the Elder script raises the roots itself
	var player_override: Node3D = null  # tests
	var _t := 0.0
	var _engaged_t := 0.0
	var _cooldown := 0.0
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		add_to_group("c1x_elder_arena")
		radius = float(L.ELDER_ARENA["radius"])
		_rng.seed = hash("c1x_elder_arena")
		if not Events.player_died.is_connected(_on_player_died):
			Events.player_died.connect(_on_player_died)
		if not Events.enemy_killed.is_connected(_on_enemy_killed):
			Events.enemy_killed.connect(_on_enemy_killed)
		if not Events.reward_granted.is_connected(_on_reward_granted):
			Events.reward_granted.connect(_on_reward_granted)

	## One RootWall per data slot (children of this arena, on the ground).
	func build_slots(area: Node) -> void:
		for i in L.ROOT_SLOTS.size():
			var w := RootWall.new()
			w.slot_index = i
			w.arena = self
			w.name = "RootSlot%d" % i
			var mid := L.root_slot_mid(i)
			var a := float(L.ROOT_SLOTS[i]["angle"])
			add_child(w)
			w.global_position = Common.ground(area, mid, -0.05)
			# local X runs along the arena tangent (-sin a, cos a)
			w.rotation.y = -atan2(cos(a), -sin(a))
			walls.append(w)

	func attach_spawner(sp: Node3D) -> void:
		spawner = sp
		sp.set_meta("c1x_arena", self)
		if sp.has_signal("enemy_spawned") and not sp.is_connected("enemy_spawned", _on_elder_spawned):
			sp.connect("enemy_spawned", _on_elder_spawned)
		if sp.has_signal("cleared") and not sp.is_connected("cleared", _on_cleared):
			sp.connect("cleared", _on_cleared)

	## A save whose spawner already cleared (e.g. quit between the kill and the reward) still gets it.
	func repair_reward() -> void:
		if bool(GameState.get_flag("spawner_cleared_" + String(L.ELDER_SPAWNER["id"]))):
			Common.grant_content(L.REWARD_ELDER, MESSAGE)

	# --- Fight state -------------------------------------------------------------------------------------------

	func centre() -> Vector3:
		return global_position

	func _player() -> Node3D:
		if player_override != null and is_instance_valid(player_override):
			return player_override
		return Common.player()

	func elder_alive() -> bool:
		if elder == null or not is_instance_valid(elder) or elder.is_queued_for_deletion():
			return false
		var h: Variant = elder.get("health")
		if h is Node and bool((h as Node).get("dead")):
			return false
		return true

	## The Elder is alive, Krystal is in (or at the edge of) the arena and alive, and the Elder is after her.
	func is_engaged() -> bool:
		if not elder_alive() or Game.mode == "dead":
			return false
		var p := _player()
		if p == null or _flat_dist(p.global_position, centre()) > radius + ENGAGE_MARGIN:
			return false
		if elder.has_method("is_threatening"):
			return bool(elder.is_threatening()) or _flat_dist((elder as Node3D).global_position, p.global_position) < radius
		return true

	func _process(delta: float) -> void:
		_t += delta
		if _t < TICK:
			return
		var dt := _t
		_t = 0.0
		tick(dt)

	## Schedule (tests call it directly).
	func tick(dt: float) -> void:
		_cooldown = maxf(_cooldown - dt, 0.0)
		var p := _player()
		if raised_count() > 0 and (not elder_alive() or p == null or _flat_dist(p.global_position, centre()) > radius + LEAVE_MARGIN):
			clear_roots()
		if not is_engaged():
			_engaged_t = 0.0
			return
		_engaged_t += dt
		if elder_driven:
			return
		if _engaged_t >= float(L.ELDER_ARENA["first_after"]) and _cooldown <= 0.0 and raised_count() == 0:
			raise_roots()

	func set_elder_driven(on: bool) -> void:
		elder_driven = on

	# --- Roots --------------------------------------------------------------------------------------------------

	## Slots currently telegraphing or standing.
	func raised_count() -> int:
		var n := 0
		for w in walls:
			if (w as RootWall).state == "telegraph" or (w as RootWall).state == "up":
				n += 1
		return n

	## Slots that do not block right now (down or sinking).
	func open_count() -> int:
		var n := 0
		for w in walls:
			if not (w as RootWall).is_blocking() and (w as RootWall).state != "telegraph":
				n += 1
		return n

	## Telegraphs, then raises roots on a few free slots. Returns how many slots will rise (0 when roots are
	## already up, or nothing is free). Never more than max_raised and never fewer than min_open slots stay open.
	func raise_roots(telegraph: float = -1.0, duration: float = -1.0) -> int:
		if raised_count() > 0 or walls.is_empty():
			return 0
		var tele := assisted_telegraph(telegraph if telegraph >= 0.0 else float(L.ELDER_ARENA["telegraph"]))
		var dur := duration if duration > 0.0 else _data_duration()
		var free: Array = []
		for w in walls:
			if (w as RootWall).state == "down" and not slot_occupied(w as RootWall):
				free.append(w)
		var cap := mini(int(L.ELDER_ARENA["max_raised"]), walls.size() - int(L.ELDER_ARENA["min_open"]))
		var n := mini(cap, free.size())
		if n <= 0:
			return 0
		# deterministic shuffle (own RNG seeded by name), then take n
		for i in range(free.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp: Variant = free[i]
			free[i] = free[j]
			free[j] = tmp
		for k in n:
			(free[k] as RootWall).begin(tele, dur)
		_cooldown = float(L.ELDER_ARENA["interval"])
		Events.caption.emit("[Roots rumble under the ground]")
		Common.play_3d("dir_root_creak", centre() + Vector3.UP, -2.0)
		var p := _player()
		if p != null and _flat_dist(p.global_position, centre()) < radius + 6.0:
			Events.camera_shake.emit(0.1, 0.5)
		roots_raised.emit(n)
		return n

	## Every root sinks now (Elder defeated / gone, Krystal down or far away).
	func clear_roots() -> void:
		var any := false
		for w in walls:
			if (w as RootWall).state != "down":
				(w as RootWall).force_down()
				any = true
		if any:
			roots_cleared.emit()

	## True when Krystal, a companion or the Elder stands on (or right next to) the slot's wall.
	func slot_occupied(w: RootWall) -> bool:
		var ends := w.world_ends()
		var clear := float(L.ELDER_ARENA["root_depth"]) * 0.5 + 0.9
		var p := _player()
		if p != null and _seg_dist(p.global_position, ends[0], ends[1]) < clear:
			return true
		for id in Game.companion_nodes:
			var c: Variant = Game.companion_nodes[id]
			if c is Node3D and is_instance_valid(c) and _seg_dist((c as Node3D).global_position, ends[0], ends[1]) < clear:
				return true
		if elder_alive() and elder is Node3D and _seg_dist((elder as Node3D).global_position, ends[0], ends[1]) < clear + 0.8:
			return true
		return false

	## Settings "timing_assist" removes the tight window: a telegraph lasts twice as long, at least
	## ASSIST_TELEGRAPH_MIN seconds (an instant rise, 0, stays instant: tests / scripted calls).
	static func assisted_telegraph(t: float) -> float:
		if t > 0.0 and bool(Settings.get_value("timing_assist")):
			return maxf(t * ASSIST_TELEGRAPH_MULT, ASSIST_TELEGRAPH_MIN)
		return t

	func _data_duration() -> float:
		var def: Dictionary = ItemDB.enemy("knotted_elder")
		for a in def.get("attacks", []):
			if a is Dictionary and String(a.get("kind", "")) == "roots" and float(a.get("duration", 0.0)) > 0.0:
				return float(a["duration"])
		return float(L.ELDER_ARENA["duration"])

	# --- Elder hooks ----------------------------------------------------------------------------------------------

	## The Elder script's own root attack (roots around Krystal, cut / sunk by the Elder itself) replaces the
	## arena's schedule: with such an Elder the arena never raises roots on its own (no double roots).
	static func elder_owns_roots(e: Node) -> bool:
		return e != null and e.has_method("clear_roots") and e.has_method("live_roots")

	func _on_elder_spawned(e: Node) -> void:
		elder = e
		if elder_owns_roots(e):
			elder_driven = true
			return
		if e != null and e.has_signal("state_changed") and not e.is_connected("state_changed", _on_elder_state):
			e.connect("state_changed", _on_elder_state)

	func _on_elder_state(new_state: String) -> void:
		if new_state.begins_with("roots") and not elder_owns_roots(elder):
			elder_driven = true
			raise_roots()

	func _on_cleared(_spawner_id: String) -> void:
		clear_roots()
		_grant()

	func _on_enemy_killed(enemy_id: String, pos: Vector3) -> void:
		if enemy_id == String(L.ELDER_SPAWNER["enemy"]) and _flat_dist(pos, centre()) < radius + 40.0:
			clear_roots()
			_grant()

	func _grant() -> void:
		Common.grant_content(L.REWARD_ELDER, MESSAGE)

	## Whoever paid rw_c1x_elder first (the Elder script on its defeat, or this arena), Krystal learns what it unlocked.
	func _on_reward_granted(reward_id: String) -> void:
		if reward_id == L.REWARD_ELDER:
			Events.hint.emit("c1x_elder", "New recipes: a Sturdy Planter at the workbench and a leaf cape pattern at the Loom.")

	func _on_player_died() -> void:
		clear_roots()
		_engaged_t = 0.0

	static func _flat_dist(a: Vector3, b: Vector3) -> float:
		return Vector2(a.x - b.x, a.z - b.z).length()

	static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
		var pp := Vector2(p.x, p.z)
		var aa := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - aa
		var t := clampf((pp - aa).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		return pp.distance_to(aa + ab * t)


## One temporary root wall on an arena slot. States: down -> telegraph (cracked glowing strip) -> up (solid, cuttable)
## -> sinking -> down. Cutting (hand harvest, root_hits hits) sinks it at once. Processing only while active.
class RootWall extends Node3D:
	const L := preload("res://data/c1x_layout.gd")
	const Common := preload("res://src/world/surface/c1x/common.gd")
	const Fx := preload("res://src/world/common/fx.gd")
	const RISE_TIME := 0.3
	const SINK_TIME := 0.45

	signal cut

	var slot_index := -1
	var arena: Node3D = null
	var state := "down"
	var length: float = 3.8
	var height: float = 1.5
	var depth: float = 0.7
	var hits_needed: int = 2
	var _t := 0.0
	var _len := 0.0
	var _duration := 6.0
	var _damage := 0
	var _roots: MeshInstance3D
	var _crack: Node3D
	var _solid: StaticBody3D
	var _interact: StaticBody3D

	func _ready() -> void:
		length = float(L.ELDER_ARENA["root_length"])
		height = float(L.ELDER_ARENA["root_height"])
		depth = float(L.ELDER_ARENA["root_depth"])
		hits_needed = maxi(1, int(L.ELDER_ARENA["root_hits"]))
		_roots = Common.mi(Common.root_wall_mesh(length, height), Common.NodeVisuals.bark_material(), "Roots", 80.0, true)
		_roots.visible = false
		add_child(_roots)
		_crack = Node3D.new()
		_crack.name = "Crack"
		var cm := Common.crack_meshes(length + 0.4)
		_crack.add_child(Common.mi(cm["soil"], Common.plain_material(), "Soil", 70.0, false))
		_crack.add_child(Common.mi(cm["glow"], Common.Mat.glow(Color("ffb35c"), 1.1), "Glow", 70.0, false))
		_crack.visible = false
		add_child(_crack)
		_solid = _box_body("Solid", Vector3(length, height + 0.4, depth))
		_interact = _box_body("Interact", Vector3(length + 0.2, height, depth + 0.5))
		_set_active_colliders(false)
		set_process(false)

	func _box_body(n: String, size: Vector3) -> StaticBody3D:
		var body := StaticBody3D.new()
		body.name = n
		body.collision_layer = 0
		body.collision_mask = 0
		body.set_meta("surface", "wood")
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = Vector3(0, size.y * 0.5, 0)
		body.add_child(cs)
		add_child(body)
		return body

	func _set_active_colliders(on: bool) -> void:
		_solid.collision_layer = Common.LAYER_WORLD if on else 0
		_interact.collision_layer = Common.LAYER_INTERACT if on else 0
		if on:
			add_to_group("harvestable")
			add_to_group("interactable")
		else:
			if is_in_group("harvestable"):
				remove_from_group("harvestable")
			if is_in_group("interactable"):
				remove_from_group("interactable")

	## The wall's ends in world space (XZ matter).
	func world_ends() -> Array:
		var half := length * 0.5
		return [global_transform * Vector3(-half, 0, 0), global_transform * Vector3(half, 0, 0)]

	func is_blocking() -> bool:
		return state == "up"

	## Starts the telegraph; the roots rise `telegraph` seconds later and stand for `duration` seconds.
	func begin(telegraph: float, duration: float) -> void:
		if state != "down":
			return
		_duration = duration
		_damage = 0
		state = "telegraph"
		_t = 0.0
		_len = maxf(telegraph, 0.0)
		_crack.visible = true
		_crack.scale = Vector3(0.2, 1.0, 1.0)
		if is_inside_tree():
			var tw := create_tween()
			tw.tween_property(_crack, "scale", Vector3.ONE, minf(0.35, maxf(_len, 0.05)))
			Fx.burst(get_parent(), global_position + Vector3.UP * 0.2, "dust", 0.6)
		set_process(true)
		if _len <= 0.0:
			_rise()

	func _process(delta: float) -> void:
		advance(delta)

	## State timer (tests call it directly).
	func advance(delta: float) -> void:
		if state == "down":
			set_process(false)
			return
		_t += delta
		if _t < _len:
			return
		match state:
			"telegraph":
				_rise()
			"up":
				sink()
			"sinking":
				_finish_down()

	func _rise() -> void:
		_crack.visible = false
		# Never close a wall on Krystal, a companion or the Elder: this slot simply stays open.
		if arena != null and arena.has_method("slot_occupied") and bool(arena.slot_occupied(self)):
			_finish_down()
			return
		state = "up"
		_t = 0.0
		_len = _duration
		_roots.visible = true
		_roots.scale = Vector3(1.0, 0.05, 1.0)
		_set_active_colliders(true)
		if is_inside_tree():
			var tw := create_tween()
			tw.tween_property(_roots, "scale", Vector3.ONE, RISE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Fx.burst(get_parent(), global_position + Vector3.UP * 0.4, "leaves", 0.8)

	## Roots sink (timer end or cut). Colliders are off from the first frame of sinking.
	func sink() -> void:
		if state != "up":
			return
		state = "sinking"
		_t = 0.0
		_len = SINK_TIME
		_set_active_colliders(false)
		if is_inside_tree():
			var tw := create_tween()
			tw.tween_property(_roots, "scale", Vector3(1.0, 0.05, 1.0), SINK_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	## Immediately down (no animation).
	func force_down() -> void:
		_finish_down()

	func _finish_down() -> void:
		state = "down"
		_t = 0.0
		_len = 0.0
		_damage = 0
		_crack.visible = false
		_roots.visible = false
		_roots.scale = Vector3.ONE
		_set_active_colliders(false)
		set_process(false)

	# --- Harvest / interaction contract (cutting) ----------------------------------------------------------

	func get_harvest_info() -> Dictionary:
		return {"tool": "hand", "name": "Thorny Roots", "kind": "c1x_roots", "hits": hits_needed,
			"depleted": state != "up", "progress": clampf(float(_damage) / float(hits_needed), 0.0, 1.0)}

	func get_interaction(_player: Node = null) -> Dictionary:
		if state != "up":
			return {}
		return {"text": "Cut the thorny roots", "enabled": true}

	func interact(player: Node = null) -> void:
		harvest_hit(player, "")

	func harvest_hit(_player: Node, _tool_item_id: String = "") -> void:
		if state != "up":
			return
		_damage += 1
		Common.play_3d("chop", global_position + Vector3.UP * 0.8, -3.0)
		if is_inside_tree():
			Fx.burst(get_parent(), global_position + Vector3.UP * 0.8, "leaves", 0.6)
		if _damage >= hits_needed:
			cut.emit()
			sink()
