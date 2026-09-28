extends "res://tests/test_case.gd"
## Fit between Krystal's appearance pieces (visual QA pass AV-00..AV-19, qa/tmp/visual/VISUAL_BUGS_MERGED.md): hair
## accessories and the flower crown sit ON every hairstyle instead of inside it, head armor covers the hair, capes stand
## out from the top they are worn over, body armor hides the jacket's front details, twin braids stay symmetric when she
## looks around, the ponytail hangs instead of hooking up, long hair drapes over back packs, skirt panels open as one
## piece and bunch up in a roll, and a tall hat folds down instead of propping up the roll.
## Numbers are measured on the real built meshes (source parts kept aside by the joint bake included).

const AvatarScript := preload("res://src/player/krystal_avatar.gd")
const AppearanceData := preload("res://data/appearance.gd")
const HairBuilder := preload("res://src/player/avatar/hair_builder.gd")
const ArmorBuilder := preload("res://src/player/avatar/armor_builder.gd")
const SkirtRig := preload("res://src/player/avatar/skirt_rig.gd")
const DT := 1.0 / 60.0

var _avs: Array = []


func after_each() -> void:
	for a in _avs:
		if is_instance_valid(a):
			(a as Node).free()
	_avs.clear()


func _avatar(look: Dictionary, driven: bool = false) -> Node3D:
	var av: Node3D = AvatarScript.new()
	av.driven = driven
	av.follow_game_state = false
	av.call("apply_look", look)
	add_child(av)
	_avs.append(av)
	return av


func _look_with(changes: Dictionary) -> Dictionary:
	var look := ItemDB.legacy_look()
	for k in changes:
		look[k] = changes[k]
	return look


func _look_for_outfit(oid: String) -> Dictionary:
	var o := ItemDB.outfit(oid)
	var look := ItemDB.legacy_look()
	for slot in o["parts"]:
		look[slot] = o["parts"][slot]
	look["palette"] = (o["palette"] as Dictionary).duplicate()
	look["hair"] = o["hair"]
	look["hair_color"] = o["hair_color"]
	return look


func _step(av: Node3D, n: int, move: Vector3 = Vector3.ZERO) -> void:
	for i in n:
		av.global_position += move * DT
		av.call("_process", DT)


## Every source mesh of a unit's containers on `host_key` (in-box parts, nested nodes, parts kept aside by the bake).
static func _unit_meshes(av: Node3D, unit: String, host_key: String, direct_only: bool = false) -> Array:
	var host: Node3D = av.get("_hosts")[host_key]
	var detached: Dictionary = av.get("_detached")
	var out: Array = []
	for b in av.get("_unit_boxes").get(unit, []):
		var box := b as Node3D
		if box.get_parent() != host:
			continue
		var stack: Array = box.get_children()
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				out.append([n, box])
			elif not direct_only:
				stack.append_array(n.get_children())
		for mi in detached.get(box.get_instance_id(), []):
			out.append([mi, box])
	return out


## Points (every `step`-th vertex) of a unit on HeadCenter, in HeadCenter space.
static func _head_points(av: Node3D, unit: String, step: int = 2) -> PackedVector3Array:
	var hc: Node3D = av.get("_head_c")
	var pts := PackedVector3Array()
	for rec in _unit_meshes(av, unit, "head_c"):
		var mi := rec[0] as MeshInstance3D
		var box := rec[1] as Node3D
		var xf: Transform3D = hc.global_transform.affine_inverse() * (mi.global_transform if mi.is_inside_tree() else box.global_transform * mi.transform)
		for s in mi.mesh.get_surface_count():
			var v: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for k in range(0, v.size(), step):
				pts.append(xf * v[k])
	return pts


## The static hair parts (spheres / capsules, HeadCenter space) of the avatar's current hair.
static func _hair_parts(av: Node3D) -> Array:
	var parts: Array = []
	for rec in _unit_meshes(av, "hair", "head_c", true):
		parts.append(rec[0])
	return HairBuilder.primitives(parts)


## True when `p` (HeadCenter space) lies inside any hair part (grown by `grow` metres) - an independent point test,
## not the ray probe the builders use.
static func _inside_hair(parts: Array, p: Vector3, grow: float = 0.0) -> bool:
	for rec in parts:
		var inv: Transform3D = rec[0]
		var q := inv * p
		var r := float(rec[2]) + grow   # part-local units: `grow` is approximate on squashed parts
		if int(rec[1]) == 0:
			if q.length() < r:
				return true
		else:
			var hh := float(rec[3])
			var c := Vector3(0, clampf(q.y, -hh, hh), 0)
			if (q - c).length() < r:
				return true
	return false


## Fraction of `pts` outside every hair part.
static func _outside_fraction(parts: Array, pts: PackedVector3Array) -> float:
	if pts.is_empty():
		return 0.0
	var out := 0
	for p in pts:
		if not _inside_hair(parts, p):
			out += 1
	return float(out) / float(pts.size())


## AV-00 / AV-17: every hair accessory shows on every hairstyle (at least half of it outside the hair - pins and clips
## legitimately push their shafts in - and resting within a few centimetres of it), bare-headed and under a hat. The
## Chapter One flower clip on the Chapter One braid is pinned to its exact spot by test_avatar_look_legacy.
func test_hair_accessories_sit_on_every_hairstyle() -> void:
	var av := _avatar(ItemDB.legacy_look())
	var worst := 1.0
	var worst_case := ""
	for hat in ["", "sun_hat", "flower_crown"]:
		for acc in ItemDB.parts_for_slot("hair_acc"):
			for hair in AppearanceData.HAIRSTYLES:
				if acc == "flower_clip" and hair == "side_braid" and hat == "":
					continue
				av.call("apply_look", _look_with({"hair": hair, "hair_acc": acc, "hat": hat}))
				var parts := _hair_parts(av)
				assert_false(parts.is_empty(), hair + " hair parts found")
				var pts := _head_points(av, "hair_acc")
				assert_true(pts.size() > 20, "%s is built on %s" % [acc, hair])
				var f := _outside_fraction(parts, pts)
				if f < worst:
					worst = f
					worst_case = "%s on %s (hat %s)" % [acc, hair, hat]
				assert_true(f >= 0.5, "%s shows on %s (hat '%s'): %.0f %% outside the hair" % [acc, hair, hat, f * 100.0])
				# resting on the hair, not floating: some of it within 2.5 cm of a hair part
				var touching := false
				for p in pts:
					if _inside_hair(parts, p, 0.025):
						touching = true
						break
				assert_true(touching, "%s rests on %s (hat '%s')" % [acc, hair, hat])
	print("  least visible hair accessory: %.0f %% outside the hair (%s)" % [worst * 100.0, worst_case])


## AV-01: the flower crown rides on top of every hairstyle, its back half too (the gameplay camera looks at her back),
## and its flowers ring the whole head.
func test_flower_crown_rides_on_the_hair() -> void:
	var av := _avatar(ItemDB.legacy_look())
	var slowest := 0
	for hair in AppearanceData.HAIRSTYLES:
		var t0 := Time.get_ticks_usec()
		av.call("apply_look", _look_with({"hair": hair, "hat": "flower_crown", "hair_acc": "lantern_ribbon"}))
		slowest = maxi(slowest, Time.get_ticks_usec() - t0)
		var parts := _hair_parts(av)
		var pts := _head_points(av, "hat")
		var back := PackedVector3Array()
		for p in pts:
			if p.z < HairBuilder.CENTRE.z - 0.05:
				back.append(p)
		var f := _outside_fraction(parts, pts)
		var fb := _outside_fraction(parts, back)
		assert_true(f >= 0.8, "flower crown on %s: %.0f %% outside the hair" % [hair, f * 100.0])
		assert_true(back.size() > 50 and fb >= 0.75, "its back half shows on %s: %.0f %%" % [hair, fb * 100.0])
		var crown: Node3D = null
		for b in av.get("_unit_boxes")["hat"]:
			crown = (b as Node).find_child("FlowerCrown", true, false) as Node3D
		assert_not_null(crown)
		var flowers := 0
		var behind := 0
		for c in crown.get_children():
			if c is Node3D and not (c is MeshInstance3D):   # the five-petal flower nodes
				flowers += 1
				if (c as Node3D).position.z < 0.0:
					behind += 1
		assert_true(flowers >= 6 and behind >= 2, "%s: flowers all round (%d, %d behind)" % [hair, flowers, behind])
	# fitting the crown and the accessory to the hair is cheap (a wardrobe change rebuilds hair + hat + accessory)
	print("  slowest hairstyle change with a fitted crown + accessory: %.1f ms" % (slowest / 1000.0))
	assert_true(slowest < 250000, "hair + fitted crown rebuild stays quick (%.1f ms)" % (slowest / 1000.0))


## AV-02: under a helm or hood no hair pokes out through the dome: every static hair vertex above the brim line is
## inside the head piece, or in the hood's face opening. No hair accessory shows over head armor.
func test_head_armor_covers_the_hair() -> void:
	var av := _avatar(ItemDB.legacy_look())
	for set_id in ["padded", "copperwood", "ironwood", "moonsteel"]:
		var helm_id := String(ItemDB.armor_set(set_id)["pieces"]["head"])
		var metal := bool(ArmorBuilder.style(helm_id)["metal"])
		for hair in AppearanceData.HAIRSTYLES:
			av.call("apply_look", _look_with({"hair": hair, "hair_acc": "bat_bow"}))
			av.call("apply_armor", true, {"head": helm_id})
			var poke := 0
			var worst := Vector3.ZERO
			var pts := PackedVector3Array()
			for rec in _unit_meshes(av, "hair", "head_c", true):
				var mi := rec[0] as MeshInstance3D
				if not (mi.mesh is SphereMesh or mi.mesh is CapsuleMesh):
					continue
				var hc: Node3D = av.get("_head_c")
				var xf: Transform3D = hc.global_transform.affine_inverse() * (mi.global_transform if mi.is_inside_tree() else (rec[1] as Node3D).global_transform * mi.transform)
				for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					pts.append(xf * (v as Vector3))
			for p in pts:
				if metal:
					# helm dome: sphere 0.285 at (0, 0.14, -0.06) scaled (1.06, 0.75, 1.02); its rim band sits at y 0.1
					var q := (p - Vector3(0, 0.14, -0.06)) / (Vector3(1.06, 0.75, 1.02) * 0.285)
					if p.y > 0.115 and q.length() > 1.0:
						poke += 1
						worst = p
				else:
					# hood dome; hair in its face opening (in front of the rim plane, or tucked under the rolled rim within
					# 2.5 cm behind it) is fine
					var q2 := (p - ArmorBuilder.HOOD_C) / ArmorBuilder.HOOD_R
					var in_opening := (p - ArmorBuilder.RIM_C).dot(ArmorBuilder.RIM_N) > -0.025
					if p.y > 0.0 and q2.length() > 1.02 and not in_opening:
						poke += 1
						worst = p
			assert_eq(poke, 0, "%s on %s: no hair through the %s (e.g. %s)" % [set_id, hair, "helm" if metal else "hood", worst])
			assert_true(_head_points(av, "hair_acc").is_empty(), "%s: the bat bow is hidden under the %s" % [hair, set_id])
			av.call("apply_armor", false, {})


## AV-04 / AV-10: body armor leaves out the jacket's buttons and pocket flaps and a cape moves out over it; a
## capelet / shawl in the colour of the top it is worn over switches colour instead of disappearing into it.
func test_body_armor_and_capes_stand_out() -> void:
	var av := _avatar(ItemDB.legacy_look())
	var brass := Color("e0b85a")
	assert_true(_unit_has_color(av, "upper", brass), "control: the jacket's brass buttons")
	av.call("apply_armor", true, {"body": "padded_vest"})
	assert_false(_unit_has_color(av, "upper", brass), "no buttons over the padded vest")
	av.call("apply_armor", false, {})
	assert_true(_unit_has_color(av, "upper", brass), "buttons back without armor")
	# the cape hangs further out over mail
	av.call("apply_look", _look_with({"back": "little_cape"}))
	var z0 := _cape_root(av).position.z
	av.call("apply_armor", true, {"body": "moonsteel_mail"})
	assert_true(_cape_root(av).position.z < z0 - 0.02, "the cape moves out over the mail (%.3f -> %.3f)" % [z0, _cape_root(av).position.z])
	av.call("apply_armor", false, {})
	# chorister capelet on its own-colour top (legacy palette: teal jacket = primary = capelet channel)
	for back in ["chorister_capelet", "moth_shawl", "little_cape"]:
		for oid in ["cozy_explorer", "velvet_vampire", "moon_moth_shawl"]:
			var look := _look_for_outfit(oid)
			look["back"] = back
			av.call("apply_look", look)
			var top := _first_channel_color(String(look["upper"]), look)
			var cape_c := _cape_color(av)
			var d := absf(top.r - cape_c.r) + absf(top.g - cape_c.g) + absf(top.b - cape_c.b)
			assert_true(d > 0.12, "%s over %s stands out from the top (%s vs %s)" % [back, oid, cape_c.to_html(false), top.to_html(false)])


func _unit_has_color(av: Node3D, unit: String, c: Color) -> bool:
	for host in ["spine", "chest", "hips"]:
		for rec in _unit_meshes(av, unit, host):
			var mat := (rec[0] as MeshInstance3D).material_override
			if mat is ShaderMaterial and not bool((mat as ShaderMaterial).get_shader_parameter("use_vertex_color")):
				var a: Color = (mat as ShaderMaterial).get_shader_parameter("albedo")
				if absf(a.r - c.r) + absf(a.g - c.g) + absf(a.b - c.b) < 0.02:
					return true
	return false


func _cape_root(av: Node3D) -> Node3D:
	for b in av.get("_unit_boxes")["back"]:
		var n := (b as Node).find_child("Cape", true, false)
		if n != null:
			return n as Node3D
	return null


## Albedo of the cape's outer cloth (the first panel part under the cape root).
func _cape_color(av: Node3D) -> Color:
	var root := _cape_root(av)
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
			var sm := (c as MeshInstance3D).material_override as ShaderMaterial
			if not bool(sm.get_shader_parameter("use_vertex_color")):
				return sm.get_shader_parameter("albedo")
	# baked: the panel parts were merged; read the first vertex colour
	for c2 in root.get_children():
		if c2 is MeshInstance3D:
			var cols: Variant = (c2 as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			if cols is PackedColorArray and not (cols as PackedColorArray).is_empty():
				return (cols as PackedColorArray)[0].linear_to_srgb()
	return Color.BLACK


func _first_channel_color(part_id: String, look: Dictionary) -> Color:
	var chans: Dictionary = ItemDB.appearance_part(part_id).get("channels", {})
	for k in chans:
		return ItemDB.swatch_color(String((look["palette"] as Dictionary)[String(chans[k])]))
	return Color.BLACK


## AV-07: twin braids hang symmetrically, also while she looks to one side: the roots turn with the head but the braids
## keep hanging in mirror image from the body (the anchors cancel the head's yaw).
func test_twin_braids_stay_symmetric_when_she_looks_around() -> void:
	var av := _avatar(_look_with({"hair": "twin_braids"}), true)
	av.set("has_look_target", true)
	av.set("look_target", av.global_position + Vector3(4.0, 1.25, 1.0))
	_step(av, 90)
	var chest: Node3D = av.get("_hosts")["chest"]
	var dirs: Array = []
	var tips: Array = []
	for nm in ["BraidR", "BraidL"]:
		var braid := (av.get("_head_c") as Node).find_child(nm, true, false) as Node3D
		assert_not_null(braid, nm)
		var tie := braid.find_child("Tie", true, false) as Node3D
		var root := chest.global_transform.affine_inverse() * braid.global_position
		var tip := chest.global_transform.affine_inverse() * tie.global_position
		dirs.append((tip - root).normalized())
		tips.append(tip)
	var r: Vector3 = dirs[0]
	var l: Vector3 = dirs[1]
	var head_yaw: float = (av.get("_pose") as PackedVector3Array)[AvatarScript.J_HEAD].y
	assert_true(absf(head_yaw) > 0.3, "control: she looks to the side (%.2f)" % head_yaw)
	assert_true((tips[0] as Vector3).x < -0.1 and (tips[1] as Vector3).x > 0.1, "one braid on each side (%s / %s)" % tips)
	assert_true(r.x < -0.2 and l.x > 0.2, "both flare out (%s / %s)" % [r, l])
	assert_true(absf(r.x + l.x) < 0.08 and absf(r.y - l.y) < 0.08 and absf(r.z - l.z) < 0.08, "mirror-image braids while she looks aside: %s vs %s" % [r, l])


## AV-06: the high ponytail (no hat) falls in an arc behind the head instead of sticking out and hooking up.
func test_high_ponytail_hangs_down() -> void:
	var av := _avatar(_look_with({"hair": "high_ponytail", "hair_acc": ""}))
	_step(av, 30)
	var hc: Node3D = av.get("_head_c")
	var holder := hc.find_child("Ponytail", true, false) as Node3D
	var ys: Array = []
	var node: Node3D = holder
	for i in 5:
		node = node.find_child("P%d" % i, false, false) as Node3D
		ys.append((hc.global_transform.affine_inverse() * node.global_position).y)
	var tip := (hc.global_transform.affine_inverse() * (node.find_child("PTip", false, false) as Node3D).global_position)
	for i in range(1, ys.size()):
		assert_true(float(ys[i]) < float(ys[i - 1]) + 0.005, "segment %d never climbs (%.3f after %.3f)" % [i, ys[i], ys[i - 1]])
	assert_true(tip.y < float(ys[0]) - 0.25, "the tip hangs well below the tie (%.3f vs %.3f)" % [tip.y, ys[0]])
	assert_true(tip.z > -0.55 and tip.z < -0.3, "close behind the head, not sticking out (z %.3f)" % tip.z)


## AV-12: long hair curtains drape over a bulky back pack instead of cutting through it.
func test_long_hair_drapes_over_back_packs() -> void:
	for hair in ["long_waves", "half_up_ribbon"]:
		for pack in ["picnic_basket", "bedroll_pack", "acorn_pack"]:
			var av := _avatar(_look_with({"hair": hair, "back": pack}))
			var hc: Node3D = av.get("_head_c")
			var lim: Array = HairBuilder.BACK_PACKS[pack]
			var curtain := hc.find_child("Curtain", true, false) as Node3D
			var bad := 0
			var node: Node3D = curtain
			for i in 3:
				node = node.find_child("W%d" % i, false, false) as Node3D
				var p := hc.global_transform.affine_inverse() * (node.global_transform * Vector3(0, -0.06, 0))
				if p.y < float(lim[1]) and p.z > float(lim[0]) - 0.02:
					bad += 1
			assert_eq(bad, 0, "%s drapes behind the %s" % [hair, pack])
			av.free()
	# no pack: the Chapter Two curtain keeps its original fall
	assert_eq(HairBuilder.drape_tilt(3, []), 0.0)


## AV-11: running legs lift the neighbouring skirt panels too (no tall slits), and in a roll the panels bunch up.
func test_skirt_opens_as_one_piece_and_bunches_in_a_roll() -> void:
	for lower in ["moth_long_skirt", "velvet_dress", "harvest_skirt"]:
		var av := _avatar(_look_with({"lower": lower}), true)
		var rig: SkirtRig = av.get("_skirt")
		av.set("speed", 7.0)
		av.set("sprinting", true)
		var worst := 0.0
		for i in 90:
			_step(av, 1, Vector3(0, 0, 7.0))
			for k in rig.count:
				worst = maxf(worst, absf(rig.flare[k] - rig.flare[(k + 1) % rig.count]))
		assert_true(worst <= SkirtRig.MAX_STEP + 0.001, "%s: neighbouring panels stay together while running (%.3f)" % [lower, worst])
		av.set("speed", 0.0)
		_step(av, 30)
		var pv := (av.get("_skirt_pivots") as Array)[0] as Node3D
		assert_almost(pv.scale.y, 1.0, 0.001, lower + " full length standing")
		av.set("roll_t", 0.5)
		_step(av, 6)
		assert_true(pv.scale.y < 0.7, "%s bunches up mid-roll (%.2f)" % [lower, pv.scale.y])
		assert_almost(rig.len_scale, pv.scale.y, 0.001, "the rig checks the legs against the bunched length")
		av.set("roll_t", -1.0)
		_step(av, 20)
		assert_almost(pv.scale.y, 1.0, 0.001, lower + " full length again")
		av.free()


## AV-19: a tall hat folds down while she rolls, so it never lifts the ball more than a small hat does.
func test_witch_hat_folds_down_in_a_roll() -> void:
	var lifts := {}
	for hat in ["", "sun_hat", "witch_hat"]:
		var av := _avatar(_look_with({"hat": hat}), true)
		var roll: Node3D = av.get("_roll")
		var lift := 0.0
		for i in 21:
			av.set("roll_t", float(i) / 20.0)
			_step(av, 2)
			var env := sin(PI * float(i) / 20.0)
			lift = maxf(lift, roll.position.y - (0.5 - 0.15 * env))
		lifts[hat] = lift
		if hat == "witch_hat":
			var node: Node3D = av.get("_hat_node")
			assert_not_null(node, "the witch hat is registered for the roll squash")
			av.set("roll_t", 0.5)
			_step(av, 4)
			assert_true(node.scale.y < 0.6, "folded mid-roll (%.2f)" % node.scale.y)
			av.set("roll_t", -1.0)
			_step(av, 20)
			assert_almost(node.scale.y, 1.0, 0.01, "full height again after the roll")
		av.free()
	print("  roll pivot lift: none %.3f, sun hat %.3f, witch hat %.3f" % [lifts[""], lifts["sun_hat"], lifts["witch_hat"]])
	assert_true(float(lifts["witch_hat"]) <= float(lifts["sun_hat"]) + 0.03, "the witch hat props the roll no more than the sun hat")


## AV-08: the velvet dress lace hangs below every panel at one height all the way round.
func test_velvet_lace_is_one_even_row() -> void:
	var av := _avatar(_look_with({"lower": "velvet_dress", "upper": "ruffle_bodice"}))
	var hips: Node3D = av.get("_hosts")["hips"]
	var lows: Array = []
	var ruff := _chan("velvet_dress", "ruffles", av)
	for pv in av.get("_skirt_pivots"):
		var low := INF
		var panel_low := INF
		var stack: Array = (pv as Node).get_children()
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if not (n is MeshInstance3D):
				continue
			var mi := n as MeshInstance3D
			var xf := hips.global_transform.affine_inverse() * mi.global_transform
			var cols: Variant = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for k in verts.size():
				var c: Color = ruff
				if cols is PackedColorArray and k < (cols as PackedColorArray).size():
					c = (cols as PackedColorArray)[k].linear_to_srgb()
				elif mi.material_override is ShaderMaterial:
					c = (mi.material_override as ShaderMaterial).get_shader_parameter("albedo")
				var y := (xf * verts[k]).y
				if absf(c.r - ruff.r) + absf(c.g - ruff.g) + absf(c.b - ruff.b) < 0.05:
					low = minf(low, y)
				else:
					panel_low = minf(panel_low, y)
		assert_true(low < panel_low - 0.02, "the lace hangs below the panel (%.3f vs %.3f)" % [low, panel_low])
		lows.append(low)
	var lo: float = lows.min()
	var hi: float = lows.max()
	assert_true(hi - lo < 0.005, "one even lace line all round (%.4f spread)" % (hi - lo))


## A palette channel colour of a part in the avatar's current look.
func _chan(part: String, ch: String, av: Node3D) -> Color:
	var look: Dictionary = av.call("current_look")
	var chans: Dictionary = ItemDB.appearance_part(part).get("channels", {})
	return ItemDB.swatch_color(String((look["palette"] as Dictionary)[String(chans[ch])]))
