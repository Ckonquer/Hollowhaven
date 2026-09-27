extends SceneTree
## Writes the Godot Engine licence and third-party component notices to a text file.
## Usage: godot --headless --path game -s res://tests/tools/dump_licenses.gd -- --out=<abs path>

func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out = String(a).substr(6)
	var text := "GODOT ENGINE LICENCE\n====================\n\n" + Engine.get_license_text() + "\n\n"
	text += "THIRD-PARTY COMPONENTS INCLUDED IN THE GODOT ENGINE\n===================================================\n\n"
	for info in Engine.get_copyright_info():
		text += "- " + String(info["name"]) + "\n"
		for part in info["parts"]:
			text += "    Files: " + ", ".join(PackedStringArray(part["files"])) + "\n"
			text += "    Copyright: " + "; ".join(PackedStringArray(part["copyright"])) + "\n"
			text += "    License: " + String(part["license"]) + "\n"
		text += "\n"
	text += "\nLICENCE TEXTS\n=============\n\n"
	var lic: Dictionary = Engine.get_license_info()
	for k in lic:
		text += "---- " + String(k) + " ----\n" + String(lic[k]) + "\n\n"
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", out, " (", text.length(), " chars)")
	quit()
