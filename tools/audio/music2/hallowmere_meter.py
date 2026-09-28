"""Measurement helpers for the Hallowmere music group (m15-m19, m27).

Implements, in plain numpy/scipy:
  * ITU-R BS.1770-4 K-weighting and gated integrated loudness (LUFS), 400 ms blocks, 75 % overlap,
    absolute gate -70 LUFS, relative gate -10 LU; stereo channels weighted 1.0.
  * short-term (3 s) loudness curve and loudness range (EBU Tech 3342 style: 10th..95th percentile
    of relatively gated short-term values).
  * true peak (BS.1770 Annex 2 style: 4x polyphase oversampling, max |sample|).
  * silence-gap finder, loop-seam check, spectral band balance and a spectrogram PNG writer with
    section markers (PIL).

Usage:  python hallowmere_meter.py <file.wav|file.ogg> ...   (prints a summary per file)
"""
from __future__ import annotations

import math
import os
import sys

sys.dont_write_bytecode = True

import numpy as np
from scipy import signal


# ----------------------------------------------------------------------------------------------
# I/O
# ----------------------------------------------------------------------------------------------

def load(path: str):
	"""Returns (float64 stereo (n, 2), sr). WAV files use hhsynth's reader (handles the smpl chunk)."""
	if path.lower().endswith(".wav"):
		here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
		if here not in sys.path:
			sys.path.insert(0, here)
		from hhsynth.wavio import read_wav
		x, sr, _ = read_wav(path)
	else:
		import soundfile as sf
		x, sr = sf.read(path, dtype="float64", always_2d=True)
	if x.ndim == 1:
		x = np.stack([x, x], axis=1)
	return x, sr


# ----------------------------------------------------------------------------------------------
# Loudness
# ----------------------------------------------------------------------------------------------

def k_weighting_sos(sr: int) -> np.ndarray:
	"""BS.1770 pre-filter (high shelf, +4 dB above ~1.7 kHz) and RLB high-pass (~38 Hz), designed by
	bilinear transform for any sample rate (Brecht De Man's parameterisation of the spec filters)."""
	# stage 1: high shelf
	f0, g, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
	k = math.tan(math.pi * f0 / sr)
	vh = 10.0 ** (g / 20.0)
	vb = vh ** 0.4996667741545416
	a0 = 1.0 + k / q + k * k
	b = [(vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
	a = [1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]
	# stage 2: RLB high-pass
	f0, q = 38.13547087602444, 0.5003270373238773
	k = math.tan(math.pi * f0 / sr)
	a0 = 1.0 + k / q + k * k
	b2 = [1.0, -2.0, 1.0]
	a2 = [1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]
	return np.array([b + a, b2 + a2])


def _block_energies(x: np.ndarray, sr: int, block: float, overlap: float) -> np.ndarray:
	"""Mean-square K-weighted energy per block, summed over channels (weights 1.0)."""
	y = signal.sosfilt(k_weighting_sos(sr), x, axis=0)
	n = int(round(block * sr))
	hop = max(1, int(round(n * (1.0 - overlap))))
	if len(y) < n:
		return np.array([np.sum(np.mean(y ** 2, axis=0))])
	c = np.concatenate([np.zeros((1, y.shape[1])), np.cumsum(y ** 2, axis=0)], axis=0)
	starts = np.arange(0, len(y) - n + 1, hop)
	e = (c[starts + n] - c[starts]) / n
	return np.sum(e, axis=1)


def _lufs(e):
	return -0.691 + 10.0 * np.log10(np.maximum(e, 1e-20))


def integrated_lufs(x: np.ndarray, sr: int) -> float:
	e = _block_energies(x, sr, 0.4, 0.75)
	l = _lufs(e)
	e1 = e[l > -70.0]
	if not len(e1):
		return -120.0
	rel = _lufs(np.mean(e1)) - 10.0
	e2 = e[(l > -70.0) & (l > rel)]
	return float(_lufs(np.mean(e2))) if len(e2) else -120.0


def short_term_curve(x: np.ndarray, sr: int, hop_s: float = 0.5) -> np.ndarray:
	"""Short-term (3 s window) loudness every hop_s seconds."""
	e = _block_energies(x, sr, 3.0, 1.0 - hop_s / 3.0)
	return _lufs(e)


def loudness_range(x: np.ndarray, sr: int) -> float:
	st = short_term_curve(x, sr, 1.0 / 3.0)
	st = st[st > -70.0]
	if len(st) < 2:
		return 0.0
	rel = _lufs(np.mean(10 ** ((st + 0.691) / 10.0))) - 20.0
	st = st[st > rel]
	return float(np.percentile(st, 95) - np.percentile(st, 10))


def true_peak_db(x: np.ndarray, oversample: int = 4) -> float:
	up = signal.resample_poly(x, oversample, 1, axis=0)
	return 20.0 * math.log10(max(float(np.max(np.abs(up))), 1e-12))


def sample_peak_db(x: np.ndarray) -> float:
	return 20.0 * math.log10(max(float(np.max(np.abs(x))), 1e-12))


# ----------------------------------------------------------------------------------------------
# Structure checks
# ----------------------------------------------------------------------------------------------

def silence_gaps(x: np.ndarray, sr: int, thresh_db: float = -55.0, min_len: float = 3.0, frame: float = 0.05):
	"""Stretches (start, end) seconds longer than min_len whose 50 ms RMS stays below thresh_db
	(absolute dBFS). The final ring-out after the last note is reported too (callers decide)."""
	m = x.mean(axis=1) if x.ndim == 2 else x
	n = int(frame * sr)
	k = len(m) // n
	r = np.sqrt(np.mean(m[:k * n].reshape(k, n) ** 2, axis=1))
	quiet = 20 * np.log10(r + 1e-12) < thresh_db
	gaps = []
	i = 0
	while i < k:
		if quiet[i]:
			j = i
			while j < k and quiet[j]:
				j += 1
			if (j - i) * frame >= min_len:
				gaps.append((i * frame, j * frame))
			i = j
		else:
			i += 1
	return gaps


def seam_report(x: np.ndarray, sr: int) -> dict:
	"""For LOOP cues: sample jump at the wrap vs typical sample-to-sample steps, and RMS continuity
	of the last/first 250 ms."""
	d = np.abs(np.diff(x, axis=0))
	jump = float(np.max(np.abs(x[0] - x[-1])))
	n = int(0.25 * sr)
	a = 20 * np.log10(np.sqrt(np.mean(x[-n:] ** 2)) + 1e-12)
	b = 20 * np.log10(np.sqrt(np.mean(x[:n] ** 2)) + 1e-12)
	return {"jump": jump, "p999_step": float(np.percentile(d, 99.9)), "rms_end_db": float(a), "rms_start_db": float(b)}


BANDS = [("sub<60", 20, 60), ("low60-250", 60, 250), ("lowmid250-1k", 250, 1000), ("mid1-4k", 1000, 4000),
	("high4-10k", 4000, 10000), ("air>10k", 10000, 20000)]


def band_balance(x: np.ndarray, sr: int) -> dict:
	"""Energy share per band in dB (0 = all energy), via Welch PSD of the mono sum."""
	m = x.mean(axis=1) if x.ndim == 2 else x
	f, p = signal.welch(m, sr, nperseg=8192)
	tot = float(np.sum(p)) + 1e-30
	return {name: round(10 * math.log10(max(float(np.sum(p[(f >= lo) & (f < hi)])), 1e-30) / tot), 1)
		for name, lo, hi in BANDS}


def spectral_centroid(x: np.ndarray, sr: int) -> float:
	m = x.mean(axis=1) if x.ndim == 2 else x
	f, p = signal.welch(m, sr, nperseg=8192)
	return float(np.sum(f * p) / (np.sum(p) + 1e-30))


def measure(x: np.ndarray, sr: int) -> dict:
	return {"duration_s": round(len(x) / sr, 2), "lufs": round(integrated_lufs(x, sr), 2),
		"true_peak_db": round(true_peak_db(x), 2), "sample_peak_db": round(sample_peak_db(x), 2),
		"lra": round(loudness_range(x, sr), 1), "centroid_hz": round(spectral_centroid(x, sr)),
		"bands": band_balance(x, sr)}


# ----------------------------------------------------------------------------------------------
# Spectrogram
# ----------------------------------------------------------------------------------------------

_CMAP = np.array([[8, 6, 20], [40, 16, 80], [110, 30, 110], [190, 60, 80], [240, 130, 40], [252, 220, 120],
	[255, 255, 230]], dtype=float)


def _colormap(v):
	v = np.clip(v, 0, 1) * (len(_CMAP) - 1)
	i = np.clip(np.floor(v).astype(int), 0, len(_CMAP) - 2)
	f = (v - i)[..., None]
	return (_CMAP[i] * (1 - f) + _CMAP[i + 1] * f).astype(np.uint8)


def spectrogram_png(x: np.ndarray, sr: int, png: str, title: str, sections=(), width: int = 1600,
		height: int = 440) -> None:
	"""Log-frequency spectrogram (30 Hz..16 kHz) with a short-term loudness strip on top and
	vertical markers + labels at section starts: sections = [(label, start_s), ...]."""
	from PIL import Image, ImageDraw
	mono = x.mean(axis=1) if x.ndim == 2 else x
	dur = len(mono) / sr
	nper = 4096
	hop = max(256, len(mono) // width)
	f, t, Z = signal.stft(mono, sr, nperseg=nper, noverlap=nper - hop, boundary=None)
	mag = 20 * np.log10(np.abs(Z) + 1e-9)
	fl = np.geomspace(30, 16000, height)
	idx = np.searchsorted(f, fl).clip(1, len(f) - 1)
	rows = mag[idx, :]
	cols = np.linspace(0, rows.shape[1] - 1, width).astype(int)
	img = rows[:, cols][::-1]
	top = np.percentile(img, 99.8)
	rgb = _colormap((img - (top - 80)) / 80.0)
	strip = 90
	canvas = Image.new("RGB", (width, height + strip + 20), (16, 14, 22))
	canvas.paste(Image.fromarray(rgb), (0, strip + 20))
	d = ImageDraw.Draw(canvas)
	st = short_term_curve(x if x.ndim == 2 else np.stack([x, x], 1), sr, 0.25)
	for i in range(width):
		k = min(len(st) - 1, int(i / width * len(st)))
		v = np.clip((st[k] + 45) / 40.0, 0, 1)            # -45..-5 LUFS
		d.line([(i, strip - v * (strip - 6)), (i, strip)], fill=(230, 200, 120))
	for lv in (-30, -20, -10):
		y = strip - np.clip((lv + 45) / 40.0, 0, 1) * (strip - 6)
		d.line([(0, y), (width, y)], fill=(70, 70, 90))
		d.text((width - 34, y - 11), "%d" % lv, fill=(150, 150, 170))
	for fr in (100, 1000, 10000):
		y = strip + 20 + int((1 - math.log(fr / 30) / math.log(16000 / 30)) * (height - 1))
		d.line([(0, y), (12, y)], fill=(255, 255, 255))
		d.text((14, y - 6), "%dk" % (fr // 1000) if fr >= 1000 else "%d" % fr, fill=(255, 255, 255))
	for label, s0 in sections:
		xp = int(s0 / dur * width)
		d.line([(xp, 0), (xp, height + strip + 20)], fill=(120, 230, 255))
		d.text((xp + 3, strip + 4), label, fill=(120, 230, 255))
	d.text((4, 2), "%s  %.1fs  (strip = short-term LUFS)" % (title, dur), fill=(255, 255, 255))
	os.makedirs(os.path.dirname(png), exist_ok=True)
	canvas.save(png)


if __name__ == "__main__":
	for p in sys.argv[1:]:
		x, sr = load(p)
		r = measure(x, sr)
		print(os.path.basename(p), r)
