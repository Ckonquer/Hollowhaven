"""Higher-level sound-design building blocks shared by the sound modules (knocks, whooshes,
thuds, pops, voices, chimes, creaks). Everything returns mono float arrays at 44.1 kHz."""
from __future__ import annotations

import numpy as np

from hhsynth.core import SR, ns, env_perc, env_points, env_adsr, smooth_random, mix, place, fade
from hhsynth import osc, noise as N, filters as F, physical as P, fm as FM, space as S, music as M


def nz(x: np.ndarray) -> np.ndarray:
	"""Normalise to peak 1 (so components can be balanced by explicit gains)."""
	pk = np.max(np.abs(x)) if x.size else 0.0
	return x / pk if pk > 0 else x


def burst(rng: np.random.Generator, length: float, lo: float = 200.0, hi: float = 8000.0) -> np.ndarray:
	"""Short Hann-windowed band-limited noise burst (an excitation or a transient)."""
	m = max(8, ns(length))
	b = rng.standard_normal(m) * np.hanning(m)
	return F.bandpass(b, lo, hi, 1)


def knock(rng: np.random.Generator, freqs, t60s, amps, dur: float = 0.4, exc_len: float = 0.003,
		exc_lp: float = 5000.0, click: float = 0.15) -> np.ndarray:
	"""Struck object: a short noise excitation driving modal resonances (wood, stone, metal)."""
	n = ns(dur)
	exc = np.zeros(n)
	b = burst(rng, exc_len, 80.0, exc_lp)
	exc[:len(b)] = b
	body = P.resonate(exc, freqs, t60s, amps)
	return nz(body) + click * nz(exc)


def wood(rng: np.random.Generator, f: float = 300.0, dur: float = 0.35, t60: float = 0.12, bright: float = 0.5,
		click: float = 0.12) -> np.ndarray:
	"""Wooden knock (plank / log / box). Inharmonic wood-bar modes."""
	ratios = [1.0, 2.32, 4.1, 6.3]
	amps = [1.0, 0.45 * bright + 0.1, 0.25 * bright, 0.1 * bright]
	t60s = [t60, t60 * 0.55, t60 * 0.3, t60 * 0.18]
	return knock(rng, [f * r for r in ratios], t60s, amps, dur, 0.003, 2500 + 5000 * bright, click)


def stone(rng: np.random.Generator, f: float = 900.0, dur: float = 0.25, t60: float = 0.04, bright: float = 0.6,
		click: float = 0.35) -> np.ndarray:
	"""Stone tap / clack: dense, short, bright modes."""
	ratios = [1.0, 1.73, 2.61, 3.9, 5.2]
	amps = [1.0, 0.7, 0.5 * bright, 0.35 * bright, 0.2 * bright]
	t60s = [t60, t60 * 0.8, t60 * 0.6, t60 * 0.45, t60 * 0.3]
	return knock(rng, [f * r for r in ratios], t60s, amps, dur, 0.0015, 7000, click)


def metal(rng: np.random.Generator, f: float = 2000.0, dur: float = 0.6, t60: float = 0.3, click: float = 0.2) -> np.ndarray:
	"""Small metal ring (tool, latch, lantern lid). Sparse inharmonic partials."""
	ratios = [1.0, 1.62, 2.43, 3.51]
	amps = [1.0, 0.6, 0.35, 0.2]
	t60s = [t60, t60 * 0.7, t60 * 0.45, t60 * 0.3]
	return knock(rng, [f * r for r in ratios], t60s, amps, dur, 0.001, 9000, click)


def thud(rng: np.random.Generator, f: float = 70.0, dur: float = 0.35, t60: float = 0.18, dirt: float = 0.3) -> np.ndarray:
	"""Soft low thud: pitch-dropping sine body + muffled noise."""
	fr = osc.glide(f * 1.8, f, 0.04, "exp", total=dur)
	body = np.sin(2 * np.pi * osc.phase(fr, dur)) * env_perc(dur, 0.002, t60)
	mud = F.lowpass(rng.standard_normal(ns(dur)), 600, 2) * env_perc(dur, 0.001, t60 * 0.4)
	return nz(body) + dirt * nz(mud)


def whoosh(rng: np.random.Generator, dur: float, f_points, q: float = 1.2, amp_points=None, color: float = 0.5) -> np.ndarray:
	"""Air movement: coloured noise through a swept band-pass, with an amplitude contour."""
	x = N.colored(dur, rng, color)
	y = F.sweep_points(x, "bandpass", f_points, q)
	if amp_points is None:
		amp_points = [(0, 0), (dur * 0.4, 1.0), (dur, 0)]
	return nz(y) * env_points(amp_points, dur, "cos")


def pop(f0: float = 380.0, f1: float = 1150.0, dur: float = 0.09, t60: float = 0.06) -> np.ndarray:
	"""Cheerful bloop: fast upward pitch sweep with a quick decay."""
	f = osc.glide(f0, f1, 0.035, "exp", total=dur)
	return np.sin(2 * np.pi * osc.phase(f, dur)) * env_perc(dur, 0.001, t60)


def crunch(rng: np.random.Generator, dur: float, density, band=(900.0, 7000.0), grain=(0.001, 0.005)) -> np.ndarray:
	return P.grains(dur, rng, density, band, grain)


def creak(rng: np.random.Generator, dur: float, rate_points, amp_points, base: float = 400.0, t60: float = 0.05) -> np.ndarray:
	ratios = [1.0, 1.9, 3.1, 4.7]
	return P.creak(dur, rng, rate_points, amp_points, [base * r for r in ratios], [t60, t60 * 0.8, t60 * 0.6, t60 * 0.4],
		[1.0, 0.6, 0.35, 0.2])


def voice(rng: np.random.Generator, f_points, dur: float, formant_bank, amp_points, rough: float = 0.0,
		breath: float = 0.1, pulse_width: float = 0.35) -> np.ndarray:
	"""Creature vocalisation: a glottal-ish pulse wave with a pitch contour through formants,
	optional roughness (random amplitude jitter) and breath noise."""
	f = osc.glide_points(f_points, dur)
	src = osc.pulse(f, dur, pulse_width) * 0.6 + osc.saw(f, dur) * 0.4
	if rough > 0:
		jit = F.lowpass(rng.standard_normal(ns(dur)), 60.0, 2)
		src *= 1.0 + rough * nz(jit)
	src += breath * F.highpass(rng.standard_normal(ns(dur)), 800, 1)
	y = F.formants(src, formant_bank)
	return nz(y) * env_points(amp_points, dur, "cos")


def squeak(f_points, dur: float, amp_points, vib_rate: float = 0.0, vib_cents: float = 0.0, harm: float = 0.12) -> np.ndarray:
	"""Tiny sine-based squeak/chirp with a pitch contour (Mochi, birds)."""
	f = osc.glide_points(f_points, dur)
	if vib_rate > 0:
		f = osc.vibrato(f, dur, vib_rate, vib_cents)
	ph = osc.phase(f, dur)
	y = np.sin(2 * np.pi * ph) + harm * np.sin(4 * np.pi * ph + 0.4) + harm * 0.3 * np.sin(6 * np.pi * ph)
	return y * env_points(amp_points, dur, "cos")


def notes(inst, seq, rng: np.random.Generator, total: float | None = None) -> np.ndarray:
	"""Renders [(time, note, vel), ...] with a music instrument into one mono buffer."""
	parts = []
	for (t, note, vel) in seq:
		sig = inst(M.hz(note), 0.4, vel, rng)
		if sig.ndim == 2:
			sig = sig.mean(axis=1)
		parts.append((t, sig))
	end = max(t + len(s) / SR for t, s in parts)
	out = np.zeros(ns(total if total else end))
	for t, s in parts:
		place(out, s, t)
	return out


def glass_notes(seq, t60: float = 1.4, sparkle: float = 1.0, detune: float = 0.0, stretch: float = 1.0,
		total: float | None = None) -> np.ndarray:
	"""[(time, note, vel), ...] rendered with the glass chime voice (Lumi, sparkles)."""
	end = max(t for t, _, _ in seq) + t60
	out = np.zeros(ns(total if total else end))
	for (t, note, vel) in seq:
		place(out, FM.glass(M.hz(note), t60, t60, sparkle, detune_cents=detune, stretch=stretch) * vel, t)
	return out


def pad_chord(rng: np.random.Generator, names, dur: float, attack: float = 0.6, release: float = 1.0,
		cutoff: float = 1400.0) -> np.ndarray:
	"""Soft chord swell (mono sum of the stereo pad voice)."""
	out = None
	for nm in names:
		p = M.pad(M.hz(nm), dur, 0.7, rng, attack=attack, release=release, cutoff=cutoff).mean(axis=1)
		out = p if out is None else mix(out, p)
	return out


def small_room(rng: np.random.Generator, x: np.ndarray, wet: float = 0.2, t60: float = 0.5) -> np.ndarray:
	ir = S.room(rng, t60)
	return S.reverb_mono(x, ir, wet, 1.0)


def cave_verb(rng: np.random.Generator, x: np.ndarray, wet: float = 0.5, dry: float = 0.5, t60: float = 4.0,
		echoes=((0.16, 0.5), (0.29, 0.35), (0.47, 0.22), (0.71, 0.14))) -> np.ndarray:
	ir = S.cave(rng, t60, echoes)
	return S.reverb_mono(x, ir, wet, dry)


def stagger(parts, total: float | None = None) -> np.ndarray:
	"""Mixes [(time, signal, gain), ...] into one mono buffer."""
	end = max(t + len(s) / SR for t, s, _ in parts)
	out = np.zeros(ns(total if total else end) + 1)
	for t, s, g in parts:
		place(out, s, t, g)
	return out
