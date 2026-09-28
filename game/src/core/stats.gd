extends RefCounted
## Krystal's derived stats (docs/CHAPTER_TWO_SPEC.md section 5 and 9, MP 5.1 / 6.2 / 16). Owner: equipment module.
##   const Stats := preload("res://src/core/stats.gd")
##   Stats.damage_reduction()      # 0 .. 0.45: armor pieces ADD, independent sources MULTIPLY, then the cap
##   Stats.move_mult()             # (1 + bonuses capped at +30%) x bounded slow
##   Stats.heal_mult()             # healing received (applied inside the player's heal path only)
##   Stats.stamina_cost_mult(action)   # "sprint" | "dodge" | "swing" | "wand" | "" (general)
##   Stats.gather_bonus()          # extra harvest power per hit (charm + gathering mastery, capped)
##   Stats.melee_damage(weapon_id) # legacy numbers: hands 5, stone tools 9, Copper Sword 18
##
## Static and STATELESS: every value is recomputed from GameState (equipment, buffs, bond levels, mastery)
## and the presence of the active companion (Game.companion_present: follower, same area, <= 25 m). Nothing
## here is saved or accumulated, so loading a save (or loading it twice) can never stack a bonus.
## The per-frame getters (move_mult, stamina_cost_mult, slow_mult) do not allocate: they read the raw data
## dictionaries (ItemDB.item returns the shared definition) instead of ItemDB.equipment()/companion_skill_at()
## (both duplicate). Numbers live in data/equipment.gd, data/companion_skills.gd, data/mastery.gd, data/items.gd.
##
## Timed buff keys consumed here (GameState.add_buff(key, mult, seconds), spec section 9):
##   glimmerstep   Lumi's skill: `mult` is the move bonus FRACTION (0.12), shares the +30% cap
##   slow          enemy slow: `mult` is a speed multiplier < 1; bounded to SLOW_FLOOR here (never chains)
##   slow_resist   food: multiplier on the strength of slows (0.5 = half as strong)
##   sprint_saver  Lumi's 3-heart perk: sprint stamina cost multiplier (0.5 = half)
##   stamina_regen legacy food buff (read by the player's stamina model)

const EquipmentData := preload("res://data/equipment.gd")
const CompanionSkills := preload("res://data/companion_skills.gd")
const MasteryData := preload("res://data/mastery.gd")

const BASE_MAX_HP := 100.0
const HAND_DAMAGE := 5.0                 # = player_logic.gd HAND_DAMAGE (legacy)
const HAND_REACH := 1.8                  # = player_logic.gd HAND_REACH (legacy)
const SWING_TIME := 0.5                  # = player_logic.gd SWING_TIME (for sustained-damage comparisons)
const SLOW_FLOOR := 0.5                  # the strongest slow Krystal can ever be under (= enemy_base SLOW_MIN_MULT)
const SLOW_MAX_SECONDS := 3.0            # a single slow never lasts longer than this
const SLOW_IMMUNITY := 2.0               # after a slow is applied through the player, new slows wait this long past its end
const SPRINT_SAVER_FLOOR := 0.25
const ARMOR_SLOTS := ["head", "body", "boots"]
const EQUIP_SLOTS := ["head", "body", "boots", "charm"]
## Stat rows shown by the inventory panel (Stats.stat_rows()), in display order.
const ROW_IDS := ["damage", "wand", "protection", "speed", "healing", "stamina", "gathering", "lantern"]


# =====================================================================================================
# Sources
# =====================================================================================================

## Id of the active companion when it counts for support (present), else "".
static func present_companion() -> String:
	var id: String = GameState.active_companion
	if id == "" or not GameState.companions.has(id) or not GameState.is_befriended(id):
		return ""
	return id if Game.companion_present(id) else ""


## A companion's current value of `section.key` ("passive" / "basic" / "signature") at its bond level:
## the base value, replaced by every reached perk that sets the same key (data/companion_skills.gd).
static func companion_value(id: String, section: String, key: String) -> float:
	var def: Variant = CompanionSkills.SKILLS.get(id)
	if not (def is Dictionary):
		return 0.0
	var v: Variant = null
	var sec: Variant = (def as Dictionary).get(section)
	if sec is Dictionary:
		v = (sec as Dictionary).get(key)
	var perks: Variant = (def as Dictionary).get("perks")
	if perks is Dictionary and GameState.companions.has(id):
		var bond: int = GameState.bond_level(id)
		for lvl in CompanionSkills.PERK_LEVELS:
			if bond < int(lvl):
				break
			var p: Variant = (perks as Dictionary).get(lvl)
			if p is Dictionary:
				var ps: Variant = (p as Dictionary).get(section)
				if ps is Dictionary and (ps as Dictionary).has(key):
					v = (ps as Dictionary)[key]
	return float(v) if (v is float or v is int) else 0.0


## Passive effect of the present companion ("damage_reduction", "heal_received", "move"), 0 when absent.
static func companion_passive(effect: String) -> float:
	var id := present_companion()
	return companion_value(id, "passive", effect) if id != "" else 0.0


## Sum of `effect` over every equipped item's `effects` (charms: gather, stamina_save, heal_received, move,
## lantern_radius; data/equipment.gd EFFECTS).
static func equipped_effect(effect: String) -> float:
	var total := 0.0
	for slot in EQUIP_SLOTS:
		var id := String(GameState.equipment.get(slot, ""))
		if id == "" or not ItemDB.has_item(id):
			continue
		var fx: Variant = ItemDB.item(id).get("effects")
		if fx is Dictionary:
			var v: Variant = (fx as Dictionary).get(effect)
			if v is float or v is int:
				total += float(v)
	return total


## Armor: the equipped pieces' `reduction` ADDED together (full sets: 6 / 12 / 20 / 26 %).
static func armor_reduction() -> float:
	var total := 0.0
	for slot in ARMOR_SLOTS:
		var id := String(GameState.equipment.get(slot, ""))
		if id == "" or not ItemDB.has_item(id):
			continue
		var d: Dictionary = ItemDB.item(id)
		if String(d.get("cat", "")) != "armor":
			continue
		var r: Variant = d.get("reduction")
		if r is float or r is int:
			total += float(r)
	return clampf(total, 0.0, 1.0)


## Value of a mastery reward key at the track's current rank. REWARDS hold totals from their rank on, so the
## highest reached rank that defines the key wins (data/mastery.gd).
static func mastery_value(track: String, key: String) -> float:
	var rewards: Variant = MasteryData.REWARDS.get(track)
	if not (rewards is Dictionary):
		return 0.0
	var rank: int = ItemDB.mastery_rank(track)
	var v := 0.0
	for r in range(1, rank + 1):
		var row: Variant = (rewards as Dictionary).get(r)
		if row is Dictionary:
			var x: Variant = (row as Dictionary).get(key)
			if x is float or x is int:
				v = float(x)
	return v


## Current timed-buff value, or `default` when the buff is not active (GameState.buff_mult returns 1.0).
static func buff_value(key: String, default: float) -> float:
	var b: Variant = GameState.buffs.get(key)
	if b is Dictionary:
		var m: Variant = (b as Dictionary).get("mult")
		if m is float or m is int:
			return float(m)
	return default


static func _effect_cap(effect: String) -> float:
	var e: Variant = EquipmentData.EFFECTS.get(effect)
	if e is Dictionary:
		return float((e as Dictionary).get("cap", 1.0))
	return 1.0


# =====================================================================================================
# Defence
# =====================================================================================================

## Independent reduction sources combined multiplicatively, capped (data/equipment.gd REDUCTION_CAP 45%).
## combine(0.2, 0.1) = 0.28 (MP 5.1 example: 20% armor with Pebble's 10%, not 30%).
static func combine(a: float, b: float = 0.0, c: float = 0.0, d: float = 0.0) -> float:
	var keep := (1.0 - clampf(a, 0.0, 1.0)) * (1.0 - clampf(b, 0.0, 1.0)) * (1.0 - clampf(c, 0.0, 1.0)) * (1.0 - clampf(d, 0.0, 1.0))
	return clampf(1.0 - keep, 0.0, EquipmentData.REDUCTION_CAP)


## Total physical damage reduction: armor (pieces add) x present companion passive x equipped effects.
## No damage type bypasses it in this release (EquipmentData.BYPASS_ARMOR is empty).
static func damage_reduction() -> float:
	return combine(armor_reduction(), companion_passive("damage_reduction"), equipped_effect("damage_reduction"))


## Damage left after reduction (before the shield). One call per hit.
static func mitigate(raw: float) -> float:
	return maxf(raw, 0.0) * (1.0 - damage_reduction())


## The player's current transient shield (Pebble's Stoneheart), 0 when none.
static func player_shield() -> float:
	var p: Node = Game.player
	if p == null or not is_instance_valid(p):
		return 0.0
	var h: Variant = p.get("health")
	if h is Node and is_instance_valid(h):
		var s: Variant = (h as Node).get("shield")
		if s is float or s is int:
			return float(s)
	return 0.0


## Effective maximum health: the saved BASE (GameState.player.max_hp, 100) plus bonuses (none in this
## release). The base is what the player writes back, so equipment can never inflate a save.
static func base_max_hp() -> float:
	return maxf(float(GameState.player.get("max_hp", BASE_MAX_HP)), 1.0)


static func effective_max_hp() -> float:
	return base_max_hp() + max_hp_bonus()


static func max_hp_bonus() -> float:
	return 0.0


# =====================================================================================================
# Movement, healing, stamina
# =====================================================================================================

## Movement bonus fraction: present companion passive (Lumi) + Glimmerstep buff + equipped effects,
## capped at data/equipment.gd MOVE_CAP (+30%).
static func move_bonus() -> float:
	var sum := companion_passive("move") + buff_value("glimmerstep", 0.0) + equipped_effect("move")
	return clampf(sum, 0.0, EquipmentData.MOVE_CAP)


## Speed multiplier of an active slow after slow resistance, bounded to [SLOW_FLOOR, 1].
static func slow_mult() -> float:
	var s := buff_value("slow", 1.0)
	if s >= 1.0:
		return 1.0
	var strength := (1.0 - clampf(s, 0.0, 1.0)) * clampf(buff_value("slow_resist", 1.0), 0.0, 1.0)
	return clampf(1.0 - strength, SLOW_FLOOR, 1.0)


## The ONE movement multiplier the player applies to walk/sprint speed (dodge and knockback stay unscaled).
static func move_mult() -> float:
	return (1.0 + move_bonus()) * slow_mult()


## Healing received multiplier: present companion passive (Mochi) + equipped effects (Kindling Charm), capped.
static func heal_mult() -> float:
	var sum := companion_passive("heal_received") + equipped_effect("heal_received")
	return 1.0 + clampf(sum, 0.0, _effect_cap("heal_received"))


## Stamina cost multiplier for "sprint" (drain), "dodge", "swing", "wand" ("" = the general value shown in the
## stats panel). Equipped stamina_save (Swiftstep) applies to every action; sprinting also gets the Wayfinding
## mastery saving and Lumi's sprint_saver buff.
static func stamina_cost_mult(action: String = "") -> float:
	var save := equipped_effect("stamina_save")
	if action == "sprint":
		save += mastery_value("wayfinding", "sprint_stamina_save")
	var m := 1.0 - clampf(save, 0.0, _effect_cap("stamina_save"))
	if action == "sprint":
		m *= clampf(buff_value("sprint_saver", 1.0), SPRINT_SAVER_FLOOR, 1.0)
	return m


## Lantern light radius multiplier ("darkness comfort", Kindling Charm), capped.
static func lantern_radius_mult() -> float:
	return 1.0 + clampf(equipped_effect("lantern_radius"), 0.0, _effect_cap("lantern_radius"))


# =====================================================================================================
# Gathering & food
# =====================================================================================================

## Extra harvest power per hit (Gatherer's Charm + Gathering mastery), capped (25%).
static func gather_bonus() -> float:
	var cap := minf(_effect_cap("gather"), MasteryData.GATHER_BONUS_CAP)
	return clampf(equipped_effect("gather") + mastery_value("gathering", "gather_power"), 0.0, cap)


## Chance of +1 of a node's main drop (Gathering mastery), capped.
static func bonus_yield_chance() -> float:
	return clampf(mastery_value("gathering", "bonus_yield_chance"), 0.0, MasteryData.YIELD_CHANCE_CAP)


## Harvest progress one hit with `tool_item_id` adds: the tool's power (stone 1.0 keeps the legacy hit
## counts exactly) x (1 + gather bonus).
static func harvest_power(tool_item_id: String) -> float:
	var p := 1.0
	if tool_item_id != "" and ItemDB.has_item(tool_item_id):
		p = maxf(float(ItemDB.item(tool_item_id).get("power", 1.0)), 0.25)
	return p * (1.0 + gather_bonus())


## Best owned harvesting tool of `kind` ("axe" | "pickaxe"): highest power, ties broken by tier. With
## min_tier > 0 only tools of at least that tier count ("" when none qualifies).
static func best_tool(kind: String, min_tier: int = 0) -> String:
	if kind == "" or kind == "hand":
		return ""
	var best := ""
	var best_power := -1.0
	var best_tier := -1
	for s in GameState.inventory.slots:
		if s == null:
			continue
		var id := String(s["id"])
		if not ItemDB.has_item(id):
			continue
		var d: Dictionary = ItemDB.item(id)
		if String(d.get("tool", "")) != kind:
			continue
		var tier: int = ItemDB.item_tier(id)
		if tier < min_tier:
			continue
		var pw := float(d.get("power", 1.0))
		if pw > best_power or (is_equal_approx(pw, best_power) and tier > best_tier):
			best = id
			best_power = pw
			best_tier = tier
	return best


## Food duration multiplier (Hearthcraft mastery "meal_buff_bonus").
static func meal_buff_mult() -> float:
	return 1.0 + maxf(mastery_value("hearthcraft", "meal_buff_bonus"), 0.0)


## Applies a food's timed buff with the family rule (data/items.gd BUFF_FAMILIES): a food of a family that is
## already active REPLACES it when stronger, otherwise only refreshes the remaining time (never below what is
## left, never stacking). Returns {"result": "none" | "new" | "replaced" | "refreshed", "keys": [...], "family"}.
static func apply_food_buff(item_id: String) -> Dictionary:
	var out := {"result": "none", "keys": [], "family": ""}
	if not ItemDB.has_item(item_id):
		return out
	var buff: Variant = ItemDB.item(item_id).get("buff")
	if not (buff is Dictionary) or (buff as Dictionary).is_empty():
		return out
	var bd: Dictionary = buff
	var fam := ItemDB.buff_family(item_id)
	out["family"] = fam
	var secs := float(bd.get("seconds", 60.0)) * meal_buff_mult()
	var fams: Dictionary = ItemDB.buff_families()
	var stronger := "higher"
	if fams.has(fam):
		stronger = String((fams[fam] as Dictionary).get("stronger", "higher"))
	for k in bd:
		var key := String(k)
		if key == "seconds":
			continue
		var v := float(bd[k])
		(out["keys"] as Array).append(key)
		var cur: Variant = GameState.buffs.get(key)
		if not (cur is Dictionary):
			GameState.add_buff(key, v, secs)
			out["result"] = "new"
		else:
			var old := float((cur as Dictionary).get("mult", 1.0))
			var is_stronger: bool = (v > old + 0.0001) if stronger == "higher" else (v < old - 0.0001)
			if is_stronger:
				GameState.add_buff(key, v, secs)
				out["result"] = "replaced"
			else:
				(cur as Dictionary)["remaining"] = maxf(float((cur as Dictionary).get("remaining", 0.0)), secs)
				if String(out["result"]) != "new" and String(out["result"]) != "replaced":
					out["result"] = "refreshed"
		if fam != "" and GameState.buffs.get(key) is Dictionary:
			(GameState.buffs[key] as Dictionary)["family"] = fam
	return out


# =====================================================================================================
# Weapons
# =====================================================================================================

## Melee damage of a weapon/tool swing ("" = bare hands). Legacy numbers are the data's: stone tools 9,
## Copper Sword 18, Ironwood 25, Moonsteel 34 (MP 5.1). Wands never melee (they are never auto-picked).
static func melee_damage(weapon_id: String) -> float:
	if weapon_id == "" or not ItemDB.has_item(weapon_id):
		return HAND_DAMAGE
	return maxf(float(ItemDB.item(weapon_id).get("damage", HAND_DAMAGE)), HAND_DAMAGE)


static func melee_reach(weapon_id: String) -> float:
	if weapon_id == "" or not ItemDB.has_item(weapon_id):
		return HAND_REACH
	return float(ItemDB.item(weapon_id).get("reach", HAND_REACH))


## Sustained melee damage per second (one swing per SWING_TIME).
static func melee_dps(weapon_id: String) -> float:
	return melee_damage(weapon_id) / SWING_TIME


## Wand stats ({} when not a wand): damage, range, stamina, cooldown, tier, projectile.
static func wand_stats(wand_id: String) -> Dictionary:
	return ItemDB.wand(wand_id)


static func wand_damage(wand_id: String) -> float:
	if not ItemDB.has_item(wand_id) or not bool(ItemDB.item(wand_id).get("ranged", false)):
		return 0.0
	return maxf(float(ItemDB.item(wand_id).get("damage", 0.0)), 0.0)


## Sustained wand damage per second (one spark per cooldown, never faster than a cast).
static func wand_dps(wand_id: String) -> float:
	if not ItemDB.has_item(wand_id):
		return 0.0
	var cd := maxf(float(ItemDB.item(wand_id).get("cooldown", 0.8)), SWING_TIME)
	return wand_damage(wand_id) / cd


## Best owned melee weapon (legacy auto-selection, never a wand: GameState.best_weapon only looks at
## weapon/tool categories).
static func best_melee_weapon() -> String:
	return GameState.best_weapon()


## Highest tier among Krystal's owned weapons and wands (1 when none): the stable gear tier companions
## scale their basic damage by (data/companion_skills.gd GEAR_TIER_DAMAGE).
static func best_weapon_tier() -> int:
	var best := 1
	for s in GameState.inventory.slots:
		if s == null or not ItemDB.has_item(String(s["id"])):
			continue
		var cat := String(ItemDB.item(String(s["id"])).get("cat", ""))
		if cat == "weapon" or cat == "wand":
			best = maxi(best, ItemDB.item_tier(String(s["id"])))
	return best


static func companion_damage_mult() -> float:
	return float(CompanionSkills.GEAR_TIER_DAMAGE.get(best_weapon_tier(), 1.0))


# =====================================================================================================
# Readable summary (inventory stats panel)
# =====================================================================================================

static func _pct(v: float) -> String:
	var p := v * 100.0
	if absf(p - roundf(p)) < 0.05:
		return "%d%%" % int(roundf(p))
	return "%.1f%%" % p


static func _item_name(id: String) -> String:
	return ItemDB.display_name(id) if id != "" and ItemDB.has_item(id) else ""


static func _companion_name(id: String) -> String:
	var c: Dictionary = ItemDB.creature(id)
	return String(c.get("name", id.capitalize()))


## The best wand in the backpack ("" when none).
static func best_wand() -> String:
	var best := ""
	var best_dmg := -1.0
	for s in GameState.inventory.slots:
		if s != null and ItemDB.has_item(String(s["id"])) and bool(ItemDB.item(String(s["id"])).get("ranged", false)):
			var d := wand_damage(String(s["id"]))
			if d > best_dmg:
				best = String(s["id"])
				best_dmg = d
	return best


## Rows for the stats readout: [{id, label, value, detail}] in ROW_IDS order (rows without anything to say
## are still listed with a neutral value, except "wand" which only appears when a wand is owned).
static func stat_rows() -> Array:
	var rows: Array = []
	var weapon := best_melee_weapon()
	rows.append({"id": "damage", "label": "Damage", "value": "%d" % int(roundf(melee_damage(weapon))),
		"detail": _item_name(weapon) if weapon != "" else "Bare hands"})
	var wand := best_wand()
	if wand != "":
		var w := wand_stats(wand)
		rows.append({"id": "wand", "label": "Wand", "value": "%d" % int(roundf(wand_damage(wand))),
			"detail": "%s · %d m" % [_item_name(wand), int(roundf(float(w.get("range", 0.0))))]})
	var armor := armor_reduction()
	var comp := present_companion()
	var parts: Array = []
	if armor > 0.0:
		parts.append("Armor %s" % _pct(armor))
	var pr := companion_passive("damage_reduction")
	if pr > 0.0:
		parts.append("%s %s" % [_companion_name(comp), _pct(pr)])
	var eq_red := equipped_effect("damage_reduction")
	if eq_red > 0.0:
		parts.append("Charm %s" % _pct(eq_red))
	var red := damage_reduction()
	var pdetail := " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "No armor worn"
	if red >= EquipmentData.REDUCTION_CAP - 0.0001:
		pdetail += " (max)"
	rows.append({"id": "protection", "label": "Protection", "value": _pct(red), "detail": pdetail})
	rows.append(_bonus_row("speed", "Speed", move_bonus(), [["companion", companion_passive("move")],
		["glimmerstep", buff_value("glimmerstep", 0.0)], ["charm", equipped_effect("move")]], comp))
	rows.append(_bonus_row("healing", "Healing", heal_mult() - 1.0, [["companion", companion_passive("heal_received")],
		["charm", equipped_effect("heal_received")]], comp))
	rows.append(_bonus_row("stamina", "Stamina use", 1.0 - stamina_cost_mult(), [["charm", equipped_effect("stamina_save")]], comp, true))
	var gm := mastery_value("gathering", "gather_power")
	rows.append(_bonus_row("gathering", "Gathering", gather_bonus(), [["charm", equipped_effect("gather")], ["mastery", gm]], comp))
	rows.append(_bonus_row("lantern", "Lantern", lantern_radius_mult() - 1.0, [["charm", equipped_effect("lantern_radius")]], comp))
	return rows


static func _bonus_row(id: String, label: String, total: float, sources: Array, comp: String, less: bool = false) -> Dictionary:
	var parts: Array = []
	for s in sources:
		var v := float(s[1])
		if v <= 0.0:
			continue
		match String(s[0]):
			"companion":
				parts.append(_companion_name(comp))
			"glimmerstep":
				parts.append("Glimmerstep")
			"charm":
				parts.append(_item_name(String(GameState.equipment.get("charm", ""))) if String(GameState.equipment.get("charm", "")) != "" else "Equipment")
			"mastery":
				parts.append("Mastery")
	var value := "normal"
	if total > 0.0001:
		value = ("-" if less else "+") + _pct(total)
	return {"id": id, "label": label, "value": value, "detail": " · ".join(PackedStringArray(parts))}


## Readable lines about the active companion's support: who it is, whether it counts right now, its passive
## and signature at the current bond level (data/companion_skills.gd texts).
static func companion_lines() -> Array:
	var out: Array = []
	var id: String = GameState.active_companion
	if id == "" or not GameState.companions.has(id) or not GameState.is_befriended(id) or not CompanionSkills.SKILLS.has(id):
		out.append("No companion is following you.")
		return out
	var nm := _companion_name(id)
	var present := present_companion() == id
	var lvl: int = GameState.bond_level(id)
	var head := "%s (bond %d)" % [nm, lvl]
	out.append(head + (": with you" if present else ": too far away to help"))
	var passive: Dictionary = CompanionSkills.SKILLS[id].get("passive", {})
	for k in passive:
		var v := companion_value(id, "passive", String(k))
		match String(k):
			"damage_reduction":
				out.append("%s less damage taken" % _pct(v))
			"heal_received":
				out.append("+%s healing received" % _pct(v))
			"move":
				out.append("+%s movement speed" % _pct(v))
			_:
				pass
	var sig: Dictionary = CompanionSkills.SKILLS[id].get("signature", {})
	if not sig.is_empty():
		out.append("Skill: %s" % String(sig.get("name", "")))
	return out
