"""Horror-director cues: distant, reverberant, restrained. Stingers swell rather than jump
(never sudden-loud; the major stinger peaks at -4 dBFS after a ~0.9 s rise)."""
from __future__ import annotations

import numpy as np

from catalog import sound
from hhsynth.core import ns, env_points, env_perc, mix, place, smooth_random
from hhsynth import osc, noise as N, filters as F, physical as P, fm as FM, music as M, space as S
import sfxlib as L
from sounds_creatures import whisper, _mochi_syllable


def _far(x, meters):
	return S.distant(x, meters)


@sound("dir_distant_pickaxe", peak=-9.0, fout=0.5)
def dir_distant_pickaxe(rng, v):
	parts = []
	for t in (0.0, 0.95, 1.92, 3.15):
		ring = L.metal(rng, rng.uniform(1850, 2050), 0.5, 0.3, 0.0) * 0.4
		thock = L.stone(rng, rng.uniform(560, 660), 0.15, 0.05, 0.6, 0.4)
		parts.append((t, mix(thock, ring), rng.uniform(0.75, 1.0)))
	dry = _far(L.stagger(parts, total=3.5), 30)
	return L.cave_verb(rng, np.pad(dry, (0, ns(3.0))), wet=0.75, dry=0.35, t60=3.8)


@sound("dir_creak", peak=-9.0, fout=0.4)
def dir_creak(rng, v):
	d = 2.0
	cr = L.creak(rng, d, [(0, 24), (0.8, 60), (1.4, 42), (d, 70)], [(0, 0.2), (0.6, 1), (1.6, 0.7), (d, 0)], 230, 0.09)
	return L.cave_verb(rng, np.pad(_far(L.nz(cr), 10), (0, ns(2.0))), wet=0.45, dry=0.7, t60=2.8)


@sound("dir_footsteps", peak=-10.0, fout=0.5)
def dir_footsteps(rng, v):
	parts = []
	t = 0.0
	for i in range(6):
		f = rng.uniform(650, 900)
		heel = mix(L.stone(rng, f, 0.12, 0.03, 0.4, 0.3), L.nz(F.lowpass(L.burst(rng, 0.02, 60, 800), 500, 2)) * 0.5)
		toe = L.stone(rng, f * 1.1, 0.1, 0.025, 0.3, 0.2) * 0.5
		parts.append((t, heel, 0.55 + 0.08 * i))
		parts.append((t + 0.07, toe, 0.5 + 0.06 * i))
		t += rng.uniform(0.5, 0.58)
	dry = _far(L.stagger(parts), 14)
	return L.cave_verb(rng, np.pad(dry, (0, ns(2.5))), wet=0.55, dry=0.6, t60=2.4)


@sound("dir_pebbles", peak=-9.0, fout=0.4)
def dir_pebbles(rng, v):
	parts = []
	for p in range(5):
		t = rng.uniform(0.0, 0.8)
		gap = rng.uniform(0.12, 0.2)
		g = rng.uniform(0.5, 1.0)
		for b in range(rng.integers(3, 6)):
			parts.append((t, L.stone(rng, rng.uniform(2000, 4500), 0.06, 0.02, 0.6, 0.4), g))
			t += gap
			gap *= 0.62
			g *= 0.65
	dust = L.crunch(rng, 1.6, [(0, 0), (0.3, 300), (1.6, 0)], (1500, 6000), (0.001, 0.004))
	dry = _far(mix(L.stagger(parts, total=1.8), L.nz(dust) * 0.15), 8)
	return L.cave_verb(rng, np.pad(dry, (0, ns(2.0))), wet=0.45, dry=0.7, t60=2.2)


@sound("dir_whisper", peak=-13.0, fin=0.2, fout=0.6)
def dir_whisper(rng, v):
	d = 3.2
	w = whisper(rng, d, syll_rate=4.0) * env_points([(0, 0), (0.6, 1), (d - 0.6, 0.8), (d, 0)], d, "cos")
	w = F.lowpass(w, 4200, 2)
	return L.cave_verb(rng, np.pad(w, (0, ns(3.0))), wet=0.7, dry=0.4, t60=3.5)


@sound("dir_wrong_squeak", peak=-11.0, fout=0.8)
def dir_wrong_squeak(rng, v):
	# the chirp Mochi makes (mochi_chirp_1 shape), a little too slow and too low, from far below
	sq = _mochi_syllable(rng, 2100 * 0.84, "up", 0.14)
	sq = _far(np.pad(sq, (0, ns(0.05))), 25)
	return L.cave_verb(rng, np.pad(sq, (0, ns(4.5))), wet=0.9, dry=0.25, t60=5.0,
		echoes=((0.21, 0.55), (0.39, 0.4), (0.62, 0.28), (0.9, 0.18), (1.25, 0.1)))


@sound("dir_flicker", peak=-10.0)
def dir_flicker(rng, v):
	d = 1.4
	gutter = F.lowpass(N.pink(d, rng), 900, 2) * np.clip(0.6 + 0.8 * smooth_random(d, rng, 14.0, -1, 1), 0, 1)
	gutter *= env_points([(0, 0), (0.05, 1), (1.1, 0.8), (d, 0)], d, "cos")
	pops = L.crunch(rng, d, [(0, 30), (0.5, 60), (d, 10)], (1000, 6000), (0.0005, 0.002))
	tick = L.metal(rng, 3100, 0.1, 0.03, 0.3)
	return L.stagger([(0.0, L.nz(gutter), 0.8), (0.0, L.nz(pops), 0.45), (0.9, tick, 0.12)])


def _scratch(rng, d, lo, hi, rough, body):
	x = F.bandpass(N.white(d, rng), lo, hi, 1)
	rate = rng.uniform(35, 60)
	saw_am = 0.5 + 0.5 * osc.saw(osc.vibrato(rate, d, 3.0, 300.0), d)
	am = (1.0 - rough) + rough * saw_am ** 3
	y = x * am
	y = mix(y, L.nz(P.resonate(y, body, [0.02, 0.015], [0.3, 0.2])) * 0.4)
	return L.nz(y) * env_points([(0, 0), (0.05, 1), (d * 0.7, 0.8), (d, 0)], d, "cos")


@sound("dir_scratch", peak=-9.0, fout=0.4)
def dir_scratch(rng, v):
	parts = [(t, _scratch(rng, rng.uniform(0.35, 0.55), 1200, 5000, 0.8, [900, 1700]), g)
		for t, g in ((0.0, 0.8), (0.7, 1.0), (1.55, 0.7))]
	dry = F.lowpass(L.stagger(parts), 5000, 2)
	return L.cave_verb(rng, np.pad(dry, (0, ns(1.5))), wet=0.35, dry=0.8, t60=1.8)


@sound("dir_scratch_soft", peak=-12.0, fout=0.4)
def dir_scratch_soft(rng, v):
	# roots rubbing against stone: lower, duller, fewer transients
	parts = [(t, _scratch(rng, rng.uniform(0.45, 0.65), 400, 1800, 0.35, [300, 620]), g)
		for t, g in ((0.0, 0.8), (0.8, 1.0), (1.7, 0.6))]
	dry = F.lowpass(L.stagger(parts), 2000, 2)
	return L.cave_verb(rng, np.pad(dry, (0, ns(1.5))), wet=0.35, dry=0.8, t60=1.8)


@sound("dir_web_rustle", peak=-11.0, fin=0.05, fout=0.4)
def dir_web_rustle(rng, v):
	d = 2.0
	silk = F.bandpass(N.pink(d, rng), 3000, 9000, 1) * (0.5 + 0.5 * smooth_random(d, rng, 5.0))
	silk *= env_points([(0, 0), (0.5, 1), (1.4, 0.8), (d, 0)], d, "cos")
	tension = L.creak(rng, 1.0, [(0, 150), (1.0, 260)], [(0, 0), (0.5, 1), (1.0, 0)], 1100, 0.02)
	stretch = L.squeak([(0, 1250), (0.8, 1330)], 0.8, [(0, 0), (0.4, 1), (0.8, 0)])
	y = L.stagger([(0.0, L.nz(silk), 0.7), (0.5, L.nz(tension), 0.3), (0.6, stretch, 0.03)])
	return L.cave_verb(rng, np.pad(y, (0, ns(1.5))), wet=0.3, dry=0.8, t60=1.6)


@sound("dir_root_creak", peak=-10.0, fout=0.4)
def dir_root_creak(rng, v):
	d = 2.2
	cr = L.creak(rng, d, [(0, 18), (1.0, 40), (d, 27)], [(0, 0.2), (0.7, 1), (d, 0)], 150, 0.1)
	soil = L.crunch(rng, d, [(0, 0), (0.8, 120), (d, 20)], (200, 2000), (0.002, 0.008))
	y = mix(L.nz(cr), L.nz(soil) * 0.2)
	return L.cave_verb(rng, np.pad(F.lowpass(y, 3500, 2), (0, ns(1.8))), wet=0.35, dry=0.8, t60=2.0)


@sound("stinger_soft", peak=-10.0, fin=0.2, fout=1.0, trim=False)
def stinger_soft(rng, v):
	d = 4.8
	env = env_points([(0, 0), (1.6, 1), (2.4, 0.8), (d, 0)], d, "cos")
	pad = sum(M.pad(M.hz(nm), 2.4, 0.8, rng, attack=1.2, release=2.2, cutoff=700).mean(axis=1) for nm in ("D2", "A2", "Eb3"))
	sub = np.sin(2 * np.pi * 36.7 * np.arange(ns(d)) / 44100)
	air = F.bandpass(N.pink(d, rng), 2000, 5000, 1)
	y = mix(L.nz(pad) * 0.8, sub * 0.25, L.nz(air) * 0.05)
	return y[:len(env)] * env


@sound("stinger_major", peak=-4.0, fin=0.3, fout=1.2, trim=False)
def stinger_major(rng, v):
	d = 5.2
	rise = 0.9
	env = env_points([(0, 0), (rise, 1.0), (1.6, 0.75), (d, 0)], d, "cos")
	bend = osc.glide_points([(0, 1.0), (rise, 1.03), (d, 1.0)], d)
	cluster = np.zeros(ns(d))
	for nm, g in (("D3", 1.0), ("Eb3", 0.8), ("A3", 0.7), ("Bb3", 0.5), ("D2", 0.9)):
		f = M.hz(nm) * bend
		cluster += g * (0.6 * osc.saw(osc.vibrato(f, d, rng.uniform(4, 6), 12.0), d) + 0.4 * osc.triangle(f, d))
	cluster = F.sweep_points(cluster, "lowpass", [(0, 350), (rise, 2400), (d, 700)], 0.8)
	noise = F.sweep_points(N.pink(d, rng), "bandpass", [(0, 500), (rise, 3000), (d, 900)], 1.0)
	boom = L.thud(rng, 42, 2.5, 1.2, 0.3)
	y = mix(L.nz(cluster) * env * 0.8, L.nz(noise) * env * 0.18)
	place(y, boom * 0.45, rise - 0.05)
	return L.small_room(rng, y, 0.3, 1.8)
