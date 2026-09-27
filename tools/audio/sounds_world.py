"""World sounds: the Ward Stone, doors, gates, the lift, checkpoints, drips and mine carts."""
from __future__ import annotations

import numpy as np

from catalog import sound
from hhsynth.core import ns, env_points, env_perc, mix, place, smooth_random
from hhsynth import osc, noise as N, filters as F, physical as P, fm as FM, music as M, space as S
import sfxlib as L


@sound("ward_hum", peak=-11.0, fin=0.3, fout=0.8, trim=False)
def ward_hum(rng, v):
	d = 5.0
	t = np.arange(ns(d)) / 44100
	env = env_points([(0, 0), (1.3, 1), (3.4, 0.9), (d, 0)], d, "cos")
	tones = (np.sin(2 * np.pi * M.hz("F2") * t) + 0.6 * np.sin(2 * np.pi * (M.hz("C3") + 0.35) * t)
		+ 0.45 * np.sin(2 * np.pi * (M.hz("F3") - 0.25) * t) + 0.12 * np.sin(2 * np.pi * M.hz("A4") * t + 1.0))
	shimmer = F.bandpass(N.pink(d, rng), 2500, 6500, 1) * (0.5 + 0.5 * smooth_random(d, rng, 1.5))
	glints = L.glass_notes([(1.0, "C6", 0.3), (2.1, "F6", 0.25), (3.0, "A5", 0.25)], t60=1.6, sparkle=0.4, total=d)
	return mix(L.nz(tones) * env * 0.8, L.nz(shimmer) * env * 0.05, L.nz(glints) * 0.18)


@sound("ward_restore", peak=-4.0, fin=0.05, fout=1.0, trim=False)
def ward_restore(rng, v):
	d = 9.5
	out = np.zeros(ns(d))
	# 1) low swell from nothing
	swell = L.pad_chord(rng, ["F2", "C3", "F3"], 3.2, attack=2.2, release=2.0, cutoff=700)
	place(out, L.nz(swell) * 0.45, 0.0)
	rise = L.whoosh(rng, 2.4, [(0, 300), (2.4, 4000)], q=0.9, amp_points=[(0, 0), (2.2, 1), (2.4, 0)], color=1.0)
	place(out, rise * 0.12, 0.2)
	# 2) cascading music box + glass arpeggios
	pent = ["F5", "G5", "A5", "C6", "D6", "F6", "G6", "A6", "C7"]
	seq = [(1.9 + i * 0.09, pent[i % len(pent)], 0.5 + 0.03 * i) for i in range(12)]
	place(out, L.nz(L.notes(M.music_box, seq, rng)) * 0.4, 0.0)
	# 3) the bloom: warm full chord with strings, then shimmering sparkles
	bloom = L.pad_chord(rng, ["F3", "C4", "A4", "E5", "G5"], 4.0, attack=0.6, release=2.6, cutoff=2200)
	place(out, L.nz(bloom) * 0.55, 3.0)
	strings = sum(M.strings(M.hz(nm), 3.6, 0.7, rng).mean(axis=1) for nm in ["F4", "A4", "C5", "F5"])
	place(out, L.nz(strings) * 0.35, 3.0)
	low = L.thud(rng, 44, 2.0, 1.4, 0.2)
	place(out, low * 0.5, 3.0)
	spk = [(3.2 + rng.uniform(0, 3.5), pent[int(rng.integers(3, 9))], rng.uniform(0.2, 0.45)) for _ in range(16)]
	place(out, L.nz(L.glass_notes(spk, t60=1.6, sparkle=0.8)) * 0.3, 0.0)
	return F.lowpass(out, 12000, 1)


@sound("door_creak", peak=-7.0, fout=0.1)
def door_creak(rng, v):
	d = 1.4
	cr = L.creak(rng, d, [(0, 60), (0.4, 150), (0.9, 105), (d, 180)], [(0, 0.2), (0.3, 1.0), (1.1, 0.8), (d, 0.1)], 340, 0.07)
	return L.small_room(rng, F.lowpass(L.nz(cr), 5000, 2), 0.2, 0.6)


@sound("gate_unlock", peak=-5.0, fout=0.2)
def gate_unlock(rng, v):
	key1 = L.metal(rng, 2500, 0.3, 0.08, 0.5)
	key2 = L.metal(rng, 2800, 0.3, 0.07, 0.5)
	bolt = L.knock(rng, [300, 720, 1450, 2600], [0.3, 0.2, 0.12, 0.06], [1.0, 0.7, 0.4, 0.2], 0.8, 0.003, 5000, 0.3)
	groan = L.creak(rng, 1.4, [(0, 32), (0.8, 58), (1.4, 42)], [(0, 0.3), (0.5, 1), (1.4, 0.2)], 180, 0.1)
	ring = L.metal(rng, 900, 1.5, 0.9, 0.0)
	out = L.stagger([(0.0, key1, 0.4), (0.25, key2, 0.45), (0.5, bolt, 1.0), (0.52, ring, 0.15), (0.85, L.nz(groan), 0.6)])
	return L.small_room(rng, out, 0.3, 1.0)


@sound("lift_move", peak=-6.0, fin=0.3, fout=0.6, trim=False)
def lift_move(rng, v):
	d = 4.2
	env = env_points([(0, 0), (0.6, 1), (d - 0.8, 1), (d, 0)], d, "cos")
	rumble = F.lowpass(N.brown(d, rng), 160, 2) * (0.8 + 0.2 * smooth_random(d, rng, 3.0))
	chain = L.stagger([(t, L.metal(rng, rng.uniform(1800, 3200), 0.12, 0.05, 0.3), rng.uniform(0.2, 0.5))
		for t in np.sort(rng.uniform(0, d, int(d * 16)))], total=d)
	ratchet = L.stagger([(t, L.wood(rng, 900, 0.05, 0.02, 0.5, 0.3), 0.35) for t in np.arange(0.1, d, 1 / 5.5)], total=d)
	creaks = mix(*[np.pad(L.nz(L.creak(rng, 0.7, [(0, 40), (0.7, 80)], [(0, 0.3), (0.35, 1), (0.7, 0)], 260, 0.06)),
		(ns(t0), 0)) for t0 in (0.7, 2.4)])
	y = mix(L.nz(rumble) * 0.7, L.nz(chain) * 0.3, L.nz(ratchet) * 0.18, creaks * 0.3)
	return y[:len(env)] * env


@sound("checkpoint_light", peak=-7.0, fout=0.4)
def checkpoint_light(rng, v):
	whoosh = L.whoosh(rng, 0.45, [(0, 400), (0.45, 1800)], q=1.0, amp_points=[(0, 0), (0.35, 1), (0.45, 0.2)], color=1.0)
	flame = F.lowpass(N.pink(0.8, rng), 1200, 2) * env_points([(0, 0), (0.1, 1), (0.8, 0)], 0.8, "cos")
	chime = L.notes(M.music_box, [(0.0, "C5", 0.6), (0.12, "G5", 0.6), (0.26, "E6", 0.65)], rng)
	pad = L.pad_chord(rng, ["C4", "E4", "G4"], 1.4, attack=0.4, release=1.2, cutoff=1200)
	return L.stagger([(0.0, whoosh, 0.35), (0.35, L.nz(flame), 0.3), (0.38, L.nz(chime), 0.8), (0.38, L.nz(pad), 0.28)])


@sound("water_drip", variants=3, peak=-9.0, fout=0.2)
def water_drip(rng, v):
	f0 = [1350, 1650, 1150][v]
	plip = P.bubble(f0, 0.12, rise=1.7, t60=0.045)
	tiny = F.bandpass(N.white(0.02, rng), 2000, 6000, 1) * env_perc(0.02, 0.0005, 0.01)
	y = mix(plip, L.nz(tiny) * 0.1)
	return L.cave_verb(rng, np.pad(y, (0, ns(1.2))), wet=0.35, dry=0.8, t60=1.4, echoes=((0.09, 0.3), (0.17, 0.18)))


@sound("mine_cart", peak=-6.0, fin=0.2, fout=0.5, trim=False)
def mine_cart(rng, v):
	d = 3.2
	env = env_points([(0, 0), (0.5, 1), (d - 0.6, 1), (d, 0)], d, "cos")
	t = np.arange(ns(d)) / 44100
	roll = F.lowpass(N.brown(d, rng), 260, 2) * (0.75 + 0.25 * np.sin(2 * np.pi * 3.1 * t))
	joints = []
	for tj in np.arange(0.15, d, 0.52):
		joints.append((tj, L.metal(rng, rng.uniform(1100, 1400), 0.2, 0.08, 0.4), 0.45))
		joints.append((tj + 0.09, L.metal(rng, rng.uniform(1100, 1400), 0.2, 0.08, 0.4), 0.35))
	clacks = L.stagger(joints, total=d)
	squeal = np.sin(2 * np.pi * osc.phase(osc.vibrato(2150, d, 0.7, 25.0), d)) * (0.5 + 0.5 * smooth_random(d, rng, 1.0))
	y = mix(L.nz(roll) * 0.8, L.nz(clacks) * 0.4, squeal * 0.025)
	return L.small_room(rng, y[:len(env)] * env, 0.25, 0.8)
