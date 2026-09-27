"""Sound registry. Sound modules register generators with @sound / @loop; generate_all.py
renders everything that is registered and checks it against REQUIRED (docs/ARCHITECTURE.md)."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

# Every sound name consumers may call (docs/ARCHITECTURE.md, Audio section).
REQUIRED = {
	"ui": ["ui_click", "ui_hover", "ui_open", "ui_close", "ui_error", "ui_craft", "ui_quest", "ui_notify",
		"ui_befriend", "ui_bond", "ui_save"],
	"sfx": [
		# player
		"step_grass", "step_stone", "step_wood", "step_water", "jump", "land", "dodge", "swing", "hurt", "eat",
		"lantern_on", "lantern_off", "death",
		# gathering
		"chop", "tree_fall", "mine_hit", "rock_break", "pickup", "grass_pull", "berry_pick", "splash",
		# building / farming
		"build_place", "build_remove", "build_invalid", "dig", "harvest_crop", "chest_open", "chest_close", "sleep",
		# combat
		"hit_soft", "hit_hard", "enemy_hurt", "enemy_defeat", "brambling_chatter", "brambling_telegraph",
		"gloomling_hiss", "gloomling_telegraph", "gloomling_alert", "gloomling_flinch", "weaver_rattle",
		"weaver_skitter", "weaver_shriek", "weaver_drop", "shade_whisper", "shade_telegraph", "shade_drift",
		"shade_shriek", "brazier_light", "heartseed_pulse",
		# companions
		"mochi_chirp", "mochi_happy", "mochi_scared", "pebble_clack", "pebble_happy", "pebble_grunt",
		"lumi_chime", "lumi_happy", "lumi_warn", "fake_lumi_chime",
		# world
		"ward_hum", "ward_restore", "door_creak", "gate_unlock", "lift_move", "checkpoint_light", "water_drip",
		"mine_cart",
		# horror director
		"dir_distant_pickaxe", "dir_creak", "dir_footsteps", "dir_pebbles", "dir_whisper", "dir_wrong_squeak",
		"dir_flicker", "dir_scratch", "dir_scratch_soft", "dir_web_rustle", "dir_root_creak", "stinger_soft",
		"stinger_major",
	],
	"ambience": ["amb_forest_day", "amb_forest_night", "amb_stream", "amb_mine", "amb_ruins", "amb_silk", "amb_boss"],
	"music": ["music_title", "music_haven", "music_night", "music_boss", "music_ending"],
}


@dataclass
class Spec:
	name: str
	fn: Callable
	cat: str                      # ui | sfx | ambience | music
	variants: int = 1
	peak: float = -5.0            # one-shots: target peak dBFS
	rms: float = -24.0            # loops: target RMS dBFS
	loop: bool = False
	seconds: float = 0.0          # loops: exact loop length
	fin: float = 0.002            # one-shot fade in (s)
	fout: float = 0.03            # one-shot fade out (s)
	trim: bool = True
	extra: dict = field(default_factory=dict)


REGISTRY: dict[str, Spec] = {}


def sound(name: str, cat: str = "sfx", variants: int = 1, peak: float = -5.0, fin: float = 0.002,
		fout: float = 0.03, trim: bool = True):
	"""Registers a one-shot generator fn(rng, variant_index) -> mono array."""
	def deco(fn):
		REGISTRY[name] = Spec(name, fn, cat, variants, peak=peak, fin=fin, fout=fout, trim=trim)
		return fn
	return deco


def loop(name: str, cat: str, seconds: float, rms: float = -24.0):
	"""Registers a loop generator fn(rng, seconds) -> exactly periodic stereo array (n, 2)."""
	def deco(fn):
		REGISTRY[name] = Spec(name, fn, cat, 1, rms=rms, loop=True, seconds=seconds)
		return fn
	return deco


def all_required() -> list:
	return [n for names in REQUIRED.values() for n in names]
