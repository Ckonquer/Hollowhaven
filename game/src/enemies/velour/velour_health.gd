extends "res://src/combat/health.gd"
## Count Velour's health: the shared Health contract (src/combat/health.gd: signals damaged -> changed -> died,
## `apply_damage` returning 0 = "blocked") plus ONE extra rule, `floor_hp`: a hit can never take hp below it.
## The boss raises the floor to the next phase threshold (a single big hit never skips a phase's mechanic) and,
## in phase C, to the "borrowed mask" floor until light has staggered him once (MP 13.1: at least one meaningful
## interaction with the candle rule, however strong her gear). A hit that finds no room above the floor deals 0,
## so Combat.melee / projectiles / companions treat it exactly like a blocked hit (spark, no knockback, no XP).
##   health.floor_hp = 126.0     # hp stays >= 126 until the boss lowers the floor
## A second, optional limit, `window_room`: a Callable returning how much more damage the boss's current attack
## window may take (his WINDOW_CAP; < 0 = no limit). It is checked BEFORE the hit lands, so the last blow of a window
## is trimmed to fit instead of overshooting the cap (QA CH2-013) - except a blow that defeats him outright (only
## possible with no floor left: phase C once the candle rule was used), so no sliver of health is left to chase.
##   health.window_room = _window_room

var floor_hp: float = 0.0
var window_room: Callable = Callable()


## Applies damage down to (never below) `floor_hp` and within `window_room`; returns the amount actually dealt
## (0 = ignored).
func apply_damage(amount: float, source: Node = null, dir: Vector3 = Vector3.ZERO) -> float:
	if dead or invulnerable or amount <= 0.0:
		return 0.0
	if Time.get_ticks_msec() < _iframe_until_ms:
		return 0.0
	var room: float = hp - maxf(floor_hp, 0.0)
	if room <= 0.0001:
		return 0.0
	var dealt: float = minf(amount * damage_taken_mult, room)
	if dealt < hp and window_room.is_valid():
		var w := float(window_room.call())
		if w >= 0.0:
			dealt = minf(dealt, w)
	if dealt <= 0.0001:
		return 0.0
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
