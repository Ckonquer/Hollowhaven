"""Loudness / peak / seam measurements for the Manor & Works cues (group_manor_works.py).

ITU-R BS.1770-4 style integrated loudness implemented in numpy/scipy:
  * K-weighting (high-shelf pre-filter + RLB high-pass, coefficients derived for any rate),
  * mean square per channel over 400 ms blocks with 75 % overlap, channel weights 1.0 (L/R),
  * absolute gate -70 LUFS, relative gate -10 LU below the ungated-by-relative mean.
True peak: 4x polyphase oversampling (BS.1770 Annex 2 style), max |x| in dBTP.
Also: short-term (3 s) loudness track, loop-seam checks and a spectrogram PNG writer.
"""
from __future__ import annotations

import math
import os

import numpy as np
from scipy import signal

SR = 44100


def k_weighting_sos(sr: int = SR) -> np.ndarray:
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


def _block_power(x: np.ndarray, sr: int, win: float, hop: float) -> np.ndarray:
	"""Channel-summed mean square of the K-weighted signal per block."""
	x = x if x.ndim == 2 else x[:, None]
	y = signal.sosfilt(k_weighting_sos(sr), x, axis=0)
	p = np.sum(y * y, axis=1)
	c = np.concatenate([[0.0], np.cumsum(p)])
	n = int(round(win * sr))
	h = int(round(hop * sr))
	if len(p) < n:
		return np.array([c[-1] / max(len(p), 1)])
	starts = np.arange(0, len(p) - n + 1, h)
	return (c[starts + n] - c[starts]) / n


def _lufs(z) -> np.ndarray:
	return -0.691 + 10.0 * np.log10(np.maximum(z, 1e-20))


def integrated_lufs(x: np.ndarray, sr: int = SR) -> float:
	z = _block_power(x, sr, 0.4, 0.1)
	l = _lufs(z)
	z = z[l > -70.0]
	if not len(z):
		return -120.0
	rel = _lufs(np.mean(z)) - 10.0
	z2 = z[_lufs(z) > rel]
	return float(_lufs(np.mean(z2))) if len(z2) else -120.0


def short_term_lufs(x: np.ndarray, sr: int = SR, hop: float = 0.5) -> np.ndarray:
	"""3 s sliding loudness (EBU R128 short-term), one value per hop."""
	return _lufs(_block_power(x, sr, 3.0, hop))


def true_peak_db(x: np.ndarray) -> float:
	x = x if x.ndim == 2 else x[:, None]
	up = signal.resample_poly(x, 4, 1, axis=0)
	return 20.0 * math.log10(max(float(np.max(np.abs(up))), float(np.max(np.abs(x))), 1e-12))


def sample_peak_db(x: np.ndarray) -> float:
	return 20.0 * math.log10(max(float(np.max(np.abs(x))), 1e-12))


def silence_gaps(x: np.ndarray, sr: int = SR, thresh_db: float = -60.0, min_len: float = 3.0) -> list:
	"""Stretches (start_s, end_s) where the 50 ms RMS stays below thresh_db for > min_len s."""
	m = x if x.ndim == 1 else np.mean(x, axis=1)
	w = int(0.05 * sr)
	k = len(m) // w
	r = np.sqrt(np.mean(m[:k * w].reshape(k, w) ** 2, axis=1))
	quiet = 20 * np.log10(r + 1e-12) < thresh_db
	out = []
	i = 0
	while i < k:
		if quiet[i]:
			j = i
			while j < k and quiet[j]:
				j += 1
			if (j - i) * 0.05 > min_len:
				out.append((i * 0.05, j * 0.05))
			i = j
		else:
			i += 1
	return out


def seam_report(x: np.ndarray, sr: int = SR) -> dict:
	"""For a loop: jump between the last and first frame vs the 99.9th percentile of the file's own
	sample-to-sample steps, and 50 ms RMS level either side of the seam vs the file's typical
	window-to-window level changes. Also a 'rolled' check: the wrapped signal around the seam is
	high-passed at 2 kHz and its local max is compared to the rest (a click would stand out)."""
	d = np.abs(np.diff(x, axis=0))
	typical = float(np.percentile(d, 99.9))
	jump = float(np.max(np.abs(x[0] - x[-1])))
	w = int(0.05 * sr)
	a = 20 * np.log10(np.sqrt(np.mean(x[-w:] ** 2)) + 1e-12)
	b = 20 * np.log10(np.sqrt(np.mean(x[:w] ** 2)) + 1e-12)
	k = len(x) // w
	lv = 20 * np.log10(np.sqrt(np.mean(x[:k * w].reshape(k, w, -1) ** 2, axis=(1, 2))) + 1e-12)
	steps = np.abs(np.diff(lv))
	rolled = np.roll(x, len(x) // 2, axis=0)          # the seam now sits in the middle
	hp = signal.sosfilt(signal.butter(4, 2000, "highpass", fs=sr, output="sos"), rolled, axis=0)
	mid = len(x) // 2
	seam_hf = float(np.max(np.abs(hp[mid - 256:mid + 256])))
	hf_p99 = float(np.percentile(np.max(np.abs(hp), axis=1), 99.9))
	return {"jump": jump, "typical_step": typical, "jump_ratio": jump / max(typical, 1e-9),
		"level_end_db": float(a), "level_start_db": float(b), "level_diff_db": float(abs(a - b)),
		"level_step_p95_db": float(np.percentile(steps, 95)), "level_step_max_db": float(np.max(steps)),
		"seam_hf": seam_hf, "hf_p999": hf_p99, "seam_hf_ratio": seam_hf / max(hf_p99, 1e-9)}


def seam_vs_downbeats(x: np.ndarray, bar_times, sr: int = SR, win: float = 0.005) -> dict:
	"""Compares the loop seam with the file's own musical downbeats. The loop is played 'around the
	corner' (last second + file + first second, so the seam is heard exactly as the game loops it and
	the filter has settled), high-passed (> 2 kHz), and the peak within +-win of the seam is compared
	with the same measure at every other bar start. A click at the seam would exceed what the music
	does on its own downbeats (ratio well above 1)."""
	n = len(x)
	P = min(sr, n)
	ext = np.concatenate([x[-P:], x, x[:P]], axis=0)
	hp = signal.sosfilt(signal.butter(4, 2000, "highpass", fs=sr, output="sos"), ext, axis=0)
	mag = np.max(np.abs(hp), axis=1)
	w = int(win * sr)

	def peak_at(i):
		j = P + int(i) % n
		return float(np.max(mag[j - w:j + w]))
	seam = max(peak_at(0), float(np.max(mag[P + n - w:P + n + w])))
	others = [peak_at(int(round(t * sr))) for t in bar_times[1:]]
	# second difference (slope change) at the seam vs the file's 99.9th percentile
	d2 = np.abs(np.diff(x, n=2, axis=0))
	ext = np.concatenate([x[-2:], x[:2]], axis=0)
	seam_d2 = float(np.max(np.abs(np.diff(ext, n=2, axis=0))))
	return {"seam_hf": seam, "downbeat_hf_max": max(others) if others else 0.0,
		"downbeat_hf_median": float(np.median(others)) if others else 0.0,
		"seam_vs_downbeat_max": seam / max(max(others) if others else 1e-9, 1e-9),
		"seam_d2_ratio": seam_d2 / max(float(np.percentile(d2, 99.9)), 1e-9)}


def band_balance(x: np.ndarray, sr: int = SR) -> dict:
	"""Energy share (dB) in low / low-mid / mid / presence / air bands."""
	m = x if x.ndim == 1 else np.mean(x, axis=1)
	f, p = signal.welch(m, sr, nperseg=8192)
	tot = float(np.sum(p)) + 1e-20
	bands = {"sub<60": (0, 60), "low60-250": (60, 250), "lowmid250-1k": (250, 1000), "mid1-4k": (1000, 4000),
		"pres4-10k": (4000, 10000), "air>10k": (10000, 22050)}
	return {k: round(10 * math.log10(max(float(np.sum(p[(f >= lo) & (f < hi)])), 1e-20) / tot), 1)
		for k, (lo, hi) in bands.items()}


# ------------------------------------------------------------------------------------------
# Spectrogram PNG (same look as tools/audio/analyze.py, plus section markers)
# ------------------------------------------------------------------------------------------

_CMAP = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21],
	[250, 193, 39], [252, 255, 164]], dtype=float)


def _colormap(v: np.ndarray) -> np.ndarray:
	v = np.clip(v, 0, 1) * (len(_CMAP) - 1)
	i = np.clip(np.floor(v).astype(int), 0, len(_CMAP) - 2)
	f = (v - i)[..., None]
	return (_CMAP[i] * (1 - f) + _CMAP[i + 1] * f).astype(np.uint8)


def spectrogram_png(x: np.ndarray, png: str, title: str, marks=(), sr: int = SR, width: int = 1400,
		height: int = 420) -> None:
	"""marks = [(seconds, label), ...] drawn as vertical lines (section boundaries)."""
	from PIL import Image, ImageDraw
	mono = x if x.ndim == 1 else x.mean(axis=1)
	nper = 2048
	hop = max(64, len(mono) // width)
	f, t, Z = signal.stft(mono, sr, nperseg=nper, noverlap=max(0, nper - hop), boundary=None)
	mag = 20 * np.log10(np.abs(Z) + 1e-9)
	fl = np.geomspace(30, 18000, height)
	rows = np.array([np.interp(fl, f, mag[:, k]) for k in range(mag.shape[1])]).T
	cols = np.linspace(0, rows.shape[1] - 1, width).astype(int)
	img = rows[:, cols][::-1]
	top = np.max(img)
	rgb = _colormap((img - (top - 90)) / 90.0)
	strip_h = 70
	seg = np.array_split(np.abs(mono), width)
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
	dur = len(mono) / sr
	for sec, label in marks:
		xp = int(sec / dur * (width - 1))
		d.line([(xp, strip_h + 18), (xp, strip_h + 18 + height)], fill=(120, 230, 255))
		d.text((xp + 3, strip_h + 20), label, fill=(120, 230, 255))
	d.text((4, strip_h + 2), "%s  %.1fs" % (title, dur), fill=(255, 255, 255))
	os.makedirs(os.path.dirname(png), exist_ok=True)
	canvas.save(png)
