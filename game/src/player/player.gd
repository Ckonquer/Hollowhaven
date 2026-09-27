extends CharacterBody3D
## PLACEHOLDER player (replaced by the Player agent). Implements the minimum contract only.

var input_enabled := true
var cam: Camera3D

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 32
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.6
	cs.shape = cap; cs.position.y = 0.8; add_child(cs)
	var mi := MeshInstance3D.new(); var cm := CapsuleMesh.new(); cm.radius = 0.35; cm.height = 1.6
	mi.mesh = cm; mi.position.y = 0.8; add_child(mi)
	cam = Camera3D.new(); cam.position = Vector3(0, 3, 6); add_child(cam); cam.rotation_degrees.x = -20; cam.current = true

func _physics_process(delta: float) -> void:
	var d := Vector3.ZERO
	if input_enabled and Game.gameplay_input_allowed():
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		d = (global_transform.basis * Vector3(v.x, 0, v.y)).normalized()
	velocity.x = d.x * 5.0; velocity.z = d.z * 5.0
	velocity.y -= 20.0 * delta if not is_on_floor() else 0.0
	move_and_slide()

func teleport(xform: Transform3D) -> void:
	global_transform = xform; velocity = Vector3.ZERO

func read_from_state() -> void: pass
func write_to_state() -> void:
	GameState.player["pos"] = [global_position.x, global_position.y, global_position.z]
func set_input_enabled(on: bool) -> void: input_enabled = on
