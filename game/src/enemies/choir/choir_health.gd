extends "res://src/combat/health.gd"
## The Borrowed Choir's Health: the shared contract (apply_damage returns what was dealt, 0 = blocked) plus a
## `floor_hp` that one hit can never go below. The boss sets it at the start of every exposure to the lowest
## hp that exposure may reach (choir_rules.gd window_min_hp), so a huge hit ends the window exactly at its cap
## and never skips a phase boundary or the third kept-flame exposure. floor_hp 0 = the ordinary rule.

var floor_hp: float = 0.0


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
