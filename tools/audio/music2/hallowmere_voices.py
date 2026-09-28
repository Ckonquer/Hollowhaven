"""Extra instrument voices for the Hallowmere music group (m15-m19, m27).

Same contract as hhsynth.music instruments: fn(freq_hz, dur_s, vel 0..1, rng, **kw) -> mono (n,) or
stereo (n, 2) float array that may ring past `dur`. Everything is built from hhsynth primitives
(Karplus-Strong strings, modal resonators, FM, band-limited oscillators, formant filters) with
proper envelopes, filtering, detuned doubles and tail fades - no bare sine beeps.
"""
from __future__ import annotations

import os
import sys

sys.dont_write_bytecode = True
_AUDIO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _AUDIO not in sys.path:
	sys.path.insert(0, _AUDIO)

import numpy as np

from hhsynth.core import SR, ns, env_perc, env_adsr, env_points, smooth_random
from hhsynth import osc, filters as F, physical as P, fm as FM, space as S, noise as N


def _fade_tail(y: np.ndarray, sec: float = 0.06) -> np.ndarray:
	m = min(len(y), ns(sec))
	if m > 1:
		w = np.linspace(1.0, 0.0, m) ** 2
		y[-m:] *= w if y.ndim == 1 else w[:, None]
	return y


def _delay(y: np.ndarray, sec: float) -> np.ndarray:
	d = ns(sec)
	if d <= 0:
		return y
	return np.concatenate([np.zeros((d,) + y.shape[1:]), y], axis=0)


# ----------------------------------------------------------------------------------------------
# Plucked / struck
# ----------------------------------------------------------------------------------------------

def pizzicato(f: float, dur: float, vel: float, rng: np.random.Generator, players: int = 2) -> np.ndarray:
	"""Soft section pizzicato: two Karplus-Strong plucks a few cents and milliseconds apart (stereo),
	finger 'thup', wooden body resonance around 250-300 Hz, harsh upper mids tamed. Rings 0.35-1.4 s
	whatever the written length (pizzicato is not damped by the bow)."""
	t60 = float(np.clip(1.05 * (220.0 / f) ** 0.35, 0.35, 1.4))
	length = t60 * 0.9 + 0.05
	out = np.zeros((ns(length) + ns(0.012), 2))
	spots = [(-4.0, -0.35, 0.0), (5.0, 0.35, 0.007)][:players] if players > 1 else [(0.0, 0.0, 0.0)]
	for c, p, dt in spots:
		fr = f * 2 ** (c / 1200.0)
		y = P.ks_pluck(fr, length, rng, t60=t60 * rng.uniform(0.9, 1.1), bright=0.12 + 0.3 * vel,
			pos=rng.uniform(0.12, 0.2), soft=0.55)
		thup = F.lowpass(rng.standard_normal(ns(0.012)), min(1800.0, f * 3.0), 2) * np.hanning(ns(0.012))
		y[:len(thup)] += thup * 0.25
		y = _delay(y, dt)[:len(out)]
		out[:len(y)] += S.pan(y, p)
	out /= len(spots) ** 0.5
	out = F.peak_eq(out, 270.0, 3.5, 1.1)
	out = F.peak_eq(out, 2600.0, -4.0, 0.8)
	out = F.lowpass(out, 4800.0, 2)
	return _fade_tail(out, 0.08) * vel


def marimba(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Rosewood bar (modal): fundamental plus the tuned 4:1 and ~10:1 overtones, which die quickly;
	a tube resonator that swells in a few ms under the fundamental; yarn-mallet thud whose brightness
	follows velocity."""
	t60 = float(np.clip(1.5 * (262.0 / f) ** 0.6, 0.35, 2.0))
	length = t60 * 0.85
	hard = 0.45 + 0.55 * vel
	y = P.modal([f, f * 3.93, f * 9.24], [1.0, 0.26 * hard, 0.07 * hard], [t60, t60 * 0.2, t60 * 0.07],
		length, rng, attack=0.0012)
	t = np.arange(len(y)) / SR
	tube = np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * (1.0 - np.exp(-t / 0.006)) * np.exp(-6.9 * t / (t60 * 1.15))
	y += 0.35 * tube
	m = ns(0.006)
	thud = F.lowpass(rng.standard_normal(m), 1500.0 + 2500.0 * vel, 2) * np.hanning(m)
	y[:m] += thud * 0.18
	y = F.lowpass(y, 6500.0, 1)
	return _fade_tail(y, 0.06) * vel


def stone_pluck(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Low wire-and-wood pluck for the quarry (between a harp's bass string and a plucked cello):
	brighter excitation, long ring, a round sine body under it and a soft palm damp at dur + 1 s."""
	t60 = float(np.clip(3.0 * (110.0 / f) ** 0.3, 1.4, 3.4))
	length = min(t60, dur + 1.0) + 0.3
	y = P.ks_pluck(f, length, rng, t60=t60, bright=0.3 + 0.3 * vel, pos=0.13, soft=0.5)
	t = np.arange(len(y)) / SR
	y += 0.45 * np.sin(2 * np.pi * f * t) * env_perc(length, 0.004, 1.1)
	damp = env_adsr(length, 0.001, 0.1, 1.0, 0.3, gate=length - 0.3)
	y = F.peak_eq(y * damp, 170.0, 3.0, 0.9)
	y = F.lowpass(y, 3200.0, 2)
	return _fade_tail(y, 0.05) * vel


def stone_bell(f: float, dur: float, vel: float, rng: np.random.Generator, t60: float = 5.5) -> np.ndarray:
	"""Struck bell with a minor-third 'tierce': hum (x0.5), prime, tierce (x1.19), quint (x1.5),
	nominal (x2) and a few upper partials; each partial has a twin a fraction of a hertz away in the
	other channel (warble), low partials ring longest, mallet thud on top. Stereo."""
	parts = [(0.5, 0.5, 1.0), (1.0, 0.8, 0.75), (1.19, 0.42, 0.55), (1.5, 0.22, 0.42), (2.0, 0.45, 0.38),
		(2.51, 0.16, 0.22), (2.66, 0.12, 0.18), (3.01, 0.08, 0.13), (4.07, 0.05, 0.08)]
	length = t60 * 0.9
	n = ns(length)
	t = np.arange(n) / SR
	bright = 0.35 + 0.65 * vel
	out = np.zeros((n, 2))
	for r, a, tf in parts:
		fr = f * r
		if fr > SR * 0.42:
			continue
		amp = a * (bright if r > 2.2 else 1.0)
		dec = np.exp(-6.9 * t / (t60 * tf))
		for c in range(2):
			w = fr + (rng.uniform(0.15, 0.6) if c else 0.0)
			out[:, c] += amp * np.sin(2 * np.pi * w * t + rng.uniform(0, 6.28)) * dec
	m = ns(0.012)
	thud = F.lowpass(rng.standard_normal(m), 900.0, 2) * np.hanning(m) * 0.3
	out[:m] += thud[:, None]
	a = ns(0.002)
	out[:a] *= np.linspace(0, 1, a)[:, None]
	out = F.lowpass(out, 6500.0, 1)
	return _fade_tail(out, 0.3) * vel * 0.5


def metal_ting(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Small struck metal plate / anvil-bar: free-bar modes (1, 2.76, 5.40, 8.93) with a detuned twin
	per mode for shimmer; short, clean decay. Stereo."""
	length = 2.6
	n = ns(length)
	t = np.arange(n) / SR
	out = np.zeros((n, 2))
	for r, a, t60 in ((1.0, 1.0, 2.4), (2.756, 0.45 * (0.5 + vel), 1.1), (5.404, 0.2 * (0.4 + vel), 0.5),
			(8.933, 0.08, 0.25)):
		fr = f * r
		if fr > SR * 0.42:
			continue
		dec = np.exp(-6.9 * t / t60)
		out[:, 0] += a * np.sin(2 * np.pi * fr * t + rng.uniform(0, 6.28)) * dec
		out[:, 1] += a * np.sin(2 * np.pi * (fr + rng.uniform(0.3, 1.1)) * t + rng.uniform(0, 6.28)) * dec
	a = ns(0.001)
	out[:a] *= np.linspace(0, 1, a)[:, None]
	out = F.lowpass(out, 7000.0, 1)
	return _fade_tail(out, 0.2) * vel * 0.45


def timpani(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Kettle drum: tuned membrane modes (1, 1.5, 1.99, 2.44, 2.89) with a slight pitch drop after the
	stroke, felt-stick noise, dark low-pass."""
	length = 2.4
	n = ns(length)
	t = np.arange(n) / SR
	fr = f * (1.0 + 0.025 * np.exp(-t / 0.06))
	ph = osc.phase(fr, length)
	y = np.zeros(n)
	for r, a, t60 in ((1.0, 1.0, 2.0), (1.5, 0.45, 1.3), (1.99, 0.28, 0.9), (2.44, 0.16, 0.6), (2.89, 0.08, 0.4)):
		y += a * np.sin(2 * np.pi * ph * r + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / t60)
	a = ns(0.003)
	y[:a] *= np.linspace(0, 1, a)
	m = ns(0.02)
	stick = F.lowpass(rng.standard_normal(m), 900.0 + 900.0 * vel, 2) * np.hanning(m)
	y[:m] += stick * 0.35
	y = F.lowpass(y, 2600.0, 2)
	return _fade_tail(y, 0.3) * vel * 0.6


def clack(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Little hardwood clack (claves / wooden spoons): three short bright modes and a tiny click."""
	y = P.modal([f, f * 1.53, f * 2.61], [1.0, 0.4, 0.18], [0.07, 0.035, 0.018], 0.14, rng, attack=0.0004)
	m = ns(0.0015)
	y[:m] += F.highpass(rng.standard_normal(m), 2000.0, 1) * 0.3
	y = F.lowpass(y, 7500.0, 1)
	return _fade_tail(y, 0.02) * vel * 0.8


def tambourine(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Small tambourine: a double clash of noise bursts ringing a handful of jingle resonances
	(5-11 kHz, slightly different per hit), plus a soft skin tap. `f` is ignored."""
	length = 0.45
	n = ns(length)
	exc = np.zeros(n)
	for k, off in enumerate((0.0, rng.uniform(0.004, 0.009))):
		m = ns(0.006)
		s0 = ns(off)
		exc[s0:s0 + m] += rng.standard_normal(m) * np.hanning(m) * (1.0 if k == 0 else 0.6)
	freqs = rng.uniform(5200, 10500, 6)
	jing = P.resonate(exc, freqs, rng.uniform(0.12, 0.28, 6), np.full(6, 0.6))
	jing += F.bandpass(exc, 4500, 11000, 2) * 0.5
	skin = P.modal([240.0, 390.0], [1.0, 0.4], [0.08, 0.05], length, rng) * 0.25
	jing /= np.max(np.abs(jing)) + 1e-9
	y = jing * 0.8 + skin
	return _fade_tail(F.highpass(y, 180, 1), 0.1) * vel * 0.6


# ----------------------------------------------------------------------------------------------
# Sustained
# ----------------------------------------------------------------------------------------------

def reed(f: float, dur: float, vel: float, rng: np.random.Generator, bright: float = 0.5) -> np.ndarray:
	"""Bassoon-like double reed: band-limited saw + narrow pulse source with a little attack scoop,
	light delayed vibrato and slow pitch drift, nasal formants (~480 / 1150 / 2500 Hz) mixed with the
	plain source (keeps the fundamental), breath noise and gentle reed saturation. Short release, so
	staccato notes stay crisp."""
	release = 0.09
	total = dur + release
	n = ns(total)
	scoop = osc.glide(f * 2 ** (-28.0 / 1200.0), f, 0.05, "exp", total=total)
	drift = smooth_random(total, rng, 1.2, -4.0, 4.0)
	fr = osc.vibrato(scoop * 2 ** (drift / 1200.0), total, rate=rng.uniform(4.8, 5.6), cents=8.0,
		delay=min(0.3, dur * 0.5), rise=0.3, phase0=rng.uniform(0, 1))
	src = 0.55 * osc.saw(fr, total, rng.uniform(0, 1)) + 0.45 * osc.pulse(fr, total, 0.32, rng.uniform(0, 1))
	src = F.lowpass(src, min(4200.0, f * (7.0 + 4.0 * bright)), 2)
	form = F.formants(src, [(500.0, 1.6, 1.0), (1150.0, 3.0, 0.45), (2500.0, 4.5, 0.12 + 0.1 * bright)])
	y = 0.45 * src + 1.0 * form
	amp = env_adsr(total, 0.028, 0.12, 0.85, release, gate=dur)
	chiff = np.exp(-np.arange(n) / SR / 0.03)
	br = F.bandpass(N.white(total, rng), 700.0, 3200.0, 2) * (0.04 + 0.1 * chiff)
	y = (y + br) * amp
	# even out the formant-dependent level differences between notes (as a player would)
	a, b = ns(0.03), max(ns(0.03) + 64, ns(min(dur, 0.4)))
	r = float(np.sqrt(np.mean(y[a:b] ** 2))) + 1e-9
	y = y * (0.3 / r) ** 0.8
	y = np.tanh(1.4 * y) / np.tanh(1.4)
	y = F.highpass(y, 55.0, 1)
	return _fade_tail(y, 0.03) * vel * 0.8


def musette(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Little bellows reed organ (accordion 'musette'): three free reeds - centre, +11 and -9 cents,
	the classic wet tuning - pulse/saw mix, bellows pressure wobble, reedy body EQ. Stereo."""
	release = 0.12
	total = dur + release
	env = env_adsr(total, 0.045, 0.3, 0.9, release, gate=dur)
	bellows = 1.0 + 0.04 * smooth_random(total, rng, 1.8, -1.0, 1.0)
	out = np.zeros((ns(total), 2))
	for c, p in ((0.0, 0.0), (11.0, 0.55), (-9.0, -0.55)):
		fr = f * 2 ** (c / 1200.0)
		v = 0.6 * osc.pulse(fr, total, 0.42, rng.uniform(0, 1)) + 0.4 * osc.saw(fr, total, rng.uniform(0, 1))
		out += S.pan(v, p)
	out /= 3.0
	out = F.lowpass(out, min(3600.0, f * 7.0), 2)
	out = F.peak_eq(out, 1300.0, 2.5, 0.9)
	out = F.highpass(out, 140.0, 1)
	return _fade_tail(out * (env * bellows)[:, None], 0.03) * vel * 0.5


def warm_strings(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.16,
		release: float = 0.55, cutoff_mul: float = 5.0, vib: float = 7.0) -> np.ndarray:
	"""Ensemble strings with a quicker bow than hhsynth.music.strings, so they can carry lines:
	four detuned band-limited saws with independent delayed vibrato, a breath of bow noise at the
	attack, cello/violin body EQ. Stereo."""
	total = dur + release
	n = ns(total)
	env = env_adsr(total, attack, 0.35, 0.85, release, gate=dur)
	out = np.zeros((n, 2))
	for c, p in ((-8.0, -0.7), (-2.5, -0.25), (3.0, 0.25), (8.5, 0.7)):
		fr = osc.vibrato(f * 2 ** (c / 1200.0), total, rate=rng.uniform(4.8, 5.8), cents=vib, delay=0.18,
			rise=0.45, phase0=rng.uniform(0, 1))
		out += S.pan(osc.saw(fr, total, rng.uniform(0, 1)), p)
	out /= 4.0
	bow = F.bandpass(N.white(total, rng), min(f * 3.0, 6000.0), min(f * 9.0, 11000.0), 1)
	bow *= np.exp(-np.arange(n) / SR / 0.1) * 0.12
	out += bow[:, None]
	out = F.lowpass(out, min(3400.0, f * cutoff_mul), 2)
	out = F.peak_eq(out, 330.0, 2.0, 0.9)
	out = F.peak_eq(out, 2500.0, -3.0, 0.9)
	return out * env[:, None] * vel * 0.55


def warm_horn(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Soft pair of horns (FM ratio 1): brightness follows the swell of the envelope (brass gets
	brighter as it gets louder), two players a few cents apart, gentle late vibrato, dark low-pass.
	Stereo."""
	release = 0.35
	total = dur + release
	env = env_adsr(total, 0.11, 0.5, 0.88, release, gate=dur)
	out = np.zeros((ns(total), 2))
	for c, p in ((-4.0, -0.3), (4.0, 0.3)):
		drift = smooth_random(total, rng, 1.0, -2.5, 2.5)
		fr = osc.vibrato(f * 2 ** ((c + drift) / 1200.0), total, rate=rng.uniform(4.6, 5.2), cents=5.0,
			delay=0.4, rise=0.5, phase0=rng.uniform(0, 1))
		idx = 0.15 + (0.5 + 1.3 * vel) * env
		y = FM.fm(fr, total, 1.0, idx)
		y = F.lowpass(y, min(2300.0, f * 6.0), 2)
		out += S.pan(y, p)
	return out * env[:, None] * vel * 0.5


VOWELS = {
	# (centre Hz, Q, gain): soft alto/soprano 'oo', 'oh', 'ah' - no consonants, so nothing is a word
	"oo": [(330.0, 3.5, 1.0), (760.0, 5.0, 0.32), (2500.0, 9.0, 0.06)],
	"oh": [(460.0, 4.0, 1.0), (830.0, 5.0, 0.45), (2700.0, 9.0, 0.08)],
	"ah": [(760.0, 4.0, 1.0), (1180.0, 5.0, 0.55), (2750.0, 9.0, 0.1)],
}


def choir(f: float, dur: float, vel: float, rng: np.random.Generator, vowel: str = "oo", vowel2: str | None = None,
		attack: float = 0.9, release: float = 1.6, voices: int = 6, air: float = 1.0) -> np.ndarray:
	"""Airy wordless choir: six detuned 'singers' (saw/triangle glottal-ish source, each with its own
	vibrato, onset and slow pitch drift), split left/right, shaped by a fixed vowel formant bank that
	can slowly morph to a second vowel over the note, plus breath noise through the same vowel.
	There are no consonants or syllables, so it cannot form intelligible words. Stereo."""
	total = dur + release
	n = ns(total)
	t = np.arange(n) / SR
	# all singers at once (rows): detune, slow random pitch drift, delayed vibrato
	cents = rng.uniform(-12.0, 12.0, (voices, 1))
	k = max(2, int(total * 0.7) + 2)
	xs = np.linspace(0.0, total, k)
	pts = rng.uniform(-4.0, 4.0, (voices, k))
	drift = np.stack([np.interp(t, xs, pts[i]) for i in range(voices)])
	rate = rng.uniform(4.5, 5.6, (voices, 1))
	depth = rng.uniform(9.0, 16.0, (voices, 1))
	delay = rng.uniform(0.2, 0.6, (voices, 1))
	vib = np.clip((t[None, :] - delay) / 0.8, 0.0, 1.0) * depth * np.sin(2 * np.pi * (rate * t[None, :] + rng.uniform(0, 1, (voices, 1))))
	fr = f * 2 ** ((cents + drift + vib) / 1200.0)
	ph = np.cumsum(fr, axis=1) / SR + rng.uniform(0, 1, (voices, 1))
	p = np.mod(ph, 1.0)
	dt = fr / SR
	blep = np.zeros_like(p)                       # polyBLEP band-limited saw
	a = p < dt
	u = p[a] / dt[a]
	blep[a] = u + u - u * u - 1.0
	b = p > 1.0 - dt
	u = (p[b] - 1.0) / dt[b]
	blep[b] = u * u + u + u + 1.0
	saw = 2.0 * p - 1.0 - blep
	tri = 4.0 * np.abs(np.mod(ph + 0.25, 1.0) - 0.5) - 1.0
	v = 0.65 * saw + 0.35 * tri
	src = np.zeros((n, 2))
	for i in range(voices):                        # staggered onsets, alternate sides
		d = ns(rng.uniform(0.0, 0.08))
		src[d:, i % 2] += v[i, :n - d]
	src /= voices / 2.0
	src = F.lowpass(src, min(3800.0, f * 10.0), 2)
	breath = np.stack([N.white(total, rng), N.white(total, rng)], axis=1)
	breath = F.bandpass(breath, max(500.0, f * 1.5), min(6000.0, f * 10.0), 1) * 0.2 * air
	x = src + breath

	def vf(v):
		# breath only through the vowel resonances (no bare hiss); a little plain source keeps the pitch
		return F.formants(x, VOWELS[v]) * 1.4 + 0.22 * src

	y = vf(vowel)
	if vowel2:
		w = env_points([(0.0, 0.0), (total * 0.2, 0.0), (total * 0.8, 1.0), (total, 1.0)], total, "cos")
		y = y * (1.0 - w)[:, None] + vf(vowel2) * w[:, None]
	env = env_adsr(total, attack, 0.6, 0.9, release, gate=dur)
	y = F.highpass(y, 110.0, 1)
	return y * env[:, None] * vel * 2.4


def glass_harp(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.13,
		release: float = 0.9) -> np.ndarray:
	"""Rubbed-glass tone (glass harmonica): nearly pure partials 1-3 with a swelling attack and a
	second, slightly sharp glass in the other channel (slow beating), faint wet-finger friction.
	Stereo."""
	total = dur + release
	n = ns(total)
	t = np.arange(n) / SR
	env = env_adsr(total, attack, 0.7, 0.78, release, gate=dur)
	out = np.zeros((n, 2))
	for c, beat in ((0, 0.0), (1, rng.uniform(0.9, 1.6))):
		fr = osc.vibrato(f + beat, total, rate=rng.uniform(3.8, 4.6), cents=3.5, delay=0.35, rise=0.8,
			phase0=rng.uniform(0, 1))
		ph = osc.phase(fr, total)
		y = np.sin(2 * np.pi * ph) + 0.16 * np.sin(4 * np.pi * ph + 0.7) + 0.045 * np.sin(6 * np.pi * ph + 2.1)
		out[:, c] += y * (1.0 if c == 0 else 0.85)
		out[:, 1 - c] += y * 0.3
	fric = F.bandpass(N.white(total, rng), f * 0.8, min(f * 1.4, 12000.0), 2) * np.exp(-t / 0.15) * 0.05
	out += fric[:, None]
	return out * env[:, None] * vel * 0.42
