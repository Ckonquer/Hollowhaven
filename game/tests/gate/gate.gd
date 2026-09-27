extends Node3D
## Toolchain gate: minimal playable scene. WASD moves the cube; logs position.

var cube: MeshInstance3D
var t := 0.0
var log_t := 0.0
var shot_path := ""
var shot_at := -1.0
var quit_at := -1.0
var log_file: FileAccess

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot_path = a.substr(7)
		elif a.begins_with("--shot-at="): shot_at = float(a.substr(10))
		elif a.begins_with("--quit-at="): quit_at = float(a.substr(10))
	log_file = FileAccess.open("user://gate_log.txt", FileAccess.WRITE)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new(); e.sky = sky
	env.environment = e; add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); sun.shadow_enabled = true; add_child(sun)
	var ground := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.45, 0.7, 0.35); ground.material_override = gm; add_child(ground)
	cube = MeshInstance3D.new(); cube.mesh = BoxMesh.new(); cube.position = Vector3(0, 0.5, 0)
	var cm := StandardMaterial3D.new(); cm.albedo_color = Color(0.95, 0.5, 0.6); cube.material_override = cm; add_child(cube)
	var cam := Camera3D.new(); cam.position = Vector3(0, 6, 10); add_child(cam); cam.look_at(Vector3.ZERO)
	var lbl := Label.new(); lbl.text = "Hollowhaven toolchain gate - WASD moves the cube"; lbl.position = Vector2(20, 20)
	lbl.add_theme_font_size_override("font_size", 28); add_child(lbl)
	_log("READY renderer=%s adapter=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])

func _log(s: String) -> void:
	print(s)
	if log_file: log_file.store_line("%.2f %s" % [t, s]); log_file.flush()

func _process(delta: float) -> void:
	t += delta
	var d := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_D): d.x += 1
	if Input.is_physical_key_pressed(KEY_A): d.x -= 1
	if Input.is_physical_key_pressed(KEY_W): d.z -= 1
	if Input.is_physical_key_pressed(KEY_S): d.z += 1
	cube.position += d * 4.0 * delta
	log_t += delta
	if log_t >= 0.5:
		log_t = 0.0
		_log("POS %.2f %.2f %.2f keyD=%s" % [cube.position.x, cube.position.y, cube.position.z, Input.is_physical_key_pressed(KEY_D)])
	if shot_path != "" and shot_at >= 0.0 and t >= shot_at:
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path); _log("SHOT saved " + shot_path); shot_at = -1.0
	if quit_at > 0.0 and t >= quit_at:
		_log("QUIT"); get_tree().quit()
