extends RefCounted
## Equipment rules (docs/CHAPTER_TWO_SPEC.md sections 4.2, 5, 8; MP 5.1). Pure data + one documented reference
## combiner; the live stat layer is src/core/stats.gd (equipment module) and reads these values through ItemDB.
##
## Slots: armor items (cat "armor") carry `slot` head | body | boots; charms (cat "charm") use "charm".
## Equipped item ids move OUT of the backpack into GameState.equipment (transactional equip / unequip).
## Appearance is separate: clothing never changes these numbers ("show equipped armor" is only a visual option).
##
## COMBINATION ORDER (one hit, processed exactly once):
##   1. invulnerable (dodge / hurt i-frames, safe zone)  -> the hit does nothing, nothing below runs
##   2. armor = SUM of the equipped pieces' `reduction`  (pieces add up WITHIN armor; full sets = SETS totals)
##   3. independent sources MULTIPLY:
##        reduction = 1 - (1 - armor) * (1 - companion) * (1 - charm) * (1 - food/other)
##      e.g. 20% ironwood armor with Pebble's 10% passive = 1 - 0.8 * 0.9 = 28%, not 30%
##   4. reduction = min(reduction, REDUCTION_CAP)                       (45%)
##   5. mitigated = raw * (1 - reduction). No damage type bypasses armor in this release (BYPASS_ARMOR is empty).
##   6. the transient shield (GameState.player_shield(), Pebble's Stoneheart) absorbs `mitigated` AFTER mitigation
##   7. Health.apply_damage(what is left)
## Movement: move_mult = 1 + min(sum of move bonuses (Lumi passive, Glimmerstep, charm), MOVE_CAP). Bonuses add.

const SLOTS := ["head", "body", "boots", "charm"]
const ARMOR_SLOTS := ["head", "body", "boots"]

const REDUCTION_CAP := 0.45
const MOVE_CAP := 0.30
const BYPASS_ARMOR: Array = []

## Share of a set's full reduction carried by each piece (transparent split: 25 / 50 / 25).
const PIECE_SHARE := {"head": 0.25, "body": 0.5, "boots": 0.25}

## Armor sets. `total` = full-set physical reduction (MP 5.1); each piece's item `reduction` = total * share.
const SETS := {
	"padded": {"name": "Padded", "tier": 1, "total": 0.06, "pieces": {"head": "padded_hood", "body": "padded_vest", "boots": "padded_boots"}},
	"copperwood": {"name": "Copperwood", "tier": 2, "total": 0.12, "pieces": {"head": "copperwood_hood", "body": "copperwood_vest", "boots": "copperwood_boots"}},
	"ironwood": {"name": "Ironwood", "tier": 3, "total": 0.2, "pieces": {"head": "ironwood_helm", "body": "ironwood_mail", "boots": "ironwood_boots"}},
	"moonsteel": {"name": "Moonsteel", "tier": 4, "total": 0.26, "pieces": {"head": "moonsteel_helm", "body": "moonsteel_mail", "boots": "moonsteel_boots"}},
}

## Tier names (tools, weapons, armor, charms).
const TIERS := {1: "Familiar", 2: "Copperwood", 3: "Ironwood", 4: "Moonsteel"}

## Charm effect ids, how they combine and their caps (after adding every source of the same effect).
##   gather          fraction of extra harvest power per hit (with mastery: GATHER_BONUS_CAP in data/mastery.gd)
##   stamina_save    fraction less stamina for sprint / roll / swing / wand casts
##   heal_received   fraction more healing received (food, Bloomguard, bed not included)
##   move            movement bonus, shares MOVE_CAP with companion buffs
##   lantern_radius  fraction larger lantern light radius ("darkness comfort")
const EFFECTS := {
	"gather": {"name": "Gathering", "cap": 0.25, "combine": "add"},
	"stamina_save": {"name": "Stamina", "cap": 0.25, "combine": "add"},
	"heal_received": {"name": "Healing", "cap": 0.25, "combine": "add"},
	"move": {"name": "Speed", "cap": 0.3, "combine": "add"},
	"lantern_radius": {"name": "Lantern", "cap": 0.3, "combine": "add"},
}

## Companion basic-attack damage multiplier from Krystal's best owned weapon tier (stable, modest; never the
## live selected tool): see data/companion_skills.gd.
## Wands: shared stamina, finite range, lower sustained damage than the melee weapon of the same tier.
const WAND_RULES := {"max_projectiles_alive": 3, "requires_line_of_sight": true, "auto_select": false}


## Reference combiner for step 3-4 above (the stat layer may call it): `sources` are independent reduction
## fractions, e.g. [armor_sum, pebble_passive, charm]. Returns the capped total reduction in [0, REDUCTION_CAP].
static func combine_reduction(sources: Array) -> float:
	var keep := 1.0
	for s in sources:
		keep *= 1.0 - clampf(float(s), 0.0, 1.0)
	return clampf(1.0 - keep, 0.0, REDUCTION_CAP)
