"""Measurement helpers for the Chapter One tension cues (owned by group_ch1_tension.py).

* ITU-R BS.1770-4 style integrated loudness: K-weighting (pre-filter shelf + RLB high-pass),
  400 ms blocks with 75 % overlap, absolute gate -70 LUFS, relative gate -10 LU, channel
  weights 1.0 for L/R. Loops are measured periodically (the filters are warmed up on the end
  of the loop, so the seam is measured the way the player hears it).
* True peak: 4x oversampling (polyphase FIR, as in BS.1770 Annex 2), periodic for loops.
* Loop seam checks, silence-gap finder, band-energy balance and a spectrogram PNG writer
  (PIL only - matplotlib is not installed) with section markers.

Plain numpy/scipy. Nothing here writes audio."""
from __future__ import annotations

import math
import os

import numpy as np
from scipy import signal

SR = 44100


def db(x: float) -> float:
	return 20.0 * math.log10(max(float(x), 1e-12))


def _stereo(x: np.ndarray) -> np.ndarray:
	x = np.asarray(x, dtype=np.float64)
	return x[:, None] if x.ndim == 1 else x


def k_weighting_sos(sr: int = SR) -> np.ndarray:
	"""BS.1770 K-weighting as two biquads, derived for any sample rate (matches the published
	48 kHz coefficients exactly at 48 kHz)."""
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


def k_filter(x: np.ndarray, sr: int = SR, periodic: bool = False) -> np.ndarray:
	x = _stereo(x)
	sos = k_weighting_sos(sr)
	if periodic:
		pad = min(len(x), sr * 2)
		ext = np.concatenate([x[-pad:], x], axis=0)
		return signal.sosfilt(sos, ext, axis=0)[pad:]
	return signal.sosfilt(sos, x, axis=0)


def block_loudness(x: np.ndarray, sr: int = SR, block: float = 0.4, overlap: float = 0.75,
		periodic: bool = False) -> np.ndarray:
	"""Per-block loudness (LUFS, ungated) of 400 ms blocks with 75 % overlap."""
	y = k_filter(x, sr, periodic)
	n = int(round(block * sr))
	hop = max(1, int(round(n * (1.0 - overlap))))
	if periodic:          # blocks may wrap around the loop end
		y = np.concatenate([y, y[:n]], axis=0)
		starts = np.arange(0, len(x), hop)
	else:
		starts = np.arange(0, max(1, len(y) - n + 1), hop)
	starts = starts[starts + n <= len(y)]
	e = np.sum(np.square(y), axis=1)            # G = 1.0 for L and R
	c = np.concatenate([[0.0], np.cumsum(e)])
	z = (c[starts + n] - c[starts]) / n
	return -0.691 + 10.0 * np.log10(np.maximum(z, 1e-20))


def integrated_loudness(x: np.ndarray, sr: int = SR, periodic: bool = False) -> float:
	"""BS.1770-4 gated integrated loudness in LUFS."""
	lk = block_loudness(x, sr, periodic=periodic)
	z = 10.0 ** ((lk + 0.691) / 10.0)
	g1 = lk > -70.0
	if not np.any(g1):
		return -120.0
	rel = -0.691 + 10.0 * np.log10(np.mean(z[g1])) - 10.0
	g2 = g1 & (lk > rel)
	return float(-0.691 + 10.0 * np.log10(np.mean(z[g2])))


def short_term(x: np.ndarray, sr: int = SR, win: float = 3.0, hop: float = 1.0, periodic: bool = False):
	"""Short-term loudness curve (3 s windows): returns (times, LUFS)."""
	y = k_filter(x, sr, periodic)
	n = int(win * sr)
	h = int(hop * sr)
	if periodic:
		y = np.concatenate([y, y[:n]], axis=0)
	e = np.sum(np.square(y), axis=1)
	c = np.concatenate([[0.0], np.cumsum(e)])
	top = len(x) if periodic else len(y) - n
	starts = np.arange(0, max(1, top), h)
	starts = starts[starts + n <= len(y)]
	z = (c[starts + n] - c[starts]) / n
	return (starts + n / 2) / sr, -0.691 + 10.0 * np.log10(np.maximum(z, 1e-20))


def true_peak_trace(x: np.ndarray, periodic: bool = False, over: int = 4) -> np.ndarray:
	"""Per-sample true-peak magnitude (max over channels and over the `over` interpolated points
	that follow each sample)."""
	x = _stereo(x)
	pad = 64
	if periodic:
		ext = np.concatenate([x[-pad:], x, x[:pad]], axis=0)
	else:
		ext = np.concatenate([np.zeros((pad, x.shape[1])), x, np.zeros((pad, x.shape[1]))], axis=0)
	up = signal.resample_poly(ext, over, 1, axis=0, window=("kaiser", 8.0))
	up = up[pad * over:(pad + len(x)) * over]
	mag = np.max(np.abs(up), axis=1).reshape(len(x), over)
	return np.maximum(np.max(mag, axis=1), np.max(np.abs(x), axis=1))


def true_peak_db(x: np.ndarray, periodic: bool = False) -> float:
	return db(np.max(true_peak_trace(x, periodic)))


def sample_peak_db(x: np.ndarray) -> float:
	return db(np.max(np.abs(x)))


def loop_seam(x: np.ndarray, sr: int = SR) -> dict:
	"""Seam discontinuity (last sample -> first sample) against the signal's own sample-to-sample
	motion, and RMS continuity of the 50 ms either side of the seam against the file's own
	window-to-window level changes (same rules as tools/audio/analyze.py)."""
	x = _stereo(x)
	d = np.abs(np.diff(x, axis=0))
	typical = float(np.percentile(d, 99.9))
	jump = float(np.max(np.abs(x[0] - x[-1])))
	w = int(0.05 * sr)
	a = db(np.sqrt(np.mean(x[-w:] ** 2)))
	b = db(np.sqrt(np.mean(x[:w] ** 2)))
	k = len(x) // w
	lv = np.array([db(np.sqrt(np.mean(x[i * w:(i + 1) * w] ** 2))) for i in range(k)])
	steps = np.abs(np.diff(lv))
	p99 = float(np.percentile(steps, 99)) if steps.size else 0.0
	# the 1 s either side of the seam: short windows, same measure
	w2 = int(1.0 * sr)
	a2 = db(np.sqrt(np.mean(x[-w2:] ** 2)))
	b2 = db(np.sqrt(np.mean(x[:w2] ** 2)))
	return {"jump": jump, "typical_step": typical, "ratio": jump / max(typical, 1e-9),
		"rms_end_db": a, "rms_start_db": b, "rms_step_db": abs(a - b), "window_step_p99_db": p99,
		"window_step_max_db": float(np.max(steps)) if steps.size else 0.0,
		"rms_1s_end_db": a2, "rms_1s_start_db": b2,
		"ok": bool(jump / max(typical, 1e-9) <= 1.0 and (abs(a - b) <= max(6.0, p99 + 3.0) or max(a, b) < -40))}


def silence_gaps(x: np.ndarray, sr: int = SR, thresh_db: float = -50.0, min_len: float = 3.0,
		periodic: bool = False) -> list:
	"""Stretches (start_s, end_s) longer than min_len where the 50 ms RMS stays below thresh_db
	(absolute dBFS). For loops a gap may wrap around the seam."""
	x = _stereo(x)
	w = int(0.05 * sr)
	k = len(x) // w
	lv = np.array([db(np.sqrt(np.mean(x[i * w:(i + 1) * w] ** 2))) for i in range(k)])
	quiet = lv < thresh_db
	gaps = []
	if periodic and np.all(quiet):
		return [(0.0, len(x) / sr)]
	i = 0
	if periodic and quiet[0]:
		# rotate so we start on a loud window
		first_loud = int(np.argmin(quiet))
		quiet = np.roll(quiet, -first_loud)
		offset = first_loud
	else:
		offset = 0
	while i < k:
		if quiet[i]:
			j = i
			while j < k and quiet[j]:
				j += 1
			if (j - i) * w / sr >= min_len:
				s = ((i + offset) % k) * w / sr
				gaps.append((round(s, 2), round(s + (j - i) * w / sr, 2)))
			i = j
		else:
			i += 1
	return gaps


BANDS = [("sub <60", 20, 60), ("bass 60-250", 60, 250), ("lowmid 250-1k", 250, 1000),
	("mid 1-4k", 1000, 4000), ("high 4-10k", 4000, 10000), ("air >10k", 10000, 20000)]


def band_balance(x: np.ndarray, sr: int = SR) -> dict:
	"""Share of energy per band in dB relative to the total (Welch PSD of the mono sum)."""
	x = _stereo(x)
	mono = np.mean(x, axis=1)
	f, p = signal.welch(mono, sr, nperseg=8192)
	tot = float(np.sum(p)) + 1e-30
	out = {}
	for name, lo, hi in BANDS:
		out[name] = round(10.0 * math.log10(max(float(np.sum(p[(f >= lo) & (f < hi)])), 1e-30) / tot), 1)
	# spectral centroid
	out["centroid_hz"] = round(float(np.sum(f * p) / tot), 0)
	return out


# ------------------------------------------------------------------------------------------
# Spectrogram PNG (PIL)
# ------------------------------------------------------------------------------------------

_CMAP = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21],
	[250, 193, 39], [252, 255, 164]], dtype=float)


def _colormap(v: np.ndarray) -> np.ndarray:
	v = np.clip(v, 0, 1) * (len(_CMAP) - 1)
	i = np.clip(np.floor(v).astype(int), 0, len(_CMAP) - 2)
	f = (v - i)[..., None]
	return (_CMAP[i] * (1 - f) + _CMAP[i + 1] * f).astype(np.uint8)


def spectrogram_png(x: np.ndarray, png: str, title: str, sections=None, sr: int = SR, width: int = 1600,
		height: int = 440, fmin: float = 30.0, fmax: float = 16000.0) -> None:
	"""Log-frequency spectrogram with an RMS/peak strip on top and labelled section markers.
	sections = [(label, start_s), ...]."""
	from PIL import Image, ImageDraw
	x = _stereo(x)
	mono = np.mean(x, axis=1)
	nper = 4096
	hop = max(64, len(mono) // width)
	f, t, Z = signal.stft(mono, sr, nperseg=nper, noverlap=max(0, nper - hop), boundary=None)
	mag = 20 * np.log10(np.abs(Z) + 1e-9)
	fl = np.geomspace(fmin, fmax, height)
	rows = np.array([np.interp(fl, f, mag[:, k]) for k in range(mag.shape[1])]).T
	cols = np.linspace(0, rows.shape[1] - 1, width).astype(int)
	img = rows[:, cols][::-1]
	top = np.percentile(img, 99.9)
	v = (img - (top - 85)) / 85.0
	rgb = _colormap(v)
	strip_h = 90
	head = 20
	dur = len(mono) / sr
	canvas = Image.new("RGB", (width, height + strip_h + head + 16), (18, 16, 24))
	canvas.paste(Image.fromarray(rgb), (0, strip_h + head))
	d = ImageDraw.Draw(canvas)
	seg = np.array_split(np.abs(mono), width)
	pk = np.array([np.max(s) if len(s) else 0 for s in seg])
	rms = np.array([np.sqrt(np.mean(s ** 2)) if len(s) else 0 for s in seg])
	# dB scale strip: -60..0 dBFS
	def ydb(a):
		return (np.clip(20 * np.log10(np.maximum(a, 1e-6)), -60, 0) + 60) / 60.0
	for i in range(width):
		p = ydb(pk[i]) * (strip_h - 4)
		q = ydb(rms[i]) * (strip_h - 4)
		d.line([(i, head + strip_h - p), (i, head + strip_h)], fill=(110, 100, 150))
		d.line([(i, head + strip_h - q), (i, head + strip_h)], fill=(230, 200, 120))
	for fr in (50, 100, 250, 1000, 4000, 10000):
		y = strip_h + head + int((1 - math.log(fr / fmin) / math.log(fmax / fmin)) * (height - 1))
		d.line([(0, y), (10, y)], fill=(255, 255, 255))
		d.text((12, y - 6), "%dk" % (fr // 1000) if fr >= 1000 else "%d" % fr, fill=(255, 255, 255))
	for sec in range(0, int(dur) + 1, 10):
		xx = int(sec / dur * (width - 1))
		d.line([(xx, height + strip_h + head), (xx, height + strip_h + head + 5)], fill=(200, 200, 200))
		d.text((xx + 2, height + strip_h + head + 3), "%ds" % sec, fill=(200, 200, 200))
	for label, st in (sections or []):
		xx = int(st / dur * (width - 1))
		d.line([(xx, head), (xx, head + strip_h + height)], fill=(120, 255, 160))
		d.text((xx + 3, head + 2), label, fill=(120, 255, 160))
	d.text((4, 3), "%s   %.1f s   (strip: peak/RMS, -60..0 dBFS)" % (title, dur), fill=(255, 255, 255))
	os.makedirs(os.path.dirname(png), exist_ok=True)
	canvas.save(png)
