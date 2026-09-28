extends "res://src/building/structures/lamp.gd"
## Carved pumpkin lantern (data interact "face"): a warm, flickering light (lamp.gd: group "light_source") with
## a carved face. The face is chosen before placing (BuildMode's variant key, saved as data.face) and can be
## re-carved any time by interacting. Faces: data/structures.gd `faces` (friendly, sleepy, toothy, cat, moon,
## ghost). Purely decorative: it never moves, hunts or harms anyone, in any season.

var preview_face := ""        # face shown by previews without a record (setup param "face")


func setup(params: Dictionary) -> void:
	super.setup(params)
	preview_face = String(params.get("face", preview_face))


func model_opts() -> Dictionary:
	var o := super.model_opts()
	if not o.has("face") and preview_face != "":
		o["face"] = preview_face
	return o


## Face ids this pumpkin can show (data order).
func faces() -> Array:
	var f: Variant = def.get("faces", [])
	return f if f is Array and not (f as Array).is_empty() else ["friendly"]


## The current face (unknown or missing = the first one).
func face() -> String:
	var fid := String(model_opts().get("face", ""))
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


## Saves and shows a new face (records only; previews just redraw).
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
