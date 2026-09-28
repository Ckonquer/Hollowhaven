extends Node3D
## The Ward Stone at the heart of Krystal's Haven: a mossy monolith with carved runes and an empty
## heart socket, inside a ring of standing stones. Its dim warm glow pulses weakly until the Heartseed
## is returned. Interaction (group "interactable", layer-16 collider):
##   first read       -> intro inscription, flag "read_ward_intro"
##   Lumi befriended or quest step "prepare" -> warning inscription, flag "read_ward_warning"
##   holding the Heartseed -> "Return the Heartseed" -> Game.complete_chapter()
##   after "ward_restored" -> "Light kept. Home kept. Thank you, Krystal."
## Chapter Two (docs/CHAPTER_TWO_SPEC.md §8, MP §2.4 / §11 / §17), all inside the ward_restored branch:
##   chapter_one_complete, not ch2_accepted -> the new inscription, then a choice (Game.ui.confirm):
##       "Follow the lantern road" -> flag ch2_accepted, reassurance line, the waygate hint;
##       "Stay a little longer" (or Esc) -> a gentle line; the choice is offered again next time.
##       No UI / no player (tests, headless) -> the inscription only, nothing is decided.
##   ch2_accepted -> a small menu of the options that apply: Read the inscription / Change your look
##       (Game.open_panel("wardrobe"), a toast until that panel exists) / Travel the Lantern Road (once
##       any arch is lit) / Celebrate the Lanternwake (after ch2_homecoming) / Close.
##   ch2_choir_defeated, first visit -> homecoming(): flag ch2_homecoming + "Light kept. Roads found. Welcome
##       home, Krystal." (the only line; the story glue adds the journal note and the Celebrate hint)
##   ch2_homecoming or chapter_two_complete -> reading gives that return line.
##   "Celebrate the Lanternwake" -> celebrate(): the story glue's celebrate("haven") = Game.complete_chapter_two()
## Nothing here auto-teleports; the new lines mention nothing spider-like (the legacy warning keeps its
## arachnophobia wording).
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

## Chapter Two flags and lines (MP §17, verbatim where quoted there).
const CH2_AVAILABLE_FLAG := "chapter_one_complete"
const CH2_ACCEPTED_FLAG := "ch2_accepted"
const CH2_READ_FLAG := "read_ward_ch2"
const CH2_HOMECOMING_FLAG := "ch2_homecoming"
const CH2_COMPLETE_FLAG := "chapter_two_complete"
const CH2_CHOIR_FLAG := "ch2_choir_defeated"
const WAYGATE_REPAIRED_FLAG := "ch2_waygate_repaired"
const CHOICE_ID := "ch2_lantern_road"
const RESTORED_LINE := "Light kept. Home kept. Thank you, %s."
const CH2_AVAILABLE_LINE := "A light well kept reaches farther than its keeper knows. There are lanterns beyond these woods. Tonight, one has answered."
const CH2_REASSURANCE_LINE := "Your hearth is safe. No road you follow shall unmake it."
const CH2_RETURN_LINE := "Light kept. Roads found. Welcome home, %s."
const CH2_DECLINE_LINE := "Rest, then. The road will keep."
const CH2_WAYGATE_LINE := "The old stones north of the Moonlit Ruin have woken."
const CHOICE_FOLLOW := ["follow", "Follow the lantern road", "AccentButton"]
const CHOICE_STAY := ["stay", "Stay a little longer", ""]

## Tests / scripted runs: the answer to the next choice or menu instead of asking the UI (consumed once).
var forced_choice: String = ""

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
		if chapter_two_available() and not chapter_two_accepted():
			await _offer_chapter_two(_player)
			return
		if chapter_two_accepted():
			await _chapter_two_visit(_player)
			return
		_say([RESTORED_LINE % who])
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


# --- Chapter Two ------------------------------------------------------------------------------------------

func chapter_two_available() -> bool:
	return bool(GameState.get_flag("ward_restored")) and bool(GameState.get_flag(CH2_AVAILABLE_FLAG))


func chapter_two_accepted() -> bool:
	return bool(GameState.get_flag(CH2_ACCEPTED_FLAG))


## The new inscription and the acceptance choice (offered again after "stay").
func _offer_chapter_two(who: Node) -> void:
	GameState.set_flag(CH2_READ_FLAG, true)
	_pulse_once()
	_say([CH2_AVAILABLE_LINE])
	var pick := await _ask("The Ward Stone", CH2_AVAILABLE_LINE, [CHOICE_FOLLOW, CHOICE_STAY], "", who)
	if not is_instance_valid(self):
		return
	apply_chapter_two_choice(pick)


## Applies an answer to the Chapter Two invitation: "follow" accepts, "stay"/"cancel" declines gently
## (offered again next time), "" (no answer could be asked) changes nothing.
func apply_chapter_two_choice(pick: String) -> void:
	if not chapter_two_available() or chapter_two_accepted():
		return
	match pick:
		"follow":
			accept_chapter_two()
		"stay", "cancel":
			Events.choice_made.emit(CHOICE_ID, "stay")
			_say([CH2_DECLINE_LINE])


## Chapter Two starts: flag ch2_accepted (spec §8), the reassurance, and the old stones wake.
func accept_chapter_two() -> void:
	if chapter_two_accepted():
		return
	if GameState.has_method("accept_chapter_two"):
		GameState.call("accept_chapter_two")
	GameState.set_flag(CH2_ACCEPTED_FLAG, true)
	Events.choice_made.emit(CHOICE_ID, "follow")
	_pulse_once()
	var lines: Array = [CH2_REASSURANCE_LINE]
	if not bool(GameState.get_flag(WAYGATE_REPAIRED_FLAG)):
		lines.append(CH2_WAYGATE_LINE)   # the pointer; the quest layer's ch2_waygate step shows the how-to hint
	_say(lines)


## After acceptance: the homecoming (once the Choir is gone), else the menu of options that apply.
func _chapter_two_visit(who: Node) -> void:
	if bool(GameState.get_flag(CH2_CHOIR_FLAG)) and not bool(GameState.get_flag(CH2_HOMECOMING_FLAG)):
		homecoming()
		return
	var buttons: Array = []
	for o in menu_options():
		buttons.append([o[0], o[1], "AccentButton" if buttons.is_empty() else ""])
	var pick := await _ask("The Ward Stone", "The runes glow warm and steady beneath your hand.", buttons, "read", who)
	if not is_instance_valid(self):
		return
	await choose(pick)


## The menu entries that apply right now: [[id, label], ...] (ids: read, look, road, celebrate, close).
func menu_options() -> Array:
	var out: Array = [["read", "Read the inscription"], ["look", "Change your look"]]
	if Game.has_method("lantern_road_destinations") and not (Game.lantern_road_destinations() as Array).is_empty():
		out.append(["road", "Travel the Lantern Road"])
	if bool(GameState.get_flag(CH2_HOMECOMING_FLAG)) and not bool(GameState.get_flag(CH2_COMPLETE_FLAG)):
		out.append(["celebrate", "Celebrate the Lanternwake"])
	out.append(["close", "Close"])
	return out


## Runs one menu entry (unknown / "close" / "cancel" do nothing). Awaitable (travel, celebration).
func choose(option: String) -> void:
	match option:
		"read":
			read_inscription()
		"look":
			_open_wardrobe()
		"road":
			if Game.has_method("travel_lantern_road"):
				await Game.travel_lantern_road()
		"celebrate":
			await celebrate()


## Step 19 "Bring the Celebration Home" (MP §11 / §17, story module C9): the first reading after the Choir.
## Sets ch2_homecoming, flares the stone and says the MP §17 return line (only that line); the story glue adds
## the journal note and a hint that "Celebrate" is now on the stone's menu (and at the Commons lantern).
func homecoming() -> void:
	if bool(GameState.get_flag(CH2_HOMECOMING_FLAG)):
		return
	GameState.set_flag(CH2_HOMECOMING_FLAG, true)
	_pulse_once()
	_say([CH2_RETURN_LINE % GameState.player_name])
	var story := _story_script()
	if story != null:
		story.call("on_homecoming")


## Step 20 "The Lanternwake" from home: the stone flares and the story glue runs Game.complete_chapter_two()
## (rewards committed and saved first; then the celebration outside the build area, the ending card, credits
## and free play). Nothing happens before the homecoming or after the chapter is complete. Awaitable.
func celebrate() -> void:
	if not bool(GameState.get_flag(CH2_HOMECOMING_FLAG)) or bool(GameState.get_flag(CH2_COMPLETE_FLAG)):
		return
	_busy = true
	_pulse_once()
	play_glow_burst(2.0)
	var story := _story_script()
	if story != null:
		await story.call("celebrate", "haven")
	elif Game.has_method("complete_chapter_two"):
		var rewards: Dictionary = Game.chapter_two_rewards() if Game.has_method("chapter_two_rewards") else {}
		await Game.complete_chapter_two(rewards)
	if is_instance_valid(self):
		_busy = false


## The Chapter Two story glue (src/world/story_ch2/story_ch2.gd), loaded safely: the stone keeps working without it.
static func _story_script() -> Script:
	var path := "res://src/world/story_ch2/story_ch2.gd"
	if not ResourceLoader.exists(path):
		return null
	var s: Variant = load(path)
	return s if s is Script and (s as Script).can_instantiate() else null


## The Chapter Two reading: the return line once she is home for good, else thanks + reassurance
## (+ the waygate reminder while it is still broken).
func read_inscription() -> void:
	var who: String = GameState.player_name
	_pulse_once()
	if bool(GameState.get_flag(CH2_COMPLETE_FLAG)) or bool(GameState.get_flag(CH2_HOMECOMING_FLAG)):
		_say([CH2_RETURN_LINE % who])
		return
	var lines: Array = [RESTORED_LINE % who, CH2_REASSURANCE_LINE]
	if not bool(GameState.get_flag(WAYGATE_REPAIRED_FLAG)):
		lines.append(CH2_WAYGATE_LINE)
	_say(lines)


func _open_wardrobe() -> void:
	if _ui_has_panel("wardrobe"):
		Game.open_panel("wardrobe")
	else:
		Events.notify.emit("A mirror to change your look is on its way. Soon!", "info")


static func _ui_has_panel(panel: String) -> bool:
	var ui: Node = Game.ui
	if ui == null or not is_instance_valid(ui):
		return false
	if ui.has_method("has_panel"):
		return bool(ui.call("has_panel", panel))
	var sc: Variant = ui.get_script()
	if sc is Script:
		var panels: Variant = (sc as Script).get_script_constant_map().get("PANELS")
		return panels is Dictionary and (panels as Dictionary).has(panel)
	return false


## Asks through Game.ui.confirm (the world pauses while it is open). Returns `fallback` when no choice
## can be shown (no UI, no interacting player, not playing) and `forced_choice` when a test set one.
func _ask(title: String, text: String, buttons: Array, fallback: String, who: Node) -> String:
	if forced_choice != "":
		var f := forced_choice
		forced_choice = ""
		return f
	var ui: Node = Game.ui
	if who == null or ui == null or not is_instance_valid(ui) or not ui.has_method("confirm") or Game.mode != "playing":
		return fallback
	_busy = true
	var pick: Variant = await ui.confirm(title, text, buttons)
	if is_instance_valid(self):
		_busy = false
	return String(pick) if (pick is String or pick is StringName) else "cancel"


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
