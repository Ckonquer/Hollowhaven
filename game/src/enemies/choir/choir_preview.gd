extends Node3D
## Visual-QA stage for the Borrowed Choir (debug builds only; never placed by any area). A bare 12.4 m vault
## floor with the real lantern anchors and resonators, a stand-in "Krystal" and the boss, for tests/preview:
##   tools/godot.sh --path game --windowed --resolution 1600x900 -- --windowed \
##     --preview=res://src/enemies/choir/choir_preview.gd --preview-anim=a --preview-dist=15 --preview-height=9 \
##     --preview-target-y=1.0 --preview-light=dark --preview-wait=4 --shot-dir=<abs dir>
## --preview-anim: "a" (forms, an anchor raised after the gather = the reveal), "b" (layers, rings, one resonator
## woken), "c" (the kept flame, false lights, the hush), "exposed" (phase A exposure), "victory" (the defeat
## presentation). Add --preview-args='{"hv": true}' for high_visibility_cues.

const AnchorScript := preload("res://src/world/works/deep/lantern_anchor.gd")
const ResonatorScript := preload("res://src/world/works/deep/resonator.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Rules := preload("res://src/enemies/choir/choir_rules.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const RADIUS := 12.4
const PERIM := 10.4

var boss: Node = null
var stand_in: Node3D = null
var anchors: Array = []
var resonators: Array = []
var mode: String = "a"
var _did: bool = false
var _t: float = 0.0


func setup(p: Dictionary) -> void:
	if bool(p.get("hv", false)):
		Settings.set_value("high_visibility_cues", true)


func _ready() -> void:
	if not OS.is_debug_build():
		return
	Kit.add(self, Kit.cylinder(RADIUS, RADIUS, 0.1, Mat.toon(Color("9a92a4")), 48), Vector3(0, -0.05, 0))
	Kit.add(self, Kit.cylinder(PERIM, PERIM, 0.1, Mat.toon(Color("c8bca4")), 48), Vector3(0, -0.04, 0))
	for i in 3:
		var r := deg_to_rad(float([-150.0, -30.0, 90.0][i]))
		var a: Node3D = AnchorScript.new()
		a.setup({"id": "preview_anchor_%d" % i, "reveal_radius": 9.0, "require_lantern": false})
		add_child(a)
		a.position = Vector3(cos(r), 0.0, sin(r)) * 7.0
		a.rotation.y = atan2(-a.position.x, -a.position.z)
		anchors.append(a)
	for x in [-10.6, 10.6]:
		var rs: Node3D = ResonatorScript.new()
		rs.setup({"id": "preview_res_%d" % int(x), "symbols": Layout.bell_symbols()})
		add_child(rs)
		rs.position = Vector3(x, 0.0, 0.0)
		rs.rotation.y = atan2(-x, 0.0)
		resonators.append(rs)
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar health: Node\nvar lantern_on := true\nfunc _init() -> void:\n\thealth = preload(\"res://src/combat/health.gd\").new()\n\thealth.name = \"Health\"\n\thealth.max_hp = 100000.0\n\tadd_child(health)\nfunc knockback(_d: Vector3, _f: float) -> void:\n\tpass\n"
	s.reload()
	stand_in = s.new()
	add_child(stand_in)
	stand_in.position = Vector3(0.0, 0.0, -8.5)
	boss = Factory.create("borrowed_choir", {"arena_center": Vector3.ZERO, "arena_radius": RADIUS, "perimeter_radius": PERIM,
		"anchor_nodes": anchors, "resonators": resonators, "symbols": Layout.bell_symbols(), "mode": "trial", "seed": 3})
	if boss == null:
		return
	add_child(boss)
	boss.set("target_override", stand_in)


func play_anim(anim: String) -> void:
	mode = anim
	if boss == null:
		return
	var ph := 1
	match anim:
		"b":
			ph = 2
		"c", "victory":
			ph = 3
	if ph > 1:
		boss.set("phase", ph)
		(boss.get("health") as Node).call("set_hp", Rules.phase_start_hp(ph, float((boss.get("health") as Node).get("max_hp"))))
	boss.call("start_fight")


func _process(delta: float) -> void:
	if boss == null or _did:
		return
	_t += delta
	var st := String(boss.get("state"))
	match mode:
		"a":
			if st == "a_wait":
				_did = true
				anchors[0].call("raise", null)
		"exposed":
			if st == "a_wait":
				anchors[0].call("raise", null)
				boss.call("pick_form", int(boss.get("genuine")), stand_in)
				_did = true
		"b":
			if st == "b_idle":
				_did = true
				for sid in (resonators[0] as Node).get("sequence"):
					(resonators[0] as Node).call("strike", String(sid))
		"victory":
			if st == "c_open":
				anchors[int(boss.get("flame_anchor"))].call("raise", null)
			elif st == "c_exposed":
				(boss.get("health") as Node).call("apply_damage", 99999.0, stand_in)
				if bool(boss.call("is_defeated")):
					_did = true
