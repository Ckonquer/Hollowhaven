extends Node3D
## The Borrowed Porch (MP §10 room 12, §14; quest step ch2_false_home). A GENERIC storybook cottage
## facade stands in an impossible place - the middle of a dark cavern - propped up from behind like a
## stage flat. It is never a copy of Krystal's real home (nothing here reads GameState.structures) and it
## changes nothing at the Haven. Its tells: the "warm" porch lamp and windows are self-lit meshes that cast
## NO light (no Light3D, not a light_source) - the boards under the lamp stay dark - while the true path
## has an anchored flame: a plain lantern bolted to the rock that really lights the ground. A painted
## hedge-and-fence flat hides the true stair beside that flame. Holding the lantern to the anchored flame
## reveals the stair: flag ch2_false_home_revealed (the hedge folds away like paper, its collision goes).
## Knocking or looking at the lamp only explains (Gentle: explicitly); retreat is always harmless.
## Intense: on first approach a brief familiar musical fragment (Audio.request_music "haven"), then
## silence (Events.music_context_changed "silence"); the controller clears it when she leaves.
## The node sits at the area origin; its parts use area coordinates (data/works_layout_deep.gd PORCH).

signal revealed

const Layout := preload("res://data/works_layout_deep.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const Props := preload("res://src/world/below/below_props.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const TrueLight := preload("res://src/world/works/deep/true_light.gd")

const FLAG := "ch2_false_home_revealed"
const MOMENT_FLAG := "moment_hw_porch"
const FRAGMENT_CONTEXT := "haven"

var is_revealed: bool = false
var fragment_playing: bool = false
var fragment_played: bool = false
var facade: Node3D = null
var porch_lamp: Node3D = null      # the tell: glows, lights nothing
var flame: Node3D = null           # the anchored flame: a real light
var illusion: Node3D = null
var _illusion_body: StaticBody3D = null
var _flame_it: Node3D = null
var _hv: Node3D = null
var _fragment_timer: SceneTreeTimer = null


func _ready() -> void:
	add_to_group("hw_porch")
	_build_facade()
	_build_flame()
	_build_illusion()
	Events.settings_changed.connect(_on_settings_changed)
	if bool(GameState.get_flag(FLAG)):
		_apply_revealed(false)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues" and _hv != null:
		_hv.visible = Art.high_visibility() and not is_revealed


# --- Reveal ---------------------------------------------------------------------------------------------

## Reveals the true stair (idempotent). True when this call revealed it.
func reveal() -> bool:
	if is_revealed:
		return false
	GameState.set_flag(FLAG, true)
	_apply_revealed(true)
	Art.caption("[the painted hedge folds away like paper; a real stair goes down]")
	var gentle := Art.intensity() == 0
	Art.say("This flame lights the ground. The porch lamp never did. The true stair was beside it all along." if gentle
		else "A true light stays with what holds it. The stair goes down beside it.", 6.0)
	revealed.emit()
	return true


func _apply_revealed(animate: bool) -> void:
	is_revealed = true
	if _illusion_body != null:
		Art.set_collision(_illusion_body, false)
	if _hv != null:
		_hv.visible = false
	if illusion != null:
		if animate and is_inside_tree():
			var tw := illusion.create_tween().set_parallel(true)
			tw.tween_property(illusion, "scale", Vector3(1.0, 0.02, 1.0), 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.chain().tween_callback(illusion.hide)
		else:
			illusion.visible = false
	if _flame_it != null:
		_flame_it.call("disable_interaction")


## The porch lamp and windows glow but are never lights: true while no Light3D exists under the facade.
func porch_lamp_casts_light() -> bool:
	return _has_light(facade)


func flame_casts_light() -> bool:
	return _has_light(flame)


static func _has_light(n: Node) -> bool:
	if n == null:
		return false
	if n is Light3D:
		return true
	for c in n.get_children():
		if _has_light(c):
			return true
	return false


# --- Approach moment (controller) ------------------------------------------------------------------------

## Once per save, when Krystal first comes near the facade.
func on_first_approach() -> void:
	if bool(GameState.get_flag(MOMENT_FLAG)):
		return
	GameState.set_flag(MOMENT_FLAG, true)
	Events.horror_event.emit("authored:hw_porch", {})
	var d: Variant = Game.director
	if d is Node and is_instance_valid(d) and (d as Node).has_method("suppress"):
		(d as Node).call("suppress", 60.0)
	match Art.intensity():
		0:
			Art.say("A porch, lit the way a home is lit. But home is not down here - and that lamp lights nothing.", 6.0)
		2:
			play_fragment()
		_:
			Art.caption("[a porch lamp glows, warm and perfectly still]")


## Intense: a few bars of a familiar tune from nowhere, then silence.
func play_fragment() -> void:
	if fragment_played:
		return
	fragment_played = true
	fragment_playing = true
	Audio.request_music(FRAGMENT_CONTEXT, "", 1.0)
	Art.caption("[a few bars of a familiar, homely tune...]")
	if is_inside_tree():
		_fragment_timer = get_tree().create_timer(float(Layout.PORCH["fragment_seconds"]))
		_fragment_timer.timeout.connect(end_fragment)


func end_fragment() -> void:
	if not fragment_playing:
		return
	fragment_playing = false
	Audio.release_music(FRAGMENT_CONTEXT, 1.2)
	Events.music_context_changed.emit("silence")
	Art.caption("[...then silence]")


# --- Interactions ----------------------------------------------------------------------------------------

func knock() -> void:
	match Art.intensity():
		0:
			Art.say("No one answers. The door is only paint on boards. Home isn't down here - look for a light that lights the ground.", 7.0)
		2:
			Art.say("No one answers.", 3.0)
			Art.caption("[silence]")
		_:
			Art.say("No one answers. The door is painted on.", 4.0)


func look_at_lamp() -> void:
	var gentle := Art.intensity() == 0
	Art.say("It glows warm, but the boards beneath it stay dark. It lights nothing." + (" A real light would light the floor." if gentle else ""), 6.0)


func _on_flame(_player: Node) -> void:
	reveal()


func _flame_text() -> Dictionary:
	if is_revealed:
		return {}
	if Art.intensity() == 0:
		return {"text": "This flame lights the ground - follow it", "enabled": true}
	return {"text": "Hold your lantern to the anchored flame", "enabled": true}


# --- Building ---------------------------------------------------------------------------------------------

func _build_facade() -> void:
	facade = Node3D.new()
	facade.name = "Facade"
	add_child(facade)
	facade.position = Layout.PORCH["facade"]
	var wood := Mat.outlined(Mat.toon(Color("a8764a")), 0.018)
	var wall := Mat.outlined(Mat.toon(Art.CREAM, {"rim": 0.25}), 0.018)
	var trim := Mat.outlined(Mat.toon(Art.PLUM), 0.016)
	var roof := Mat.outlined(Mat.toon(Color("8a4a3c"), {"rim": 0.3}), 0.02)
	var door_mat := Mat.outlined(Mat.toon(Color("5a3a4e")), 0.016)
	var warm := Mat.glow(Palette.LANTERN_GLOW, 1.8)
	var pumpkin := Mat.outlined(Mat.toon(Art.PUMPKIN, {"rim": 0.35}), 0.016)
	var stem := Mat.toon(Color("5a7a3a"))
	# Deck and steps (walkable)
	Kit.add(facade, Kit.box(Vector3(8.0, 0.3, 2.4), wood), Vector3(0, 0.15, 1.2))
	Kit.add(facade, Kit.box(Vector3(2.4, 0.15, 0.45), wood), Vector3(0, 0.075, -0.22))
	# Posts, rail, porch roof
	for sx in [-1.0, 1.0]:
		Kit.add(facade, Kit.cylinder(0.1, 0.12, 2.7, trim, 8), Vector3(sx * 3.6, 1.65, 0.2))
		Kit.add(facade, Kit.box(Vector3(2.2, 0.08, 0.08), trim), Vector3(sx * 2.5, 1.0, 0.2))
	Kit.add(facade, Kit.box(Vector3(8.6, 0.18, 2.9), roof), Vector3(0, 3.05, 1.15), Vector3(-6, 0, 0))
	# House front, gable, roof edges
	Kit.add(facade, Kit.box(Vector3(8.0, 5.0, 0.3), wall), Vector3(0, 2.8, 2.55))
	Kit.add(facade, Kit.prism(Vector3(8.2, 2.4, 0.3), wall), Vector3(0, 6.5, 2.55))
	for sx in [-1.0, 1.0]:
		Kit.add(facade, Kit.box(Vector3(5.1, 0.3, 0.5), roof), Vector3(sx * 2.1, 6.55, 2.5), Vector3(0, 0, -sx * 30.0))
	# Door + ribbon wreath
	Kit.add(facade, Kit.box(Vector3(1.1, 2.1, 0.08), door_mat), Vector3(0, 1.35, 2.37))
	Kit.add(facade, Kit.sphere(0.05, Mat.toon(Art.BRASS), 6, 8), Vector3(0.38, 1.3, 2.31))
	Kit.add(facade, Kit.torus(0.16, 0.26, Mat.toon(Color("6a8a4a"))), Vector3(0, 2.05, 2.3), Vector3(90, 0, 0))
	Kit.add(facade, Kit.box(Vector3(0.1, 0.3, 0.02), Mat.toon(Art.RIBBONS[0])), Vector3(0.06, 1.8, 2.28), Vector3(0, 0, 14))
	# Windows: warm glow, NO light
	for sx in [-1.0, 1.0]:
		Kit.add(facade, Kit.box(Vector3(1.2, 1.0, 0.06), warm), Vector3(sx * 2.4, 1.9, 2.37))
		Kit.add(facade, Kit.box(Vector3(1.3, 0.08, 0.1), trim), Vector3(sx * 2.4, 1.9, 2.33))
		Kit.add(facade, Kit.box(Vector3(0.08, 1.1, 0.1), trim), Vector3(sx * 2.4, 1.9, 2.33))
	Kit.add(facade, Kit.cylinder(0.4, 0.4, 0.06, warm, 16), Vector3(0, 6.1, 2.37), Vector3(90, 0, 0))
	# Pumpkins and bunting (festival whimsy)
	for p in [Vector3(-1.6, 0.45, 0.4), Vector3(1.7, 0.42, 0.35), Vector3(-2.9, 0.4, 1.9)]:
		Kit.add(facade, Kit.sphere(0.24, pumpkin, 10, 12), p, Vector3.ZERO, Vector3(1.15, 0.8, 1.15))
		Kit.add(facade, Kit.cylinder(0.03, 0.04, 0.12, stem, 6), p + Vector3(0, 0.22, 0))
	for i in 9:
		var c: Color = Art.RIBBONS[i % Art.RIBBONS.size()]
		Kit.add(facade, Kit.prism(Vector3(0.3, 0.34, 0.02), Mat.toon(c)), Vector3(-3.3 + float(i) * 0.82, 2.75, 0.12), Vector3(180, 0, 0))
	# The porch lamp: warm-looking, self-lit, casts NO light. The boards under it stay dark.
	porch_lamp = Node3D.new()
	porch_lamp.name = "PorchLamp"
	facade.add_child(porch_lamp)
	porch_lamp.position = Vector3(1.2, 2.45, 1.4)
	Kit.add(porch_lamp, Kit.cylinder(0.012, 0.012, 0.5, Mat.toon(Color("3a3034")), 5), Vector3(0, 0.3, 0))
	Kit.add(porch_lamp, Kit.cylinder(0.12, 0.15, 0.06, Mat.toon(Color("3a3034")), 10), Vector3(0, 0.05, 0))
	Kit.add(porch_lamp, Kit.cylinder(0.11, 0.11, 0.26, Mat.transparent(Color(1.0, 0.86, 0.6, 0.3), true), 10), Vector3(0, -0.12, 0))
	Kit.add(porch_lamp, Kit.sphere(0.07, Mat.glow(Palette.LANTERN_GLOW, 3.2), 8, 10), Vector3(0, -0.12, 0))
	# Stage-flat struts behind (walk around it and it is only a front)
	for sx in [-3.2, 0.0, 3.2]:
		Kit.add(facade, Kit.box(Vector3(0.14, 5.2, 0.14), wood), Vector3(sx, 2.3, 4.0), Vector3(-32, 0, 0))
	# Collision: deck, steps, posts, the flat
	var body := StaticBody3D.new()
	body.name = "FacadeBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	facade.add_child(body)
	for spec in [[Vector3(0, 0.15, 1.2), Vector3(8.0, 0.3, 2.4)], [Vector3(0, 2.8, 2.55), Vector3(8.0, 5.0, 0.3)],
			[Vector3(-3.6, 1.65, 0.2), Vector3(0.24, 2.7, 0.24)], [Vector3(3.6, 1.65, 0.2), Vector3(0.24, 2.7, 0.24)]]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = spec[1]
		cs.shape = sh
		cs.position = spec[0]
		body.add_child(cs)
	var step := CollisionShape3D.new()
	var ssh := BoxShape3D.new()
	ssh.size = Vector3(2.4, 0.2, 1.0)
	step.shape = ssh
	step.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-17.0)), Vector3(0, 0.05, -0.4))
	body.add_child(step)
	# Interactions: knock, look at the lamp
	var door_it: Node3D = Interactable.new()
	door_it.setup({"text": "Knock on the door", "size": Vector3(1.6, 2.2, 1.6), "offset": Vector3(0, 1.4, 1.7),
		"handler": func(_p: Node) -> void: knock(), "id": "hw_porch_door"})
	door_it.name = "Door"
	facade.add_child(door_it)
	var lamp_it: Node3D = Interactable.new()
	lamp_it.setup({"text": "Look at the porch lamp", "size": Vector3(1.2, 1.4, 1.2), "offset": Vector3(1.2, 1.9, 1.0),
		"handler": func(_p: Node) -> void: look_at_lamp(), "id": "hw_porch_lamp"})
	lamp_it.name = "LampLook"
	facade.add_child(lamp_it)


func _build_flame() -> void:
	flame = Node3D.new()
	flame.name = "AnchoredFlame"
	add_child(flame)
	flame.position = Layout.PORCH["flame"]
	var iron := Mat.outlined(Mat.toon(Color("3b3238"), {"rim": 0.4}), 0.014)
	# bolted to the rock: a bracket plate, bolts, a short chain
	Kit.add(flame, Kit.box(Vector3(0.6, 0.8, 0.12), iron), Vector3(0.9, 1.9, 0))
	for y in [1.65, 2.15]:
		Kit.add(flame, Kit.sphere(0.05, iron, 6, 8), Vector3(0.83, float(y), 0))
	Props.lamp(flame, Vector3.ZERO, {"style": "post", "color": Palette.LANTERN_GLOW, "energy": 1.5, "range": 6.5, "idle": 0.04, "shadow": false})
	var src: Node3D = TrueLight.new()
	src.name = "TrueLight"
	src.set("light_radius", 4.5)
	flame.add_child(src)
	src.position = Vector3(0, 1.4, 0)
	_flame_it = Interactable.new()
	_flame_it.setup({"size": Vector3(1.6, 2.2, 1.6), "offset": Vector3(-0.3, 1.1, 0), "handler": Callable(self, "_on_flame"),
		"text_func": Callable(self, "_flame_text"), "accent": true, "id": "hw_porch_flame"})
	_flame_it.name = "FlameInteract"
	flame.add_child(_flame_it)
	_hv = Node3D.new()
	_hv.name = "Hv"
	flame.add_child(_hv)
	Art.bold_ring(_hv, 1.1)
	_hv.visible = Art.high_visibility()


func _build_illusion() -> void:
	illusion = Node3D.new()
	illusion.name = "PaintedHedge"
	add_child(illusion)
	illusion.position = Layout.PORCH["illusion"]
	var hedge := Mat.outlined(Mat.toon(Color("5f8a4a"), {"rim": 0.25}), 0.016)
	var white := Mat.outlined(Mat.toon(Color("efe8dc")), 0.014)
	var flat := Mat.toon(Color("4a6a3c"))
	# the flat itself (faces west, -x), painted hedge blobs and a picket fence in front
	Kit.add(illusion, Kit.box(Vector3(0.12, 3.8, 4.6), flat), Vector3(0.1, 1.9, 0))
	for i in 5:
		Kit.add(illusion, Kit.sphere(0.75, hedge, 8, 10), Vector3(-0.05, 1.3 + float(i % 2) * 0.5, -1.9 + float(i) * 0.95), Vector3.ZERO, Vector3(0.35, 1.2, 1.0))
	for i in 9:
		Kit.add(illusion, Kit.box(Vector3(0.06, 1.0, 0.16), white), Vector3(-0.3, 0.5, -2.0 + float(i) * 0.5))
	Kit.add(illusion, Kit.box(Vector3(0.06, 0.1, 4.4), white), Vector3(-0.3, 0.75, 0))
	_illusion_body = StaticBody3D.new()
	_illusion_body.name = "IllusionBody"
	_illusion_body.collision_layer = 1
	_illusion_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.5, 3.8, 4.6)
	cs.shape = sh
	cs.position = Vector3(0, 1.9, 0)
	_illusion_body.add_child(cs)
	illusion.add_child(_illusion_body)
