extends RefCounted
## Combat and support of ONE companion node (owned by companion.gd as `combat`; MP §6, spec §9):
##  * Basic attack against enemies Krystal is fighting or that go for her (never a peaceful group, never a
##    stalker, dummy, invulnerable or refusing target: can_be_hit_by / health.invulnerable), only with line of
##    sight (world|structure), within reach of Krystal (ENGAGE_RADIUS, Stay close: CLOSE_RADIUS) and roughly
##    on the pet's level. The damage happens on the attack animation's impact frame (action_event): Mochi and
##    Lumi launch a projectile (src/combat/projectile.gd, shared & pooled; LOS-checked every tick), Pebble
##    resolves its headbutt against the target only (reach + LOS re-checked at the impact).
##  * Signature skill with ONE cooldown per companion (companion_support.gd: GameState "skill_ready_at" on the
##    play_seconds timeline) shared by the autocast and the manual Companion Skill action.
##    Bloomguard: heal-over-time ticked here (Krystal's health.heal, which applies Stats.heal_mult itself);
##    Stoneheart: health.add_shield (+ a brief stagger of ordinary enemies, never bosses / elites);
##    Glimmerstep: GameState.add_buff("glimmerstep") (+ "sprint_saver" perk) and a short light pulse that
##    exposes light-fearing enemies (a temporary light_source; enemies may also implement expose(seconds)).
##  * Everything ticks from the companion's _physics_process, so pause freezes it; nothing allocates per frame
##    except on the (throttled) scan.
## Settings: companion_auto_attack (off = support only), companion_autocast.

const Logic := preload("res://src/companions/companion_logic.gd")
const Support := preload("res://src/companions/companion_support.gd")
const Fx := preload("res://src/companions/companion_fx.gd")
const SkillsData := preload("res://data/companion_skills.gd")
const COMBAT_SCRIPT := "res://src/combat/combat.gd"
const PROJECTILE_SCRIPT := "res://src/combat/projectile.gd"
const HITFX_SCRIPT := "res://src/combat/hit_fx.gd"

const ENGAGE_RADIUS := 12.0           # Assist: enemies this close to Krystal
const CLOSE_RADIUS := 4.0             # Stay close: only enemies right at Krystal
const ATTACK_LEASH := 9.0             # a pet that walks to its target never goes farther than this from Krystal
const ENGAGED_MEMORY_MS := 4000       # an enemy that fought Krystal stays a target this long (stunned, flinching)
const MELEE_MAX_DY := 1.6
const PROJECTILE_MAX_DY := 3.0
const LOS_REFRESH := 0.3
const HOT_TICK := 0.5
const STAGGER_RADIUS := 4.0
const THREAT_NEAR := 6.0
const MAX_CANDIDATES := 12
const ATTACK_ACTIONS := {"mochi": "spore_puff", "pebble": "stone_bump", "lumi": "light_bolt"}
const PROJECTILE_LOOK := {
	"mochi": {"color": Color("f7c6d0"), "radius": 0.13, "kind": "spore", "light": false},
	"lumi": {"color": Color("ffe39a"), "radius": 0.11, "kind": "light_bolt", "light": true},
}
const CAST_ACTION := "cast"
const MELEE_KNOCKBACK := 2.5
const UNREACHABLE_MS := 5000

var c: Node3D                         # the companion (companion.gd)
var id: String = ""
var target: Node3D = null
var hot: Dictionary = {}              # {"total", "duration", "elapsed"} while Bloomguard heals
var attacks_fired: int = 0            # impact frames resolved (tests / telemetry)
var last_skill_result: Dictionary = {}

var _engaged: Dictionary = {}         # enemy instance id -> msec last seen fighting Krystal
var _unreachable: Dictionary = {}     # enemy instance id -> msec until it may be picked again
var _attack_cd: float = 1.2
var _pending: Dictionary = {}         # {"action", "target", "t"} between the attack start and its impact frame
var _los_ok: bool = false
var _los_t: float = 0.0
var _autocast_t: float = 1.5
var _ready_t: float = 0.0
var _was_cooling: bool = false
var _pulse: Node3D = null
var _pulse_t: float = 0.0
var _combat_s: Script = null
var _projectile_s: Script = null
var _hitfx_s: Script = null


## A short-lived light (Glimmerstep's pulse): joins group "light_source" while active so Combat.light_at
## (and through it the Gloomlings' exposure) sees it.
class PulseLight extends Node3D:
	var light_radius: float = 6.0
	var light_strength: float = 1.0
	var _on: bool = false

	func set_on(on: bool) -> void:
		_on = on
		if on and not is_in_group("light_source"):
			add_to_group("light_source")
		elif not on and is_in_group("light_source"):
			remove_from_group("light_source")

	func is_light_active() -> bool:
		return _on


func _init(companion: Node3D, companion_id: String) -> void:
	c = companion
	id = companion_id
	_combat_s = _load_script(COMBAT_SCRIPT)
	_projectile_s = _load_script(PROJECTILE_SCRIPT)
	_hitfx_s = _load_script(HITFX_SCRIPT)
	_was_cooling = not Support.is_ready(id)


static func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var s: Variant = load(path)
	if s is Script and (s as Script).can_instantiate():
		return s
	return null


# --- Shared checks ----------------------------------------------------------------------------------------------

func _player() -> Node3D:
	var p: Variant = c.get("_player")
	return p if p is Node3D and is_instance_valid(p) else null


func is_follower() -> bool:
	return String(c.get("mode")) == "follow" and GameState.active_companion == id and GameState.is_befriended(id)


## Follower, same area, within the presence range of Krystal (support and passives need this, MP 6.1).
func is_present() -> bool:
	if not is_follower() or not c.is_inside_tree():
		return false
	var p := _player()
	return p != null and p.is_inside_tree() and c.global_position.distance_to(p.global_position) <= SkillsData.PRESENCE_RANGE


func player_health() -> Node:
	var p := _player()
	if p == null:
		return null
	return find_health(p)


func find_health(n: Object) -> Node:
	if _combat_s != null:
		return _combat_s.call("find_health", n)
	if n == null or not is_instance_valid(n):
		return null
	var h: Variant = n.get("health")
	return h if h is Node and is_instance_valid(h) and (h as Node).has_method("apply_damage") else null


static func enemy_info(e: Node) -> Dictionary:
	var d: Variant = e.get("data")
	if d is Dictionary and not (d as Dictionary).is_empty():
		return d
	var eid: Variant = e.get("enemy_id")
	if eid is String and String(eid) != "":
		return ItemDB.enemy(String(eid))
	return {}


static func is_dummy(e: Node) -> bool:
	if e.is_in_group("dummy") or e.is_in_group("practice_dummy"):
		return true
	var v: Variant = e.get("is_dummy")
	return v is bool and v


## Whether this companion may hit `e` right now (alive, a real enemy, not armoured / refusing, not a dummy).
func can_target(e: Variant) -> bool:
	if not c.call("_enemy_alive", e):
		return false
	var n: Node3D = e
	if n.is_in_group("stalker") or is_dummy(n):
		return false
	var h := find_health(n)
	if h == null or bool(h.get("invulnerable")):
		return false
	if n.has_method("can_be_hit_by") and not _truthy(n.call("can_be_hit_by", c)):
		return false
	return true


func _engaged_now(e: Node3D) -> bool:
	if e.has_method("is_threatening") and _truthy(e.call("is_threatening")):
		return true
	var st: Variant = e.get("state")
	if st is String and String(st) in ["idle", "wander", "return", "dead"]:
		return false
	return Time.get_ticks_msec() - int(_engaged.get(e.get_instance_id(), -100000)) < ENGAGED_MEMORY_MS


static func _attacking_now(e: Node3D) -> bool:
	var st: Variant = e.get("state")
	return st is String and String(st) in ["telegraph", "attack"]


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return false


func _space() -> PhysicsDirectSpaceState3D:
	return c.get_world_3d().direct_space_state if c.is_inside_tree() else null


func attack_origin() -> Vector3:
	return c.global_position + Vector3.UP * 0.45


func aim_point(t: Node3D) -> Vector3:
	if _combat_s != null:
		return _combat_s.call("aim_point", t)
	return t.global_position + Vector3.UP * 0.8


func has_los(t: Node3D) -> bool:
	var space := _space()
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(attack_origin(), aim_point(t), 1 | 32)
	var ex: Array[RID] = []
	if c is CollisionObject3D:
		ex.append((c as CollisionObject3D).get_rid())
	if t is CollisionObject3D:
		ex.append((t as CollisionObject3D).get_rid())
	q.exclude = ex
	return space.intersect_ray(q).is_empty()


func _basic() -> Dictionary:
	return Support.basic(id)


func is_melee() -> bool:
	return String(_basic().get("kind", "")) == "melee"


func attack_range() -> float:
	return float(_basic().get("range", 2.0))


func mode() -> String:
	return Support.mode(id)


# --- Target scan (on the companion's 0.45 s threat-scan cadence) --------------------------------------------------

## Remembers who is fighting Krystal and picks the basic-attack target. `enemies`: the companion's shared
## enemy cache (may hold freed entries).
func scan(enemies: Array) -> void:
	var p := _player()
	var now := Time.get_ticks_msec()
	if _engaged.size() > 64:
		_engaged.clear()
	if _unreachable.size() > 32:
		_unreachable.clear()
	for e in enemies:
		if c.call("_enemy_alive", e) and (e as Node3D).has_method("is_threatening") and _truthy((e as Node3D).call("is_threatening")):
			_engaged[(e as Node3D).get_instance_id()] = now
	if p == null or not is_follower() or not Support.auto_attack():
		_drop_target()
		return
	# Keep a good current target (stable, no flicker between two enemies).
	if target != null and _target_still_valid(target, p):
		return
	_drop_target()
	var cands: Array = []
	var nodes: Array = []
	var ppos := p.global_position
	for e in enemies:
		if nodes.size() >= MAX_CANDIDATES:
			break
		if not c.call("_enemy_alive", e):
			continue
		var e3: Node3D = e
		if e3.global_position.distance_to(ppos) > ENGAGE_RADIUS + 2.0:
			continue
		if int(_unreachable.get(e3.get_instance_id(), 0)) > now:
			continue
		nodes.append(e3)
		cands.append({"pos": e3.global_position, "engaged": _engaged_now(e3), "attacking": _attacking_now(e3), "valid": can_target(e3)})
	var close := mode() == "close"
	var opts := {"range": attack_range(), "max_dy": MELEE_MAX_DY if is_melee() else PROJECTILE_MAX_DY,
		"engage_radius": ENGAGE_RADIUS, "close": close, "close_radius": CLOSE_RADIUS, "melee": is_melee()}
	# At most two line-of-sight rays per scan: the best candidate, then the next best.
	for attempt in 2:
		var i := Logic.pick_attack_target(c.global_position, ppos, cands, opts)
		if i < 0:
			return
		if has_los(nodes[i]):
			target = nodes[i]
			_los_ok = true
			_los_t = LOS_REFRESH
			return
		cands[i]["valid"] = false


## Pebble's old brave opener (the comic 2-damage charge) follows the same rules as the basic attack.
func may_charge(t: Node3D) -> bool:
	return Support.auto_attack() and mode() == "assist" and can_target(t) and has_los(t)


func _target_still_valid(t: Node3D, p: Node3D) -> bool:
	if not can_target(t) or not _engaged_now(t):
		return false
	var radius := CLOSE_RADIUS + 1.0 if mode() == "close" else ENGAGE_RADIUS + 1.0
	if t.global_position.distance_to(p.global_position) > radius:
		return false
	var max_dy := MELEE_MAX_DY if is_melee() else PROJECTILE_MAX_DY
	return absf(t.global_position.y - c.global_position.y) <= max_dy + 0.4


func _drop_target() -> void:
	target = null
	_los_ok = false
	if String(c.get("override")) == "attack":
		c.call("_clear_override")


## A melee pet could not get to its target: leave it alone for a while.
func give_up_target() -> void:
	if target != null and is_instance_valid(target):
		_unreachable[target.get_instance_id()] = Time.get_ticks_msec() + UNREACHABLE_MS
	_drop_target()


func has_target() -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree()


## Where a melee pet stands to strike: just in front of the target, on the side it comes from.
func melee_spot() -> Vector3:
	if not has_target():
		return c.global_position
	var tp := target.global_position
	var away := Vector3(c.global_position.x - tp.x, 0.0, c.global_position.z - tp.z)
	if away.length() < 0.05:
		away = Vector3.BACK
	var r := 0.55 + (float(target.get("hit_radius")) if (target.get("hit_radius") is float) else 0.45)
	return tp + away.normalized() * r


func within_reach(t: Node3D) -> bool:
	var flat := Vector3(t.global_position.x - c.global_position.x, 0.0, t.global_position.z - c.global_position.z).length()
	var tr: Variant = t.get("hit_radius")
	var rad: float = float(tr) if (tr is float or tr is int) else 0.45
	return flat <= attack_range() + rad and absf(t.global_position.y - c.global_position.y) <= MELEE_MAX_DY


## True while the melee approach should continue (target valid and Krystal close enough).
func approach_ok() -> bool:
	var p := _player()
	if p == null or not has_target() or not is_follower():
		return false
	var leash := CLOSE_RADIUS + 0.5 if mode() == "close" else ATTACK_LEASH
	if c.global_position.distance_to(p.global_position) > leash:
		return false
	return _target_still_valid(target, p)


# --- Per-frame tick ------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_tick_hot(delta)
	_tick_pulse(delta)
	_tick_pending(delta)
	_ready_t -= delta
	if _ready_t <= 0.0:
		_ready_t = 0.25
		_check_ready()
	if not is_follower():
		return
	_autocast_t -= delta
	if _autocast_t <= 0.0:
		_autocast_t = float(SkillsData.AUTOCAST.get("min_interval", 1.5))
		try_autocast()
	_try_attack(delta)


func _check_ready() -> void:
	var cooling := not Support.is_ready(id)
	if _was_cooling and not cooling and GameState.is_befriended(id):
		Events.companion_skill_ready.emit(id)
	_was_cooling = cooling


## States in which the pet may start an attack animation.
func _state_allows_attack() -> bool:
	var o := String(c.get("override"))
	if o == "":
		return true
	if o == "attack":
		return true
	# Mochi puffs spores from behind Krystal even while she shelters there.
	return o == "afraid" and not is_melee()


func _try_attack(delta: float) -> void:
	if not has_target():
		if target != null:
			_drop_target()
		return
	if not Support.auto_attack():
		_drop_target()
		return
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = LOS_REFRESH
		_los_ok = has_los(target)
	if not _pending.is_empty() or _attack_cd > 0.0 or not _state_allows_attack():
		return
	if is_melee():
		if within_reach(target) and _los_ok:
			_start_attack()
		elif String(c.get("override")) == "":
			c.call("begin_attack_approach")      # Stay close: approach_ok() keeps it at Krystal's side
		return
	var dist := c.global_position.distance_to(target.global_position)
	if dist <= attack_range() and _los_ok:
		_start_attack()


func _start_attack() -> void:
	var action := String(ATTACK_ACTIONS.get(id, ""))
	_attack_cd = float(_basic().get("interval", 2.4))
	c.call("_face_towards", target.global_position)
	var v: Variant = c.get("visual")
	var length := 0.0
	if v is Node and action != "":
		length = float((v as Node).call("play_action", action))
	if length <= 0.0:
		_pending = {"action": action, "target": target, "t": 0.0}
		_resolve_pending()
		return
	_pending = {"action": action, "target": target, "t": length + 0.1}
	Events.companion_attacked.emit(id, target)


func _tick_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	_pending["t"] = float(_pending["t"]) - delta
	var v: Variant = c.get("visual")
	# The animation was replaced before its impact frame (another reaction): no hit, try again soon.
	var still := v is Node and String((v as Node).call("get_action")) == String(_pending["action"])
	if float(_pending["t"]) <= 0.0 or not still:
		_pending = {}
		_attack_cd = minf(_attack_cd, 0.4)


## visual.action_event: resolves the hit on the attack's impact frame. Returns true when consumed.
func on_action(action_name: String) -> bool:
	if _pending.is_empty() or action_name != String(_pending.get("action", "")):
		return false
	_resolve_pending()
	return true


func _resolve_pending() -> void:
	var t: Variant = _pending.get("target")
	_pending = {}
	if not (t is Node3D) or not can_target(t):
		return
	attacks_fired += 1
	if is_melee():
		_melee_hit(t)
	else:
		_shoot(t)


func _melee_hit(t: Node3D) -> void:
	if not within_reach(t) or not has_los(t):
		return
	var dir := Vector3(t.global_position.x - c.global_position.x, 0.0, t.global_position.z - c.global_position.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var dealt := deliver(t, Support.basic_damage(id), dir, MELEE_KNOCKBACK)
	var ap := aim_point(t)
	Fx.chips(c.get_parent(), ap - dir * 0.3, Color("9a948a"), 5)
	if dealt > 0.0:
		c.call("_voice", "clack")


func _shoot(t: Node3D) -> void:
	var look: Dictionary = PROJECTILE_LOOK.get(id, {"color": Color("fff4e0"), "radius": 0.12, "kind": "companion", "light": false})
	var b := _basic()
	var from := attack_origin() + (aim_point(t) - attack_origin()).normalized() * 0.3
	var dmg := Support.basic_damage(id)
	if _projectile_s != null:
		var p: Variant = _projectile_s.call("fire", {"shooter": c, "from": from, "target": t, "damage": dmg,
			"speed": float(b.get("projectile_speed", 10.0)), "range": float(b.get("range", 9.0)) + 1.5,
			"radius": float(look["radius"]), "groups": ["enemy"], "color": look["color"], "light": bool(look["light"]),
			"kind": String(look["kind"]), "max_per_shooter": 2, "on_hit": _on_projectile_hit})
		if p == null:
			attacks_fired -= 1       # refused (too many projectiles in flight): no shot, no invisible hit
		return
	# No shared projectile script at all (older build): the puff lands at once (LOS was just checked).
	var dir := Vector3(t.global_position.x - c.global_position.x, 0.0, t.global_position.z - c.global_position.z)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	deliver(t, dmg, dir, 0.0)


func _on_projectile_hit(t: Node, dealt: float) -> void:
	if dealt > 0.0 and t is Node and is_instance_valid(t):
		_reward_hit(t)


## Applies companion damage to `t` (never through can_be_hit_by / armour): the combat conventions of
## combat.gd (apply_damage with the companion as the source, knockback, impact FX, on_hit_blocked). No hitstop
## or camera shake for companion hits (comfort). Returns the damage dealt.
func deliver(t: Node3D, dmg: float, dir: Vector3, knock: float) -> float:
	var h := find_health(t)
	if h == null or dmg <= 0.0:
		return 0.0
	var dealt := 0.0
	if not (t.has_method("can_be_hit_by") and not _truthy(t.call("can_be_hit_by", c))):
		dealt = float(h.call("apply_damage", dmg, c, dir))
	if dealt <= 0.0:
		if t.has_method("on_hit_blocked"):
			t.call("on_hit_blocked", c, dir)
		return 0.0
	if knock > 0.0 and t.has_method("knockback"):
		t.call("knockback", dir, knock)
	if _hitfx_s != null:
		var col: Variant = t.get("hit_color")
		_hitfx_s.call("impact", aim_point(t) - dir * 0.25, dealt, col if col is Color else Color(1.0, 0.93, 0.8))
	_reward_hit(t)
	return dealt


## Working together: +1 bond per landed hit on a real enemy, inside the shared daily work cap (never from
## dummies or blocked hits).
func _reward_hit(t: Node) -> void:
	# (A projectile may meet another enemy on its way: the stalker is never a source of bond either.)
	if is_dummy(t) or t.is_in_group("stalker") or not GameState.is_befriended(id):
		return
	var xp := Logic.work_bond(GameState.companion(id), GameState.day())
	if xp > 0:
		GameState.add_bond(id, xp)


# --- Signature skill ------------------------------------------------------------------------------------------------

## Can the signature skill be used now? {"ok", "reason", "skill"} (the reason is shown to Krystal).
func skill_check(manual: bool) -> Dictionary:
	var sig := Support.signature(id)
	var nm := String(ItemDB.creature(id).get("name", id.capitalize()))
	var sk := String(sig.get("name", "Skill"))
	var out := {"ok": false, "reason": "", "skill": String(sig.get("id", ""))}
	if sig.is_empty():
		out["reason"] = "%s has no special skill." % nm
		return out
	if not GameState.is_befriended(id) or not is_follower():
		out["reason"] = "%s needs to be following you." % nm
		return out
	if not is_present():
		out["reason"] = "%s is too far away." % nm
		return out
	if String(c.get("override")) in ["befriending", "leaving", "refuse", "brave"]:
		out["reason"] = "%s is busy right now." % nm
		return out
	var rem := Support.remaining(id)
	if rem > 0.0:
		out["reason"] = "%s is recharging (%d s)." % [sk, ceili(rem)]
		return out
	var h := player_health()
	if h != null and bool(h.get("dead")):
		out["reason"] = "Not right now."
		return out
	if String(sig.get("id", "")) == "bloomguard":
		if h == null:
			out["reason"] = "Nothing to heal."
			return out
		var missing := float(h.get("max_hp")) - float(h.get("hp"))
		if missing < 1.0:
			out["reason"] = "You're not hurt." if manual else "Not needed."
			return out
	out["ok"] = true
	return out


## Uses the signature skill (manual = the Companion Skill action / Friends panel; else autocast). One cooldown.
func use_skill(manual: bool) -> Dictionary:
	var r := skill_check(manual)
	last_skill_result = r
	if not bool(r["ok"]):
		return r
	var sig := Support.signature(id)
	Support.start_cooldown(id)
	_was_cooling = true
	match String(sig.get("id", "")):
		"bloomguard":
			_cast_bloomguard(sig)
		"stoneheart":
			_cast_stoneheart(sig)
		"glimmerstep":
			_cast_glimmerstep(sig)
	var v: Variant = c.get("visual")
	if v is Node:
		(v as Node).call("play_action", CAST_ACTION)
		(v as Node).call("show_emote", "sparkle", 1.4)
	c.call("_voice", "happy")
	c.call("_say", "skill", 2.6, manual)
	Events.companion_skill_used.emit(id, String(sig.get("id", "")))
	return r


func try_autocast() -> bool:
	if not Support.autocast() or not Support.is_ready(id) or not is_present():
		return false
	var sig := Support.signature(id)
	var ctx := _autocast_context(sig)
	if not Logic.should_autocast(sig, ctx):
		return false
	return bool(use_skill(false).get("ok", false))


func _autocast_context(sig: Dictionary) -> Dictionary:
	var h := player_health()
	var ratio := 1.0
	var missing := 0.0
	var shield := false
	if h != null:
		var mx := maxf(float(h.get("max_hp")), 1.0)
		ratio = float(h.get("hp")) / mx
		missing = mx - float(h.get("hp"))
		var s: Variant = h.get("shield")
		shield = (s is float or s is int) and float(s) > 0.0
	var threats := 0
	var attacking := false
	var shadow := false
	var p := _player()
	if p != null:
		var pulse_r := float(sig.get("pulse_radius", 6.0))
		for e in c.call("_enemies"):
			if not c.call("_enemy_alive", e):
				continue
			var e3: Node3D = e
			if not (e3.has_method("is_threatening") and _truthy(e3.call("is_threatening"))):
				continue
			var d := e3.global_position.distance_to(p.global_position)
			if d <= THREAT_NEAR:
				threats += 1
				if _attacking_now(e3):
					attacking = true
			if d <= pulse_r and bool(enemy_info(e3).get("light_fear", false)) and not e3.is_in_group("stalker"):
				shadow = true
	return {"hp_ratio": ratio, "missing_hp": missing, "hot_active": not hot.is_empty(), "shield_active": shield,
		"threats_near": threats, "attacking_near": attacking, "shadow_near": shadow}


func _cast_bloomguard(sig: Dictionary) -> void:
	hot = {"total": float(sig.get("heal", 18.0)), "duration": maxf(float(sig.get("duration", 6.0)), 0.1),
		"elapsed": 0.0, "applied": 0.0, "next": HOT_TICK}
	var p := _player()
	if p != null:
		Fx.sparkles(c.get_parent(), p.global_position + Vector3.UP * 0.9, 0.6, 14, Color(0.72, 1.0, 0.7))
	if int(sig.get("cleanse_slow", 0)) > 0:
		cleanse_slow()


## Mochi's 3-heart perk: clears one clinging web/root slow.
func cleanse_slow() -> bool:
	var p := _player()
	if p != null and p.has_method("cleanse_slow"):
		return _truthy(p.call("cleanse_slow"))
	if GameState.buffs.has("slow"):
		GameState.buffs.erase("slow")
		return true
	return false


func _tick_hot(delta: float) -> void:
	if hot.is_empty():
		return
	if not is_present():
		hot = {}                      # sent away mid-heal: support needs the companion beside Krystal
		return
	var after := minf(float(hot["elapsed"]) + delta, float(hot["duration"]))
	hot["elapsed"] = after
	if after < float(hot["next"]) and after < float(hot["duration"]):
		return
	# Heal the part since the last tick (telescoping: the ticks always add up to exactly `total`).
	var amount := Logic.hot_amount(float(hot["total"]), float(hot["duration"]), float(hot["applied"]), after)
	hot["applied"] = after
	hot["next"] = float(hot["next"]) + HOT_TICK
	var h := player_health()
	if h != null and amount > 0.0 and not bool(h.get("dead")):
		var healed := float(h.call("heal", amount))
		if healed > 0.0:
			Events.player_healed.emit(healed)
	if after >= float(hot["duration"]):
		hot = {}


func _cast_stoneheart(sig: Dictionary) -> void:
	var amount := float(sig.get("shield", 25.0))
	var secs := float(sig.get("duration", 6.0))
	var p := _player()
	if p != null:
		if p.has_method("add_shield"):
			p.call("add_shield", amount, secs, "stoneheart")
		else:
			var h := player_health()
			if h != null and h.has_method("add_shield"):
				h.call("add_shield", amount, secs, "stoneheart")
		if int(sig.get("resist_knockback", 0)) > 0 and p.has_method("add_knockback_resist"):
			p.call("add_knockback_resist", int(sig.get("resist_knockback", 1)), secs)
		Fx.chips(c.get_parent(), p.global_position + Vector3.UP * 0.6, Color("b9b2a6"), 10)
		stagger_near(p.global_position, float(sig.get("stagger", 0.8)), bool(sig.get("stagger_bosses", false)))


## Brief stagger of ordinary enemies fighting near Krystal. Bosses and elites never (no lock). Returns count.
func stagger_near(center: Vector3, seconds: float, bosses: bool = false) -> int:
	var n := 0
	if seconds <= 0.0:
		return 0
	for e in _fresh_enemies():
		if not can_target(e):
			continue
		var e3: Node3D = e
		if e3.global_position.distance_to(center) > STAGGER_RADIUS or not _engaged_now(e3):
			continue
		var info := enemy_info(e3)
		if not bosses and (bool(info.get("boss", false)) or bool(info.get("elite", false)) or e3.is_in_group("boss")):
			continue
		# Its own stagger rule (flinch immunity, armour...) decides whether it is eligible right now: no chains.
		if e3.has_method("can_stagger") and not _truthy(e3.call("can_stagger", 0.0, c)):
			continue
		if e3.has_method("stun"):
			e3.call("stun", seconds)
			n += 1
	return n


func _cast_glimmerstep(sig: Dictionary) -> void:
	var secs := float(sig.get("duration", 4.0))
	GameState.add_buff("glimmerstep", float(sig.get("move", 0.12)), secs)
	var save := float(sig.get("sprint_stamina_save", 0.0))
	if save > 0.0:
		GameState.add_buff("sprint_saver", clampf(1.0 - save, 0.0, 1.0), secs)
	var radius := float(sig.get("pulse_radius", 6.0))
	var expose := float(sig.get("expose_seconds", 3.0))
	_start_pulse(radius, expose)
	for e in _fresh_enemies():
		if not c.call("_enemy_alive", e):
			continue
		var e3: Node3D = e
		if e3.global_position.distance_to(c.global_position) <= radius and e3.has_method("expose"):
			e3.call("expose", expose)
	Fx.sparkles(c.get_parent(), c.global_position + Vector3.UP * 0.5, radius * 0.35, 18, Color(1.0, 0.92, 0.6))


## A cast is a one-off: read the enemy group now (the shared scan cache may be up to 0.4 s old).
func _fresh_enemies() -> Array:
	return c.get_tree().get_nodes_in_group("enemy") if c.is_inside_tree() else []


func _start_pulse(radius: float, seconds: float) -> void:
	if _pulse == null or not is_instance_valid(_pulse):
		_pulse = PulseLight.new()
		_pulse.name = "GlimmerPulse"
		c.add_child(_pulse)
		_pulse.position = Vector3.UP * 0.4
	_pulse.set("light_radius", radius)
	_pulse.call("set_on", true)
	_pulse_t = seconds


func pulse_active() -> bool:
	return _pulse != null and is_instance_valid(_pulse) and bool(_pulse.call("is_light_active"))


func _tick_pulse(delta: float) -> void:
	if _pulse_t <= 0.0:
		return
	_pulse_t -= delta
	if _pulse_t <= 0.0 and _pulse != null and is_instance_valid(_pulse):
		_pulse.call("set_on", false)


## Status for the UI: {"ready", "remaining", "cooldown", "reason", "name", "range"}.
func skill_status() -> Dictionary:
	var r := skill_check(true)
	var sig := Support.signature(id)
	var rng := float(sig.get("pulse_radius", 0.0))
	return {"ready": Support.is_ready(id), "remaining": Support.remaining(id), "cooldown": Support.cooldown(id),
		"ok": bool(r["ok"]), "reason": String(r["reason"]), "name": String(sig.get("name", "")),
		"range": rng if rng > 0.0 else SkillsData.PRESENCE_RANGE}


## Ends everything that belongs to this presence (sent away, area unloads).
func reset() -> void:
	hot = {}
	_pending = {}
	target = null
	if _pulse != null and is_instance_valid(_pulse):
		_pulse.call("set_on", false)
	_pulse_t = 0.0
