extends "res://tests/test_case.gd"
## Jump reach with movement buffs and slows (player.gd + player_logic.gd, headless physics, real input actions).
## Lead decision for MP 6.2 ("do not increase jump distance unpredictably"): in the air the movement multiplier is
## minf(Stats.move_mult(), 1.10) and a take-off keeps only that share of the ground speed, so a +30% buff stretches a
## sprint jump by ~10% at most; slows still apply fully; the ground speed keeps the whole multiplier.

const PlayerScript := preload("res://src/player/player.gd")
const Logic := preload("res://src/player/player_logic.gd")

const START := Vector3(0, 0.05, 24)

var floor_body: StaticBody3D
var player: CharacterBody3D
var _saved_mode := ""


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 70)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	player = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, START))
	await wait_physics(8)


func after_each() -> void:
	for a in ["move_forward", "sprint", "jump"]:
		Input.action_release(a)
	GameState.buffs.clear()
	Game.mode = _saved_mode
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


## Sprints forward (-Z) until at full speed, then jumps (held) and returns {"ground": speed before take-off,
## "reach": horizontal distance from take-off to landing, "mult": the player's move multiplier}.
func _sprint_jump(buffs: Dictionary) -> Dictionary:
	GameState.buffs.clear()
	for k in buffs:
		GameState.add_buff(String(k), float(buffs[k]), 60.0)
	player.teleport(Transform3D(Basis.IDENTITY, START))
	player.refresh_stats()
	player.stamina = 100.0
	player.rig.snap(0.0)
	Game.mode = "playing"
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics(36)
	var ground := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_press("jump")
	(player.get("_jump") as RefCounted).call("press")
	var took_off := false
	var from := Vector3.ZERO
	var reach := -1.0
	for i in 120:
		await wait_physics(1)
		if not took_off:
			if not player.is_on_floor() and player.velocity.y > 0.0:
				took_off = true
				from = player.global_position
			continue
		if player.is_on_floor():
			var d := player.global_position - from
			reach = Vector2(d.x, d.z).length()
			break
	Input.action_release("jump")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await wait_physics(20)
	return {"ground": ground, "reach": reach, "mult": float(player.move_mult())}


func test_jump_reach_with_a_speed_buff_and_while_slowed() -> void:
	var normal := await _sprint_jump({})
	var buffed := await _sprint_jump({"glimmerstep": 0.3})
	var slowed := await _sprint_jump({"slow": 0.5})
	print("  sprint jump reach: normal %.2f m, +30%% %.2f m, slowed %.2f m" % [normal["reach"], buffed["reach"], slowed["reach"]])
	assert_almost(float(normal["mult"]), 1.0, 0.0001)
	assert_almost(float(buffed["mult"]), 1.3, 0.0001, "the buff is the full +30%")
	assert_almost(float(slowed["mult"]), 0.5, 0.0001)
	assert_almost(float(normal["ground"]), Logic.SPRINT_SPEED, 0.1, "legacy sprint speed")
	assert_almost(float(buffed["ground"]), Logic.SPRINT_SPEED * 1.3, 0.15, "ground speed keeps the whole bonus")
	assert_almost(float(slowed["ground"]), Logic.SPRINT_SPEED * 0.5, 0.1, "a slow applies on the ground")
	var n := float(normal["reach"])
	assert_true(n > 3.5 and n < 5.5, "a legacy sprint jump covers ~4.5 m (%.2f)" % n)
	var up := float(buffed["reach"]) / n
	assert_true(up <= 1.11 and up >= 1.05, "+30%% speed stretches the jump by ~10%% at most (x%.3f)" % up)
	var down := float(slowed["reach"]) / n
	assert_almost(down, 0.5, 0.05, "a slow shortens the jump fully (x%.3f)" % down)
