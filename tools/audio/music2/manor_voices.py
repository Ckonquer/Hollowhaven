"""Extra instrument voices for the Manor & Works cues (group_manor_works.py).

Same contract as hhsynth.music instruments: fn(freq_hz, dur_s, vel 0..1, rng, **kw) -> mono (n,) or
stereo (n, 2) float array that may ring past `dur` (release / decay tails). Built from hhsynth
primitives (Karplus-Strong strings, modal resonators, band-limited oscillators, formant banks);
every voice has a shaped envelope, filtering and some detune / drift - no raw sine beeps.
"""
from __future__ import annotations

import numpy as np

from hhsynth.core import SR, ns, env_perc, env_adsr, env_points
from hhsynth import osc, filters as F, physical as P, space as S


def _wander(dur: float, rng: np.random.Generator, rate: float, lo: float, hi: float) -> np.ndarray:
	"""Slowly wandering control signal (cosine-eased random points ~rate per second, like
	hhsynth.core.smooth_random) computed on a coarse grid and linearly upsampled - cheap on long notes."""
	n = ns(dur)
	k = max(2, int(np.ceil(dur * rate)) + 1)
	pts = rng.uniform(lo, hi, k)
	m = n // 128 + 2
	u = np.linspace(0.0, k - 1.0, m)
	i = np.clip(np.floor(u).astype(int), 0, k - 2)
	f = u - i
	f = 0.5 - 0.5 * np.cos(np.pi * f)
	coarse = pts[i] + (pts[i + 1] - pts[i]) * f
	return np.interp(np.arange(n), np.linspace(0, n, m), coarse)


# --- low internal-rate oscillators for long, dark sustained notes ---------------------------
# Drones and pads that are low-passed far below Nyquist are synthesised at SR/2 or SR/4 and then
# up-sampled (polyphase FIR); the tone filters run afterwards at the full rate. Same recipe, 2-4x
# less work on 20-second notes.

def _lr_saw(fr: np.ndarray, sr: float, ph0: float) -> np.ndarray:
	"""PolyBLEP sawtooth for a per-sample frequency array at sample rate sr."""
	p = np.mod(ph0 + np.concatenate([[0.0], np.cumsum(fr[:-1])]) / sr, 1.0)
	dt = np.clip(np.abs(fr) / sr, 1e-6, 0.5)
	y = 2.0 * p - 1.0
	a = p < dt
	x = p[a] / dt[a]
	y[a] -= x + x - x * x - 1.0
	b = p > 1.0 - dt
	x = (p[b] - 1.0) / dt[b]
	y[b] -= x * x + x + x + 1.0
	return y


def _lr_tri(fr: np.ndarray, sr: float, ph0: float) -> np.ndarray:
	p = np.mod(ph0 + 0.25 + np.concatenate([[0.0], np.cumsum(fr[:-1])]) / sr, 1.0)
	return 4.0 * np.abs(p - 0.5) - 1.0


def _lr_vibrato(base: float, n: int, sr: float, rate: float, cents: float, delay: float, rise: float,
		phase0: float) -> np.ndarray:
	t = np.arange(n) / sr
	depth = np.clip((t - delay) / max(rise, 1e-3), 0.0, 1.0) * cents
	return base * 2.0 ** (depth * np.sin(2 * np.pi * (rate * t + phase0)) / 1200.0)


def _upsample(y: np.ndarray, D: int, n_out: int) -> np.ndarray:
	from scipy import signal as sg
	u = sg.resample_poly(y, D, 1, axis=0)
	if len(u) < n_out:
		u = np.concatenate([u, np.zeros((n_out - len(u),) + u.shape[1:])], axis=0)
	return u[:n_out]


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
# Plucked keyboard & strings
# ------------------------------------------------------------------------------------------

def harpsichord(f: float, dur: float, vel: float, rng: np.random.Generator, four: bool = False,
		buff: bool = False) -> np.ndarray:
	"""Harpsichord-like: two quill-plucked unison strings (8'+8', a couple of cents apart, plucked near
	the nut for the nasal comb colour), optional 4' octave string, a quill 'tick', and the damper
	stopping the strings shortly after key release (small release thump). buff=True is the lute stop
	(felt against the strings: shorter, rounder)."""
	t60 = float(np.clip(5.0 * (110.0 / f) ** 0.55, 0.9, 7.5)) * (0.35 if buff else 1.0)
	gate = max(dur, 0.06)
	length = min(gate + 0.14, t60 + 0.05)
	bright = 0.5 if buff else 0.78
	a = P.ks_pluck(f, length, rng, t60=t60, bright=bright, pos=rng.uniform(0.07, 0.1), soft=0.0)
	b = P.ks_pluck(f * 2 ** (rng.uniform(1.2, 2.2) / 1200.0), length, rng, t60=t60 * 0.92, bright=bright - 0.08,
		pos=rng.uniform(0.11, 0.14), soft=0.15)
	y = 0.6 * a + 0.45 * b
	if four and f * 2 < 4200:
		y += 0.3 * P.ks_pluck(f * 2.0, length, rng, t60=t60 * 0.6, bright=0.7, pos=0.12, soft=0.3)
	# damper: quick but not instant (felt dampers leave a short ring)
	damp = env_adsr(length, 0.0004, 0.1, 1.0, 0.075, gate=gate)
	y = y * damp
	# quill tick at the pluck, jack thump at the release
	tick = F.bandpass(rng.standard_normal(ns(0.006)), 1800, 6500, 1) * np.hanning(ns(0.006))
	y[:len(tick)] += tick * 0.06
	j = ns(gate)
	thump = F.lowpass(rng.standard_normal(ns(0.02)), 900, 2) * np.hanning(ns(0.02)) * 0.02
	if j + len(thump) < len(y):
		y[j:j + len(thump)] += thump
	# soundboard: a little low body, tamed top end so it sits with the soft house palette
	y = F.peak_eq(y, 230, 3.0, 1.0)
	y = F.peak_eq(y, 3000, -5.0, 0.7)
	y = F.lowpass(y, 5200 if not buff else 3000, 2)
	return _fade_tail(_soft_start(y, 0.0006), 0.03) * (0.62 + 0.38 * vel)


def pizz(f: float, dur: float, vel: float, rng: np.random.Generator, ring: float = 1.0) -> np.ndarray:
	"""Pizzicato string (cello / bass section): soft finger pluck, woody body, short ring."""
	length = float(np.clip(1.5 * (98.0 / f) ** 0.35, 0.35, 1.7)) * ring
	y = P.ks_pluck(f, length, rng, t60=length * 0.85, bright=0.2 + 0.2 * vel, pos=rng.uniform(0.22, 0.3), soft=0.6)
	y += 0.35 * np.sin(2 * np.pi * f * np.arange(len(y)) / SR) * env_perc(length, 0.003, length * 0.45)
	y = F.peak_eq(y, 260, 4.0, 1.3)
	y = F.lowpass(y, min(1900.0, f * 10.0), 2)
	return _fade_tail(y, 0.08) * vel


def piano(f: float, dur: float, vel: float, rng: np.random.Generator, pedal: float = 0.0,
		soft: float = 0.35) -> np.ndarray:
	"""Warm felt piano: inharmonic partials (stiff string), double decay (prompt + aftersound),
	a unison pair beating on the low partials, hammer knock, damper at key/pedal release.
	pedal = extra seconds of sustain after the key is released; soft 0..1 = felt / una corda."""
	hold = max(dur + pedal, 0.1)
	T = float(np.clip(10.0 * (262.0 / f) ** 0.7, 1.2, 16.0))      # fundamental t60 if undamped
	rel = float(np.clip(0.35 * (262.0 / f) ** 0.3, 0.12, 0.6))
	length = min(hold + rel, T * 0.9)
	n = ns(length)
	D = 2                                                   # partials stop at 7 kHz: build at 22.05 kHz
	nl = n // D + 2
	t = np.arange(nl) / (SR / D)
	B = float(np.clip(0.00008 * (f / 130.0) ** 1.1, 0.00003, 0.0015))
	hard = (0.35 + 0.65 * vel) * (1.0 - 0.45 * soft)
	strike = 0.11 + 0.02 * rng.uniform(-1, 1)            # hammer position (comb in the spectrum)
	y = np.zeros(nl)
	for k in range(1, 30):
		fk = k * f * np.sqrt(1.0 + B * k * k)
		if fk > 7000.0:
			break
		a = (abs(np.sin(np.pi * k * strike)) + 0.12) / k ** (1.35 - 0.55 * hard)
		a *= np.exp(-k * f / (2200.0 + 4200.0 * hard))           # brighter when played harder
		tk = T / (1.0 + 0.28 * (k - 1) ** 1.15)
		m = min(nl, ns(tk * 1.1) // D + 1)                       # partial has decayed below -60 dB
		tt = t[:m]
		env = 0.62 * np.exp(-6.9 * tt / (tk * 0.22)) + 0.38 * np.exp(-6.9 * tt / tk)
		ph = rng.uniform(0, 2 * np.pi)
		if k <= 6:
			d = fk * (0.00035 + 0.0003 * rng.uniform())          # second string, slow beating
			y[:m] += a * env * 0.5 * (np.sin(2 * np.pi * fk * tt + ph) + np.sin(2 * np.pi * (fk + d) * tt + ph * 1.3))
		else:
			y[:m] += a * env * np.sin(2 * np.pi * fk * tt + ph)
	y = _upsample(y, D, n)
	knock = F.lowpass(rng.standard_normal(ns(0.025)), 700 + 1500 * hard, 2) * env_perc(0.025, 0.0005, 0.02)
	y[:len(knock)] += knock * 0.05 * hard
	damp = env_adsr(length, 0.0008, 0.1, 1.0, rel, gate=min(hold, length - 0.01))
	y = y * damp
	y = F.lowpass(y, 3200 + 3800 * hard, 2)
	return _fade_tail(_soft_start(y, 0.001), 0.04) * vel * 0.55


def marimba(f: float, dur: float, vel: float, rng: np.random.Generator, hard: float = 0.45) -> np.ndarray:
	"""Rosewood bar: tuned partials 1 : 3.93 : 9.2 (marimba tuning), tube resonance, soft mallet."""
	t60 = float(np.clip(1.7 * (262.0 / f) ** 0.7, 0.25, 2.8))
	length = t60 * 0.9
	h = hard * (0.5 + 0.5 * vel)
	y = P.modal([f, f * 3.93, f * 9.2, f * 1.002], [1.0, 0.25 * h + 0.04, 0.07 * h, 0.35],
		[t60 * 0.8, t60 * 0.3, t60 * 0.1, t60], length, rng, attack=0.0012 + 0.002 * (1 - h))
	thud = F.lowpass(rng.standard_normal(ns(0.012)), 900 + 2500 * h, 2) * np.hanning(ns(0.012))
	y[:len(thud)] += thud * 0.06
	y = F.lowpass(y, 6500, 1)
	return _fade_tail(y, 0.06) * vel * 0.8


def clack(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Little wooden 'bones' clack (two slats): short inharmonic modes + a tiny noise snap, doubled."""
	length = 0.16
	y = P.modal([f, f * 2.31, f * 3.73, f * 5.9], [1.0, 0.6, 0.3, 0.15], [0.07, 0.05, 0.035, 0.02], length, rng)
	snap = F.bandpass(rng.standard_normal(ns(0.004)), 1500, 7000, 1) * np.hanning(ns(0.004))
	y[:len(snap)] += snap * 0.4
	d = ns(rng.uniform(0.012, 0.02))            # second slat a hair later
	y2 = np.zeros_like(y)
	y2[d:] = y[:-d] * 0.45
	return F.highpass(y + y2, 300, 2) * vel


def tick(f: float, dur: float, vel: float, rng: np.random.Generator, t60: float = 0.35) -> np.ndarray:
	"""Small struck metal (gear tooth, clock escapement, bellhouse fittings)."""
	length = t60 * 1.1
	y = P.modal([f, f * 2.76, f * 5.40, f * 8.93], [1.0, 0.45, 0.22, 0.1], [t60, t60 * 0.5, t60 * 0.25, t60 * 0.1],
		length, rng)
	click = F.highpass(rng.standard_normal(ns(0.002)), 2500, 2) * np.hanning(ns(0.002))
	y[:len(click)] += click * 0.3
	return _fade_tail(F.lowpass(y, 8000, 1), 0.03) * vel * 0.7


# ------------------------------------------------------------------------------------------
# Bowed & blown
# ------------------------------------------------------------------------------------------

def muted_strings(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.2,
		release: float = 0.5, bright: float = 1.0, vib: float = 7.0, width: float = 0.6) -> np.ndarray:
	"""Section strings con sordino (stereo): three detuned bowed saws, gentle delayed vibrato, dark
	mute formant, a whisper of bow noise. Short attack/release values give detached 'pah' chords."""
	total = dur + release
	env = env_adsr(total, attack, 0.3, 0.9, release, gate=dur)
	cut = min(1500.0 * bright, 5.0 * f + 300.0)
	D = (4 if cut <= 1200.0 else 2) if (total > 3.0 and cut <= 2500.0) else 1
	n = ns(total)
	nl = n // D + 2
	y = np.zeros((nl, 2))
	for c, p in ((-7.0, -width), (0.5, 0.0), (6.5, width)):
		fr = _lr_vibrato(f * 2 ** (c / 1200.0), nl, SR / D, rng.uniform(4.8, 5.6), vib, 0.15, 0.4, rng.uniform(0, 1))
		y += S.pan(_lr_saw(fr, SR / D, rng.uniform(0, 1)), p)
	y = _upsample(y / 3.0, D, n) if D > 1 else y[:n] / 3.0
	y = F.lowpass(y, cut, 2)
	y = F.peak_eq(y, 480, 3.0, 1.2)
	y = F.highpass(y, 40, 2)
	bow = F.bandpass(rng.standard_normal(ns(total)), min(f * 2.5, 6000), min(f * 7.0, 9000), 1) * 0.03
	y += S.pan(bow, 0.0) * env_perc(total, 0.01, max(attack * 2, 0.08))[:, None]
	return y * env[:, None] * vel * 0.55


def house_pad(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.9, release: float = 1.4,
		cutoff: float = 1300.0, detune: float = 7.0) -> np.ndarray:
	"""The house pad (same recipe as hhsynth.music.pad: three detuned saw/triangle voices with slow
	vibrato, 2-pole low-pass at min(cutoff, 5 f), gentle high-pass) with its oscillators run at SR/4 -
	for the very long, dark drone chords of the Works (cutoff <= 1.2 kHz)."""
	total = dur + release
	n = ns(total)
	D = 4 if min(cutoff, f * 5.0) <= 1200.0 else 1
	nl = n // D + 2
	sl = SR / D
	env = env_adsr(total, attack, 0.5, 1.0, release, gate=dur)
	y = np.zeros((nl, 2))
	for c, p in ((-detune, -0.6), (0.0, 0.0), (detune, 0.6)):
		fr = _lr_vibrato(f * 2 ** (c / 1200.0), nl, sl, rng.uniform(0.15, 0.35), 3.0, 0.0, 1e-3, rng.uniform(0, 1))
		v = 0.55 * _lr_saw(fr, sl, rng.uniform(0, 1)) + 0.45 * _lr_tri(fr, sl, rng.uniform(0, 1))
		y += S.pan(v, p)
	y = y / 3.0
	y = _upsample(y, D, n) if D > 1 else y[:n]
	y = F.lowpass(y, min(cutoff, f * 5.0), 2)
	y = F.highpass(y, 60, 1)
	return y * env[:, None] * vel


def fiddle(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.08,
		release: float = 0.22, vib: float = 13.0, swell: float = 0.0) -> np.ndarray:
	"""Solo bowed string ('velvet fiddle'): saw source with pitch drift + delayed vibrato through a
	violin-body formant bank, bow noise, optional crescendo on long notes."""
	total = dur + release
	n = ns(total)
	drift = _wander(total, rng, 2.0, -4.0, 4.0)
	fr = osc.vibrato(f * 2 ** (drift / 1200.0), total, rate=rng.uniform(5.2, 5.9), cents=vib,
		delay=min(0.2, dur * 0.3), rise=0.35, phase0=rng.uniform(0, 1))
	src = osc.saw(fr, total, rng.uniform(0, 1))
	y = F.formants(src, [(290, 2.5, 1.0), (540, 2.5, 0.7), (1150, 3.0, 0.5), (2300, 3.5, 0.35), (3400, 4.0, 0.12)])
	y += 0.12 * F.lowpass(src, 1800, 2)
	y = F.lowpass(y, 5200, 2)
	amp = env_adsr(total, attack, 0.4, 0.85, release, gate=dur)
	if swell > 0 and dur > 0.6:
		t = np.arange(n) / SR
		amp *= (1.0 - swell) + swell * np.clip(t / dur, 0, 1) ** 0.8
	bow = F.lowpass(F.bandpass(rng.standard_normal(n), 2200, 5000, 1), 6000, 2) * 0.022
	return F.lowpass(y + bow, 4800, 1) * amp * vel * 0.9


def reed(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.03,
		release: float = 0.09, vib: float = 6.0) -> np.ndarray:
	"""Bassoon-like double reed: buzzy saw/pulse source, nasal formants (~470 Hz and ~1.2 kHz),
	light vibrato and breath. Works staccato (short dur) and legato."""
	total = dur + release
	n = ns(total)
	drift = _wander(total, rng, 2.5, -3.0, 3.0)
	fr = osc.vibrato(f * 2 ** (drift / 1200.0), total, rate=rng.uniform(4.6, 5.2), cents=vib,
		delay=min(0.25, dur * 0.5), rise=0.3, phase0=rng.uniform(0, 1))
	src = 0.7 * osc.saw(fr, total, rng.uniform(0, 1)) + 0.3 * osc.pulse(fr, total, 0.42, rng.uniform(0, 1))
	src = F.lowpass(src, min(3800.0, f * 14.0), 2)
	y = F.formants(src, [(470, 4.0, 1.0), (1180, 5.0, 0.45), (2500, 6.0, 0.12)]) + 0.35 * F.lowpass(src, 650, 2)
	amp = env_adsr(total, attack, 0.15, 0.8, release, gate=dur)
	t = np.arange(n) / SR
	amp *= 1.0 + 0.25 * np.exp(-t / 0.04)        # little tongued accent
	breath = F.bandpass(rng.standard_normal(n), 1200, 4000, 1) * 0.02
	return F.highpass((y + breath) * amp, 50, 2) * vel * 0.8


_VOWELS = {
	"oo": [(320, 5.0, 1.0), (780, 6.0, 0.30), (2300, 9.0, 0.05)],
	"oh": [(460, 5.0, 1.0), (840, 6.0, 0.50), (2400, 9.0, 0.07)],
	"ah": [(720, 5.0, 1.0), (1100, 6.0, 0.55), (2500, 9.0, 0.09)],
	"mm": [(260, 4.0, 1.0), (1800, 8.0, 0.04), (2600, 9.0, 0.02)],
}


def choir(f: float, dur: float, vel: float, rng: np.random.Generator, vowel: str = "oo", to: str | None = None,
		voices: int = 5, attack: float = 0.55, release: float = 1.0, spread: float = 0.7) -> np.ndarray:
	"""Wordless choral pad (stereo): several singers (detuned, own vibrato and drift) through vowel
	formants, optionally morphing from `vowel` to `to` over the note; breath noise. No words."""
	total = dur + release
	n = ns(total)
	D = 2                                   # singers rendered at 22.05 kHz (all content < 6.5 kHz)
	nl = n // D + 2
	sl = SR / D
	idx = np.minimum(np.arange(nl) * D, n - 1)
	L = np.zeros(nl)
	R = np.zeros(nl)
	for i in range(voices):
		c = rng.uniform(-10.0, 10.0)
		drift = _wander(total, rng, 1.2, -5.0, 5.0)[idx]
		fr = _lr_vibrato(f * 2 ** (c / 1200.0), nl, sl, rng.uniform(4.4, 5.6), rng.uniform(10, 18), 0.25, 0.6,
			rng.uniform(0, 1)) * 2 ** (drift / 1200.0)
		v = _lr_saw(fr, sl, rng.uniform(0, 1))
		v *= 1.0 + 0.08 * _wander(total, rng, 3.0, -1.0, 1.0)[idx]
		p = spread * (2.0 * i / max(voices - 1, 1) - 1.0)
		a = (p + 1.0) * 0.25 * np.pi
		L += v * np.cos(a)
		R += v * np.sin(a)
	src = _upsample(np.stack([L, R], axis=1) / voices, D, n)
	src = F.lowpass(src, 3000, 2)

	def bank(x, name):
		return F.formants(x, [(fc, q, g) for fc, q, g in _VOWELS[name]])
	y = bank(src, vowel)
	if to is not None and to != vowel:
		w = np.clip(np.arange(n) / max(ns(dur), 1), 0, 1)[:, None]
		y = y * (1 - w) + bank(src, to) * w
	breath = F.lowpass(F.bandpass(rng.standard_normal((n, 2)), 1500, 5000, 1), 5500, 2) * 0.025
	y = F.lowpass(y + breath, 6500, 2)
	env = env_adsr(total, attack, 0.6, 0.9, release, gate=dur)
	return F.highpass(y, 90, 2) * env[:, None] * vel * 1.6


# ------------------------------------------------------------------------------------------
# Bells, metal, drums
# ------------------------------------------------------------------------------------------

_BELL = [(0.5, 0.45, 1.3), (1.0, 0.7, 1.0), (1.183, 0.5, 0.75), (1.506, 0.28, 0.55), (2.0, 1.0, 0.5),
	(2.51, 0.3, 0.35), (2.99, 0.22, 0.25), (4.16, 0.14, 0.16), (5.43, 0.08, 0.1)]


def church_bell(f: float, dur: float, vel: float, rng: np.random.Generator, t60: float = 6.0,
		bright: float = 0.6) -> np.ndarray:
	"""Cast bell: hum / prime / minor-third tierce / quint / nominal ... partials, each a slowly
	beating pair (warble), plus a clapper strike. f = the prime (heard pitch)."""
	length = t60 * 1.1
	n = ns(length)
	t = np.arange(n) / SR
	y = np.zeros(n)
	for r, a, d in _BELL:
		fr = f * r
		if fr > 12000:
			continue
		amp = a * (bright if r > 2.5 else 1.0)
		beat = rng.uniform(0.2, 0.9) * (0.5 + r * 0.3)
		ph = rng.uniform(0, 2 * np.pi)
		part = 0.5 * (np.sin(2 * np.pi * fr * t + ph) + np.sin(2 * np.pi * (fr + beat) * t + ph + 1.0))
		y += amp * part * np.exp(-6.9 * t / (t60 * d))
	strike = F.bandpass(rng.standard_normal(ns(0.015)), 800, 5000, 1) * env_perc(0.015, 0.0005, 0.012)
	y[:len(strike)] += strike * 0.15 * (0.5 + vel)
	y = F.lowpass(y, 7000, 1)
	return _fade_tail(_soft_start(y, 0.001), 0.3) * vel * 0.5


def bowed_metal(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 2.5,
		release: float = 3.5) -> np.ndarray:
	"""Bowed metal plate / singing bowl drone (stereo): stretched partials whose levels wander slowly,
	each a beating pair, cosine swell in and out; faint bow grit on the strongest partial."""
	total = dur + release
	n = ns(total)
	D = 4 if f * 5.4 < 4000.0 else 1
	nl = n // D + 2
	t = np.arange(nl) / (SR / D)
	L = np.zeros(nl)
	R = np.zeros(nl)
	for i, (r, a) in enumerate(((1.0, 1.0), (2.02, 0.35), (2.76, 0.3), (4.07, 0.12), (5.4, 0.06))):
		fr = f * r
		if fr > 10000:
			continue
		w = _wander(total, rng, 0.25, 0.0, 1.0)
		lvl = a * (0.6 + 0.4 * np.interp(np.arange(nl) * D, np.arange(len(w)), w))
		beat = rng.uniform(0.15, 0.6)
		ph = rng.uniform(0, 2 * np.pi, 2)
		L += lvl * np.sin(2 * np.pi * fr * t + ph[0])
		R += lvl * np.sin(2 * np.pi * (fr + beat) * t + ph[1])
	y = np.stack([L, R], axis=1)
	y = _upsample(y, D, n) if D > 1 else y[:n]
	grit = F.bandpass(rng.standard_normal(n), f * 2.6, f * 2.95, 2) * 0.05
	env = env_points([(0, 0), (attack, 1.0), (max(dur, attack + 0.01), 0.85), (total, 0)], total, "cos")
	y = (y + grit[:, None]) * env[:, None]
	return y * vel * 0.4


def timpani(f: float, dur: float, vel: float, rng: np.random.Generator, t60: float = 1.8) -> np.ndarray:
	"""Kettle drum: membrane modes 1 : 1.5 : 1.74 : 2.0 : 2.24 (tuned timpani), tiny pitch drop
	after the stroke, felt-mallet thump."""
	length = t60 * 1.1
	n = ns(length)
	t = np.arange(n) / SR
	bend = 1.0 + 0.012 * np.exp(-t / 0.05)
	y = np.zeros(n)
	for r, a, d in ((1.0, 1.0, 1.0), (1.504, 0.55, 0.75), (1.742, 0.3, 0.6), (2.0, 0.22, 0.5), (2.245, 0.12, 0.4),
			(2.494, 0.08, 0.3)):
		ph = osc.phase(f * r * bend, length)
		y += a * np.sin(2 * np.pi * ph + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / (t60 * d))
	thump = F.lowpass(rng.standard_normal(ns(0.03)), 500 + 900 * vel, 2) * env_perc(0.03, 0.001, 0.025)
	y[:len(thump)] += thump * 0.5
	y = F.lowpass(y, 2800, 2)
	return _fade_tail(_soft_start(y, 0.0015), 0.1) * vel * 0.8


def frame_drum(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Low frame drum / taiko-ish: pitch-dropping body, skin noise, short room-like ring."""
	length = 0.8
	fr = osc.glide(f * 1.6, f, 0.06, "exp", total=length)
	body = np.sin(2 * np.pi * osc.phase(fr, length)) * env_perc(length, 0.002, 0.5)
	body += 0.25 * np.sin(2 * np.pi * osc.phase(fr * 1.58, length)) * env_perc(length, 0.002, 0.18)
	skin = F.bandpass(rng.standard_normal(ns(length)), 200, 2400, 1) * env_perc(length, 0.001, 0.06)
	return F.lowpass(body + 0.3 * skin, 3000, 1) * vel


def brush(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Soft brushed snare swish (for light action rhythms)."""
	length = 0.22
	y = F.bandpass(rng.standard_normal(ns(length)), 1800, 7500, 2)
	env = env_points([(0, 0), (0.006, 1.0), (0.05, 0.4), (length, 0)], length)
	return y * env * vel * 0.45
