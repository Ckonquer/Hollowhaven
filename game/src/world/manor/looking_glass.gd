extends Node3D
## The Looking-Glass Hall's lesson (MP §9 "teach reflection/light clues", §13.1 Phase B): Moonveil's mirrors
## show only TRUE light. The mirror world behind the west wall (built by the area, batched) is a dim copy
## where only real candles glow - the "painted" glass flames on the sideboard never appear. A practice ward
## candle stands in front of the second mirror: lighting it with the Lantern makes it burn twice (once in
## the glass) and reveals the lesson for the Count's fight: of three identical little bat figures facing
## the fourth mirror, only ONE shows in the glass - the one with the golden collar. Sets mm_mirror_clue and
## discovers lore_ch2_manor_looking_glass. No forced camera; visual + caption + text only.
## API: practice_candle, is_revealed(), reveal(announce), mirrored(pos) (static).

signal revealed

const Layout := preload("res://data/manor_layout.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const WardCandle := preload("res://src/world/manor/ward_candle.gd")
const Interactable := preload("res://src/world/manor/manor_interactable.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const LORE_CARD := "lore_ch2_manor_looking_glass"
const FLAME := Color("ffc562")
const COLLAR := Color("ffd35a")

var practice_candle: Node3D = null
var hall_card: Node3D = null
var _reflection: Node3D
var _collar: Node3D
var _bold: MeshInstance3D
var _revealed := false


## Mirror image of a hall position across the looking-glass plane.
static func mirrored(p: Vector3) -> Vector3:
	return Vector3(2.0 * Layout.MIRROR_X - p.x, p.y, p.z)


func _ready() -> void:
	name = "LookingGlass"
	add_to_group("mm_looking_glass")
	_build()
	if bool(GameState.get_flag(Layout.FLAG_MIRROR_CLUE)):
		practice_candle.call("restore", true)
		reveal(false)
	if not Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.connect(_on_settings_changed)


func is_revealed() -> bool:
	return _revealed


func collar_visible() -> bool:
	return _collar != null and _collar.visible


func _on_practice_lit(_c: Node3D) -> void:
	reveal(true)


## Shows the candle's reflection and the golden collar in the glass. announce: first-time text + flag.
func reveal(announce: bool) -> void:
	if _revealed:
		return
	_revealed = true
	_reflection.visible = true
	_collar.visible = true
	_bold.visible = bool(Settings.get_value("high_visibility_cues"))
	if announce:
		var first := not bool(GameState.get_flag(Layout.FLAG_MIRROR_CLUE))
		GameState.set_flag(Layout.FLAG_MIRROR_CLUE, true)
		GameState.discover_lore(LORE_CARD)
		Events.caption.emit("[the looking-glass brightens: the candle burns twice]")
		if first:
			Events.say.emit("", "In the looking-glass the candle burns twice. The painted flames on the sideboard don't show at all.", 6.0)
			if is_inside_tree():
				get_tree().create_timer(6.2).timeout.connect(_second_line)
	revealed.emit()


func _second_line() -> void:
	if is_instance_valid(self):
		Events.say.emit("", "And of the three little bats before the fourth glass, only one appears in it: the one with a golden collar.", 7.0)


func _read_card() -> void:
	var l := LoreDB.get_lore(LORE_CARD)
	GameState.discover_lore(LORE_CARD)
	Events.say.emit(String(l.get("title", "")), String(l.get("text", "")), 12.0)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" and _bold != null:
		_bold.visible = _revealed and bool(Settings.get_value("high_visibility_cues"))


func _build() -> void:
	practice_candle = WardCandle.new()
	practice_candle.setup({"id": "practice", "kind": "practice", "lit": false, "pool_radius": 2.2, "height": 1.1,
		"prompt": "Light the candle before the looking-glass"})
	practice_candle.name = "PracticeCandle"
	add_child(practice_candle)
	practice_candle.position = Layout.PRACTICE_CANDLE
	practice_candle.lit.connect(_on_practice_lit)
	# The candle's reflection in the second glass.
	_reflection = Node3D.new()
	_reflection.name = "CandleReflection"
	add_child(_reflection)
	var flame_at := Layout.PRACTICE_CANDLE + Vector3.UP * (1.1 + 0.46)
	_reflection.position = mirrored(flame_at)
	var f := Kit.sphere(0.06, Mat.glow(FLAME, 3.2), 8, 10)
	Kit.add(_reflection, f, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.9, 1.0))
	var h := Kit.sphere(0.24, Mat.transparent(Color(1.0, 0.8, 0.45, 0.2), true), 8, 12)
	Kit.add(_reflection, h, Vector3.ZERO)
	Kit.add(_reflection, Kit.cylinder(0.075, 0.085, 0.26, Mat.glow(Color("fff2dc"), 0.6), 10), Vector3(0, -0.21, 0))
	for c in _reflection.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reflection.visible = false
	# The golden collar of the true bat, seen only in the glass.
	var bat: Vector3 = Layout.BAT_FIGURES[Layout.TRUE_BAT]
	_collar = Node3D.new()
	_collar.name = "CollarGlint"
	add_child(_collar)
	_collar.position = mirrored(bat) + Vector3(0.0, 0.22, 0.0)
	var ring := Kit.torus(0.06, 0.09, Mat.glow(COLLAR, 2.6))
	Kit.add(_collar, ring, Vector3.ZERO, Vector3(0, 0, 90))   # faces the hall (seen face-on in the glass)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spark := Kit.sphere(0.035, Mat.glow(Color("fff6d0"), 3.0), 6, 8)
	Kit.add(_collar, spark, Vector3(0.07, 0.02, 0.0))
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bold = Kit.torus(0.2, 0.26, Mat.glow(Color("fff4d0"), 1.8))
	Kit.add(_collar, _bold, Vector3.ZERO, Vector3(0, 0, 90))
	_bold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bold.visible = false
	_collar.visible = false
	# The house rule, written down.
	hall_card = Interactable.new()
	hall_card.setup({"id": "looking_glass_card", "text": "Read the card by the looking-glasses", "radius": 0.7,
		"offset": Vector3(0, 1.0, 0), "handler": Callable(self, "_read_card")})
	hall_card.name = "LookingGlassCard"
	add_child(hall_card)
	hall_card.position = Layout.HALL_CARD
	var gold := Mat.toon(Color("d6ad55"), {"rim": 0.5})
	Kit.add(hall_card, Kit.cylinder(0.05, 0.08, 1.0, gold, 8), Vector3(0, 0.5, 0))
	Kit.add(hall_card, Kit.box(Vector3(0.4, 0.28, 0.03), Mat.toon(Color("f7ecd6"))), Vector3(0, 1.08, 0), Vector3(-30, 90, 0))
	var sh := CylinderShape3D.new()
	sh.radius = 0.1
	sh.height = 1.0
	Kit.static_collider(hall_card, sh, Vector3(0, 0.5, 0), 1).name = "SolidBody"
