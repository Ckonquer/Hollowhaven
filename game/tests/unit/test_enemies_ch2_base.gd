extends "res://tests/test_case.gd"
## Chapter Two ordinary enemies + the Quarry Warden (module C5) - the shared rules, against Krystal's REAL health
## component (src/player/player_health.gd: i-frames -> reduction -> shield -> hp):
##  * factory registration, safe loading, groups / layers, hp from data, data within MP section 12 ranges
##  * every committed attack lands exactly ONCE with its data damage through the player's health path, and a dodge
##    (i-frames) avoids every one of them; companions are never hit
##  * committed telegraphs never faster than 1.0 s; the pack cap (2 at once) and Gentle's "no overlap" (1 at once);
##    Gentle / Intense rest lengths; nothing louder or faster on Intense
##  * existing sound names only, no Light3D anywhere, nothing spider-like (the arachnophobia setting changes nothing)
##  * cheap to tick

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const Combat := preload("res://src/combat/combat.gd")
const PLAYER_HEALTH := "res://src/player/player_health.gd"
const PLAIN_HEALTH := "res://src/combat/health.gd"
const SHARED_PROJECTILE := "res://src/combat/projectile.gd"
const IDS := ["pumpkin_mimic", "patchwalker", "velvet_wing", "bellcap_sentry", "borrowed_wisp", "quarry_warden"]
## MP section 12 starting ranges [hp min, hp max, damage min, damage max] (the Warden is an elite without a range).
const MP_RANGES := {"pumpkin_mimic": [65, 85, 12, 15], "patchwalker": [80, 100, 15, 18], "velvet_wing": [45, 60, 10, 13],
	"bellcap_sentry": [70, 90, 13, 17], "borrowed_wisp": [55, 75, 14, 18]}
## Every sound name the six scripts use (grep-able; each must exist).
const USED_SOUNDS := ["grass_pull", "brambling_chatter", "brambling_telegraph", "chest_close", "dig", "mine_cart", "land",
	"enemy_hurt", "harvest_crop", "dir_creak", "swing", "splash", "dir_wrong_squeak", "shade_drift", "dodge",
	"shade_telegraph", "shade_whisper", "gloomling_flinch", "lantern_off", "ward_hum", "mine_hit", "dir_pebbles",
	"rock_break", "fake_lumi_chime", "heartseed_pulse", "tree_fall", "hit_soft"]
const DT := 1.0 / 60.0

## Every committed attack: id, forced attack, data attack id, Krystal's spot, needs a floor + movement, end state,
## extra setup (property -> value) before the wind-up.
const ATTACKS := [
	{"id": "pumpkin_mimic", "force": "bite", "attack": "bite", "pos": Vector3(0, 0, -2.0), "move": false, "end": "recover", "set": {}},
	{"id": "pumpkin_mimic", "force": "roll", "attack": "roll", "pos": Vector3(0, 0, -5.0), "move": true, "end": "stuck", "set": {"bites_done": 1}},
	{"id": "patchwalker", "force": "rake", "attack": "rake", "pos": Vector3(0, 0, -2.4), "move": false, "end": "recover", "set": {}},
	{"id": "patchwalker", "force": "mud_clod", "attack": "mud_clod", "pos": Vector3(0, 0, -6.0), "move": false, "end": "recover", "set": {}},
	{"id": "velvet_wing", "force": "dash", "attack": "dash", "pos": Vector3(0, 0, -4.0), "move": true, "end": "recover", "set": {}},
	{"id": "velvet_wing", "force": "drain", "attack": "drain", "pos": Vector3(0, 0, -5.0), "move": false, "end": "recover", "set": {"ward_light_override": 0.0}},
	{"id": "bellcap_sentry", "force": "", "attack": "pulse", "pos": Vector3(0, 0, -2.5), "move": false, "end": "recover", "set": {}},
	{"id": "borrowed_wisp", "force": "", "attack": "sweep", "pos": Vector3(0, 0, -3.0), "move": false, "end": "recover", "set": {"light_override": 0.0}},
	{"id": "quarry_warden", "force": "slam", "attack": "slam", "pos": Vector3(0, 0, -3.0), "move": false, "end": "recover", "set": {}},
	{"id": "quarry_warden", "force": "charge", "attack": "charge", "pos": Vector3(0, 0, -6.0), "move": true, "end": "recover", "set": {"slams_done": 1}},
]

var _nodes: Array = []
var _saved_area: Node = null


## Krystal stand-in: the player group, the player's health component, knockback and the player's slow API.
class Krystal extends CharacterBody3D:
	var health: Node
	var knocks: int = 0
	var damaged_count: int = 0
	var slows: Array = []

	func use_health(script: Script) -> void:
		health = script.new()
		health.name = "Health"
		health.max_hp = 100.0
		add_child(health)
		collision_layer = 2
		health.damaged.connect(func(_a: float, _s: Node, _d: Vector3) -> void: damaged_count += 1)

	func knockback(_dir: Vector3, _force: float) -> void:
		knocks += 1

	func apply_slow(mult: float, seconds: float, source: String = "") -> bool:
		slows.append({"mult": mult, "seconds": seconds, "source": source})
		return true


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	Settings.set_value("reduce_flashing", false)
	Settings.set_value("timing_assist", false)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_stop_projectiles()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	GameState.buffs.erase("slow")
	Game.area = _saved_area
	await wait_frames(2)


func _health_script() -> Script:
	if ResourceLoader.exists(PLAYER_HEALTH):
		var s: Script = load(PLAYER_HEALTH)
		if s != null and s.can_instantiate():
			return s
	return load(PLAIN_HEALTH)


func _krystal(pos: Vector3, group: String = "player") -> Krystal:
	var k := Krystal.new()
	k.use_health(_health_script())
	add_child(k)
	k.global_position = pos
	if group != "":
		k.add_to_group(group)
	_nodes.append(k)
	return k


func _box(pos: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.collision_layer = layer
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	w.add_child(cs)
	add_child(w)
	w.global_position = pos
	_nodes.append(w)
	return w


func _enemy(id: String, target: Node3D, pos: Vector3 = Vector3.ZERO) -> Node:
	var e: Node = Factory.create(id, {"home": pos, "no_drops": true})
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _stop_projectiles() -> void:
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("stop_all")


func _fly(p: Node3D, max_t: float = 4.0) -> void:
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("invalidate_targets")
	p.set_physics_process(false)
	var t := 0.0
	while is_instance_valid(p) and String(p.get("result")) == "" and t < max_t:
		p.step(DT)
		t += DT


func _until(e: Node, s: String, max_t: float, move: bool) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		if move:
			e._apply_movement(DT)
		t += DT
	return t


func _data_damage(spec: Dictionary) -> float:
	for a in ItemDB.enemy(String(spec["id"])).get("attacks", []):
		if String((a as Dictionary).get("id", "")) == String(spec["attack"]):
			return float(a["damage"])
	return -1.0


## One full wind-up -> attack -> end state of `spec` against `k` (a thrown clod is flown to the end).
func _run(spec: Dictionary, k: Krystal) -> Node:
	var e := _enemy(String(spec["id"]), k)
	for key in (spec["set"] as Dictionary):
		e.set(String(key), spec["set"][key])
	if bool(spec["move"]):
		await wait_physics(2)
	if String(spec["force"]) != "":
		e.next_attack = String(spec["force"])
	_until(e, "telegraph", 6.0, bool(spec["move"]))
	assert_eq(e.state, "telegraph", "%s/%s winds up" % [spec["id"], spec["attack"]])
	_until(e, String(spec["end"]), 8.0, bool(spec["move"]))
	assert_eq(e.state, String(spec["end"]), "%s/%s resolves (%s)" % [spec["id"], spec["attack"], e.state])
	var clod: Variant = e.get("clod")
	if clod is Node3D:
		_fly(clod as Node3D)
	for i in 30:
		e.tick(DT)
	return e


# --- Factory / data ---------------------------------------------------------------------------------------------

func test_factory_registers_and_spawns_safely() -> void:
	for id in IDS:
		assert_true(Factory.has_enemy(id), "%s registered" % id)
		assert_true(Factory.can_spawn(id), "%s compiles" % id)
		var e: Node = Factory.spawn(id, self, Transform3D(Basis.IDENTITY, Vector3(60, 0, 60)), {"no_drops": true})
		_nodes.append(e)
		assert_not_null(e, "%s spawned" % id)
		if e == null:
			continue
		e.set_physics_process(false)
		assert_true(e.is_in_group("enemy"), "%s in group enemy (awake by default)" % id)
		assert_eq((e as CharacterBody3D).collision_layer, 8, "%s enemy layer" % id)
		assert_eq((e as CharacterBody3D).collision_mask, 1 | 32, "%s collides with world|structure" % id)
		assert_almost(float(e.health.max_hp), float(ItemDB.enemy(id)["hp"]), 0.001, "%s hp from data" % id)
		assert_not_null(e.visual, "%s has a procedural visual" % id)
		assert_true((e.committed_states as Array).size() > 0, "%s declares its committed states" % id)
		assert_true(bool(e.needs_clear_shot), "%s checks a clear line before winding up" % id)


func test_data_within_master_prompt_ranges() -> void:
	for id in MP_RANGES:
		var d: Dictionary = ItemDB.enemy(id)
		var r: Array = MP_RANGES[id]
		assert_true(float(d["hp"]) >= float(r[0]) and float(d["hp"]) <= float(r[1]), "%s hp %.0f in MP range" % [id, d["hp"]])
		assert_true(float(d["damage"]) >= float(r[2]) and float(d["damage"]) <= float(r[3]), "%s damage in MP range" % id)
		for a in d.get("attacks", []):
			assert_true(String((a as Dictionary).get("tell", "")) != "", "%s/%s has a readable tell (caption text)" % [id, a["id"]])
	var w: Dictionary = ItemDB.enemy("quarry_warden")
	assert_true(bool(w.get("elite", false)), "the Warden is an elite")
	assert_true(int(w.get("pillars", 0)) >= 2, "at least two pillars")


func test_committed_telegraphs_are_never_faster_than_a_second() -> void:
	var d := _krystal(Vector3(0, 0, -30))
	for id in IDS:
		var e := _enemy(id, d, Vector3(float(IDS.find(id)) * 8.0, 0, 20))
		for a in ItemDB.enemy(id).get("attacks", []):
			var t: float = e.attack_telegraph(a)
			assert_true(t >= 1.0, "%s/%s wind-up %.2f s >= 1.0 s" % [id, a["id"], t])
			assert_true(t <= 1.6 + 0.001, "%s/%s wind-up %.2f s stays readable, not endless" % [id, a["id"], t])


# --- The player's health path ---------------------------------------------------------------------------------

func test_every_committed_attack_lands_once_through_player_health() -> void:
	assert_true(ResourceLoader.exists(PLAYER_HEALTH), "the player module's health script is present")
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	for spec in ATTACKS:
		var k := _krystal(spec["pos"])
		var e: Node = await _run(spec, k)
		var want := _data_damage(spec)
		assert_true(want > 0.0, "%s/%s has data damage" % [spec["id"], spec["attack"]])
		assert_eq(k.damaged_count, 1, "%s/%s damages exactly once" % [spec["id"], spec["attack"]])
		assert_almost(float(k.health.hp), 100.0 - want, 0.001, "%s/%s deals its data damage (%.0f)" % [spec["id"], spec["attack"], want])
		var lh: Variant = k.health.get("last_hit")
		if lh is Dictionary and not (lh as Dictionary).is_empty():
			assert_almost(float(lh["raw"]), want, 0.001, "%s/%s: the raw hit reached the player's intake" % [spec["id"], spec["attack"]])
		e.queue_free()
		k.queue_free()
		_stop_projectiles()
		Base.reset_attack_tokens()
		GameState.buffs.erase("slow")
		await wait_frames(1)


func test_dodge_iframes_avoid_every_committed_attack() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	for spec in ATTACKS:
		var k := _krystal(spec["pos"])
		k.health.grant_iframes(30.0)
		var e: Node = await _run(spec, k)
		assert_almost(float(k.health.hp), 100.0, 0.001, "%s/%s is dodged by i-frames" % [spec["id"], spec["attack"]])
		assert_eq(k.damaged_count, 0, "%s/%s: no damage signal" % [spec["id"], spec["attack"]])
		assert_eq(k.knocks, 0, "%s/%s: no knockback on a dodge" % [spec["id"], spec["attack"]])
		assert_eq(k.slows.size(), 0, "%s/%s: no slow on a dodge" % [spec["id"], spec["attack"]])
		if String(spec["attack"]) == "drain":
			assert_almost(float(e.healed_total), 0.0, 0.001, "a dodged drain heals nothing")
		e.queue_free()
		k.queue_free()
		_stop_projectiles()
		Base.reset_attack_tokens()
		await wait_frames(1)


func test_companions_are_never_hit() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	for spec in ATTACKS:
		var k := _krystal(spec["pos"])
		var pos: Vector3 = spec["pos"]
		var friend := _krystal(pos * 0.6 + Vector3(0.3, 0, 0), "companion")
		var e: Node = await _run(spec, k)
		assert_almost(float(friend.health.hp), 100.0, 0.001, "%s/%s never hurts a companion" % [spec["id"], spec["attack"]])
		assert_eq(friend.slows.size(), 0, "%s/%s never slows a companion" % [spec["id"], spec["attack"]])
		e.queue_free()
		k.queue_free()
		friend.queue_free()
		_stop_projectiles()
		Base.reset_attack_tokens()
		GameState.buffs.erase("slow")
		await wait_frames(1)


# --- Caps and intensity -----------------------------------------------------------------------------------------

func _windups(list: Array) -> int:
	var n := 0
	for e in list:
		if e.state == "telegraph" or e.state in (e.committed_states as Array):
			n += 1
	return n


func _pack(level: int) -> int:
	Settings.set_value("horror_intensity", level)
	Base.reset_attack_tokens()
	var d := _krystal(Vector3(0, 0, 0))
	var list: Array = []
	for i in 3:
		var a := TAU * float(i) / 3.0
		var e := _enemy("patchwalker", d, Vector3(cos(a) * 2.2, 0, sin(a) * 2.2))
		e.next_attack = "rake"
		list.append(e)
	var most := 0
	var clock := 100000
	for f in 600:
		clock += 17
		Base.clock_override_ms = clock
		for e in list:
			if e.state == "recover" or e.state == "chase":
				e.next_attack = "rake"
			e.tick(DT)
		most = maxi(most, _windups(list))
	for e in list:
		e.queue_free()
	d.queue_free()
	return most


func test_pack_cap_and_gentle_never_overlaps() -> void:
	assert_eq(_pack(1), Base.MAX_ATTACKERS, "Standard: at most two committed wind-ups at once")
	assert_eq(_pack(2), Base.MAX_ATTACKERS, "Intense: still at most two (never more overlap)")
	assert_eq(_pack(0), 1, "Gentle: never two wind-ups at once")


func test_intensity_changes_rest_not_tells() -> void:
	var rests := {}
	var tells := {}
	for level in [0, 1, 2]:
		Settings.set_value("horror_intensity", level)
		Base.reset_attack_tokens()
		var d := _krystal(Vector3(0, 0, -2.0))
		var e := _enemy("bellcap_sentry", d)
		var t := _until(e, "telegraph", 4.0, false)
		var tele := _until(e, "pulse", 4.0, false)
		_until(e, "recover", 2.0, false)
		rests[level] = float(e._cooldown)
		tells[level] = tele
		e.queue_free()
		d.queue_free()
		await wait_frames(1)
		assert_true(t < 4.0, "level %d winds up" % level)
	assert_true(float(rests[0]) > float(rests[1]), "Gentle rests longer (%.2f > %.2f)" % [rests[0], rests[1]])
	assert_true(float(rests[2]) < float(rests[1]), "Intense rests less (%.2f < %.2f)" % [rests[2], rests[1]])
	assert_true(float(tells[0]) > float(tells[1]), "Gentle wind-ups are longer")
	assert_almost(float(tells[2]), float(tells[1]), DT * 2.0, "Intense never shortens a tell")


# --- Presentation rules -------------------------------------------------------------------------------------------

func test_sounds_are_existing_names_only() -> void:
	for s in USED_SOUNDS:
		assert_true(Audio.has_sound(String(s), true), "sound '%s' exists" % s)
	var re := RegEx.new()
	re.compile("Audio\\.play_3d\\(\"([a-z_0-9]+)\"")
	for id in IDS:
		var path: String = Factory.script_path(id)
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			assert_true(USED_SOUNDS.has(m.get_string(1)), "%s plays a listed sound (%s)" % [id, m.get_string(1)])


static func _lights(n: Node) -> int:
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _lights(ch)
	return c


static func _mesh_count(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _mesh_count(ch)
	return c


func test_no_lights_and_nothing_spider_like() -> void:
	var d := _krystal(Vector3(0, 0, -40))
	var counts := {}
	for id in IDS:
		var e := _enemy(id, d, Vector3(float(IDS.find(id)) * 6.0, 0, 30))
		assert_eq(_lights(e), 0, "%s adds no Light3D (few dynamic lights; the wisp must light nothing)" % id)
		assert_false(e.is_in_group("light_source"), "%s is not a light source" % id)
		assert_eq(String(ItemDB.enemy(id).get("alt_name", "")), "", "%s is not spider-like: no arachnophobia swap needed" % id)
		counts[id] = _mesh_count(e.visual)
	Settings.set_value("arachnophobia", true)
	for id in IDS:
		var e2 := _enemy(id, d, Vector3(float(IDS.find(id)) * 6.0, 0, 40))
		assert_eq(_mesh_count(e2.visual), int(counts[id]), "%s looks the same in arachnophobia mode (nothing to swap)" % id)
		assert_eq(String(ItemDB.enemy_display_name(id)), String(ItemDB.enemy(id)["name"]), "%s keeps its name" % id)


func test_six_new_enemies_tick_cheaply() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	var target := _krystal(Vector3.ZERO)
	var list: Array = []
	for i in 12:
		var id: String = IDS[i % IDS.size()]
		var a := TAU * float(i) / 12.0
		list.append(_enemy(id, target, Vector3(cos(a) * 8.0, 0.0, sin(a) * 8.0)))
	await wait_physics(2)
	var t0 := Time.get_ticks_usec()
	var frames := 120
	for f in frames:
		for e in list:
			e.tick(DT)
			e._apply_movement(DT)
	var per_frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	print("PERF ch2 enemies: 12 enemies tick+move = %.3f ms per frame" % per_frame_ms)
	assert_true(per_frame_ms < 4.0, "12 Chapter Two enemies cost < 4 ms per frame (%.3f ms)" % per_frame_ms)
