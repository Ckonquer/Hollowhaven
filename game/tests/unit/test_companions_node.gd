extends "res://tests/test_case.gd"
## Companion nodes in a tiny physics world (floor + fake Krystal): befriending, commands and the
## one-follower rule, pet/feed once per day, bond xp from work & zones, Mochi's refusal at the mine,
## stuck recovery, abilities (forage, tend, mining assist, gift), threats, and the spawner.

const CompanionScript := preload("res://src/companions/companion.gd")
const BoulderScript := preload("res://src/companions/pebble_boulder.gd")
const Spawner := preload("res://src/companions/companion_spawner.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var nodes: Array = []
var said: Array = []
var _say_cb: Callable
var _floor: StaticBody3D
var player: CharacterBody3D
var _saved_area_id := ""


class FakePlayer extends CharacterBody3D:
	var sprinting := false

	func _ready() -> void:
		add_to_group("player")
		collision_layer = 2
		collision_mask = 1 | 32

	func is_sprinting() -> bool:
		return sprinting

	func get_facing() -> Vector3:
		return Vector3(0, 0, -1)


class FakeBush extends Node3D:
	func _ready() -> void:
		add_to_group("harvestable")

	func get_harvest_info() -> Dictionary:
		return {"tool": "hand", "name": "Berry Bush"}


class FakeEnemy extends Node3D:
	var health: Node

	func _ready() -> void:
		add_to_group("enemy")
		health = load("res://src/combat/health.gd").new()
		health.max_hp = 20.0
		add_child(health)

	func is_threatening() -> bool:
		return true


func before_each() -> void:
	fresh_state()
	said = []
	_say_cb = func(speaker: String, text: String, _d: float) -> void: said.append([speaker, text])
	Events.say.connect(_say_cb)
	_saved_area_id = Game.area_id
	Game.area_id = ""
	_floor = StaticBody3D.new()
	_floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	_floor.add_child(cs)
	add_child(_floor)
	player = FakePlayer.new()
	add_child(player)
	player.global_position = Vector3(0, 0.05, 6)
	Game.player = player
	await wait_physics(2)


func after_each() -> void:
	if Events.say.is_connected(_say_cb):
		Events.say.disconnect(_say_cb)
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()
	Game.player = null
	Game.companion_nodes = {}
	Game.area_id = _saved_area_id
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(_floor):
		_floor.queue_free()
	await wait_frames(2)


func _make(id: String, mode: String, pos: Vector3, extra: Dictionary = {}) -> Node3D:
	var params := {"id": id, "mode": mode, "home": Vector3(0, 0.05, 10), "wild": pos}
	params.merge(extra, true)
	var c: Node3D = CompanionScript.new()
	c.setup(params)
	add_child(c)
	c.global_position = pos
	nodes.append(c)
	Game.companion_nodes[id] = c
	return c


func _befriend(id: String, assignment: String = "home") -> void:
	GameState.companion(id)["befriended"] = true
	GameState.set_companion_assignment(id, assignment)


func _cmd(c: Node, cmd: String) -> Dictionary:
	c.set("_last_command_ms", -100000)     # bypass the double-press debounce between test steps
	return c.command(cmd)


func _said_contains(fragment: String) -> bool:
	for s in said:
		if String(s[1]).contains(fragment):
			return true
	return false


# --- Befriending ----------------------------------------------------------------------------------------

func test_befriend_mochi_with_three_berries() -> void:
	var m := _make("mochi", "wild", Vector3(0, 0.05, 3))
	await wait_physics(2)
	GameState.give_item("berries", 5)
	var p: Dictionary = m.get_interaction(player)
	assert_true(p["enabled"], "prompt enabled with 3+ berries")
	assert_eq(p["text"], "Offer 3 Berries")
	m.interact(player)
	assert_eq(GameState.count_item("berries"), 2, "3 berries consumed right away")
	assert_true(GameState.is_befriended("mochi"), "friendship saved immediately (safe if the game quits mid-animation)")
	assert_eq(m.get_state(), "befriending", "stays put for the little ceremony")
	await wait_seconds(3.6)
	assert_true(GameState.is_befriended("mochi"), "befriended")
	assert_eq(GameState.active_companion, "mochi", "follows Krystal")
	assert_eq(m.get_state(), "follow")
	assert_true(_said_contains("You've made a friend"), "befriend line said: %s" % str(said))


func test_mochi_needs_berries() -> void:
	var m := _make("mochi", "wild", Vector3(0, 0.05, 3))
	GameState.give_item("berries", 2)
	var p: Dictionary = m.get_interaction(player)
	assert_false(p["enabled"])
	assert_true(String(p["text"]).contains("2/3"))
	m.interact(player)
	await wait_seconds(0.3)
	assert_eq(GameState.count_item("berries"), 2, "nothing taken")
	assert_false(GameState.is_befriended("mochi"))


func test_wild_mochi_hides_from_sprinting_krystal() -> void:
	var m := _make("mochi", "wild", Vector3(0, 0.05, 3))
	(player as FakePlayer).sprinting = true
	await wait_physics(4)
	assert_eq(m.get_state(), "afraid", "skittish when Krystal sprints nearby")
	GameState.give_item("berries", 3)
	assert_false(bool(m.get_interaction(player)["enabled"]), "can't befriend while frightened")
	(player as FakePlayer).sprinting = false
	await wait_seconds(4.3)
	assert_eq(m.get_state(), "wild", "calms down after a few seconds")


func test_lumi_needs_the_ruin_cleared() -> void:
	var l := _make("lumi", "wild", Vector3(0, 0.05, 3))
	assert_false(bool(l.get_interaction(player)["enabled"]), "too frightened while Bramblings remain")
	assert_false(l.is_light_active(), "dim while hiding")
	GameState.set_flag("ruin_cleared", true)
	var p: Dictionary = l.get_interaction(player)
	assert_true(p["enabled"])
	assert_eq(p["text"], "Reach out to the little light")
	l.interact(player)
	await wait_seconds(3.4)
	assert_true(GameState.is_befriended("lumi"))
	assert_true(l.is_in_group("light_source"), "Lumi is a light source")
	assert_true(l.is_light_active(), "glowing once befriended")
	assert_almost(float(l.get("light_radius")), 5.0, 0.001)


func test_boulder_frees_pebble() -> void:
	var peb := _make("pebble", "pinned", Vector3(0, 0.05, 0.6))
	var b: Node3D = BoulderScript.new()
	b.setup({"pebble": peb, "front": Vector3(0, 0, 1)})
	add_child(b)
	nodes.append(b)
	await wait_frames(2)
	assert_true(peb.get("pinned"), "pinned under the boulder")
	assert_eq(peb.get_interaction(player), {}, "boulder handles the prompt")
	var p: Dictionary = b.get_interaction(player)
	assert_eq(p["text"], "Needs a Pickaxe")
	assert_false(p["enabled"])
	b.harvest_hit(player, "")
	assert_almost(float(b.get("damage")), 0.0, 0.001, "bare hands do nothing")
	assert_eq(b.get_harvest_info()["tool"], "pickaxe")
	GameState.give_item("stone_pickaxe", 1)
	assert_true(bool(b.get_interaction(player)["enabled"]))
	for i in 4:
		b.set("_hit_cd", 0.0)
		b.harvest_hit(player, "stone_pickaxe")
	assert_true(b.is_broken(), "4 pickaxe hits break it")
	assert_true(GameState.is_depleted("pebble_boulder"), "persistently broken")
	assert_false(peb.get("pinned"), "Pebble tumbles out")
	assert_eq(GameState.count_item("stone"), 2, "a little stone from the boulder")
	await wait_seconds(3.4)
	assert_true(GameState.is_befriended("pebble"), "Pebble befriended")
	assert_eq(GameState.active_companion, "pebble")


# --- Commands & the one-follower rule -----------------------------------------------------------------------

func test_commands_and_one_follower_rule() -> void:
	var m := _make("mochi", "home", Vector3(-2, 0.05, 2))
	var p := _make("pebble", "home", Vector3(2, 0.05, 2))
	_befriend("mochi")
	_befriend("pebble")
	await wait_physics(2)
	assert_true(_cmd(m, "follow")["ok"])
	assert_eq(GameState.active_companion, "mochi")
	assert_eq(m.get("mode"), "follow")
	_cmd(p, "follow")
	assert_eq(GameState.active_companion, "pebble", "new follower")
	assert_eq(String(GameState.companion("mochi")["assignment"]), "home", "previous follower goes home")
	assert_eq(m.get("mode"), "home", "and its node walks home")
	_cmd(p, "wait")
	assert_eq(String(GameState.companion("pebble")["assignment"]), "wait")
	assert_eq(GameState.active_companion, "", "nobody follows while waiting")
	var wp: Variant = GameState.companion("pebble")["wait_pos"]
	assert_true(wp is Array and wp.size() == 3, "wait position saved")
	assert_eq(p.get("mode"), "wait")
	_cmd(p, "home")
	assert_eq(String(GameState.companion("pebble")["assignment"]), "home")
	# Debounce: a second toggle in the same instant (player + another system) is ignored.
	p.set("_last_command_ms", -100000)
	assert_true(p.command("follow")["ok"])
	assert_false(p.command("wait")["ok"], "double press debounced")
	assert_eq(GameState.active_companion, "pebble")


func test_commands_require_befriending() -> void:
	var m := _make("mochi", "wild", Vector3(0, 0.05, 3))
	assert_false(_cmd(m, "follow")["ok"])
	assert_eq(GameState.active_companion, "")


func test_pet_and_feed_once_per_day() -> void:
	var m := _make("mochi", "home", Vector3(0, 0.05, 3))
	_befriend("mochi")
	assert_eq(int(_cmd(m, "pet")["bond"]), 5)
	assert_eq(int(_cmd(m, "pet")["bond"]), 0, "just a happy wiggle the second time")
	assert_eq(int(GameState.companion("mochi")["bond_xp"]), 5)
	GameState.total_minutes += 1440.0
	assert_eq(int(_cmd(m, "pet")["bond"]), 5, "a new day")
	var r := _cmd(m, "feed")
	assert_false(r["ok"], "no berries yet")
	assert_eq(r["text"], "no_food")
	GameState.give_item("berries", 2)
	r = _cmd(m, "feed")
	assert_true(r["ok"])
	assert_eq(int(r["bond"]), 8)
	assert_eq(GameState.count_item("berries"), 1, "one favourite food eaten")
	r = _cmd(m, "feed")
	assert_eq(r["text"], "full", "once per day")
	assert_eq(GameState.count_item("berries"), 1, "not wasted when full")
	assert_eq(int(GameState.companion("mochi")["bond_xp"]), 18)


# --- Following, refusal, recovery ------------------------------------------------------------------------------

func test_mochi_refuses_at_the_mine_threshold() -> void:
	var th := Vector3(0, 0.05, -12)
	var m := _make("mochi", "follow", Vector3(1, 0.05, 2), {"threshold": th})
	_befriend("mochi", "follow")
	player.global_position = Vector3(0, 0.05, -5)
	await wait_physics(3)
	assert_eq(m.get_state(), "refuse", "stops and trembles near the mine")
	assert_true(_said_contains("mine's mouth"), "refuse line")
	await wait_seconds(5.8)
	assert_eq(String(GameState.companion("mochi")["assignment"]), "wait", "waits at the threshold")
	assert_eq(GameState.active_companion, "")
	var wp: Array = GameState.companion("mochi")["wait_pos"]
	assert_true(Vector2(wp[0] - th.x, wp[2] - th.z).length() < 0.5, "right at the threshold spot")
	# Called again right away (same approach): follows without refusing again.
	_cmd(m, "follow")
	await wait_physics(3)
	assert_eq(m.get_state(), "follow", "only once per approach")


func test_mochi_does_not_refuse_when_coming_back_out() -> void:
	# Krystal is already standing by the mine when Mochi (re)appears: she's leaving, not entering.
	player.global_position = Vector3(0, 0.05, -10)
	var th := Vector3(0, 0.05, -12)
	var m := _make("mochi", "reunite", Vector3(1, 0.05, -11), {"threshold": th, "wait": Vector3(1, 0.05, -11)})
	_befriend("mochi", "follow")
	await wait_seconds(1.5)
	assert_eq(m.get_state(), "follow", "rejoined and stays with Krystal")
	assert_eq(GameState.active_companion, "mochi")
	assert_true(_said_contains("relieved"), "reunite line")
	# Walking away and coming back later is a new approach: she refuses again.
	player.global_position = Vector3(0, 0.05, 10)
	await wait_physics(3)
	player.global_position = Vector3(0, 0.05, -6)
	await wait_physics(3)
	assert_eq(m.get_state(), "refuse")


func test_brave_companions_do_not_refuse() -> void:
	var p := _make("pebble", "follow", Vector3(1, 0.05, 2), {"threshold": Vector3(0, 0.05, -12)})
	_befriend("pebble", "follow")
	player.global_position = Vector3(0, 0.05, -10)
	await wait_physics(4)
	assert_ne(p.get_state(), "refuse")


func test_stuck_recovery_teleports_near_krystal() -> void:
	var m := _make("mochi", "follow", Vector3(0, 0.05, 0))
	_befriend("mochi", "follow")
	player.global_position = Vector3(30, 0.05, 0)
	await wait_physics(3)
	var d: float = m.global_position.distance_to(player.global_position)
	assert_true(d < 4.0, "recovered next to Krystal (was 30 m away, now %.1f)" % d)
	assert_true(m.global_position.y > -0.5 and m.global_position.y < 1.0, "on the ground")


func test_follower_keeps_up() -> void:
	var m := _make("mochi", "follow", Vector3(0, 0.05, 8))
	_befriend("mochi", "follow")
	for i in 90:
		player.global_position += Vector3(0, 0, -4.0 / 60.0)
		await wait_physics(1)
	var d: float = m.global_position.distance_to(player.global_position)
	assert_true(d < 4.5 and d > 0.8, "trails a little behind Krystal (%.2f m)" % d)
	assert_true(m.global_position.z > player.global_position.z, "behind, not in front")


# --- Bond from adventures & work ---------------------------------------------------------------------------------

func test_zone_bond_through_events() -> void:
	var m := _make("mochi", "follow", Vector3(0, 0.05, 4))
	_befriend("mochi", "follow")
	Events.zone_entered.emit("glade")
	Events.zone_entered.emit("glade")
	assert_eq(int(GameState.companion("mochi")["bond_xp"]), 3, "+3 first time only")
	m.command("wait")
	Events.zone_entered.emit("quarry")
	assert_eq(int(GameState.companion("mochi")["bond_xp"]), 3, "only while adventuring together")


func test_pebble_mining_assist() -> void:
	var p := _make("pebble", "follow", Vector3(0, 0.05, 4))
	_befriend("pebble", "follow")
	await wait_physics(2)
	Events.harvested.emit("rock", "stone", 1, Vector3(0.5, 0.3, 5.0))
	assert_eq(p.get_state(), "working", "runs over to help")
	await wait_seconds(2.5)
	assert_eq(GameState.count_item("stone"), 1, "headbutt: +1 stone")
	assert_eq(int(GameState.companion("pebble")["bond_xp"]), 1, "+1 bond for working together")
	Events.harvested.emit("rock", "stone", 1, Vector3(0.5, 0.3, 5.0))
	assert_ne(p.get_state(), "working", "cooldown between assists")
	Events.harvested.emit("tree", "wood", 1, Vector3(0.5, 0.3, 5.0))
	assert_ne(p.get_state(), "working", "only rocks and ore")


func test_pebble_assist_reaches_solid_rock() -> void:
	# Real quarry rocks are solid ~1 m bodies: Pebble can't reach their centre, bumping counts.
	var p := _make("pebble", "follow", Vector3(0, 0.05, 5.5))
	_befriend("pebble", "follow")
	var rock := StaticBody3D.new()
	rock.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	cs.shape = sph
	rock.add_child(cs)
	add_child(rock)
	nodes.append(rock)
	rock.global_position = Vector3(0, 0.6, 2.5)
	await wait_physics(2)
	Events.harvested.emit("ore", "copper_ore", 2, rock.global_position)
	await wait_seconds(3.0)
	assert_eq(GameState.count_item("copper_ore"), 1, "headbutted the solid rock: +1 ore")
	assert_ne(p.get_state(), "working", "and got back to following")


func test_mochi_forages_nearby_bush() -> void:
	var m := _make("mochi", "follow", Vector3(0, 0.05, 4))
	_befriend("mochi", "follow")
	var bush := FakeBush.new()
	add_child(bush)
	nodes.append(bush)
	bush.global_position = Vector3(1.5, 0.0, 4.5)
	await wait_physics(2)
	m.set("_ability_t", 0.0)
	await wait_physics(2)
	assert_eq(m.get_state(), "working", "trots to the bush")
	await wait_seconds(3.0)
	var got := GameState.count_item("berries")
	assert_true(got >= 1 and got <= 2, "found 1-2 berries (%d)" % got)


func _fill_backpack() -> void:
	for i in GameState.INVENTORY_SIZE:
		GameState.inventory.set_slot(i, {"id": "wood", "count": 99})


func _forage_bush() -> Node3D:
	var bush := FakeBush.new()
	add_child(bush)
	nodes.append(bush)
	bush.global_position = Vector3(1.5, 0.0, 4.5)
	return bush


func test_mochi_does_not_forage_into_a_full_backpack() -> void:
	# Regression: every forage used to spill a new persistent pickup + a "Backpack full!" toast & sound.
	_fill_backpack()
	var m := _make("mochi", "follow", Vector3(0, 0.05, 4))
	_befriend("mochi", "follow")
	_forage_bush()
	var toasts: Array = []
	var cb := func(text: String, _kind: String) -> void: toasts.append(text)
	Events.notify.connect(cb)
	await wait_physics(2)
	var trips := 0
	for r in 3:
		m.set("_ability_t", 0.0)
		await wait_physics(2)
		if m.get_state() == "working":
			trips += 1
		await wait_seconds(0.4)
	Events.notify.disconnect(cb)
	assert_eq(trips, 0, "no trips to the bush with no room to carry anything")
	assert_eq(GameState.dropped.size(), 0, "no pickups spilled on the ground")
	var full := toasts.filter(func(t: Variant) -> bool: return String(t).begins_with("Backpack full"))
	assert_eq(full.size(), 0, "no 'Backpack full!' toasts")
	var lines := said.filter(func(s: Variant) -> bool: return String(s[1]).contains("backpack is full"))
	assert_true(lines.size() <= 1, "mentions the full backpack at most once (%d)" % lines.size())


func test_mochi_brings_fiber_when_only_fiber_fits() -> void:
	_fill_backpack()
	GameState.inventory.set_slot(0, {"id": "berries", "count": ItemDB.stack_max("berries")})
	GameState.inventory.set_slot(1, {"id": "fiber", "count": 10})
	assert_eq(GameState.inventory.space_for("berries"), 0, "no room for berries")
	var m := _make("mochi", "follow", Vector3(0, 0.05, 4))
	_befriend("mochi", "follow")
	_forage_bush()
	await wait_physics(2)
	m.set("_ability_t", 0.0)
	await wait_physics(2)
	assert_eq(m.get_state(), "working", "still trots to the bush")
	await wait_seconds(3.0)
	assert_eq(GameState.count_item("berries"), ItemDB.stack_max("berries"), "no berries forced in")
	var f := GameState.count_item("fiber")
	assert_true(f >= 11 and f <= 12, "brought 1-2 fiber instead (%d)" % f)
	assert_eq(GameState.dropped.size(), 0, "nothing spilled")


func test_mochi_forage_backpack_filled_on_the_way() -> void:
	var m := _make("mochi", "follow", Vector3(0, 0.05, 4))
	_befriend("mochi", "follow")
	_forage_bush()
	await wait_physics(2)
	m.set("_ability_t", 0.0)
	await wait_physics(2)
	assert_eq(m.get_state(), "working", "trots to the bush")
	_fill_backpack()                       # Krystal stuffs the backpack meanwhile
	await wait_seconds(3.0)
	assert_eq(GameState.count_item("berries"), 0, "nothing to hand over")
	assert_eq(GameState.dropped.size(), 0, "and nothing spilled on the ground")
	assert_ne(m.get_state(), "working", "back to following")


func test_mochi_tends_crops_at_home() -> void:
	var m := _make("mochi", "home", Vector3(0, 0.05, 9))
	_befriend("mochi")
	var uid := GameState.add_structure("crop_plot", Vector3(1.5, 0.0, 10.5), 0.0)
	GameState.crops[uid] = {"crop": "sweetroot", "planted_at": GameState.total_minutes, "tended_minutes": 0.0}
	await wait_physics(2)
	m.set("_ability_t", 0.0)
	await wait_physics(2)
	assert_eq(m.get_state(), "working")
	await wait_seconds(3.5)
	assert_almost(float(GameState.crops[uid]["tended_minutes"]), 30.0, 0.01, "tended 30 minutes")


func test_pebble_daily_gift() -> void:
	var p := _make("pebble", "follow", Vector3(0, 0.05, 4.5))
	_befriend("pebble", "follow")
	await wait_physics(2)
	p.set("_gift_timer", 60.0)
	await wait_seconds(3.0)
	assert_eq(GameState.count_item("shiny_pebble"), 1, "a Shiny Pebble gift")
	assert_eq(int(GameState.companion("pebble")["last_gift_day"]), GameState.day())
	p.set("_gift_timer", 60.0)
	await wait_seconds(2.0)
	assert_eq(GameState.count_item("shiny_pebble"), 1, "only once per day")


# --- Threats & reactions ----------------------------------------------------------------------------------------------

func test_notice_threat_and_react() -> void:
	var l := _make("lumi", "follow", Vector3(1, 0.05, 4))
	_befriend("lumi", "follow")
	await wait_physics(2)
	l.notice_threat(Vector3(0, 0, -8))
	assert_eq(l.get_state(), "notice", "Lumi freezes and stares")
	assert_false(l.is_light_active(), "and dims")
	await wait_seconds(1.7)
	assert_eq(l.get_state(), "follow", "then stays close behind Krystal")
	var reactions: Array = []
	var cb := func(id: String, r: String) -> void: reactions.append([id, r])
	Events.companion_reaction.connect(cb)
	l.react("celebrate")
	assert_eq(l.get_state(), "celebrate")
	l.react("happy")
	Events.companion_reaction.disconnect(cb)
	assert_eq(reactions.size(), 2, "reactions are broadcast for the UI")
	var m := _make("mochi", "home", Vector3(-1, 0.05, 4))
	_befriend("mochi")
	m.notice_threat(Vector3(0, 0, -8))
	assert_eq(m.get_state(), "afraid", "Mochi hides instead")


func test_home_command_below_leaves_safely() -> void:
	Game.area_id = "below"
	var p := _make("pebble", "follow", Vector3(1, 0.05, 4))
	_befriend("pebble", "follow")
	_cmd(p, "home")
	assert_eq(p.get_state(), "leaving")
	await wait_seconds(2.6)
	assert_false(is_instance_valid(p), "poofed off home")
	assert_false(Game.companion_nodes.has("pebble"))
	assert_eq(String(GameState.companion("pebble")["assignment"]), "home")


# --- Spawner -------------------------------------------------------------------------------------------------------------

func _make_area() -> Node3D:
	var area: Node3D = AreaBase.new()
	add_child(area)
	nodes.append(area)
	for i in 3:
		var id: String = ["mochi", "pebble", "lumi"][i]
		area.register_spawn("companion_wild_" + id, Transform3D(Basis.IDENTITY, Vector3(-6 + i * 6, 0.05, -6)))
		area.register_spawn("companion_home_" + id, Transform3D(Basis.IDENTITY, Vector3(-3 + i * 3, 0.05, 10)))
	area.register_spawn("mine_threshold", Transform3D(Basis.IDENTITY, Vector3(15, 0.05, 15)))
	return area


func test_spawner_surface_fresh_game() -> void:
	var area := _make_area()
	GameState.player["spawn"] = "haven_start"
	var out: Dictionary = Spawner.spawn_for_area(area, "surface", player)
	for id in out:
		nodes.append(out[id])
	assert_eq(out.size(), 3, "three wild creatures")
	var boulder := area.get_node_or_null("PebbleBoulder")
	assert_not_null(boulder, "boulder spawned at Pebble's wild spot")
	assert_true(out["pebble"].get("pinned"))
	assert_eq(out["mochi"].get_state(), "wild")
	assert_true((out["lumi"] as Node3D).global_position.distance_to(Vector3(6, 0.05, -6)) < 0.5, "at companion_wild_lumi")


func test_spawner_follower_beside_krystal_and_below_rules() -> void:
	var area := _make_area()
	_befriend("mochi", "follow")
	_befriend("pebble", "home")
	GameState.deplete("pebble_boulder", -1.0)
	player.global_position = Vector3(0, 0.05, 0)
	var out: Dictionary = Spawner.spawn_for_area(area, "surface", player)
	for id in out:
		nodes.append(out[id])
	var d: float = (out["mochi"] as Node3D).global_position.distance_to(player.global_position)
	assert_true(d < 4.0, "follower appears beside Krystal (%.2f)" % d)
	assert_eq(out["pebble"].get_state(), "home")
	assert_null(area.get_node_or_null("PebbleBoulder"), "no boulder once broken")
	# Into the Below with Mochi: she stays at the surface threshold instead.
	var below := _make_area()
	var out2: Dictionary = Spawner.spawn_for_area(below, "below", player)
	for id in out2:
		nodes.append(out2[id])
	assert_eq(out2.size(), 0, "Mochi never comes below")
	assert_eq(String(GameState.companion("mochi")["assignment"]), "wait")
	assert_eq(String(GameState.companion("mochi")["wait_area"]), "surface")
	# Back out through the mine exit: she rejoins.
	GameState.player["spawn"] = "mine_exit"
	var surf := _make_area()
	surf.register_spawn("mine_threshold", Transform3D(Basis.IDENTITY, Vector3(50, 0.05, -66)))
	var out3: Dictionary = Spawner.spawn_for_area(surf, "surface", player)
	for id in out3:
		nodes.append(out3[id])
	assert_eq(out3["mochi"].get_state(), "reunite", "bounces over to Krystal")
	assert_eq(GameState.active_companion, "mochi")


func test_spawner_below_keeps_a_waiting_companion() -> void:
	var area := _make_area()
	_befriend("pebble", "follow")
	_befriend("lumi")
	GameState.set_companion_assignment("lumi", "wait", "below", Vector3(4, 0.05, 3))
	player.global_position = Vector3(0, 0.05, 0)
	var out: Dictionary = Spawner.spawn_for_area(area, "below", player)
	for id in out:
		nodes.append(out[id])
	assert_true(out.has("pebble"), "the follower comes along")
	assert_true(out.has("lumi"), "Lumi is still waiting where Krystal left her")
	assert_eq(out["lumi"].get_state(), "wait")
	var d: float = (out["lumi"] as Node3D).global_position.distance_to(Vector3(4, 0.05, 3))
	assert_true(d < 0.5, "at her wait spot (%.2f m away)" % d)
	assert_false(out.has("mochi"), "Mochi never appears below")


func test_teleport_near_carries_only_the_follower() -> void:
	# Regression: the Below's lift calls teleport_near() on every companion node. The one told to
	# wait used to pop out beside Krystal and trudge back toward a spot 170 m away through rock.
	var spot := Vector3(-12, 0.05, -10)
	var p := _make("pebble", "wait", spot, {"wait": spot})
	_befriend("pebble")
	GameState.set_companion_assignment("pebble", "wait", "", spot)
	var m := _make("mochi", "follow", Vector3(2, 0.05, 6))
	_befriend("mochi", "follow")
	await wait_physics(2)
	var target := Vector3(30, 0.05, 20)
	player.global_position = target
	p.teleport_near(target)
	m.teleport_near(target)
	var dp: float = p.global_position.distance_to(spot)
	assert_true(dp < 0.5, "the waiting companion stays at its spot (%.1f m away)" % dp)
	assert_eq(p.get_state(), "wait", "still waiting")
	var dm: float = m.global_position.distance_to(target)
	assert_true(dm < 4.0, "the follower rides along (%.1f m from Krystal)" % dm)


func test_waiting_companion_slips_back_to_its_spot() -> void:
	# Knocked far off its spot (e.g. by a physics push): the one told to wait must end up back at
	# its spot, not wander off or get stuck walking back.
	var spot := Vector3(0, 0.05, -10)
	var p := _make("pebble", "wait", spot, {"wait": spot})
	_befriend("pebble")
	GameState.set_companion_assignment("pebble", "wait", "", spot)
	await wait_physics(2)
	p.global_position = Vector3(25, 0.05, 20)
	await wait_seconds(1.6)
	var d: float = p.global_position.distance_to(spot)
	assert_true(d < 1.5, "back at the wait spot (%.2f m away)" % d)
	assert_eq(p.get_state(), "wait", "still waiting")


func test_afraid_follower_is_never_left_behind() -> void:
	var m := _make("mochi", "follow", Vector3(1, 0.05, 5))
	_befriend("mochi", "follow")
	await wait_physics(2)
	m.react("scared")
	m.set("_override_t", 60.0)      # a Brambling keeps chasing Krystal: Mochi stays frightened
	assert_eq(m.get_state(), "afraid")
	player.global_position = Vector3(40, 0.05, 6)
	await wait_physics(3)
	var d: float = m.global_position.distance_to(player.global_position)
	assert_true(d < 5.0, "caught up with Krystal while still frightened (%.1f m)" % d)


func test_pebble_charges_ground_enemies_only() -> void:
	var p := _make("pebble", "follow", Vector3(1, 0.05, 7))
	_befriend("pebble", "follow")
	var e := FakeEnemy.new()
	add_child(e)
	nodes.append(e)
	e.global_position = player.global_position + Vector3(0, 5.0, -2.5)    # up on the ceiling
	await wait_physics(2)
	p.set("_charge_cd", 0.0)
	await wait_seconds(1.2)
	assert_ne(p.get_state(), "charge", "no charging at something on the ceiling")
	assert_almost(float(e.health.hp), 20.0, 0.001, "and no bonk on thin air")
	e.global_position = player.global_position + Vector3(0, 0.0, -2.5)    # it drops to the floor
	p.set("_charge_cd", 0.0)
	var saw_charge := false
	for i in 150:
		await wait_physics(1)
		if p.get_state() == "charge":
			saw_charge = true
		if float(e.health.hp) < 20.0:
			break
	assert_true(saw_charge, "brave Pebble charges an enemy on the ground")
	assert_almost(float(e.health.hp), 18.0, 0.001, "a comic 2 damage")
	assert_eq(p.get_state(), "dizzy", "then sees stars")


func test_leaving_the_below_cannot_be_interrupted() -> void:
	# Sent home in the Below; a stalker/boss notice or a reaction arrives while it's leaving.
	Game.area_id = "below"
	var p := _make("pebble", "follow", Vector3(1, 0.05, 4))
	_befriend("pebble", "follow")
	await wait_physics(2)
	_cmd(p, "home")
	assert_eq(p.get_state(), "leaving")
	await wait_seconds(0.5)
	p.notice_threat(Vector3(0, 0, -8))
	p.react("scared")
	p.react("celebrate")
	assert_eq(p.get_state(), "leaving", "not replaced by a notice / reaction")
	await wait_seconds(2.3)
	assert_false(is_instance_valid(p), "still poofed off home (never stranded below in home mode)")
	assert_false(Game.companion_nodes.has("pebble"))


func test_a_defeated_enemy_freed_mid_scan_is_harmless() -> void:
	# Enemies are freed after their defeat animation; the threat scan's shared cache can still hold
	# them for a moment. That must never raise a script error (the runner fails on any).
	var l := _make("lumi", "follow", Vector3(1, 0.05, 5))
	_befriend("lumi", "follow")
	var e := FakeEnemy.new()
	add_child(e)
	e.global_position = Vector3(0, 0.05, -2)
	await wait_seconds(0.6)            # scanned and cached
	assert_eq(l.get_state(), "notice", "Lumi noticed it")
	l.call("_scan_threats")            # fresh cache holding the enemy (e.g. a new area's follower scans at once)
	e.free()
	l.call("_scan_threats")            # same cache, now holding a freed enemy
	await wait_seconds(0.6)
	assert_true(is_instance_valid(l), "Lumi carries on")
