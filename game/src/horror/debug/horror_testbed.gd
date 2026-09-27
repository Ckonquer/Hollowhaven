extends Node3D
## QA testbed for the horror director (debug preview only; never used by the game).
##   tools/godot.sh --path game --windowed --resolution 1280x720 -- \
##     --preview=res://src/horror/debug/horror_testbed.gd --preview-light=dark \
##     --preview-args='{"scenario":"glimpse","arachnophobia":false}' --preview-wait=1.4 --preview-shots=3 --shot-dir=<abs dir>
## Scenarios: glimpse, cross, scratch, flicker, ambush, idle.
## Builds a small timbered mine corridor ending in a lit side room (far from the preview stage's
## own origin), a stand-in player with a third-person camera, director anchors and a real director,
## then forces one event so the effect can be screenshotted from the player's point of view.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Director := preload("res://src/horror/director.gd")

const ORIGIN := Vector3(120, 0, 0)
const HEIGHT := 3.4
const HALF_W := 2.0


## Minimal stand-in for the player contract the director reads.
class StandIn extends Node3D:
	var cam: Camera3D

	func get_camera() -> Camera3D:
		return cam

	func get_facing() -> Vector3:
		return -global_basis.z

	func is_sprinting() -> bool:
		return false


var scenario: String = "glimpse"
var arachnophobia: bool = false
var trigger_at: float = 0.6
var director: Node = null
var player: StandIn = null
var qa_cam: Camera3D = null
var _t: float = 0.0
var _fired: bool = false


func setup(params: Dictionary) -> void:
	scenario = String(params.get("scenario", scenario))
	arachnophobia = bool(params.get("arachnophobia", arachnophobia))
	trigger_at = float(params.get("trigger_at", trigger_at))


func _ready() -> void:
	if not Debug.is_cheat_allowed():
		queue_free()
		return
	position = ORIGIN
	Settings.set_value("arachnophobia", arachnophobia)      # session only; never saved here
	_build_corridor()
	_build_player()
	_build_anchors()
	director = Director.new()
	director.setup({"area": self, "seed": 1})
	add_child(director)
	director.enabled = false                                # events are forced by the scenario
	_setup_camera()


func _process(delta: float) -> void:
	_t += delta
	if qa_cam != null:
		qa_cam.make_current()
	if not _fired and _t >= trigger_at:
		_fired = true
		_trigger()


func _trigger() -> void:
	var d: Dictionary = {}
	match scenario:
		"glimpse":
			d = director.debug_force("far_glimpse")
		"cross":
			d = director.debug_force("stalker_pass")
		"scratch":
			d = director.debug_force("scratching_above")
		"flicker":
			d = director.debug_force("lantern_flicker")
		"ambush":
			d = director.debug_force("gloomling_ambush")
		_:
			pass
	print("Testbed[%s]: %s" % [scenario, str(d.get("event_id", "-"))])
	for line in director.debug_log:
		print("  ", line)


# --- Construction --------------------------------------------------------------------------------

func _build_corridor() -> void:
	var rock := Mat.toon(Palette.MINE_ROCK, {"noise": 0.12, "noise_scale": 0.8})
	var rock_dark := Mat.toon(Palette.MINE_ROCK_DARK, {"noise": 0.1})
	var timber := Mat.outlined(Mat.toon(Palette.MINE_TIMBER), 0.015)
	# Corridor z +16 .. -18, then a wider room -18 .. -27.
	_solid(Vector3(0, -0.25, -5.5), Vector3(14, 0.5, 45), rock_dark)                 # floor
	_solid(Vector3(0, HEIGHT + 0.25, -1), Vector3(HALF_W * 2 + 1, 0.5, 34), rock)     # corridor ceiling
	_solid(Vector3(-HALF_W - 0.5, HEIGHT * 0.5, -1), Vector3(1, HEIGHT, 34), rock)    # left wall
	_solid(Vector3(HALF_W + 0.5, HEIGHT * 0.5, -1), Vector3(1, HEIGHT, 34), rock)     # right wall
	# Wall with a doorway into the far room.
	_solid(Vector3(-2.6, HEIGHT * 0.5, -18.2), Vector3(4.4, HEIGHT, 0.5), rock)
	_solid(Vector3(2.6, HEIGHT * 0.5, -18.2), Vector3(4.4, HEIGHT, 0.5), rock)
	_solid(Vector3(0, 2.4 + (HEIGHT - 2.4) * 0.5, -18.2), Vector3(0.9, HEIGHT - 2.4, 0.5), rock)
	# Far room
	_solid(Vector3(0, HEIGHT + 0.25, -22.8), Vector3(10, 0.5, 9), rock)
	_solid(Vector3(-5, HEIGHT * 0.5, -22.8), Vector3(0.5, HEIGHT, 9), rock)
	_solid(Vector3(5, HEIGHT * 0.5, -22.8), Vector3(0.5, HEIGHT, 9), rock)
	_solid(Vector3(0, HEIGHT * 0.5, -27.3), Vector3(10, HEIGHT, 0.5), rock)
	# Timber frames every 4 m.
	var z := 14.0
	while z > -17.0:
		Kit.add(self, Kit.box(Vector3(0.28, HEIGHT, 0.28), timber), Vector3(-HALF_W + 0.14, HEIGHT * 0.5, z))
		Kit.add(self, Kit.box(Vector3(0.28, HEIGHT, 0.28), timber), Vector3(HALF_W - 0.14, HEIGHT * 0.5, z))
		Kit.add(self, Kit.box(Vector3(HALF_W * 2, 0.3, 0.32), timber), Vector3(0, HEIGHT - 0.15, z))
		z -= 4.0
	# Lamps: a lantern pool near the player, one mid-corridor, a warm lamp in the far room (backlight).
	_lamp(Vector3(1.6, 2.4, 1.0), 1.4, 7.0)
	_lamp(Vector3(-1.6, 2.4, -9.0), 1.0, 6.5)
	_lamp(Vector3(0, 2.6, -24.0), 2.2, 9.0)
	# Rails for scale.
	var rail := Mat.toon(Palette.STONE_DARK)
	for x in [-0.55, 0.55]:
		Kit.add(self, Kit.box(Vector3(0.08, 0.08, 33), rail), Vector3(x, 0.04, -1))


func _solid(pos: Vector3, size: Vector3, mat: Material) -> void:
	Kit.add(self, Kit.box(size, mat), pos)
	var sh := BoxShape3D.new()
	sh.size = size
	Kit.static_collider(self, sh, pos, 1)


func _lamp(pos: Vector3, energy: float, radius: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = Palette.MINE_LIGHT
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = true
	add_child(l)
	l.position = pos
	Kit.add(self, Kit.sphere(0.12, Mat.glow(Palette.LANTERN_GLOW, 2.5)), pos)


func _build_player() -> void:
	player = StandIn.new()
	player.name = "StandInPlayer"
	player.add_to_group("player")
	add_child(player)
	player.position = Vector3(0, 0, 2)
	var body := Kit.capsule(0.32, 1.5, Mat.outlined(Mat.toon(Palette.K_JACKET)))
	Kit.add(player, body, Vector3(0, 0.75, 0))
	Kit.add(player, Kit.sphere(0.24, Mat.outlined(Mat.toon(Palette.K_SKIN))), Vector3(0, 1.62, 0))
	var cam := Camera3D.new()
	cam.fov = 70.0
	player.add_child(cam)
	cam.position = Vector3(0.5, 2.1, 3.4)
	player.cam = cam


func _build_anchors() -> void:
	_anchor("doorway_far", "doorway", Vector3(0, 0, -19.2))
	_anchor("ceiling_near", "ceiling", Vector3(0, HEIGHT, -2.5))
	_anchor("ceiling_mid", "ceiling", Vector3(0, HEIGHT, -7.0))
	_anchor("spawn_behind", "spawn", Vector3(0.6, 0, 13.0))
	_anchor("sound_behind", "sound", Vector3(-1, 1.2, 9.0))


func _anchor(anchor_name: String, kind: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = anchor_name
	m.set_meta("zone", "mine")
	m.set_meta("kind", kind)
	m.add_to_group("director_anchor")
	add_child(m)
	m.position = pos


func _setup_camera() -> void:
	player.cam.look_at(player.global_position + Vector3(0, 1.5, -12))
	qa_cam = player.cam
	match scenario:
		"scratch":
			qa_cam = Camera3D.new()
			qa_cam.fov = 60.0
			add_child(qa_cam)
			qa_cam.position = Vector3(1.4, 1.3, 1.5)
			qa_cam.look_at(global_position + Vector3(-0.2, 2.2, -2.5))
		"cross":
			player.cam.look_at(player.global_position + Vector3(0, 3.0, -12))
		"ambush":
			qa_cam = Camera3D.new()
			qa_cam.fov = 60.0
			add_child(qa_cam)
			qa_cam.position = Vector3(1.4, 2.6, 5.0)
			qa_cam.look_at(global_position + Vector3(0.6, 0.6, 13.0))
