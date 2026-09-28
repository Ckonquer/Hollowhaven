extends "res://src/world/area_base.gd"
## Hollowhaven Woods (surface area root). Builds the whole area in code in _ready():
## terrain (height field, stream, pond, paths), sky & day/night, water, vegetation, landmarks,
## harvestable resource nodes, ambient life, audio, spawn points, zones and an invisible boundary.
## Public API (see docs/ARCHITECTURE.md "Area roots"):
##   height_at(x, z) -> float            exact ground height (matches the collision)
##   surface_at(pos: Vector3) -> String  "grass" | "stone" | "water" (footsteps)
##   water_level_at(x, z) -> float       water surface or -1000 when dry
##   play_restoration()                  awaitable ending bloom (~10 s)
##   get_zone_at / is_safe_zone / validate_position / on_player_spawned (area_base overrides)

const Layout := preload("res://data/world_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const Terrain := preload("res://src/world/surface/terrain.gd")
const SkyScript := preload("res://src/world/surface/sky.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const TerrainBody := preload("res://src/world/surface/terrain_body.gd")
const TERRAIN_SHADER := preload("res://shaders/surface_terrain.gdshader")
const WaterScript := preload("res://src/world/surface/water.gd")
const VegetationScript := preload("res://src/world/surface/vegetation.gd")
const GrassScript := preload("res://src/world/surface/grass.gd")
const LandmarksScript := preload("res://src/world/surface/landmarks.gd")
const AmbientScript := preload("res://src/world/surface/ambient_life.gd")
const Fx := preload("res://src/world/common/fx.gd")

const MUSIC_DAY := "music_haven"
const MUSIC_NIGHT := "music_night"
## Gentle pacing: the (looping) surface track plays for about two passes, fades out, and the woods
## are left to birds, wind and the stream for a while before the music returns.
const MUSIC_PLAY_SECONDS := 175.0
const MUSIC_REST_SECONDS := 70.0

var terrain: RefCounted
var terrain_material: ShaderMaterial
var sky: Node
var water: Node3D
var vegetation: Node3D
var grass: Node3D
var landmarks: Node3D
var ambient: Node3D
var bloom_root: Node3D
var bloom_material: ShaderMaterial
var build_times: Dictionary = {}
var restoring := false
var structure_mask: Image
var structure_mask_tex: ImageTexture
var _t_last := 0
var _tick := 0.0
var _audio_started := false
var _was_night := false
var _music_t := 0.0
var _music_on := false


func _ready() -> void:
	area_id = "surface"
	_t_last = Time.get_ticks_usec()
	var t_start := _t_last
	terrain = Terrain.new()
	terrain.generate()
	_mark("terrain_gen")
	sky = SkyScript.new()
	add_child(sky)
	var ground := Node3D.new()
	ground.name = "Terrain"
	add_child(ground)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	terrain_material.set_shader_parameter("splat_tex", ImageTexture.create_from_image(terrain.splat_image()))
	terrain_material.set_shader_parameter("path_color", Color("cdb084"))
	terrain_material.set_shader_parameter("path_edge_color", Color("a98a63"))
	terrain_material.set_shader_parameter("sand_color", Palette.SAND)
	terrain_material.set_shader_parameter("wet_color", Color("a38d63"))
	terrain_material.set_shader_parameter("rock_color", Palette.STONE)
	terrain_material.set_shader_parameter("rock_dark", Palette.STONE_DARK)
	terrain.build_meshes(ground, terrain_material)
	var body: StaticBody3D = terrain.build_collision(ground, TerrainBody)
	body.set("area", self)
	_mark("terrain_mesh")
	water = WaterScript.new()
	water.terrain = terrain
	add_child(water)
	_mark("water")
	build_times["water_detail"] = water.build_times
	var plan: Dictionary = VegetationScript.plan(terrain)
	_mark("veg_plan")
	VegetationScript.clear_grass_for(terrain, plan)
	preload("res://src/world/surface/annexes.gd").clear_grass(terrain)   # Chapter Two annex footprints
	vegetation = VegetationScript.new()
	vegetation.terrain = terrain
	vegetation.plan_data = plan
	add_child(vegetation)
	_mark("vegetation")
	build_times["veg_detail"] = vegetation.build_times
	grass = GrassScript.new()
	grass.terrain = terrain
	add_child(grass)
	_mark("grass")
	landmarks = LandmarksScript.new()
	landmarks.terrain = terrain
	add_child(landmarks)
	_mark("landmarks")
	build_times["landmark_detail"] = landmarks.build_times
	ambient = AmbientScript.new()
	ambient.terrain = terrain
	add_child(ambient)
	bloom_root = Node3D.new()
	bloom_root.name = "BloomFlowers"
	add_child(bloom_root)
	bloom_material = vegetation.build_restore_flowers(bloom_root)
	_mark("ambient")
	_register_spawns()
	_add_zones()
	_build_boundary()
	preload("res://src/world/surface/annexes.gd").build(self)   # Chapter Two additions (waygate, annexes)
	_mark("spawns")
	_apply_restored_state(bool(GameState.get_flag("ward_restored")))
	_update_daylight()
	_setup_structure_mask()
	build_times["total"] = float(Time.get_ticks_usec() - t_start) / 1000.0
	if OS.is_debug_build():
		print("SurfaceWorld: built in %.0f ms %s" % [build_times["total"], str(build_times)])


# --- Built structures hide grass & flowers underneath --------------------------------------------------

func _setup_structure_mask() -> void:
	structure_mask = Image.create(Terrain.N, Terrain.N, false, Image.FORMAT_R8)
	structure_mask_tex = ImageTexture.create_from_image(structure_mask)
	if grass != null:
		grass.grass_material.set_shader_parameter("occ_tex", structure_mask_tex)
	var flower_mats: Array = [bloom_material]
	for mmi in vegetation.flower_nodes:
		if mmi is GeometryInstance3D and (mmi as GeometryInstance3D).material_override != null and not flower_mats.has((mmi as GeometryInstance3D).material_override):
			flower_mats.append((mmi as GeometryInstance3D).material_override)
	for m in flower_mats:
		if m is ShaderMaterial:
			(m as ShaderMaterial).set_shader_parameter("occ_tex", structure_mask_tex)
	if not Events.structure_placed.is_connected(_on_structures_changed):
		Events.structure_placed.connect(_on_structures_changed)
		Events.structure_removed.connect(_on_structures_changed)
	rebuild_structure_mask()


func _on_structures_changed(_uid: String, _sid: String) -> void:
	rebuild_structure_mask.call_deferred()


## Marks the footprint of every structure in this area (GameState.structures) in the occupancy mask.
func rebuild_structure_mask() -> void:
	if structure_mask == null:
		return
	structure_mask.fill(Color(0, 0, 0))
	var half := float(Terrain.N - 1) * 0.5
	for uid in GameState.structures:
		var st: Dictionary = GameState.structures[uid]
		if String(st.get("area", "surface")) != "surface":
			continue
		var p: Variant = st.get("pos")
		if not (p is Array) or (p as Array).size() != 3:
			continue
		var def: Dictionary = ItemDB.structure(String(st.get("id", "")))
		var sz: Variant = def.get("size", Vector2i(1, 1))
		var ext := 1.0
		if sz is Vector2i:
			ext = float(maxi((sz as Vector2i).x, (sz as Vector2i).y))
		var r := ext * 0.5 + 0.35
		var cx := float(p[0]) + half
		var cz := float(p[2]) + half
		for j in range(maxi(0, int(floor(cz - r - 1.0))), mini(Terrain.N, int(ceil(cz + r + 1.0)) + 1)):
			for i in range(maxi(0, int(floor(cx - r - 1.0))), mini(Terrain.N, int(ceil(cx + r + 1.0)) + 1)):
				var d := Vector2(float(i) - cx, float(j) - cz).length()
				if d <= r + 0.5:
					structure_mask.set_pixel(i, j, Color(1, 0, 0))
	structure_mask_tex.update(structure_mask)


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25:
		return
	var dt := _tick
	_tick = 0.0
	_update_daylight()
	if _audio_started:
		_update_audio(dt)


func _update_daylight() -> void:
	var dl: float = sky.daylight if sky != null else 1.0
	if landmarks != null:
		landmarks.set_daylight(dl)
	if ambient != null:
		ambient.set_daylight(dl)


## Called by Game once Krystal is placed: starts the surface soundscape.
func on_player_spawned(_player: Node3D) -> void:
	_audio_started = true
	_was_night = bool(sky.is_night)
	Audio.play_ambience("amb_forest_night" if _was_night else "amb_forest_day", 4.0)
	_start_music()


func _start_music() -> void:
	_music_on = true
	_music_t = 0.0
	if Audio.music_director_active():
		return      # the music director (src/audio/music_director.gd) rotates the Haven/woods playlists
	Audio.play_music(MUSIC_NIGHT if bool(sky.is_night) else MUSIC_DAY, 4.0)


## Ambience follows day/night. Music: with the music director active it owns the surface playlists
## (day/night rotation, rests); otherwise the legacy cycle plays (MUSIC_PLAY_SECONDS) -> quiet rest
## -> play again. Called a few times per second. Never touches the music during cutscenes.
func _update_audio(dt: float) -> void:
	if restoring or Game.mode == "cutscene":
		return
	var night: bool = sky.is_night
	var legacy_music := not Audio.music_director_active()
	if night != _was_night:
		_was_night = night
		Audio.play_ambience("amb_forest_night" if night else "amb_forest_day", 4.0)
		if _music_on and legacy_music:
			Audio.play_music(MUSIC_NIGHT if night else MUSIC_DAY, 4.0)   # crossfade, keep the phase
	if not legacy_music:
		return
	_music_t += dt
	if _music_on and _music_t > MUSIC_PLAY_SECONDS:
		_music_on = false
		_music_t = 0.0
		var cur: String = Audio.current_music()
		if cur == MUSIC_DAY or cur == MUSIC_NIGHT:
			Audio.stop_music(8.0)       # only ever fade out our own tracks
		else:
			_music_on = true            # something else is playing (e.g. the ending theme): let it be
	elif not _music_on and _music_t > MUSIC_REST_SECONDS:
		_start_music()


func _mark(label: String) -> void:
	var now := Time.get_ticks_usec()
	build_times[label] = float(now - _t_last) / 1000.0
	_t_last = now


# --- Queries -------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain != null else 0.0


func water_level_at(x: float, z: float) -> float:
	return terrain.water_level_at(x, z) if terrain != null else -1000.0


func surface_at(pos: Vector3) -> String:
	return terrain.surface_at(pos.x, pos.z) if terrain != null else "grass"


func is_inside_bounds(pos: Vector3, margin: float = 0.0) -> bool:
	var lim := SL.BOUNDARY - margin
	return absf(pos.x) < lim and absf(pos.z) < lim and Vector2(pos.x, pos.z).length() < lim / 0.86


## Haven safe zone (Chapter Two, MP §3 / spec 7.1): the legacy "haven" zone (and any other safe zone), plus
## every buildable region of the expanded Haven (data/world_layout.gd BUILD_AREA "extra") with a
## HAVEN_SAFE_BUFFER margin. Only authored regions count: player-built lights never make a safe field.
## Cheap and allocation-free (the Game zone poll and enemies call it often).
const HAVEN_SAFE_BUFFER := 4.0

func is_safe_zone(pos: Vector3) -> bool:
	if super.is_safe_zone(pos):
		return true
	var p := Vector2(pos.x, pos.z)
	var ba: Dictionary = Layout.BUILD_AREA
	if p.distance_to(ba["center"]) <= float(ba["radius"]) + HAVEN_SAFE_BUFFER:
		return true
	var extra: Array = ba["extra"]
	for r in extra:
		if p.distance_to(r["center"]) <= float(r["radius"]) + HAVEN_SAFE_BUFFER:
			return true
	return false


## Saved positions must be on solid ground, inside the boundary and not under water. A bridge deck or
## stepping stone standing clearly above the stream bed is dry footing, even over deep water. Open-water
## depth is still measured to height_at() at the saved x/z (NOT to the ray hit: the stream is ~0.60 m
## deep almost everywhere and the terrain collider differs from height_at() by a few cm).
func validate_position(pos: Vector3) -> Variant:
	if not is_inside_bounds(pos, 2.0):
		return null
	var g: Variant = super.validate_position(pos)
	if not (g is Vector3):
		return null
	var gp: Vector3 = g
	if terrain != null and terrain.is_water(pos.x, pos.z):
		# super returns the hit + 0.1 m; a crossing's walkway is well above the bed it spans.
		var on_crossing: bool = gp.y - 0.1 > float(terrain.height_at(gp.x, gp.z)) + 0.25
		var wl: float = terrain.water_level_at(pos.x, pos.z)
		if not on_crossing and wl - float(terrain.height_at(pos.x, pos.z)) > 0.6:
			return null
	return gp


# --- Spawns, zones, boundary ------------------------------------------------------------------------------

## Yaw (radians) that makes a node at `from` face `to` (forward = -Z).
static func yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length() < 0.001:
		return 0.0
	return atan2(-d.x, -d.y)


func _spawn_xform(p: Vector2, look: Vector2) -> Transform3D:
	var y := height_at(p.x, p.y) + 0.08
	return Transform3D(Basis(Vector3.UP, yaw_towards(p, look)), Vector3(p.x, y, p.y))


func _register_spawns() -> void:
	var facing := {
		"haven_start": SL.WARD_STONE,
		"haven_respawn": SL.WARD_STONE,
		"mine_exit": Vector2.ZERO,
		"companion_wild_mochi": Vector2(-50, 12),
		"companion_wild_pebble": Vector2(58, -12),
		"companion_wild_lumi": Vector2(-12, -58),
		"companion_home_mochi": Vector2(0, 3),
		"companion_home_pebble": Vector2(0, 3),
		"companion_home_lumi": Vector2(0, 3),
		"mine_threshold": Vector2(20, -20),
	}
	var markers := Node3D.new()
	markers.name = "SpawnPoints"
	add_child(markers)
	for id in Layout.SPAWN_HINTS:
		var p: Vector2 = Layout.SPAWN_HINTS[id]
		var look: Vector2 = facing.get(id, Vector2.ZERO)
		var xf := _spawn_xform(p, look)
		register_spawn(id, xf)
		var m := Marker3D.new()
		m.name = "Spawn_" + String(id)
		markers.add_child(m)
		m.transform = xf


func _add_zones() -> void:
	for id in Layout.LANDMARKS:
		var l: Dictionary = Layout.LANDMARKS[id]
		var p: Vector2 = l["pos"]
		add_zone(id, Vector3(p.x, height_at(p.x, p.y), p.y), float(l["radius"]), id == "haven")


## Invisible walls just inside the hills: a rounded square ring of tall boxes.
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var b := SL.BOUNDARY
	var r := b / 0.86
	var pts: Array = []
	var segs := 64
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var d := Vector2(cos(a), sin(a))
		# Intersection of the ray with max(|x|,|z|) = b and |p| = r (whichever is closer).
		var t_sq := b / maxf(absf(d.x), absf(d.y))
		pts.append(d * minf(t_sq, r))
	for i in segs:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % segs]
		var mid := (p0 + p1) * 0.5
		var seg_len := p0.distance_to(p1) + 0.6
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(seg_len, 60.0, 1.0)
		cs.shape = sh
		var dir := (p1 - p0).normalized()
		cs.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), Vector3(mid.x, height_at(mid.x, mid.y) + 20.0, mid.y))
		body.add_child(cs)


# --- Restoration ------------------------------------------------------------------------------------------

## Instantly shows (or hides) the restored Haven: bright Ward Stone, lanterns, garlands, bloom flowers,
## warmer sky and the night-time firefly swirl.
func _apply_restored_state(on: bool) -> void:
	if landmarks != null:
		landmarks.set_restored_instant(on)
		if landmarks.ward_stone != null:
			landmarks.ward_stone.set_restored(1.0 if on else 0.0)
	if bloom_material != null:
		bloom_material.set_shader_parameter("bloom_radius", 100000.0 if on else 0.0)
	if bloom_root != null:
		bloom_root.visible = on
	if sky != null:
		sky.warmth = 1.0 if on else 0.0
	if ambient != null and on:
		ambient.start_swirl(false)


## The ending bloom (~10 s, awaitable): a column of warm light rises from the Ward Stone, a ring of
## light and flowers sweeps across the Haven, lanterns and garlands appear, fireflies swirl and the sky warms.
func play_restoration() -> void:
	if landmarks == null or landmarks.ward_stone == null:
		return
	restoring = true
	var ws: Node3D = landmarks.ward_stone
	var center: Vector3 = ws.global_position
	if Audio.has_sound("ward_restore"):
		Audio.play_sfx("ward_restore", 0.0, 0.0)
	if Audio.has_sound("music_ending"):
		Audio.request_music("restoration", "music_ending", 1.5)     # m14, once (released after the ending)
	Events.camera_shake.emit(0.18, 0.8)
	Events.caption.emit("[The Ward Stone hums, warm and bright]")
	var cine := _start_cinematic_camera(center)
	var column := _make_light_column(center)
	var ring := _make_shock_ring(center)
	ambient.start_swirl(true)
	ws.play_glow_burst(3.0)
	Fx.burst(self, center + Vector3(0, 1.8, 0.4), "sparkle", 3.0)
	bloom_root.visible = true
	bloom_material.set_shader_parameter("bloom_radius", 0.0)
	landmarks.restore_group.visible = true
	var set_bloom := func(r: float) -> void:
		bloom_material.set_shader_parameter("bloom_radius", r)
	var set_ring := func(a: float) -> void:
		_set_ring_alpha(ring, a)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(column, "scale:y", 1.0, 1.4).from(0.01).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(set_bloom, 0.0, 40.0, 6.0).set_delay(1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ring, "scale", Vector3(40.0, 1.0, 40.0), 6.0).from(Vector3(0.5, 1.0, 0.5)).set_delay(1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(set_ring, 1.0, 0.0, 2.5).set_delay(4.7)
	tw.tween_property(sky, "warmth", 1.0, 7.0).set_delay(0.5)
	var items: Array = landmarks.restore_items
	for i in items.size():
		var node: Node3D = items[i][0]
		var target: Vector3 = items[i][1]
		node.scale = Vector3.ONE * 0.01
		var d := Vector2(node.global_position.x - center.x, node.global_position.z - center.z).length()
		var delay := 1.4 + d / 40.0 * 6.0
		tw.tween_property(node, "scale", target, 0.6).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var pop := func() -> void:
			if is_instance_valid(node):
				Fx.burst(self, node.global_position + Vector3(0, 2.0, 0), "sparkle", 0.6)
		tw.tween_callback(pop).set_delay(delay + 0.2)
	tw.tween_property(column, "scale:x", 0.01, 1.5).set_delay(7.8)
	tw.tween_property(column, "scale:z", 0.01, 1.5).set_delay(7.8)
	await get_tree().create_timer(10.0, false).timeout
	_end_cinematic_camera(cine)
	if is_instance_valid(column):
		column.queue_free()
	if is_instance_valid(ring):
		ring.queue_free()
	_apply_restored_state(true)
	restoring = false
	Audio.play_ambience("amb_forest_night" if sky.is_night else "amb_forest_day", 3.0)
	_was_night = bool(sky.is_night)
	_music_on = true      # the ending theme (then the UI's Haven theme) is playing now
	_music_t = 0.0


func _make_light_column(center: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "LightColumn"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 1.3
	cyl.height = 40.0
	cyl.radial_segments = 20
	cyl.cap_top = false
	cyl.cap_bottom = false
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.86, 0.6, 0.16)
	m.emission_enabled = true
	m.emission = Palette.WARD_GLOW
	m.emission_energy_multiplier = 0.7
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 2.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = center + Vector3(0, 20.0, 0)
	mi.scale = Vector3(1, 0.01, 1)
	return mi


func _make_shock_ring(center: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "BloomRing"
	var tor := TorusMesh.new()
	tor.inner_radius = 0.92
	tor.outer_radius = 1.0
	tor.rings = 64
	tor.ring_segments = 6
	mi.mesh = tor
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.85, 0.6, 0.8)
	m.emission_enabled = true
	m.emission = Palette.WARD_GLOW
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = center + Vector3(0, 0.25, 0)
	mi.scale = Vector3(0.5, 1.0, 0.5)
	return mi


func _set_ring_alpha(ring: MeshInstance3D, a: float) -> void:
	if is_instance_valid(ring) and ring.material_override is StandardMaterial3D:
		var m := ring.material_override as StandardMaterial3D
		m.albedo_color.a = 0.8 * a
		m.emission_energy_multiplier = 2.0 * a


## A slow rising orbit around the Ward Stone. Restores the previous camera afterwards.
func _start_cinematic_camera(center: Vector3) -> Dictionary:
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "RestorationCamera"
	cam.fov = 60.0
	cam.far = 600.0
	add_child(cam)
	var start_yaw := 0.0
	if prev != null:
		var off := prev.global_position - center
		start_yaw = atan2(off.x, off.z)
	var place := func(t: float) -> void:
		if not is_instance_valid(cam):
			return
		var yaw := start_yaw + t * 1.1
		var dist := lerpf(7.0, 17.0, t)
		var hgt := lerpf(2.2, 9.0, t)
		var pos := center + Vector3(sin(yaw) * dist, hgt, cos(yaw) * dist)
		var look := center + Vector3(0, lerpf(1.8, 0.5, t), 0)
		cam.global_position = pos
		if pos.distance_to(look) > 0.01:
			cam.look_at(look, Vector3.UP)
	place.call(0.0)
	cam.make_current()
	var tw := create_tween()
	tw.tween_method(place, 0.0, 1.0, 9.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return {"cam": cam, "prev": prev, "tween": tw}


func _end_cinematic_camera(c: Dictionary) -> void:
	var tw: Tween = c.get("tween")
	if tw != null and tw.is_valid():
		tw.kill()
	var prev: Variant = c.get("prev")
	if prev != null and is_instance_valid(prev):
		(prev as Camera3D).make_current()
	var cam: Variant = c.get("cam")
	if cam != null and is_instance_valid(cam):
		(cam as Camera3D).queue_free()
