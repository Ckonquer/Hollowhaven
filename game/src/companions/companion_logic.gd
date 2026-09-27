extends RefCounted
## Pure decision logic for the companions. No scene access: everything here takes plain values
## and returns plain values so it can be unit tested (tests/unit/test_companions_*.gd).
##   const Logic := preload("res://src/companions/companion_logic.gd")

const ORDER := ["mochi", "pebble", "lumi"]
const SURFACE_AREAS := ["surface", "arena"]    # areas that have homes / wild spots / the threshold

const PET_BOND := 5
const FEED_BOND := 8
const WORK_BOND := 1
const WORK_BOND_DAILY_MAX := 5
const ZONE_BOND := 3

const STUCK_FAR := 20.0            # farther than this from Krystal -> recover immediately
const STUCK_SECONDS := 4.0         # no progress for this long while following -> recover
const STUCK_PROGRESS := 0.5        # metres of improvement that count as progress
const NO_LOS_SECONDS := 7.0        # can't see Krystal this long while near -> recover
const REFUSE_RADIUS := 8.0         # Mochi refuses when Krystal gets this close to the mine threshold
const REFUSE_RESET_RADIUS := 14.0  # ...and may refuse again once Krystal has walked this far away
const THRESHOLD_MATCH := 6.0       # a wait spot this close to the threshold counts as "at the threshold"
const PINNED_BOULDER_ID := "pebble_boulder"


static func is_surface_area(area_id: String) -> bool:
	return SURFACE_AREAS.has(area_id)


static func vec_from(v: Variant) -> Variant:
	if v is Vector3:
		return v
	if v is Array and v.size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return null


# --- Spawning ---------------------------------------------------------------------------------------

## Decides which companions appear in an area, how, and which GameState changes that implies.
## records: id -> companion record (GameState.companions). active: current follower id.
## arrival_spawn: spawn id Krystal arrived at. defs: id -> creature definition (ItemDB.creature).
## boulder_gone: GameState.is_depleted("pebble_boulder"). threshold: mine threshold position or null.
## Returns {"spawns": [{"id", "mode", "pos"?}], "changes": [{"id", "assignment", "wait_area", "wait_pos"}], "boulder": bool}
## Modes: wild | pinned | home | wait | follow | reunite (rejoins as follower) | reunite_home
static func plan_spawns(area_id: String, records: Dictionary, active: String, arrival_spawn: String,
		defs: Dictionary, boulder_gone: bool, threshold: Variant) -> Dictionary:
	var spawns: Array = []
	var changes: Array = []
	var boulder := false
	var ids: Array = []
	for id in ORDER:
		if records.has(id) or defs.has(id):
			ids.append(id)
	for id in records:
		if not ids.has(id) and defs.has(id):
			ids.append(id)
	if is_surface_area(area_id):
		var follower := active
		# A follower that is not befriended (corrupt data) is ignored.
		if follower != "" and not bool(records.get(follower, {}).get("befriended", false)):
			follower = ""
		for id in ids:
			var rec: Dictionary = records.get(id, {})
			if not bool(rec.get("befriended", false)):
				if id == "pebble" and not boulder_gone:
					boulder = true
					spawns.append({"id": id, "mode": "pinned"})
				else:
					spawns.append({"id": id, "mode": "wild"})
				continue
			var assignment := String(rec.get("assignment", "home"))
			if assignment == "follow" and follower == id:
				spawns.append({"id": id, "mode": "follow"})
				continue
			if assignment == "follow" and follower != id:
				changes.append({"id": id, "assignment": "home"})
				spawns.append({"id": id, "mode": "home"})
				continue
			if assignment == "wait":
				var wp: Variant = vec_from(rec.get("wait_pos"))
				if String(rec.get("wait_area", "")) == area_id and wp != null:
					var at_threshold := threshold is Vector3 and _flat_dist(wp, threshold) <= THRESHOLD_MATCH
					if at_threshold and arrival_spawn == "mine_exit":
						if follower == "":
							follower = id
							changes.append({"id": id, "assignment": "follow"})
							spawns.append({"id": id, "mode": "reunite", "pos": wp})
						else:
							changes.append({"id": id, "assignment": "home"})
							spawns.append({"id": id, "mode": "reunite_home", "pos": wp})
					else:
						spawns.append({"id": id, "mode": "wait", "pos": wp})
					continue
				# Waiting somewhere that isn't this area: it found its way home safely.
				changes.append({"id": id, "assignment": "home"})
				spawns.append({"id": id, "mode": "home"})
				continue
			if assignment != "home":
				changes.append({"id": id, "assignment": "home"})
			spawns.append({"id": id, "mode": "home"})
	else:
		# The Below (and any other dungeon-like area): only the follower, and only if it dares.
		if active != "" and bool(records.get(active, {}).get("befriended", false)):
			var def: Dictionary = defs.get(active, {})
			if bool(def.get("enters_below", false)):
				spawns.append({"id": active, "mode": "follow"})
			else:
				var tpos: Variant = threshold if threshold is Vector3 else null
				changes.append({"id": active, "assignment": "wait", "wait_area": "surface", "wait_pos": tpos})
		# ...plus anyone Krystal told to wait down here (e.g. after continuing from a lantern save):
		# they are still where she left them, never silently gone.
		for id in ids:
			if id == active:
				continue
			var wrec: Dictionary = records.get(id, {})
			if not bool(wrec.get("befriended", false)) or String(wrec.get("assignment", "")) != "wait":
				continue
			if String(wrec.get("wait_area", "")) != area_id or not bool(defs.get(id, {}).get("enters_below", false)):
				continue
			var wpos: Variant = vec_from(wrec.get("wait_pos"))
			if wpos != null:
				spawns.append({"id": id, "mode": "wait", "pos": wpos})
	return {"spawns": spawns, "changes": changes, "boulder": boulder}


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Bond --------------------------------------------------------------------------------------------

## Petting: bond xp to grant today (PET_BOND once per in-game day, else 0). Marks the record.
static func pet_bond(rec: Dictionary, day: int) -> int:
	if int(rec.get("last_pet_day", -1)) == day:
		return 0
	rec["last_pet_day"] = day
	return PET_BOND


## Feeding check: "ok" | "full" (already fed today) | "no_food".
static func feed_check(rec: Dictionary, day: int, has_food: bool) -> String:
	if int(rec.get("last_fed_day", -1)) == day:
		return "full"
	if not has_food:
		return "no_food"
	return "ok"


## Marks the record as fed today and returns the bond xp to grant.
static func feed_bond(rec: Dictionary, day: int) -> int:
	if int(rec.get("last_fed_day", -1)) == day:
		return 0
	rec["last_fed_day"] = day
	return FEED_BOND


## Working together (forage / mining assists): +1 per assist, at most WORK_BOND_DAILY_MAX per day.
static func work_bond(rec: Dictionary, day: int) -> int:
	if int(rec.get("work_day", -1)) != day:
		rec["work_day"] = day
		rec["work_xp"] = 0
	if int(rec.get("work_xp", 0)) >= WORK_BOND_DAILY_MAX:
		return 0
	rec["work_xp"] = int(rec.get("work_xp", 0)) + WORK_BOND
	return WORK_BOND


## Entering a zone together for the first time: +ZONE_BOND once per zone id.
static func zone_bond(rec: Dictionary, zone_id: String) -> int:
	if zone_id == "":
		return 0
	var zv: Variant = rec.get("zones")
	var zones: Array = zv if zv is Array else []    # tolerate a damaged save value
	if zones.has(zone_id):
		return 0
	zones.append(zone_id)
	rec["zones"] = zones
	return ZONE_BOND


static func gift_due(rec: Dictionary, day: int) -> bool:
	return bool(rec.get("befriended", false)) and int(rec.get("last_gift_day", -1)) != day


# --- Mochi at the mine ---------------------------------------------------------------------------------

static func should_refuse(enters_below: bool, assignment: String, dist_to_threshold: float, refused_this_approach: bool) -> bool:
	return not enters_below and assignment == "follow" and dist_to_threshold <= REFUSE_RADIUS and not refused_this_approach


static func approach_reset(dist_to_threshold: float) -> bool:
	return dist_to_threshold > REFUSE_RESET_RADIUS


# --- Following -------------------------------------------------------------------------------------------

static func new_stuck_tracker() -> Dictionary:
	return {"best": INF, "timer": 0.0}


static func reset_stuck(tr: Dictionary) -> void:
	tr["best"] = INF
	tr["timer"] = 0.0


## Feeds one frame of the follow distance into the tracker. Returns "" (fine), "far" (recover now:
## more than STUCK_FAR away) or "stuck" (no STUCK_PROGRESS of improvement for STUCK_SECONDS while
## lagging behind).
static func stuck_update(tr: Dictionary, dist: float, delta: float, follow_distance: float) -> String:
	if dist > STUCK_FAR:
		reset_stuck(tr)
		return "far"
	if dist <= follow_distance + 1.5:
		reset_stuck(tr)
		return ""
	if dist < float(tr.get("best", INF)) - STUCK_PROGRESS:
		tr["best"] = dist
		tr["timer"] = 0.0
		return ""
	tr["timer"] = float(tr.get("timer", 0.0)) + delta
	if float(tr["timer"]) >= STUCK_SECONDS:
		reset_stuck(tr)
		return "stuck"
	return ""


## Second stuck detector: wanting to move (goal > 1 m away) but the net displacement over
## STUCK_SECONDS stays under 1 m (e.g. hopping against a wall). Returns true when stuck.
static func progress_update(tr: Dictionary, pos: Vector3, wants_move: bool, delta: float) -> bool:
	if not wants_move or not tr.has("start"):
		tr["start"] = pos
		tr["t"] = 0.0
		return false
	tr["t"] = float(tr.get("t", 0.0)) + delta
	if float(tr["t"]) < STUCK_SECONDS:
		return false
	var start: Vector3 = tr["start"]
	tr["start"] = pos
	tr["t"] = 0.0
	return _flat_dist(pos, start) < 1.0


## Third detector: no line of sight to Krystal for NO_LOS_SECONDS while she's near (e.g. the
## companion ended up on the wrong side of a thin wall). Returns true when it should recover.
static func los_update(tr: Dictionary, has_los: bool, dist: float, delta: float) -> bool:
	if has_los or dist > STUCK_FAR:
		tr["no_los"] = 0.0
		return false
	tr["no_los"] = float(tr.get("no_los", 0.0)) + delta
	if float(tr["no_los"]) >= NO_LOS_SECONDS:
		tr["no_los"] = 0.0
		return true
	return false


## Where a follower wants to stand: a little behind and beside Krystal (side = -1 left, +1 right).
static func follow_goal(player_pos: Vector3, player_fwd: Vector3, side: float, follow_distance: float) -> Vector3:
	var f := Vector3(player_fwd.x, 0.0, player_fwd.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	f = f.normalized()
	var right := f.cross(Vector3.UP).normalized()
	return player_pos - f * follow_distance * 0.5 + right * side * follow_distance * 0.58


## Candidate follow spots around Krystal, best first: behind-beside (own side), behind-beside
## (other side), straight behind, beside, beside (other side), in front-beside. The companion uses
## the first one that Krystal can see (never a spot on the far side of a wall).
static func goal_candidates(player_pos: Vector3, player_fwd: Vector3, side: float, follow_distance: float) -> Array:
	var f := Vector3(player_fwd.x, 0.0, player_fwd.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var back := follow_distance * 0.5
	var lat := follow_distance * 0.58
	return [
		player_pos - f * back + r * side * lat,
		player_pos - f * back - r * side * lat,
		player_pos - f * follow_distance * 0.75,
		player_pos + r * side * lat * 1.1,
		player_pos - r * side * lat * 1.1,
		player_pos + f * back + r * side * lat,
	]


## Keeps a point out of the corridor between the camera and Krystal (so the companion never
## blocks the view). Returns the point pushed sideways to `clearance` if needed.
static func camera_safe(point: Vector3, player_pos: Vector3, cam_pos: Vector3, side: float, clearance: float = 1.1) -> Vector3:
	var a := Vector2(cam_pos.x, cam_pos.z)
	var b := Vector2(player_pos.x, player_pos.z)
	var p := Vector2(point.x, point.z)
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.01:
		return point
	var t := (p - a).dot(ab) / len2
	if t < -0.1 or t > 0.92:
		return point
	var closest := a + ab * clampf(t, 0.0, 1.0)
	var off := p - closest
	var d := off.length()
	if d >= clearance:
		return point
	var n: Vector2
	if d > 0.001:
		n = off / d
	else:
		n = Vector2(-ab.y, ab.x).normalized() * (1.0 if side >= 0.0 else -1.0)
	var np := closest + n * clearance
	return Vector3(np.x, point.y, np.y)


static func in_camera_corridor(point: Vector3, player_pos: Vector3, cam_pos: Vector3, clearance: float = 1.1) -> bool:
	return camera_safe(point, player_pos, cam_pos, 1.0, clearance).distance_to(point) > 0.01


## Speed toward the follow goal: matches Krystal while she moves (never slower than her when
## lagging), sprints to catch up when far, and eases in on arrival when she stands still.
static func follow_speed(dist_to_goal: float, move_speed: float, player_speed: float) -> float:
	if dist_to_goal < 0.3 and player_speed < 0.5:
		return 0.0
	var catchup := clampf((dist_to_goal - 0.6) / 3.5, 0.0, 1.0)
	var cruise := clampf(player_speed, move_speed * 0.55, move_speed * 1.6)
	var spd := lerpf(cruise, move_speed * 1.9, catchup)
	if player_speed >= 0.5:
		return maxf(spd, player_speed * (1.0 + clampf(dist_to_goal - 0.3, 0.0, 0.3)))
	return spd * clampf(dist_to_goal / 1.2, 0.3, 1.0)


## Breadcrumbs: appends Krystal's position when she has moved at least `min_step`. Returns true if added.
static func trail_push(trail: Array, pos: Vector3, min_step: float = 0.4, max_len: int = 48) -> bool:
	if not trail.is_empty():
		var last: Vector3 = trail[trail.size() - 1]
		if last.distance_to(pos) < min_step:
			return false
	trail.append(pos)
	while trail.size() > max_len:
		trail.pop_front()
	return true


## Resumes the breadcrumb trail from the crumb nearest to the companion (crumbs pile up while it
## steers directly, so the oldest crumb may be far behind), drops everything before it (and the
## crumb itself once reached) and returns the next crumb to walk to, or null when used up.
static func trail_next(trail: Array, from: Vector3, reach: float = 0.7) -> Variant:
	if trail.is_empty():
		return null
	var best_i := -1
	var best_d := INF
	for i in trail.size():
		var c: Vector3 = trail[i]
		var d := _flat_dist(c, from) + absf(c.y - from.y) * 2.0
		if d <= best_d:
			best_d = d
			best_i = i
	var drop := best_i + (1 if best_d < reach else 0)
	for k in drop:
		trail.pop_front()
	if trail.is_empty():
		return null
	return trail[0]


## Safe-spot candidates for recovering / placing a companion near Krystal, best first:
## just behind the camera (out of view), then behind and beside Krystal.
static func placement_candidates(player_pos: Vector3, player_fwd: Vector3, cam_pos: Variant, side: float) -> Array:
	var out: Array = []
	var f := Vector3(player_fwd.x, 0.0, player_fwd.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	f = f.normalized()
	var right := f.cross(Vector3.UP).normalized()
	if cam_pos is Vector3:
		var cp: Vector3 = cam_pos
		var cf := Vector3(player_pos.x - cp.x, 0.0, player_pos.z - cp.z)
		var cam_dist := cf.length()
		if cam_dist > 0.5 and cam_dist < 12.0:
			cf = cf / cam_dist
			var cr := cf.cross(Vector3.UP).normalized()
			var behind := Vector3(cp.x, player_pos.y, cp.z) - cf * 1.3
			out.append(behind + cr * side * 0.8)
			out.append(behind - cr * side * 0.8)
	out.append(player_pos - f * 2.0 + right * side * 1.0)
	out.append(player_pos - f * 2.0 - right * side * 1.0)
	out.append(player_pos + right * side * 1.6)
	out.append(player_pos - right * side * 1.6)
	out.append(player_pos - f * 1.1)
	return out


## True if `point` is roughly inside the camera's view cone.
static func in_view(cam_pos: Vector3, cam_fwd: Vector3, point: Vector3, half_fov_deg: float = 55.0) -> bool:
	var to := point - cam_pos
	if to.length() < 0.01:
		return true
	return cam_fwd.normalized().dot(to.normalized()) > cos(deg_to_rad(half_fov_deg))


# --- Befriending prompts ------------------------------------------------------------------------------------

## Interaction prompt for a creature that is not befriended yet.
## ctx: {"have": int (items owned), "need": int, "item_name": String, "scared": bool,
##       "ruin_cleared": bool, "pinned": bool}
static func wild_prompt(id: String, def: Dictionary, ctx: Dictionary) -> Dictionary:
	var how: Dictionary = def.get("befriend", {})
	match String(how.get("type", "")):
		"offer_item":
			if bool(ctx.get("scared", false)):
				return {"text": "It's too frightened right now", "enabled": false}
			var need := int(how.get("count", 1))
			var have := int(ctx.get("have", 0))
			var item_name := String(ctx.get("item_name", String(how.get("item", ""))))
			if have >= need:
				return {"text": "Offer %d %s" % [need, item_name], "enabled": true}
			return {"text": "Offer %d %s (%d/%d)" % [need, item_name, have, need], "enabled": false}
		"free_from_boulder":
			if bool(ctx.get("pinned", false)):
				return {"text": "Something is stuck under the boulder", "enabled": false}
			return {"text": "Help the little stone creature up", "enabled": true}
		"rescue":
			if not bool(ctx.get("ruin_cleared", false)):
				return {"text": "The little light is too frightened", "enabled": false}
			return {"text": "Reach out to the little light", "enabled": true}
	return {"text": "Say hello", "enabled": true}
