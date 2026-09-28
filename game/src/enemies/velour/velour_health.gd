extends "res://src/combat/health.gd"
## Count Velour's health: the shared Health contract (src/combat/health.gd: signals damaged -> changed -> died,
## `apply_damage` returning 0 = "blocked") plus ONE extra rule, `floor_hp`: a hit can never take hp below it.
## The boss raises the floor to the next phase threshold (a single big hit never skips a phase's mechanic) and,
## in phase C, to the "borrowed mask" floor until light has staggered him once (MP 13.1: at least one meaningful
## interaction with the candle rule, however strong her gear). A hit that finds no room above the floor deals 0,
## so Combat.melee / projectiles / companions treat it exactly like a blocked hit (spark, no knockback, no XP).
##   health.floor_hp = 126.0     # hp stays >= 126 until the boss lowers the floor

var floor_hp: float = 0.0


## Applies damage down to (never below) `floor_hp`; returns the amount actually dealt (0 = ignored).
func apply_damage(amount: float, source: Node = null, dir: Vector3 = Vector3.ZERO) -> float:
	if dead or invulnerable or amount <= 0.0:
		return 0.0
	if Time.get_ticks_msec() < _iframe_until_ms:
		return 0.0
	var room: float = hp - maxf(floor_hp, 0.0)
	if room <= 0.0001:
		return 0.0
	var dealt: float = minf(amount * damage_taken_mult, room)
	hp -= dealt
	damaged.emit(dealt, source, dir)
	changed.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit()
	return dealt


## Heals at most up to `ceiling` (the top of the current phase) and never above max_hp. Returns the hp restored.
func heal_capped(amount: float, ceiling: float) -> float:
	var room: float = minf(ceiling, max_hp) - hp
	if room <= 0.0 or amount <= 0.0:
		return 0.0
	return heal(minf(amount, room))
