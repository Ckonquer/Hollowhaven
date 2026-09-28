extends PanelContainer
## Rotating 3D preview of Krystal for the "Meet Krystal" creation screen and the wardrobe panel
## (docs/ch2/maps/player_avatar.md recipe (d)). A SubViewport with its OWN World3D (never the live area:
## no light or shadow leaks either way), a transparent background, a key light + ambient fill, and a
## non-driven krystal_avatar (idle breathing and blinks) on a turntable. It spins slowly on its own; drag
## with the mouse or call turn() (the panels bind < and > keys) to look around. Renders only while visible.
##   var p := AvatarPreview.new(); p.setup({"look": look, "size": Vector2(480, 620)}); box.add_child(p)
##   p.set_look(new_look)
## The avatar's appearance API is duck-typed (the avatar module owns it): a `set_appearance(look)` method
## (or apply_appearance / apply_look) updates in place ("live"); an `appearance` property alone means the
## avatar is rebuilt ("rebuild"); with neither the Chapter One model is shown with a clear note ("legacy");
## a missing script shows a note ("none"). Optional: `driven`/`preview`/`show_armor` properties,
## `apply_armor(show, equipment)` or `set_show_armor(on)`, `play_anim("idle")`.
## krystal_avatar.gd (Wave B) has apply_look(look) (callable before add_child, so she is built once with the
## look) and apply_armor(show_armor, equipment): the preview is "live" and shows the equipped armor on demand.
## Face mode (visual QA UI-08: on the Eyes / Skin tabs the turntable often showed her back): set_face_mode(true)
## eases her round to a front three-quarter view (FACE_YAW), holds the spin there and moves the camera in on her head
## and shoulders; face_front() re-faces her after a pick. Dragging or the turn keys still work; leaving face mode
## frames her whole again and the slow spin resumes.

const Kit := preload("res://src/ui/ui_kit.gd")
const AVATAR_SCRIPT := "res://src/player/krystal_avatar.gd"
const SPIN_SPEED := 0.45                # rad/s while idle
const RESUME_SPIN_AFTER := 4.0          # seconds after a manual turn before the turntable spins again
const TURN_STEP := PI / 4.0
const DRAG_SENS := 0.012                # rad per pixel
const CAM_POS := Vector3(0.0, 0.98, 4.1)      # frames y -0.15..2.05 m (hats included) at fov 30
const CAM_TARGET := Vector3(0.0, 0.95, 0.0)
const CAM_FACE_POS := Vector3(0.0, 1.24, 2.45)  # face mode: head and shoulders
const CAM_FACE_TARGET := Vector3(0.0, 1.17, 0.0)
const FACE_YAW := 0.32                  # front three-quarter (rad; 0 = straight at the camera)
const FACE_TURN_TIME := 0.45
const FRAME_TIME := 0.35
const NOTE_LEGACY := "This preview still shows Krystal's classic look. Your choices are saved and will appear as her new outfits arrive."
const NOTE_NONE := "Krystal's preview can't be drawn here, but your choices are still saved."
## Appearance API names accepted from the avatar module (first match wins).
const LOOK_METHODS := ["set_appearance", "apply_appearance", "apply_look"]
const LOOK_PROPS := ["appearance"]

var look: Dictionary = {}
var show_armor: bool = false
var equipment: Dictionary = {}          # slot -> armor item id (GameState.equipment shape) for "show armor"
var auto_spin: bool = true
var mode: String = "none"               # live | rebuild | legacy | none (see header)
var holder: SubViewportContainer
var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var avatar: Node3D = null
var note: Label
var yaw: float = 0.0
var _idle: float = RESUME_SPIN_AFTER
var _dragging: bool = false
var _size := Vector2(480, 620)
var _look_method := ""
var _look_prop := ""
var face_mode: bool = false
var _face_t := -1.0                     # >= 0 while easing round to FACE_YAW
var _face_from := 0.0
var _frame := 0.0                       # 0 = whole figure, 1 = face framing (tweened)
var _frame_tw: Tween

static var _script_cache: Script = null
static var _script_checked: bool = false


func setup(p: Dictionary) -> void:
	var l: Variant = p.get("look", {})
	look = (l as Dictionary).duplicate(true) if l is Dictionary else {}
	var s: Variant = p.get("size", _size)
	if s is Vector2:
		_size = s
	show_armor = bool(p.get("show_armor", false))
	var eq: Variant = p.get("equipment", {})
	equipment = (eq as Dictionary).duplicate() if eq is Dictionary else {}
	auto_spin = bool(p.get("auto_spin", true))


func _ready() -> void:
	theme_type_variation = "Inset"
	custom_minimum_size = _size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	tooltip_text = "Drag to turn Krystal around"
	holder = SubViewportContainer.new()
	holder.name = "PreviewHolder"
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(holder)
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.own_world_3d = true            # never render (or light) the live area
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	holder.add_child(viewport)
	_build_stage()
	var nm := Kit.margin([18, 0, 18, 16])
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(nm)
	note = Kit.wrap_label("", "Small", maxf(_size.x - 60.0, 120.0), HORIZONTAL_ALIGNMENT_CENTER)
	note.visible = false
	nm.add_child(note)
	_spawn_avatar()


func _build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.93, 0.88)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	key.light_energy = 1.15
	key.light_color = Color(1.0, 0.96, 0.9)
	key.shadow_enabled = false
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.rotation_degrees = Vector3(-20.0, 200.0, 0.0)
	rim.light_energy = 0.35
	rim.light_color = Color(0.85, 0.88, 1.0)
	rim.shadow_enabled = false
	viewport.add_child(rim)
	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = 30.0
	camera.near = 0.05
	camera.far = 20.0
	viewport.add_child(camera)
	camera.look_at_from_position(CAM_POS, CAM_TARGET, Vector3.UP)
	camera.current = true
	pivot = Node3D.new()
	pivot.name = "Turntable"
	viewport.add_child(pivot)


## The avatar script, loaded once (null if it is missing or does not compile).
static func avatar_script() -> Script:
	if not _script_checked:
		_script_checked = true
		if ResourceLoader.exists(AVATAR_SCRIPT):
			var s: Variant = load(AVATAR_SCRIPT)
			if s is Script and (s as Script).can_instantiate():
				_script_cache = s
	return _script_cache


func _spawn_avatar() -> void:
	if avatar != null and is_instance_valid(avatar):
		pivot.remove_child(avatar)
		avatar.queue_free()
	avatar = null
	_look_method = ""
	_look_prop = ""
	var s := avatar_script()
	if s == null:
		mode = "none"
		_set_note(NOTE_NONE)
		return
	var av: Node3D = s.new()
	av.name = "PreviewKrystal"
	if "driven" in av:
		av.set("driven", false)
	if "preview" in av:
		av.set("preview", true)
	for m in LOOK_METHODS:
		if av.has_method(String(m)):
			_look_method = String(m)
			break
	for pn in LOOK_PROPS:
		if String(pn) in av:
			_look_prop = String(pn)
			break
	var pre_applied := false
	if _look_prop != "":
		av.set(_look_prop, look.duplicate(true))   # before add_child: the avatar builds once
	elif _look_method == "apply_look":
		av.call(_look_method, look.duplicate(true))   # documented as callable before add_child: built once
		pre_applied = true
	if "show_armor" in av:
		av.set("show_armor", show_armor)
	if av.has_method("apply_armor"):
		av.call("apply_armor", show_armor, equipment.duplicate())
	pivot.add_child(av)
	avatar = av
	if _look_method != "":
		mode = "live"
		if _look_prop == "" and not pre_applied:
			av.call(_look_method, look.duplicate(true))
	elif _look_prop != "":
		mode = "rebuild"
	else:
		mode = "legacy"
	if av.has_method("play_anim"):
		av.call("play_anim", "idle")
	if "lantern_owned" in av:
		av.set("lantern_owned", false)   # after play_anim (which clips the lantern on): the preview is about her look
	_set_note(NOTE_LEGACY if mode == "legacy" else "")


func _set_note(text: String) -> void:
	if note == null:
		return
	note.text = text
	note.visible = text != ""


## Shows `l` (a look dictionary, data/appearance.gd). Cheap when the avatar updates in place.
func set_look(l: Dictionary) -> void:
	if l == look:
		return   # same look (deep, order-free): nothing to rebuild
	look = l.duplicate(true)
	if not is_inside_tree():
		return
	match mode:
		"live":
			if avatar != null and is_instance_valid(avatar):
				avatar.call(_look_method, look.duplicate(true))
		"rebuild":
			_spawn_avatar()


func set_show_armor(on: bool) -> void:
	if on == show_armor:
		return
	show_armor = on
	if avatar == null or not is_instance_valid(avatar):
		return
	if avatar.has_method("apply_armor"):
		avatar.call("apply_armor", on, equipment.duplicate())
		return
	if avatar.has_method("set_show_armor"):
		avatar.call("set_show_armor", on)
		return
	if not ("show_armor" in avatar):
		return
	avatar.set("show_armor", on)
	if mode == "live":
		avatar.call(_look_method, look.duplicate(true))
	elif mode == "rebuild":
		_spawn_avatar()


## True when the preview can show the chosen look (the avatar module's appearance API is present).
func shows_looks() -> bool:
	return mode == "live" or mode == "rebuild"


## Turns Krystal by `radians` (keyboard / buttons); the idle spin pauses for a moment.
func turn(radians: float = TURN_STEP) -> void:
	_face_t = -1.0
	yaw = wrapf(yaw + radians, -PI, PI)
	_idle = 0.0
	if pivot != null:
		pivot.rotation.y = yaw


## Face-related tabs (eyes, skin, hair colour...): turn her to the front, keep her there, frame her face.
func set_face_mode(on: bool) -> void:
	if on == face_mode:
		if on:
			face_front()
		return
	face_mode = on
	if on:
		face_front()
	else:
		_idle = 0.0          # the slow spin comes back after the usual pause
	_set_frame(1.0 if on else 0.0)


## Eases her round to the front three-quarter view (and pauses the spin for RESUME_SPIN_AFTER afterwards).
func face_front() -> void:
	_face_from = yaw
	_face_t = 0.0
	_idle = 0.0


func _set_frame(to: float) -> void:
	if camera == null or not is_inside_tree():
		_frame = to
		return
	if _frame_tw != null and _frame_tw.is_valid():
		_frame_tw.kill()
	_frame_tw = create_tween()
	_frame_tw.tween_method(_apply_frame, _frame, to, FRAME_TIME).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _apply_frame(f: float) -> void:
	_frame = f
	if camera != null:
		camera.look_at_from_position(CAM_POS.lerp(CAM_FACE_POS, f), CAM_TARGET.lerp(CAM_FACE_TARGET, f), Vector3.UP)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		_idle = 0.0
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		turn((event as InputEventMouseMotion).relative.x * DRAG_SENS)
		accept_event()


func _process(delta: float) -> void:
	if pivot == null or not is_visible_in_tree():
		return
	if _dragging:
		_idle = 0.0
		_face_t = -1.0
		return
	if _face_t >= 0.0:
		_face_t = minf(_face_t + delta / FACE_TURN_TIME, 1.0)
		var k := _face_t * _face_t * (3.0 - 2.0 * _face_t)
		yaw = lerp_angle(_face_from, FACE_YAW, k)
		pivot.rotation.y = yaw
		_idle = 0.0
		if _face_t >= 1.0:
			_face_t = -1.0
		return
	if not auto_spin or face_mode:
		return
	_idle += delta
	if _idle >= RESUME_SPIN_AFTER:
		yaw = wrapf(yaw + delta * SPIN_SPEED, -PI, PI)
		pivot.rotation.y = yaw
