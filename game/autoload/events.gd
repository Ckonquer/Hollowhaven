extends Node
## Global signal bus. Emit from anywhere: Events.notify.emit("Hello", "info").
## Keep this file declarative: no state, no logic.

# --- Inventory & items ---------------------------------------------------
signal inventory_changed
signal item_added(item_id: String, count: int)            # entered player inventory (any source)
signal item_removed(item_id: String, count: int)
signal item_overflow_dropped(item_id: String, count: int, position: Vector3)
signal key_item_added(item_id: String)
signal hotbar_selected(index: int)
signal crafted(recipe_id: String, item_id: String, count: int)
signal item_consumed(item_id: String)
signal recipe_unlocked(recipe_id: String)

# --- Gathering & world ---------------------------------------------------
signal harvested(node_kind: String, item_id: String, count: int, position: Vector3)  # node_kind: tree/rock/ore/bush/grass/stick/stone/glowcap/silk/crystal
signal tree_felled(position: Vector3)
signal flag_set(flag: String, value: Variant)
signal counter_changed(counter: String, value: int)
signal lore_discovered(lore_id: String)
signal time_of_day_changed(day: int, time: float)           # emitted ~once per in-game minute
signal day_started(day: int)

# --- Building & farming --------------------------------------------------
signal structure_placed(uid: String, structure_id: String)
signal structure_removed(uid: String, structure_id: String)
signal build_mode_changed(active: bool)
signal crop_planted(uid: String, crop_id: String)
signal crop_harvested(uid: String, crop_id: String, count: int)

# --- Companions -----------------------------------------------------------
signal companion_befriended(companion_id: String)
signal companion_assignment_changed(companion_id: String, assignment: String)
signal companion_bond_changed(companion_id: String, level: int)
signal companion_reaction(companion_id: String, reaction: String)

# --- Combat ----------------------------------------------------------------
signal player_damaged(amount: float, source: Node)
signal player_healed(amount: float)
signal player_died
signal player_respawned
signal enemy_killed(enemy_id: String, position: Vector3)
signal boss_defeated(boss_id: String)
signal boss_health_changed(boss_id: String, hp: float, max_hp: float)   # hp < 0 hides the bar

# --- Quests & story -------------------------------------------------------
signal quest_step_started(step_id: String)
signal quest_step_completed(step_id: String)
signal objectives_changed
signal chapter_completed
signal hint(hint_id: String, text: String)                 # onboarding hint (HUD shows once per id)

# --- Areas & flow ----------------------------------------------------------
signal area_loaded(area_id: String)
signal area_exiting(area_id: String)
signal zone_entered(zone_id: String)                        # haven/glade/quarry/ruin/meadow/mine_mouth/mine/ruins/silk/boss
signal safe_zone_changed(in_safe: bool)
signal paused_changed(paused: bool)
signal ui_stack_changed(open_count: int)
signal game_saved(ok: bool)
signal game_loaded
signal settings_changed(key: String)
signal cutscene_changed(active: bool)

# --- Horror -----------------------------------------------------------------
signal horror_event(event_id: String, data: Dictionary)     # also used for authored moments: "authored:<id>"
signal horror_state_changed(state: String)                  # calm/unease/anticipation/encounter/recovery

# --- UI messaging & feel ----------------------------------------------------
signal notify(text: String, kind: String)                   # kind: info/success/warn/item/quest/bond
signal say(speaker: String, text: String, duration: float)  # speech line / inscription (bottom dialog)
signal caption(text: String)                                # sound caption (only shown if Settings captions on)
signal camera_shake(strength: float, duration: float)       # consumers must scale by Settings
signal screen_flash(color: Color, duration: float)          # consumers must respect reduce_flashing
signal hitstop(duration: float)

# --- Build mode UI ---------------------------------------------------------------------
signal build_selection_changed(item_id: String)                  # "" = nothing selected
signal build_placement_state(valid: bool, reason: String)       # live validity of the ghost preview

# --- Chapter Two & progression (docs/CHAPTER_TWO_SPEC.md) -----------------------------------------
signal chapter2_step_started(step_id: String)
signal chapter2_step_completed(step_id: String)
signal chapter2_completed
signal optional_goal_completed(goal_id: String)
signal reward_granted(reward_id: String)
signal mastery_changed(track: String, xp: int, rank: int)
signal appearance_changed
signal equipment_changed(slot: String, item_id: String)
signal stats_changed
signal capacity_changed(kind: String, size: int)
signal station_queue_changed(uid: String)
signal choice_made(choice_id: String, option: String)
signal landmark_discovered(area_id: String, landmark_id: String)
signal arch_lit(arch_id: String)
signal trial_started(trial_id: String)
signal trial_ended(trial_id: String, won: bool)

# --- Companion combat -----------------------------------------------------------------------------
signal companion_skill_used(companion_id: String, skill_id: String)
signal companion_skill_ready(companion_id: String)
signal companion_attacked(companion_id: String, target: Node)
signal player_shield_changed(amount: float)

# --- Combat state & music -------------------------------------------------------------------------
signal combat_state_changed(in_combat: bool)                 # ordinary fights (threat nearby & engaged)
signal boss_phase_changed(boss_id: String, phase: int)
signal boss_encounter_changed(boss_id: String, active: bool)  # arena engaged / ended (music, saving)
signal music_cue_changed(cue_id: String)
signal music_context_changed(context: String)                 # optional hint from areas (e.g. "pond")
