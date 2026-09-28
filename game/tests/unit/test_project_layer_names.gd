extends "res://tests/test_case.gd"
## project.godot [layer_names] must match docs/ARCHITECTURE.md golden rule 11 and the code's layer constants (pass 3,
## R3-34): the camera-only blockers (src/camera/camera_block.gd) use physics layer 10 (bit value 512), which only the
## follow camera's mask includes. The editor shows these names, so a renamed / reused layer is caught here.

const CameraBlock := preload("res://src/camera/camera_block.gd")
const Rig := preload("res://src/camera/camera_rig.gd")

## Rule 11: layer number -> [name, bit value].
const LAYERS := {
	1: ["world", 1], 2: ["player", 2], 3: ["companion", 4], 4: ["enemy", 8], 5: ["interact", 16],
	6: ["structure", 32], 7: ["pickup", 64], 8: ["trigger", 128], 9: ["hitbox", 256], 10: ["camera", 512],
}


func test_layer_names_match_the_architecture_rule() -> void:
	for n in LAYERS:
		var key := "layer_names/3d_physics/layer_%d" % int(n)
		assert_eq(String(ProjectSettings.get_setting(key, "")), String(LAYERS[n][0]), "%s is named as in rule 11" % key)
		assert_eq(1 << (int(n) - 1), int(LAYERS[n][1]), "layer %d is bit value %d" % [int(n), int(LAYERS[n][1])])


func test_camera_blockers_use_the_named_camera_layer_and_only_the_camera_sees_it() -> void:
	assert_eq(CameraBlock.LAYER, int(LAYERS[10][1]), "CameraBlock.LAYER is layer 10 (512)")
	assert_eq(Rig.COLLISION_MASK, 1 | 32 | CameraBlock.LAYER, "the follow camera collides with world | structure | camera")
	var host := Node3D.new()
	add_child(host)
	var body := CameraBlock.add_box(host, Vector3(0, 2.9, 0), Vector3(1.0, 0.5, 1.0))
	assert_eq(body.collision_layer, CameraBlock.LAYER, "a blocker sits on the camera layer only")
	assert_eq(body.collision_mask, 0, "a blocker collides with nothing itself")
	host.queue_free()
