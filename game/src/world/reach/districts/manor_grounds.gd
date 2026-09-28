extends RefCounted
## Moonveil Manor grounds - a Hallowmere Reach district (docs/CHAPTER_TWO_SPEC.md §7.2, §10; MP §9, §17).
## Loaded by src/world/reach/reach_districts.gd:
##   footprints()          ground kept clear of generic trees and grass (house, forecourt, path, gate, pocket)
##   shape_terrain(t)      levels the house footprint to the manor_door plaza, paints the approach path
##                         (the loader keeps every edit inside hr_manor_grounds (18, -74) r 26)
##   build(area)           the facade, the approach and the front door (below)
## A small gothic manor, whimsical rather than grim: dusky plum stone, violet slate roofs with gold ridges,
## crescent windows glowing with candles, a witch-hat turret, a belvedere holding the manor's lamp cage and an
## extravagant bat-shaped crest (scalloped velvet wings, a gold moon, a tiny crown) over the front door.
## The approach runs from the Lantern Road arch (region, (10, -50)) through a pumpkin-lantern gate, lined
## with candle posts, to the steps (spawn manor_door (18, -82) stays outside and clear). A side garden of bat
## topiaries holds the Velvet Wing pocket (spawner hr_sp_manor_wings, only when EnemyFactory knows the id).
## The front door (src/world/manor/manor_door.gd, "grand") -> Game.change_area("moonveil_manor", "manor_entry"),
## registered as area.exits["manor_door"] when the area keeps an exits dictionary. The grounds controller sets
## ch2_found_manor_lamp on the first approach and holds the invitation (MP §17) beside the door.
## Everything reads data/manor_layout.gd GROUNDS; heights come from area.height_at(x, z).

const Layout := preload("res://data/manor_layout.gd")
const Builder := preload("res://src/world/manor/manor_builder.gd")
const DoorScript := preload("res://src/world/manor/manor_door.gd")
const Controller := preload("res://src/world/manor/manor_grounds_controller.gd")
const Interactable := preload("res://src/world/manor/manor_interactable.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const SPAWNER_SCRIPT := "res://src/enemies/enemy_spawner.gd"
const WALL := Color("6a5a78")
const WALL_DARK := Color("4a3a52")
const SLATE := Color("2e2440")
const GOLD := Color("d9b25a")
const CREAM := Color("e8dcc4")
const VELVET := Color("5b2a4e")
const BERRY := Color("9b3b5a")
const GLOW := Color("ffc978")
const STONE := Color("a39a8e")
const IRON := Color("35283a")
const HEDGE := Color("3f5a3a")


static func footprints() -> Array:
	return (Layout.GROUNDS["footprints"] as Array).duplicate(true)


## Heightfield edits (inside the landmark circle; see reach_terrain.gd "District shaping API").
static func shape_terrain(terrain: Variant) -> void:
	if terrain == null or not (terrain is Object):
		return
	var g: Dictionary = Layout.GROUNDS
	var door: Vector2 = g["door"]
	var level := 0.0
	if terrain.has_method("plaza_height"):
		level = float(terrain.call("plaza_height", "manor_door"))
	elif terrain.has_method("raw_height"):
		level = float(terrain.call("raw_height", door.x, door.y))
	var f: Dictionary = g["flatten"]
	if terrain.has_method("flatten"):
		terrain.call("flatten", f["center"], float(f["radius"]), float(f["blend"]), level)
	if terrain.has_method("mark_path"):
		terrain.call("mark_path", (g["path"] as Array).duplicate(), float(g["path_w"]) * 0.5, 0.85)
	if terrain.has_method("add_stone_disc"):
		terrain.call("add_stone_disc", Vector2(door.x, door.y + 2.0), 3.2)
	if terrain.has_method("tint_disc"):
		terrain.call("tint_disc", Vector2(18.0, -88.0), 7.0, 15.0, Color("5e4a62"), 0.35)


static func _h(area: Node3D, x: float, z: float) -> float:
	if area.has_method("height_at"):
		return float(area.call("height_at", x, z))
	return 0.0


static func build(area: Node3D) -> void:
	var root := Node3D.new()
	root.name = "ManorGrounds"
	area.add_child(root)
	var b := Builder.new(root)
	b.visibility_end = 170.0
	var g: Dictionary = Layout.GROUNDS
	var door: Vector2 = g["door"]
	var base := _h(area, door.x, door.y)
	b.begin("manor_house")
	_house(b, base)
	_crest(b, base)
	_steps(b, area, base)
	b.begin("manor_approach")
	_path(b, area)
	_gate(b, area)
	b.begin("manor_topiary")
	_topiary(b, area)
	b.finish()
	# The front door into the manor.
	var d: Node3D = DoorScript.new()
	d.setup({"text": "Enter Moonveil Manor", "target_area": Layout.AREA_ID, "target_spawn": "manor_entry", "style": "grand"})
	d.name = "ManorFrontDoor"
	root.add_child(d)
	d.position = Vector3(door.x, base + float(g["steps"]["rise"]), float(g["door_plane_z"]) + 0.3)
	var ex: Variant = area.get("exits")
	if ex is Dictionary:
		(ex as Dictionary)["manor_door"] = d
	# Found-flag trigger, the tower lamp and the invitation.
	var c: Node3D = Controller.new()
	var inv: Vector2 = g["invitation"]
	var tower: Dictionary = g["tower"]
	c.setup({"lamp_pos": Vector3(door.x, base + float(g["lamp_y"]), (float(tower["z0"]) + float(tower["z1"])) * 0.5),
		"invitation_pos": Vector3(inv.x, _h(area, inv.x, inv.y), inv.y)})
	root.add_child(c)
	# The bat sign in the topiary garden.
	var sp: Vector2 = g["bat_sign"]
	var sign_node: Node3D = Interactable.new()
	sign_node.setup({"id": "bat_sign", "text": "Read the little sign", "radius": 0.7, "offset": Vector3(0, 1.0, 0),
		"say": ["", "PLEASE DO NOT FEED THE BATS. They are fed. They are simply dramatic about it.", 6.0]})
	sign_node.name = "BatSign"
	root.add_child(sign_node)
	sign_node.position = Vector3(sp.x, _h(area, sp.x, sp.y), sp.y)
	# The board faces the approach path (read face-on from the road), a little bat cut-out on top.
	sign_node.rotation.y = Layout.yaw_towards(sp, nearest_path_point(sp)) + PI
	Kit.add(sign_node, Kit.cylinder(0.05, 0.06, 1.1, Mat.toon(Color("5a3a2e")), 6), Vector3(0, 0.55, 0))
	Kit.add(sign_node, Kit.box(Vector3(0.62, 0.36, 0.05), Mat.toon(CREAM)), Vector3(0, 1.1, 0))
	Kit.add(sign_node, Kit.box(Vector3(0.66, 0.04, 0.07), Mat.toon(VELVET)), Vector3(0, 1.3, 0))
	for s in [-1.0, 1.0]:
		Kit.add(sign_node, Kit.sphere(0.09, Mat.toon(Color("2a1830")), 6, 8), Vector3(float(s) * 0.1, 1.38, 0), Vector3(0, 0, float(s) * -25.0), Vector3(1.4, 0.55, 0.3))
	Kit.add(sign_node, Kit.sphere(0.05, Mat.toon(Color("2a1830")), 6, 8), Vector3(0, 1.39, 0))
	var sh := CylinderShape3D.new()
	sh.radius = 0.08
	sh.height = 1.1
	Kit.static_collider(sign_node, sh, Vector3(0, 0.55, 0), 1).name = "SolidBody"
	# The Velvet Wing pocket (guarded: the enemy arrives in a later wave).
	if Factory.can_spawn(Layout.WING_ID) and ResourceLoader.exists(SPAWNER_SCRIPT):
		var sd: Dictionary = Layout.GROUNDS_SPAWNER
		var wp: Vector2 = g["wing_pocket"]
		var s: Node3D = load(SPAWNER_SCRIPT).new()
		s.setup({"enemy": String(sd["enemy"]), "count": int(sd["count"]), "radius": float(sd["radius"]),
			"respawn_minutes": float(sd["respawn_minutes"]), "spawner_id": String(sd["id"])})
		s.name = "Spawner_" + String(sd["id"])
		root.add_child(s)
		s.position = Vector3(wp.x, _h(area, wp.x, wp.y), wp.y)
	# The spawn outside the door belongs to the Reach (data/hallowmere_layout.gd); only fill it in if missing.
	var spawns: Variant = area.get("spawns")
	if spawns is Dictionary and not (spawns as Dictionary).has("manor_door") and area.has_method("register_spawn"):
		var spn: Vector2 = g["spawn"]
		area.call("register_spawn", "manor_door", Transform3D(Basis(Vector3.UP, Layout.yaw_towards(spn, Vector2(10, -50))),
			Vector3(spn.x, _h(area, spn.x, spn.y) + 0.08, spn.y)))


# --- The house -------------------------------------------------------------------------------------------

static func _house(b: Builder, base: float) -> void:
	var g: Dictionary = Layout.GROUNDS
	var hs: Dictionary = g["house"]
	var x0 := float(hs["x0"])
	var x1 := float(hs["x1"])
	var z0 := float(hs["z0"])
	var z1 := float(hs["z1"])
	var hh := float(hs["h"])
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var bottom := base - 3.0
	# Main block (sunk into the ground so any slope is hidden), plinth band and cornice.
	b.solid(Vector3(cx, (bottom + base + hh) * 0.5, cz), Vector3(x1 - x0, base + hh - bottom, z1 - z0), WALL, "stone")
	b.vbox(Vector3(cx, base + 0.35, cz), Vector3(x1 - x0 + 0.3, 0.9, z1 - z0 + 0.3), WALL_DARK)
	b.vbox(Vector3(cx, base + hh, cz), Vector3(x1 - x0 + 0.5, 0.35, z1 - z0 + 0.5), CREAM, Basis.IDENTITY, {"shadows": false})
	# Steep violet roof with a gold ridge, two chimneys.
	b.vprism(Vector3(cx, base + hh + 2.3, cz), Vector3(z1 - z0 + 0.9, 4.6, x1 - x0 + 0.6), SLATE, Basis(Vector3.UP, PI * 0.5))
	b.vbox(Vector3(cx, base + hh + 4.62, cz), Vector3(x1 - x0 + 0.6, 0.14, 0.16), GOLD, Basis.IDENTITY, {"shadows": false})
	for x in [x0 + 3.0, x1 - 3.0]:
		b.solid(Vector3(float(x), base + hh + 3.4, cz - 2.2), Vector3(1.0, 3.4, 1.0), WALL_DARK, "stone")
		b.vbox(Vector3(float(x), base + hh + 5.2, cz - 2.2), Vector3(1.3, 0.25, 1.3), CREAM, Basis.IDENTITY, {"shadows": false})
	# Crescent windows glowing with candles on the front (south) face of both wings, gabled dormers above.
	var face_z := z1 + 0.02
	for x in [x0 + 2.4, x0 + 5.2, x1 - 5.2, x1 - 2.4]:
		for y in [2.2, 5.1]:
			b.crescent_window(Vector3(float(x), base + float(y), face_z), Vector3(0, 0, 1), 0.62, GLOW, GOLD, 1.3)
			b.vbox(Vector3(float(x), base + float(y) - 0.78, face_z + 0.12), Vector3(1.5, 0.1, 0.3), CREAM, Basis.IDENTITY, {"shadows": false})
			for k in 3:
				b.candle(Vector3(float(x) - 0.4 + float(k) * 0.4, base + float(y) - 0.72, face_z + 0.16), 0.12 + float(k % 2) * 0.08, 0.035)
	for x in [x0 + 3.8, x1 - 3.8]:
		b.vprism(Vector3(float(x), base + hh + 1.2, z1 - 0.9), Vector3(2.6, 2.2, 1.8), SLATE)
		b.vbox(Vector3(float(x), base + hh + 0.5, z1 - 0.5), Vector3(2.2, 1.2, 1.0), WALL)
		b.crescent_window(Vector3(float(x), base + hh + 0.6, z1 + 0.02), Vector3(0, 0, 1), 0.4, GLOW, GOLD, 1.3)
	# Side windows (east / west faces).
	for z in [cz - 2.5, cz + 2.5]:
		b.crescent_window(Vector3(x0 - 0.02, base + 3.2, float(z)), Vector3(-1, 0, 0), 0.55, GLOW, GOLD, 1.2)
		b.crescent_window(Vector3(x1 + 0.02, base + 3.2, float(z)), Vector3(1, 0, 0), 0.55, GLOW, GOLD, 1.2)
	# Central tower with a belvedere (the lamp cage lives there) and a tall slate spire.
	var tw: Dictionary = g["tower"]
	var tx0 := float(tw["x0"])
	var tx1 := float(tw["x1"])
	var tz0 := float(tw["z0"])
	var tz1 := float(tw["z1"])
	var th := float(tw["h"])
	var tcx := (tx0 + tx1) * 0.5
	var tcz := (tz0 + tz1) * 0.5
	b.solid(Vector3(tcx, (bottom + base + th) * 0.5, tcz), Vector3(tx1 - tx0, base + th - bottom, tz1 - tz0), WALL, "stone")
	b.vbox(Vector3(tcx, base + th, tcz), Vector3(tx1 - tx0 + 0.5, 0.35, tz1 - tz0 + 0.5), CREAM, Basis.IDENTITY, {"shadows": false})
	for sx in [tx0 + 0.3, tx1 - 0.3]:
		for sz in [tz0 + 0.3, tz1 - 0.3]:
			b.vcyl(Vector3(float(sx), base + th + 1.1, float(sz)), 0.16, 2.2, CREAM)
	b.vbox(Vector3(tcx, base + th + 2.3, tcz), Vector3(tx1 - tx0 + 0.4, 0.3, tz1 - tz0 + 0.4), GOLD, Basis.IDENTITY, {"shadows": false})
	b.vcone(Vector3(tcx, base + th + 4.8, tcz), 4.2, 5.0, SLATE, Basis(Vector3.UP, PI * 0.25), {"segments": 4})
	b.vsphere(Vector3(tcx, base + th + 7.45, tcz), Vector3(0.3, 0.3, 0.3), GOLD, Basis.IDENTITY, {"shadows": false})
	b.vcyl(Vector3(tcx, base + th + 8.1, tcz), 0.34, 0.05, GOLD, Basis(Vector3.RIGHT, PI * 0.5), {"shadows": false})
	# Crescent window high on the tower front and tall arched windows either side of the crest.
	b.crescent_window(Vector3(tcx, base + 8.9, tz1 + 0.02), Vector3(0, 0, 1), 0.8, GLOW, GOLD, 1.3)
	for sx in [tx0 + 1.0, tx1 - 1.0]:
		b.arched_window(Vector3(float(sx), base + 4.4, tz1 + 0.02), Vector3(0, 0, 1), 0.8, 2.2, GLOW, GOLD, 1.2)
	# Porch canopy over the door on two slim columns.
	var cols: Array = g["porch_columns"]
	for cp in cols:
		var p2: Vector2 = cp
		b.column(Vector3(p2.x, base, p2.y), 0.14, 3.6, CREAM, GOLD)
	b.vprism(Vector3(tcx, base + 3.95, (tz1 + float((cols[0] as Vector2).y)) * 0.5), Vector3(4.4, 0.8, 1.5), SLATE)
	b.vbox(Vector3(tcx, base + 3.62, (tz1 + float((cols[0] as Vector2).y)) * 0.5), Vector3(4.4, 0.14, 1.5), GOLD, Basis.IDENTITY, {"shadows": false})
	# Witch-hat turret on the east corner.
	var tu: Dictionary = g["turret"]
	var tp: Vector2 = tu["pos"]
	var tr := float(tu["r"])
	var tuh := float(tu["h"])
	b.vcyl(Vector3(tp.x, (bottom + base + tuh) * 0.5, tp.y), tr, base + tuh - bottom, WALL, Basis.IDENTITY, {"segments": 18})
	b.col_cyl(Vector3(tp.x, (bottom + base + tuh) * 0.5, tp.y), tr, base + tuh - bottom, "stone")
	b.vcyl(Vector3(tp.x, base + tuh, tp.y), tr + 0.25, 0.3, CREAM, Basis.IDENTITY, {"shadows": false, "segments": 18})
	b.vcone(Vector3(tp.x - 0.2, base + tuh + 2.6, tp.y), tr + 0.6, 5.2, SLATE, Basis(Vector3.FORWARD, 0.12), {"segments": 16})
	b.vcyl(Vector3(tp.x - 0.55, base + tuh + 5.4, tp.y), 0.3, 0.05, GOLD, Basis(Vector3.RIGHT, PI * 0.5), {"shadows": false})
	for k in 3:
		var a := -0.4 + float(k) * 0.55
		b.crescent_window(Vector3(tp.x + sin(a) * (tr + 0.02), base + 3.0 + float(k) * 1.9, tp.y + cos(a) * (tr + 0.02)), Vector3(sin(a), 0, cos(a)), 0.36, GLOW, GOLD, 1.3)


## The extravagant bat-shaped crest over the door: scalloped velvet wings, a gold moon, a tiny crown.
static func _crest(b: Builder, base: float) -> void:
	var g: Dictionary = Layout.GROUNDS
	var door: Vector2 = g["door"]
	var z := float(g["door_plane_z"]) + 0.12
	var c := Vector3(door.x, base + float(g["crest_y"]), z)
	var face := Basis(Vector3.RIGHT, PI * 0.5)
	b.vcyl(c + Vector3(0, 0.2, -0.04), 0.9, 0.08, GOLD, face, {"shadows": false, "segments": 24})
	b.vcyl(c + Vector3(0.36, 0.34, 0.0), 0.72, 0.09, Color("241a36"), face, {"shadows": false, "segments": 24})
	for s in [-1.0, 1.0]:
		var sg := float(s)
		var scallops := [[0.95, 0.25, Vector3(1.05, 0.62, 0.14)], [1.8, 0.35, Vector3(0.95, 0.56, 0.14)], [2.55, 0.12, Vector3(0.72, 0.46, 0.14)]]
		for sc in scallops:
			var off := Vector3(sg * float(sc[0]), float(sc[1]), 0.06)
			b.vsphere(c + off + Vector3(0, 0.03, -0.03), (sc[2] as Vector3) * Vector3(1.08, 1.1, 1.0), GOLD, Basis(Vector3.FORWARD, sg * 0.18), {"shadows": false})
			b.vsphere(c + off, sc[2], VELVET, Basis(Vector3.FORWARD, sg * 0.18), {"shadows": false})
		b.vbox(c + Vector3(sg * 1.5, 0.72, 0.08), Vector3(2.4, 0.06, 0.06), GOLD, Basis(Vector3.FORWARD, sg * 0.28), {"shadows": false})
		b.vcone(c + Vector3(sg * 0.2, 1.05, 0.12), 0.12, 0.34, Color("241a36"), Basis(Vector3.FORWARD, sg * -0.25), {"shadows": false})
		b.glow_sphere(c + Vector3(sg * 0.11, 0.72, 0.36), Vector3(0.07, 0.07, 0.07), Color("ffd27a"), 2.4)
	b.vsphere(c + Vector3(0, 0.1, 0.14), Vector3(0.9, 1.0, 0.5), Color("241a36"), Basis.IDENTITY, {"shadows": false})
	b.vsphere(c + Vector3(0, 0.72, 0.18), Vector3(0.55, 0.5, 0.45), Color("241a36"), Basis.IDENTITY, {"shadows": false})
	b.vring(c + Vector3(0, 0.46, 0.24), 0.28, 0.6, GOLD, face)
	b.vcyl(c + Vector3(0, 1.05, 0.2), 0.16, 0.12, GOLD, Basis.IDENTITY, {"shadows": false})
	for k in 5:
		var a := TAU * float(k) / 5.0
		b.vcone(c + Vector3(cos(a) * 0.13, 1.17, 0.2 + sin(a) * 0.13), 0.035, 0.12, GOLD, Basis.IDENTITY, {"shadows": false, "segments": 6})
	# A velvet ribbon banner beneath.
	b.vbox(c + Vector3(0, -0.72, 0.1), Vector3(2.6, 0.34, 0.06), BERRY, Basis.IDENTITY, {"shadows": false})
	for s in [-1.0, 1.0]:
		b.vprism(c + Vector3(float(s) * 1.45, -0.72, 0.1), Vector3(0.34, 0.34, 0.06), BERRY, Basis(Vector3.FORWARD, float(s) * -PI * 0.5), {"shadows": false})
	b.vbox(c + Vector3(0, -0.55, 0.14), Vector3(2.6, 0.04, 0.04), GOLD, Basis.IDENTITY, {"shadows": false})
	b.vbox(c + Vector3(0, -0.89, 0.14), Vector3(2.6, 0.04, 0.04), GOLD, Basis.IDENTITY, {"shadows": false})


static func _steps(b: Builder, area: Node3D, base: float) -> void:
	var g: Dictionary = Layout.GROUNDS
	var st: Dictionary = g["steps"]
	var door: Vector2 = g["door"]
	var zb := float(st["z_bottom"])
	var zt := float(st["z_top"])
	var ground := _h(area, door.x, zb)
	var top := base + float(st["rise"])
	b.stairs(Vector3(door.x, top, zt), Vector3(door.x, ground, zb), float(st["width"]), 0.18, STONE, CREAM, "stone")
	# Candle clusters on both sides of the steps and pumpkins at their foot.
	for s in [-1.0, 1.0]:
		var sx := door.x + float(s) * (float(st["width"]) * 0.5 + 0.75)
		for k in 4:
			b.candle(Vector3(sx + float(s) * float(k % 2) * 0.22, _h(area, sx, zb) + 0.02, zb - 0.1 - float(k) * 0.3), 0.16 + float(k % 3) * 0.08, 0.04)
		b.pumpkin(Vector3(door.x + float(s) * 2.9, _h(area, door.x + float(s) * 2.9, zb + 1.0), zb + 1.0), 0.34)


# --- The approach ----------------------------------------------------------------------------------------

## The point of the approach path (polyline GROUNDS.path) closest to p.
static func nearest_path_point(p: Vector2) -> Vector2:
	var pts: Array = Layout.GROUNDS["path"]
	var best: Vector2 = pts[0]
	var best_d := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var ab := c - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


static func _path_points() -> Array:
	var pts: Array = Layout.GROUNDS["path"]
	var out: Array = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var n := maxi(int(a.distance_to(c) / 1.05), 1)
		for k in n:
			out.append(a.lerp(c, float(k) / float(n)))
	out.append(pts[pts.size() - 1])
	return out


static func _path(b: Builder, area: Node3D) -> void:
	var g: Dictionary = Layout.GROUNDS
	var pts := _path_points()
	var w := float(g["path_w"])
	var arch: Vector2 = Layout.GROUNDS["path"][0]
	var spawn: Vector2 = g["spawn"]
	var gate_p: Vector2 = g["gate"]["pos"]
	for i in pts.size():
		var p: Vector2 = pts[i]
		var nxt: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var prv: Vector2 = pts[maxi(i - 1, 0)]
		var dir := (nxt - prv)
		if dir.length() < 0.01:
			dir = Vector2(0, -1)
		dir = dir.normalized()
		var perp := Vector2(-dir.y, dir.x)
		var yaw := atan2(-dir.x, -dir.y)
		for s in [-0.28, 0.28]:
			var q := p + perp * float(s) * w * (1.0 if i % 2 == 0 else 0.7)
			b.vbox(Vector3(q.x, _h(area, q.x, q.y) + 0.03, q.y), Vector3(w * 0.42, 0.06, 0.78), STONE.darkened(0.06 * float(i % 3)), Basis(Vector3.UP, yaw + 0.1 * float(i % 3)), {"shadows": false})
		# Candle posts every few metres, alternating sides (not on the arch plaza nor near the spawn).
		if i % 6 == 3 and p.distance_to(arch) > 4.5 and p.distance_to(spawn) > 2.5 and p.distance_to(gate_p) > 3.2:
			var side := 1.0 if (i / 6) % 2 == 0 else -1.0
			var lp := p + perp * side * (w * 0.5 + 0.9)
			var y := _h(area, lp.x, lp.y)
			b.vcyl(Vector3(lp.x, y + 0.65, lp.y), 0.05, 1.3, IRON, Basis.IDENTITY, {"shadows": false, "segments": 6})
			b.vcyl(Vector3(lp.x, y + 1.38, lp.y), 0.11, 0.22, IRON, Basis.IDENTITY, {"shadows": false, "segments": 8})
			b.glow_sphere(Vector3(lp.x, y + 1.38, lp.y), Vector3(0.14, 0.18, 0.14), GLOW, 2.2)
			b.vcone(Vector3(lp.x, y + 1.58, lp.y), 0.15, 0.2, IRON, Basis.IDENTITY, {"shadows": false, "segments": 8})
			b.col_cyl(Vector3(lp.x, y + 0.7, lp.y), 0.12, 1.4, "stone")
			if (i / 6) % 3 == 1:
				b.pumpkin(Vector3(lp.x + perp.x * 0.5, y, lp.y + perp.y * 0.5), 0.28)


static func _gate(b: Builder, area: Node3D) -> void:
	var g: Dictionary = Layout.GROUNDS
	var gp: Vector2 = g["gate"]["pos"]
	var gw := float(g["gate"]["width"])
	var pts: Array = g["path"]
	var dir := ((pts[3] as Vector2) - (pts[2] as Vector2)).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var yaw := atan2(-dir.x, -dir.y)
	var basis := Basis(Vector3.UP, yaw)
	var ribbons := [Color("e8862f"), BERRY, Color("7a5aa8"), Color("f2c14e")]
	for s in [-1.0, 1.0]:
		var pp := gp + perp * float(s) * (gw * 0.5 + 0.35)
		var y := _h(area, pp.x, pp.y)
		b.solid(Vector3(pp.x, y + 1.1, pp.y), Vector3(0.7, 2.2, 0.7), STONE, "stone", basis)
		b.vbox(Vector3(pp.x, y + 2.25, pp.y), Vector3(0.86, 0.12, 0.86), CREAM, basis, {"shadows": false})
		b.pumpkin(Vector3(pp.x, y + 2.31, pp.y), 0.3)
		b.glow_sphere(Vector3(pp.x, y + 2.55, pp.y), Vector3(0.12, 0.1, 0.12), GLOW, 2.0)
		# A short crooked fence either side of the gate (ribbons tied on it).
		for k in 5:
			var fp := gp + perp * float(s) * (gw * 0.5 + 1.0 + float(k) * 0.95)
			var fy := _h(area, fp.x, fp.y)
			b.vbox(Vector3(fp.x, fy + 0.55, fp.y), Vector3(0.12, 1.1, 0.12), IRON, Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, 0.05 * float(k % 3 - 1)), {"shadows": false})
			b.vcone(Vector3(fp.x, fy + 1.18, fp.y), 0.08, 0.18, GOLD, Basis.IDENTITY, {"shadows": false, "segments": 6})
			if k % 2 == 1:
				b.vbox(Vector3(fp.x, fy + 0.95, fp.y), Vector3(0.2, 0.3, 0.05), ribbons[(k + int(s + 1.0)) % ribbons.size()], basis * Basis(Vector3.FORWARD, 0.4), {"shadows": false})
		var mid := gp + perp * float(s) * (gw * 0.5 + 2.9)
		var my := _h(area, mid.x, mid.y)
		for yy in [0.35, 0.85]:
			b.vbox(Vector3(mid.x, my + float(yy), mid.y), Vector3(4.0, 0.06, 0.06), IRON, basis, {"shadows": false})
		b.col_box(Vector3(mid.x, my + 0.6, mid.y), Vector3(4.0, 1.2, 0.2), "stone", basis)
	# The wrought-iron arch over the gate with a crescent at its apex.
	var gy := _h(area, gp.x, gp.y)
	var r := gw * 0.5 + 0.35
	for i in 11:
		var a := PI * (float(i) + 0.5) / 11.0
		var off := perp * cos(a) * r
		var p := Vector3(gp.x + off.x, gy + 2.2 + sin(a) * r * 0.8, gp.y + off.y)
		b.vbox(p, Vector3(0.1, 0.1, r * PI / 11.0 * 1.15), IRON, basis * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -(a - PI * 0.5)), {"shadows": false})
	var apex := Vector3(gp.x, gy + 2.2 + r * 0.8 + 0.35, gp.y)
	b.vcyl(apex, 0.34, 0.06, GOLD, basis * Basis(Vector3.RIGHT, PI * 0.5), {"shadows": false, "segments": 20})
	b.vcyl(apex + Vector3(perp.x * 0.14, 0.06, perp.y * 0.14), 0.29, 0.07, IRON, basis * Basis(Vector3.RIGHT, PI * 0.5), {"shadows": false, "segments": 20})


static func _topiary(b: Builder, area: Node3D) -> void:
	var g: Dictionary = Layout.GROUNDS
	for tp in g["topiaries"]:
		var p: Vector2 = tp
		var y := _h(area, p.x, p.y)
		var toward := (g["wing_pocket"] as Vector2) - p
		var yaw := atan2(-toward.x, -toward.y)
		var basis := Basis(Vector3.UP, yaw)
		b.vcyl(Vector3(p.x, y + 0.2, p.y), 0.55, 0.4, STONE, Basis.IDENTITY, {"segments": 10})
		b.vsphere(Vector3(p.x, y + 1.15, p.y), Vector3(0.95, 1.3, 0.8), HEDGE, basis)
		b.vsphere(Vector3(p.x, y + 1.95, p.y), Vector3(0.6, 0.55, 0.55), HEDGE.darkened(0.05), basis)
		for s in [-1.0, 1.0]:
			var wing := basis * Vector3(float(s) * 0.95, 0.0, 0.0)
			b.vsphere(Vector3(p.x, y + 1.35, p.y) + wing, Vector3(1.0, 0.6, 0.25), HEDGE.lightened(0.05), basis * Basis(Vector3.FORWARD, float(s) * 0.3))
			b.vcone(Vector3(p.x, y + 2.3, p.y) + basis * Vector3(float(s) * 0.22, 0, 0), 0.14, 0.38, HEDGE, basis, {"segments": 6})
		b.col_cyl(Vector3(p.x, y + 1.0, p.y), 0.75, 2.0, "grass")
	var bb: Vector2 = g["birdbath"]
	var by := _h(area, bb.x, bb.y)
	b.vcyl(Vector3(bb.x, by + 0.45, bb.y), 0.14, 0.9, STONE, Basis.IDENTITY, {"segments": 10})
	b.vtaper(Vector3(bb.x, by + 0.98, bb.y), 0.3, 0.55, 0.18, STONE, Basis.IDENTITY)
	b.vcyl(Vector3(bb.x, by + 1.06, bb.y), 0.46, 0.03, Color("6fa9b8"), Basis.IDENTITY, {"shadows": false})
	b.col_cyl(Vector3(bb.x, by + 0.55, bb.y), 0.5, 1.1, "stone")
	var wp: Vector2 = g["wing_pocket"]
	for k in 4:
		var a := float(k) * 1.7
		b.pumpkin(Vector3(wp.x + cos(a) * 3.6, _h(area, wp.x + cos(a) * 3.6, wp.y + sin(a) * 3.6), wp.y + sin(a) * 3.6), 0.22 + float(k % 2) * 0.08, Color("9b6ad0") if k % 2 == 0 else Color("e8862f"))
