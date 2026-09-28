extends "res://tests/test_case.gd"
## Module B7: numeric geometry checks of the procedural props (no screenshots possible here): sizes, ground
## contact, the ribbon knot on its branch, the cache lid opening upward, root walls matching their colliders,
## shared (cached) meshes and materials.

const L := preload("res://data/c1x_layout.gd")
const Common := preload("res://src/world/surface/c1x/common.gd")
const Tailor := preload("res://src/world/surface/c1x/tailor_cache.gd")
const Bramble := preload("res://src/world/surface/c1x/bramblewatch.gd")


func _aabb_of(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := node.global_transform.affine_inverse() * mi.global_transform if node.is_inside_tree() else _local_xf(node, mi)
		var box: AABB = xf * mi.mesh.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out


func _local_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func test_ribbon_is_tied_on_its_branch() -> void:
	for v in 3:
		var mesh := Common.branch_mesh(v)
		var knot := Common.branch_knot(v)
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var best := INF
		for p in verts:
			best = minf(best, p.distance_to(knot))
		assert_true(best < 0.1, "branch %d: the knot touches the branch (%.3f m)" % [v, best])
		assert_true(knot.y > 0.8 and knot.y < 1.3, "a LOW branch: knot at %.2f m" % knot.y)
		var box := mesh.get_aabb()
		assert_true(box.position.y > -0.2 and box.end.y < 1.6, "branch %d height %.2f" % [v, box.end.y])
	var marker := Common.ribbon_marker(Common.RIBBON_COLORS["rose"], 1, true)
	add_child(marker)
	var bow := marker.get_node("Bow") as Node3D
	assert_true(bow.position.distance_to(Common.branch_knot(1)) < 0.001, "the bow sits at the knot")
	var tails := marker.get_node("Tails") as MeshInstance3D
	var tb: AABB = tails.transform * tails.mesh.get_aabb()
	assert_true(tb.end.y <= bow.position.y + 0.05 and tb.position.y > 0.3, "the tails hang below the knot, above the ground")
	marker.queue_free()


func test_prop_sizes_and_ground_contact() -> void:
	var pm := Common.pumpkin_mesh(0).get_aabb()
	assert_true(pm.position.y > -0.05 and pm.position.y < 0.05, "pumpkin rests on the ground (%.3f)" % pm.position.y)
	assert_true(pm.size.x > 0.35 and pm.size.x < 0.8 and pm.size.y > 0.3 and pm.size.y < 0.7, "pumpkin size %s" % pm.size)
	var stump := Common.sap_stump_visual(0)
	add_child(stump)
	var sb := _aabb_of(stump)
	assert_true(sb.position.y > -0.2 and sb.position.y < 0.05, "stump on the ground (%.2f)" % sb.position.y)
	assert_true(sb.end.y > 0.55 and sb.end.y < 0.9, "stump height %.2f" % sb.end.y)
	assert_true(sb.size.x < 1.4 and sb.size.z < 1.6, "stump footprint %s within the layout radius" % sb.size)
	assert_true(float(stump.get_meta("solid_radius")) <= L.SAP_RADIUS, "collider inside the footprint")
	stump.queue_free()
	for v in 3:
		var fl := Common.sunflax_visual(v)
		add_child(fl)
		var fb := _aabb_of(fl)
		assert_true(fb.end.y > 0.6 and fb.end.y < 1.3 and fb.position.y > -0.1, "sunflax %d height %.2f" % [v, fb.end.y])
		assert_true(maxf(fb.size.x, fb.size.z) < L.PLANT_RADIUS * 2.0 + 0.5, "sunflax %d footprint" % v)
		fl.queue_free()
	var rb := Common.roseberry_visual(0)
	add_child(rb)
	var rbb := _aabb_of(rb)
	assert_true(rbb.end.y > 0.8 and rbb.end.y < 1.6, "roseberry bush height %.2f" % rbb.end.y)
	rb.queue_free()
	var mb := Common.moonbell_mesh().get_aabb()
	assert_true(mb.end.y > 0.4 and mb.end.y < 0.8 and mb.position.y > -0.05, "moonbell height %.2f" % mb.end.y)
	var post := Common.post_mesh().get_aabb()
	assert_true(post.end.y > 1.6 and post.end.y < 2.3, "watch post height %.2f" % post.end.y)
	var tree := Common.sticky_tree_meshes()
	var tb := (tree["bark"] as ArrayMesh).get_aabb().merge((tree["crown"] as ArrayMesh).get_aabb())
	assert_true(tb.end.y > 6.0 and tb.end.y < 11.0, "the sticky old tree is a proper tree (%.1f m)" % tb.end.y)
	var resin := (tree["resin"] as ArrayMesh).get_aabb()
	assert_true(resin.end.y < 4.4 and resin.position.y > 0.3, "resin runs down the trunk")


func test_cache_lid_closes_on_the_body_and_opens_upward() -> void:
	fresh_state()
	var holder := Node3D.new()
	add_child(holder)
	var c := Tailor.Cache.new()
	holder.add_child(c)
	var body := (c.get_node("Body") as MeshInstance3D).mesh.get_aabb()
	var lid_mi := c.lid.get_node("LidMesh") as MeshInstance3D
	var closed: AABB = c.lid.transform * lid_mi.mesh.get_aabb()
	assert_almost(closed.position.y, body.end.y, 0.06, "the closed lid sits on the body")
	assert_true(absf(closed.get_center().z) < 0.06 and absf(closed.get_center().x) < 0.06, "and covers the box (centred on it: %s)" % closed.get_center())
	assert_true(closed.size.x >= 0.78 and closed.size.z >= 0.5, "as wide and deep as the box (%s)" % closed.size)
	assert_true(closed.size.y < 0.3, "a low dome (%.2f m)" % closed.size.y)
	c.lid.rotation.x = Tailor.Cache.OPEN_ANGLE
	var open: AABB = c.lid.transform * lid_mi.mesh.get_aabb()
	assert_true(open.end.y > closed.end.y + 0.25, "the lid swings up when open")
	assert_true(open.get_center().z < closed.get_center().z, "and back, over its hinge")
	var box := (c.get_node("Solid").get_child(0) as CollisionShape3D).shape as BoxShape3D
	assert_true(box.size.x >= 0.78 and box.size.x <= 0.9 and box.size.z >= 0.5 and box.size.z <= 0.6, "collider matches the box (%s)" % box.size)
	holder.queue_free()


func test_root_wall_matches_its_collider_and_slot() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var w := Bramble.RootWall.new()
	holder.add_child(w)
	var mesh := (w.get("_roots") as MeshInstance3D).mesh.get_aabb()
	var length := float(L.ELDER_ARENA["root_length"])
	var h := float(L.ELDER_ARENA["root_height"])
	assert_true(absf(mesh.size.x - length) < 0.9, "roots span the slot (%.2f vs %.2f)" % [mesh.size.x, length])
	assert_true(mesh.end.y > h * 0.7 and mesh.end.y < h + 0.5, "roots stand about %.1f m (%.2f)" % [h, mesh.end.y])
	var solid := (w.get("_solid") as StaticBody3D).get_child(0) as CollisionShape3D
	var sbox := solid.shape as BoxShape3D
	assert_almost(sbox.size.x, length, 0.001, "collider length = slot length")
	assert_true(sbox.size.y >= h, "collider at least as tall as the roots (no hopping over by accident)")
	var crack := Common.crack_meshes(length + 0.4)
	var cb := (crack["soil"] as ArrayMesh).get_aabb()
	assert_true(cb.size.y < 0.25 and cb.size.x > length, "the telegraph is a flat strip covering the slot")
	holder.queue_free()


func test_meshes_and_materials_are_shared() -> void:
	assert_eq(Common.pumpkin_mesh(0), Common.pumpkin_mesh(0), "pumpkin mesh cached")
	assert_eq(Common.root_wall_mesh(3.8, 1.5), Common.root_wall_mesh(3.8, 1.5), "root mesh cached")
	assert_eq(Common.prop_material(), Common.prop_material(), "prop material cached")
	assert_eq(Common.resin_material(), Common.resin_material(), "resin material cached")
	var a := Common.sap_stump_visual(1)
	var b := Common.sap_stump_visual(1)
	assert_eq((a.get_node("Stump") as MeshInstance3D).mesh, (b.get_node("Stump") as MeshInstance3D).mesh, "stumps share geometry")
	a.free()
	b.free()
