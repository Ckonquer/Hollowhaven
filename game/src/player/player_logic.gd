extends RefCounted
## Scene-free logic used by the player controller. Everything here is pure (no nodes, no autoloads
## except where noted) so it can be unit-tested in tests/unit/test_player_logic.gd.
##   const Logic := preload("res://src/player/player_logic.gd")
##   var st := Logic.Stamina.new()          # sprint/dodge/swing stamina model
##   var sw := Logic.Swing.new()            # swing timing: one strike per swing, one buffered click
##   var jp := Logic.JumpAssist.new()       # coyote time + jump buffering
##   var safe := Logic.SafeTracker.new()    # last safe grounded positions for fall recovery

# --- Movement tuning ------------------------------------------------------------------------------
const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.0
const GROUND_ACCEL := 30.0          # m/s^2 when speeding up on the ground
const GROUND_DECEL := 36.0          # m/s^2 when slowing down on the ground
const AIR_ACCEL := 9.0
const AIR_DECEL := 3.5
const TURN_RATE := 14.0             # 1/s, exponential smoothing of the facing
const GRAVITY := 18.0
const FALL_GRAVITY_MULT := 1.2      # slightly heavier fall = less floaty
const TERMINAL_FALL := 32.0
const JUMP_VELOCITY := 6.0
const JUMP_CUT := 0.8               # releasing jump early keeps this fraction of the upward speed (tap ~0.7 m, hold ~1 m)
const COYOTE_TIME := 0.12
const STEP_HEIGHT := 0.3            # small lips / floor tiles / pebbles are stepped over
const JUMP_BUFFER := 0.12

# --- Stamina ------------------------------------------------------------------------------------------
const STAMINA_MAX := 100.0
const SPRINT_DRAIN := 18.0          # per second while sprinting
const STAMINA_REGEN := 22.0         # per second after the delay
const REGEN_DELAY := 0.6            # seconds after the last use before regeneration starts
const SPRINT_RESUME := 25.0         # after running dry, sprint again once stamina is back to this

# --- Dodge ---------------------------------------------------------------------------------------------
const DODGE_TIME := 0.45
const DODGE_SPEED_START := 8.6
const DODGE_SPEED_END := 3.2
const DODGE_IFRAMES := 0.3
const DODGE_COST := 20.0
const DODGE_COOLDOWN := 0.12

# --- Swings --------------------------------------------------------------------------------------------
const SWING_TIME := 0.5
const SWING_STRIKE := 0.22          # seconds into the swing when the hit happens
const SWING_COST := 6.0
const TIRED_SWING_MULT := 1.25      # swings are a little slower without stamina (never blocked)
const HAND_DAMAGE := 5.0
const HAND_REACH := 1.8
const MELEE_ARC := 110.0

# --- Interaction ---------------------------------------------------------------------------------------
const INTERACT_RANGE := 2.6

# --- Recovery --------------------------------------------------------------------------------------------
const OUTSIDE_MARGIN := 12.0        # metres past WORLD_HALF_EXTENT before the surface recovers you
const BELOW_FLOOR_MARGIN := 2.5     # metres under the terrain surface that count as "stuck below"
const MAX_AIR_TIME := 6.0           # falling this long means something went wrong


## Stamina model: sprint drain, regeneration delay, exhaustion hysteresis and costs.
class Stamina extends RefCounted:
	var value: float = 100.0
	var max_value: float = 100.0
	var delay_left: float = 0.0
	var exhausted: bool = false

	func reset(v: float, mx: float) -> void:
		max_value = maxf(mx, 1.0)
		value = clampf(v, 0.0, max_value)
		delay_left = 0.0
		exhausted = false

	## Advances by dt. `draining` = currently sprinting. regen_mult comes from food buffs.
	func tick(dt: float, draining: bool, regen_mult: float = 1.0) -> void:
		if dt <= 0.0:
			return
		if draining:
			value -= SPRINT_DRAIN * dt
			delay_left = REGEN_DELAY
			if value <= 0.0:
				value = 0.0
				exhausted = true
		else:
			var regen_time := dt
			if delay_left > 0.0:
				var used := minf(delay_left, dt)
				delay_left -= used
				regen_time = dt - used
			if regen_time > 0.0:
				value = minf(max_value, value + STAMINA_REGEN * maxf(regen_mult, 0.0) * regen_time)
		if exhausted and value >= SPRINT_RESUME:
			exhausted = false

	func can_sprint() -> bool:
		return value > 0.0 and not exhausted

	## All-or-nothing spend (dodge). Returns false and changes nothing if there is not enough.
	func try_spend(cost: float) -> bool:
		if value + 0.0001 < cost:
			return false
		value = maxf(0.0, value - cost)
		delay_left = REGEN_DELAY
		return true

	## Spends what is available (swings are never blocked). Returns true if the full cost was paid.
	func spend_soft(cost: float) -> bool:
		var full := value + 0.0001 >= cost
		value = maxf(0.0, value - cost)
		delay_left = REGEN_DELAY
		return full

	func ratio() -> float:
		return value / max_value if max_value > 0.0 else 0.0


## Swing timing. tick() reports STRIKE exactly once per swing and FINISHED at the end.
## A click during a swing is buffered (at most one) once the swing is past BUFFER_FROM.
class Swing extends RefCounted:
	const STRIKE := 1
	const FINISHED := 2
	const BUFFER_FROM := 0.2          # fraction of the swing after which clicks are buffered

	var active: bool = false
	var kind: String = ""
	var t: float = 0.0
	var duration: float = 0.5
	var strike_at: float = 0.22
	var struck: bool = false
	var buffered: bool = false

	## Starts a swing. Returns false (no change) if one is already running.
	func start(p_kind: String, p_duration: float = SWING_TIME, p_strike: float = SWING_STRIKE) -> bool:
		if active:
			return false
		active = true
		kind = p_kind
		t = 0.0
		duration = maxf(p_duration, 0.05)
		strike_at = clampf(p_strike, 0.0, duration)
		struck = false
		buffered = false
		return true

	## Attack pressed. Returns true when a swing may start right now; otherwise the click is buffered
	## (only one, and only late enough in the current swing) and false is returned.
	func request() -> bool:
		if not active:
			return true
		if not buffered and t >= duration * BUFFER_FROM:
			buffered = true
		return false

	func tick(dt: float) -> int:
		if not active:
			return 0
		var ev := 0
		t += maxf(dt, 0.0)
		if not struck and t >= strike_at:
			struck = true
			ev |= STRIKE
		if t >= duration:
			active = false
			ev |= FINISHED
		return ev

	## Returns and clears the buffered click.
	func take_buffer() -> bool:
		var b := buffered
		buffered = false
		return b

	func progress() -> float:
		return clampf(t / duration, 0.0, 1.0) if active else 0.0

	## A wind-up can be cancelled (dodge, flinch); a swing that already struck plays out.
	func can_cancel() -> bool:
		return active and not struck

	func cancel() -> void:
		active = false
		buffered = false


## Coyote time (jump shortly after leaving a ledge) and jump buffering (press shortly before landing).
class JumpAssist extends RefCounted:
	var coyote_left: float = 0.0
	var buffer_left: float = 0.0

	func tick(dt: float, grounded: bool) -> void:
		if grounded:
			coyote_left = COYOTE_TIME
		else:
			coyote_left = maxf(0.0, coyote_left - dt)
		buffer_left = maxf(0.0, buffer_left - dt)

	func press() -> void:
		buffer_left = JUMP_BUFFER

	## True (once) when a buffered press meets ground/coyote time.
	func try_consume() -> bool:
		if buffer_left > 0.0 and coyote_left > 0.0:
			buffer_left = 0.0
			coyote_left = 0.0
			return true
		return false

	func clear() -> void:
		coyote_left = 0.0
		buffer_left = 0.0


## Remembers recent safe grounded positions (sampled every INTERVAL seconds).
class SafeTracker extends RefCounted:
	const INTERVAL := 0.5
	const HISTORY := 8
	const MIN_STEP := 0.25

	var points: Array[Vector3] = []
	var timer: float = 0.0

	## Call every physics frame. Records when the interval has passed and the spot is safe.
	## Returns true when a point was recorded.
	func tick(dt: float, pos: Vector3, safe_now: bool) -> bool:
		timer += dt
		if timer < INTERVAL or not safe_now:
			return false
		timer = 0.0
		record(pos)
		return true

	func record(pos: Vector3) -> void:
		if not points.is_empty() and points[points.size() - 1].distance_to(pos) < MIN_STEP:
			points[points.size() - 1] = pos
			return
		points.append(pos)
		while points.size() > HISTORY:
			points.remove_at(0)

	func has_point() -> bool:
		return not points.is_empty()

	func last() -> Vector3:
		return points[points.size() - 1] if not points.is_empty() else Vector3.ZERO

	## Where to put the player back: one sample older than the newest (further from the edge they
	## fell off), or the newest if that is all we have, or the fallback.
	func recovery_point(fallback: Vector3) -> Vector3:
		if points.size() >= 2:
			return points[points.size() - 2]
		if points.size() == 1:
			return points[0]
		return fallback

	## Drops the newest sample (used when recovering to it failed validation).
	func drop_last() -> void:
		if not points.is_empty():
			points.remove_at(points.size() - 1)

	func clear() -> void:
		points.clear()
		timer = 0.0


# --- Static helpers ---------------------------------------------------------------------------------

## Why the player must be recovered, or "" when all is well.
## ground_h: terrain height under the player (NAN when unknown).
static func recovery_reason(pos: Vector3, area_id: String, kill_y: float, half_extent: float, ground_h: float, air_time: float) -> String:
	if pos.y < kill_y:
		return "fell"
	if area_id == "surface" and (absf(pos.x) > half_extent + OUTSIDE_MARGIN or absf(pos.z) > half_extent + OUTSIDE_MARGIN):
		return "outside"
	if not is_nan(ground_h) and pos.y < ground_h - BELOW_FLOOR_MARGIN:
		return "below_floor"
	if air_time > MAX_AIR_TIME:
		return "falling"
	return ""


## Interaction prompt from a target's interaction / harvest info.
## interaction: result of get_interaction(player) ({} when the node has none)
## harvest: result of get_harvest_info() ({} when none); owned_tool: best owned item id for its tool
## ("" when missing; ignored for "hand").
## Tool harvestables (axe/pickaxe) always prompt the attack action ("Chop Oak Tree" / "Needs an Axe"),
## even when they also answer get_interaction (resource nodes do): LMB is how tools are used and pressing
## E on them swings the tool too. Everything else prompts its interaction first (hand harvestables such as
## sticks and berry bushes are picked with E), then a plain "Gather X" attack prompt.
static func build_prompt(interaction: Dictionary, harvest: Dictionary, owned_tool: String) -> Dictionary:
	var htool := String(harvest.get("tool", "hand")) if not harvest.is_empty() else ""
	var tool_harvest := htool != "" and htool != "hand"
	if not tool_harvest and not interaction.is_empty() and String(interaction.get("text", "")) != "":
		var p := {"text": String(interaction["text"]), "action": "interact", "enabled": _truthy(interaction.get("enabled", true), true)}
		if String(interaction.get("reason", "")) != "":
			p["reason"] = String(interaction["reason"])
		return p
	if not harvest.is_empty():
		var tool := htool
		var nm := String(harvest.get("name", ""))
		if tool == "hand" or tool == "" or owned_tool != "":
			var txt := harvest_verb(tool)
			if nm != "":
				txt += " " + nm
			return {"text": txt, "action": "attack", "enabled": true}
		return {"text": "Needs " + tool_article_name(tool), "action": "attack", "enabled": false}
	return {}


## Duck-typed flag read (other modules' dictionaries): bools, numbers, else the default. Never errors.
static func _truthy(v: Variant, def: bool) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return def


static func harvest_verb(tool: String) -> String:
	match tool:
		"axe":
			return "Chop"
		"pickaxe":
			return "Mine"
	return "Gather"


static func tool_article_name(tool: String) -> String:
	match tool:
		"axe":
			return "an Axe"
		"pickaxe":
			return "a Pickaxe"
	var nm := tool.capitalize()
	if nm == "":
		return "a Tool"
	return ("an " if "AEIOU".contains(nm.left(1)) else "a ") + nm


## Swing animation kind for a weapon/tool item (by its data): "sword" | "axe" | "pickaxe" | "hands".
static func weapon_kind(item_id: String, cat: String, tool: String) -> String:
	if item_id == "":
		return "hands"
	if cat == "weapon":
		return "sword"
	if tool == "axe" or tool == "pickaxe":
		return tool
	return "hands"


## Scores an interaction candidate (lower is better); INF = rejected.
## surface_dist: horizontal distance from the player to the candidate's collision surface.
static func score_candidate(player_pos: Vector3, facing: Vector3, target_pos: Vector3, surface_dist: float, max_dist: float, from_ray: bool) -> float:
	if surface_dist > max_dist:
		return INF
	var dy := target_pos.y - player_pos.y
	if dy < -1.4 or dy > 2.9:
		return INF
	var to := Vector3(target_pos.x - player_pos.x, 0.0, target_pos.z - player_pos.z)
	var f := Vector3(facing.x, 0.0, facing.z)
	var dot := 1.0
	if to.length_squared() > 0.0001 and f.length_squared() > 0.0001:
		dot = f.normalized().dot(to.normalized())
	if dot < -0.15 and surface_dist > 0.6:
		return INF
	var s := surface_dist + (1.0 - dot) * 0.9
	if from_ray:
		s -= 0.55
	return s


## Lantern brightness multiplier: softer in surface daylight (a raised lantern at noon should not paint
## a spotlight on the grass), full strength at dusk, night and anywhere underground.
static func lantern_scale(area_id: String, hour: float) -> float:
	if area_id != "surface":
		return 1.0
	var h := fposmod(hour, 24.0)
	var day := 0.45
	if h >= 8.0 and h <= 17.0:
		return day
	if h > 17.0 and h < 19.5:
		return lerpf(day, 1.0, (h - 17.0) / 2.5)
	if h > 5.5 and h < 8.0:
		return lerpf(1.0, day, (h - 5.5) / 2.5)
	return 1.0


## Horizontal dodge speed over the roll (t = 0..1): fast burst that eases out.
static func dodge_speed(t: float) -> float:
	var k := clampf(t, 0.0, 1.0)
	return lerpf(DODGE_SPEED_START, DODGE_SPEED_END, k * k)


## Horizontal velocity smoothing toward the wished velocity.
static func approach(current: Vector3, target: Vector3, grounded: bool, dt: float) -> Vector3:
	var speeding_up := target.length_squared() > current.length_squared() * 0.98 and target.length_squared() > 0.0001
	var rate: float
	if grounded:
		rate = GROUND_ACCEL if speeding_up else GROUND_DECEL
	else:
		rate = AIR_ACCEL if speeding_up else AIR_DECEL
	return current.move_toward(target, rate * dt)


## Yaw (radians, Godot convention: forward = -Z) that faces a horizontal direction.
static func yaw_for_dir(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


## Forward (-Z) direction for a yaw.
static func dir_for_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Camera-relative wish direction from the raw input vector (x = right, y = back as from
## Input.get_vector(left, right, forward, back)). Length is preserved (analog), at most 1.
static func camera_relative(raw: Vector2, cam_yaw: float) -> Vector3:
	var fwd := dir_for_yaw(cam_yaw)
	var right := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var v := right * raw.x - fwd * raw.y
	if v.length() > 1.0:
		v = v.normalized()
	return v
