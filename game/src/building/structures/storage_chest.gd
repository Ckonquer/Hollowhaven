extends "res://src/building/structure.gd"
## Storage chest: opens the storage panel for its GameState.storages[uid] inventory.
## The lid swings open with a springy hinge while the panel is up and closes when the UI closes.

const OPEN_ANGLE := -105.0

var _open := false
var _lid_tween: Tween


func _setup_behaviour() -> void:
	Events.ui_stack_changed.connect(_on_ui_stack_changed)


func get_interaction(_player: Node) -> Dictionary:
	var inv: Variant = GameState.storages.get(uid)
	var used := 0
	var total := int(def.get("slots", 20))
	if inv != null:
		used = int(inv.size) - int(inv.free_slots())
		total = int(inv.size)
	return {"text": "Open %s (%d/%d)" % [display_name(), used, total], "enabled": true}


func interact(_player: Node) -> void:
	set_open(true)
	Game.open_panel("storage", {"uid": uid})
	# If no panel actually opened (e.g. a placeholder UI), close again after a moment.
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(self) and _open and not Game.is_ui_open():
			set_open(false))


func is_open() -> bool:
	return _open


func set_open(open: bool) -> void:
	if open == _open:
		return
	_open = open
	Audio.play_sfx("chest_open" if open else "chest_close")
	var lid: Variant = parts.get("lid")
	if not (lid is Node3D) or not is_inside_tree():
		return
	if _lid_tween != null and _lid_tween.is_valid():
		_lid_tween.kill()
	_lid_tween = create_tween()
	_lid_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)     # keep animating while the panel pauses the world
	if open:
		_lid_tween.tween_property(lid, "rotation:x", deg_to_rad(OPEN_ANGLE), 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_lid_tween.tween_property(lid, "rotation:x", 0.0, 0.28).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _on_ui_stack_changed(open_count: int) -> void:
	if _open and open_count == 0:
		set_open(false)
