extends "res://tests/test_case.gd"
## Procedural visuals of the Chapter Two enemies (module C5), checked numerically (no screenshots): distinct
## silhouettes (bounds / proportions), feet on the ground, bounded mesh counts, no lights, readable wind-up poses
## (mimic mouth gapes / feet tuck, patchwalker rake raised / mud clod grows, velvet wing folds its cloak / hangs,
## bellcap swells, wisp's true form appears only when revealed, warden's shell splits open when exposed) and
## telegraph tints that only firm up (never strobe) with reduce_flashing.

const MimicVisual := preload("res://src/enemies/pumpkin_mimic_visual.gd")
const WalkerVisual := preload("res://src/enemies/patchwalker_visual.gd")
const WingVisual := preload("res://src/enemies/velvet_wing_visual.gd")
const BellVisual := preload("res://src/enemies/bellcap_sentry_visual.gd")
const WispVisual := preload("res://src/enemies/borrowed_wisp_visual.gd")
const WardenVisual := preload("res://src/enemies/quarry_warden_visual.gd")

const DT := 1.0 / 60.0
const MAX_MESHES := 110

var _nodes: Array = []


func before_each() -> void:
	Settings.set_value("reduce_flashing", false)


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Settings.set_value("reduce_flashing", false)
	await wait_frames(1)


func _make(script: Script, pos: Vector3) -> Node3D:
	var v: Node3D = script.new()
	add_child(v)
	v.global_position = pos
	_nodes.append(v)
	return v


static func _meshes(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
	return out


static func _aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for mi in _meshes(root):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.top_level:
			continue
		var skip := false
		var p: Node = m.get_parent()
		while p != null and p != root:
			if p is Node3D and (p as Node3D).top_level:
				skip = true
				break
			p = p.get_parent()
		if skip:
			continue
		var ab: AABB = (inv * m.global_transform) * m.get_aabb()
		out = ab if first else out.merge(ab)
		first = false
	return out


static func _lights(n: Node) -> int:
	var c := 1 if n is Light3D else 0
	for ch in n.get_children():
		c += _lights(ch)
	return c


func _run(v: Node3D, seconds: float) -> void:
	for i in int(seconds / DT):
		v._process(DT)


func test_silhouettes_are_distinct_grounded_and_bounded() -> void:
	var mimic := _make(MimicVisual, Vector3(0, 0, 0))
	var walker := _make(WalkerVisual, Vector3(10, 0, 0))
	var bell := _make(BellVisual, Vector3(20, 0, 0))
	var warden := _make(WardenVisual, Vector3(30, 0, 0))
	for v in [mimic, walker, bell, warden]:
		_run(v, 0.5)
	var bm := _aabb(mimic)
	var bw := _aabb(walker)
	var bb := _aabb(bell)
	var bd := _aabb(warden)
	for pair in [["mimic", bm], ["patchwalker", bw], ["bellcap", bb], ["warden", bd]]:
		var ab: AABB = pair[1]
		assert_true(absf(ab.position.y) < 0.12, "%s stands on the ground (min y %.2f)" % [pair[0], ab.position.y])
	assert_true(bm.size.y < 1.05 and bm.size.x > bm.size.y * 0.9, "mimic: low and round (%s)" % str(bm.size))
	assert_true(bw.size.y > 1.8 and bw.size.y > bw.size.x, "patchwalker: tall and narrow (%s)" % str(bw.size))
	assert_true(bb.size.y > 1.4 and bb.size.y < 2.0, "bellcap: squat bell (%s)" % str(bb.size))
	assert_true(bd.size.x > 2.0 and bd.size.y > 2.0, "warden: broad and big (%s)" % str(bd.size))
	var wing := _make(WingVisual, Vector3(40, 0, 0))
	var wisp := _make(WispVisual, Vector3(50, 0, 0))
	for v in [mimic, walker, bell, warden, wing, wisp]:
		var n := _meshes(v).size()
		assert_true(n <= MAX_MESHES, "%s mesh count bounded (%d)" % [v.name, n])
		assert_eq(_lights(v), 0, "%s adds no dynamic light" % v.name)


func test_mimic_dormant_bite_and_roll_poses() -> void:
	var v := _make(MimicVisual, Vector3.ZERO)
	v.set_state("dormant")
	_run(v, 0.5)
	assert_false(bool(v.eyes_open()), "dormant: eyes shut")
	assert_true(float(v.feet_out) < 0.2, "dormant: feet tucked (it reads as a pumpkin)")
	v.twitch()
	assert_true(bool(v.twitching), "a stem twitch plays")
	_run(v, 0.4)
	assert_false(bool(v.twitching), "a quick twitch")
	v.set_attack("bite")
	v.set_state("telegraph", 1.0)
	_run(v, 0.5)
	assert_true(bool(v.eyes_open()), "awake: eyes open")
	assert_true(float(v.mouth_open) > 0.8, "bite tell: the mouth gapes wide")
	assert_true(float(v.tint_alpha()) > 0.1, "tinted")
	v.set_attack("roll")
	v.set_state("telegraph", 1.4)
	_run(v, 0.5)
	assert_true(float(v.feet_out) < 0.2, "roll tell: the vine feet tuck in")


func test_patchwalker_two_distinct_tells() -> void:
	var v := _make(WalkerVisual, Vector3.ZERO)
	v.set_attack("rake")
	v.set_state("telegraph", 1.1)
	_run(v, 0.6)
	assert_true(float(v.rake_raise) > 0.8, "rake raised high")
	assert_true(float(v.mud_size) < 0.1, "no mud")
	v.set_state("recover", 1.0)
	_run(v, 0.5)
	v.set_attack("mud_clod")
	v.set_state("telegraph", 1.6)
	_run(v, 1.4)
	assert_true(float(v.mud_size) > 0.8, "a mud clod grows in its hand")
	assert_true(float(v.rake_raise) < 0.2, "the rake stays down: a different pose")


func test_velvet_wing_hangs_and_folds() -> void:
	var v := _make(WingVisual, Vector3.ZERO)
	v.set_state("idle")
	_run(v, 1.0)
	assert_true(bool(v.hanging), "idle: hangs upside down")
	v.set_state("chase")
	_run(v, 1.0)
	assert_false(bool(v.hanging))
	assert_true(float(v.fold) < 0.2, "flying: wings open")
	v.set_attack("dash")
	v.set_state("telegraph", 1.0)
	_run(v, 0.6)
	assert_true(float(v.fold) > 0.8, "dash tell: the cloak folds")
	v.set_attack("drain")
	v.set_state("telegraph", 1.5)
	_run(v, 0.6)
	assert_true(float(v.fold) < 0.2, "drain tell: wings spread")
	assert_true(bool(v.eyes_glowing()), "and its eyes glow")


func test_bellcap_swells_and_shows_symbols() -> void:
	var v := _make(BellVisual, Vector3.ZERO)
	v.set_radius(4.0)
	_run(v, 0.3)
	assert_false(bool(v.symbols_visible()), "no symbols at rest")
	v.set_state("telegraph", 1.3)
	_run(v, 1.2)
	assert_true(bool(v.symbols_visible()), "symbols during the swell")
	assert_true(float(v.swell) > 0.7, "the cap swells")
	v.set_state("recover", 1.8)
	_run(v, 0.6)
	assert_false(bool(v.symbols_visible()), "symbols gone in the recovery")
	assert_true(float(v.swell) < 0.3, "the cap settles")


func test_wisp_true_form_only_when_revealed() -> void:
	var v := _make(WispVisual, Vector3.ZERO)
	v.preview = true
	_run(v, 0.5)
	assert_almost(float(v.reveal_k), 0.0, 0.001, "veiled: the false light only")
	var veiled := _aabb(v)
	v.set_revealed(true)
	_run(v, 0.6)
	assert_almost(float(v.reveal_k), 1.0, 0.001, "revealed")
	var true_form := _aabb(v)
	assert_true(true_form.size.y > veiled.size.y * 0.9, "a hooded body with a tail appears (%s vs %s)" % [str(true_form.size), str(veiled.size)])
	assert_eq(_lights(v), 0, "never a real light")


func test_warden_shell_opens_only_when_exposed() -> void:
	var v := _make(WardenVisual, Vector3.ZERO)
	v.set_state("chase")
	_run(v, 0.5)
	assert_true(float(v.shell_open) < 0.05, "shell closed")
	assert_false(bool(v.bell_glowing()), "bell dim")
	v.set_state("exposed", 6.0)
	_run(v, 0.8)
	assert_true(float(v.shell_open) > 0.9, "exposed: the shell splits open")
	assert_true(bool(v.bell_glowing()), "around the glowing bell")
	v.set_attack("pulses")
	v.set_state("telegraph", 1.6)
	v.set_pips(3)
	assert_eq(int(v.pips_lit), 3, "three pips")
	v.pulse_fired(2)
	assert_eq(int(v.pips_lit), 2, "one goes out per pulse")


func test_reduce_flashing_tints_only_firm_up() -> void:
	Settings.set_value("reduce_flashing", true)
	var specs := [[MimicVisual, "bite"], [WalkerVisual, "rake"], [WingVisual, "dash"], [WardenVisual, "slam"]]
	for s in specs:
		var v := _make(s[0], Vector3.ZERO)
		v.set_attack(String(s[1]))
		v.set_state("telegraph", 1.2)
		var prev := -1.0
		var ok := true
		for i in 70:
			v._process(DT)
			var a: float = v.tint_alpha()
			if prev >= 0.0 and a < prev - 0.001:
				ok = false
			prev = a
		assert_true(ok, "%s: with reduce_flashing the tint never pulses" % String(s[1]))
		assert_true(prev > 0.1, "%s: but it is tinted" % String(s[1]))
	var w := _make(WispVisual, Vector3.ZERO)
	w.set_state("telegraph", 1.4)
	var p2 := -1.0
	var ok2 := true
	for i in 70:
		w._process(DT)
		var a2: float = w.tint_alpha()
		if p2 >= 0.0 and a2 < p2 - 0.001:
			ok2 = false
		p2 = a2
	assert_true(ok2, "wisp: steady tint with reduce_flashing")
