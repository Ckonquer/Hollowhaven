extends "res://tests/test_case.gd"
## Player node integration (headless physics): contract API, state sync, damage & i-frames,
## eating, lantern, movement through real input actions, fall recovery, one strike per swing and
## the camera rig (clamps, comfort-scaled shake, live settings).

const PlayerScript := preload("res://src/player/player.gd")
const DummyScript := preload("res://src/player/qa_dummy.gd")
const Logic := preload("res://src/player/player_logic.gd")

var floor_body: StaticBody3D
var player: CharacterBody3D
var _saved_mode: String = ""
var _saved_settings: Dictionary = {}
var _damaged_events: int = 0


func before_each() -> void:
	fresh_state()
	_saved_mode = Game.mode
	for k in ["fov", "reduce_shake", "mouse_sensitivity", "invert_y", "camera_distance"]:
		_saved_settings[k] = Settings.get_value(k)
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	player = PlayerScript.new()
	add_child(player)
	player.read_from_state()
	player.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)))
	await wait_physics(10)


func after_each() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump"]:
		Input.action_release(a)
	Game.mode = _saved_mode
	for k in _saved_settings:
		Settings.set_value(k, _saved_settings[k])
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(floor_body):
		floor_body.queue_free()
	for c in get_children():
		c.queue_free()
	await wait_frames(2)


func _allow_input() -> void:
	Game.mode = "playing"


# --- Contract ------------------------------------------------------------------------------------------

func test_contract_shape() -> void:
	assert_true(player.is_in_group("player"), "group player")
	assert_true(player.is_in_group("light_source"), "group light_source")
	assert_eq(player.collision_layer, 2, "layer")
	assert_eq(player.collision_mask, 1 | 32, "mask")
	assert_almost(player.floor_max_angle, deg_to_rad(46.0), 0.01)
	assert_not_null(player.health, "health child")
	assert_eq(player.health.get_parent(), player)
	assert_almost(float(player.health.max_hp), 100.0, 0.001)
	assert_true(player.get_camera() is Camera3D, "camera")
	assert_almost(float(player.light_radius), 6.0, 0.001)
	for m in ["teleport", "read_from_state", "write_to_state", "set_input_enabled", "get_camera", "set_lantern",
			"is_sprinting", "is_dodging", "is_moving", "get_prompt", "get_focus_target", "get_facing",
			"play_emote", "knockback", "is_light_active"]:
		assert_true(player.has_method(m), "has %s" % m)
	assert_true(player.is_on_floor(), "stands on the floor")
	assert_eq(player.get_prompt(), {}, "no prompt without targets")


func test_teleport_sets_position_and_facing() -> void:
	var xf := Transform3D(Basis(Vector3.UP, 1.2), Vector3(3, 0.05, -2))
	player.teleport(xf)
	assert_true(player.global_position.distance_to(Vector3(3, 0.05, -2)) < 0.001)
	assert_true(player.get_facing().distance_to(-xf.basis.z) < 0.01, "faces the spawn's -Z")
	assert_almost(angle_difference(float(player.rig.yaw), 1.2), 0.0, 0.01, "camera snapped behind")


func test_read_and_write_state() -> void:
	GameState.player["hp"] = 40.0
	GameState.player["stamina"] = 30.0
	GameState.player["lantern_on"] = true
	player.read_from_state()
	assert_almost(float(player.health.hp), 40.0, 0.001, "hp loaded")
	assert_almost(float(player.stamina), 30.0, 0.001, "stamina loaded")
	assert_false(player.lantern_on, "lantern stays off without the lantern item")
	assert_false(bool(GameState.player["lantern_on"]), "and the state is corrected")
	GameState.give_item("lantern", 1)
	GameState.player["lantern_on"] = true
	player.read_from_state()
	assert_true(player.lantern_on, "lantern restored when owned")
	GameState.player["hp"] = 0.0
	player.read_from_state()
	assert_almost(float(player.health.hp), 100.0, 0.001, "never loads dead")
	await wait_physics(2)
	player.write_to_state()
	var p: Variant = GameState.player["pos"]
	assert_true(p is Array and absf(float(p[0])) < 0.01 and absf(float(p[2])) < 0.01, "grounded position written")
	assert_true(bool(GameState.player["lantern_on"]), "lantern written")


func test_write_state_skips_position_in_danger() -> void:
	await wait_physics(40)                       # safe tracker records the spawn area
	player.global_position = Vector3(5, 0.05, 0)  # moved (not a teleport) and immediately hurt
	await wait_physics(3)
	player.health.apply_damage(5.0)
	player.write_to_state()
	var after: Array = GameState.player["pos"]
	var saved := Vector3(float(after[0]), 0.0, float(after[2]))
	assert_true(saved.distance_to(Vector3.ZERO) < 0.5, "in danger: the last safe spot is saved, not the current one (%s)" % str(after))


func test_damage_sync_iframes_and_event() -> void:
	_damaged_events = 0
	Events.player_damaged.connect(_on_player_damaged)
	var dealt: float = float(player.health.apply_damage(15.0, null, Vector3(0, 0, 1)))
	assert_almost(dealt, 15.0, 0.001)
	assert_almost(float(GameState.player["hp"]), 85.0, 0.001, "hp synced to GameState")
	assert_eq(_damaged_events, 1, "Events.player_damaged emitted")
	assert_true(player.velocity.z > 1.0, "knocked back along the hit direction")
	assert_almost(float(player.health.apply_damage(15.0)), 0.0, 0.001, "hurt i-frames")
	Events.player_damaged.disconnect(_on_player_damaged)


func _on_player_damaged(_amount: float, _source: Node) -> void:
	_damaged_events += 1


func test_knockback_replaces_and_is_ignored_while_rolling() -> void:
	player.knockback(Vector3(1, 0, 0), 5.0)
	player.knockback(Vector3(1, 0, 0), 5.0)
	assert_almost(player.velocity.x, 5.0, 0.001, "knockback does not stack")
	player.knockback(Vector3(0, 0, 0), 5.0)
	assert_almost(player.velocity.x, 5.0, 0.001, "zero direction ignored")
	player.set("_dodge_t", 0.1)
	player.knockback(Vector3(-1, 0, 0), 9.0)
	assert_almost(player.velocity.x, 5.0, 0.001, "no knockback during a roll")


func test_death_disables_input_and_respawn_revives() -> void:
	# Game.mode is not "playing" here, so Game.on_player_died() returns without the respawn flow.
	player.health.apply_damage(500.0)
	assert_true(player.is_dead(), "dead")
	_allow_input()
	assert_false(player.can_probe(), "no interaction while dead")
	Input.action_press("move_forward")
	await wait_physics(10)
	assert_true(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "no movement while dead")
	Input.action_release("move_forward")
	Game.mode = _saved_mode
	GameState.player["hp"] = 100.0
	player.read_from_state()
	assert_false(player.is_dead(), "revived by read_from_state")
	assert_almost(float(player.health.hp), 100.0, 0.001)


func test_eating_rules() -> void:
	GameState.give_item("berries", 2)
	assert_false(player.eat("berries"), "refused at full health")
	assert_eq(GameState.count_item("berries"), 2, "nothing consumed when refused")
	player.health.apply_damage(20.0)
	assert_true(player.eat("berries"), "eats when hurt")
	assert_eq(GameState.count_item("berries"), 1, "one consumed")
	assert_almost(float(player.health.hp), 80.0 + float(ItemDB.item("berries")["heal"]), 0.001, "healed by item data")
	assert_false(player.eat("berries"), "eating is rate limited")
	player.set("_eat_lock", 0.0)
	player.health.reset()
	GameState.give_item("hearty_stew", 1)
	assert_true(player.eat("hearty_stew"), "buff food is allowed at full health")
	assert_almost(GameState.buff_mult("stamina_regen"), 1.6, 0.001, "buff applied from item data")


func test_lantern_contract() -> void:
	player.set_lantern(true)
	assert_true(player.is_light_active(), "light active")
	assert_true(bool(GameState.player["lantern_on"]), "state synced")
	var light: OmniLight3D = player.avatar.get_lantern_light()
	await wait_frames(2)
	assert_true(light.visible and light.shadow_enabled, "shadowed lantern light visible")
	assert_true(light.omni_range >= 6.5, "lantern range")
	player.set_lantern(false)
	await wait_frames(1)
	assert_false(light.visible, "light hidden when lowered")


func test_walks_camera_relative_and_decelerates() -> void:
	_allow_input()
	player.rig.snap(0.0)
	Input.action_press("move_forward")
	await wait_physics(40)
	var v: Vector3 = player.velocity
	assert_almost(Vector2(v.x, v.z).length(), Logic.WALK_SPEED, 0.05, "walk speed")
	assert_true(v.z < -4.0, "moves toward camera forward (-Z)")
	assert_true(player.is_moving())
	Input.action_press("sprint")
	await wait_physics(40)
	assert_true(player.is_sprinting(), "sprinting")
	assert_true(float(player.stamina) < 90.0, "sprint drains stamina")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await wait_physics(20)
	assert_true(Vector2(player.velocity.x, player.velocity.z).length() < 0.05, "stops")
	player.rig.snap(PI * 0.5)
	Input.action_press("move_forward")
	await wait_physics(30)
	assert_true(player.velocity.x < -4.0, "forward follows the camera yaw")
	assert_true(player.get_facing().dot(Vector3(-1, 0, 0)) > 0.95, "turns to face the movement")


func test_input_ignored_when_disabled() -> void:
	_allow_input()
	player.set_input_enabled(false)
	Input.action_press("move_forward")
	await wait_physics(20)
	assert_true(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "no movement with input disabled")
	player.set_input_enabled(true)
	Game.mode = "title"
	await wait_physics(10)
	assert_true(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "no movement when gameplay input is not allowed")


func test_fall_recovery_returns_to_safe_ground() -> void:
	await wait_physics(40)
	var safe: Vector3 = player.global_position
	player.global_position = Vector3(0, -45, 0)
	await wait_physics(4)
	assert_true(player.global_position.distance_to(safe) < 1.0, "recovered to the last safe spot (%s)" % str(player.global_position))


func test_one_harvest_hit_per_swing_with_owned_tool() -> void:
	_allow_input()
	GameState.give_item("stone_axe", 1)
	var tree: Node3D = DummyScript.new()
	tree.setup({"mode": "harvest"})
	add_child(tree)
	tree.global_position = Vector3(0, 0, -1.3)
	await wait_physics(8)
	player.probe.refresh()
	assert_eq(player.get_focus_target(), tree, "probe focuses the harvestable in front")
	assert_eq(String(player.get_prompt().get("text", "")), "Chop Test Tree")
	player.call("_on_attack_pressed")
	player.call("_on_attack_pressed")          # too early to buffer (double-click)
	await wait_physics(45)
	assert_eq(tree.get("hits"), ["stone_axe"], "exactly one harvest_hit with the owned tool")


func test_missing_tool_gives_no_harvest() -> void:
	_allow_input()
	var tree: Node3D = DummyScript.new()
	tree.setup({"mode": "harvest"})
	add_child(tree)
	tree.global_position = Vector3(0, 0, -1.3)
	await wait_physics(8)
	player.probe.refresh()
	var pr: Dictionary = player.get_prompt()
	assert_eq(String(pr.get("text", "")), "Needs an Axe")
	assert_false(bool(pr.get("enabled", true)))
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_eq((tree.get("hits") as Array).size(), 0, "no harvest without the tool")


# --- Camera rig ------------------------------------------------------------------------------------------------

func test_camera_clamps_and_zoom() -> void:
	var rig = player.rig
	rig.rotate_by(Vector2(0, -100000))
	var a: float = rig.pitch
	rig.rotate_by(Vector2(0, 100000))
	var b: float = rig.pitch
	assert_almost(maxf(a, b), rig.PITCH_MAX, 0.0001, "pitch max")
	assert_almost(minf(a, b), rig.PITCH_MIN, 0.0001, "pitch min")
	rig.zoom_by(100.0)
	assert_almost(float(rig.zoom_target), 8.0, 0.0001, "zoom max")
	rig.zoom_by(-100.0)
	assert_almost(float(rig.zoom_target), 2.5, 0.0001, "zoom min")


func test_camera_invert_and_sensitivity_live() -> void:
	var rig = player.rig
	Settings.set_value("invert_y", false)
	Settings.set_value("mouse_sensitivity", 1.0)
	rig.pitch = 0.0
	rig.rotate_by(Vector2(0, -10))              # mouse up
	var up_normal: float = rig.pitch
	assert_true(up_normal > 0.0, "mouse up looks up")
	Settings.set_value("invert_y", true)
	rig.pitch = 0.0
	rig.rotate_by(Vector2(0, -10))
	assert_true(float(rig.pitch) < 0.0, "inverted")
	Settings.set_value("invert_y", false)
	Settings.set_value("mouse_sensitivity", 2.0)
	rig.pitch = 0.0
	rig.rotate_by(Vector2(0, -10))
	assert_almost(float(rig.pitch), up_normal * 2.0, 0.0001, "sensitivity applied live")


func test_camera_fov_distance_and_shake_comfort() -> void:
	var rig = player.rig
	Settings.set_value("fov", 80.0)
	Settings.set_value("camera_distance", 6.5)
	await wait_frames(30)
	assert_almost(rig.get_camera().fov, 80.0, 0.5, "fov from settings")
	assert_almost(float(rig.zoom_target), 6.5, 0.001, "distance from settings")
	Settings.set_value("reduce_shake", true)
	Events.camera_shake.emit(0.5, 0.5)
	assert_almost(float(rig.shake_amount()), 0.0, 0.0001, "reduce_shake scales shake to zero")
	Settings.set_value("reduce_shake", false)
	Events.camera_shake.emit(5.0, 0.5)
	assert_almost(float(rig.shake_amount()), rig.MAX_SHAKE, 0.0001, "shake is clamped small")
	await wait_seconds(0.7)
	assert_true(float(rig.shake_amount()) < 0.05, "shake decays")


func test_emotes_play_and_stop() -> void:
	player.play_emote("sleep")
	await wait_frames(2)
	assert_eq(player.avatar.current_action(), "sleep", "sleep loops")
	player.play_emote("stop")
	assert_eq(player.avatar.current_action(), "", "stop ends the emote")
	player.play_emote("wave")
	assert_eq(player.avatar.current_action(), "wave")
	player.play_emote("not_an_emote")
	assert_eq(player.avatar.current_action(), "wave", "unknown emotes are ignored")
	_allow_input()
	player.play_emote("sleep")
	Input.action_press("move_forward")
	await wait_physics(3)
	assert_eq(player.avatar.current_action(), "", "moving wakes her up")


# --- Reviewer additions ---------------------------------------------------------------------------------------

## Away from the origin: other suites may leave world items around (0, 0, 0) in the shared test scene.
const SPOT := Vector3(20, 0, 20)


## Minimal duck-typed harvestable/interactable on the interact layer only (never blocks line of sight).
class FakeNode extends Node3D:
	var info: Dictionary = {"tool": "axe", "name": "Oak Tree"}
	var interaction: Dictionary = {}
	var hits: Array = []
	var interacts: int = 0

	func _ready() -> void:
		var body := StaticBody3D.new()
		body.collision_layer = 16
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.4
		cyl.height = 1.6
		cs.shape = cyl
		cs.position = Vector3(0, 0.8, 0)
		body.add_child(cs)
		add_child(body)

	func get_harvest_info() -> Dictionary:
		return info

	func get_interaction(_p: Node = null) -> Dictionary:
		return interaction

	func interact(_p: Node = null) -> void:
		interacts += 1

	func harvest_hit(_p: Node, tool_item_id: String) -> void:
		hits.append(tool_item_id)


class FakeArea extends Node:
	func surface_at(_pos: Vector3) -> String:
		return "water"


func _fake(pos: Vector3, harvest: Dictionary, interaction: Dictionary) -> Node3D:
	if player.global_position.distance_to(SPOT) > 1.0:
		player.teleport(Transform3D(Basis.IDENTITY, SPOT + Vector3(0, 0.05, 0)))
	var n := FakeNode.new()
	n.info = harvest
	n.interaction = interaction
	add_child(n)
	n.global_position = pos
	return n


func test_stamina_assignment_sticks() -> void:
	# The bed refills stamina with player.set("stamina", max): it must not be overwritten next tick.
	player.stamina = 12.0
	assert_almost(float(GameState.player["stamina"]), 12.0, 0.001, "state synced on assignment")
	await wait_physics(3)
	assert_true(float(player.stamina) >= 12.0 and float(player.stamina) < 14.0, "keeps the assigned value (+ a little regen): %.2f" % float(player.stamina))
	player.get("_stamina").exhausted = true
	player.set("stamina", 100.0)
	await wait_physics(3)
	assert_almost(float(player.stamina), 100.0, 0.001, "a full refill sticks")
	assert_almost(float(GameState.player["stamina"]), 100.0, 0.001)
	assert_true(player.get("_stamina").can_sprint(), "a refill ends exhaustion")
	player.stamina = 500.0
	assert_almost(float(player.stamina), 100.0, 0.001, "clamped to the maximum")


func test_depleted_harvestable_has_no_prompt() -> void:
	_allow_input()
	GameState.give_item("stone_axe", 1)
	var stump := _fake(SPOT + Vector3(0, 0, -1.3), {"tool": "axe", "name": "Oak Tree", "depleted": true}, {})
	await wait_physics(4)
	player.probe.refresh()
	assert_eq(player.get_prompt(), {}, "a felled tree's stump shows no 'Chop' prompt")
	assert_null(player.get_focus_target(), "and is not focused")
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_eq((stump.get("hits") as Array).size(), 0, "no harvest_hit on a depleted node")
	var ProbeScript: Script = load("res://src/player/interaction_probe.gd")
	assert_true(ProbeScript.is_depleted_info({"depleted": 1}))
	assert_false(ProbeScript.is_depleted_info({"depleted": "no"}), "odd values never error")


func test_interact_on_tool_harvestable_swings_once() -> void:
	_allow_input()
	GameState.give_item("stone_axe", 1)
	var tree := _fake(SPOT + Vector3(0, 0, -1.3), {"tool": "axe", "name": "Oak Tree"}, {"text": "Chop Oak Tree", "enabled": true})
	await wait_physics(4)
	player.probe.refresh()
	var pr: Dictionary = player.get_prompt()
	assert_eq(String(pr.get("action", "")), "attack", "tool harvestables prompt the attack action")
	assert_eq(String(pr.get("text", "")), "Chop Oak Tree")
	player.call("_interact")
	player.call("_interact")                # mashing E inside one swing: no extra hit
	await wait_physics(45)
	assert_eq(tree.get("hits"), ["stone_axe"], "E swings the tool and hits exactly once")
	assert_eq(int(tree.get("interacts")), 0, "the node's instant interact() is not used")


func test_enemy_in_front_takes_priority_over_gathering() -> void:
	_allow_input()
	GameState.give_item("stone_axe", 1)
	var tree := _fake(SPOT + Vector3(0, 0, -1.3), {"tool": "axe", "name": "Oak Tree"}, {})
	var foe: Node3D = DummyScript.new()
	foe.setup({"mode": "enemy"})
	add_child(foe)
	foe.global_position = SPOT + Vector3(0.7, 0, -1.2)
	await wait_physics(4)
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_eq((tree.get("hits") as Array).size(), 0, "no gathering while an enemy is right there")
	var dmg := float(ItemDB.item(GameState.best_weapon())["damage"])
	assert_almost(float(foe.get("health").hp), 30.0 - dmg, 0.01, "the swing hit the enemy once")
	foe.global_position = SPOT + Vector3(0, 3.5, -1.2)   # far above (e.g. on the ceiling): gathering is back
	await wait_physics(4)
	player.call("_on_attack_pressed")
	await wait_physics(45)
	assert_eq(tree.get("hits"), ["stone_axe"], "enemies out of reach do not block harvesting")


func test_footstep_surface_refined_by_the_area() -> void:
	await wait_physics(2)
	assert_eq(player.surface_name(), "grass", "default outside the Below")
	var saved_area: Node = Game.area
	var saved_id: String = Game.area_id
	var fa := FakeArea.new()
	add_child(fa)
	Game.area = fa
	Game.area_id = "surface"
	var s1: String = player.surface_name()
	floor_body.set_meta("surface", "wood")
	var s2: String = player.surface_name()
	floor_body.set_meta("surface", "grass")
	var s3: String = player.surface_name()
	Game.area_id = "below"
	floor_body.remove_meta("surface")
	var s4: String = player.surface_name()
	Game.area = saved_area
	Game.area_id = saved_id
	assert_eq(s1, "water", "terrain without meta asks the area (stream water)")
	assert_eq(s2, "wood", "explicit collider meta wins")
	assert_eq(s3, "water", "generic 'grass' terrain is refined by the area")
	assert_eq(s4, "stone", "the Below defaults to stone")


func test_companion_command_result() -> void:
	assert_false(bool(player.call("_command_ok", {"ok": false, "text": "debounced"})), "refused -> no toast")
	assert_true(bool(player.call("_command_ok", {"ok": true})))
	assert_true(bool(player.call("_command_ok", null)), "void implementations count as ok")


func test_camera_shoulder_never_slips_behind_a_right_wall() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 4.0, 14.0)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = SPOT + Vector3(0.33 + 0.2, 2.0, 0.0)    # face at x = 0.33 (player radius 0.32)
	player.teleport(Transform3D(Basis.IDENTITY, SPOT + Vector3(0, 0.05, 0)))   # faces -Z: the wall is on her right
	await wait_seconds(0.8)
	var eye: Vector3 = player.get_camera().get_camera_transform().origin
	assert_true(eye.x - SPOT.x < 0.33 - 0.05, "camera eye stays on Krystal's side of the wall (x %.3f)" % (eye.x - SPOT.x))
	wall.queue_free()
	await wait_seconds(1.5)
	eye = player.get_camera().get_camera_transform().origin
	var lateral: float = eye.x - player.global_position.x
	assert_true(lateral > 0.25, "shoulder offset eases back out in the open (%.3f)" % lateral)


func test_camera_starts_at_full_distance_after_a_teleport() -> void:
	# Spawns / respawns / recoveries snap the rig: the first frames must not start inside Krystal's head
	# (stale SpringArm3D hit length) and then slowly zoom out.
	var rig = player.rig
	player.teleport(Transform3D(Basis.IDENTITY, SPOT + Vector3(0, 0.05, 0)))
	await wait_frames(1)
	assert_true(float(rig.arm_length()) > float(rig.zoom_target) - 0.3, "arm %.2f right after the snap" % float(rig.arm_length()))
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 6.0, 0.4)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = SPOT + Vector3(0, 2.0, 2.2)          # right behind her (the camera side)
	await wait_physics(2)
	player.teleport(Transform3D(Basis.IDENTITY, SPOT + Vector3(0, 0.05, 0)))
	await wait_frames(1)
	var cam_z: float = player.get_camera().global_position.z - SPOT.z
	assert_true(cam_z < 2.0 - 0.05, "a wall behind the spawn: the camera starts in front of it (z %.2f)" % cam_z)
	wall.queue_free()
