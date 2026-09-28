extends RefCounted
## Companion combat & support as the game uses it (MP §6, docs/CHAPTER_TWO_SPEC.md §3, §4.6, §9): the skill /
## perk numbers at the current bond level, the ONE signature-skill cooldown per companion (GameState companion
## record "skill_ready_at", a value on the GameState.stats.play_seconds timeline: frozen while paused, saved
## with the journey, untouched by switching pets / loading / area changes), behaviour modes, Krystal's gear
## tier for basic damage, the ribbon, and the texts the Friends panel shows. Reads GameState / ItemDB /
## Settings only (no scene access), so the panel can show a companion that is not spawned right now.
##   const Support := preload("res://src/companions/companion_support.gd")

const SkillsData := preload("res://data/companion_skills.gd")
const Logic := preload("res://src/companions/companion_logic.gd")
const Stats := preload("res://src/core/stats.gd")

const RIBBON_BOND := "bond_ribbon"           # the cosmetic ribbon earned at the 5-heart perk (derived, not an item)
const RIBBON_FLAG := "c1x_ribbon_given"      # optional goal Brave Little Steps (data/optional_goals.gd)


## id -> {bond level -> table}. data/companion_skills.gd is const, so a merged table never changes: the
## combat tick and the HUD read it often without re-merging (ItemDB.companion_skill_at deep-copies).
static var _tables: Dictionary = {}


## Numbers at the companion's current bond level (ItemDB.companion_skill_at): passive / basic / signature
## with every reached perk applied, plus "perks_active" and "ribbon". {} for an unknown id. Shared and cached:
## callers must not modify it.
static func table(id: String) -> Dictionary:
	var lvl := GameState.bond_level(id) if id != "" and GameState.companions.has(id) else 0
	var per: Variant = _tables.get(id)
	if not (per is Dictionary):
		per = {}
		_tables[id] = per
	var t: Variant = (per as Dictionary).get(lvl)
	if not (t is Dictionary):
		t = ItemDB.companion_skill_at(id, lvl)
		(per as Dictionary)[lvl] = t
	return t


static func signature(id: String) -> Dictionary:
	var t := table(id)
	var s: Variant = t.get("signature")
	return s if s is Dictionary else {}


static func basic(id: String) -> Dictionary:
	var t := table(id)
	var b: Variant = t.get("basic")
	return b if b is Dictionary else {}


## Now on the cooldown timeline (seconds of unpaused play).
static func now() -> float:
	return float(GameState.stats.get("play_seconds", 0.0))


static func cooldown(id: String) -> float:
	return maxf(float(signature(id).get("cooldown", 0.0)), 0.0)


## Seconds until the signature skill is ready again (0 = ready). Shared by autocast and the manual action.
static func remaining(id: String) -> float:
	if id == "":
		return 0.0
	var rec := GameState.companion(id)
	return Logic.cooldown_remaining(float(rec.get("skill_ready_at", 0.0)), now(), cooldown(id))


static func is_ready(id: String) -> bool:
	return remaining(id) <= 0.0


## Starts the cooldown (called once per cast, whoever asked for it).
static func start_cooldown(id: String) -> void:
	GameState.companion(id)["skill_ready_at"] = now() + cooldown(id)


## 0..1 of the cooldown still to run (the HUD ring).
static func cooldown_fraction(id: String) -> float:
	var cd := cooldown(id)
	return clampf(remaining(id) / cd, 0.0, 1.0) if cd > 0.0 else 0.0


## "assist" | "close" (the saved behaviour choice; "wait" is the separate assignment).
static func mode(id: String) -> String:
	var m := String(GameState.companion(id).get("combat_mode", SkillsData.DEFAULT_MODE))
	return m if SkillsData.COMBAT_MODES.has(m) else SkillsData.DEFAULT_MODE


static func set_mode(id: String, m: String) -> bool:
	if not SkillsData.COMBAT_MODES.has(m):
		return false
	GameState.companion(id)["combat_mode"] = m
	return true


## Setting: the follower attacks by itself (support always works).
static func auto_attack() -> bool:
	return _setting_true("companion_auto_attack")


## Setting: the follower casts its signature skill by itself when it helps.
static func autocast() -> bool:
	return _setting_true("companion_autocast") and bool(SkillsData.AUTOCAST.get("enabled", true))


## A boolean companion setting ("companion_auto_attack", "companion_autocast"); missing = on (the default).
static func setting_on(key: String) -> bool:
	return _setting_true(key)


static func _setting_true(key: String) -> bool:
	var v: Variant = Settings.get_value(key)
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return true


## Krystal's best owned weapon tier (weapons and wands in the backpack; 1 = stone / none). Stable: never the
## tool she happens to hold. One source of truth: Stats.best_weapon_tier() (src/core/stats.gd).
static func gear_tier() -> int:
	return Stats.best_weapon_tier()


static func gear_damage_mult() -> float:
	var t := gear_tier()
	var m: Variant = SkillsData.GEAR_TIER_DAMAGE.get(t)
	if m == null:
		var top := 1
		for k in SkillsData.GEAR_TIER_DAMAGE:
			if int(k) <= t:
				top = maxi(top, int(k))
		m = SkillsData.GEAR_TIER_DAMAGE.get(top, 1.0)
	return float(m)


## Basic-attack damage with the gear-tier bonus.
static func basic_damage(id: String) -> float:
	return float(basic(id).get("damage", 0.0)) * gear_damage_mult()


## The ribbon a companion wears: "comfort_ribbon" (given), RIBBON_BOND (5-heart perk) or "".
static func ribbon(id: String) -> String:
	var r := String(GameState.companion(id).get("ribbon", ""))
	if r != "":
		return r
	return RIBBON_BOND if bool(table(id).get("ribbon", false)) else ""


## Can Krystal tie a Comfort Ribbon on this companion now? {"ok", "reason"}.
static func ribbon_check(id: String) -> Dictionary:
	var def := ItemDB.creature(id)
	var item := String(def.get("ribbon_item", ""))
	if item == "":
		return {"ok": false, "reason": "", "item": ""}
	if not GameState.is_befriended(id):
		return {"ok": false, "reason": "Not a friend yet.", "item": item}
	if String(GameState.companion(id).get("ribbon", "")) == item:
		return {"ok": false, "reason": "%s already wears it." % _name(id), "item": item}
	if not GameState.has_item(item):
		return {"ok": false, "reason": "Make a %s at the Loom first." % ItemDB.display_name(item), "item": item}
	return {"ok": true, "reason": "", "item": item}


## Ties the Comfort Ribbon (consumes one, once). Returns true when given now.
static func give_ribbon(id: String) -> bool:
	var chk := ribbon_check(id)
	if not bool(chk["ok"]):
		return false
	var item := String(chk["item"])
	if not GameState.take_item(item, 1):
		return false
	GameState.companion(id)["ribbon"] = item
	GameState.set_flag(RIBBON_FLAG, true)
	return true


static func has_courage(id: String) -> bool:
	var f := String(ItemDB.creature(id).get("courage_flag", ""))
	return f != "" and bool(GameState.get_flag(f))


# --- Texts for the Friends panel ------------------------------------------------------------------------------

static func _name(id: String) -> String:
	return String(ItemDB.creature(id).get("name", id.capitalize()))


static func _arachno() -> bool:
	var v: Variant = Settings.get_value("arachnophobia")
	return v is bool and v


static func role(id: String) -> String:
	return String(table(id).get("role", ""))


## "+10% healing received while Mochi is with you..." (the passive at the current bond level).
static func passive_text(id: String) -> String:
	var t := table(id)
	var p: Dictionary = t.get("passive", {})
	var base: Dictionary = ItemDB.companion_skill(id).get("passive", {})
	var txt := String(t.get("passive_text", ""))
	# The data text quotes the base number: keep it honest when a perk raised it.
	for k in p:
		if base.has(k) and not is_equal_approx(float(base[k]), float(p[k])):
			txt = txt.replace("%d%%" % roundi(float(base[k]) * 100.0), "%d%%" % roundi(float(p[k]) * 100.0))
	return txt


## "Spore Puff: 4 damage every 2.4 s, up to 9 m. Helps with enemies you're fighting."
static func attack_text(id: String) -> String:
	var b := basic(id)
	if b.is_empty():
		return ""
	var reach := "up to %d m" % roundi(float(b.get("range", 0.0))) if String(b.get("kind", "")) == "projectile" else "up close"
	return "%s: %s damage every %.1f s, %s. Only enemies you're fighting or that go for you." % [
		String(b.get("name", "Attack")), _num(basic_damage(id)), float(b.get("interval", 0.0)), reach]


static func skill_name(id: String) -> String:
	return String(signature(id).get("name", ""))


## "Bloomguard: restores 22 health over 6 s..." with the current (perk) numbers.
static func skill_text(id: String) -> String:
	var s := signature(id)
	if s.is_empty():
		return ""
	var t := ""
	match String(s.get("id", "")):
		"bloomguard":
			t = "Restores %s health over %s s. Casts itself when you're meaningfully hurt." % [_num(float(s.get("heal", 0.0))), _num(float(s.get("duration", 0.0)))]
			if int(s.get("cleanse_slow", 0)) > 0:
				t += " Also clears one clinging %s slow." % ("root" if _arachno() else "web or root")
		"stoneheart":
			t = "A %s-point shield for up to %s s; briefly staggers ordinary enemies nearby, never bosses." % [_num(float(s.get("shield", 0.0))), _num(float(s.get("duration", 0.0)))]
			if int(s.get("resist_knockback", 0)) > 0:
				t += " Shrugs off one knockback."
		"glimmerstep":
			t = "+%d%% speed for %s s and a light pulse (%s m) that exposes shadow enemies." % [roundi(float(s.get("move", 0.0)) * 100.0), _num(float(s.get("duration", 0.0))), _num(float(s.get("pulse_radius", 0.0)))]
			if float(s.get("sprint_stamina_save", 0.0)) > 0.0:
				t += " Sprinting costs less stamina meanwhile."
		_:
			t = String(s.get("text", ""))
	return "%s: %s Recharge %s s." % [String(s.get("name", "")), t, _num(cooldown(id))]


## Perks for display: [{"level", "text", "active"}].
static func perk_rows(id: String) -> Array:
	var out: Array = []
	var perks: Dictionary = ItemDB.companion_skill(id).get("perks", {})
	var lvl := GameState.bond_level(id) if GameState.companions.has(id) else 0
	for l in SkillsData.PERK_LEVELS:
		if not perks.has(l):
			continue
		var p: Dictionary = perks[l]
		var t := String(p.get("alt_text", p.get("text", ""))) if _arachno() else String(p.get("text", ""))
		out.append({"level": int(l), "text": t, "active": lvl >= int(l)})
	return out


## "Next at 3 hearts: ..." or "" when every perk is unlocked.
static func next_perk_text(id: String) -> String:
	var perks: Dictionary = ItemDB.companion_skill(id).get("perks", {})
	var lvl := GameState.bond_level(id) if GameState.companions.has(id) else 0
	var n := Logic.next_perk(perks, SkillsData.PERK_LEVELS, lvl, _arachno())
	if n.is_empty():
		return ""
	return "Next at %d hearts: %s" % [int(n["level"]), String(n["text"])]


static func _num(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
