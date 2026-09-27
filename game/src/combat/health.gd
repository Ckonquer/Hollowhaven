extends Node
## Health component. Add as a child named "Health" and expose it as a `health` property on the owner.
##   health = preload("res://src/combat/health.gd").new(); health.name = "Health"; health.max_hp = 30.0
##   add_child(health)
## Damage multipliers/invulnerability are handled here so every damage source behaves the same.

signal damaged(amount: float, source: Node, dir: Vector3)
signal healed(amount: float)
signal died
signal changed(hp: float, max_hp: float)

@export var max_hp: float = 100.0
var hp: float = -1.0
var dead: bool = false
var invulnerable: bool = false          # e.g. dodge i-frames, cutscenes
var damage_taken_mult: float = 1.0      # e.g. 2.0 while a Gloomling is "exposed" by light
var _iframe_until_ms: int = 0


func _ready() -> void:
	if hp < 0.0:
		hp = max_hp


## Applies damage and returns the amount actually dealt (0 if ignored).
func apply_damage(amount: float, source: Node = null, dir: Vector3 = Vector3.ZERO) -> float:
	if dead or invulnerable or amount <= 0.0:
		return 0.0
	if Time.get_ticks_msec() < _iframe_until_ms:
		return 0.0
	var dealt: float = minf(amount * damage_taken_mult, hp)
	hp -= dealt
	damaged.emit(dealt, source, dir)
	changed.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit()
	return dealt


## Grants temporary invulnerability (seconds) after a hit.
func grant_iframes(seconds: float) -> void:
	_iframe_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func heal(amount: float) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var h: float = minf(amount, max_hp - hp)
	if h <= 0.0:
		return 0.0
	hp += h
	healed.emit(h)
	changed.emit(hp, max_hp)
	return h


func set_hp(value: float) -> void:
	hp = clampf(value, 0.0, max_hp)
	dead = hp <= 0.0
	changed.emit(hp, max_hp)


func reset() -> void:
	hp = max_hp
	dead = false
	_iframe_until_ms = 0
	changed.emit(hp, max_hp)


func ratio() -> float:
	return hp / max_hp if max_hp > 0.0 else 0.0
