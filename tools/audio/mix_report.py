"""Prints the per-bus level balance of each music track (active-section RMS after the bus gain,
relative to the loudest bus). Used while mixing without being able to listen.

    .tools/pyenv/Scripts/python.exe tools/audio/mix_report.py [music_title ...]
"""
from __future__ import annotations

import os
import sys

sys.dont_write_bytecode = True     # keep tools/audio free of __pycache__ folders

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import music_tracks  # noqa: E402,F401
from catalog import REGISTRY  # noqa: E402
from hhsynth.core import rng_for  # noqa: E402
from hhsynth.music import Song  # noqa: E402


def main() -> None:
	names = sys.argv[1:] or [n for n, s in REGISTRY.items() if s.cat == "music"]
	for name in names:
		spec = REGISTRY[name]
		spec.fn(rng_for(name + ":0"), spec.seconds)
		rep = Song.last_report
		top = max(rep.values())
		print(name)
		for bus, lvl in sorted(rep.items(), key=lambda kv: -kv[1]):
			print("   %-8s %6.1f dB" % (bus, lvl - top))


if __name__ == "__main__":
	main()
