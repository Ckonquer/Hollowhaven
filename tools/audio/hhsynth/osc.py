"""Oscillators. `freq` may be a scalar or a per-sample array (glides, vibrato, FM)."""
from __future__ import annotations

import numpy as np

from .core import SR, ns


def _freq_array(freq, n: int) -> np.ndarray:
	if np.isscalar(freq):
		return np.full(n, float(freq))
	f = np.asarray(freq, dtype=float)
	if len(f) < n:
		f = np.concatenate([f, np.full(n - len(f), f[-1] if len(f) else 0.0)])
	return f[:n]


def phase(freq, dur: float, phase0: float = 0.0) -> np.ndarray:
	"""Phase in cycles (unwrapped) for a constant or time-varying frequency."""
	n = ns(dur)
	if np.isscalar(freq):
		return phase0 + float(freq) * np.arange(n) / SR
	f = _freq_array(freq, n)
	return phase0 + np.concatenate([[0.0], np.cumsum(f[:-1])]) / SR


def sine(freq, dur: float, phase0: float = 0.0) -> np.ndarray:
	return np.sin(2.0 * np.pi * phase(freq, dur, phase0))


def _polyblep(p: np.ndarray, dt: np.ndarray) -> np.ndarray:
	out = np.zeros_like(p)
	a = p < dt
	x = p[a] / dt[a]
	out[a] = x + x - x * x - 1.0
	b = p > 1.0 - dt
	x = (p[b] - 1.0) / dt[b]
	out[b] = x * x + x + x + 1.0
	return out


def saw(freq, dur: float, phase0: float = 0.0) -> np.ndarray:
	"""Band-limited (polyBLEP) sawtooth, -1..1."""
	n = ns(dur)
	p = np.mod(phase(freq, dur, phase0), 1.0)
	dt = np.clip(np.abs(_freq_array(freq, n)) / SR, 1e-6, 0.5)
	return 2.0 * p - 1.0 - _polyblep(p, dt)


def pulse(freq, dur: float, width: float = 0.5, phase0: float = 0.0) -> np.ndarray:
	"""Band-limited pulse/square wave."""
	n = ns(dur)
	p = np.mod(phase(freq, dur, phase0), 1.0)
	dt = np.clip(np.abs(_freq_array(freq, n)) / SR, 1e-6, 0.5)
	y = np.where(p < width, 1.0, -1.0)
	y += _polyblep(p, dt)
	y -= _polyblep(np.mod(p + 1.0 - width, 1.0), dt)
	return y


def triangle(freq, dur: float, phase0: float = 0.0) -> np.ndarray:
	p = np.mod(phase(freq, dur, phase0) + 0.25, 1.0)
	return 4.0 * np.abs(p - 0.5) - 1.0


def additive(freq, dur: float, partials, phase_rng: np.random.Generator | None = None) -> np.ndarray:
	"""Sum of harmonics/partials: partials = [(ratio, amp), ...]. Partials above Nyquist are skipped."""
	n = ns(dur)
	base = phase(freq, dur)
	fmax = float(np.max(_freq_array(freq, n))) if n else 0.0
	out = np.zeros(n)
	for ratio, amp in partials:
		if fmax * ratio >= SR * 0.45:
			continue
		ph = phase_rng.uniform(0, 1) if phase_rng is not None else 0.0
		out += amp * np.sin(2.0 * np.pi * (base * ratio + ph))
	return out


def glide(f0: float, f1: float, dur: float, curve: str = "exp", total: float | None = None) -> np.ndarray:
	"""Frequency ramp from f0 to f1 over dur, holding f1 until total (default dur)."""
	n = ns(total if total is not None else dur)
	m = max(1, ns(dur))
	u = np.clip(np.arange(n) / m, 0.0, 1.0)
	if curve == "exp":
		return f0 * (f1 / f0) ** u
	if curve == "ease":
		u = 0.5 - 0.5 * np.cos(np.pi * u)
	return f0 + (f1 - f0) * u


def glide_points(points, dur: float) -> np.ndarray:
	"""Frequency contour through (time, hz) points, interpolated in log-frequency."""
	n = ns(dur)
	t = np.arange(n) / SR
	xs = np.array([p[0] for p in points], dtype=float)
	ys = np.log(np.array([p[1] for p in points], dtype=float))
	return np.exp(np.interp(t, xs, ys))


def vibrato(base, dur: float, rate: float = 5.0, cents: float = 15.0, delay: float = 0.0,
		rise: float = 0.3, phase0: float = 0.0) -> np.ndarray:
	"""Applies a (delayed, fading-in) sinusoidal vibrato to a frequency (scalar or array)."""
	n = ns(dur)
	t = np.arange(n) / SR
	depth = np.clip((t - delay) / max(rise, 1e-3), 0.0, 1.0) * cents
	f = _freq_array(base, n)
	return f * 2.0 ** (depth * np.sin(2 * np.pi * (rate * t + phase0)) / 1200.0)
