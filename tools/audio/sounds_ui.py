"""UI sounds: gentle wooden/paper clicks and soft chimes (F major / C major colours, like the
title theme). Peaks are kept well below the SFX so menus never feel loud."""
from __future__ import annotations

import numpy as np

from catalog import sound
from hhsynth.core import ns, env_points, mix, place
from hhsynth import filters as F, music as M
import sfxlib as L


@sound("ui_click", "ui", peak=-13.0, fout=0.01)
def ui_click(rng, v):
	# small wooden 'tok' + a whisper of paper
	tok = L.wood(rng, 1180.0, 0.12, t60=0.045, bright=0.55, click=0.18)
	paper = L.crunch(rng, 0.03, 900, (2500, 7000), (0.0008, 0.002)) * 0.15
	return F.lowpass(mix(tok, paper), 7500, 1)


@sound("ui_hover", "ui", peak=-15.0, fout=0.008)
def ui_hover(rng, v):
	tick = L.wood(rng, 2300.0, 0.05, t60=0.018, bright=0.3, click=0.1)
	return F.lowpass(tick, 6000, 1)


@sound("ui_open", "ui", peak=-11.0)
def ui_open(rng, v):
	swish = L.whoosh(rng, 0.2, [(0, 1200), (0.2, 3600)], q=1.4, amp_points=[(0, 0), (0.08, 1), (0.2, 0)], color=0.6)
	chime = L.notes(M.celesta, [(0.02, "A5", 0.55), (0.1, "E6", 0.5)], rng)
	return mix(swish * 0.25, L.nz(chime) * 0.9)


@sound("ui_close", "ui", peak=-13.0)
def ui_close(rng, v):
	swish = L.whoosh(rng, 0.18, [(0, 3400), (0.18, 1100)], q=1.4, amp_points=[(0, 0), (0.05, 1), (0.18, 0)], color=0.6)
	chime = L.notes(M.celesta, [(0.0, "E6", 0.45), (0.08, "A5", 0.4)], rng)
	return mix(swish * 0.25, L.nz(chime) * 0.8)


@sound("ui_error", "ui", peak=-11.0)
def ui_error(rng, v):
	# two muted marimba-like bonks, falling (a friendly "nope", no buzzer)
	def bonk(f):
		return L.knock(rng, [f, f * 3.93, f * 9.2], [0.16, 0.05, 0.02], [1.0, 0.25, 0.05], 0.35, 0.004, 2500, 0.05)
	y = L.stagger([(0.0, bonk(M.hz("E4")), 1.0), (0.12, bonk(M.hz("C4")), 0.9)])
	return F.lowpass(y, 2600, 2)


@sound("ui_craft", "ui", peak=-9.0)
def ui_craft(rng, v):
	# wooden pieces clicking together, a little ratchet, then a bright 'done' arpeggio
	parts = [(0.0, L.wood(rng, 420, 0.2, 0.08, 0.6), 0.9), (0.09, L.wood(rng, 560, 0.2, 0.07, 0.6), 0.7),
		(0.2, L.wood(rng, 360, 0.25, 0.09, 0.5), 1.0)]
	for i in range(4):
		parts.append((0.13 + i * 0.012, L.wood(rng, 1900 + 150 * i, 0.03, 0.012, 0.3, 0.2), 0.18))
	tools = L.stagger(parts)
	sparkle = L.notes(M.celesta, [(0.3, "C6", 0.45), (0.345, "E6", 0.45), (0.39, "G6", 0.5), (0.435, "C7", 0.4)], rng)
	return mix(L.nz(tools) * 0.9, L.nz(sparkle) * 0.55)


@sound("ui_quest", "ui", peak=-9.0)
def ui_quest(rng, v):
	arp = L.notes(M.music_box, [(0.0, "F5", 0.7), (0.11, "A5", 0.7), (0.22, "C6", 0.75), (0.36, "F6", 0.8)], rng)
	pad = L.pad_chord(rng, ["F4", "A4", "C5"], 0.9, attack=0.25, release=0.9)
	return mix(L.nz(arp), L.nz(pad) * 0.22)


@sound("ui_notify", "ui", peak=-13.0)
def ui_notify(rng, v):
	return L.glass_notes([(0.0, "C6", 0.8), (0.07, "G6", 0.45)], t60=1.1, sparkle=0.6)


@sound("ui_befriend", "ui", peak=-8.0)
def ui_befriend(rng, v):
	arp = L.notes(M.music_box, [(0.0, "F5", 0.7), (0.1, "C6", 0.7), (0.2, "A5", 0.7), (0.32, "F6", 0.85)], rng)
	pent = ["C7", "D7", "F7", "G7", "A7"]
	spark = L.glass_notes([(0.42 + 0.07 * i, pent[int(rng.integers(0, 5))], 0.25) for i in range(5)], t60=0.9, sparkle=0.8)
	pad = L.pad_chord(rng, ["F4", "C5", "A5"], 1.3, attack=0.3, release=1.0)
	return mix(L.nz(arp), L.nz(spark) * 0.35, L.nz(pad) * 0.25)


@sound("ui_bond", "ui", peak=-9.0)
def ui_bond(rng, v):
	box = L.notes(M.music_box, [(0.0, "C6", 0.7), (0.16, "A5", 0.65), (0.34, "F6", 0.75)], rng)
	pad = L.pad_chord(rng, ["F4", "G4", "C5"], 1.2, attack=0.35, release=1.0)
	return mix(L.nz(box), L.nz(pad) * 0.28)


@sound("ui_save", "ui", peak=-12.0)
def ui_save(rng, v):
	# a book gently closing, then a soft fifth
	swish = L.whoosh(rng, 0.14, [(0, 900), (0.14, 2200)], q=1.0, amp_points=[(0, 0), (0.1, 1), (0.14, 0.3)], color=0.8)
	book = L.wood(rng, 190, 0.3, 0.07, 0.25, 0.3)
	chime = L.glass_notes([(0.0, "G5", 0.5), (0.05, "D6", 0.4)], t60=1.2, sparkle=0.4)
	return L.stagger([(0.0, swish, 0.25), (0.13, book, 0.7), (0.2, L.nz(chime), 0.6)])
