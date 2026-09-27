"""Audio QA: per-file duration, peak/RMS levels, clipping, click-free edges and loop seams, plus
spectrogram PNGs for music/ambience (and a few SFX) so problems can be spotted visually.

    .tools/pyenv/Scripts/python.exe tools/audio/analyze.py [--spectrograms all|loops|none]

Writes qa/tmp/audio/report.txt and qa/tmp/audio/spectrograms/*.png. Exit code 1 if any file
breaks a hard rule (clipping, loud edges, bad loop seam, out-of-range loudness)."""
from __future__ import annotations

import argparse
import os
import sys

sys.dont_write_bytecode = True     # keep tools/audio free of __pycache__ folders

import numpy as np
from scipy import signal

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
	sys.path.insert(0, HERE)

from hhsynth.wavio import read_wav  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(ROOT, "game", "assets", "audio")
OUT = os.path.join(ROOT, "qa", "tmp", "audio")

# loudness rules per category: (max peak dBFS, rms range for loops)
PEAK_MAX = {"ui": -7.0, "sfx": -3.0, "ambience": -3.0, "music": -1.0}
RMS_RANGE = {"ambience": (-29.0, -21.5), "music": (-23.0, -17.5)}


def db(x: float) -> float:
	return 20.0 * np.log10(max(float(x), 1e-12))


def short_term_max_rms(mono: np.ndarray, sr: int, win: float = 0.4) -> float:
	n = max(1, int(win * sr))
	if len(mono) <= n:
		return db(np.sqrt(np.mean(mono ** 2)))
	c = np.cumsum(np.concatenate([[0.0], mono ** 2]))
	e = (c[n:] - c[:-n]) / n
	return db(np.sqrt(np.max(e)))


def k_weighting_sos(sr: int) -> np.ndarray:
	"""ITU-R BS.1770 K-weighting (high-shelf pre-filter + RLB high-pass) for any sample rate."""
	import math
	f0, gain, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
	k = math.tan(math.pi * f0 / sr)
	vh = 10.0 ** (gain / 20.0)
	vb = vh ** 0.4996667741545416
	a0 = 1.0 + k / q + k * k
	shelf = [(vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
		1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]
	f0, q = 38.13547087602444, 0.5003270373238773
	k = math.tan(math.pi * f0 / sr)
	a0 = 1.0 + k / q + k * k
	hp = [1.0, -2.0, 1.0, 1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]
	return np.array([shelf, hp])


def short_term_k(mono: np.ndarray, sr: int, win: float = 0.1) -> float:
	"""Loudest short-term K-weighted level (dB, ungated). A rough loudness proxy that makes spiky
	clicks, tonal squeaks and low thumps comparable (peak levels do not)."""
	y = signal.sosfilt(k_weighting_sos(sr), mono)
	n = max(1, int(win * sr))
	if len(y) <= n:
		return db(np.sqrt(np.mean(y ** 2)))
	c = np.cumsum(np.concatenate([[0.0], y ** 2]))
	return db(np.sqrt(np.max((c[n:] - c[:-n]) / n)))


def band_share_db(mono: np.ndarray, sr: int, lo: float, hi: float) -> float:
	"""Share of the signal's energy between lo and hi Hz, in dB (0 = everything)."""
	spec = np.abs(np.fft.rfft(mono)) ** 2
	f = np.fft.rfftfreq(len(mono), 1.0 / sr)
	return 10.0 * np.log10(max(float(np.sum(spec[(f >= lo) & (f < hi)])), 1e-20) / max(float(np.sum(spec)), 1e-20))


# Mix-balance rules checked on the one-shots (short-term K-weighted level). These encode design
# decisions from the review, so a re-render cannot silently undo them:
#   * the four footstep surfaces sound about equally loud (group means within FOOTSTEP_SPREAD dB);
#   * the stalker telegraph and its arachnophobia twin are comparably clear (TELEGRAPH_GAP dB);
#   * a tiny companion's squeak never outshouts the boss shriek (COMPANION_UNDER_SHRIEK dB below).
FOOTSTEP_SPREAD = 3.0
TELEGRAPH_GAP = 5.0
COMPANION_UNDER_SHRIEK = 1.0
SILK_TONE_SHARE_MAX = -4.0      # amb_silk: 2-4 kHz tones stay a quiet bed, not the main content


def balance_checks(results: list) -> list:
	"""Returns report lines; lines starting with '!!' are failures."""
	lv = {r["name"][:-4]: r["st_k"] for r in results if "st_k" in r}

	def group(prefix: str) -> list:
		return [v for k, v in lv.items() if k == prefix or (k.startswith(prefix + "_") and k[len(prefix) + 1:].isdigit())]

	def mean_db(vals: list) -> float:
		return db(np.sqrt(np.mean([10.0 ** (v / 10.0) for v in vals]))) if vals else -240.0

	out = ["", "Mix balance (short-term K-weighted level of the file, dB; see analyze.py for the rules)"]
	steps = {s: mean_db(group("step_" + s)) for s in ("grass", "stone", "wood", "water")}
	spread = max(steps.values()) - min(steps.values())
	out.append("%s footsteps %s  spread %.1f dB (max %.1f)" % ("!!" if spread > FOOTSTEP_SPREAD else "  ",
		"  ".join("%s %.1f" % kv for kv in steps.items()), spread, FOOTSTEP_SPREAD))
	if "weaver_rattle" in lv and "shade_telegraph" in lv:
		gap = abs(lv["weaver_rattle"] - lv["shade_telegraph"])
		out.append("%s telegraphs weaver_rattle %.1f vs shade_telegraph %.1f  gap %.1f dB (max %.1f)" % (
			"!!" if gap > TELEGRAPH_GAP else "  ", lv["weaver_rattle"], lv["shade_telegraph"], gap, TELEGRAPH_GAP))
	shriek = min([lv[k] for k in ("weaver_shriek", "shade_shriek") if k in lv] or [0.0])
	for c in ("mochi_chirp", "mochi_happy", "mochi_scared", "pebble_clack", "pebble_happy", "pebble_grunt",
			"lumi_chime", "lumi_happy", "lumi_warn"):
		g = group(c)
		if g:
			loud = max(g)
			bad = loud > shriek - COMPANION_UNDER_SHRIEK
			out.append("%s companion %-13s loudest %.1f (must stay <= %.1f)" % ("!!" if bad else "  ", c, loud,
				shriek - COMPANION_UNDER_SHRIEK))
	for r in results:
		if r["name"] == "amb_silk.wav" and "tone_share" in r:
			bad = r["tone_share"] > SILK_TONE_SHARE_MAX
			out.append("%s amb_silk 2-4 kHz share %.1f dB (max %.1f)" % ("!!" if bad else "  ", r["tone_share"],
				SILK_TONE_SHARE_MAX))
	return out


def attack_time(mono: np.ndarray, sr: int) -> float:
	"""Seconds from the start until the envelope first reaches -6 dB below its peak."""
	env = np.abs(mono)
	k = max(1, int(0.01 * sr))
	env = np.convolve(env, np.ones(k) / k, mode="same")
	pk = np.max(env)
	idx = np.nonzero(env >= pk * 0.5)[0]
	return float(idx[0] / sr) if idx.size else 0.0


def analyze_file(path: str, cat: str) -> dict:
	x, sr, loop = read_wav(path)
	ch = 1 if x.ndim == 1 else x.shape[1]
	mono = x if x.ndim == 1 else x.mean(axis=1)
	allc = x if x.ndim == 2 else x[:, None]
	peak = np.max(np.abs(allc))
	r = {"name": os.path.basename(path), "cat": cat, "sr": sr, "ch": ch, "frames": len(x),
		"dur": len(x) / sr, "peak": db(peak), "rms": db(np.sqrt(np.mean(allc ** 2))),
		"st_rms": short_term_max_rms(mono, sr), "clip": int(np.sum(np.abs(allc) >= 32767 / 32768.0)),
		"loop": loop, "issues": []}
	if cat in ("ui", "sfx"):
		r["st_k"] = short_term_k(mono, sr)
	if r["name"] == "amb_silk.wav":
		r["tone_share"] = band_share_db(mono, sr, 2000.0, 4000.0)
	if sr != 44100:
		r["issues"].append("sample rate %d" % sr)
	want_ch = 2 if cat in ("ambience", "music") else 1
	if ch != want_ch:
		r["issues"].append("expected %d channel(s)" % want_ch)
	if r["clip"] > 0:
		r["issues"].append("%d clipped samples" % r["clip"])
	if r["peak"] > PEAK_MAX[cat] + 0.05:
		r["issues"].append("peak %.1f dBFS above %.1f" % (r["peak"], PEAK_MAX[cat]))
	if cat in RMS_RANGE:
		lo, hi = RMS_RANGE[cat]
		if not (lo <= r["rms"] <= hi):
			r["issues"].append("RMS %.1f outside %.1f..%.1f" % (r["rms"], lo, hi))
	if loop is None:
		if cat in ("ambience", "music"):
			r["issues"].append("not marked as a loop")
		# one-shots must start and end near silence (fades) - no clicks
		edge_start = db(np.max(np.abs(allc[:1])))
		edge_end = db(np.max(np.abs(allc[-1:])))
		r["edges"] = (edge_start, edge_end)
		if edge_start > -60 or edge_end > -60:
			r["issues"].append("edge not faded (start %.0f dB, end %.0f dB)" % (edge_start, edge_end))
	else:
		start, end = loop
		if start != 0 or end != len(x) - 1:
			r["issues"].append("unexpected loop points %s for %d frames" % (loop, len(x)))
		seg = allc[start:end]
		# the extra wrap frame must equal the first frame
		if not np.allclose(allc[end], allc[start], atol=1.5 / 32768):
			r["issues"].append("wrap frame differs from first frame")
		# seam discontinuity vs the signal's own sample-to-sample motion
		d = np.abs(np.diff(seg, axis=0))
		typical = np.percentile(d, 99.9)
		jump = np.max(np.abs(seg[0] - seg[-1]))
		r["seam_jump"] = jump
		r["seam_ratio"] = jump / max(typical, 1e-9)
		if r["seam_ratio"] > 1.0:
			r["issues"].append("loop seam jump %.4f > 99.9th pct step %.4f" % (jump, typical))
		# level continuity across the seam (50 ms each side), judged against the file's own
		# window-to-window level changes (a musical downbeat at the loop start is legitimate)
		w = int(0.05 * sr)
		a = db(np.sqrt(np.mean(seg[-w:] ** 2)))
		b = db(np.sqrt(np.mean(seg[:w] ** 2)))
		r["seam_level"] = (a, b)
		k = len(seg) // w
		lv = np.array([db(np.sqrt(np.mean(seg[i * w:(i + 1) * w] ** 2))) for i in range(k)])
		steps = np.abs(np.diff(lv))
		limit = max(6.0, float(np.max(steps)) + 3.0) if steps.size else 6.0
		r["seam_level_limit"] = limit
		if abs(a - b) > limit and max(a, b) > -40:
			r["issues"].append("level jump across seam %.1f -> %.1f dB (max elsewhere %.1f)" % (a, b, limit - 3.0))
	if r["name"].startswith("stinger_major"):
		r["attack"] = attack_time(mono, sr)
		if r["attack"] < 0.3:
			r["issues"].append("stinger rises too suddenly (%.2fs)" % r["attack"])
		if r["peak"] > -3.0:
			r["issues"].append("stinger peak above -3 dBFS")
	return r


# ------------------------------------------------------------------------------------------
# Spectrograms
# ------------------------------------------------------------------------------------------

_CMAP = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21],
	[250, 193, 39], [252, 255, 164]], dtype=float)


def colormap(v: np.ndarray) -> np.ndarray:
	v = np.clip(v, 0, 1) * (len(_CMAP) - 1)
	i = np.clip(np.floor(v).astype(int), 0, len(_CMAP) - 2)
	f = (v - i)[..., None]
	return (_CMAP[i] * (1 - f) + _CMAP[i + 1] * f).astype(np.uint8)


def spectrogram_png(path: str, png: str, width: int = 1400, height: int = 420) -> None:
	from PIL import Image, ImageDraw
	x, sr, loop = read_wav(path)
	mono = x if x.ndim == 1 else x.mean(axis=1)
	nper = 2048
	hop = max(64, len(mono) // width)
	f, t, Z = signal.stft(mono, sr, nperseg=nper, noverlap=max(0, nper - hop), boundary=None)
	mag = 20 * np.log10(np.abs(Z) + 1e-9)
	# log-frequency rows (30 Hz .. 18 kHz)
	fl = np.geomspace(30, 18000, height)
	rows = np.array([np.interp(fl, f, mag[:, k]) for k in range(mag.shape[1])]).T
	cols = np.linspace(0, rows.shape[1] - 1, width).astype(int)
	img = rows[:, cols][::-1]
	top = np.max(img)
	v = (img - (top - 90)) / 90.0
	rgb = colormap(v)
	# amplitude strip on top
	strip_h = 70
	env = np.abs(mono)
	seg = np.array_split(env, width)
	pk = np.array([np.max(s) if len(s) else 0 for s in seg])
	rms = np.array([np.sqrt(np.mean(s ** 2)) if len(s) else 0 for s in seg])
	canvas = Image.new("RGB", (width, height + strip_h + 18), (18, 16, 24))
	canvas.paste(Image.fromarray(rgb), (0, strip_h + 18))
	d = ImageDraw.Draw(canvas)
	for i in range(width):
		p = min(1.0, pk[i]) * (strip_h - 4)
		q = min(1.0, rms[i]) * (strip_h - 4)
		d.line([(i, strip_h - p), (i, strip_h)], fill=(110, 100, 150))
		d.line([(i, strip_h - q), (i, strip_h)], fill=(230, 200, 120))
	for fr in (100, 1000, 10000):
		y = strip_h + 18 + int((1 - np.log(fr / 30) / np.log(18000 / 30)) * (height - 1))
		d.line([(0, y), (12, y)], fill=(255, 255, 255))
		d.text((14, y - 6), "%dk" % (fr // 1000) if fr >= 1000 else "%d" % fr, fill=(255, 255, 255))
	d.text((4, strip_h + 2), "%s  %.1fs  %s" % (os.path.basename(path), len(mono) / sr, "loop" if loop else ""), fill=(255, 255, 255))
	os.makedirs(os.path.dirname(png), exist_ok=True)
	canvas.save(png)


def contact_sheets(paths: list, out_dir: str, per_page: int = 24, tile=(420, 170)) -> list:
	"""Small spectrogram + waveform tiles for many one-shots, 3 columns per page."""
	from PIL import Image, ImageDraw
	tw, th = tile
	cols = 3
	pages = []
	for p0 in range(0, len(paths), per_page):
		chunk = paths[p0:p0 + per_page]
		rows = (len(chunk) + cols - 1) // cols
		sheet = Image.new("RGB", (cols * tw, rows * th), (18, 16, 24))
		for i, path in enumerate(chunk):
			x, sr, _ = read_wav(path)
			mono = x if x.ndim == 1 else x.mean(axis=1)
			nper = 1024
			hop = max(16, len(mono) // (tw - 10))
			f, t, Z = signal.stft(mono, sr, nperseg=nper, noverlap=max(0, nper - hop), boundary="zeros")
			mag = 20 * np.log10(np.abs(Z) + 1e-9)
			h = th - 58
			fl = np.geomspace(40, 18000, h)
			img = np.array([np.interp(fl, f, mag[:, k]) for k in range(mag.shape[1])]).T[::-1]
			cols_idx = np.linspace(0, img.shape[1] - 1, tw - 10).astype(int)
			img = img[:, cols_idx]
			v = (img - (np.max(img) - 80)) / 80.0
			tile_img = Image.fromarray(colormap(v))
			cx, cy = (i % cols) * tw, (i // cols) * th
			sheet.paste(tile_img, (cx + 5, cy + 52))
			d = ImageDraw.Draw(sheet)
			seg = np.array_split(np.abs(mono), tw - 10)
			pk = np.array([np.max(s) if len(s) else 0 for s in seg])
			for k in range(tw - 10):
				a = min(1.0, pk[k]) * 30
				d.line([(cx + 5 + k, cy + 48 - a), (cx + 5 + k, cy + 48)], fill=(230, 200, 120))
			d.text((cx + 6, cy + 2), "%s  %.2fs  pk %.1f" % (os.path.basename(path)[:-4], len(mono) / sr,
				db(np.max(np.abs(mono)))), fill=(255, 255, 255))
		out = os.path.join(out_dir, "sheet_%02d.png" % (len(pages) + 1))
		os.makedirs(out_dir, exist_ok=True)
		sheet.save(out)
		pages.append(out)
	return pages


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--spectrograms", default="loops", choices=["all", "loops", "none"])
	ap.add_argument("--sheets", action="store_true", help="contact sheets of all one-shots")
	args = ap.parse_args()
	sys.path.insert(0, HERE)
	from catalog import REQUIRED
	results = []
	for cat in ("ui", "sfx", "ambience", "music"):
		d = os.path.join(AUDIO, cat)
		if not os.path.isdir(d):
			continue
		for f in sorted(os.listdir(d)):
			if f.endswith(".wav"):
				results.append(analyze_file(os.path.join(d, f), cat))
	names = {r["name"][:-4] for r in results}
	missing = []
	for cat, lst in REQUIRED.items():
		for n in lst:
			if n not in names and not any(k.startswith(n + "_") and k[len(n) + 1:].isdigit() for k in names):
				missing.append(n)
	lines = ["Hollowhaven audio report", "=" * 24, "",
		"NOTE: this report is generated by analysis only. Nobody has listened to these files during",
		"the automated build; levels, seams and spectra were checked numerically and visually.", ""]
	hdr = "%-28s %-8s %2s %7s %7s %7s %7s %7s  %s" % ("file", "cat", "ch", "dur s", "peak", "rms", "stRMS", "stK",
		"notes")
	lines += ["stK = loudest 100 ms of K-weighted level (a loudness proxy for one-shots).", "", hdr, "-" * len(hdr)]
	bad = 0
	total_bytes = 0
	for r in results:
		extra = ""
		if r["loop"]:
			extra = "loop seam jump %.5f (x%.2f of 99.9%% step), seam level %.1f/%.1f dB" % (
				r["seam_jump"], r["seam_ratio"], r["seam_level"][0], r["seam_level"][1])
		if "attack" in r:
			extra += " attack %.2fs" % r["attack"]
		if r["issues"]:
			bad += 1
			extra += "  !! " + "; ".join(r["issues"])
		stk = ("%7.1f" % r["st_k"]) if "st_k" in r else "%7s" % "-"
		lines.append("%-28s %-8s %2d %7.2f %7.1f %7.1f %7.1f %s  %s" % (r["name"], r["cat"], r["ch"], r["dur"], r["peak"],
			r["rms"], r["st_rms"], stk, extra))
		total_bytes += r["frames"] * r["ch"] * 2
	balance = balance_checks(results)
	bad_balance = sum(1 for ln in balance if ln.startswith("!!"))
	lines += balance
	lines += ["", "files: %d   total PCM: %.1f MB   files with issues: %d   balance failures: %d   missing names: %s" % (
		len(results), total_bytes / 1048576.0, bad, bad_balance, ", ".join(missing) if missing else "none")]
	for cat in ("ui", "sfx", "ambience", "music"):
		rs = [r for r in results if r["cat"] == cat]
		if rs:
			lines.append("%-9s peak %.1f..%.1f dBFS   rms %.1f..%.1f dBFS   %d files, %.0f s" % (cat,
				min(r["peak"] for r in rs), max(r["peak"] for r in rs), min(r["rms"] for r in rs),
				max(r["rms"] for r in rs), len(rs), sum(r["dur"] for r in rs)))
	os.makedirs(OUT, exist_ok=True)
	with open(os.path.join(OUT, "report.txt"), "w", encoding="utf-8") as fh:
		fh.write("\n".join(lines) + "\n")
	print("\n".join(lines[-7:]))
	if args.spectrograms != "none":
		for r in results:
			if args.spectrograms == "all" or r["cat"] in ("music", "ambience"):
				src = os.path.join(AUDIO, r["cat"], r["name"])
				spectrogram_png(src, os.path.join(OUT, "spectrograms", r["name"][:-4] + ".png"))
	if args.sheets:
		shots = [os.path.join(AUDIO, r["cat"], r["name"]) for r in results if r["cat"] in ("ui", "sfx")]
		for p in contact_sheets(shots, os.path.join(OUT, "sheets")):
			print("sheet: " + p)
	return 1 if (bad or bad_balance or missing) else 0


if __name__ == "__main__":
	sys.exit(main())
