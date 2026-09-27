extends RefCounted
## Companion creature definitions (personality rules are authored; no language model).
## bond: xp needed per level (5 levels). Bond xp sources: pet (once per in-game day), feed favourite,
## working together (gather/mine assists), adventures (entering new zones together).

const BOND_XP_PER_LEVEL := [0, 10, 25, 45, 70, 100]   # cumulative xp for levels 0..5

const CREATURES := {
	"mochi": {
		"name": "Mochi",
		"species": "Puffcap",
		"blurb": "A round, timid mushroom sprite who loves berries.",
		"favorite_food": "berries",
		"befriend": {"type": "offer_item", "item": "berries", "count": 3},
		"ability": "forager",            # picks nearby berries/fiber while following; tends crops at home
		"move_speed": 4.6, "follow_distance": 2.6,
		"enters_below": false,           # waits at the mine threshold (intentional, readable)
		"brave": 0.1,
		"voice": "mochi",               # sound prefix: mochi_chirp, mochi_happy, mochi_scared ...
		"colors": {"cap": Color("e4665c"), "spots": Color("fff4e0"), "body": Color("f6e7cf")},
	},
	"pebble": {
		"name": "Pebble",
		"species": "Cobblet",
		"blurb": "A small, overconfident stone creature devoted to rocks.",
		"favorite_food": "shiny_pebble",
		"befriend": {"type": "free_from_boulder"},   # mine the boulder pinning it at the quarry
		"ability": "miner",              # bonus stone/ore when you mine near it; brings small gifts
		"move_speed": 4.2, "follow_distance": 2.8,
		"enters_below": true,
		"brave": 1.0,
		"voice": "pebble",
		"colors": {"body": Color("9a948a"), "moss": Color("7dbb5b"), "eyes": Color("2b2a3f")},
	},
	"lumi": {
		"name": "Lumi",
		"species": "Glimmerkit",
		"blurb": "A gentle, luminous woodland creature who sees what others miss.",
		"favorite_food": "sweetroot",
		"befriend": {"type": "rescue", "flag": "ruin_cleared"},   # clear the Bramblings from the ruin, then approach
		"ability": "lightbearer",        # soft light; notices threats before the player and warns
		"move_speed": 4.8, "follow_distance": 2.4,
		"enters_below": true,
		"brave": 0.4,
		"voice": "lumi",
		"light": {"color": Color("ffd98a"), "energy": 1.2, "range": 6.5},
		"colors": {"body": Color("fff1c9"), "glow": Color("ffd98a"), "ears": Color("f7c35c")},
	},
}

## Short original lines, keyed by context. {name} is replaced by the player name (Krystal).
## Companions "speak" through little descriptive lines rather than full dialogue.
const LINES := {
	"mochi": {
		"befriend": ["Mochi nibbles a berry, then bumps its cap against your boot. You've made a friend!"],
		"pet": ["Mochi wiggles happily.", "Mochi makes a tiny, contented squeak.", "Mochi leans into your hand, cap-first."],
		"follow": ["Mochi hops after you.", "Mochi bounces along behind {name}."],
		"wait": ["Mochi sits down and waits patiently."],
		"home": ["Mochi scurries off toward the Haven."],
		"gather": ["Mochi found some berries!", "Mochi proudly offers a bundle of fiber."],
		"scared": ["Mochi hides behind you, trembling.", "Mochi squeaks and ducks behind {name}."],
		"refuse_below": ["Mochi stops at the mine's mouth and trembles. It will wait for you here."],
		"reunite": ["Mochi bounces over, relieved to see you!"],
		"tend": ["Mochi pats the soil around the sprouts."],
		"celebrate": ["Mochi spins in circles, spores sparkling!"],
		"idle": ["Mochi sniffs a flower.", "Mochi hums a little mushroom tune."],
		"idle_below": ["Mochi stays very close to you."],
	},
	"pebble": {
		"befriend": ["The boulder cracks apart and a little stone creature tumbles out. It salutes you with great seriousness. Pebble has joined you!"],
		"pet": ["Pebble puffs out its chest proudly.", "Pebble clacks happily.", "Pebble pretends it doesn't enjoy that. It does."],
		"follow": ["Pebble marches after you, very bravely.", "Pebble falls in step beside {name}."],
		"wait": ["Pebble plants itself firmly. Nothing will move it now."],
		"home": ["Pebble rolls off toward the Haven."],
		"mine": ["Pebble headbutts the rock! Extra stone!", "Pebble helps! Clonk!"],
		"gift": ["Pebble presents you with a Shiny Pebble. It's clearly the best one.", "Pebble found a shiny pebble just for you."],
		"brave": ["Pebble charges at the enemy! ...and bounces off. It is undeterred.", "Pebble growls a tiny gravelly growl."],
		"dizzy": ["Pebble is seeing stars, but insists it's fine."],
		"celebrate": ["Pebble does a very dignified victory stomp."],
		"idle": ["Pebble inspects a rock with deep respect.", "Pebble is polishing itself."],
		"idle_below": ["Pebble taps the tunnel wall approvingly. Good rock.", "Pebble marches on, pretending not to be nervous."],
	},
	"lumi": {
		"befriend": ["The little light creeps out of the ruin and settles beside you, glowing warmly. Lumi trusts you now."],
		"pet": ["Lumi's glow brightens softly.", "Lumi chimes, a sound like a tiny bell.", "Lumi curls its tail around your wrist."],
		"follow": ["Lumi floats along at your shoulder.", "Lumi follows {name}, lighting the way."],
		"wait": ["Lumi settles down, glowing gently."],
		"home": ["Lumi drifts back toward the Haven."],
		"notice": ["Lumi stops, staring into the dark.", "Lumi's light dims. It has noticed something.", "Lumi goes very still."],
		"warn": ["Lumi presses close behind you.", "Lumi chimes a quiet warning."],
		"calm": ["Lumi's glow steadies.", "Lumi relaxes a little."],
		"celebrate": ["Lumi sparkles like a tiny festival of lights!"],
		"idle": ["Lumi chases a firefly.", "Lumi watches the leaves with great interest."],
		"idle_below": ["Lumi's glow brushes the old stone walls.", "Lumi hums softly to keep the dark at bay."],
	},
}
