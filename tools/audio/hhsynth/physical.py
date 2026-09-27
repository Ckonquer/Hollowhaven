"""Physically flavoured generators: modal resonators (wood, stone, glass), Karplus-Strong plucks,
stick-slip creaks, granular crunches/rustles and water bubbles."""
from __future__ import annotations

import numpy as np
from scipy import signal

from .core import SR, ns, env_perc
from . import filters as F
from . import osc


def modal(freqs, amps, t60s, dur: float, rng: np.random.Generator | None = None, attack: float = 0.0006) -> np.ndarray:
	"""Sum of exponentially decaying sine modes (a struck object)."""
	n = ns(dur)
	t = np.arange(n) / SR
	out = np.zeros(n)
	for f, a, t60 in zip(freqs, amps, t60s):
		if f >= SR * 0.45:
			continue
		ph = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
		out += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-6.907755 * t / max(t60, 1e-4))
	if attack > 0:
		m = min(n, ns(attack))
		out[:m] *= np.linspace(0, 1, m)
	return out


def resonate(exc: np.ndarray, freqs, t60s, amps) -> np.ndarray:
	"""Drives two-pole resonators (one per mode) with an excitation signal. Good for giving
	knocks, scrapes and creaks a material 'body'. Each mode's impulse response has amplitude
	`amp` (independent of its decay time)."""
	out = np.zeros(len(exc))
	for f, t60, a in zip(freqs, t60s, amps):
		if f >= SR * 0.45:
			continue
		r = np.exp(-6.907755 / (max(t60, 1e-4) * SR))
		w = 2 * np.pi * f / SR
		b = [np.sin(w)]
		aa = [1.0, -2.0 * r * np.cos(w), r * r]
		out += a * signal.lfilter(b, aa, exc)
	return out


def ks_pluck(freq: float, dur: float, rng: np.random.Generator, t60: float = 2.0, bright: float = 0.5,
		pos: float = 0.18, soft: float = 0.0) -> np.ndarray:
	"""Karplus-Strong plucked string, accurately tuned by resampling.
	bright 0..1 = excitation brightness, pos = pluck position (comb), soft = extra lowpass 0..1."""
	n_out = ns(dur)
	period = SR / freq - 0.5          # the 2-tap average adds half a sample of delay
	N = max(2, int(np.floor(period)))
	f_act = SR / (N + 0.5)
	ratio = freq / f_act                # <= 1: read slower to lower the pitch
	total = int(n_out * ratio) + N + 4
	exc = rng.uniform(-1, 1, N)
	cutoff = 800.0 + bright * bright * 9000.0
	exc = F.zero_phase_lowpass(np.concatenate([exc, exc, exc]), cutoff, 1)[N:2 * N]
	d = max(1, int(pos * N))
	exc = exc - np.roll(exc, d) * 0.9
	exc -= np.mean(exc)
	exc /= max(np.max(np.abs(exc)), 1e-9)
	rho = 0.001 ** (N / (SR * max(t60, 0.05)))
	y = np.zeros(total)
	y[:N] = exc
	for s in range(N, total, N):
		e = min(s + N, total)
		m = e - s
		a = y[s - N:s - N + m]
		if s - N - 1 >= 0:
			b = y[s - N - 1:s - N - 1 + m]
		else:
			b = np.concatenate([[0.0], y[0:m - 1]])
		y[s:e] = rho * 0.5 * (a + b)
	# resample to the exact pitch
	src_t = np.arange(n_out) * ratio
	out = np.interp(src_t, np.arange(total), y)
	if soft > 0:
		out = F.lowpass(out, 9000.0 - soft * 7000.0, 1)
	# tiny attack smoothing so the pluck starts clean
	m = min(n_out, ns(0.0015))
	out[:m] *= np.linspace(0, 1, m)
	return out


def creak(dur: float, rng: np.random.Generator, rate_points, amp_points, freqs, t60s, amps,
		jitter: float = 0.12) -> np.ndarray:
	"""Stick-slip creak: an irregular impulse train (slip rate contour in Hz, typically 20-250;
	the rate is heard as the creak's pitch) exciting wooden resonances. `jitter` is the timing
	spread as a fraction of the slip period; the rate itself also wobbles a little."""
	n = ns(dur)
	t = np.arange(n) / SR
	rate = np.exp(np.interp(t, [p[0] for p in rate_points], np.log([p[1] for p in rate_points])))
	wobble = np.interp(t, np.linspace(0, dur, max(2, int(dur * 9))), rng.uniform(-1, 1, max(2, int(dur * 9))))
	rate = rate * (1.0 + 0.12 * wobble)
	ph = np.cumsum(rate) / SR
	idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0]
	exc = np.zeros(n)
	amp = np.interp(t, [p[0] for p in amp_points], [p[1] for p in amp_points])
	for i in idx:
		j = int(np.clip(i + rng.normal(0, jitter * SR / max(rate[i], 1.0)), 0, n - 1))
		exc[j] += amp[i] * rng.uniform(0.4, 1.0) * rng.choice([-1.0, 1.0], p=[0.3, 0.7])
	# each slip is a short noisy tick rather than a perfect impulse
	tick = rng.standard_normal(ns(0.0012)) * np.hanning(ns(0.0012))
	exc = np.convolve(exc, tick)[:n]
	return resonate(exc, freqs, t60s, amps)


def grains(dur: float, rng: np.random.Generator, density, band: tuple, grain_len=(0.002, 0.012),
		n_bands: int = 6, amp_jitter: float = 0.7, q_order: int = 1, decay: bool = True) -> np.ndarray:
	"""Granular texture (crunch, crackle, rustle, gravel). density = grains per second, scalar or a
	list of (time, rate) points; band = (lo_hz, hi_hz). Grains are windowed noise bursts summed
	into a few frequency bands, each band filtered once (fast)."""
	n = ns(dur)
	t_end = n / SR
	if np.isscalar(density):
		pts = [(0.0, float(density)), (t_end, float(density))]
	else:
		pts = list(density)
	xs = np.array([p[0] for p in pts], dtype=float)
	ys = np.array([p[1] for p in pts], dtype=float)
	peak_rate = max(float(np.max(ys)), 1e-6)
	# thinning of a homogeneous Poisson process
	k = rng.poisson(peak_rate * t_end)
	times = np.sort(rng.uniform(0, t_end, k))
	keep = rng.uniform(0, 1, k) < np.interp(times, xs, ys) / peak_rate
	times = times[keep]
	lo, hi = band
	edges = np.geomspace(lo, hi, n_bands + 1)
	buses = np.zeros((n_bands, n))
	for tt in times:
		gl = rng.uniform(grain_len[0], grain_len[1])
		m = max(4, ns(gl))
		s = ns(tt)
		if s >= n:
			continue
		m = min(m, n - s)
		w = np.hanning(m + 2)[1:-1]
		if decay:
			w = w * np.exp(-np.linspace(0, 3.0, m))
		g = rng.standard_normal(m) * w * (1.0 - amp_jitter * rng.uniform(0, 1))
		buses[rng.integers(0, n_bands), s:s + m] += g
	out = np.zeros(n)
	for i in range(n_bands):
		if np.any(buses[i]):
			out += F.bandpass(buses[i], edges[i], edges[i + 1], q_order)
	return out


def bubble(f0: float, dur: float, rise: float = 1.8, t60: float = 0.05, glide_time: float | None = None) -> np.ndarray:
	"""A water 'plip': a sine whose pitch rises (bubble reaching the surface) and decays fast."""
	gt = glide_time if glide_time is not None else t60
	f = osc.glide(f0, f0 * rise, gt, "exp", total=dur)
	return osc.sine(f, dur) * env_perc(dur, 0.0008, t60)


def bubbles(dur: float, rng: np.random.Generator, density, f_range=(500, 2500), t60=(0.02, 0.07),
		rise=(1.2, 2.5), amp=(0.2, 1.0)) -> np.ndarray:
	"""Many bubbles (babbling water, splashes). density scalar or (time, rate) points."""
	n = ns(dur)
	out = np.zeros(n)
	t_end = n / SR
	pts = [(0.0, density), (t_end, density)] if np.isscalar(density) else list(density)
	xs = np.array([p[0] for p in pts], dtype=float)
	ys = np.array([p[1] for p in pts], dtype=float)
	peak = max(float(np.max(ys)), 1e-6)
	k = rng.poisson(peak * t_end)
	times = rng.uniform(0, t_end, k)
	times = times[rng.uniform(0, 1, k) < np.interp(times, xs, ys) / peak]
	for tt in times:
		f0 = float(np.exp(rng.uniform(np.log(f_range[0]), np.log(f_range[1]))))
		tt60 = rng.uniform(*t60)
		b = bubble(f0, tt60 * 1.3, rng.uniform(*rise), tt60) * rng.uniform(*amp)
		s = ns(tt)
		m = min(len(b), n - s)
		if m > 0:
			out[s:s + m] += b[:m]
	return out
