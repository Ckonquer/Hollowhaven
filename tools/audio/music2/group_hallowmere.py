"""Hallowmere music group (Chapter Two): m15, m16, m17, m18, m19 and m27.

Original compositions, synthesised with tools/audio/hhsynth (read-only) plus the extra voices in
hallowmere_voices.py. Every cue is a through-composed piece with a real ending (none of these is a
LOOP cue); the MusicDirector plays it and moves on.

THE LANTERNWAKE MOTIF (shared by m15 and m27 only)
    Six notes, "da-da di-di da DAAH": scale degrees 1 5 #4 5 6 3 with the rhythm
    8th 8th 16th 16th 8th quarter, e.g. Bb4 F5 E5 F5 G5 D5 in Bb major. A leap up a fifth, an impish
    chromatic lower-neighbour snap, a lift to the sixth and a drop of a fourth onto the third.
    (Deliberately unlike the "For Krystal" motif 5-1-7-6-5, which leaps a fourth and walks down.)
THE HAVEN MOTIF (quoted in m27): the first bar of HAVEN_A in tools/audio/music_tracks.py, imported
    from there: D5 G5 F#5 E5 D5 B4 (5 1 7 6 5 3 in G). In m27 the two motifs are combined in
    counterpoint - the Lanternwake line climbs from 1 to 6 while the haven line falls from 1 to 3.

    .tools/pyenv/Scripts/python.exe tools/audio/music2/group_hallowmere.py [--only m15,m27] [--jobs 6]

Writes game/assets/audio/music/<cue>.ogg (OGG Vorbis, 44.1 kHz stereo), qa/tmp/music2/<cue>.png
(spectrogram with section markers) and tools/audio/music2/manifest_hallowmere.json. Deterministic:
every cue is seeded from its id.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time

sys.dont_write_bytecode = True     # keep tools/audio free of __pycache__ folders

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.dirname(HERE)
ROOT = os.path.abspath(os.path.join(AUDIO, "..", ".."))
for _p in (AUDIO, HERE):
	if _p not in sys.path:
		sys.path.insert(0, _p)

import numpy as np

from hhsynth.core import SR, ns, rng_for, db, place, limiter, fade
from hhsynth import music as M, space as S, filters as F
from hhsynth.music import Song
import hallowmere_voices as V
import hallowmere_meter as Q
from music_tracks import HAVEN_A          # read-only: the existing haven theme

OUT_DIR = os.path.join(ROOT, "game", "assets", "audio", "music")
QA_DIR = os.path.join(ROOT, "qa", "tmp", "music2")
MANIFEST = os.path.join(HERE, "manifest_hallowmere.json")

# ==============================================================================================
# Harmony helpers (own chord table: hhsynth's plus a few extra shapes)
# ==============================================================================================

_PCS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
SHAPES = dict(M.CHORD_SHAPES)
SHAPES.update({"6": [0, 4, 7, 9], "dim7": [0, 3, 6, 9], "m7b5": [0, 3, 6, 10], "9": [0, 4, 7, 10, 14],
	"add9": [0, 4, 7, 14], "m6": [0, 3, 7, 9], "7sus4": [0, 5, 7, 10], "sus4": [0, 5, 7], "sus2": [0, 2, 7]})


def _pc(name: str) -> int:
	return (_PCS[name[0]] + name[1:].count("#") - name[1:].count("b")) % 12


def chord(sym: str):
	"""'Gm7' -> (root_pc, intervals, bass_pc); 'Cmaj7/E' -> bass E."""
	bass = None
	if "/" in sym:
		sym, b = sym.split("/")
		bass = _pc(b)
	m = re.fullmatch(r"([A-G][#b]?)(.*)", sym)
	root = _pc(m.group(1))
	return root, SHAPES[m.group(2)], (root if bass is None else bass)


def at_or_above(pc: int, lo: int) -> int:
	return lo + ((pc - lo) % 12)


def split(entry, bpb: int):
	"""A bar's harmony: 'F' or [('Am7', 2), ('D', 2)] -> [(sym, start_beat, beats)]."""
	if isinstance(entry, str):
		return [(entry, 0.0, float(bpb))]
	out, b = [], 0.0
	for sym, n in entry:
		out.append((sym, b, float(n)))
		b += n
	return out


def tones(sym: str, lo: int = 50, tr: int = 0) -> dict:
	root, ivs, bass = chord(sym)
	r = at_or_above((root + tr) % 12, lo)
	t = {"bass": at_or_above((bass + tr) % 12, lo - 12), "root": r, "third": r + ivs[1], "fifth": r + ivs[2],
		"top": r + 12, "seventh": r + (ivs[3] if len(ivs) > 3 else 12), "ninth": r + 14}
	t["fifth_lo"] = t["fifth"] - 12
	t["third_hi"] = t["third"] + 12
	t["fifth_hi"] = t["fifth"] + 12
	t["bass8"] = t["bass"] + 12
	return t


def motif(tonic: str, shape, tail=None):
	"""Builds a bar from (semitones above tonic, beats) pairs; tail = extra (note, beats) items."""
	t = M.midi(tonic)
	out = [(t + s if s is not None else "r", b) for s, b in shape]
	return out + list(tail or [])


# The Lanternwake motif: 1 5 #4 5 6 3 (semitones 0 7 6 7 9 4), 8th 8th 16th 16th 8th quarter
LANTERN = [(0, 0.5), (7, 0.5), (6, 0.25), (7, 0.25), (9, 0.5), (4, 1.0)]
LANTERN_MINOR = [(0, 0.5), (7, 0.5), (6, 0.25), (7, 0.25), (8, 0.5), (3, 1.0)]   # 1 5 #4 5 b6 b3
# The haven motif, taken from the existing theme (first bar of HAVEN_A: D5 G5 F#5 E5 D5 B4 in G)
HAVEN_MOTIF = list(HAVEN_A[0])


def shift(bar, semis: int):
	return [(n if n == "r" else M.midi(n) + semis,) + tuple(rest) for n, *rest in bar]


# ==============================================================================================
# A linear (non-looping) sequencer with a tempo map
# ==============================================================================================

class Piece(Song):
	"""hhsynth Song for through-composed cues: a piecewise-linear tempo map (ritardandos, fermata-like
	holds), no loop folding, and a render that keeps the natural reverb ring-out as the ending."""

	PREROLL = 0.04    # seconds of air before bar 1, so the first attack is never shaved by the start fade

	def __init__(self, bpm: float, bpb: int, bars: int, rng: np.random.Generator, tempo=None, swing: float = 0.0,
			tail: float = 8.0):
		super().__init__(bpm, bpb, bars, rng, tail=tail, swing=swing)
		pts = sorted(tempo or [(0.0, bpm), (bars, bpm)])
		step = 1.0 / 48.0
		pos = np.arange(0.0, bars * bpb + 24.0, step)
		bpm_at = np.interp(pos / bpb, [p[0] for p in pts], [p[1] for p in pts])
		dt = 60.0 / bpm_at * step
		self._pos = pos
		self._t = np.concatenate([[0.0], np.cumsum(dt[:-1])])
		self.length = self.tpos(bars * bpb) + self.PREROLL      # end of the last bar in the file
		self.n = ns(self.length)
		self.bus_eq = {}     # bus -> [(rbj kind, fc, gain_db, q), ...] corrective EQ applied at mixdown

	def tpos(self, beats: float) -> float:
		return float(np.interp(beats, self._pos, self._t))

	def bar_time(self, bar: float) -> float:
		"""Where a bar starts in the rendered file (seconds)."""
		return self.tpos(bar * self.bpb) + self.PREROLL

	def time(self, bar: float, beat: float = 0.0) -> float:
		b = beat
		if self.swing > 0:
			frac = b - np.floor(b)
			if abs(frac - 0.5) < 1e-6:
				b = np.floor(b) + 0.5 + self.swing * 0.5
		return self.tpos(bar * self.bpb + b)

	def add(self, bus: str, t: float, sig: np.ndarray, pan: float = 0.0, gain: float = 1.0) -> None:
		buf = self.bus(bus)
		st = S.pan(sig, pan) if sig.ndim == 1 else sig
		place(buf, st, max(t, 0.0) + self.PREROLL, gain)

	def note(self, bus: str, inst, note, bar: float, beat: float, beats: float, vel: float = 0.8, pan: float = 0.0,
			human: float = 0.006, gain: float = 1.0, **kw) -> None:
		f = M.hz(note) if not isinstance(note, float) else note
		p0 = bar * self.bpb + beat
		t = self.time(bar, beat) + (self.rng.normal(0, human) if human > 0 else 0.0)
		dur = max(0.03, self.tpos(p0 + beats) - self.tpos(p0))
		v = float(np.clip(vel * (1.0 + (self.rng.normal(0, 0.05) if human > 0 else 0.0)), 0.05, 1.0))
		self.add(bus, t, inst(f, dur, v, self.rng, **kw), pan, gain)

	def render(self, levels: dict, ir: np.ndarray, master_lp: float = 13000.0, hp: float = 32.0) -> np.ndarray:
		total = self.n + ns(self.tail)
		dry = np.zeros((total, 2))
		send = np.zeros((total, 2))
		self.bus_report = {}
		for name, buf in self.buses.items():
			for kind, fc, gain_db, q in self.bus_eq.get(name, ()):
				buf = F.rbj(buf, kind, fc, q, gain_db)
			g, s = levels[name]
			dry += buf * db(g)
			send += buf * db(g) * s
			active = buf[np.max(np.abs(buf), axis=1) > 1e-4]
			self.bus_report[name] = round(20 * np.log10(np.sqrt(np.mean(np.square(active))) * db(g) + 1e-12), 1) \
				if len(active) else -120.0
		wet = S.reverb(send, ir, wet=1.0, dry=0.0)
		full = np.zeros((len(wet), 2))
		full[:total] += dry
		full += wet
		full = F.highpass(full, hp, 2)
		full = F.lowpass(full, master_lp, 1)
		# the piece ends where its ring-out has decayed 60 dB below the loudest passage
		fr = ns(0.02)
		k = len(full) // fr
		env = np.sqrt(np.mean(full[:k * fr].reshape(k, fr, 2) ** 2, axis=(1, 2)))
		last = int(np.nonzero(env > np.max(env) * db(-60.0))[0][-1])
		end = max(min(len(full), (last + 1) * fr + ns(0.25)), self.n)
		return fade(full[:end], 0.005, 1.2)


# ==============================================================================================
# Writing helpers
# ==============================================================================================

def line(p: Piece, bus: str, inst, bars, start: int, vel: float = 0.7, pan: float = 0.0, tr: int = 0,
		legato: float = 0.95, accent: float = 0.06, human: float = 0.006, **kw):
	"""bars = [[(note|'r', beats[, art]), ...], ...]; art: 's' staccato, '>' accent, '~' tie-over (legato 1.05).
	Every bar must add up to the meter (catches transcription slips)."""
	for i, bar in enumerate(bars):
		beat = 0.0
		for item in bar:
			note, beats = item[0], item[1]
			art = item[2] if len(item) > 2 else ""
			if note != "r":
				ln = beats * legato
				v = vel + (accent if beat == 0 else 0.0)
				if "s" in art:
					ln = min(beats * 0.55, 0.3)
				if ">" in art:
					v += 0.12
				if "~" in art:
					ln = beats * 1.05
				p.note(bus, inst, M.midi(note) + tr, start + i, beat, ln, min(v, 1.0), pan, human=human, **kw)
			beat += beats
		if abs(beat - p.bpb) > 1e-6:
			raise ValueError("%s bar %d adds up to %.3f beats, meter has %d" % (bus, start + i, beat, p.bpb))


def pads(p: Piece, bus: str, inst, chords, start: int, lo: int = 53, hi: int = 69, vel: float = 0.5, pan: float = 0.0,
		overlap: float = 0.15, tr: int = 0, **kw):
	prev = None
	for i, entry in enumerate(chords):
		for sym, b0, nb in split(entry, p.bpb):
			root, ivs, _ = chord(sym)
			v = M.voice_lead(prev, [root + iv + tr for iv in ivs], lo, hi)
			prev = v
			for n in v:
				p.note(bus, inst, n, start + i, b0, nb + overlap, vel, pan, human=0.0, **kw)


def bassline(p: Piece, bus: str, inst, chords, start: int, pattern, lo: int = 36, vel: float = 0.75, tr: int = 0,
		pan: float = 0.0, **kw):
	"""pattern = [(beat, beats, deg[, vel_mul])], deg: 'b' bass, '5' fifth, '8' octave, '3' third."""
	for i, entry in enumerate(chords):
		for sym, b0, nb in split(entry, p.bpb):
			root, ivs, bass = chord(sym)
			b = at_or_above((bass + tr) % 12, lo)
			deg = {"b": b, "5": at_or_above((root + ivs[2] + tr) % 12, lo), "8": b + 12,
				"3": at_or_above((root + ivs[1] + tr) % 12, lo)}
			for item in pattern:
				beat, beats, d = item[:3]
				vm = item[3] if len(item) > 3 else 1.0
				if b0 <= beat < b0 + nb:
					p.note(bus, inst, deg[d], start + i, beat, beats, vel * vm, pan, **kw)


def arp(p: Piece, bus: str, inst, chords, start: int, pattern, vel: float = 0.5, pan: float = 0.0, lo: int = 50,
		tr: int = 0, beats: float = 1.0, **kw):
	"""pattern = [(beat, degree, vel_mul)], degree from tones()."""
	for i, entry in enumerate(chords):
		for sym, b0, nb in split(entry, p.bpb):
			t = tones(sym, lo, tr)
			for beat, deg, vm in pattern:
				if b0 <= beat < b0 + nb:
					p.note(bus, inst, t[deg], start + i, beat, beats, vel * vm, pan, **kw)


def hits(p: Piece, bus: str, inst, chords, start: int, beat_list, lo: int = 55, hi: int = 67, vel: float = 0.45,
		pan: float = 0.0, length: float = 0.5, roll: float = 0.0, tr: int = 0, spread: float = 0.25, **kw):
	"""Voice-led block chords struck on the given beats: beat_list = [(beat, vel_mul)]."""
	prev = None
	for i, entry in enumerate(chords):
		for sym, b0, nb in split(entry, p.bpb):
			root, ivs, _ = chord(sym)
			v = M.voice_lead(prev, [root + iv + tr for iv in ivs[:4]], lo, hi)
			prev = v
			for beat, vm in beat_list:
				if b0 <= beat < b0 + nb:
					for k, n in enumerate(v):
						pk = pan + spread * (k / max(1, len(v) - 1) - 0.5)
						p.note(bus, inst, n, start + i, beat + roll * k, length, vel * vm, pk, **kw)


def guide(p: Piece, bus: str, inst, chords, start: int, lo: int, hi: int, vel: float = 0.45, pan: float = 0.0,
		tr: int = 0, legato: float = 0.98, **kw):
	"""A smooth counter-line of guide tones (third / seventh, else fifth) nearest the previous note;
	repeated notes are tied instead of re-struck."""
	segs = []
	prev = None
	for i, entry in enumerate(chords):
		for sym, b0, nb in split(entry, p.bpb):
			root, ivs, _ = chord(sym)
			pcs = {(root + ivs[1] + tr) % 12, (root + (ivs[3] if len(ivs) > 3 else ivs[2]) + tr) % 12}
			cands = [n for n in range(lo, hi + 1) if n % 12 in pcs]
			tgt = prev if prev is not None else (lo + hi) / 2.0
			n = min(cands, key=lambda c: (abs(c - tgt), c))
			pos = (start + i) * p.bpb + b0
			if segs and segs[-1][0] == n and abs(segs[-1][1] + segs[-1][2] - pos) < 1e-6:
				segs[-1][2] += nb
			else:
				segs.append([n, pos, nb])
			prev = n
	for n, pos, nb in segs:
		p.note(bus, inst, n, 0, pos, nb * legato, vel, pan, **kw)


def perc(p: Piece, bus: str, inst, freq: float, bars, beat_list, vel: float = 0.4, pan: float = 0.0,
		human: float = 0.004, **kw):
	for bar in bars:
		for item in beat_list:
			beat, vm = (item, 1.0) if not isinstance(item, tuple) else item
			p.note(bus, inst, float(freq), bar, beat, 0.25, vel * vm, pan, human=human, **kw)


def roll(p: Piece, bus: str, inst, note, bar: int, beat: float, beats: float, v0: float, v1: float, rate: int = 6,
		pan: float = 0.0):
	k = max(1, int(round(beats * rate)))
	for i in range(k):
		v = v0 + (v1 - v0) * i / max(1, k - 1)
		p.note(bus, inst, note, bar, beat + i / rate, 1.0 / rate, v, pan + (0.12 if i % 2 else -0.12), human=0.003)


# ==============================================================================================
# m15 "Welcome to Lanternwake" - Bb major, 4/4, 104 bpm
# ==============================================================================================

M15_INTRO = ["Bb6", "Gm7", "Cm7", "F7"]
M15_Aa = ["Bb6", [("Cm7", 2), ("F7", 2)], "Bb/D", [("Eb", 2), ("Ebm6", 2)], [("Bb/F", 2), ("Gm", 2)],
	[("Cm7", 2), ("F7sus4", 1), ("F7", 1)], [("Eb", 2), ("F7", 2)], "Bb"]
M15_Ab = M15_Aa[:4] + [[("Gm7", 2), ("C7", 2)], [("Cm7", 2), ("F7", 2)], [("Bb/D", 2), ("Eb6", 2)], [("F7", 2), ("Bb", 2)]]
M15_B = ["Gm", "Gm/F", "Ebmaj7", [("D7sus4", 2), ("D7", 2)], "Gm", "Cm7", "F7", "Bbmaj7",
	"Ebmaj7", "Dm7", "Cm7", "F7", "Gm", "Eb", "Cm7", [("F7sus4", 2), ("F7", 2)]]
M15_CODA = ["Eb", "Ebm6", [("Bb/F", 2), ("Gm7", 2)], [("Cm7", 2), ("F7", 2)], "Bb", "Bb"]

M15_MEL_a = [
	motif("Bb4", LANTERN, [("r", 1)]),
	[("r", .5), ("Eb5", .5), ("D5", .5), ("C5", .5), ("A4", .5), ("C5", .5), ("F5", 1)],
	[("D5", .5), ("A5", .5), ("G#5", .25), ("A5", .25), ("Bb5", .5), ("F5", 1), ("r", 1)],
	[("G5", .5), ("F5", .5), ("Eb5", .5), ("C5", .5), ("Bb4", .5), ("Gb4", .5), ("Bb4", 1)],
	[("F5", .5), ("Bb5", .5), ("A5", .25), ("Bb5", .25), ("C6", .5), ("D6", 1), ("Bb5", .5), ("G5", .5)],
	[("Eb6", 1), ("D6", .5), ("C6", .5), ("Bb5", 1), ("A5", 1)],
	[("G5", .5), ("Eb5", .5), ("D5", .25), ("Eb5", .25), ("F5", .5), ("A5", .5), ("C6", .5), ("F5", .5), ("A5", .5)],
	[("Bb5", 1.5), ("F5", .5), ("Bb4", 1), ("r", 1)],
]
M15_MEL_b = M15_MEL_a[:4] + [
	[("Bb5", .5), ("G5", .5), ("F#5", .25), ("G5", .25), ("A5", .5), ("Bb5", 1), ("E5", 1)],
	[("Eb5", .5), ("G5", .5), ("C6", .5), ("Bb5", .5), ("A5", 1), ("C5", 1)],
	[("D5", .5), ("F5", .5), ("Bb5", 1), ("C6", .5), ("Bb5", .5), ("G5", 1)],
	[("A5", .5), ("G5", .5), ("F5", .5), ("Eb5", .5), ("D5", 1), ("Bb4", 1)],
]
M15_MEL_B = [
	[("r", 1), ("D5", 1), ("G5", 1), ("A5", 1)],
	[("Bb5", 2.5), ("A5", .5), ("G5", 1)],
	[("G5", 1.5), ("F5", .5), ("Eb5", 1), ("D5", 1)],
	[("C5", 1.5), ("D5", .5), ("A4", 1), ("r", 1)],
	[("r", .5), ("D5", .5), ("G5", 1), ("Bb5", 1), ("A5", 1)],
	[("G5", 2), ("Eb5", 1), ("C5", 1)],
	[("F5", 1), ("A5", 1), ("C6", 1.5), ("Bb5", .5)],
	[("A5", 3), ("r", 1)],
	[("r", .5), ("Bb4", .5), ("Eb5", 1), ("G5", 1), ("Bb5", 1)],
	[("A5", 2), ("F5", 1), ("D5", 1)],
	[("Eb5", 1), ("G5", 1), ("Bb5", 1.5), ("C6", .5)],
	[("A5", 2), ("G5", .5), ("F5", .5), ("Eb5", 1)],
	[("D5", 1.5), ("G5", .5), ("Bb5", 2)],
	[("G5", 2), ("F5", 1), ("Eb5", 1)],
	[("Eb5", 1.5), ("D5", .5), ("C5", 2)],
	[("Bb4", 2), ("A4", 1), ("r", 1)],
]


def m15(rng):
	# bars: intro 0-3 | A 4-19 | B 20-35 | break 36 | A' 37-52 | coda 53-58
	tempo = [(0, 104), (36, 104), (36.999, 84), (37, 104), (55, 104), (57, 82), (57.001, 66), (58, 66),
		(58.001, 100), (59, 100)]
	p = Piece(104, 4, 59, rng, tempo=tempo, swing=0.05)
	A = M15_Aa + M15_Ab
	# --- intro: pizzicato vamp, the motif rises out of the low strings in bar 3 (the curtain)
	bassline(p, "pzb", V.pizzicato, M15_INTRO[:3], 0, [(0, .5, "b"), (2, .5, "5", .8)], lo=34, vel=0.7)
	hits(p, "pzc", V.pizzicato, M15_INTRO[:3], 0, [(1, 1.0), (3, 0.85)], lo=55, hi=67, vel=0.42, length=0.4)
	line(p, "pzb", V.pizzicato, [motif("F2", LANTERN, [("r", 1)])], 3, 0.72)
	p.note("cel", M.celesta, "F6", 1, 3.0, 1.0, 0.25, 0.4)
	p.note("cel", M.celesta, "D6", 2, 3.5, 1.0, 0.22, 0.4)
	# --- A: celesta sings the Lanternwake tune over tiptoe pizzicato
	line(p, "cel", M.celesta, M15_MEL_a + M15_MEL_b, 4, 0.66, 0.1)
	bassline(p, "pzb", V.pizzicato, A, 4, [(0, .5, "b"), (2, .5, "5", .8)], lo=34, vel=0.68)
	hits(p, "pzc", V.pizzicato, A, 4, [(1, 1.0), (3, 0.85)], lo=55, hi=67, vel=0.38, length=0.4)
	perc(p, "perc", M.woodblock, 1250.0, range(5, 20, 2), [(3.5, 1.0)], 0.22, 0.3)
	# --- B: the flute takes a longer-breathed tune in G minor, strings and harp carry it
	line(p, "flute", M.flute, M15_MEL_B, 20, 0.6, -0.1, legato=0.97)
	pads(p, "pad", M.strings, M15_B, 20, lo=55, hi=70, vel=0.42)
	arp(p, "harp", M.harp, M15_B, 20, [(0, "bass", 1.0), (.5, "fifth_lo", .55), (1, "root", .6), (1.5, "third", .55),
		(2, "fifth", .6), (2.5, "top", .5), (3, "fifth", .5), (3.5, "third", .45)], 0.42, -0.3, lo=50)
	bassline(p, "pzb", V.pizzicato, M15_B, 20, [(0, 1, "b"), (2, 1, "5", .75)], lo=34, vel=0.55)
	for bar, notes in ((23, ["A5", "D6", "F#6"]), (27, ["Bb5", "D6", "F6"]), (31, ["A5", "C6", "F6"])):
		for k, nm in enumerate(notes):
			p.note("cel", M.celesta, nm, bar, 3.0 + 0.33 * k, 0.5, 0.3, 0.35)
	# --- break: a sly chromatic run and a held breath
	line(p, "cel", M.celesta, [[("C5", .25), ("D5", .25), ("Eb5", .25), ("E5", .25), ("F5", .25), ("F#5", .25),
		("G5", .25), ("A5", .25), ("C6", .5), ("r", 1.5)]], 36, 0.55, 0.1, accent=0.0)
	p.note("pzb", V.pizzicato, "F2", 36, 0.0, 0.5, 0.7)
	for nm in ("Eb3", "A3"):
		p.note("pzc", V.pizzicato, nm, 36, 2.0, 0.5, 0.45)
	# --- A': celesta again, a bassoon-ish reed sneaks a counter-line in, the flute doubles the second half
	line(p, "cel", M.celesta, M15_MEL_a + M15_MEL_b, 37, 0.7, 0.1)
	guide(p, "reed", V.reed, M15_Aa, 37, 46, 58, 0.5, -0.2)
	line(p, "flute", M.flute, M15_MEL_b, 45, 0.5, -0.15, legato=0.9)
	arp(p, "harp", M.harp, A, 37, [(0, "bass", .9), (1, "root", .5), (1.5, "third", .45), (2, "fifth_lo", .6),
		(3, "third", .5), (3.5, "fifth", .45)], 0.38, -0.3, lo=50)
	bassline(p, "pzb", V.pizzicato, A, 37, [(0, .5, "b"), (2, .5, "5", .8), (3.5, .4, "8", .5)], lo=34, vel=0.7)
	hits(p, "pzc", V.pizzicato, A, 37, [(1, 1.0), (3, 0.85)], lo=55, hi=67, vel=0.4, length=0.4)
	pads(p, "pad", M.strings, M15_Ab, 45, lo=58, hi=72, vel=0.32)
	perc(p, "perc", M.woodblock, 1250.0, range(37, 53), [(1.5, .7), (3.5, 1.0)], 0.2, 0.3)
	perc(p, "perc", M.shaker, 440.0, range(45, 53), [0.5, 1.5, 2.5, 3.5], 0.22, -0.3)
	# --- coda: the motif is tossed from low strings to celesta, a warm cadence, then a pizzicato 'ta-da'
	line(p, "pzb", V.pizzicato, [motif("Eb3", LANTERN, [("r", 1)])], 53, 0.75)
	line(p, "cel", M.celesta, [[("r", 4)], motif("Eb5", LANTERN_MINOR, [("r", 1)]), motif("Bb5", LANTERN, [("r", 1)]),
		[("r", .5), ("Eb5", .5), ("D5", .5), ("C5", .5), ("A4", .5), ("C5", .5), ("F5", 1)]], 53, 0.62, 0.1)
	line(p, "flute", M.flute, [[("r", .5), ("Eb5", .5), ("D5", .5), ("C5", .5), ("A4", .5), ("C5", .5), ("F5", 1)],
		[("D5", 4)]], 56, 0.45, -0.15, legato=0.95)
	bassline(p, "pzb", V.pizzicato, M15_CODA[1:4], 54, [(0, .5, "b"), (2, .5, "5", .8)], lo=34, vel=0.62)
	hits(p, "pzc", V.pizzicato, M15_CODA[:4], 53, [(1, 1.0), (3, 0.85)], lo=55, hi=67, vel=0.36, length=0.4)
	pads(p, "pad", M.strings, M15_CODA[:5], 53, lo=55, hi=70, vel=0.38)
	for k, nm in enumerate(["Bb3", "F4", "Bb4", "D5", "F5", "Bb5"]):
		p.note("harp", M.harp, nm, 57, 0.12 * k, 3.0, 0.5, -0.2 + 0.08 * k)
	for k, nm in enumerate(["Bb4", "D5", "F5", "Bb5", "D6"]):
		p.note("cel", M.celesta, nm, 57, 0.5 + 0.18 * k, 2.0, 0.42, 0.2)
	p.note("pzb", V.pizzicato, "Bb1", 57, 0.0, 1.0, 0.8)
	p.note("pzc", V.pizzicato, "F3", 58, 2.0, 0.4, 0.62, -0.1)
	for nm in ("Bb2", "Bb3", "D4"):
		p.note("pzc", V.pizzicato, nm, 58, 3.0, 0.5, 0.72, 0.1)
	p.note("cel", M.celesta, "Bb6", 58, 3.0, 1.0, 0.3, 0.35)
	p.note("perc", M.woodblock, 1250.0, 58, 3.0, 0.25, 0.25, 0.3)
	levels = {"cel": (0.0, 0.42), "flute": (-3.0, 0.34), "reed": (-3.0, 0.3), "pzb": (2.5, 0.2), "pzc": (0.0, 0.3),
		"harp": (0.0, 0.32), "pad": (-11.0, 0.45), "perc": (-2.0, 0.2)}
	meta = dict(id="m15", title="Welcome to Lanternwake", bpm="104 (swing 0.05; held breath bar 37, rit. in coda)",
		key="Bb major (B section G minor)", meter="4/4",
		sections=[("Intro", 0), ("A", 4), ("B", 20), ("Break", 36), ("A'", 37), ("Coda", 53)],
		instruments="celesta (lead), section pizzicato (bass + offbeat chords), flute (B tune, A' doubling), "
			"bassoon-like reed counter-line (A'), harp, strings pad, woodblock/shaker",
		motif_notes="Establishes the Lanternwake motif: Bb4 F5 E5 F5 G5 D5 (1 5 #4 5 6 3; 8th 8th 16th 16th 8th qtr). "
			"A: motif + answer phrases, sequenced on D, minor-iv (Ebm6) shadow; B: new legato flute tune in G minor; "
			"coda tosses the motif low pizz -> celesta (on Ebm) -> high celesta, pizzicato 'ta-da' button.",
		location_playlist="hallowmere_safe: Lanternwake Commons / regional safe areas (rotate with m16)",
		target=-17.3)
	return p, levels, S.hall(rng, 2.2, brightness=7000), meta


# ==============================================================================================
# m16 "Copper Leaves at Dusk" - A major, 6/8 (dotted quarter = 56), rondo-ish A B C A'' coda
# ==============================================================================================

M16_INTRO = ["A", "D/A", "A", "E7sus4"]
M16_Aa = ["A", "C#m7", "D", "Dm6", "A/C#", "Bm7", [("E7sus4", 3), ("E7", 3)], "A"]
M16_Ab = ["A", "F#m", "D", [("Bm7", 3), ("E7", 3)], "C#m7", "F#m7", [("Bm7", 3), ("E7", 3)], "A"]
M16_B = ["F#m", "C#m/E", "D", "E", "F#m", "Bm/D", "C#7sus4", "C#7", "D", "E", "C#m7", "F#m", "Bm7", "E7",
	[("Bm7", 3), ("E7", 3)], "E7"]
M16_C = ["F", "Dm7", "Bbmaj7", "Gm7", "F/A", "Bbmaj7", "Bbm6", [("E7sus4", 3), ("E7", 3)]]
M16_CODA = ["D", "Dm6", "A/E", [("E7sus4", 3), ("E7", 3)], "A", "Aadd9"]

M16_MEL_a = [
	[("E4", 2), ("A4", 1), ("C#5", 2), ("B4", 1)],
	[("G#4", 3), ("E4", 2), ("r", 1)],
	[("F#4", 2), ("A4", 1), ("D5", 2), ("C#5", 1)],
	[("B4", 3), ("A4", 2), ("F4", 1)],
	[("E4", 2), ("A4", 1), ("E5", 2), ("D5", 1)],
	[("C#5", 2), ("B4", 1), ("D5", 2), ("F#4", 1)],
	[("A4", 3), ("G#4", 2), ("B4", 1)],
	[("A4", 3), ("r", 3)],
]
M16_MEL_b = [
	[("E4", 2), ("A4", 1), ("C#5", 2), ("E5", 1)],
	[("F#5", 3), ("C#5", 2), ("A4", 1)],
	[("B4", 2), ("A4", 1), ("F#4", 2), ("A4", 1)],
	[("D5", 2), ("C#5", 1), ("B4", 2), ("G#4", 1)],
	[("E5", 3), ("G#4", 2), ("B4", 1)],
	[("A4", 2), ("C#5", 1), ("E5", 2), ("C#5", 1)],
	[("D5", 3), ("B4", 2), ("D5", 1)],
	[("C#5", 2), ("B4", 1), ("A4", 3)],
]
M16_MEL_B = [
	[("C#5", 2), ("F#5", 2), ("A5", 2)],
	[("G#5", 3), ("E5", 3)],
	[("F#5", 2), ("E5", 2), ("D5", 2)],
	[("B4", 3), ("E5", 2), ("r", 1)],
	[("C#5", 2), ("F#5", 2), ("A5", 2)],
	[("B5", 3), ("F#5", 2), ("D5", 1)],
	[("F#5", 3), ("G#5", 2), ("F#5", 1)],
	[("E#5", 3), ("G#5", 2), ("r", 1)],
	[("F#5", 2), ("A5", 2), ("D6", 2)],
	[("B5", 3), ("G#5", 2), ("E5", 1)],
	[("E5", 2), ("G#5", 2), ("B5", 2)],
	[("A5", 3), ("F#5", 2), ("C#5", 1)],
	[("D5", 2), ("F#5", 2), ("A5", 2)],
	[("G#5", 2), ("B5", 1), ("D6", 3)],
	[("C#6", 2), ("B5", 1), ("A5", 2), ("G#5", 1)],
	[("B5", 3), ("r", 3)],
]
M16_C_CELLO = [
	[("C3", 2), ("F3", 1), ("A3", 2), ("G3", 1)],
	[("F3", 3), ("D3", 3)],
	[("D3", 2), ("F3", 1), ("A3", 3)],
	[("Bb2", 3), ("D3", 3)],
	[("A2", 3), ("C3", 3)],
	[("D3", 3), ("F3", 3)],
	[("Db3", 3), ("F3", 3)],
	[("E3", 3), ("D3", 3)],
]
M16_C_CEL = [
	[("r", 6)],
	[("A4", 2), ("D5", 1), ("F5", 2), ("E5", 1)],
	[("r", 6)],
	[("Bb4", 2), ("D5", 1), ("F5", 3)],
	[("C5", 2), ("F5", 1), ("A5", 2), ("G5", 1)],
	[("F5", 3), ("D5", 3)],
	[("F5", 3), ("Db5", 3)],
	[("B4", 3), ("G#4", 3)],
]
M16_MEL_CODA = [
	[("F#4", 2), ("A4", 1), ("D5", 2), ("C#5", 1)],
	[("B4", 3), ("F4", 2), ("r", 1)],
	[("E4", 2), ("A4", 1), ("C#5", 3)],
	[("D5", 3), ("B4", 2), ("G#4", 1)],
	[("A4", 6)],
	[("r", 6)],
]
ROLL_68 = [(0, "bass", 1.0), (1, "root", .55), (2, "third", .6), (3, "fifth", .7), (4, "top", .55), (5, "third", .5)]
HEMIOLA_68 = [(0, "bass", 1.0), (2, "root", .5), (2, "third", .48), (2, "fifth", .45), (4, "root", .5), (4, "third", .45),
	(4, "fifth", .42)]


def m16(rng):
	# bars: intro 0-3 | A 4-19 | B 20-35 | C 36-43 | A'' 44-51 | coda 52-57
	tempo = [(0, 168), (35, 168), (36, 158), (36.001, 160), (44, 160), (44.001, 168), (54, 168), (56, 132), (58, 118)]
	p = Piece(168, 6, 58, rng, tempo=tempo)
	A = M16_Aa + M16_Ab
	# intro: rolling harp, dusk strings enter
	arp(p, "harp", M.harp, M16_INTRO, 0, ROLL_68, 0.45, -0.2, lo=52, beats=2.0)
	pads(p, "pad", M.strings, M16_INTRO[1:], 1, lo=52, hi=66, vel=0.36)
	bassline(p, "bass", M.pluck_bass, M16_INTRO[2:], 2, [(0, 2.6, "b")], lo=40, vel=0.6)
	# A: a warm viola-like section tune over rolling harp
	line(p, "lead", V.warm_strings, M16_MEL_a + M16_MEL_b, 4, 0.62, 0.05, legato=1.0, attack=0.12)
	arp(p, "harp", M.harp, A, 4, ROLL_68, 0.45, -0.2, lo=52, beats=2.0)
	pads(p, "pad", M.strings, A, 4, lo=50, hi=64, vel=0.32)
	bassline(p, "bass", M.pluck_bass, A, 4, [(0, 2.6, "b"), (3, 2.6, "5", .75)], lo=40, vel=0.7)
	for bar, notes in ((11, ["E6", "C#6", "A5"]), (19, ["A5", "C#6", "E6"])):
		for k, nm in enumerate(notes):
			p.note("cel", M.celesta, nm, bar, 3 + k, 1.0, 0.3, 0.35)
	# B: a little musette dances a hemiola tune in F# minor; the harp switches to 3/4 chords
	line(p, "mus", V.musette, M16_MEL_B, 20, 0.58, 0.15, legato=0.92)
	arp(p, "harp", M.harp, M16_B, 20, HEMIOLA_68, 0.42, -0.25, lo=54, beats=1.8)
	pads(p, "pad", M.strings, M16_B, 20, lo=50, hi=64, vel=0.3)
	bassline(p, "bass", M.pluck_bass, M16_B, 20, [(0, 2.6, "b"), (3, 2.6, "5", .7)], lo=40, vel=0.68)
	perc(p, "perc", M.tom, 96.0, range(20, 36), [(0, 1.0), (3, .6)], 0.4, 0.0)
	perc(p, "perc", M.shaker, 440.0, range(20, 36), [(1, .7), (2, .5), (4, .7), (5, .5)], 0.22, 0.3)
	perc(p, "perc", V.tambourine, 1.0, (20, 28), [(0, 1.0)], 0.3, -0.3)
	# C: dusk - F major, the tune's opening turns into a canon between low strings and celesta
	line(p, "cello", V.warm_strings, M16_C_CELLO, 36, 0.48, -0.15, legato=1.0, attack=0.25, cutoff_mul=4.0)
	line(p, "cel", M.celesta, M16_C_CEL, 36, 0.44, 0.3)
	arp(p, "harp", M.harp, M16_C, 36, [(0, "bass", 1.0), (3, "fifth", .55), (4, "top", .45)], 0.3, -0.2, lo=52, beats=2.5)
	pads(p, "pad", M.pad, M16_C, 36, lo=55, hi=69, vel=0.28, attack=1.2, cutoff=1100)
	# (review: at vel 0.38 this sustained sine bass was the loudest bus of the section and put ~37 % of
	# the section's energy below 120 Hz, crowding the low canon voice; -4 dB keeps the warmth)
	bassline(p, "bass", M.soft_bass, M16_C, 36, [(0, 5.5, "b")], lo=40, vel=0.24)
	# A'': home again - the tune with a musette counter-line in close harmony
	line(p, "lead", V.warm_strings, M16_MEL_a, 44, 0.66, 0.05, legato=1.0, attack=0.12)
	guide(p, "mus", V.musette, M16_Aa, 44, 64, 73, 0.28, 0.2)
	arp(p, "harp", M.harp, M16_Aa, 44, ROLL_68, 0.48, -0.2, lo=52, beats=2.0)
	pads(p, "pad", M.strings, M16_Aa, 44, lo=50, hi=64, vel=0.34)
	bassline(p, "bass", M.pluck_bass, M16_Aa, 44, [(0, 2.6, "b"), (3, 2.6, "5", .75)], lo=40, vel=0.72)
	perc(p, "perc", M.shaker, 440.0, range(44, 52), [(1, .6), (2, .45), (4, .6), (5, .45)], 0.2, 0.3)
	# coda: slower, the last phrase settles; harp rolls up and the celesta leaves the ninth hanging
	line(p, "lead", V.warm_strings, M16_MEL_CODA, 52, 0.6, 0.05, legato=1.0, attack=0.14)
	arp(p, "harp", M.harp, M16_CODA[:4], 52, ROLL_68, 0.44, -0.2, lo=52, beats=2.0)
	pads(p, "pad", M.strings, M16_CODA, 52, lo=50, hi=66, vel=0.34)
	bassline(p, "bass", M.pluck_bass, M16_CODA[:5], 52, [(0, 2.6, "b"), (3, 2.6, "5", .7)], lo=40, vel=0.65)
	for k, nm in enumerate(["A2", "E3", "A3", "C#4", "E4", "B4", "C#5", "E5"]):
		p.note("harp", M.harp, nm, 56, 0.35 * k, 4.0, 0.5, -0.3 + 0.08 * k)
	p.note("cel", M.celesta, "B5", 57, 0.0, 2.0, 0.32, 0.3)
	p.note("cel", M.celesta, "E6", 57, 1.5, 2.0, 0.24, 0.35)
	levels = {"lead": (-1.0, 0.38), "mus": (-2.0, 0.3), "cello": (-4.0, 0.35), "cel": (-6.0, 0.45), "harp": (-2.0, 0.3),
		"pad": (-16.0, 0.45), "bass": (-8.0, 0.12), "perc": (-11.0, 0.18)}
	meta = dict(id="m16", title="Copper Leaves at Dusk", bpm="dotted quarter 56 (eighth 168), rit. in coda",
		key="A major (B: F# minor, C: F major)", meter="6/8",
		sections=[("Intro", 0), ("A", 4), ("B", 20), ("C", 36), ("A''", 44), ("Coda", 52)],
		instruments="warm section strings (viola-register lead), musette (bellows reed; B tune and A'' counter-line), "
			"harp 6/8 rolls and 3/4 hemiola chords, low strings canon, celesta, plucked bass, frame drum/shaker/tambourine",
		motif_notes="Own tune (not the Lanternwake motif): a lilting rising sixth E4-A4-C#5 that falls back by step; "
			"B is a hemiola musette dance (2+2+2 against 6/8); C is a loose canon (free imitation) on the tune's "
			"opening between low strings and celesta in F major (bVI), turning back via Bbm6 -> E7.",
		location_playlist="hallowmere_explore: Hallowmere travel / festival outskirts (rotate with m15)",
		target=-17.5)
	return p, levels, S.hall(rng, 2.4, brightness=6500), meta


# ==============================================================================================
# m17 "Pumpkin Patch Parade" - C major, 4/4, 96 bpm, light shuffle
# ==============================================================================================

M17_INTRO = ["C", "Am7", "Dm7", "G7"]
M17_Aa = ["C", [("F", 2), ("C/E", 2)], [("Dm7", 2), ("G7", 2)], "C", "Am", [("F", 2), ("Fm6", 2)],
	[("C/G", 2), ("G7", 2)], "C"]
M17_Ab = M17_Aa[:4] + [[("E7", 2), ("Am", 2)], [("D7", 2), ("G", 2)], [("F", 2), ("G7", 2)], "C"]
M17_B = ["Am", "Am/G", "Fmaj7", [("E7sus4", 2), ("E7", 2)], "Am", "Dm7", "G7", "Cmaj7", "Fmaj7", "Em7", "Dm7", "G7",
	"Am", "F", "Dm7", [("G7sus4", 2), ("G7", 2)]]
M17_CODA = [[("F", 2), ("Fm6", 2)], [("C/G", 2), ("G7", 2)], "C", "C"]

M17_MEL_a = [
	[("C3", .5, "s"), ("E3", .5, "s"), ("G3", .5, "s"), ("E3", .5, "s"), ("A3", 1), ("G3", 1)],
	[("A3", .5, "s"), ("F3", .5, "s"), ("A3", .5, "s"), ("C4", .5, "s"), ("G3", 1), ("E3", 1)],
	[("F3", .5, "s"), ("E3", .5, "s"), ("D3", .5, "s"), ("F3", .5, "s"), ("B2", 1), ("D3", 1)],
	[("C3", 1.5), ("G2", .5, "s"), ("C3", 1, "s"), ("r", 1)],
	[("E3", .5, "s"), ("A3", .5, "s"), ("C4", .5, "s"), ("A3", .5, "s"), ("B3", 1), ("C4", 1)],
	[("A3", 1), ("C4", .5, "s"), ("A3", .5, "s"), ("Ab3", 1), ("F3", 1)],
	[("G3", 1), ("E3", .5, "s"), ("C3", .5, "s"), ("D3", .5, "s"), ("F3", .5, "s"), ("B2", 1)],
	[("C3", 1, "s"), ("r", 1), ("G2", .5, "s"), ("r", .5), ("C3", .5, "s"), ("r", .5)],
]
M17_MEL_b = M17_MEL_a[:4] + [
	[("G#3", 1), ("B3", .5, "s"), ("D4", .5, "s"), ("C4", 1), ("A3", 1)],
	[("F#3", .5, "s"), ("A3", .5, "s"), ("C4", .5, "s"), ("A3", .5, "s"), ("B3", 1), ("G3", 1)],
	[("A3", .5, "s"), ("C4", .5, "s"), ("F4", 1), ("D4", .5, "s"), ("B3", .5, "s"), ("G3", 1)],
	[("C4", 1.5), ("G3", .5, "s"), ("C3", 1, "s"), ("r", 1)],
]
M17_MEL_B = [
	[("E5", 3), ("C5", 1)],
	[("B4", 2), ("A4", 1), ("G4", 1)],
	[("A4", 2), ("C5", 1), ("E5", 1)],
	[("D5", 2), ("G#4", 2)],
	[("C5", 1), ("E5", 1), ("A5", 2)],
	[("F5", 2), ("E5", 1), ("D5", 1)],
	[("B4", 2), ("D5", 1), ("F5", 1)],
	[("E5", 3), ("r", 1)],
	[("A5", 2), ("G5", 1), ("F5", 1)],
	[("G5", 2), ("E5", 1), ("B4", 1)],
	[("F5", 1.5), ("E5", .5), ("D5", 1), ("A4", 1)],
	[("B4", 2), ("D5", 1), ("G5", 1)],
	[("C6", 2), ("B5", 1), ("A5", 1)],
	[("A5", 1.5), ("G5", .5), ("F5", 1), ("C5", 1)],
	[("D5", 1), ("F5", 1), ("A5", 1), ("C6", 1)],
	[("C6", 2), ("B5", 2)],
]
MAR_ARP = [(0, "root", .7), (.5, "third", .45), (1, "fifth", .5), (1.5, "top", .4), (2, "third_hi", .5), (2.5, "top", .4),
	(3, "fifth", .45), (3.5, "third", .4)]


def m17(rng):
	# bars: intro 0-3 | A 4-19 | B 20-35 | A' 36-43 | A'' 44-51 | coda 52-55
	tempo = [(0, 96), (53, 96), (55, 84), (56, 80)]
	p = Piece(96, 4, 56, rng, tempo=tempo, swing=0.1)
	A = M17_Aa + M17_Ab
	A2 = M17_Aa[:4] + M17_Ab[4:]
	# intro: marimba and clacks set up the little parade
	hits(p, "mar", V.marimba, M17_INTRO, 0, [(1, 1.0), (3, 0.9)], lo=60, hi=72, vel=0.42, length=0.5, roll=0.02)
	bassline(p, "bass", M.pluck_bass, M17_INTRO, 0, [(0, .9, "b"), (2, .9, "5", .8)], lo=36, vel=0.7)
	perc(p, "perc", V.clack, 2300.0, range(0, 4), [(1, 1.0), (3, 1.0)], 0.35, 0.25)
	perc(p, "perc", M.woodblock, 760.0, (1, 3), [(3.5, 1.0)], 0.3, -0.25)
	pads(p, "str", V.warm_strings, M17_INTRO[2:], 2, lo=64, hi=76, vel=0.3, attack=0.8)
	# A: the bassoon-ish reed leads, marimba 'pah' on the backbeats, soft drum and clacks
	line(p, "reed", V.reed, M17_MEL_a + M17_MEL_b, 4, 0.72, -0.05, legato=0.92)
	hits(p, "mar", V.marimba, A, 4, [(1, 1.0), (3, 0.9)], lo=60, hi=72, vel=0.38, length=0.5, roll=0.02)
	bassline(p, "bass", M.pluck_bass, A, 4, [(0, .9, "b"), (2, .9, "5", .8)], lo=36, vel=0.72)
	pads(p, "str", V.warm_strings, M17_Ab, 12, lo=64, hi=76, vel=0.26, attack=0.6)
	perc(p, "perc", M.tom, 62.0, range(4, 20), [(0, 1.0), (2, .75)], 0.45, 0.0)
	perc(p, "perc", V.clack, 2300.0, range(4, 20), [(1, 1.0), (3, .9)], 0.3, 0.25)
	perc(p, "perc", M.woodblock, 760.0, range(5, 20, 2), [(3.5, 1.0)], 0.26, -0.25)
	# B: warm strings sing in A minor; marimba ripples; the parade drum rests
	line(p, "str", V.warm_strings, M17_MEL_B, 20, 0.62, 0.05, legato=1.0, attack=0.2)
	arp(p, "mar", V.marimba, M17_B, 20, MAR_ARP, 0.36, -0.1, lo=55, beats=0.5)
	pads(p, "pad", M.strings, M17_B, 20, lo=52, hi=64, vel=0.3)
	# (review: at vel 0.4 the sustained sine bass out-weighed the string tune in raw energy and made B
	# the boomiest passage in the catalogue (-5.7 dB of energy below 120 Hz vs -14.6 in A); -4 dB)
	bassline(p, "bass", M.soft_bass, M17_B, 20, [(0, 1.8, "b"), (2, 1.8, "5", .8)], lo=38, vel=0.25)
	perc(p, "perc", M.shaker, 440.0, range(20, 36), [(1, 1.0), (3, 1.0)], 0.2, 0.3)
	perc(p, "perc", V.clack, 2300.0, (27, 35), [(3, 1.0), (3.5, .7)], 0.25, 0.25)
	# A': role swap - marimba plays the tune up high, the reed goes 'oom-pah' underneath
	line(p, "mar", V.marimba, M17_MEL_a, 36, 0.55, 0.15, tr=24, legato=1.0)
	bassline(p, "reed", V.reed, M17_Aa, 36, [(0, .35, "b"), (1, .3, "5", .7), (2, .35, "8", .85), (3, .3, "5", .7)],
		lo=43, vel=0.55)
	bassline(p, "bass", M.pluck_bass, M17_Aa, 36, [(0, .9, "b"), (2, .9, "5", .8)], lo=36, vel=0.62)
	pads(p, "str", V.warm_strings, M17_Aa, 36, lo=64, hi=76, vel=0.24, attack=0.5)
	perc(p, "perc", M.tom, 62.0, range(36, 44), [(0, 1.0), (2, .75)], 0.42, 0.0)
	perc(p, "perc", V.clack, 2300.0, range(36, 44), [(1, 1.0), (3, .9), (3.5, .5)], 0.3, 0.25)
	# A'': everybody - reed tune, marimba two octaves up, strings, shaker
	line(p, "reed", V.reed, M17_MEL_b, 44, 0.75, -0.05, legato=0.92)
	line(p, "mar", V.marimba, M17_MEL_b, 44, 0.4, 0.2, tr=24, legato=1.0)
	hits(p, "mar", V.marimba, A2, 44, [(1, 1.0), (3, 0.9)], lo=60, hi=72, vel=0.3, length=0.5, roll=0.02)
	bassline(p, "bass", M.pluck_bass, A2, 44, [(0, .9, "b"), (2, .9, "5", .8)], lo=36, vel=0.74)
	pads(p, "str", V.warm_strings, A2, 44, lo=62, hi=76, vel=0.3, attack=0.4)
	perc(p, "perc", M.tom, 62.0, range(44, 52), [(0, 1.0), (2, .75)], 0.46, 0.0)
	perc(p, "perc", V.clack, 2300.0, range(44, 52), [(1, 1.0), (3, .9)], 0.3, 0.25)
	perc(p, "perc", M.shaker, 440.0, range(44, 52), [.5, 1.5, 2.5, 3.5], 0.22, -0.3)
	# coda: a last sigh (F -> Fm), a marimba scamper and a two-note 'pum-pum' button
	line(p, "reed", V.reed, [[("A3", 1), ("C4", 1), ("Ab3", 1), ("F3", 1)], [("E3", 1), ("C3", 1), ("B2", 1), ("D3", 1)],
		[("C3", 2), ("r", 2)], [("r", 1), ("G2", .5, "s"), ("r", .5), ("C2", .5, "s"), ("r", 1.5)]], 52, 0.7, -0.05)
	line(p, "mar", V.marimba, [[("r", 4)], [("G5", .5), ("E5", .5), ("C5", .5), ("E5", .5), ("D5", .5), ("F5", .5),
		("B4", .5), ("D5", .5)]], 52, 0.45, 0.2)
	pads(p, "str", V.warm_strings, M17_CODA[:3], 52, lo=62, hi=76, vel=0.3, attack=0.4)
	bassline(p, "bass", M.pluck_bass, M17_CODA[:3], 52, [(0, .9, "b"), (2, .9, "5", .8)], lo=36, vel=0.65)
	for nm in ("C5", "E5", "G5", "C6"):
		p.note("mar", V.marimba, nm, 54, 0.0, 1.0, 0.45, 0.1)
	for nm in ("C4", "C5"):
		p.note("mar", V.marimba, nm, 55, 2.0, 1.0, 0.5, 0.1)
	perc(p, "perc", V.clack, 2300.0, (52,), [(1, .8), (3, .7)], 0.28, 0.25)
	p.note("perc", V.clack, 2300.0, 55, 2.0, 0.25, 0.4, 0.25)
	p.note("perc", M.tom, 62.0, 55, 2.0, 0.25, 0.5, 0.0)
	levels = {"reed": (-1.0, 0.25), "mar": (-1.0, 0.28), "str": (0.0, 0.35), "pad": (-14.0, 0.4), "bass": (-6.0, 0.1),
		"perc": (-5.0, 0.16)}
	meta = dict(id="m17", title="Pumpkin Patch Parade", bpm="96 (light shuffle 0.1), small rit. on the last bars",
		key="C major (B section A minor)", meter="4/4",
		sections=[("Intro", 0), ("A", 4), ("B", 20), ("A'", 36), ("A''", 44), ("Coda", 52)],
		instruments="bassoon-like reed (lead / oom-pah), marimba (backbeat chords, arpeggios, tune in A'), warm strings "
			"(B tune, pads), plucked bass, little clacks (claves), woodblock, soft parade drum, shaker",
		motif_notes="Own tune: a bouncing staccato arpeggio C-E-G-E answered by legato steps, with a comic minor-iv "
			"sigh (A-C-Ab-F) in bar 6. B: lyrical A-minor string tune (no drum). A' swaps roles (marimba tune, reed oom-pah).",
		location_playlist="hallowmere_orchard: Orchard / seasonal gardening",
		target=-17.0)
	return p, levels, S.hall(rng, 1.8, brightness=7500), meta


# ==============================================================================================
# m18 "Stone Bells, Quiet Hills" - E minor / Dorian, 4/4, 84 bpm
# ==============================================================================================

M18_INTRO = ["Em", "D/E", "Cmaj7/E", "Em"]
M18_A = ["Em", "Em", "D", "D", "A/C#", "C", "G/B", "Bm", "Em", "Em", "D", "A/C#", "C", "Am7", "B7sus4", "B7"]
M18_B = ["C", "G/B", "Am7", "Em", "C", "D", "G", "Bm", "C", "Am7", "Dsus4", "D"]
M18_INTER = ["Em", "Cmaj7", "Am7", "B7sus4"]
M18_A2 = M18_A[:8] + M18_A[12:]
M18_CODA = ["Em", "C", "D", "E"]

M18_MEL_A = [
	[("B3", 2), ("E4", 2)],
	[("F#4", 1.5), ("G4", .5), ("F#4", 1), ("E4", 1)],
	[("D4", 3), ("A3", 1)],
	[("F#4", 2), ("E4", 1), ("D4", 1)],
	[("C#4", 2), ("E4", 2)],
	[("G4", 3), ("E4", 1)],
	[("D4", 2), ("G4", 1.5), ("A4", .5)],
	[("B4", 4)],
	[("B3", 2), ("E4", 2)],
	[("G4", 1.5), ("A4", .5), ("B4", 2)],
	[("A4", 2), ("F#4", 1), ("D4", 1)],
	[("E4", 3), ("A4", 1)],
	[("G4", 2), ("C5", 2)],
	[("B4", 1), ("A4", 1), ("E4", 2)],
	[("E4", 2), ("F#4", 2)],
	[("D#4", 3), ("r", 1)],
]
M18_MEL_B = [
	[("G4", 1), ("C5", 1), ("E5", 2)],
	[("D5", 3), ("B4", 1)],
	[("C5", 2), ("E5", 1), ("G5", 1)],
	[("G5", 2), ("F#5", 1), ("E5", 1)],
	[("E5", 1), ("G5", 1), ("C6", 2)],
	[("A5", 2), ("F#5", 1), ("D5", 1)],
	[("D5", 1), ("G5", 1), ("B5", 2)],
	[("A5", 1), ("F#5", 1), ("D5", 2)],
	[("E5", 2), ("G5", 2)],
	[("A5", 2), ("E5", 1), ("C5", 1)],
	[("D5", 2), ("G5", 2)],
	[("F#5", 3), ("r", 1)],
]
M18_MEL_CODA = [[("B3", 2), ("E4", 2)], [("G4", 4)], [("F#4", 2), ("A4", 2)], [("G#4", 4)]]
PLUCK_Q = [(0, 1.0, "b"), (1, 1.0, "5", .6), (2, 1.0, "8", .72), (3, 1.0, "5", .6)]
PLUCK_B = [(0, 1.5, "b"), (1.5, .5, "5", .6), (2, 1.0, "8", .75), (3, 1.0, "5", .6)]
PLUCK_H = [(0, 2.0, "b"), (2, 2.0, "5", .65)]


def m18(rng):
	# bars: intro 0-3 | A 4-19 | B 20-31 | interlude 32-35 | A' 36-47 | coda 48-51
	tempo = [(0, 84), (31, 84), (32, 78), (35, 78), (36, 84), (49, 84), (51, 66), (52, 58)]
	p = Piece(84, 4, 52, rng, tempo=tempo)
	# intro: measured low plucks over an E pedal, a stone bell answers
	bassline(p, "pluck", V.stone_pluck, M18_INTRO, 0, PLUCK_H, lo=40, vel=0.7)
	pads(p, "pad", M.pad, M18_INTRO[1:], 1, lo=55, hi=69, vel=0.42, attack=1.5, cutoff=1000)
	p.note("bell", V.stone_bell, "E4", 0, 0.0, 4.0, 0.55, 0.2)
	p.note("bell", V.metal_ting, "B5", 2, 2.0, 1.0, 0.35, -0.4)
	line(p, "horn", V.warm_horn, [[("r", 2), ("B3", 2)], [("E4", 3), ("r", 1)]], 2, 0.42, 0.2, legato=1.0)
	# A: horns set out on a broad Dorian theme
	line(p, "horn", V.warm_horn, M18_MEL_A, 4, 0.6, -0.1, legato=0.98)
	bassline(p, "pluck", V.stone_pluck, M18_A, 4, PLUCK_Q, lo=40, vel=0.66)
	pads(p, "pad", M.strings, M18_A[8:], 12, lo=52, hi=67, vel=0.34)
	bassline(p, "bass", M.soft_bass, M18_A[8:], 12, [(0, 3.6, "b")], lo=40, vel=0.45)
	p.note("bell", V.stone_bell, "E4", 4, 0.0, 4.0, 0.5, 0.25)
	p.note("bell", V.stone_bell, "B3", 12, 0.0, 4.0, 0.45, -0.2)
	p.note("bell", V.metal_ting, "E6", 8, 3.0, 1.0, 0.3, 0.45)
	p.note("bell", V.metal_ting, "F#5", 17, 2.0, 1.0, 0.28, -0.45)
	# B: the hills open - strings climb through C major, horns answer below
	line(p, "str", V.warm_strings, M18_MEL_B, 20, 0.62, 0.1, legato=1.0, attack=0.25)
	guide(p, "horn", V.warm_horn, M18_B, 20, 55, 64, 0.48, -0.15)
	bassline(p, "pluck", V.stone_pluck, M18_B, 20, PLUCK_B, lo=40, vel=0.66)
	pads(p, "pad", M.strings, M18_B, 20, lo=50, hi=64, vel=0.32)
	bassline(p, "bass", M.soft_bass, M18_B, 20, [(0, 3.6, "b")], lo=40, vel=0.5)
	for bar in (20, 24, 28):
		p.note("timp", V.timpani, "C2", bar, 0.0, 1.0, 0.45)
	p.note("bell", V.stone_bell, "G4", 20, 0.0, 4.0, 0.42, 0.3)
	p.note("bell", V.metal_ting, "B5", 25, 3.0, 1.0, 0.26, 0.4)
	p.note("bell", V.stone_bell, "E4", 28, 0.0, 4.0, 0.4, -0.25)
	# interlude: only stones and bells - the quarry breathing
	line(p, "bell", V.stone_bell, [[("E4", 4)], [("G4", 2), ("r", 2)], [("A3", 4)], [("B3", 2), ("F#4", 2)]], 32, 0.55, 0.15)
	p.note("bell", V.metal_ting, "B5", 33, 2.0, 1.0, 0.3, -0.45)
	p.note("bell", V.metal_ting, "E6", 34, 3.0, 1.0, 0.25, 0.45)
	bassline(p, "pluck", V.stone_pluck, M18_INTER, 32, PLUCK_H, lo=40, vel=0.6)
	pads(p, "pad", M.pad, M18_INTER, 32, lo=55, hi=69, vel=0.36, attack=1.5, cutoff=1000)
	roll(p, "timp", V.timpani, "B1", 35, 2.0, 2.0, 0.12, 0.5)
	# A': theme again, strings in octaves above the horns, timpani underline the arrivals
	line(p, "horn", V.warm_horn, M18_MEL_A[:8] + M18_MEL_A[12:], 36, 0.64, -0.1, legato=0.98)
	line(p, "str", V.warm_strings, M18_MEL_A[:8] + M18_MEL_A[12:], 36, 0.5, 0.15, tr=12, legato=1.0, attack=0.25)
	bassline(p, "pluck", V.stone_pluck, M18_A2, 36, PLUCK_Q + [(3.5, .5, "8", .45)], lo=40, vel=0.68)
	pads(p, "pad", M.strings, M18_A2, 36, lo=50, hi=64, vel=0.34)
	bassline(p, "bass", M.soft_bass, M18_A2, 36, [(0, 3.6, "b")], lo=40, vel=0.5)
	p.note("timp", V.timpani, "E2", 36, 0.0, 1.0, 0.6)
	p.note("bell", V.stone_bell, "E3", 36, 0.0, 4.0, 0.55, 0.0)
	p.note("timp", V.timpani, "E2", 40, 0.0, 1.0, 0.4)
	p.note("bell", V.metal_ting, "E6", 42, 2.0, 1.0, 0.26, 0.4)
	roll(p, "timp", V.timpani, "B1", 47, 0.0, 3.0, 0.15, 0.45)
	# coda: the theme's first gesture, then E major (Picardy) with a last bell
	line(p, "horn", V.warm_horn, M18_MEL_CODA, 48, 0.6, -0.1, legato=1.0)
	line(p, "str", V.warm_strings, M18_MEL_CODA, 48, 0.42, 0.15, tr=12, legato=1.0, attack=0.3)
	bassline(p, "pluck", V.stone_pluck, M18_CODA, 48, PLUCK_H, lo=40, vel=0.62)
	pads(p, "pad", M.strings, M18_CODA, 48, lo=52, hi=68, vel=0.34)
	bassline(p, "bass", M.soft_bass, M18_CODA, 48, [(0, 3.8, "b")], lo=40, vel=0.48)
	p.note("timp", V.timpani, "E2", 51, 0.0, 1.0, 0.5)
	p.note("bell", V.stone_bell, "E4", 51, 0.0, 4.0, 0.5, 0.2)
	p.note("bell", V.metal_ting, "G#5", 51, 1.5, 1.0, 0.3, -0.35)
	levels = {"horn": (-2.0, 0.34), "str": (4.0, 0.38), "pluck": (-4.0, 0.25), "bell": (-2.0, 0.5), "pad": (-13.0, 0.45),
		"bass": (-10.0, 0.1), "timp": (-8.0, 0.3)}
	meta = dict(id="m18", title="Stone Bells, Quiet Hills", bpm="84 (interlude 78, rit. in coda)",
		key="E Dorian / E minor (B section C major), ends on E major", meter="4/4",
		sections=[("Intro", 0), ("A", 4), ("B", 20), ("Interlude", 32), ("A'", 36), ("Coda", 48)],
		instruments="low wire-and-wood plucks (measured quarter notes), warm horn pair (theme), warm strings, "
			"stone bells (tierce bell) and small struck-metal tings, timpani, pad, soft bass",
		motif_notes="Own theme: a rising fourth B3-E4 that climbs by broad steps to B4 over Em-D-A/C#-C-G/B-Bm "
			"(the C# gives the Dorian colour). B: strings climb through C-G/B-Am7 to a high C6. Interlude: bells only. "
			"Coda: Picardy E major with a last bell.",
		location_playlist="ashbell_quarry: Ashbell Quarry exploration",
		target=-17.3)
	return p, levels, S.hall(rng, 2.8, brightness=5500), meta


# ==============================================================================================
# m19 "Candles for the Moon" - A minor, 3/4, 66 bpm lullaby
# ==============================================================================================

M19_INTRO = ["Am", "Fmaj7", "Am", "E7sus4"]
M19_A = ["Am", "G", "Fmaj7", "E7", "Am", "Dm/F", "E7sus4", "E7", "Am", "G", "Fmaj7", "Bb", "Am/E", "Dm6", "E7", "Am"]
M19_B = ["F", "Dm7", "Bbmaj7", "C", "Ab", "Fm6", "E7sus4", "E7", "F", "Dm7", "Bbmaj7", "E7"]
M19_A2 = M19_A[:8] + M19_A[12:]
M19_CODA = ["Am", "Fmaj7", "Dm6", "E7", "Aadd9", "Aadd9"]

M19_MEL_A = [
	[("E5", 1), ("C5", 1), ("A4", 1)],
	[("B4", 1.5), ("C5", .5), ("B4", 1)],
	[("A4", 1), ("C5", 1), ("E5", 1)],
	[("D5", 2), ("B4", 1)],
	[("C5", 1), ("E5", 1), ("A5", 1)],
	[("A5", 1.5), ("F5", .5), ("D5", 1)],
	[("E5", 2), ("D5", 1)],
	[("G#4", 3)],
	[("E5", 1), ("C5", 1), ("A4", 1)],
	[("B4", 1.5), ("C5", .5), ("D5", 1)],
	[("E5", 2), ("C5", 1)],
	[("D5", 1.5), ("F5", .5), ("Bb4", 1)],
	[("C5", 2), ("E5", 1)],
	[("F5", 1), ("D5", 1), ("B4", 1)],
	[("B4", 1.5), ("G#4", .5), ("E4", 1)],
	[("A4", 3)],
]
M19_MEL_B = [
	[("C5", 2), ("A4", 1)],
	[("F5", 2), ("E5", 1)],
	[("D5", 3)],
	[("C5", 2), ("E5", 1)],
	[("Eb5", 3)],
	[("D5", 2), ("C5", 1)],
	[("B4", 3)],
	[("G#4", 2), ("B4", 1)],
	[("A4", 1), ("C5", 1), ("F5", 1)],
	[("E5", 2), ("D5", 1)],
	[("D5", 1.5), ("C5", .5), ("A4", 1)],
	[("G#4", 3)],
]
M19_MEL_CODA = [
	[("E5", 1), ("C5", 1), ("A4", 1)],
	[("A4", 1), ("C5", 1), ("E5", 1)],
	[("F5", 2), ("D5", 1)],
	[("G#4", 2), ("B4", 1)],
	[("C#5", 3)],
	[("r", 3)],
]
ROCK_34 = [(0, "bass", .9), (1, "root", .45), (1, "third", .4), (2, "fifth", .4), (2, "third", .35)]


def m19(rng):
	# bars: intro 0-3 | A 4-19 | B 20-31 | A' 32-43 | coda 44-49
	tempo = [(0, 66), (30, 66), (32, 58), (32.001, 64), (44, 64), (47, 56), (50, 46)]
	p = Piece(66, 3, 50, rng, tempo=tempo, tail=9.0)
	# (review: the choir's fixed 'oo' formant at 330 Hz, plus the E4 common tone the pad voicing holds through
	# most chords, made one steady band 9-15 dB above its neighbours (the intro had ~85 % of its energy in
	# 200-500 Hz). A broad dip evens out the chord tones; the 'oo' colour stays.)
	p.bus_eq = {"choir": [("peak", 330.0, -5.0, 1.6)], "choirlead": [("peak", 330.0, -3.0, 1.6)]}
	# intro: a wordless 'oo' choir alone, the harp starts rocking in bar 2
	pads(p, "choir", V.choir, M19_INTRO, 0, lo=55, hi=67, vel=0.5, overlap=0.4, vowel="oo", attack=1.4, voices=4)
	arp(p, "harp", M.harp, M19_INTRO[2:], 2, ROCK_34, 0.4, -0.2, lo=57, beats=1.5)
	bassline(p, "low", V.warm_strings, M19_INTRO[1:], 1, [(0, 3.0, "b")], lo=38, vel=0.4, attack=0.8, cutoff_mul=3.0)
	# A: the lullaby on glass harmonica
	line(p, "glass", V.glass_harp, M19_MEL_A, 4, 0.62, 0.05, legato=1.02)
	pads(p, "choir", V.choir, M19_A, 4, lo=55, hi=67, vel=0.42, overlap=0.4, vowel="oo", attack=1.0, voices=4)
	arp(p, "harp", M.harp, M19_A, 4, ROCK_34, 0.4, -0.2, lo=57, beats=1.5)
	bassline(p, "low", V.warm_strings, M19_A, 4, [(0, 3.0, "b")], lo=38, vel=0.4, attack=0.6, cutoff_mul=3.0)
	# B: the choir takes the tune ('oh' opening to 'ah'), glass floats a high line; Ab and Fm6 darken it
	line(p, "choirlead", V.choir, M19_MEL_B, 20, 0.58, -0.05, legato=1.05, vowel="oh", vowel2="ah", attack=0.35,
		release=1.2)
	guide(p, "glass", V.glass_harp, M19_B, 20, 81, 88, 0.36, 0.3)
	pads(p, "choir", V.choir, M19_B, 20, lo=53, hi=64, vel=0.34, overlap=0.4, vowel="oo", attack=1.0, voices=4)
	arp(p, "harp", M.harp, M19_B, 20, [(0, "bass", .8), (1.5, "fifth", .4), (2, "top", .35)], 0.4, -0.2, lo=57, beats=1.5)
	bassline(p, "low", V.warm_strings, M19_B, 20, [(0, 3.0, "b")], lo=38, vel=0.45, attack=0.6, cutoff_mul=3.0)
	for bar in range(24, 28):
		p.note("choir", V.choir, "E5", bar, 0.0, 3.05, 0.2, 0.4, human=0.0, vowel="oo", attack=1.2)
	# A': the lullaby returns, a low 'oo' shadow an octave below the glass
	line(p, "glass", V.glass_harp, M19_MEL_A[:8] + M19_MEL_A[12:], 32, 0.6, 0.05, legato=1.02)
	line(p, "choirlead", V.choir, M19_MEL_A[:8] + M19_MEL_A[12:], 32, 0.34, -0.1, tr=-12, legato=1.05, vowel="oo",
		attack=0.4, release=1.2)
	pads(p, "choir", V.choir, M19_A2, 32, lo=55, hi=67, vel=0.36, overlap=0.4, vowel="oo", attack=1.0, voices=4)
	arp(p, "harp", M.harp, M19_A2, 32, ROCK_34, 0.38, -0.2, lo=57, beats=1.5)
	bassline(p, "low", V.warm_strings, M19_A2, 32, [(0, 3.0, "b")], lo=38, vel=0.4, attack=0.6, cutoff_mul=3.0)
	# candle flickers: rare, very soft high harp harmonics on chord tones
	for sec, chords, bar0 in ((M19_A, M19_A, 4), (M19_A2, M19_A2, 32)):
		for k in range(9):
			i = int(rng.integers(0, len(chords)))
			t = tones(chords[i], 81)
			nm = [t["root"], t["third"], t["fifth"]][int(rng.integers(0, 3))]
			p.note("flick", M.harp, nm, bar0 + i, float(rng.choice([1.5, 2.0, 2.5])), 1.0, 0.2,
				float(rng.uniform(-0.7, 0.7)))
	# coda: the opening phrase once more, then A major - candles lit
	line(p, "glass", V.glass_harp, M19_MEL_CODA, 44, 0.58, 0.05, legato=1.02)
	pads(p, "choir", V.choir, M19_CODA, 44, lo=55, hi=69, vel=0.4, overlap=0.5, vowel="oo", attack=1.0, voices=4)
	arp(p, "harp", M.harp, M19_CODA[:4], 44, ROCK_34, 0.36, -0.2, lo=57, beats=1.5)
	bassline(p, "low", V.warm_strings, M19_CODA[:5], 44, [(0, 3.0, "b")], lo=38, vel=0.4, attack=0.6, cutoff_mul=3.0)
	for k, nm in enumerate(["A2", "E3", "A3", "C#4", "E4", "B4"]):
		p.note("harp", M.harp, nm, 48, 0.3 * k, 3.0, 0.42, -0.3 + 0.1 * k)
	p.note("flick", M.harp, "E6", 49, 0.5, 1.0, 0.22, 0.4)
	p.note("flick", M.harp, "B6", 49, 1.5, 1.0, 0.16, -0.4)
	# (choir +2 dB after its 330 Hz dip: the E4 region nets -3 dB, the rest of the chord +2 dB, and the
	# choir-only intro keeps its level instead of dropping another 2.5 dB)
	levels = {"glass": (0.0, 0.5), "choir": (-14.0, 0.55), "choirlead": (-6.0, 0.5), "harp": (0.0, 0.4),
		"low": (-5.0, 0.3), "flick": (-4.0, 0.7)}
	meta = dict(id="m19", title="Candles for the Moon", bpm="66 (rit. into A', coda slows to 46)",
		key="A minor (B: F major colour with Ab / Fm6), ends on A major add9", meter="3/4",
		sections=[("Intro", 0), ("A", 4), ("B", 20), ("A'", 32), ("Coda", 44)],
		instruments="glass harmonica (lullaby lead), airy wordless choir pad ('oo'/'oh'/'ah' vowel formants only, "
			"no consonants = no intelligible words), harp rocking accompaniment, bowed low strings, rare harp-harmonic flickers",
		motif_notes="Own lullaby: a rocking falling triad E5-C5-A4 answered by a turn around B4, cadencing on the "
			"leading tone G#4; B: choir sings a slower tune through F-Dm7-Bbmaj7-C-Ab-Fm6-E7 (the Ab/Fm6 are the eerie "
			"shadows); A' adds a low 'oo' shadow; coda resolves to A major.",
		location_playlist="candleyard: Candleyard (quiet, eerie-gentle; no stingers)",
		target=-18.0)
	return p, levels, S.hall(rng, 3.4, brightness=6000), meta


# ==============================================================================================
# m27 "Every Road Leads Home" - G major -> A major, 4/4, 112 bpm festival reprise
# ==============================================================================================

M27_INTRO = ["G", "G", "C", [("D7sus4", 2), ("D7", 2)]]
M27_A = ["G", "C", "D7", "G", "Em", "Am7", "D7", "G", "G", "C", "A7", "D", "Bm7", "E7", [("Am7", 2), ("D7", 2)], "G"]
M27_B = ["C", "Am7", "Fmaj7", [("G7sus4", 2), ("G7", 2)], "C/E", "F", "Dm7", "G7", "Am", "Em/G", "F", "C/E", "Dm7", "Fm6",
	"C/G", "D7"]
M27_BRIDGE = ["G", "Em7", "F", [("E7sus4", 2), ("E7", 2)]]
M27_CODA = ["D", "Dm6", "A/E", "E7", "F#m", "D", [("E7sus4", 2), ("E7", 2)], "A", "A"]

M27_MEL_A = [
	motif("G4", LANTERN, [("D5", .5), ("E5", .5)]),
	[("G5", 1.5), ("E5", .5), ("C5", 1), ("E5", 1)],
	[("F#5", .5), ("A5", .5), ("G5", .5), ("F#5", .5), ("E5", 1), ("C5", 1)],
	[("B4", 1.5), ("A4", .5), ("G4", 1), ("r", 1)],
	motif("E4", LANTERN_MINOR, [("B4", .5), ("C5", .5)]),
	[("E5", 1.5), ("C5", .5), ("A4", 1), ("C5", 1)],
	[("D5", .5), ("F#5", .5), ("A5", .5), ("C6", .5), ("B5", .5), ("A5", .5), ("F#5", 1)],
	[("G5", 2), ("r", 2)],
	motif("G5", LANTERN, [("r", 1)]),
	[("C6", 1), ("B5", .5), ("A5", .5), ("G5", 1), ("E5", 1)],
	[("C#5", .5), ("E5", .5), ("A5", .5), ("G5", .5), ("E5", 1), ("C#5", 1)],
	[("D5", 1.5), ("E5", .5), ("F#5", 1), ("A5", 1)],
	[("B5", 1), ("A5", .5), ("F#5", .5), ("D5", 1), ("F#5", 1)],
	[("G#5", 1), ("B5", .5), ("G#5", .5), ("E5", 1), ("D5", 1)],
	[("C5", .5), ("E5", .5), ("A5", 1), ("F#5", .5), ("A5", .5), ("C6", 1)],
	[("B5", 1.5), ("A5", .5), ("G5", 1), ("r", 1)],
]
M27_B_CLAR = [
	shift(HAVEN_MOTIF, -7),
	[("r", 4)],
	[("A4", 1), ("C5", .5), ("E5", 1.5), ("D5", .5), ("C5", .5)],
	[("C5", 2), ("B4", 1), ("r", 1)],
	shift(HAVEN_MOTIF, -7),
	[("A4", 4)],
	[("F4", .5), ("A4", .5), ("D5", 1), ("C5", 1), ("A4", 1)],
	[("B4", 1.5), ("D5", .5), ("G4", 1), ("F4", 1)],
]
M27_B_CEL = [
	[("r", 4)],
	motif("A4", LANTERN_MINOR[:4] + [(10, .5), (3, 1.0)], [("r", 1)]),
	[("r", 4)],
	[("r", 3), ("G5", .25), ("A5", .25), ("B5", .5)],
	[("r", 4)],
	motif("F5", LANTERN, [("r", 1)]),
	[("r", 4)],
	[("r", 4)],
	[("r", 4)],
	motif("E5", LANTERN_MINOR, [("r", 1)]),
]
M27_B_STR = [
	[("E5", .5), ("A5", 1), ("G5", .5), ("F5", .5), ("E5", .5), ("C5", 1)],
	[("r", 4)],
	[("A5", 1.5), ("G5", .5), ("F5", 1), ("C5", 1)],
	[("E5", 1), ("G5", 1), ("C6", 2)],
	[("F5", 1), ("A5", 1), ("C6", 1), ("A5", 1)],
	[("Ab5", 2), ("F5", 1), ("D5", 1)],
	[("E5", 1.5), ("D5", .5), ("C5", 1), ("G4", 1)],
]
M27_BRIDGE_HORN = [
	motif("G4", LANTERN, [("r", 1)]),
	motif("E4", [(0, .5), (7, .5), (6, .25), (7, .25), (10, .5), (3, 1.0)], [("r", 1)]),
	motif("F4", LANTERN, [("r", 1)]),
	[("A4", 2), ("G#4", 1), ("B4", 1)],
]
M27_MEL_CODA = [
	[("F#5", 1), ("A5", 1), ("D6", 2)],
	[("F5", 1), ("A5", 1), ("B5", 2)],
	[("C#6", 1.5), ("B5", .5), ("A5", 2)],
	[("G#5", 1), ("B5", 1), ("D6", 2)],
	[("C#6", 2), ("A5", 2)],
	[("A4", 1), ("E5", 1), ("D#5", .5), ("E5", .5), ("F#5", 1)],
	[("E5", 1), ("A5", 1), ("G#5", 1), ("F#5", 1)],
	[("E5", 1), ("C#5", 1), ("A5", 2)],
	[("A5", 4)],
]
STRUM = [(0, "bass", 1.0), (1, "root", .6), (1, "third", .55), (1, "fifth", .5), (2, "fifth_lo", .8), (3, "root", .6),
	(3, "third", .55), (3, "fifth", .5), (3.5, "third", .4)]
FLOW = [(0, "bass", 1.0), (.5, "fifth_lo", .55), (1, "root", .6), (1.5, "third", .55), (2, "fifth", .6), (2.5, "top", .5),
	(3, "fifth", .5), (3.5, "third", .45)]


def _strum(p, chords, start, vel, tr=0):
	for i, entry in enumerate(chords):
		for sym, b0, nb in split(entry, p.bpb):
			t = tones(sym, 55, tr)
			for beat, deg, vm in STRUM:
				if b0 <= beat < b0 + nb:
					r = {"root": 0.0, "third": 0.03, "fifth": 0.06}.get(deg, 0.0)
					p.note("harp", M.harp, t[deg], start + i, beat + r, 0.8, vel * vm, -0.3)


def m27(rng):
	# bars: intro 0-3 | A 4-19 | B 20-35 | bridge 36-39 | A' 40-55 | coda 56-64
	tempo = [(0, 112), (56, 112), (59, 106), (61, 98), (63, 80), (64, 62), (65, 56)]
	p = Piece(112, 4, 65, rng, tempo=tempo)
	# intro: the Lanternwake motif and the haven motif greet each other
	line(p, "pzb", V.pizzicato, [motif("G2", LANTERN, [("r", 1)])], 0, 0.75)
	line(p, "mar", V.marimba, [motif("G4", LANTERN, [("r", 1)])], 0, 0.5, 0.2)
	line(p, "flute", M.flute, [HAVEN_MOTIF], 1, 0.62, -0.1, legato=0.95)
	line(p, "mar", V.marimba, [[("r", 4)], [("r", 4)], motif("C5", LANTERN, [("r", 1)])], 0, 0.5, 0.2)
	line(p, "str", V.warm_strings, [[("r", 4)], [("r", 4)], motif("C4", LANTERN, [("r", 1)]),
		[("A4", .5), ("B4", .5), ("C5", .5), ("D5", .5), ("E5", .5), ("F#5", .5), ("A5", 1)]], 0, 0.55, 0.1, legato=1.0)
	pads(p, "pad", M.strings, M27_INTRO[1:], 1, lo=55, hi=69, vel=0.34)
	bassline(p, "pzb", V.pizzicato, M27_INTRO[1:], 1, [(0, .5, "b"), (2, .5, "5", .8)], lo=38, vel=0.7)
	roll(p, "timp", V.timpani, "D2", 3, 2.0, 2.0, 0.12, 0.5)
	p.note("swell", M.swell, 1000.0, 3, 1.0, 3.0, 0.6, 0.0, human=0.0)
	# A: a festival tune grown from the Lanternwake motif
	line(p, "flute", M.flute, M27_MEL_A, 4, 0.64, -0.1, legato=0.92)
	_strum(p, M27_A, 4, 0.5)
	bassline(p, "pzb", V.pizzicato, M27_A, 4, [(0, .5, "b"), (2, .5, "5", .8)], lo=38, vel=0.72)
	bassline(p, "bass", M.soft_bass, M27_A, 4, [(0, .9, "b"), (2, .9, "5", .8)], lo=38, vel=0.5)
	hits(p, "mar", V.marimba, M27_A, 4, [(.5, .8), (1.5, 1.0), (2.5, .8), (3.5, 1.0)], lo=60, hi=72, vel=0.3, length=0.4)
	perc(p, "perc", M.tom, 62.0, range(4, 20), [(0, 1.0), (2, .75)], 0.45, 0.0)
	perc(p, "perc", V.tambourine, 1.0, range(4, 20), [(1, 1.0), (3, 1.0)], 0.3, 0.3)
	for bar, notes in ((7, ["D6", "G6", "B6"]), (11, ["E6", "G6", "C7"]), (19, ["D6", "G6", "B6"])):
		for k, nm in enumerate(notes):
			p.note("cel", M.celesta, nm, bar, 2.5 + 0.33 * k, 0.5, 0.35, 0.35)
	# B: 'home' - the haven motif on clarinet over new harmony, the celesta answers with Lanternwake
	line(p, "clar", M.clarinet, M27_B_CLAR, 20, 0.6, 0.1, legato=0.9)
	line(p, "cel", M.celesta, M27_B_CEL, 20, 0.5, 0.3)
	line(p, "str", V.warm_strings, M27_B_STR, 28, 0.56, -0.05, legato=1.0, attack=0.18)
	line(p, "clar", M.clarinet, [[("D5", .5), ("G5", 1), ("F#5", .5), ("E5", .5), ("D5", .5), ("C5", 1)]], 35, 0.6, 0.1,
		legato=0.9)
	guide(p, "clar", M.clarinet, M27_B[8:15], 28, 67, 74, 0.4, 0.15)
	arp(p, "harp", M.harp, M27_B, 20, FLOW, 0.4, -0.3, lo=50, beats=1.0)
	pads(p, "pad", M.strings, M27_B, 20, lo=55, hi=69, vel=0.34)
	bassline(p, "pzb", V.pizzicato, M27_B, 20, [(0, 1, "b"), (2, 1, "5", .75)], lo=38, vel=0.6)
	bassline(p, "bass", M.soft_bass, M27_B, 20, [(0, 1.8, "b"), (2, 1.8, "5", .8)], lo=38, vel=0.45)
	perc(p, "perc", M.shaker, 440.0, range(20, 36), [(.5, .7), (1.5, 1.0), (2.5, .7), (3.5, 1.0)], 0.2, -0.3)
	perc(p, "perc", M.woodblock, 900.0, range(21, 36, 2), [(3.5, 1.0)], 0.22, 0.3)
	# bridge: the motif climbs through G, E minor and F on horns; timpani and a harp sweep lift us to A major
	line(p, "horn", V.warm_horn, M27_BRIDGE_HORN, 36, 0.8, -0.05)
	line(p, "str", V.warm_strings, M27_BRIDGE_HORN, 36, 0.5, 0.1, tr=12, legato=1.0, attack=0.12)
	_strum(p, M27_BRIDGE, 36, 0.5)
	perc(p, "perc", M.tom, 62.0, range(36, 39), [(0, 1.0), (2, .75)], 0.45, 0.0)
	perc(p, "perc", V.tambourine, 1.0, range(36, 39), [(1, 1.0), (3, 1.0)], 0.28, 0.3)
	pads(p, "pad", M.strings, M27_BRIDGE, 36, lo=55, hi=70, vel=0.4)
	bassline(p, "pzb", V.pizzicato, M27_BRIDGE, 36, [(0, .5, "b"), (2, .5, "5", .8)], lo=38, vel=0.7)
	bassline(p, "bass", M.soft_bass, M27_BRIDGE, 36, [(0, 1.8, "b"), (2, 1.8, "5", .8)], lo=38, vel=0.5)
	roll(p, "timp", V.timpani, "E2", 38, 0.0, 8.0, 0.1, 0.55)
	sweep = ["E4", "F#4", "G#4", "A4", "B4", "C#5", "D5", "E5", "F#5", "G#5", "A5", "B5", "C#6", "D6", "E6"]
	for k, nm in enumerate(sweep):
		p.note("harp", M.harp, nm, 39, 2.0 + k * 0.125, 0.5, 0.35 + 0.02 * k, -0.4 + 0.05 * k, human=0.0)
	p.note("swell", M.swell, 1000.0, 39, 0.0, 4.0, 0.7, 0.0, human=0.0)
	# A': A major, full festival - the tune in the flute, the haven motif under it in the clarinet
	melA2 = [list(b) for b in M27_MEL_A]
	melA2[8] = motif("G4", LANTERN, [("r", 1)])
	line(p, "flute", M.flute, melA2, 40, 0.66, -0.1, tr=2, legato=0.92)
	line(p, "cel", M.celesta, melA2[:8], 40, 0.4, 0.3, tr=2)
	# (bar 44 is F# minor: the haven motif in its diatonic minor form)
	for bar, hm in ((40, shift(HAVEN_MOTIF, -10)), (44, [("C#4", .5), ("F#4", 1), ("E4", .5), ("D4", .5), ("C#4", .5), ("A3", 1)]),
			(48, shift(HAVEN_MOTIF, -10))):
		line(p, "clar", M.clarinet, [hm], bar, 0.56, 0.15, legato=0.9)
	guide(p, "str", V.warm_strings, M27_A[8:], 48, 69, 76, 0.4, 0.1, tr=2, attack=0.2)
	_strum(p, M27_A, 40, 0.52, tr=2)
	bassline(p, "pzb", V.pizzicato, M27_A, 40, [(0, .5, "b"), (2, .5, "5", .8), (3.5, .4, "8", .45)], lo=38, vel=0.74, tr=2)
	bassline(p, "bass", M.soft_bass, M27_A, 40, [(0, .9, "b"), (2, .9, "5", .8)], lo=38, vel=0.52, tr=2)
	hits(p, "mar", V.marimba, M27_A, 40, [(.5, .8), (1.5, 1.0), (2.5, .8), (3.5, 1.0)], lo=61, hi=73, vel=0.3, length=0.4, tr=2)
	pads(p, "pad", M.strings, M27_A, 40, lo=57, hi=71, vel=0.3, tr=2)
	perc(p, "perc", M.tom, 62.0, range(40, 56), [(0, 1.0), (2, .75)], 0.48, 0.0)
	perc(p, "perc", V.tambourine, 1.0, range(40, 56), [(1, 1.0), (3, 1.0)], 0.32, 0.3)
	perc(p, "perc", M.shaker, 440.0, range(40, 56), [.5, 1.5, 2.5, 3.5], 0.2, -0.3)
	# coda (new ending): D - Dm6 - A/E - E7 - F#m (not yet!) - D - E7 - A, broadening to a held A major
	line(p, "str", V.warm_strings, M27_MEL_CODA, 56, 0.64, 0.05, legato=1.0, attack=0.15)
	line(p, "flute", M.flute, M27_MEL_CODA[:8], 56, 0.52, -0.15, tr=-12, legato=0.95)
	line(p, "clar", M.clarinet, [[("r", 4)]] * 6 + [[("E4", 1), ("A4", 1), ("G#4", 1), ("F#4", 1)],
		[("E4", 1), ("C#4", 1), ("E4", 2)], [("C#4", 4)]], 56, 0.5, 0.15, legato=0.97)
	pads(p, "pad", M.strings, M27_CODA, 56, lo=57, hi=72, vel=0.42)
	_strum(p, M27_CODA[:7], 56, 0.46)
	bassline(p, "pzb", V.pizzicato, M27_CODA[:8], 56, [(0, .5, "b"), (2, .5, "5", .8)], lo=38, vel=0.7)
	bassline(p, "bass", M.soft_bass, M27_CODA, 56, [(0, 1.8, "b"), (2, 1.8, "5", .8)], lo=38, vel=0.55)
	perc(p, "perc", M.tom, 62.0, range(56, 62), [(0, 1.0)], 0.4, 0.0)
	perc(p, "perc", V.tambourine, 1.0, range(56, 62), [(1, 1.0), (3, 1.0)], 0.26, 0.3)
	roll(p, "timp", V.timpani, "E2", 63, 0.0, 4.0, 0.12, 0.55)
	p.note("timp", V.timpani, "A2", 64, 0.0, 1.0, 0.7)
	p.note("swell", M.swell, 1000.0, 63, 0.0, 4.0, 0.8, 0.0, human=0.0)
	p.note("perc", V.tambourine, 1.0, 64, 0.0, 0.25, 0.4, 0.3)
	for k, nm in enumerate(["A2", "E3", "A3", "C#4", "E4", "A4", "C#5", "E5", "A5"]):
		p.note("harp", M.harp, nm, 64, 0.08 * k, 3.5, 0.5, -0.35 + 0.08 * k, human=0.0)
	p.note("pzb", V.pizzicato, "A1", 64, 0.0, 1.0, 0.8)
	line(p, "cel", M.celesta, [[("r", 1), ("A5", .5), ("E6", .5), ("D#6", .25), ("E6", .25), ("F#6", .5), ("C#6", 1)]],
		64, 0.4, 0.35, accent=0.0)
	levels = {"flute": (-1.0, 0.3), "clar": (-2.0, 0.28), "cel": (-6.0, 0.4), "str": (3.0, 0.35), "horn": (-1.0, 0.3),
		"harp": (1.0, 0.22), "pzb": (1.0, 0.15), "bass": (-9.0, 0.08), "mar": (-6.0, 0.25), "pad": (-13.0, 0.4),
		"perc": (-10.0, 0.15), "timp": (-8.0, 0.3), "swell": (-19.0, 0.4)}
	meta = dict(id="m27", title="Every Road Leads Home", bpm="112, broadening to 56 on the final chord",
		key="G major, lifts to A major for A' and the coda", meter="4/4",
		sections=[("Intro", 0), ("A", 4), ("B", 20), ("Bridge", 36), ("A'", 40), ("Coda", 56)],
		instruments="flute (festival tune), clarinet (haven motif), celesta, warm strings, horn pair (bridge), "
			"harp strum/arpeggios, pizzicato + soft bass, marimba offbeats, tambourine, soft drum, shaker, woodblock, timpani",
		motif_notes="Combines the Lanternwake motif (from m15; 1 5 #4 5 6 3, e.g. G4 D5 C#5 D5 E5 B4) and the HAVEN "
			"motif (first bar of HAVEN_A in music_tracks.py: D5 G5 F#5 E5 D5 B4). Intro: they greet each other; A: new "
			"festival tune grown from the Lanternwake motif; B: haven motif on clarinet over new harmony, celesta answers "
			"with Lanternwake; bridge: motif climbs G-Em-F on horns to A major; A': both motifs in counterpoint "
			"(Lanternwake rising in the flute, haven falling in the clarinet); NEW coda D-Dm6-A/E-E7-F#m-D-E7-A with a "
			"broad final cadence.",
		location_playlist="chapter2_return: Chapter Two return / celebration; optional later safe-home rotation",
		target=-16.8)
	return p, levels, S.hall(rng, 2.1, brightness=8000), meta


# Independent review (numbers only, nobody has listened) - copied into the manifest rows.
REVIEW = {
	"m15": "Re-measured, unchanged. Quiet pizzicato intro (~-24 LUFS short-term, ~6 LU under A) is deliberate.",
	"m16": "Section C sustained sine bass lowered 4 dB (was the loudest bus there, ~37 % of the section's energy "
		"below 120 Hz). C is now ~-19.5 LUFS short-term.",
	"m17": "Section B sustained sine bass lowered 4 dB (it out-weighed the string tune; B had -5.7 dB of energy "
		"below 120 Hz vs -14.6 dB in A).",
	"m18": "Re-measured, unchanged. Quiet intro (~-24 LUFS short-term) is deliberate.",
	"m19": "Choir buses get a broad dip at 330 Hz (pad -5 dB, lead -3 dB, Q 1.6) and the pad +2 dB: the 'oo' "
		"formant plus the held E4 common tone made one steady 315 Hz band 9-15 dB above its neighbours. Choir "
		"stays dark ('oo'); the intro is still dominated by the held E4.",
	"m27": "Re-measured, unchanged.",
}

CUES = {"m15": (m15, "m15_welcome_to_lanternwake.ogg"), "m16": (m16, "m16_copper_leaves_at_dusk.ogg"),
	"m17": (m17, "m17_pumpkin_patch_parade.ogg"), "m18": (m18, "m18_stone_bells_quiet_hills.ogg"),
	"m19": (m19, "m19_candles_for_the_moon.ogg"), "m27": (m27, "m27_every_road_leads_home.ogg")}


# ==============================================================================================
# Mastering, writing, verification
# ==============================================================================================

def master(y: np.ndarray, target: float, ceiling: float = -1.5) -> tuple:
	"""Gain to the target integrated loudness; a transparent look-ahead limiter only touches the rare
	peaks above `ceiling` (no compression, dynamics stay). Iterates until loudness and true peak hold."""
	y = y * db(target - Q.integrated_lufs(y, SR))
	info = {}
	for _ in range(6):
		info["limiter_max_gr_db"] = round(max(0.0, Q.sample_peak_db(y) - ceiling), 2)
		z = limiter(y, ceiling, 0.025)
		tp = Q.true_peak_db(z)
		if tp > -1.3:
			ceiling -= tp + 1.3 + 0.05
			continue
		lz = Q.integrated_lufs(z, SR)
		if abs(lz - target) <= 0.05:
			break
		y = y * db(target - lz)
	info["limited_share_pct"] = round(100.0 * float(np.mean(np.max(np.abs(y), axis=1) > db(ceiling))), 3)
	return z, info


def write_ogg(path: str, y: np.ndarray) -> np.ndarray:
	"""Writes OGG Vorbis and returns the decoded file; lowers the gain if Vorbis overshoots -1 dBTP."""
	import soundfile as sf
	for _ in range(4):
		# soundfile's OGG/VORBIS writer overflows the stack when handed minutes of audio in one call
		# (libsndfile Vorbis encoder), so the same format is written block by block
		with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS") as fh:
			for k in range(0, len(y), 8192):
				fh.write(np.ascontiguousarray(y[k:k + 8192], dtype=np.float32))
		dec, sr = sf.read(path, dtype="float64", always_2d=True)
		tp = Q.true_peak_db(dec)
		if tp <= -1.05:
			return dec
		y = y * db(-(tp + 1.15))
	return dec


def _fmt_sections(p: Piece, secs, dur: float) -> str:
	out = []
	for k, (lab, bar) in enumerate(secs):
		t0 = p.bar_time(bar)
		t1 = p.bar_time(secs[k + 1][1]) if k + 1 < len(secs) else dur
		out.append("%s(%.0f-%.0fs%s)" % (lab, t0, t1, " incl. ring-out" if k + 1 == len(secs) else ""))
	return " ".join(out)


def render_cue(cue: str, out_dir: str = OUT_DIR, qa_dir: str = QA_DIR) -> dict:
	fn, fname = CUES[cue]
	t0 = time.time()
	rng = rng_for("music2_hallowmere_" + cue)
	p, levels, ir, meta = fn(rng)
	raw = p.render(levels, ir)
	y, minfo = master(raw, meta["target"])
	os.makedirs(out_dir, exist_ok=True)
	path = os.path.join(out_dir, fname)
	dec = write_ogg(path, y)
	m = Q.measure(dec, SR)
	dur = len(dec) / SR
	secs = meta["sections"]
	sec_times = [(lab, p.bar_time(bar)) for lab, bar in secs]
	# loudness of each section (short-term mean) - shows the dynamic shape
	st = Q.short_term_curve(dec, SR, 0.5)
	sec_lufs = {}
	for k, (lab, s0) in enumerate(sec_times):
		s1 = sec_times[k + 1][1] if k + 1 < len(sec_times) else p.length
		a, b = int(s0 / 0.5), max(int(s0 / 0.5) + 1, int((s1 - 3.0) / 0.5))
		seg = st[a:b]
		seg = seg[seg > -70]
		sec_lufs[lab] = round(float(10 * np.log10(np.mean(10 ** (seg / 10)))), 1) if len(seg) else None
	gaps = Q.silence_gaps(dec, SR, -55.0, 3.0)
	last_note = p.length
	gaps_music = [g for g in gaps if g[0] < last_note - 0.5]
	os.makedirs(qa_dir, exist_ok=True)
	Q.spectrogram_png(dec, SR, os.path.join(qa_dir, cue + ".png"), "%s %s" % (cue, meta["title"]), sec_times)
	row = {"id": cue, "title": meta["title"], "file": "res://assets/audio/music/" + fname, "duration_s": round(dur, 2),
		"loop": False, "bpm": meta["bpm"], "key": meta["key"], "meter": meta["meter"],
		"sections": _fmt_sections(p, secs, dur), "instruments": meta["instruments"], "motif_notes": meta["motif_notes"],
		"peak_dbfs": m["true_peak_db"], "loudness_lufs": m["lufs"], "location_playlist": meta["location_playlist"],
		"verified": "analysis only - not listened", "review": REVIEW.get(cue, "")}
	report = {"cue": cue, "file": path, "render_s": round(time.time() - t0, 1), "measure": m, "section_lufs": sec_lufs,
		"silence_gaps_in_music": gaps_music, "silence_after_last_note": [g for g in gaps if g not in gaps_music],
		"target_lufs": meta["target"], "master": minfo, "bus_rms_db": p.bus_report,
		"notes_end_s": round(last_note, 2)}
	return {"row": row, "report": report}


def render_all(out_dir: str = OUT_DIR, only=None, jobs: int = 6, qa_dir: str = QA_DIR,
		manifest: str = MANIFEST) -> list:
	"""Renders every Hallowmere cue (or `only`), writes the OGGs, spectrograms and the manifest rows.
	Returns the per-cue reports."""
	cues = [c for c in CUES if not only or c in only]
	results = []
	if jobs > 1 and len(cues) > 1:
		from concurrent.futures import ProcessPoolExecutor
		with ProcessPoolExecutor(max_workers=min(jobs, len(cues))) as ex:
			futs = [ex.submit(render_cue, c, out_dir, qa_dir) for c in cues]
			results = [f.result() for f in futs]
	else:
		results = [render_cue(c, out_dir, qa_dir) for c in cues]
	rows = {}
	if os.path.exists(manifest) and only:
		for r in json.load(open(manifest, encoding="utf-8")):
			rows[r["id"]] = r
	for r in results:
		rows[r["row"]["id"]] = r["row"]
	with open(manifest, "w", encoding="utf-8") as fh:
		json.dump([rows[k] for k in sorted(rows)], fh, indent=2, ensure_ascii=False)
	return [r["report"] for r in results]


def main() -> int:
	ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	ap.add_argument("--only", default="", help="comma-separated cue ids (m15,m16,m17,m18,m19,m27)")
	ap.add_argument("--jobs", type=int, default=6)
	ap.add_argument("--out", default=OUT_DIR)
	a = ap.parse_args()
	t0 = time.time()
	only = [c.strip() for c in a.only.split(",") if c.strip()] or None
	reports = render_all(a.out, only, a.jobs)
	for r in reports:
		print(json.dumps(r))
	print("total %.1fs" % (time.time() - t0))
	return 0


if __name__ == "__main__":
	sys.exit(main())
