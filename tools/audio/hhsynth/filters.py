"""Filters: Butterworth (scipy sos), RBJ-cookbook biquads, swept (time-varying) biquads and
formant banks. All functions accept mono (n,) or stereo (n, 2) signals."""
from __future__ import annotations

import numpy as np
from scipy import signal

from .core import SR, ns


def _nyq_clip(f: float) -> float:
	return float(np.clip(f, 5.0, SR * 0.49))


def lowpass(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
	sos = signal.butter(order, _nyq_clip(fc), "lowpass", fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


def highpass(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
	sos = signal.butter(order, _nyq_clip(fc), "highpass", fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
	lo, hi = _nyq_clip(lo), _nyq_clip(hi)
	if hi <= lo * 1.01:
		hi = lo * 1.05
	sos = signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


def zero_phase_lowpass(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
	sos = signal.butter(order, _nyq_clip(fc), "lowpass", fs=SR, output="sos")
	return signal.sosfiltfilt(sos, x, axis=0)


# --- RBJ cookbook biquads -------------------------------------------------------------------

def biquad(kind: str, fc: float, q: float = 0.707, gain_db: float = 0.0):
	"""Returns (b, a) for kind in lowpass/highpass/bandpass/notch/peak/lowshelf/highshelf."""
	fc = _nyq_clip(fc)
	w0 = 2.0 * np.pi * fc / SR
	cw, sw = np.cos(w0), np.sin(w0)
	alpha = sw / (2.0 * max(q, 1e-3))
	A = 10.0 ** (gain_db / 40.0)
	if kind == "lowpass":
		b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "highpass":
		b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "bandpass":       # constant 0 dB peak gain
		b = [alpha, 0.0, -alpha]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "notch":
		b = [1.0, -2 * cw, 1.0]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "peak":
		b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
		a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
	elif kind == "lowshelf":
		sq = 2 * np.sqrt(A) * alpha
		b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sq)]
		a = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sq]
	elif kind == "highshelf":
		sq = 2 * np.sqrt(A) * alpha
		b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sq)]
		a = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sq]
	else:
		raise ValueError(kind)
	b = np.array(b) / a[0]
	a = np.array(a) / a[0]
	return b, a


def rbj(x: np.ndarray, kind: str, fc: float, q: float = 0.707, gain_db: float = 0.0) -> np.ndarray:
	b, a = biquad(kind, fc, q, gain_db)
	return signal.lfilter(b, a, x, axis=0)


def peak_eq(x: np.ndarray, fc: float, gain_db: float, q: float = 1.0) -> np.ndarray:
	return rbj(x, "peak", fc, q, gain_db)


def resonator(x: np.ndarray, fc: float, q: float = 8.0) -> np.ndarray:
	"""Constant-peak bandpass (ringing resonance)."""
	return rbj(x, "bandpass", fc, q)


def formants(x: np.ndarray, bank) -> np.ndarray:
	"""Parallel resonances: bank = [(fc, q, gain), ...]."""
	out = np.zeros_like(x)
	for fc, q, g in bank:
		out += g * rbj(x, "bandpass", fc, q)
	return out


# --- Swept (time-varying) biquad ------------------------------------------------------------

def sweep(x: np.ndarray, kind: str, fc, q=0.707, block: int = 64, gain_db: float = 0.0) -> np.ndarray:
	"""Biquad whose cutoff (and optionally q) changes over time. fc/q may be scalars or
	per-sample arrays; coefficients update every `block` samples (state carried across)."""
	if x.ndim == 2:
		return np.stack([sweep(x[:, c], kind, fc, q, block, gain_db) for c in range(x.shape[1])], axis=1)
	n = len(x)
	fcs = np.full(n, float(fc)) if np.isscalar(fc) else np.asarray(fc, dtype=float)
	qs = np.full(n, float(q)) if np.isscalar(q) else np.asarray(q, dtype=float)
	if len(fcs) < n:
		fcs = np.concatenate([fcs, np.full(n - len(fcs), fcs[-1])])
	if len(qs) < n:
		qs = np.concatenate([qs, np.full(n - len(qs), qs[-1])])
	y = np.empty(n)
	zi = np.zeros(2)
	for s in range(0, n, block):
		e = min(n, s + block)
		m = (s + e) // 2
		b, a = biquad(kind, fcs[m], qs[m], gain_db)
		y[s:e], zi = signal.lfilter(b, a, x[s:e], zi=zi)
	return y


def sweep_points(x: np.ndarray, kind: str, points, q=0.707, block: int = 64) -> np.ndarray:
	"""sweep() with a cutoff contour through (time, hz) points (log-interpolated)."""
	n = len(x)
	t = np.arange(n) / SR
	xs = np.array([p[0] for p in points], dtype=float)
	ys = np.log(np.array([p[1] for p in points], dtype=float))
	return sweep(x, kind, np.exp(np.interp(t, xs, ys)), q, block)


def tilt(x: np.ndarray, db_per_octave_hint: float = -3.0, pivot: float = 1000.0) -> np.ndarray:
	"""Cheap spectral tilt: low shelf up + high shelf down around a pivot."""
	g = db_per_octave_hint * 2.0
	y = rbj(x, "lowshelf", pivot / 2.0, 0.6, -g / 2.0)
	return rbj(y, "highshelf", pivot * 2.0, 0.6, g / 2.0)


def env_follow(x: np.ndarray, smooth: float = 0.01) -> np.ndarray:
	"""Amplitude envelope (rectify + lowpass)."""
	mag = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
	sos = signal.butter(1, 1.0 / max(smooth, 1e-4), "lowpass", fs=SR, output="sos")
	return np.maximum(signal.sosfiltfilt(sos, mag), 0.0)


def delay(x: np.ndarray, seconds: float) -> np.ndarray:
	d = ns(seconds)
	pad = [(d, 0)] + ([(0, 0)] if x.ndim == 2 else [])
	return np.pad(x, pad)[:len(x)]
