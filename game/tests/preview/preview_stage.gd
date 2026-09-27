extends Node3D
## Visual preview stage for art QA (debug builds). Builds a neutral lit stage, instantiates a node
## from --preview=<script>, orbits a camera and saves PNGs, then quits.
##   Godot --path game -- --preview=res://src/companions/mochi_visual.gd --shot-dir=C:/tmp/prev
## Options: --preview-args=<json for setup()>  --preview-dist=4  --preview-height=1.4  --preview-target-y=0.6
##          --preview-shots=4  --preview-wait=1.0  --preview-anim=<name> (calls play_anim(name))
##          --preview-light=day|night|dark   (dark = dungeon-like with a lantern light)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")


func _ready() -> void:
	var light_mode := Debug.arg("preview-light", "day")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2b2a3f") if light_mode != "day" else Color("cfe3ef")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Palette.AMBIENT_DAY if light_mode == "day" else Palette.AMBIENT_BELOW
	e.ambient_light_energy = 0.6 if light_mode == "day" else 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	if light_mode != "dark":
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-48, 35, 0)
		sun.light_color = Palette.SUN_DAY if light_mode == "day" else Palette.MOON
		sun.light_energy = 1.3 if light_mode == "day" else 0.5
		sun.shadow_enabled = true
		add_child(sun)
	else:
		var om := OmniLight3D.new()
		om.position = Vector3(1.5, 2.0, 2.0)
		om.light_color = Palette.MINE_LIGHT
		om.light_energy = 1.6
		om.omni_range = 9.0
		om.shadow_enabled = true
		add_child(om)
	var ground := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 6.0
	cm.height = 0.2
	ground.mesh = cm
	ground.position.y = -0.1
	ground.material_override = Mat.toon(Palette.GRASS if light_mode == "day" else Palette.MINE_ROCK)
	add_child(ground)
	var script: Script = load(Debug.arg("preview"))
	var node: Node = script.new()
	if node.has_method("setup") and Debug.has_arg("preview-args"):
		node.setup(JSON.parse_string(Debug.arg("preview-args")))
	add_child(node)
	if Debug.has_arg("preview-anim") and node.has_method("play_anim"):
		node.play_anim(Debug.arg("preview-anim"))
	_shoot.call_deferred()


func _shoot() -> void:
	var dir := Debug.arg("shot-dir", "user://preview")
	DirAccess.make_dir_recursive_absolute(dir)
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.make_current()
	var dist := float(Debug.arg("preview-dist", "4"))
	var h := float(Debug.arg("preview-height", "1.4"))
	var ty := float(Debug.arg("preview-target-y", "0.6"))
	var shots := int(Debug.arg("preview-shots", "4"))
	await get_tree().create_timer(float(Debug.arg("preview-wait", "1.0"))).timeout
	for i in shots:
		var ang := TAU * float(i) / float(shots) + 0.35
		cam.global_position = Vector3(sin(ang) * dist, h, cos(ang) * dist)
		cam.look_at(Vector3(0, ty, 0))
		for k in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join("preview_%02d.png" % i))
		print("Preview: saved shot ", i)
	get_tree().quit()
