extends Node3D
## QA-ONLY helper (debug builds via the preview stage): fells a tree, mines a rock and picks a bush
## while saving screenshots, to check the hit wobble, particles, topple, stump and respawn growth.
##   tools/godot.sh --path game --windowed -- --preview=res://src/world/common/qa_harvest.gd --preview-wait=90 --shot-dir=<dir>

const ResourceNode := preload("res://src/world/common/resource_node.gd")

var _cam: Camera3D


func _ready() -> void:
	if not Debug.is_cheat_allowed():
		return
	GameState.new_game()
	GameState.give_item("stone_axe", 1)
	GameState.give_item("stone_pickaxe", 1)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.position = Vector3(0, 3.2, 9.0)
	_cam.look_at(Vector3(0, 2.0, 0), Vector3.UP)
	_cam.make_current()
	_run.call_deferred()


func _shot(dir: String, label: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(dir.path_join("harvest_%s.png" % label))
	print("QA harvest: ", label)


func _run() -> void:
	var dir := Debug.arg("shot-dir", "user://qa_harvest")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	_cam.make_current()   # the preview stage makes its own camera current after our _ready
	var tree: Node3D = ResourceNode.new()
	tree.setup({"node_id": "qa_tree", "kind": "tree", "visual": "oak", "seed": 1})
	add_child(tree)
	var rock: Node3D = ResourceNode.new()
	rock.setup({"node_id": "qa_rock", "kind": "rock", "seed": 0})
	add_child(rock)
	rock.position = Vector3(-3.2, 0, 2.0)
	var bush: Node3D = ResourceNode.new()
	bush.setup({"node_id": "qa_bush", "kind": "bush", "seed": 1})
	add_child(bush)
	bush.position = Vector3(3.0, 0, 2.5)
	var fake_player := Node3D.new()
	add_child(fake_player)
	fake_player.position = Vector3(-1.5, 0, 3.0)
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "00_start")
	for i in 3:
		tree.harvest_hit(fake_player, "stone_axe")
		rock.harvest_hit(fake_player, "stone_pickaxe")
		await get_tree().create_timer(0.08).timeout
		if i == 0:
			await _shot(dir, "01_hit_wobble")
		await get_tree().create_timer(0.45).timeout
	bush.interact(fake_player)
	tree.harvest_hit(fake_player, "stone_axe")
	await get_tree().create_timer(0.6).timeout
	await _shot(dir, "02_falling")
	await get_tree().create_timer(0.7).timeout
	await _shot(dir, "03_landed")
	await get_tree().create_timer(1.6).timeout
	await _shot(dir, "04_stump")
	GameState.total_minutes += 2000.0
	tree.restore(true)
	rock.restore(true)
	bush.restore(true)
	await get_tree().create_timer(0.5).timeout
	await _shot(dir, "05_regrowing")
	await get_tree().create_timer(1.2).timeout
	await _shot(dir, "06_regrown")
	print("QA harvest: wood=%d stone=%d berries=%d felled=%d" % [GameState.count_item("wood"), GameState.count_item("stone"), GameState.count_item("berries"), GameState.get_counter("trees_felled")])
	get_tree().quit()
