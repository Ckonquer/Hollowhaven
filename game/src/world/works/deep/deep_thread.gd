extends Node3D
## A veil of the Weaver's fresh threads strung across an opening (MP §10 room 9, §13.2). With the
## arachnophobia setting it is a drifting PALE VEIL of cloth scraps and pale roots instead (different
## name, text, visuals and sounds; swaps live). A TEMPORARY obstacle, taught in the Threaded Winch:
## * interact with the lantern down  -> cut():  cleared for regrow_seconds() (timing_assist: much longer),
##   then it creeps back - never while Krystal (or the test player) stands in the doorway;
## * interact with the lantern raised -> burn(): gone for good (persist_flag remembers it);
## * lifetime > 0: a thread thrown during a fight that expires on its own (crossing_arena.spawn_thread);
##   cutting one ends it for good (it never creeps back mid-fight);
## * line >= 0: the arena's line-brazier with that index burns it (crossing_arena.gd);
## * thick: cannot be cut or burned by Krystal (the arena's exit / the Matron's deeper route).
## Spans local X (`width`) and Y (`height`, from the floor at the node origin). Blocks with a layer-1
## StaticBody while whole. Groups: "hw_thread" + "hw_thread_web" | "hw_thread_veil" (visual variant).
##   var t = Thread.new(); t.setup({"id": "hw_thread_nook", "width": 4.0, "height": 3.0, "flag": "..."})

signal cleared(thread_id: String, how: String)      # how: cut | burn | expire | dissolve
signal regrown(thread_id: String)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")

const REGROW_SECONDS := 40.0
const REGROW_ASSIST_SECONDS := 150.0
const KEEP_CLEAR := 2.0            # never regrow while someone is this close to the veil line
const CUT_FADE_SECONDS := 1.0      # a cut fight thread (lifetime > 0) shows its stubs this long, then expires
const VEIL_COLOR := Color("e3dccb")
const VEIL_SHEER := Color(0.93, 0.88, 0.8, 0.32)
const WEB_SHEER := Color(0.91, 0.89, 0.95, 0.2)

var thread_id: String = ""
var width: float = 3.0
var height: float = 3.0
var persist_flag: String = ""      # set when burned: stays gone after reloads
var dissolve_flag: String = ""     # when this flag is set the whole trail is gone (the Weaver left)
var lifetime: float = -1.0         # > 0: expires by itself after this many seconds
var line: int = -1                 # arena line index (a line-brazier burns its line)
var thick: bool = false
var teach: bool = false            # the teaching veil (its text spells the rule out)
var state: String = "whole"        # whole | cut | burned | expired | gone
var regrow_left: float = 0.0
var life_left: float = 0.0
var player_override: Node3D = null

var _vis: Node3D
var _stubs: Node3D
var _hv: Node3D
var _body: StaticBody3D
var _area: Area3D
var _built_arachno: bool = false


func setup(p: Dictionary) -> void:
	thread_id = String(p.get("id", thread_id))
	width = float(p.get("width", width))
	height = float(p.get("height", height))
	persist_flag = String(p.get("flag", persist_flag))
	dissolve_flag = String(p.get("dissolve_flag", dissolve_flag))
	lifetime = float(p.get("lifetime", lifetime))
	line = int(p.get("line", line))
	thick = bool(p.get("thick", thick))
	teach = bool(p.get("teach", teach))


static func regrow_seconds() -> float:
	return REGROW_ASSIST_SECONDS if Art.timing_assist() else REGROW_SECONDS


func _ready() -> void:
	add_to_group("hw_thread")
	_body = StaticBody3D.new()
	_body.name = "Block"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, height, 0.35)
	cs.shape = sh
	cs.position = Vector3(0.0, height * 0.5, 0.0)
	_body.add_child(cs)
	add_child(_body)
	_area = Area3D.new()
	_area.name = "InteractArea"
	_area.collision_layer = 16
	_area.collision_mask = 0
	_area.monitoring = false
	var acs := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(width, minf(height, 2.4), 1.4)
	acs.shape = ash
	acs.position = Vector3(0.0, minf(height, 2.4) * 0.5, 0.0)
	_area.add_child(acs)
	add_child(_area)
	_build_visual()
	Events.settings_changed.connect(_on_settings_changed)
	if lifetime > 0.0:
		life_left = lifetime
	if dissolve_flag != "" and bool(GameState.get_flag(dissolve_flag)):
		_set_state("gone")
	elif persist_flag != "" and bool(GameState.get_flag(persist_flag)):
		_set_state("burned")
	else:
		_set_state("whole")


func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia" or key == "high_visibility_cues":
		_build_visual()
		_apply_visual()


# --- State ----------------------------------------------------------------------------------------

func is_blocking() -> bool:
	return state == "whole"


func is_whole() -> bool:
	return state == "whole"


## Cuts the veil (temporary). False when it isn't whole or is too thick.
func cut() -> bool:
	if state != "whole" or thick:
		return false
	# a thread thrown in a fight (lifetime) never grows back: its torn stubs just fade, then it is gone
	regrow_left = regrow_seconds() if lifetime <= 0.0 else CUT_FADE_SECONDS
	_set_state("cut")
	var a := Art.arachno()
	Art.sfx3d("dir_root_creak" if a else "dir_web_rustle", global_position + Vector3.UP * 1.4, -4.0)
	Art.caption("[the pale veil tears softly and drifts aside]" if a else "[the threads snap and drift loose]")
	cleared.emit(thread_id, "cut")
	return true


## Burns the veil away for good (the lantern, or a line-brazier). Works on cut veils too; not on thick ones
## unless `force` (the arena clearing its own barrier).
func burn(force: bool = false) -> bool:
	if state == "burned" or state == "gone" or state == "expired":
		return false
	if thick and not force:
		return false
	if persist_flag != "":
		GameState.set_flag(persist_flag, true)
	_set_state("burned")
	var a := Art.arachno()
	Art.sfx3d("brazier_light", global_position + Vector3.UP * 1.4, -9.0)
	Art.caption("[the veil curls up in a warm flare and is gone]" if a else "[the threads crackle and burn away]")
	cleared.emit(thread_id, "burn")
	return true


## The whole trail is gone (the Weaver left the Works): no sound, no caption.
func dissolve() -> void:
	if state == "gone":
		return
	_set_state("gone")
	cleared.emit(thread_id, "dissolve")


## A cut veil grows back now (tests / scripted); true if it did.
func regrow() -> bool:
	if state != "cut":
		return false
	_set_state("whole")
	var a := Art.arachno()
	Art.caption("[the pale veil drifts back across the doorway]" if a else "[threads creep back across the doorway]")
	regrown.emit(thread_id)
	return true


## Advances regrowth / expiry by dt seconds (called from _process; tests call it directly).
func tick(dt: float) -> void:
	if state == "cut":
		regrow_left -= dt
		if regrow_left <= 0.0:
			if lifetime > 0.0:
				_set_state("expired")
				cleared.emit(thread_id, "expire")
			elif someone_in_doorway():
				regrow_left = 0.0
			else:
				regrow()
	elif state == "whole" and lifetime > 0.0:
		life_left -= dt
		if life_left <= 0.0:
			_set_state("expired")
			cleared.emit(thread_id, "expire")


func _process(delta: float) -> void:
	tick(delta)


## True when the player stands within KEEP_CLEAR of the veil line (so it never closes on her).
func someone_in_doorway() -> bool:
	var p := Art.player_or(player_override)
	if p == null or not is_inside_tree():
		return false
	var local := to_local(p.global_position)
	var half := width * 0.5
	var dx := maxf(absf(local.x) - half, 0.0)
	return Vector2(dx, local.z).length() < KEEP_CLEAR and local.y > -1.0 and local.y < height + 1.0


func _set_state(s: String) -> void:
	state = s
	var blocking := s == "whole"
	if _body != null:
		Art.set_collision(_body, blocking)
	set_process(s == "cut" or (s == "whole" and lifetime > 0.0))
	if blocking:
		add_to_group("interactable")
	elif is_in_group("interactable"):
		remove_from_group("interactable")
	_apply_visual()


func _apply_visual() -> void:
	if _vis != null:
		_vis.visible = state == "whole"
	if _stubs != null:
		_stubs.visible = state == "cut"
	if _hv != null:
		_hv.visible = state == "whole" and Art.high_visibility() and not thick


# --- Interaction contract ---------------------------------------------------------------------------

func get_interaction(player: Node = null) -> Dictionary:
	if state != "whole":
		return {}
	var a := Art.arachno()
	if thick:
		return {"text": "A heavy pale veil, rooted deep. It will not part" if a else "Thick threads, anchored deep. They will not part", "enabled": false}
	var p: Node = player if player != null else Art.player_or(player_override)
	if Art.lantern_raised(p):
		return {"text": "Burn the veil with your lantern" if a else "Burn the threads with your lantern", "enabled": true}
	if teach:
		return {"text": "Part the pale veil (it drifts back - burn it with your lantern raised)" if a else "Cut the threads (they grow back - raise your lantern to burn them)", "enabled": true}
	return {"text": "Part the pale veil" if a else "Cut the threads", "enabled": true}


func interact(player: Node = null) -> void:
	if state != "whole" or thick:
		return
	var p: Node = player if player != null else Art.player_or(player_override)
	if Art.lantern_raised(p):
		burn()
	else:
		cut()


func display_name() -> String:
	return "pale veil" if Art.arachno() else "Weaver threads"


# --- Visuals ------------------------------------------------------------------------------------------

func _build_visual() -> void:
	for n in [_vis, _stubs, _hv]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
			remove_child(n)
	_vis = Node3D.new()
	_vis.name = "Veil"
	add_child(_vis)
	_stubs = Node3D.new()
	_stubs.name = "Stubs"
	add_child(_stubs)
	_built_arachno = Art.arachno()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(thread_id) if thread_id != "" else 7
	if _built_arachno:
		_build_veil(rng)
		_vis.add_to_group("hw_thread_veil")
	else:
		_build_web(rng)
		_vis.add_to_group("hw_thread_web")
	_hv = Art.bold_frame(self, width + 0.2, height + 0.1)
	_apply_visual()


func _strand_mat() -> Material:
	return Mat.toon(Palette.SILK_WEB, {"rim": 0.7, "emission": Palette.SILK_WEB, "emission_energy": 0.3, "noise": 0.0})


func _line(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.02:
		return
	var mi := Kit.cylinder(radius, radius, 1.0, mat, 5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var up := d / length
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up).normalized()
	mi.transform = Transform3D(Basis(side, up * length, fwd), (a + b) * 0.5)


func _build_web(rng: RandomNumberGenerator) -> void:
	var mat := _strand_mat()
	var hw := width * 0.5
	var r := 0.016 if not thick else 0.03
	var count := 7 if not thick else 13
	for i in count:
		var a := Vector3(rng.randf_range(-hw, hw), height, rng.randf_range(-0.08, 0.08))
		var b := Vector3(rng.randf_range(-hw, hw), rng.randf_range(0.0, height * 0.3), rng.randf_range(-0.08, 0.08))
		_line(_vis, a, b, r, mat)
	for i in (4 if not thick else 8):
		var y := rng.randf_range(0.5, height - 0.3)
		_line(_vis, Vector3(-hw, y, 0.0), Vector3(hw, y + rng.randf_range(-0.6, 0.6), 0.0), r, mat)
	var sheet := Kit.box(Vector3(width * 0.96, height * 0.94, 0.02), Mat.transparent(WEB_SHEER if not thick else Color(WEB_SHEER, 0.42), true))
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(_vis, sheet, Vector3(0.0, height * 0.5, 0.0))
	for sx in [-1.0, 1.0]:
		Kit.add(_vis, Kit.sphere(0.07, mat, 6, 8), Vector3(sx * hw, height - 0.1, 0.0))
		Kit.add(_stubs, Kit.cylinder(0.014, 0.014, 0.6, mat, 5), Vector3(sx * (hw - 0.05), height - 0.3, 0.0), Vector3(0, 0, sx * 12.0))
		Kit.add(_stubs, Kit.cylinder(0.014, 0.014, 0.4, mat, 5), Vector3(sx * (hw - 0.05), 0.25, 0.0), Vector3(0, 0, -sx * 10.0))


func _build_veil(rng: RandomNumberGenerator) -> void:
	var cloth := Mat.transparent(VEIL_SHEER if not thick else Color(VEIL_SHEER, 0.55), true)
	var root := Mat.outlined(Mat.toon(Palette.ROOTS.lightened(0.35), {"rim": 0.4}), 0.012)
	var bulb := Mat.glow(Color("d9f2c4"), 0.8)
	var hw := width * 0.5
	var panels := 3 if not thick else 5
	for i in panels:
		var x := lerpf(-hw * 0.66, hw * 0.66, float(i) / maxf(float(panels - 1), 1.0))
		var h := height * rng.randf_range(0.78, 0.98)
		var p := Kit.box(Vector3(width / float(panels) * 1.25, h, 0.02), cloth)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.add(_vis, p, Vector3(x, height - h * 0.5, rng.randf_range(-0.06, 0.06)), Vector3(0, rng.randf_range(-8.0, 8.0), rng.randf_range(-3.0, 3.0)))
	Kit.add(_vis, Kit.cylinder(0.035, 0.035, width, root, 6), Vector3(0.0, height - 0.05, 0.0), Vector3(0, 0, 90))
	for i in (4 if not thick else 7):
		var x := rng.randf_range(-hw * 0.9, hw * 0.9)
		var length := rng.randf_range(height * 0.4, height * 0.85)
		_line(_vis, Vector3(x, height, 0.05), Vector3(x + rng.randf_range(-0.2, 0.2), height - length, 0.05), 0.03, root)
		Kit.add(_vis, Kit.sphere(0.05, bulb, 5, 6), Vector3(x, height - length, 0.05))
	for sx in [-1.0, 1.0]:
		var stub := Kit.box(Vector3(0.35, 0.8, 0.02), cloth)
		stub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit.add(_stubs, stub, Vector3(sx * (hw - 0.2), height - 0.45, 0.0))
