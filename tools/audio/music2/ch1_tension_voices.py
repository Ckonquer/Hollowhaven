"""Extra instrument voices for the Chapter One tension cues (owned by group_ch1_tension.py).

Same contract as tools/audio/hhsynth/music.py instruments: fn(freq, dur, vel, rng, **kw) ->
mono (n,) or stereo (n, 2) float array that may ring past `dur`. Built from hhsynth pieces
(oscillators, envelopes, filters, Karplus-Strong, modal resonators) - no samples.

  marimba      rosewood bar: tuned 1 : 3.9 : 9.2 modes, tube bloom, mallet thump
  pizz         pizzicato string section (2 detuned KS plucks + body resonances, stereo)
  reed         double-reed lead: kind='oboe' (nasal, bright) or 'bassoon' (dark, woody)
  violins      legato bowed section with expressive vibrato and optional messa di voce (stereo)
  spicc        short off-the-string bowed note for 16th-note ostinati (stereo)
  bowed_pad    dark bowed-synth texture: slow bow, optional sul-ponticello glass (stereo)
  low_brass    trombone/tuba-like section with brightness that follows loudness (stereo)
  bowed_metal  noise-bowed modal resonators (bowed glass / bowed plate), slow and eerie
  ruin_bell    dark minor-third bell (hum, prime, tierce, quint, nominal) with beating pairs
  pipe         struck steel pipe/rail: free-bar modes with slow beating (mine metal)
  felt_pulse   very soft low felt-mallet pulse (sub-ish, restrained)
  taiko        big low drum; frame_drum a lighter hand drum; brush a soft snare-ish hit;
  tick         dark metallic hat-like tick; roll_hit single stroke used for snare rolls
"""
from __future__ import annotations

import os
import sys

import numpy as np

_AUDIO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
if _AUDIO not in sys.path:
	sys.path.insert(0, _AUDIO)

from hhsynth.core import SR, ns, env_perc, env_adsr, env_points, smooth_random  # noqa: E402
from hhsynth import osc, filters as F, physical as P, space as S  # noqa: E402


def _fade_tail(y: np.ndarray, sec: float = 0.05) -> np.ndarray:
	m = min(len(y), ns(sec))
	if m > 1:
		w = np.linspace(1.0, 0.0, m) ** 2
		y[-m:] *= w if y.ndim == 1 else w[:, None]
	return y


def _soft_start(y: np.ndarray, sec: float = 0.0015) -> np.ndarray:
	m = min(len(y), ns(sec))
	if m > 1:
		w = np.linspace(0.0, 1.0, m)
		y[:m] *= w if y.ndim == 1 else w[:, None]
	return y


# ------------------------------------------------------------------------------------------
# Mallets & plucks
# ------------------------------------------------------------------------------------------

def marimba(f: float, dur: float, vel: float, rng: np.random.Generator, hard: float = 0.5) -> np.ndarray:
	"""Rosewood marimba bar. The fundamental blooms a few ms after the strike (resonator tube),
	the tuned overtones (~4x, ~10x) die quickly; harder mallets bring out more of them."""
	t60 = float(np.clip(1.5 * (262.0 / f) ** 0.55, 0.3, 2.4))
	length = min(t60, 2.6) + 0.05
	n = ns(length)
	t = np.arange(n) / SR
	h = float(np.clip(hard * (0.6 + 0.6 * vel), 0.1, 1.0))
	modes = [(1.0, 1.0, t60), (3.93, 0.22 + 0.25 * h, t60 * 0.22), (9.2, 0.05 + 0.1 * h, t60 * 0.08),
		(2.72, 0.03, t60 * 0.15)]
	y = np.zeros(n)
	for r, a, d in modes:
		fr = f * r
		if fr > SR * 0.42:
			continue
		comp = a * np.sin(2 * np.pi * fr * t + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / max(d, 0.02))
		if r == 1.0:
			comp *= 1.0 - 0.45 * np.exp(-t / 0.01)          # tube bloom
		y += comp
	m = ns(0.004)
	thump = F.lowpass(rng.standard_normal(m), 800 + 2500 * h, 2) * np.hanning(m)
	y[:m] += thump * 0.25 * h
	y = F.lowpass(y, 7500, 1)
	return _fade_tail(_soft_start(y, 0.0008), 0.04) * vel


def pizz(f: float, dur: float, vel: float, rng: np.random.Generator, ring: float = 0.5) -> np.ndarray:
	"""Pizzicato string section: two slightly detuned plucks panned apart, violin-body peaks."""
	t60 = float(np.clip(1.0 * (196.0 / f) ** 0.5, 0.22, 1.3))
	length = min(t60, dur + ring) + 0.05
	out = np.zeros((ns(length), 2))
	for c, p in ((-5.0, -0.35), (5.0, 0.35)):
		y = P.ks_pluck(f * 2 ** (c / 1200.0), length, rng, t60=t60, bright=0.3 + 0.35 * vel,
			pos=rng.uniform(0.18, 0.3), soft=0.35)
		y += 0.35 * np.sin(2 * np.pi * f * np.arange(len(y)) / SR) * env_perc(length, 0.002, t60 * 0.6)
		out += S.pan(y, p) * 0.6
	out = F.peak_eq(out, 290, 4.0, 1.2)
	out = F.peak_eq(out, 2600, 2.0, 1.0)
	out = F.lowpass(out, 6500, 2)
	return _fade_tail(out, 0.06) * vel


# ------------------------------------------------------------------------------------------
# Winds & brass
# ------------------------------------------------------------------------------------------

_REED = {
	# formant bank (fc, q, gain), brightness multiplier, scoop cents, source pulse width
	"oboe": ([(1080, 4.0, 1.0), (2750, 5.0, 0.55), (4100, 7.0, 0.18)], 5.5, -18.0, 0.34),
	"bassoon": ([(470, 3.0, 1.0), (1150, 4.0, 0.55), (2400, 6.0, 0.15)], 4.0, -25.0, 0.42),
}


def reed(f: float, dur: float, vel: float, rng: np.random.Generator, kind: str = "oboe", attack: float = 0.035,
		release: float = 0.12, vib_cents: float = 11.0, breath: float = 1.0) -> np.ndarray:
	"""Double-reed lead: band-limited saw + pulse through a formant bank; a small pitch scoop and
	a loudness-dependent brightness make it speak like a reed rather than an organ."""
	bank, bmul, scoop, pw = _REED[kind]
	total = dur + release
	n = ns(total)
	t = np.arange(n) / SR
	drift = smooth_random(total, rng, 1.3, -3.0, 3.0)
	sc = scoop * np.exp(-t / 0.045)
	fr = osc.vibrato(f * 2 ** ((drift + sc) / 1200.0), total, rate=rng.uniform(4.8, 5.6), cents=vib_cents,
		delay=min(0.22, dur * 0.4), rise=0.3, phase0=rng.uniform(0, 1))
	env = env_adsr(total, attack, 0.18, 0.86, release, gate=dur)
	src = 0.65 * osc.saw(fr, total, rng.uniform(0, 1)) + 0.45 * osc.pulse(fr, total, pw, rng.uniform(0, 1))
	fc = np.minimum(f * (1.5 + bmul * (0.35 + 0.65 * vel) * env ** 0.7) + 200.0, 7500.0)
	src = F.sweep(src, "lowpass", fc, 0.8, block=128)
	y = 0.3 * src + F.formants(src, bank)
	nz = F.bandpass(rng.standard_normal(n), bank[0][0] * 0.8, bank[1][0] * 1.4, 2)
	y += nz * (0.018 + 0.05 * np.exp(-t / 0.04)) * breath
	y = F.highpass(y, f * 0.7, 1)
	return y * env * vel * 0.55


def low_brass(f: float, dur: float, vel: float, rng: np.random.Generator, shape: str = "swell",
		release: float = 0.35, bright: float = 1.0) -> np.ndarray:
	"""Low brass section (stereo). shape: 'swell' (slow crescendo to the end of the note),
	'fp' (accent, drop, crescendo - desperate), 'hairpin' (< >), 'stab' (short accent),
	'plain'. Brightness rises with loudness, like real brass."""
	total = dur + release
	n = ns(total)
	if shape == "swell":
		env = env_points([(0, 0.0), (0.06, 0.18), (dur * 0.85, 1.0), (dur, 0.92), (total, 0.0)], total, "cos")
	elif shape == "fp":
		env = env_points([(0, 0.0), (0.03, 0.95), (0.22, 0.32), (max(0.3, dur * 0.9), 1.0), (dur, 0.9), (total, 0.0)],
			total, "cos")
	elif shape == "hairpin":
		env = env_points([(0, 0.0), (0.08, 0.2), (dur * 0.5, 1.0), (dur, 0.25), (total, 0.0)], total, "cos")
	elif shape == "stab":
		env = env_points([(0, 0.0), (0.02, 1.0), (0.12, 0.55), (dur, 0.35), (total, 0.0)], total, "cos")
	else:
		env = env_adsr(total, 0.05, 0.3, 0.8, release, gate=dur)
	t = np.arange(n) / SR
	scoop = -35.0 * np.exp(-t / 0.06)
	out = np.zeros((n, 2))
	for c, p in ((-7.0, -0.5), (0.0, 0.0), (6.0, 0.5)):
		fr = osc.vibrato(f * 2 ** ((c + scoop) / 1200.0), total, rate=rng.uniform(4.2, 5.0), cents=5.0,
			delay=0.5, rise=0.8, phase0=rng.uniform(0, 1))
		v = osc.saw(fr, total, rng.uniform(0, 1))
		out += S.pan(v, p)
	fc = np.minimum(f * (1.3 + 6.5 * bright * env ** 1.5) + 120.0, 3200.0)
	out = F.sweep(out, "lowpass", fc, 0.9, block=128)
	out = np.tanh(out * 0.9) / np.tanh(0.9)
	out = F.highpass(out, 38, 2)
	return out * env[:, None] * vel * 0.35


# ------------------------------------------------------------------------------------------
# Bowed strings & textures
# ------------------------------------------------------------------------------------------

def violins(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.12, release: float = 0.35,
		vib_cents: float = 14.0, swell: float = 0.0, voices: int = 4, bright: float = 0.6) -> np.ndarray:
	"""Legato violin section (stereo). swell > 0 adds a messa-di-voce hairpin inside the note."""
	total = dur + release
	n = ns(total)
	t = np.arange(n) / SR
	env = env_adsr(total, attack, 0.4, 0.88, release, gate=dur)
	if swell > 0:
		u = np.clip(t / max(dur, 1e-3), 0, 1)
		env = env * (1.0 - swell + swell * np.sin(np.pi * u) ** 1.2)
	out = np.zeros((n, 2))
	cents = np.linspace(-10, 10, voices) + rng.uniform(-2, 2, voices)
	pans = np.linspace(-0.7, 0.7, voices)
	for c, p in zip(cents, pans):
		fr = osc.vibrato(f * 2 ** (c / 1200.0), total, rate=rng.uniform(5.0, 6.0), cents=vib_cents,
			delay=min(0.18, dur * 0.3), rise=0.35, phase0=rng.uniform(0, 1))
		out += S.pan(osc.saw(fr, total, rng.uniform(0, 1)), p)
	out /= voices
	out = F.lowpass(out, min(1800.0 + 3500.0 * bright * vel, f * 9.0), 2)
	out = F.peak_eq(out, 420, 2.5, 1.0)          # wooden body
	out = F.peak_eq(out, 2400, -3.5, 0.9)        # tame the synthetic buzz
	bow = F.bandpass(rng.standard_normal(n), 2500, 6000, 2) * 0.012
	out += S.pan(bow, rng.uniform(-0.3, 0.3))
	out = F.highpass(out, 70, 2)
	return out * env[:, None] * vel * 0.9


def spicc(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Spiccato: a short bounced bow stroke (stereo), for fast ostinati."""
	length = 0.16 + min(dur, 0.2)
	n = ns(length)
	t = np.arange(n) / SR
	env = env_points([(0, 0.0), (0.008, 1.0), (0.05, 0.45), (length, 0.0)], length, "cos")
	out = np.zeros((n, 2))
	for c, p in ((-6.0, -0.4), (5.0, 0.4)):
		out += S.pan(osc.saw(f * 2 ** (c / 1200.0), length, rng.uniform(0, 1)), p)
	out *= 0.5
	fc = np.minimum(f * (2.0 + 6.0 * vel * np.exp(-t / 0.05)) + 300.0, 7000.0)
	out = F.sweep(out, "lowpass", fc, 0.8, block=64)
	scr = F.bandpass(rng.standard_normal(n), 2000, 6000, 2) * np.exp(-t / 0.012) * 0.08
	out += S.pan(scr, 0.0)
	out = F.peak_eq(out, 2400, -3.0, 0.9)
	return out * env[:, None] * vel * 0.6


def bowed_pad(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 1.8, release: float = 2.5,
		cutoff: float = 900.0, pont: float = 0.0, voices: int = 3, trem: float = 0.0, detune: float = 8.0) -> np.ndarray:
	"""Dark bowed-synth texture (stereo). pont (0..1) adds a glassy sul-ponticello layer (upper
	harmonics only, thin and uneasy); trem adds a slow uneven bow pressure wobble."""
	total = dur + release
	n = ns(total)
	env = env_adsr(total, attack, 1.0, 0.9, release, gate=dur)
	if trem > 0:
		env = env * (1.0 - trem + trem * smooth_random(total, rng, 3.0, 0.2, 1.0))
	out = np.zeros((n, 2))
	cents = np.linspace(-detune, detune, voices) + rng.uniform(-0.25, 0.25, voices) * detune
	pans = np.linspace(-0.8, 0.8, voices)
	for c, p in zip(cents, pans):
		fr = osc.vibrato(f * 2 ** (c / 1200.0), total, rate=rng.uniform(3.5, 5.0), cents=6.0, delay=0.6, rise=1.0,
			phase0=rng.uniform(0, 1))
		v = 0.6 * osc.saw(fr, total, rng.uniform(0, 1)) + 0.4 * osc.triangle(fr, total, rng.uniform(0, 1))
		out += S.pan(v, p)
	out /= voices
	base = F.lowpass(out, min(cutoff, f * 6.0), 2)
	if pont > 0:
		hi = F.bandpass(out, f * 3.5, min(f * 12.0, 9000.0), 2)
		base = base * (1.0 - 0.5 * pont) + hi * 1.6 * pont
	bow = F.bandpass(rng.standard_normal(n), min(f * 4, 4000), min(f * 10, 9000), 1) * 0.02
	base += S.pan(bow, 0.0)
	base = F.highpass(base, 45, 2)
	return base * env[:, None] * vel


def bowed_metal(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 1.2,
		release: float = 2.0, ratios=(1.0, 2.32, 4.25, 6.63), amps=(1.0, 0.45, 0.22, 0.1), t60: float = 1.2,
		rough: float = 0.4) -> np.ndarray:
	"""Bowed glass/plate: continuous (slightly rough) noise excitation driving narrow modal
	resonators at inharmonic ratios. Normalised so `vel` sets the steady level."""
	total = dur + release
	n = ns(total)
	env = env_adsr(total, attack, 1.0, 0.95, release, gate=dur)
	grit = 1.0 - rough + rough * smooth_random(total, rng, 9.0, 0.0, 1.0)
	exc = F.lowpass(rng.standard_normal(n), 5000, 1) * env * grit
	modes = [f * r for r in ratios]
	y = P.resonate(exc, modes, [t60 * (1.0 - 0.12 * i) for i in range(len(modes))], amps)
	y = F.highpass(y, 60, 2)
	r = np.sqrt(np.mean(np.square(y[ns(attack):ns(max(dur, attack + 0.1))]))) if dur > attack + 0.1 else np.sqrt(np.mean(y ** 2))
	y = y / max(r, 1e-9) * 0.25
	return _fade_tail(y, 0.2) * vel


# ------------------------------------------------------------------------------------------
# Metal & bells
# ------------------------------------------------------------------------------------------

def ruin_bell(f: float, dur: float, vel: float, rng: np.random.Generator, t60: float = 4.5, bright: float = 0.5,
		warble: float = 0.9) -> np.ndarray:
	"""Old bronze bell heard through stone: minor-third tierce, hum a octave below, every partial
	split into a slowly beating pair (warble Hz). Soft mallet, dark top."""
	length = min(t60 * 1.1, 9.0)
	n = ns(length)
	t = np.arange(n) / SR
	parts = [(0.5, 0.45, 1.3), (1.0, 1.0, 1.0), (1.19, 0.5, 0.7), (1.5, 0.22, 0.55), (2.0, 0.4 * bright, 0.45),
		(2.52, 0.2 * bright, 0.28), (3.01, 0.12 * bright, 0.18), (4.08, 0.07 * bright, 0.1)]
	y = np.zeros(n)
	for r, a, dm in parts:
		fr = f * r
		if fr * 1.01 > SR * 0.42:
			continue
		split = warble * (0.6 + 0.8 * rng.uniform()) * r
		for s in (-0.5, 0.5):
			y += 0.5 * a * np.sin(2 * np.pi * (fr + s * split) * t + rng.uniform(0, 6.28)) * np.exp(
				-6.9 * t / (t60 * dm))
	m = ns(0.006)
	y[:m] += F.lowpass(rng.standard_normal(m), 3000, 2) * np.hanning(m) * 0.15
	y = F.lowpass(y, 6000, 1)
	return _fade_tail(_soft_start(y, 0.002), 0.3) * vel * 0.55


def pipe(f: float, dur: float, vel: float, rng: np.random.Generator, t60: float = 3.2, bright: float = 0.5) -> np.ndarray:
	"""Struck steel pipe / hanging rail (the mine's metal): free-bar modes 1 : 2.756 : 5.404 :
	8.933, each doubled with a slow beat, a hard little strike and a long, clean ring."""
	length = min(t60 * 1.05, 7.0)
	n = ns(length)
	t = np.arange(n) / SR
	parts = [(1.0, 1.0, 1.0), (2.756, 0.32 * (0.5 + bright), 0.5), (5.404, 0.12 * bright, 0.22),
		(8.933, 0.05 * bright, 0.1)]
	y = np.zeros(n)
	for r, a, dm in parts:
		fr = f * r
		if fr * 1.01 > SR * 0.42:
			continue
		beat = rng.uniform(0.4, 1.3)
		for s in (-0.5, 0.5):
			y += 0.5 * a * np.sin(2 * np.pi * (fr + s * beat) * t + rng.uniform(0, 6.28)) * np.exp(
				-6.9 * t / (t60 * dm))
	m = ns(0.003)
	y[:m] += F.bandpass(rng.standard_normal(m), 2000, 7000, 2) * np.hanning(m) * 0.3 * bright
	y = F.lowpass(y, 7000, 1)
	return _fade_tail(_soft_start(y, 0.0008), 0.25) * vel * 0.6


# ------------------------------------------------------------------------------------------
# Low pulses & percussion
# ------------------------------------------------------------------------------------------

def felt_pulse(f: float, dur: float, vel: float, rng: np.random.Generator, decay: float = 0.9) -> np.ndarray:
	"""A restrained low pulse: felt-mallet bass note (fundamental + soft 2nd harmonic), with a
	tiny pitch settle. Mostly felt below 150 Hz."""
	length = decay + 0.2
	n = ns(length)
	t = np.arange(n) / SR
	fr = osc.glide(f * 1.06, f, 0.05, "exp", total=length)
	ph = osc.phase(fr, length)
	env = env_perc(length, 0.018, decay)
	y = np.sin(2 * np.pi * ph) + 0.25 * np.sin(4 * np.pi * ph + 0.4) * np.exp(-t / 0.15)
	y = F.lowpass(y, 420, 2)
	return _fade_tail(y * env, 0.05) * vel


def taiko(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Large low drum: pitch-dropping body, circular-membrane overtones, soft skin noise."""
	length = 1.1
	n = ns(length)
	t = np.arange(n) / SR
	fr = osc.glide(f * 1.7, f, 0.05, "exp", total=length)
	ph = osc.phase(fr, length)
	body = np.sin(2 * np.pi * ph) * env_perc(length, 0.002, 0.75)
	body += 0.3 * np.sin(2 * np.pi * ph * 1.59) * env_perc(length, 0.002, 0.28)
	body += 0.15 * np.sin(2 * np.pi * ph * 2.14) * env_perc(length, 0.002, 0.15)
	skin = F.lowpass(rng.standard_normal(n), 900, 2) * env_perc(length, 0.001, 0.07)
	y = np.tanh(1.4 * (body + 0.5 * skin)) / np.tanh(1.4)
	return _fade_tail(F.lowpass(y, 3000, 1), 0.1) * vel


def frame_drum(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Hand frame drum: short tonal thump plus a papery slap."""
	length = 0.5
	n = ns(length)
	t = np.arange(n) / SR
	fr = osc.glide(f * 1.4, f, 0.03, "exp", total=length)
	body = np.sin(2 * np.pi * osc.phase(fr, length)) * env_perc(length, 0.0015, 0.22)
	slap = F.bandpass(rng.standard_normal(n), 900, 3500, 2) * env_perc(length, 0.001, 0.05)
	return _fade_tail(F.lowpass(body + 0.45 * slap, 6000, 1), 0.05) * vel


def brush(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Soft snare-ish hit (brush on a snare with loose wires): noise body + short 190 Hz tone."""
	length = 0.35
	n = ns(length)
	t = np.arange(n) / SR
	nz = F.bandpass(rng.standard_normal(n), 1400, 6500, 2)
	env = env_points([(0, 0), (0.004, 1.0), (0.04, 0.4), (length, 0)], length, "db")
	tone = np.sin(2 * np.pi * 190 * t) * env_perc(length, 0.001, 0.07)
	y = 0.8 * nz * env + 0.5 * tone
	return _fade_tail(F.lowpass(y, 7000, 1), 0.05) * vel


def roll_hit(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""One stroke of a soft snare roll (shorter than brush, no tone)."""
	length = 0.14
	n = ns(length)
	nz = F.bandpass(rng.standard_normal(n), 1500, 6000, 2)
	env = env_points([(0, 0), (0.003, 1.0), (0.03, 0.3), (length, 0)], length, "db")
	return _fade_tail(F.lowpass(nz * env, 6500, 1), 0.02) * vel * 0.7


def tick(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Dark metallic tick (closed-hat-like, but warm): noise + two inharmonic high partials."""
	length = 0.09
	n = ns(length)
	t = np.arange(n) / SR
	nz = F.bandpass(rng.standard_normal(n), 3500, 8500, 2) * env_perc(length, 0.0008, 0.035)
	ring = (np.sin(2 * np.pi * 3170 * t) + 0.7 * np.sin(2 * np.pi * 4730 * t)) * env_perc(length, 0.0005, 0.025)
	return _fade_tail(F.lowpass(0.7 * nz + 0.12 * ring, 9000, 1), 0.01) * vel * 0.6
