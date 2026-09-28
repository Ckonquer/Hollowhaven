extends RefCounted
## Krystal's appearance catalogue (MP 4, docs/CHAPTER_TWO_SPEC.md 4.1 / 8). Appearance is purely cosmetic:
## nothing here changes stats, the collision capsule, movement or interaction reach.
##
## Look dictionary (GameState.appearance; every value is an id from the tables below):
##   {"hair", "hair_color", "skin", "eyes", "upper", "lower", "shoes", "hat", "hair_acc", "back",
##    "palette": {"primary", "secondary", "accent"}, "outfit"}
## hat / hair_acc / back may be "" (nothing worn). palette values are SWATCHES ids. outfit is informational
## (the preset the look came from). Unknown ids from a later version are kept in the saved look but shown as
## the safe default of their slot (ItemDB.sanitize_look reports them); ownership is never erased.
##
## Ownership (GameState.wardrobe.owned): starter parts are always owned; earnable parts carry a `pattern` id
## (PATTERNS) that becomes owned from a Loom pattern recipe (data/recipes.gd SPECIAL_RECIPES) or a reward.
## Switching between owned parts, hair, eyes, skin and unlocked colours is always free.
##
## Colour channels: each clothing part names which palette channel colours its main cloth (`channels`),
## plus `fixed` colours for details that never change (buttons, leather, flower petals). The avatar module
## builds each part from its `mesh` builder id. Materials are per-avatar (never shared with companions).

const SLOTS := ["upper", "lower", "shoes", "hat", "hair_acc", "back"]
## Slots that may be empty ("").
const OPTIONAL_SLOTS := ["hat", "hair_acc", "back"]
const PALETTE_CHANNELS := ["primary", "secondary", "accent"]
const PRESET_SLOTS := 3

## The Chapter One avatar exactly (auburn side braid explorer). Fixed by the lead: spec section 8.
const LEGACY_LOOK := {"hair": "side_braid", "hair_color": "auburn", "skin": "skin_2", "eyes": "eye_1",
	"upper": "explorer_jacket", "lower": "explorer_trousers", "shoes": "explorer_boots", "hat": "",
	"hair_acc": "flower_clip", "back": "satchel", "palette": {"primary": "teal", "secondary": "sunflower", "accent": "plum"},
	"outfit": "cozy_explorer"}

# --- Hair --------------------------------------------------------------------------------------------------
## springs = secondary-motion chains the avatar animates (braids, ponytails, ribbon tails).
const HAIRSTYLES := {
	"side_braid": {"name": "Side Braid", "mesh": "hair_side_braid", "legacy": true, "springs": ["braid"]},
	"bob": {"name": "Bob", "mesh": "hair_bob", "springs": []},
	"long_waves": {"name": "Long Waves", "mesh": "hair_long_waves", "springs": ["waves"]},
	"high_ponytail": {"name": "High Ponytail", "mesh": "hair_high_ponytail", "springs": ["ponytail"]},
	"twin_braids": {"name": "Twin Braids", "mesh": "hair_twin_braids", "springs": ["braid_left", "braid_right"]},
	"space_buns": {"name": "Space Buns", "mesh": "hair_space_buns", "springs": []},
	"braided_crown": {"name": "Braided Crown", "mesh": "hair_braided_crown", "springs": []},
	"half_up_ribbon": {"name": "Half-Up Ribbon", "mesh": "hair_half_up_ribbon", "springs": ["ribbon_tails"]},
}

## base / dark (shadowed locks) / light (highlights). auburn = the Chapter One hair (Palette.K_HAIR and the
## avatar's HAIR_DARK / HAIR_LIGHT).
const HAIR_COLORS := {
	"auburn": {"name": "Auburn", "base": Color("7a3b2e"), "dark": Color("5e2c22"), "light": Color("94503a"), "legacy": true},
	"chestnut": {"name": "Chestnut", "base": Color("8b5a3c"), "dark": Color("6b4230"), "light": Color("a8724f")},
	"espresso": {"name": "Espresso", "base": Color("4a3028"), "dark": Color("33211c"), "light": Color("634036")},
	"raven": {"name": "Raven", "base": Color("2e2a33"), "dark": Color("1d1a22"), "light": Color("474150")},
	"honey": {"name": "Honey", "base": Color("d9a35a"), "dark": Color("b8843f"), "light": Color("ebc07a")},
	"platinum": {"name": "Platinum", "base": Color("eee3c8"), "dark": Color("d4c6a6"), "light": Color("fff6e2")},
	"strawberry": {"name": "Strawberry Blonde", "base": Color("e0845c"), "dark": Color("c26844"), "light": Color("f0a27e")},
	"copper": {"name": "Copper", "base": Color("c1602f"), "dark": Color("9c4a22"), "light": Color("d87d4a")},
	"rose": {"name": "Rose", "base": Color("e48aa6"), "dark": Color("c66d8a"), "light": Color("f2aec3")},
	"lavender": {"name": "Lavender", "base": Color("b59ad8"), "dark": Color("957ab9"), "light": Color("cfb8ec")},
	"mint": {"name": "Mint", "base": Color("8fd1b9"), "dark": Color("6fb39b"), "light": Color("b3e6d3")},
	"sky": {"name": "Sky", "base": Color("8fbfe8"), "dark": Color("6f9fcc"), "light": Color("b5d8f5")},
	"silver": {"name": "Silver", "base": Color("b9bcc6"), "dark": Color("9699a5"), "light": Color("d8dae2")},
}

# --- Skin and eyes -----------------------------------------------------------------------------------------
## skin_2 = the Chapter One skin (Palette.K_SKIN) with the avatar's BLUSH.
const SKIN_TONES := {
	"skin_1": {"name": "Porcelain", "base": Color("fbe3cf"), "blush": Color("f7a8b4")},
	"skin_2": {"name": "Peach", "base": Color("f0c6a0"), "blush": Color("f4a0ab"), "legacy": true},
	"skin_3": {"name": "Honey", "base": Color("dea77c"), "blush": Color("e88f8f")},
	"skin_4": {"name": "Caramel", "base": Color("c08559"), "blush": Color("d77a78")},
	"skin_5": {"name": "Cocoa", "base": Color("8f5b3a"), "blush": Color("b8605e")},
	"skin_6": {"name": "Umber", "base": Color("5e3a27"), "blush": Color("8e4a48")},
}

## iris = the warm inner colour, dark = pupil / outer ring. eye_1 = the Chapter One eyes (avatar EYE_WARM /
## EYE_DARK).
const EYE_COLORS := {
	"eye_1": {"name": "Warm Brown", "iris": Color("7a4632"), "dark": Color("2e2233"), "legacy": true},
	"eye_2": {"name": "Hazel", "iris": Color("8a6a2e"), "dark": Color("2e2233")},
	"eye_3": {"name": "Moss Green", "iris": Color("4e8a4a"), "dark": Color("22302a")},
	"eye_4": {"name": "Pond Blue", "iris": Color("3f7ab8"), "dark": Color("1f2a44")},
	"eye_5": {"name": "Storm Grey", "iris": Color("7d8794"), "dark": Color("2a2e36")},
	"eye_6": {"name": "Violet", "iris": Color("7a5aa8"), "dark": Color("2a2040")},
	"eye_7": {"name": "Amber", "iris": Color("b8742a"), "dark": Color("3a2418")},
	"eye_8": {"name": "Deep Brown", "iris": Color("4a2c22"), "dark": Color("1e1418")},
}

# --- Colour swatches and dye palettes ------------------------------------------------------------------------
## Clothing colours. starter = free from the start; otherwise `dye` names the DYE_PALETTES entry that unlocks
## it. teal / sunflower / plum / cream / leather / satchel = the Chapter One outfit colours (Palette.K_*).
const SWATCHES := {
	"teal": {"name": "Teal", "color": Color("3fa7a0"), "starter": true},
	"sunflower": {"name": "Sunflower", "color": Color("f2c14e"), "starter": true},
	"plum": {"name": "Plum", "color": Color("5a4a6e"), "starter": true},
	"cream": {"name": "Cream", "color": Color("f3e6c8"), "starter": true},
	"rose": {"name": "Rose", "color": Color("e98aa5"), "starter": true},
	"lavender": {"name": "Lavender", "color": Color("b6a0d9"), "starter": true},
	"mint": {"name": "Mint", "color": Color("9fd8c0"), "starter": true},
	"sky": {"name": "Sky", "color": Color("8fbfe8"), "starter": true},
	"oat": {"name": "Oat", "color": Color("e2d3b5"), "starter": true},
	"caramel": {"name": "Caramel", "color": Color("c98a55"), "starter": true},
	"cocoa": {"name": "Cocoa", "color": Color("7a5236"), "starter": true},
	"berry": {"name": "Berry", "color": Color("c64468"), "starter": true},
	"moss": {"name": "Moss", "color": Color("7fa35a"), "starter": true},
	"butter": {"name": "Butter", "color": Color("f7e08a"), "starter": true},
	"slate": {"name": "Slate", "color": Color("6e7a8a"), "starter": true},
	"snow": {"name": "Snow", "color": Color("fbf8f2"), "starter": true},
	"leather": {"name": "Leather", "color": Color("6b4428"), "starter": true},
	"satchel": {"name": "Saddle", "color": Color("b07a4f"), "starter": true},
	"rosewood": {"name": "Rosewood", "color": Color("a8506a"), "starter": false, "dye": "rose"},
	"peony": {"name": "Peony", "color": Color("f4b3c8"), "starter": false, "dye": "rose"},
	"pumpkin": {"name": "Pumpkin", "color": Color("e8812f"), "starter": false, "dye": "pumpkin"},
	"marigold": {"name": "Marigold", "color": Color("f2a33a"), "starter": false, "dye": "pumpkin"},
	"wisteria": {"name": "Wisteria", "color": Color("9a7ec8"), "starter": false, "dye": "lavender"},
	"heather": {"name": "Heather", "color": Color("c8b4e0"), "starter": false, "dye": "lavender"},
	"linen": {"name": "Linen", "color": Color("efe4cf"), "starter": false, "dye": "cream"},
	"buttercream": {"name": "Buttercream", "color": Color("fff1d0"), "starter": false, "dye": "cream"},
	"ember": {"name": "Ember", "color": Color("c8502e"), "starter": false, "dye": "ember"},
	"rust": {"name": "Rust", "color": Color("9c4a2c"), "starter": false, "dye": "ember"},
	"midnight": {"name": "Midnight", "color": Color("2f3158"), "starter": false, "dye": "midnight"},
	"starlight": {"name": "Starlight", "color": Color("d9dcf5"), "starter": false, "dye": "midnight"},
}

## Dye palettes, mixed once at the Loom (cost consumed once, then reusable forever): they unlock extra
## clothing swatches AND a furniture tint (structure data.tint = palette id, for `tintable` structures).
const DYE_PALETTES := {
	"rose": {"name": "Rose Dye", "tint": Color("e98aa5"), "swatches": ["rosewood", "peony"], "cost": {"roseberries": 4}, "station": "loom"},
	"pumpkin": {"name": "Pumpkin Dye", "tint": Color("e8812f"), "swatches": ["pumpkin", "marigold"], "cost": {"pumpkin": 2}, "station": "loom"},
	"lavender": {"name": "Lavender Dye", "tint": Color("b6a0d9"), "swatches": ["wisteria", "heather"], "cost": {"moonpetal": 3}, "station": "loom"},
	"cream": {"name": "Cream Dye", "tint": Color("f3e6c8"), "swatches": ["linen", "buttercream"], "cost": {"sunflax": 4}, "station": "loom"},
	"ember": {"name": "Ember Dye", "tint": Color("c8502e"), "swatches": ["ember", "rust"], "cost": {"resin": 2, "berries": 3}, "station": "loom"},
	"midnight": {"name": "Midnight Dye", "tint": Color("2f3158"), "swatches": ["midnight", "starlight"], "cost": {"moonpetal": 2, "echo_shard": 1}, "station": "loom"},
}

# --- Clothing parts ----------------------------------------------------------------------------------------
## name, slot, mesh (builder id), starter, pattern ("" for starter parts), skirt (procedural sway panels),
## hides_hair (hat covers the crown: the avatar drops the top curl / fringe), channels {part: palette channel},
## fixed {part: Color}, style (lower garments: trousers | pinafore | pleated_skirt | culottes | dress |
## dungarees | skirt), legacy (the Chapter One piece).
const PARTS := {
	# upper
	"explorer_jacket": {"name": "Explorer Jacket", "slot": "upper", "mesh": "upper_explorer_jacket", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"jacket": "primary", "scarf": "secondary"}, "fixed": {"shirt": Color("f3e6c8"), "buttons": Color("e0b85a")}, "legacy": true},
	"puff_blouse": {"name": "Puff-Sleeve Blouse", "slot": "upper", "mesh": "upper_puff_blouse", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"blouse": "secondary", "collar": "accent"}, "fixed": {}},
	"ribbon_blouse": {"name": "Sailor Ribbon Blouse", "slot": "upper", "mesh": "upper_ribbon_blouse", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"blouse": "secondary", "collar": "primary", "ribbon": "accent"}, "fixed": {}},
	"cloud_cardigan": {"name": "Cloud Cardigan", "slot": "upper", "mesh": "upper_cloud_cardigan", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"cardigan": "primary", "top": "secondary"}, "fixed": {"buttons": Color("fbf8f2")}},
	"moonflower_bodice": {"name": "Moonflower Bodice", "slot": "upper", "mesh": "upper_moonflower_bodice", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"bodice": "primary", "sash": "accent"}, "fixed": {}},
	"striped_tee": {"name": "Striped Tee", "slot": "upper", "mesh": "upper_striped_tee", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"tee": "secondary", "stripes": "accent"}, "fixed": {}},
	"pumpkin_cardigan": {"name": "Pumpkin Patch Cardigan", "slot": "upper", "mesh": "upper_pumpkin_cardigan", "starter": false, "pattern": "pat_pumpkin_patch", "skirt": false, "hides_hair": false,
		"channels": {"cardigan": "primary", "top": "secondary"}, "fixed": {"buttons": Color("7fa35a")}},
	"witch_blouse": {"name": "Ribbon Witch Blouse", "slot": "upper", "mesh": "upper_witch_blouse", "starter": false, "pattern": "pat_ribbon_witch", "skirt": false, "hides_hair": false,
		"channels": {"blouse": "secondary", "laces": "accent"}, "fixed": {}},
	"ruffle_bodice": {"name": "Velvet Ruffle Bodice", "slot": "upper", "mesh": "upper_ruffle_bodice", "starter": false, "pattern": "pat_velvet_vampire", "skirt": false, "hides_hair": false,
		"channels": {"bodice": "primary", "ruffles": "secondary", "collar": "accent"}, "fixed": {}},
	"ghost_bodice": {"name": "Ghostlight Bodice", "slot": "upper", "mesh": "upper_ghost_bodice", "starter": false, "pattern": "pat_ghostlight_party", "skirt": false, "hides_hair": false,
		"channels": {"bodice": "primary", "trim": "secondary"}, "fixed": {"glow": Color("d8e8ff")}},
	"moth_blouse": {"name": "Moon Moth Blouse", "slot": "upper", "mesh": "upper_moth_blouse", "starter": false, "pattern": "pat_moon_moth", "skirt": false, "hides_hair": false,
		"channels": {"blouse": "secondary", "cuffs": "accent"}, "fixed": {}},
	"festival_bodice": {"name": "Lanternwake Bodice", "slot": "upper", "mesh": "upper_festival_bodice", "starter": false, "pattern": "pat_lanternwake", "skirt": false, "hides_hair": false,
		"channels": {"bodice": "primary", "lacing": "secondary"}, "fixed": {"embroidery": Color("f2c14e")}},
	# lower (garment or dress)
	"explorer_trousers": {"name": "Explorer Trousers", "slot": "lower", "mesh": "lower_explorer_trousers", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"trousers": "accent"}, "fixed": {}, "style": "trousers", "legacy": true},
	"pinafore_skirt": {"name": "Strawberry Pinafore", "slot": "lower", "mesh": "lower_pinafore", "starter": true, "pattern": "", "skirt": true, "hides_hair": false,
		"channels": {"pinafore": "primary", "pocket": "accent"}, "fixed": {"strawberry": Color("e4665c")}, "style": "pinafore"},
	"pleated_skirt_leggings": {"name": "Pleated Skirt & Leggings", "slot": "lower", "mesh": "lower_pleated_skirt_leggings", "starter": true, "pattern": "", "skirt": true, "hides_hair": false,
		"channels": {"skirt": "primary", "leggings": "accent"}, "fixed": {}, "style": "pleated_skirt"},
	"cloud_culottes": {"name": "Cloud Culottes", "slot": "lower", "mesh": "lower_cloud_culottes", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"culottes": "secondary"}, "fixed": {}, "style": "culottes"},
	"moonflower_dress": {"name": "Moonflower Day Dress", "slot": "lower", "mesh": "lower_moonflower_dress", "starter": true, "pattern": "", "skirt": true, "hides_hair": false,
		"channels": {"dress": "primary", "hem": "secondary"}, "fixed": {"flowers": Color("fff4e0")}, "style": "dress"},
	"dungarees": {"name": "Mushroom Dungarees", "slot": "lower", "mesh": "lower_dungarees", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"dungarees": "primary", "patch": "accent"}, "fixed": {"buckles": Color("e0b85a")}, "style": "dungarees"},
	"harvest_skirt": {"name": "Harvest Skirt", "slot": "lower", "mesh": "lower_harvest_skirt", "starter": false, "pattern": "pat_pumpkin_patch", "skirt": true, "hides_hair": false,
		"channels": {"skirt": "accent"}, "fixed": {}, "style": "skirt"},
	"witch_dress": {"name": "Ribbon Witch Dress", "slot": "lower", "mesh": "lower_witch_dress", "starter": false, "pattern": "pat_ribbon_witch", "skirt": true, "hides_hair": false,
		"channels": {"dress": "primary", "ribbons": "accent"}, "fixed": {}, "style": "dress"},
	"velvet_dress": {"name": "Velvet Ruffled Dress", "slot": "lower", "mesh": "lower_velvet_dress", "starter": false, "pattern": "pat_velvet_vampire", "skirt": true, "hides_hair": false,
		"channels": {"dress": "primary", "ruffles": "secondary"}, "fixed": {}, "style": "dress"},
	"tulle_party_dress": {"name": "Ghostlight Party Dress", "slot": "lower", "mesh": "lower_tulle_party_dress", "starter": false, "pattern": "pat_ghostlight_party", "skirt": true, "hides_hair": false,
		"channels": {"tulle": "primary", "underskirt": "secondary"}, "fixed": {"sparkles": Color("fffbe8")}, "style": "dress"},
	"moth_long_skirt": {"name": "Moon Moth Long Skirt", "slot": "lower", "mesh": "lower_moth_long_skirt", "starter": false, "pattern": "pat_moon_moth", "skirt": true, "hides_hair": false,
		"channels": {"skirt": "primary"}, "fixed": {}, "style": "skirt"},
	"lanternwake_dress": {"name": "Lanternwake Festival Dress", "slot": "lower", "mesh": "lower_lanternwake_dress", "starter": false, "pattern": "pat_lanternwake", "skirt": true, "hides_hair": false,
		"channels": {"dress": "primary", "apron": "secondary", "hem": "accent"}, "fixed": {}, "style": "dress"},
	# shoes
	"explorer_boots": {"name": "Explorer Boots", "slot": "shoes", "mesh": "shoes_explorer_boots", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"boots": Color("6b4428"), "cuff": Color("8a5a36"), "sole": Color("6e4a33")}, "legacy": true},
	"mary_janes": {"name": "Mary Janes", "slot": "shoes", "mesh": "shoes_mary_janes", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"shoes": "accent"}, "fixed": {"socks": Color("fbf8f2")}},
	"lace_up_boots": {"name": "Lace-Up Boots", "slot": "shoes", "mesh": "shoes_lace_up_boots", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"boots": "accent"}, "fixed": {"laces": Color("fbf8f2")}},
	"ballet_flats": {"name": "Ballet Flats", "slot": "shoes", "mesh": "shoes_ballet_flats", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"flats": "secondary"}, "fixed": {}},
	"wellies": {"name": "Wellies", "slot": "shoes", "mesh": "shoes_wellies", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"boots": "accent"}, "fixed": {}},
	"buckle_boots": {"name": "Buckle Boots", "slot": "shoes", "mesh": "shoes_buckle_boots", "starter": false, "pattern": "pat_ribbon_witch", "skirt": false, "hides_hair": false,
		"channels": {"boots": "accent"}, "fixed": {"buckles": Color("e0b85a")}},
	"velvet_slippers": {"name": "Velvet Slippers", "slot": "shoes", "mesh": "shoes_velvet_slippers", "starter": false, "pattern": "pat_velvet_vampire", "skirt": false, "hides_hair": false,
		"channels": {"slippers": "primary"}, "fixed": {"bows": Color("2f3158")}},
	# hats (non-obstructive: small brims, the camera always sees her face)
	"sun_hat": {"name": "Straw Sun Hat", "slot": "hat", "mesh": "hat_sun_hat", "starter": true, "pattern": "", "skirt": false, "hides_hair": true,
		"channels": {"band": "accent"}, "fixed": {"straw": Color("e6cf8a")}},
	# accent: a toadstool cap (berry red in the Mushroom Dungarees preset), not a plain beret in the dungaree colour
	"mushroom_beret": {"name": "Mushroom Beret", "slot": "hat", "mesh": "hat_mushroom_beret", "starter": true, "pattern": "", "skirt": false, "hides_hair": true,
		"channels": {"beret": "accent"}, "fixed": {"spots": Color("fff4e0")}},
	"witch_hat": {"name": "Ribbon Witch Hat", "slot": "hat", "mesh": "hat_witch_hat", "starter": false, "pattern": "pat_witch_hat", "skirt": false, "hides_hair": true,
		"channels": {"hat": "primary", "ribbon": "accent"}, "fixed": {}},
	"flower_crown": {"name": "Lantern Flower Crown", "slot": "hat", "mesh": "hat_flower_crown", "starter": false, "pattern": "pat_lanternwake", "skirt": false, "hides_hair": false,
		"channels": {"leaves": "secondary"}, "fixed": {"flowers": Color("f6d25a")}},
	# hair accessories
	"flower_clip": {"name": "Flower Clip", "slot": "hair_acc", "mesh": "acc_flower_clip", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"petals": Color("fff4e0"), "centre": Color("f6d25a")}, "legacy": true},
	"strawberry_clip": {"name": "Strawberry Clips", "slot": "hair_acc", "mesh": "acc_strawberry_clip", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"berry": Color("e4665c"), "leaf": Color("7fa35a")}},
	"big_bow": {"name": "Big Bow", "slot": "hair_acc", "mesh": "acc_big_bow", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"bow": "accent"}, "fixed": {}},
	"star_pins": {"name": "Star Pins", "slot": "hair_acc", "mesh": "acc_star_pins", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"stars": Color("f7e08a")}},
	"ribbon_bow": {"name": "Tailor's Ribbon Bow", "slot": "hair_acc", "mesh": "acc_ribbon_bow", "starter": false, "pattern": "pat_ribbon_bow", "skirt": false, "hides_hair": false,
		"channels": {"ribbon": "primary"}, "fixed": {}},
	"leaf_clip": {"name": "Autumn Leaf Clip", "slot": "hair_acc", "mesh": "acc_leaf_clip", "starter": false, "pattern": "pat_pumpkin_patch", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"leaf": Color("e9a15b")}},
	"ribbon_ties": {"name": "Witch Ribbon Ties", "slot": "hair_acc", "mesh": "acc_ribbon_ties", "starter": false, "pattern": "pat_ribbon_witch", "skirt": false, "hides_hair": false,
		"channels": {"ribbons": "accent"}, "fixed": {}},
	"bat_bow": {"name": "Bat Bow", "slot": "hair_acc", "mesh": "acc_bat_bow", "starter": false, "pattern": "pat_velvet_vampire", "skirt": false, "hides_hair": false,
		"channels": {"bow": "secondary"}, "fixed": {}},
	"glow_pins": {"name": "Ghostlight Pins", "slot": "hair_acc", "mesh": "acc_glow_pins", "starter": false, "pattern": "pat_ghostlight_party", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"glow": Color("d8e8ff")}},
	"moth_antennae_band": {"name": "Moon Moth Headband", "slot": "hair_acc", "mesh": "acc_moth_antennae_band", "starter": false, "pattern": "pat_moon_moth", "skirt": false, "hides_hair": false,
		"channels": {"band": "accent"}, "fixed": {"tips": Color("d9dcf5")}},
	"lantern_ribbon": {"name": "Lantern Ribbon", "slot": "hair_acc", "mesh": "acc_lantern_ribbon", "starter": false, "pattern": "pat_lanternwake", "skirt": false, "hides_hair": false,
		"channels": {"ribbon": "accent"}, "fixed": {"lantern": Color("ffc978")}},
	# worn pushed up into the hair at the side of the head, never over the face
	"masquerade_mask": {"name": "Moonlit Masquerade Mask", "slot": "hair_acc", "mesh": "acc_masquerade_mask", "starter": false, "pattern": "pat_echo_masquerade", "skirt": false, "hides_hair": false,
		"channels": {"mask": "primary", "plume": "secondary"}, "fixed": {"trim": Color("e0b85a")}},
	"chime_ribbons": {"name": "Chime Ribbons", "slot": "hair_acc", "mesh": "acc_chime_ribbons", "starter": false, "pattern": "pat_echo_chime", "skirt": false, "hides_hair": false,
		"channels": {"ribbons": "accent"}, "fixed": {"chimes": Color("e8c66a")}},
	# visible back accessories (capes / shawls hide the jacket patch; the satchel keeps the belt lantern)
	"satchel": {"name": "Explorer Satchel", "slot": "back", "mesh": "back_satchel", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"bag": Color("b07a4f")}, "legacy": true},
	"picnic_basket": {"name": "Picnic Basket Pack", "slot": "back", "mesh": "back_picnic_basket", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"cloth": "primary"}, "fixed": {"wicker": Color("c9a26e")}},
	"bedroll_pack": {"name": "Bedroll Pack", "slot": "back", "mesh": "back_bedroll_pack", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"roll": "secondary"}, "fixed": {"straps": Color("6b4428")}},
	"tote_bag": {"name": "Cloud Tote", "slot": "back", "mesh": "back_tote_bag", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {"tote": "secondary"}, "fixed": {}},
	"acorn_pack": {"name": "Acorn Backpack", "slot": "back", "mesh": "back_acorn_pack", "starter": true, "pattern": "", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"cap": Color("7a5236"), "nut": Color("c98a55")}},
	"leaf_cape": {"name": "Bramble Leaf Cape", "slot": "back", "mesh": "back_leaf_cape", "starter": false, "pattern": "pat_leaf_cape", "skirt": false, "hides_hair": false,
		"channels": {"cape": "secondary"}, "fixed": {"leaves": Color("7fa35a")}, "cape": true},
	"little_cape": {"name": "Little Velvet Cape", "slot": "back", "mesh": "back_little_cape", "starter": false, "pattern": "pat_velvet_cape", "skirt": false, "hides_hair": false,
		"channels": {"cape": "accent", "lining": "primary"}, "fixed": {}, "cape": true},
	"ghostlight_wings": {"name": "Ghostlight Wings", "slot": "back", "mesh": "back_ghostlight_wings", "starter": false, "pattern": "pat_ghostlight_party", "skirt": false, "hides_hair": false,
		"channels": {}, "fixed": {"wings": Color("e8f0ff")}},
	"moth_shawl": {"name": "Moon Moth Shawl", "slot": "back", "mesh": "back_moth_shawl", "starter": false, "pattern": "pat_moon_moth", "skirt": false, "hides_hair": false,
		"channels": {"shawl": "primary", "spots": "accent"}, "fixed": {}, "cape": true},
	"lantern_backpack": {"name": "Paper Lantern Pack", "slot": "back", "mesh": "back_lantern_backpack", "starter": false, "pattern": "pat_lanternwake", "skirt": false, "hides_hair": false,
		"channels": {"paper": "secondary"}, "fixed": {"glow": Color("ffc978")}},
	"opera_cloak": {"name": "Moonlit Opera Cloak", "slot": "back", "mesh": "back_opera_cloak", "starter": false, "pattern": "pat_echo_masquerade", "skirt": false, "hides_hair": false,
		"channels": {"cloak": "accent", "lining": "primary"}, "fixed": {"clasp": Color("e0b85a")}, "cape": true},
	# secondary / accent: most tops are primary, so the capelet stands out as coloured (and the wardrobe tile, which
	# shows the first channel, matches the render); the builder's contrast guard still swaps over a secondary top
	"chorister_capelet": {"name": "Chorister Capelet", "slot": "back", "mesh": "back_chorister_capelet", "starter": false, "pattern": "pat_echo_chime", "skirt": false, "hides_hair": false,
		"channels": {"capelet": "secondary", "collar": "accent"}, "fixed": {"chime": Color("e8c66a")}, "cape": true},
}

## Ownership patterns: which parts each grants and how it is earned. `recipe` = the Loom pattern recipe
## (SPECIAL_RECIPES), unlocked by `flag` (data/unlocks.gd); recipe "" = granted directly by a reward.
const PATTERNS := {
	"pat_ribbon_bow": {"name": "Tailor's Ribbon Bow", "parts": ["ribbon_bow"], "recipe": "pattern_ribbon_bow", "flag": "c1x_tailor_cache",
		"source": "The Tailor's Cache near the Old Oak teaches it; sew it at the Loom."},
	"pat_leaf_cape": {"name": "Bramble Leaf Cape", "parts": ["leaf_cape"], "recipe": "pattern_leaf_cape", "flag": "c1x_elder_defeated",
		"source": "Defeat the Knotted Elder at Bramblewatch; sew it at the Loom."},
	"pat_pumpkin_patch": {"name": "Pumpkin Patch", "parts": ["pumpkin_cardigan", "harvest_skirt", "leaf_clip"], "recipe": "pattern_pumpkin_patch", "flag": "ch2_pumpkin_face",
		"source": "Finish 'A Pumpkin With a Face'; sew it at the Loom."},
	"pat_ribbon_witch": {"name": "Ribbon Witch", "parts": ["witch_blouse", "witch_dress", "buckle_boots", "ribbon_ties"], "recipe": "pattern_ribbon_witch", "flag": "ch2_manor_restored",
		"source": "Restore the Moonveil Manor lantern; sew it at the Loom."},
	"pat_witch_hat": {"name": "Ribbon Witch Hat", "parts": ["witch_hat"], "recipe": "", "flag": "",
		"reward": "rw_opt_hat_too_large", "source": "Follow the fluttering ribbons in 'A Hat Too Large' to the stranded hat."},
	"pat_velvet_vampire": {"name": "Velvet Vampire", "parts": ["ruffle_bodice", "velvet_dress", "velvet_slippers", "bat_bow"], "recipe": "pattern_velvet_vampire", "flag": "ch2_manor_restored",
		"source": "Restore the Moonveil Manor lantern; sew it at the Loom."},
	"pat_velvet_cape": {"name": "Little Velvet Cape", "parts": ["little_cape"], "recipe": "pattern_velvet_cape", "flag": "ch2_count_wardrobe",
		"source": "Find all three velvet scraps for 'The Count's Wardrobe'; sew it at the Loom."},
	"pat_ghostlight_party": {"name": "Ghostlight Party", "parts": ["ghost_bodice", "tulle_party_dress", "glow_pins", "ghostlight_wings"], "recipe": "pattern_ghostlight_party", "flag": "ch2_candleyard_pattern",
		"source": "Find the dress pattern hidden in the Candleyard; sew it at the Loom."},
	"pat_moon_moth": {"name": "Moon Moth Shawl", "parts": ["moth_blouse", "moth_long_skirt", "moth_antennae_band", "moth_shawl"], "recipe": "pattern_moon_moth", "flag": "ch2_trial_matron",
		"source": "First clear of the Matron echo trial; sew it at the Loom."},
	"pat_echo_masquerade": {"name": "Moonlit Masquerade", "parts": ["masquerade_mask", "opera_cloak"], "recipe": "pattern_echo_masquerade", "flag": "ch2_trial_velour",
		"source": "First clear of the Count Velour echo trial; sew it at the Loom."},
	"pat_echo_chime": {"name": "Chime Chorister", "parts": ["chime_ribbons", "chorister_capelet"], "recipe": "pattern_echo_chime", "flag": "ch2_trial_choir",
		"source": "First clear of the Borrowed Choir echo trial; sew it at the Loom."},
	"pat_lanternwake": {"name": "Lanternwake Festival", "parts": ["festival_bodice", "lanternwake_dress", "lantern_ribbon", "flower_crown", "lantern_backpack"], "recipe": "pattern_lanternwake", "flag": "ch2_feast",
		"source": "Celebrate the Lanternwake at the end of Chapter Two; sew it at the Loom."},
}

# --- Complete looks ------------------------------------------------------------------------------------------
## parts: one id per SLOTS entry ("" = nothing in an optional slot); palette: starter swatches only, so any owned
## outfit can be worn without dyes. Applying an outfit changes clothing + palette, never hair, skin or eyes
## (`hair` / `hair_color` are only the preview suggestion). unlock: starter, or the patterns it needs.
const OUTFITS := {
	"cozy_explorer": {"name": "Cozy Explorer", "starter": true, "legacy": true, "hair": "side_braid", "hair_color": "auburn",
		"parts": {"upper": "explorer_jacket", "lower": "explorer_trousers", "shoes": "explorer_boots", "hat": "", "hair_acc": "flower_clip", "back": "satchel"},
		"palette": {"primary": "teal", "secondary": "sunflower", "accent": "plum"}, "unlock": {"kind": "starter"},
		"desc": "Krystal's original explorer outfit: teal jacket, mustard scarf and sturdy boots."},
	"strawberry_picnic": {"name": "Strawberry Picnic", "starter": true, "hair": "twin_braids", "hair_color": "chestnut",
		"parts": {"upper": "puff_blouse", "lower": "pinafore_skirt", "shoes": "mary_janes", "hat": "", "hair_acc": "strawberry_clip", "back": "picnic_basket"},
		"palette": {"primary": "rose", "secondary": "cream", "accent": "berry"}, "unlock": {"kind": "starter"},
		"desc": "A rosy pinafore over a puff-sleeve blouse, with a picnic basket on her back."},
	"ribboned_adventurer": {"name": "Ribboned Adventurer", "starter": true, "hair": "high_ponytail", "hair_color": "honey",
		"parts": {"upper": "ribbon_blouse", "lower": "pleated_skirt_leggings", "shoes": "lace_up_boots", "hat": "", "hair_acc": "big_bow", "back": "bedroll_pack"},
		"palette": {"primary": "sky", "secondary": "snow", "accent": "plum"}, "unlock": {"kind": "starter"},
		"desc": "A pleated skirt over warm leggings, a sailor-collar blouse and a big bow."},
	"cloud_cardigan": {"name": "Cloud Cardigan", "starter": true, "hair": "bob", "hair_color": "espresso",
		"parts": {"upper": "cloud_cardigan", "lower": "cloud_culottes", "shoes": "ballet_flats", "hat": "", "hair_acc": "star_pins", "back": "tote_bag"},
		"palette": {"primary": "lavender", "secondary": "cream", "accent": "sky"}, "unlock": {"kind": "starter"},
		"desc": "A fluffy cloud cardigan with wide culottes and a little tote."},
	"moonflower_dress": {"name": "Moonflower Dress", "starter": true, "hair": "long_waves", "hair_color": "auburn",
		"parts": {"upper": "moonflower_bodice", "lower": "moonflower_dress", "shoes": "ballet_flats", "hat": "sun_hat", "hair_acc": "", "back": ""},
		"palette": {"primary": "snow", "secondary": "mint", "accent": "sunflower"}, "unlock": {"kind": "starter"},
		"desc": "A flowing day dress embroidered with moonflowers and a straw sun hat."},
	"mushroom_dungarees": {"name": "Mushroom Dungarees", "starter": true, "hair": "space_buns", "hair_color": "copper",
		"parts": {"upper": "striped_tee", "lower": "dungarees", "shoes": "wellies", "hat": "mushroom_beret", "hair_acc": "", "back": "acorn_pack"},
		"palette": {"primary": "moss", "secondary": "cream", "accent": "berry"}, "unlock": {"kind": "starter"},
		"desc": "Sturdy dungarees, a striped tee, wellies and a spotted mushroom beret."},
	"pumpkin_patch": {"name": "Pumpkin Patch", "starter": false, "hair": "half_up_ribbon", "hair_color": "espresso",
		"parts": {"upper": "pumpkin_cardigan", "lower": "harvest_skirt", "shoes": "lace_up_boots", "hat": "", "hair_acc": "leaf_clip", "back": "picnic_basket"},
		"palette": {"primary": "caramel", "secondary": "cream", "accent": "moss"}, "unlock": {"kind": "pattern", "patterns": ["pat_pumpkin_patch"]},
		"desc": "A chunky pumpkin cardigan over a swishy harvest skirt."},
	"ribbon_witch": {"name": "Ribbon Witch", "starter": false, "hair": "long_waves", "hair_color": "raven",
		"parts": {"upper": "witch_blouse", "lower": "witch_dress", "shoes": "buckle_boots", "hat": "witch_hat", "hair_acc": "ribbon_ties", "back": ""},
		"palette": {"primary": "plum", "secondary": "cream", "accent": "rose"}, "unlock": {"kind": "pattern", "patterns": ["pat_ribbon_witch", "pat_witch_hat"]},
		"desc": "A ribboned witch dress, buckle boots and a pointed hat that stays out of her eyes."},
	"velvet_vampire": {"name": "Velvet Vampire", "starter": false, "hair": "braided_crown", "hair_color": "raven",
		"parts": {"upper": "ruffle_bodice", "lower": "velvet_dress", "shoes": "velvet_slippers", "hat": "", "hair_acc": "bat_bow", "back": "little_cape"},
		"palette": {"primary": "berry", "secondary": "snow", "accent": "plum"}, "unlock": {"kind": "pattern", "patterns": ["pat_velvet_vampire", "pat_velvet_cape"]},
		"desc": "A ruffled velvet dress with a little cape and a bat-shaped bow."},
	"ghostlight_party": {"name": "Ghostlight Party", "starter": false, "hair": "space_buns", "hair_color": "lavender",
		"parts": {"upper": "ghost_bodice", "lower": "tulle_party_dress", "shoes": "mary_janes", "hat": "", "hair_acc": "glow_pins", "back": "ghostlight_wings"},
		"palette": {"primary": "sky", "secondary": "snow", "accent": "lavender"}, "unlock": {"kind": "pattern", "patterns": ["pat_ghostlight_party"]},
		"desc": "A floaty tulle party dress with gentle ghost-light wings."},
	"moon_moth_shawl": {"name": "Moon Moth Shawl", "starter": false, "hair": "half_up_ribbon", "hair_color": "silver",
		"parts": {"upper": "moth_blouse", "lower": "moth_long_skirt", "shoes": "ballet_flats", "hat": "", "hair_acc": "moth_antennae_band", "back": "moth_shawl"},
		"palette": {"primary": "lavender", "secondary": "cream", "accent": "slate"}, "unlock": {"kind": "pattern", "patterns": ["pat_moon_moth"]},
		"desc": "A long skirt and a soft spotted shawl that spreads like moth wings."},
	"lanternwake_dress": {"name": "Lanternwake Dress", "starter": false, "hair": "braided_crown", "hair_color": "honey",
		"parts": {"upper": "festival_bodice", "lower": "lanternwake_dress", "shoes": "mary_janes", "hat": "flower_crown", "hair_acc": "lantern_ribbon", "back": "lantern_backpack"},
		"palette": {"primary": "sunflower", "secondary": "cream", "accent": "teal"}, "unlock": {"kind": "pattern", "patterns": ["pat_lanternwake"]},
		"desc": "The festival dress of Lanternwake, with a flower crown and a paper lantern pack."},
}
