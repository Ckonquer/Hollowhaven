extends "res://src/building/structures/lamp.gd"
## Carved pumpkin lantern (data interact "face"): a warm, flickering light (lamp.gd: group "light_source") with
## a carved face. The face is chosen before placing (BuildMode's variant key, saved as data.face) and can be
## re-carved any time by interacting. Faces: data/structures.gd `faces` (friendly, sleepy, toothy, cat, moon,
## ghost), then the festival faces (FESTIVAL_FACES: starry, lanternwake) once the Lanternwake unlocked them
## (src/building/pumpkin_faces.gd). A saved face that is locked or unknown is SHOWN as the first face; the saved
## data.face is never rewritten by loading or looking (only a new carving writes it).
## Purely decorative: it never moves, hunts or harms anyone, in any season.

const Faces := preload("res://src/building/pumpkin_faces.gd")

var preview_face := ""        # face shown by previews without a record (setup param "face")


func setup(params: Dictionary) -> void:
	super.setup(params)
	preview_face = String(params.get("face", preview_face))


## The model always gets the face to SHOW (resolved against what is unlocked now).
func model_opts() -> Dictionary:
	var o := super.model_opts()
	o["face"] = face()
	return o


## Face ids this pumpkin can show now (data order, then unlocked festival faces).
func faces() -> Array:
	var d: Dictionary = def if not def.is_empty() else ItemDB.structure(structure_id)
	var f := Faces.unlocked_faces(d)
	return f if not f.is_empty() else ["friendly"]


## The face id stored for this pumpkin: the record's data.face, else the preview's ("" = none).
func saved_face() -> String:
	var data: Variant = record().get("data", {})
	if data is Dictionary and (data as Dictionary).has("face"):
		return String((data as Dictionary)["face"])
	return preview_face


## The current face (unknown, locked or missing = the first one).
func face() -> String:
	var fid := saved_face()
	var list := faces()
	return fid if list.has(fid) else String(list[0])


func next_face() -> String:
	var list := faces()
	return String(list[(list.find(face()) + 1) % list.size()])


static func face_name(face_id: String) -> String:
	return face_id.capitalize()


func get_interaction(_player: Node) -> Dictionary:
	return {"text": "Carve a new face (%s)" % face_name(next_face()), "enabled": true}


func interact(_player: Node) -> void:
	set_face(next_face())


## Saves and shows a new face (records only; previews just redraw). Only faces available now are accepted.
func set_face(face_id: String) -> void:
	if not faces().has(face_id):
		return
	var rec := record()
	if not rec.is_empty():
		if not (rec.get("data") is Dictionary):
			rec["data"] = {}
		rec["data"]["face"] = face_id
	else:
		preview_face = face_id
	rebuild_model()
	if is_inside_tree():
		_puff(global_position + Vector3.UP * 0.3, 6)
		Audio.play_3d("harvest_crop", global_position + Vector3.UP * 0.3)
