"""Noise colours. Coloured noise is shaped in the frequency domain, which also makes it exactly
periodic over its length - handy for seamless ambience loops."""
from __future__ import annotations

import numpy as np

from .core import SR, ns


def white(dur: float, rng: np.random.Generator) -> np.ndarray:
	return rng.standard_normal(ns(dur)) * 0.5


def colored(dur: float, rng: np.random.Generator, exponent: float, lo: float = 10.0, hi: float | None = None,
		order: int = 2) -> np.ndarray:
	"""Noise with power spectrum ~ 1/f^exponent (0 white, 1 pink, 2 brown, -1 blue), band-limited
	to [lo, hi] Hz with soft Butterworth-like slopes of `order` (6*order dB/octave; order=0 gives
	brick-wall edges), normalised to RMS 0.25. Periodic over its own length."""
	n = ns(dur)
	if n < 2:
		return np.zeros(n)
	spec = rng.standard_normal(n // 2 + 1) + 1j * rng.standard_normal(n // 2 + 1)
	f = np.fft.rfftfreq(n, 1.0 / SR)
	shape = np.zeros_like(f)
	fmin = SR / n
	if order <= 0:
		ok = f >= max(lo, fmin)
		if hi is not None:
			ok &= f <= hi
		shape[ok] = f[ok] ** (-exponent / 2.0)
	else:
		ok = f >= fmin
		fk = f[ok]
		mag = fk ** (-exponent / 2.0) / np.sqrt(1.0 + (lo / fk) ** (2 * order))
		if hi is not None:
			mag /= np.sqrt(1.0 + (fk / hi) ** (2 * order))
		shape[ok] = mag
	y = np.fft.irfft(spec * shape, n)
	r = np.sqrt(np.mean(y * y))
	return y * (0.25 / r) if r > 0 else y


def pink(dur: float, rng: np.random.Generator, lo: float = 10.0, hi: float | None = None) -> np.ndarray:
	return colored(dur, rng, 1.0, lo, hi)


def brown(dur: float, rng: np.random.Generator, lo: float = 10.0, hi: float | None = None) -> np.ndarray:
	return colored(dur, rng, 2.0, lo, hi)


def band(dur: float, rng: np.random.Generator, lo: float, hi: float, exponent: float = 0.0) -> np.ndarray:
	"""Brick-wall band-limited noise (soft, no filter ringing). Periodic over its length."""
	return colored(dur, rng, exponent, lo, hi)


def crackle(dur: float, rng: np.random.Generator, density: float) -> np.ndarray:
	"""Sparse random impulses (density per second) with random amplitudes and signs."""
	n = ns(dur)
	out = np.zeros(n)
	k = rng.poisson(density * dur)
	if k > 0 and n > 0:
		idx = rng.integers(0, n, k)
		out[idx] += rng.uniform(0.2, 1.0, k) * rng.choice([-1.0, 1.0], k)
	return out
