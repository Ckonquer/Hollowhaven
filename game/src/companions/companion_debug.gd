extends Node
## DEBUG-ONLY QA helper for the companions (added by companion_spawner.gd only when
## Debug.is_cheat_allowed() and one of these args is present). Never active in release builds.
##   --companion-walk=loop|far|circle     drives Krystal along a scripted route (arena layout)
##   --companion-log=<file.jsonl>         logs companion states twice per second
##   --companion-scenario=befriend|boulder|lumi|threat|pet|refuse|return|night
##                                        scripted interactions to watch the sequences

const ROUTES := {
	"loop": [Vector3(0, 0, 6), Vector3(0, 0, -6), Vector3(2.5, 0, -13), Vector3(2.5, 0, -22), Vector3(-6, 0, -25),
		Vector3(-14, 0, -18), Vector3(-13.5, 0, -3), Vector3(-2, 0, 4), Vector3(14, 0, 4), Vector3(14, 0, 16), Vector3(0, 0, 8)],
	"ramps": [Vector3(0, 0, 2), Vector3(-10, 0, -5), Vector3(-10, 0, -10.8), Vector3(-10, 0, -6), Vector3(10, 0, -8),
		Vector3(10, 0, -16.5), Vector3(10, 0, -6), Vector3(0, 0, 4)],
	"circle": [Vector3(6, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 6), Vector3(-4, 0, 4), Vector3(-6, 0, 0), Vector3(-4, 0, -4), Vector3(0, 0, -6), Vector3(4, 0, -4)],
}

var _t: float = 0.0
var _route: Array = []
var _wp: int = 0
var _speed: float = 4.2
var _log: FileAccess
var _log_t: float = 0.0
var _scenario: String = ""
var _steps_done: Dictionary = {}
var _pause_t: float = 0.0
var _dummy: Node3D
var _gain: float = 1.0
var _last_pos := Vector3.INF
static var _log_started := false


func _ready() -> void:
	if not Debug.is_cheat_allowed():
		queue_free()
		return
	process_physics_priority = 100
	var walk := Debug.arg("companion-walk")
	if ROUTES.has(walk):
		_route = ROUTES[walk]
	elif walk == "far":
		_route = [Vector3(0, 0, 6), Vector3(0, 0, -2)]
	if Debug.has_arg("companion-log"):
		# Truncate on the first area of this run, append after area changes.
		var path := Debug.arg("companion-log")
		if _log_started and FileAccess.file_exists(path):
			_log = FileAccess.open(path, FileAccess.READ_WRITE)
			if _log != null:
				_log.seek_end()
		else:
			_log = FileAccess.open(path, FileAccess.WRITE)
		_log_started = true
	_scenario = Debug.arg("companion-scenario")


func _physics_process(delta: float) -> void:
	_t += delta
	var p := Game.player
	if p == null or not is_instance_valid(p):
		return
	if Debug.arg("companion-walk") == "far" and _t > 6.0 and not _steps_done.has("far"):
		_steps_done["far"] = true
		p.global_position = p.global_position + Vector3(0, 0, -26)
		print("CompanionDebug: teleported Krystal 26 m away")
	if not _route.is_empty() and _t > 1.5 and _pause_t <= 0.0:
		_drive(p, delta)
	_pause_t -= delta
	_run_scenario(p)
	if _log != null:
		_log_t += delta
		if _log_t >= 0.5:
			_log_t = 0.0
			_write_log(p)


func _drive(p: Node3D, delta: float) -> void:
	var target: Vector3 = _route[_wp % _route.size()]
	var to := Vector3(target.x - p.global_position.x, 0.0, target.z - p.global_position.z)
	if to.length() < 0.4:
		_wp += 1
		if _wp % 4 == 0:
			_pause_t = 2.5     # stop now and then so we can watch the companion settle
			_last_pos = Vector3.INF
		_speed = 6.8 if (_wp % 5 == 2) else 4.2
		return
	var dir := to.normalized()
	# Adaptive gain: the real player keeps (and moves with) the velocity we set, the placeholder
	# zeroes it. Measure the actual speed and scale so Krystal moves at the intended pace either way.
	if _last_pos != Vector3.INF and delta > 0.0:
		var actual := Vector2(p.global_position.x - _last_pos.x, p.global_position.z - _last_pos.z).length() / delta
		if actual > 0.5:
			_gain = clampf(_gain * lerpf(1.0, _speed / actual, 0.15), 0.3, 1.5)
	_last_pos = p.global_position
	if p is CharacterBody3D:
		var cb: CharacterBody3D = p
		cb.velocity = Vector3(dir.x * _speed * _gain, cb.velocity.y, dir.z * _speed * _gain)
		cb.move_and_slide()
	else:
		p.global_position += dir * _speed * delta
	p.rotation.y = lerp_angle(p.rotation.y, atan2(-dir.x, -dir.z), 0.2)
	# Keep the (real) camera rig looking along the walk so screenshots show what follows.
	var rig: Variant = p.get("rig")
	if rig is Node and "yaw" in rig:
		rig.set("yaw", lerp_angle(float(rig.get("yaw")), atan2(-dir.x, -dir.z), 0.04))


func _run_scenario(p: Node3D) -> void:
	match _scenario:
		"befriend":
			_step("give", 1.0, func() -> void: GameState.give_item("berries", 3))
			_step("walk_to_mochi", 1.5, func() -> void: _put_player_near("mochi", 1.8))
			_step("offer", 3.5, func() -> void: _interact("mochi"))
		"boulder":
			_step("give", 1.0, func() -> void: GameState.give_item("stone_pickaxe", 1))
			_step("walk", 1.5, func() -> void: _put_player_near_boulder())
			for i in 4:
				_step("hit%d" % i, 3.0 + float(i) * 0.9, func() -> void: _hit_boulder())
		"lumi":
			_step("walk", 1.0, func() -> void: _put_player_near("lumi", 5.0))
			_step("clear", 4.0, func() -> void: GameState.set_flag("ruin_cleared", true))
			_step("reach", 8.0, func() -> void: _interact("lumi"))
		"threat":
			_step("dummy", 3.0, func() -> void: _spawn_dummy(p.global_position + _player_fwd(p) * 7.0))
			_step("close", 6.0, func() -> void:
				if _dummy != null and is_instance_valid(_dummy):
					_dummy.global_position = p.global_position + _player_fwd(p) * 4.0)
			_step("gone", 11.0, func() -> void:
				if _dummy != null and is_instance_valid(_dummy):
					_dummy.queue_free())
		"pet":
			_step("view", 0.5, func() -> void: _view_homes(p))
			for i in 3:
				_step("pet%d" % i, 2.0 + float(i) * 2.0, func() -> void: _command_all("pet"))
			_step("feed", 8.5, func() -> void:
				GameState.give_item("berries", 2)
				GameState.give_item("shiny_pebble", 1)
				GameState.give_item("sweetroot", 1)
				_command_all("feed"))
			_step("celebrate", 11.0, func() -> void:
				for id in Game.companion_nodes:
					Game.companion_nodes[id].react("celebrate"))
		"return":
			if Game.area_id == "below":
				_step("up", 3.0, func() -> void: Game.change_area("surface", "mine_exit"))
		"refuse":
			if not (Game.area_id == "surface" or Game.area_id == "arena"):
				return
			# Full mine flow (use with --save-dir=user://test_saves/...): Mochi refuses at the threshold,
			# Krystal goes below alone, comes back out of the mine and Mochi bounces over.
			_step("near", 2.0, func() -> void: _put_near_threshold(p, 13.0))
			_step("close", 5.0, func() -> void: _put_near_threshold(p, 5.0))
			_step("below", 11.0, func() -> void: Game.change_area("below", "mine_entry"))
		"night":
			_step("view", 0.5, func() -> void: _view_homes(p))
			_step("night", 0.6, func() -> void: GameState.total_minutes = float(GameState.day() - 1) * 1440.0 + 22.0 * 60.0)


func _put_near_threshold(p: Node3D, dist: float) -> void:
	if Game.area == null or not Game.area.has_method("get_spawn"):
		return
	var th: Transform3D = Game.area.get_spawn("mine_threshold")
	var ex: Transform3D = Game.area.get_spawn("mine_exit")
	var away := th.origin - ex.origin
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	# Approach from the side away from the mine mouth.
	var pos := th.origin - away * dist
	if Game.area.has_method("height_at"):
		pos.y = float(Game.area.height_at(pos.x, pos.z)) + 0.1
	p.global_position = pos
	print("CompanionDebug: Krystal placed %.1f m from the threshold" % dist)


## Stands Krystal a few metres from the companion homes, looking at them.
func _view_homes(p: Node3D) -> void:
	var sum := Vector3.ZERO
	var n := 0
	for id in Game.companion_nodes:
		var c := _node(String(id))
		if c != null:
			sum += c.get("home_pos")
			n += 1
	if n == 0:
		return
	var center := sum / float(n)
	p.global_position = center + Vector3(0, 0.05, 4.2)
	p.rotation.y = 0.0
	var rig: Variant = p.get("rig")
	if rig is Node and "yaw" in rig:
		rig.set("yaw", 0.0)


func _step(key: String, at: float, fn: Callable) -> void:
	if _steps_done.has(key) or _t < at:
		return
	_steps_done[key] = true
	print("CompanionDebug: step ", key, " at ", snappedf(_t, 0.1))
	fn.call()


func _node(id: String) -> Node3D:
	var n: Variant = Game.companion_nodes.get(id)
	return n if n is Node3D and is_instance_valid(n) else null


func _put_player_near(id: String, dist: float) -> void:
	var c := _node(id)
	if c == null or Game.player == null:
		return
	var p := Game.player
	# Stand a little to the side so Krystal doesn't hide the creature from the camera.
	var from := c.global_position + Vector3(dist * 0.55, 0, dist * 0.85)
	p.global_position = from
	p.rotation.y = 0.0


func _put_player_near_boulder() -> void:
	for b in get_tree().get_nodes_in_group("harvestable"):
		if b.name == "PebbleBoulder":
			var fwd: Vector3 = b.get("front")
			Game.player.global_position = (b as Node3D).global_position + fwd * 2.2
			return


func _hit_boulder() -> void:
	for b in get_tree().get_nodes_in_group("harvestable"):
		if b.name == "PebbleBoulder" and b.has_method("harvest_hit"):
			b.harvest_hit(Game.player, GameState.best_tool("pickaxe"))


func _interact(id: String) -> void:
	var c := _node(id)
	if c != null:
		print("CompanionDebug: prompt ", c.get_interaction(Game.player))
		c.interact(Game.player)


func _command_all(cmd: String) -> void:
	for id in Game.companion_nodes:
		var c := _node(String(id))
		if c != null:
			print("CompanionDebug: ", id, " ", cmd, " -> ", c.command(cmd))


func _player_fwd(p: Node3D) -> Vector3:
	var f := -p.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


func _spawn_dummy(pos: Vector3) -> void:
	var d := _DummyEnemy.new()
	Game.area.add_child(d)
	d.global_position = pos
	_dummy = d


func _write_log(p: Node3D) -> void:
	var row := {"t": snappedf(_t, 0.01), "area": Game.area_id, "player": _v(p.global_position)}
	var cs := {}
	for id in Game.companion_nodes:
		var c := _node(String(id))
		if c == null:
			continue
		cs[id] = {"state": c.get_state(), "mode": c.get("mode"), "pos": _v(c.global_position),
			"dist": snappedf(c.global_position.distance_to(p.global_position), 0.01),
			"emote": c.visual.get_emote_kind(), "bond": int(GameState.companion(String(id))["bond_xp"])}
	row["companions"] = cs
	row["active"] = GameState.active_companion
	_log.store_line(JSON.stringify(row))
	_log.flush()


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


## A stand-in "enemy" for watching threat reactions (debug scenario only).
class _DummyEnemy extends Node3D:
	func _ready() -> void:
		add_to_group("enemy")
		var mi := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 0.35
		m.height = 0.7
		mi.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("6e3a52")
		mi.material_override = mat
		add_child(mi)
		mi.position.y = 0.35

	func is_threatening() -> bool:
		return true
