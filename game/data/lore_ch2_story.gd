extends RefCounted
## Chapter Two story notes (module C9: story glue and the ending; docs/CHAPTER_TWO_SPEC.md §10). Journal
## entries for the three closing beats of "The Lanterns of Hallowmere" (MP §11 steps 18-20, MP §17):
##   lore_ch2_every_road  - the festival roads wake after the Choir (arriving in the Reach, ch2_returned_to_reach)
##   lore_ch2_homecoming  - the Ward Stone's welcome home (ch2_homecoming)
##   lore_ch2_lanternwake - the Lanternwake celebration and the ending card (chapter_two_complete)
## Discovered by src/world/story_ch2/story_ch2.gd (GameState.discover_lore) when those flags are set, and
## repaired from the flags on load, so a save that crashed mid-ending still gets them. Read through LoreDB.
## Nothing here is spider-like, so no alt_ text is needed.

const ORDER := ["lore_ch2_every_road", "lore_ch2_homecoming", "lore_ch2_lanternwake"]

const LORE := {
	"lore_ch2_every_road": {
		"title": "Lanterns on Every Road",
		"text": "When the Choir fell quiet, the festival lamps along the roads woke one after another, as if somebody had finally remembered whose turn it was to light them. Travellers used to follow them to the Commons. Now they are yours to follow.",
	},
	"lore_ch2_homecoming": {
		"title": "The Ward Stone's Welcome",
		"text": "The runes that once asked you to carry light have changed their words. They say only: Light kept. Roads found. Welcome home, Krystal.",
	},
	"lore_ch2_lanternwake": {
		"title": "The Lanternwake",
		"text": "The lanterns shine beyond the trees. The quiet below is quiet again. There are pumpkins to plant, walls to raise, and friends waiting by the fire. The road will keep. Tonight is yours.",
	},
}
