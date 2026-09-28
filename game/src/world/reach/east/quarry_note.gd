extends Node3D
## The Ashbell quarry log: a weathered tally book on a lectern by the tool shed. Reading it discovers the lore
## entry lore_ch2_quarry_log (the text itself belongs to the region module's data/lore_ch2_reach.gd, read
## through src/core/lore_db.gd; a neutral line stands in until that entry exists). Reading is free and
## repeatable; the journal entry is recorded once.
## Interaction contract: group "interactable" + a layer-16 sphere; the lectern is solid (layer 1).

const Q := preload("res://data/reach_east.gd")
const QV := preload("res://src/world/reach/east/quarry_visuals.gd")
const NV := preload("res://src/world/common/node_visuals.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const LORE_DB_PATH := "res://src/core/lore_db.gd"

var lore_id: String = Q.LORE_LOG


func _ready() -> void:
	name = "QuarryLog"
	add_to_group("interactable")
	var wood := NV.Merger.new()
	QV.add_rod(wood, Vector3(0, -0.1, 0), Vector3(0, 1.0, 0), 0.07, Palette.WOOD_DARK)
	QV.add_box(wood, Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3(0, 1.08, 0)), Vector3(0.62, 0.06, 0.44), Palette.WOOD)
	QV.add_box(wood, Transform3D(Basis(), Vector3(0, -0.02, 0)), Vector3(0.5, 0.08, 0.5), Palette.WOOD_DARK)
	add_child(NV._mi(wood.commit(), QV.wood_material(), "Lectern"))
	var book := Kit.box(Vector3(0.5, 0.05, 0.34), Mat.toon(Color("efe0bd"), {"emission": Color("efe0bd"), "emission_energy": 0.12}))
	book.name = "Book"
	book.position = Vector3(0, 1.13, 0.02)
	book.rotation = Vector3(-0.45, 0, 0)
	add_child(book)
	var spine := Kit.box(Vector3(0.04, 0.07, 0.36), Mat.toon(Q.COL_RIBBON_B))
	spine.position = Vector3(0, 1.14, 0.02)
	spine.rotation = Vector3(-0.45, 0, 0)
	add_child(spine)
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.6, 1.1, 0.5)
	cs.shape = bx
	cs.position = Vector3(0, 0.55, 0)
	body.add_child(cs)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.8
	ics.shape = sph
	ics.position = Vector3(0, 1.0, 0)
	ib.add_child(ics)
	add_child(ib)


func get_interaction(_player: Node = null) -> Dictionary:
	return {"text": Q.TEXT["log_read"], "enabled": true}


func interact(_player: Node = null) -> void:
	read()


## Shows the note and records the lore entry (once). Returns true when the entry was new.
func read() -> bool:
	var title: String = Q.TEXT["log_missing_title"]
	var text: String = Q.TEXT["log_missing_text"]
	if ResourceLoader.exists(LORE_DB_PATH):
		var db: Variant = load(LORE_DB_PATH)
		if db is Script and bool((db as Script).call("has_lore", lore_id)):
			var l: Variant = (db as Script).call("get_lore", lore_id)
			if l is Dictionary:
				title = String((l as Dictionary).get("title", title))
				text = String((l as Dictionary).get("text", text))
	var fresh := GameState.discover_lore(lore_id)
	if Audio.has_method("play_ui"):
		Audio.play_ui("ui_open", -6.0)
	Events.say.emit(title, text, 9.0)
	return fresh
