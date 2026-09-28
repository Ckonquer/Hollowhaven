extends "res://src/combat/health.gd"
## Krystal's Health (docs/CHAPTER_TWO_SPEC.md section 9). Same contract as src/combat/health.gd plus the
## Chapter Two damage intake order, processed exactly once per apply_damage() call:
##   1. dead / invulnerable / amount <= 0 / inside i-frames  -> 0, nothing else happens (i-frames BEFORE damage)
##   2. reduction  (Stats.damage_reduction(): armor pieces add, Pebble / charms multiply, cap 45%)
##   3. shield     (transient, Pebble's Stoneheart via add_shield) absorbs what is left AFTER mitigation
##   4. Health     (the rest; `damaged` reports the hp actually lost, Events.player_damaged follows it)
## A hit the shield swallows completely returns 0 (the "blocked" convention: no knockback, no hurt) and
## grants SHIELD_BLOCK_IFRAMES so one attack can't chew through the shield twice.
## Healing: heal(amount) applies Stats.heal_mult() (Mochi's passive, Kindling Charm) - callers never scale.
## The shield is not saved (spec section 5); its timer only runs while the tree runs (pause suspends it).

signal shield_changed(amount: float)
signal shield_hit(absorbed: float)

const Stats := preload("res://src/core/stats.gd")
const SHIELD_BLOCK_IFRAMES := 0.3
const MAX_SHIELD := 60.0

var shield: float = 0.0
var shield_max: float = 0.0
var shield_source: String = ""
var shield_left: float = 0.0            # seconds until the shield fades
## The last processed hit (tests / telemetry): {"raw", "reduction", "mitigated", "absorbed", "dealt"}.
var last_hit: Dictionary = {}


func _ready() -> void:
	super._ready()
	set_physics_process(false)


## Applies one hit through i-frames -> reduction -> shield -> Health. Returns the hp actually lost.
func apply_damage(amount: float, source: Node = null, dir: Vector3 = Vector3.ZERO) -> float:
	if dead or invulnerable or amount <= 0.0:
		return 0.0
	if Time.get_ticks_msec() < _iframe_until_ms:
		return 0.0
	var reduction := Stats.damage_reduction()
	var mitigated := amount * (1.0 - reduction) * damage_taken_mult
	var absorbed := 0.0
	if shield > 0.0 and mitigated > 0.0:
		absorbed = minf(shield, mitigated)
		_set_shield(shield - absorbed)
	var rest := mitigated - absorbed
	last_hit = {"raw": amount, "reduction": reduction, "mitigated": mitigated, "absorbed": absorbed, "dealt": 0.0}
	if rest <= 0.0001:
		grant_iframes(SHIELD_BLOCK_IFRAMES)
		if absorbed > 0.0:
			shield_hit.emit(absorbed)
		return 0.0
	var dealt: float = minf(rest, hp)
	last_hit["dealt"] = dealt
	hp -= dealt
	damaged.emit(dealt, source, dir)
	changed.emit(hp, max_hp)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		_set_shield(0.0)
		died.emit()
	return dealt


## Heals `amount` x Stats.heal_mult() (never above max_hp). Returns the hp restored.
func heal(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	return super.heal(amount * Stats.heal_mult())


## Adds a transient shield. Shields never stack: the larger amount wins; an equal or larger one also
## restarts the timer, a smaller one only extends the current shield's time. Returns the shield now held.
func add_shield(amount: float, seconds: float, source: String = "") -> float:
	if dead or amount <= 0.0 or seconds <= 0.0:
		return shield
	var a := minf(amount, MAX_SHIELD)
	if a >= shield:
		shield_max = a
		shield_source = source
		shield_left = seconds
		_set_shield(a)
	else:
		shield_left = maxf(shield_left, seconds)
	set_physics_process(shield > 0.0)
	return shield


func clear_shield() -> void:
	shield_left = 0.0
	_set_shield(0.0)


func has_shield() -> bool:
	return shield > 0.0


func reset() -> void:
	clear_shield()
	super.reset()


func _set_shield(v: float) -> void:
	var nv := clampf(v, 0.0, MAX_SHIELD)
	if is_equal_approx(nv, shield):
		return
	shield = nv
	if shield <= 0.0:
		shield_max = 0.0
		shield_source = ""
		shield_left = 0.0
		set_physics_process(false)
	shield_changed.emit(shield)
	Events.player_shield_changed.emit(shield)


func _physics_process(delta: float) -> void:
	if shield <= 0.0:
		set_physics_process(false)
		return
	shield_left -= delta
	if shield_left <= 0.0:
		_set_shield(0.0)
