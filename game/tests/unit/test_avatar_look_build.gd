extends "res://tests/test_case.gd"
## Krystal's appearance build (src/player/krystal_avatar.gd + src/player/avatar/*): every hairstyle with several
## outfits, every catalogue part with its own geometry, colours per data, rebuild-only-what-changed, unknown-id
## fallback, independent avatars (no shared-material / shared-mesh bleed), show-armor pieces and cosmetics that
## never add collision.

const AvatarScript := preload("res://src/player/krystal_avatar.gd")
const AppearanceData := preload("res://data/appearance.gd")

var _avs: Array = []


func after_each() -> void:
	for a in _avs:
		if is_instance_valid(a):
			(a as Node).free()
	_avs.clear()


func _avatar(look: Dictionary = {}, driven: bool = false) -> Node3D:
	var av: Node3D = AvatarScript.new()
	av.driven = driven
	if not look.is_empty():
		av.call("apply_look", look)
	add_child(av)
	_avs.append(av)
	return av


func _look_for_outfit(oid: String) -> Dictionary:
	var o := ItemDB.outfit(oid)
	var look := ItemDB.legacy_look()
	for slot in o["parts"]:
		look[slot] = o["parts"][slot]
	look["palette"] = (o["palette"] as Dictionary).duplicate()
	look["hair"] = o["hair"]
	look["hair_color"] = o["hair_color"]
	look["outfit"] = oid
	return look


## Every mesh under `n` (recursive), including parts kept aside by the joint bake.
static func _meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_meshes(c, out)


## Vertex count + bounds (in `ref` space) of every mesh of a unit, including the source parts merged into its
## joints' bakes (they are kept aside, see krystal_avatar.gd _detached).
static func _unit_geometry(av: Node3D, unit: String, ref: Node3D) -> Dictionary:
	var verts := 0
	var box := AABB()
	var first := true
	var cols: Array = []
	var boxes: Array = av.get("_unit_boxes").get(unit, [])
	var detached: Dictionary = av.get("_detached")
	for b in boxes:
		var list: Array = []
		_meshes(b, list)
		list.append_array(detached.get((b as Node).get_instance_id(), []))
		for m in list:
			var mi := m as MeshInstance3D
			var xf := _to(mi, b as Node3D, ref)
			var mat := mi.material_override
			var vcol := mat is ShaderMaterial and bool((mat as ShaderMaterial).get_shader_parameter("use_vertex_color"))
			if mat is ShaderMaterial and not vcol:
				cols.append((mat as ShaderMaterial).get_shader_parameter("albedo"))
			for s in mi.mesh.get_surface_count():
				var arrs := mi.mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
				if vcol and arrs[Mesh.ARRAY_COLOR] is PackedColorArray:
					var pc: PackedColorArray = arrs[Mesh.ARRAY_COLOR]
					for k2 in range(0, pc.size(), 5):
						cols.append(pc[k2].linear_to_srgb())
				verts += v.size()
				for k in range(0, v.size(), 4):
					var p := xf * v[k]
					if first:
						box = AABB(p, Vector3.ZERO)
						first = false
					else:
						box = box.expand(p)
	return {"verts": verts, "aabb": box, "colors": cols}


## True when `cols` holds a colour within `tol` of `c` per channel (baked colours are 8-bit linear).
static func _near(cols: Array, c: Color, tol: float = 0.02) -> bool:
	for d in cols:
		var e := d as Color
		if absf(e.r - c.r) <= tol and absf(e.g - c.g) <= tol and absf(e.b - c.b) <= tol:
			return true
	return false


## Transform of a mesh (maybe detached from its container) into `ref` space.
static func _to(mi: MeshInstance3D, box: Node3D, ref: Node3D) -> Transform3D:
	if mi.is_inside_tree():
		return ref.global_transform.affine_inverse() * mi.global_transform
	return ref.global_transform.affine_inverse() * box.global_transform * mi.transform


func test_every_hairstyle_builds_with_several_outfits() -> void:
	var av := _avatar()
	var worst_draws := 0
	var worst := ""
	for hair in AppearanceData.HAIRSTYLES:
		for oid in ["cozy_explorer", "strawberry_picnic", "moonflower_dress", "ribbon_witch", "velvet_vampire", "lanternwake_dress"]:
			var look := _look_for_outfit(oid)
			look["hair"] = hair
			av.call("apply_look", look)
			assert_eq(av.call("missing_ids"), [], "%s + %s: every id known" % [hair, oid])
			var cur: Dictionary = av.call("current_look")
			assert_eq(cur["hair"], hair)
			assert_eq(cur["lower"], look["lower"])
			var draws: int = av.call("draw_call_estimate")
			if draws > worst_draws:
				worst_draws = draws
				worst = "%s + %s" % [hair, oid]
			var hair_geo := _unit_geometry(av, "hair", av.get("_head_c"))
			assert_true(int(hair_geo["verts"]) > 2000, "%s builds its hair (%d verts)" % [hair, hair_geo["verts"]])
			for m in _all_meshes(av):
				assert_eq((m as MeshInstance3D).layers, AvatarScript.AVATAR_LAYER, "%s + %s: avatar layer only" % [hair, oid])
	print("  worst draw-call estimate %d (%s)" % [worst_draws, worst])
	assert_true(worst_draws <= 150, "draw calls stay bounded (%d for %s)" % [worst_draws, worst])
	# every outfit (fresh avatars too, not only rebuilds)
	for oid2 in AppearanceData.OUTFITS:
		var fresh := _avatar(_look_for_outfit(oid2))
		assert_eq(String(fresh.call("current_look")["outfit"]), oid2)
		assert_true(int(fresh.call("draw_call_estimate")) > 40, oid2 + " is drawn")
		fresh.free()
	_avs = _avs.filter(func(a: Variant) -> bool: return is_instance_valid(a))


func _all_meshes(av: Node3D) -> Array:
	var out: Array = []
	_meshes(av.get("_body_root"), out)
	return out


func test_every_part_has_its_own_geometry() -> void:
	var av := _avatar()
	var hosts: Dictionary = av.get("_hosts")
	for slot in AppearanceData.SLOTS:
		var seen := {}
		for pid in ItemDB.parts_for_slot(slot):
			var look := ItemDB.legacy_look()
			look[slot] = pid
			if slot == "hat" and pid != "":
				look["hair_acc"] = ""
			av.call("apply_look", look)
			assert_eq(av.call("missing_ids"), [], pid)
			var unit := String(slot)
			var geo := _unit_geometry(av, unit, hosts["hips"])
			assert_true(int(geo["verts"]) > 0, "%s (%s) builds meshes" % [pid, slot])
			var aabb: AABB = geo["aabb"]
			var sig := "%d|%.3f|%.3f|%.3f" % [geo["verts"], aabb.size.x, aabb.size.y, aabb.size.z]
			assert_false(seen.has(sig), "%s has its own mesh (same as %s)" % [pid, seen.get(sig, "")])
			seen[sig] = pid
		assert_true(seen.size() >= 2, slot)
	# hairstyles: eight different silhouettes, with at least the spring chains the catalogue lists
	var shapes := {}
	for hair in AppearanceData.HAIRSTYLES:
		av.call("apply_look", _look_with("hair", hair))
		var geo := _unit_geometry(av, "hair", av.get("_head_c"))
		var aabb: AABB = geo["aabb"]
		var sig := "%d|%.3f|%.3f|%.3f" % [geo["verts"], aabb.size.x, aabb.size.y, aabb.size.z]
		assert_false(shapes.has(sig), "%s has its own silhouette (same as %s)" % [hair, shapes.get(sig, "")])
		shapes[sig] = hair
		var springs: Array = AppearanceData.HAIRSTYLES[hair]["springs"]
		var hair_chains := 0
		for ch in av.get("_chains"):
			if String(ch["kind"]) == "braid":
				hair_chains += 1
		assert_true(hair_chains >= springs.size(), "%s animates its springs %s" % [hair, str(springs)])
	assert_eq(shapes.size(), 8)


func _look_with(slot: String, id: String) -> Dictionary:
	var look := ItemDB.legacy_look()
	look[slot] = id
	return look


func test_colours_follow_the_catalogue() -> void:
	var av := _avatar()
	var head_c: Node3D = av.get("_head_c")
	for hc in AppearanceData.HAIR_COLORS:
		var look := ItemDB.legacy_look()
		look["hair_color"] = hc
		av.call("apply_look", look)
		var cols: Array = _unit_geometry(av, "hair", head_c)["colors"]
		assert_true(_near(cols, (AppearanceData.HAIR_COLORS[hc]["base"] as Color)), hc + " hair colour")
		assert_true(_near(cols, (AppearanceData.HAIR_COLORS[hc]["dark"] as Color)), hc + " brows")
	for sk in AppearanceData.SKIN_TONES:
		var look2 := ItemDB.legacy_look()
		look2["skin"] = sk
		av.call("apply_look", look2)
		var cols2: Array = _unit_geometry(av, "skin", head_c)["colors"]
		assert_true(_near(cols2, (AppearanceData.SKIN_TONES[sk]["base"] as Color)), sk)
		assert_true(_near(cols2, (AppearanceData.SKIN_TONES[sk]["blush"] as Color)), sk + " blush")
	for ey in AppearanceData.EYE_COLORS:
		var look3 := ItemDB.legacy_look()
		look3["eyes"] = ey
		av.call("apply_look", look3)
		var cols3: Array = _unit_geometry(av, "eyes", head_c)["colors"]
		assert_true(_near(cols3, (AppearanceData.EYE_COLORS[ey]["iris"] as Color)), ey)
	# palette channels recolour the garments per their data (jacket = primary, scarf = secondary, trousers = accent)
	var look4 := ItemDB.legacy_look()
	look4["palette"] = {"primary": "rose", "secondary": "mint", "accent": "sky"}
	av.call("apply_look", look4)
	var up: Array = _unit_geometry(av, "upper", head_c)["colors"]
	assert_true(_near(up, ItemDB.swatch_color("rose")), "jacket = primary")
	assert_true(_near(up, ItemDB.swatch_color("mint")), "scarf = secondary")
	assert_false(_near(up, ItemDB.swatch_color("teal"), 0.01), "no legacy teal left")
	var low: Array = _unit_geometry(av, "lower", head_c)["colors"]
	assert_true(_near(low, ItemDB.swatch_color("sky")), "trousers = accent")
	# a dress: primary cloth, secondary hem
	var look5 := _look_for_outfit("moonflower_dress")
	look5["palette"] = {"primary": "berry", "secondary": "butter", "accent": "slate"}
	av.call("apply_look", look5)
	var dress: Array = _unit_geometry(av, "lower", head_c)["colors"]
	assert_true(_near(dress, ItemDB.swatch_color("berry")), "dress = primary")
	assert_true(_near(dress, ItemDB.swatch_color("butter")), "hem = secondary")


func test_apply_look_is_idempotent_and_rebuilds_only_changed_units() -> void:
	var av := _avatar(ItemDB.legacy_look())
	var boxes: Dictionary = av.get("_unit_boxes")
	var upper_box: Node = (boxes["upper"] as Array)[0]
	assert_eq(av.call("apply_look", ItemDB.legacy_look()), [], "same look: nothing rebuilt")
	assert_eq(av.call("apply_look", ItemDB.legacy_look()), [], "still nothing")
	var look := ItemDB.legacy_look()
	look["shoes"] = "wellies"
	assert_eq(av.call("apply_look", look), ["shoes"], "only the shoes")
	assert_true(is_instance_valid(upper_box) and upper_box == (boxes["upper"] as Array)[0], "the jacket container is untouched")
	look["hair_color"] = "mint"
	assert_eq(av.call("apply_look", look), ["hair"], "hair colour -> hair (+ brows) only")
	look["eyes"] = "eye_6"
	assert_eq(av.call("apply_look", look), ["eyes"])
	look["back"] = "tote_bag"
	assert_eq(av.call("apply_look", look), ["back"])
	look["hat"] = "sun_hat"
	var r: Array = av.call("apply_look", look)
	r.sort()
	assert_eq(r, ["hair", "hair_acc", "hat"], "a crown-covering hat also drops the top curl and refits the clip")
	look["hat"] = "flower_crown"
	r = av.call("apply_look", look)
	r.sort()
	assert_eq(r, ["hair", "hair_acc", "hat"])
	look["skin"] = "skin_5"
	r = av.call("apply_look", look)
	r.sort()
	assert_eq(r, ["lower", "skin", "upper"], "skin: head/hands and the garments that show skin")
	assert_eq(av.call("apply_look", look), [], "idempotent after changes")
	# the partial look fills the rest from the legacy look
	r = av.call("apply_look", {"hair": "bob"})
	assert_true(r.has("hair") and r.has("shoes") and r.has("back"))
	assert_eq(String(av.call("current_look")["upper"]), "explorer_jacket")
	# no source parts leak: every kept-aside part belongs to a live container
	var detached: Dictionary = av.get("_detached")
	for did in detached:
		assert_true(is_instance_valid(instance_from_id(did)), "kept parts belong to live containers")


func test_unknown_ids_fall_back_without_touching_the_saved_look() -> void:
	var look := ItemDB.legacy_look()
	look["hair"] = "future_curls"
	look["upper"] = "jetpack_2099"
	look["hat"] = "crown_of_tomorrow"
	look["palette"]["primary"] = "neon"
	var before := look.duplicate(true)
	var av := _avatar(look)
	assert_eq(look, before, "the given look (saved data) is never modified")
	var cur: Dictionary = av.call("current_look")
	assert_eq(cur["hair"], "side_braid", "safe default hair")
	assert_eq(cur["upper"], "explorer_jacket")
	assert_eq(cur["hat"], "", "unknown hat -> the legacy (none)")
	var missing: Array = av.call("missing_ids")
	for m in ["hair=future_curls", "upper=jetpack_2099", "hat=crown_of_tomorrow", "palette.primary=neon"]:
		assert_true(missing.has(m), "reports " + m)
	assert_true(int(av.call("draw_call_estimate")) > 60, "still fully drawn")
	# the player's avatar keeps GameState.appearance as it is
	fresh_state()
	GameState.appearance["hair"] = "future_curls"
	var pl := _avatar({}, true)
	assert_eq(String(GameState.appearance["hair"]), "future_curls", "the saved value survives")
	assert_eq(String(pl.call("current_look")["hair"]), "side_braid")
	assert_true((pl.call("missing_ids") as Array).has("hair=future_curls"))
	fresh_state()


func test_two_avatars_render_independently() -> void:
	var a := _avatar(ItemDB.legacy_look())
	var look := ItemDB.legacy_look()
	look["palette"] = {"primary": "rose", "secondary": "lavender", "accent": "mint"}
	look["hair_color"] = "platinum"
	look["skin"] = "skin_4"
	var b := _avatar(look)
	var before := _colors_of(a)
	var bc := _colors_of(b)
	assert_ne(before, bc, "different looks look different")
	assert_true(_draws(a, Color("3fa7a0")), "A keeps the legacy teal")
	assert_false(_draws(b, Color("3fa7a0"), 0.01), "B has no teal")
	# baked joint meshes are not shared when the colours differ ...
	var sa: Array = _baked_meshes(a, "spine")
	var sb: Array = _baked_meshes(b, "spine")
	assert_true(not sa.is_empty() and not sb.is_empty())
	for m in sa:
		assert_false(sb.has(m), "no shared baked mesh between different colours")
	# ... and changing B again never touches A
	look["palette"] = {"primary": "berry", "secondary": "snow", "accent": "cocoa"}
	look["upper"] = "cloud_cardigan"
	b.call("apply_look", look)
	assert_eq(_colors_of(a), before, "A unchanged after B changed")
	# identical looks share the cached merged meshes (content-keyed cache)
	var c := _avatar(ItemDB.legacy_look())
	var sc: Array = _baked_meshes(c, "spine")
	assert_eq(sc.size(), sa.size())
	for m in sc:
		assert_true(sa.has(m), "same look -> same cached mesh")


func _baked_meshes(av: Node3D, host_key: String) -> Array:
	var host: Node3D = av.get("_hosts")[host_key]
	var out: Array = []
	for c in host.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Baked"):
			out.append((c as MeshInstance3D).mesh)
	return out


## Every albedo / vertex colour drawn by an avatar (sRGB html, 8-bit).
func _colors_of(av: Node3D) -> Dictionary:
	var out := {}
	for c in _color_list(av):
		out[(c as Color).to_html(false)] = true
	return out


## True when the avatar draws a colour within `tol` of `c` (baked vertex colours are stored as 8-bit linear).
func _draws(av: Node3D, c: Color, tol: float = 0.02) -> bool:
	for d in _color_list(av):
		var e := d as Color
		if absf(e.r - c.r) <= tol and absf(e.g - c.g) <= tol and absf(e.b - c.b) <= tol:
			return true
	return false


func _color_list(av: Node3D) -> Array:
	var out: Array = []
	for m in _all_meshes(av):
		var mi := m as MeshInstance3D
		var mat := mi.material_override
		if not (mat is ShaderMaterial):
			continue
		var sm := mat as ShaderMaterial
		if bool(sm.get_shader_parameter("use_vertex_color")):
			var cols: Variant = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			if cols is PackedColorArray:
				for k in range(0, (cols as PackedColorArray).size(), 7):
					out.append((cols as PackedColorArray)[k].linear_to_srgb())
		else:
			out.append(sm.get_shader_parameter("albedo") as Color)
	return out


func test_driven_avatar_follows_game_state_and_events() -> void:
	fresh_state()
	var av := _avatar({}, true)
	assert_eq(av.call("current_look"), ItemDB.legacy_look(), "the migration default is the legacy look")
	GameState.appearance["hair"] = "space_buns"
	GameState.appearance["lower"] = "tulle_party_dress"
	Events.appearance_changed.emit()
	assert_eq(String(av.call("current_look")["hair"]), "space_buns")
	assert_true(av.get("_skirt") != null, "the party dress sways")
	# show equipped armor: hood / vest / boots over the look, off again when hidden
	GameState.equipment["head"] = "copperwood_hood"
	GameState.equipment["body"] = "copperwood_vest"
	GameState.equipment["boots"] = "copperwood_boots"
	GameState.wardrobe["show_armor"] = false
	Events.equipment_changed.emit("head", "copperwood_hood")
	assert_true((av.get("_unit_boxes")["armor"] as Array).is_empty(), "armor hidden while show_armor is off")
	GameState.wardrobe["show_armor"] = true
	Events.appearance_changed.emit()
	assert_false((av.get("_unit_boxes")["armor"] as Array).is_empty(), "vest shown")
	var copper := Color("c98a55")
	assert_true(_draws(av, copper), "copperwood tier colour")
	GameState.wardrobe["show_armor"] = false
	Events.appearance_changed.emit()
	assert_false(_draws(av, copper, 0.01), "armor hidden again")
	fresh_state()
	Events.game_loaded.emit()
	assert_eq(av.call("current_look"), ItemDB.legacy_look(), "reload -> the loaded look")


func test_show_armor_pieces_replace_or_cover_their_slot() -> void:
	var look := _look_for_outfit("ribbon_witch")
	var av := _avatar(look)
	var hc: Node3D = av.get("_head_c")
	for set_id in ["padded", "copperwood", "ironwood", "moonsteel"]:
		var st := ItemDB.armor_set(set_id)
		var pieces: Dictionary = st["pieces"]
		var r: Array = av.call("apply_armor", true, pieces)
		assert_true(r.has("hat") and r.has("armor") and r.has("shoes"), set_id + " rebuilds hat / armor / shoes")
		var tint: Color = ItemDB.item(String(pieces["body"]))["color"]
		assert_true(_draws(av, tint), set_id + " tier colour shown")
		var hat_nodes: Array = []
		for b in av.get("_unit_boxes")["hat"]:
			for c in (b as Node).get_children():
				hat_nodes.append(String(c.name))
		assert_true(hat_nodes.has("ArmorHead"), set_id + ": the helm / hood replaces the witch hat")
		assert_false(hat_nodes.has("WitchHat"))
		assert_true(bool(av.call("_hides_hair")), "the helm hides the crown hair")
		var boots_geo := _unit_geometry(av, "shoes", hc)
		assert_false(_near(boots_geo["colors"], ItemDB.swatch_color("rose"), 0.01), set_id + " boots replace the buckle boots")
	# unknown / wrong-slot ids never show
	var back: Array = av.call("apply_armor", true, {"head": "copper_sword", "body": "nope", "boots": "moonsteel_helm"})
	assert_true((av.get("_unit_boxes")["armor"] as Array).is_empty(), "wrong-slot ids are never drawn")
	assert_true(back.has("hat"), "witch hat back")
	assert_eq(av.call("apply_armor", false, {}), [], "nothing left to change")
	var names: Array = []
	for b2 in av.get("_unit_boxes")["hat"]:
		for c2 in (b2 as Node).get_children():
			names.append(String(c2.name))
	assert_true(names.has("WitchHat"))


func test_appearance_never_adds_collision() -> void:
	var av := _avatar()
	var looks: Array = []
	for oid in AppearanceData.OUTFITS:
		looks.append(_look_for_outfit(oid))
	for look in looks:
		av.call("apply_look", look)
		av.call("apply_armor", true, ItemDB.armor_set("moonsteel")["pieces"])
		var stack: Array = [av]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			assert_false(n is CollisionObject3D or n is CollisionShape3D, "cosmetics never add collision (%s)" % look["outfit"])


## Contract with the appearance UI module's widget (src/ui/widgets/avatar_preview.gd, duck-typed): the real
## avatar runs in "live" mode, is built once from the `appearance` set before add_child, updates in place and
## shows the equipment it was given through set_show_armor (apply_armor on the avatar).
func test_ui_preview_widget_drives_the_real_avatar() -> void:
	const WIDGET := "res://src/ui/widgets/avatar_preview.gd"
	if not ResourceLoader.exists(WIDGET):
		return   # the UI module's widget is not in this build
	fresh_state()
	var widget_script: Script = load(WIDGET)
	widget_script.set("_script_cache", null)
	widget_script.set("_script_checked", false)
	var look := ItemDB.legacy_look()
	look["hair"] = "bob"
	look["lower"] = "pleated_skirt_leggings"
	var pv: Control = widget_script.new()
	pv.call("setup", {"look": look, "size": Vector2(300, 400), "equipment": {"head": "", "body": "ironwood_mail", "boots": ""}})
	add_child(pv)
	_avs.append(pv)
	await wait_frames(1)
	assert_eq(String(pv.get("mode")), "live", "the widget recognises the appearance API")
	var av: Node3D = pv.get("avatar")
	assert_eq(av.get_script(), AvatarScript)
	assert_false(bool(av.get("driven")))
	assert_eq(String(av.call("current_look")["hair"]), "bob", "built from the look given before add_child")
	assert_not_null(av.get("_skirt"))
	look["hair"] = "space_buns"
	pv.call("set_look", look)
	assert_eq(String(av.call("current_look")["hair"]), "space_buns", "updated in place")
	pv.call("set_show_armor", true)
	assert_false((av.get("_unit_boxes")["armor"] as Array).is_empty(), "equipped mail shown in the preview")
	pv.call("set_show_armor", false)
	assert_true((av.get("_unit_boxes")["armor"] as Array).is_empty())
	fresh_state()
