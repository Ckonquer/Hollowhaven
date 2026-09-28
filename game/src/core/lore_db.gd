extends RefCounted
## All lore notes, legacy and Chapter Two, through one lookup (journal, world notes, QA).
##   LoreDB.get_lore(id) -> {"title", "text"} (arachnophobia-aware), LoreDB.has_lore(id), LoreDB.ids()
## Legacy notes stay in src/world/below/lore.gd (never renamed). Chapter Two notes live in one data file
## per module (docs/CHAPTER_TWO_SPEC.md §10), each shaped like lore.gd: `const ORDER := [ids]` and
## `const LORE := {id: {"title", "text", optional "alt_title"/"alt_text"}}`. Missing files are skipped.

const LEGACY := preload("res://src/world/below/lore.gd")
const FILES := [
	"res://data/lore_ch2_annex.gd",
	"res://data/lore_ch2_reach.gd",
	"res://data/lore_ch2_manor.gd",
	"res://data/lore_ch2_works.gd",
	"res://data/lore_ch2_story.gd",
]

static var _tables: Array = []   # [[ORDER, LORE], ...] legacy first, loaded once


static func _load() -> void:
	if not _tables.is_empty():
		return
	_tables.append([LEGACY.ORDER, LEGACY.LORE])
	for path in FILES:
		if not ResourceLoader.exists(String(path)):
			continue
		var s: Script = load(String(path))
		if s == null:
			continue
		var consts: Dictionary = s.get_script_constant_map()
		var lore: Variant = consts.get("LORE", {})
		var order: Variant = consts.get("ORDER", [])
		if lore is Dictionary:
			_tables.append([order if order is Array else lore.keys(), lore])


## Every lore id in journal order (legacy first, then each Chapter Two file in FILES order).
static func ids() -> Array:
	_load()
	var out: Array = []
	for t in _tables:
		for id in t[0]:
			if not out.has(id) and (t[1] as Dictionary).has(id):
				out.append(id)
	return out


static func has_lore(id: String) -> bool:
	_load()
	for t in _tables:
		if (t[1] as Dictionary).has(id):
			return true
	return false


static func get_lore(id: String) -> Dictionary:
	_load()
	for t in _tables:
		var lore: Dictionary = t[1]
		if lore.has(id):
			var e: Dictionary = lore[id]
			var arach := bool(Settings.get_value("arachnophobia"))
			var title := String(e.get("alt_title", e.get("title", ""))) if arach else String(e.get("title", ""))
			var text := String(e.get("alt_text", e.get("text", ""))) if arach else String(e.get("text", ""))
			return {"title": title, "text": text}
	return {"title": "", "text": ""}


## Tests only: forget the cached tables (after adding a file).
static func reload() -> void:
	_tables = []
