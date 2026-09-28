extends RefCounted
## Companion combat and support numbers: the ONE table for MP sections 6.2 / 6.3 (docs/CHAPTER_TWO_SPEC.md 4.6).
## Starting values for playtesting; change them here and nowhere else. Read through ItemDB.companion_skill(id)
## (base values) or ItemDB.companion_skill_at(id, bond_level) (perks of every reached bond level applied).
##
## Rules the systems follow (MP 6.1):
##  * Only GameState.active_companion counts, and only while present: same area, follower, within PRESENCE_RANGE
##    of Krystal (Game.companion_present(id)). A pet waiting at home never fires invisible attacks.
##  * Passives never stack across pets (one follower). Skill cooldown is shared by autocast and the manual
##    Companion Skill action (one cooldown, saved as skill_ready_at). Pause suspends timers.
##  * Basic attacks need line of sight; projectiles never pass through rooms or scenery. No XP for hitting
##    invulnerable bosses, the practice dummy or friendly objects. Companions are never damaged permanently.
##  * Basic damage is multiplied by GEAR_TIER_DAMAGE[best owned weapon tier of Krystal] (stable, modest).
##  * Signature numbers under "perks" REPLACE the base value of the same key (they are the new totals).
##
## Keys: passive {effect: value}; basic {kind melee|projectile, name, damage, interval (s), range (m), ...};
## signature {id, name, cooldown (s), ...values}; perks {bond_level: {"passive"?: {...}, "signature"?: {...},
## "basic"?: {...}, "ribbon"?: bool, "affection"?: animation id, "text": shown in the Friends panel}}.

const MOVE_BUFF_CAP := 0.30
const REDUCTION_CAP := 0.45
const PRESENCE_RANGE := 25.0
const PERK_LEVELS := [2, 3, 5]
const COMBAT_MODES := ["assist", "close"]   # the existing "wait" command still parks the companion
const DEFAULT_MODE := "assist"
## Basic-attack damage multiplier by Krystal's best owned weapon tier (1 stone .. 4 moonsteel).
const GEAR_TIER_DAMAGE := {1: 1.0, 2: 1.1, 3: 1.2, 4: 1.3}
## Autocast defaults (a setting may turn automatic attacks off while support stays on).
const AUTOCAST := {"enabled": true, "min_interval": 1.5}

const SKILLS := {
	"mochi": {
		"role": "Gentle healer",
		"passive": {"heal_received": 0.08},
		"passive_text": "+8% healing received while Mochi is with you. Still forages as before.",
		"basic": {"kind": "projectile", "name": "Spore Puff", "damage": 4.0, "interval": 2.4, "range": 9.0, "projectile_speed": 8.0, "requires_los": true},
		"signature": {"id": "bloomguard", "name": "Bloomguard", "cooldown": 25.0, "heal": 18.0, "duration": 6.0,
			"autocast_hp_ratio": 0.6, "no_overheal": true,
			"text": "Restores 18 health over 6 s. Cast automatically when you are meaningfully hurt."},
		"perks": {
			2: {"passive": {"heal_received": 0.1}, "text": "Healing bonus rises to 10%."},
			3: {"signature": {"cleanse_slow": 1}, "text": "Bloomguard also clears one clinging web or root slow.",
				"alt_text": "Bloomguard also clears one clinging root slow."},
			5: {"signature": {"heal": 22.0}, "ribbon": true, "affection": "mochi_twirl", "text": "Bloomguard heals 22. Mochi earns a companion ribbon."},
		},
	},
	"pebble": {
		"role": "Brave protector",
		"passive": {"damage_reduction": 0.1},
		"passive_text": "10% less physical damage while Pebble is with you (multiplies with armor). Still helps you mine.",
		"basic": {"kind": "melee", "name": "Stone Bump", "damage": 8.0, "interval": 2.4, "range": 1.8, "requires_los": true},
		"signature": {"id": "stoneheart", "name": "Stoneheart", "cooldown": 26.0, "shield": 25.0, "duration": 6.0,
			"stagger": 0.8, "stagger_bosses": false, "autocast_threat_range": 6.0,
			"text": "A 25-point shield for up to 6 s. Briefly staggers ordinary enemies nearby, never bosses."},
		"perks": {
			2: {"signature": {"shield": 28.0}, "text": "Stoneheart shield rises to 28."},
			3: {"signature": {"resist_knockback": 1}, "text": "Stoneheart also shrugs off one knockback."},
			5: {"signature": {"shield": 32.0}, "ribbon": true, "affection": "pebble_hug", "text": "Stoneheart shield reaches 32. Pebble earns a companion ribbon."},
		},
	},
	"lumi": {
		"role": "Swift lightbearer",
		"passive": {"move": 0.08},
		"passive_text": "+8% movement speed while Lumi is with you, plus its light and early warnings.",
		"basic": {"kind": "projectile", "name": "Light Bolt", "damage": 6.0, "interval": 2.2, "range": 10.0, "projectile_speed": 12.0, "requires_los": true},
		"signature": {"id": "glimmerstep", "name": "Glimmerstep", "cooldown": 24.0, "move": 0.12, "duration": 4.0,
			"pulse_radius": 6.0, "expose_seconds": 3.0,
			"text": "+12% movement for 4 s (within the 30% cap) and a light pulse that exposes nearby shadow enemies."},
		"perks": {
			2: {"passive": {"move": 0.1}, "text": "Lumi's speed bonus rises to 10%."},
			3: {"signature": {"sprint_stamina_save": 0.5}, "text": "During Glimmerstep, sprinting costs half the stamina."},
			5: {"signature": {"duration": 6.0}, "ribbon": true, "affection": "lumi_glow_spin", "text": "Glimmerstep lasts 6 s. Lumi earns a companion ribbon."},
		},
	},
	# Optional fourth friend (MP 15, bonus scope). Data only: the creature itself is not in data/creatures.gd yet.
	"pipkin": {
		"optional": true,
		"role": "Treasure scout",
		"passive": {"cache_sense": 30.0},
		"passive_text": "A little sparkle points toward undiscovered optional caches within 30 m.",
		"basic": {"kind": "melee", "name": "Swoop", "damage": 5.0, "interval": 2.4, "range": 2.0, "requires_los": true},
		"signature": {"id": "moon_mote", "name": "Moon Mote", "cooldown": 25.0, "mark_seconds": 6.0, "next_hit_bonus": 0.25,
			"no_boss_loot": true, "text": "Marks one enemy: Krystal's next hit on it deals 25% more."},
		"perks": {
			2: {"passive": {"cache_sense": 36.0}, "text": "Senses caches from 36 m."},
			3: {"signature": {"mark_seconds": 8.0}, "text": "Moon Mote lasts 8 s."},
			5: {"signature": {"next_hit_bonus": 0.3}, "ribbon": true, "affection": "pipkin_hang", "text": "Moon Mote bonus 30%. Pipkin earns a companion ribbon."},
		},
	},
}
