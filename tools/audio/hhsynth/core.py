"""Core helpers: time, envelopes, mixing, fades, loudness, loops and a gentle limiter."""
from __future__ import annotations

import zlib

import numpy as np
from scipy import ndimage, signal

SR = 44100


# ---------------------------------------------------------------------------------------------
# Time & randomness
# ---------------------------------------------------------------------------------------------

def ns(seconds: float) -> int:
	"""Seconds -> sample count."""
	return max(0, int(round(seconds * SR)))


def t_axis(dur: float) -> np.ndarray:
	return np.arange(ns(dur)) / SR


def silence(dur: float, stereo: bool = False) -> np.ndarray:
	return np.zeros((ns(dur), 2)) if stereo else np.zeros(ns(dur))


def rng_for(key: str) -> np.random.Generator:
	"""Deterministic generator from a string key (stable across runs and machines)."""
	return np.random.default_rng(zlib.crc32(key.encode("utf-8")))


def db(x: float) -> float:
	return 10.0 ** (x / 20.0)


def to_db(x: float) -> float:
	return 20.0 * np.log10(max(float(x), 1e-12))


def peak_db(x: np.ndarray) -> float:
	return to_db(np.max(np.abs(x))) if x.size else -240.0


def rms_db(x: np.ndarray) -> float:
	return to_db(np.sqrt(np.mean(np.square(x)))) if x.size else -240.0


# ---------------------------------------------------------------------------------------------
# Envelopes
# ---------------------------------------------------------------------------------------------

def env_points(points, dur: float, curve: str = "lin") -> np.ndarray:
	"""Piecewise envelope through (time, value) points. curve='lin' interpolates amplitude,
	'db' interpolates in decibels (values are linear amplitudes, 0 maps to -90 dB), 'cos' eases."""
	n = ns(dur)
	t = np.arange(n) / SR
	pts = sorted(points, key=lambda p: p[0])
	xs = np.array([p[0] for p in pts], dtype=float)
	ys = np.array([p[1] for p in pts], dtype=float)
	if curve == "db":
		yd = 20.0 * np.log10(np.maximum(ys, db(-90.0)))
		return 10.0 ** (np.interp(t, xs, yd) / 20.0) * (np.interp(t, xs, ys) > 0)
	if curve == "cos":
		out = np.empty(n)
		idx = np.clip(np.searchsorted(xs, t, side="right") - 1, 0, len(xs) - 1)
		nxt = np.clip(idx + 1, 0, len(xs) - 1)
		span = np.maximum(xs[nxt] - xs[idx], 1e-9)
		u = np.clip((t - xs[idx]) / span, 0.0, 1.0)
		u = 0.5 - 0.5 * np.cos(np.pi * u)
		out[:] = ys[idx] + (ys[nxt] - ys[idx]) * u
		return out
	return np.interp(t, xs, ys)


def env_perc(dur: float, attack: float = 0.002, t60: float = 0.3, hold: float = 0.0) -> np.ndarray:
	"""Percussive envelope: raised-cosine attack, optional hold, exponential decay to -60 dB at t60."""
	n = ns(dur)
	t = np.arange(n) / SR
	e = np.exp(-6.907755 * np.maximum(t - attack - hold, 0.0) / max(t60, 1e-4))
	if attack > 0:
		a = t < attack
		e[a] = 0.5 - 0.5 * np.cos(np.pi * t[a] / attack)
	return e


def env_adsr(dur: float, a: float, d: float, s: float, r: float, gate: float | None = None) -> np.ndarray:
	"""ADSR (linear attack, exponential-ish decay/release). gate = note-on length (default dur - r)."""
	n = ns(dur)
	t = np.arange(n) / SR
	g = (dur - r) if gate is None else gate
	e = np.where(t < a, t / max(a, 1e-5), s + (1.0 - s) * np.exp(-(t - a) * 5.0 / max(d, 1e-5)))
	level_at_gate = (g / max(a, 1e-5)) if g < a else s + (1.0 - s) * np.exp(-(g - a) * 5.0 / max(d, 1e-5))
	rel = t >= g
	e[rel] = level_at_gate * np.exp(-(t[rel] - g) * 6.9 / max(r, 1e-5))
	return e


def smooth_random(dur: float, rng: np.random.Generator, rate: float, lo: float = 0.0, hi: float = 1.0,
		periodic: bool = False) -> np.ndarray:
	"""Slowly wandering control signal (cosine-interpolated random points ~rate per second)."""
	n = ns(dur)
	k = max(2, int(np.ceil(dur * rate)) + 1)
	pts = rng.uniform(lo, hi, k)
	if periodic:
		pts[-1] = pts[0]
	xs = np.linspace(0, n, k)
	t = np.arange(n)
	idx = np.clip(np.searchsorted(xs, t, side="right") - 1, 0, k - 2)
	u = (t - xs[idx]) / (xs[idx + 1] - xs[idx])
	u = 0.5 - 0.5 * np.cos(np.pi * u)
	return pts[idx] + (pts[idx + 1] - pts[idx]) * u


# ---------------------------------------------------------------------------------------------
# Mixing
# ---------------------------------------------------------------------------------------------

def to_stereo(x: np.ndarray) -> np.ndarray:
	return x if x.ndim == 2 else np.stack([x, x], axis=1)


def place(dst: np.ndarray, src: np.ndarray, t: float, gain: float = 1.0) -> None:
	"""Adds src into dst starting at time t (seconds); clips at both ends. Mono src into a
	stereo dst is duplicated to both channels."""
	start = ns(t) if t >= 0 else -ns(-t)
	if dst.ndim == 2 and src.ndim == 1:
		src = np.stack([src, src], axis=1)
	s0 = max(0, -start)
	d0 = max(0, start)
	m = min(len(src) - s0, len(dst) - d0)
	if m > 0:
		dst[d0:d0 + m] += src[s0:s0 + m] * gain


def concat(*parts: np.ndarray) -> np.ndarray:
	return np.concatenate(parts, axis=0)


def mix(*parts: np.ndarray) -> np.ndarray:
	"""Sums signals of different lengths (padded with zeros)."""
	n = max(len(p) for p in parts)
	stereo = any(p.ndim == 2 for p in parts)
	out = np.zeros((n, 2)) if stereo else np.zeros(n)
	for p in parts:
		place(out, p, 0.0)
	return out


def pad_to(x: np.ndarray, dur: float) -> np.ndarray:
	n = ns(dur)
	if len(x) >= n:
		return x[:n]
	pad = [(0, n - len(x))] + ([(0, 0)] if x.ndim == 2 else [])
	return np.pad(x, pad)


# ---------------------------------------------------------------------------------------------
# Fades, trimming, normalisation
# ---------------------------------------------------------------------------------------------

def fade(x: np.ndarray, fin: float = 0.003, fout: float = 0.02) -> np.ndarray:
	"""Raised-cosine fade in/out (in place safe copy)."""
	y = x.copy()
	a = min(ns(fin), len(y))
	b = min(ns(fout), len(y))
	if a > 0:
		w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
		y[:a] *= w if y.ndim == 1 else w[:, None]
	if b > 0:
		w = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, b))
		y[-b:] *= w if y.ndim == 1 else w[:, None]
	return y


def trim_tail(x: np.ndarray, thresh_db: float = -70.0, keep: float = 0.03) -> np.ndarray:
	"""Cuts trailing near-silence (relative to the peak), keeping a little room for the fade."""
	mag = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
	pk = np.max(mag) if mag.size else 0.0
	if pk <= 0:
		return x[:ns(0.05)]
	above = np.nonzero(mag > pk * db(thresh_db))[0]
	end = min(len(x), (above[-1] if above.size else 0) + ns(keep))
	return x[:max(end, ns(0.02))]


def trim_head(x: np.ndarray, thresh_db: float = -60.0) -> np.ndarray:
	mag = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
	pk = np.max(mag) if mag.size else 0.0
	above = np.nonzero(mag > pk * db(thresh_db))[0]
	return x[max(0, (above[0] if above.size else 0) - ns(0.001)):]


def normalize_peak(x: np.ndarray, target_db: float) -> np.ndarray:
	pk = np.max(np.abs(x))
	return x if pk <= 0 else x * (db(target_db) / pk)


def normalize_rms(x: np.ndarray, target_db: float) -> np.ndarray:
	r = np.sqrt(np.mean(np.square(x)))
	return x if r <= 0 else x * (db(target_db) / r)


def dc_block(x: np.ndarray, fc: float = 18.0) -> np.ndarray:
	sos = signal.butter(2, fc, "highpass", fs=SR, output="sos")
	return signal.sosfilt(sos, x, axis=0)


# ---------------------------------------------------------------------------------------------
# Loops
# ---------------------------------------------------------------------------------------------

def fold_loop(buf: np.ndarray, n: int) -> np.ndarray:
	"""Folds a buffer longer than the loop (tails, reverb) back onto the first n samples, so
	sounds that ring past the end continue seamlessly at the start: an exactly periodic loop."""
	out = np.zeros((n,) + buf.shape[1:])
	for k in range(0, len(buf), n):
		seg = buf[k:k + n]
		out[:len(seg)] += seg
	return out


def circular(fn, x: np.ndarray, pad: int) -> np.ndarray:
	"""Applies a causal/stateful process fn to a periodic signal without breaking the seam:
	runs it over [tail | x | head] and keeps the middle."""
	pad = min(pad, len(x))
	ext = np.concatenate([x[-pad:], x, x[:pad]], axis=0)
	y = fn(ext)
	return y[pad:pad + len(x)]


def seam_crossfade(buf: np.ndarray, n: int, xfade: float) -> np.ndarray:
	"""Classic loop crossfade: buf must be at least n + xfade long. The part after the loop end
	is equal-power crossfaded into the beginning. Used for material that is not built
	periodically (e.g. recorded-style one-off renders)."""
	m = ns(xfade)
	out = buf[:n].copy()
	tail = buf[n:n + m]
	m = len(tail)
	w = np.linspace(0.0, 1.0, m)
	fi = np.sin(0.5 * np.pi * w)
	fo = np.cos(0.5 * np.pi * w)
	if out.ndim == 2:
		fi = fi[:, None]
		fo = fo[:, None]
	out[:m] = out[:m] * fi + tail * fo
	return out


# ---------------------------------------------------------------------------------------------
# Dynamics
# ---------------------------------------------------------------------------------------------

def limiter(x: np.ndarray, ceiling_db: float = -1.0, window: float = 0.03) -> np.ndarray:
	"""Zero-phase look-ahead peak limiter. The per-sample gain requirement is min-held over
	+/-window and then averaged over one window: the average never exceeds the requirement at
	any sample (so peaks stay under the ceiling) while gain changes stay smooth (~window long).
	Quiet material passes untouched."""
	ceil = db(ceiling_db)
	mag = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=1)
	g = np.minimum(1.0, ceil / np.maximum(mag, 1e-12))
	if np.all(g >= 1.0):
		return x.copy()
	h = max(1, ns(window))
	g = ndimage.minimum_filter1d(g, size=2 * h + 1, mode="nearest")
	g = ndimage.uniform_filter1d(g, size=h, mode="nearest")
	y = x * (g if x.ndim == 1 else g[:, None])
	# hard safety net against float rounding (should never do anything audible)
	return np.clip(y, -ceil, ceil)


def soft_saturate(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
	"""Gentle tanh warmth, level compensated."""
	return np.tanh(x * drive) / np.tanh(drive)
