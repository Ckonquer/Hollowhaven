extends RefCounted
## Chapter One: "The Dimming Ward". A linear chain of short, contextual steps.
## Objectives are STATE checks (evaluated against GameState), so they survive save/load and
## never need to observe an event live. Types:
##   {"type": "flag", "flag": "x"}                        GameState.get_flag(x) is truthy
##   {"type": "item", "item": "wood", "count": 3}          inventory + key pouch count >= count
##   {"type": "item_any", "items": [...], "count": 2}      sum of these items >= count
##   {"type": "placed", "structure": "workbench", "count": 1}
##   {"type": "befriended", "creature": "mochi"}
##   {"type": "counter", "counter": "trees_felled", "count": 2, "since_start": true}
## target: landmark id (data/world_layout.gd) used for the map marker; "" = none.
## hint: onboarding hint shown once when the step starts (key names are filled by the UI:
##       {interact} {attack} {inventory} {craft} {build} {sprint} {jump} {dodge} {lantern} {journal} {map} {use}
##       and {move}, the four movement keys)
## on_complete: {"give": {item: count}, "flags": [...], "message": "..."}
## skip_if_flag: optional flag; once it is set the step counts as done and passes silently (no toasts or
##       hint). Used by the story steps that stop making sense once the Heartseed is back ("ward_restored"),
##       because nothing stops Krystal from running the dungeon before the tracker sends her there.
##       Only use it on steps without on_complete rewards the player should notice.

const STEPS := [
	{"id": "wake", "title": "A Dim Haven", "target": "haven", "skip_if_flag": "ward_restored",
		"text": "You've arrived at the old clearing. At its heart stands a mossy Ward Stone, its light barely flickering.",
		"hint": "Move with {move} and look with the mouse. Walk up to the Ward Stone and press {interact} to read it.",
		"objectives": [{"type": "flag", "flag": "read_ward_intro", "label": "Read the Ward Stone"}],
		"on_complete": {}},
	{"id": "gather_basics", "title": "Gather Supplies", "target": "haven",
		"text": "A home needs tools, and tools need materials. Sticks, stones and grass lie all around the clearing.",
		"hint": "Press {interact} to pick up sticks and stones, and to pull tall grass for fiber.",
		"objectives": [
			{"type": "item", "item": "wood", "count": 3, "label": "Collect Wood (sticks)"},
			{"type": "item", "item": "stone", "count": 2, "label": "Collect Stone"},
			{"type": "item", "item": "fiber", "count": 2, "label": "Collect Plant Fiber"}],
		"on_complete": {}},
	{"id": "craft_axe", "title": "A Proper Tool", "target": "",
		"text": "Bind stone to wood with fiber and you'll have an axe.",
		"hint": "Press {craft} to open crafting. Select the Stone Axe and press Craft.",
		"objectives": [{"type": "item", "item": "stone_axe", "count": 1, "label": "Craft a Stone Axe"}],
		"on_complete": {}},
	{"id": "chop", "title": "Timber!", "target": "",
		"text": "The trees around the Haven will give plenty of wood. They grow back, too.",
		"hint": "Face a tree and press {attack} to chop it. Your axe is used automatically.",
		"objectives": [
			{"type": "counter", "counter": "trees_felled", "count": 2, "since_start": true, "label": "Fell trees"},
			{"type": "item", "item": "wood", "count": 10, "label": "Hold 10 Wood"}],
		"on_complete": {}},
	{"id": "workbench", "title": "A Place to Work", "target": "haven",
		"text": "A workbench at the Haven will let you make sturdier things.",
		"hint": "Craft a Workbench, then press {build} to enter build mode. Place it inside the Haven.",
		"objectives": [{"type": "placed", "structure": "workbench", "count": 1, "label": "Place a Workbench at the Haven"}],
		"on_complete": {}},
	{"id": "mochi", "title": "A Timid Friend", "target": "glade",
		"text": "Something has been squeaking in the Berry Glade to the west. Perhaps it's hungry?",
		"hint": "Pick berries from bushes with {interact}. Approach the creature slowly and offer 3 berries.",
		"objectives": [{"type": "befriended", "creature": "mochi", "label": "Befriend the creature in the Berry Glade"}],
		"on_complete": {"give": {"sweetroot_seeds": 3}, "message": "Mochi dug up a little pouch of Sweetroot Seeds for you!"}},
	{"id": "pebble", "title": "Something Stuck", "target": "quarry",
		"text": "Across the stream, at the quarry, a boulder keeps grumbling. Boulders aren't supposed to grumble.",
		"hint": "Craft a Stone Pickaxe. Mine rocks and ore with {attack}.",
		"objectives": [
			{"type": "item", "item": "stone_pickaxe", "count": 1, "label": "Craft a Stone Pickaxe"},
			{"type": "befriended", "creature": "pebble", "label": "Free whatever is under the quarry boulder"}],
		"on_complete": {"give": {"copper_ore": 2}, "message": "Pebble shows you where the best copper veins are."}},
	{"id": "home", "title": "Make It Home", "target": "haven",
		"text": "A bed to rest in and a garden to tend. The Haven is starting to feel like home.",
		"hint": "Build a Cozy Bed and a Crop Plot. Select seeds on your hotbar and press {interact} on the plot to plant them.",
		"objectives": [
			{"type": "placed", "structure": "bed", "count": 1, "label": "Place a Cozy Bed"},
			{"type": "placed", "structure": "crop_plot", "count": 1, "label": "Place a Crop Plot"},
			{"type": "counter", "counter": "crops_planted", "count": 1, "since_start": false, "label": "Plant seeds"}],
		"on_complete": {"message": "Sleeping in your bed sets your return point and saves your journey."}},
	{"id": "lumi", "title": "Lights in the Ruin", "target": "ruin",
		"text": "At night a small light flickers in the old ruin to the north. Grumpy Bramblings have been gathering around it.",
		"hint": "A Copper Sword makes fighting easier. Enemies wiggle before they attack. Press {dodge} to roll away.",
		"objectives": [
			{"type": "flag", "flag": "ruin_cleared", "label": "Drive the Bramblings from the ruin"},
			{"type": "befriended", "creature": "lumi", "label": "Reach the little light"}],
		"on_complete": {}},
	{"id": "prepare", "title": "The Ward Remembers", "target": "haven", "skip_if_flag": "ward_restored",
		"text": "The Ward Stone's light is failing. Its heart, the Heartseed, was carried into the old mine long ago. Something down there must not be allowed out. You'll need light and supplies.",
		"hint": "Craft a Lantern at the Workbench and press {lantern} to raise it. Cook or craft healing food.",
		"objectives": [
			{"type": "flag", "flag": "read_ward_warning", "label": "Listen to the Ward Stone"},
			{"type": "item", "item": "lantern", "count": 1, "label": "Craft a Lantern"},
			{"type": "item_any", "items": ["berry_snack", "hearty_stew", "glowcap_skewer"], "count": 2, "label": "Prepare 2 healing meals"}],
		"on_complete": {}},
	{"id": "descend", "title": "The Hollow Mine", "target": "mine_mouth", "skip_if_flag": "ward_restored",
		"text": "The old mine lies north-east, where the stream begins. Its entrance was sealed with rubble long ago.",
		"hint": "Clear the rubble with your pickaxe. You can adjust horror comfort settings any time from the pause menu.",
		"objectives": [
			{"type": "flag", "flag": "mine_opened", "label": "Clear the mine entrance"},
			{"type": "flag", "flag": "entered_below", "label": "Enter the mine"}],
		"on_complete": {}},
	{"id": "old_mine", "title": "The Old Mine", "target": "", "skip_if_flag": "ward_restored",
		"text": "The miners left in a hurry. The lower gate is locked; the foreman kept the key.",
		"hint": "Light lanterns on the walls with {interact} to save and set your return point.",
		"objectives": [{"type": "item", "item": "foreman_key", "count": 1, "label": "Find the Foreman's Key"}],
		"on_complete": {}},
	{"id": "deeper", "title": "Deeper Still", "target": "", "skip_if_flag": "ward_restored",
		"text": "Below the mine lie ruins far older than the miners. Something has been walking here.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "reached_silk_hollows", "label": "Find a way deeper"}],
		"on_complete": {}},
	{"id": "silk", "title": "The Silk Hollows", "target": "", "skip_if_flag": "ward_restored",
		"text": "The Heartseed is somewhere in the webbed hollows. Keep your light close.",
		"alt_title": "The Pale Hollows",
		"alt_text": "The Heartseed is somewhere in the pale, root-choked hollows. Keep your light close.",
		"hint": "Light drives it back. Listen for the rattle before it strikes.",
		"alt_hint": "Light drives it back. Listen for the whisper before it strikes.",
		"objectives": [{"type": "item", "item": "heartseed", "count": 1, "label": "Reclaim the Heartseed"}],
		"on_complete": {}},
	{"id": "return", "title": "Bring Back the Light", "target": "haven",
		"text": "The Heartseed beats warmly in your hands. Take it home.",
		"hint": "",
		"objectives": [{"type": "flag", "flag": "ward_restored", "label": "Return the Heartseed to the Ward Stone"}],
		"on_complete": {"give": {"haven_banner": 1}, "flags": ["chapter_one_complete"], "message": "The Haven is safe. New recipe: Heartbloom Lamp."}},
	{"id": "free_play", "title": "Krystal's Haven", "target": "",
		"text": "Chapter One is complete. The woods are yours to enjoy: build, farm, decorate and spend time with your friends.",
		"hint": "",
		"objectives": [
			{"type": "counter", "counter": "max_bond", "count": 5, "since_start": false, "label": "Reach max bond with a companion (optional)"},
			{"type": "placed", "structure": "heartbloom_lamp", "count": 1, "label": "Build a Heartbloom Lamp (optional)"}],
		"optional": true,
		"on_complete": {"message": "You've done it all, and the Haven has never looked lovelier."}},
]
