extends Node3D
## Preview/QA helper: Mochi, Pebble and Lumi side by side (optionally next to a 1.6 m reference
## post the height of Krystal). Used with the preview stage:
##   --preview=res://src/companions/companion_lineup.gd --preview-args='{"anim":"happy","ref":true}'
## Also handy for menus/dioramas: setup({"anim": "idle"}).

const VISUALS := {
	"mochi": "res://src/companions/mochi_visual.gd",
	"pebble": "res://src/companions/pebble_visual.gd",
	"lumi": "res://src/companions/lumi_visual.gd",
}
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")

var visuals: Dictionary = {}
var _params: Dictionary = {}


func setup(params: Dictionary) -> void:
	_params = params


func _ready() -> void:
	var order := ["mochi", "pebble", "lumi"]
	for i in order.size():
		var id: String = order[i]
		var v: Node3D = load(VISUALS[id]).new()
		add_child(v)
		v.position = Vector3((float(i) - 1.0) * 0.85, 0.0, 0.0)
		visuals[id] = v
	if bool(_params.get("ref", false)):
		var post := Kit.capsule(0.18, 1.6, Mat.toon(Palette.K_JACKET))
		Kit.add(self, post, Vector3(-1.9, 0.8, -0.4))
	play_anim(String(_params.get("anim", "idle")))
	if _params.has("glow"):
		for id in visuals:
			visuals[id].set_glow(float(_params["glow"]))


func play_anim(anim_name: String) -> void:
	for id in visuals:
		var v: Node3D = visuals[id]
		if v.has_method("play_anim"):
			v.play_anim(anim_name)
