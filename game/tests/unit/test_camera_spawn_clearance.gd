extends "res://tests/test_case.gd"
## Visual QA theme T1 regression (arrival / respawn cameras inside geometry: RE-00, RE-01, IN-00, IN-01, IN-03,
## IN-04, IN-05, IN-06). Every spawn of every Chapter Two area (plus the Chapter Two spawns on the surface) is
## loaded and the REAL follow camera (src/camera/camera_rig.gd, default 5 m zoom and pitch) is snapped behind a
## stand-in Krystal at the spawn exactly like Player.teleport() does. Once it has placed its arm:
##   * the arm is at least MIN_ARM long (the camera is not squeezed into her head); arrival / respawn spawns the
##     player sees after a load, a death or a ride (ARRIVALS) need MIN_ARRIVAL_ARM,
##   * no visible triangle of the area crosses the arm (her head -> the camera): nothing hides her,
##   * no visible triangle lies on screen within NEAR_CLEAR of the camera (the camera is not inside a lintel, bunting,
##     lantern glass, a lift roof or a door panel), no on-screen Label3D within LABEL_CLEAR (not flying through
##     letters), and at most MAX_VIEW_COVER of the view is filled by geometry within NEAR_VIEW (not framed by a prop
##     at the lens). Visible meshes are mirrored as trimeshes on a probe-only layer and checked with physics queries.
## Numbers per spawn are printed (arm, nearest surface) so a regression shows where and by how much.
## Also: the camera blockers are camera-only (no gameplay layer), and the Echo Trial plates fade near the camera.

const Rig := preload("res://src/camera/camera_rig.gd")
const CameraBlock := preload("res://src/camera/camera_block.gd")
const Logic := preload("res://src/player/player_logic.gd")
const EchoTrial := preload("res://src/world/areas_ch2/echo_trial.gd")
const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")

const ZOOM := 5.0
const MIN_ARM := 1.6
const MIN_ARRIVAL_ARM := 3.0
const NEAR_CLEAR := 0.25
const LABEL_CLEAR := 1.0
## Spawns seen right after a load, a death, a trial entry or a ride: they must show a proper third-person view.
const ARRIVALS := {
	"hallowmere_reach": ["waygate_arrival", "reach_respawn", "commons_arch", "orchard_arch", "quarry_arch", "manor_arch", "conservatory"],
	"tobin_annex": ["annex_lantern"],
	"hushed_works": ["crossing_gate", "vault_exit", "hw_lift_landing", "bell_throat"],
	"echo_trial": ["trial_start"],
	"surface": ["waygate", "annex_door"],
}
## Chapter Two spawns on the surface (src/world/surface/annexes.gd + c1x/tobin_door.gd). Both arrivals get the full
## arrival arm: "waygate" stands Annexes.WAYGATE_SPAWN_OFFSET (5.8 m) south of the Lanternwake gate (the gate's camera
## blocker also keeps the camera out of the lintel), "annex_door" 5.6 m out from Tobin's side door
## (TobinDoor.DOOR_SPAWN_LOCAL), so neither camera ends in the arch, the door leaf, its name plate or the cliff.
const SURFACE_CH2_SPAWNS := ["waygate", "annex_door", "annex_hatch"]
const TRIAL_FLAGS := ["chapter_one_complete", "weaver_defeated", "ward_restored", "ch2_accepted", "ch2_velour_defeated",
	"ch2_manor_restored", "ch2_crossing_cleared", "ch2_choir_defeated"]

var _probes: Dictionary = {}         # mesh instance id -> true once mirrored on the probe layer


func after_each() -> void:
	EchoTrial.pending_trial = ""
	await wait_frames(2)


func _load_area(id: String) -> Node3D:
	var ps: Variant = load(String(Game.AREAS[id]))
	if not (ps is PackedScene):
		fail("%s: scene is not a PackedScene" % id)
		return null
	var a: Node3D = (ps as PackedScene).instantiate()
	add_child(a)
	await wait_physics(3)
	return a


func _free(a: Node) -> void:
	if a != null and is_instance_valid(a):
		a.queue_free()
	_probes.clear()
	await wait_frames(2)


# --- The camera, exactly as the game places it ------------------------------------------------------------------

## Snaps the real rig behind a stand-in at the spawn and returns {cam, basis, fov, pivot, arm, arm_origin}.
func _camera_at(a: Node3D, xf: Transform3D) -> Dictionary:
	var stand := Node3D.new()
	stand.name = "StandInKrystal"
	a.add_child(stand)
	stand.global_position = xf.origin
	var rig: Node3D = Rig.new()
	a.add_child(rig)
	rig.call("setup", stand)
	rig.set("zoom_target", ZOOM)
	rig.set("_zoom", ZOOM)
	var f := -xf.basis.z
	f.y = 0.0
	var yaw := Logic.yaw_for_dir(f.normalized()) if f.length() > 0.01 else 0.0
	rig.call("snap", yaw)
	await wait_physics(1)
	await wait_frames(2)
	var cam: Camera3D = rig.call("get_camera")
	var out := {"cam": cam.global_position, "basis": cam.global_basis.orthonormalized(), "fov": cam.fov, "pivot": rig.global_position, "arm": float(rig.call("arm_length")),
		"arm_origin": (cam.get_parent() as Node3D).global_transform * Vector3(cam.position.x, 0.0, 0.0)}
	rig.queue_free()
	stand.queue_free()
	await wait_frames(1)
	return out


# --- Visible geometry near the camera ---------------------------------------------------------------------------
# Every visible mesh near a camera is mirrored as a trimesh on a probe-only physics layer (built once per mesh, in
# world space), so the checks run as C++ ray / sphere queries instead of GDScript triangle loops.

const PROBE_LAYER := 1 << 20
const NEAR_STEPS := [0.25, 0.4, 0.6, 1.0]
const VISIBLE_FROM := 0.1         # metres in front of the camera (its near plane is 0.05 m): closer is clipped
const NEAR_VIEW := 2.0            # "right at the lens": geometry this close covering the view
## At most this much of the first frame may be covered by geometry within NEAR_VIEW of the camera. Measured when this
## test was written: 0-1 % at every spawn after the fixes; before them 10-12 % at the Lantern Road arches (posts,
## bunting, lantern), 78 % at the Reach arrival (waygate lintel, lanterns), 16 % in Tobin's lantern niche, 58 % at the
## Wrong Landing lift, 32 % at vault_exit, 75-100 % in the three Echo Trials (pale door) and 22 % at the Woods gate.
const MAX_VIEW_COVER := 0.05
const VIEW_GRID := Vector2i(16, 9)


func _ensure_probes(a: Node3D, box: AABB) -> void:
	var root := a.get_node_or_null("CamProbe") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "CamProbe"
		a.add_child(root)
	for n in a.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var key := mi.get_instance_id()
		if _probes.has(key) or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if not (mi.global_transform * mi.get_aabb()).intersects(box):
			continue
		_probes[key] = true
		var faces := mi.mesh.get_faces()
		if faces.size() < 3:
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(mi.global_transform * faces)
		var body := StaticBody3D.new()
		body.collision_layer = PROBE_LAYER
		body.collision_mask = 0
		body.set_meta("mesh_path", _path_name(a, mi))
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)


## Visible mesh surfaces around the arm: {"blocked": [meshes crossing the arm], "near": the smallest NEAR_STEPS
## radius around the camera that touches a mesh ON SCREEN (INF if none), "near_name": that mesh}. Surfaces behind the
## camera, outside its view or clipped by its 5 cm near plane are not on screen and do not count.
func _probe_visuals(a: Node3D, from: Vector3, cam: Vector3, basis: Basis, fov: float) -> Dictionary:
	var box := AABB(from, Vector3.ZERO).expand(cam).grow(1.1).merge(AABB(cam, Vector3.ZERO).grow(NEAR_VIEW + 0.2))
	_ensure_probes(a, box)
	await wait_physics(1)
	var space := a.get_world_3d().direct_space_state
	var blocked: Array = []
	var ex: Array[RID] = []
	var arm_end := cam + (from - cam).normalized() * VISIBLE_FROM
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(from, arm_end, PROBE_LAYER, ex)
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var col: Object = hit["collider"]
		blocked.append(String((col as Node).get_meta("mesh_path", "?")) if col is Node else "?")
		ex.append(hit["rid"])
	var near := INF
	var near_name := ""
	var sph := SphereShape3D.new()
	for r in NEAR_STEPS:
		sph.radius = float(r)
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = sph
		sq.transform = Transform3D(Basis.IDENTITY, cam)
		sq.collision_mask = PROBE_LAYER
		var pts := space.collide_shape(sq, 32)
		var seen := false
		for k in range(1, pts.size(), 2):
			if _on_screen((pts[k] as Vector3) - cam, basis, fov):
				seen = true
				break
		if seen:
			near = float(r)
			var info := space.get_rest_info(sq)
			var col2: Object = instance_from_id(int(info.get("collider_id", 0))) if not info.is_empty() else null
			near_name = String((col2 as Node).get_meta("mesh_path", "?")) if col2 is Node else "?"
			break
	# How much of the screen is filled by something within NEAR_VIEW of the camera (a lintel, an arch frame, a lift
	# cage right at the lens): a grid of view rays; Krystal herself is not in the probe set.
	var close := 0
	var close_names := {}
	var tv := tan(deg_to_rad(fov) * 0.5)
	for gy in VIEW_GRID.y:
		for gx in VIEW_GRID.x:
			var sx := ((float(gx) + 0.5) / float(VIEW_GRID.x) * 2.0 - 1.0) * tv * (16.0 / 9.0)
			var sy := ((float(gy) + 0.5) / float(VIEW_GRID.y) * 2.0 - 1.0) * tv
			var dir := (-basis.z + basis.x * sx + basis.y * sy).normalized()
			var rq := PhysicsRayQueryParameters3D.create(cam + dir * VISIBLE_FROM, cam + dir * NEAR_VIEW, PROBE_LAYER)
			rq.hit_back_faces = true
			var rh := space.intersect_ray(rq)
			if not rh.is_empty():
				close += 1
				var rc: Object = rh["collider"]
				close_names[String((rc as Node).get_meta("mesh_path", "?")) if rc is Node else "?"] = true
	var cover := float(close) / float(VIEW_GRID.x * VIEW_GRID.y)
	return {"blocked": blocked, "near": near, "near_name": near_name, "cover": cover, "cover_names": close_names.keys()}


## True when a point (relative to the camera) is inside the camera's view (16:9) beyond VISIBLE_FROM.
static func _on_screen(rel: Vector3, basis: Basis, fov: float) -> bool:
	var z := -rel.dot(basis.z)
	if z <= VISIBLE_FROM:
		return false
	var tv := tan(deg_to_rad(fov) * 0.5)
	return absf(rel.dot(basis.y)) <= z * tv and absf(rel.dot(basis.x)) <= z * tv * (16.0 / 9.0)


## On-screen Label3Ds too close to the camera (a label that fades itself out there is fine).
func _labels_near(a: Node3D, cam: Vector3, basis: Basis, fov: float) -> Array:
	var out: Array = []
	for n in a.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if not l.is_visible_in_tree() or l.text.strip_edges() == "":
			continue
		var near_pt := l.global_position
		if l.billboard == BaseMaterial3D.BILLBOARD_DISABLED:
			var gb := l.global_transform * l.get_aabb()
			near_pt = Vector3(clampf(cam.x, gb.position.x, gb.end.x), clampf(cam.y, gb.position.y, gb.end.y), clampf(cam.z, gb.position.z, gb.end.z))
		var d := cam.distance_to(near_pt)
		if d >= LABEL_CLEAR or not _on_screen(near_pt - cam, basis, fov * 1.2):
			continue
		if l.visibility_range_begin > 0.0 and d < l.visibility_range_begin + l.visibility_range_begin_margin:
			continue
		if d < LABEL_CLEAR:
			out.append("%s (%.2f m)" % [_path_name(a, l), d])
	return out


static func _path_name(a: Node, n: Node) -> String:
	var p := String(a.get_path_to(n))
	return p if p.length() <= 90 else "..." + p.right(87)


# --- Per area ---------------------------------------------------------------------------------------------------

func _check_area(label: String, a: Node3D, ids: Array, arrivals: Array) -> void:
	if a == null:
		return
	var spawns: Dictionary = a.get("spawns")
	for id in ids:
		if not spawns.has(id):
			fail("%s: spawn %s missing" % [label, id])
			continue
		var xf: Transform3D = spawns[id]
		var c: Dictionary = await _camera_at(a, xf)
		var cam: Vector3 = c["cam"]
		var from: Vector3 = c["arm_origin"]
		var arm: float = c["arm"]
		var v: Dictionary = await _probe_visuals(a, from, cam, c["basis"], float(c["fov"]))
		var labels := _labels_near(a, cam, c["basis"], float(c["fov"]))
		var need := MIN_ARRIVAL_ARM if arrivals.has(id) else MIN_ARM
		var line := "    %s/%s: arm %.2f m (need %.1f), nearest surface < %.2f m (%s), view within %.0f m: %.0f%%%s%s" % [label, id, arm, need,
			float(v["near"]), String(v["near_name"]), NEAR_VIEW, float(v["cover"]) * 100.0,
			"" if (v["blocked"] as Array).is_empty() else ", BLOCKED by " + str(v["blocked"]),
			"" if labels.is_empty() else ", labels " + str(labels)]
		print(line)
		assert_true(arm >= need, "%s/%s: the camera arm has room (%.2f m, needs %.1f)" % [label, id, arm, need])
		assert_eq(v["blocked"], [], "%s/%s: nothing visible between Krystal and the camera" % [label, id])
		assert_true(float(v["near"]) > NEAR_CLEAR, "%s/%s: the camera is not inside %s (a surface within %.2f m)" % [label, id, v["near_name"], NEAR_CLEAR])
		assert_eq(labels, [], "%s/%s: no sign text at the camera" % [label, id])
		assert_true(float(v["cover"]) <= MAX_VIEW_COVER, "%s/%s: the first frame is not filled by a prop at the lens (%.0f%% within %.0f m: %s)" % [label, id,
			float(v["cover"]) * 100.0, NEAR_VIEW, str(v["cover_names"])])


func _all_ids(a: Node3D) -> Array:
	var ids: Array = (a.get("spawns") as Dictionary).keys()
	ids.sort()
	return ids


func _blockers_are_camera_only(label: String, a: Node3D) -> int:
	var n := 0
	for b in a.find_children(CameraBlock.NAME + "*", "StaticBody3D", true, false):
		var body := b as StaticBody3D
		n += 1
		assert_eq(body.collision_layer, CameraBlock.LAYER, "%s: %s is on the camera layer only" % [label, _path_name(a, body)])
		assert_eq(body.collision_mask, 0, "%s: %s detects nothing" % [label, _path_name(a, body)])
	return n


# --- Tests ------------------------------------------------------------------------------------------------------

func test_camera_layer_is_camera_only() -> void:
	assert_eq(Rig.COLLISION_MASK & CameraBlock.LAYER, CameraBlock.LAYER, "the follow camera collides with camera blockers")
	for mask in [1 | 32, 1, 16, 8, 2, 4]:
		assert_eq(int(mask) & CameraBlock.LAYER, 0, "gameplay mask %d ignores the camera layer" % int(mask))


func test_reach_spawns_give_the_camera_room() -> void:
	fresh_state()
	var a := await _load_area("hallowmere_reach")
	await _check_area("hallowmere_reach", a, _all_ids(a), ARRIVALS["hallowmere_reach"])
	assert_true(_blockers_are_camera_only("hallowmere_reach", a) >= 6, "the mirror waygate and the five arches carry camera blockers")
	await _free(a)


func test_annex_spawns_give_the_camera_room() -> void:
	fresh_state()
	var a := await _load_area("tobin_annex")
	await _check_area("tobin_annex", a, _all_ids(a), ARRIVALS["tobin_annex"])
	await _free(a)


func test_manor_spawns_give_the_camera_room() -> void:
	fresh_state()
	var a := await _load_area("moonveil_manor")
	await _check_area("moonveil_manor", a, _all_ids(a), [])
	await _free(a)


func test_works_spawns_give_the_camera_room() -> void:
	fresh_state()
	# How she stands there in play: she burned her way through the winch threads, and vault_exit is her respawn
	# only after the Choir (choir_arena.gd), when the portcullis in front of the exit alcove is open.
	for f in ["hw_thread_nook_burned", "hw_thread_winch_exit_burned", "ch2_choir_defeated"]:
		GameState.set_flag(f, true)
	var a := await _load_area("hushed_works")
	await _check_area("hushed_works", a, _all_ids(a), ARRIVALS["hushed_works"])
	assert_true(_blockers_are_camera_only("hushed_works", a) >= 3, "the deep lifts carry camera blockers")
	await _free(a)


func test_every_echo_trial_arrival_gives_the_camera_room() -> void:
	for trial in ["matron", "velour", "choir"]:
		fresh_state()
		for f in TRIAL_FLAGS:
			GameState.set_flag(f, true)
		EchoTrial.pending_trial = "" if trial == "matron" else String(trial)
		var a := await _load_area("echo_trial")
		if a == null:
			continue
		assert_eq(String(a.get("trial_id")), String(trial), "the %s trial is hosted" % trial)
		await _check_area("echo_trial:" + String(trial), a, ["trial_start"], ARRIVALS["echo_trial"])
		assert_eq(_blockers_are_camera_only("echo_trial:" + String(trial), a), 1, "the pale door carries a camera blocker")
		# IN-01: the title plate and the record line fade out near the camera, and walking in from the pad the
		# camera never meets one of them while it is still showing.
		var plates: Array = []
		for n in a.find_children("*", "Label3D", false, false):
			if n == a.get("record_label") or (n as Label3D).text.begins_with("Echo Trial"):
				plates.append(n)
		assert_true(plates.size() >= 2, "%s: title plate and record line" % trial)
		var start: Vector3 = (a.get_spawn("trial_start") as Transform3D).origin
		var ar: Dictionary = a.get("arena")
		var fit: float = float(ar.get("plate_width", EchoTrial.MATRON_PLATE_WIDTH))
		for p in plates:
			var l := p as Label3D
			assert_true(EchoTrial.label_width(l) <= fit + 0.01, "%s: '%s' fits its corridor (%.2f m <= %.2f m)" % [trial, l.text.left(24), EchoTrial.label_width(l), fit])
			assert_true(l.visibility_range_begin >= 2.0 and l.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF,
				"%s: plate '%s' fades near the camera" % [trial, l.text.left(24)])
			for k in 40:
				var her := start + Vector3(0, 0, -0.5 * float(k))
				var cam := her + Vector3(0.36, Rig.TARGET_HEIGHT + ZOOM * sin(-Rig.DEFAULT_PITCH), ZOOM * cos(Rig.DEFAULT_PITCH))
				var d := cam.distance_to(l.global_position)
				assert_true(d >= LABEL_CLEAR or d < l.visibility_range_begin, "%s: the camera meets '%s' only while it is faded (%.2f m)" % [trial, l.text.left(24), d])
		await _free(a)
	EchoTrial.pending_trial = ""


func test_surface_chapter_two_spawns_give_the_camera_room() -> void:
	fresh_state()
	var w: Node3D = SurfaceWorld.new()
	add_child(w)
	await wait_physics(3)
	var ids: Array = []
	for id in SURFACE_CH2_SPAWNS:
		ids.append(id)
	await _check_area("surface", w, ids, ARRIVALS["surface"])
	await _free(w)
