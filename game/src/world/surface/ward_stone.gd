extends Node3D
## The Ward Stone at the heart of Krystal's Haven: a mossy monolith with carved runes and an empty
## heart socket, inside a ring of standing stones. Its dim warm glow pulses weakly until the Heartseed
## is returned. Interaction (group "interactable", layer-16 collider):
##   first read       -> intro inscription, flag "read_ward_intro"
##   Lumi befriended or quest step "prepare" -> warning inscription, flag "read_ward_warning"
##   holding the Heartseed -> "Return the Heartseed" -> Game.complete_chapter()
##   after "ward_restored" -> "Light kept. Home kept. Thank you, Krystal."
## set_restored(t) blends the look from dim (0) to restored (1); play_glow_burst() for the ending.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")
const AudioUtil := preload("res://src/world/surface/audio_util.gd")

const SPEAKER := "Ward Stone"
const LINE_SECONDS := 5.5
const RESTORED_RUNE := Color("ffbf4d")

var restored_amount := 0.0
var rune_material: StandardMaterial3D
var heart_material: StandardMaterial3D
var light: OmniLight3D
var _t := 0.0
var _busy := false
var _say_tw: Tween
var _flash := 0.0              # 0..1 extra brightness while the stone answers a reading
var _flash_tw: Tween
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	name = "WardStone"
	add_to_group("interactable")
	add_to_group("ward_stone")
	add_to_group("light_source")
	_build()
	set_restored(1.0 if GameState.get_flag("ward_restored") else 0.0)


func _build() -> void:
	var stone_mat := NodeVisuals.rock_material(0.03)
	var tint := Color("a9a79a")
	# Plinth
	var plinth := Props.instance(Props.stone_block(1, Vector3(3.4, 0.45, 3.0), Palette.STONE_DARK, 0.3), stone_mat)
	plinth.position = Vector3(0, -0.2, 0)
	add_child(plinth)
	# Monolith (front faces +Z, toward the Haven centre).
	var mono := Props.instance(Props.stone_block(7, Vector3(1.35, 3.3, 0.85), tint, 0.85), stone_mat)
	mono.position = Vector3(0, 0.1, 0)
	add_child(mono)
	var cap := Props.instance(Props.stone_block(8, Vector3(1.0, 0.5, 0.7), tint.lightened(0.05), 1.0), stone_mat)
	cap.position = Vector3(0.05, 3.2, 0)
	cap.rotation_degrees = Vector3(0, 12, 6)
	add_child(cap)
	# Moss drapes
	var moss_mat := Mat.outlined(Mat.toon(Palette.MOSS, {"noise": 0.18, "noise_scale": 2.5, "rim": 0.3}), 0.016)
	for i in 5:
		var mb := MeshInstance3D.new()
		mb.mesh = Kit.blob_mesh(0.28 + float(i % 2) * 0.1, 9100 + i, 0.35, 0.55, 1)
		mb.material_override = moss_mat
		add_child(mb)
		mb.position = Vector3([-0.45, 0.4, -0.2, 0.55, 0.0][i], [3.05, 2.9, 3.3, 1.6, 0.5][i], [0.2, -0.15, 0.1, 0.3, 0.42][i])
	# Runes: carved glowing marks (unique material so the glow can pulse and brighten).
	rune_material = StandardMaterial3D.new()
	rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_material.albedo_color = Palette.WARD_GLOW
	rune_material.emission_enabled = true
	rune_material.emission = Palette.WARD_GLOW
	rune_material.emission_energy_multiplier = 0.6
	var runes := NodeVisuals.Merger.new()
	var front := 0.43
	var marks: Array = [
		[Vector3(0, 2.75, front), Vector3(0.5, 0.05, 0.04), 0.0], [Vector3(0, 2.55, front), Vector3(0.05, 0.36, 0.04), 0.0],
		[Vector3(-0.2, 2.25, front), Vector3(0.2, 0.05, 0.04), 35.0], [Vector3(0.2, 2.25, front), Vector3(0.2, 0.05, 0.04), -35.0],
		[Vector3(-0.32, 1.25, front), Vector3(0.05, 0.3, 0.04), 0.0], [Vector3(0.32, 1.25, front), Vector3(0.05, 0.3, 0.04), 0.0],
		[Vector3(0, 0.85, front), Vector3(0.44, 0.05, 0.04), 0.0], [Vector3(-0.15, 0.7, front), Vector3(0.05, 0.2, 0.04), 20.0],
		[Vector3(0.15, 0.7, front), Vector3(0.05, 0.2, 0.04), -20.0],
	]
	for mk in marks:
		runes.add(NodeVisuals._box(mk[1]), Transform3D(Basis(Vector3.BACK, deg_to_rad(float(mk[2]))), mk[0]), Color.WHITE)
	var ring_b := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.22
	tor.outer_radius = 0.27
	tor.rings = 20
	tor.ring_segments = 6
	runes.add(tor, Transform3D(ring_b, Vector3(0, 1.75, front)), Color.WHITE)
	var runes_mi := MeshInstance3D.new()
	runes_mi.mesh = runes.commit()
	runes_mi.material_override = rune_material
	runes_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(runes_mi)
	# Heart socket: where the Heartseed belongs.
	heart_material = StandardMaterial3D.new()
	heart_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	heart_material.albedo_color = Palette.HEART_GLOW.darkened(0.5)
	heart_material.emission_enabled = true
	heart_material.emission = Palette.HEART_GLOW
	heart_material.emission_energy_multiplier = 0.25
	var heart := MeshInstance3D.new()
	heart.mesh = NodeVisuals._sph(0.16, 8, 12)
	heart.material_override = heart_material
	heart.position = Vector3(0, 1.75, front - 0.02)
	heart.scale = Vector3(1, 1.15, 0.6)
	heart.name = "HeartSocket"
	add_child(heart)
	# Ring of smaller standing stones.
	var ring_n := 7
	for i in ring_n:
		var a := TAU * float(i) / float(ring_n) + PI * 0.5 + 0.45
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.3:
			continue   # leave the south side open toward the Haven
		var hgt := 0.9 + float((i * 37) % 5) * 0.12
		var st := Props.instance(Props.stone_block(20 + i, Vector3(0.55, hgt, 0.45), tint.darkened(0.05), 0.9), stone_mat, 120.0)
		st.position = Vector3(cos(a) * 2.9, -0.05, sin(a) * 2.9)
		st.rotation.y = -a + PI * 0.5
		st.rotation.z = deg_to_rad(float((i * 13) % 9) - 4.0)
		add_child(st)
	# Collision: monolith + ring stones (layer 1), interaction sphere (layer 16).
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.25, 3.4, 0.8)
	cs.shape = box
	cs.position = Vector3(0, 1.7, 0)
	body.add_child(cs)
	var plinth_cs := CollisionShape3D.new()
	var pc := CylinderShape3D.new()
	pc.radius = 1.45
	pc.height = 0.3
	plinth_cs.shape = pc
	plinth_cs.position = Vector3(0, 0.0, 0)
	body.add_child(plinth_cs)
	for i in ring_n:
		var a := TAU * float(i) / float(ring_n) + PI * 0.5 + 0.45
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.3:
			continue
		var rcs := CollisionShape3D.new()
		var rc := CylinderShape3D.new()
		rc.radius = 0.3
		rc.height = 1.6
		rcs.shape = rc
		rcs.position = Vector3(cos(a) * 2.9, 0.8, sin(a) * 2.9)
		body.add_child(rcs)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.4
	ics.shape = sph
	ics.position = Vector3(0, 1.3, 0.3)
	ib.add_child(ics)
	add_child(ib)
	light = OmniLight3D.new()
	light.light_color = Palette.WARD_GLOW
	light.omni_range = 5.0
	light.light_energy = 0.4
	light.shadow_enabled = false
	light.position = Vector3(0, 1.8, 1.6)
	add_child(light)
	_hum = AudioUtil.make_loop("ward_hum", "SFX", -14.0, 12.0)
	if _hum != null:
		_hum.position = Vector3(0, 1.6, 0)
		add_child(_hum)


# --- Look -------------------------------------------------------------------------------------------

## 0 = dim, fading ward; 1 = restored and radiant.
func set_restored(t: float) -> void:
	restored_amount = clampf(t, 0.0, 1.0)
	_apply_glow(0.0)


## Rune/heart brightness. Both materials are UNSHADED, and unshaded surfaces output their albedo only
## (emission is ignored), so the glow is an HDR albedo: above ~1.0 it crosses the environment's glow
## threshold and blooms. Dim ward: ~0.9-1.2 (a faint warm pulse); restored: ~1.5-1.7 (a real glow).
func _apply_glow(pulse: float) -> void:
	var r := restored_amount
	if rune_material != null:
		var k := lerpf(0.9 + pulse * 0.28, 1.6 + pulse * 0.15, r) + _flash * 0.55
		# Deeper gold as it brightens, so the tonemapper keeps the hue instead of washing it to cream.
		var c := Palette.WARD_GLOW.lerp(RESTORED_RUNE, r)
		rune_material.albedo_color = Color(c.r * k, c.g * k, c.b * k)
		rune_material.emission_energy_multiplier = lerpf(0.45 + pulse * 0.35, 2.6 + pulse * 0.4, r)
	if heart_material != null:
		var hk := lerpf(1.0, 1.45 + pulse * 0.15, r) + _flash * 0.3
		var h := Palette.HEART_GLOW.darkened(lerpf(0.55, 0.0, r))
		heart_material.albedo_color = Color(h.r * hk, h.g * hk, h.b * hk)
		heart_material.emission_energy_multiplier = lerpf(0.2 + pulse * 0.2, 3.2 + pulse * 0.5, r)
	if light != null:
		light.light_energy = lerpf(0.35 + pulse * 0.25, 1.4 + pulse * 0.25, r)
		light.omni_range = lerpf(5.0, 11.0, r)
		light.light_color = Palette.WARD_GLOW.lerp(Color("ffd3c0"), r * 0.4)
	if _hum != null:
		_hum.volume_db = lerpf(-16.0, -9.0, r)


func _process(delta: float) -> void:
	_t += delta
	# A weak, uneven pulse while dim (the ward is failing); a calm, slow breath once restored.
	var pulse: float
	if restored_amount < 0.5:
		pulse = clampf(0.5 + 0.5 * sin(_t * 1.1) * (0.6 + 0.4 * sin(_t * 0.37)), 0.0, 1.0)
		if fmod(_t, 7.3) < 0.18:
			pulse *= 0.3
	else:
		pulse = 0.5 + 0.5 * sin(_t * 0.8)
	_apply_glow(pulse)


# --- Light source contract ------------------------------------------------------------------------------

var light_radius: float = 5.0


func is_light_active() -> bool:
	return true


# --- Interaction ------------------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if not GameState.get_flag("ward_restored") and GameState.has_item("heartseed"):
		return {"text": "Return the Heartseed", "enabled": true}
	return {"text": "Read the Ward Stone", "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	var who: String = GameState.player_name
	if GameState.get_flag("ward_restored"):
		_say(["Light kept. Home kept. Thank you, %s." % who])
		return
	if GameState.has_item("heartseed"):
		_busy = true
		Audio.play_3d("heartseed_pulse", global_position + Vector3.UP * 1.7, -2.0)
		await Game.complete_chapter()
		_busy = false
		return
	if not GameState.get_flag("read_ward_intro"):
		GameState.set_flag("read_ward_intro", true)
		_pulse_once()
		_say(["Light kept, home kept. The seed sleeps below; the stone remembers.",
			"Welcome, %s. This haven has waited a long time for someone to love it." % who])
		return
	var lumi_ready: bool = GameState.is_befriended("lumi") or GameState.quests.current_id() == "prepare"
	if lumi_ready and not GameState.get_flag("read_ward_warning"):
		GameState.set_flag("read_ward_warning", true)
		_pulse_once()
		# Arachnophobia mode drops the web-spinning wording (as lore.gd's alt text does). Read at the
		# moment the inscription is spoken, so no live-toggle listener is needed.
		var took: String = "What took it still waits in the dark." if bool(Settings.get_value("arachnophobia")) else "What took it still weaves in the dark."
		_say(["Its heart was taken to the deep. " + took,
			"Carry light. Carry friends. Come home."])
		return
	if GameState.get_flag("read_ward_warning"):
		_say(["Carry light. Carry friends. Come home."])
	else:
		_say(["Light kept, home kept. The seed sleeps below; the stone remembers."])


## Says the lines one after another (a tween owned by this node, so nothing fires after it is freed).
## A new reading replaces any lines still queued from the previous one (no interleaved inscriptions).
func _say(lines: Array) -> void:
	if lines.is_empty():
		return
	if _say_tw != null and _say_tw.is_valid():
		_say_tw.kill()
	_say_tw = null
	Events.say.emit(SPEAKER, String(lines[0]), LINE_SECONDS)
	if lines.size() > 1:
		var tw := create_tween()
		_say_tw = tw
		for i in range(1, lines.size()):
			var line := String(lines[i])
			tw.tween_interval(LINE_SECONDS)
			tw.tween_callback(func() -> void: Events.say.emit(SPEAKER, line, LINE_SECONDS))


func _pulse_once() -> void:
	Audio.play_3d("ward_hum", global_position + Vector3.UP * 1.5, -6.0)
	# _process re-applies the glow every frame, so flash through _flash (read by _apply_glow).
	if _flash_tw != null and _flash_tw.is_valid():
		_flash_tw.kill()
	_flash_tw = create_tween()
	_flash_tw.tween_property(self, "_flash", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	_flash_tw.tween_property(self, "_flash", 0.0, 1.2).set_trans(Tween.TRANS_SINE)


## Ending: flare the stone brightly, then settle into the restored glow.
func play_glow_burst(duration: float = 3.0) -> void:
	var tw := create_tween()
	tw.tween_method(set_restored, restored_amount, 1.0, duration).set_trans(Tween.TRANS_SINE)
