"""Loudness helpers for the home/woods music group (owned by group_home_woods.py).

ITU-R BS.1770-4 style integrated loudness (K-weighting, 400 ms blocks with 75 % overlap,
absolute gate -70 LUFS, relative gate -10 LU), a 4x-oversampled true-peak estimate, short-term
loudness curves and a few analysis helpers. Plain numpy/scipy, no external loudness package."""
from __future__ import annotations

import math

import numpy as np
from scipy import signal

SR = 44100


def k_weighting_sos(sr: int = SR) -> np.ndarray:
	"""BS.1770 K-weighting (stage 1 high shelf + stage 2 RLB high-pass), exact for any rate."""
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


def _as_channels(x: np.ndarray) -> np.ndarray:
	x = np.asarray(x, dtype=np.float64)
	return x[:, None] if x.ndim == 1 else x


def _block_powers(x: np.ndarray, sr: int, block: float, overlap: float) -> np.ndarray:
	"""Mean-square of K-weighted signal per block, summed over channels (G = 1 for L/R)."""
	x = _as_channels(x)
	y = signal.sosfilt(k_weighting_sos(sr), x, axis=0)
	n = int(round(block * sr))
	hop = max(1, int(round(n * (1.0 - overlap))))
	if len(y) < n:
		return np.array([np.sum(np.mean(y ** 2, axis=0))])
	c = np.cumsum(np.concatenate([np.zeros((1, y.shape[1])), y ** 2], axis=0), axis=0)
	starts = np.arange(0, len(y) - n + 1, hop)
	ms = (c[starts + n] - c[starts]) / n
	return np.sum(ms, axis=1)


def integrated_lufs(x: np.ndarray, sr: int = SR) -> float:
	"""Gated integrated loudness (LUFS)."""
	z = _block_powers(x, sr, 0.4, 0.75)
	lk = -0.691 + 10.0 * np.log10(np.maximum(z, 1e-20))
	z1 = z[lk > -70.0]
	if z1.size == 0:
		return -70.0
	rel = -0.691 + 10.0 * np.log10(np.mean(z1)) - 10.0
	z2 = z[(lk > -70.0) & (lk > rel)]
	if z2.size == 0:
		return -70.0
	return float(-0.691 + 10.0 * np.log10(np.mean(z2)))


def short_term_curve(x: np.ndarray, sr: int = SR, win: float = 3.0, hop: float = 1.0) -> np.ndarray:
	"""Short-term loudness (3 s window) every `hop` seconds, LUFS."""
	x = _as_channels(x)
	y = signal.sosfilt(k_weighting_sos(sr), x, axis=0)
	n = int(win * sr)
	h = int(hop * sr)
	c = np.cumsum(np.concatenate([np.zeros((1, y.shape[1])), y ** 2], axis=0), axis=0)
	starts = np.arange(0, max(1, len(y) - n + 1), h)
	ms = np.sum((c[np.minimum(starts + n, len(y))] - c[starts]) / n, axis=1)
	return -0.691 + 10.0 * np.log10(np.maximum(ms, 1e-20))


def loudness_range(x: np.ndarray, sr: int = SR) -> float:
	"""EBU Tech 3342 style LRA (10th..95th percentile of gated short-term loudness)."""
	st = short_term_curve(x, sr, 3.0, 0.1)
	st = st[st > -70.0]
	if st.size < 2:
		return 0.0
	rel = 10.0 * np.log10(np.mean(10.0 ** (st / 10.0))) - 20.0
	st = st[st > rel]
	return float(np.percentile(st, 95) - np.percentile(st, 10))


def true_peak_db(x: np.ndarray, oversample: int = 4) -> float:
	"""Inter-sample peak estimate (dBTP) via polyphase 4x oversampling."""
	x = _as_channels(x)
	up = signal.resample_poly(x, oversample, 1, axis=0)
	pk = max(float(np.max(np.abs(up))), float(np.max(np.abs(x))))
	return 20.0 * np.log10(max(pk, 1e-12))


def sample_peak_db(x: np.ndarray) -> float:
	return 20.0 * np.log10(max(float(np.max(np.abs(x))), 1e-12))


def silence_gaps(x: np.ndarray, sr: int = SR, thresh_db: float = -50.0, min_len: float = 3.0,
		win: float = 0.05) -> list:
	"""Spans (start_s, end_s) longer than min_len where the RMS (50 ms windows) stays below
	thresh_db dBFS. Leading/trailing spans are included (the caller decides what is intended)."""
	x = _as_channels(x)
	mono = np.mean(x, axis=1)
	n = int(win * sr)
	k = len(mono) // n
	lv = 10.0 * np.log10(np.mean(mono[:k * n].reshape(k, n) ** 2, axis=1) + 1e-20)
	quiet = lv < thresh_db
	gaps = []
	i = 0
	while i < k:
		if quiet[i]:
			j = i
			while j < k and quiet[j]:
				j += 1
			if (j - i) * win >= min_len:
				gaps.append((i * win, j * win))
			i = j
		else:
			i += 1
	return gaps


def band_balance(x: np.ndarray, sr: int = SR) -> dict:
	"""Energy share (dB relative to total) in low / low-mid / mid / high / air bands."""
	mono = np.mean(_as_channels(x), axis=1)
	f, p = signal.welch(mono, sr, nperseg=8192)
	tot = np.sum(p) + 1e-30
	bands = {"sub<60": (0, 60), "low60-250": (60, 250), "lowmid250-1k": (250, 1000), "mid1k-4k": (1000, 4000),
		"high4k-10k": (4000, 10000), "air>10k": (10000, sr / 2)}
	out = {}
	for name, (lo, hi) in bands.items():
		out[name] = round(10.0 * np.log10(np.sum(p[(f >= lo) & (f < hi)]) / tot + 1e-20), 1)
	cent = float(np.sum(f * p) / tot)
	out["centroid_hz"] = round(cent, 0)
	return out
