"""Ambience loops (stereo, seamless). Every layer is built to be exactly periodic over the loop:
noise beds are FFT-shaped over the loop length, modulators are periodic, steady tones use
frequencies with a whole number of cycles per loop, stateful filters run circularly, and event
layers (birds, drips, creaks) are rendered with their tails and folded back onto the start."""
from __future__ import annotations

import numpy as np

from catalog import loop
from hhsynth.core import SR, ns, env_points, env_perc, mix, place, fold_loop, circular, smooth_random
from hhsynth import osc, noise as N, filters as F, physical as P, fm as FM, music as M, space as S
import sfxlib as L


# ------------------------------------------------------------------------------------------
# Loop helpers
# ------------------------------------------------------------------------------------------

def qf(f: float, seconds: float) -> float:
	"""Quantise a frequency so it completes a whole number of cycles per loop."""
	return max(1.0, round(f * seconds)) / seconds


def tone(f: float, seconds: float, phase0: float = 0.0) -> np.ndarray:
	return np.sin(2 * np.pi * (qf(f, seconds) * np.arange(ns(seconds)) / SR + phase0))


def pmod(seconds: float, rng, rate: float, lo: float = 0.0, hi: float = 1.0) -> np.ndarray:
	"""Periodic slow random modulation."""
	return smooth_random(seconds, rng, rate, lo, hi, periodic=True)


def stereo_noise(seconds: float, rng, exponent: float, lo: float, hi: float, corr: float = 0.3) -> np.ndarray:
	"""Periodic stereo noise bed with partial inter-channel correlation."""
	c = N.colored(seconds, rng, exponent, lo, hi)
	l_ = N.colored(seconds, rng, exponent, lo, hi)
	r_ = N.colored(seconds, rng, exponent, lo, hi)
	a = np.sqrt(1 - corr)
	b = np.sqrt(corr)
	return np.stack([a * l_ + b * c, a * r_ + b * c], axis=1)


def circ(fn, x, pad=1.0):
	return circular(fn, x, ns(pad))


def circ_sweep(x: np.ndarray, kind: str, fc: np.ndarray, q, pad: float = 1.0) -> np.ndarray:
	"""Periodic time-varying filter (fc array is extended the same way as the signal)."""
	p = ns(pad)
	fcx = np.concatenate([fc[-p:], fc, fc[:p]])
	ext = np.concatenate([x[-p:], x, x[:p]], axis=0)
	y = F.sweep(ext, kind, fcx, q, block=128)
	return y[p:p + len(x)]


def event_times(rng, seconds: float, count: int, min_gap: float = 0.5) -> np.ndarray:
	"""Roughly even but irregular event times in [0, seconds)."""
	base = (np.arange(count) + rng.uniform(0.15, 0.85, count)) * seconds / count
	return np.sort(np.mod(base, seconds))


class Events:
	"""Stereo event bus with room for tails; fold() returns the periodic loop."""

	def __init__(self, seconds: float, tail: float = 8.0):
		self.n = ns(seconds)
		self.buf = np.zeros((self.n + ns(tail), 2))

	def add(self, t: float, sig: np.ndarray, pan: float = 0.0, gain: float = 1.0):
		place(self.buf, S.pan(sig, pan) if sig.ndim == 1 else sig, t, gain)

	def fold(self, ir: np.ndarray | None = None, wet: float = 0.3, dry: float = 1.0) -> np.ndarray:
		x = self.buf
		if ir is not None:
			x = S.reverb(x, ir, wet=wet, dry=dry)
		return fold_loop(x, self.n)


def looped_grains(seconds: float, rng, density_fn, band, grain, stereo_corr: float = 0.0) -> np.ndarray:
	"""Granular layer (rustle, crackle) folded into a seamless stereo loop."""
	pad = 0.1
	ts = np.linspace(0, seconds, int(seconds * 4) + 2)
	pts = [(float(t), float(density_fn(t))) for t in ts] + [(seconds + 0.001, 0.0), (seconds + pad, 0.0)]
	chans = [fold_loop(P.grains(seconds + pad, rng, pts, band, grain), ns(seconds)) for _ in range(2)]
	return np.stack(chans, axis=1)


def outdoor_ir(rng):
	return S.impulse_response(1.3, rng, predelay=0.025, damping=0.75, brightness=6000,
		early=[(0.03, 0.4), (0.07, 0.3), (0.12, 0.2)])


# ------------------------------------------------------------------------------------------
# Birds (original, synthesised phrases; not modelled on any real recording)
# ------------------------------------------------------------------------------------------

def bird_warbler(rng) -> np.ndarray:
	count = int(rng.integers(6, 11))
	base = rng.uniform(3600, 5000)
	parts = []
	t = 0.0
	for i in range(count):
		d = rng.uniform(0.035, 0.07)
		f0 = base * rng.uniform(0.9, 1.1) * (1.0 - 0.02 * i)
		pts = [(0, f0), (d * 0.3, f0 * 1.08), (d, f0 * rng.uniform(0.65, 0.8))]
		parts.append((t, L.squeak(pts, d, [(0, 0), (0.006, 1), (d * 0.6, 0.7), (d, 0)], harm=0.05), rng.uniform(0.6, 1.0)))
		t += d + rng.uniform(0.02, 0.05)
	return L.stagger(parts)


def bird_whistler(rng) -> np.ndarray:
	a = rng.uniform(2200, 2700)
	b = a * rng.uniform(1.12, 1.25)
	tee = L.squeak([(0, a), (0.17, b)], 0.2, [(0, 0), (0.03, 1), (0.15, 0.8), (0.2, 0)], 5.0, 8.0, 0.04)
	yoo = L.squeak([(0, b * 1.02), (0.3, a * 0.82)], 0.32, [(0, 0), (0.03, 1), (0.25, 0.6), (0.32, 0)], 5.0, 10.0, 0.04)
	parts = [(0.0, tee, 0.9), (0.26, yoo, 1.0)]
	if rng.uniform() < 0.5:
		parts.append((0.66, L.squeak([(0, a * 1.05), (0.12, b)], 0.14, [(0, 0), (0.02, 1), (0.14, 0)], harm=0.04), 0.6))
	return L.stagger(parts)


def bird_chip(rng) -> np.ndarray:
	f = rng.uniform(4200, 5800)
	parts = []
	t = 0.0
	for i in range(int(rng.integers(3, 6))):
		d = rng.uniform(0.018, 0.028)
		parts.append((t, L.squeak([(0, f * 1.1), (d, f * 0.8)], d, [(0, 0), (0.003, 1), (d, 0)], harm=0.03), 1.0))
		t += rng.uniform(0.2, 0.34)
	return L.stagger(parts)


def bird_trill(rng) -> np.ndarray:
	f = rng.uniform(3400, 4400)
	rate = rng.uniform(17, 24)
	count = int(rng.integers(14, 26))
	parts = []
	for i in range(count):
		g = np.sin(np.pi * (i + 0.5) / count) ** 0.7
		parts.append((i / rate, L.squeak([(0, f * 1.05), (0.025, f * 0.9)], 0.028, [(0, 0), (0.004, 1), (0.028, 0)], harm=0.03), g))
	return L.stagger(parts)


def bird_coo(rng) -> np.ndarray:
	f = rng.uniform(470, 560)
	parts = []
	t = 0.0
	for i, (d, g) in enumerate(((0.3, 0.7), (0.45, 1.0), (0.32, 0.75))):
		fr = osc.glide(f * (1.03 if i == 1 else 1.0), f * 0.95, d, "exp")
		y = np.sin(2 * np.pi * osc.phase(fr, d)) + 0.08 * np.sin(4 * np.pi * osc.phase(fr, d))
		y = y + 0.06 * F.bandpass(rng.standard_normal(ns(d)), f * 0.8, f * 2.5, 1)
		y *= env_points([(0, 0), (0.07, 1), (d * 0.6, 0.8), (d, 0)], d, "cos")
		parts.append((t, y, g))
		t += d + rng.uniform(0.12, 0.2)
	return L.stagger(parts)


def bird(rng, kind: str) -> np.ndarray:
	return {"warbler": bird_warbler, "whistler": bird_whistler, "chip": bird_chip, "trill": bird_trill,
		"coo": bird_coo}[kind](rng)


# ------------------------------------------------------------------------------------------
# Loops
# ------------------------------------------------------------------------------------------

@loop("amb_forest_day", "ambience", 72.0, rms=-27.0)
def amb_forest_day(rng, seconds):
	n = ns(seconds)
	gust = pmod(seconds, rng, 0.12, 0.25, 1.0)
	wind = stereo_noise(seconds, rng, 1.0, 140, 1600, 0.4) * gust[:, None]
	rustle = looped_grains(seconds, rng, lambda t: 40 + 520 * np.interp(t, np.arange(n) / SR, gust) ** 2,
		(1800, 7500), (0.002, 0.01))
	ev = Events(seconds)
	# resident birds: each sings from its own spot at its own pace
	residents = [("whistler", -0.55, 9.5, 18), ("warbler", 0.45, 13.0, 22), ("chip", 0.8, 7.0, 30)]
	for kind, p, gap, dist in residents:
		t = rng.uniform(0, gap)
		while t < seconds:
			sig = S.distant(bird(rng, kind), dist * rng.uniform(0.8, 1.2))
			ev.add(t, F.lowpass(sig, 8000, 2), p + rng.uniform(-0.1, 0.1), rng.uniform(0.7, 1.0))
			t += gap * rng.uniform(0.75, 1.3)
	for t in event_times(rng, seconds, 9):
		kind = ["warbler", "trill", "chip", "whistler"][int(rng.integers(0, 4))]
		sig = S.distant(bird(rng, kind), rng.uniform(15, 45))
		ev.add(t, F.lowpass(sig, 8000, 2), rng.uniform(-0.9, 0.9), rng.uniform(0.5, 0.9))
	for t in event_times(rng, seconds, 3):
		ev.add(t, S.distant(bird(rng, "coo"), 60), rng.uniform(-0.8, 0.8), 0.9)
	birds = ev.fold(outdoor_ir(rng), wet=0.35, dry=1.0)
	return 0.2 * L.nz(wind) + 0.28 * L.nz(rustle) + 0.4 * L.nz(birds)


def cricket_chirp(rng, f: float, pulses: int, rate: float) -> np.ndarray:
	d = pulses / rate + 0.03
	y = np.zeros(ns(d))
	pl = ns(min(0.018, 0.7 / rate))
	w = np.hanning(pl)
	t = np.arange(pl) / SR
	for i in range(pulses):
		s = ns(i / rate)
		car = np.sin(2 * np.pi * f * t) + 0.15 * np.sin(4 * np.pi * f * t)
		y[s:s + pl] += car[:len(y[s:s + pl])] * w[:len(y[s:s + pl])] * (0.8 + 0.2 * rng.uniform())
	return y


@loop("amb_forest_night", "ambience", 70.0, rms=-28.0)
def amb_forest_night(rng, seconds):
	gust = pmod(seconds, rng, 0.08, 0.2, 0.8)
	wind = stereo_noise(seconds, rng, 1.2, 110, 1000, 0.4) * gust[:, None]
	ev = Events(seconds)
	# crickets: each has its own pitch, rhythm and place
	for c in range(7):
		f = rng.uniform(3900, 5200)
		period = rng.uniform(0.55, 0.95)
		pulses = int(rng.integers(3, 5))
		rate = rng.uniform(26, 36)
		p = rng.uniform(-0.9, 0.9)
		g = rng.uniform(0.25, 1.0)
		dist = rng.uniform(4, 25)
		chirp = S.distant(cricket_chirp(rng, f, pulses, rate), dist)
		# crickets pause now and then (periodic-ish activity envelope)
		act = pmod(seconds, rng, 0.05, -0.6, 1.0)
		t = rng.uniform(0, period)
		while t < seconds:
			a = float(np.clip(act[min(ns(t), len(act) - 1)], 0, 1))
			if a > 0.05:
				ev.add(t, chirp, p, g * a * rng.uniform(0.8, 1.0))
			t += period * rng.uniform(0.95, 1.05)
	for t in event_times(rng, seconds, 3):
		ev.add(t, S.distant(_hoot(rng), 40), rng.uniform(-0.7, 0.7), 1.0)
	calls = ev.fold(outdoor_ir(rng), wet=0.3, dry=1.0)
	rustle = looped_grains(seconds, rng, lambda t: 10 + 120 * float(np.interp(t, np.linspace(0, seconds, len(gust)), gust)) ** 3,
		(1500, 6000), (0.003, 0.012))
	return 0.25 * L.nz(wind) + 0.3 * L.nz(calls) + 0.08 * L.nz(rustle)


def _hoot(rng) -> np.ndarray:
	"""Owl-like 'hoo ... hoo-hoo' (soft, low, breathy)."""
	f = rng.uniform(360, 420)
	parts = []
	for t, d, g in ((0.0, 0.55, 1.0), (0.95, 0.28, 0.75), (1.33, 0.42, 0.85)):
		fr = osc.glide(f * 1.02, f * 0.94, d, "exp")
		y = np.sin(2 * np.pi * osc.phase(fr, d)) + 0.05 * np.sin(4 * np.pi * osc.phase(fr, d))
		y += 0.08 * F.bandpass(rng.standard_normal(ns(d)), f, f * 3, 1)
		parts.append((t, y * env_points([(0, 0), (0.09, 1), (d * 0.5, 0.85), (d, 0)], d, "cos"), g))
	return L.stagger(parts)


@loop("amb_stream", "ambience", 48.0, rms=-27.0)
def amb_stream(rng, seconds):
	pad = 0.3
	chans = []
	for c in range(2):
		b = P.bubbles(seconds + pad, rng, [(0, 260), (seconds, 260), (seconds + 0.001, 0), (seconds + pad, 0)],
			(280, 2400), (0.012, 0.05), (1.3, 2.6), (0.05, 1.0))
		chans.append(fold_loop(b, ns(seconds)))
	bub = np.stack(chans, axis=1)
	rush = stereo_noise(seconds, rng, 0.5, 400, 6000, 0.5) * (0.8 + 0.2 * pmod(seconds, rng, 0.7))[:, None]
	gurgle = stereo_noise(seconds, rng, 1.5, 90, 500, 0.6) * pmod(seconds, rng, 1.5, 0.3, 1.0)[:, None]
	return 0.8 * L.nz(bub) + 0.12 * L.nz(rush) + 0.18 * L.nz(gurgle)


def _drip(rng, f0) -> np.ndarray:
	return P.bubble(f0, 0.12, rise=rng.uniform(1.4, 1.9), t60=rng.uniform(0.03, 0.06))


def _far_creak(rng, base) -> np.ndarray:
	d = rng.uniform(1.2, 2.2)
	cr = L.creak(rng, d, [(0, rng.uniform(20, 30)), (d * 0.6, rng.uniform(45, 70)), (d, 30)],
		[(0, 0.1), (d * 0.5, 1), (d, 0)], base, 0.08)
	return F.lowpass(L.nz(cr), 2500, 2)


@loop("amb_mine", "ambience", 60.0, rms=-26.0)
def amb_mine(rng, seconds):
	drone = (tone(55.0, seconds) + 0.55 * tone(82.4, seconds, 0.3) + 0.3 * tone(110.3, seconds, 0.6))
	drone = drone * (0.75 + 0.25 * pmod(seconds, rng, 0.07))
	rumble = stereo_noise(seconds, rng, 2.0, 25, 160, 0.7) * pmod(seconds, rng, 0.05, 0.4, 1.0)[:, None]
	air = stereo_noise(seconds, rng, 1.0, 150, 2500, 0.2) * pmod(seconds, rng, 0.1, 0.2, 1.0)[:, None]
	ev = Events(seconds)
	for t in event_times(rng, seconds, 16):
		ev.add(t, _drip(rng, rng.uniform(900, 1700)), rng.uniform(-0.9, 0.9), rng.uniform(0.3, 1.0))
	for t in event_times(rng, seconds, 3):
		ev.add(t, S.distant(_far_creak(rng, rng.uniform(180, 260)), 12), rng.uniform(-0.7, 0.7), 0.8)
	cave = S.cave(rng, 3.5)
	events = ev.fold(cave, wet=0.6, dry=0.6)
	return 0.12 * L.nz(drone)[:, None] + 0.18 * L.nz(rumble) + 0.22 * L.nz(air) + 0.6 * L.nz(events)


@loop("amb_ruins", "ambience", 60.0, rms=-26.0)
def amb_ruins(rng, seconds):
	drone = (tone(146.83, seconds) + 0.6 * tone(220.0, seconds, 0.2) + 0.35 * tone(293.9, seconds, 0.5)
		+ 0.12 * tone(659.3, seconds, 0.1))
	drone = drone * (0.25 + 0.75 * pmod(seconds, rng, 0.06))
	# wind moaning through arches: narrow resonances drifting in pitch
	n = ns(seconds)
	wind = np.zeros((n, 2))
	for c in range(2):
		src = N.colored(seconds, rng, 1.0, 100, 4000)
		fc = 500 + 800 * pmod(seconds, rng, 0.05)
		moan = circ_sweep(src, "bandpass", fc, 9.0)
		wind[:, c] = L.nz(moan) * pmod(seconds, rng, 0.06, 0.1, 1.0)
	hiss = stereo_noise(seconds, rng, 0.8, 1000, 6000, 0.2) * pmod(seconds, rng, 0.08, 0.2, 0.8)[:, None]
	ev = Events(seconds, tail=9.0)
	for t in event_times(rng, seconds, 20):
		ev.add(t, _drip(rng, rng.uniform(700, 1300)), rng.uniform(-0.9, 0.9), rng.uniform(0.3, 1.0))
	for t in event_times(rng, seconds, 5):
		d = rng.uniform(0.6, 1.1)
		lap = F.lowpass(rng.standard_normal(ns(d)), 500, 2) * env_points([(0, 0), (d * 0.4, 1), (d, 0)], d, "cos")
		ev.add(t, L.nz(lap) * 0.5, rng.uniform(-0.6, 0.6), 0.6)
	hall = S.impulse_response(3.2, rng, predelay=0.04, damping=0.8, brightness=4500,
		early=[(0.03, 0.5), (0.07, 0.35), (0.13, 0.25)])
	events = ev.fold(hall, wet=0.6, dry=0.6)
	return 0.14 * L.nz(drone)[:, None] + 0.4 * L.nz(wind) + 0.05 * L.nz(hiss) + 0.55 * L.nz(events)


@loop("amb_silk", "ambience", 60.0, rms=-28.5)
def amb_silk(rng, seconds):
	n = ns(seconds)
	# a few very quiet, slowly beating high tones that fade in and out (uneasy, not melodic).
	# Review fix: at weight 0.2 these 2-3 kHz sine pairs carried ~56% of the loop's energy and swelled
	# to the loudest short-term level of any dungeon bed (tinnitus-like, not "very quiet"); now 6 dB
	# lower relative to the creaks and drips, and the loop target is 0.5 dB lower so those stay put.
	tones = np.zeros((n, 2))
	for i in range(6):
		f = rng.uniform(2200, 3300)
		beat = rng.uniform(0.7, 2.5)
		pair = tone(f, seconds, rng.uniform()) + tone(f + beat, seconds, rng.uniform())
		env = np.clip(pmod(seconds, rng, 0.08, -1.2, 1.0), 0, 1) ** 2
		tones += S.pan(pair * env, rng.uniform(-0.8, 0.8))
	sub = tone(46.0, seconds) * (0.5 + 0.5 * pmod(seconds, rng, 0.04))
	air = stereo_noise(seconds, rng, 0.8, 2500, 8000, 0.1) * pmod(seconds, rng, 0.07, 0.1, 0.6)[:, None]
	ev = Events(seconds)
	for t in event_times(rng, seconds, 3):
		d = rng.uniform(0.8, 1.4)
		cr = L.creak(rng, d, [(0, 120), (d, 220)], [(0, 0), (d * 0.5, 1), (d, 0)], rng.uniform(700, 1000), 0.02)
		ev.add(t, F.lowpass(L.nz(cr), 4000, 2), rng.uniform(-0.8, 0.8), 0.6)
	for t in event_times(rng, seconds, 6):
		ev.add(t, _drip(rng, rng.uniform(1400, 2000)), rng.uniform(-0.9, 0.9), rng.uniform(0.2, 0.5))
	events = ev.fold(S.cave(rng, 2.8, echoes=((0.12, 0.35), (0.23, 0.2)), brightness=3000), wet=0.6, dry=0.5)
	return 0.1 * L.nz(tones) + 0.035 * L.nz(sub)[:, None] + 0.05 * L.nz(air) + 0.5 * L.nz(events)


@loop("amb_boss", "ambience", 45.0, rms=-28.0)
def amb_boss(rng, seconds):
	# A tense low pulse WITHOUT percussive hits: the boss music (120 bpm) plays on top of this bed,
	# so a separate drum rhythm would clash. The "pulse" is a slow, smooth throb of the drone.
	n = ns(seconds)
	period = seconds / 20.0                   # 2.25 s throb, 20 per loop (exactly periodic)
	t = np.arange(n) / SR
	throb = (0.5 - 0.5 * np.cos(2 * np.pi * t / period)) ** 1.5
	drone = (tone(73.42, seconds) + 0.6 * tone(110.0, seconds, 0.25) + 0.3 * tone(77.78, seconds, 0.5)
		+ 0.15 * tone(146.83, seconds, 0.1))
	drone = drone * (0.45 + 0.55 * throb)
	sub = tone(36.71, seconds) * (0.3 + 0.7 * throb)
	breath = stereo_noise(seconds, rng, 1.2, 150, 900, 0.5) * (0.35 + 0.65 * throb)[:, None]
	tension = stereo_noise(seconds, rng, 0.8, 400, 4000, 0.3)
	fc = 900 + 700 * pmod(seconds, rng, 0.05)
	tension = np.stack([circ_sweep(tension[:, c], "bandpass", fc, 3.0) for c in range(2)], axis=1)
	tension *= pmod(seconds, rng, 0.07, 0.3, 1.0)[:, None]
	ev = Events(seconds)
	for t0 in event_times(rng, seconds, 2):
		ev.add(t0, S.distant(_far_creak(rng, rng.uniform(150, 220)), 15), rng.uniform(-0.7, 0.7), 0.7)
	creaks = ev.fold(S.cave(rng, 3.0), wet=0.6, dry=0.5)
	return (0.35 * L.nz(drone)[:, None] + 0.12 * L.nz(sub)[:, None] + 0.25 * L.nz(breath) + 0.22 * L.nz(tension)
		+ 0.3 * L.nz(creaks))
