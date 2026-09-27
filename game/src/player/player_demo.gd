extends Node
## DEBUG-ONLY scripted QA driver for the player (never part of normal play: player.gd only adds it
## when Debug.is_cheat_allowed() and --player-demo=<scenario> is on the command line).
## It presses real input actions (InputEventAction via Input.parse_input_event) so the whole input
## path is exercised, logs player state as JSON lines, saves labelled screenshots and prints checks:
##   --player-demo=arena --player-log=<file.jsonl> --player-shots=<dir>
## Scenario "arena" expects tests/preview/arena.gd and --give=lantern:1,berries:3,stone_axe:1
## (run with --no-focus-pause so losing window focus does not pause the game).

const Logic := preload("res://src/player/player_logic.gd")

var player = null          # the player node (duck typed on purpose: debug-only driver)
var _log: FileAccess
var _shots: String = ""
var _t: float = 0.0
var _log_t: float = 0.0
var _checks: Array = []
var _held: Dictionary = {}
var _follow_cam: bool = true


func _ready() -> void:
	if not Debug.is_cheat_allowed() or player == null:
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Debug.has_arg("player-log"):
		_log = FileAccess.open(Debug.arg("player-log"), FileAccess.WRITE)
	_shots = Debug.arg("player-shots", "")
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	# Godot releases every held input when the window loses focus: keep the scripted "held" keys held.
	for a in _held:
		if not Input.is_action_pressed(a):
			var ev := InputEventAction.new()
			ev.action = a
			ev.pressed = true
			ev.strength = float(_held[a])
			Input.parse_input_event(ev)


func _process(delta: float) -> void:
	_t += delta
	_log_t += delta
	if _log != null and _log_t >= 0.1 and is_instance_valid(player):
		_log_t = 0.0
		_log.store_line(JSON.stringify(_snapshot()))


func _snapshot() -> Dictionary:
	var p: Vector3 = player.global_position
	var v: Vector3 = player.velocity
	var rig = player.get("rig")
	return {"t": snappedf(_t, 0.01), "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)],
		"hspeed": snappedf(Vector2(v.x, v.z).length(), 0.01), "vy": snappedf(v.y, 0.01),
		"floor": player.is_on_floor(), "stamina": snappedf(float(player.stamina), 0.1),
		"hp": snappedf(float(player.health.hp), 0.1), "sprint": player.is_sprinting(), "dodge": player.is_dodging(),
		"lantern": player.lantern_on, "prompt": player.get_prompt(),
		"cam_arm": snappedf(float(rig.arm_length()), 0.01) if rig != null else 0.0,
		"cam_pitch": snappedf(float(rig.pitch), 0.01) if rig != null else 0.0,
		"cam_yaw": snappedf(float(rig.yaw), 0.01) if rig != null else 0.0,
		"zoom": snappedf(float(rig.zoom_target), 0.01) if rig != null else 0.0,
		"mouse_captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED}


# --- Input helpers ------------------------------------------------------------------------------------

func _send(action: String, pressed: bool, strength: float = 1.0) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = strength if pressed else 0.0
	Input.parse_input_event(ev)
	if pressed:
		_held[action] = strength
	else:
		_held.erase(action)


func _tap(action: String) -> void:
	_send(action, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_send(action, false)


func _release_moves() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint"]:
		if _held.has(a):
			_send(a, false)


func _steer(dir: Vector3) -> void:
	var rig = player.get("rig")
	var yaw: float = float(rig.get("yaw"))
	var f := Logic.dir_for_yaw(yaw)
	var r := Vector3(cos(yaw), 0.0, -sin(yaw))
	var x := dir.dot(r)
	var y := -dir.dot(f)
	_axis("move_right", "move_left", x)
	_axis("move_back", "move_forward", y)
	if _follow_cam and dir.length() > 0.1:
		rig.set("yaw", lerp_angle(yaw, Logic.yaw_for_dir(dir), 0.06))


func _axis(pos_action: String, neg_action: String, v: float) -> void:
	if v > 0.05:
		_send(pos_action, true, clampf(v, 0.0, 1.0))
		if _held.has(neg_action):
			_send(neg_action, false)
	elif v < -0.05:
		_send(neg_action, true, clampf(-v, 0.0, 1.0))
		if _held.has(pos_action):
			_send(pos_action, false)
	else:
		if _held.has(pos_action):
			_send(pos_action, false)
		if _held.has(neg_action):
			_send(neg_action, false)


## Walks (or sprints) toward an XZ target. Returns true if reached within the timeout.
func _goto(target: Vector3, timeout: float, sprint: bool = false, radius: float = 0.5) -> bool:
	var t0 := _t
	if sprint:
		_send("sprint", true)
	while _t - t0 < timeout:
		var to: Vector3 = target - player.global_position
		to.y = 0.0
		if to.length() < radius:
			_release_moves()
			return true
		_steer(to.normalized())
		await get_tree().physics_frame
	_release_moves()
	return false


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(label: String) -> void:
	if _shots == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots.path_join(label + ".png"))
	print("DEMO shot ", label)


func _check(check_name: String, ok: bool, detail: String = "") -> void:
	_checks.append({"check": check_name, "ok": ok, "detail": detail})
	print("DEMO CHECK %s %s %s" % [check_name, "PASS" if ok else "FAIL", detail])


# --- Scenario ----------------------------------------------------------------------------------------------

func _run() -> void:
	while Game.mode != "playing":
		await get_tree().process_frame
	await _wait(1.0)
	match Debug.arg("player-demo", "arena"):
		"walk":
			await _walk()
		"log":
			# Passive: only logs state (for driving the game with real OS input, tools/winctl.ps1).
			await _wait(float(Debug.arg("player-demo-seconds", "20")))
		"wallhug":
			await _wallhug()
		"harvest":
			await _harvest_real()
		"deathcut":
			await _death_in_cutscene()
		_:
			await _arena()
	if _log != null:
		_log.store_line(JSON.stringify({"summary": _checks}))
		_log.flush()
	var failed := 0
	for c in _checks:
		if not bool(c["ok"]):
			failed += 1
	print("DEMO DONE %d checks, %d failed" % [_checks.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)


func _spawn_dummy(mode: String, dist: float) -> Node3D:
	var s: Script = load("res://src/player/qa_dummy.gd")
	var d: Node3D = s.new()
	d.setup({"mode": mode})
	get_tree().current_scene.add_child(d)
	var f: Vector3 = player.get_facing()
	d.global_position = player.global_position + f * dist
	await get_tree().physics_frame
	await _wait(0.25)
	return d


func _hspeed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _arena() -> void:
	var rig = player.get("rig")
	await _shot("00_spawn")
	_check("spawn_grounded", player.is_on_floor(), str(player.global_position))
	# Walk (+X, open ground) and measure speed
	_send("move_right", true)
	await _wait(1.2)
	_check("walk_speed", absf(_hspeed() - Logic.WALK_SPEED) < 0.3, "%.2f" % _hspeed())
	await _shot("01_walk")
	# Sprint: faster and drains stamina
	_send("sprint", true)
	await _wait(1.0)
	_check("sprint_speed", absf(_hspeed() - Logic.SPRINT_SPEED) < 0.4, "%.2f" % _hspeed())
	_check("sprint_drains", float(player.stamina) < 90.0, "stamina %.1f" % float(player.stamina))
	await _shot("02_sprint")
	_release_moves()
	await _wait(0.8)
	_check("decelerates", _hspeed() < 0.2, "%.2f" % _hspeed())
	await _wait(1.5)
	# Jump: held = full height, tap = smaller hop (variable jump)
	var y0: float = player.global_position.y
	var peak := y0
	_send("jump", true)
	for i in 50:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	_send("jump", false)
	_check("jump_full_height", peak - y0 > 0.85 and peak - y0 < 1.15, "%.2f m" % (peak - y0))
	await _wait(0.5)
	peak = y0
	_tap("jump")
	for i in 50:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
	_check("jump_tap_height", peak - y0 > 0.6 and peak - y0 < 0.95, "%.2f m" % (peak - y0))
	await _wait(0.4)
	# Dodge: burst + i-frames + stamina cost, then regeneration after the delay
	var st0: float = float(player.stamina)
	_send("move_left", true)
	await _wait(0.2)
	_tap("dodge")
	await _wait(0.08)
	var dodge_speed := _hspeed()
	var dealt: float = float(player.health.apply_damage(10.0, null, Vector3.ZERO))
	_check("dodge_burst", player.is_dodging() and dodge_speed > 6.0, "%.2f" % dodge_speed)
	_check("dodge_iframes", dealt == 0.0, "dealt %.1f" % dealt)
	_check("dodge_cost", float(player.stamina) <= st0 - Logic.DODGE_COST + 0.5, "%.1f -> %.1f" % [st0, float(player.stamina)])
	await _shot("03_roll")
	_release_moves()
	var st1: float = float(player.stamina)
	await _wait(0.3)
	_check("regen_delay", absf(float(player.stamina) - st1) < 1.0, "%.1f -> %.1f" % [st1, float(player.stamina)])
	await _wait(0.8)
	_check("stamina_regen", float(player.stamina) > st1 + 8.0, "%.1f -> %.1f" % [st1, float(player.stamina)])
	# Hurt: damage, hp sync, knockback, i-frames
	var hp0: float = float(player.health.hp)
	dealt = float(player.health.apply_damage(12.0, null, Vector3(1, 0, 0)))
	await _wait(0.05)
	await _shot("04_hurt")
	_check("hurt_damage", dealt > 0.0 and absf(float(GameState.player["hp"]) - (hp0 - dealt)) < 0.01, "hp %.1f" % float(GameState.player["hp"]))
	_check("hurt_knockback", player.velocity.x > 1.0, "vx %.2f" % player.velocity.x)
	var dealt2: float = float(player.health.apply_damage(12.0, null, Vector3.ZERO))
	_check("hurt_iframes", dealt2 == 0.0, "second hit %.1f" % dealt2)
	await _wait(1.0)
	# Eat berries from the hotbar
	for i in GameState.HOTBAR_SIZE:
		var s: Variant = GameState.inventory.get_slot(i)
		if s is Dictionary and String(s["id"]) == "berries":
			_tap("hotbar_%d" % (i + 1))
			break
	await _wait(0.1)
	var hp1: float = float(player.health.hp)
	var berries0: int = GameState.count_item("berries")
	_tap("use_item")
	await _wait(0.45)
	await _shot("05_eat")
	_check("eat_heals", float(player.health.hp) > hp1 and GameState.count_item("berries") == berries0 - 1, "hp %.1f berries %d" % [float(player.health.hp), GameState.count_item("berries")])
	await _wait(1.0)
	# Lantern
	_tap("lantern")
	await _wait(0.4)
	_check("lantern_on", bool(player.lantern_on) and bool(player.is_light_active()) and bool(GameState.player["lantern_on"]), "")
	await _shot("06_lantern")
	_tap("lantern")
	await _wait(0.3)
	_check("lantern_off", not bool(player.lantern_on), "")
	# Harvestable: prompt without / with the tool, exactly one harvest_hit per swing, buffered click
	var tree: Node3D = await _spawn_dummy("harvest", 1.35)
	var pr: Dictionary = player.get_prompt()
	_check("prompt_needs_tool", String(pr.get("text", "")) == "Needs an Axe" and not bool(pr.get("enabled", true)), str(pr))
	GameState.give_item("stone_axe", 1)
	await _wait(0.25)
	pr = player.get_prompt()
	_check("prompt_chop", String(pr.get("text", "")) == "Chop Test Tree" and String(pr.get("action", "")) == "attack" and bool(pr.get("enabled", false)), str(pr))
	_tap("attack")
	await _wait(0.16)
	await _shot("07_axe_windup")
	await _wait(0.08)
	await _shot("08_axe_strike")
	await _wait(0.5)
	_check("harvest_one_hit", tree.get("hits") == ["stone_axe"], str(tree.get("hits")))
	_tap("attack")
	await _wait(0.2)
	_tap("attack")
	await _wait(0.05)
	_tap("attack")        # a third click inside the same swing must be ignored (one buffered click max)
	await _wait(1.4)
	_check("harvest_buffered", (tree.get("hits") as Array).size() == 3, str(tree.get("hits")))
	tree.queue_free()
	await _wait(0.3)
	# Interactable
	var chest: Node3D = await _spawn_dummy("chest", 1.3)
	pr = player.get_prompt()
	_check("prompt_interact", String(pr.get("text", "")) == "Open Test Chest" and String(pr.get("action", "")) == "interact", str(pr))
	_tap("interact")
	await _wait(0.3)
	_check("interact_once", int(chest.get("interacts")) == 1, str(chest.get("interacts")))
	chest.queue_free()
	await _wait(0.3)
	# Enemy: weapon swing (best weapon = stone axe, 9 damage) hits exactly once
	var foe: Node3D = await _spawn_dummy("enemy", 1.4)
	_tap("attack")
	await _wait(0.7)
	var foe_hp: float = float(foe.get("health").hp)
	_check("melee_one_hit", absf(foe_hp - 21.0) < 0.01, "enemy hp %.1f" % foe_hp)
	GameState.give_item("copper_sword", 1)
	_tap("attack")
	await _wait(0.2)
	await _shot("09_sword")
	await _wait(0.6)
	foe_hp = float(foe.get("health").hp)
	_check("sword_damage", absf(foe_hp - 3.0) < 0.01, "enemy hp %.1f" % foe_hp)
	foe.queue_free()
	await _wait(0.3)
	# Ramp (20 deg) up and off the high end
	await _goto(Vector3(10, 0, -8.5), 10.0)
	var ok: bool = await _goto(Vector3(10, 0, -16.5), 6.0)
	var top_y: float = player.global_position.y
	_check("ramp_climb", ok and top_y > 2.0, "y %.2f" % top_y)
	await _shot("10_ramp_top")
	await _goto(Vector3(10, 0, -21.0), 4.0)
	await _wait(0.8)
	_check("ramp_drop_land", player.is_on_floor() and player.global_position.y < 0.3, "y %.2f" % player.global_position.y)
	# Steep (50 deg) slope: cannot be walked up
	await _goto(Vector3(18, 0, -6.0), 10.0)
	var max_y := 0.0
	var t0 := _t
	while _t - t0 < 2.5:
		_steer(Vector3(0, 0, -1))
		max_y = maxf(max_y, player.global_position.y)
		await get_tree().physics_frame
	_release_moves()
	_check("steep_slope_blocks", max_y < 1.2, "max y %.2f" % max_y)
	await _shot("11_steep")
	# Stairs (ramp collision with a small lip at the top)
	await _goto(Vector3(14, 0, -7.5), 6.0)
	await _goto(Vector3(-10, 0, -6.8), 12.0)
	ok = await _goto(Vector3(-10, 0, -12.2), 6.0)
	_check("stairs_climb", ok and player.global_position.y > 1.95, "y %.2f" % player.global_position.y)
	await _shot("12_stairs_top")
	# Doorway (1 m gap)
	await _goto(Vector3(2.5, 0, -14.5), 12.0)
	ok = await _goto(Vector3(2.5, 0, -21.0), 6.0, false, 0.4)
	_check("doorway_pass", ok and player.global_position.z < -19.0, "z %.2f" % player.global_position.z)
	rig.set("yaw", 0.0)
	await _wait(0.7)
	await _shot("13_doorway_back")
	# Wall corner: camera pulls in, then eases back out
	await _goto(Vector3(2.5, 0, -15.0), 6.0)
	await _goto(Vector3(6.5, 0, -17.4), 6.0, false, 0.3)
	_follow_cam = false
	rig.set("yaw", deg_to_rad(-120.0))
	await _wait(0.8)
	var arm: float = float(rig.arm_length())
	_check("camera_wall_pullin", arm < 3.0, "arm %.2f" % arm)
	await _shot("14_corner_cam")
	rig.set("yaw", deg_to_rad(-45.0))
	await _wait(1.6)
	_check("camera_eases_out", float(rig.arm_length()) > arm + 0.5, "arm %.2f" % float(rig.arm_length()))
	await _shot("15_corner_open")
	_follow_cam = true
	# Pitch clamp and zoom clamp
	rig.rotate_by(Vector2(0, -5000))
	var pa: float = float(rig.pitch)
	rig.rotate_by(Vector2(0, 5000))
	var pb: float = float(rig.pitch)
	_check("pitch_clamp", absf(maxf(pa, pb) - 0.6109) < 0.01 and absf(minf(pa, pb) + 1.1345) < 0.01, "%.3f .. %.3f" % [minf(pa, pb), maxf(pa, pb)])
	rig.set("pitch", -0.3)
	rig.zoom_by(-20.0)
	_check("zoom_clamp", absf(float(rig.zoom_target) - 2.5) < 0.01, "")
	rig.zoom_by(2.5)
	# Fall into the void off the arena edge -> recovery to safe ground
	await _goto(Vector3(0, 0, 36.0), 16.0, true)
	await _wait(0.6)
	var safe_before: Vector3 = player.global_position
	var t1 := _t
	var fell := false
	while _t - t1 < 9.0:
		if not fell:
			_steer(Vector3(0, 0, 1))
		if player.global_position.y < -3.0 and not fell:
			fell = true
			_release_moves()
			await _shot("16_falling")
		if fell and player.is_on_floor() and player.global_position.y > -0.5:
			break
		await get_tree().physics_frame
	_release_moves()
	await _wait(0.8)
	var back: Vector3 = player.global_position
	_check("fall_recovery", fell and player.is_on_floor() and back.y > -0.5 and back.distance_to(safe_before) < 8.0, "back at %s" % str(back))
	await _shot("17_recovered")
	# Sprint until empty: exhaustion stops sprinting
	await _wait(2.0)
	_send("sprint", true)
	var t2 := _t
	var emptied := false
	while _t - t2 < 8.0:
		# Re-press every frame: Godot releases held inputs when the window loses focus.
		_send("sprint", true)
		_steer(Vector3(0, 0, -1) if player.global_position.z > -12.0 else Vector3(0, 0, 1))
		if float(player.stamina) <= 0.01:
			emptied = true
			break
		await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sprint_after: bool = player.is_sprinting()
	_release_moves()
	_check("stamina_exhaust", emptied and not sprint_after, "stamina %.1f" % float(player.stamina))
	# Save state
	await _wait(0.5)
	player.write_to_state()
	var pos: Variant = GameState.player.get("pos")
	_check("write_state", pos is Array and (pos as Array).size() == 3, str(pos))


## Generic stroll for real areas (surface / below): walks a square, sprints, jumps, lantern at the end.
## Checks: no unexpected fall recovery, stays grounded most of the time, footstep surfaces reported.
func _walk() -> void:
	var rig = player.get("rig")
	var surfaces := {}
	var av = player.get("avatar")
	av.footstep.connect(func(_f: int) -> void: surfaces[player.surface_name()] = true)
	await _shot("walk_00_spawn")
	var grounded_frames := 0
	var frames := 0
	var yaw0: float = float(rig.get("yaw"))
	for leg in 4:
		var dir := Logic.dir_for_yaw(yaw0 + float(leg) * PI * 0.5)
		var t0 := _t
		if leg == 2:
			_send("sprint", true)
		while _t - t0 < 3.0:
			_steer(dir)
			frames += 1
			if player.is_on_floor():
				grounded_frames += 1
			await get_tree().physics_frame
		_release_moves()
		if leg == 1:
			_tap("jump")
		await _wait(0.4)
		await _shot("walk_%02d_leg" % (leg + 1))
	GameState.give_item("lantern", 1)
	_tap("lantern")
	_follow_cam = false
	rig.set("yaw", float(rig.get("yaw")) + PI)
	await _wait(1.0)
	await _shot("walk_05_lantern_front")
	_check("no_unexpected_recovery", int(player.get("recoveries")) == 0, "recoveries %d" % int(player.get("recoveries")))
	_check("mostly_grounded", frames > 0 and float(grounded_frames) / float(frames) > 0.8, "%d/%d" % [grounded_frames, frames])
	_check("footsteps", not surfaces.is_empty(), str(surfaces.keys()))


## Camera vs. walls on the shoulder side (arena wall x 6.8..7.2, z -18..-12): Krystal hugs the wall with
## it on her right, the camera looks along it. The eye must never end up inside / behind the wall.
## Optional --wallhug-pos="x,y,z" --wallhug-yaw=<deg> for other areas (e.g. the Below tunnel).
func _wallhug() -> void:
	var rig = player.get("rig")
	_follow_cam = false
	var pv := Debug.arg("wallhug-pos", "6.45,0.05,-17.2").split(",")
	var pos := Vector3(float(pv[0]), float(pv[1]), float(pv[2]))
	var yaw := deg_to_rad(float(Debug.arg("wallhug-yaw", "0")))
	player.teleport(Transform3D(Basis(Vector3.UP, yaw), pos))
	# Press into the wall on the right for a moment so she really touches it.
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var t0 := _t
	while _t - t0 < 0.6:
		_steer(right)
		await get_tree().physics_frame
	_release_moves()
	rig.set("yaw", yaw)
	await _wait(1.2)
	var cam: Camera3D = player.get_camera()
	var eye: Vector3 = cam.get_camera_transform().origin
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var from: Vector3 = player.global_position + Vector3.UP * 1.38
	var q := PhysicsRayQueryParameters3D.create(from, eye, 1 | 32, [player.get_rid()])
	var hit := space.intersect_ray(q)
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = eye
	pq.collision_mask = 1 | 32
	var inside := not space.intersect_point(pq, 1).is_empty()
	_check("eye_not_behind_wall", hit.is_empty() and not inside, "eye %s hit %s inside %s" % [str(eye), str(hit.get("position", "-")), str(inside)])
	await _shot("wallhug_right")
	rig.set("yaw", yaw + deg_to_rad(25.0))
	await _wait(1.0)
	await _shot("wallhug_right_turned")


## Death while Game is not "playing" (e.g. a hit during the lift-ride cutscene): Game.on_player_died()
## ignores it, so the player must retry once play resumes. Checks that Krystal is revived afterwards.
func _death_in_cutscene() -> void:
	Game.set_respawn(Game.area_id, "haven_respawn")    # wake in this area (same player node, no reload)
	Game.set_cutscene(true)
	player.health.apply_damage(500.0)
	await _wait(0.5)
	_check("dead_in_cutscene", bool(player.is_dead()) and Game.mode == "cutscene", "mode %s" % Game.mode)
	Game.set_cutscene(false)
	var t0 := _t
	var saw_dead_mode := false
	while _t - t0 < 12.0:
		if Game.mode == "dead":
			saw_dead_mode = true
		if saw_dead_mode and Game.mode == "playing" and is_instance_valid(player) and not bool(player.is_dead()):
			break
		await get_tree().process_frame
	var p: Node = Game.player
	_check("death_retried_and_revived", saw_dead_mode and p != null and is_instance_valid(p) and not bool(p.is_dead()) and Game.mode == "playing", "mode %s" % Game.mode)


## Real resource nodes (surface): chop the nearest tree with E (the prompt says LMB; E swings too), then
## make sure the felled stump shows no "Chop" prompt. --give=stone_axe:1 is added by the scenario itself.
func _harvest_real() -> void:
	GameState.give_item("stone_axe", 1)
	var best: Node3D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("harvestable"):
		if not (n is Node3D) or not n.has_method("get_harvest_info"):
			continue
		var info: Dictionary = n.get_harvest_info()
		if String(info.get("tool", "")) != "axe" or bool(info.get("depleted", false)):
			continue
		var d: float = (n as Node3D).global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		_check("found_tree", false, "no tree")
		return
	var tp: Vector3 = best.global_position
	var from := tp + Vector3(0, 0, 1.6)
	if Game.area != null and Game.area.has_method("height_at"):
		from.y = float(Game.area.height_at(from.x, from.z)) + 0.05
	player.teleport(Transform3D(Basis.IDENTITY, from))
	await _wait(0.8)
	var pr: Dictionary = player.get_prompt()
	_check("tree_prompt_attack", String(pr.get("action", "")) == "attack" and String(pr.get("text", "")).begins_with("Chop"), str(pr))
	await _shot("harvest_00_prompt")
	var wood0: int = GameState.count_item("wood")
	for i in 8:
		_tap("interact")
		await _wait(0.62)
		if i == 0:
			await _shot("harvest_01_swing")
		var info: Dictionary = best.get_harvest_info()
		if bool(info.get("depleted", false)):
			break
	await _wait(2.0)
	_check("tree_felled_with_e", bool(best.get_harvest_info().get("depleted", false)) and GameState.count_item("wood") > wood0, "wood %d -> %d" % [wood0, GameState.count_item("wood")])
	await _shot("harvest_02_stump")
	pr = player.get_prompt()
	_check("stump_no_chop_prompt", not String(pr.get("text", "")).begins_with("Chop"), str(pr))
