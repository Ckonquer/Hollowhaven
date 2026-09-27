"""Player, gathering, building/farming and combat sounds. Soft and organic: everything is
low-passed a little, attacks are fast but never harsh, and low thumps stay round."""
from __future__ import annotations

import numpy as np

from catalog import sound
from hhsynth.core import ns, env_points, env_perc, mix, place, smooth_random
from hhsynth import osc, noise as N, filters as F, physical as P, fm as FM, music as M
import sfxlib as L


# ------------------------------------------------------------------------------------------
# Footsteps (4 variants each; heel + softer toe)
# ------------------------------------------------------------------------------------------

@sound("step_grass", variants=4, peak=-8.0, fout=0.02)
def step_grass(rng, v):
	def crunch(amount):
		c = L.crunch(rng, 0.11, [(0, 1400 * amount), (0.02, 900 * amount), (0.11, 0)], (700, 6500), (0.001, 0.004))
		thump = L.nz(F.lowpass(L.burst(rng, 0.03, 40, 400), 300, 2)) * 0.35
		return mix(L.nz(c), thump)
	toe_t = 0.07 + 0.02 * rng.uniform()
	y = L.stagger([(0.0, crunch(1.0), 1.0), (toe_t, crunch(0.7), 0.55 + 0.1 * v / 3)])
	return F.lowpass(y, 6000 - 300 * v, 2)


# Surface balance (review): peaks differ on purpose so the four surfaces sound about equally loud
# (short-term K/A-weighted loudness within ~1-4 dB of grass, also through a 250 Hz small-speaker
# high-pass). Stone taps are spikier than grass crunch, so they need a higher peak; water is fuller.
@sound("step_stone", variants=4, peak=-5.5, fout=0.02)
def step_stone(rng, v):
	def tap(g):
		f = rng.uniform(700, 1050)
		t = L.stone(rng, f, 0.12, t60=0.03, bright=0.5, click=0.25)
		grit = L.crunch(rng, 0.04, 1500, (2000, 7500), (0.0005, 0.002)) * 0.25
		sole = F.lowpass(L.burst(rng, 0.02, 60, 800), 500, 2)
		return mix(t * 0.7, grit, L.nz(sole) * 0.4) * g
	y = L.stagger([(0.0, tap(1.0), 1.0), (0.06 + 0.02 * rng.uniform(), tap(0.6), 0.6)])
	return F.lowpass(y, 5500, 2)


@sound("step_wood", variants=4, peak=-5.0, fout=0.02)
def step_wood(rng, v):
	# plank knock: a board mode around 200-250 Hz plus a hollow mid 'tok'. (The first version sat at
	# 150-190 Hz with little else, ~10 dB quieter than grass and inaudible on laptop speakers.)
	def board(g):
		f = rng.uniform(200, 250)
		k = L.wood(rng, f, 0.3, t60=0.08, bright=0.6, click=0.22)
		tok = L.wood(rng, f * rng.uniform(2.6, 3.0), 0.12, t60=0.035, bright=0.5, click=0.1)
		return mix(L.nz(k), 0.6 * L.nz(tok)) * g
	y = L.stagger([(0.0, board(1.0), 1.0), (0.065 + 0.02 * rng.uniform(), board(0.55), 0.5)])
	return F.lowpass(y, 5000, 2)


@sound("step_water", variants=4, peak=-10.0)
def step_water(rng, v):
	dur = 0.38
	splash = F.bandpass(N.white(dur, rng), 500, 5000, 1) * env_points([(0, 0), (0.01, 1), (0.06, 0.4), (dur, 0)], dur)
	bub = P.bubbles(dur, rng, [(0, 120), (0.15, 40), (dur, 0)], (450, 1800), (0.015, 0.045), (1.3, 2.2))
	slosh = F.lowpass(N.white(dur, rng), 700, 2) * env_points([(0, 0), (0.05, 1), (0.25, 0.2), (dur, 0)], dur, "cos")
	return F.lowpass(mix(L.nz(splash) * 0.6, L.nz(bub) * 0.5, L.nz(slosh) * 0.45), 6000, 2)


# ------------------------------------------------------------------------------------------
# Movement
# ------------------------------------------------------------------------------------------

@sound("jump", peak=-12.0)
def jump(rng, v):
	w = L.whoosh(rng, 0.22, [(0, 320), (0.22, 1300)], q=1.1, amp_points=[(0, 0), (0.06, 1), (0.22, 0)])
	scuff = L.crunch(rng, 0.05, 900, (600, 5000), (0.001, 0.004))
	return mix(w, L.nz(scuff) * 0.45)


@sound("land", peak=-8.0)
def land(rng, v):
	th = L.thud(rng, 58, 0.35, 0.16, 0.4)
	dirt = L.crunch(rng, 0.14, [(0, 1600), (0.14, 0)], (300, 4500), (0.001, 0.005))
	return mix(th, L.nz(dirt) * 0.45)


@sound("dodge", peak=-9.0)
def dodge(rng, v):
	w = L.whoosh(rng, 0.32, [(0, 1800), (0.32, 450)], q=1.0, amp_points=[(0, 0), (0.07, 1), (0.32, 0)])
	cloth = L.crunch(rng, 0.25, 500, (500, 3500), (0.004, 0.012)) * np.sin(np.linspace(0, np.pi, ns(0.25)))
	roll = L.thud(rng, 80, 0.25, 0.1, 0.5)
	return L.stagger([(0.0, w, 1.0), (0.02, L.nz(cloth), 0.35), (0.22, roll, 0.45)])


@sound("swing", variants=3, peak=-9.0)
def swing(rng, v):
	d = 0.24 + 0.03 * v
	peak_f = 1400 + 300 * v
	return L.whoosh(rng, d, [(0, 380), (d * 0.45, peak_f), (d, 520)], q=1.8,
		amp_points=[(0, 0), (d * 0.45, 1), (d, 0)], color=0.7)


@sound("hurt", variants=2, peak=-7.0)
def hurt(rng, v):
	# a soft bump + a gentle falling 'bwomp' (never a scream)
	bump = L.thud(rng, 120, 0.2, 0.1, 0.6)
	f0 = 430 if v == 0 else 390
	tone = FM.fm(osc.glide(f0, f0 * 0.62, 0.22, "exp", total=0.3), 0.3, 1.0, 0.9 * env_perc(0.3, 0.005, 0.2))
	tone *= env_points([(0, 0), (0.015, 1), (0.12, 0.6), (0.3, 0)], 0.3, "cos")
	return F.lowpass(mix(bump, L.nz(tone) * 0.55), 3000, 2)


@sound("eat", peak=-9.0)
def eat(rng, v):
	def bite(g):
		c = L.crunch(rng, 0.09, [(0, 2500), (0.09, 200)], (900, 6000), (0.0008, 0.003))
		m = F.lowpass(L.burst(rng, 0.05, 80, 900), 600, 2)
		return mix(L.nz(c), L.nz(m) * 0.5) * g
	return F.lowpass(L.stagger([(0.0, bite(1.0), 1.0), (0.19, bite(0.8), 1.0), (0.37, bite(0.65), 1.0)]), 6500, 2)


@sound("lantern_on", peak=-9.0)
def lantern_on(rng, v):
	click = L.metal(rng, 2600, 0.2, 0.08, 0.4)
	strike = L.crunch(rng, 0.06, 2500, (2500, 8000), (0.0005, 0.002))
	flame = F.sweep_points(N.pink(0.6, rng), "lowpass", [(0, 250), (0.2, 1600), (0.6, 700)], 0.9)
	flame = L.nz(flame) * env_points([(0, 0), (0.12, 1), (0.6, 0)], 0.6, "cos")
	glow = (np.sin(2 * np.pi * M.hz("A3") * np.arange(ns(0.9)) / 44100) +
		0.5 * np.sin(2 * np.pi * M.hz("E4") * np.arange(ns(0.9)) / 44100)) * env_points([(0, 0), (0.3, 1), (0.9, 0)], 0.9, "cos")
	return L.stagger([(0.0, click, 0.45), (0.02, L.nz(strike), 0.35), (0.07, flame, 0.8), (0.1, L.nz(glow), 0.12)])


@sound("lantern_off", peak=-11.0)
def lantern_off(rng, v):
	puff = F.lowpass(N.white(0.16, rng), 900, 2) * env_points([(0, 0), (0.01, 1), (0.16, 0)], 0.16)
	lid = L.metal(rng, 2200, 0.25, 0.1, 0.3)
	return L.stagger([(0.0, L.nz(puff), 0.8), (0.07, lid, 0.4)])


@sound("death", peak=-8.0, fout=0.3)
def death(rng, v):
	thump = L.thud(rng, 70, 0.5, 0.25, 0.4)
	box = L.notes(M.music_box, [(0.25, "A5", 0.6), (0.62, "F5", 0.55), (1.0, "D5", 0.5), (1.45, "A4", 0.5)], rng)
	pad = L.pad_chord(rng, ["D3", "A3", "F4"], 2.2, attack=0.8, release=1.2, cutoff=900)
	return mix(thump * 0.5, L.nz(box) * 0.8, L.nz(pad) * 0.3)


# ------------------------------------------------------------------------------------------
# Gathering
# ------------------------------------------------------------------------------------------

@sound("chop", variants=3, peak=-5.0)
def chop(rng, v):
	k = 1.0 + 0.08 * (v - 1)
	trunk = L.knock(rng, [140 * k, 318 * k, 640 * k, 1260 * k], [0.16, 0.1, 0.06, 0.03], [1.0, 0.7, 0.45, 0.2], 0.45, 0.004, 4000, 0.2)
	bite = L.burst(rng, 0.004, 2000, 6500)
	bark = L.crunch(rng, 0.18, [(0, 1800), (0.05, 700), (0.18, 0)], (1500, 7000), (0.0006, 0.003))
	low = L.thud(rng, 90, 0.2, 0.08, 0.2)
	y = mix(trunk, L.nz(bite) * 0.4, L.nz(bark) * 0.35, low * 0.35)
	return F.lowpass(y, 7500, 2)


@sound("tree_fall", peak=-4.0, fout=0.4)
def tree_fall(rng, v):
	total = 4.2
	out = np.zeros(ns(total))
	cr = L.creak(rng, 1.45, [(0, 28), (0.8, 55), (1.45, 95)], [(0, 0.2), (1.0, 0.8), (1.45, 1.0)], 300, 0.06)
	place(out, L.nz(cr) * 0.6, 0.0)
	crack = L.knock(rng, [420, 980, 2100], [0.08, 0.05, 0.03], [1, 0.6, 0.3], 0.3, 0.003, 6000, 0.5)
	place(out, crack * 0.7, 1.4)
	wh = L.whoosh(rng, 1.3, [(0, 500), (0.9, 1600), (1.3, 400)], q=0.8, amp_points=[(0, 0), (0.9, 1), (1.3, 0.2)], color=1.0)
	place(out, wh * 0.55, 1.45)
	leaves = L.crunch(rng, 2.2, [(0, 0), (0.5, 500), (1.2, 1300), (1.6, 300), (2.2, 0)], (1800, 7500), (0.002, 0.01))
	place(out, L.nz(leaves) * 0.35, 1.45)
	boom = L.thud(rng, 48, 1.2, 0.6, 0.6)
	place(out, boom * 0.95, 2.72)
	debris = L.crunch(rng, 0.8, [(0, 900), (0.8, 0)], (300, 3000), (0.002, 0.01))
	place(out, L.nz(debris) * 0.3, 2.74)
	return F.lowpass(out, 8000, 2)


@sound("mine_hit", variants=3, peak=-5.0)
def mine_hit(rng, v):
	k = [1.0, 1.07, 0.94][v]
	ring = L.metal(rng, 2150 * k, 0.6, 0.32, 0.0) * 0.28
	thock = L.stone(rng, 620 * k, 0.2, t60=0.05, bright=0.7, click=0.4)
	grit = L.crunch(rng, 0.07, [(0, 3000), (0.07, 0)], (2000, 7500), (0.0004, 0.002))
	low = L.thud(rng, 110, 0.15, 0.06, 0.3)
	return F.lowpass(mix(thock, ring, L.nz(grit) * 0.3, low * 0.3), 9000, 2)


@sound("rock_break", peak=-5.0)
def rock_break(rng, v):
	parts = [(0.0, L.stone(rng, 520, 0.3, 0.06, 0.8, 0.6), 1.0), (0.0, L.thud(rng, 70, 0.4, 0.2, 0.5), 0.6)]
	t = 0.04
	for i in range(11):
		parts.append((t, L.stone(rng, rng.uniform(900, 2600), 0.12, 0.025, 0.6, 0.3), 0.55 * (0.85 ** i)))
		t += rng.uniform(0.02, 0.07)
	grit = L.crunch(rng, 0.6, [(0, 2500), (0.6, 0)], (800, 6000), (0.001, 0.004))
	parts.append((0.01, L.nz(grit), 0.3))
	return F.lowpass(L.stagger(parts), 8000, 2)


@sound("pickup", variants=2, peak=-8.0)
def pickup(rng, v):
	p = L.pop(360 + 40 * v, 1100 + 150 * v, 0.1, 0.06)
	pl = P.ks_pluck(M.hz("C6" if v == 0 else "E6"), 0.5, rng, t60=0.45, bright=0.6, pos=0.2)
	return L.stagger([(0.0, p, 0.7), (0.03, L.nz(pl), 0.6)])


@sound("grass_pull", peak=-9.0)
def grass_pull(rng, v):
	tear_env = [(0, 0), (0.05, 2600), (0.12, 1200), (0.16, 2800), (0.24, 0)]
	tear = L.crunch(rng, 0.26, tear_env, (1500, 8000), (0.0006, 0.003))
	soil = L.crunch(rng, 0.2, [(0, 400), (0.2, 0)], (250, 1800), (0.002, 0.008))
	p = L.pop(300, 700, 0.08, 0.05)
	return L.stagger([(0.0, L.nz(tear), 0.7), (0.05, L.nz(soil), 0.35), (0.22, p, 0.35)])


@sound("berry_pick", peak=-9.0)
def berry_pick(rng, v):
	rustle = L.crunch(rng, 0.12, [(0, 900), (0.12, 0)], (1800, 7000), (0.002, 0.008))
	p = L.pop(480, 950, 0.09, 0.05)
	squish = F.bandpass(N.white(0.04, rng), 600, 1600, 1) * env_perc(0.04, 0.002, 0.03)
	return L.stagger([(0.0, L.nz(rustle), 0.4), (0.06, p, 0.8), (0.06, L.nz(squish), 0.25)])


@sound("splash", peak=-6.0, fout=0.1)
def splash(rng, v):
	d = 0.9
	body = F.bandpass(N.white(d, rng), 300, 6000, 1) * env_points([(0, 0), (0.015, 1), (0.12, 0.45), (0.6, 0.1), (d, 0)], d)
	bub = P.bubbles(d, rng, [(0, 260), (0.3, 90), (d, 0)], (350, 2200), (0.02, 0.06), (1.3, 2.4))
	low = F.lowpass(N.white(d, rng), 500, 2) * env_points([(0, 0), (0.03, 1), (0.4, 0.2), (d, 0)], d, "cos")
	return F.lowpass(mix(L.nz(body) * 0.6, L.nz(bub) * 0.5, L.nz(low) * 0.5), 7000, 2)


# ------------------------------------------------------------------------------------------
# Building & farming
# ------------------------------------------------------------------------------------------

@sound("build_place", peak=-6.0)
def build_place(rng, v):
	main = L.knock(rng, [175, 405, 860, 1480], [0.14, 0.09, 0.05, 0.03], [1.0, 0.6, 0.4, 0.2], 0.5, 0.004, 3500, 0.15)
	settle = L.wood(rng, 260, 0.25, 0.06, 0.4)
	rattle = L.stagger([(i * 0.018, L.wood(rng, rng.uniform(700, 1200), 0.05, 0.02, 0.4), 0.2) for i in range(3)])
	low = L.thud(rng, 75, 0.3, 0.12, 0.3)
	return L.stagger([(0.0, main, 1.0), (0.0, low, 0.5), (0.075, settle, 0.35), (0.11, rattle, 0.6)])


@sound("build_remove", peak=-7.0)
def build_remove(rng, v):
	cr = L.creak(rng, 0.16, [(0, 110), (0.16, 220)], [(0, 0.5), (0.16, 1.0)], 600, 0.03)
	pop_ = L.wood(rng, 520, 0.2, 0.05, 0.6, 0.3)
	parts = [(0.0, L.nz(cr), 0.4), (0.15, pop_, 0.8)]
	for i, f in enumerate([380, 300, 240]):
		parts.append((0.24 + i * 0.07, L.wood(rng, f, 0.25, 0.07, 0.4), 0.55 - 0.1 * i))
	parts.append((0.14, L.whoosh(rng, 0.25, [(0, 1600), (0.25, 600)], 1.2), 0.2))
	return L.stagger(parts)


@sound("build_invalid", peak=-9.0)
def build_invalid(rng, v):
	# two soft falling wood bonks (D4 -> Bb3). Review fix: the first version (240/196 Hz, 1.8 kHz
	# low-pass, -12 dBFS) measured ~7 dB (A-weighted) under ui_error and nearly vanished on small
	# speakers, although it is the only feedback for a refused placement.
	a = L.wood(rng, 294, 0.25, 0.09, 0.45, 0.08)
	b = L.wood(rng, 233, 0.3, 0.1, 0.45, 0.08)
	return F.lowpass(L.stagger([(0.0, a, 1.0), (0.13, b, 0.9)]), 3000, 2)


@sound("dig", peak=-7.0)
def dig(rng, v):
	scoop = L.crunch(rng, 0.22, [(0, 0), (0.02, 3000), (0.22, 300)], (200, 3200), (0.001, 0.006))
	th = L.thud(rng, 85, 0.25, 0.1, 0.8)
	scatter = L.crunch(rng, 0.3, [(0, 600), (0.3, 0)], (400, 3000), (0.002, 0.01))
	return F.lowpass(L.stagger([(0.0, L.nz(scoop), 0.8), (0.0, th, 0.5), (0.2, L.nz(scatter), 0.3)]), 5000, 2)


@sound("harvest_crop", peak=-7.0)
def harvest_crop(rng, v):
	soil = L.crunch(rng, 0.16, [(0, 1800), (0.16, 0)], (250, 2600), (0.001, 0.006))
	leaves = L.crunch(rng, 0.2, [(0, 700), (0.2, 0)], (2000, 7000), (0.002, 0.008))
	p = L.pop(300, 720, 0.12, 0.07)
	pl = P.ks_pluck(M.hz("G5"), 0.5, rng, t60=0.5, bright=0.5)
	return L.stagger([(0.0, L.nz(soil), 0.6), (0.02, L.nz(leaves), 0.3), (0.12, p, 0.7), (0.16, L.nz(pl), 0.4)])


@sound("chest_open", peak=-7.0)
def chest_open(rng, v):
	latch = L.metal(rng, 3000, 0.15, 0.05, 0.4)
	cr = L.creak(rng, 0.4, [(0, 90), (0.4, 170)], [(0, 0.4), (0.2, 1.0), (0.4, 0.3)], 520, 0.04)
	lid = L.wood(rng, 230, 0.3, 0.08, 0.3)
	sparkle = L.glass_notes([(0.0, "G6", 0.5), (0.06, "D7", 0.3)], t60=0.8, sparkle=0.6)
	return L.stagger([(0.0, latch, 0.5), (0.05, L.nz(cr), 0.45), (0.44, lid, 0.5), (0.36, L.nz(sparkle), 0.15)])


@sound("chest_close", peak=-7.0)
def chest_close(rng, v):
	lid = L.knock(rng, [160, 360, 780], [0.12, 0.08, 0.04], [1.0, 0.5, 0.25], 0.4, 0.004, 3000, 0.1)
	latch = L.metal(rng, 2800, 0.15, 0.05, 0.4)
	return L.stagger([(0.0, lid, 1.0), (0.05, latch, 0.4), (0.0, L.thud(rng, 90, 0.2, 0.08, 0.2), 0.3)])


@sound("sleep", peak=-9.0, fout=0.4)
def sleep(rng, v):
	box = L.notes(M.music_box, [(0.0, "C6", 0.55), (0.45, "A5", 0.5), (0.9, "F5", 0.5), (1.35, "G5", 0.45),
		(1.9, "E5", 0.45), (2.4, "F5", 0.5)], rng)
	pad = L.pad_chord(rng, ["F3", "C4", "A4"], 3.0, attack=1.0, release=1.4, cutoff=900)
	air = F.bandpass(N.pink(4.0, rng), 1500, 5000, 1) * env_points([(0, 0), (1.5, 1), (4.0, 0)], 4.0, "cos")
	return mix(L.nz(box) * 0.8, L.nz(pad) * 0.3, L.nz(air) * 0.04)


# ------------------------------------------------------------------------------------------
# Combat
# ------------------------------------------------------------------------------------------

@sound("hit_soft", variants=3, peak=-6.0)
def hit_soft(rng, v):
	slap = F.lowpass(N.white(0.08, rng), 1800 + 200 * v, 2) * env_perc(0.08, 0.001, 0.04)
	body = L.thud(rng, 140 + 15 * v, 0.2, 0.09, 0.3)
	knock_ = L.wood(rng, 560 + 60 * v, 0.12, 0.04, 0.3)
	return mix(L.nz(slap) * 0.6, body * 0.8, knock_ * 0.3)


@sound("hit_hard", variants=3, peak=-4.0)
def hit_hard(rng, v):
	crack = L.burst(rng, 0.006, 1500, 5000)
	body = L.thud(rng, 95 + 10 * v, 0.35, 0.15, 0.5)
	crunch_ = L.crunch(rng, 0.07, [(0, 3000), (0.07, 0)], (1000, 5000), (0.0006, 0.003))
	whump = F.lowpass(N.white(0.15, rng), 700, 2) * env_perc(0.15, 0.002, 0.08)
	return F.lowpass(mix(L.nz(crack) * 0.4, body, L.nz(crunch_) * 0.3, L.nz(whump) * 0.5), 7000, 2)


@sound("enemy_hurt", variants=3, peak=-10.0)
def enemy_hurt(rng, v):
	f0 = [760, 690, 820][v]
	d = 0.2
	f = osc.vibrato(osc.glide(f0, f0 * 0.57, 0.16, "exp", total=d), d, 17.0, 40.0)
	idx = 1.2 * env_perc(d, 0.003, 0.12) + 0.3
	y = FM.fm(f, d, 1.0, idx) * env_points([(0, 0), (0.01, 1), (0.1, 0.7), (d, 0)], d, "cos")
	puff = F.bandpass(N.white(0.1, rng), 800, 3000, 1) * env_perc(0.1, 0.002, 0.06)
	return F.lowpass(mix(L.nz(y), L.nz(puff) * 0.25), 5000, 2)


@sound("enemy_defeat", peak=-7.0, fout=0.15)
def enemy_defeat(rng, v):
	swirl = L.whoosh(rng, 0.55, [(0, 3000), (0.55, 600)], q=1.2, amp_points=[(0, 0), (0.05, 1), (0.55, 0)])
	puff = F.lowpass(N.white(0.3, rng), 700, 2) * env_points([(0, 0), (0.02, 1), (0.3, 0)], 0.3, "cos")
	sparkle = L.glass_notes([(0.0, "C7", 0.5), (0.06, "G6", 0.5), (0.12, "E6", 0.5), (0.2, "C6", 0.6)], t60=0.9)
	return L.stagger([(0.0, swirl, 0.55), (0.0, L.nz(puff), 0.6), (0.08, L.nz(sparkle), 0.45)])


@sound("brazier_light", peak=-5.0, fout=0.3)
def brazier_light(rng, v):
	d = 1.6
	whoomph = F.sweep_points(N.pink(d, rng), "lowpass", [(0, 200), (0.3, 2600), (1.6, 900)], 0.8)
	whoomph = L.nz(whoomph) * env_points([(0, 0), (0.25, 1), (0.6, 0.5), (d, 0)], d, "cos")
	low = L.thud(rng, 62, 0.8, 0.4, 0.5)
	crackle = L.crunch(rng, d, [(0, 0), (0.25, 200), (d, 30)], (1200, 6000), (0.0005, 0.002))
	warm = L.pad_chord(rng, ["F3", "C4"], 0.8, attack=0.3, release=0.8, cutoff=900)
	return L.stagger([(0.0, whoomph, 0.8), (0.05, low, 0.6), (0.1, L.nz(crackle), 0.3), (0.15, L.nz(warm), 0.12)])


@sound("heartseed_pulse", peak=-6.0, fout=0.3)
def heartseed_pulse(rng, v):
	lub = L.thud(rng, 58, 0.5, 0.22, 0.1)
	dub = L.thud(rng, 52, 0.5, 0.2, 0.1)
	shimmer = L.glass_notes([(0.05, "F5", 0.35), (0.1, "C6", 0.3), (0.16, "A6", 0.25), (0.22, "E6", 0.2)], t60=1.6, sparkle=0.4)
	hum = np.sin(2 * np.pi * M.hz("F2") * np.arange(ns(1.8)) / 44100) * env_points([(0, 0), (0.5, 1), (1.8, 0)], 1.8, "cos")
	return L.stagger([(0.0, lub, 0.9), (0.28, dub, 0.7), (0.0, L.nz(shimmer), 0.3), (0.0, hum, 0.25)])
