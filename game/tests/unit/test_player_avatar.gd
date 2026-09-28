extends "res://tests/test_case.gd"
## Krystal's avatar (src/player/krystal_avatar.gd): procedural poses that must stay physically plausible.

const AvatarScript := preload("res://src/player/krystal_avatar.gd")

var av: Node3D


func before_each() -> void:
	av = AvatarScript.new()
	av.driven = true
	add_child(av)
	await wait_frames(1)


func after_each() -> void:
	if is_instance_valid(av):
		av.queue_free()
	await wait_frames(1)


## Lowest point of the head + hair (a ~0.3 m hull around the head centre) in world space.
func _head_low() -> float:
	var hc: Node3D = av.get("_head_c")
	var xf := hc.global_transform
	var low := INF
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				var d := Vector3(x, y, z)
				if d == Vector3.ZERO:
					continue
				var p: Vector3 = xf * (Vector3(0.0, 0.03, -0.03) + d.normalized() * 0.3)
				low = minf(low, p.y)
	return low


func _step(n: int) -> void:
	for i in n:
		av.call("_process", 1.0 / 60.0)


func test_roll_keeps_the_head_out_of_the_ground() -> void:
	var worst := INF
	var worst_t := 0.0
	for i in 21:
		var t := float(i) / 20.0
		av.set("roll_t", t)
		_step(2)
		var low := _head_low()
		if low < worst:
			worst = low
			worst_t = t
	assert_true(worst > -0.06, "head/hair dips %.2f m into the ground at roll t=%.2f" % [worst, worst_t])
	av.set("roll_t", -1.0)
	_step(3)
	assert_true(_head_low() > 0.9, "standing again after the roll")


func test_idle_head_height_and_blink() -> void:
	_step(10)
	var hc: Node3D = av.get("_head_c")
	assert_true(hc.global_position.y > 1.1 and hc.global_position.y < 1.45, "chibi head centre height %.2f" % hc.global_position.y)
	var eyes: Array = av.get("_eyes")
	av.set("_blink_timer", 0.0)
	_step(4)
	assert_true((eyes[0] as Node3D).scale.y < 0.8, "blinks")
	# Deterministic: the blink just scheduled its next one at random (18% chance of a quick double blink 0.22-0.3 s
	# later, which could still be half closed at the check below). Push the next blink out of the test window.
	av.set("_blink_timer", 10.0)
	_step(20)
	assert_almost((eyes[0] as Node3D).scale.y, 1.0, 0.01, "eyes open again")


# --- Wand (Chapter Two, B3 review: casts used to show the bare-hands swing) ------------------------------------------

func _wand() -> Node3D:
	return (av.get("_tools") as Dictionary).get("wand") as Node3D


func test_wand_model_is_built_only_when_held_and_follows_swings_and_actions() -> void:
	assert_null(_wand(), "no wand model until one is held (legacy meshes untouched)")
	assert_null(av.find_child("Wand", true, false))
	var draws := int(av.call("draw_call_estimate"))
	av.call("set_held_tool", "wand")
	var w := _wand()
	assert_not_null(w, "built on first use")
	assert_true(w.visible, "shown in the right hand")
	assert_true(int(av.call("draw_call_estimate")) > draws, "the wand is drawn")
	assert_true(int(av.call("draw_call_estimate")) <= draws + 6, "a small model (%d extra draws)" % (int(av.call("draw_call_estimate")) - draws))
	var stack: Array = [w]
	var meshes := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		assert_false(n is CollisionObject3D or n is CollisionShape3D or n is Light3D, "purely visual: no collision, no light")
		if n is MeshInstance3D:
			meshes += 1
			assert_eq((n as MeshInstance3D).layers, AvatarScript.AVATAR_LAYER, "on Krystal's render layer")
	assert_true(meshes >= 2 and meshes <= 6, "baked into a few meshes (%d)" % meshes)
	# a tool swing shows its own tool, then hands the wand back
	var axe: Node3D = (av.get("_tools") as Dictionary)["axe"]
	av.call("show_tool", "axe", 0.2)
	assert_true(axe.visible and not w.visible, "the axe replaces it for the swing")
	_step(20)
	assert_true(w.visible and not axe.visible, "the wand comes back after the swing")
	# eating needs the hand: the wand is put away until the bite is over
	av.call("play_action", "eat")
	_step(2)
	assert_false(w.visible, "put away while eating")
	_step(80)
	assert_true(w.visible, "back in hand after eating")
	# nothing held: hidden, the draw calls are the legacy ones again, and building twice never happens
	av.call("set_held_tool", "")
	assert_false(w.visible)
	assert_eq(int(av.call("draw_call_estimate")), draws, "legacy draw calls with no wand held")
	av.call("set_held_tool", "wand")
	assert_eq(_wand(), w, "the same model is reused")
	av.call("set_held_tool", "sword")
	assert_eq(String(av.call("held_tool")), "", "only wands are carried between swings")


func test_wand_cast_pose_points_the_wand_forward() -> void:
	av.call("set_held_tool", "wand")
	var tip: Node3D = _wand().get_node("Tip")
	av.set("swing_kind", "wand")
	var best_z := -INF
	var release_y := 0.0
	var max_scale := 0.0
	var wind_y := -INF
	for i in 28:
		var t := float(i) / 27.0
		av.set("swing_t", t)
		_step(1)
		var p := av.global_transform.affine_inverse() * tip.global_position
		max_scale = maxf(max_scale, tip.scale.x)
		if t > 0.15 and t < 0.25:
			wind_y = maxf(wind_y, p.y)
		if absf(t - 0.37) < 0.02:
			best_z = p.z
			release_y = p.y
	print("  wand tip: wind-up height %.2f m, release %.2f m ahead at %.2f m, seed pulse x%.2f" % [wind_y, best_z, release_y, max_scale])
	assert_true(wind_y > 1.2, "wind-up: the wand flicks up by the shoulder (tip at %.2f m)" % wind_y)
	assert_true(best_z > 0.45, "at the release the wand points ahead of her (tip %.2f m in front)" % best_z)
	assert_true(release_y > 0.7 and release_y < 1.5, "about chest height (%.2f m)" % release_y)
	assert_true(max_scale > 1.4, "the seed swells as the spark leaves (%.2f)" % max_scale)
	# the cast is not the bare-hands swing any more (right shoulder, pose channel J_SH_R)
	av.set("swing_t", 0.36)
	_step(1)
	var wand_sh: Vector3 = (av.get("_pose") as PackedVector3Array)[AvatarScript.J_SH_R]
	av.set("swing_kind", "hands")
	_step(1)
	var hands_sh: Vector3 = (av.get("_pose") as PackedVector3Array)[AvatarScript.J_SH_R]
	assert_true(wand_sh.distance_to(hands_sh) > 0.1, "own pose (%s vs hands %s)" % [str(wand_sh), str(hands_sh)])
	av.set("swing_t", -1.0)
	_step(30)
	assert_almost(tip.scale.x, 1.0, 0.001, "the seed settles after the cast")
