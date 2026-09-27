"""Space: panning, synthetic impulse responses (rooms, halls, caves) and convolution reverb."""
from __future__ import annotations

import numpy as np
from scipy import signal

from .core import SR, ns, to_stereo
from . import filters as F


def pan(x: np.ndarray, p: float) -> np.ndarray:
	"""Equal-power pan of a mono signal, p in [-1 (left), 1 (right)] -> (n, 2)."""
	a = (np.clip(p, -1.0, 1.0) + 1.0) * 0.25 * np.pi
	return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * np.sqrt(2.0)


def pan_moving(x: np.ndarray, p: np.ndarray) -> np.ndarray:
	"""Pan with a per-sample position array."""
	a = (np.clip(p[:len(x)], -1.0, 1.0) + 1.0) * 0.25 * np.pi
	return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * np.sqrt(2.0)


def width(x: np.ndarray, amount: float) -> np.ndarray:
	"""Mid/side stereo width (1 = unchanged, 0 = mono, >1 wider)."""
	m = (x[:, 0] + x[:, 1]) * 0.5
	s = (x[:, 0] - x[:, 1]) * 0.5 * amount
	return np.stack([m + s, m - s], axis=1)


def impulse_response(t60: float, rng: np.random.Generator, predelay: float = 0.012, damping: float = 0.5,
		early=None, brightness: float = 8000.0, stereo: bool = True, length: float | None = None) -> np.ndarray:
	"""Synthetic reverb IR: decorrelated noise whose bands decay at different rates (highs die
	first, `damping` 0..1), optional discrete early reflections [(time, gain), ...] and a
	pre-delay. Normalised to unit energy per channel so `wet` levels are intuitive."""
	length = length if length is not None else t60 * 1.15
	n = ns(length)
	t = np.arange(n) / SR
	chans = []
	band_edges = [(20, 250), (250, 1200), (1200, 4000), (4000, 16000)]
	decay_mul = [1.15, 1.0, 1.0 - 0.45 * damping, 1.0 - 0.75 * damping]
	for c in range(2 if stereo else 1):
		tail = np.zeros(n)
		for (lo, hi), dm in zip(band_edges, decay_mul):
			nz = F.bandpass(rng.standard_normal(n), lo, min(hi, SR * 0.45), 2)
			tail += nz * np.exp(-6.907755 * t / max(t60 * dm, 0.02))
		tail = F.lowpass(tail, brightness, 1)
		# smooth onset of the diffuse tail
		m = ns(0.012)
		tail[:m] *= np.linspace(0, 1, m) ** 2
		ir = np.zeros(n + ns(predelay) + 1)
		ir[ns(predelay):ns(predelay) + n] += tail
		if early:
			for (et, eg) in early:
				j = ns(predelay + et * rng.uniform(0.92, 1.08))
				if j < len(ir) - 64:
					blip = np.hanning(24) * rng.choice([-1.0, 1.0])
					ir[j:j + 24] += blip * eg * np.sqrt(np.sum(tail ** 2)) * 0.12
		ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
		chans.append(ir)
	return np.stack(chans, axis=1) if stereo else chans[0]


def hall(rng: np.random.Generator, t60: float = 2.6, brightness: float = 7000.0) -> np.ndarray:
	return impulse_response(t60, rng, predelay=0.02, damping=0.55, brightness=brightness,
		early=[(0.011, 0.6), (0.019, 0.5), (0.027, 0.45), (0.041, 0.35), (0.053, 0.3)])


def room(rng: np.random.Generator, t60: float = 0.6, brightness: float = 9000.0) -> np.ndarray:
	return impulse_response(t60, rng, predelay=0.004, damping=0.4, brightness=brightness,
		early=[(0.004, 0.7), (0.009, 0.5), (0.014, 0.4)])


def cave(rng: np.random.Generator, t60: float = 4.0, echoes=((0.16, 0.5), (0.29, 0.35), (0.47, 0.22), (0.71, 0.14)),
		brightness: float = 3500.0) -> np.ndarray:
	"""Big dark cave: long, dark tail plus distinct slap-back echoes off far walls."""
	ir = impulse_response(t60, rng, predelay=0.03, damping=0.85, brightness=brightness,
		early=[(0.013, 0.5), (0.027, 0.4)])
	n = len(ir)
	for (et, eg) in echoes:
		for c in range(2):
			j = ns(0.03 + et * rng.uniform(0.95, 1.05) + (0.004 * c))
			if j < n - 2000:
				smear = F.lowpass(rng.standard_normal(ns(0.03)) * np.hanning(ns(0.03)), brightness * 0.8, 2)
				smear /= np.sqrt(np.sum(smear ** 2)) + 1e-12
				ir[j:j + len(smear), c] += smear * eg
	ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True)) + 1e-12
	return ir


def reverb(x: np.ndarray, ir: np.ndarray, wet: float = 0.25, dry: float = 1.0, tail: bool = True) -> np.ndarray:
	"""Convolution reverb. Mono input + stereo IR -> stereo. With tail=True the output is
	longer than the input by the IR length (callers trim, fade or fold it into a loop)."""
	xs = to_stereo(x) if ir.ndim == 2 else x
	if ir.ndim == 2:
		w = np.stack([signal.oaconvolve(xs[:, c], ir[:, c]) for c in range(2)], axis=1)
	else:
		w = signal.oaconvolve(xs, ir)
	out = w * wet
	out[:len(xs)] += xs * dry
	return out if tail else out[:len(xs)]


def reverb_mono(x: np.ndarray, ir: np.ndarray, wet: float = 0.25, dry: float = 1.0) -> np.ndarray:
	"""Mono reverb for SFX (uses the left channel of a stereo IR)."""
	h = ir[:, 0] if ir.ndim == 2 else ir
	w = signal.oaconvolve(x, h)
	out = w * wet
	out[:len(x)] += x * dry
	return out


def distant(x: np.ndarray, meters: float) -> np.ndarray:
	"""Air absorption & distance: darker and quieter with distance."""
	fc = 16000.0 / (1.0 + meters / 12.0)
	return F.lowpass(x, fc, 2) / (1.0 + meters / 8.0)


def echoes(x: np.ndarray, taps) -> np.ndarray:
	"""Discrete echoes [(delay_s, gain, lowpass_hz), ...]; output extended by the longest delay."""
	longest = max(t for t, _, _ in taps)
	pad = [(0, ns(longest) + 1)] + ([(0, 0)] if x.ndim == 2 else [])
	out = np.pad(x, pad)
	for t, g, lp in taps:
		d = ns(t)
		y = F.lowpass(x, lp, 2) if lp else x
		out[d:d + len(x)] += y * g
	return out
