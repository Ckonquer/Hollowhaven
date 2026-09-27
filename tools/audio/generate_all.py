"""Hollowhaven audio build: renders every original sound, ambience loop and music track.

Usage (from the repo root, Git Bash):
    .tools/pyenv/Scripts/python.exe tools/audio/generate_all.py            # everything
    .tools/pyenv/Scripts/python.exe tools/audio/generate_all.py --only ui_click,chop
    .tools/pyenv/Scripts/python.exe tools/audio/generate_all.py --cat music --jobs 8

Output: game/assets/audio/{ui,sfx,ambience,music}/<name>.wav (variants <name>_1.._n), 44.1 kHz
16-bit, mono for UI/SFX, stereo for ambience/music, plus Godot .import files (loops marked
'forward', QOA compression for long files). Every generator is seeded from its name, so builds
are reproducible bit-for-bit. Afterwards run the Godot import:
    timeout 600 tools/godot.sh --headless --path game --import
"""
from __future__ import annotations

import argparse
import os
import re
import sys

sys.dont_write_bytecode = True     # keep tools/audio free of __pycache__ folders
import time
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
	sys.path.insert(0, HERE)

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "game", "assets", "audio")
MODULES = ["sounds_ui", "sounds_player", "sounds_world", "sounds_creatures", "sounds_director", "ambience", "music_tracks"]
QOA_MIN_SECONDS = 2.5          # one-shots longer than this are QOA-compressed too


def _load_modules():
	import importlib
	for m in MODULES:
		importlib.import_module(m)


def file_names(spec) -> list:
	if spec.variants <= 1:
		return [spec.name + ".wav"]
	return ["%s_%d.wav" % (spec.name, i + 1) for i in range(spec.variants)]


def render_job(job):
	"""Worker: renders one file. job = (name, variant_index, out_dir). Returns a small result dict."""
	_load_modules()
	import numpy as np
	from catalog import REGISTRY
	from hhsynth import core as C
	from hhsynth.wavio import write_wav

	name, v, out_dir = job
	spec = REGISTRY[name]
	fname = file_names(spec)[v]
	path = os.path.join(out_dir, spec.cat, fname)
	t0 = time.time()
	rng = C.rng_for("%s:%d" % (name, v))
	if spec.loop:
		x = np.asarray(spec.fn(rng, spec.seconds), dtype=np.float64)
		n = C.ns(spec.seconds)
		assert x.ndim == 2 and x.shape[1] == 2, name + ": loops must be stereo"
		assert len(x) == n, "%s: loop length %d != %d" % (name, len(x), n)
		x = x - np.mean(x, axis=0, keepdims=True)
		x = C.normalize_rms(x, spec.rms)
		ceiling = -1.5 if spec.cat == "music" else -3.0
		x = C.circular(lambda s: C.limiter(s, ceiling, 0.02), x, C.ns(0.5))
		frames = write_wav(path, x, loop=True)
	else:
		x = np.asarray(spec.fn(rng, v), dtype=np.float64)
		if x.ndim == 2:
			x = x.mean(axis=1)
		x = C.dc_block(x)
		if spec.trim:
			x = C.trim_tail(x, -66.0)
		x = C.fade(x, spec.fin, spec.fout)
		x = C.normalize_peak(x, spec.peak)
		frames = write_wav(path, x, loop=False)
	return {"name": name, "file": fname, "cat": spec.cat, "loop": spec.loop, "frames": frames,
		"seconds": frames / C.SR, "render_s": time.time() - t0}


# --- Godot import files ---------------------------------------------------------------------------

def write_import(wav_path: str, loop: bool, compress: bool) -> None:
	"""Creates or updates <file>.wav.import so Godot imports it with the right loop/compression.
	Existing files keep their uid and dest paths; only the relevant [params] are changed."""
	imp = wav_path + ".import"
	params = {
		"force/8_bit": "false", "force/mono": "false", "force/max_rate": "false", "force/max_rate_hz": "44100",
		"edit/trim": "false", "edit/normalize": "false",
		"edit/loop_mode": "2" if loop else "1",          # 2 = Forward, 1 = Disabled
		"edit/loop_begin": "0", "edit/loop_end": "-1",
		"compress/mode": "2" if compress else "0",       # 2 = QOA, 0 = PCM (uncompressed)
	}
	if os.path.exists(imp):
		with open(imp, encoding="utf-8") as fh:
			text = fh.read()
		head, sep, body = text.partition("[params]")
		if not sep:
			head = text.rstrip() + "\n\n"
		lines = []
		seen = set()
		for line in body.splitlines():
			m = re.match(r"^([\w/]+)=(.*)$", line.strip())
			if m and m.group(1) in params:
				lines.append("%s=%s" % (m.group(1), params[m.group(1)]))
				seen.add(m.group(1))
			elif line.strip():
				lines.append(line.strip())
		for k, val in params.items():
			if k not in seen:
				lines.append("%s=%s" % (k, val))
		new = head.rstrip() + "\n\n[params]\n\n" + "\n".join(lines) + "\n"
		if new != text:
			with open(imp, "w", encoding="utf-8", newline="\n") as fh:
				fh.write(new)
	else:
		body = "\n".join("%s=%s" % kv for kv in params.items())
		with open(imp, "w", encoding="utf-8", newline="\n") as fh:
			fh.write('[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n\n[params]\n\n' + body + "\n")


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--only", default="", help="comma-separated sound names")
	ap.add_argument("--cat", default="", help="ui | sfx | ambience | music")
	ap.add_argument("--jobs", type=int, default=max(1, min(16, (os.cpu_count() or 4) - 2)))
	ap.add_argument("--keep-stale", action="store_true", help="do not delete WAVs that are no longer generated")
	ap.add_argument("--out", default=OUT, help="output root (default game/assets/audio); another folder is "
		"handy to check that a re-render is byte-identical: no .import files are written there")
	args = ap.parse_args()
	out_root = os.path.abspath(args.out)
	in_project = os.path.normcase(out_root) == os.path.normcase(os.path.abspath(OUT))

	_load_modules()
	from catalog import REGISTRY, REQUIRED, all_required

	missing = [n for n in all_required() if n not in REGISTRY]
	if missing:
		print("ERROR: no generator for: " + ", ".join(missing))
		return 2
	for cat, names in REQUIRED.items():
		for n in names:
			if REGISTRY[n].cat != cat:
				print("ERROR: %s registered as %s, expected %s" % (n, REGISTRY[n].cat, cat))
				return 2

	only = set(s for s in args.only.split(",") if s)
	specs = [s for s in REGISTRY.values() if (not only or s.name in only) and (not args.cat or s.cat == args.cat)]
	for cat in ("ui", "sfx", "ambience", "music"):
		os.makedirs(os.path.join(out_root, cat), exist_ok=True)
	# longest jobs first so the pool stays busy
	weight = {"music": 0, "ambience": 1, "sfx": 2, "ui": 3}
	jobs = [(s.name, v, out_root) for s in sorted(specs, key=lambda s: weight[s.cat]) for v in range(s.variants)]
	print("Rendering %d files with %d workers..." % (len(jobs), args.jobs))
	t0 = time.time()
	results = []
	if args.jobs <= 1:
		results = [render_job(j) for j in jobs]
	else:
		with ProcessPoolExecutor(max_workers=args.jobs) as ex:
			for r in ex.map(render_job, jobs):
				results.append(r)
	for r in sorted(results, key=lambda r: (r["cat"], r["file"])):
		print("  %-9s %-28s %6.2fs  (%.1fs)" % (r["cat"], r["file"], r["seconds"], r["render_s"]))
		if in_project:
			path = os.path.join(out_root, r["cat"], r["file"])
			write_import(path, r["loop"], r["loop"] or r["seconds"] > QOA_MIN_SECONDS)

	if not only and not args.cat and not args.keep_stale:
		expected = {os.path.join(out_root, s.cat, f) for s in REGISTRY.values() for f in file_names(s)}
		for cat in ("ui", "sfx", "ambience", "music"):
			d = os.path.join(out_root, cat)
			for f in os.listdir(d):
				p = os.path.join(d, f)
				if f.endswith(".wav") and p not in expected:
					print("  removing stale " + os.path.relpath(p, ROOT))
					os.remove(p)
					if os.path.exists(p + ".import"):
						os.remove(p + ".import")
				elif f.endswith(".wav.import") and p[:-7] not in expected:
					os.remove(p)
	print("Done: %d files in %.1fs" % (len(results), time.time() - t0))
	return 0


if __name__ == "__main__":
	sys.exit(main())
