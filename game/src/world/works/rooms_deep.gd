extends RefCounted
## Hushed Works rooms 9-14 (works module B; MP §10 rooms 9-14, §13.2, §13.3, §14; spec §7.4, §10).
## Called by the Works area script (src/world/areas_ch2/hushed_works_world.gd, works module C7):
##   var b = Builder.new(self, seed, merged_rooms)      # data/works_layout.gd ROOMS + data/works_layout_deep.gd ROOMS
##   ... rooms 1-8 ...
##   RoomsDeep.build(self, b)                          # BEFORE b.finish(): our visuals are batched too
##   b.finish()
## Contract with the hub (room 7): its EAST wall (x 40..41) carries the lower ward door, centre
## Layout.HUB_DOOR (40, -18, 0), opening z [-1.5, 1.5] (at most [-1.6, 1.6]), 3.4 m tall; room 9's west side
## is "all" and its corridor (hw_winch_way, z -2..2) closes around that door.
##
## What build() adds to the area. The Works area API is used when present (place_spawn, add_checkpoint,
## add_safe_room, add_anchor, register_mood, director_hold/_release/_suppress, set_fight); otherwise only
## area_base.gd is assumed (tests / previews: src/world/works/deep/deep_preview_host.gd):
##   * geometry for rooms 9-14 through the shared Builder (begin / shell / dress_room_rock / Props), our own
##     dressing RNG (Layout.DRESS_SEED; the builder's rng state is restored afterwards);
##   * a "WorksDeep" controller node (deep/deep_controller.gd) holding every interactive node (threads, the
##     Wrong Landing lifts + room 9's winch cage back down, arenas, porch, Bell Throat, the winch moment);
##   * spawns crossing_gate, bell_throat, vault_exit (+ hw_wrong_siding, hw_lift_landing);
##   * checkpoint lanterns hw_crossing_gate / hw_bell_throat (checkpoint_lantern.gd, area "hushed_works");
##   * safety: the whole Bell Throat (add_safe_room, else a safe circle) + the checkpoints;
##   * zones: the area registers every merged room's zone; without that API one circle per deep zone;
##   * director anchors (Layout.ANCHORS: winch ceiling, wrong-landing spawn anchors for WORKS_EVENTS);
##   * per-zone light temperature / ambience (Layout.MOODS / AMBIENCE through register_mood; the vault's
##     loop is choir_arena.gd vault_ambience(): calm once ch2_choir_defeated).

const Layout := preload("res://data/works_layout_deep.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const Controller := preload("res://src/world/works/deep/deep_controller.gd")
const ThreadScript := preload("res://src/world/works/deep/deep_thread.gd")
const LiftScript := preload("res://src/world/works/deep/deep_lift.gd")
const CrossingArena := preload("res://src/world/works/deep/crossing_arena.gd")
const ChoirArena := preload("res://src/world/works/deep/choir_arena.gd")
const PorchScript := preload("res://src/world/works/deep/porch.gd")
const ThroatScript := preload("res://src/world/works/deep/throat.gd")
const WinchMoment := preload("res://src/world/works/deep/winch_moment.gd")
const Checkpoint := preload("res://src/world/below/checkpoint_lantern.gd")
const SpiderDecor := preload("res://src/world/below/spider_decor.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")

const OUT := {"outline": true, "outline_w": 0.018}
const WINCH_ROCK := [Color("4e4038"), Color("5c4a3e"), Color("43362f")]
const SLATE_ROCK := [Color("46505e"), Color("3b4452"), Color("515c6a")]
const PORCH_ROCK := [Color("3a3044"), Color("2e2638"), Color("463a52")]
const SAND_ROCK := [Color("a88a62"), Color("97795a"), Color("b8986c")]
const BRIDGE_IRON := Color("56606e")
const ROPE := Color("c9a66b")


static func build(area: Node3D, b: Builder) -> void:
	var t0 := Time.get_ticks_usec()
	var saved_seed: int = b.rng.seed
	var saved_state: int = b.rng.state
	b.rng.seed = Layout.DRESS_SEED
	var ctl: Node3D = Controller.new()
	ctl.name = "WorksDeep"
	ctl.call("setup", area)
	area.add_child(ctl)
	var decor: Node3D = SpiderDecor.new()
	decor.name = "DeepDecor"
	ctl.add_child(decor)
	var times: Dictionary = ctl.get("build_times")
	_register_spawns(area, ctl)
	times["setup"] = _ms(t0)
	_winch(b, area, ctl, decor)
	times["winch"] = _ms(t0)
	_gate(b, area, ctl)
	times["gate"] = _ms(t0)
	_crossing(b, area, ctl, decor)
	times["crossing"] = _ms(t0)
	_wrong_landing(b, area, ctl)
	times["wrong_landing"] = _ms(t0)
	_porch(b, area, ctl)
	times["porch"] = _ms(t0)
	_throat(b, area, ctl)
	times["throat"] = _ms(t0)
	_vault(b, area, ctl)
	times["vault"] = _ms(t0)
	_register_zones(area)
	_register_moods(area)
	_director_anchors(area, ctl)
	decor.call("build")
	times["decor"] = _ms(t0)
	ctl.call("apply_winch_lamps")
	b.rng.seed = saved_seed
	b.rng.state = saved_state
	ctl.set("build_ms", float(Time.get_ticks_usec() - t0) / 1000.0)
	if OS.is_debug_build():
		print("Hushed Works rooms 9-14: %s" % str(times))


# --- Registration -------------------------------------------------------------------------------------

static func _register_spawns(area: Node3D, ctl: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "DeepSpawns"
	ctl.add_child(holder)
	for id in Layout.SPAWNS:
		var s: Dictionary = Layout.SPAWNS[id]
		var xf := Layout.spawn_xform(id)
		if area.has_method("place_spawn"):
			area.call("place_spawn", String(id), s["pos"], float(s["yaw"]))     # Works area API (+0.05 lift)
		else:
			area.call("register_spawn", id, xf)
		var m := Marker3D.new()
		m.name = "Spawn_" + String(id)
		holder.add_child(m)
		m.transform = xf


## True when the area already knows our room table (the real Works area merges it and registers every
## room's zone and safety itself).
static func _area_has_our_rooms(area: Node3D) -> bool:
	var rooms: Variant = area.get("rooms")
	return rooms is Dictionary and (rooms as Dictionary).has("hw_winch") and area.has_method("add_safe_room")


static func _register_zones(area: Node3D) -> void:
	if _area_has_our_rooms(area):
		for id in Layout.ROOMS:
			if bool((Layout.ROOMS[id] as Dictionary).get("safe", false)):
				area.call("add_safe_room", String(id))
		return
	var known := {}
	var zs: Variant = area.get("zones")
	if zs is Array:
		for z in zs:
			if z is Dictionary:
				known[String((z as Dictionary).get("id", ""))] = true
	for design in Layout.DESIGN_ROOMS:
		var rid: String = Layout.DESIGN_ROOMS[design]
		var zone := Layout.zone_of_room(rid)
		if known.has(zone):
			continue
		var r: Dictionary = Layout.ROOMS[rid]
		var c := Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, float(r["y"]), (float(r["z0"]) + float(r["z1"])) * 0.5)
		var rad := Vector2(float(r["x1"]) - float(r["x0"]), float(r["z1"]) - float(r["z0"])).length() * 0.5
		area.call("add_zone", zone, c, rad, false)
		known[zone] = true
	var ts: Dictionary = Layout.THROAT_SAFE
	add_safe(area, ts["center"], float(ts["radius"]), "hw_throat")


## Our light temperatures and ambience per zone, through the Works area's register_mood when present.
## The vault's loop comes from the arena: the Choir's until ch2_choir_defeated, calm on a won save's builds.
static func _register_moods(area: Node3D) -> void:
	if not area.has_method("register_mood"):
		return
	for zone in Layout.MOODS:
		var amb := String(Layout.AMBIENCE.get(zone, ""))
		if String(zone) == ChoirArena.VAULT_ZONE:
			amb = ChoirArena.vault_ambience()
		area.call("register_mood", String(zone), (Layout.MOODS[zone] as Dictionary).duplicate(), amb)


## Adds a safe circle through whatever the area offers (deep_art.gd add_safe).
static func add_safe(area: Node3D, center: Vector3, radius: float, zone: String) -> void:
	Art.add_safe(area, center, radius, zone)


## A checkpoint lantern: the Works area's add_checkpoint (lantern + safe nook) when present, else our own
## checkpoint_lantern.gd (safe once lit, like the Below's lanterns).
static func _checkpoint(area: Node3D, ctl: Node3D, parent: Node3D, id: String) -> Node3D:
	var d: Dictionary = Layout.CHECKPOINTS[id]
	var pos: Vector3 = d["pos"]
	var zone := String(d["zone"])
	var cp: Node3D = null
	if area.has_method("add_checkpoint"):
		cp = area.call("add_checkpoint", id, pos, String(d["spawn"]), zone)
	if cp == null:
		cp = Checkpoint.new()
		cp.setup({"id": id, "spawn": String(d["spawn"]), "zone": zone, "area": Layout.AREA_ID})
		cp.name = "Checkpoint_" + id
		parent.add_child(cp)
		cp.position = pos
		cp.rotation_degrees.y = float(d["yaw"])
		var cps: Variant = area.get("checkpoints")
		if cps is Dictionary:
			(cps as Dictionary)[id] = cp
		if bool(cp.get("lit")):
			add_safe(area, pos, Layout.SAFE_RADIUS, zone)
		cp.connect("lit_changed", func(_cid: String, lit: bool) -> void:
			if lit:
				add_safe(area, pos, Layout.SAFE_RADIUS, zone))
	(ctl.get("checkpoints") as Dictionary)[id] = cp
	return cp


static func _director_anchors(area: Node3D, ctl: Node3D) -> void:
	if area.has_method("add_anchor"):
		for a in Layout.ANCHORS:
			area.call("add_anchor", String(a[0]), String(a[1]), String(a[2]), a[3])
		return
	var holder := Node3D.new()
	holder.name = "DirectorAnchors"
	ctl.add_child(holder)
	var i := 0
	for a in Layout.ANCHORS:
		var m := Marker3D.new()
		m.name = "Anchor_%d" % i
		m.add_to_group("director_anchor")
		m.set_meta("room", String(a[0]))
		m.set_meta("zone", String(a[1]))
		m.set_meta("kind", String(a[2]))
		holder.add_child(m)
		m.position = a[3]
		i += 1


static func _lamp(parent: Node3D, pos: Vector3, color: Color, energy: float, rng_: float, style: String = "wall", yaw: float = 0.0, extra: Dictionary = {}) -> Node3D:
	var o := {"style": style, "color": color, "energy": energy, "range": rng_, "yaw": yaw, "idle": 0.05}
	o.merge(extra, true)
	return Props.lamp(parent, pos, o)


static func _rail_run(b: Builder, a: Vector3, c: Vector3, color: Color) -> void:
	## A guardrail from floor point a to c (straight, level): posts every ~2 m, two rails, a 1.8 m collider.
	var d := c - a
	var length := d.length()
	if length < 0.1:
		return
	var dir := d / length
	var basis := Basis.looking_at(dir, Vector3.UP)
	var n := maxi(int(length / 2.0), 1)
	for i in n + 1:
		var p := a + dir * (length * float(i) / float(n))
		b.vbox(p + Vector3(0, 0.55, 0), Vector3(0.14, 1.1, 0.14), color, basis, OUT)
	var mid := (a + c) * 0.5
	b.vbox(mid + Vector3(0, 1.1, 0), Vector3(0.1, 0.1, length), color, basis, OUT)
	b.vbox(mid + Vector3(0, 0.6, 0), Vector3(0.07, 0.07, length), color, basis, {"shadows": false})
	b.col_box(mid + Vector3(0, 0.9, 0), Vector3(0.2, 1.8, length), "stone", basis)


# --- 9 Threaded Winch ------------------------------------------------------------------------------------

static func _winch(b: Builder, area: Node3D, ctl: Node3D, decor: Node3D) -> void:
	var y := -18.0
	b.begin("hw_winch_way")
	b.shell("hw_winch_way", Art.PLATE, Art.IRON_RUST.darkened(0.25), Art.IRON)
	Props.timber_frame(b, 42.0, -2.0, 2.0, y, 3.6, "z")
	var n := b.begin("hw_winch")
	b.shell("hw_winch", Art.PLATE, Color("4a3c34"), Color("2e2628"))
	b.dress_room_rock("hw_winch", WINCH_ROCK, {"height_frac": 0.72, "size": 1.15, "spacing": 1.55})
	# riveted iron floor plates
	for i in 6:
		for j in 6:
			var px := 45.5 + float(i) * 2.9
			var pz := -7.5 + float(j) * 2.95
			b.vbox(Vector3(px, y + 0.012, pz), Vector3(2.7, 0.024, 2.75), Art.PLATE.lightened(0.06) if (i + j) % 2 == 0 else Art.PLATE.darkened(0.08), Basis.IDENTITY, {"shadows": false})
	# timber buttresses (the south wall keeps the nook mouth clear)
	for x in [46.0, 50.8, 55.6, 60.4]:
		for side in [-1.0, 1.0]:
			if side > 0.0 and x > 46.2 and x < 51.8:
				continue
			var pz: float = side * 8.62
			b.vbox(Vector3(x, y + 4.6, pz), Vector3(0.42, 9.2, 0.42), b.vary(Art.TIMBER, 0.06), Basis.IDENTITY, OUT)
			b.col_box(Vector3(x, y + 4.6, pz), Vector3(0.42, 9.2, 0.42), "wood")
			b.vbox(Vector3(x, y + 8.8, pz - side * 0.9), Vector3(0.3, 0.3, 2.0), Art.TIMBER_DARK, Basis(Vector3.RIGHT, side * 0.7), OUT)
	# the winch: a huge drum on timber trestles, its cable rising into a dark shaft
	var d: Vector3 = Layout.WINCH["drum"]
	var along := Basis(Vector3(0, 0, 1), PI * 0.5)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.vbox(Vector3(d.x + sx * 2.8, y + 1.7, d.z + sz * 1.05), Vector3(0.36, 3.4, 0.36), b.vary(Art.TIMBER, 0.05), Basis(Vector3(0, 0, 1), sx * 0.12), OUT)
		b.vbox(Vector3(d.x + sx * 2.8, y + 3.3, d.z), Vector3(0.4, 0.4, 2.6), Art.TIMBER_DARK, Basis.IDENTITY, OUT)
	b.vcyl(Vector3(d.x, y + 2.6, d.z), 1.25, 4.6, Art.IRON_RUST, along, OUT)
	b.vcyl(Vector3(d.x, y + 2.6, d.z), 1.3, 3.0, Color("6a5a48"), along)
	for sx in [-2.1, 0.0, 2.1]:
		b.vcyl(Vector3(d.x + sx, y + 2.6, d.z), 1.34, 0.16, Art.IRON, along)
	b.vcyl(Vector3(d.x - 2.5, y + 2.6, d.z), 1.6, 0.18, Art.IRON, along, OUT)
	b.vcyl(Vector3(d.x, y + 7.9, d.z - 1.2), 0.07, 8.2, Art.IRON)
	b.vbox(Vector3(d.x, y + 11.96, d.z - 1.2), Vector3(1.8, 0.1, 1.8), Color(0.04, 0.03, 0.04), Basis.IDENTITY, {"shadows": false})
	b.col_box(Vector3(d.x, y + 1.9, d.z), Vector3(6.2, 3.8, 2.9), "wood")
	# the overhead service gantry: the visible route along the north wall, into dark holes at both ends
	var gy := float(Layout.WINCH["gantry_y"])
	var gz := float(Layout.WINCH["gantry_z"])
	var gx: Array = Layout.WINCH["gantry_x"]
	var gl := float(gx[1]) - float(gx[0])
	var gm := (float(gx[0]) + float(gx[1])) * 0.5
	b.vbox(Vector3(gm, gy - 0.06, gz), Vector3(gl, 0.12, 1.1), Art.IRON, Basis.IDENTITY, OUT)
	for side in [-1.0, 1.0]:
		b.vbox(Vector3(gm, gy + 0.9, gz + side * 0.55), Vector3(gl, 0.07, 0.07), Art.IRON_RUST, Basis.IDENTITY, {"shadows": false})
	var hx := float(gx[0]) + 1.0
	while hx < float(gx[1]):
		b.vcyl(Vector3(hx, (gy + y + 12.0) * 0.5, gz), 0.035, y + 12.0 - gy, Art.IRON)
		b.vbox(Vector3(hx, gy + 0.45, gz + 0.55), Vector3(0.06, 0.9, 0.06), Art.IRON_RUST, Basis.IDENTITY, {"shadows": false})
		hx += 2.8
	for ex in [float(gx[0]) - 0.45, float(gx[1]) + 0.45]:
		b.vbox(Vector3(ex, gy + 1.0, gz), Vector3(0.1, 2.2, 1.3), Color(0.03, 0.02, 0.03), Basis.IDENTITY, {"shadows": false})
	# clutter
	Props.crate(b, Vector3(58.6, y, 7.2), 0.9, 12.0)
	Props.crate(b, Vector3(59.6, y, 6.2), 0.7, -8.0)
	Props.barrel(b, Vector3(45.4, y, 7.4))
	Props.rope_coil(b, Vector3(46.4, y, -7.6))
	Props.rope_coil(b, Vector3(52.2, y, -7.9))
	Props.pickaxe_lean(b, Vector3(61.4, y, 6.6), -90.0)
	b.pebbles(44.5, 61.5, -8.5, 8.5, y, WINCH_ROCK, 26)
	# light: a cold shaft light over the winch, dim work lamps (the nook switch wakes them), a gantry lamp
	Props.glow_light(n, Vector3(d.x, y + 9.5, d.z + 1.5), Color("a8c4e8"), 1.1, 12.0)
	for spec in [[Vector3(45.6, y + 3.4, 8.9), 180.0], [Vector3(56.0, y + 3.4, 8.9), 180.0], [Vector3(60.0, y + 3.4, -8.9), 0.0]]:
		var l := _lamp(n, spec[0], Palette.MINE_LIGHT, 1.3, 8.5, "wall", float(spec[1]))
		(ctl.get("winch_lamps") as Array).append(l)
	_lamp(n, Vector3(gm + 2.0, gy + 0.02, gz), Color("b8d0f0"), 0.6, 5.0, "floor")
	# the winch plate (reading it holds the moment: never an event while she reads)
	Props.sign_board(b, Vector3(44.08, y + 1.7, -3.4), 90.0, 1.3, 0.7, Color("6a5a48"))
	var plate := Art.label(n, "WINCH No. 3", Vector3(44.14, y + 1.78, -3.4), 30, Color("f3e6c8"))
	plate.rotation_degrees = Vector3(0, 90, 0)
	var sign_it: Node3D = Interactable.new()
	sign_it.setup({"text": "Read the winch plate", "size": Vector3(1.0, 1.2, 1.6), "offset": Vector3(0.5, 1.7, 0),
		"handler": func(_p: Node) -> void: _read_winch_plate(ctl), "id": "hw_winch_plate"})
	sign_it.name = "WinchPlate"
	n.add_child(sign_it)
	sign_it.position = Vector3(44.1, y, -3.4)
	# the winch cage: loop B back down (usable once a lift up has been ridden)
	var cage_d: Dictionary = Layout.WINCH_CAGE
	var cage: Node3D = LiftScript.new()
	cage.setup({"id": "hw_winch_cage", "kind": "true", "requires_flag": String(cage_d["flag"]),
		"text": "Ride the winch cage down", "locked_text": "The cage's brake is chained from somewhere below",
		"sign": "WINCH CAGE - DOWN", "handler": Callable(ctl, "_on_lift")})
	cage.name = "Lift_hw_winch_cage"
	n.add_child(cage)
	cage.position = cage_d["pos"]
	cage.rotation.y = PI                  # mouth (local -z) faces south, into the hall
	(ctl.get("lifts") as Dictionary)["hw_winch_cage"] = cage
	# the teaching nook: behind a thread veil, the work-lamp switch
	var nook := b.begin("hw_winch_nook")
	b.shell("hw_winch_nook", Art.PLATE, Color("4a3c34"), Color("2e2628"))
	var sw: Vector3 = Layout.WINCH["switch"]
	b.vbox(sw + Vector3(0, 1.2, 0.35), Vector3(0.7, 0.9, 0.12), Art.IRON, Basis.IDENTITY, OUT)
	b.vbox(sw + Vector3(0.12, 1.3, 0.22), Vector3(0.08, 0.5, 0.08), Color("c84b3c"), Basis(Vector3.RIGHT, -0.5), OUT)
	var sw_it: Node3D = Interactable.new()
	sw_it.setup({"size": Vector3(1.2, 1.4, 1.2), "offset": Vector3(0, 1.2, 0), "accent": true,
		"handler": func(_p: Node) -> void: ctl.call("switch_winch_lamps"),
		"text_func": func() -> Dictionary: return {"text": "Switch the work lamps %s" % ("off" if bool(ctl.call("winch_lamps_on")) else "on"), "enabled": true},
		"id": "hw_winch_switch"})
	sw_it.name = "LampSwitch"
	nook.add_child(sw_it)
	sw_it.position = sw
	Props.crate(b, Vector3(47.4, y, 11.6), 0.7, 20.0)
	# threads (the Weaver's recent trail): the nook veil teaches, the exit veil is the first real use
	for id in Layout.THREADS:
		var td: Dictionary = Layout.THREADS[id]
		var t: Node3D = ThreadScript.new()
		t.setup({"id": id, "width": float(td["width"]), "height": float(td["height"]), "flag": String(td["flag"]),
			"teach": bool(td.get("teach", false)), "dissolve_flag": "ch2_crossing_cleared"})
		t.name = String(id)
		n.add_child(t)
		t.position = td["pos"]
		t.rotation.y = 0.0 if String(td["axis"]) == "x" else PI * 0.5
		(ctl.get("threads") as Dictionary)[id] = t
	# old trail dressing (webs, or pale roots with arachnophobia: SpiderDecor swaps it)
	decor.call("add_web", Vector3(44.9, y + 9.4, -8.2), Vector3(1, 0, 1).normalized(), 2.6, 0.8)
	decor.call("add_web", Vector3(61.1, y + 8.8, 8.2), Vector3(-1, 0, -1).normalized(), 2.2, 0.7)
	decor.call("add_web", Vector3(61.1, y + 9.8, -8.2), Vector3(-1, 0, 1).normalized(), 2.4, 0.9)
	for s in [[Vector3(50.0, gy - 0.1, gz + 0.4), Vector3(50.6, y + 4.4, d.z - 1.2)], [Vector3(55.2, gy - 0.1, gz + 0.4), Vector3(55.0, y + 3.2, d.z - 1.0)],
			[Vector3(58.6, y + 11.8, 3.0), Vector3(58.9, y + 6.5, 3.3)], [Vector3(47.5, y + 11.8, 4.0), Vector3(47.2, y + 7.0, 4.4)]]:
		decor.call("add_strand", s[0], s[1])
	decor.call("add_sheet", Vector3(55.5, y + 11.6, 3.5), Vector2(5.0, 4.0), 0.7)
	# the moment
	var wm: Node3D = WinchMoment.new()
	wm.setup({"controller": ctl})
	wm.name = "WinchMoment"
	ctl.add_child(wm)
	ctl.set("winch", wm)


static func _read_winch_plate(ctl: Node3D) -> void:
	var w: Variant = ctl.get("winch")
	if w is Node:
		(w as Node).call("note_read")
	var a := Art.arachno()
	Art.say("WINCH No. 3 - KEEP CLEAR OF THE CABLE.\nScratched underneath, fresh: \"%s\"" % ("it drifts back along the gantry" if a else "she comes back along the gantry"), 7.0)


# --- Crossing gate (checkpoint before the arena) ------------------------------------------------------

static func _gate(b: Builder, area: Node3D, ctl: Node3D) -> void:
	var y := -18.0
	var n := b.begin("hw_crossing_gate")
	b.shell("hw_crossing_gate", Art.SLATE, Art.SLATE_DARK, Art.IRON)
	for sz in [-1.0, 1.0]:
		b.vbox(Vector3(67.4, y + 1.9, sz * 1.95), Vector3(0.4, 3.8, 0.5), Art.IRON, Basis.IDENTITY, OUT)
	b.vbox(Vector3(67.4, y + 3.75, 0.0), Vector3(0.5, 0.35, 4.4), Art.IRON, Basis.IDENTITY, OUT)
	for i in 7:
		b.vbox(Vector3(67.4, y + 3.55, -1.5 + float(i) * 0.5), Vector3(0.06, 0.4, 0.06), Art.IRON_RUST, Basis.IDENTITY, {"shadows": false})
	var lbl := Art.label(n, "SERVICE BRIDGE - MIND THE RAILS", Vector3(64.5, y + 2.9, -2.35), 26, Color("f3e6c8"))
	lbl.rotation_degrees = Vector3.ZERO
	b.vbox(Vector3(64.5, y + 2.9, -2.38), Vector3(2.8, 0.36, 0.04), Color("3a3238"), Basis.IDENTITY, {"shadows": false})
	Props.barrel(b, Vector3(63.5, y, 1.9), 0.3, 0.8)
	_checkpoint(area, ctl, n, "hw_crossing_gate")


# --- 10 Weaver's Crossing ------------------------------------------------------------------------------

static func _crossing(b: Builder, area: Node3D, ctl: Node3D, decor: Node3D) -> void:
	var y := -18.0
	var n := b.begin("hw_crossing")
	var r: Dictionary = b.rooms["hw_crossing"]
	b.ceiling_rect(68.0, 108.0, -12.0, 12.0, y + 14.0, Art.SLATE_DARK)
	for side in ["n", "s", "w", "e"]:
		b.wall_side(r, side, Art.SLATE)
	b.floor_rect(68.0, 72.0, -12.0, 12.0, y, Art.SLATE)
	b.floor_rect(104.0, 108.0, -12.0, 12.0, y, Art.SLATE)
	b.floor_rect(72.0, 104.0, -5.0, 5.0, y, Art.DECK, "wood")
	b.dress_room_rock("hw_crossing", SLATE_ROCK, {"height_frac": 0.55, "base": false, "size": 1.25, "spacing": 1.8})
	# deck planks, girders, cross beams, stone piers down to the pit floor
	var px := 72.25
	while px < 104.0:
		b.vbox(Vector3(px, y + 0.005, 0.0), Vector3(0.46, 0.02, 9.9), b.vary(Art.DECK, 0.07), Basis.IDENTITY, {"shadows": false})
		px += 0.5
	for zz in [-4.6, 4.6]:
		b.vbox(Vector3(88.0, y - 0.95, zz), Vector3(32.0, 0.9, 0.35), BRIDGE_IRON, Basis.IDENTITY, OUT)
	var cx := 74.0
	while cx < 104.0:
		b.vbox(Vector3(cx, y - 0.75, 0.0), Vector3(0.3, 0.5, 9.4), BRIDGE_IRON.darkened(0.15))
		cx += 4.0
	for pier in [80.0, 96.0]:
		b.solid(Vector3(pier, -22.35, 0.0), Vector3(2.0, 7.3, 7.0), Art.SLATE_DARK)
	# guardrails: both bridge sides + the ledge edges above the pit (the pit stair mouth stays open)
	var rail := float(Layout.CROSSING["rail"]) + 0.1
	for side in [-1.0, 1.0]:
		_rail_run(b, Vector3(72.0, y, side * rail), Vector3(104.0, y, side * rail), BRIDGE_IRON)
	_rail_run(b, Vector3(71.9, y, 5.0), Vector3(71.9, y, 9.3), BRIDGE_IRON)
	_rail_run(b, Vector3(71.9, y, -12.0), Vector3(71.9, y, -5.0), BRIDGE_IRON)
	_rail_run(b, Vector3(104.1, y, -12.0), Vector3(104.1, y, -5.0), BRIDGE_IRON)
	_rail_run(b, Vector3(104.1, y, 5.0), Vector3(104.1, y, 12.0), BRIDGE_IRON)
	# authored ceiling anchors: beams across the vault with iron rings (the arena lists them as Marker3D)
	for a in Layout.CROSSING["anchors"]:
		var ap: Vector3 = a
		b.vbox(Vector3(ap.x, y + 13.55, 0.0), Vector3(0.8, 0.7, 24.0), Art.IRON, Basis.IDENTITY, OUT)
		b.vcyl(Vector3(ap.x, (ap.y + y + 13.2) * 0.5, ap.z), 0.05, y + 13.2 - ap.y, Art.IRON)
		var ring := Kit.torus(0.22, 0.3, Mat.outlined(Mat.toon(Color("4a4048"), {"rim": 0.5}), 0.014))
		Kit.add(n, ring, ap, Vector3(90, 0, 0))
	# cold slate light + two warm service lamps at the ledges
	for spec in [[Vector3(78.0, y + 5.0, -12.0), 0.0], [Vector3(98.0, y + 5.0, -12.0), 0.0], [Vector3(88.0, y + 5.0, 12.0), 180.0]]:
		_lamp(n, spec[0], Color("9fc0ff"), 1.0, 11.0, "wall", float(spec[1]))
	_lamp(n, Vector3(68.2, y + 2.6, -8.0), Palette.MINE_LIGHT, 0.9, 6.5, "wall", 90.0)
	_lamp(n, Vector3(107.8, y + 2.6, 7.0), Palette.MINE_LIGHT, 0.9, 6.5, "wall", -90.0)
	# the pit: a dry sluice bed 8 m down with a stair back up (no bottomless drop)
	var pn := b.begin("hw_crossing_pit")
	var pr: Dictionary = b.rooms["hw_crossing_pit"]
	b.floor_rect(72.0, 104.0, -12.0, 12.0, -26.0, Art.SLATE_DARK)
	for side in ["n", "s", "w", "e"]:
		b.wall_side(pr, side, Art.SLATE_DARK)
	b.dress_room_rock("hw_crossing_pit", SLATE_ROCK, {"height_frac": 0.8, "size": 1.0})
	var st: Array = Layout.CROSSING["pit_stair"]
	b.stairs(st[0], st[1], 2.2, 0.26, Art.SLATE, Art.SLATE_DARK)
	var sa: Vector3 = st[0]
	var sb: Vector3 = st[1]
	var sfwd := (sb - sa).normalized()
	var sside := sfwd.cross(Vector3.UP).normalized()
	var sup := sside.cross(sfwd).normalized()
	var sbasis := Basis(sside, sup, -sfwd)
	var smid := (sa + sb) * 0.5 + Vector3(0, 0.0, -1.2) + sup * 0.6
	b.vbox(smid + sup * 0.4, Vector3(0.1, 0.1, (sb - sa).length()), BRIDGE_IRON, sbasis, OUT)
	b.col_box(smid, Vector3(0.15, 1.6, (sb - sa).length()), "stone", sbasis)
	b.vbox(Vector3(88.0, -25.99, -1.0), Vector3(30.0, 0.02, 2.4), Color("24303c"), Basis.IDENTITY, {"shadows": false})
	Props.cart(b, Vector3(99.0, -26.0, -7.0), 0.5, true, false)
	b.pebbles(73.0, 103.0, -11.5, 11.5, -26.0, SLATE_ROCK, 30)
	_lamp(pn, Vector3(94.0, -26.0, 11.2), Palette.MINE_LIGHT, 0.9, 7.0, "floor")
	# the Matron's deeper route (the arena seals it after the fight)
	b.begin("hw_matron_route")
	b.shell("hw_matron_route", Art.SLATE_DARK, Art.SLATE_DARK, Art.SLATE_DARK)
	b.vbox(Vector3(106.0, y + 1.5, -15.85), Vector3(3.4, 3.0, 0.1), Color(0.02, 0.02, 0.03), Basis.IDENTITY, {"shadows": false})
	# trail dressing under and around the bridge
	for s in [[Vector3(80.0, y - 0.6, 5.1), Vector3(80.4, y - 3.6, 5.8)], [Vector3(92.0, y - 0.6, -5.1), Vector3(91.6, y - 4.2, -5.9)],
			[Vector3(100.0, y + 13.2, -9.0), Vector3(100.3, y + 8.4, -8.6)], [Vector3(75.0, y + 13.2, 9.0), Vector3(75.4, y + 9.0, 8.4)]]:
		decor.call("add_strand", s[0], s[1])
	decor.call("add_web", Vector3(68.6, y + 11.0, 11.4), Vector3(1, 0, -1).normalized(), 2.8, 0.8)
	decor.call("add_web", Vector3(107.4, y + 11.5, -11.4), Vector3(-1, 0, 1).normalized(), 2.8, 0.9)
	decor.call("add_sheet", Vector3(88.0, y + 13.5, 8.0), Vector2(6.0, 4.0), 0.6)
	# the arena node
	var arena: Node3D = CrossingArena.new()
	arena.setup({"area": area, "controller": ctl})
	arena.name = "CrossingArena"
	n.add_child(arena)
	ctl.set("crossing", arena)
	# exit stair down to the Wrong Landing
	b.begin("hw_crossing_exit")
	b.shell("hw_crossing_exit", Art.SLATE, Art.SLATE_DARK, Art.SLATE_DARK, {"no_floor": true})
	var ex: Array = Layout.slope_ends("hw_crossing_exit")
	b.stairs(ex[0], ex[1], 4.0, 0.25, Art.SLATE, Art.SLATE_DARK)
	b.solid(Vector3(117.5, -15.8, 0.0), Vector3(1.0, 3.6, 4.0), Art.SLATE_DARK)
	_lamp(b.node(), Vector3(113.0, -17.2, -2.0), Color("c8e8d0"), 0.8, 6.0, "wall", 0.0)


# --- 11 The Wrong Landing ------------------------------------------------------------------------------

static func _wrong_landing(b: Builder, _area: Node3D, ctl: Node3D) -> void:
	var y := -22.0
	var n := b.begin("hw_wrong_landing")
	b.shell("hw_wrong_landing", Art.TILE_DARK, Art.GREEN_WALL, Art.GREEN_IRON)
	var tx := 118.0
	var i := 0
	while tx < 140.0:
		var tz := -10.0
		var j := 0
		while tz < 10.0:
			if (i + j) % 2 == 0:
				b.vbox(Vector3(tx + 0.625, y + 0.01, tz + 0.625), Vector3(1.2, 0.02, 1.2), Art.TILE, Basis.IDENTITY, {"shadows": false})
			tz += 1.25
			j += 1
		tx += 1.25
		i += 1
	# green iron columns, a ceiling pipe run, two rail tracks leading into the cages
	for c in [Vector3(127.5, y, -4.0), Vector3(130.5, y, -4.0), Vector3(124.0, y, 5.5), Vector3(134.0, y, 5.5)]:
		b.vcyl(c + Vector3(0, 2.2, 0), 0.26, 4.4, Art.GREEN_IRON, Basis.IDENTITY, OUT)
		b.vcyl(c + Vector3(0, 0.15, 0), 0.4, 0.3, Art.GREEN_IRON.darkened(0.2))
		b.col_cyl(c + Vector3(0, 2.2, 0), 0.3, 4.4)
	b.vcyl(Vector3(129.0, y + 4.1, 8.6), 0.14, 21.0, Art.GREEN_IRON.darkened(0.25), Basis(Vector3(0, 0, 1), PI * 0.5))
	for lx in [123.0, 133.0]:
		Props.rails(b, Vector3(lx, y, -10.4), Vector3(lx, y, -1.0))
	Props.sign_board(b, Vector3(128.0, y + 2.6, -10.02), 0.0, 1.8, 0.5, Color("3a4a40"))
	var hint := Art.label(n, "MIND WHICH LAMP LIGHTS THE FLOOR", Vector3(128.0, y + 2.62, -9.96), 22, Color("f3e6c8"))
	hint.rotation_degrees = Vector3.ZERO
	# gas-light: cold green-white
	for spec in [[Vector3(118.2, y + 2.9, -5.0), 90.0], [Vector3(118.2, y + 2.9, 6.0), 90.0], [Vector3(139.8, y + 2.9, -4.0), -90.0], [Vector3(122.0, y + 2.9, 9.8), 180.0], [Vector3(136.0, y + 2.9, 9.8), 180.0]]:
		_lamp(n, spec[0], Color("c8f0d0"), 0.8, 8.0, "wall", float(spec[1]))
	Props.crate(b, Vector3(137.8, y, 8.4), 0.8, 10.0)
	Props.barrel(b, Vector3(119.4, y, 8.8))
	# the two lift recesses and their identical cages
	for id in Layout.LIFTS:
		var rn := b.begin(id)
		b.shell(id, Art.TILE_DARK, Art.GREEN_WALL.darkened(0.15), Art.GREEN_IRON)
		var ld: Dictionary = Layout.LIFTS[id]
		var l: Node3D = LiftScript.new()
		l.setup({"id": id, "kind": String(ld["kind"]), "text": "Ride the lift up", "sign": "LIFT - REFUGE LEVEL",
			"handler": Callable(ctl, "_on_lift")})
		l.name = "Lift_" + String(id)
		rn.add_child(l)
		l.position = ld["pos"]
		l.rotation.y = PI
		(ctl.get("lifts") as Dictionary)[id] = l
	# the service siding where the false lift jams (walk straight back through the south-east door)
	var sn := b.begin("hw_wrong_siding")
	b.shell("hw_wrong_siding", Art.TILE_DARK, Art.GREEN_WALL.darkened(0.2), Art.GREEN_IRON.darkened(0.2))
	for sx in [-1.0, 1.0]:
		b.vbox(Vector3(146.0 + sx * 1.05, y + 1.3, -9.2), Vector3(0.12, 2.6, 0.12), Art.GREEN_IRON, Basis.IDENTITY, OUT)
	b.vbox(Vector3(146.0, y + 2.62, -9.2), Vector3(2.3, 0.14, 0.9), Art.GREEN_IRON.darkened(0.2), Basis.IDENTITY, OUT)
	Props.rails(b, Vector3(146.0, y, -9.8), Vector3(146.0, y, -4.0))
	Props.crate(b, Vector3(142.2, y, -8.8), 0.8, 30.0)
	Props.sack(b, Vector3(147.2, y, 3.0), 20.0)
	_lamp(sn, Vector3(147.8, y + 2.2, -1.0), Color("ffe0a8"), 0.9, 7.0, "wall", -90.0)
	var arrow := Art.label(sn, "<- LANDING", Vector3(141.06, y + 1.9, 0.2), 30, Color("f3e6c8"))
	arrow.rotation_degrees = Vector3(0, 90, 0)


# --- 12 The Borrowed Porch -------------------------------------------------------------------------------

static func _porch(b: Builder, _area: Node3D, ctl: Node3D) -> void:
	var y := -22.0
	b.begin("hw_porch_way")
	b.shell("hw_porch_way", Art.VIOLET_DARK, Art.VIOLET_ROCK, Art.VIOLET_DARK)
	var n := b.begin("hw_porch")
	b.shell("hw_porch", Art.VIOLET_DARK, Art.VIOLET_ROCK, Art.VIOLET_DARK)
	b.dress_room_rock("hw_porch", PORCH_ROCK, {"height_frac": 0.7, "size": 1.3, "spacing": 1.7})
	b.ceiling_lumps(109.0, 139.0, 19.0, 43.0, y + 11.0, PORCH_ROCK, 26, 1.5)
	# a few tall rock spurs so the facade reads as "in a cave", not in a street
	for p in [Vector3(111.5, y, 41.0), Vector3(137.0, y, 42.0), Vector3(112.5, y, 22.0), Vector3(116.0, y, 42.5)]:
		b.vblob(p + Vector3(0, 1.6, 0), Vector3(1.3, 2.4, 1.2), b.vary(b.pick(PORCH_ROCK), 0.06))
		b.col_cyl(p + Vector3(0, 1.4, 0), 0.9, 2.8)
	# painted autumn leaves scattered around the facade (part of the illusion; dungeon-contained)
	for k in 34:
		var lp := Vector3(b.rng.randf_range(115.0, 129.0), y + 0.012, b.rng.randf_range(26.0, 31.2))
		b.vbox(lp, Vector3(0.18, 0.012, 0.12), b.pick([Color("e9a15b"), Color("d9546a"), Color("f2c14e")]), Basis(Vector3.UP, b.rng.randf() * TAU), {"shadows": false})
	b.pebbles(109.0, 139.0, 19.0, 43.0, y, PORCH_ROCK, 36)
	# only a faint cold violet glow high up: the cavern's single true light is the anchored flame
	Props.glow_light(n, Vector3(124.0, y + 8.5, 24.0), Color("8a78b8"), 0.45, 14.0)
	var porch: Node3D = PorchScript.new()
	porch.name = "BorrowedPorch"
	n.add_child(porch)
	ctl.set("porch", porch)
	# the true stair (hidden by the painted hedge until ch2_false_home_revealed)
	b.begin("hw_true_stair")
	b.shell("hw_true_stair", Art.SAND_DARK, Art.SAND_DARK, Art.SAND_DARK, {"no_floor": true})
	var sl: Array = Layout.slope_ends("hw_true_stair")
	b.stairs(sl[0], sl[1], 4.6, 0.25, Art.SAND, Art.SAND_DARK)
	_lamp(b.node(), Vector3(148.0, -24.2, 31.3), Color("ffd08a"), 1.0, 7.0, "wall", 0.0)


# --- 13 Bell Throat --------------------------------------------------------------------------------------

static func _throat(b: Builder, area: Node3D, ctl: Node3D) -> void:
	var y := -28.0
	var n := b.begin("hw_throat")
	b.shell("hw_throat", Art.SAND_DARK, Art.SAND, Art.SAND_DARK)
	b.dress_room_rock("hw_throat", SAND_ROCK, {"height_frac": 0.3, "size": 0.9, "spacing": 1.4})
	# pilasters up the long walls, beams across, bells hanging at different heights, ribbons, candles
	var z := 19.5
	while z < 43.0:
		for side in [-1.0, 1.0]:
			var wx: float = 157.0 + side * 4.75
			if side < 0.0 and z > 30.8 and z < 36.2:
				continue
			if side > 0.0 and z > 38.8:
				continue
			b.vbox(Vector3(wx, y + 8.0, z), Vector3(0.5, 16.0, 0.7), Art.SAND.lightened(0.08), Basis.IDENTITY, OUT)
		b.vbox(Vector3(157.0, y + 12.5, z), Vector3(10.0, 0.45, 0.45), Art.TIMBER_DARK, Basis.IDENTITY, OUT)
		z += 3.5
	var bi := 0
	var bz := 20.5
	while bz < 42.5:
		var bx := 157.0 + sin(float(bi) * 1.7) * 2.2
		var by := y + 7.5 + float(bi % 3) * 1.4
		b.vcyl(Vector3(bx, (by + y + 12.3) * 0.5, bz), 0.03, y + 12.3 - by, Art.IRON)
		b.vcone(Vector3(bx, by - 0.4, bz), 0.55 + float(bi % 2) * 0.2, 1.0, Art.BRASS.darkened(0.1))
		b.vcyl(Vector3(bx, by - 0.85, bz), 0.62 + float(bi % 2) * 0.2, 0.12, Art.BRASS)
		for k in 2:
			var c: Color = Art.RIBBONS[(bi + k) % Art.RIBBONS.size()]
			b.vbox(Vector3(bx + (float(k) - 0.5) * 0.5, by - 1.6, bz + 0.3), Vector3(0.08, 1.3, 0.02), c, Basis(Vector3(0, 0, 1), (float(k) - 0.5) * 0.3), {"shadows": false})
		bi += 1
		bz += 3.1
	var candle := Color("f3e6c8")
	for cz in [21.0, 26.0, 38.0, 42.0]:
		for side in [-1.0, 1.0]:
			var cx: float = 157.0 + side * 4.6
			if side < 0.0 and cz > 30.8 and cz < 36.2:
				continue
			b.vcyl(Vector3(cx, y + 1.25, cz), 0.06, 0.3, candle)
			b.vglow(Builder.unit_sphere(), Transform3D(Basis.IDENTITY.scaled(Vector3(0.09, 0.15, 0.09)), Vector3(cx, y + 1.46, cz)), Color("ffd08a"), 2.4)
			b.vbox(Vector3(cx + side * 0.1, y + 1.05, cz), Vector3(0.3, 0.1, 0.4), Art.SAND_DARK)
	for lz in [22.5, 31.0, 39.5]:
		_lamp(n, Vector3(157.0, y + 6.0, lz), Color("ffcf8a"), 1.5, 10.0, "hanging", 0.0, {"hang": 1.2})
	Props.table(b, Vector3(154.0, y, 39.0), 90.0, 1.4, 0.8)
	Props.papers(b, Vector3(154.0, y + 0.82, 39.0), 20.0)
	Props.barrel(b, Vector3(153.2, y, 42.6))
	var throat: Node3D = ThroatScript.new()
	throat.setup({"controller": ctl})
	throat.name = "BellThroat"
	n.add_child(throat)
	ctl.set("throat", throat)
	_checkpoint(area, ctl, n, "hw_bell_throat")
	# the stair down to the vault
	b.begin("hw_vault_way")
	b.shell("hw_vault_way", Art.PALE_DARK, Art.PALE_DARK, Art.PALE_DARK, {"no_floor": true})
	var vw: Array = Layout.slope_ends("hw_vault_way")
	b.stairs(vw[0], vw[1], 4.0, 0.25, Art.PALE, Art.PALE_DARK)
	_lamp(b.node(), Vector3(155.2, -29.4, 49.0), Color("d8c8f0"), 0.7, 6.0, "wall", 90.0)


# --- 14 Choir Vault ------------------------------------------------------------------------------------------

static func _vault(b: Builder, area: Node3D, ctl: Node3D) -> void:
	var y := -32.0
	var n := b.begin("hw_vault")
	var r: Dictionary = b.rooms["hw_vault"]
	var c: Vector3 = Layout.VAULT["center"]
	var rad := float(Layout.VAULT["radius"])
	var h := float(r["h"])
	b.floor_rect(144.0, 170.0, 52.0, 78.0, y, Art.PALE_DARK)
	b.ceiling_rect(144.0, 170.0, 52.0, 78.0, y + h, Art.PALE_DARK.darkened(0.2))
	for side in ["n", "s", "w", "e"]:
		b.wall_side(r, side, Art.PALE_DARK, false)
	# the ring wall: 48 segments, two doorways (north entry, south exit) with lintels
	var segs := 48
	var chord := 2.0 * (rad + 1.0) * sin(PI / float(segs)) * 1.1
	var half := float(Layout.VAULT["door_half_angle"])
	for i in segs:
		var ang := TAU * float(i) / float(segs)
		var deg := rad_to_deg(ang)
		var basis := Basis(Vector3.UP, PI * 0.5 - ang)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var wc := c + dir * (rad + 0.5)
		var door := false
		for da in [float(Layout.VAULT["entry_angle"]), float(Layout.VAULT["exit_angle"])]:
			if absf(wrapf(deg - da, -180.0, 180.0)) <= half:
				door = true
		if door:
			b.solid(Vector3(wc.x, y + 3.6 + (h - 3.6) * 0.5, wc.z), Vector3(chord, h - 3.6, 1.0), Art.PALE, "stone", basis)
		else:
			b.solid(Vector3(wc.x, y + h * 0.5, wc.z), Vector3(chord, h, 1.0), Art.PALE, "stone", basis)
			b.vbox(Vector3(wc.x, y + 0.35, wc.z) - dir * 0.55, Vector3(chord, 0.7, 0.2), Art.PALE_DARK, basis, {"shadows": false})
		# the safe perimeter band (warm stone, walkable all the way round)
		var bc := c + dir * ((float(Layout.VAULT["perimeter"]) + rad) * 0.5)
		b.vbox(Vector3(bc.x, y + 0.012, bc.z), Vector3(chord * 0.92, 0.024, rad - float(Layout.VAULT["perimeter"])), Art.WARM_BAND, basis, {"shadows": false})
		# inner rings of the floor
		for ring_r in [3.2, 6.4]:
			var rc := c + dir * float(ring_r)
			b.vbox(Vector3(rc.x, y + 0.014, rc.z), Vector3(TAU * float(ring_r) / float(segs) * 1.05, 0.02, 0.3), Art.PALE_DARK.darkened(0.25), basis, {"shadows": false})
	b.vcyl(Vector3(c.x, y + 0.01, c.z), 2.0, 0.02, Art.PALE_DARK.darkened(0.35), Basis.IDENTITY, {"shadows": false, "segments": 24})
	# the Choir's trappings around the rim: cracked bells, wooden masks, harvest ribbons (all harmless)
	for k in 12:
		var ang := TAU * (float(k) + 0.5) / 12.0
		var deg := rad_to_deg(ang)
		if absf(wrapf(deg - float(Layout.VAULT["entry_angle"]), -180.0, 180.0)) < 20.0 or absf(wrapf(deg - float(Layout.VAULT["exit_angle"]), -180.0, 180.0)) < 20.0:
			continue
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var bp := c + dir * (rad - 1.2) + Vector3(0, 10.0 + float(k % 3) * 1.2, 0)
		b.vcyl(Vector3(bp.x, (bp.y + y + h) * 0.5, bp.z), 0.03, y + h - bp.y, Art.IRON)
		b.vcone(bp - Vector3(0, 0.5, 0), 0.6, 1.1, Art.BRASS.darkened(0.3))
		b.vbox(bp - Vector3(0, 0.6, 0) + dir * 0.35, Vector3(0.05, 0.8, 0.03), Color(0.1, 0.08, 0.09), Basis(Vector3.UP, PI * 0.5 - ang).rotated(dir, 0.3), {"shadows": false})
		var mp := c + dir * (rad - 0.05) + Vector3(0, 5.2, 0)
		b.vblob(mp, Vector3(0.5, 0.65, 0.18), Color("c9a878"), 2, Basis(Vector3.UP, PI * 0.5 - ang))
		for s in [-1.0, 1.0]:
			b.vbox(mp - dir * 0.14 + Vector3(0, 0.12, 0) + dir.cross(Vector3.UP) * s * 0.17, Vector3(0.1, 0.07, 0.05), Color(0.08, 0.06, 0.07), Basis(Vector3.UP, PI * 0.5 - ang), {"shadows": false})
		var rc: Color = Art.RIBBONS[k % Art.RIBBONS.size()]
		b.vbox(bp - Vector3(0, 1.6, 0) - dir * 0.2, Vector3(0.1, 1.8, 0.02), rc, Basis(Vector3.UP, PI * 0.5 - ang), {"shadows": false})
	for k in 4:
		var ang := TAU * (float(k) + 0.25) / 4.0
		Props.glow_light(n, c + Vector3(cos(ang) * 8.5, 7.5, sin(ang) * 8.5), Color("c8b8e8"), 0.9, 13.0)
	var arena: Node3D = ChoirArena.new()
	arena.setup({"area": area, "controller": ctl})
	arena.name = "ChoirArena"
	n.add_child(arena)
	ctl.set("choir", arena)
	# the exit alcove (portcullis + bell-lift are the arena's)
	var en := b.begin("hw_vault_exit")
	b.shell("hw_vault_exit", Art.PALE_DARK, Art.PALE, Art.PALE_DARK)
	_lamp(en, Vector3(158.8, y + 2.6, 81.0), Color("ffe0a8"), 0.9, 6.0, "wall", -90.0)


static func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0
