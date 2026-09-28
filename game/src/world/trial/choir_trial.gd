extends RefCounted
## ECHO TRIAL "The Borrowed Song" - the arena builder of the Borrowed Choir's trial (data/trials.gd "choir"; MP §13.3,
## §15). A remembered copy of the Choir Vault (data/works_layout_deep.gd VAULT, positions relative to its centre and
## turned half round so the corridor comes in from +z like every trial, which keeps the vault exactly as it looks
## from its real entrance): the large circular pale vault (radius 12.4), the warm SAFE PERIMETER walk (radius
## >= 10.4, the band every Choir attack stops at), the three FIXED lantern anchors and the two FIXED resonators (the
## real src/world/works/deep/lantern_anchor.gd and resonator.gd, fresh nodes carrying the Bellmaker's symbols of
## data/works_layout_deep.gd bell_symbols()), the Choir's harmless trappings (cracked bells, wooden masks, harvest
## ribbons) and the sealed exit gate. The corridor holds the bellmakers' order (the symbol order the resonators
## answer to, readable, never colour alone) and ends in the pale entry pad (safe) and the pale door.
##
## The boss is the REAL src/enemies/borrowed_choir.gd in mode "trial", with no arena node: it wakes when Krystal
## steps inside the perimeter walk, stands down (to the start of the phase reached) when she walks back to the pad,
## never reads or writes ch2_choir_defeated, never emits Events.boss_defeated, never dismisses itself on the story
## flag. The anchors and resonators persist nothing. Arachnophobia: nothing here is spider-like. Comfort: the
## boss's own warnings honour timing_assist / high_visibility_cues; nothing here flashes.
##   static func build(area: Node3D) -> Dictionary   (called by src/world/areas_ch2/echo_trial.gd _ready)
## Returns {pad, exit, exit_yaw, bounds, zone_center, zone_radius, plate, boss, anchors, resonators, symbols,
## arena_center, arena_radius, perimeter_radius, order_board}.

const VaultLayout := preload("res://data/works_layout_deep.gd")
const Builder := preload("res://src/world/manor/manor_builder.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const AnchorScript := preload("res://src/world/works/deep/lantern_anchor.gd")
const ResonatorScript := preload("res://src/world/works/deep/resonator.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Fx := preload("res://src/world/trial/trial_fx.gd")

const BOSS_ID := "borrowed_choir"
const ROOM := "echo_vault"
const HEIGHT := 12.0
const SEGMENTS := 48
const CORRIDOR_HALF := 2.0
const CORRIDOR_START := 12.2
const CORRIDOR_END := 25.0
const CORRIDOR_H := 4.5
const DOOR_H := 3.6
const PAD_Z := 21.8
const EXIT_Z := CORRIDOR_END - 0.6


static func radius() -> float:
	return float(VaultLayout.VAULT["radius"])


static func perimeter() -> float:
	return float(VaultLayout.VAULT["perimeter"])


## A point of the real vault in the memory: relative to the vault centre, turned half round (x, z) -> (-x, -z).
static func rel(p: Vector3) -> Vector3:
	var c: Vector3 = VaultLayout.VAULT["center"]
	return Vector3(c.x - p.x, p.y - c.y, c.z - p.z)


static func build(area: Node3D) -> Dictionary:
	area.call("build_environment", {"bg": Color("0e0c14"), "ambient": Color("6e6888"), "ambient_energy": 0.45,
		"lamps": [[Vector3(0, 3.2, PAD_Z), Color("ffe2a8"), 0.9, 7.0]]})
	var b := Builder.new(area)
	b.begin(ROOM)
	_shell(b)
	_trappings(b)
	b.finish()
	for k in 4:
		var ang := TAU * (float(k) + 0.25) / 4.0
		var o := OmniLight3D.new()
		o.name = "VaultGlow%d" % k
		o.light_color = Color("c8b8e8")
		o.light_energy = 0.9
		o.omni_range = 13.0
		o.shadow_enabled = false
		area.add_child(o)
		o.position = Vector3(cos(ang) * 8.5, 7.5, sin(ang) * 8.5)
	var symbols: Array = VaultLayout.bell_symbols()
	var anchors := _anchors(area)
	var resonators := _resonators(area, symbols)
	var board := _order_board(area, symbols)
	Fx.motes(area, Vector3(0, 4.0, 0), Vector3(10.0, 3.5, 10.0))
	Fx.pad_ring(area, Vector3(0, 0, PAD_Z), 2.4)
	var points: Array = []
	for a in anchors:
		points.append((a as Node3D).position)
	var out := {"pad": Vector3(0, 0, PAD_Z), "exit": Vector3(0, 0, EXIT_Z), "exit_yaw": PI,
		"bounds": Rect2(-radius() - 1.5, -radius() - 1.5, (radius() + 1.5) * 2.0, CORRIDOR_END + radius() + 2.5),
		"zone_center": Vector3(0, 0, 5.0), "zone_radius": 26.0, "plate": Vector3(0, 3.4, PAD_Z - 1.4),
		"anchors": anchors, "anchor_points": points, "resonators": resonators, "symbols": symbols, "order_board": board,
		"arena_center": Vector3.ZERO, "arena_radius": radius(), "perimeter_radius": perimeter(), "boss": null}
	out["boss"] = _spawn_boss(area, out)
	return out


## The real boss in trial mode (null when its script is missing: a quiet memory, the pale door still leads home).
static func _spawn_boss(area: Node3D, a: Dictionary) -> Node:
	if not Factory.can_spawn(BOSS_ID):
		return null
	var boss: Node = Factory.spawn(BOSS_ID, area, Transform3D(Basis.IDENTITY, Vector3.ZERO), {
		"arena_center": Vector3.ZERO, "arena_radius": radius(), "perimeter_radius": perimeter(),
		"anchors": (a["anchor_points"] as Array).duplicate(), "anchor_nodes": (a["anchors"] as Array).duplicate(),
		"resonators": (a["resonators"] as Array).duplicate(), "symbols": (a["symbols"] as Array).duplicate(true),
		"mode": "trial", "alert": false})
	if boss != null:
		boss.name = "EchoChoir"
	return boss


# --- Room ---------------------------------------------------------------------------------------------------

static func _shell(b: Builder) -> void:
	var r := radius()
	var pr := perimeter()
	# Floor: one slab under the vault + the corridor slab (collision), discs for the look.
	b.floor_rect(-r - 1.5, r + 1.5, -r - 1.5, r + 1.5, 0.0, Art.PALE_DARK, "stone", false)
	b.floor_rect(-CORRIDOR_HALF, CORRIDOR_HALF, r + 1.5, CORRIDOR_END, 0.0, Art.PALE_DARK, "stone")
	b.vcyl(Vector3(0, -0.2, 0), r + 1.2, 0.4, Art.PALE_DARK, Basis.IDENTITY, {"segments": 48})
	b.vcyl(Vector3(0, 0.012, 0), r, 0.024, Art.WARM_BAND, Basis.IDENTITY, {"shadows": false, "segments": 48})
	b.vcyl(Vector3(0, 0.02, 0), pr, 0.024, Art.PALE, Basis.IDENTITY, {"shadows": false, "segments": 48})
	b.vcyl(Vector3(0, 0.03, 0), 2.0, 0.02, Art.PALE_DARK.darkened(0.35), Basis.IDENTITY, {"shadows": false, "segments": 24})
	for ring_r in [3.2, 6.4]:
		b.vring(Vector3(0, 0.03, 0), float(ring_r), 0.02, Art.PALE_DARK.darkened(0.25))
	# The ring wall, open where the corridor comes in (+z); a lintel over the doorway.
	var chord := 2.0 * (r + 1.0) * sin(PI / float(SEGMENTS)) * 1.1
	for i in SEGMENTS:
		var ang := TAU * float(i) / float(SEGMENTS)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var wc := dir * (r + 0.5)
		var basis := Basis(Vector3.UP, PI * 0.5 - ang)
		if wc.z > 0.0 and absf(wc.x) < CORRIDOR_HALF + chord * 0.5:
			b.solid(Vector3(wc.x, DOOR_H + (HEIGHT - DOOR_H) * 0.5, wc.z), Vector3(chord, HEIGHT - DOOR_H, 1.0), Art.PALE, "stone", basis)
			continue
		b.solid(Vector3(wc.x, HEIGHT * 0.5, wc.z), Vector3(chord, HEIGHT, 1.0), Art.PALE, "stone", basis)
		b.vbox(Vector3(wc.x, 0.35, wc.z) - dir * 0.55, Vector3(chord, 0.7, 0.2), Art.PALE_DARK, basis, {"shadows": false})
	# Fillers where the ring meets the corridor (no gap to step off into).
	for sx in [-1.0, 1.0]:
		b.solid(Vector3(float(sx) * (CORRIDOR_HALF + 1.2), CORRIDOR_H * 0.5, r + 0.6), Vector3(2.4, CORRIDOR_H, 1.4), Art.PALE)
	# Ceiling (a dark dome disc, visual) and the corridor.
	b.vcyl(Vector3(0, HEIGHT + 0.2, 0), r + 1.2, 0.4, Art.PALE_DARK.darkened(0.45), Basis.IDENTITY, {"shadows": false, "segments": 48})
	var clen := CORRIDOR_END - CORRIDOR_START + 0.5
	for sx in [-1.0, 1.0]:
		b.solid(Vector3(float(sx) * (CORRIDOR_HALF + 0.25), CORRIDOR_H * 0.5, (CORRIDOR_START + CORRIDOR_END) * 0.5 + 0.25), Vector3(0.5, CORRIDOR_H, clen), Art.PALE_DARK)
	b.solid(Vector3(0, CORRIDOR_H * 0.5, CORRIDOR_END + 0.25), Vector3(CORRIDOR_HALF * 2.0 + 1.0, CORRIDOR_H, 0.5), Art.PALE_DARK)
	b.solid(Vector3(0, CORRIDOR_H + 0.25, (r + CORRIDOR_END) * 0.5 + 0.8), Vector3(CORRIDOR_HALF * 2.0 + 1.0, 0.5, CORRIDOR_END - r - 1.0), Art.PALE_DARK.darkened(0.2))
	# The real vault's exit side (opposite the entrance): the portcullis stays shut in the memory (visual).
	var gz := -(r + 0.02)
	for k in 10:
		b.vcyl(Vector3(-1.8 + float(k) * 0.4, 1.8, gz), 0.045, 3.6, Art.IRON, Basis.IDENTITY, {"shadows": false, "segments": 6})
	for y in [0.5, 1.8, 3.1]:
		b.vbox(Vector3(0, float(y), gz), Vector3(3.8, 0.1, 0.1), Art.IRON, Basis.IDENTITY, {"shadows": false})


## The Choir's trappings round the rim: cracked bells, wooden masks, harvest ribbons (all harmless, no collision).
static func _trappings(b: Builder) -> void:
	var r := radius()
	for k in 12:
		var ang := TAU * (float(k) + 0.5) / 12.0
		var deg := rad_to_deg(ang)
		if absf(wrapf(deg - 90.0, -180.0, 180.0)) < 20.0 or absf(wrapf(deg + 90.0, -180.0, 180.0)) < 20.0:
			continue
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var basis := Basis(Vector3.UP, PI * 0.5 - ang)
		var bp := dir * (r - 1.2) + Vector3(0, 8.0 + float(k % 3) * 1.0, 0)
		b.vcyl(Vector3(bp.x, (bp.y + HEIGHT) * 0.5, bp.z), 0.03, HEIGHT - bp.y, Art.IRON, Basis.IDENTITY, {"shadows": false})
		b.vcone(bp - Vector3(0, 0.5, 0), 0.6, 1.1, Art.BRASS.darkened(0.3), Basis.IDENTITY, {"shadows": false})
		b.vbox(bp - Vector3(0, 0.6, 0) + dir * 0.35, Vector3(0.05, 0.8, 0.03), Color(0.1, 0.08, 0.09), basis, {"shadows": false})
		var mp := dir * (r - 0.05) + Vector3(0, 5.2, 0)
		b.vsphere(mp, Vector3(0.5, 0.65, 0.18), Color("c9a878"), basis, {"shadows": false})
		for s in [-1.0, 1.0]:
			b.vbox(mp - dir * 0.14 + Vector3(0, 0.12, 0) + dir.cross(Vector3.UP) * float(s) * 0.17, Vector3(0.1, 0.07, 0.05), Color(0.08, 0.06, 0.07), basis, {"shadows": false})
		var rc: Color = Art.RIBBONS[k % Art.RIBBONS.size()]
		b.vbox(bp - Vector3(0, 1.6, 0) - dir * 0.2, Vector3(0.1, 1.8, 0.02), rc, basis, {"shadows": false})


## The three fixed lantern anchors (fresh nodes: nothing persists), hooks facing the empty centre.
static func _anchors(area: Node3D) -> Array:
	var out: Array = []
	var list: Array = VaultLayout.VAULT["anchors"]
	for i in list.size():
		var a: Node3D = AnchorScript.new()
		a.setup({"id": "echo_vault_anchor_%d" % i, "reveal_radius": 9.0})
		a.name = "EchoAnchor_%d" % i
		area.add_child(a)
		var p := rel(list[i])
		a.position = Vector3(p.x, 0.0, p.z)
		a.rotation.y = atan2(-p.x, -p.z)       # hook arm (local +z) points at the centre
		out.append(a)
	return out


## The two fixed resonators carrying the Bellmaker's symbols, plates facing the centre.
static func _resonators(area: Node3D, symbols: Array) -> Array:
	var out: Array = []
	var list: Array = VaultLayout.VAULT["resonators"]
	for i in list.size():
		var r: Node3D = ResonatorScript.new()
		r.setup({"id": "echo_resonator_%d" % i, "symbols": symbols})
		r.name = "EchoResonator_%d" % i
		area.add_child(r)
		var p := rel(list[i])
		r.position = Vector3(p.x, 0.0, p.z)
		r.rotation.y = atan2(-p.x, -p.z)       # plates (local +z) face the centre
		out.append(r)
	return out


## "The bellmakers' order" on the corridor's west wall, facing the corridor: numbered symbols with their names
## (shape + words, never colour alone); reading it says the order in words.
static func _order_board(area: Node3D, symbols: Array) -> Node3D:
	var n := Node3D.new()
	n.name = "EchoOrderBoard"
	area.add_child(n)
	n.position = Vector3(-CORRIDOR_HALF + 0.02, 0.0, 16.0)
	n.rotation.y = PI * 0.5                  # faces +x, into the corridor
	var wood := Mat.outlined(Mat.toon(Color("5a3b27")), 0.016)
	var sheet := Mat.toon(Color("efe0bd"), {"emission": Color("efe0bd"), "emission_energy": 0.12})
	Kit.add(n, Kit.box(Vector3(2.7, 1.35, 0.08), wood), Vector3(0, 1.9, 0.04))
	Kit.add(n, Kit.box(Vector3(2.5, 1.15, 0.02), sheet), Vector3(0, 1.9, 0.09))
	var title := Art.label(n, "THE BELLMAKERS' ORDER", Vector3(0, 2.36, 0.11), 24, Color("3a2a22"))
	title.outline_size = 0
	var names: Array = []
	var k := symbols.size()
	for i in k:
		var s: Dictionary = symbols[i]
		var nm := String(s.get("name", String(s["id"]).capitalize()))
		names.append(nm)
		var x := (float(i) - float(k - 1) * 0.5) * 0.6
		var num := Art.label(n, str(i + 1), Vector3(x, 2.14, 0.11), 26, Color("3a2a22"))
		num.outline_size = 0
		var sym := Art.symbol(n, String(s["id"]), 0.36, Color("b0703a"), nm)
		sym.position = Vector3(x, 1.86, 0.12)
		var tag: Variant = sym.get_node_or_null("Name")
		if tag is Label3D:
			(tag as Label3D).font_size = 20
	var order := ", then ".join(PackedStringArray(names))
	var it: Node3D = Interactable.new()
	it.setup({"text": "Read the bellmakers' order", "size": Vector3(2.6, 1.6, 1.0), "offset": Vector3(0, 1.8, 0.5),
		"handler": func(_p: Node) -> void: Events.say.emit("The bellmakers' order", "%s. The resonators still answer to it." % order, 8.0),
		"id": "echo_order"})
	it.name = "OrderInteract"
	n.add_child(it)
	n.set_meta("order_text", order)
	return n
