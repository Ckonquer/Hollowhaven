extends RefCounted
## Resolves a (sanitized) look dictionary into the colours Krystal's part builders use. Reads the appearance
## catalogue through ItemDB (data/appearance.gd). Pure: no nodes, no state.
##
## resolve(look) -> {skin, blush, hair, hair_dark, hair_light, iris, eye_dark, primary, secondary, accent, leg,
##                   palette_key}
##   leg = the colour of Krystal's lower legs (ankles above low shoes): the trouser / legging colour, or skin
##   under skirts, dresses and culottes.
## channel(part_id, name, col) -> Color: a part's palette channel colour (e.g. "jacket" -> primary)
## fixed(part_id, name, fallback) -> Color: a part's fixed detail colour

const LEG_CHANNEL := {"trousers": "trousers", "dungarees": "dungarees", "pleated_skirt": "leggings"}


static func resolve(look: Dictionary) -> Dictionary:
	var hair: Dictionary = ItemDB.appearance_table("hair_colors").get(String(look.get("hair_color", "")), {})
	var skin: Dictionary = ItemDB.appearance_table("skin_tones").get(String(look.get("skin", "")), {})
	var eyes: Dictionary = ItemDB.appearance_table("eye_colors").get(String(look.get("eyes", "")), {})
	var legacy := ItemDB.legacy_look()
	if hair.is_empty():
		hair = ItemDB.appearance_table("hair_colors")[legacy["hair_color"]]
	if skin.is_empty():
		skin = ItemDB.appearance_table("skin_tones")[legacy["skin"]]
	if eyes.is_empty():
		eyes = ItemDB.appearance_table("eye_colors")[legacy["eyes"]]
	var pal: Dictionary = look.get("palette", {}) if look.get("palette", {}) is Dictionary else {}
	var col := {
		"skin": skin["base"], "blush": skin["blush"],
		"hair": hair["base"], "hair_dark": hair["dark"], "hair_light": hair["light"],
		"iris": eyes["iris"], "eye_dark": eyes["dark"],
	}
	var swatches := ItemDB.appearance_table("swatches")
	for ch in ["primary", "secondary", "accent"]:
		var sw := String(pal.get(ch, legacy["palette"][ch]))
		if not swatches.has(sw):
			sw = String(legacy["palette"][ch])
		col[ch] = ItemDB.swatch_color(sw)
	col["palette_key"] = "%s/%s/%s" % [(col["primary"] as Color).to_html(false), (col["secondary"] as Color).to_html(false),
		(col["accent"] as Color).to_html(false)]
	var lower := ItemDB.appearance_part(String(look.get("lower", "")))
	var style := String(lower.get("style", "trousers"))
	col["leg"] = col["skin"]
	if LEG_CHANNEL.has(style):
		col["leg"] = channel(String(look.get("lower", "")), String(LEG_CHANNEL[style]), col)
	return col


## Colour of one palette channel of a part (`channels` in data/appearance.gd); unknown channel -> primary.
static func channel(part_id: String, channel_name: String, col: Dictionary) -> Color:
	var p := ItemDB.appearance_part(part_id)
	var chans: Dictionary = p.get("channels", {})
	var which := String(chans.get(channel_name, "primary"))
	return col.get(which, col.get("primary", Color.WHITE))


## A part's fixed detail colour (`fixed` in data/appearance.gd), or `fallback`.
static func fixed(part_id: String, key: String, fallback: Color) -> Color:
	var p := ItemDB.appearance_part(part_id)
	var fx: Dictionary = p.get("fixed", {})
	var c: Variant = fx.get(key, null)
	return c if c is Color else fallback
