"""FM voices: generic 2-operator FM, soft bells, glass chimes and woodwind-like tones."""
from __future__ import annotations

import numpy as np

from .core import SR, ns, env_perc, env_adsr, smooth_random
from . import osc
from . import filters as F
from . import noise as N


def fm(freq, dur: float, ratio: float, index, mod_phase: float = 0.0, feedback: float = 0.0) -> np.ndarray:
	"""sin(carrier + index * sin(modulator)); modulator = ratio * carrier frequency. `index` may be a
	per-sample array (an index envelope is what makes FM sounds evolve)."""
	n = ns(dur)
	pc = osc.phase(freq, dur)
	pm = pc * ratio + mod_phase
	idx = index if np.isscalar(index) else np.asarray(index)[:n]
	mod = np.sin(2 * np.pi * pm)
	if feedback > 0:
		mod = np.sin(2 * np.pi * pm + feedback * mod)
	return np.sin(2 * np.pi * pc + idx * mod)


def bell(f: float, dur: float, t60: float = 2.5, ratio: float = 3.5, index: float = 2.0, index_t60: float = 0.25,
		attack: float = 0.001) -> np.ndarray:
	"""Soft FM bell: bright strike that mellows quickly."""
	n = ns(dur)
	t = np.arange(n) / SR
	idx = 0.15 + index * np.exp(-6.9 * t / index_t60)
	return fm(f, dur, ratio, idx) * env_perc(dur, attack, t60)


def glass(f: float, dur: float, t60: float = 1.8, sparkle: float = 1.0, attack: float = 0.0012,
		detune_cents: float = 0.0, stretch: float = 1.0) -> np.ndarray:
	"""Glassy chime (Lumi's voice, sparkles): FM shimmer on the fundamental plus two inharmonic
	'bar' partials. `stretch` != 1 warps the partial ratios (used for the subtly wrong imitation)."""
	n = ns(dur)
	t = np.arange(n) / SR
	f = f * 2 ** (detune_cents / 1200.0)
	# keep the 3rd FM sideband (f * (1 + 3 * ratio)) below Nyquist on very high notes: no aliasing
	safe = float(np.clip((SR * 0.45) / (f * (1.0 + 3.0 * 3.5 * stretch)), 0.25, 1.0))
	idx = (0.12 + 1.1 * sparkle * np.exp(-6.9 * t / 0.18)) * safe
	body = fm(f, dur, 3.5 * stretch, idx) * env_perc(dur, attack, t60)
	p2 = np.sin(2 * np.pi * f * 2.756 * stretch * t + 0.7) * env_perc(dur, attack, t60 * 0.33)
	p3 = np.sin(2 * np.pi * f * 5.404 * stretch * t + 1.9) * env_perc(dur, attack, t60 * 0.12)
	return body + 0.28 * sparkle * p2 + 0.1 * sparkle * p3


def woodwind(f: float, dur: float, rng: np.random.Generator, kind: str = "flute", vel: float = 0.8,
		attack: float = 0.07, release: float = 0.16, vib_cents: float = 12.0, breath: float = 1.0) -> np.ndarray:
	"""Soft woodwind-like FM voice. kind = 'flute' (ratio 1, breathy) or 'clarinet' (ratio 2, hollow,
	odd harmonics) or 'ocarina' (almost pure, very soft). Returns dur + release seconds."""
	total = dur + release
	n = ns(total)
	t = np.arange(n) / SR
	drift = smooth_random(total, rng, 1.5, -3.0, 3.0)
	fr = osc.vibrato(f * 2 ** (drift / 1200.0), total, rate=rng.uniform(4.6, 5.4), cents=vib_cents,
		delay=min(0.25, dur * 0.4), rise=0.35, phase0=rng.uniform(0, 1))
	amp = env_adsr(total, attack, 0.25, 0.82, release, gate=dur)
	chiff = np.exp(-t / 0.05)
	if kind == "clarinet":
		idx = (0.9 + 0.5 * vel) * (0.75 + 0.25 * amp) + 0.5 * chiff
		y = fm(fr, total, 2.0, idx)
		y = F.lowpass(y, 2600 + 1800 * vel, 2)
		breath_bw = (1.5, 3.5)
	elif kind == "ocarina":
		idx = 0.18 + 0.3 * chiff
		y = fm(fr, total, 1.0, idx)
		breath_bw = (1.8, 3.0)
		breath *= 0.6
	else:
		idx = (0.35 + 0.35 * vel) * (0.7 + 0.3 * amp) + 0.7 * chiff
		y = fm(fr, total, 1.0, idx) + 0.12 * np.sin(2 * np.pi * osc.phase(fr * 2.0, total))
		y = F.lowpass(y, 3500 + 2000 * vel, 2)
		breath_bw = (1.6, 3.2)
	nz = N.white(total, rng)
	nz = F.bandpass(nz, f * breath_bw[0], min(f * breath_bw[1], 12000.0), 2)
	nz = F.lowpass(nz, 7000, 2)
	nz *= (0.035 + 0.14 * chiff) * breath
	return (y + nz * 2.0) * amp * vel
