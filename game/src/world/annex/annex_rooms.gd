extends RefCounted
## Geometry and dressing of Tobin's Lost Shift, built with the (layout-agnostic) Below builder:
##   Builder.new(area, seed, AnnexLayout.ROOMS), then AnnexRooms.build(b, area), then b.finish() once.
## Three silhouettes, one amber mine mood:
##   entry   - low (3 m), square, board-clad and timbered; warm and lived-in (a lamp rack, a bench, the chalk
##             shift rules). Safe.
##   lockers - long and tall (4.8 m) with heavy ceiling beams, lined wall to wall with shift lockers; open
##             floor in the middle for the Drudge encounter; scuffs where a pick was dragged.
##   sump    - reached down a timbered stair; wide and low-lying, wet dark stone, a sluice channel across it,
##             the sluice gate, echo crystals, the scratched lantern and the hatch shaft with its ladder.
## Returns named nodes the area needs: {"sump_lamp", "tobin_locker": {...}}.

const Palette := preload("res://src/art/palette.gd")
const Layout := preload("res://src/world/annex/annex_layout.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const BelowProps := preload("res://src/world/below/below_props.gd")
const Props := preload("res://src/world/annex/annex_props.gd")

const FLOOR := Color("5f4a3b")
const BOARDS := Color("7d5b3e")
const WALL := Color("5a4636")
const CEIL := Color("3b2a22")
const WET_FLOOR := Color("4b4640")
const WET_WALL := Color("474641")
const CHANNEL_BED := Color("363935")
const SHAFT := Color("5b4230")
const LAMP := Color("ffb35c")
const LAMP_DIM := Color("f2a24e")
const NO_SHADOW := {"shadows": false}


static func rock_cols() -> Array:
	return [Palette.MINE_ROCK, Palette.MINE_ROCK.lerp(Palette.MINE_ROCK_DARK, 0.45), Palette.MINE_ROCK.lerp(Palette.DIRT_DARK, 0.3), Color("6a5140")]


static func wet_cols() -> Array:
	return [Color("4d4a44"), Color("3f3f3b"), Color("55504a"), Color("46493f")]


static func build(b: Builder, area: Node3D) -> Dictionary:
	var refs := {}
	_entry(b, area, refs)
	_lockers(b, area, refs)
	_niche(b, area, refs)
	_stair(b, area, refs)
	_sump(b, area, refs)
	return refs


static func _r(id: String) -> Dictionary:
	return Layout.ROOMS[id]


## A plain doorway frame on a wall face: two posts just outside the opening and a lintel above it (never
## narrows or lowers the opening). `along` = the wall's direction, `facing` = into the room.
static func _doorway(b: Builder, center: Vector3, along: Vector3, facing: Vector3, width: float, height: float) -> void:
	var basis := Basis.looking_at(-facing, Vector3.UP)
	var half := width * 0.5 + 0.14
	for s: float in [-1.0, 1.0]:
		var p := center + along * (float(s) * half) + facing * 0.1 + Vector3(0, (height + 0.3) * 0.5, 0)
		b.vbox(p, Vector3(0.28, height + 0.3, 0.28), b.vary(BelowProps.TIMBER, 0.06), basis, BelowProps.OUT)
		b.col_box(p, Vector3(0.28, height + 0.3, 0.28), "wood", basis)
	b.vbox(center + facing * 0.1 + Vector3(0, height + 0.16, 0), Vector3(width + 0.9, 0.32, 0.32), b.vary(BelowProps.TIMBER, 0.05), basis, BelowProps.OUT)


# --- ta_entry: Tobin's lamp room ------------------------------------------------------------------------

static func _entry(b: Builder, _area: Node3D, _refs: Dictionary) -> void:
	var n := b.begin("entry")
	var r := _r("entry")
	var g := _r("entry_gap")
	b.shell("entry", BOARDS, WALL, CEIL, {"surface": "wood"})
	b.floor_rect(float(g["x0"]), float(g["x1"]), float(g["z0"]), float(g["z1"]), 0.0, BOARDS, "wood")
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	# Board cladding on the walls (visual), leaving the door in the south wall bare.
	for i in 10:
		var z := -0.35 - float(i) * 0.7
		for sx: float in [x0 + 0.03, x1 - 0.03]:
			b.vbox(Vector3(float(sx), 1.25, z), Vector3(0.05, 2.5, 0.66), b.vary(BelowProps.PLANK, 0.1), Basis.IDENTITY, NO_SHADOW)
	for i in 4:
		for s: float in [-1.0, 1.0]:
			b.vbox(Vector3(float(s) * (1.55 + float(i) * 0.7), 1.25, -0.03), Vector3(0.66, 2.5, 0.05), b.vary(BelowProps.PLANK, 0.1), Basis.IDENTITY, NO_SHADOW)
	# Timber frames and ceiling lagging.
	BelowProps.timber_frame(b, -2.3, x0, x1, 0.0, 3.0, "x")
	BelowProps.timber_frame(b, -4.9, x0, x1, 0.0, 3.0, "x")
	for k in 11:
		b.vbox(Vector3(-3.6 + float(k) * 0.72, 2.95, -3.5), Vector3(0.62, 0.06, 6.9), b.vary(BelowProps.PLANK.darkened(0.3), 0.08), Basis.IDENTITY, NO_SHADOW)
	# The Foreman's chalk board (teaches the Drudge's tells) and the sign-in slate: Tobin signed in, never out.
	Props.chalk_board(b, n, Layout.POINTS["shift_board"], Vector3(1, 0, 0), "SHIFT RULES")
	var slate_pos := Vector3(x0 + 0.06, 1.5, -5.95)
	b.vbox(slate_pos, Vector3(0.05, 0.62, 0.86), BelowProps.TIMBER, Basis.IDENTITY, BelowProps.OUT)
	b.vbox(slate_pos + Vector3(0.03, 0, 0), Vector3(0.02, 0.54, 0.78), Props.SLATE, Basis.IDENTITY, NO_SHADOW)
	Props.label(n, "IN:   Tobin\nOUT:", slate_pos + Vector3(0.05, 0.02, 0), Basis(Vector3.UP, PI * 0.5), 26, Props.CHALK, 0.0032)
	# Lamp rack (one hook empty: Tobin's), a bench, crates.
	Props.lamp_rack(b, Vector3(x1 - 0.12, 1.85, -3.6), Vector3(-1, 0, 0), 4, 2)
	Props.bench(b, Vector3(x1 - 0.5, 0.0, -1.3), 1.2, "z")
	BelowProps.crate(b, Vector3(3.3, 0.0, -6.3), 0.8, 12.0)
	BelowProps.crate(b, Vector3(2.4, 0.0, -6.4), 0.7, -8.0)
	BelowProps.barrel(b, Vector3(-3.4, 0.0, -6.35))
	BelowProps.sack(b, Vector3(-3.35, 0.0, -0.8), 30.0)
	BelowProps.pickaxe_lean(b, Vector3(x1 - 0.2, 0.0, -5.4), -90.0)
	# Warm lights: this is the safe room.
	BelowProps.lamp(n, Vector3(1.7, 3.0, -3.6), {"style": "hanging", "hang": 0.3, "energy": 1.5, "range": 8.0, "shadow": true, "color": LAMP})
	BelowProps.lamp(n, Vector3(-1.6, 2.2, -0.05), {"style": "wall", "energy": 0.8, "range": 4.5, "color": LAMP, "yaw": 180.0})


# --- ta_lockers: the shift lockers -----------------------------------------------------------------------

static func _lockers(b: Builder, _area: Node3D, refs: Dictionary) -> void:
	var n := b.begin("lockers")
	var r := _r("lockers")
	var cols := rock_cols()
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	var z0: float = float(r["z0"])
	var z1: float = float(r["z1"])
	b.shell("lockers", FLOOR, WALL, CEIL)
	b.dress_room_rock("lockers", cols, {"size": 1.0, "spacing": 1.3})
	b.ceiling_lumps(x0 + 0.5, x1 - 0.5, z0 + 0.5, z1 - 0.5, float(r["h"]), [CEIL, Palette.MINE_ROCK_DARK], 8, 0.9)
	b.pebbles(x0 + 1.1, x1 - 1.1, z0 + 0.5, z1 - 0.5, 0.0, cols, 34)
	# Heavy ceiling beams (the tall silhouette).
	var z := z1 - 2.0
	while z > z0 + 0.5:
		b.vbox(Vector3(0, float(r["h"]) - 0.35, z), Vector3(x1 - x0 + 0.6, 0.32, 0.36), b.vary(BelowProps.TIMBER, 0.06), Basis.IDENTITY, BelowProps.OUT)
		z -= 3.2
	# Lockers wall to wall; Tobin's (a node, it opens) stands in the east row.
	var letter: Vector3 = Layout.POINTS["letter"]
	var niche_open: Array = r["open"]["w"][0]
	Props.locker_row(b, x0, 1.0, letter.z, z0 + 0.2, z1 - 0.2, [[float(niche_open[0]) - 0.6, float(niche_open[1]) + 0.6]])
	Props.locker_row(b, x1, -1.0, letter.z, z0 + 0.2, z1 - 0.2, [], true)
	refs["tobin_locker"] = Props.tobin_locker(n, Vector3(x1 - 0.25 - Props.LOCKER_D * 0.5, 0.0, letter.z), Vector3(-1, 0, 0))
	# Doorways: to the lamp room (south), the lantern niche (west) and the stair (north).
	var so: Array = r["open"]["s"][0]
	var no: Array = r["open"]["n"][0]
	_doorway(b, Vector3(0, 0, z1), Vector3(1, 0, 0), Vector3(0, 0, -1), float(so[1]) - float(so[0]), float(so[2]))
	_doorway(b, Vector3(0, 0, z0), Vector3(1, 0, 0), Vector3(0, 0, 1), float(no[1]) - float(no[0]), float(no[2]))
	_doorway(b, Vector3(x0, 0, (float(niche_open[0]) + float(niche_open[1])) * 0.5), Vector3(0, 0, 1), Vector3(1, 0, 0),
		float(niche_open[1]) - float(niche_open[0]), float(niche_open[2]))
	# Where the empty coat works: pick scuffs on the stone, a torn-off locker door, a bench by the entrance.
	var home: Vector3 = Layout.DRUDGE["pos"]
	Props.scuffs(b, home, 2.6, 16, 0.0)
	b.vbox(Vector3(-1.7, 0.025, -18.2), Vector3(0.58, 0.04, 1.9), Props.LOCKER.darkened(0.1), Basis(Vector3.UP, 0.4), NO_SHADOW)
	Props.bench(b, Vector3(x0 + 1.15, 0.0, -10.2), 2.0, "z")
	BelowProps.crate(b, Vector3(2.9, 0.0, z0 + 0.7), 0.7, 18.0)
	BelowProps.pickaxe_lean(b, Vector3(-2.2, 0.0, z0 + 0.3), 0.0)
	refs["lockers_lamp"] = BelowProps.lamp(n, Vector3(0.0, float(r["h"]), -11.2), {"style": "hanging", "hang": 1.5, "energy": 1.6, "range": 9.0, "shadow": true, "color": LAMP})
	BelowProps.lamp(n, Vector3(-1.2, float(r["h"]), -20.4), {"style": "hanging", "hang": 1.7, "energy": 1.0, "range": 6.5, "color": LAMP_DIM})


# --- the lantern niche (checkpoint) -----------------------------------------------------------------------

static func _niche(b: Builder, _area: Node3D, _refs: Dictionary) -> void:
	var n := b.begin("niche")
	var g := _r("niche_gap")
	b.shell("niche", FLOOR, WALL, CEIL)
	b.floor_rect(float(g["x0"]), float(g["x1"]), float(g["z0"]), float(g["z1"]), 0.0, FLOOR)
	b.dress_room_rock("niche", rock_cols(), {"size": 0.8, "spacing": 1.1})
	BelowProps.glowcaps(b, n, Vector3(-7.55, 0.0, -20.1), 5, 0.25, 0.45, 3.0)
	BelowProps.glowcaps(b, n, Vector3(-7.6, 0.0, -17.4), 4, 0.2)


# --- the stair down to the sump ------------------------------------------------------------------------------

static func _stair(b: Builder, _area: Node3D, _refs: Dictionary) -> void:
	var n := b.begin("stair")
	var r := _r("stair")
	var cols := rock_cols()
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	var z0: float = float(r["z0"])
	var z1: float = float(r["z1"])
	var top := float(r["y"]) + float(r["h"])            # flat ceiling (2.8)
	# Floors: the top landing (with the doorway through the lockers' wall), the stair, the bottom landing
	# (with the doorway through the sump's wall).
	b.floor_rect(x0, x1, Layout.STAIR_TOP_Z, float(_r("stair_top")["z1"]), 0.0, FLOOR)
	b.stairs(Vector3(0, 0.0, Layout.STAIR_TOP_Z), Vector3(0, -Layout.STAIR_DROP, Layout.STAIR_BOTTOM_Z), x1 - x0, 0.2, FLOOR, BelowProps.TIMBER_DARK)
	b.floor_rect(x0, x1, float(_r("stair_foot")["z0"]), Layout.STAIR_BOTTOM_Z, -Layout.STAIR_DROP, WET_FLOOR)
	var wall_h := top - float(r["y"])
	for s: float in [-1.0, 1.0]:
		var wx: float = (x0 - 0.5) if s < 0.0 else (x1 + 0.5)
		b.solid(Vector3(wx, float(r["y"]) + wall_h * 0.5, (z0 + z1) * 0.5), Vector3(1.0, wall_h, z1 - z0), WALL)
	b.ceiling_rect(x0, x1, z0, z1, top, CEIL)
	b.rock_wall(Vector3(x0, 0.0, z1), Vector3(x0, -Layout.STAIR_DROP, z0), Vector3(1, 0, 0), 4.6, cols, {"size": 0.75, "protrude": 0.2})
	b.rock_wall(Vector3(x1, 0.0, z1), Vector3(x1, -Layout.STAIR_DROP, z0), Vector3(-1, 0, 0), 4.6, cols, {"size": 0.75, "protrude": 0.2})
	for fz: float in [-25.8, -28.4]:
		var fy := Layout.stair_floor(0.0, float(fz))
		BelowProps.timber_frame(b, float(fz), x0, x1, fy, 3.1, "x")
	BelowProps.lamp(n, Vector3(x1 - 0.02, 1.0, -27.1), {"style": "wall", "energy": 0.9, "range": 5.0, "color": LAMP_DIM, "yaw": -90.0})


# --- ta_sump: the sluice sump -----------------------------------------------------------------------------------

static func _sump(b: Builder, _area: Node3D, refs: Dictionary) -> void:
	var n := b.begin("sump")
	var r := _r("sump")
	var cols := wet_cols()
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	var z0: float = float(r["z0"])
	var z1: float = float(r["z1"])
	var y: float = float(r["y"])
	var top: float = y + float(r["h"])
	var ch: Dictionary = Layout.CHANNEL
	b.shell("sump", WET_FLOOR, WET_WALL, CEIL, {"no_floor": true, "no_ceiling": true})
	# Floors: stone either side of the sluice channel; the channel bed is "water" underfoot.
	b.floor_rect(x0, x1, float(ch["z1"]), z1, y, WET_FLOOR)
	b.floor_rect(x0, x1, float(ch["z0"]), float(ch["z1"]), y, CHANNEL_BED, "water")
	b.floor_rect(x0, x1, z0, float(ch["z0"]), y, WET_FLOOR)
	Props.water_sheet(n, x0, x1, float(ch["z0"]), float(ch["z1"]), y + float(ch["depth"]))
	for i in 16:
		var ex := x0 + 0.5 + float(i) * (x1 - x0 - 1.0) / 15.0
		for ez: float in [float(ch["z0"]), float(ch["z1"])]:
			b.vblob(Vector3(ex + b.rng.randf_range(-0.2, 0.2), y + 0.03, float(ez) + b.rng.randf_range(-0.12, 0.12)), Vector3(0.22, 0.1, 0.18), b.vary(b.pick(cols), 0.08), -1, Basis(Vector3.UP, b.rng.randf() * TAU), {"small": true})
	# Ceiling with the hatch hole, and the plank-lined shaft above it (its top is the hatch lid).
	var hh: Dictionary = Layout.HATCH_HOLE
	var hx0: float = float(hh["x0"])
	var hx1: float = float(hh["x1"])
	var hz0: float = float(hh["z0"])
	var hz1: float = float(hh["z1"])
	b.solid(Vector3((x0 + x1) * 0.5, top + 0.3, (hz1 + z1 + 0.1) * 0.5), Vector3(x1 - x0 + 0.2, 0.6, z1 + 0.1 - hz1), CEIL)
	b.solid(Vector3((x0 - 0.1 + hx0) * 0.5, top + 0.3, (z0 - 0.1 + hz1) * 0.5), Vector3(hx0 - x0 + 0.1, 0.6, hz1 - z0 + 0.1), CEIL)
	b.solid(Vector3((hx1 + x1 + 0.1) * 0.5, top + 0.3, (z0 - 0.1 + hz1) * 0.5), Vector3(x1 + 0.1 - hx1, 0.6, hz1 - z0 + 0.1), CEIL)
	var sh := Layout.SHAFT_HEIGHT
	var sc := Vector3((hx0 + hx1) * 0.5, top + sh * 0.5, (hz0 + hz1) * 0.5)
	b.solid(Vector3(hx0 - 0.15, sc.y, sc.z), Vector3(0.3, sh, hz1 - hz0 + 0.6), SHAFT)
	b.solid(Vector3(hx1 + 0.15, sc.y, sc.z), Vector3(0.3, sh, hz1 - hz0 + 0.6), SHAFT)
	b.solid(Vector3(sc.x, sc.y, hz0 - 0.15), Vector3(hx1 - hx0, sh, 0.3), SHAFT)
	b.solid(Vector3(sc.x, sc.y, hz1 + 0.15), Vector3(hx1 - hx0, sh, 0.3), SHAFT)
	# Wet rock on every wall, kept clear of the stair opening, the sluice gate, the mark and the ladder.
	var mark: Vector3 = Layout.POINTS["mark"]
	var ladder: Vector3 = Layout.POINTS["ladder"]
	var sluice: Vector3 = Layout.POINTS["sluice"]
	var so: Array = r["open"]["s"][0]
	b.rock_wall(Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(0, 0, 1), 5.0, cols,
		{"size": 1.0, "skip": [[mark.x - x0 - 1.6, mark.x - x0 + 1.6, 3.0], [ladder.x - x0 - 1.0, ladder.x - x0 + 1.0, 5.2]]})
	b.rock_wall(Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(-1, 0, 0), 5.0, cols,
		{"size": 1.0, "skip": [[sluice.z - z0 - 1.7, sluice.z - z0 + 1.7, 3.6]]})
	b.rock_wall(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(1, 0, 0), 5.0, cols, {"size": 1.05})
	b.rock_wall(Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(0, 0, -1), 5.0, cols,
		{"size": 1.0, "skip": [[float(so[0]) - x0, float(so[1]) - x0, float(so[2])]]})
	b.ceiling_lumps(x0 + 0.5, hx0 - 0.8, z0 + 1.6, z1 - 0.5, top, [CEIL, Color("2f2a26")], 9, 1.0)
	b.pebbles(x0 + 0.6, x1 - 0.8, float(ch["z1"]) + 0.3, z1 - 0.4, y, cols, 30)
	b.pebbles(x0 + 0.6, x1 - 0.8, z0 + 0.4, float(ch["z0"]) - 0.3, y, cols, 18)
	# The sluice gate where the channel runs in; the ledge by it where Tobin left his note.
	Props.sluice_gate(b, n, Vector3(x1, y, sluice.z), Vector3(-1, 0, 0), float(ch["z1"]) - float(ch["z0"]))
	var note: Vector3 = Layout.POINTS["note"]
	b.solid(Vector3(x1 - 0.45, y + 0.35, note.z), Vector3(0.9, 0.7, 1.2), WET_WALL.lightened(0.12))
	BelowProps.papers(b, Vector3(x1 - 0.5, y + 0.7, note.z), 20.0)
	# A tall timber frame across the room (silhouette), crates and rope by the stair foot.
	BelowProps.timber_frame(b, z1 - 1.6, x0, x1, y, float(r["h"]), "x")
	BelowProps.crate(b, Vector3(-2.3, y, z1 - 0.7), 0.8, 10.0)
	BelowProps.rope_coil(b, Vector3(2.2, y, z1 - 0.6))
	# The ladder up the hatch shaft, and the lantern Tobin scratched into the north wall.
	Props.ladder(b, ladder, top + sh, Vector3(0, 0, 1))
	Props.lantern_mark(b, n, mark, Vector3(0, 0, 1))
	refs["sump_lamp"] = BelowProps.lamp(n, Vector3(0.6, top, -34.8), {"style": "hanging", "hang": 0.9, "energy": 1.5, "range": 9.0, "shadow": true, "color": LAMP_DIM})
	BelowProps.lamp(n, Vector3(x1 - 0.05, y + 2.1, note.z - 0.7), {"style": "wall", "energy": 0.8, "range": 4.5, "color": LAMP, "yaw": -90.0})
