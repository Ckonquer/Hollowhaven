"""Original music for Hollowhaven. All melodies are hand-written for this game.

The "For Krystal" motif is a rising fourth that leans back down by step (scale degrees
5-1-7-6-5, e.g. C5 F5 E5 D5 C5 in F major). It opens the title theme, colours the haven tune,
floats through the night piece, turns minor and low in the boss loop, and returns fuller in the
ending (a whole step higher, in G, for a brighter homecoming).

Every track is an exact loop: note tails and reverb are folded back onto the beginning."""
from __future__ import annotations

import re

import numpy as np

from catalog import loop
from hhsynth.core import ns
from hhsynth import music as M, space as S
from hhsynth.music import Song

# ------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------

_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def _pc(name: str) -> int:
	return (_PC[name[0]] + name[1:].count("#") - name[1:].count("b")) % 12


def chord_info(sym: str) -> dict:
	"""'Gm7' -> {'root': pc, 'ivs': [0,3,7,10], 'bass': pc}; 'C/E' -> bass E."""
	bass = None
	if "/" in sym:
		sym, b = sym.split("/")
		bass = _pc(b)
	m = re.fullmatch(r"([A-G][#b]?)(.*)", sym)
	root = _pc(m.group(1))
	ivs = M.CHORD_SHAPES[m.group(2)]
	return {"root": root, "ivs": ivs, "bass": root if bass is None else bass}


def in_range(pc: int, lo: int) -> int:
	"""Lowest midi note with pitch class pc that is >= lo."""
	return lo + ((pc - lo) % 12)


def split_bar(entry, beats_per_bar: int):
	"""A bar's harmony: 'F' or [('Am7', 2), ('D', 2)] -> [(sym, start_beat, beats)]."""
	if isinstance(entry, str):
		return [(entry, 0.0, float(beats_per_bar))]
	out = []
	b = 0.0
	for sym, n in entry:
		out.append((sym, b, float(n)))
		b += n
	return out


def play_line(song: Song, bus: str, inst, bars, start_bar: int, vel: float = 0.8, pan: float = 0.0,
		transpose: int = 0, legato: float = 1.0, accent_downbeat: float = 0.08, **kw):
	"""bars = [[(note|'r', beats), ...], ...] starting at start_bar."""
	for i, bar in enumerate(bars):
		beat = 0.0
		for note, beats in bar:
			if note != "r":
				v = vel + (accent_downbeat if beat == 0 else 0.0)
				song.note(bus, inst, M.midi(note) + transpose, start_bar + i, beat, beats * legato, min(v, 1.0), pan, **kw)
			beat += beats


def pad_line(song: Song, bus: str, chords, start_bar: int, inst=M.pad, lo: int = 53, hi: int = 69, vel: float = 0.6,
		pan: float = 0.0, transpose: int = 0, overlap: float = 0.15, **kw):
	prev = None
	for i, entry in enumerate(chords):
		for sym, b0, nb in split_bar(entry, song.bpb):
			ci = chord_info(sym)
			tones = [ci["root"] + iv for iv in ci["ivs"]]
			v = M.voice_lead(prev, [t + transpose for t in tones], lo, hi)
			prev = v
			for n in v:
				song.note(bus, inst, n, start_bar + i, b0, nb + overlap, vel, pan, human=0.0, **kw)


def bass_notes(song: Song, bus: str, chords, start_bar: int, inst, pattern, lo: int = 36, vel: float = 0.8,
		transpose: int = 0, **kw):
	"""pattern = [(beat, beats, degree)] with degree 'b' (bass), '5' (fifth), '8' (octave)."""
	for i, entry in enumerate(chords):
		for sym, b0, nb in split_bar(entry, song.bpb):
			ci = chord_info(sym)
			bass = in_range((ci["bass"] + transpose) % 12, lo)
			fifth = in_range((ci["root"] + 7 + transpose) % 12, lo)
			for beat, beats, deg in pattern:
				if beat < b0 or beat >= b0 + nb:
					continue
				n = {"b": bass, "5": fifth, "8": bass + 12}[deg]
				song.note(bus, inst, n, start_bar + i, beat, beats, vel, 0.0, **kw)


def arp_tones(sym: str, transpose: int = 0, lo: int = 50) -> dict:
	ci = chord_info(sym)
	root = in_range((ci["root"] + transpose) % 12, lo)
	third = root + ci["ivs"][1]
	fifth = root + ci["ivs"][2]
	bass = in_range((ci["bass"] + transpose) % 12, lo - 12)
	return {"bass": bass, "root": root, "third": third, "fifth": fifth, "top": root + 12,
		"seventh": root + (ci["ivs"][3] if len(ci["ivs"]) > 3 else 12)}


def harp_arp(song: Song, bus: str, chords, start_bar: int, pattern, vel: float = 0.55, pan: float = -0.25,
		transpose: int = 0, lo: int = 50, inst=M.harp):
	"""pattern = [(beat, degree, vel_mul)], degree in bass/root/third/fifth/top/seventh/fifth_lo."""
	for i, entry in enumerate(chords):
		for sym, b0, nb in split_bar(entry, song.bpb):
			t = arp_tones(sym, transpose, lo)
			t["fifth_lo"] = t["fifth"] - 12
			t["third_hi"] = t["third"] + 12
			for beat, deg, vm in pattern:
				if beat < b0 or beat >= b0 + nb:
					continue
				song.note(bus, inst, t[deg], start_bar + i, beat, 1.0, vel * vm, pan)


# ------------------------------------------------------------------------------------------
# The "For Krystal" theme (F major, 3/4) - shared by the title and the ending
# ------------------------------------------------------------------------------------------

THEME_CHORDS = [
	# A
	"F", "C/E", "Dm", "Bb", "F", "Gm7", "Bb", "C",
	# A'
	"F", "C/E", "Dm", "Bbmaj7", "Gm7", "Bbm", "F/C", "C7",
	# B
	"Dm", "Bb", "F", "C", "Dm", "Bb", "Gm7", [("C7sus4", 2), ("C7", 1)],
	# A''
	"F", "C/E", "Dm", "Bb", "Gm7", "Bbm", "F", "F",
]

THEME_A = [
	[("C5", 1), ("F5", 1.5), ("E5", 0.5)],
	[("D5", 1.5), ("C5", 0.5), ("G4", 1)],
	[("A4", 1), ("D5", 1.5), ("C5", 0.5)],
	[("Bb4", 1), ("D5", 1), ("F5", 1)],
	[("A5", 1.5), ("G5", 0.5), ("F5", 1)],
	[("F5", 1), ("D5", 1), ("Bb4", 1)],
	[("C5", 1), ("D5", 1), ("F5", 1)],
	[("F5", 1), ("E5", 2)],
]
THEME_A2 = [
	[("C5", 1), ("F5", 1.5), ("E5", 0.5)],
	[("D5", 1.5), ("C5", 0.5), ("G4", 1)],
	[("A4", 1), ("D5", 1), ("F5", 1)],
	[("A5", 1.5), ("G5", 0.5), ("F5", 1)],
	[("D5", 1), ("G5", 1), ("Bb5", 1)],
	[("F5", 2), ("Db5", 1)],
	[("C5", 2), ("A4", 1)],
	[("G4", 1), ("Bb4", 1), ("E5", 1)],
]
THEME_B = [
	[("F5", 1.5), ("E5", 0.5), ("D5", 1)],
	[("F5", 2), ("D5", 1)],
	[("C5", 1), ("F5", 1), ("A5", 1)],
	[("G5", 3)],
	[("A5", 1.5), ("G5", 0.5), ("F5", 1)],
	[("D5", 1), ("F5", 2)],
	[("Bb5", 1), ("A5", 1), ("G5", 1)],
	[("F5", 2), ("E5", 1)],
]
THEME_A3 = [
	[("C5", 1), ("F5", 1.5), ("E5", 0.5)],
	[("D5", 1.5), ("C5", 0.5), ("G4", 1)],
	[("A4", 1), ("D5", 1.5), ("C5", 0.5)],
	[("Bb4", 1), ("D5", 1), ("F5", 1)],
	[("G5", 1.5), ("F5", 0.5), ("D5", 1)],
	[("F5", 2), ("Db5", 1)],
	[("C5", 3)],
	[("r", 1), ("A4", 1), ("Bb4", 1)],
]

WALTZ_EIGHTHS = [(0.0, "bass", 1.0), (0.5, "fifth_lo", 0.7), (1.0, "root", 0.8), (1.5, "third", 0.75),
	(2.0, "root", 0.75), (2.5, "fifth_lo", 0.65)]
WALTZ_QUARTERS = [(0.0, "bass", 1.0), (1.0, "root", 0.65), (1.0, "third", 0.55), (2.0, "fifth_lo", 0.55),
	(2.0, "third", 0.5)]


@loop("music_title", "music", 32 * 3 * 60.0 / 76.0, rms=-20.0)
def music_title(rng, seconds):
	s = Song(76, 3, 32, rng)
	# melody: music box, with the flute singing the B section
	play_line(s, "box", M.music_box, THEME_A, 0, 0.72, 0.15)
	play_line(s, "box", M.music_box, THEME_A2, 8, 0.75, 0.15)
	play_line(s, "flute", M.flute, THEME_B, 16, 0.6, -0.1, legato=0.95)
	play_line(s, "box", M.music_box, THEME_A3, 24, 0.75, 0.15)
	# celesta doubles the last phrase an octave up, very softly
	play_line(s, "cel", M.celesta, THEME_A3[:6], 24, 0.35, 0.35, transpose=12)
	# music box answers in the B section (a high chord tone on beat 3)
	for i, sym in enumerate(THEME_CHORDS[16:24]):
		sym0 = sym if isinstance(sym, str) else sym[0][0]
		t = arp_tones(sym0, 0, 62)
		s.note("box", M.music_box, t["top"] + 12, 16 + i, 2.0, 1.0, 0.42, 0.4)
	# harp: gentle waltz first, flowing eighths from A'
	harp_arp(s, "harp", THEME_CHORDS[:8], 0, WALTZ_QUARTERS, 0.5)
	harp_arp(s, "harp", THEME_CHORDS[8:30], 8, WALTZ_EIGHTHS, 0.5)
	harp_arp(s, "harp", THEME_CHORDS[30:], 30, WALTZ_QUARTERS, 0.45)
	# pad & bass
	pad_line(s, "pad", THEME_CHORDS, 0, lo=53, hi=69, vel=0.5)
	bass_notes(s, "bass", THEME_CHORDS[8:31], 8, M.soft_bass, [(0.0, 2.6, "b")], lo=36, vel=0.7)
	ir = S.hall(rng, 2.6)
	return s.mix({"box": (0.0, 0.32), "flute": (-3.0, 0.35), "cel": (-9.0, 0.45), "harp": (-4.0, 0.28),
		"pad": (-15.0, 0.45), "bass": (-13.0, 0.12)}, ir, rms_db=-20.0)


# ------------------------------------------------------------------------------------------
# Haven (G major, 4/4, cosy and bouncy)
# ------------------------------------------------------------------------------------------

HAVEN_CHORDS = [
	"G", "C", "G/B", "C", "Em", "Am7", "D7sus4", "D7",
	"G", "C", "G/B", "C", "Em", "C", [("Am7", 2), ("D", 2)], "G",
	"C", "D", "Bm7", "Em", "C", "D", "Em7", [("Dsus4", 2), ("D", 2)],
	"G", "C", "G/B", "C", "Em", "Am7", "D7sus4", "G",
]
HAVEN_A = [
	[("D5", 0.5), ("G5", 1), ("F#5", 0.5), ("E5", 0.5), ("D5", 0.5), ("B4", 1)],
	[("C5", 0.5), ("E5", 1), ("G5", 0.5), ("E5", 1), ("C5", 1)],
	[("D5", 0.5), ("G5", 1), ("B5", 0.5), ("A5", 0.5), ("G5", 0.5), ("D5", 1)],
	[("E5", 1.5), ("D5", 0.5), ("C5", 1), ("r", 1)],
	[("B4", 0.5), ("E5", 1), ("G5", 0.5), ("F#5", 0.5), ("E5", 0.5), ("B4", 1)],
	[("C5", 0.5), ("E5", 1), ("A5", 0.5), ("G5", 1), ("E5", 1)],
	[("D5", 1), ("G5", 1.5), ("A5", 0.5), ("G5", 1)],
	[("F#5", 2), ("E5", 0.5), ("D5", 0.5), ("C5", 0.5), ("A4", 0.5)],
]
HAVEN_A2 = [
	[("D5", 0.5), ("G5", 1), ("F#5", 0.5), ("E5", 0.5), ("D5", 0.5), ("B4", 1)],
	[("C5", 0.5), ("E5", 1), ("G5", 0.5), ("C6", 1), ("B5", 0.5), ("A5", 0.5)],
	[("G5", 1.5), ("D5", 0.5), ("B4", 1), ("D5", 1)],
	[("E5", 0.5), ("G5", 0.5), ("C6", 1), ("B5", 0.5), ("A5", 0.5), ("G5", 1)],
	[("G5", 1), ("F#5", 0.5), ("E5", 0.5), ("B4", 1), ("E5", 1)],
	[("E5", 1.5), ("G5", 0.5), ("E5", 1), ("C5", 1)],
	[("C5", 0.5), ("A4", 0.5), ("C5", 0.5), ("E5", 0.5), ("D5", 0.5), ("F#5", 0.5), ("A5", 1)],
	[("G5", 3), ("r", 1)],
]
HAVEN_B = [
	[("E5", 1), ("G5", 1), ("C6", 1.5), ("B5", 0.5)],
	[("A5", 2), ("F#5", 1), ("D5", 1)],
	[("D5", 1), ("F#5", 1), ("B5", 1.5), ("A5", 0.5)],
	[("G5", 3), ("E5", 1)],
	[("E5", 1), ("G5", 1), ("C6", 1), ("E6", 1)],
	[("D6", 2), ("C6", 0.5), ("B5", 0.5), ("A5", 1)],
	[("B5", 1.5), ("A5", 0.5), ("G5", 1), ("E5", 1)],
	[("G5", 2), ("F#5", 2)],
]
HAVEN_A3 = HAVEN_A[:7] + [[("G5", 2), ("r", 1), ("B4", 0.5), ("C5", 0.5)]]

STRUM_4 = [(0.0, "bass", 1.0), (1.0, "root", 0.6), (1.0, "third", 0.55), (1.0, "fifth", 0.5), (2.0, "fifth_lo", 0.8),
	(3.0, "root", 0.6), (3.0, "third", 0.55), (3.0, "fifth", 0.5), (3.5, "third", 0.4)]


def _strum(song, bus, chords, start_bar, vel, pan):
	"""Boom-chick guitar: bass on 1 and 3, rolled chords on 2 and 4 (15 ms roll)."""
	for i, entry in enumerate(chords):
		for sym, b0, nb in split_bar(entry, song.bpb):
			t = arp_tones(sym, 0, 55)
			t["fifth_lo"] = t["fifth"] - 12
			for beat, deg, vm in STRUM_4:
				if beat < b0 or beat >= b0 + nb:
					continue
				roll = {"root": 0.0, "third": 0.03, "fifth": 0.06}.get(deg, 0.0)
				song.note(bus, M.harp, t[deg], start_bar + i, beat + roll, 0.8, vel * vm, pan)


@loop("music_haven", "music", 32 * 4 * 60.0 / 88.0, rms=-20.0)
def music_haven(rng, seconds):
	s = Song(88, 4, 32, rng, swing=0.08)
	play_line(s, "clar", M.clarinet, HAVEN_A, 0, 0.6, 0.1, legato=0.9)
	play_line(s, "clar", M.clarinet, HAVEN_A2, 8, 0.62, 0.1, legato=0.9)
	play_line(s, "flute", M.flute, HAVEN_B, 16, 0.6, -0.15, legato=0.95)
	play_line(s, "clar", M.clarinet, HAVEN_A3, 24, 0.62, 0.1, legato=0.9)
	# flute holds soft thirds under the last A section
	for i, entry in enumerate(HAVEN_CHORDS[24:31]):
		for sym, b0, nb in split_bar(entry, 4):
			t = arp_tones(sym, 0, 62)
			s.note("flute2", M.ocarina, t["third"], 24 + i, b0, min(nb, 4) - 0.2, 0.5, -0.3)
	_strum(s, "gtr", HAVEN_CHORDS, 0, 0.55, -0.3)
	bass_notes(s, "bass", HAVEN_CHORDS, 0, M.pluck_bass, [(0.0, 0.9, "b"), (2.0, 0.9, "5")], lo=40, vel=0.75)
	# music box answers at phrase ends
	for bar, notes in ((3, ["G5", "B5", "D6"]), (7, ["A5", "F#5", "D6"]), (11, ["G5", "C6", "E6"]), (15, ["D6", "B5", "G5"]),
			(19, ["B5", "E6", "G6"]), (23, ["A5", "D6", "F#6"]), (27, ["G5", "B5", "D6"])):
		for k, nm in enumerate(notes):
			s.note("box", M.music_box, nm, bar, 3.0 + 0.33 * k, 0.5, 0.5, 0.4)
	# light percussion from the second phrase on
	for bar in range(8, 32):
		for b in (0.5, 1.5, 2.5, 3.5):
			s.note("perc", M.shaker, 0.0 + 440.0, bar, b, 0.25, 0.35, 0.35)
		if bar >= 24 or 8 <= bar < 16:
			for b in (1.0, 3.0):
				s.note("perc", M.woodblock, 880.0, bar, b, 0.25, 0.25, -0.2)
	pad_line(s, "pad", HAVEN_CHORDS[16:24], 16, lo=55, hi=71, vel=0.5)
	ir = S.hall(rng, 1.9, brightness=8000)
	return s.mix({"clar": (-2.0, 0.25), "flute": (-3.0, 0.3), "flute2": (-12.0, 0.35), "gtr": (0.0, 0.2),
		"bass": (-8.0, 0.08), "box": (-5.0, 0.35), "perc": (-9.0, 0.15), "pad": (-18.0, 0.4)}, ir, rms_db=-20.0)


# ------------------------------------------------------------------------------------------
# Night (D major, 4/4 at 60, sparse and dreamy)
# ------------------------------------------------------------------------------------------

NIGHT_CHORDS = ["Dmaj9", "Gmaj7", "Dmaj9", "Gmaj7", "Bm9", "Gmaj7", "Em9", "A7sus4",
	"Dmaj9", "F#m7", "Gmaj7", "Gm6", "D/F#", "Bm9", "Em9", "A7sus4",
	"Gmaj7", "Gm6", "Dmaj9", "A7sus4"]
NIGHT_MEL = [
	[("A4", 1), ("D5", 2), ("C#5", 1)], [("B4", 3), ("r", 1)], [("A4", 1), ("E5", 2), ("F#5", 1)], [("D5", 4)],
	[("C#5", 1), ("D5", 1), ("F#5", 2)], [("E5", 2), ("D5", 2)], [("B4", 1), ("E5", 1), ("F#5", 1), ("G5", 1)], [("E5", 4)],
	[("A4", 1), ("D5", 2), ("C#5", 1)], [("A4", 3), ("r", 1)], [("B4", 1), ("D5", 1), ("F#5", 2)], [("E5", 2), ("D5", 1), ("Bb4", 1)],
	[("A4", 4)], [("r", 1), ("F#5", 1), ("E5", 1), ("D5", 1)], [("G5", 2), ("F#5", 1), ("E5", 1)], [("D5", 2), ("E5", 2)],
	[("F#5", 3), ("r", 1)], [("E5", 2), ("D5", 2)], [("A4", 2), ("F#4", 2)], [("r", 3), ("E5", 1)],
]


@loop("music_night", "music", 20 * 4 * 60.0 / 60.0, rms=-20.0)
def music_night(rng, seconds):
	s = Song(60, 4, 20, rng)
	play_line(s, "cel", M.celesta, NIGHT_MEL[:8], 0, 0.6, 0.2)
	play_line(s, "oca", M.ocarina, NIGHT_MEL[8:16], 8, 0.55, -0.1, legato=0.92)
	play_line(s, "cel", M.celesta, NIGHT_MEL[16:], 16, 0.6, 0.2)
	play_line(s, "box", M.music_box, NIGHT_MEL[16:], 16, 0.35, -0.3, transpose=12)
	pad_line(s, "pad", NIGHT_CHORDS, 0, lo=50, hi=69, vel=0.55, attack=1.6, release=2.4, cutoff=1100)
	# slow harp: one rising arpeggio per bar
	harp_arp(s, "harp", NIGHT_CHORDS, 0, [(0.0, "bass", 1.0), (1.0, "fifth_lo", 0.6), (2.0, "root", 0.6), (3.0, "third", 0.55)],
		0.42, -0.35, lo=50)
	bass_notes(s, "bass", NIGHT_CHORDS, 0, M.soft_bass, [(0.0, 3.8, "b")], lo=38, vel=0.5)
	# faint 'stars': high glass glints
	pent = ["A6", "B6", "D7", "E7", "F#7"]
	for k in range(14):
		bar = float(rng.uniform(0, 20))
		s.note("stars", M.celesta, pent[int(rng.integers(0, 5))], int(bar), (bar % 1) * 4, 0.5, 0.25, float(rng.uniform(-0.8, 0.8)))
	ir = S.hall(rng, 3.6, brightness=6000)
	return s.mix({"cel": (1.0, 0.5), "oca": (-4.0, 0.45), "box": (-12.0, 0.5), "pad": (-14.0, 0.5),
		"harp": (-6.0, 0.4), "bass": (-13.0, 0.15), "stars": (-16.0, 0.7)}, ir, rms_db=-20.0)


# ------------------------------------------------------------------------------------------
# Boss (D minor, 4/4 at 120: ostinato, low drums, dissonant pads - tense, not overwhelming)
# ------------------------------------------------------------------------------------------

BOSS_A_CH = ["Dm", "A/C#", "Bb", "A", "Dm", "A/C#", "Gm", "A"]
BOSS_B_CH = ["Bb", "C", "Dm", "Dm", "Bb", "C", "Eb", "A"]
BOSS_CHORDS = ["Dm", "Dm"] + BOSS_A_CH + BOSS_B_CH + BOSS_A_CH + ["Dm", "Dm", "Dm", "A"]
# the Krystal motif turned minor and low (A D C# Bb A)
BOSS_MOTIF = [
	[("A3", 1), ("D4", 3)], [("C#4", 4)], [("Bb3", 2), ("D4", 2)], [("A3", 4)],
	[("A3", 1), ("D4", 3)], [("E4", 2), ("C#4", 2)], [("D4", 2), ("Bb3", 2)], [("A3", 4)],
]
BOSS_B_MEL = [
	[("F4", 2), ("D4", 2)], [("E4", 4)], [("F4", 1), ("A4", 3)], [("G4", 2), ("F4", 2)],
	[("D4", 2), ("F4", 2)], [("G4", 2), ("E4", 2)], [("G4", 4)], [("C#4", 2), ("E4", 2)],
]
OSTINATO = {  # eighth-note figures per chord root (tense, with a flat second)
	"D": ["D3", "D3", "A3", "D3", "Eb3", "D3", "C4", "A3"],
	"A": ["A2", "A2", "E3", "A2", "Bb2", "A2", "G3", "E3"],
	"C#": ["C#3", "C#3", "A3", "C#3", "D3", "C#3", "E3", "A2"],
	"Bb": ["Bb2", "Bb2", "F3", "Bb2", "C3", "Bb2", "A3", "F3"],
	"G": ["G2", "G2", "D3", "G2", "A2", "G2", "F3", "D3"],
	"C": ["C3", "C3", "G3", "C3", "D3", "C3", "Bb3", "G3"],
	"Eb": ["Eb3", "Eb3", "Bb3", "Eb3", "F3", "Eb3", "D4", "Bb3"],
}


def horn(f, dur, vel, rng):
	"""Low, soft brass-like FM voice."""
	from hhsynth import fm as FM, filters as F
	from hhsynth.core import env_adsr
	total = dur + 0.3
	n = ns(total)
	t = np.arange(n) / 44100
	env = env_adsr(total, 0.09, 0.4, 0.85, 0.3, gate=dur)
	idx = 1.2 + 1.2 * env
	y = FM.fm(f, total, 1.0, idx)
	y = F.lowpass(y, 1400, 2)
	return y * env * vel


@loop("music_boss", "music", 30 * 4 * 60.0 / 120.0, rms=-20.0)
def music_boss(rng, seconds):
	s = Song(120, 4, 30, rng)
	for i, sym in enumerate(BOSS_CHORDS):
		key = sym.split("/")[1] if "/" in sym else re.match(r"[A-G][#b]?", sym).group(0)
		fig = OSTINATO[key]
		soft = 26 <= i <= 28
		for k, nm in enumerate(fig):
			v = (0.55 if k in (0, 4) else 0.42) * (0.55 if soft else 1.0)
			s.note("ost", M.ostinato_pluck, nm, i, k * 0.5, 0.45, v, 0.15 if k % 2 else -0.15, human=0.003)
	play_line(s, "horn", horn, BOSS_MOTIF, 2, 0.6, -0.1, legato=0.95)
	play_line(s, "horn", horn, BOSS_B_MEL, 10, 0.62, -0.1, legato=0.95)
	play_line(s, "horn", horn, BOSS_MOTIF, 18, 0.66, -0.1, legato=0.95)
	# dissonant pad: strings on the chords plus a quiet flat-second rub
	pad_line(s, "str", BOSS_CHORDS, 0, inst=M.strings, lo=50, hi=65, vel=0.5, overlap=0.1)
	for i, sym in enumerate(BOSS_CHORDS):
		ci = chord_info(sym)
		s.note("rub", M.pad, in_range((ci["root"] + 1) % 12, 62), i, 0.0, 3.9, 0.35, 0.5, human=0.0, attack=1.2, cutoff=900)
	# drums: low toms, a heavier hit at each section start, heartbeat in the breakdown
	for bar in range(30):
		if 26 <= bar <= 28:
			for b in (0.0, 0.5):
				s.note("drum", M.heartbeat, 48.0 if b == 0 else 44.0, bar, b, 0.3, 0.8, 0.0, human=0.0)
				s.note("drum", M.heartbeat, 48.0 if b == 0 else 44.0, bar, 2.0 + b, 0.3, 0.7, 0.0, human=0.0)
			continue
		big = bar in (0, 2, 10, 18)
		s.note("drum", M.tom, 55.0 if big else 68.0, bar, 0.0, 0.5, 1.0 if big else 0.8, 0.0, human=0.002)
		s.note("drum", M.tom, 92.0, bar, 1.5, 0.5, 0.45, 0.25, human=0.002)
		s.note("drum", M.tom, 68.0, bar, 2.0, 0.5, 0.7, 0.0, human=0.002)
		s.note("drum", M.tom, 92.0, bar, 3.0, 0.5, 0.4, 0.25, human=0.002)
		s.note("drum", M.tom, 80.0, bar, 3.5, 0.5, 0.5, -0.2, human=0.002)
	# a rising swell into the last bar so the loop restarts with intent
	s.note("swell", M.swell, 0.0 + 1000.0, 29, 0.0, 4.0, 0.9, 0.0, human=0.0)
	ir = S.hall(rng, 2.2, brightness=5000)
	return s.mix({"ost": (3.0, 0.18), "horn": (-6.0, 0.3), "str": (-12.0, 0.35), "rub": (-20.0, 0.4),
		"drum": (-4.0, 0.15), "swell": (-18.0, 0.4)}, ir, rms_db=-20.0)


# ------------------------------------------------------------------------------------------
# Ending (G major, 3/4: the title theme returns, fuller and a step higher)
# ------------------------------------------------------------------------------------------

END_INTRO = ["F", "Dm7", "Bbmaj7", "C"]          # (written in F, transposed +2 like the theme)
END_OUTRO = ["F", "Bbm6", "F", "C7"]


@loop("music_ending", "music", 40 * 3 * 60.0 / 80.0, rms=-19.5)
def music_ending(rng, seconds):
	s = Song(80, 3, 40, rng)
	T = 2  # F -> G
	chords = END_INTRO + THEME_CHORDS + END_OUTRO
	# intro: harp and pad, a music box glimpse of the motif
	s.note("box", M.music_box, M.midi("C6") + T, 2, 0.0, 1, 0.5, 0.3)
	s.note("box", M.music_box, M.midi("F6") + T, 2, 1.0, 1.5, 0.5, 0.3)
	s.note("box", M.music_box, M.midi("E6") + T, 2, 2.5, 0.5, 0.5, 0.3)
	s.note("box", M.music_box, M.midi("D6") + T, 3, 0.0, 3, 0.45, 0.3)
	# theme: flute leads A, music box A', strings+flute B, everything together A''
	play_line(s, "flute", M.flute, THEME_A, 4, 0.62, -0.1, transpose=T, legato=0.95)
	play_line(s, "box", M.music_box, THEME_A2, 12, 0.72, 0.2, transpose=T)
	play_line(s, "flute", M.flute, THEME_A2, 12, 0.42, -0.2, transpose=T - 12, legato=0.95)
	play_line(s, "flute", M.flute, THEME_B, 20, 0.66, -0.1, transpose=T, legato=0.95)
	play_line(s, "cel", M.celesta, THEME_B, 20, 0.3, 0.35, transpose=T + 12)
	play_line(s, "flute", M.flute, THEME_A3[:7], 28, 0.68, -0.1, transpose=T, legato=0.95)
	play_line(s, "box", M.music_box, THEME_A3[:7], 28, 0.6, 0.25, transpose=T + 12)
	# outro: the motif one last time, softly, then the pickup back to the intro
	play_line(s, "box", M.music_box, [[("C5", 1), ("F5", 1.5), ("E5", 0.5)], [("Db5", 1.5), ("C5", 0.5), ("Bb4", 1)],
		[("A4", 3)], [("r", 3)]], 36, 0.55, 0.2, transpose=T)
	harp_arp(s, "harp", chords, 0, WALTZ_EIGHTHS, 0.5, transpose=T)
	pad_line(s, "pad", chords, 0, lo=55, hi=71, vel=0.5, transpose=T)
	pad_line(s, "str", chords[20:36], 20, inst=M.strings, lo=60, hi=76, vel=0.55, transpose=T)
	bass_notes(s, "bass", chords, 0, M.soft_bass, [(0.0, 2.6, "b")], lo=36, vel=0.7, transpose=T)
	for bar in (4, 12, 20, 28):
		s.note("drum", M.tom, 58.0, bar, 0.0, 0.5, 0.55, 0.0, human=0.0)
	s.note("swell", M.swell, 1000.0, 27, 0.0, 3.0, 0.8, 0.0, human=0.0)
	ir = S.hall(rng, 2.8)
	return s.mix({"flute": (-2.0, 0.35), "box": (-2.0, 0.32), "cel": (-11.0, 0.45), "harp": (-4.0, 0.28),
		"pad": (-16.0, 0.45), "str": (-11.0, 0.4), "bass": (-11.0, 0.12), "drum": (-10.0, 0.3), "swell": (-18.0, 0.5)},
		ir, rms_db=-19.5)
