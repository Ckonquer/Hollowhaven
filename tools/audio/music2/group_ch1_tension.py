"""Chapter One tension cues for Hollowhaven (original compositions, synthesised in code).

    "C:/Users/Ali/Desktop/Hollowhaven/.tools/pyenv/Scripts/python.exe" tools/audio/music2/group_ch1_tension.py

Cues (all seamless loops, OGG Vorbis 44.1 kHz stereo, game/assets/audio/music/):
  m10_thorns_in_the_path.ogg    ordinary Chapter One combat   E minor 6/8, dotted-quarter 100
  m11_the_last_shift.ogg        Old Mine / Tobin annex        G minor 4/4, 60 bpm, very sparse
  m12_eyes_that_stay_shut.ogg   Ruins / Silk approach         octatonic on B, 3/4, 48 bpm
  m13_layer2.ogg / _layer3.ogg  phase layers for music_boss   D minor 4/4, 120 bpm, 30 bars = the
                                                              boss loop sample-for-sample
  m25_no_thread_left_unseen.ogg Weaver's Crossing rematch     C minor, 7/8 + 4/4, eighth = 300

Every piece is written note by note below (melody, harmony, bass, counter-lines, percussion) and
rendered with hhsynth instruments (tools/audio/hhsynth, used read-only) plus the extra voices in
ch1_tension_voices.py. Tails and reverb are folded back onto the loop start (hhsynth Song.mix),
so every file is exactly periodic. Mastering: BS.1770 integrated loudness to a target next to
the matching existing track (measured with ch1_tension_qa.py), then a smooth true-peak limiter
(ceiling below -1 dBTP) that only touches rare peaks. Fixed seeds -> identical renders.

Nobody has listened to these renders during the automated build: verification is analysis only
(levels, loop seams, silence gaps, spectra and spectrogram images)."""
from __future__ import annotations

import json
import os
import re
import sys
import time

sys.dont_write_bytecode = True

import numpy as np
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.abspath(os.path.join(HERE, ".."))
ROOT = os.path.abspath(os.path.join(AUDIO, "..", ".."))
for p in (AUDIO, HERE):
	if p not in sys.path:
		sys.path.insert(0, p)

from hhsynth.core import ns, rng_for, db  # noqa: E402
from hhsynth import music as M, space as S  # noqa: E402
from hhsynth.music import Song  # noqa: E402
import ch1_tension_voices as V  # noqa: E402
import ch1_tension_qa as Q  # noqa: E402

SR = 44100
OUT_DIR = os.path.join(ROOT, "game", "assets", "audio", "music")
QA_DIR = os.path.join(ROOT, "qa", "tmp", "music2")
MANIFEST = os.path.join(HERE, "manifest_ch1_tension.json")
BOSS_WAV = os.path.join(OUT_DIR, "music_boss.wav")
GENERATOR = "tools/audio/music2/group_ch1_tension.py (+ ch1_tension_voices.py, ch1_tension_qa.py; hhsynth read-only)"

# Loudness references (integrated LUFS of the existing loops, measured with ch1_tension_qa):
#   music_boss -17.8, music_night -17.6, music_haven -17.0 (title -17.3, ending -16.4)
REF_BOSS = -17.8
REF_NIGHT = -17.6
TP_CEILING = -1.7            # pre-encode true-peak ceiling (Vorbis adds a few tenths of a dB)

# ------------------------------------------------------------------------------------------
# Harmony & sequencing helpers
# ------------------------------------------------------------------------------------------

SHAPES = dict(M.CHORD_SHAPES)
SHAPES.update({"7b9": [0, 4, 7, 10, 13], "dim7": [0, 3, 6, 9], "m7b5": [0, 3, 6, 10], "maj7#11": [0, 4, 7, 11, 18],
	"m(maj7)": [0, 3, 7, 11]})
_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pc(name: str) -> int:
	return (_PC[name[0]] + name[1:].count("#") - name[1:].count("b")) % 12


def chord_info(sym: str) -> dict:
	"""'Gm7' -> root/intervals/bass; 'C/E' puts E in the bass."""
	bass = None
	if "/" in sym:
		sym, b = sym.split("/")
		bass = pc(b)
	m = re.fullmatch(r"([A-G][#b]?)(.*)", sym)
	root = pc(m.group(1))
	return {"root": root, "ivs": SHAPES[m.group(2)], "bass": root if bass is None else bass, "name": m.group(1)}


def in_range(p: int, lo: int) -> int:
	return lo + ((p - lo) % 12)


def split_bar(entry, beats: float):
	"""'Em' or [('C', 3), ('B7', 3)] -> [(sym, start_beat, n_beats)]."""
	if isinstance(entry, str):
		return [(entry, 0.0, float(beats))]
	out, b = [], 0.0
	for sym, n in entry:
		out.append((sym, b, float(n)))
		b += n
	return out


class Grid:
	"""Bar/beat grid with per-bar meters (beats may be eighths). at(bar, beat) -> absolute beat.
	Notes go into an hhsynth Song built with beats_per_bar=1, so time = absolute beat * spb."""

	def __init__(self, meters):
		self.meters = list(meters)
		self.starts = np.concatenate([[0.0], np.cumsum(self.meters)])
		self.total = int(self.starts[-1])

	def at(self, bar: int, beat: float = 0.0) -> float:
		return float(self.starts[bar] + beat)

	def song(self, bpm: float, rng, tail: float = 9.0) -> Song:
		return Song(bpm, 1, self.total, rng, tail=tail)

	def sec(self, bar: int, bpm: float) -> float:
		return float(self.starts[bar]) * 60.0 / bpm


def put(s: Song, g: Grid, bus: str, inst, note, bar: int, beat: float, beats: float, vel: float, pan: float = 0.0,
		human: float = 0.004, **kw) -> None:
	s.note(bus, inst, note, 0, g.at(bar, beat), beats, float(min(max(vel, 0.03), 1.0)), pan, human=human, **kw)


def line(s: Song, g: Grid, bus: str, inst, bars, start_bar: int, vel: float, pan: float = 0.0, transpose: int = 0,
		legato: float = 0.95, accents=None, human: float = 0.005, **kw) -> list:
	"""bars = [[(note | 'r', beats), ...], ...]. accents = {beat_in_bar: +vel}. Returns the notes
	placed as (bar, beat, midi, beats) for the manifest/analysis."""
	placed = []
	for i, bar in enumerate(bars):
		beat = 0.0
		for note, nb in bar:
			if note != "r":
				v = vel + (accents or {}).get(beat, 0.0)
				mid = M.midi(note) + transpose
				put(s, g, bus, inst, mid, start_bar + i, beat, nb * legato, v, pan, human=human, **kw)
				placed.append((start_bar + i, beat, mid, nb))
			beat += nb
	return placed


def chord_pad(s: Song, g: Grid, bus: str, inst, chords, start_bar: int, lo: int, hi: int, vel: float, pan: float = 0.0,
		overlap: float = 0.2, merge: bool = True, **kw) -> None:
	"""Sustained voice-led chords; identical consecutive chords are merged into one long note."""
	events = []
	for i, entry in enumerate(chords):
		for sym, b0, nb in split_bar(entry, g.meters[start_bar + i]):
			if merge and events and events[-1][0] == sym and abs(events[-1][1] + events[-1][2] - g.at(start_bar + i, b0)) < 1e-6:
				events[-1][2] += nb
			else:
				events.append([sym, g.at(start_bar + i, b0), nb])
	prev = None
	for sym, t0, nb in events:
		ci = chord_info(sym)
		tones = [ci["root"] + iv for iv in ci["ivs"]]
		v = M.voice_lead(prev, tones, lo, hi)
		prev = v
		for n in v:
			s.note(bus, inst, n, 0, t0, nb + overlap, vel, pan, human=0.0, **kw)


def tones_of(sym: str, lo: int) -> dict:
	ci = chord_info(sym)
	root = in_range(ci["root"], lo)
	return {"root": root, "third": root + ci["ivs"][1], "fifth": root + ci["ivs"][2], "top": root + 12,
		"third_hi": root + 12 + ci["ivs"][1], "bass": in_range(ci["bass"], lo - 12),
		"seventh": root + (ci["ivs"][3] if len(ci["ivs"]) > 3 else 12)}


# ------------------------------------------------------------------------------------------
# Mastering
# ------------------------------------------------------------------------------------------

def tp_limit(x: np.ndarray, ceiling_db: float, window: float = 0.012):
	"""Smooth, periodic (loop-safe) true-peak limiter: the per-sample gain needed to keep the 4x
	oversampled peak under the ceiling is min-held over +/-window and averaged over one window,
	so it never overshoots and never pumps faster than ~window. Returns (y, stats)."""
	ceil = db(ceiling_db)
	tp = Q.true_peak_trace(x, periodic=True)
	g = np.minimum(1.0, ceil / np.maximum(tp, 1e-12))
	if np.all(g >= 1.0):
		return x.copy(), {"max_gr_db": 0.0, "pct_over_0p5db": 0.0}
	h = max(1, ns(window))
	g = ndimage.minimum_filter1d(g, size=2 * h + 1, mode="wrap")
	g = ndimage.uniform_filter1d(g, size=h, mode="wrap")
	stats = {"max_gr_db": round(-20 * np.log10(np.min(g)), 2), "pct_over_0p5db": round(100.0 * float(np.mean(g < db(-0.5))), 3)}
	return x * g[:, None], stats


def master(x: np.ndarray, target_lufs: float, ceiling_db: float = TP_CEILING):
	"""Loudness to target (periodic BS.1770), then gentle true-peak limiting; iterated so the
	limiter's small level loss is made up."""
	x = x - np.mean(x, axis=0, keepdims=True)
	x = x * db(target_lufs - Q.integrated_loudness(x, periodic=True))
	stats = {}
	for _ in range(4):
		x, stats = tp_limit(x, ceiling_db)
		err = target_lufs - Q.integrated_loudness(x, periodic=True)
		if abs(err) < 0.03:
			break
		x = x * db(err)
	x, st2 = tp_limit(x, ceiling_db)
	stats["max_gr_db"] = max(stats.get("max_gr_db", 0.0), st2["max_gr_db"])
	return x, stats


def finish(s: Song, levels: dict, ir: np.ndarray, hp: float = 35.0, lp: float = 14000.0) -> np.ndarray:
	"""hhsynth mix (fold tails into the loop, periodic HP/LP) at a low working level so its own
	limiter never engages; mastering happens afterwards. Also stores each bus's K-weighted gated
	loudness relative to the whole mix (LU) in s.bus_lu - the balance check used while mixing."""
	x = s.mix(levels, ir, rms_db=-30.0, ceiling_db=-0.05, hp=hp, master_lp=lp)
	total = Q.integrated_loudness(x, periodic=True)
	scale = db(-30.0) / max(float(np.sqrt(np.mean(np.square(sum(
		fold(buf * db(levels.get(k, (0.0, 0.2))[0]), s.n) for k, buf in s.buses.items()))))), 1e-12)
	s.bus_lu = {}
	for k, buf in s.buses.items():
		y = fold(buf * db(levels.get(k, (0.0, 0.2))[0]), s.n) * scale
		s.bus_lu[k] = round(Q.integrated_loudness(y, periodic=True) - total, 1)
	return x


def fold(buf: np.ndarray, n: int) -> np.ndarray:
	from hhsynth.core import fold_loop
	return fold_loop(buf, n)


# ------------------------------------------------------------------------------------------
# m10  Thorns in the Path  (ordinary Chapter One combat)
# ------------------------------------------------------------------------------------------
# E minor, 6/8 (eighth = 300/min, dotted quarter = 100), 56 bars = 67.2 s.
# Intro 0-3 | A 4-19 (oboe) | B 20-35 (G major: bassoon, then violins) | A' 36-51 (oboe + violin
# counter-line, flute joins) | coda 52-55 (motif, cadence C-B7-Em, drum pickup back to the intro).
# Motif "thorn": E-E-B (two repeated eighths, a fifth leap up) falling back by step.

M10_INTRO = ["Em", "Em", "Em", [("C", 3), ("B7", 3)]]
M10_A_CH = ["Em", "D", "C", "B7", "Em", "D", [("Am", 3), ("D", 3)], [("B7", 3), ("Em", 3)],
	"Em", "D", "C", "Am", [("C", 3), ("Am", 3)], "B7", "Em", [("B7", 3), ("Em", 3)]]
M10_B_CH = ["G", "D/F#", "Em", "C", "G", "D", "C", "D", "Em", "Bm", "C", "G/B", "Am", "Em/G", [("Am", 3), ("D", 3)], "B7"]
M10_CODA = ["Em", [("C", 3), ("B7", 3)], "Em", "B7"]
M10_MEL_A = [
	[("E5", 1), ("E5", 1), ("B5", 1), ("A5", 2), ("G5", 1)],
	[("F#5", 2), ("D5", 1), ("A4", 3)],
	[("G4", 1), ("C5", 1), ("E5", 1), ("G5", 2), ("F#5", 1)],
	[("F#5", 3), ("D#5", 3)],
	[("E5", 1), ("E5", 1), ("B5", 1), ("A5", 2), ("G5", 1)],
	[("F#5", 2), ("A5", 1), ("D6", 3)],
	[("C6", 2), ("B5", 1), ("A5", 1), ("G5", 1), ("F#5", 1)],
	[("G5", 1), ("F#5", 1), ("D#5", 1), ("E5", 3)],
	[("E5", 1), ("E5", 1), ("B5", 1), ("A5", 2), ("G5", 1)],
	[("F#5", 2), ("D5", 1), ("A4", 3)],
	[("G4", 1), ("C5", 1), ("E5", 1), ("G5", 1), ("A5", 1), ("B5", 1)],
	[("C6", 2), ("B5", 1), ("A5", 3)],
	[("G5", 2), ("E5", 1), ("C5", 2), ("E5", 1)],
	[("D#5", 2), ("F#5", 1), ("A5", 3)],
	[("G5", 1), ("F#5", 1), ("E5", 1), ("B5", 2), ("G5", 1)],
	[("F#5", 2), ("D#5", 1), ("E5", 3)],
]
M10_MEL_B = [
	[("D5", 3), ("B4", 3)],
	[("A4", 3), ("F#4", 2), ("A4", 1)],
	[("G4", 2), ("B4", 1), ("E5", 3)],
	[("D5", 2), ("C5", 1), ("G4", 3)],
	[("D5", 3), ("G5", 3)],
	[("F#5", 2), ("E5", 1), ("D5", 3)],
	[("E5", 2), ("D5", 1), ("C5", 2), ("B4", 1)],
	[("A4", 6)],
	[("B4", 1), ("E5", 1), ("G5", 1), ("B5", 3)],
	[("A5", 2), ("F#5", 1), ("D5", 3)],
	[("E5", 2), ("G5", 1), ("C6", 2), ("B5", 1)],
	[("B5", 3), ("G5", 3)],
	[("C6", 2), ("A5", 1), ("E5", 3)],
	[("G5", 2), ("E5", 1), ("B4", 3)],
	[("C5", 1), ("E5", 1), ("A5", 1), ("G5", 2), ("F#5", 1)],
	[("F#5", 3), ("D#5", 2), ("B4", 1)],
]
M10_COUNTER_1 = [[("G4", 6)], [("F#4", 6)], [("E4", 6)], [("D#4", 3), ("F#4", 3)],
	[("E4", 3), ("G4", 3)], [("F#4", 3), ("A4", 3)], [("C5", 3), ("A4", 3)], [("B4", 3), ("G4", 3)]]
M10_COUNTER_2 = [[("B4", 6)], [("A4", 6)], [("G4", 3), ("E4", 3)], [("E4", 6)],
	[("E4", 3), ("G4", 3)], [("F#4", 6)], [("G4", 3), ("E4", 3)], [("F#4", 3), ("G4", 3)]]
M10_CODA_MEL = [[("E5", 1), ("E5", 1), ("B5", 1), ("r", 3)],
	[("G5", 1), ("A5", 1), ("B5", 1), ("A5", 1), ("F#5", 1), ("D#5", 1)],
	[("E5", 5), ("r", 1)], [("r", 6)]]
ACC68 = {0.0: 0.1, 3.0: 0.05}
MAR_A = [(0, "root", 1.0), (1, "fifth", 0.55), (2, "top", 0.75), (3, "fifth", 0.85), (4, "third_hi", 0.6), (5, "fifth", 0.5)]
MAR_B = [(0, "root", 1.0), (1, "fifth", 0.5), (2, "third", 0.85), (3, "top", 0.5), (4, "fifth", 0.85), (5, "third_hi", 0.5)]


def compose_m10(rng):
	g = Grid([6] * 56)
	bpm = 300.0
	s = g.song(bpm, rng)
	chords = M10_INTRO + M10_A_CH + M10_B_CH + M10_A_CH + M10_CODA
	assert len(chords) == 56
	# --- melody & lines ---
	line(s, g, "lead", lambda f, d, v, r: V.reed(f, d, v, r, "oboe"), M10_MEL_A, 4, 0.7, 0.08, accents=ACC68, legato=0.92)
	line(s, g, "bsn", lambda f, d, v, r: V.reed(f, d, v, r, "bassoon", vib_cents=8.0), M10_MEL_B[:8], 20, 0.74, -0.1,
		transpose=-12, accents=ACC68, legato=0.95)
	line(s, g, "vln", V.violins, M10_MEL_B[8:], 28, 0.62, 0.15, accents=ACC68, legato=0.97)
	line(s, g, "bsn", lambda f, d, v, r: V.reed(f, d, v, r, "bassoon", vib_cents=8.0), M10_MEL_B[8:], 28, 0.45, -0.15,
		transpose=-12, legato=0.95)
	line(s, g, "lead", lambda f, d, v, r: V.reed(f, d, v, r, "oboe"), M10_MEL_A, 36, 0.74, 0.08, accents=ACC68, legato=0.92)
	line(s, g, "vln", lambda f, d, v, r: V.violins(f, d, v, r, attack=0.2, swell=0.35), M10_COUNTER_1, 36, 0.5, -0.25,
		legato=1.0)
	line(s, g, "vln", lambda f, d, v, r: V.violins(f, d, v, r, attack=0.2, swell=0.35), M10_COUNTER_2, 44, 0.52, -0.25,
		legato=1.0)
	line(s, g, "flute", M.flute, M10_MEL_A[8:], 44, 0.45, -0.2, accents=ACC68, legato=0.92)
	# coda: the thorn motif by the whole melody group, cadence C - B7 - Em
	line(s, g, "lead", lambda f, d, v, r: V.reed(f, d, v, r, "oboe"), M10_CODA_MEL, 52, 0.8, 0.08, accents=ACC68, legato=0.9)
	line(s, g, "flute", M.flute, M10_CODA_MEL, 52, 0.5, -0.2, legato=0.9)
	line(s, g, "vln", V.violins, M10_CODA_MEL, 52, 0.45, 0.2, transpose=-12, legato=0.9)
	for n in ("E4", "G4", "B4"):
		put(s, g, "vln", lambda f, d, v, r: V.violins(f, d, v, r, attack=0.08), n, 54, 0, 4.6, 0.5, -0.3, human=0.0)
	put(s, g, "bsn", lambda f, d, v, r: V.reed(f, d, v, r, "bassoon"), "E3", 54, 0, 4.6, 0.6, -0.1)
	# --- marimba ostinato (hemiola figure in B) ---
	for i, entry in enumerate(chords[:52]):
		pat = MAR_B if 20 <= i < 36 else MAR_A
		sec_vel = 0.42 if 20 <= i < 36 else (0.55 if i < 4 else 0.6)
		for sym, b0, nb in split_bar(entry, 6):
			t = tones_of(sym, 52)
			for e8, deg, vm in pat:
				if b0 <= e8 < b0 + nb:
					put(s, g, "mar", V.marimba, t[deg], i, e8, 1.0, sec_vel * vm, 0.3 if e8 % 2 else -0.15, human=0.003)
	# coda marimba: motif, arpeggios, a rolled final chord with a soft tremolo, then a pickup
	for k, n in enumerate(("E4", "E4", "B4")):
		put(s, g, "mar", V.marimba, n, 52, k, 1, 0.7, 0.0, human=0.002)
	for k, n in enumerate(("C4", "E4", "G4", "B3", "D#4", "F#4")):
		put(s, g, "mar", V.marimba, n, 53, k, 1, 0.6, 0.2 if k % 2 else -0.2, human=0.002)
	for k, n in enumerate(("E3", "B3", "E4", "G4", "B4", "E5")):
		put(s, g, "mar", V.marimba, n, 54, 0.12 * k, 2, 0.75 - 0.04 * k, -0.4 + 0.16 * k, human=0.0)
	for k in range(14):
		put(s, g, "mar", V.marimba, "E4" if k % 2 == 0 else "G4", 54, 1.0 + 0.25 * k, 0.3, 0.32 - 0.018 * k,
			-0.2 if k % 2 == 0 else 0.2, human=0.0, hard=0.3)
	for k, n in enumerate(("B3", "D#4", "F#4", "A4")):
		put(s, g, "mar", V.marimba, n, 55, 2 + k, 1, 0.35 + 0.1 * k, 0.1, human=0.002)
	# --- pizzicato chords ---
	for i, entry in enumerate(chords[:52]):
		if i < 2:
			continue
		for sym, b0, nb in split_bar(entry, 6):
			t = tones_of(sym, 60)
			spots = (0.0, 3.0) if 20 <= i < 36 else (2.0, 5.0)
			v = 0.35 if 20 <= i < 36 else 0.45
			for e8 in spots:
				if b0 <= e8 < b0 + nb:
					for deg in ("third", "fifth"):
						put(s, g, "pizz", V.pizz, t[deg], i, e8, 1.0, v, 0.35, human=0.004)
	# --- bass (upright pluck) ---
	for i, entry in enumerate(chords):
		if i >= 52:
			break
		pat = [(0, 2.7, "b"), (3, 2.7, "5")] if (i < 4 or 20 <= i < 36) else [(0, 2.6, "b"), (3, 1.8, "5"), (5, 0.9, "8")]
		for sym, b0, nb in split_bar(entry, 6):
			ci = chord_info(sym)
			bass = in_range(ci["bass"], 40)
			fifth = in_range((ci["root"] + 7) % 12, 40)
			for e8, nb8, deg in pat:
				if b0 <= e8 < b0 + nb:
					n = {"b": bass, "5": fifth, "8": bass + 12}[deg]
					put(s, g, "bass", M.pluck_bass, n, i, e8, nb8 if nb >= 6 or deg != "b" else min(nb8, nb), 0.8, 0.0)
	for bar, e8, n, nb8 in ((52, 0, "E2", 2.8), (53, 0, "C2", 2.8), (53, 3, "B1", 2.8), (54, 0, "E2", 5.5), (55, 3, "B1", 2.6)):
		put(s, g, "bass", M.pluck_bass, n, bar, e8, nb8, 0.85, 0.0)
	# --- string pad under B, and under the final chord ---
	chord_pad(s, g, "str", M.strings, M10_B_CH, 20, 55, 67, 0.36)
	chord_pad(s, g, "str", M.strings, ["Em"], 54, 55, 67, 0.4)
	# --- percussion ---
	for i in range(56):
		sec = "intro" if i < 4 else "A" if i < 20 else "B" if i < 36 else "A2" if i < 52 else "coda"
		if sec in ("intro", "A", "A2"):
			put(s, g, "taiko", V.taiko, 66.0, i, 0, 1, 0.85 if sec != "intro" else 0.7, 0.0, human=0.002)
			put(s, g, "taiko", V.taiko, 82.0, i, 3, 1, 0.55, 0.1, human=0.002)
			if i % 2 == 1:
				put(s, g, "taiko", V.taiko, 82.0, i, 5, 1, 0.35, -0.1, human=0.002)
			if i >= 2:
				for e8 in range(6):
					put(s, g, "tick", V.tick, 0.0, i, e8, 0.5, 0.32 if e8 in (0, 3) else 0.18, 0.35, human=0.002)
			if sec != "intro":
				put(s, g, "frame", V.frame_drum, 150.0, i, 3, 1, 0.6, -0.2, human=0.002)
				put(s, g, "frame", V.frame_drum, 170.0, i, 5, 1, 0.25, -0.2, human=0.002)
			if sec == "A2":
				put(s, g, "brush", V.brush, 0.0, i, 3, 1, 0.45, 0.15, human=0.002)
		elif sec == "B":
			put(s, g, "taiko", V.taiko, 70.0, i, 0, 1, 0.6, 0.0, human=0.002)
			put(s, g, "frame", V.frame_drum, 150.0, i, 3, 1, 0.35, -0.2, human=0.002)
			for e8 in (1, 2, 4, 5):
				s.note("shaker", M.shaker, 440.0, 0, g.at(i, e8), 0.5, 0.35 if e8 in (2, 5) else 0.25, 0.4, human=0.003)
	for bar in (3, 11, 19, 27, 43, 51):
		for k, e8 in enumerate((3.0, 4.0, 4.5, 5.0, 5.5)):
			put(s, g, "frame", V.frame_drum, 160.0 + 12 * k, bar, e8, 0.5, 0.35 + 0.1 * k, 0.2, human=0.002)
	for k, e8 in enumerate((0, 1, 2, 3, 4, 5)):          # end of B: a bigger build back into A'
		put(s, g, "taiko", V.taiko, 60.0 + 4 * k, 35, e8, 1, 0.45 + 0.08 * k, 0.0, human=0.002)
	for e8 in (0, 1, 2):                                  # coda hits with the motif
		put(s, g, "taiko", V.taiko, 64.0, 52, e8, 1, 0.8, 0.0, human=0.0)
		put(s, g, "frame", V.frame_drum, 150.0, 52, e8, 1, 0.5, -0.2, human=0.0)
	put(s, g, "taiko", V.taiko, 70.0, 53, 0, 1, 0.7, 0.0)
	put(s, g, "taiko", V.taiko, 62.0, 53, 3, 1, 0.75, 0.0)
	put(s, g, "taiko", V.taiko, 55.0, 54, 0, 1, 1.0, 0.0, human=0.0)
	s.note("swell", M.swell, 1000.0, 0, g.at(53, 0), 6.0, 0.6, 0.0, human=0.0)
	for k, e8 in enumerate((0, 2, 3, 4, 4.5, 5, 5.5)):     # drum pickup into the intro (loop seam)
		put(s, g, "frame", V.frame_drum, 150.0 + 10 * k, 55, e8, 0.5, 0.3 + 0.08 * k, 0.15, human=0.002)
	put(s, g, "taiko", V.taiko, 82.0, 55, 3, 1, 0.55, 0.0)
	put(s, g, "taiko", V.taiko, 70.0, 55, 5, 1, 0.7, 0.0)
	ir = S.hall(rng, 1.7, brightness=6500)
	levels = {"lead": (2.0, 0.22), "bsn": (0.0, 0.2), "vln": (-1.0, 0.3), "flute": (-11.0, 0.3), "mar": (-9.0, 0.18),
		"pizz": (-8.0, 0.2), "bass": (-6.5, 0.08), "str": (-13.0, 0.35), "taiko": (-6.5, 0.12), "frame": (-8.0, 0.12),
		"tick": (4.0, 0.1), "brush": (-8.0, 0.15), "shaker": (-8.0, 0.1), "swell": (-16.0, 0.4)}
	x = finish(s, levels, ir)
	sections = [("intro", g.sec(0, bpm)), ("A", g.sec(4, bpm)), ("B", g.sec(20, bpm)), ("A'", g.sec(36, bpm)),
		("coda", g.sec(52, bpm))]
	return x, sections, dict(s.bus_lu)


# ------------------------------------------------------------------------------------------
# m11  The Last Shift  (Old Mine / Tobin annex)
# ------------------------------------------------------------------------------------------
# G minor, 4/4 at 60 (bar = 4 s), 36 bars = 144 s.
# A 0-11: lopsided low pulse (beat 1 and the "and" of 2) under a dark bowed drone; single struck
#   pipe notes spell the Last-Shift motif D5 - Bb4 A4 - G4 D5 - C5 with long rests.
# B 12-23: the pulse slows to half-notes; a low cello line (F D Bb, A G F G ...) sings Tobin's
#   lament through Bb - F/A - Abmaj7 - Cm/Eb - D7b9; the pipe only answers at phrase ends.
# A' 24-35: the motif returns, varied (G5 instead of G4, softer celesta echoes), the pulse
#   thins out and stops for the last two bars so the loop breathes before it begins again.

M11_CH = (["Gmadd9"] * 4 + ["Ebmaj7"] * 4 + ["Cm9"] * 2 + ["D7sus4", "D"] +
	["Bb"] * 2 + ["Bb/D"] * 2 + ["F/A"] * 2 + ["Abmaj7"] * 2 + ["Cm/Eb"] * 2 + ["D7b9"] * 2 +
	["Gmadd9"] * 4 + ["Ebmaj7"] * 4 + ["Cm"] * 2 + ["D7sus4"] * 2)
M11_PAD = [(0, 12, "Gmadd9", {"cutoff": 650.0}), (4, 10, "Ebmaj7", {"cutoff": 650.0}), (8, 7, "Cm9", {"cutoff": 650.0}),
	(10, 4.3, "D7sus4", {"cutoff": 650.0}), (11, 4.3, "D", {"cutoff": 650.0}),
	(12, 8.3, "Bb", {"cutoff": 800.0, "trem": 0.25}), (14, 8.3, "Bb/D", {"cutoff": 800.0, "trem": 0.25}),
	(16, 8.3, "F/A", {"cutoff": 800.0, "trem": 0.25}), (18, 8.3, "Abmaj7", {"cutoff": 800.0, "trem": 0.25}),
	(20, 8.3, "Cm/Eb", {"cutoff": 800.0, "trem": 0.25}), (22, 8.3, "D7b9", {"cutoff": 800.0, "trem": 0.25}),
	(24, 12, "Gmadd9", {"cutoff": 700.0, "pont": 0.3}), (28, 10, "Ebmaj7", {"cutoff": 700.0, "pont": 0.3}),
	(32, 7, "Cm", {"cutoff": 700.0, "pont": 0.3}), (34, 8, "D7sus4", {"cutoff": 700.0, "pont": 0.3})]
M11_PIPE_A = [(1, 0, "D5", 0.7), (2, 0, "Bb4", 0.6), (2, 2, "A4", 0.55), (4, 0, "G4", 0.6), (4, 1.5, "D5", 0.5),
	(5, 0, "C5", 0.6), (7, 2, "Bb4", 0.45), (8, 0, "Eb5", 0.6), (8, 1, "D5", 0.5), (8, 2, "C5", 0.5), (9, 0, "G4", 0.55),
	(10, 0, "A4", 0.5), (11, 2, "F#4", 0.5)]
M11_PIPE_B = [(13, 2, "F5", 0.42), (15, 2.5, "D5", 0.38), (17, 2, "C5", 0.42), (19, 2, "G5", 0.34), (21, 2, "Eb5", 0.4),
	(23, 2, "F#5", 0.34)]
M11_PIPE_A2 = [(25, 0, "D5", 0.65), (26, 0, "Bb4", 0.55), (26, 2, "A4", 0.5), (28, 0, "G5", 0.55), (28, 1.5, "D5", 0.45),
	(29, 0, "Bb4", 0.5), (31, 2, "A4", 0.45), (32, 0, "C5", 0.55), (32, 1, "Eb5", 0.45), (32, 2, "D5", 0.45),
	(34, 0, "G4", 0.45)]
M11_CELLO = [
	[("F3", 2), ("D3", 2)], [("Bb3", 4)], [("A3", 2), ("G3", 1), ("F3", 1)], [("G3", 4)],
	[("A3", 3), ("C4", 1)], [("F3", 4)], [("Eb4", 2), ("C4", 2)], [("G3", 4)],
	[("G3", 2), ("Eb3", 2)], [("C4", 3), ("Bb3", 1)], [("A3", 2), ("F#3", 2)], [("Eb3", 2), ("D3", 2)],
]


def compose_m11(rng):
	g = Grid([4] * 36)
	bpm = 60.0
	s = g.song(bpm, rng, tail=10.0)
	# drone: dark bowed pad. In A and A' each harmony is held for less than its span, so the
	# drone breathes out (the cave reverb carries the gap); in B it sustains under the lament.
	# A' gets a faint glassy ponticello edge.
	prev = None
	for bar, nb, sym, kw in M11_PAD:
		ci = chord_info(sym)
		v = M.voice_lead(prev, [ci["root"] + iv for iv in ci["ivs"]], 43, 60)
		prev = v
		for n in v:
			s.note("pad", lambda f, d, vv, r, kw=kw: V.bowed_pad(f, d, vv, r, attack=3.0, release=3.5, **kw), n, 0,
				g.at(bar), nb, 0.42, 0.0, human=0.0)
	# low restrained pulses (C2..B2 region, felt more than heard); phrase ends skip the off-beat
	for i, sym in enumerate(M11_CH):
		root = in_range(chord_info(sym)["bass"], 36)
		if i < 12 or 24 <= i < 32:
			first = 0.55 if i == 0 else 0.75
			put(s, g, "pulse", V.felt_pulse, root, i, 0, 1, first, 0.0, human=0.0)
			if i not in (3, 7, 27, 31):
				put(s, g, "pulse", V.felt_pulse, root, i, 1.5, 1, first * 0.56, 0.0, human=0.0)
		elif i < 24:
			put(s, g, "pulse", V.felt_pulse, root, i, 0, 1, 0.55, 0.0, human=0.0, decay=1.3)
			put(s, g, "pulse", V.felt_pulse, root, i, 2, 1, 0.32, 0.0, human=0.0, decay=1.3)
		elif i < 34:
			put(s, g, "pulse", V.felt_pulse, root, i, 0, 1, 0.5, 0.0, human=0.0, decay=1.4)
		else:                                   # the breath: the pulse fades and leads back to bar 0
			put(s, g, "pulse", V.felt_pulse, root, i, 0, 1, 0.4 if i == 34 else 0.3, 0.0, human=0.0, decay=1.4)
			if i == 35:
				put(s, g, "pulse", V.felt_pulse, root, i, 2, 1, 0.24, 0.0, human=0.0, decay=1.4)
	# the struck-pipe motif (isolated metal notes)
	for bar, beat, n, v in M11_PIPE_A + M11_PIPE_B + M11_PIPE_A2:
		put(s, g, "pipe", V.pipe, n, bar, beat, 2, v, float(rng.uniform(-0.45, 0.45)), human=0.01)
	# A': distant celesta echoes of the pipe, an octave up, softly
	for bar, beat, n, v in M11_PIPE_A2:
		put(s, g, "cel", M.celesta, M.midi(n) + 12, bar, beat + 1.5, 1, v * 0.4, 0.5, human=0.01)
	# B: Tobin's lament on a low bowed line
	line(s, g, "cello", lambda f, d, v, r: V.violins(f, d, v, r, attack=0.5, release=0.8, vib_cents=9.0, swell=0.4,
		voices=3, bright=0.3), M11_CELLO, 12, 0.6, -0.15, legato=1.0, human=0.01)
	ir = S.cave(rng, 3.8, brightness=3200)
	levels = {"pad": (-8.0, 0.4), "pulse": (-6.0, 0.12), "pipe": (1.0, 0.55), "cel": (-8.0, 0.6), "cello": (-3.0, 0.35)}
	x = finish(s, levels, ir, hp=28.0, lp=12000.0)
	sections = [("A", 0.0), ("B", g.sec(12, bpm)), ("A'", g.sec(24, bpm)), ("breath", g.sec(34, bpm))]
	return x, sections, dict(s.bus_lu)


# ------------------------------------------------------------------------------------------
# m12  Eyes That Stay Shut  (Ruins / Silk approach)
# ------------------------------------------------------------------------------------------
# Octatonic around B (B C D Eb F F# G# A), 3/4 at 48 (bar = 3.75 s), 36 bars = 135 s.
# Bell motif: B - C - F (a semitone, then a tritone): an eye that tries to open. "Eyes" = the
# F5 + B5 tritone dyad. Fragments stop short ("stay shut") and leave real silence.
# A 0-11: pedal B, slow bowed clusters (B F# C / B F A / C G B / B D F C), motif fragments;
#   bars 10-11 fall away to near silence, then the eyes dyad alone.
# B 12-23: the pedal moves a tritone to F; a bowed-glass line sinks chromatically E5 -> B4 while
#   the bells answer with the motif upside down (F - E - Bb); bars 22-23 near silence + one low bell.
# A' 24-33: back on B, the texture opens to a hollow fifth B-F# before the flat ninth creeps back;
#   the motif returns with the eyes dyad; coda 34-35 a last bowed-glass B and the loop.

M12_CLUSTERS = [(0, 2, ["B2", "F#3", "C4"]), (2, 2, ["B2", "F3", "A3"]), (4, 2, ["C3", "G3", "B3"]),
	(6, 2, ["B2", "D3", "F3", "C4"]), (8, 2, ["B2", "F#3", "C4"]),
	(12, 2, ["F2", "C3", "F#3"]), (14, 2, ["F2", "B2", "E3"]), (16, 2, ["F2", "C3", "Db3"]), (18, 2, ["E2", "B2", "F3"]),
	(20, 2, ["F#2", "C#3", "G3"]),
	(24, 2, ["B2", "F#3"]), (26, 2, ["B2", "F#3", "B3"]), (28, 2, ["B2", "F3", "A3"]), (30, 2, ["C3", "G3", "B3"]),
	(32, 2, ["B2", "F#3", "C4"]), (34, 2, ["B2", "F#3"])]
M12_PEDAL = [(0, 10, "B1", 0.5), (12, 10, "F2", 0.42), (24, 12, "B1", 0.5)]
M12_BELLS = [
	(0, 1, "B4", 0.6), (0, 2, "C5", 0.5), (1, 1, "F5", 0.55),
	(3, 0, "B4", 0.5), (3, 1, "C5", 0.45),
	(5, 0, "F5", 0.45), (5, 0.03, "B5", 0.34),
	(7, 0, "G#4", 0.45), (7, 1, "A4", 0.4), (7, 2, "D5", 0.45),
	(9, 0, "B4", 0.55), (9, 1, "C5", 0.5), (9, 2, "F5", 0.5),
	(11, 1, "F5", 0.34), (11, 1.03, "B5", 0.27),
	(13, 1, "F5", 0.45), (13, 2, "E5", 0.4), (14, 1, "Bb4", 0.45),
	(17, 0, "C5", 0.35), (17, 1, "B4", 0.3),
	(19, 2, "G#5", 0.32),
	(21, 0, "F5", 0.4), (21, 1, "E5", 0.35), (21, 2, "Bb4", 0.4),
	(23, 1, "B3", 0.5),
	(24, 1, "B4", 0.55), (24, 2, "C5", 0.48), (25, 1, "F5", 0.5),
	(26, 1, "B4", 0.5), (26, 2, "C5", 0.45), (27, 1, "F5", 0.45), (27, 1.03, "B5", 0.34),
	(29, 0, "G#4", 0.45), (29, 1, "A4", 0.4), (29, 2, "D5", 0.45),
	(31, 0, "D5", 0.45), (31, 1, "D#5", 0.42), (31, 2, "A5", 0.4),
	(33, 0, "B4", 0.45), (33, 1, "C5", 0.4),
]
M12_GLASS = [(12, 0, 7.0, "E5", 0.5), (14, 1, 4.0, "D#5", 0.48), (16, 0, 5.0, "D5", 0.48), (17, 2, 3.0, "C#5", 0.46),
	(19, 0, 4.0, "C5", 0.46), (20, 1, 5.0, "B4", 0.5), (34, 0, 5.5, "B4", 0.35)]


def compose_m12(rng):
	g = Grid([3] * 36)
	bpm = 48.0
	s = g.song(bpm, rng, tail=11.0)
	for bar, nbars, notes in M12_CLUSTERS:
		pont = 0.5 if bar < 12 else 0.35 if bar < 24 else 0.2
		for k, n in enumerate(notes):
			put(s, g, "bow", lambda f, d, v, r, p=pont: V.bowed_pad(f, d, v, r, attack=2.4, release=3.2, cutoff=900.0,
				pont=p, trem=0.35), n, bar, 0.0, 3 * nbars - 0.6, 0.42 - 0.03 * k, -0.5 + 0.5 * k, human=0.0)
	for bar, nbars, n, v in M12_PEDAL:
		put(s, g, "pedal", lambda f, d, vv, r: V.bowed_pad(f, d, vv, r, attack=4.0, release=4.0, cutoff=300.0, voices=3,
			detune=3.0),
			n, bar, 0.0, 3 * nbars - 1.0, v, 0.0, human=0.0)
	for bar, beat, n, v in M12_BELLS:
		pan = {"B": -0.35, "C": 0.3, "F": 0.1, "G": -0.2, "A": 0.25, "D": -0.1, "E": 0.35}.get(n[0], 0.0)
		put(s, g, "bell", V.ruin_bell, n, bar, beat, 2, v, pan, human=0.012)
	for bar, beat, nb, n, v in M12_GLASS:
		put(s, g, "glass", lambda f, d, vv, r: V.bowed_metal(f, d, vv, r, attack=1.6, release=2.5, t60=1.4, rough=0.5),
			n, bar, beat, nb, v, 0.2, human=0.0)
	ir = S.hall(rng, 4.6, brightness=4200)
	levels = {"bow": (-5.0, 0.45), "pedal": (-7.0, 0.3), "bell": (-1.0, 0.5), "glass": (-7.0, 0.5)}
	x = finish(s, levels, ir, hp=30.0, lp=12000.0)
	sections = [("A", 0.0), ("space", g.sec(10, bpm)), ("B", g.sec(12, bpm)), ("space", g.sec(22, bpm)),
		("A'", g.sec(24, bpm)), ("coda", g.sec(34, bpm))]
	return x, sections, dict(s.bus_lu)


# ------------------------------------------------------------------------------------------
# m13  Boss phase layers for music_boss.wav ("The Thread Above")
# ------------------------------------------------------------------------------------------
# music_boss (tools/audio/music_tracks.py): Song(120 bpm, 4/4, 30 bars) = 60.000 s = 2 646 000
# frames at 44.1 kHz, D minor. Chords: Dm Dm | A: Dm A/C# Bb A Dm A/C# Gm A | B: Bb C Dm Dm Bb C Eb A
# | A again | breakdown Dm Dm Dm | A. Horn motif A3 D4 C#4 Bb3 A3 in bars 2-9 and 18-25, B-melody
# 10-17. Both layers use exactly that grid (same Song length, same bar/beat -> time mapping).
# Layer 2 (urgency): 16th-note spiccato arpeggios in 3+3+2, dark ticks, backbeat brush, a deep
#   taiko that syncopates against the boss toms, snare rolls into each section; a ticking clock and
#   repeated D's in the breakdown; a full-bar roll into the loop start.
# Layer 3 (desperation): a violin counter-melody that moves where the horn holds (F-Eb-F-A cell,
#   b9 sighs over A, a climb to F6 in the B section) plus low brass fp/swells on every bar; in the
#   breakdown the violins sing a lone Phrygian descent A5 G5 F5 Eb5 D5 (C#5); bar 29 swells into
#   the loop. Both layers keep the boss's b2 (Eb) on Dm bars - see M13_COUNTER.

BOSS_CHORDS = ["Dm", "Dm"] + ["Dm", "A/C#", "Bb", "A", "Dm", "A/C#", "Gm", "A"] + \
	["Bb", "C", "Dm", "Dm", "Bb", "C", "Eb", "A"] + ["Dm", "A/C#", "Bb", "A", "Dm", "A/C#", "Gm", "A"] + ["Dm", "Dm", "Dm", "A"]
# Over every Dm bar music_boss colours D minor with a flat second: its ostinato plays Eb3 on beat 3
# and its 'rub' pad holds Eb4 all bar (music_tracks.py OSTINATO["D"], the root+1 rub). The layers
# therefore use Eb, never E natural, on Dm bars (review fix: E5 used to sound against the boss's
# Eb3 at the same instant in bars 1, 2, 6 and 28). E natural stays where the boss chord is A.
M13_COUNTER = [
	[("D5", 3), ("Eb5", 1)], [("F5", 2), ("Eb5", 1), ("D5", 1)],
	[("r", 1), ("F5", 1), ("Eb5", 0.5), ("F5", 0.5), ("A5", 1)], [("G5", 2), ("E5", 1), ("C#5", 1)],
	[("D5", 1.5), ("F5", 0.5), ("Bb5", 2)], [("A5", 1), ("G5", 0.5), ("F5", 0.5), ("E5", 2)],
	[("r", 1), ("F5", 1), ("Eb5", 0.5), ("F5", 0.5), ("A5", 1)], [("Bb5", 2), ("A5", 1), ("G5", 1)],
	[("F5", 1), ("E5", 0.5), ("D5", 0.5), ("G5", 2)], [("E5", 2), ("C#5", 1), ("A4", 1)],
	[("D6", 1.5), ("C6", 0.5), ("Bb5", 1), ("A5", 1)], [("G5", 3), ("E5", 1)],
	[("D6", 1.5), ("Eb6", 0.5), ("F6", 2)], [("Eb6", 1), ("D6", 1), ("A5", 2)],
	[("Bb5", 1), ("A5", 0.5), ("G5", 0.5), ("F5", 2)], [("E5", 1), ("G5", 1), ("C6", 2)],
	[("Bb5", 2), ("G5", 1), ("Eb5", 1)], [("C#5", 1), ("E5", 1), ("G5", 1), ("Bb5", 1)],
	[("D6", 1), ("C#6", 0.5), ("D6", 0.5), ("A5", 2)], [("G5", 2), ("E5", 1), ("C#5", 1)],
	[("D5", 1.5), ("F5", 0.5), ("Bb5", 2)], [("A5", 1), ("G5", 0.5), ("F5", 0.5), ("E5", 2)],
	[("A5", 1), ("D6", 1), ("F6", 2)], [("E6", 2), ("C#6", 1), ("A5", 1)],
	[("Bb5", 2), ("A5", 1), ("G5", 1)], [("F5", 1), ("E5", 1), ("C#5", 2)],
	[("A5", 4)], [("G5", 2), ("F5", 2)], [("Eb5", 3), ("D5", 1)], [("C#5", 2), ("E5", 2)],
]
# Upper neighbour added to the layer-2 arpeggios in the B section: the same neighbour music_boss's
# ostinato uses on that chord (b2 on D and A, 9th on Bb, G, C and Eb).
NINTH = {"D": 1, "A": 1, "Bb": 2, "G": 2, "C": 2, "Eb": 2}


def _boss_grid():
	return Grid([4] * 30)


def compose_m13_layer2(rng):
	g = _boss_grid()
	bpm = 120.0
	s = g.song(bpm, rng)
	prev = None
	for i, sym in enumerate(BOSS_CHORDS):
		ci = chord_info(sym)
		v3 = M.voice_lead(prev, [ci["root"] + iv for iv in ci["ivs"]], 64, 77)
		prev = v3
		lo_, mid_, hi_ = v3[0], v3[1], v3[-1]
		breakdown = 26 <= i <= 28
		if breakdown:
			for e in range(8):              # repeated D's, quiet and insistent
				put(s, g, "spicc", V.spicc, "D4" if e % 2 == 0 else "D5", i, 0.5 * e, 0.25, 0.3 if e % 2 == 0 else 0.2,
					-0.2 if e % 2 else 0.2, human=0.002)
			continue
		bsec = 10 <= i <= 17
		n9 = in_range((ci["root"] + NINTH[ci["name"]]) % 12, hi_ - 5)
		half = [hi_, mid_, lo_, hi_, mid_, lo_, hi_, mid_] if not bsec else [lo_, mid_, hi_, lo_, mid_, hi_, n9, mid_]
		base = 0.42 if i < 2 else (0.5 if not bsec else 0.54)
		if i == 29:
			base = 0.3
		for step in range(16):
			k = step % 8
			acc = k in (0, 3, 6)
			v = base * (1.0 if acc else 0.62)
			if i == 29:
				v = (0.25 + 0.5 * step / 15.0) * (1.0 if acc else 0.7)
			put(s, g, "spicc", V.spicc, half[k], i, 0.25 * step, 0.22, v, 0.35 if step % 2 else -0.35, human=0.002)
	# percussion
	for i in range(30):
		breakdown = 26 <= i <= 28
		if breakdown:
			for e in range(8):
				put(s, g, "tick", V.tick, 0.0, i, 0.5 * e, 0.25, 0.14 if e % 2 == 0 else 0.1, 0.4, human=0.001)
			continue
		if i < 29:
			for step in range(16):
				k = step % 8
				put(s, g, "tick", V.tick, 0.0, i, 0.25 * step, 0.2, 0.3 if k in (0, 3, 6) else 0.14, 0.4, human=0.001)
		if 2 <= i <= 25:
			put(s, g, "taiko", V.taiko, 64.0, i, 0.0, 1, 0.8 if i % 2 == 0 else 0.6, 0.0, human=0.001)
			put(s, g, "taiko", V.taiko, 72.0, i, 2.5, 1, 0.45, 0.0, human=0.001)
			if 10 <= i <= 17:
				put(s, g, "taiko", V.taiko, 76.0, i, 3.5, 1, 0.35, 0.0, human=0.001)
			for b in (1.0, 3.0):
				put(s, g, "brush", V.brush, 0.0, i, b, 0.5, 0.5, -0.15, human=0.002)
			put(s, g, "brush", V.brush, 0.0, i, 3.75, 0.25, 0.18, -0.15, human=0.002)
	put(s, g, "taiko", V.taiko, 62.0, 26, 0.0, 1, 0.5, 0.0, human=0.0)
	rolls = [(1, 2.0, 4.0, 0.15, 0.7), (9, 3.0, 4.0, 0.25, 0.6), (17, 2.0, 4.0, 0.15, 0.7), (25, 3.0, 4.0, 0.2, 0.55)]
	for bar, b0, b1, v0, v1 in rolls:
		steps = int((b1 - b0) / 0.125)
		for k in range(steps):
			put(s, g, "roll", V.roll_hit, 0.0, bar, b0 + 0.125 * k, 0.125, v0 + (v1 - v0) * k / max(steps - 1, 1),
				0.1 if k % 2 else -0.1, human=0.001)
	for k in range(24):                     # bar 29: the whole bar builds back into the loop start
		b = 0.25 * k if k < 8 else 2.0 + 0.125 * (k - 8)
		put(s, g, "roll", V.roll_hit, 0.0, 29, b, 0.125, 0.12 + 0.75 * k / 23.0, 0.1 if k % 2 else -0.1, human=0.001)
	for b, v in ((2.0, 0.5), (3.0, 0.65), (3.5, 0.8)):
		put(s, g, "taiko", V.taiko, 64.0, 29, b, 1, v, 0.0, human=0.0)
	ir = S.hall(rng, 2.2, brightness=5000)
	levels = {"spicc": (2.0, 0.22), "tick": (-2.0, 0.12), "taiko": (-10.0, 0.12), "brush": (-6.0, 0.15), "roll": (-8.0, 0.15)}
	x = finish(s, levels, ir)
	return x, dict(s.bus_lu)


def compose_m13_layer3(rng):
	g = _boss_grid()
	bpm = 120.0
	s = g.song(bpm, rng)
	vl = lambda f, d, v, r: V.violins(f, d, v, r, attack=0.1, vib_cents=16.0, swell=0.25, voices=5, bright=0.55)  # noqa: E731
	line(s, g, "vln", vl, M13_COUNTER[:26], 0, 0.62, 0.25, legato=0.98, accents={0.0: 0.05}, human=0.004)
	lament = lambda f, d, v, r: V.violins(f, d, v, r, attack=0.35, vib_cents=18.0, swell=0.5, voices=5, bright=0.45)  # noqa: E731
	line(s, g, "vln", lament, M13_COUNTER[26:], 26, 0.5, 0.25, legato=1.0, human=0.004)
	# low brass: a 2-bar swell into the first motif, fp-crescendo bars in A, swells in B
	for i, sym in enumerate(BOSS_CHORDS):
		if 26 <= i <= 28 or i == 1:
			continue
		ci = chord_info(sym)
		bass = in_range(ci["bass"], 36)
		upper = in_range(ci["root"], bass + 3) if ci["bass"] != ci["root"] else in_range((ci["root"] + 7) % 12, bass + 5)
		if i == 0:
			shape, nb, v = "swell", 7.8, 0.5
		elif i == 29:
			shape, nb, v = "swell", 4.0, 0.72
		elif 10 <= i <= 17:
			shape, nb, v = "swell", 3.9, 0.58
		else:
			shape, nb, v = "fp", 3.85, 0.6
		for k, n in enumerate((bass, upper)):
			put(s, g, "brass", lambda f, d, vv, r, sh=shape: V.low_brass(f, d, vv, r, shape=sh), n, i, 0.0, nb,
				v * (1.0 if k == 0 else 0.8), -0.25 if k == 0 else 0.25, human=0.003)
		if i == 29:
			put(s, g, "brass", lambda f, d, vv, r: V.low_brass(f, d, vv, r, shape="swell"), "A1", i, 0.0, 4.0, 0.5, 0.0)
	ir = S.hall(rng, 2.2, brightness=5000)
	levels = {"vln": (0.0, 0.32), "brass": (-6.0, 0.22)}
	x = finish(s, levels, ir)
	return x, dict(s.bus_lu)


# ------------------------------------------------------------------------------------------
# m25  No Thread Left Unseen  (Weaver's Crossing rematch)
# ------------------------------------------------------------------------------------------
# C minor. Eighth = 300/min. Mixed meter: 7/8 (2+2+3) with a 4/4 middle section.
# intro 0-3 (7/8, the skitter ostinato alone, then drums) | A 4-19 (7/8, violins: the "thread"
# theme C-G-F-Eb-D, snagging on repeated falls) | A2 20-27 (7/8, low bassoon/cello line with
# oboe "snag" answers falling in sequence) | B 28-43 (4/4, broadening: low brass nods to the boss
# motif (5-1-7 ...) under a new soaring violin line, 16th-note pluck threads above) | C 44-51
# (7/8 breakdown: pedal C, a ponticello line sinking chromatically G5 -> C5, heartbeat pulses,
# ticks multiplying) | A' 52-67 (7/8 theme in violins + oboe with brass stabs) | T 68-69 (4/4,
# G7b9 build back into the intro). 70 bars, 508 eighths = 101.6 s.

M25_METERS = [7] * 28 + [8] * 16 + [7] * 24 + [8] * 2
M25_INTRO_CH = ["Cm", "Cm", "Cm", "G"]
M25_A_CH = ["Cm", "Cm", "Ab", "G", "Cm", "Cm", "Fm", "G", "Ab", "Bb", "Cm", "Fm", "Db", "G", "Ab", "G7"]
M25_A2_CH = ["Cm", "Bb", "Ab", "G", "Cm", "Bb", "Ab", "G"]
M25_B_CH = ["Cm", "G/B", "Ab", "G", "Cm", "G/B", "Fm/Ab", "G", "Eb", "Bb/D", "Cm", "Ab", "Fm", "Db", "G", "G"]
M25_C_CH = ["Cm"] * 8
M25_T_CH = ["G7b9", "G7b9"]
M25_THEME = [
	[("C5", 2), ("G5", 2), ("F5", 1), ("Eb5", 1), ("D5", 1)],
	[("Eb5", 2), ("C5", 2), ("G4", 3)],
	[("Ab4", 2), ("Eb5", 2), ("D5", 1), ("C5", 1), ("Bb4", 1)],
	[("B4", 2), ("C5", 1), ("D5", 1), ("G4", 3)],
	[("C5", 2), ("G5", 2), ("F5", 1), ("Eb5", 1), ("D5", 1)],
	[("Eb5", 2), ("G5", 2), ("C6", 3)],
	[("Ab5", 2), ("G5", 1), ("F5", 1), ("Eb5", 1), ("D5", 1), ("C5", 1)],
	[("D5", 2), ("B4", 2), ("G4", 3)],
	[("Eb5", 2), ("Ab5", 2), ("G5", 1), ("F5", 1), ("Eb5", 1)],
	[("F5", 2), ("Bb5", 2), ("Ab5", 1), ("G5", 1), ("F5", 1)],
	[("G5", 2), ("C6", 2), ("Bb5", 1), ("Ab5", 1), ("G5", 1)],
	[("Ab5", 2), ("F5", 2), ("C5", 3)],
	[("Db5", 2), ("F5", 2), ("Ab5", 3)],
	[("G5", 2), ("F5", 1), ("Eb5", 1), ("D5", 3)],
	[("C5", 2), ("Eb5", 2), ("D5", 1), ("C5", 1), ("B4", 1)],
	[("B4", 2), ("D5", 2), ("F5", 3)],
]
M25_A2_LOW = [
	[("C3", 2), ("Eb3", 2), ("G3", 3)], [("F3", 2), ("D3", 2), ("Bb2", 3)], [("Ab2", 2), ("C3", 2), ("Eb3", 3)],
	[("D3", 2), ("B2", 2), ("G2", 3)], [("C3", 2), ("G3", 2), ("C4", 3)], [("Bb3", 2), ("F3", 2), ("D3", 3)],
	[("C4", 2), ("Ab3", 2), ("Eb3", 3)], [("B2", 2), ("D3", 2), ("G3", 1), ("F3", 1), ("D3", 1)],
]
M25_SNAGS = [("G5", "F5", "Eb5"), ("F5", "Eb5", "D5"), ("Eb5", "D5", "C5"), ("D5", "C5", "B4"),
	("G5", "F5", "Eb5"), ("F5", "Eb5", "D5"), ("Eb5", "D5", "C5"), None]
M25_B_BRASS = [
	[("G2", 2), ("C3", 6)], [("B2", 6), ("D3", 2)], [("Ab2", 4), ("C3", 4)], [("G2", 8)],
	[("G2", 2), ("C3", 6)], [("D3", 4), ("B2", 4)], [("Ab2", 4), ("F2", 4)], [("G2", 8)],
	[("Eb2", 8)], [("D2", 8)], [("C2", 4), ("G2", 4)], [("Ab2", 8)],
	[("F2", 8)], [("Db2", 8)], [("G2", 8)], [("G2", 4), ("B2", 4)],
]
M25_B_VLN = [
	[("Eb5", 4), ("D5", 2), ("C5", 2)], [("D5", 6), ("G5", 2)], [("C6", 4), ("Bb5", 2), ("Ab5", 2)], [("G5", 8)],
	[("Eb5", 4), ("F5", 2), ("G5", 2)], [("Ab5", 4), ("G5", 2), ("F5", 2)], [("F5", 4), ("Eb5", 2), ("D5", 2)],
	[("D5", 6), ("r", 2)],
	[("G5", 4), ("Bb5", 4)], [("Ab5", 4), ("F5", 4)], [("G5", 2), ("Eb5", 2), ("C6", 4)], [("C6", 4), ("Eb6", 2), ("D6", 2)],
	[("C6", 4), ("Ab5", 2), ("F5", 2)], [("F5", 4), ("Ab5", 2), ("Db6", 2)], [("B5", 8)], [("D6", 4), ("B5", 2), ("G5", 2)],
]
M25_C_LINE = ["G5", "F#5", "F5", "E5", "Eb5", "D5", "Db5", "C5"]
SKITTER = {
	"C": ["C4", "C4", "G4", "C4", "Ab4", "G4", "Eb4"], "G": ["G3", "G3", "D4", "G3", "Eb4", "D4", "B3"],
	"Ab": ["Ab3", "Ab3", "Eb4", "Ab3", "F4", "Eb4", "C4"], "F": ["F3", "F3", "C4", "F3", "Db4", "C4", "Ab3"],
	"Bb": ["Bb3", "Bb3", "F4", "Bb3", "G4", "F4", "D4"], "Db": ["Db4", "Db4", "Ab4", "Db4", "Bb4", "Ab4", "F4"],
	"Eb": ["Eb4", "Eb4", "Bb4", "Eb4", "C5", "Bb4", "G4"],
}
ACC78 = {0.0: 0.08, 2.0: 0.04, 4.0: 0.06}


def compose_m25(rng):
	g = Grid(M25_METERS)
	bpm = 300.0
	s = g.song(bpm, rng)
	chords = M25_INTRO_CH + M25_A_CH + M25_A2_CH + M25_B_CH + M25_C_CH + M25_A_CH + M25_T_CH
	assert len(chords) == len(M25_METERS) == 70 and g.total == 508
	vln = lambda f, d, v, r: V.violins(f, d, v, r, attack=0.05, vib_cents=13.0, voices=5, bright=0.65)  # noqa: E731
	oboe = lambda f, d, v, r: V.reed(f, d, v, r, "oboe")  # noqa: E731
	bsn = lambda f, d, v, r: V.reed(f, d, v, r, "bassoon", vib_cents=7.0)  # noqa: E731
	# --- melodies ---
	line(s, g, "vln", vln, M25_THEME, 4, 0.66, 0.2, accents=ACC78, legato=0.88)
	line(s, g, "oboe", oboe, M25_THEME[8:], 12, 0.42, -0.15, transpose=-12, accents=ACC78, legato=0.88)
	line(s, g, "low", bsn, M25_A2_LOW, 20, 0.72, -0.15, accents=ACC78, legato=0.9)
	line(s, g, "low", lambda f, d, v, r: V.violins(f, d, v, r, attack=0.06, voices=3, bright=0.4), M25_A2_LOW, 20, 0.5,
		0.2, accents=ACC78, legato=0.9)
	for k, sn in enumerate(M25_SNAGS):
		if sn:
			for j, n in enumerate(sn):
				put(s, g, "oboe", oboe, n, 20 + k, 4 + j, 0.9, 0.58 - 0.06 * j, 0.25)
	line(s, g, "brass", lambda f, d, v, r: V.low_brass(f, d, v, r, shape="hairpin"), M25_B_BRASS, 28, 0.62, 0.0,
		legato=0.98, human=0.004)
	line(s, g, "vln", lambda f, d, v, r: V.violins(f, d, v, r, attack=0.18, vib_cents=15.0, swell=0.3, voices=5),
		M25_B_VLN, 28, 0.6, 0.2, legato=0.99)
	for k, n in enumerate(M25_C_LINE):
		put(s, g, "pont", lambda f, d, v, r: V.bowed_pad(f, d, v, r, attack=0.8, release=1.5, cutoff=2500.0, pont=0.7,
			voices=3), n, 44 + k, 0, 6.8, 0.42 + 0.02 * k, 0.1, human=0.0)
	line(s, g, "vln", vln, M25_THEME, 52, 0.7, 0.2, accents=ACC78, legato=0.86)
	line(s, g, "oboe", oboe, M25_THEME, 52, 0.5, -0.15, transpose=-12, accents=ACC78, legato=0.86)
	# --- skitter ostinato (7/8 sections), 16th-note threads in B ---
	for i, sym in enumerate(chords):
		m = M25_METERS[i]
		key = chord_info(sym)["name"]
		if 44 <= i < 52:                        # breakdown: no ostinato
			continue
		if m == 7:
			fig = SKITTER[key]
			base = 0.5 if i < 2 else 0.58
			for e, n in enumerate(fig):
				v = base * (1.0 if e in (0, 2, 4) else 0.66)
				put(s, g, "ost", M.ostinato_pluck, n, i, e, 0.9, v, -0.3 if e % 2 else 0.3, human=0.002)
		elif i < 68:                            # B: threads in 16ths, alternating around a pedal
			t = tones_of(sym, 67)
			ped = in_range(pc("G"), 67)
			seq = [t["top"], ped, t["third"], ped, t["fifth"], ped, t["third"], ped]
			for k in range(16):
				put(s, g, "thread", M.ostinato_pluck, seq[k % 8], i, 0.5 * k, 0.45, 0.42 if k % 4 == 0 else 0.28,
					-0.6 if k % 2 else 0.6, human=0.002)
	# the G7b9 turnaround: threads climb
	for k in range(32):
		n = ["G4", "B4", "D5", "F5", "Ab5"][k % 5] if k < 30 else "G5"
		put(s, g, "thread", M.ostinato_pluck, n, 68 + k // 16, 0.5 * (k % 16), 0.45, 0.25 + 0.4 * k / 31, 0.5 if k % 2 else -0.5,
			human=0.002)
	# --- bass ---
	for i, sym in enumerate(chords):
		ci = chord_info(sym)
		b = in_range(ci["bass"], 36)
		m = M25_METERS[i]
		if 44 <= i < 52:
			continue
		if m == 7 and i >= 2:
			for e, nb in ((0, 1.8), (2, 1.8), (4, 2.8)):
				put(s, g, "bass", M.soft_bass, b, i, e, nb, 0.72 if e == 0 else 0.6, 0.0, human=0.002)
		elif m == 8 and i < 68:
			put(s, g, "bass", M.soft_bass, b, i, 0, 3.8, 0.7, 0.0)
			put(s, g, "bass", M.soft_bass, b, i, 4, 3.6, 0.55, 0.0)
	# --- breakdown C: pedal fifth, heartbeat, threads that pluck at random-looking but fixed spots ---
	for n in ("C3", "G3"):
		put(s, g, "pad", lambda f, d, v, r: V.bowed_pad(f, d, v, r, attack=1.5, release=2.0, cutoff=700.0), n, 44, 0,
			7 * 8 - 1, 0.45, -0.2 if n == "C3" else 0.2, human=0.0)
	for i in range(44, 52):
		put(s, g, "pulse", V.felt_pulse, "C2", i, 0, 1, 0.8, 0.0, human=0.0)
		put(s, g, "pulse", V.felt_pulse, "C2", i, 1.5, 1, 0.5, 0.0, human=0.0)
	col = [(44, 3, "C6"), (45, 5, "G5"), (46, 1, "Db6"), (46, 4.5, "C6"), (47, 2, "G5"), (47, 6, "Ab5"), (48, 0.5, "C6"),
		(48, 3.5, "Db6"), (49, 1, "G5"), (49, 4, "C6"), (49, 6, "Eb6"), (50, 0, "Db6"), (50, 2.5, "C6"), (50, 5, "G5"),
		(51, 1, "Ab5"), (51, 3, "Db6"), (51, 4.5, "C6"), (51, 6, "G5")]
	for bar, e, n in col:
		put(s, g, "col", V.pizz, n, bar, e, 0.5, 0.42, float(rng.uniform(-0.7, 0.7)), human=0.0)
	for i in range(44, 52):                     # ticks multiply through the breakdown
		k = i - 44
		spots = [] if k < 2 else [0, 2, 4] if k < 4 else list(range(7)) if k < 6 else [0.5 * j for j in range(14)]
		for e in spots:
			put(s, g, "tick", V.tick, 0.0, i, e, 0.25, 0.14 + 0.03 * k, 0.4, human=0.001)
	for k in range(14):                         # roll into A'
		put(s, g, "roll", V.roll_hit, 0.0, 51, 0.5 * k, 0.5, 0.12 + 0.6 * k / 13.0, 0.1 if k % 2 else -0.1, human=0.001)
	# --- A' brass stabs on the 2+2+3 accents ---
	for i in range(52, 68):
		ci = chord_info(chords[i])
		b = in_range(ci["bass"], 38)
		for e, v in ((0, 0.62), (2, 0.45), (4, 0.55)):
			for n, vm in ((b, 1.0), (b + 7, 0.75)):
				put(s, g, "brass", lambda f, d, vv, r: V.low_brass(f, d, vv, r, shape="stab"), n, i, e, 1.1 if e < 4 else 1.8,
					v * vm, 0.0, human=0.003)
	# --- turnaround T: brass swell + violin tremolo on the b9 ---
	for n, v in (("G2", 0.6), ("D3", 0.5), ("F3", 0.45), ("Ab3", 0.4)):
		put(s, g, "brass", lambda f, d, vv, r: V.low_brass(f, d, vv, r, shape="swell"), n, 68, 0, 15.5, v, 0.0)
	for k in range(32):
		put(s, g, "vln", lambda f, d, v, r: V.spicc(f, d, v, r), "Ab5" if k % 2 == 0 else "G5", 68 + k // 16, 0.5 * (k % 16),
			0.4, 0.2 + 0.4 * k / 31, 0.2, human=0.001)
	# --- percussion ---
	for i in range(70):
		m = M25_METERS[i]
		if 44 <= i < 52:
			continue
		if m == 7:
			if i >= 2:
				put(s, g, "taiko", V.taiko, 64.0, i, 0, 1, 0.85, 0.0, human=0.002)
				put(s, g, "taiko", V.taiko, 74.0, i, 4, 1, 0.6, 0.0, human=0.002)
				if i % 2 == 0:
					put(s, g, "taiko", V.taiko, 82.0, i, 6, 1, 0.35, 0.0, human=0.002)
				put(s, g, "frame", V.frame_drum, 160.0, i, 2, 1, 0.55, -0.2, human=0.002)
				put(s, g, "frame", V.frame_drum, 175.0, i, 5, 1, 0.3, -0.2, human=0.002)
			for e in range(7):
				put(s, g, "tick", V.tick, 0.0, i, e, 0.5, 0.3 if e in (0, 2, 4) else 0.17, 0.35, human=0.001)
			if i >= 52:
				put(s, g, "brush", V.brush, 0.0, i, 4, 1, 0.42, 0.15, human=0.002)
				for e in (4.5, 5.5, 6.5):
					put(s, g, "tick", V.tick, 0.0, i, e, 0.25, 0.12, -0.35, human=0.001)
		elif i < 68:                             # B: half-time drive
			put(s, g, "taiko", V.taiko, 62.0, i, 0, 1, 0.8, 0.0, human=0.002)
			put(s, g, "brush", V.brush, 0.0, i, 4, 1, 0.5, 0.15, human=0.002)
			put(s, g, "taiko", V.taiko, 70.0, i, 6.5 if i % 2 else 3, 1, 0.4, 0.0, human=0.002)
			for e in range(8):
				put(s, g, "tick", V.tick, 0.0, i, e, 0.5, 0.26 if e % 2 == 0 else 0.15, 0.35, human=0.001)
		else:                                    # T: taikos on 3+3+2, then eighths crescendo
			if i == 68:
				for e, v in ((0, 0.8), (3, 0.65), (6, 0.7)):
					put(s, g, "taiko", V.taiko, 62.0, i, e, 1, v, 0.0, human=0.0)
			else:
				for e in range(8):
					put(s, g, "taiko", V.taiko, 62.0 + 3 * e, i, e, 1, 0.45 + 0.06 * e, 0.0, human=0.0)
			for k in range(16):
				put(s, g, "roll", V.roll_hit, 0.0, i, 0.5 * k, 0.5, 0.1 + 0.35 * ((i - 68) * 16 + k) / 31, 0.1, human=0.001)
	for bar in (11, 19, 27, 59, 67):          # phrase-end rolls
		for k in range(6):
			put(s, g, "roll", V.roll_hit, 0.0, bar, 4 + 0.5 * k, 0.5, 0.2 + 0.08 * k, 0.1 if k % 2 else -0.1, human=0.001)
	put(s, g, "taiko", V.taiko, 60.0, 44, 0, 1, 0.9, 0.0, human=0.0)
	# the landing: the T build resolves onto a big hit on the loop's first downbeat, then the
	# skitter is left alone for two bars
	put(s, g, "taiko", V.taiko, 62.0, 0, 0, 1, 0.95, 0.0, human=0.0)
	put(s, g, "frame", V.frame_drum, 150.0, 0, 0, 1, 0.6, 0.0, human=0.0)
	for n, v in (("C2", 0.62), ("G2", 0.5), ("C3", 0.45)):
		put(s, g, "brass", lambda f, d, vv, r: V.low_brass(f, d, vv, r, shape="stab"), n, 0, 0, 2.5, v, 0.0, human=0.0)
	put(s, g, "bass", M.soft_bass, "C2", 0, 0, 3.5, 0.75, 0.0, human=0.0)
	s.note("swell", M.swell, 1000.0, 0, g.at(43, 4), 4.0, 0.6, 0.0, human=0.0)
	ir = S.hall(rng, 2.0, brightness=5500)
	levels = {"vln": (0.0, 0.28), "oboe": (3.0, 0.24), "low": (-2.0, 0.22), "brass": (-1.0, 0.22), "pont": (-2.0, 0.4),
		"ost": (5.0, 0.15), "thread": (1.0, 0.2), "bass": (-9.0, 0.08), "pad": (-10.0, 0.35), "pulse": (-7.0, 0.1),
		"col": (-6.0, 0.4), "taiko": (-6.0, 0.12), "frame": (-8.0, 0.12), "tick": (4.0, 0.1), "brush": (-8.0, 0.15),
		"roll": (-9.0, 0.15), "swell": (-16.0, 0.4)}
	x = finish(s, levels, ir)
	sections = [("intro", 0.0), ("A", g.sec(4, bpm)), ("A2", g.sec(20, bpm)), ("B 4/4", g.sec(28, bpm)),
		("C", g.sec(44, bpm)), ("A'", g.sec(52, bpm)), ("T", g.sec(68, bpm))]
	return x, sections, dict(s.bus_lu)


# ------------------------------------------------------------------------------------------
# Cue table, render & verification
# ------------------------------------------------------------------------------------------

CUES = {
	"m10": {"title": "Thorns in the Path", "file": "m10_thorns_in_the_path.ogg", "target": REF_BOSS + 0.2, "bpm": 100,
		"key": "E minor (B section in G major)", "meter": "6/8 (dotted quarter = 100; eighth = 300)",
		"instruments": "oboe-like double reed (lead), bassoon-like reed, violin section, flute (hhsynth), marimba ostinato, "
			"pizzicato strings, upright pluck bass (hhsynth), string pad (hhsynth), taiko, frame drum, brush, dark ticks, "
			"shaker (hhsynth), hall reverb 1.7 s",
		"motif": "Thorn motif E5-E5-B5 (repeated note, fifth leap) falling by step A5-G5-F#5; A phrase E E B A G | F# D A "
			"| G C E G F# | F# D#; cadence G F# D# E. B section: new lyrical G-major tune (D5 B4 | A4 F#4 A4 | G4 B4 E5) "
			"on bassoon then violins. Coda restates the thorn motif and cadences C-B7-Em. Own material, no shared motif.",
		"playlist": "ch1_combat (ordinary Chapter One enemies: bramblings, gloomlings)"},
	"m11": {"title": "The Last Shift", "file": "m11_the_last_shift.ogg", "target": REF_NIGHT - 1.4, "bpm": 60,
		"key": "G minor", "meter": "4/4",
		"instruments": "struck steel pipe (modal, beating partials), felt low pulse, dark bowed-synth drone, low bowed "
			"'cello' line, celesta echoes (hhsynth), cave reverb 3.8 s with slap echoes",
		"motif": "Last-Shift motif on isolated pipe notes: D5 . Bb4 A4 . G4 D5 C5 . Bb4 | Eb5 D5 C5 G4 | A4 F#4; B section "
			"lament F3 D3 Bb3 A3 G3 F3 G3 | A3 C4 F3 | Eb4 C4 G3 | G3 Eb3 C4 Bb3 | A3 F#3 Eb3 D3. Own material.",
		"playlist": "old_mine, tobin_annex"},
	"m12": {"title": "Eyes That Stay Shut", "file": "m12_eyes_that_stay_shut.ogg", "target": REF_NIGHT - 1.4, "bpm": 48,
		"key": "octatonic on B (B C D Eb F F# G# A); B section pedal F", "meter": "3/4",
		"instruments": "dark bronze 'ruin bells' (minor-third tierce, beating partials), bowed-synth clusters with "
			"sul-ponticello glass, low bowed pedal, bowed-glass modal resonators, hall reverb 4.6 s",
		"motif": "Bell cell B4-C5-F5 (semitone + tritone), often cut short to B-C; 'eyes' dyad F5+B5; transposed G#4-A4-D5 and "
			"D5-D#5-A5; inverted F5-E5-Bb4 in B; bowed-glass line sinks E5 D#5 D5 C#5 C5 B4. Own material.",
		"playlist": "ruins, silk_approach"},
	"m25": {"title": "No Thread Left Unseen", "file": "m25_no_thread_left_unseen.ogg", "target": REF_BOSS + 0.5, "bpm": 150,
		"key": "C minor", "meter": "7/8 (2+2+3) with a 16-bar 4/4 middle section; eighth = 300",
		"instruments": "violin section (lead), oboe-like reed, bassoon-like reed, low brass section, skitter ostinato pluck "
			"(hhsynth, shared timbre with the boss loop), 16th-note pluck threads, ponticello bowed synth, pizzicato "
			"col-legno threads, soft bass (hhsynth), felt pulse, taiko, frame drum, brush, ticks, snare roll, hall 2.0 s",
		"motif": "Thread theme C5 G5 F5 Eb5 D5 | Eb5 C5 G4 (fifth up, 'snagging' fall), sequenced up to C6; A2 'snag' "
			"answers G-F-Eb falling in sequence over a bassoon line; B: low brass G2 C3 | B2 ... nods to the boss motif "
			"shape (5-1-7, from music_boss/M13) under a new violin line Eb5 D5 C5 | D5 G5 | C6 Bb5 Ab5 | G5; C: chromatic "
			"G5->C5 ponticello descent.",
		"playlist": "weavers_crossing (Weaver rematch)"},
}
LAYER_INFO = {
	"m13_layer2": {"title": "The Thread Above - phase 2 layer (urgency)", "file": "m13_layer2.ogg",
		"instruments": "spiccato violin 16ths (3+3+2 arpeggios), deep taiko, backbeat brush, dark 16th ticks, snare rolls, "
			"hall 2.2 s (same IR settings as music_boss)",
		"motif": "No melody by design (ostinato layer): 16th arpeggios on the boss chords in 3+3+2; in the B section each "
			"chord adds the same upper neighbour the boss ostinato uses (b2 Eb on Dm, b9 Bb on A, 9th on Bb/C/Eb); "
			"breakdown: repeated D4/D5 eighths + ticking clock; bar 29 roll into the loop start."},
	"m13_layer3": {"title": "The Thread Above - phase 3 layer (desperation)", "file": "m13_layer3.ogg",
		"instruments": "violin section counter-melody, low brass section (fp-crescendo and swells), hall 2.2 s",
		"motif": "Counter-melody answering the boss horn motif (A3 D4 C#4 Bb3 A3): D5 Eb5 F5 Eb5 D5 | . F5 Eb5 F5 A5 | G5 "
			"E5 C#5 | D5 F5 Bb5 | A5 G5 F5 E5; climbs to F6 (D6 Eb6 F6 | Eb6 D6) in the B section; Phrygian lament A5 G5 F5 "
			"Eb5 D5 C#5 in the breakdown. On Dm bars it uses Eb (the boss's own flat second), never E natural."},
}


def write_ogg(path: str, x: np.ndarray, block: int = 16384) -> None:
	"""OGG Vorbis via soundfile (same as sf.write(path, x, 44100, format='OGG', subtype='VORBIS')),
	but fed in blocks: libsndfile 1.2.2's Vorbis encoder overflows the stack on Windows when a
	whole multi-minute buffer is written in one call."""
	import soundfile as sf
	os.makedirs(os.path.dirname(path), exist_ok=True)
	x = np.ascontiguousarray(np.asarray(x, dtype=np.float32))
	with sf.SoundFile(path, "w", SR, x.shape[1], format="OGG", subtype="VORBIS") as fh:
		for i in range(0, len(x), block):
			fh.write(x[i:i + block])


def read_audio(path: str) -> np.ndarray:
	import soundfile as sf
	y, sr = sf.read(path, dtype="float64", always_2d=True)
	assert sr == SR, path
	return y


def analyse(path: str, sections, loop: bool = True) -> dict:
	y = read_audio(path)
	import soundfile as sf
	info = sf.info(path)
	r = {"frames": len(y), "duration_s": round(len(y) / SR, 3), "channels": y.shape[1], "samplerate": info.samplerate,
		"format": "%s/%s" % (info.format, info.subtype),
		"loudness_lufs": round(Q.integrated_loudness(y, periodic=loop), 2),
		"true_peak_dbtp": round(Q.true_peak_db(y, periodic=loop), 2), "sample_peak_dbfs": round(Q.sample_peak_db(y), 2),
		"seam": {k: (round(v, 5) if isinstance(v, float) else v) for k, v in Q.loop_seam(y).items()},
		"silence_gaps_gt3s_below_-50dBFS": Q.silence_gaps(y, periodic=loop),
		"quiet_passages_gt1s_below_-45dBFS": Q.silence_gaps(y, thresh_db=-45.0, min_len=1.0, periodic=loop),
		"bands_db": Q.band_balance(y)}
	t, st = Q.short_term(y, periodic=loop)
	r["short_term_range_lufs"] = [round(float(np.min(st)), 1), round(float(np.max(st)), 1)]
	r["section_loudness_lufs"] = {}
	bounds = [b for _, b in sections] + [len(y) / SR]
	for (name, b0), b1 in zip(sections, bounds[1:]):
		seg = y[int(b0 * SR):int(b1 * SR)]
		if len(seg) > SR:
			r["section_loudness_lufs"]["%s@%.1fs" % (name, b0)] = round(Q.integrated_loudness(seg), 1)
	return r


def _render(cue: str, out_dir: str, t0: float) -> dict:
	"""Worker: composes, masters, writes and analyses one cue (m13 -> both layers)."""
	if cue == "m13":
		return _render_layers(out_dir, t0)
	rng = rng_for("ch1_tension:" + cue)
	fn = {"m10": compose_m10, "m11": compose_m11, "m12": compose_m12, "m25": compose_m25}[cue]
	x, sections, buses = fn(rng)
	meta = CUES[cue]
	y, lim = master(x, meta["target"])
	path = os.path.join(out_dir, meta["file"])
	write_ogg(path, y)
	res = analyse(path, sections)
	res.update({"id": cue, "sections": sections, "limiter": lim, "bus_lu_rel_mix": buses,
		"render_s": round(time.time() - t0, 1), "path": path, "target_lufs": meta["target"]})
	Q.spectrogram_png(read_audio(path), os.path.join(QA_DIR, cue + ".png"), "%s  %s" % (cue, meta["title"]), sections)
	return res


def _gain_for(boss: np.ndarray, layers: list, target: float) -> float:
	"""Bisection on the gain (dB) of the last layer so LUFS(boss + sum(layers)) hits target."""
	base = boss + sum(layers[:-1]) if len(layers) > 1 else boss
	lo, hi = -40.0, 12.0
	for _ in range(30):
		mid = 0.5 * (lo + hi)
		L = Q.integrated_loudness(base + layers[-1] * db(mid), periodic=True)
		if L > target:
			hi = mid
		else:
			lo = mid
	return 0.5 * (lo + hi)


def load_boss() -> tuple:
	"""music_boss.wav (read-only): 44.1 kHz stereo 16-bit, 2 646 001 frames = the 2 646 000-frame
	loop plus one wrap frame (copy of frame 0); Godot loops [0, 2646000) (loop_end -1 = frames-1)."""
	from hhsynth.wavio import read_wav
	x, sr, loop = read_wav(BOSS_WAV)
	assert sr == SR and x.ndim == 2 and x.shape[1] == 2
	n = loop[1] if loop else len(x)
	return x[:n], {"wav_frames": len(x), "loop": list(loop) if loop else None, "loop_frames": n, "sr": sr}


BOSS_PLUS_L2 = REF_BOSS + 1.0         # phase 2 = boss + layer 2
BOSS_PLUS_L23 = REF_BOSS + 1.9        # phase 3 = boss + layer 2 + layer 3 (stays within +2 LU)
SUM_CEILING = -1.7                    # true-peak ceiling for the summed phase-3 mix (pre-encode)


def _render_layers(out_dir: str, t0: float) -> dict:
	boss, binfo = load_boss()
	n = len(boss)
	l2, bus2 = compose_m13_layer2(rng_for("ch1_tension:m13_layer2"))
	l3, bus3 = compose_m13_layer3(rng_for("ch1_tension:m13_layer3"))
	assert len(l2) == n and len(l3) == n, (len(l2), len(l3), n)
	l2 = l2 - np.mean(l2, axis=0, keepdims=True)
	l3 = l3 - np.mean(l3, axis=0, keepdims=True)
	g2 = _gain_for(boss, [l2], BOSS_PLUS_L2)
	l2 = l2 * db(g2)
	g3 = _gain_for(boss, [l2, l3], BOSS_PLUS_L23)
	l3 = l3 * db(g3)
	# joint "sidechain" limiter on the layers only: wherever boss + layers would exceed the ceiling
	# (in any combination the director can play), the layers dip smoothly; the boss is untouched.
	ceil = db(SUM_CEILING)
	req = np.ones(n)
	for combo in (l2, l3, l2 + l3):
		tot = Q.true_peak_trace(boss + combo, periodic=True)
		over = tot > ceil
		if np.any(over):
			# linear estimate of the layer gain that brings this sample back under the ceiling
			lay = Q.true_peak_trace(combo, periodic=True)
			bpk = Q.true_peak_trace(boss, periodic=True)
			need = np.clip((ceil - bpk) / np.maximum(lay, 1e-9), 0.0, 1.0)
			req = np.minimum(req, np.where(over, need, 1.0))
	h = ns(0.012)
	if np.any(req < 1.0):
		req = ndimage.minimum_filter1d(req, size=2 * h + 1, mode="wrap")
		req = ndimage.uniform_filter1d(req, size=h, mode="wrap")
	l2 = l2 * req[:, None]
	l3 = l3 * req[:, None]
	l2, lim2 = tp_limit(l2, TP_CEILING)
	l3, lim3 = tp_limit(l3, TP_CEILING)
	results = {"id": "m13", "boss": binfo, "gains_db": {"layer2": round(g2, 2), "layer3": round(g3, 2)},
		"sidechain_min_gain_db": round(20 * np.log10(max(np.min(req), 1e-9)), 2), "layers": {}}
	grid = _boss_grid()
	sections = [("intro", 0.0), ("A", grid.sec(2, 120)), ("B", grid.sec(10, 120)), ("A", grid.sec(18, 120)),
		("breakdown", grid.sec(26, 120)), ("build", grid.sec(29, 120))]
	for name, y, lim, buses in (("m13_layer2", l2, lim2, bus2), ("m13_layer3", l3, lim3, bus3)):
		path = os.path.join(out_dir, LAYER_INFO[name]["file"])
		write_ogg(path, y)
		r = analyse(path, sections)
		r.update({"limiter": lim, "bus_lu_rel_mix": buses, "path": path})
		results["layers"][name] = r
		Q.spectrogram_png(read_audio(path), os.path.join(QA_DIR, name + ".png"), name + "  " + LAYER_INFO[name]["title"],
			sections)
	# the decoded files, summed with the boss loop at unity gain
	d2 = read_audio(os.path.join(out_dir, LAYER_INFO["m13_layer2"]["file"]))
	d3 = read_audio(os.path.join(out_dir, LAYER_INFO["m13_layer3"]["file"]))
	sums = {}
	for label, mixx in (("boss", boss), ("boss+L2", boss + d2), ("boss+L3", boss + d3), ("boss+L2+L3", boss + d2 + d3)):
		sums[label] = {"loudness_lufs": round(Q.integrated_loudness(mixx, periodic=True), 2),
			"true_peak_dbtp": round(Q.true_peak_db(mixx, periodic=True), 2),
			"sample_peak_dbfs": round(Q.sample_peak_db(mixx), 2), "clipped_samples": int(np.sum(np.abs(mixx) >= 1.0))}
	results["sums"] = sums
	results["sections"] = sections
	Q.spectrogram_png(boss + d2 + d3, os.path.join(QA_DIR, "m13_sum_boss_l2_l3.png"), "music_boss + m13_layer2 + m13_layer3 (unity)",
		sections)
	results["render_s"] = round(time.time() - t0, 1)
	return results


def _fmt_sections(sections, total: float, extra: str = "") -> str:
	parts = []
	bounds = [b for _, b in sections] + [total]
	for (name, b0), b1 in zip(sections, bounds[1:]):
		parts.append("%s(%.1f-%.1fs)" % (name, b0, b1))
	return " ".join(parts) + extra


def build_manifest(results: dict) -> list:
	rows = []
	for cue in ("m10", "m11", "m12"):
		r = results[cue]
		meta = CUES[cue]
		rows.append(_row(cue, meta, r))
	m13 = results["m13"]
	for name in ("m13_layer2", "m13_layer3"):
		r = m13["layers"][name]
		info = LAYER_INFO[name]
		sums = m13["sums"]
		rows.append({"id": name, "title": info["title"], "file": info["file"], "duration_s": r["duration_s"], "loop": True,
			"bpm": 120, "key": "D minor", "meter": "4/4",
			"sections": _fmt_sections(m13["sections"], r["duration_s"], " - bar grid identical to music_boss (30 bars x 2 s)"),
			"instruments": info["instruments"], "motif_notes": info["motif"], "peak_dbfs": r["sample_peak_dbfs"],
			"true_peak_dbtp": r["true_peak_dbtp"], "loudness_lufs": r["loudness_lufs"],
			"loudness_note": "additive stem: alone it is quieter than music_boss on purpose; the mixes the player hears "
				"are boss %.2f LUFS, boss+L2 %.2f LUFS, boss+L2+L3 %.2f LUFS (true peak %.2f dBTP, %d clipped samples at "
				"unity gain)" % (sums["boss"]["loudness_lufs"], sums["boss+L2"]["loudness_lufs"],
				sums["boss+L2+L3"]["loudness_lufs"], sums["boss+L2+L3"]["true_peak_dbtp"], sums["boss+L2+L3"]["clipped_samples"]),
			"sync": "%d frames = music_boss.wav loop length. music_boss.wav is already 44.1 kHz stereo 16-bit (no "
				"resampling needed); it has %d frames = the %d-frame loop + 1 wrap frame (copy of frame 0). Its import "
				"(loop_mode Forward, loop_end -1) is taken to loop [0, %d) without the wrap frame, as the project's earlier "
				"audio audit found; not re-checked in the engine here (Godot not run). If Godot looped all %d frames, the "
				"boss would drift 1 frame (23 us) per loop against the layers. Start all three streams on the same mix "
				"frame." % (r["frames"], m13["boss"]["wav_frames"], m13["boss"]["loop_frames"], m13["boss"]["loop_frames"],
				m13["boss"]["wav_frames"]),
			"location_playlist": "boss_matron phase 2 (layer2) / phase 3 (layer2 + layer3), over music_boss",
			"generator": GENERATOR, "qa": dict(_qa(r), sums_with_boss_unity_gain=sums),
			"verified": "analysis only - not listened"})
	rows.append(_row("m25", CUES["m25"], results["m25"]))
	for row in rows:
		row["import"] = IMPORT_NOTE
		row["review"] = REVIEW[row["id"]]
	return rows


IMPORT_NOTE = ("OGG Vorbis 44.1 kHz stereo (AudioStreamOggVorbis). Needs loop=true, loop_offset=0 in its .import; no .import "
	"file was written and Godot's importer was not run for this group.")
_REVIEW_COMMON = ("Independent review 2026-09-27 (numbers and spectrograms only, nobody listened): generator code read; "
	"loudness/true peak re-measured with ffmpeg ebur128; loop seam checked for clicks (>4 kHz residual at the seam vs the "
	"file's own transients) and spectral jumps; DC below -90 dBFS; >8 kHz band at most about -49 dBFS per 200 ms window "
	"(music_boss -47). ")
REVIEW = {
	"m10": _REVIEW_COMMON + "Composition: E minor 6/8, A (oboe, 16 bars), B (G major, bassoon then violins), A' (violin "
		"counter-lines, flute), coda cadence C-B7-Em then a drum pickup; own material, unrelated to music_boss. No change.",
	"m11": _REVIEW_COMMON + "Composition: G minor, pipe motif A, cello lament B over Bb-F/A-Abmaj7-Cm/Eb-D7b9, varied A', "
		"thinning breath into the loop. The drone breathes out to below -60 dBFS for about 1.1 s at 15 s and 1.3 s at 111 s "
		"(the intended 'space'; the mine ambience will sit under it). No change.",
	"m12": _REVIEW_COMMON + "Composition: octatonic on B, bell cell B-C-F, bowed clusters, tritone-shifted B section on F, "
		"return. Deliberate silences below -60 dBFS for about 1.6-1.7 s at 41 s and 86 s. No change.",
	"m13_layer2": _REVIEW_COMMON + "Review fix: in the B section, Dm bars 12-13 now add Eb (the b2 music_boss's ostinato and "
		"rub pad use on D) instead of E natural, so every added neighbour note matches the boss's own. Checked against "
		"music_boss's note lists (music_tracks.py): no layer-2 note forms a semitone with a boss note sounding at the same "
		"moment. Onset cross-correlation with the decoded boss: best lag -1 ms (1 ms steps).",
	"m13_layer3": _REVIEW_COMMON + "Review fix: E natural on Dm bars (0, 1, 2, 6, 12, 13, 28) changed to Eb. Before, E5 "
		"sounded against the boss ostinato's Eb3 at the same instant in bars 1, 2, 6 and 28 (a cross-relation the boss "
		"never makes). After, no layer-3 note forms a semitone with a boss ostinato note sounding at the same moment. Six "
		"brief passing/neighbour tones remain against sustained string chord tones, which is normal counterpoint. The "
		"sum boss+L2+L3 was re-measured after the fix.",
	"m25": _REVIEW_COMMON + "Composition: C minor, 7/8 thread theme (new), A2 bassoon/snags, 4/4 B with brass nodding to "
		"the boss motif under a new violin line, chromatic breakdown, A', G7b9 turnaround; not a copy of music_boss. Low end: "
		"45-100 Hz holds -5.0 dB of the total energy vs -9.2 dB for music_boss, but relative to its 1-4 kHz band m25 (+5.9 "
		"dB) matches music_boss (+6.4 dB), because m25 also has more upper-mid content. Judged not a defect and left "
		"unchanged; still worth a headphone check.",
}


def _qa(r: dict) -> dict:
	return {"frames": r["frames"], "format": "OGG Vorbis, %d Hz, %d ch" % (r["samplerate"], r["channels"]),
		"loop_seam": "end->start jump %.4f = x%.2f of the file's 99.9th-percentile sample step; 50 ms RMS %.1f -> %.1f dBFS "
			"(step %.1f dB, file p99 window step %.1f dB): %s" % (r["seam"]["jump"], r["seam"]["ratio"], r["seam"]["rms_end_db"],
			r["seam"]["rms_start_db"], r["seam"]["rms_step_db"], r["seam"]["window_step_p99_db"], "OK" if r["seam"]["ok"] else "CHECK"),
		"silence_gaps_gt3s": r["silence_gaps_gt3s_below_-50dBFS"],
		"quiet_passages_gt1s_below_-45dBFS": r["quiet_passages_gt1s_below_-45dBFS"],
		"short_term_lufs_range": r["short_term_range_lufs"], "section_loudness_lufs": r["section_loudness_lufs"],
		"band_balance_db": r["bands_db"]}


def _row(cue: str, meta: dict, r: dict) -> dict:
	ref = "music_boss (-17.8 LUFS)" if meta["target"] > -18.5 else "music_night (-17.6 LUFS), kept ~1.4 LU quieter"
	return {"id": cue, "title": meta["title"], "file": meta["file"], "duration_s": r["duration_s"], "loop": True,
		"bpm": meta["bpm"], "key": meta["key"], "meter": meta["meter"],
		"sections": _fmt_sections(r["sections"], r["duration_s"], " -> loops to start"),
		"instruments": meta["instruments"], "motif_notes": meta["motif"], "peak_dbfs": r["sample_peak_dbfs"],
		"true_peak_dbtp": r["true_peak_dbtp"], "loudness_lufs": r["loudness_lufs"], "loudness_reference": ref,
		"location_playlist": meta["playlist"], "generator": GENERATOR, "qa": _qa(r),
		"verified": "analysis only - not listened"}


def render_all(out_dir: str = OUT_DIR, jobs: int = 5, write_manifest: bool = True, only=None) -> dict:
	"""Renders every cue of this group into out_dir (OGG Vorbis), writes spectrograms to
	qa/tmp/music2/ and the manifest rows. Returns the analysis results."""
	from concurrent.futures import ProcessPoolExecutor
	t0 = time.time()
	cues = [c for c in ["m13", "m25", "m10", "m12", "m11"] if not only or c in only]
	results = {}
	if jobs > 1:
		with ProcessPoolExecutor(max_workers=jobs) as ex:
			futs = {c: ex.submit(_render, c, out_dir, time.time()) for c in cues}
			for c, f in futs.items():
				results[c] = f.result()
	else:
		for c in cues:
			results[c] = _render(c, out_dir, time.time())
	if write_manifest and len(results) == 5:
		rows = build_manifest(results)
		with open(MANIFEST, "w", encoding="utf-8") as fh:
			json.dump(rows, fh, indent=1)
		with open(os.path.join(QA_DIR, "ch1_tension_analysis.json"), "w", encoding="utf-8") as fh:
			json.dump(results, fh, indent=1, default=float)
	results["_total_s"] = round(time.time() - t0, 1)
	return results


if __name__ == "__main__":
	import argparse
	ap = argparse.ArgumentParser()
	ap.add_argument("--jobs", type=int, default=5)
	ap.add_argument("--out", default=OUT_DIR)
	ap.add_argument("--only", default="", help="comma list, e.g. m10,m13 (a partial list skips the manifest)")
	a = ap.parse_args()
	res = render_all(a.out, a.jobs, only=[c for c in a.only.split(",") if c] or None)
	for c in ("m10", "m11", "m12", "m25"):
		if c not in res:
			continue
		r = res[c]
		print("     bus LU vs mix:", r["bus_lu_rel_mix"], " sections:", r["section_loudness_lufs"])
		print("%-4s %-34s %6.1fs  %6.2f LUFS  TP %6.2f dBTP  seam x%.2f  gaps %s  render %.0fs" % (c, CUES[c]["file"],
			r["duration_s"], r["loudness_lufs"], r["true_peak_dbtp"], r["seam"]["ratio"], r["silence_gaps_gt3s_below_-50dBFS"],
			r["render_s"]))
	for name, r in (res["m13"]["layers"].items() if "m13" in res else []):
		print("     bus LU:", r["bus_lu_rel_mix"], r["section_loudness_lufs"])
		print("%-10s %-30s %6.1fs  %6.2f LUFS  TP %6.2f dBTP  frames %d  seam x%.2f" % (name, r["path"].split(os.sep)[-1],
			r["duration_s"], r["loudness_lufs"], r["true_peak_dbtp"], r["frames"], r["seam"]["ratio"]))
	for k, v in (res["m13"]["sums"].items() if "m13" in res else []):
		print("   %-12s %s" % (k, v))
	print("total %.1fs" % res["_total_s"])
