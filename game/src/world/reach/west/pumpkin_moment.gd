extends Node3D
## "The Pumpkin That Turned" (MP §14, docs/ch2/maps/horror.md 13b): a carved show pumpkin on a hay bale beside
## the orchard lane - clearly nobody's crop (a prize rosette hangs from the bale, it is not a structure and not
## near any build area). She sees it; after she has walked away and comes back, it faces a different way.
## Later, close up, its stem twitches twice: the lesson that teaches how to recognise a Pumpkin Mimic.
## It never attacks, is never in the "enemy" group and never damages anyone. Once per save (flags below).
##   Gentle (horror_intensity 0): it turns while unseen; when she notices it, it does a playful little hop +
##     a caption.  Standard (1): it turns while unseen, silently (a purely visual change).
##   Intense (2): while she watches from a distance, the face quietly turns toward its new direction, then
##     holds perfectly still - no sound at all, so no volume spike.
## Flags: Data.FLAG_MOMENT_SEEN (seen once), Data.FLAG_MOMENT_TURNED (the once-per-save turn),
## Data.FLAG_MOMENT_TWITCH (the stem lesson). On load it is rebuilt already turned from the flags.
## The district controller calls check(player_pos, on_screen) a few times per second; there is no director
## in the Reach, so it emits Events.horror_event("authored:pumpkin_turned") for listeners and suppresses a
## director only if one exists.

const Data := preload("res://data/reach_west.gd")
const Art := preload("res://src/world/reach/west/west_art.gd")
const B := preload("res://src/world/reach/west/west_build.gd")
const Fx := preload("res://src/world/common/fx.gd")

const WATCH := "watch"       # not seen yet
const AWAY := "away"         # seen; waiting for her to walk away
const RETURNING := "return"  # she left; it turns when she comes back (per intensity)
const TURNED := "turned"     # turned; the twitch lesson comes next
const DONE := "done"

const RADIUS := 0.42

var phase: String = WATCH
var intensity_override: int = -1
var turn_seconds: float = 2.4          # Intense on-screen turn duration (tests shorten it)
var face_yaw: float = 0.0
var turned_yaw: float = 0.0
var pending_notice: bool = false       # Gentle: a playful hop + caption when she next looks at it
var events: Array = []                 # what fired, in order (tests / QA)

var pumpkin: Node3D                    # the rotating pivot (face + body + stem)
var stem: Node3D
var _base: Vector3 = Vector3.ZERO
var _tw: Tween


func setup(p: Dictionary) -> void:
	_base = p.get("pos", _base)
	face_yaw = float(p.get("face_yaw", face_yaw))
	turned_yaw = float(p.get("turned_yaw", turned_yaw))


func _ready() -> void:
	name = "PumpkinThatTurned"
	position = _base
	_build()
	restore()


func _build() -> void:
	var prop := Art.prop_material()
	var bale := Props_instance(Art.hay_bale(), prop)
	add_child(bale)
	# A festival prize rosette pinned to the bale: this pumpkin belongs to the festival, not to a garden.
	var ros := MeshInstance3D.new()
	ros.mesh = Art._torus(0.06, 0.13)
	ros.material_override = Art.tinted(Color("5f8fd9"), 0.2)
	ros.position = Vector3(0.0, 0.34, 0.44)
	ros.rotation_degrees = Vector3(90, 0, 0)
	add_child(ros)
	var tail := MeshInstance3D.new()
	tail.mesh = Art.ribbon_strip(0.3)
	tail.material_override = Art.ribbon_material(Art.RIBBON_GOLD)
	tail.position = Vector3(0.0, 0.2, 0.46)
	tail.rotation_degrees = Vector3(0, 0, 180)
	add_child(tail)
	pumpkin = Node3D.new()
	pumpkin.name = "Pivot"
	pumpkin.position = Vector3(0, 0.6, 0)
	add_child(pumpkin)
	var body := MeshInstance3D.new()
	body.mesh = Art.pumpkin_body(1)
	body.material_override = prop
	body.scale = Vector3.ONE * RADIUS
	pumpkin.add_child(body)
	var face := MeshInstance3D.new()
	face.name = "Face"
	face.mesh = Art.carved_face()
	face.material_override = Art.glow(Color("ffb347"), 1.4)
	face.scale = Vector3.ONE * RADIUS
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pumpkin.add_child(face)
	stem = Node3D.new()
	stem.name = "Stem"
	stem.position = Vector3(0, RADIUS * Art.pumpkin_top(1), 0)
	pumpkin.add_child(stem)
	var sm := MeshInstance3D.new()
	sm.mesh = Art.pumpkin_stem(true)
	sm.material_override = prop
	sm.scale = Vector3.ONE * RADIUS
	stem.add_child(sm)
	# The carved face looks along +Z of the pivot; yaw so that +Z points at the target.
	pumpkin.rotation.y = face_yaw


static func Props_instance(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


## Face yaw (radians) so the carved +Z side looks from `from` toward `to`.
static func face_yaw_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y)


func intensity() -> int:
	if intensity_override >= 0:
		return intensity_override
	return clampi(int(Settings.get_value("horror_intensity")), 0, 2)


## Rebuilds the phase and the pumpkin's facing from the saved flags.
func restore() -> void:
	pending_notice = false
	if _flag(Data.FLAG_MOMENT_TWITCH):
		phase = DONE
	elif _flag(Data.FLAG_MOMENT_TURNED):
		phase = TURNED
	elif _flag(Data.FLAG_MOMENT_SEEN):
		phase = RETURNING       # loading the area again means she was away
	else:
		phase = WATCH
	if pumpkin != null:
		pumpkin.rotation.y = turned_yaw if phase in [TURNED, DONE] else face_yaw


func is_turned() -> bool:
	return phase in [TURNED, DONE]


## One step of the moment. Returns the event that fired ("" if none): seen, left, turn, turn_watched,
## notice, twitch.
func check(player_pos: Vector3, on_screen: bool) -> String:
	var d := Vector2(player_pos.x - _base.x, player_pos.z - _base.z).length()
	var ev := ""
	match phase:
		WATCH:
			if on_screen and d <= Data.MOMENT_SEE_DIST:
				GameState.set_flag(Data.FLAG_MOMENT_SEEN, true)
				phase = AWAY
				ev = "seen"
		AWAY:
			if d >= Data.MOMENT_LEAVE_DIST:
				phase = RETURNING
				ev = "left"
		RETURNING:
			if d <= Data.MOMENT_RETURN_DIST:
				if intensity() >= 2:
					if on_screen and d >= Data.MOMENT_INTENSE_MIN:
						_turn(true)
						ev = "turn_watched"
					elif not on_screen and d < Data.MOMENT_INTENSE_MIN:
						_turn(false)
						ev = "turn"
				elif not on_screen:
					_turn(false)
					pending_notice = intensity() == 0
					ev = "turn"
		TURNED:
			if pending_notice and on_screen and d <= Data.MOMENT_NOTICE_DIST:
				pending_notice = false
				_playful_notice()
				ev = "notice"
			elif on_screen and d <= Data.MOMENT_TWITCH_DIST:
				_twitch_lesson()
				ev = "twitch"
	if ev != "":
		events.append(ev)
	return ev


func _turn(watched: bool) -> void:
	if _flag(Data.FLAG_MOMENT_TURNED):
		phase = TURNED
		return
	GameState.set_flag(Data.FLAG_MOMENT_TURNED, true)      # once per save: flag first
	phase = TURNED
	# "pos" = the pumpkin itself: a following companion that reacts to horror cues (Mochi shelters) turns
	# toward the real pumpkin instead of an invented point ahead of Krystal - one more visual pointer.
	Events.horror_event.emit("authored:pumpkin_turned", {"kind": "authored", "zone": Data.ORCHARD,
		"intensity": intensity(), "watched": watched, "pos": _base + Vector3.UP * 0.6})
	if Game.director != null and is_instance_valid(Game.director) and Game.director.has_method("suppress"):
		Game.director.suppress(30.0)
	_kill_tween()
	if watched and turn_seconds > 0.01 and is_inside_tree():
		# Intense: the face turns slowly while she watches, eases to a stop, then holds perfectly still.
		_tw = create_tween()
		_tw.tween_interval(0.35)
		_tw.tween_property(pumpkin, "rotation:y", turned_yaw, turn_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		pumpkin.rotation.y = turned_yaw


func _playful_notice() -> void:
	Events.caption.emit("[The roadside pumpkin has shuffled round to face the other way. It looks very pleased with itself.]")
	if not is_inside_tree():
		return
	_kill_tween()
	_tw = create_tween()
	_tw.tween_property(pumpkin, "position:y", 0.85, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_property(pumpkin, "position:y", 0.6, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_tw.tween_property(pumpkin, "rotation:z", 0.18, 0.12)
	_tw.tween_property(pumpkin, "rotation:z", -0.14, 0.14)
	_tw.tween_property(pumpkin, "rotation:z", 0.0, 0.12)


## The mimic lesson: two clear stem twitches, a caption and a one-time hint. Never an attack.
func _twitch_lesson() -> void:
	GameState.set_flag(Data.FLAG_MOMENT_TWITCH, true)
	phase = DONE
	Events.caption.emit("[The pumpkin's stem twitches twice... then holds very still.]")
	Events.hint.emit("hr_mimic_tell", "A stem that twitches twice is no ordinary pumpkin. Mimics hide in the orchard's marked patch: inspect them from arm's length, and be ready.")
	twitch_stem(stem, self)


## Two quick stem twitches (also used by the mimic pocket). Visual only.
static func twitch_stem(stem_node: Node3D, owner_node: Node) -> void:
	if stem_node == null or owner_node == null or not owner_node.is_inside_tree():
		return
	var tw := owner_node.create_tween()
	for i in 2:
		tw.tween_property(stem_node, "rotation:z", 0.45, 0.08)
		tw.tween_property(stem_node, "rotation:z", -0.25, 0.08)
		tw.tween_property(stem_node, "rotation:z", 0.0, 0.1)
		tw.tween_interval(0.14)


func _kill_tween() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null
	if pumpkin != null:
		pumpkin.position.y = 0.6
		pumpkin.rotation.z = 0.0


func _flag(f: String) -> bool:
	var v: Variant = GameState.get_flag(f)
	return v is bool and v
