extends "res://tests/test_case.gd"
## Chapter One additions (module B8) against Krystal's REAL health component (src/player/player_health.gd,
## spec section 9: i-frames -> reduction -> shield -> hp): every new committed attack (Brambleback charge, Lantern
## Moth orb, Hollow Drudge pick swing + ground scrape, Brood Skitter leap, Knotted Elder root sweep + charge)
## lands exactly ONCE with its data damage, a dodge (i-frames) avoids each one, a shield absorbs first; plus the
## radial-pulse helper (radius, walls, player group only), slows through the player's own bounded API, and
## drops rolled from data. Falls back to the plain health.gd when the player module's script is missing.

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Base := preload("res://src/enemies/enemy_base.gd")
const PLAYER_HEALTH := "res://src/player/player_health.gd"
const PLAIN_HEALTH := "res://src/combat/health.gd"
const SHARED_PROJECTILE := "res://src/combat/projectile.gd"
const LOCAL_PROJECTILE := "res://src/enemies/enemy_projectile.gd"
const NEW_IDS := ["brambleback", "lantern_moth", "hollow_drudge", "brood_skitter", "knotted_elder"]

const DT := 1.0 / 60.0

## Every committed attack: enemy id, forced attack (next_attack, "" = its only one), data attack id, where
## Krystal stands, whether it moves (charges need a floor and move_and_slide), whether it shoots an orb.
const ATTACKS := [
	{"id": "brambleback", "force": "", "attack": "charge", "pos": Vector3(0, 0, -4.5), "move": true, "orb": false},
	{"id": "lantern_moth", "force": "", "attack": "dust_orb", "pos": Vector3(0, 0, -6.0), "move": false, "orb": true},
	{"id": "hollow_drudge", "force": "pick_swing", "attack": "pick_swing", "pos": Vector3(0, 0, -2.0), "move": false, "orb": false},
	{"id": "hollow_drudge", "force": "scrape", "attack": "scrape", "pos": Vector3(0, 0, -3.3), "move": false, "orb": false},
	{"id": "brood_skitter", "force": "", "attack": "leap", "pos": Vector3(0, 0, -2.5), "move": false, "orb": false},
	{"id": "knotted_elder", "force": "root_sweep", "attack": "root_sweep", "pos": Vector3(0, 0, -2.4), "move": false, "orb": false},
	{"id": "knotted_elder", "force": "charge", "attack": "charge", "pos": Vector3(0, 0, -6.0), "move": true, "orb": false},
]

var _nodes: Array = []
var _saved_area: Node = null


## Krystal stand-in: the player group, the player's health component, knockback and the player's slow API.
class Krystal extends CharacterBody3D:
	var health: Node
	var knocks: int = 0
	var damaged_count: int = 0
	var slows: Array = []
	var accept_slow := true

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
		return accept_slow


func before_each() -> void:
	fresh_state()
	_nodes.clear()
	Base.reset_attack_tokens()
	Base.clock_override_ms = 100000
	Settings.set_value("horror_intensity", 1)
	Settings.set_value("arachnophobia", false)
	_saved_area = Game.area
	Game.area = null


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_stop_orbs()
	Base.clock_override_ms = -1
	Base.reset_attack_tokens()
	Settings.set_value("horror_intensity", 1)
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
	var p := {"home": pos, "no_drops": true}
	if id == "knotted_elder":
		p["reward_id"] = ""
	var e: Node = Factory.create(id, p)
	add_child(e)
	(e as Node3D).global_position = pos
	e.set_physics_process(false)
	e.target_override = target
	_nodes.append(e)
	return e


func _stop_orbs() -> void:
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("stop_all")
	for p in get_children():
		if p.get_script() != null and p.get_script().resource_path == LOCAL_PROJECTILE:
			p.queue_free()


func _fly(orb: Node3D, max_t: float = 4.0) -> void:
	if ResourceLoader.exists(SHARED_PROJECTILE):
		load(SHARED_PROJECTILE).call("invalidate_targets")
	orb.set_physics_process(false)
	var t := 0.0
	while is_instance_valid(orb) and String(orb.get("result")) == "" and t < max_t:
		orb.step(DT)
		t += DT


func _until(e: Node, s: String, max_t: float, move: bool) -> float:
	var t := 0.0
	while e.state != s and t < max_t:
		e.tick(DT)
		if move:
			e._apply_movement(DT)
		t += DT
	return t


## Runs one full wind-up -> attack -> recover of `spec` against `k` (and flies the orb). Returns the enemy.
func _run(spec: Dictionary, k: Krystal) -> Node:
	var e := _enemy(String(spec["id"]), k)
	if bool(spec["move"]):
		await wait_physics(2)
	if String(spec["force"]) != "":
		e.next_attack = String(spec["force"])
	_until(e, "telegraph", 5.0, bool(spec["move"]))
	assert_eq(e.state, "telegraph", "%s/%s winds up" % [spec["id"], spec["attack"]])
	_until(e, "recover", 6.0, bool(spec["move"]))
	assert_eq(e.state, "recover", "%s/%s resolves and recovers" % [spec["id"], spec["attack"]])
	if bool(spec["orb"]):
		var orb: Variant = e.get("orb")
		assert_true(orb is Node3D, "the moth released its orb")
		if orb is Node3D:
			_fly(orb as Node3D)
	for i in 30:                                   # a little of the recovery: nothing may hit again
		e.tick(DT)
	return e


func _data_damage(spec: Dictionary) -> float:
	for a in ItemDB.enemy(String(spec["id"])).get("attacks", []):
		if String((a as Dictionary).get("id", "")) == String(spec["attack"]):
			return float(a["damage"])
	return -1.0


# --- One hit through the player's health path ------------------------------------------------------------------

func test_every_committed_attack_lands_once_through_player_health() -> void:
	assert_true(ResourceLoader.exists(PLAYER_HEALTH), "the player module's health script is present")
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
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
		assert_eq(k.knocks, 1, "%s/%s: one knockback" % [spec["id"], spec["attack"]])
		e.queue_free()
		k.queue_free()
		_stop_orbs()
		Base.reset_attack_tokens()
		await wait_frames(1)


func test_dodge_iframes_avoid_every_committed_attack() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	for spec in ATTACKS:
		var k := _krystal(spec["pos"])
		k.health.grant_iframes(30.0)               # rolling the whole time
		var e: Node = await _run(spec, k)
		assert_almost(float(k.health.hp), 100.0, 0.001, "%s/%s is dodged by i-frames" % [spec["id"], spec["attack"]])
		assert_eq(k.damaged_count, 0, "%s/%s: no damage signal" % [spec["id"], spec["attack"]])
		assert_eq(k.knocks, 0, "%s/%s: no knockback on a dodge" % [spec["id"], spec["attack"]])
		e.queue_free()
		k.queue_free()
		_stop_orbs()
		Base.reset_attack_tokens()
		await wait_frames(1)


func test_shield_absorbs_an_enemy_hit_first() -> void:
	var k := _krystal(Vector3(0, 0, -2.0))
	if not k.health.has_method("add_shield"):
		assert_true(false, "player_health.gd offers add_shield (spec 9)")
		return
	k.health.add_shield(40.0, 30.0, "test")
	await _run(ATTACKS[2], k)                      # the Drudge's pick swing (15)
	assert_almost(float(k.health.hp), 100.0, 0.001, "the shield took the whole swing")
	assert_almost(float(k.health.get("shield")), 25.0, 0.001, "shield 40 - 15")
	assert_eq(k.knocks, 0, "a fully absorbed hit is 'blocked': no knockback")


# --- Radial pulse helper --------------------------------------------------------------------------------------

func test_pulse_hits_radius_walls_and_player_only() -> void:
	var k := _krystal(Vector3(0, 0, -3.0))
	var friend := _krystal(Vector3(1.0, 0, 0), "companion")
	var e := _enemy("hollow_drudge", k)
	await wait_physics(2)
	var hits: Array = e.pulse_hits(Vector3.ZERO, 4.0, 12.0, 3.0)
	assert_eq(hits.size(), 1, "one target inside the ring")
	assert_almost(float(k.health.hp), 88.0, 0.001, "pulse damage through the player's health")
	assert_almost(float(friend.health.hp), 100.0, 0.001, "companions are never hit")
	k.global_position = Vector3(0, 0, -5.0)
	k.health.set("_iframe_until_ms", 0)
	hits = e.pulse_hits(Vector3.ZERO, 4.0, 12.0, 3.0)
	assert_eq(hits.size(), 0, "outside the ring: safe")
	k.global_position = Vector3(0, 0, -3.0)
	_box(Vector3(0, 1.0, -1.5), Vector3(6, 3, 0.4))
	await wait_physics(2)
	hits = e.pulse_hits(Vector3.ZERO, 4.0, 12.0, 3.0)
	assert_eq(hits.size(), 0, "a wall between the centre and her blocks the pulse")
	assert_eq(k.damaged_count, 1, "only the first pulse landed")


# --- Slows go through the player's own bounded API -----------------------------------------------------------

func test_slow_goes_through_the_players_own_api() -> void:
	var k := _krystal(Vector3.ZERO)
	assert_true(Base.apply_slow(k, 0.1, 9.0, 4.0, "mud_clod"), "applied through the player")
	assert_eq(k.slows.size(), 1, "the player's apply_slow was used")
	assert_almost(float(k.slows[0]["mult"]), Base.SLOW_MIN_MULT, 0.001, "clamped before it reaches her")
	assert_almost(float(k.slows[0]["seconds"]), Base.SLOW_MAX_SECONDS, 0.001, "bounded duration")
	assert_eq(String(k.slows[0]["source"]), "mud_clod")
	assert_false(GameState.buffs.has("slow"), "the enemy side did not write the buff itself")
	assert_false(Base.apply_slow(k, 0.7, 1.0), "never chains: immune after a slow")
	assert_eq(k.slows.size(), 1)
	Base.reset_attack_tokens()
	k.accept_slow = false
	assert_false(Base.apply_slow(k, 0.7, 1.0), "a slow the player refuses is not applied")
	Base.clock_override_ms = 100001
	k.accept_slow = true
	assert_true(Base.apply_slow(k, 0.7, 1.0), "a refused slow starts no enemy-side immunity")


# --- Drops from data ------------------------------------------------------------------------------------------

func test_drops_roll_from_data() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for id in NEW_IDS:
		var drops: Array = ItemDB.enemy(id).get("drops", [])
		assert_true(drops.size() > 0, "%s has drops in data" % id)
		var allowed := {}
		for d in drops:
			assert_true(ItemDB.has_item(String(d["item"])), "%s drop %s is a real item" % [id, d["item"]])
			allowed[String(d["item"])] = d
		var seen := {}
		for i in 200:
			for r in Base.roll_drops(drops, rng):
				var item := String(r["item"])
				assert_true(allowed.has(item), "%s only drops data items (%s)" % [id, item])
				var d: Dictionary = allowed.get(item, {})
				assert_true(int(r["count"]) >= maxi(int(d.get("min", 1)), 1) and int(r["count"]) <= int(d.get("max", 1)), "%s %s count in range" % [id, item])
				seen[item] = true
		for d in drops:
			if float(d.get("chance", 1.0)) >= 1.0 and int(d.get("max", 1)) > 0:
				assert_true(seen.has(String(d["item"])), "%s guaranteed drop %s appears" % [id, d["item"]])
