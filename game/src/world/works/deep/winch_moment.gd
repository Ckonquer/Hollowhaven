extends Node3D
## Authored moment "Scratching Above the Winch" (MP §14, room 9). Once per save (flag moment_hw_winch,
## set FIRST). When Krystal walks into the Threaded Winch hall:
##   1. dust sifts from the visible overhead service gantry + a caption naming the sound (anticipation);
##   2. a pale shape crosses along the gantry (PaleShape: a weaver silhouette, or with arachnophobia the
##      faceless drifting shade with veil/dust sounds and captions) - Gentle 1 pass, Standard 2 passes;
##   3. Intense only: a longer anticipation, then a clearly marked approach: the shape stops above the
##      crossing gate in plain view, then slips through ahead of her (never a lunge).
## It never attacks or damages, and never moves on while she is reading (a UI panel open, or for a few
## seconds after she reads the winch plate): the timers simply wait. Director: authored event + suppress.
## Timing per intensity: data/works_layout_deep.gd WINCH_TIMING. Tests drive check(p, dt) directly.

const Layout := preload("res://data/works_layout_deep.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const PaleShape := preload("res://src/world/below/pale_shape.gd")

const FLAG := "moment_hw_winch"
const PASS_SECONDS := 2.8
const PAUSE_SECONDS := 1.8
const APPROACH_HOLD := 2.6
const READ_HOLD := 6.0

var phase: String = "idle"          # idle | dust | pass | pause | approach | done
var t: float = 0.0
var passes_left: int = 0
var passes_done: int = 0
var approach: bool = false
var hold: float = 0.0               # "reading" hold (seconds)
var shape: Node3D = null
var fired: Array = []               # log for tests: "start", "pass", "approach", "done"
var controller: Node = null


func setup(p: Dictionary) -> void:
	controller = p.get("controller", controller)


func _ready() -> void:
	if bool(GameState.get_flag(FLAG)):
		phase = "done"


## Krystal read something in the room: hold the moment for a few seconds.
func note_read() -> void:
	hold = READ_HOLD


func _reading() -> bool:
	if hold > 0.0:
		return true
	if Game.has_method("is_ui_open") and bool(Game.is_ui_open()):
		return true
	return false


## Called ~10x per second by the controller while Krystal is in the winch rooms.
func check(p: Node3D, dt: float, in_winch: bool = true) -> void:
	if phase == "done":
		return
	if hold > 0.0:
		hold = maxf(hold - dt, 0.0)
	if phase == "idle":
		if p == null or not in_winch:
			return
		if bool(GameState.get_flag(FLAG)):
			phase = "done"
			return
		if p.global_position.x > float(Layout.WINCH["trigger_x"]) and not _reading():
			start()
		return
	if _reading():
		return
	t -= dt
	if t > 0.0:
		return
	match phase:
		"dust", "pause":
			_begin_pass()
		"pass":
			passes_done += 1
			passes_left -= 1
			if passes_left > 0:
				phase = "pause"
				t = PAUSE_SECONDS
				_dust(1)
			elif approach:
				_begin_approach()
			else:
				_finish()
		"approach":
			_finish()


func start() -> void:
	if phase != "idle":
		return
	GameState.set_flag(FLAG, true)
	var timing: Dictionary = Layout.WINCH_TIMING[Art.intensity()]
	passes_left = int(timing["passes"])
	approach = bool(timing["approach"])
	t = float(timing["anticipation"])
	phase = "dust"
	fired.append("start")
	Events.horror_event.emit("authored:hw_winch", {})
	_suppress(60.0)
	_dust(0)
	var a := Art.arachno()
	Art.sfx3d("shade_drift" if a else "dir_scratch_soft", Layout.WINCH["dust"][1], -4.0)
	Art.caption("[dust drifts down from the gantry above]" if a else "[scratching overhead - dust sifts from the gantry]")
	if Art.intensity() == 0:
		Art.say("Dust trickles from the service gantry high above. Something is moving up there.", 4.5)


func _begin_pass() -> void:
	phase = "pass"
	t = PASS_SECONDS * (1.15 if approach else 1.0)
	fired.append("pass")
	var xs: Array = Layout.WINCH["gantry_x"]
	var y := float(Layout.WINCH["gantry_y"])
	var z := float(Layout.WINCH["gantry_z"])
	var west := Vector3(float(xs[0]) + 0.3, y, z)
	var east := Vector3(float(xs[1]) - 0.3, y, z)
	var from := west if passes_done % 2 == 0 else east
	var to := east if passes_done % 2 == 0 else west
	_spawn_shape()
	if shape != null and shape.is_inside_tree():
		shape.call("cross", from, to, t)
	var a := Art.arachno()
	Art.sfx3d("shade_drift" if a else "weaver_skitter", (from + to) * 0.5, -6.0)
	Art.caption("[something pale drifts along the gantry]" if a else "[quick, light steps along the gantry]")


func _begin_approach() -> void:
	phase = "approach"
	t = APPROACH_HOLD + 0.9
	fired.append("approach")
	var y := float(Layout.WINCH["gantry_y"])
	var z := float(Layout.WINCH["gantry_z"])
	_spawn_shape()
	if shape != null and shape.is_inside_tree():
		var p := Art.player_or(controller.get("player_override") if controller != null else null)
		var facing := Vector3.LEFT
		if p != null:
			facing = p.global_position - Vector3(60.6, y, z)
		shape.call("cling", Vector3(60.6, y - 0.1, z), facing)
		var tw := shape.create_tween()
		tw.tween_interval(APPROACH_HOLD)
		tw.tween_callback(Callable(shape, "recoil").bind(Vector3(63.6, y + 0.4, z), 0.9))
	Art.caption("[it waits above the crossing gate, in plain sight... then slips through ahead of you]")


func _finish() -> void:
	phase = "done"
	fired.append("done")
	if shape != null and is_instance_valid(shape):
		shape.queue_free()
	shape = null
	_suppress(45.0)


func _spawn_shape() -> void:
	if shape != null and is_instance_valid(shape):
		shape.queue_free()
	shape = null
	if not is_inside_tree():
		return
	var s: Node3D = PaleShape.new()
	s.setup({"variant": "shade" if Art.arachno() else "spider"})
	s.name = "WinchShape"
	add_child(s)
	shape = s


func _dust(i: int) -> void:
	var pts: Array = Layout.WINCH["dust"]
	var n := pts.size()
	for k in n:
		if k % 2 == i % 2 or n <= 1:
			Art.dust(self, pts[k], 22)


func _suppress(seconds: float) -> void:
	var a: Variant = controller.get("area") if controller != null and is_instance_valid(controller) else null
	Art.director_suppress(a as Node, seconds)
