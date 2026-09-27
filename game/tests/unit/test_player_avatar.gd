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
	_step(20)
	assert_almost((eyes[0] as Node3D).scale.y, 1.0, 0.01, "eyes open again")
