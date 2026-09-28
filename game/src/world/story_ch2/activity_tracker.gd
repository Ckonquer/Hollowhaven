extends Node
## Chapter Two story & cross-area activity tracker (module C9). ONE instance lives under the Game autoload for
## the whole session (Game creates it once; see the module report for the one-line hook). It only listens to
## Events and forwards them to the pure, state-based helpers in story_ch2.gd:
##   area_loaded      -> back in the Reach after the Choir: ch2_returned_to_reach (step 18); the area's story
##                       dressing is ensured (if the region's build did not add it itself)
##   game_loaded      -> repair every derived flag / counter / journal note from the save (sync_state)
##   reward_granted   -> rw_ch2_feast: the Lanternwake outfit + furnishing finishes, synchronously (before the
##                       ending's save, so a crash during the ending still resumes with them)
##   lore_discovered  -> Tobin's / Hask's notes ("The Miner Who Came Back")
##   flag_set         -> the manor balcony shortcut ("The Long Way Home"); the Choir falling while in the Reach
##   crafted          -> different seasonal dishes cooked ("The Harvest Table")
##   structure_placed -> a table set for the festival ("The Harvest Table")
##   crop_harvested   -> a pumpkin grown and harvested ("A Pumpkin With a Face")
##   choice_made      -> accepting the Ward Stone's invitation shows the "Chapter Two" title card
## Nothing here grants a reward: the optional log / chapter log pay them once the objective flags hold.

const Story := preload("res://src/world/story_ch2/story_ch2.gd")
const CARD_DELAY := 2.2      # seconds after "Follow the lantern road" (after the reassurance line starts)

var _card_timer: SceneTreeTimer = null
var _debug_done := false      # debug builds: -- --story-ch2=<beat> applied once (story_ch2.debug_state)


func _ready() -> void:
	name = "StoryCh2Tracker"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("story_ch2_tracker")
	Events.area_loaded.connect(_on_area_loaded)
	Events.game_loaded.connect(_on_game_loaded)
	Events.reward_granted.connect(_on_reward_granted)
	Events.lore_discovered.connect(_on_lore)
	Events.flag_set.connect(_on_flag_set)
	Events.crafted.connect(_on_crafted)
	Events.structure_placed.connect(_on_structure_placed)
	Events.crop_harvested.connect(_on_crop_harvested)
	Events.choice_made.connect(_on_choice)
	if GameState.active:
		Story.sync_state()


func _exit_tree() -> void:
	for pair in [[Events.area_loaded, _on_area_loaded], [Events.game_loaded, _on_game_loaded],
			[Events.reward_granted, _on_reward_granted], [Events.lore_discovered, _on_lore],
			[Events.flag_set, _on_flag_set], [Events.crafted, _on_crafted],
			[Events.structure_placed, _on_structure_placed], [Events.crop_harvested, _on_crop_harvested],
			[Events.choice_made, _on_choice]]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)


func _on_area_loaded(area_id: String) -> void:
	if not GameState.active:
		return
	if not _debug_done and Debug.is_cheat_allowed() and Debug.has_arg("story-ch2"):
		_debug_done = true
		Story.debug_state(Debug.arg("story-ch2"))
	Story.sync_state()
	Story.note_area(area_id)
	var area: Node = Game.area
	if Game.area_id == area_id and area != null and is_instance_valid(area) and area is Node3D:
		Story.ensure_dressing(area as Node3D, area_id)


func _on_game_loaded() -> void:
	if GameState.active:
		Story.sync_state()


func _on_reward_granted(reward_id: String) -> void:
	if reward_id == Story.FEAST_REWARD:
		Story.sync_feast_unlocks()


func _on_lore(lore_id: String) -> void:
	Story.note_lore(lore_id)


func _on_flag_set(flag_name: String, value: Variant) -> void:
	Story.note_flag(flag_name, value)
	# The Choir fell while Krystal is already in the Reach (a debug clear): she is back on its roads.
	if flag_name == Story.CHOIR_FLAG and value and Game.area_id == Story.REACH_AREA:
		Story.note_area(Game.area_id)


func _on_crafted(_recipe_id: String, item_id: String, _count: int) -> void:
	Story.note_crafted(item_id)


func _on_structure_placed(_uid: String, structure_id: String) -> void:
	Story.note_structure(structure_id)


func _on_crop_harvested(_uid: String, crop_id: String, _count: int) -> void:
	Story.note_crop(crop_id)


func _on_choice(choice_id: String, option: String) -> void:
	if choice_id != Story.ACCEPT_CHOICE or option != "follow" or not is_inside_tree():
		return
	_card_timer = get_tree().create_timer(CARD_DELAY)
	_card_timer.timeout.connect(_show_chapter_card)


## "Chapter Two - The Lanterns of Hallowmere" (chapter_card.gd picks its autumn style from the title).
func _show_chapter_card() -> void:
	_card_timer = null
	var ui: Node = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("show_chapter_card"):
		ui.show_chapter_card(Story.CARD_TITLE, Story.CARD_SUBTITLE)
