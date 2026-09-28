extends "res://tests/test_case.gd"
## Count Velour's procedural views (module C6a): the figure (src/enemies/velour_visual.gd) runs every pose without
## runtime errors, reads its tells without sound (bow tint, the Intense final tell's crown glint, drain eyes, the
## reveal halo) and calms its pulses with reduce_flashing; the floor shadows (velour/velour_fx.gd) - the drop
## shadow shrinks as he rises, the lane shadow grows along the dash lane; the true bat looks different from the
## decoys; the drain / candle stream meter; the defeat dispersal frees itself (no gore, nothing left behind).
## Headless (views are built and processed; nothing is rendered).

const Visual := preload("res://src/enemies/velour_visual.gd")
const Fx := preload("res://src/enemies/velour/velour_fx.gd")
const Tether := preload("res://src/enemies/velour/drain_tether.gd")

const STATES := ["dormant", "intro", "glide", "bow", "flourish", "final_tell", "dash", "recoil", "drain_tele", "drain",
	"drain_rest", "disperse", "hidden", "reform", "channel_fly", "channel", "channel_rest", "stagger", "transition"]

var _nodes: Array = []


func before_each() -> void:
	_nodes.clear()
	Settings.set_value("reduce_flashing", false)


func after_each() -> void:
	Settings.set_value("reduce_flashing", false)
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await wait_frames(2)


func _add(n: Node) -> Node:
	add_child(n)
	_nodes.append(n)
	return n


func test_every_pose_runs_and_the_tells_read_without_sound() -> void:
	var v: Node3D = _add(Visual.new())
	for s in STATES:
		v.call("set_state", s, 1.2)
		await wait_frames(3)
	v.call("set_state", "bow", 1.2)
	await wait_frames(4)
	assert_true(float(v.call("tint_alpha")) > 0.05, "the bow tints red (the dash tell)")
	v.call("set_state", "final_tell", 1.0)
	await wait_seconds(0.35)
	assert_true(float(v.get("crown_glint")) > 0.3, "the Intense final tell: his crown flashes")
	v.call("set_state", "flourish", 0.4)
	await wait_seconds(0.35)
	assert_true(float(v.get("crown_glint")) < 0.5, "the feint flourish has no glint (not the real tell)")
	v.call("set_state", "drain", 2.5)
	await wait_frames(2)
	assert_true(bool(v.call("eyes_hot")), "eye-slits glow while he drains")
	v.call("set_state", "reform", 3.0)
	v.call("set_revealed", true)
	await wait_frames(2)
	var halo: Node3D = v.get("_halo")
	assert_true(halo.visible, "candle-light reveal: a gold halo")
	v.call("set_state", "glide", 2.0)
	await wait_frames(2)
	assert_false(halo.visible)
	v.call("hit_flash", 0.2)
	await wait_frames(1)
	assert_true(float(v.call("tint_alpha")) > 0.05, "hit flash")
	v.call("play_anim", "reform")
	assert_almost(float(v.position.y), 1.4, 0.001, "preview pose above the stage floor")


func test_reduce_flashing_keeps_tells_steady() -> void:
	Settings.set_value("reduce_flashing", true)
	var v: Node3D = _add(Visual.new())
	v.call("set_state", "bow", 1.2)
	await wait_frames(3)
	var a: float = float(v.call("tint_alpha"))
	await wait_frames(3)
	var b: float = float(v.call("tint_alpha"))
	assert_true(b >= a - 0.0001, "no strobe: the tint only firms up (%.3f -> %.3f)" % [a, b])
	assert_true(b <= 0.35, "and stays soft")


func test_floor_shadows() -> void:
	var fx: Node3D = _add(Fx.new())
	await wait_frames(1)
	fx.call("set_drop", Vector3(1, 0, 2), 3.2, true)
	var drop: MeshInstance3D = fx.get("_drop")
	var high := drop.global_transform.basis.get_scale().x
	fx.call("set_drop", Vector3(1, 0, 2), 1.0, true)
	var low := drop.global_transform.basis.get_scale().x
	assert_true(low > high, "a broader shadow when he is low (within reach)")
	fx.call("show_lane", Vector3(0, 0, 0), Vector3(0, 0, -8), 0.0)
	var lane: Node3D = fx.get("_lane_head")
	var d0: float = lane.global_position.distance_to(Vector3.ZERO)
	fx.call("show_lane", Vector3(0, 0, 0), Vector3(0, 0, -8), 1.0)
	var d1: float = lane.global_position.distance_to(Vector3.ZERO)
	assert_true(d1 > d0 + 2.0, "his shadow stretches along the lane as the bow completes")
	assert_almost(d1, 8.0, 0.1, "reaching the end of the lane")
	fx.call("hide_all")
	assert_false(bool(fx.get("lane_visible")))
	assert_false(bool(fx.get("drop_visible")))


func test_true_bat_looks_different() -> void:
	var t: Node3D = _add(Fx.bat_node(1.7, true))
	var d: Node3D = _add(Fx.bat_node(1.0, false))
	assert_eq(String(t.name), "TrueBat")
	var nt := t.find_children("*", "MeshInstance3D", true, false).size()
	var nd := d.find_children("*", "MeshInstance3D", true, false).size()
	assert_true(nt >= nd + 8, "collar ruff, lining, gold ring and crown (%d vs %d meshes)" % [nt, nd])
	assert_true(t.scale.x > d.scale.x)
	Fx.flap(t, 0.3, 1.0)
	var wings := 0
	for c in t.get_children():
		if c.has_meta("wing"):
			wings += 1
			assert_true(absf((c as Node3D).rotation.z) > 0.1, "flap beats the wing (cached wing list, no per-frame get_children)")
	assert_eq(wings, 2)


func test_stream_meter_and_defeat_dispersal_cleanup() -> void:
	var t: Node3D = _add(Tether.new())
	await wait_frames(1)
	t.call("show_link", Vector3(0, 1, 0), Vector3(0, 2, -5), 0.0, false)
	assert_true(bool(t.call("is_showing")))
	assert_false(bool(t.get("channeling")), "the warning ribbon")
	t.call("show_link", Vector3(0, 1, 0), Vector3(0, 2, -5), 0.8, true)
	await wait_frames(2)
	var fill: MeshInstance3D = t.get("_fill")
	assert_true(fill.visible, "the channel meter fills from her end")
	t.call("hide_link")
	assert_false(t.visible)
	var fx: Node3D = Fx.disperse(self, Vector3(0, 1.5, 0), true)
	assert_not_null(fx, "the defeat burst builds")
	assert_true(fx.find_children("BorrowedMask", "", true, false).size() == 1, "the borrowed mask falls")
	await wait_seconds(2.7)
	assert_false(is_instance_valid(fx), "it frees itself: nothing is left behind")
