"""Creature voices: companions (Mochi squeaks, Pebble clacks/grunts, Lumi glass chimes and the
subtly wrong imitation) and enemies (Brambling, Gloomling, Weaver, and the non-arachnid Shade
alternatives used in arachnophobia mode)."""
from __future__ import annotations

import numpy as np

from catalog import sound
from hhsynth.core import ns, env_points, env_perc, mix, place, smooth_random
from hhsynth import osc, noise as N, filters as F, physical as P, fm as FM, music as M
import sfxlib as L


# ------------------------------------------------------------------------------------------
# Mochi: tiny, high, pitch-bent squeaks
# (Review: peaks lowered 3 dB more. Near-sine squeaks at 2-3 kHz measured as loud as the Weaver's
# shriek in short-term weighted loudness; now they sit between Lumi's chimes and Pebble's voice.)
# ------------------------------------------------------------------------------------------

def _mochi_syllable(rng, f0, shape: str, dur: float, vib: float = 0.0) -> np.ndarray:
	if shape == "up":
		pts = [(0, f0 * 0.8), (dur * 0.6, f0 * 1.25), (dur, f0 * 1.15)]
	elif shape == "down":
		pts = [(0, f0 * 1.2), (dur * 0.3, f0 * 1.3), (dur, f0 * 0.85)]
	elif shape == "hat":
		pts = [(0, f0 * 0.9), (dur * 0.4, f0 * 1.3), (dur, f0 * 0.95)]
	else:  # question
		pts = [(0, f0), (dur * 0.5, f0 * 0.95), (dur, f0 * 1.4)]
	amp = [(0, 0), (min(0.012, dur * 0.2), 1.0), (dur * 0.7, 0.8), (dur, 0)]
	return L.squeak(pts, dur, amp, vib_rate=vib, vib_cents=60 if vib else 0, harm=0.15)


@sound("mochi_chirp", variants=3, peak=-15.0)
def mochi_chirp(rng, v):
	if v == 0:
		y = _mochi_syllable(rng, 2100, "up", 0.11)
	elif v == 1:
		y = L.stagger([(0.0, _mochi_syllable(rng, 2300, "down", 0.075), 1.0), (0.1, _mochi_syllable(rng, 2200, "up", 0.09), 0.85)])
	else:
		y = _mochi_syllable(rng, 1900, "question", 0.16)
	return F.lowpass(y, 8000, 2)


@sound("mochi_happy", variants=3, peak=-14.5)
def mochi_happy(rng, v):
	if v == 0:
		fs = [1900, 2200, 2500, 2900]
		parts = [(i * 0.07, _mochi_syllable(rng, f, "hat", 0.06), 0.8 + 0.05 * i) for i, f in enumerate(fs)]
	elif v == 1:
		parts = [(0.0, _mochi_syllable(rng, 2000, "up", 0.08), 0.9), (0.09, _mochi_syllable(rng, 2600, "hat", 0.07), 0.9),
			(0.17, _mochi_syllable(rng, 2400, "up", 0.16, vib=18.0), 1.0)]
	else:
		pts = [(0, 1700), (0.12, 2900), (0.2, 2500), (0.3, 3100)]
		parts = [(0.0, L.squeak(pts, 0.32, [(0, 0), (0.02, 1), (0.25, 0.8), (0.32, 0)], 14.0, 45.0, 0.15), 1.0)]
	return F.lowpass(L.stagger(parts), 8500, 2)


@sound("mochi_scared", variants=3, peak=-15.0)
def mochi_scared(rng, v):
	if v == 0:
		pts = [(0, 2500), (0.1, 2650), (0.42, 1600)]
		y = L.squeak(pts, 0.45, [(0, 0), (0.02, 1), (0.3, 0.6), (0.45, 0)], 13.0, 70.0, 0.12)
		y *= 1.0 - 0.45 * (0.5 + 0.5 * np.sin(2 * np.pi * 11.0 * np.arange(len(y)) / 44100))
	elif v == 1:
		y = L.stagger([(0.0, _mochi_syllable(rng, 2600, "down", 0.08), 1.0), (0.11, _mochi_syllable(rng, 2200, "down", 0.1), 0.8)])
	else:
		eep = _mochi_syllable(rng, 2800, "hat", 0.07)
		tail = L.squeak([(0, 2200), (0.3, 1700)], 0.3, [(0, 0), (0.03, 0.6), (0.3, 0)], 16.0, 90.0, 0.1)
		y = L.stagger([(0.0, eep, 1.0), (0.08, tail, 0.7)])
	return F.lowpass(y, 8000, 2)


# ------------------------------------------------------------------------------------------
# Pebble: gravelly clacks and grunts
# ------------------------------------------------------------------------------------------

def _clack(rng, f, g=1.0):
	return L.stone(rng, f, 0.1, t60=0.035, bright=0.7, click=0.4) * g


def _gravel(rng, dur, dens=900):
	return L.nz(L.crunch(rng, dur, [(0, dens), (dur, 0)], (1500, 6500), (0.0005, 0.002)))


@sound("pebble_clack", variants=3, peak=-8.0)
def pebble_clack(rng, v):
	counts = [2, 3, 2][v]
	parts = []
	t = 0.0
	for i in range(counts):
		parts.append((t, _clack(rng, rng.uniform(1200, 1800)), 1.0 - 0.15 * i))
		t += rng.uniform(0.06, 0.1)
	parts.append((0.0, _gravel(rng, t + 0.08, 500), 0.2))
	return F.lowpass(L.stagger(parts), 7500, 2)


def _pebble_voice(rng, f_pts, dur, rough=0.9):
	bank = [(520, 5.0, 1.0), (980, 6.0, 0.6), (2300, 8.0, 0.25)]
	amp = [(0, 0), (0.025, 1), (dur * 0.7, 0.8), (dur, 0)]
	y = L.voice(rng, f_pts, dur, bank, amp, rough=rough, breath=0.15)
	grit = F.bandpass(rng.standard_normal(ns(dur)), 1500, 5000, 1)
	am = np.abs(F.lowpass(rng.standard_normal(ns(dur)), 45, 2))
	return F.lowpass(y + 0.12 * L.nz(grit * am) * env_points(amp, dur), 4500, 2)


@sound("pebble_happy", variants=3, peak=-8.0)
def pebble_happy(rng, v):
	if v == 0:
		a = _pebble_voice(rng, [(0, 150), (0.12, 210)], 0.14)
		b = _pebble_voice(rng, [(0, 170), (0.15, 240)], 0.17)
		y = L.stagger([(0.0, a, 0.9), (0.18, b, 1.0), (0.36, _clack(rng, 1500), 0.4)])
	elif v == 1:
		a = _pebble_voice(rng, [(0, 140), (0.1, 190), (0.25, 230)], 0.27)
		y = L.stagger([(0.0, a, 1.0), (0.29, _clack(rng, 1400), 0.5), (0.36, _clack(rng, 1700), 0.4)])
	else:
		y = L.stagger([(0.0, _clack(rng, 1300), 0.6), (0.08, _clack(rng, 1600), 0.6),
			(0.16, _pebble_voice(rng, [(0, 160), (0.2, 250)], 0.22), 1.0)])
	return y


@sound("pebble_grunt", variants=3, peak=-8.0)
def pebble_grunt(rng, v):
	f0 = [125, 112, 135][v]
	d = [0.28, 0.33, 0.24][v]
	y = _pebble_voice(rng, [(0, f0 * 1.08), (d * 0.3, f0 * 1.12), (d, f0 * 0.86)], d, rough=1.2)
	return mix(y, _gravel(rng, d, 400) * 0.12)


# ------------------------------------------------------------------------------------------
# Lumi: glassy three-note chimes (and the imitation: same motif, reversed & detuned)
# ------------------------------------------------------------------------------------------

LUMI_MOTIFS = [["E6", "G#6", "B6"], ["B6", "G#6", "E6"], ["E6", "B6", "G#6"]]


def _lumi(motif, spacing=0.12, t60=1.4, detune=0.0, stretch=1.0, sparkle=0.9):
	seq = [(i * spacing, n, 0.9 - 0.1 * i) for i, n in enumerate(motif)]
	return L.glass_notes(seq, t60=t60, sparkle=sparkle, detune=detune, stretch=stretch)


@sound("lumi_chime", variants=3, peak=-9.0, fout=0.15)
def lumi_chime(rng, v):
	return F.lowpass(_lumi(LUMI_MOTIFS[v]), 11000, 2)


@sound("lumi_happy", variants=3, peak=-10.0, fout=0.15)   # review: -2 dB, was louder than the shrieks (K-weighted)
def lumi_happy(rng, v):
	runs = [["E6", "G#6", "B6", "E7"], ["B5", "E6", "G#6", "B6", "C#7"], ["G#6", "B6", "E7", "B6", "E7"]]
	seq = [(i * 0.065, n, 0.8) for i, n in enumerate(runs[v])]
	y = L.glass_notes(seq, t60=1.2, sparkle=1.1)
	shimmer = F.bandpass(N.pink(1.2, rng), 5000, 10000, 1) * env_points([(0, 0), (0.2, 1), (1.2, 0)], 1.2, "cos")
	return F.lowpass(mix(L.nz(y), L.nz(shimmer) * 0.05), 11000, 2)


@sound("lumi_warn", variants=2, peak=-9.0, fout=0.2)
def lumi_warn(rng, v):
	motif = [(0.0, "B5", 0.9), (0.2, "G#5", 0.85)] if v == 0 else [(0.0, "C#6", 0.9), (0.2, "A5", 0.8), (0.4, "G#5", 0.7)]
	y = L.glass_notes(motif, t60=1.6, sparkle=0.5)
	trem = 1.0 - 0.35 * (0.5 + 0.5 * np.sin(2 * np.pi * 6.5 * np.arange(len(y)) / 44100))
	return F.lowpass(y * trem, 8000, 2)


@sound("fake_lumi_chime", variants=2, peak=-10.0, fin=0.02, fout=0.05)
def fake_lumi_chime(rng, v):
	# Same motif as lumi_chime_1/_2, but: partials slightly stretched, detuned ~a third of a
	# semitone flat, colder (no warm low end), and played backwards (swells into abrupt stops).
	y = _lumi(LUMI_MOTIFS[v], spacing=0.13, t60=1.3, detune=-38.0, stretch=1.035, sparkle=1.2)
	y = F.highpass(y, 900, 2)[::-1].copy()
	cold = L.squeak([(0, M.hz("E7") * 1.01), (len(y) / 44100, M.hz("E7") * 0.99)], len(y) / 44100,
		[(0, 0), (len(y) / 44100 * 0.8, 1), (len(y) / 44100, 0)])
	return mix(L.nz(y), cold * 0.03)


# ------------------------------------------------------------------------------------------
# Brambling: grumpy chattering thornball
# ------------------------------------------------------------------------------------------

def _bram_syllable(rng, f, d):
	bank = [(650, 4.0, 1.0), (1250, 5.0, 0.7), (2600, 6.0, 0.3)]
	pts = [(0, f), (d * 0.5, f * rng.uniform(1.05, 1.25)), (d, f * rng.uniform(0.8, 0.95))]
	return L.voice(rng, pts, d, bank, [(0, 0), (0.008, 1), (d * 0.6, 0.7), (d, 0)], rough=0.8, breath=0.2)


def _leaves(rng, d, pts):
	return L.nz(L.crunch(rng, d, pts, (1800, 7500), (0.002, 0.009)))


@sound("brambling_chatter", variants=3, peak=-8.0)
def brambling_chatter(rng, v):
	count = [5, 7, 4][v]
	parts = []
	t = 0.0
	for i in range(count):
		d = rng.uniform(0.045, 0.075)
		parts.append((t, _bram_syllable(rng, rng.uniform(210, 300), d), rng.uniform(0.6, 1.0)))
		t += d + rng.uniform(0.015, 0.05)
	parts.append((0.0, _leaves(rng, t + 0.1, [(0, 300), (t + 0.1, 100)]), 0.25))
	return F.lowpass(L.stagger(parts), 6000, 2)


@sound("brambling_telegraph", peak=-6.0)
def brambling_telegraph(rng, v):
	d = 0.8
	rustle = _leaves(rng, d, [(0, 40), (0.6, 600), (d, 700)]) * env_points([(0, 0.2), (0.7, 1), (d, 0.6)], d)
	growl = L.voice(rng, [(0, 135), (0.7, 215), (d, 230)], d, [(600, 4.0, 1.0), (1100, 5.0, 0.6), (2500, 6.0, 0.25)],
		[(0, 0), (0.5, 0.6), (0.75, 1.0), (d, 0)], rough=1.1, breath=0.25)
	thorns = L.stagger([(t, L.wood(rng, rng.uniform(1600, 2400), 0.04, 0.015, 0.4), 0.3) for t in np.sort(rng.uniform(0.2, d, 9))])
	return F.lowpass(L.stagger([(0.0, rustle, 0.6), (0.0, growl, 0.7), (0.0, L.nz(thorns), 0.3)], total=d + 0.05), 6500, 2)


# ------------------------------------------------------------------------------------------
# Gloomling: breathy shadow with dry-leaf tells
# ------------------------------------------------------------------------------------------

def _breath(rng, d, lo, hi, amp_pts, formant_bank=((2600, 3.0, 1.0), (4400, 4.0, 0.6))):
	x = F.bandpass(N.pink(d, rng), lo, hi, 1)
	x = mix(x * 0.3, F.formants(x, formant_bank))
	flutter = 1.0 + 0.2 * smooth_random(d, rng, 12.0, -1.0, 1.0)
	return L.nz(x * flutter) * env_points(amp_pts, d, "cos")


@sound("gloomling_hiss", variants=2, peak=-9.0, fout=0.1)
def gloomling_hiss(rng, v):
	d = 1.1 + 0.2 * v
	h = _breath(rng, d, 1500, 7000, [(0, 0), (0.22, 1), (0.7, 0.8), (d, 0)])
	low = _breath(rng, d, 300, 1000, [(0, 0), (0.3, 1), (d, 0)], ((600, 2.0, 1.0),))
	return F.lowpass(mix(h, low * 0.3), 7500, 2)


@sound("gloomling_telegraph", peak=-7.0)
def gloomling_telegraph(rng, v):
	d = 0.85
	crackle = L.crunch(rng, d, [(0, 60), (0.7, 700), (d, 900)], (2000, 9000), (0.0005, 0.0025))
	intake = F.sweep_points(N.pink(d, rng), "bandpass", [(0, 800), (d, 3200)], 2.0)
	intake = L.nz(intake) * env_points([(0, 0), (d * 0.8, 1), (d, 0.3)], d, "cos")
	return F.lowpass(mix(L.nz(crackle) * 0.45, intake * 0.7), 8000, 2)


@sound("gloomling_alert", peak=-7.0)
def gloomling_alert(rng, v):
	h = _breath(rng, 0.45, 1500, 7000, [(0, 0), (0.025, 1), (0.2, 0.6), (0.45, 0)])
	clicks = L.stagger([(i * 0.04, L.stone(rng, rng.uniform(2200, 3200), 0.03, 0.01, 0.5, 0.2), 0.5) for i in range(6)])
	growl = L.voice(rng, [(0, 95), (0.4, 85)], 0.4, [(400, 3.0, 1.0), (900, 4.0, 0.5)], [(0, 0), (0.05, 1), (0.4, 0)], 1.0, 0.3)
	return F.lowpass(L.stagger([(0.0, h, 0.8), (0.05, L.nz(clicks), 0.25), (0.0, growl, 0.35)]), 7500, 2)


@sound("gloomling_flinch", peak=-8.0)
def gloomling_flinch(rng, v):
	d = 0.35
	hiss = F.sweep_points(N.pink(d, rng), "bandpass", [(0, 4200), (d, 1200)], 2.5)
	hiss = L.nz(hiss) * env_points([(0, 0), (0.02, 1), (d, 0)], d, "cos")
	whimper = L.squeak([(0, 900), (0.3, 580)], 0.3, [(0, 0), (0.03, 1), (0.3, 0)], 11.0, 50.0, 0.3)
	return F.lowpass(mix(hiss * 0.8, whimper * 0.35), 7000, 2)


# ------------------------------------------------------------------------------------------
# Weaver (spider-like; replaced by Shade sounds in arachnophobia mode)
# ------------------------------------------------------------------------------------------

def _chitin_click(rng, g=1.0):
	f = rng.uniform(1700, 2300)
	return L.knock(rng, [f, f * 1.7, f * 2.8], [0.012, 0.008, 0.005], [1.0, 0.6, 0.3], 0.03, 0.0008, 8000, 0.3) * g


@sound("weaver_rattle", peak=-3.0, fout=0.04)
def weaver_rattle(rng, v):
	# The stalker/boss telegraph ("it rattles before lunging"), so it must read clearly. Review fix:
	# bare clicks measured ~7.5 dB (K-weighted) under shade_telegraph, its arachnophobia twin; a dry
	# papery buzz that follows the clicks fills the gaps (more loudness, no extra peak) and the peak
	# rose from -6 to -3 dBFS: short-term K-weighted level ~-17.5 dB now, vs -14.6 for the shade.
	d = 1.15
	times = []
	t = 0.0
	while t < d:
		rate = 16.0 + 20.0 * (t / d) ** 1.3
		times.append(t)
		t += 1.0 / rate * rng.uniform(0.85, 1.15)
	parts = [(tt, _chitin_click(rng), 0.25 + 0.75 * (tt / d) ** 1.5) for tt in times]
	clicks = L.stagger(parts, total=d)
	body = P.resonate(clicks, [720, 1300], [0.03, 0.02], [0.4, 0.2])
	am = np.zeros(len(clicks))
	w = np.hanning(ns(0.03))
	for tt in times:
		seg = am[ns(tt):ns(tt) + len(w)]
		seg += w[:len(seg)] * (0.25 + 0.75 * (tt / d) ** 1.5)
	buzz = F.bandpass(N.white(len(clicks) / 44100, rng), 1800, 5500, 1) * am
	return F.lowpass(mix(clicks, L.nz(body) * 0.35, L.nz(buzz) * 0.35), 7000, 2)


@sound("weaver_skitter", variants=2, peak=-8.0, fout=0.08)
def weaver_skitter(rng, v):
	d = 1.25
	parts = []
	for leg in range(8):
		rate = rng.uniform(9.0, 14.0)
		t = rng.uniform(0, 0.08)
		while t < d:
			parts.append((t, _chitin_click(rng), rng.uniform(0.3, 0.8)))
			t += 1.0 / rate * rng.uniform(0.8, 1.2)
	clicks = L.stagger(parts, total=d)
	scrape = F.bandpass(N.white(d, rng), 2500, 6000, 1) * 0.04
	env = env_points([(0, 0), (0.2, 1), (d - 0.25, 1), (d, 0)], d, "cos")
	return F.lowpass(mix(clicks, scrape)[:len(env)] * env, 7000 - 800 * v, 2)


@sound("weaver_shriek", peak=-5.0, fin=0.03, fout=0.2)
def weaver_shriek(rng, v):
	d = 1.7
	amp = [(0, 0), (0.14, 1.0), (0.7, 0.8), (d, 0)]
	layers = []
	for f0, g in ((620, 1.0), (657, 0.8), (905, 0.45)):
		f = osc.glide_points([(0, f0 * 0.9), (0.25, f0 * 1.26), (0.8, f0 * 1.15), (d, f0 * 0.75)], d)
		f = osc.vibrato(f, d, 23.0, 35.0)
		layers.append(FM.fm(f, d, 1.0, 1.8) * g)
	y = sum(layers)
	y = F.lowpass(y, 3200, 2)
	breath = F.bandpass(N.pink(d, rng), 1200, 4500, 1)
	rattle = weaver_rattle(rng, 0)
	out = mix(L.nz(y) * env_points(amp, d, "cos"), L.nz(breath) * env_points(amp, d, "cos") * 0.3)
	return F.lowpass(mix(out, L.nz(rattle) * 0.12), 5000, 2)


@sound("weaver_drop", peak=-4.0, fout=0.2)
def weaver_drop(rng, v):
	# heavy, soft landing: works for both the Weaver and the Hollow Mother
	boom = L.thud(rng, 50, 1.0, 0.45, 0.6)
	dust = F.lowpass(N.pink(1.0, rng), 1200, 2) * env_points([(0, 0), (0.05, 1), (1.0, 0)], 1.0, "cos")
	debris = L.stagger([(t, L.stone(rng, rng.uniform(900, 2200), 0.08, 0.02, 0.5, 0.2), 0.3 * np.exp(-t * 3))
		for t in np.sort(rng.uniform(0.05, 0.8, 9))])
	return L.stagger([(0.0, boom, 1.0), (0.0, L.nz(dust), 0.35), (0.03, L.nz(debris), 0.3)])


# ------------------------------------------------------------------------------------------
# Shade (arachnophobia alternative): whispery, airy, drifting - nothing clicks or skitters
# ------------------------------------------------------------------------------------------

def whisper(rng, d: float, syll_rate: float = 5.0) -> np.ndarray:
	"""Unintelligible whisper: noise through vowel-ish formants that jump every syllable,
	with a syllabic amplitude envelope and occasional soft sibilants."""
	n = ns(d)
	src = F.highpass(N.white(d, rng), 250, 2)
	f1 = np.zeros(n)
	f2 = np.zeros(n)
	amp = np.zeros(n)
	t = 0.0
	while t < d:
		sd = rng.uniform(0.7, 1.4) / syll_rate
		a = ns(t)
		b = min(n, ns(t + sd))
		f1[a:b] = rng.uniform(350, 800)
		f2[a:b] = rng.uniform(900, 2300)
		if b > a:
			w = np.sin(np.linspace(0, np.pi, b - a)) ** 1.5
			amp[a:b] = w * rng.uniform(0.4, 1.0)
		t += sd + rng.uniform(0.0, 0.12)
	f1 = F.lowpass(f1, 25, 1)
	f2 = F.lowpass(f2, 25, 1)
	y = F.sweep(src, "bandpass", np.maximum(f1, 200), 4.0) + 0.7 * F.sweep(src, "bandpass", np.maximum(f2, 500), 5.0)
	y += 0.25 * F.rbj(src, "bandpass", 2800, 3.0)
	sib_env = np.zeros(n)
	for _ in range(int(d * 1.2)):
		s = ns(rng.uniform(0, max(d - 0.15, 0.01)))
		m = ns(rng.uniform(0.06, 0.14))
		sib_env[s:s + m] += np.hanning(len(sib_env[s:s + m]))
	sib = F.bandpass(N.white(d, rng), 4500, 9000, 1) * sib_env * 0.6
	return L.nz(y * amp + sib * amp.max())


@sound("shade_whisper", variants=2, peak=-10.0, fin=0.05, fout=0.2)
def shade_whisper(rng, v):
	d = 2.0 + 0.4 * v
	w = whisper(rng, d)
	w = F.lowpass(w, 7000, 2) * env_points([(0, 0), (0.3, 1), (d - 0.4, 0.9), (d, 0)], d, "cos")
	return L.small_room(rng, w, 0.25, 0.9)


@sound("shade_telegraph", peak=-6.0, fin=0.05)
def shade_telegraph(rng, v):
	d = 1.1
	intake = F.sweep_points(N.pink(d, rng), "bandpass", [(0, 600), (d, 2600)], 1.6)
	intake = L.nz(intake) * env_points([(0, 0), (d * 0.85, 1), (d, 0.2)], d, "cos")
	hum = FM.fm(osc.glide(110, 142, d, "exp"), d, 2.0, 0.6) * env_points([(0, 0), (d * 0.9, 1), (d, 0)], d, "cos")
	air = F.bandpass(N.pink(d, rng), 3000, 7000, 1) * env_points([(0, 0), (d, 1)], d)
	return F.lowpass(mix(intake * 0.8, L.nz(hum) * 0.35, L.nz(air) * 0.1), 7000, 2)


@sound("shade_drift", peak=-8.0, fin=0.1, fout=0.3)
def shade_drift(rng, v):
	d = 2.2
	air = L.whoosh(rng, d, [(0, 400), (1.0, 1200), (d, 500)], q=1.5, amp_points=[(0, 0), (0.9, 1), (d, 0)], color=1.0)
	f = osc.vibrato(osc.glide_points([(0, 520), (1.1, 560), (d, 470)], d), d, 2.7, 30.0)
	tone = np.sin(2 * np.pi * osc.phase(f, d)) + 0.3 * np.sin(2 * np.pi * osc.phase(f * 1.41, d))
	tone *= env_points([(0, 0), (1.0, 1), (d, 0)], d, "cos")
	return L.small_room(rng, mix(air * 0.8, L.nz(tone) * 0.18), 0.3, 1.2)


@sound("shade_shriek", peak=-5.0, fin=0.05, fout=0.3)
def shade_shriek(rng, v):
	d = 1.6
	amp = [(0, 0), (0.16, 1), (0.7, 0.7), (d, 0)]
	y = np.zeros(ns(d))
	for f0, g in ((700, 1.0), (741, 0.8), (1050, 0.3)):
		f = osc.vibrato(osc.glide_points([(0, f0), (0.3, f0 * 1.08), (d, f0 * 0.62)], d), d, 6.0, 25.0)
		y += g * np.sin(2 * np.pi * osc.phase(f, d))
	breath = F.bandpass(N.pink(d, rng), 900, 5000, 1)
	out = mix(L.nz(y) * 0.7, L.nz(breath) * 0.5) * env_points(amp, d, "cos")
	return L.small_room(rng, F.lowpass(out, 4500, 2), 0.3, 1.2)
