extends "res://src/enemies/enemy_base.gd"
## Brambling (surface): a grumpy walking thornball. Hops around, crouches and wiggles with a red
## tint for 0.7 s before a lunge-bite, then sits dizzy for 1.1 s (the punish window).
## Stats: data/enemies.gd "brambling". Sounds: brambling_chatter, brambling_telegraph.

const Visual := preload("res://src/enemies/brambling_visual.gd")

const LEAF_COLOR := Color("8cc063")


func _init() -> void:
	hit_color = Color(0.72, 0.86, 0.5)


func _default_id() -> String:
	return "brambling"


func _build_visual() -> Node3D:
	return Visual.new()


func _body_radius() -> float:
	return 0.42


func _body_height() -> float:
	return 1.0


func _lunge_distance() -> float:
	return 1.3


func _on_alert() -> void:
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.5, 0.0, 0.12)


func _on_telegraph_start() -> void:
	Audio.play_3d("brambling_telegraph", global_position + Vector3.UP * 0.5, 0.0, 0.05)


func _on_attack_start() -> void:
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.5, -3.0, 0.2)


func _idle_sound() -> void:
	Audio.play_3d("brambling_chatter", global_position + Vector3.UP * 0.5, -8.0, 0.15)


func _on_hurt(_amount: float) -> void:
	Audio.play_3d("enemy_hurt", global_position + Vector3.UP * 0.5, -3.0, 0.12)
	HitFx.chips(global_position + Vector3.UP * 0.6, LEAF_COLOR, 7, 3.0, 0.55)


## Dizzy spin, a squeak, then a harmless puff of leaves (no gore).
func _play_defeat() -> void:
	if visual == null:
		return
	if visual.has_method("set_state"):
		visual.set_state("dead")
	var tw := create_tween()
	tw.tween_property(visual, "rotation:y", visual.rotation.y + TAU * 1.5, 0.55).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "scale", Vector3(1.15, 0.7, 1.15), 0.55)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.05, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tw.finished
	var pos := global_position + Vector3.UP * 0.5
	HitFx.chips(pos, LEAF_COLOR, 14, 3.8, 0.8)
	HitFx.chips(pos, Color("e3c08a"), 8, 3.2, 0.7)
	HitFx.burst(pos, Color(0.85, 0.95, 0.75, 0.6), 6, 1.2, 1.6, 0.5, 0.6)
