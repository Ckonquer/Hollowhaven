extends "res://tests/test_case.gd"
## LEGACY_LOOK reproduces the Chapter One avatar exactly (spec section 8). GOLDEN is the fingerprint of the
## Chapter One build (krystal_avatar.gd before the Chapter Two appearance refactor), recorded with fingerprint()
## below: per rig joint path (containers ignored) and material class (outline thickness, rim, noise, shadow):
## vertex count, sum of vertex positions (Body space, rest pose) and sum of linear vertex / albedo colours.
## Same parts + same colours + same proportions + same animated parents => same numbers.

const AvatarScript := preload("res://src/player/krystal_avatar.gd")

## Chapter One: 60 mesh instances, 50 visible, 82 draw calls (visible meshes + outline passes).
const GOLDEN_MESHES := 60
const GOLDEN_DRAWS := 82
const GOLDEN := {
	"Hips/Leg0/Knee0|toon|0.006|0.42|0.04|0": [87, Vector3(8.0040, 1.9140, 4.2362), Vector3(13.5656, 5.9576, 2.8801)],
	"Hips/Leg0/Knee0|toon|0.011|0.42|0.04|1": [1492, Vector3(137.2643, 298.1964, 17.2192), Vector3(223.7203, 104.6187, 118.3524)],
	"Hips/Leg0|toon|0.011|0.42|0.04|1": [630, Vector3(57.9599, 299.2506, -1.7495), Vector3(64.4122, 43.1411, 98.2341)],
	"Hips/Leg1/Knee1|toon|0.006|0.42|0.04|0": [87, Vector3(-8.0040, 1.9140, 4.2362), Vector3(13.5656, 5.9576, 2.8801)],
	"Hips/Leg1/Knee1|toon|0.011|0.42|0.04|1": [1492, Vector3(-137.2643, 298.1964, 17.2192), Vector3(223.7203, 104.6187, 118.3524)],
	"Hips/Leg1|toon|0.011|0.42|0.04|1": [630, Vector3(-57.9599, 299.2506, -1.7495), Vector3(64.4122, 43.1411, 98.2341)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3/B4/B5/Tie|toon|0.006|0.42|0.04|1": [325, Vector3(-78.5239, 253.7176, -86.4165), Vector3(288.5747, 173.3154, 24.7602)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3/B4/B5/Tie|toon|0.012|0.42|0.04|1": [310, Vector3(-77.1871, 221.7769, -89.0777), Vector3(59.5688, 13.3726, 7.2941)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3/B4/B5|toon|0.012|0.42|0.04|1": [180, Vector3(-44.1651, 148.2256, -44.6011), Vector3(35.0313, 7.8723, 4.9178)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3/B4|toon|0.012|0.42|0.04|1": [180, Vector3(-37.8203, 158.3035, -40.8957), Vector3(35.0313, 7.8723, 4.9178)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3|toon|0.012|0.42|0.04|1": [180, Vector3(-39.9758, 169.8345, -36.6599), Vector3(35.0313, 7.8723, 4.9178)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2|toon|0.012|0.42|0.04|1": [180, Vector3(-33.6310, 179.9125, -32.9545), Vector3(35.0313, 7.8723, 4.9178)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1|toon|0.012|0.42|0.04|1": [180, Vector3(-35.7865, 191.4435, -28.7187), Vector3(35.0313, 7.8723, 4.9178)],
	"Hips/Spine/Chest/Head/HeadCenter/Braid/B0|toon|0.012|0.42|0.04|1": [180, Vector3(-29.4416, 201.5215, -25.0133), Vector3(35.0313, 7.8723, 4.9178)],
	"Hips/Spine/Chest/Head/HeadCenter/Brow0|toon|0.000|0.00|0.00|0": [630, Vector3(55.3611, 826.5127, 139.6429), Vector3(70.5170, 15.8676, 10.0777)],
	"Hips/Spine/Chest/Head/HeadCenter/Brow1|toon|0.000|0.00|0.00|0": [630, Vector3(-55.3611, 826.5131, 139.6433), Vector3(70.5170, 15.8676, 10.0777)],
	"Hips/Spine/Chest/Head/HeadCenter/Eye0|glow|0.000|0.00|0.00|0": [182, Vector3(17.5806, 224.1119, 40.7697), Vector3(182.0000, 182.0000, 182.0000)],
	"Hips/Spine/Chest/Head/HeadCenter/Eye0|toon|0.000|0.00|0.00|0": [1076, Vector3(116.6520, 1341.6689, 214.8740), Vector3(55.6705, 24.6430, 33.7567)],
	"Hips/Spine/Chest/Head/HeadCenter/Eye1|glow|0.000|0.00|0.00|0": [182, Vector3(-17.5806, 224.1119, 40.7697), Vector3(182.0000, 182.0000, 182.0000)],
	"Hips/Spine/Chest/Head/HeadCenter/Eye1|toon|0.000|0.00|0.00|0": [1076, Vector3(-116.6520, 1341.6689, 214.8740), Vector3(55.6705, 24.6430, 33.7567)],
	"Hips/Spine/Chest/Head/HeadCenter/FlowerClip|toon|0.000|0.42|0.04|0": [110, Vector3(22.9606, 152.0069, 11.6726), Vector3(101.3741, 70.8927, 11.2466)],
	"Hips/Spine/Chest/Head/HeadCenter/FlowerClip|toon|0.005|0.42|0.04|0": [550, Vector3(110.2470, 759.0533, 55.1730), Vector3(550.0000, 496.0751, 409.8019)],
	"Hips/Spine/Chest/Head/HeadCenter|toon|0.000|0.00|0.00|0": [1116, Vector3(-0.0000, 1277.5549, 220.2282), Vector3(532.3676, 162.0654, 204.5205)],
	"Hips/Spine/Chest/Head/HeadCenter|toon|0.000|0.42|0.04|0": [130, Vector3(0.0000, 153.6600, 30.3671), Vector3(113.2778, 73.4125, 45.6992)],
	"Hips/Spine/Chest/Head/HeadCenter|toon|0.006|0.42|0.04|1": [576, Vector3(7.4989, 914.6870, -5.3269), Vector3(112.1001, 25.1916, 15.7368)],
	"Hips/Spine/Chest/Head/HeadCenter|toon|0.012|0.42|0.04|1": [5736, Vector3(26.3451, 6976.1567, 61.0585), Vector3(1684.2183, 695.0103, 414.2331)],
	"Hips/Spine/Chest/ScarfEnd0/Tip|toon|0.000|0.42|0.04|0": [24, Vector3(2.5923, 19.0074, -4.8748), Vector3(16.6529, 9.0303, 1.0155)],
	"Hips/Spine/Chest/ScarfEnd0/Tip|toon|0.011|0.42|0.04|1": [630, Vector3(63.2347, 519.8785, -122.9659), Vector3(559.3886, 335.9633, 47.9971)],
	"Hips/Spine/Chest/ScarfEnd0|toon|0.011|0.42|0.04|1": [630, Vector3(47.4240, 588.3923, -105.5062), Vector3(559.3886, 335.9633, 47.9971)],
	"Hips/Spine/Chest/ScarfEnd1/Tip|toon|0.000|0.42|0.04|0": [24, Vector3(1.4207, 19.4244, -4.7684), Vector3(16.6529, 9.0303, 1.0155)],
	"Hips/Spine/Chest/ScarfEnd1/Tip|toon|0.011|0.42|0.04|1": [630, Vector3(38.9841, 518.9810, -123.1952), Vector3(559.3886, 335.9633, 47.9971)],
	"Hips/Spine/Chest/ScarfEnd1|toon|0.011|0.42|0.04|1": [630, Vector3(51.9548, 588.0526, -105.5928), Vector3(559.3886, 335.9633, 47.9971)],
	"Hips/Spine/Chest/Shoulder0/Elbow0/Hand0/Lantern|glow|0.000|0.00|0.00|0": [67, Vector3(13.0650, 26.4650, 0.2625), Vector3(67.0000, 39.1333, 12.5840)],
	"Hips/Spine/Chest/Shoulder0/Elbow0/Hand0/Lantern|toon|0.008|0.42|0.04|0": [555, Vector3(108.2250, 273.4684, 0.6071), Vector3(347.1759, 217.9987, 48.5881)],
	"Hips/Spine/Chest/Shoulder0/Elbow0/Hand0|toon|0.011|0.42|0.04|1": [900, Vector3(155.2498, 503.0990, 16.1417), Vector3(783.5313, 508.2328, 314.1176)],
	"Hips/Spine/Chest/Shoulder0/Elbow0|toon|0.011|0.42|0.04|1": [955, Vector3(186.2254, 631.3261, -1.9012), Vector3(37.2939, 319.8643, 289.9806)],
	"Hips/Spine/Chest/Shoulder0|toon|0.011|0.42|0.04|1": [1080, Vector3(210.6004, 969.2984, -0.5688), Vector3(50.8231, 415.0549, 376.9430)],
	"Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Axe|toon|0.011|0.42|0.04|1": [544, Vector3(-106.1042, 152.6163, 147.9379), Vector3(331.8406, 288.7426, 122.2032)],
	"Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Pickaxe|toon|0.011|0.42|0.04|1": [922, Vector3(-179.7902, 246.7753, 284.8237), Vector3(512.6854, 456.2472, 267.4738)],
	"Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Sword|toon|0.000|0.00|0.00|0": [24, Vector3(-4.6800, 6.6469, 2.6564), Vector3(22.3227, 14.9751, 7.9788)],
	"Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Sword|toon|0.011|0.42|0.04|1": [521, Vector3(-101.5950, 307.4286, -10.0978), Vector3(360.3635, 229.9083, 49.8037)],
	"Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Sword|toon|0.011|0.80|0.02|1": [44, Vector3(-8.5800, 6.8619, 7.0684), Vector3(30.3686, 11.2157, 3.2784)],
	"Hips/Spine/Chest/Shoulder1/Elbow1/Hand1|toon|0.011|0.42|0.04|0": [180, Vector3(-33.3000, 96.3000, 11.0434), Vector3(124.8968, 10.4050, 25.9432)],
	"Hips/Spine/Chest/Shoulder1/Elbow1/Hand1|toon|0.011|0.42|0.04|1": [900, Vector3(-155.2498, 503.0990, 16.1417), Vector3(783.5313, 508.2328, 314.1176)],
	"Hips/Spine/Chest/Shoulder1/Elbow1|toon|0.011|0.42|0.04|1": [955, Vector3(-186.2254, 631.3261, -1.9012), Vector3(37.2939, 319.8643, 289.9806)],
	"Hips/Spine/Chest/Shoulder1|toon|0.011|0.42|0.04|1": [1080, Vector3(-210.6004, 969.2984, -0.5688), Vector3(50.8231, 415.0549, 376.9430)],
	"Hips/Spine/Chest|toon|0.011|0.42|0.04|1": [1100, Vector3(33.7500, 1122.3422, -63.1295), Vector3(974.9073, 582.3590, 81.9602)],
	"Hips/Spine/Patch|toon|0.000|0.00|0.00|0": [850, Vector3(0.1100, 739.2990, -128.6128), Vector3(90.5490, 243.2148, 51.2153)],
	"Hips/Spine/Patch|toon|0.005|0.42|0.04|0": [107, Vector3(0.0000, 92.8326, -15.2302), Vector3(95.9009, 84.6689, 61.8010)],
	"Hips/Spine/Satchel/BeltLantern|toon|0.008|0.42|0.04|0": [622, Vector3(146.0281, 385.4183, -101.8286), Vector3(401.0391, 264.2422, 77.4901)],
	"Hips/Spine/Satchel|toon|0.000|0.00|0.00|0": [130, Vector3(34.3348, 80.6000, -12.9866), Vector3(96.9026, 62.3117, 13.2914)],
	"Hips/Spine/Satchel|toon|0.011|0.42|0.04|1": [1080, Vector3(223.2857, 683.0482, -80.2957), Vector3(340.5921, 151.0577, 61.0585)],
	"Hips/Spine|toon|0.000|0.00|0.00|0": [520, Vector3(-0.0000, 423.7992, 73.8748), Vector3(387.4493, 248.7825, 53.0194)],
	"Hips/Spine|toon|0.000|0.42|0.04|0": [920, Vector3(0.0000, 622.3917, 144.8195), Vector3(39.0585, 231.0563, 205.6450)],
	"Hips/Spine|toon|0.011|0.42|0.04|1": [1042, Vector3(9.7500, 838.7801, -4.2155), Vector3(173.9366, 338.0061, 274.4646)],
	"Hips|toon|0.011|0.42|0.04|1": [450, Vector3(-0.0000, 283.4999, 1.5389), Vector3(46.0087, 30.8151, 70.1668)],
}

const RIG_NAMES := ["Hips", "Leg0", "Leg1", "Knee0", "Knee1", "Spine", "Chest", "Shoulder0", "Shoulder1",
	"Elbow0", "Elbow1", "Hand0", "Hand1", "Head", "HeadCenter", "Eye0", "Eye1", "Brow0", "Brow1", "ScarfEnd0", "ScarfEnd1", "Tip",
	"Braid", "B0", "B1", "B2", "B3", "B4", "B5", "Tie", "Lantern", "BeltLantern", "Satchel", "Patch", "FlowerClip", "Axe", "Pickaxe",
	"Sword", "ToolAnchor"]

var _avs: Array = []


func after_each() -> void:
	for a in _avs:
		if is_instance_valid(a):
			(a as Node).free()
	_avs.clear()


func _avatar(look: Dictionary, driven: bool = false) -> Node3D:
	var av: Node3D = AvatarScript.new()
	av.driven = driven
	if not look.is_empty():
		av.call("apply_look", look)
	add_child(av)
	_avs.append(av)
	return av


static func _rig_path(n: Node, root: Node) -> String:
	var names: Array = []
	var p: Node = n.get_parent()
	while p != null and p != root:
		if RIG_NAMES.has(String(p.name)):
			names.push_front(String(p.name))
		p = p.get_parent()
	return "/".join(names)


## Rest-pose fingerprint of an avatar (call before its first _process).
static func fingerprint(av: Node3D) -> Dictionary:
	var body: Node3D = av.get("_body_root")
	var out := {}
	var meshes := 0
	var stack: Array = [body]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		meshes += 1
		var xf: Transform3D = body.global_transform.affine_inverse() * mi.global_transform
		var mat: Material = mi.material_override
		var kind := "other"
		var thick := 0.0
		var rim := 0.0
		var noise := 0.0
		var vcol := false
		var albedo := Color.WHITE
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			kind = "toon"
			rim = float(sm.get_shader_parameter("rim_strength"))
			noise = float(sm.get_shader_parameter("noise_amount"))
			vcol = bool(sm.get_shader_parameter("use_vertex_color"))
			albedo = sm.get_shader_parameter("albedo")
			if sm.next_pass is ShaderMaterial:
				thick = float((sm.next_pass as ShaderMaterial).get_shader_parameter("thickness"))
		elif mat is StandardMaterial3D:
			kind = "glow"
			albedo = (mat as StandardMaterial3D).albedo_color
		var key := "%s|%s|%.3f|%.2f|%.2f|%d" % [_rig_path(mi, body), kind, thick, rim, noise, mi.cast_shadow]
		var rec: Array = out.get(key, [0, Vector3.ZERO, Vector3.ZERO])
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols: Variant = arr[Mesh.ARRAY_COLOR]
			for k in v.size():
				var c: Color = albedo.srgb_to_linear()
				if vcol and cols is PackedColorArray and k < (cols as PackedColorArray).size():
					c = (cols as PackedColorArray)[k]
				rec[0] = int(rec[0]) + 1
				rec[1] = (rec[1] as Vector3) + xf * v[k]
				rec[2] = (rec[2] as Vector3) + Vector3(c.r, c.g, c.b)
		out[key] = rec
	return {"groups": out, "meshes": meshes}


## Differences between a fingerprint and GOLDEN ([] = identical within float noise).
static func golden_diff(fp: Dictionary) -> Array:
	var out: Array = []
	var groups: Dictionary = fp["groups"]
	for key in GOLDEN:
		if not groups.has(key):
			out.append("missing group " + key)
			continue
		var g: Array = GOLDEN[key]
		var r: Array = groups[key]
		if int(r[0]) != int(g[0]):
			out.append("%s vertex count %d != %d" % [key, r[0], g[0]])
		var dp := ((r[1] as Vector3) - (g[1] as Vector3)).length()
		if dp >= 0.02:
			out.append("%s geometry moved (%.4f)" % [key, dp])
		var dc := ((r[2] as Vector3) - (g[2] as Vector3)).length()
		if dc >= 0.01 * maxf(1.0, float(g[0]) / 50.0):
			out.append("%s colours differ (%.4f)" % [key, dc])
	for key2 in groups:
		if not GOLDEN.has(key2):
			out.append("unexpected group " + key2)
	return out


func _assert_matches_golden(fp: Dictionary, what: String) -> void:
	for d in golden_diff(fp):
		fail("%s: %s" % [what, d])


func test_legacy_look_equals_the_chapter_one_build() -> void:
	var av := _avatar(ItemDB.legacy_look())
	var fp := fingerprint(av)
	_assert_matches_golden(fp, "legacy look")
	assert_eq(int(fp["meshes"]), GOLDEN_MESHES, "same mesh instance count")
	assert_eq(int(av.call("draw_call_estimate")), GOLDEN_DRAWS, "same draw calls")
	# the player's avatar on a fresh / migrated save shows the same
	fresh_state()
	var pl := _avatar({}, true)
	_assert_matches_golden(fingerprint(pl), "player avatar (GameState default)")


func test_legacy_look_after_a_round_trip_rebuild() -> void:
	var av := _avatar(ItemDB.legacy_look())
	var other := ItemDB.outfit("velvet_vampire")
	var look := ItemDB.legacy_look()
	for slot in other["parts"]:
		look[slot] = other["parts"][slot]
	look["palette"] = other["palette"]
	look["hair"] = "braided_crown"
	look["hair_color"] = "raven"
	look["skin"] = "skin_5"
	look["eyes"] = "eye_4"
	av.call("apply_look", look)
	av.call("apply_armor", true, ItemDB.armor_set("ironwood")["pieces"])
	av.call("apply_armor", false, {})
	var back: Array = av.call("apply_look", ItemDB.legacy_look())
	assert_eq(back.size(), 9, "every unit but the (hidden) armor rebuilt: %s" % str(back))
	_assert_matches_golden(fingerprint(av), "legacy after rebuilds")
	assert_eq(int(av.call("draw_call_estimate")), GOLDEN_DRAWS, "same draw calls after rebuilds")


func test_legacy_rig_hull_and_springs_unchanged() -> void:
	var av := _avatar(ItemDB.legacy_look())
	assert_eq((av.get("_head_hull") as Array).size(), 14, "no extra hull points: the Chapter One roll")
	assert_eq(av.get("_skirt"), null, "trousers: no skirt panels")
	var chains: Array = av.get("_chains")
	var kinds: Array = []
	for ch in chains:
		kinds.append(String(ch["kind"]))
	assert_eq(kinds, ["braid", "scarf", "scarf"], "one braid, two scarf ends")
	assert_eq((av.get("_braid") as Array).size(), 6)
	assert_eq((av.get("_scarf_ends") as Array).size(), 2)
	var belt: Node3D = av.get("_lantern_belt")
	assert_true(belt != null and String(belt.get_parent().name) == "Satchel", "belt lantern on the satchel")
	assert_true((av.get("_patch") as Node3D).visible, "explorer patch visible")


## Negative control: the fingerprint really sees small changes (one colour, one part, one proportion).
func test_fingerprint_detects_small_differences() -> void:
	var look := ItemDB.legacy_look()
	look["eyes"] = "eye_2"
	var a := _avatar(look)
	assert_false(golden_diff(fingerprint(a)).is_empty(), "another iris colour is detected")
	var look2 := ItemDB.legacy_look()
	look2["hair_acc"] = "star_pins"
	var b := _avatar(look2)
	assert_false(golden_diff(fingerprint(b)).is_empty(), "another hair accessory is detected")
	var c := _avatar(ItemDB.legacy_look())
	var hc: Node3D = c.get("_head_c")
	hc.position.y += 0.01
	assert_false(golden_diff(fingerprint(c)).is_empty(), "a 1 cm head shift is detected")


# --- Animation ---------------------------------------------------------------------------------------------
## GOLDEN_MOTION: per rig node (path of rig names from the avatar root; "#light" = the lantern light), the sums of
## position, rotation, (visible ? +1 : -1) * scale and rotation * sin(0.7 frame) (timing of the springs) over the
## scripted 374 frames of _motion_script() (idle, walk, turn, sprint, roll, jump, lantern + sword swing, wave, sleep).
## Recorded from the Chapter One source (git 8de11a1, before the appearance refactor) by the independent review;
## the new avatar matched it to 1e-5.
## Pins the refactored scarf / braid spring loops, the roll hull and the lantern for LEGACY_LOOK.
const MOTION_NAMES := ["Body", "RollPivot", "Rig", "Hips", "Leg0", "Leg1", "Knee0", "Knee1", "Spine", "Chest", "Shoulder0",
	"Shoulder1", "Elbow0", "Elbow1", "Hand0", "Hand1", "Head", "HeadCenter", "Eye0", "Eye1", "Brow0", "Brow1", "ScarfEnd0",
	"ScarfEnd1", "Tip", "Braid", "B0", "B1", "B2", "B3", "B4", "B5", "Tie", "Lantern", "BeltLantern", "Satchel", "Patch",
	"FlowerClip", "Axe", "Pickaxe", "Sword", "ToolAnchor"]
const GOLDEN_MOTION := {
	"#light": [Vector3(43.5185, 130.0276, 45.9581), Vector3(0.0000, 0.0000, 0.0000), Vector3(-190.0000, -190.0000, -190.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body": [Vector3(0.0000, 0.0000, 0.0000), Vector3(0.0000, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body/RollPivot": [Vector3(0.0000, 186.3127, 0.0000), Vector3(90.5092, 0.0000, 0.0000), Vector3(374.0000, 366.1021, 374.0000), Vector3(-7.2750, 0.0000, 0.0000)],
	"Body/RollPivot/Rig": [Vector3(0.0000, -206.2657, -3.7200), Vector3(0.0000, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips": [Vector3(0.0000, 224.4008, 0.0000), Vector3(0.0000, 7.5168, -2.6784), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, -0.1136, -0.0263)],
	"Body/RollPivot/Rig/Hips/Leg0": [Vector3(34.4078, -1.8700, 0.0000), Vector3(-97.4889, -5.5800, 6.4077), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.2925, -0.0284, -0.0056)],
	"Body/RollPivot/Rig/Hips/Leg0/Knee0": [Vector3(0.0000, -87.8902, 0.0000), Vector3(211.2020, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(-1.3928, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Leg1": [Vector3(-34.4078, -1.8700, 0.0000), Vector3(-108.1693, 5.5800, -6.4077), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.6246, 0.0284, 0.0056)],
	"Body/RollPivot/Rig/Hips/Leg1/Knee1": [Vector3(0.0000, -87.8902, 0.0000), Vector3(206.3407, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(-1.3152, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine": [Vector3(0.0000, 7.4800, 0.0000), Vector3(49.5667, -4.5106, 2.8650), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0150, 1.0356, -0.0903)],
	"Body/RollPivot/Rig/Hips/Spine/Chest": [Vector3(0.0000, 134.6402, 0.0000), Vector3(0.0000, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head": [Vector3(0.0000, 14.9600, 0.0000), Vector3(13.4935, -0.6912, 9.6729), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0470, 0.2453, 0.3290)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter": [Vector3(0.0000, 86.0202, 0.0000), Vector3(0.0000, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid": [Vector3(-63.5797, -37.4000, -48.6200), Vector3(130.8997, 0.0000, -67.3201), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.5673, 0.0000, -0.2917)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid/B0": [Vector3(0.0000, 0.0000, 0.0000), Vector3(16.7435, 0.0000, 12.5756), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0417, 0.0000, -0.0135)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1": [Vector3(0.0000, -24.3100, 0.0000), Vector3(4.6882, 0.0000, 3.1268), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0117, 0.0000, -0.0197)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2": [Vector3(0.0000, -24.3100, 0.0000), Vector3(5.6928, 0.0000, 3.9654), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0142, 0.0000, -0.0139)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3": [Vector3(0.0000, -24.3100, 0.0000), Vector3(6.6974, 0.0000, 5.0442), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0167, 0.0000, 0.0004)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3/B4": [Vector3(0.0000, -24.3100, 0.0000), Vector3(7.7020, 0.0000, 6.1756), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0192, 0.0000, 0.0144)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3/B4/B5": [Vector3(0.0000, -24.3100, 0.0000), Vector3(8.7066, 0.0000, 7.1402), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0217, 0.0000, 0.0197)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Braid/B0/B1/B2/B3/B4/B5/Tie": [Vector3(0.0000, -28.0501, 0.0000), Vector3(0.0000, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Brow0": [Vector3(32.9119, 23.0609, 83.0280), Vector3(-74.8000, 130.5511, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.3241, 0.5657, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Brow1": [Vector3(-32.9119, 23.0609, 83.0280), Vector3(-74.8000, -130.5511, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.3241, -0.5657, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Eye0": [Vector3(32.5380, -8.2280, 77.0442), Vector3(0.0000, 137.0777, 0.0000), Vector3(374.0000, 323.2751, 374.0000), Vector3(0.0000, 0.5940, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/Eye1": [Vector3(-32.5380, -8.2280, 77.0442), Vector3(0.0000, -137.0777, 0.0000), Vector3(374.0000, 323.2751, 374.0000), Vector3(0.0000, -0.5940, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Head/HeadCenter/FlowerClip": [Vector3(74.8000, 48.6200, 37.4000), Vector3(-65.2755, 359.0140, 65.2755), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.2829, 1.5558, 0.2829)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/ScarfEnd0": [Vector3(22.4400, 7.4800, -56.1002), Vector3(183.2487, 0.0000, 103.1334), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.3703, 0.0000, 0.3494)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/ScarfEnd0/Tip": [Vector3(0.0000, -48.6200, 0.0000), Vector3(58.0137, 0.0000, 11.9162), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0129, 0.0000, -0.0041)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/ScarfEnd1": [Vector3(35.5299, 7.4800, -56.1002), Vector3(183.4201, 0.0000, -46.4666), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.3676, 0.0000, -0.2989)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/ScarfEnd1/Tip": [Vector3(0.0000, -48.6200, 0.0000), Vector3(58.2888, 0.0000, 11.9162), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.0074, 0.0000, -0.0041)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder0": [Vector3(72.9299, -7.4800, 0.0000), Vector3(-119.2514, -8.2739, 79.3617), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.5731, -0.2955, 0.5279)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder0/Elbow0": [Vector3(0.0000, -72.9299, 0.0000), Vector3(-316.1486, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.2329, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder0/Elbow0/Hand0": [Vector3(0.0000, -74.8000, 0.0000), Vector3(0.0000, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder0/Elbow0/Hand0/Lantern": [Vector3(0.0013, -14.9592, -0.0011), Vector3(184.8734, -93.4439, -121.5739), Vector3(-190.0000, -190.0000, -190.0000), Vector3(-0.6860, -2.5026, -2.2702)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder1": [Vector3(-72.9299, -7.4800, 0.0000), Vector3(-79.4081, 21.8613, -213.7256), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.1643, 2.2457, 4.1492)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder1/Elbow1": [Vector3(0.0000, -72.9299, 0.0000), Vector3(-258.8447, 0.0000, 0.9821), Vector3(374.0000, 374.0000, 374.0000), Vector3(1.2641, 0.0000, 0.4245)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder1/Elbow1/Hand1": [Vector3(0.0000, -74.8000, 0.0000), Vector3(0.0000, 0.0000, 0.4911), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.2123)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor": [Vector3(0.0000, -7.4800, 0.0000), Vector3(0.0000, 0.0000, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Axe": [Vector3(0.0000, 0.0000, 0.0000), Vector3(860.1970, 0.0000, 0.0000), Vector3(-374.0000, -374.0000, -374.0000), Vector3(3.7277, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Pickaxe": [Vector3(0.0000, 0.0000, 0.0000), Vector3(860.1970, 0.0000, 0.0000), Vector3(-374.0000, -374.0000, -374.0000), Vector3(3.7277, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Chest/Shoulder1/Elbow1/Hand1/ToolAnchor/Sword": [Vector3(0.0000, 0.0000, 0.0000), Vector3(1028.5000, 0.0000, 0.0000), Vector3(-268.0000, -268.0000, -268.0000), Vector3(4.4570, 0.0000, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Patch": [Vector3(0.0000, 93.5000, -53.1078), Vector3(-52.2201, 1174.9580, 0.0000), Vector3(374.0000, 374.0000, 374.0000), Vector3(-0.2263, 5.0917, 0.0000)],
	"Body/RollPivot/Rig/Hips/Spine/Satchel": [Vector3(74.8000, 0.0000, -26.1799), Vector3(0.0000, 750.6689, -32.6378), Vector3(374.0000, 374.0000, 374.0000), Vector3(0.0000, 3.2530, -0.1414)],
	"Body/RollPivot/Rig/Hips/Spine/Satchel/BeltLantern": [Vector3(26.1799, 14.9600, 26.1799), Vector3(0.0000, 0.0000, 0.0000), Vector3(104.0001, 104.0001, 104.0001), Vector3(0.0000, 0.0000, 0.0000)],
}


static func _motion_path(n: Node, root: Node) -> String:
	var names: Array = []
	var p: Node = n
	while p != null and p != root:
		if MOTION_NAMES.has(String(p.name)):
			names.push_front(String(p.name))
		p = p.get_parent()
	return "/".join(names)


static func _motion_script() -> Array:
	var fr: Array = []
	for i in 30:
		fr.append({})
	fr.append({"speed": 4.2, "lantern_owned": true})
	for i in 60:
		fr.append({"move": Vector3(0, 0, 4.2), "turn_rate": 0.5 if i > 30 else 0.0})
	fr.append({"speed": 7.0, "sprinting": true})
	for i in 60:
		fr.append({"move": Vector3(1, 0, 7.0), "yaw": 0.01})
	for i in 28:
		fr.append({"roll_t": float(i) / 27.0, "move": Vector3(0, 0, 6.0)})
	fr.append({"roll_t": -1.0, "grounded": false})
	for i in 40:
		var vy := 6.0 - 18.0 * float(i) / 60.0
		fr.append({"vertical_speed": vy, "move": Vector3(0, vy, 5.0)})
	fr.append({"grounded": true, "vertical_speed": 0.0, "speed": 0.0, "sprinting": false, "lantern_on": true, "tool": "sword"})
	for i in 30:
		fr.append({"swing_kind": "sword", "swing_t": float(i) / 29.0})
	fr.append({"swing_t": -1.0, "action": "wave"})
	for i in 60:
		fr.append({})
	fr.append({"action": "sleep", "lantern_on": false})
	for i in 60:
		fr.append({})
	return fr


## Drives `av` through the script (60 fps) and returns the per-node sums (see GOLDEN_MOTION).
static func motion_sums(av: Node3D) -> Dictionary:
	var nodes := {}
	var stack: Array = [av]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node3D and not (n is MeshInstance3D) and (MOTION_NAMES.has(String(n.name)) or n is OmniLight3D):
			nodes[_motion_path(n, av) + ("#light" if n is OmniLight3D else "")] = n
	var out := {}
	for k in nodes:
		out[k] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var fi := 0
	for f in _motion_script():
		var fd: Dictionary = f
		fi += 1
		for k in fd:
			match String(k):
				"move":
					av.global_position += (fd["move"] as Vector3) / 60.0
				"yaw":
					av.rotation.y += float(fd["yaw"])
				"action":
					av.call("play_action", fd["action"])
				"tool":
					av.call("show_tool", fd["tool"], 0.9)
				_:
					av.set(k, fd[k])
		av.call("_process", 1.0 / 60.0)
		for k in nodes:
			var n := nodes[k] as Node3D
			var r: Array = out[k]
			r[0] = (r[0] as Vector3) + n.position
			r[1] = (r[1] as Vector3) + n.rotation
			r[2] = (r[2] as Vector3) + n.scale * (1.0 if n.visible else -1.0)
			r[3] = (r[3] as Vector3) + n.rotation * sin(0.7 * float(fi))
	return out


func test_legacy_animation_equals_the_chapter_one_motion() -> void:
	seed(4242)   # blink / idle look-around timers
	var av: Node3D = AvatarScript.new()
	av.driven = true
	av.follow_game_state = false
	add_child(av)
	_avs.append(av)
	var sums := motion_sums(av)
	for key in GOLDEN_MOTION:
		if not sums.has(key):
			fail("missing rig node " + key)
			continue
		for i in 4:
			var got: Vector3 = (sums[key] as Array)[i]
			var want: Vector3 = (GOLDEN_MOTION[key] as Array)[i]
			var d := (got - want).length()
			if d > 0.0005:   # same-machine float noise ~1e-5; a 3 % scarf stiffness change shows 1e-3
				fail("%s %s differs from Chapter One by %.4f" % [key, ["position", "rotation", "scale", "rotation timing"][i], d])
	for key2 in sums:
		if not GOLDEN_MOTION.has(key2):
			fail("unexpected rig node " + key2)
