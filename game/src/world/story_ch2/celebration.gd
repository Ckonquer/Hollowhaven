extends Node3D
## The Lanternwake celebration (module C9; MP §11 step 20, §17 "a small skippable celebration"). Pure
## presentation, created by Game.complete_chapter_two() AFTER the rewards are committed and saved
## (story_ch2.start_celebration()); nothing here is saved and nothing is placed where Krystal builds:
##   * a ring of warm festival lanterns floats OUTSIDE the build area (every build circle incl. the Haven
##     expansion's "extra" regions, + 1.5 m) - at home around the Haven, at the Commons around the festival
##     lantern (and outside the outpost build area); no tables, no guests, no colliders;
##   * sky lanterns drift up from that ring (one MultiMesh, no per-frame allocation);
##   * two warm unshadowed lights;
##   * a gentle camera shot whose viewpoint is VALIDATED against her buildings and the world (clear line of
##     sight to the focus, nothing solid around the lens, open sky above it, above the ground); if no
##     candidate is clear the player's own camera is kept (the simple safe shot).
## play() is awaitable (DURATION s, any key press / mouse click skips after SKIP_AFTER s - never the mouse wheel or a
## held key's repeat); the ending screen then plays over
## the still-glowing scene; finish() restores the camera and removes everything.
## Companions celebrate through Game (react("celebrate")); music is the director's (m27 on chapter2_completed).

signal done

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const Layout := preload("res://data/world_layout.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const FestivalLights := preload("res://src/world/story_ch2/festival_lights.gd")

const DURATION := 9.0
const SKIP_AFTER := 1.2
## Mouse buttons that never skip (is_skip_input).
const WHEEL_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
const RING_COUNT := 28
const HAVEN_RING_MIN := 17.5
const HAVEN_RING_MAX := 34.0
const OUTSIDE_MARGIN := 1.5
const RING_HEIGHT := 3.3
const COMMONS_RING_COUNT := 12
const COMMONS_RING_RADIUS := 10.5         # between the Commons' light posts (~8 m) and its stalls (~14 m)
const SKY_MAX := 16
const SKY_RISE := 26.0
const SKY_SECONDS := 8.0
const WORLD_MASK := 1 | 32
const STRUCTURE_MASK := 32
const LENS_CLEARANCE := 0.6
const DOLLY := 0.14

var area: Node3D = null
var area_id: String = ""
var player: Node3D = null
var venue: String = ""           # "haven" | "commons" | "" (no festival lights, safe shot only)
var focus := Vector3.ZERO        # what the celebration looks at (Ward Stone / festival lantern / Krystal)
var facing := Vector3.BACK       # the focus' front (the Ward Stone faces the Haven)
var duration: float = DURATION
var ring_points: Array = []      # [{"pos": Vector3 (world), "color", "scale"}] of the festival ring
var shot: Dictionary = {}        # {"pos", "end", "look"}; {} = the player's own camera (safe fallback)
var camera: Camera3D = null
var skipped := false
var _prev_camera: Camera3D = null
var _sky: MultiMesh = null
var _sky_starts: Array = []      # Vector3 world start of each sky lantern
var _t := 0.0
var _playing := false
var _finished := false


func setup(params: Dictionary) -> void:
	area = params.get("area", null)
	area_id = String(params.get("area_id", ""))
	player = params.get("player", null)
	duration = float(params.get("duration", DURATION))
	venue = String(params.get("venue", venue_for(area_id)))


static func venue_for(p_area_id: String) -> String:
	if p_area_id == Story.HAVEN_AREA:
		return "haven"
	if p_area_id == Story.REACH_AREA:
		return "commons"
	return ""


func _ready() -> void:
	name = "StoryCh2Celebration"
	process_mode = Node.PROCESS_MODE_ALWAYS
	top_level = true
	global_transform = Transform3D.IDENTITY
	_find_focus()
	var hfn := func(x: float, z: float) -> float: return _ground(x, z)
	match venue:
		"haven":
			ring_points = haven_ring(hfn)
		"commons":
			ring_points = commons_ring(Vector2(focus.x, focus.z), hfn)
		_:
			ring_points = []
	add_child(FestivalLights.lanterns(ring_points, "FestivalRing"))
	_build_sky()
	if venue != "":
		var l1 := FestivalLights.warm_light(1.3, 18.0)
		l1.name = "CelebrationGlow"
		l1.position = focus + Vector3(0, 3.5, 0)
		add_child(l1)
		var l2 := FestivalLights.warm_light(0.9, 14.0, Color("ffb0c0"))
		l2.name = "CelebrationGlow2"
		l2.position = focus + facing * 8.0 + Vector3(0, 4.0, 0)
		add_child(l2)


func _ground(x: float, z: float) -> float:
	if area != null and is_instance_valid(area) and area.has_method("height_at"):
		return float(area.height_at(x, z))
	return focus.y


func _find_focus() -> void:
	facing = Vector3.BACK
	if area == null or not is_instance_valid(area):
		return
	match venue:
		"haven":
			var ws := _first_in_group("ward_stone")
			if ws != null:
				focus = ws.global_position
				var z := ws.global_transform.basis.z
				facing = Vector3(z.x, 0, z.z).normalized() if Vector2(z.x, z.z).length() > 0.01 else Vector3.BACK
			else:
				var c := _layout_stone()
				focus = Vector3(c.x, _ground(c.x, c.y), c.y)
				var to_home := Vector2(Layout.BUILD_AREA["center"]) - c
				facing = Vector3(to_home.x, 0, to_home.y).normalized() if to_home.length() > 0.01 else Vector3.BACK
		"commons":
			var pole := _first_in_group("lanternwake_pole")
			var commons: Vector2 = Reach.LANDMARKS["hr_commons"]["pos"]
			if pole != null:
				focus = pole.global_position
			else:
				focus = Vector3(commons.x, _ground(commons.x, commons.y), commons.y)
			var to_c := commons - Vector2(focus.x, focus.z)
			facing = Vector3(to_c.x, 0, to_c.y).normalized() if to_c.length() > 0.5 else Vector3.BACK
		_:
			if player != null and is_instance_valid(player) and player.is_inside_tree():
				focus = player.global_position
			else:
				focus = area.global_position


func _first_in_group(group: String) -> Node3D:
	if not area.is_inside_tree():
		return null
	for n in area.get_tree().get_nodes_in_group(group):
		if n is Node3D and area.is_ancestor_of(n):
			return n as Node3D
	return null


static func _layout_stone() -> Vector2:
	for b in Layout.BUILD_AREA.get("blocked", []):
		if String((b as Dictionary).get("name", "")) == "Ward Stone":
			return (b as Dictionary)["center"]
	return Vector2(0, -6)


# --- Where the festival lights go ------------------------------------------------------------------------------

## Every buildable circle of the Haven: [[Vector2 centre, float radius], ...] (the legacy circle + the
## Haven expansion's "extra" regions).
static func build_circles() -> Array:
	var out: Array = [[Vector2(Layout.BUILD_AREA["center"]), float(Layout.BUILD_AREA["radius"])]]
	var extra: Variant = Layout.BUILD_AREA.get("extra", [])
	if extra is Array:
		for e in extra:
			if e is Dictionary and (e as Dictionary).get("center") is Vector2:
				out.append([(e as Dictionary)["center"], float((e as Dictionary).get("radius", 0.0))])
	return out


static func outside_build(p: Vector2, margin: float, circles: Array) -> bool:
	for c in circles:
		if p.distance_to(c[0]) < float(c[1]) + margin:
			return false
	return true


## The Haven festival ring: RING_COUNT directions around the build centre; each lantern takes the first
## radius (from HAVEN_RING_MIN outwards) that is outside every build circle by OUTSIDE_MARGIN.
static func haven_ring(height_fn: Callable, circles: Array = []) -> Array:
	if circles.is_empty():
		circles = build_circles()
	var centre: Vector2 = Layout.BUILD_AREA["center"]
	var out: Array = []
	for i in RING_COUNT:
		var a := TAU * float(i) / float(RING_COUNT)
		var dir := Vector2(cos(a), sin(a))
		var r := HAVEN_RING_MIN
		while r <= HAVEN_RING_MAX:
			var p := centre + dir * r
			if outside_build(p, OUTSIDE_MARGIN, circles):
				var y: float = float(height_fn.call(p.x, p.y)) + RING_HEIGHT + 0.3 * sin(a * 3.0)
				out.append({"pos": Vector3(p.x, y, p.y), "color": FestivalLights.color_for(i), "scale": 1.15, "yaw": a})
				break
			r += 1.0
	return out


## The Commons ring around the festival lantern, never over the outpost build area.
static func commons_ring(center: Vector2, height_fn: Callable) -> Array:
	var out_c: Vector2 = Reach.OUTPOST_BUILD_AREA["center"]
	var out_r: float = float(Reach.OUTPOST_BUILD_AREA["radius"])
	var out: Array = []
	for i in COMMONS_RING_COUNT:
		var a := TAU * float(i) / float(COMMONS_RING_COUNT)
		var p := center + Vector2(cos(a), sin(a)) * COMMONS_RING_RADIUS
		if p.distance_to(out_c) < out_r + OUTSIDE_MARGIN:
			continue
		var y: float = float(height_fn.call(p.x, p.y)) + RING_HEIGHT + 0.5 + 0.25 * sin(a * 2.0)
		out.append({"pos": Vector3(p.x, y, p.y), "color": FestivalLights.color_for(i), "scale": 1.1, "yaw": a})
	return out


func _build_sky() -> void:
	_sky_starts = []
	for i in ring_points.size():
		if _sky_starts.size() >= SKY_MAX:
			break
		if i % 2 == 0 or ring_points.size() <= SKY_MAX:
			_sky_starts.append((ring_points[i] as Dictionary)["pos"])
	if _sky_starts.is_empty():
		return
	_sky = MultiMesh.new()
	_sky.transform_format = MultiMesh.TRANSFORM_3D
	_sky.use_colors = true
	_sky.mesh = FestivalLights.body_mesh()
	_sky.instance_count = _sky_starts.size()
	_sky.visible_instance_count = 0
	for i in _sky_starts.size():
		_sky.set_instance_transform(i, Transform3D(Basis.IDENTITY, _sky_starts[i]))
		_sky.set_instance_color(i, FestivalLights.color_for(i + 2))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SkyLanterns"
	mmi.multimesh = _sky
	mmi.material_override = FestivalLights.body_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _update_sky() -> void:
	if _sky == null:
		return
	var n := _sky_starts.size()
	var spread := maxf(duration * 0.55, 0.01)
	var shown := 0
	for i in n:
		var start := 0.3 + spread * float(i) / float(n)
		var k := (_t - start) / SKY_SECONDS
		if k < 0.0:
			continue
		shown = i + 1
		var s0: Vector3 = _sky_starts[i]
		var up := SKY_RISE * k * (0.6 + 0.4 * k)
		var drift := Vector3(sin(float(i) * 2.3 + _t * 0.3), 0.0, cos(float(i) * 1.7 + _t * 0.25)) * (1.5 * k)
		var sc := maxf(1.0 - 0.35 * k, 0.4)
		_sky.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(sc, sc, sc)), s0 + drift + Vector3(0.0, up, 0.0)))
	_sky.visible_instance_count = shown


# --- The camera shot ------------------------------------------------------------------------------------------

## Candidate viewpoints for a venue: [{"pos", "look"}] in preference order (all well above head height).
static func candidate_shots(p_venue: String, p_focus: Vector3, p_facing: Vector3) -> Array:
	var f := Vector3(p_facing.x, 0.0, p_facing.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.BACK
	var right := f.cross(Vector3.UP).normalized()
	var rel: Array = []
	var look := p_focus
	match p_venue:
		"haven":
			# Over the Ward Stone's shoulders toward the Haven, then wider and higher.
			look = p_focus + Vector3(0, 2.2, 0) + f * 3.0
			rel = [[-8.0, 6.0, 4.5], [-8.0, -6.0, 4.5], [-11.0, 0.0, 6.5], [3.0, 10.0, 3.8], [3.0, -10.0, 3.8],
				[-14.0, 0.0, 9.5], [9.0, 5.0, 12.0]]
		"commons":
			look = p_focus + Vector3(0, 2.6, 0)
			rel = [[9.0, 3.0, 4.2], [-9.0, 3.0, 4.2], [3.0, 9.0, 4.2], [3.0, -9.0, 4.2], [11.0, 6.0, 7.0],
				[-11.0, -6.0, 7.0], [7.0, 0.0, 13.0]]
		_:
			return []
	var out: Array = []
	for r in rel:
		out.append({"pos": p_focus + f * float(r[0]) + right * float(r[1]) + Vector3(0, float(r[2]), 0), "look": look})
	return out


## A viewpoint is usable when: it is at least 1.2 m above the ground under it; nothing solid (world or
## player-built) is within LENS_CLEARANCE of it; the line to the look point is clear; nothing player-built is
## above it (not under one of her roofs). `ground_y` = ground height under `pos`.
static func shot_is_clear(space: PhysicsDirectSpaceState3D, pos: Vector3, look: Vector3, ground_y: float, exclude: Array = []) -> bool:
	if space == null or pos.y < ground_y + 1.2:
		return false
	var sphere := SphereShape3D.new()
	sphere.radius = LENS_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, pos)
	q.collision_mask = WORLD_MASK
	q.exclude = exclude
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var sight := PhysicsRayQueryParameters3D.create(look, pos, WORLD_MASK)
	sight.exclude = exclude
	if not space.intersect_ray(sight).is_empty():
		return false
	var sky := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, 30, 0), STRUCTURE_MASK)
	sky.exclude = exclude
	return space.intersect_ray(sky).is_empty()


## The first clear candidate as {"pos", "end" (a short dolly toward the look point, also checked), "look"},
## or {} when none is clear (the caller keeps the player's own camera).
static func pick_shot(space: PhysicsDirectSpaceState3D, candidates: Array, ground_fn: Callable, exclude: Array = []) -> Dictionary:
	for c in candidates:
		var pos: Vector3 = (c as Dictionary)["pos"]
		var look: Vector3 = (c as Dictionary)["look"]
		if not shot_is_clear(space, pos, look, float(ground_fn.call(pos.x, pos.z)), exclude):
			continue
		var end := pos.lerp(look, DOLLY)
		if not shot_is_clear(space, end, look, float(ground_fn.call(end.x, end.z)), exclude):
			continue
		return {"pos": pos, "end": end, "look": look}
	return {}


func _choose_shot() -> void:
	shot = {}
	if venue == "" or not is_inside_tree():
		return
	var hfn := func(x: float, z: float) -> float: return _ground(x, z)
	shot = pick_shot(get_world_3d().direct_space_state, candidate_shots(venue, focus, facing), hfn)


func _apply_shot() -> void:
	if shot.is_empty() or not is_inside_tree():
		return
	_prev_camera = get_viewport().get_camera_3d()
	camera = Camera3D.new()
	camera.name = "CelebrationCamera"
	camera.fov = float(Settings.get_value("fov"))
	add_child(camera)
	camera.global_position = shot["pos"]
	camera.look_at(shot["look"], Vector3.UP)
	camera.make_current()


# --- Running ---------------------------------------------------------------------------------------------------

## Plays the celebration; returns after `duration` seconds or when skipped. The lights stay until finish().
func play() -> void:
	if _finished or not is_inside_tree():
		return
	_choose_shot()
	_apply_shot()
	_playing = true
	await done


func _stop_playing() -> void:
	if not _playing:
		return
	_playing = false
	done.emit()


## Skip / end early (the same as a key press after SKIP_AFTER seconds).
func skip() -> void:
	skipped = true
	_stop_playing()


func _process(delta: float) -> void:
	_t += delta
	_update_sky()
	if camera != null and not shot.is_empty():
		var k := smoothstep(0.0, maxf(duration, 0.01), _t)
		camera.global_position = (shot["pos"] as Vector3).lerp(shot["end"], k)
		camera.look_at(shot["look"], Vector3.UP)
	if _playing and _t >= duration:
		_stop_playing()


func _input(event: InputEvent) -> void:
	if not _playing:
		return
	if _t >= SKIP_AFTER and is_skip_input(event):
		get_viewport().set_input_as_handled()
		skip()


## A deliberate press that may skip the celebration: a key press (not a held key's echo) or a mouse button press.
## The mouse wheel (and its horizontal tilt) never skips: a scroll to look around or a stray wheel tick must not
## cut the moment short.
static func is_skip_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var k := event as InputEventKey
		return k.pressed and not k.echo
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and not WHEEL_BUTTONS.has(mb.button_index)
	return false


## Restores the player's camera and removes the celebration (called after the ending screen).
func finish() -> void:
	if _finished:
		return
	_finished = true
	_stop_playing()
	_restore_camera()
	queue_free()


func _restore_camera() -> void:
	if camera == null:
		return
	var back: Camera3D = null
	if _prev_camera != null and is_instance_valid(_prev_camera) and _prev_camera.is_inside_tree():
		back = _prev_camera
	elif player != null and is_instance_valid(player) and player.has_method("get_camera"):
		var pc: Variant = player.get_camera()
		if pc is Camera3D and is_instance_valid(pc):
			back = pc
	if back != null:
		back.make_current()
	camera.current = false


func _exit_tree() -> void:
	# Freed with its area (an area change mid-ending): never leave the ending awaiting forever.
	_stop_playing()
	if not _finished:
		_restore_camera()
