extends "res://tests/test_case.gd"
## Camera clearance (2.0.3): a companion the gameplay camera ends up inside - 2.0.2 QA, Sunken Bellhouse service
## stair: Mochi walked Krystal's trail down the narrow stair right through the camera and its cap filled the whole
## frame (native_202_visible/s4/shots/005_service_gate_open.png) - hides its body until the camera is clear again.
## The rule (companion_logic.gd camera_hides) and the node glue (companion.gd update_camera_clearance / _process):
## any creature, hysteresis, only Krystal's own follow camera while it renders, and nothing but the visual changes.

const CompanionScript := preload("res://src/companions/companion.gd")
const Logic := preload("res://src/companions/companion_logic.gd")

## g2 telemetry of that run at t = 617.2 s: the follow camera and Mochi's feet 0.3 m from it.
const BELLHOUSE_CAM := Vector3(72.27, 2.40, -80.04)
const BELLHOUSE_MOCHI := Vector3(71.98, 2.19, -80.05)

var nodes: Array = []
var player: CharacterBody3D
var cam: Camera3D
var _floor: StaticBody3D
var _saved_area_id := ""


## Stand-in Krystal with a follow camera (Player.get_camera() returns the rig's Camera3D).
class CamPlayer extends CharacterBody3D:
	var camera: Camera3D = null

	func _ready() -> void:
		add_to_group("player")
		collision_layer = 2
		collision_mask = 1 | 32

	func get_camera() -> Camera3D:
		return camera

	func is_sprinting() -> bool:
		return false

	func get_facing() -> Vector3:
		return Vector3(0, 0, -1)


func before_each() -> void:
	fresh_state()
	_saved_area_id = Game.area_id
	Game.area_id = ""
	_floor = StaticBody3D.new()
	_floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	_floor.add_child(cs)
	add_child(_floor)
	player = CamPlayer.new()
	add_child(player)
	player.global_position = Vector3(0, 0.05, 8)
	cam = Camera3D.new()
	cam.name = "FollowCam"
	add_child(cam)
	cam.global_position = Vector3(0, 2.5, 13)
	player.set("camera", cam)
	Game.player = player
	await wait_physics(2)


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	Game.player = null
	Game.companion_nodes = {}
	Game.area_id = _saved_area_id
	for n in [cam, player, _floor]:
		if is_instance_valid(n):
			n.queue_free()
	await wait_frames(2)


## A companion that stays put: told to wait on the spot it stands on.
func _make(id: String, pos: Vector3) -> Node3D:
	var c: Node3D = CompanionScript.new()
	c.setup({"id": id, "mode": "wait", "home": Vector3(0, 0.05, 20), "wild": pos, "wait": pos})
	add_child(c)
	c.global_position = pos
	nodes.append(c)
	return c


## A part of the companion's visual (companion_visual.gd: rig = every body mesh, emote_anchor = the bubble).
func _part(c: Node3D, part: String) -> Node3D:
	var v: Node3D = c.get("visual")
	return v.get(part) if part != "" else v


func _body_shown(c: Node3D) -> bool:
	return _part(c, "rig").visible and _part(c, "emote_anchor").visible


## Names of everything of `n` that is still drawn (meshes, sprites, particles visible in the tree).
func _drawn(n: Node) -> Array:
	var out: Array = []
	for ch in n.get_children():
		if ch is GeometryInstance3D and (ch as GeometryInstance3D).is_visible_in_tree():
			out.append(String(ch.name))
		out.append_array(_drawn(ch))
	return out


# --- The rule -----------------------------------------------------------------------------------------------------

func test_bellhouse_pose_hides() -> void:
	assert_true(Logic.camera_body_distance(BELLHOUSE_CAM, BELLHOUSE_MOCHI) < 0.4, "the camera sat inside Mochi")
	assert_true(Logic.camera_hides(BELLHOUSE_CAM, BELLHOUSE_MOCHI, false), "hidden at the 2.0.2 pose")


func test_rule_thresholds_and_hysteresis() -> void:
	var feet := Vector3(3, 1, -2)
	var mid := feet + Vector3(0, 0.35, 0)
	assert_true(Logic.camera_hides(mid, feet, false), "camera in the middle of the body")
	assert_true(Logic.camera_hides(feet + Vector3(0, 1.2, 0), feet, false), "camera just above the cap (0.65 m)")
	assert_true(Logic.camera_hides(mid + Vector3(0.8, 0, 0), feet, false), "0.8 m beside the body")
	assert_false(Logic.camera_hides(mid + Vector3(0.9, 0, 0), feet, false), "0.9 m: not hidden yet")
	assert_true(Logic.camera_hides(mid + Vector3(0.9, 0, 0), feet, true), "0.9 m: stays hidden (hysteresis)")
	assert_false(Logic.camera_hides(mid + Vector3(1.05, 0, 0), feet, true), "1.05 m: shown again")
	# the ordinary follow view: camera ~4-5 m behind and above Krystal, the companion 2.6 m beside/behind her
	assert_false(Logic.camera_hides(Vector3(0, 2.6, 5), Vector3(1.5, 0, 2.0), false), "normal follow view untouched")
	# the camera pulled in to its 0.2 m minimum arm in a tight spot, companion 1.3 m from Krystal
	assert_false(Logic.camera_hides(Vector3(0, 1.4, 0.2), Vector3(1.3, 0, 0), false), "close but beside: shown")
	assert_true(Logic.CAM_SHOW_DIST > Logic.CAM_HIDE_DIST, "hysteresis band")


# --- The node -----------------------------------------------------------------------------------------------------

func test_hidden_at_camera_and_restored_for_every_companion() -> void:
	for id in ["mochi", "pebble", "lumi"]:
		var c := _make(id, Vector3(2, 0.05, 2))
		await wait_physics(2)
		c.update_camera_clearance(null)
		assert_true(_body_shown(c), "%s shown with no camera" % id)
		assert_true(_drawn(c).size() > 5, "%s is drawn before (%d parts)" % [id, _drawn(c).size()])
		var probe := Camera3D.new()
		add_child(probe)
		probe.global_position = c.global_position + Vector3(0.1, 0.3, 0.1)
		c.update_camera_clearance(probe)
		assert_true(c.is_camera_hidden(), "%s: camera inside it -> hidden" % id)
		assert_false(_part(c, "rig").visible, "%s body hidden" % id)
		assert_false(_part(c, "emote_anchor").visible, "%s emote bubble hidden" % id)
		assert_true(_part(c, "").visible, "%s visual root itself untouched" % id)
		assert_eq(_drawn(c), [], "%s: nothing of it is drawn while the camera is inside it" % id)
		probe.global_position = c.global_position + Vector3(0.9, 0.35, 0.0)
		c.update_camera_clearance(probe)
		assert_true(c.is_camera_hidden(), "%s: 0.9 m, still hidden (hysteresis)" % id)
		probe.global_position = c.global_position + Vector3(2.5, 1.5, 0.0)
		c.update_camera_clearance(probe)
		assert_false(c.is_camera_hidden(), "%s: camera moved away -> shown" % id)
		assert_true(_body_shown(c), "%s body and emote shown again" % id)
		c.update_camera_clearance(probe)
		assert_true(_body_shown(c), "%s stays shown" % id)
		probe.free()
		c.queue_free()
		await wait_frames(1)


func test_only_the_visual_changes() -> void:
	var c := _make("lumi", Vector3(-2, 0.05, 3))
	await wait_physics(3)
	var light: OmniLight3D = _part(c, "light")
	var light_on := light.visible
	var state := String(c.get_state())
	var col: CollisionShape3D = c.get("_collision")
	var area: Area3D = c.get("_interact_area")
	var probe := Camera3D.new()
	add_child(probe)
	probe.global_position = c.global_position + Vector3(0, 0.4, 0)
	c.update_camera_clearance(probe)
	assert_true(c.is_camera_hidden())
	assert_eq(light.visible, light_on, "Lumi's light keeps lighting the room (no light pop)")
	assert_false(col.disabled, "collision untouched")
	assert_eq(int(c.get("collision_layer")), 4, "companion layer untouched")
	assert_eq(area.collision_layer, 16, "still interactable")
	assert_eq(String(c.get_state()), state, "AI state untouched")
	var p: Dictionary = c.get_interaction(player)
	assert_true(p.has("text"), "interaction prompt still offered")
	probe.free()


func test_follow_camera_drives_it_every_frame() -> void:
	var c := _make("mochi", Vector3(1, 0.05, 4))
	await wait_physics(3)
	cam.make_current()
	cam.global_position = c.global_position + Vector3(0.2, 0.3, 0.2)
	await wait_frames(2)
	assert_true(c.is_camera_hidden(), "Krystal's follow camera inside Mochi hides it")
	assert_false(_part(c, "rig").visible)
	cam.global_position = c.global_position + Vector3(0, 2.0, 3.5)
	await wait_frames(2)
	assert_false(c.is_camera_hidden(), "restored as soon as the camera is clear")
	assert_true(_body_shown(c))


func test_other_cameras_never_hide_it() -> void:
	var c := _make("pebble", Vector3(-1, 0.05, 4))
	await wait_physics(3)
	cam.make_current()
	cam.global_position = c.global_position + Vector3(0, 0.4, 0)
	await wait_frames(2)
	assert_true(c.is_camera_hidden(), "hidden by the follow camera")
	# a cutscene / celebration camera takes over (the follow camera stays where it was): shown again
	var cutscene := Camera3D.new()
	add_child(cutscene)
	cutscene.global_position = c.global_position + Vector3(0.1, 0.4, 0.3)
	cutscene.make_current()
	await wait_frames(2)
	assert_false(c.is_camera_hidden(), "a close-up by another camera is never hidden")
	assert_true(_body_shown(c))
	cutscene.free()
	# no player at all (title / preview)
	Game.player = null
	player.remove_from_group("player")
	c.set("_player", null)
	await wait_frames(2)
	assert_false(c.is_camera_hidden(), "no follow camera: shown")
