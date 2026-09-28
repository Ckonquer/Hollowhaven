extends RefCounted
## Which faces a carved pumpkin lantern may show (shared by build_mode.gd and structures/pumpkin_lantern.gd).
## A piece's own `faces` list (data/structures.gd, the six MP §9 faces) is always available. The festival faces
## (data/structures.gd FESTIVAL_FACES, the MP §17 ending reward "carved-lantern patterns") join the end of that
## list once their unlock flag is set (ch2_feast: the Lanternwake). Pure lookups over GameState flags: nothing
## here ever writes a record, so a saved face that is locked (or unknown) is only SHOWN as the first face and
## stays in the save untouched.

const StructuresData := preload("res://data/structures.gd")


## The piece's own faces from its data ([] when it has none, i.e. it is not a carved pumpkin).
static func base_faces(def: Dictionary) -> Array:
	var f: Variant = def.get("faces", [])
	return (f as Array).duplicate() if f is Array else []


## Every face id a model can carve (the six base faces + every festival face, locked or not).
static func all_face_ids() -> Array:
	var out: Array = StructuresData.PUMPKIN_FACES.duplicate()
	for fid in StructuresData.FESTIVAL_FACES:
		if not out.has(String(fid)):
			out.append(String(fid))
	return out


static func is_festival(face_id: String) -> bool:
	return StructuresData.FESTIVAL_FACES.has(face_id)


## The flag that unlocks a festival face ("" for a base / unknown face).
static func unlock_flag(face_id: String) -> String:
	return String(StructuresData.FESTIVAL_FACES.get(face_id, ""))


## True when a festival face's unlock flag is set (false for base / unknown ids).
static func is_unlocked(face_id: String) -> bool:
	var flag := unlock_flag(face_id)
	return flag != "" and (true if GameState.get_flag(flag) else false)


## Festival faces unlocked right now (data order).
static func unlocked_festival() -> Array:
	var out: Array = []
	for fid in StructuresData.FESTIVAL_FACES:
		if is_unlocked(String(fid)):
			out.append(String(fid))
	return out


## Faces the player can choose / carve for this piece now: its base faces, then the unlocked festival faces.
## [] when the piece has no faces at all (festival faces never turn another piece into a pumpkin).
static func unlocked_faces(def: Dictionary) -> Array:
	var out := base_faces(def)
	if out.is_empty():
		return out
	for fid in unlocked_festival():
		if not out.has(fid):
			out.append(fid)
	return out


## The face to SHOW for a saved/selected id: itself when it is available now, else the piece's first face.
static func resolve(def: Dictionary, face_id: String) -> String:
	var list := unlocked_faces(def)
	if list.is_empty():
		return ""
	return face_id if list.has(face_id) else String(list[0])
