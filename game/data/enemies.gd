extends RefCounted
## Enemy definitions. All values are tuned for "friendly but real" combat.
## telegraph = seconds of visible/audible wind-up before an attack lands (readable attacks).
## recover   = seconds the enemy is open to punishment after attacking.
## Damage is scaled at runtime by horror intensity for underground threats (see data/horror_events.gd INTENSITY).

const ENEMIES := {
	"brambling": {
		"name": "Brambling", "alt_name": "",
		"hp": 30.0, "damage": 10.0, "speed": 3.2, "chase_speed": 4.4,
		"aggro_radius": 9.0, "leash_radius": 22.0, "attack_range": 1.8,
		"telegraph": 0.7, "recover": 1.1, "cooldown": 1.6, "knockback": 5.0,
		"drops": [{"item": "fiber", "min": 1, "max": 3, "chance": 1.0}, {"item": "berries", "min": 1, "max": 2, "chance": 0.5}],
		"sound": "brambling", "area": "surface",
		"desc": "A grumpy walking thornball. It wiggles before it pounces.",
	},
	"gloomling": {
		"name": "Gloomling", "alt_name": "",
		"hp": 40.0, "damage": 12.0, "speed": 3.0, "chase_speed": 4.8,
		"aggro_radius": 11.0, "leash_radius": 26.0, "attack_range": 1.9,
		"telegraph": 0.8, "recover": 1.2, "cooldown": 1.8, "knockback": 5.5,
		"light_fear": true,                # hesitates in lantern light and takes double damage while "exposed"
		"drops": [{"item": "glowcap", "min": 0, "max": 1, "chance": 0.6}, {"item": "echo_shard", "min": 1, "max": 1, "chance": 0.25}],
		"sound": "gloomling", "area": "below",
		"desc": "A shadow with glowing eyes. Its eyes flare before it swipes. It hates bright light.",
	},
	"weaver": {
		"name": "The Weaver", "alt_name": "The Hollow Shade",
		"hp": 999.0, "damage": 18.0, "speed": 5.0, "chase_speed": 6.0,
		"telegraph": 1.0, "recover": 1.6, "cooldown": 4.0, "knockback": 6.0,
		"light_fear": true, "stalker": true,
		"sound": "weaver", "alt_sound": "shade", "area": "below",
		"desc": "Something that lives in the Silk Hollows. It rattles before it strikes and flees from strong light.",
	},
	"weaver_matron": {
		"name": "The Weaver Matron", "alt_name": "The Hollow Mother",
		"hp": 240.0, "damage": 20.0, "speed": 5.0,
		"telegraph": 1.2, "recover": 2.5, "cooldown": 3.0, "knockback": 7.0,
		"light_fear": true, "boss": true,
		"sound": "weaver", "alt_sound": "shade", "area": "below",
		"desc": "The guardian that took the Heartseed. Light the braziers to drive it from the ceiling.",
	},
}
