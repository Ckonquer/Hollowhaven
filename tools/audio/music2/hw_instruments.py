"""Extra instruments for the home / woods cues (m03 m04 m06 m07 m08 m09), owned by group_home_woods.py.

Same contract as hhsynth.music instruments: fn(freq, dur, vel, rng, **kw) -> mono (n,) or stereo (n, 2)
float array that may ring past `dur`. Everything is physically flavoured additive / modal /
Karplus-Strong synthesis with proper envelopes, filtering and detune - no bare sine beeps.

  marimba      rosewood bar: tuned 1:4:10 partials, resonator-tube bloom, yarn-mallet contact noise
  felt_piano   inharmonic string partials, hammer-position comb, 2-3 detuned unison strings,
               two-stage (prompt/aftersound) decay, damper or sustain pedal, felt thump
  soft_bell    rubber-mallet glockenspiel/handbell hybrid with a slow beating fundamental
  pizzicato    plucked string (KS) through a violin-family body formant bank
  kalimba      thumb-piano tine: 1 : 5.9 : 17 partials, pitch settle, box resonance
  droplet      "water pluck": a tone that rises into pitch like a bubble, octave shimmer, plip
  air_lead     airy woodwind-like synth: soft additive tone + pitch-tracking breath noise + chiff
  bowed        warm bowed ensemble pad (stereo): detuned saws, bow-pressure filter, slow vibrato
  lullaby_harp warm harp (hhsynth KS harp with longer ring and a round body tone)
  nylon        hhsynth KS nylon/harp pluck with an even touch (per-pluck level normalisation)
  brush, tink, clay_pot   soft percussion
"""
from __future__ import annotations

import numpy as np

from hhsynth.core import SR, ns, env_perc, env_adsr, env_points, smooth_random
from hhsynth import osc
from hhsynth import filters as F
from hhsynth import physical as P
from hhsynth import space as S
from hhsynth import music as M


def _fade_end(y: np.ndarray, sec: float) -> np.ndarray:
	m = min(len(y), ns(sec))
	if m > 1:
		w = np.linspace(1.0, 0.0, m) ** 2
		y[-m:] *= w if y.ndim == 1 else w[:, None]
	return y


def _attack(y: np.ndarray, sec: float) -> np.ndarray:
	m = min(len(y), ns(sec))
	if m > 1:
		w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, m))
		y[:m] *= w if y.ndim == 1 else w[:, None]
	return y


def _even(y: np.ndarray, level: float, win: float = 0.1) -> np.ndarray:
	"""Karplus-Strong plucks start from random noise, so two plucks at the same velocity can differ
	by ~6 dB. Scales a pluck so its first `win` seconds have a consistent RMS (like a player's
	even touch); velocity is applied by the caller."""
	m = min(len(y), ns(win))
	r = float(np.sqrt(np.mean(y[:m] ** 2))) if m else 0.0
	return y * (level / r) if r > 1e-9 else y


def _midi_of(f: float) -> float:
	return 69.0 + 12.0 * np.log2(max(f, 1.0) / 440.0)


# ---------------------------------------------------------------------------------------------
# Mallets & plucks
# ---------------------------------------------------------------------------------------------

def marimba(f: float, dur: float, vel: float, rng: np.random.Generator, hard: float = 0.0) -> np.ndarray:
	"""Rosewood marimba bar with yarn mallets. The bar is undercut so its overtones sit at ~4x and
	~10x the fundamental; the tuned resonator tube under it reinforces and lengthens the
	fundamental (a slightly delayed, slightly detuned 'bloom'). Softer strokes excite fewer
	overtones and a darker contact noise."""
	h = float(np.clip(0.3 + 0.55 * vel + hard, 0.0, 1.2))        # mallet hardness / stroke energy
	t60 = float(np.clip(1.35 * (262.0 / f) ** 0.7, 0.32, 3.0))
	length = t60 * 1.02
	n = ns(length)
	t = np.arange(n) / SR
	y = np.zeros(n)
	parts = [(1.0, 1.0, t60), (3.98, 0.17 * (0.25 + 0.75 * h), t60 * 0.2), (9.85, 0.045 * h * h, t60 * 0.07)]
	for r, a, d in parts:
		if f * r > 11000:
			continue
		y += a * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / d)
	# resonator bloom: builds over ~15 ms and rings a touch longer (a gentle beat against the bar)
	bloom_env = (1.0 - np.exp(-t / 0.015)) * np.exp(-6.9 * t / (t60 * 1.2))
	y += 0.32 * np.sin(2 * np.pi * f * 1.0009 * t + 0.4) * bloom_env
	# mallet contact: short, lowpassed noise 'thock' (yarn: dark)
	cn = ns(0.006)
	if cn < n:
		c = F.lowpass(rng.standard_normal(cn), 900 + 2600 * h, 2) * np.hanning(cn)
		y[:cn] += c * 0.11 * h
	y = _attack(y, 0.0012 + 0.0015 * (1.0 - min(h, 1.0)))
	y = F.lowpass(y, 2400 + 6500 * min(h, 1.0), 1)
	return _fade_end(y, min(0.12, length * 0.3)) * vel * 0.9


def felt_piano(f: float, dur: float, vel: float, rng: np.random.Generator, pedal: float = 0.0,
		bright: float = 0.0, felt: float = 0.5) -> np.ndarray:
	"""Soft upright/felt piano. Partials are stretched by string stiffness (inharmonicity B rises
	towards the treble), weighted by the hammer's strike position (a comb near the 8th partial)
	and by velocity (harder strokes = flatter spectrum). The lowest partials come from 2-3 very
	slightly detuned unison strings (slow beating). Each partial decays in two stages (fast
	'prompt' sound, slower 'aftersound'). The damper stops the note at dur (+ pedal seconds);
	`felt` adds the soft felt layer's muted, darker attack."""
	m = _midi_of(f)
	B = 0.00007 * 2.0 ** ((m - 48.0) / 12.0 * 1.15)
	T1 = float(np.clip(10.0 * (130.8 / f) ** 0.62, 1.1, 14.0))
	gate = dur + pedal
	length = min(T1 * 0.8, gate + 0.45)
	n = ns(length)
	t = np.arange(n) / SR
	x0 = 1.0 / 8.3                                  # strike position along the string
	p = 2.35 - 1.1 * vel - 0.4 * bright + 0.4 * felt   # spectral slope
	n_part = int(np.clip(9500.0 / f, 3, 20))
	y = np.zeros(n)
	norm = 0.0
	for k in range(1, n_part + 1):
		fk = k * f * np.sqrt(1.0 + B * k * k)
		if fk > 12000:
			break
		a = (1.0 / k ** p) * (0.25 + 0.75 * abs(np.sin(np.pi * k * x0)))
		if fk < 140.0:                                 # a soundboard radiates low fundamentals weakly
			a *= (fk / 140.0) ** 0.9
		Tk = T1 / (1.0 + 0.3 * (k - 1) + 0.00006 * fk)
		nk = min(n, ns(Tk * 1.1))                     # the partial is ~-70 dB by then: stop computing
		tk = t[:nk]
		env = 0.72 * np.exp(-6.9 * tk / (Tk * 0.28)) + 0.28 * np.exp(-6.9 * tk / Tk)
		if k <= 7:
			nstr = 3 if m > 55 else 2
			part = np.zeros(nk)
			for s in range(nstr):
				cents = (s - (nstr - 1) / 2.0) * rng.uniform(0.6, 1.4)
				part += np.sin(2 * np.pi * fk * 2 ** (cents / 1200.0) * tk + rng.uniform(0, 6.28))
			part /= nstr
		else:
			part = np.sin(2 * np.pi * fk * tk + rng.uniform(0, 6.28))
		y[:nk] += a * part * env
		norm += a
	y /= max(norm, 1e-9) * 0.62
	# hammer / felt thump: a short dark knock plus a tiny noise of the action
	kn = ns(0.03)
	if kn < n:
		knock = np.sin(2 * np.pi * min(f, 180.0) * 0.5 * t[:kn]) * np.exp(-t[:kn] / 0.008)
		y[:kn] += knock * 0.05 * vel
		nz = F.lowpass(rng.standard_normal(kn), 1400 + 2500 * vel, 2) * np.exp(-t[:kn] / 0.004)
		y[:kn] += nz * 0.03 * vel
	# damper
	if gate < length:
		g0 = ns(gate)
		y[g0:] *= np.exp(-6.9 * (t[g0:] - gate) / 0.32)
	# felt: darker when soft, slightly slower attack
	fc = 1500.0 + 5200.0 * vel ** 1.4 * (1.0 - 0.35 * felt) + 2000.0 * bright
	y = F.lowpass(y, min(fc, 12000.0), 2)
	y = F.peak_eq(y, 220.0, 1.5, 0.9)             # a little soundboard warmth
	y = _attack(y, 0.0015 + 0.004 * felt)
	return _fade_end(y, min(0.15, length * 0.25)) * vel


def soft_bell(f: float, dur: float, vel: float, rng: np.random.Generator, ring: float = 1.0) -> np.ndarray:
	"""Soft bell: a small steel bar struck with a rubber mallet (partials 1 : 2.76 : 5.40) with a
	handbell-like pair of close fundamentals that beat slowly (~0.7 Hz), so held notes shimmer."""
	t60 = float(np.clip(3.0 * (523.25 / f) ** 0.45, 1.0, 4.5)) * ring
	length = t60 * 0.9
	n = ns(length)
	t = np.arange(n) / SR
	h = 0.4 + 0.5 * vel
	y = np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / t60)
	y += 0.45 * np.sin(2 * np.pi * (f + 0.7) * t + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / (t60 * 0.8))
	for r, a, d in ((2.756, 0.22 * h, 0.33), (5.404, 0.07 * h * h, 0.12), (3.0, 0.06, 0.5)):
		if f * r < 12000:
			y += a * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / (t60 * d))
	cn = ns(0.004)
	if cn < n:
		y[:cn] += F.bandpass(rng.standard_normal(cn), 1500, 6000, 1) * np.hanning(cn) * 0.05 * h
	y = _attack(y, 0.0018)
	y = F.lowpass(y, 7500, 1)
	return _fade_end(y, 0.1) * vel * 0.75


def pizzicato(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Plucked violin/viola/cello string: a Karplus-Strong string heard through a wooden body
	(formant bank near the main air and wood resonances), plus the finger's soft thump."""
	t60 = float(np.clip(1.0 * (196.0 / f) ** 0.35, 0.3, 1.6))
	length = t60 * 0.85
	y = P.ks_pluck(f, length, rng, t60=t60, bright=0.3 + 0.35 * vel, pos=rng.uniform(0.2, 0.3), soft=0.35)
	body = F.formants(y, [(280.0, 3.5, 1.0), (470.0, 4.0, 0.7), (1100.0, 3.0, 0.35), (2700.0, 2.0, 0.12)])
	y = 0.33 * y + 0.95 * body
	n = len(y)
	th = ns(0.008)
	if th < n:
		t = np.arange(th) / SR
		y[:th] += F.lowpass(rng.standard_normal(th), 700, 2) * np.exp(-t / 0.002) * 0.06
	y = F.lowpass(y, 4300, 2)
	y = F.highpass(y, 55, 1)
	tt = np.arange(len(y)) / SR
	y = y * (1.0 - 0.5 * np.exp(-tt / 0.009))       # flesh-of-the-finger: a softer first few ms
	y = _even(y, 0.1)
	return _fade_end(_attack(y, 0.0025), min(0.08, length * 0.3)) * vel


def kalimba(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Thumb-piano tine: the steel tine's overtones sit near 5.9x and 17x the fundamental; the
	pitch settles from a few cents sharp as the tine stops being pushed; a hollow box resonance."""
	T = float(np.clip(2.1 * (440.0 / f) ** 0.35, 0.8, 3.0))
	length = T * 0.9
	n = ns(length)
	t = np.arange(n) / SR
	fr = f * (1.0 + 0.004 * np.exp(-t / 0.025))
	ph = np.cumsum(fr) / SR
	y = np.sin(2 * np.pi * ph) * np.exp(-6.9 * t / T)
	y += 0.14 * (0.5 + vel) * np.sin(2 * np.pi * 5.93 * ph + 1.1) * np.exp(-6.9 * t / (T * 0.12))
	y += 0.04 * vel * np.sin(2 * np.pi * 17.2 * ph + 0.3) * np.exp(-6.9 * t / (T * 0.04)) if f * 17.2 < 12000 else 0.0
	y = y + 0.25 * F.resonator(y, 250.0, 2.5)
	cn = ns(0.003)
	if cn < n:
		y[:cn] += F.bandpass(rng.standard_normal(cn), 2000, 7000, 1) * np.hanning(cn) * 0.04
	y = _attack(y, 0.0008)
	return _fade_end(F.lowpass(y, 8000, 1), 0.08) * vel * 0.85


def droplet(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Water-like pluck: a round tone that rises into its pitch the way a bubble does (a few %
	below, settling within ~15 ms), a quickly fading octave shimmer and a tiny surface 'plip'."""
	T = float(np.clip(1.3 * (880.0 / f) ** 0.3, 0.45, 2.0))
	length = T * 0.95
	n = ns(length)
	t = np.arange(n) / SR
	fr = f * (1.0 - 0.055 * np.exp(-t / 0.013))
	ph = np.cumsum(fr) / SR
	y = np.sin(2 * np.pi * ph) * np.exp(-6.9 * t / T)
	y += 0.2 * np.sin(2 * np.pi * 2.0 * ph + 0.5) * np.exp(-6.9 * t / (T * 0.22))
	y += 0.07 * np.sin(2 * np.pi * 3.01 * ph + 1.3) * np.exp(-6.9 * t / (T * 0.08))
	pl = P.bubble(min(f * 2.2, 5000.0), 0.09, rise=1.7, t60=0.03)
	m = min(len(pl), n)
	y[:m] += pl[:m] * 0.12 * (0.5 + vel)
	y = _attack(y, 0.0007)
	y = F.lowpass(y, 9000, 1)
	return _fade_end(y, 0.06) * vel * 0.9


def lullaby_harp(f: float, dur: float, vel: float, rng: np.random.Generator, ring: float = 3.0) -> np.ndarray:
	"""Warm concert-harp pluck: hhsynth's KS harp with a longer ring and a round body tone."""
	y = _even(M.harp(f, dur, vel, rng, ring=ring), 0.09 * vel)
	n = len(y)
	t = np.arange(n) / SR
	t60 = float(np.clip(2.8 * (196.0 / f) ** 0.45, 0.7, 4.0))
	body = np.sin(2 * np.pi * f * t + 0.3) * np.exp(-6.9 * t / t60) * (1 - np.exp(-t / 0.004))
	y = y + 0.22 * vel * body
	return _fade_end(F.lowpass(y, 4200, 1), min(0.25, n / SR * 0.3))


def nylon(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""hhsynth's nylon/harp pluck with an even touch (see _even)."""
	return _even(M.harp(f, dur, vel, rng), 0.09 * vel)


# ---------------------------------------------------------------------------------------------
# Sustained voices
# ---------------------------------------------------------------------------------------------

def air_lead(f: float, dur: float, vel: float, rng: np.random.Generator, breath: float = 1.0,
		attack: float = 0.12) -> np.ndarray:
	"""Airy woodwind-like synth (pan-pipe / soft synth flute): a nearly pure additive tone with a
	breath-noise band that follows the pitch, a soft chiff at the start and a delayed vibrato."""
	release = 0.38
	total = dur + release
	n = ns(total)
	t = np.arange(n) / SR
	drift = smooth_random(total, rng, 1.2, -4.0, 4.0)
	fr = osc.vibrato(f * 2 ** (drift / 1200.0), total, rate=rng.uniform(4.4, 5.0), cents=7.0,
		delay=min(0.4, dur * 0.45), rise=0.5, phase0=rng.uniform(0, 1))
	ph = osc.phase(fr, total)
	tone = np.sin(2 * np.pi * ph) + 0.16 * np.sin(4 * np.pi * ph + 0.4) + 0.05 * np.sin(6 * np.pi * ph + 1.0)
	amp = env_adsr(total, attack, 0.3, 0.85, release, gate=dur)
	chiff = np.exp(-t / 0.06)
	nz = rng.standard_normal(n)
	band = F.bandpass(nz, f * 0.9, min(f * 3.4, 12000.0), 2)
	band = band / (np.std(band) + 1e-9)
	hiss = F.highpass(nz, 5500, 2)
	hiss = hiss / (np.std(hiss) + 1e-9)
	y = tone * (0.85 + 0.15 * vel) + band * (0.055 * breath + 0.22 * chiff) + hiss * 0.012 * breath
	y = F.lowpass(y * amp, 3200 + 2200 * vel, 2)
	return y * vel * 0.8


def bowed(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.55,
		release: float = 1.5, cutoff: float = 1700.0, detune: float = 6.0) -> np.ndarray:
	"""Warm bowed ensemble pad (stereo): three detuned band-limited saws with a delayed slow
	vibrato; the lowpass opens with the bow pressure (the amplitude envelope), a little bow noise."""
	total = dur + release
	n = ns(total)
	env = env_adsr(total, attack, 0.6, 0.9, release, gate=dur)
	y = np.zeros((n, 2))
	for c, p in ((-detune, -0.7), (0.0, 0.0), (detune, 0.7)):
		fr = osc.vibrato(f * 2 ** (c / 1200.0), total, rate=rng.uniform(4.2, 5.2), cents=6.0, delay=0.35, rise=0.8,
			phase0=rng.uniform(0, 1))
		v = osc.saw(fr, total, rng.uniform(0, 1))
		y += S.pan(v, p)
	y /= 3.0
	fc = np.minimum(cutoff, f * 5.0) * (0.45 + 0.55 * env)
	y = F.sweep(y, "lowpass", np.maximum(fc, 150.0), 0.707, block=256)
	nz = F.bandpass(rng.standard_normal(n), min(f * 2, 3000.0), min(f * 5, cutoff * 2.0, 6000.0), 2) * 0.007
	y += S.pan(nz, 0.0)
	y = F.highpass(y, 70, 1)
	y = F.peak_eq(y, 1900.0, -3.0, 0.8)
	return y * env[:, None] * vel * 0.55


# ---------------------------------------------------------------------------------------------
# Soft percussion
# ---------------------------------------------------------------------------------------------

def brush(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Brush on a snare head: a short swish (noise, band-limited) with a soft tap."""
	length = 0.32
	n = ns(length)
	t = np.arange(n) / SR
	nz = F.bandpass(rng.standard_normal(n), 1800, 8500, 2)
	env = env_points([(0, 0), (0.012, 1.0), (0.06, 0.45), (length, 0.0)], length, "cos")
	tap = F.lowpass(rng.standard_normal(n), 2200, 2) * np.exp(-t / 0.012)
	return (nz * env * 0.5 + tap * 0.25) * vel


def tink(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""A spoon touching a porcelain cup: small, high, quickly fading modes."""
	y = P.modal([f, f * 2.32, f * 4.25, f * 6.1], [1.0, 0.5, 0.25, 0.1], [0.55, 0.3, 0.14, 0.07], 0.6, rng)
	return _fade_end(F.lowpass(y, 10000, 1), 0.05) * vel * 0.5


def clay_pot(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Soft hand drum on a clay pot: a low round tone that bends up into pitch, plus palm noise."""
	length = 0.6
	n = ns(length)
	t = np.arange(n) / SR
	fr = osc.glide(f * 0.82, f, 0.05, "exp", total=length)
	y = np.sin(2 * np.pi * osc.phase(fr, length)) * env_perc(length, 0.003, 0.32)
	y += 0.2 * np.sin(2 * np.pi * osc.phase(fr * 2.3, length)) * env_perc(length, 0.002, 0.08)
	y += F.lowpass(rng.standard_normal(n), 900, 2) * np.exp(-t / 0.01) * 0.25
	return F.lowpass(y, 1600, 2) * vel
