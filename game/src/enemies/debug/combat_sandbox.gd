extends Node
## DEBUG ONLY combat sandbox (does nothing in release builds). Launch through the preview harness:
##   tools/godot.sh --path game --windowed --resolution 1280x720 -- \
##     --preview=res://src/enemies/debug/combat_sandbox.gd --preview-wait=999 --preview-shots=1 \
##     --sandbox=field|boss|stalker|spawner --shot-dir=<abs dir> [--sandbox-dark] [--settings=arachnophobia=true]
## It boots the debug arena (--sandbox-area, default "arena") through Game.load_area, builds the
## scenario, logs every enemy state change ("SANDBOX ...") and saves screenshots automatically when
## telegraphs / key beats happen, then quits. The placeholder player gets a debug Health child so
## hits can land (the real player owns its own health).

const Factory := preload("res://src/enemies/enemy_factory.gd")
const Health := preload("res://src/combat/health.gd")
const Brazier := preload("res://src/enemies/boss_brazier.gd")
const Spawner := preload("res://src/enemies/enemy_spawner.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var _dir := ""
var _t0 := 0
var _shots: Dictionary = {}
var _cam: Camera3D
var _player_health: Node
var _log: Array = []
var _frame_enemies := false


func _ready() -> void:
	if not Debug.is_cheat_allowed():
		queue_free()
		return
	process_priority = 10000      # run after the player camera so the sandbox camera wins
	_start.call_deferred()


func _now() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


func _say(msg: String) -> void:
	var line := "SANDBOX t=%.2f %s" % [_now(), msg]
	print(line)
	_log.append(line)


func _start() -> void:
	var tree := get_tree()
	# Let the preview stage start its (very long) shot timer first so it never runs.
	await tree.process_frame
	get_parent().remove_child(self)
	tree.root.add_child(self)
	_t0 = Time.get_ticks_msec()
	_dir = Debug.arg("shot-dir", "user://sandbox")
	DirAccess.make_dir_recursive_absolute(_dir)
	GameState.new_game()
	Settings.set_value("comfort_confirmed", true)
	for g in Debug.arg("give", "lantern:1,copper_sword:1").split(",", false):
		var p := g.split(":")
		GameState.give_item(p[0], int(p[1]) if p.size() > 1 else 1)
	await Game.load_area(Debug.arg("sandbox-area", "arena"), "haven_start", false)
	await tree.process_frame
	_give_player_health()
	if Debug.has_arg("sandbox-dark"):
		_make_dark()
	var sc := Debug.arg("sandbox", "field")
	_say("scenario " + sc + " arachnophobia=" + str(Settings.get_value("arachnophobia")) + " intensity=" + str(Settings.get_value("horror_intensity")))
	if Debug.has_arg("sandbox-swap-at"):
		get_tree().create_timer(float(Debug.arg("sandbox-swap-at"))).timeout.connect(func() -> void:
			Settings.set_value("arachnophobia", not bool(Settings.get_value("arachnophobia")))
			_say("arachnophobia toggled -> " + str(Settings.get_value("arachnophobia")))
			await _wait(0.5)
			await _shot("after_swap"))
	match sc:
		"field":
			await _field()
		"boss":
			await _boss()
		"stalker":
			await _stalker()
		"spawner":
			await _spawner()
		"area_boss":
			await _area_boss()
		"area_stalker":
			await _area_stalker()
		"hits":
			await _hits()
	_write_log()
	tree.quit()


# --- Helpers ----------------------------------------------------------------------------------------------

func _give_player_health() -> void:
	var p: Node3D = Game.player
	if p == null:
		return
	var Combat: Script = load("res://src/combat/combat.gd")
	_player_health = Combat.find_health(p)
	if _player_health == null:
		_player_health = Health.new()
		_player_health.name = "Health"
		_player_health.max_hp = 100.0
		p.add_child(_player_health)
	_player_health.damaged.connect(func(a: float, _s: Node, _d: Vector3) -> void: _say("player damaged %.1f hp=%.1f" % [a, float(_player_health.hp)]))


func _process(_delta: float) -> void:
	if _cam != null and is_instance_valid(_cam) and not _cam.current:
		_cam.make_current()


## Frames an enemy and the player from the side (used right before telegraph shots).
func _frame(e: Node3D) -> void:
	var p: Node3D = Game.player
	if p == null or e == null or not is_instance_valid(e):
		return
	var mid := (e.global_position + p.global_position) * 0.5 + Vector3.UP * 0.7
	var d := e.global_position - p.global_position
	d.y = 0.0
	var side := Vector3(-d.z, 0.0, d.x).normalized() if d.length() > 0.1 else Vector3.RIGHT
	_camera(mid + side * 4.2 + Vector3.UP * 1.6 - d.normalized() * 1.0, mid)


func _make_dark() -> void:
	var area: Node = Game.area
	for c in area.get_children():
		if c is WorldEnvironment:
			var e: Environment = (c as WorldEnvironment).environment
			e.background_mode = Environment.BG_COLOR
			e.background_color = Color("15121c")
			e.ambient_light_color = Palette.AMBIENT_BELOW
			e.ambient_light_energy = 0.35
			e.fog_enabled = true
			e.fog_light_color = Color("1b1824")
			e.fog_density = 0.02
		elif c is DirectionalLight3D:
			(c as DirectionalLight3D).light_energy = 0.08
			(c as DirectionalLight3D).light_color = Palette.MOON


func _camera(pos: Vector3, look: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 55.0
		Game.area.add_child(_cam)
	_cam.global_position = pos
	_cam.look_at(look)
	_cam.make_current()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join(name + ".png")
	img.save_png(path)
	var cam := get_viewport().get_camera_3d()
	_say("shot %s (camera %s at %s)" % [path, cam.name if cam != null else "none", str(cam.global_position.snapped(Vector3.ONE * 0.1)) if cam != null else ""])


func _watch(e: Node, label: String, shoot_states: Dictionary) -> void:
	if e == null:
		return
	e.connect("state_changed", func(s: String) -> void:
		_say("%s -> %s" % [label, s])
		if shoot_states.has(s):
			var key := label + "_" + s
			var n := int(_shots.get(key, 0))
			if n < int(shoot_states[s][1]):
				_shots[key] = n + 1
				await get_tree().create_timer(float(shoot_states[s][0])).timeout
				if is_instance_valid(e):
					if _frame_enemies:
						_frame(e as Node3D)
					await _shot("%s_%s_%d" % [label, s, n]))


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _write_log() -> void:
	var f := FileAccess.open(_dir.path_join("sandbox_log.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log))


# --- Scenarios ----------------------------------------------------------------------------------------------

## Bramblings + a gloomling chase the (stationary) placeholder player; shots on telegraph / recover.
func _field() -> void:
	var p: Node3D = Game.player
	# The arena spawn is inside its safe "haven" zone (enemies correctly ignore it there).
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(6, 0.1, -3)))
	if p.has_method("set_input_enabled"):
		p.set_input_enabled(false)
	if Debug.has_arg("sandbox-lantern") and p.has_method("set_lantern"):
		p.set_lantern(true)
	_frame_enemies = true
	await _wait(0.2)
	var base := p.global_position
	var list := Debug.arg("sandbox-enemies", "brambling,brambling,gloomling").split(",", false)
	var i := 0
	for id in list:
		var ang := -0.9 + float(i) * 0.9
		var pos := base + Vector3(sin(ang) * 5.0, 0.2, -cos(ang) * 5.0)
		var e := Factory.spawn(id, Game.area, Transform3D(Basis(Vector3.UP, PI), pos), {"home": pos, "wander_radius": 3.0})
		_watch(e, "%s%d" % [id, i], {"telegraph": [0.4, 2], "recover": [0.35, 1], "attack": [0.12, 1]})
		i += 1
	_camera(base + Vector3(5.5, 3.2, 3.5), base + Vector3(0, 0.6, -2.0))
	await _wait(1.0)
	await _shot("field_start")
	await _wait(float(Debug.arg("sandbox-time", "9")))
	# Fight back: hit every enemy a few times so defeat + drops run.
	var Combat: Script = load("res://src/combat/combat.gd")
	for k in 8:
		for e in get_tree().get_nodes_in_group("enemy"):
			var d: Vector3 = (e as Node3D).global_position - p.global_position
			Combat.melee(p, p.global_position + Vector3.UP, d, 30.0, 360.0, 18.0, ["enemy"], 4.0)
			break
		await _wait(0.35)
		if k == 1:
			await _shot("field_hits")
	await _wait(1.2)
	await _shot("field_end")
	_say("enemies_defeated=%d inv=%s" % [int(GameState.stats.get("enemies_defeated", 0)), str(GameState.inventory.totals())])


## Mini boss room: three anchors at 7.5 m, three braziers; scripted brazier lighting + damage.
func _boss() -> void:
	var center := Vector3(10, 0, 4)
	var anchors := [center + Vector3(-6, 7.5, -3), center + Vector3(6, 7.5, -3), center + Vector3(0, 7.5, 5)]
	var brs: Array = []
	for k in 3:
		var b: Node3D = Brazier.new()
		b.setup({"id": "brazier_%d" % k})
		Game.area.add_child(b)
		var a: Vector3 = anchors[k]
		b.global_position = Vector3(a.x * 0.8, 0.0, center.z + (a.z - center.z) * 0.8)
		brs.append(b)
	# A ceiling slab so the anchors sit on something (visual reference only)
	var slab := Kit.box(Vector3(20, 0.6, 18), Mat.toon(Palette.SILK_ROCK))
	Game.area.add_child(slab)
	slab.global_position = center + Vector3(0, 7.8, 0)
	var boss := Factory.spawn("weaver_matron", Game.area, Transform3D.IDENTITY, {"arena_center": center, "anchors": anchors, "braziers": brs})
	_watch(boss, "boss", {"intro": [0.8, 1], "telegraph": [0.8, 2], "stuck": [0.4, 1], "scorched": [0.8, 1], "climb": [0.5, 1], "rebound": [0.2, 1]})
	boss.connect("defeated", func() -> void: _say("boss defeated flag=%s" % str(GameState.get_flag("weaver_defeated"))))
	Events.boss_health_changed.connect(func(id: String, hp: float, mx: float) -> void: _say("boss bar %s %.0f/%.0f" % [id, hp, mx]))
	var p: Node3D = Game.player
	_camera(center + Vector3(9, 5.5, 13), center + Vector3(0, 2.5, 0))
	var probe := Timer.new()
	probe.wait_time = 1.0
	probe.autostart = true
	add_child(probe)
	probe.timeout.connect(func() -> void:
		if is_instance_valid(boss):
			_say("boss probe state=%s t=%.2f len=%.2f pos=%s anchors=%d hp=%.0f" % [boss.get("state"), float(boss.get("state_time")), float(boss.get("_state_len")), str((boss as Node3D).global_position.snapped(Vector3.ONE * 0.1)), (boss.get("anchors") as Array).size(), float(boss.get("health").hp)]))
	# Adaptive fight: swing only while it is stunned, light a brazier every ~9 s while it clings,
	# and sidestep every other drop (a dodge) so both the "rebound" and the "stuck" branches show.
	var lit := 0
	var next_light := _now() + 8.0
	var drops := 0
	var dodged_this_drop := false
	while _now() < 75.0 and is_instance_valid(boss) and boss.get("state") != "gone":
		await _wait(0.3)
		var st: String = String(boss.get("state"))
		if bool(boss.call("is_vulnerable")):
			Load.melee_boss(p, boss)
		if st == "telegraph" and float(boss.get("state_time")) > 0.6 and not dodged_this_drop:
			dodged_this_drop = true
			drops += 1
			if drops % 2 == 0:
				_say("player sidesteps the drop")
				p.teleport(Transform3D(Basis.IDENTITY, p.global_position + Vector3(4.5, 0, 0)))
		elif st != "telegraph" and st != "drop":
			dodged_this_drop = false
		if lit < 3 and _now() >= next_light and st in ["cling", "reposition", "telegraph"]:
			_say("lighting brazier %d" % lit)
			(brs[lit] as Node).call("light")
			lit += 1
			next_light = _now() + 9.0
	await _wait(1.0)
	await _shot("boss_after_defeat")
	var seeds := get_tree().get_nodes_in_group("heartseed_pickup")
	_say("heartseed pickups=%d" % seeds.size())
	if not seeds.is_empty():
		_camera((seeds[0] as Node3D).global_position + Vector3(2.2, 1.8, 2.8), (seeds[0] as Node3D).global_position + Vector3.UP * 1.1)
		await _wait(0.5)
		await _shot("heartseed")


## A low ceiling over a dark strip: the stalker ambushes a player standing still in the dark.
func _stalker() -> void:
	var p: Node3D = Game.player
	var base := Vector3(0, 0, -8)
	var ceiling := Kit.box(Vector3(18, 0.5, 6), Mat.toon(Palette.SILK_ROCK))
	Game.area.add_child(ceiling)
	ceiling.global_position = base + Vector3(0, 4.25, 0)
	var sh := BoxShape3D.new()
	sh.size = Vector3(18, 0.5, 6)
	Kit.static_collider(Game.area, sh, base + Vector3(0, 4.25, 0), 1)
	var route: Array = []
	for k in 7:
		route.append(base + Vector3(-7.5 + 2.5 * float(k), 4.0, 0.3 * sin(float(k))))
	p.teleport(Transform3D(Basis.IDENTITY, base + Vector3(0.5, 0.1, 0.5)))
	var st := Factory.spawn("weaver", Game.area, Transform3D.IDENTITY, {"route": route, "ambush_points": [base], "zone": "silk"})
	_watch(st, "stalker", {"emerge": [0.3, 1], "rattle": [0.55, 1], "lunge": [0.25, 1], "landed": [0.1, 1], "pass": [1.2, 2], "retreat": [0.3, 1]})
	st.connect("state_changed", func(_s: String) -> void: pass)
	_camera(base + Vector3(6.5, 2.2, 6.5), base + Vector3(0, 2.4, 0))
	# 1) Krystal lingers in the dark under the route -> rattle -> lunge.
	for k in 30:
		await _wait(0.5)
		if st.get("state") == "hidden" and _now() > 8.0:
			break
	# 2) Director pass (Krystal stepped away a little).
	p.teleport(Transform3D(Basis.IDENTITY, base + Vector3(0.5, 0.1, 5.5)))
	await _wait(1.0)
	_say("director pass_overhead() -> %s" % str(st.call("pass_overhead")))
	for k in 30:
		await _wait(0.5)
		if st.get("state") == "hidden":
			break
	# 3) Another ambush, answered by raising the lantern mid-rattle -> recoil and flee.
	p.teleport(Transform3D(Basis.IDENTITY, base + Vector3(0.5, 0.1, 0.5)))
	await _wait(0.5)
	_say("forced ambush -> %s" % str(st.call("start_ambush")))
	await _wait(0.4)
	if p.has_method("set_lantern"):
		p.set_lantern(true)
	else:
		p.set("lantern_on", true)
	_say("lantern raised, light at player=%.2f" % float(load("res://src/combat/combat.gd").light_at(p.global_position + Vector3.UP)))
	await _wait(3.0)
	await _shot("stalker_end")


## Spawner check: spawns near the player, sets the clear flag once all are defeated.
func _spawner() -> void:
	var p: Node3D = Game.player
	var sp: Node3D = Spawner.new()
	sp.setup({"enemy": "brambling", "count": 3, "radius": 4.0, "respawn_minutes": -1.0, "spawner_id": "sandbox_bramblings", "quest_flag_on_clear": "ruin_cleared", "clear_message": "The Bramblings scatter!"})
	Game.area.add_child(sp)
	sp.global_position = p.global_position + Vector3(0, 0, -12)
	sp.set("ignore_safe_zones", true)
	await _wait(2.0)
	_say("alive=%d" % (sp.get("alive") as Array).size())
	_camera(p.global_position + Vector3(6, 4, 4), sp.global_position)
	await _shot("spawner_spawned")
	var Combat: Script = load("res://src/combat/combat.gd")
	for k in 20:
		for e in get_tree().get_nodes_in_group("enemy"):
			var h: Node = Combat.find_health(e)
			if h != null:
				h.apply_damage(15.0, p, Vector3.FORWARD)
		await _wait(0.3)
	await _wait(1.0)
	_say("flags cleared=%s ruin_cleared=%s alive=%d" % [str(GameState.get_flag("spawner_cleared_sandbox_bramblings")), str(GameState.get_flag("ruin_cleared")), (sp.get("alive") as Array).size()])


## Integration check in a real area (--sandbox-area=below): finds the dungeon-placed boss, walks
## Krystal into the arena with her lantern up and records the opening beats of the fight.
func _area_boss() -> void:
	var boss: Node3D = null
	for n in get_tree().get_nodes_in_group("enemy"):
		if n.has_method("reset_fight"):
			boss = n
	if boss == null:
		_say("no boss found in area " + Game.area_id)
		return
	var center: Vector3 = boss.get("arena_center")
	_say("boss found: state=%s center=%s anchors=%d braziers=%d" % [boss.get("state"), str(center), (boss.get("anchors") as Array).size(), (boss.get("braziers") as Array).size()])
	_watch(boss, "areaboss", {"intro": [1.0, 1], "telegraph": [0.8, 2], "stuck": [0.4, 1], "scorched": [0.8, 1], "rebound": [0.2, 1]})
	var p: Node3D = Game.player
	p.teleport(Transform3D(Basis.IDENTITY, center + Vector3(0, 0.2, 6.0)))
	if p.has_method("set_input_enabled"):
		p.set_input_enabled(false)
	if p.has_method("set_lantern"):
		p.set_lantern(true)
	_camera(center + Vector3(6.0, 4.0, 8.5), center + Vector3(-1.0, 2.5, -1.0))
	await _wait(12.0)
	var brs: Array = boss.get("braziers")
	if not brs.is_empty():
		_say("lighting a dungeon brazier")
		(brs[0] as Node).call("light")
	await _wait(4.0)
	await _shot("area_boss_end")
	if not Debug.has_arg("sandbox-full"):
		return
	# --sandbox-full: fight to the end (strike while stunned, light the next brazier every ~9 s),
	# then record the retreat into the crack and the freed Heartseed.
	_watch(boss, "areaboss", {"gone": [0.2, 1]})
	boss.connect("defeated", func() -> void: _say("boss defeated flag=%s" % str(GameState.get_flag("weaver_defeated"))))
	# The brazier prompt as the real player's probe sees it (needs the Lantern the sandbox gave her).
	if brs.size() > 1:
		var bp: Vector3 = (brs[1] as Node3D).global_position
		var stand2 := bp + (center - bp).normalized() * 1.6 + Vector3.UP * 0.1
		p.teleport(Transform3D(Basis.looking_at(Vector3(bp.x, stand2.y, bp.z) - stand2, Vector3.UP), stand2))
		if p.has_method("set_input_enabled"):
			p.set_input_enabled(true)
		await _wait(0.5)
		_say("prompt near brazier 1: %s" % str(p.call("get_prompt") if p.has_method("get_prompt") else "?"))
		if p.has_method("set_input_enabled"):
			p.set_input_enabled(false)
		p.teleport(Transform3D(Basis.IDENTITY, center + Vector3(0, 0.2, 6.0)))
	var lit := 1
	var next_light := _now() + 6.0
	while _now() < 110.0 and boss.get("state") != "gone" and boss.get("state") != "defeat":
		await _wait(0.3)
		var st: String = String(boss.get("state"))
		if bool(boss.call("is_vulnerable")):
			(boss.get("health") as Node).call("apply_damage", 18.0, p, Vector3.ZERO)   # stand-in for Krystal's swings
		if lit < brs.size() and _now() >= next_light and st in ["cling", "reposition", "telegraph"]:
			(brs[lit] as Node).call("light")
			_say("lighting dungeon brazier %d" % lit)
			lit += 1
			next_light = _now() + 9.0
	_say("boss state=%s hp=%.0f" % [str(boss.get("state")), float(boss.get("health").hp)])
	if boss.get("state") == "defeat":
		_camera(center + Vector3(4.5, 1.7, 6.5), center + Vector3(0.0, 3.8, -1.5))
		await _wait(1.0)
		await _shot("area_boss_defeat_shriek")
		await _wait(1.6)
		await _shot("area_boss_defeat_rising")
		await _wait(1.4)
		await _shot("area_boss_defeat_gone")
	await _wait(1.5)
	var seeds := get_tree().get_nodes_in_group("heartseed_pickup")
	_say("heartseed pickups=%d flag=%s" % [seeds.size(), str(GameState.get_flag("weaver_defeated"))])
	# The real player's interaction probe must find the freed seed; taking it gives the key item.
	if not seeds.is_empty():
		var sp: Vector3 = (seeds[0] as Node3D).global_position
		var stand := sp + Vector3(0.0, 0.1, 1.7)
		p.teleport(Transform3D(Basis.looking_at(Vector3(sp.x, stand.y, sp.z) - stand, Vector3.UP), stand))
		if p.has_method("set_input_enabled"):
			p.set_input_enabled(true)
		await _wait(0.6)
		_say("prompt near the seed: %s" % str(p.call("get_prompt") if p.has_method("get_prompt") else "?"))
		(seeds[0] as Node).call("interact", p)
		await _wait(1.0)
		_say("heartseed carried=%s pickups left=%d" % [str(GameState.has_item("heartseed")), get_tree().get_nodes_in_group("heartseed_pickup").size()])


## Integration check in the real Silk Hollows (--sandbox-area=below): Krystal waits at the dungeon's
## first ambush point with her lantern down, so the dungeon-placed stalker ambushes in the real
## passage (ceiling normals probed from the real geometry). Records rattle -> lunge -> retreat.
func _area_stalker() -> void:
	var st: Node3D = null
	for n in get_tree().get_nodes_in_group("stalker"):
		if n is Node3D:
			st = n
	if st == null:
		_say("no stalker found in area " + Game.area_id)
		return
	if Game.director != null and is_instance_valid(Game.director) and Game.director.has_method("suppress"):
		Game.director.suppress(999.0)
	var amb: Array = st.get("ambush_points")
	if amb.is_empty():
		_say("stalker has no ambush points")
		return
	var a: Vector3 = amb[0]
	var p: Node3D = Game.player
	p.teleport(Transform3D(Basis.IDENTITY, a + Vector3.UP * 0.2))
	if p.has_method("set_input_enabled"):
		p.set_input_enabled(false)
	if p.has_method("set_lantern"):
		p.set_lantern(false)
	_say("stalker found: route=%d ambush=%s" % [(st.get("route") as Array).size(), str(a)])
	_watch(st, "areastalker", {"rattle": [0.5, 1], "lunge": [0.2, 1], "landed": [0.05, 1], "retreat": [0.3, 1]})
	_camera(a + Vector3(1.5, 1.4, 7.0), a + Vector3(0.0, 3.2, 0.0))
	var Combat: Script = load("res://src/combat/combat.gd")
	for k in 40:
		await _wait(0.5)
		if k % 4 == 0:
			var srcs: Array = []
			for s in get_tree().get_nodes_in_group("light_source"):
				if s is Node3D and s.has_method("is_light_active") and s.is_light_active() and (s as Node3D).global_position.distance_to(p.global_position) < 12.0:
					srcs.append("%s@%.1fm" % [s.name, (s as Node3D).global_position.distance_to(p.global_position)])
			_say("probe dist=%.1f st=%s cd=%.1f intensity=%d light=%.2f linger=%.2f safe=%s mode=%s lights=%s" % [p.global_position.distance_to(a), str(st.get("state")), float(st.get("_cooldown")), int(st.call("intensity")), float(Combat.light_at(p.global_position + Vector3.UP)),
				float(st.get("_linger")), str(Game.area.is_safe_zone(p.global_position)) if Game.area.has_method("is_safe_zone") else "?", Game.mode, str(srcs)])
		if st.get("state") == "retreat" or (st.get("state") == "hidden" and k > 20):
			break
	await _wait(2.5)
	_say("stalker state=%s player hp=%s segments=%s" % [str(st.get("state")), str(GameState.player.get("hp")), str(st.get("_seg_ok"))])
	await _shot("area_stalker_end")
	# A director-style pass while Krystal stands further up the passage.
	for k in 20:
		if st.get("state") == "hidden":
			break
		await _wait(0.5)
	p.teleport(Transform3D(Basis.IDENTITY, a + Vector3(0.5, 0.2, 7.0)))
	await _wait(0.5)
	st.set("_watch_positions", true)
	var ok: bool = bool(st.call("pass_overhead"))
	var pts: Array = []
	for e in (st.get("_path") as Array):
		pts.append(str((e["pos"] as Vector3).snapped(Vector3.ONE * 0.1)))
	_say("pass_overhead -> %s from %s path %s" % [str(ok), str((st as Node3D).global_position.snapped(Vector3.ONE * 0.1)), ", ".join(pts)])
	_watch(st, "areapass", {"pass": [1.0, 1]})
	for k in 30:
		await _wait(0.5)
		if st.get("state") == "hidden":
			break
	_say("pass finished state=%s" % str(st.get("state")))


## Hit feedback close-up: swings at a stationary enemy and captures the frames right after impact
## (white-rose flash, particle puff, floating number, knockback).
func _hits() -> void:
	var p: Node3D = Game.player
	p.teleport(Transform3D(Basis.IDENTITY, Vector3(6, 0.1, -3)))
	if p.has_method("set_input_enabled"):
		p.set_input_enabled(false)
	await _wait(0.3)
	var id := Debug.arg("sandbox-enemies", "brambling").split(",")[0]
	var pos := p.global_position + Vector3(0, 0.1, -1.8)
	var e: Node3D = Factory.spawn(id, Game.area, Transform3D(Basis(Vector3.UP, 0.0), pos), {"home": pos, "no_drops": true})
	e.set_physics_process(false)
	e.rotation.y = 0.0
	e.look_at(p.global_position + Vector3(0, e.global_position.y - p.global_position.y, 0), Vector3.UP)
	_camera(pos + Vector3(2.6, 1.4, 1.2), pos + Vector3(0, 0.6, 0))
	await _wait(1.0)
	await _shot("hits_before")
	var Combat: Script = load("res://src/combat/combat.gd")
	for k in 3:
		Combat.melee(p, p.global_position + Vector3.UP, e.global_position - p.global_position, 3.0, 90.0, 9.0, ["enemy"], 3.0)
		await get_tree().process_frame
		await _shot("hits_impact_%d" % k)
		await _wait(0.25)
		await _shot("hits_after_%d" % k)
		await _wait(1.2)


class Load:
	## Swings at the boss from right next to it (only lands while it is stunned).
	static func melee_boss(p: Node3D, boss: Node3D) -> void:
		var Combat: Script = load("res://src/combat/combat.gd")
		var aim: Vector3 = boss.call("get_aim_point")
		var from := aim + (p.global_position - aim).normalized() * 2.0
		from.y = aim.y
		Combat.melee(p, from, aim - from, 3.0, 120.0, 18.0, ["enemy"], 0.0)
