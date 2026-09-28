"""Hollowhaven Part 2 music - home & woods group: six original, through-composed cues with endings.

    m03  Wood, Wool & Windows     Haven day B (building)          C major  4/4  96 bpm   6-bar phrases
    m04  Berry Tea Afternoon      Haven day C (crafting/garden)   Bb major 6/8  50 dotted-quarter
    m06  Firefly Wishes           Haven night B (lullaby)         Eb major 3/4  63 bpm
    m07  Footpaths & Ferns        Chapter One woods A             A major  4/4  104 bpm (walking bass)
    m08  The Long Way Home        Chapter One woods B             E major  4/4  74 bpm (spacious)
    m09  Ripples at Mirror Pond   pond / quiet glade              Db major 4/4  56 bpm (sparse)

Every melody here is hand-written for this game (note data below, one string per section, bars
separated by '|', tokens NOTE/beats, 'r' = rest, '_' = tie, 'A4+C5' = dyad). None of the pieces is
a loop: each has an intro, contrasting sections, a ritardando and a real final chord. m08's coda
quotes the game's own "For Krystal" motif (5-1-7-6-5, from music_tracks.py) as a homecoming hint.

Usage (Git Bash, repo root):
    .tools/pyenv/Scripts/python.exe tools/audio/music2/group_home_woods.py            # render + verify
    .tools/pyenv/Scripts/python.exe tools/audio/music2/group_home_woods.py --only m03  # one cue
    .tools/pyenv/Scripts/python.exe tools/audio/music2/group_home_woods.py --no-verify

Output: game/assets/audio/music/<cue>.ogg (OGG Vorbis 44.1 kHz stereo), spectrograms in
qa/tmp/music2/<cue>.png, manifest rows in tools/audio/music2/manifest_home_woods.json.
Deterministic: every cue is seeded from its id. Only hhsynth is imported (read-only)."""
from __future__ import annotations

import json
import math
import os
import re
import sys
import time

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO_TOOLS = os.path.dirname(HERE)
for _p in (AUDIO_TOOLS, HERE):
	if _p not in sys.path:
		sys.path.insert(0, _p)

import numpy as np  # noqa: E402

from hhsynth.core import SR, ns, db, rng_for, place, limiter  # noqa: E402
from hhsynth import music as M, space as S, filters as F  # noqa: E402
import hw_instruments as I  # noqa: E402
import hw_loudness as L  # noqa: E402

ROOT = os.path.abspath(os.path.join(AUDIO_TOOLS, "..", ".."))
OUT_DIR = os.path.join(ROOT, "game", "assets", "audio", "music")
QA_DIR = os.path.join(ROOT, "qa", "tmp", "music2")
MANIFEST = os.path.join(HERE, "manifest_home_woods.json")

# ==========================================================================================
# Notation, chords
# ==========================================================================================

_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
SHAPES = dict(M.CHORD_SHAPES)
SHAPES.update({"maj7#11": [0, 4, 7, 11, 18], "69": [0, 4, 7, 9, 14], "m11": [0, 3, 7, 10, 14, 17]})


def _pc(name: str) -> int:
	return (_PC[name[0]] + name[1:].count("#") - name[1:].count("b")) % 12


def chord_info(sym: str) -> dict:
	"""'Gm7' -> root/ivs/bass; 'C/E' has bass E."""
	bass = None
	if "/" in sym:
		sym, b = sym.split("/")
		bass = _pc(b)
	m = re.fullmatch(r"([A-G][#b]?)(.*)", sym)
	root = _pc(m.group(1))
	ivs = SHAPES[m.group(2)]
	return {"root": root, "ivs": ivs, "bass": root if bass is None else bass}


def in_range(pc: int, lo: int) -> int:
	return lo + ((pc - lo) % 12)


def chord_segments(entry: str, bpb: float) -> list:
	"""'F' -> whole bar; 'F Dm7' -> halves; 'Fm7*2 Bb7*1' -> explicit beats."""
	toks = entry.split()
	fixed = sum(float(t.split("*")[1]) for t in toks if "*" in t)
	free = [t for t in toks if "*" not in t]
	each = (bpb - fixed) / len(free) if free else 0.0
	out, b = [], 0.0
	for t in toks:
		if "*" in t:
			s, n = t.split("*")
			n = float(n)
		else:
			s, n = t, each
		out.append((s, b, n))
		b += n
	assert abs(b - bpb) < 1e-6, "chord bar %r does not fill %s beats" % (entry, bpb)
	return out


def chord_tones(sym: str, lo: int) -> dict:
	ci = chord_info(sym)
	r = in_range(ci["root"], lo)
	iv = ci["ivs"]
	t = {"b": in_range(ci["bass"], lo - 12), "r": r, "3": r + iv[1], "5": r + (iv[2] if len(iv) > 2 else 7),
		"8": r + 12, "9": r + 14}
	t["7"] = r + iv[3] if len(iv) > 3 and iv[3] < 12 else r + 12
	return t


def degree(tones: dict, deg: str) -> int:
	return tones[deg.strip("+-")] + 12 * deg.count("+") - 12 * deg.count("-")


def voicing(sym: str, lo: int, hi: int, prev, max_voices: int = 4) -> list:
	ci = chord_info(sym)
	pcs = []
	for iv in ci["ivs"]:
		pc = (ci["root"] + iv) % 12
		if pc not in pcs:
			pcs.append(pc)
	while len(pcs) > max_voices:
		fifth = (ci["root"] + 7) % 12
		pcs.remove(fifth if fifth in pcs else ci["root"])
	return M.voice_lead(prev, [60 + p for p in pcs], lo, hi)


def parse_line(text: str, bpb: float) -> list:
	"""-> list of events (bar_index, beat, beats, [notes]) with ties merged. Asserts bar sums."""
	bars = [b.strip() for b in text.strip().split("|")]
	events = []
	for i, bar in enumerate(bars):
		beat = 0.0
		for tok in bar.split():
			name, d = tok.rsplit("/", 1)
			d = float(d)
			if name == "_":
				events[-1][2] += d
			elif name != "r":
				events.append([i, beat, d, name.split("+")])
			beat += d
		assert abs(beat - bpb) < 1e-6, "bar %d %r sums to %s, not %s" % (i, bar, beat, bpb)
	return events


def n_bars(text: str) -> int:
	return len([b for b in text.strip().split("|")])


# ==========================================================================================
# Score: a bar/beat sequencer with a tempo map (ritardando), buses, automation, no looping
# ==========================================================================================

class Score:
	RES = 96

	def __init__(self, bpm: float, bpb: int, bars: int, rng: np.random.Generator, tempo=None, tail: float = 7.0,
			pre: float = 0.1):
		self.bpb = bpb
		self.pre = pre                      # a little silence before the first attack
		self.bars = bars
		self.rng = rng
		pts = tempo or [(0, bpm), (bars, bpm)]
		xs = [b * bpb for b, _ in pts]
		ys = [v for _, v in pts]
		k = (np.arange(bars * bpb * self.RES) + 0.5) / self.RES
		bpm_k = np.interp(k, xs, ys)
		self.last_bpm = float(bpm_k[-1])
		self.tt = np.concatenate([[0.0], np.cumsum(60.0 / bpm_k / self.RES)])
		self.length = self.pre + float(self.tt[-1])
		self.n = ns(self.length + tail)
		self.buses: dict[str, np.ndarray] = {}
		self.auto: dict[str, list] = {}
		self.master_auto = [(0, 0.0)]
		self.count = 0

	def time_beats(self, b: float) -> float:
		total = self.bars * self.bpb
		if b >= total:
			return self.length + (b - total) * 60.0 / self.last_bpm
		return self.pre + float(np.interp(b * self.RES, np.arange(len(self.tt)), self.tt))

	def time(self, bar: float, beat: float = 0.0) -> float:
		return self.time_beats(bar * self.bpb + beat)

	def bus(self, name: str) -> np.ndarray:
		if name not in self.buses:
			self.buses[name] = np.zeros((self.n, 2))
		return self.buses[name]

	def add(self, bus: str, t: float, sig: np.ndarray, pan: float = 0.0) -> None:
		if sig.ndim == 1:
			st = S.pan(sig, pan)
		else:
			st = sig * np.array([min(1.0, 1.0 - pan), min(1.0, 1.0 + pan)])
		place(self.bus(bus), st, max(0.0, t))

	def note_t(self, bus: str, inst, note, t: float, dur: float, vel: float, pan: float = 0.0, **kw) -> None:
		f = float(note) if isinstance(note, float) else M.hz(note)
		sig = inst(f, max(dur, 0.03), float(np.clip(vel, 0.03, 1.0)), self.rng, **kw)
		self.add(bus, t, sig, pan)
		self.count += 1

	def note(self, bus: str, inst, note, bar: float, beat: float, beats: float, vel: float = 0.7, pan: float = 0.0,
			human: float = 0.006, **kw) -> None:
		b0 = bar * self.bpb + beat
		t0 = self.time_beats(b0)
		dur = self.time_beats(b0 + beats) - t0
		if human > 0:
			t0 += self.rng.normal(0.0, human)
			vel *= 1.0 + self.rng.normal(0.0, 0.05)
		self.note_t(bus, inst, note, t0, dur, vel, pan, **kw)

	def automate(self, bus: str, points) -> None:
		"""points = [(bar, gain_db), ...]; linear in dB between points, held outside."""
		self.auto[bus] = points

	def _curve(self, points, n: int) -> np.ndarray:
		ts = [self.time(b) for b, _ in points]
		gs = [g for _, g in points]
		t = np.arange(n) / SR
		return 10.0 ** (np.interp(t, ts, gs) / 20.0)

	def mix(self, levels: dict, ir: np.ndarray, hp: float = 32.0, lp: float = 15000.0) -> np.ndarray:
		"""levels: bus -> (gain_db, reverb_send). Linear (non-looping) mix with the reverb tail,
		trimmed after the last audible ring and faded."""
		dry = np.zeros((self.n, 2))
		send = np.zeros((self.n, 2))
		self.bus_report = {}
		for name, buf in self.buses.items():
			g, s = levels[name]
			y = buf * db(g)
			if name in self.auto:
				y = y * self._curve(self.auto[name], len(y))[:, None]
			dry += y
			send += y * s
			act = y[np.max(np.abs(y), axis=1) > 1e-4]
			self.bus_report[name] = round(20 * np.log10(np.sqrt(np.mean(act ** 2)) + 1e-12), 1) if len(act) else -120.0
		wet = S.reverb(send, ir, wet=1.0, dry=0.0)
		full = wet
		full[:len(dry)] += dry
		full = full * self._curve(self.master_auto, len(full))[:, None]
		full = F.highpass(full, hp, 2)
		full = F.lowpass(full, lp, 1)
		full -= np.mean(full, axis=0, keepdims=True)
		# trim: keep until the ring falls 66 dB under the peak (and at least the written length)
		mag = np.max(np.abs(full), axis=1)
		above = np.nonzero(mag > np.max(mag) * db(-66.0))[0]
		end = max(int(above[-1]) if above.size else 0, ns(self.length)) + ns(0.2)
		full = full[:min(end, len(full))]
		fo = ns(1.2)
		full[-fo:] *= (np.linspace(1.0, 0.0, fo) ** 2)[:, None]
		fi = ns(0.004)
		full[:fi] *= np.linspace(0.0, 1.0, fi)[:, None]
		return full


# ==========================================================================================
# Writing helpers
# ==========================================================================================

def line(sc: Score, bus: str, inst, text: str, bar0: int, vel: float = 0.7, pan: float = 0.0, transpose: int = 0,
		legato: float = 0.95, arch: float = 0.14, phrase: int = 4, accent: float = 0.05, human: float = 0.006,
		roll: float | None = None, roll_inst=None, only_bars=None, **kw) -> None:
	"""Plays a melody. Velocity follows a phrase arch (rises to the middle of each `phrase`-bar
	group and relaxes at its end), downbeats get a small accent, higher notes lean a little louder.
	Notes of `roll` beats or longer are played as mallet rolls (marimba)."""
	ev = parse_line(text, sc.bpb)
	mids = [M.midi(n) for e in ev for n in e[3]]
	mean = float(np.mean(mids)) if mids else 60.0
	for bi, beat, beats, notes in ev:
		if only_bars is not None and bi not in only_bars:
			continue
		u = ((bi % phrase) + beat / sc.bpb) / phrase
		for nm in notes:
			m = M.midi(nm) + transpose
			v = vel * (1.0 + arch * (math.sin(math.pi * u) - 0.4)) + (accent if beat == 0 else 0.0)
			v *= 1.0 + 0.012 * (m - transpose - mean)
			if roll is not None and beats >= roll:
				mallet_roll(sc, bus, roll_inst or inst, m, bar0 + bi, beat, beats * legato, v, pan)
			else:
				sc.note(bus, inst, m, bar0 + bi, beat, beats * legato, v, pan, human, **kw)


def mallet_roll(sc: Score, bus: str, inst, m: int, bar: int, beat: float, beats: float, vel: float, pan: float,
		rate: float = 12.5) -> None:
	"""Marimba roll: alternating-hand strokes; accented start, a gentle swell, soft release."""
	t0 = sc.time(bar, beat)
	t1 = sc.time(bar, beat + beats)
	k = max(2, int((t1 - t0) * rate))
	for i in range(k):
		u = i / max(k - 1, 1)
		env = 1.0 if i == 0 else (0.5 + 0.22 * math.sin(math.pi * min(1.0, u * 1.2))) * (1.0 - 0.35 * u)
		hand = 1.0 if i % 2 == 0 else 0.88
		t = t0 + i / rate + sc.rng.normal(0.0, 0.004)
		sc.note_t(bus, inst, m, t, 0.2, vel * env * hand, pan + (0.06 if i % 2 else -0.06))


def arp(sc: Score, bus: str, inst, chords, bar0: int, pattern, lo: int, vel: float, pan: float = 0.0,
		hold: bool = False, human: float = 0.006, **kw) -> None:
	"""Broken-chord accompaniment. pattern: [(beat, degree, vel_mul[, beats])] applied per bar
	(entries outside a chord's span are skipped) or {segment_beats: pattern} relative to each chord.
	hold=True lets every note ring to the end of its chord (sustain pedal / let-ring)."""
	for i, entry in enumerate(chords):
		for sym, b0, nb in chord_segments(entry, sc.bpb):
			tones = chord_tones(sym, lo)
			if isinstance(pattern, dict):
				pat = [(b0 + p[0],) + tuple(p[1:]) for p in pattern[round(nb, 3)]]
			else:
				pat = [p for p in pattern if b0 - 1e-6 <= p[0] < b0 + nb - 1e-6]
			for item in pat:
				beat, deg, vm = item[0], item[1], item[2]
				ln = item[3] if len(item) > 3 else 1.0
				if hold:
					ln = b0 + nb - beat + 0.15
				sc.note(bus, inst, degree(tones, deg), bar0 + i, beat, ln, vel * vm, pan, human, **kw)


def blocks(sc: Score, bus: str, inst, chords, bar0: int, hits, lo: int, hi: int, vel: float, pan: float = 0.0,
		roll: float = 0.0, max_voices: int = 4, human: float = 0.006, **kw) -> None:
	"""Voice-led block chords struck at `hits` = [(beat, beats, vel_mul)] (per bar) or
	{segment_beats: [...]} (relative to each chord). roll = spread per voice in beats (strum)."""
	prev = None
	for i, entry in enumerate(chords):
		for sym, b0, nb in chord_segments(entry, sc.bpb):
			v = voicing(sym, lo, hi, prev, max_voices)
			prev = v
			if isinstance(hits, dict):
				hh = [(b0 + h[0],) + tuple(h[1:]) for h in hits[round(nb, 3)]]
			else:
				hh = [h for h in hits if b0 - 1e-6 <= h[0] < b0 + nb - 1e-6]
			for beat, ln, vm in hh:
				for k, n in enumerate(v):
					sc.note(bus, inst, n, bar0 + i, beat + roll * k, ln, vel * vm * (0.9 + 0.1 * (k == len(v) - 1)),
						pan, human, **kw)


def pads(sc: Score, bus: str, inst, chords, bar0: int, lo: int, hi: int, vel: float, pan: float = 0.0,
		overlap: float = 0.2, max_voices: int = 4, **kw) -> None:
	"""Sustained voice-led chords. Common tones are tied across chord changes (held, not
	re-attacked), as an ensemble would play them."""
	prev = None
	held: dict[int, list] = {}          # pitch -> [start_beat, length]
	done = []
	for i, entry in enumerate(chords):
		for sym, b0, nb in chord_segments(entry, sc.bpb):
			v = voicing(sym, lo, hi, prev, max_voices)
			prev = v
			start = (bar0 + i) * sc.bpb + b0
			for p in list(held):
				if p not in v:
					done.append((p,) + tuple(held.pop(p)))
			for p in v:
				if p in held:
					held[p][1] += nb
				else:
					held[p] = [start, nb]
	done += [(p,) + tuple(h) for p, h in held.items()]
	for p, start, length in sorted(done, key=lambda d: d[1]):
		sc.note(bus, inst, p, 0, start, length + overlap, vel, pan, 0.0, **kw)


def bassline(sc: Score, bus: str, inst, chords, bar0: int, pattern, lo: int, vel: float, human: float = 0.004,
		**kw) -> None:
	"""pattern [(beat, beats, deg)] per bar or {segment_beats: [...]}; deg b / 5 / 8 / 3."""
	for i, entry in enumerate(chords):
		for sym, b0, nb in chord_segments(entry, sc.bpb):
			ci = chord_info(sym)
			b = in_range(ci["bass"], lo)
			notes = {"b": b, "8": b + 12, "5": in_range((ci["root"] + 7) % 12, lo),
				"3": in_range((ci["root"] + ci["ivs"][1]) % 12, lo)}
			if isinstance(pattern, dict):
				pat = [(b0 + p[0],) + tuple(p[1:]) for p in pattern[round(nb, 3)]]
			else:
				pat = [p for p in pattern if b0 - 1e-6 <= p[0] < b0 + nb - 1e-6]
			for beat, beats, deg in pat:
				sc.note(bus, inst, notes[deg], bar0 + i, beat, beats, vel * (1.0 if beat == b0 else 0.85), 0.0, human, **kw)


def perc(sc: Score, bus: str, inst, freq: float, bars, beats, vel: float, pan: float = 0.0, human: float = 0.005,
		accent: dict | None = None) -> None:
	for bar in bars:
		for b in beats:
			v = vel * (accent.get(b, 1.0) if accent else 1.0)
			sc.note(bus, inst, float(freq), bar, b, 0.25, v, pan, human)


def chord_pcs_at(chords, bpb: float, bar: int, beat: float):
	"""Pitch classes (chord tones + bass) of the chord sounding at bar/beat of a whole-piece chord list."""
	if chords is None or not 0 <= bar < len(chords):
		return None
	for sym, b0, nb in chord_segments(chords[bar], bpb):
		if b0 - 1e-6 <= beat < b0 + nb - 1e-6:
			ci = chord_info(sym)
			return {(ci["root"] + iv) % 12 for iv in ci["ivs"]} | {ci["bass"]}
	return None


def glints(sc: Score, bus: str, inst, notes, bar_a: float, bar_b: float, count: int, vel=(0.18, 0.32),
		spread: float = 0.8, chords=None) -> None:
	"""Randomly placed high notes (fireflies, ripples) - seeded, so reproducible. With `chords` (the
	whole-piece chord list from bar 0) a glint never lands a semitone against the chord of the moment:
	only notes that are chord tones or a whole step (or more) from every chord tone are drawn."""
	for _ in range(count):
		b = float(sc.rng.uniform(bar_a, bar_b))
		bar = int(b)
		beat = round((b - bar) * sc.bpb * 2) / 2.0
		if beat >= sc.bpb:
			continue
		cand = notes
		pcs = chord_pcs_at(chords, sc.bpb, bar, beat)
		if pcs:
			ok = [n for n in notes if M.midi(n) % 12 in pcs
				or not any((M.midi(n) - q) % 12 in (1, 11) for q in pcs)]
			if not ok:
				continue
			cand = ok
		sc.note(bus, inst, cand[int(sc.rng.integers(0, len(cand)))], bar, beat, 0.5,
			float(sc.rng.uniform(*vel)), float(sc.rng.uniform(-spread, spread)), 0.01)


# ==========================================================================================
# m03  Wood, Wool & Windows  (C major, 4/4, 96 bpm; 6-bar phrases, 3+3+2 marimba pulse)
# ==========================================================================================

M03_A = """
E5/.5 D5/.5 E5/1 A5/1.5 G5/.5 | F5/.5 E5/.5 F5/1 C6/1.5 A5/.5 | G5/1 D5/.5 E5/.5 D5/2 |
E5/.5 D5/.5 E5/1 A5/1.5 G5/.5 | F5/.5 E5/.5 F5/1 D6/1 C6/.5 A5/.5 | G5/.5 F5/.5 D5/.5 B4/.5 C5/2 |
E5/.5 D5/.5 E5/1 A5/1.5 G5/.5 | C6/1 B5/.5 A5/.5 E5/2 | F5/.5 E5/.5 F5/1 A5/1 C6/1 |
C6/1.5 B5/.5 G5/1 F5/1 | A5/.5 G5/.5 F5/.5 E5/.5 D5/.5 E5/.5 F5/.5 D5/.5 | C5/.5 E5/.5 G5/.5 C6/.5 r/2
"""
M03_B = """
E5/2 C5/1 A4/1 | A4/1.5 C5/.5 E5/1 F5/1 | G5/2 E5/1 C5/1 | D5/1.5 C5/.5 B4/1 G4/1 |
A4/1 C5/1 E5/1 A5/1 | A5/2 G#5/2 | A5/1.5 G5/.5 F5/1 C5/1 | D5/1 E5/.5 F5/.5 G5/2 |
E5/1.5 B5/1.5 C6/1 | D6/1.5 C6/1.5 A5/1 | Ab5/2 F5/1 D5/1 | G5/1.5 F5/.5 D5/1 r/1
"""
# B bars 8-9 were 'E5/1 G5/1 C6/1.5 B5/.5 | A5/2 F5/1 D5/1' - the opening of music_haven's B section
# (E5 G5 C6. B5 | A5-- F#5 D5) at the same pitch and rhythm, in a cue that rotates with music_haven.
# Reviewer rewrite: the climb now rides the piece's own 3+3+2 pulse up to D6.
M03_C = """
A5/1 C6/1 E6/2 | D6/1 B5/1 G5/2 | F5/1 A5/1 C6/1.5 A5/.5 | B5/3 r/1 | A5/1 G5/1 E5/1 C5/1 | D5/2 F5/1 r/1
"""
M03_DESCANT = "E6/4 | E6/2 C6/2 | D6/2 F6/2 | F6/2 D6/2 | C6/2 B5/2 | C6/2 r/2"
M03_CODA = "E5/.5 D5/.5 E5/1 A5/2 | G5/4 | F5/.5 E5/.5 F5/1 Ab5/2 | G5/1 C6/3"

M03_INTRO_CH = ["C", "F/C"]
M03_A_CH = ["C", "F", "G", "C/E", "F Dm7", "G7 C", "C", "Am", "Dm7", "G7sus4 G7", "F G", "C"]
M03_B_CH = ["Am", "Fmaj7", "C/G", "F G", "Am", "Esus4 E", "F", "G", "Em7 Am", "Dm7", "Fm6", "G7sus4 G7"]
M03_C_CH = ["Fmaj7", "Em7", "Dm7", "Cmaj7/E", "Fmaj7", "G7sus4 G7"]
M03_CODA_CH = ["F/C", "C", "Fm6/C", "Cadd9"]

MAR_LIGHT = [(0, "b", 1.0), (1.5, "3", 0.75), (3, "5", 0.7), (3.5, "8", 0.4)]
MAR_FULL = [(0, "b", 1.0), (0.5, "5", 0.45), (1, "3", 0.5), (1.5, "r", 0.85), (2, "5", 0.45), (2.5, "3", 0.5),
	(3, "8", 0.8), (3.5, "5", 0.42)]
BASS_332 = [(0, 1.3, "b"), (1.5, 1.3, "5"), (3, 0.9, "8")]


def cue_m03(rng):
	chords = M03_INTRO_CH + M03_A_CH + M03_B_CH + M03_C_CH + M03_A_CH + M03_CODA_CH
	sec = {"intro": 0, "A": 2, "B": 14, "C": 26, "A'": 32, "coda": 44, "end": 48}
	sc = Score(96, 4, 48, rng, tempo=[(0, 96), (45, 96), (46.5, 86), (48, 66)])
	A, B, C, A2, CO = sec["A"], sec["B"], sec["C"], sec["A'"], sec["coda"]
	# --- melody -------------------------------------------------------------------------
	line(sc, "pizz", I.pizzicato, M03_A, A, 0.78, 0.12, phrase=6)
	line(sc, "harp", I.nylon, M03_A, A, 0.34, 0.2, phrase=6)
	line(sc, "marlead", I.marimba, M03_B, B, 0.72, -0.08, phrase=6, roll=2.0, legato=1.0)
	line(sc, "cel", M.celesta, M03_C, C, 0.62, 0.22, phrase=6)
	line(sc, "pizz", I.pizzicato, M03_A, A2, 0.72, 0.14, phrase=6)
	line(sc, "marlead", I.marimba, M03_A, A2, 0.5, -0.12, transpose=-12, phrase=6)
	line(sc, "cel", M.celesta, M03_DESCANT, A2 + 6, 0.36, 0.35, phrase=6)
	line(sc, "pizz", I.pizzicato, M03_CODA, CO, 0.7, 0.1, phrase=4)
	line(sc, "marlead", I.marimba, M03_CODA, CO, 0.5, -0.1, phrase=4, roll=3.0, legato=1.0, only_bars={3})
	# --- marimba 3+3+2 pulse --------------------------------------------------------------
	arp(sc, "mar", I.marimba, M03_INTRO_CH, 0, MAR_LIGHT, 55, 0.5, -0.2)
	arp(sc, "mar", I.marimba, M03_A_CH[:6], A, MAR_LIGHT, 55, 0.5, -0.2)
	arp(sc, "mar", I.marimba, M03_A_CH[6:], A + 6, MAR_FULL, 55, 0.48, -0.2)
	arp(sc, "mar", I.marimba, M03_A_CH, A2, MAR_FULL, 55, 0.52, -0.2)
	arp(sc, "mar", I.marimba, M03_CODA_CH[:3], CO, MAR_LIGHT, 55, 0.42, -0.2)
	# --- plucked chords: pizz "chick" in B, harp offbeat strums in the second halves ----------
	blocks(sc, "pizzch", I.pizzicato, M03_B_CH, B, [(1, 0.5, 0.8), (3, 0.5, 0.7)], 55, 72, 0.42, 0.3, roll=0.03,
		max_voices=3)
	strum = [(1, 0.8, 0.8), (3, 0.8, 0.7), (3.5, 0.4, 0.45)]
	blocks(sc, "harp", I.nylon, M03_A_CH[6:], A + 6, strum, 55, 72, 0.4, 0.3, roll=0.04, max_voices=3)
	blocks(sc, "harp", I.nylon, M03_B_CH, B, [(0, 2, 0.7), (2, 2, 0.55)], 52, 69, 0.36, -0.35, roll=0.08, max_voices=4)
	arp(sc, "harp", I.nylon, M03_C_CH, C, [(0, "b", 0.8, 2), (0.5, "5", 0.6), (1, "8", 0.55), (1.5, "3+", 0.5),
		(2, "5+", 0.5, 2), (3, "3+", 0.45)], 53, 0.42, -0.3)
	blocks(sc, "harp", I.nylon, M03_A_CH, A2, strum, 55, 72, 0.4, 0.3, roll=0.04, max_voices=3)
	# --- bass -------------------------------------------------------------------------------
	bassline(sc, "bass", M.pluck_bass, M03_INTRO_CH[1:], 1, BASS_332, 36, 0.62)
	bassline(sc, "bass", M.pluck_bass, M03_A_CH, A, BASS_332, 36, 0.72)
	bassline(sc, "bass", M.pluck_bass, M03_B_CH, B, [(0, 1.8, "b"), (2, 1.8, "5")], 36, 0.66)
	bassline(sc, "bass", M.soft_bass, M03_C_CH, C, [(0, 3.2, "b")], 36, 0.34)
	bassline(sc, "bass", M.pluck_bass, M03_A_CH, A2, BASS_332, 36, 0.76)
	bassline(sc, "bass", M.soft_bass, M03_CODA_CH, CO, [(0, 3.6, "b")], 36, 0.42)
	# --- warm pad under B, C, A' and the ending -----------------------------------------------
	pads(sc, "pad", I.bowed, M03_B_CH + M03_C_CH, B, 52, 67, 0.4, cutoff=1300)
	pads(sc, "pad", I.bowed, M03_A_CH, A2, 55, 70, 0.34, cutoff=1500)
	pads(sc, "pad", I.bowed, M03_CODA_CH, CO, 52, 67, 0.4, cutoff=1200, release=2.6)
	# --- final chord: low marimba strike, pizz arpeggio, celesta glint ------------------------
	for k, nm in enumerate(["C3", "G3", "E4"]):
		sc.note("mar", I.marimba, nm, CO + 3, 0.0 + 0.06 * k, 1.0, 0.55, -0.2, 0.0)
	for k, nm in enumerate(["C3", "G3", "E4", "G4", "C5"]):
		sc.note("pizzch", I.pizzicato, nm, CO + 3, 0.5 + 0.12 * k, 1.0, 0.45, 0.3, 0.0)
	for k, nm in enumerate(["G6", "C7"]):
		sc.note("cel", M.celesta, nm, CO + 3, 1.0 + 0.5 * k, 1.0, 0.28, 0.4, 0.0)
	# --- light percussion: shaker in A's second half, clay-pot pulse in B2, all in A' ----------
	perc(sc, "perc", M.shaker, 440.0, range(A + 6, A + 12), (0.5, 1.5, 2.5, 3.5), 0.3, 0.35)
	perc(sc, "perc", I.clay_pot, 150.0, range(B + 6, B + 12), (0.0, 2.5), 0.4, -0.1, accent={2.5: 0.7})
	perc(sc, "perc", M.shaker, 440.0, range(A2, A2 + 12), (0.5, 1.5, 2.5, 3.5), 0.34, 0.35)
	perc(sc, "perc", M.woodblock, 900.0, range(A2, A2 + 12), (1.5, 3.0), 0.22, -0.25)
	perc(sc, "perc", I.clay_pot, 150.0, range(A2, A2 + 12), (0.0,), 0.38, -0.1)
	# dynamics: gentle growth, the quiet 'windows' interlude, a full return, a soft ending
	sc.master_auto = [(0, -1.5), (A, -1.0), (B, -0.5), (C - 0.5, 0.0), (C, -2.5), (A2 - 0.5, -2.0), (A2, 0.5),
		(CO, 0.0), (48, -2.0)]
	ir = S.hall(rng, 1.7, brightness=7500)
	levels = {"pizz": (8.5, 0.25), "marlead": (-4.0, 0.25), "cel": (-5.0, 0.4), "mar": (-7.5, 0.22),
		"pizzch": (0.0, 0.25), "harp": (3.5, 0.3), "bass": (-7.0, 0.08), "pad": (-14.0, 0.4), "perc": (-11.0, 0.18)}
	return sc, levels, ir, sec


# ==========================================================================================
# m04  Berry Tea Afternoon  (Bb major, 6/8 counted in eighths, dotted quarter = 50)
# ==========================================================================================

M04_A = """
F4/1 Bb4/1 D5/1 F5/2 D5/1 | Eb5/2 G5/1 F5/2 Eb5/1 | D5/2 F5/1 Bb5/2 A5/1 | G5/3 F5/3 |
D5/1 G5/1 Bb5/1 A5/2 G5/1 | G5/2 Eb5/1 C5/2 Eb5/1 | D5/2 C5/1 A4/2 C5/1 | Bb4/3 r/3
"""
M04_A2 = """
F4/1 Bb4/1 D5/1 F5/2 D5/1 | Eb5/2 G5/1 F5/2 Eb5/1 | D5/2 F5/1 Bb5/2 A5/1 | G5/3 F5/3 |
Eb5/1 G5/1 Bb5/1 C6/2 Bb5/1 | A5/2 F5/1 G5/2 D5/1 | C6/2 Bb5/1 G5/2 Eb5/1 | D5/1 C5/1 Bb4/4
"""
M04_B = """
Bb4/2 Eb5/1 G5/3 | F5/2 Eb5/1 C5/3 | D5/2 F5/1 A5/3 | G5/6 |
Eb5/2 G5/1 Bb5/2 G5/1 | A5/3 F5/3 | F5/2 D5/1 G5/2 Eb5/1 | F5/4 r/2
"""
M04_B2 = """
Bb4/2 Eb5/1 G5/2 Bb5/1 | A5/3 C6/3 | A5/2 G5/1 F5/2 D5/1 | F5/2 G5/1 D5/3 |
Eb5/2 D5/1 C5/2 Bb4/1 | C5/3 Gb5/3 | F5/6 | r/6
"""
M04_FILL = "Bb4/1 C5/1 Eb5/1 A4/1 C5/1 Eb5/1"
M04_TENOR = "D4/6 | Eb4/3 G4/3 | F4/6 | Eb4/6 | G4/6 | F4/3 D4/3 | Eb4/6 | D4/6"
M04_CODA = "F4/1 Bb4/1 D5/1 G5/3 | F4/1 A4/1 C5/1 A5/3 | F5/3 D5/3 | Eb5/3 C5/3 | D5/6"

M04_INTRO_CH = ["Bb", "Ebmaj7/Bb"]
M04_A_CH = ["Bb", "Eb", "Bb/D", "Cm7 F7", "Gm", "Eb", "Cm7 F7", "Bb"]
M04_A2_CH = ["Bb", "Eb", "Bb/D", "Cm7 F7", "Ebmaj7", "Dm7 Gm7", "Cm7 F7sus4", "Bb"]
M04_B_CH = ["Ebmaj7", "F", "Dm7", "Gm", "Cm7", "F/A", "Bb/D Eb", "F7sus4 F7"]
M04_B2_CH = ["Ebmaj7", "F/Eb", "Dm7", "Gm7", "Cm9", "Ebm6", "Bb/F", "F7sus4 F7"]
M04_CODA_CH = ["Ebmaj7", "F/Eb", "Dm7 Gm7", "Cm7 F7sus4", "Bbadd9"]

BARC = {6: [(0, "b", 1.0), (1, "5-", 0.5), (2, "r", 0.5), (3, "3", 0.6), (4, "r", 0.45), (5, "5-", 0.42)],
	3: [(0, "b", 0.95), (1, "5-", 0.5), (2, "3", 0.5)]}
BARC_SOFT = {6: [(0, "b", 1.0), (2, "r", 0.45), (3, "3", 0.5), (5, "5-", 0.4)], 3: [(0, "b", 0.9), (2, "3", 0.45)]}


def cue_m04(rng):
	chords = M04_INTRO_CH + M04_A_CH + M04_A2_CH + M04_B_CH + M04_B2_CH + M04_A2_CH + M04_CODA_CH
	sec = {"intro": 0, "A": 2, "A2": 10, "B": 18, "B'": 26, "A'": 34, "coda": 42, "end": 47}
	sc = Score(150, 6, 47, rng, tempo=[(0, 150), (44, 150), (45.5, 132), (47, 96)])
	A, A2, B, B2, A3, CO = sec["A"], sec["A2"], sec["B"], sec["B'"], sec["A'"], sec["coda"]
	piano = I.felt_piano
	# --- piano: melody + barcarolle left hand (with pedal) -----------------------------------
	arp(sc, "pianoL", piano, M04_INTRO_CH, 0, BARC_SOFT, 58, 0.42, -0.15, hold=True)
	line(sc, "pianoR", piano, M04_A, A, 0.6, 0.1, phrase=4, legato=1.05, pedal=0.25)
	arp(sc, "pianoL", piano, M04_A_CH, A, BARC, 58, 0.42, -0.15, hold=True)
	line(sc, "pianoR", piano, M04_A2, A2, 0.6, 0.1, phrase=4, legato=1.05, pedal=0.25)
	line(sc, "cel", M.celesta, M04_A2, A2, 0.34, 0.3, transpose=12, phrase=4)
	arp(sc, "pianoL", piano, M04_A2_CH, A2, BARC, 58, 0.42, -0.15, hold=True)
	# B: the airy lead sings; piano changes to soft dotted-quarter chords
	line(sc, "air", I.air_lead, M04_B, B, 0.62, -0.12, phrase=4, legato=0.97)
	blocks(sc, "pianoL", piano, M04_B_CH, B, {6: [(0, 2.8, 0.8), (3, 2.8, 0.6)], 3: [(0, 2.8, 0.7)]}, 55, 70, 0.36,
		-0.1, roll=0.12, pedal=0.3)
	# B': duet (celesta shadows the air lead an octave up), then the piano alone for a breath
	line(sc, "air", I.air_lead, M04_B2, B2, 0.6, -0.12, phrase=4, legato=0.97)
	line(sc, "cel", M.celesta, M04_B2, B2, 0.28, 0.35, transpose=12, phrase=4)
	blocks(sc, "pianoL", piano, M04_B2_CH[:6], B2, {6: [(0, 2.8, 0.8), (3, 2.8, 0.6)]}, 55, 70, 0.34, -0.1,
		roll=0.12, pedal=0.3)
	arp(sc, "pianoL", piano, M04_B2_CH[6:], B2 + 6, BARC_SOFT, 58, 0.38, -0.15, hold=True)
	line(sc, "pianoR", piano, M04_FILL, B2 + 7, 0.42, 0.1, phrase=1, pedal=0.2)
	# A': tutti - piano melody + celesta, the air lead's warm tenor counter-line
	line(sc, "pianoR", piano, M04_A2, A3, 0.64, 0.1, phrase=4, legato=1.05, pedal=0.25)
	line(sc, "cel", M.celesta, M04_A2, A3, 0.38, 0.3, transpose=12, phrase=4)
	line(sc, "air", I.air_lead, M04_TENOR, A3, 0.5, -0.25, phrase=4, legato=0.98, arch=0.2)
	arp(sc, "pianoL", piano, M04_A2_CH, A3, BARC, 58, 0.45, -0.15, hold=True)
	# coda: the opening figure over new harmony, slowing to the final chord
	line(sc, "pianoR", piano, M04_CODA, CO, 0.56, 0.1, phrase=5, legato=1.05, pedal=0.4)
	arp(sc, "pianoL", piano, M04_CODA_CH[:4], CO, BARC_SOFT, 58, 0.4, -0.15, hold=True)
	for k, nm in enumerate(["Bb1", "F2", "D3", "C4", "F4"]):
		sc.note("pianoL", piano, nm, CO + 4, 0.0 + 0.25 * k, 6.0, (0.3 if k < 2 else 0.4) - 0.02 * k, -0.15, 0.0, pedal=2.0)
	for k, nm in enumerate(["D6", "F6", "C7"]):
		sc.note("cel", M.celesta, nm, CO + 4, 2.0 + 1.0 * k, 1.0, 0.3, 0.35, 0.0)
	# --- bass & pad ------------------------------------------------------------------------------
	bassline(sc, "bass", M.soft_bass, M04_B_CH + M04_B2_CH[:6], B, {6: [(0, 5.4, "b")], 3: [(0, 2.7, "b")]}, 36, 0.55)
	bassline(sc, "bass", M.soft_bass, M04_A2_CH, A3, {6: [(0, 2.7, "b"), (3, 2.7, "5")], 3: [(0, 2.7, "b")]}, 36, 0.55)
	pads(sc, "pad", I.bowed, M04_B_CH + M04_B2_CH[:7], B, 53, 67, 0.36, cutoff=1200)
	pads(sc, "pad", I.bowed, M04_A2_CH, A3, 55, 69, 0.3, cutoff=1300)
	pads(sc, "pad", I.bowed, M04_CODA_CH, CO, 53, 67, 0.34, cutoff=1100, release=2.8)
	# --- sparse percussion: brush on the 4th eighth, a shaker whisper, spoon-on-cup 'tinks' -----
	perc(sc, "perc", I.brush, 1.0, range(A + 4, A + 8), (3,), 0.3, 0.2)
	perc(sc, "perc", I.brush, 1.0, range(A2, A2 + 8), (3,), 0.34, 0.2)
	perc(sc, "perc", M.shaker, 440.0, range(A2, A2 + 8), (2, 5), 0.22, 0.4)
	perc(sc, "perc", M.tom, 72.0, (B, B + 4), (0,), 0.3, 0.0)
	perc(sc, "perc", I.brush, 1.0, range(A3, A3 + 8), (3,), 0.36, 0.2)
	perc(sc, "perc", M.shaker, 440.0, range(A3, A3 + 8), (2, 5), 0.24, 0.4)
	perc(sc, "perc", I.clay_pot, 160.0, range(A3, A3 + 8, 2), (0,), 0.35, -0.1)
	for bar, e, f in ((A2 + 7, 3, 2637.0), (B + 3, 4, 2349.0), (B + 7, 4, 2637.0), (B2 + 3, 4, 2349.0),
			(A3 + 7, 3, 2637.0), (CO + 4, 5, 2794.0)):
		sc.note("tink", I.tink, f, bar, e, 0.5, 0.4, 0.45, 0.0)
	sc.master_auto = [(0, -2.0), (A, -1.0), (A2, 0.0), (B, -0.5), (B2 + 5, -1.0), (B2 + 6, -2.5), (A3, 0.5),
		(CO, -0.5), (47, -2.0)]
	ir = S.hall(rng, 2.0, brightness=7000)
	levels = {"pianoR": (4.0, 0.28), "pianoL": (-4.5, 0.3), "cel": (-5.0, 0.4), "air": (-4.0, 0.32),
		"bass": (-10.0, 0.08), "pad": (-15.0, 0.4), "perc": (-11.0, 0.2), "tink": (-13.0, 0.45)}
	return sc, levels, ir, sec


# ==========================================================================================
# m06  Firefly Wishes  (Eb major, 3/4, 63 bpm; a lullaby built on a rising-sixth 'wish')
# ==========================================================================================

# bars 1-2 were 're. do la | sol-- mi' (F5. Eb5 C5 | Bb4-- G4) - pitch and rhythm of the 'over the
# ocean' cadence of "My Bonnie" in the same 3/4; reviewer rewrite: 'fa. re la | do-- sol'.
M06_A = """
Eb5/1 Bb4/1 G5/1 | Ab5/1.5 F5/.5 C5/1 | Eb5/2 Bb4/1 | Ab4/2 D5/1 |
C5/1 G4/1 Eb5/1 | Eb5/1.5 C5/.5 Ab4/1 | F5/1.5 Eb5/.5 D5/1 | Eb5/3
"""
M06_A2 = """
Eb5/1 Bb4/1 G5/1 | Ab5/1.5 G5/.5 F5/1 | D5/1 F5/1 Bb5/1 | G5/2 F5/.5 Eb5/.5 |
C5/1 Eb5/1 G5/1 | Bb5/1.5 Ab5/.5 G5/1 | F5/1 Ab5/1 D5/1 | Eb5/3
"""
M06_B = """
C5/2 Eb5/1 | D5/3 | Bb4/2 D5/1 | C5/3 | Ab4/1 C5/1 F5/1 | Ab5/2 F5/1 | G5/2 Bb5/1 | C6/2 Bb5/1 | Bb5/2 Ab5/1
"""
M06_CODA = "Eb5/1 Bb4/1 G5/1 | Ab5/1.5 F5/.5 Cb5/1 | Bb4/3 | Ab4/2 F4/1 | G4/3"

M06_INTRO_CH = ["Eb", "Abmaj7/Eb", "Eb", "Bb7sus4"]
M06_A_CH = ["Eb", "Ab/Eb", "Eb/G", "Bb7sus4*2 Bb7*1", "Cm", "Ab", "Fm7*2 Bb7*1", "Eb"]
M06_A2_CH = ["Eb", "Ab/Eb", "Gm7", "Cm", "Abmaj7", "Eb/Bb", "Fm7*2 Bb7*1", "Eb"]
M06_B_CH = ["Ab", "Bb/Ab", "Gm7", "Cm", "Fm7", "Bb7", "Ebmaj7/G", "Ab*2 Bb7sus4*1", "Bb7sus4*2 Bb7*1"]
M06_CODA_CH = ["Abmaj7", "Abm6", "Eb/G", "Fm7*2 Bb7sus4*1", "Ebadd9"]

HARP_Q = {3: [(0, "b", 0.9), (1, "5", 0.55), (1.5, "8", 0.5), (2, "3+", 0.5)],
	2: [(0, "b", 0.85), (1, "5", 0.5)], 1: [(0, "3+", 0.5)]}
HARP_8 = {3: [(0, "b", 0.9), (0.5, "5", 0.5), (1, "8", 0.5), (1.5, "3+", 0.5), (2, "5+", 0.45), (2.5, "8", 0.4)],
	2: [(0, "b", 0.85), (0.5, "5", 0.5), (1, "8", 0.5), (1.5, "3+", 0.45)], 1: [(0, "b", 0.7), (0.5, "5", 0.45)]}
EB_PENT_HI = ["Eb6", "F6", "G6", "Bb6", "C7"]


def cue_m06(rng):
	chords = M06_INTRO_CH + M06_A_CH + M06_A2_CH + M06_B_CH + M06_A_CH + M06_CODA_CH
	sec = {"intro": 0, "A": 4, "A2": 12, "B": 20, "A'": 29, "coda": 37, "end": 42}
	sc = Score(63, 3, 42, rng, tempo=[(0, 63), (38, 63), (40, 56), (42, 42)], tail=9.0)
	A, A2, B, A3, CO = sec["A"], sec["A2"], sec["B"], sec["A'"], sec["coda"]
	harp = I.lullaby_harp
	# --- melody -----------------------------------------------------------------------------
	line(sc, "harpmel", harp, M06_A, A, 0.62, 0.18, phrase=4, arch=0.18)
	line(sc, "clar", M.clarinet, M06_A2, A2, 0.5, -0.12, transpose=-12, phrase=4, legato=0.97, arch=0.2)
	line(sc, "str", I.bowed, M06_B, B, 0.6, 0.05, phrase=4, legato=1.0, arch=0.2, attack=0.28, release=1.1,
		cutoff=2300)
	line(sc, "box", M.music_box, M06_A, A3, 0.5, 0.25, transpose=12, phrase=4, arch=0.15)
	line(sc, "harpmel", harp, M06_A, A3, 0.5, -0.2, phrase=4, arch=0.15)
	line(sc, "harpmel", harp, M06_CODA, CO, 0.55, 0.12, phrase=5, arch=0.1)
	# --- harp accompaniment -------------------------------------------------------------------
	arp(sc, "harp", harp, M06_INTRO_CH, 0, HARP_Q, 51, 0.5, -0.3)
	arp(sc, "harp", harp, M06_A_CH + M06_A2_CH, A, HARP_Q, 51, 0.46, -0.3)
	arp(sc, "harp", harp, M06_B_CH[:8], B, HARP_8, 51, 0.44, -0.3)
	arp(sc, "harp", harp, M06_A_CH, A3, HARP_8, 51, 0.4, -0.3)
	arp(sc, "harp", harp, M06_CODA_CH[:4], CO, HARP_Q, 51, 0.42, -0.3)
	# transition (bar 28): a rising harp glissando on the Eb pentatonic, a soft air swell
	gl = ["Bb3", "C4", "Eb4", "F4", "G4", "Bb4", "C5", "Eb5", "F5", "G5", "Bb5"]
	for k, nm in enumerate(gl):
		sc.note("harp", harp, nm, B + 8, 1.0 + k * 0.14, 1.0, 0.3 + 0.02 * k, -0.4 + 0.07 * k, 0.0)
	sc.note("swell", M.swell, 1000.0, B + 8, 0.5, 2.3, 0.6, 0.0, 0.0)
	# final bar: a slow rolled Eb(add9) from the bass to the top
	for k, nm in enumerate(["Eb2", "Bb2", "G3", "Eb4", "F4", "Bb4", "Eb5"]):
		sc.note("harp", harp, nm, CO + 4, 0.3 + 0.22 * k, 3.0, 0.45 - 0.02 * k, -0.3 + 0.1 * k, 0.0)
	# --- warm sustained tones ------------------------------------------------------------------
	pads(sc, "pad", I.bowed, M06_INTRO_CH[2:] + M06_A_CH, 2, 50, 65, 0.36, cutoff=900, attack=1.2, release=2.0)
	pads(sc, "pad", I.bowed, M06_A2_CH + M06_B_CH, A2, 51, 67, 0.4, cutoff=1000, attack=1.0, release=2.0)
	pads(sc, "pad", M.pad, M06_A_CH, A3, 55, 70, 0.4, attack=1.4, release=2.2, cutoff=1100)
	pads(sc, "pad", I.bowed, M06_CODA_CH, CO, 50, 65, 0.4, cutoff=850, attack=1.2, release=4.0)
	bassline(sc, "bass", M.soft_bass, M06_A2_CH + M06_B_CH + M06_A_CH, A2, {3: [(0, 2.8, "b")], 2: [(0, 1.9, "b")],
		1: [(0, 0.9, "b")]}, 36, 0.5)
	bassline(sc, "bass", M.soft_bass, M06_CODA_CH, CO, {3: [(0, 2.9, "b")], 2: [(0, 1.9, "b")], 1: [(0, 0.9, "b")]},
		36, 0.45)
	# --- fireflies: celesta glints, most around the final lullaby statement ----------------------
	glints(sc, "fly", M.celesta, EB_PENT_HI, 1, A, 3, chords=chords)
	glints(sc, "fly", M.celesta, EB_PENT_HI, A, A2, 4, chords=chords)
	glints(sc, "fly", M.celesta, EB_PENT_HI, A2, B, 3, chords=chords)
	glints(sc, "fly", M.celesta, EB_PENT_HI, B + 4, A3, 2, chords=chords)
	glints(sc, "fly", M.celesta, EB_PENT_HI, A3, CO, 9, vel=(0.2, 0.36), chords=chords)
	glints(sc, "fly", M.celesta, EB_PENT_HI, CO, CO + 4, 3, chords=chords)
	sc.note("fly", M.celesta, "Eb7", CO + 4, 2.0, 1.0, 0.25, 0.5, 0.0)
	sc.master_auto = [(0, 3.0), (A - 0.5, 2.0), (A, -0.5), (A2, -0.5), (B, 0.0), (B + 7, 0.8), (A3, -0.5), (CO, -1.0),
		(42, -2.5)]
	ir = S.hall(rng, 3.4, brightness=6000)
	levels = {"harpmel": (9.5, 0.4), "clar": (-10.5, 0.4), "str": (1.5, 0.42), "box": (-2.5, 0.45),
		"harp": (1.5, 0.38), "pad": (-11.0, 0.5), "bass": (-12.0, 0.12), "fly": (-14.0, 0.7), "swell": (-20.0, 0.5)}
	return sc, levels, ir, sec


# ==========================================================================================
# m07  Footpaths & Ferns  (A major, 4/4, 104 bpm; walking bass, bells, climbing phrases)
# ==========================================================================================

M07_A = """
A4/.5 B4/.5 C#5/.5 E5/.5 A5/1 r/1 | F#5/1 E5/.5 D5/.5 A4/1 r/1 | B4/.5 C#5/.5 E5/.5 G#5/.5 B5/1 r/1 | A5/1.5 E5/.5 C#5/1 r/1 |
F#4/.5 A4/.5 C#5/.5 E5/.5 F#5/1 A5/1 | F#5/1.5 E5/.5 D5/1 A4/1 | B4/.5 C#5/.5 D5/.5 F#5/.5 A5/1 B5/1 | B5/1 A5/1 G#5/1 E5/1
"""
M07_A2 = """
A4/.5 B4/.5 C#5/.5 E5/.5 A5/1 r/1 | F#5/1 E5/.5 D5/.5 A4/1 r/1 | B4/.5 C#5/.5 E5/.5 G#5/.5 B5/1 C#6/1 | E6/1.5 C#6/.5 B5/1 G#5/1 |
F#4/.5 A4/.5 C#5/.5 E5/.5 F#5/1 A5/1 | B5/1 A5/.5 F#5/.5 D5/1 F#5/1 | E5/1 D5/.5 B4/.5 G#4/1 B4/1 | A4/2 r/2
"""
M07_INTRO_BELLS = "r/4 | r/4 | r/2 A4/.5 B4/.5 C#5/.5 E5/.5 | A5/1 r/1 B4/.5 C#5/.5 D5/.5 E5/.5"
M07_A2_BELLS = "r/3 C#6/.5 E6/.5 | r/3 D6/.5 F#6/.5 | r/4 | r/4 | r/4 | r/4 | r/4 | r/2 C#6/.5 E6/.5 A6/1"
M07_B = """
A4/1 D5/1 F#5/2 | E5/1.5 D5/.5 B4/2 | C#5/1 E5/1 G#5/2 | A5/3 r/1 |
B4/1 D5/1 F#5/1.5 E5/.5 | E5/1 G#5/1 B5/2 | C#6/2 A5/2 | B5/2 A5/1 E5/1
"""
M07_B_BELLS = "r/4 | r/4 | r/4 | r/2 E6/.5 C#6/.5 A5/1 | r/4 | r/4 | r/4 | r/4"
M07_B2 = """
A4/1 D5/1 F#5/2 | G#5/1.5 F#5/.5 E5/2 | E5/1 G#5/1 B5/2 | C#6/3 r/1 |
D#5/1 F#5/1 A5/1.5 B5/.5 | B5/2 G#5/2 | A5/1 F#5/1 C#6/2 | B5/2 G#5/2
"""
M07_B2_BELLS = "r/4 | r/4 | r/4 | r/2 G#6/.5 E6/.5 C#6/1 | r/4 | r/4 | r/4 | r/4"
M07_BREATH = "A4/.5 B4/.5 C#5/.5 E5/.5 A5/2 | B4/.5 C#5/.5 E5/.5 F#5/.5 G#5/1 B5/1"
M07_A3_BELLS = """
A5/.5 B5/.5 C#6/.5 E6/.5 A6/1 r/1 | r/3 D6/.5 F#6/.5 | B5/.5 C#6/.5 E6/.5 G#6/.5 B6/1 r/1 | r/4 |
F#5/.5 A5/.5 C#6/.5 E6/.5 F#6/1 r/1 | r/4 | r/4 | r/2 C#6/.5 E6/.5 A6/1
"""
M07_CODA = "A4/.5 B4/.5 C#5/.5 E5/.5 A5/2 | B4/.5 C#5/.5 E5/.5 G#5/.5 B5/2 | C#5/.5 D#5/.5 F#5/.5 A5/.5 C#6/2 | C#6/.5 E6/.5 A6/3"
M07_CODA_FL = "E5/4 | E5/2 G#5/2 | F#5/4 | E5/4"

M07_INTRO_CH = ["A", "D/A", "A", "E7sus4"]
M07_A_CH = ["A", "D/A", "E/A", "A", "F#m", "D", "Bm7", "E7sus4 E7"]
M07_A2_CH = ["A", "D/A", "E/A", "C#m7", "F#m", "D", "Bm7 E7", "A"]
M07_B_CH = ["D", "E/D", "C#m7", "F#m7", "Bm7", "E", "C#m7 F#m7", "Bm7 E7sus4"]
M07_B2_CH = ["D", "E/D", "C#m7", "F#m7", "B7/D#", "E", "Dmaj7", "E7sus4 E7"]
M07_BR_CH = ["Dmaj7", "E7sus4 E7"]
M07_CODA_CH = ["Dmaj7", "E/D", "B/A", "Aadd9"]
A_MAJOR = {9, 11, 1, 2, 4, 6, 8}


def walking_bass(sc: Score, bus: str, inst, chords, bar0: int, lo: int, vel: float, next_chord: str | None = None):
	"""Quarter-note walking line: chord root, a chord tone, another chord tone, then a step (scale
	step preferred, chromatic otherwise) into the next bar's bass note."""
	seq = [chord_segments(e, sc.bpb) for e in chords]
	for i, segs in enumerate(seq):
		nxt = seq[i + 1][0][0] if i + 1 < len(seq) else next_chord
		notes = []
		if len(segs) == 1:
			ci = chord_info(segs[0][0])
			b = in_range(ci["bass"], lo)
			third = in_range((ci["root"] + ci["ivs"][1]) % 12, b)
			fifth = in_range((ci["root"] + 7) % 12, b)
			notes = [b, third if i % 2 == 0 else fifth, fifth if i % 2 == 0 else b + 12]
		else:
			c1, c2 = chord_info(segs[0][0]), chord_info(segs[1][0])
			b1 = in_range(c1["bass"], lo)
			notes = [b1, in_range((c1["root"] + 7) % 12, b1), in_range(c2["bass"], lo)]
		if nxt is None:
			notes.append(notes[0])
		else:
			target = in_range(chord_info(nxt)["bass"], lo)
			cand = [target + 2, target - 2, target - 1, target + 1]
			pick = next((c for c in cand if c % 12 in A_MAJOR and c != notes[-1]), target - 1)
			notes.append(pick)
		for k, n in enumerate(notes):
			sc.note(bus, inst, n, bar0 + i, float(k), 0.9, vel * (1.0 if k == 0 else 0.8 if k == 2 else 0.72), 0.0, 0.005)


def cue_m07(rng):
	chords = M07_INTRO_CH + M07_A_CH + M07_A2_CH + M07_B_CH + M07_B2_CH + M07_BR_CH + M07_A2_CH + M07_CODA_CH
	sec = {"intro": 0, "A": 4, "A2": 12, "B": 20, "B2": 28, "breath": 36, "A'": 38, "coda": 46, "end": 50}
	sc = Score(104, 4, 50, rng, tempo=[(0, 104), (47, 104), (48.5, 92), (50, 70)], tail=7.0)
	A, A2, B, B2, BR, A3, CO = (sec[k] for k in ("A", "A2", "B", "B2", "breath", "A'", "coda"))
	bell = I.soft_bell
	# --- melody ------------------------------------------------------------------------------
	line(sc, "bell", bell, M07_INTRO_BELLS, 0, 0.5, 0.2, phrase=4)
	line(sc, "bell", bell, M07_A, A, 0.62, 0.15, phrase=4)
	line(sc, "flute", M.flute, M07_A2, A2, 0.6, -0.1, phrase=4, legato=0.92)
	line(sc, "bell", bell, M07_A2_BELLS, A2, 0.45, 0.35)
	line(sc, "str", I.bowed, M07_B, B, 0.6, 0.0, phrase=4, legato=1.0, attack=0.22, release=0.9, cutoff=2600)
	line(sc, "bell", bell, M07_B_BELLS, B, 0.4, 0.35)
	line(sc, "str", I.bowed, M07_B2, B2, 0.64, 0.0, phrase=4, legato=1.0, attack=0.22, release=0.9, cutoff=2800)
	line(sc, "flute", M.flute, M07_B2, B2, 0.32, -0.2, transpose=-12, phrase=4, only_bars={4, 5, 6, 7})
	line(sc, "bell", bell, M07_B2_BELLS, B2, 0.4, 0.35)
	line(sc, "bell", bell, M07_BREATH, BR, 0.55, 0.1, phrase=2)
	line(sc, "flute", M.flute, M07_A2, A3, 0.64, -0.1, phrase=4, legato=0.92)
	line(sc, "bell", bell, M07_A3_BELLS, A3, 0.36, 0.3)
	line(sc, "bell", bell, M07_CODA, CO, 0.55, 0.12, phrase=4)
	line(sc, "flute", M.flute, M07_CODA_FL, CO, 0.44, -0.15, phrase=4, legato=0.98)
	# --- walking bass (the 'footpath') --------------------------------------------------------
	walking_bass(sc, "bass", M.pluck_bass, M07_INTRO_CH + M07_A_CH + M07_A2_CH, 0, 38, 0.7, "D")
	bassline(sc, "bass", M.pluck_bass, M07_B_CH + M07_B2_CH, B, [(0, 1.8, "b"), (2, 1.3, "5"), (3.5, 0.45, "b")],
		38, 0.62)
	bassline(sc, "bass", M.soft_bass, M07_BR_CH, BR, {4: [(0, 3.4, "b")], 2: [(0, 1.8, "b")]}, 38, 0.36)
	walking_bass(sc, "bass", M.pluck_bass, M07_A2_CH, A3, 38, 0.72, "Dmaj7")
	bassline(sc, "bass", M.soft_bass, M07_CODA_CH, CO, [(0, 3.6, "b")], 38, 0.4)
	# --- harp: skipping off-beat dyads in A, uncurling 'fern' arpeggios in B -------------------
	offb = [(0.5, "r", 0.6, 0.4), (0.5, "3", 0.5, 0.4), (1.5, "5", 0.55, 0.4), (1.5, "8", 0.45, 0.4),
		(2.5, "r", 0.55, 0.4), (2.5, "3", 0.45, 0.4), (3.5, "5", 0.5, 0.4), (3.5, "8", 0.4, 0.4)]
	fern = [(0, "r", 0.7), (0.5, "5", 0.5), (1, "8", 0.5), (1.5, "3+", 0.5), (2, "5+", 0.5), (2.5, "3+", 0.45),
		(3, "8", 0.45), (3.5, "5", 0.4)]
	arp(sc, "harp", I.nylon, M07_INTRO_CH[2:], 2, offb, 57, 0.36, -0.3)
	arp(sc, "harp", I.nylon, M07_A_CH + M07_A2_CH, A, offb, 57, 0.4, -0.3)
	arp(sc, "harp", I.nylon, M07_B_CH + M07_B2_CH, B, fern, 57, 0.4, -0.35)
	arp(sc, "harp", I.nylon, M07_A2_CH, A3, offb, 57, 0.42, -0.3)
	arp(sc, "harp", I.nylon, M07_CODA_CH, CO, [(0, "r", 0.6, 3), (0.5, "5", 0.5, 3), (1, "8", 0.5, 3),
		(1.5, "3+", 0.45, 2)], 57, 0.4, -0.3)
	# --- pad ------------------------------------------------------------------------------------
	pads(sc, "pad", I.bowed, M07_B_CH + M07_B2_CH + M07_BR_CH, B, 52, 67, 0.36, cutoff=1300)
	pads(sc, "pad", I.bowed, M07_A2_CH + M07_CODA_CH, A3, 54, 69, 0.3, cutoff=1400, release=2.6)
	# --- light footsteps: shaker, woodblock taps, clay pot --------------------------------------
	eighths = (0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5)
	acc = {0.5: 1.3, 1.5: 1.3, 2.5: 1.3, 3.5: 1.3}
	perc(sc, "perc", M.shaker, 440.0, range(2, A), eighths, 0.18, 0.35, accent=acc)
	perc(sc, "perc", M.shaker, 440.0, range(A, B), eighths, 0.22, 0.35, accent=acc)
	perc(sc, "perc", M.woodblock, 1100.0, range(A, B), (1.0, 3.0), 0.22, -0.3)
	perc(sc, "perc", I.clay_pot, 140.0, range(A, B, 2), (0.0,), 0.36, 0.0)
	perc(sc, "perc", M.shaker, 440.0, range(B, B2), (0.5, 1.5, 2.5, 3.5), 0.2, 0.35)
	perc(sc, "perc", M.shaker, 440.0, range(B2, BR), (0.5, 1.5, 2.5, 3.5), 0.24, 0.35)
	perc(sc, "perc", I.clay_pot, 140.0, range(B2, BR), (0.0, 2.5), 0.34, 0.0, accent={2.5: 0.7})
	perc(sc, "perc", M.shaker, 440.0, range(A3, CO + 2), eighths, 0.24, 0.35, accent=acc)
	perc(sc, "perc", M.woodblock, 1100.0, range(A3, CO), (1.0, 3.0), 0.24, -0.3)
	perc(sc, "perc", I.clay_pot, 140.0, range(A3, CO, 2), (0.0,), 0.38, 0.0)
	sc.automate("perc", [(CO, 0.0), (CO + 2, -9.0)])
	sc.master_auto = [(0, 1.5), (A - 0.5, 1.0), (A, -1.0), (A2, 0.0), (B, -0.5), (B2 + 4, 0.5), (BR, -2.0), (A3, 0.5),
		(CO, 0.0),
		(50, -1.5)]
	ir = S.hall(rng, 2.3, brightness=7500)
	levels = {"bell": (-1.0, 0.35), "flute": (-3.5, 0.3), "str": (6.0, 0.35), "bass": (-6.0, 0.08),
		"harp": (6.0, 0.28), "pad": (-15.0, 0.45), "perc": (-11.0, 0.18)}
	return sc, levels, ir, sec


# ==========================================================================================
# m08  The Long Way Home  (E major, 4/4, 74 bpm; long lines, open space, a homecoming hint)
# ==========================================================================================

M08_A = """
E5/1 B5/3 | C#6/1 B5/1 F#5/2 | E5/4 | r/2 C#5/1 E5/1 |
B5/3 G#5/1 | E5/2 D#5/2 | C#5/1.5 E5/.5 B4/2 | r/4
"""
M08_A2 = """
E5/1 B5/3 | D#6/1 C#6/1 B5/2 | E6/3 C#6/1 | A5/2 E5/2 |
G#5/1.5 F#5/.5 E5/2 | D#5/2 B4/2 | C#5/1 E5/1 F#5/1 A5/1 | G#5/4
"""
M08_A2_HARM = "r/4 | r/4 | r/4 | r/4 | E5/1.5 D#5/.5 C#5/2 | B4/2 G#4/2 | A4/1 C#5/1 D#5/1 F#5/1 | E5/4"
M08_BELLS = "r/2 G5/2 | r/1 E5/3 | r/2 G5/1 B5/1 | A5/4"
M08_B = """
C#5/3 B4/1 | A4/2 E4/2 | G#4/1 A4/1 B4/2 | F#4/4 |
E5/3 D#5/1 | C#5/2 A4/2 | A4/1 B4/1 C#5/1 E5/1 | E5/2 D#5/2
"""
M08_B_FL = "r/2 G#5/2 | E5/4 | r/2 F#5/1 G#5/1 | A5/2 F#5/2"
M08_A3_BOX = "r/2 B5/1 E6/1 | r/4 | r/2 C#6/1 E6/1 | r/4 | r/2 G#5/1 B5/1 | r/4 | r/4 | r/2 E6/1 G#6/1"
M08_CODA_BOX = "B4/1 E5/2 D#5/1 | C#5/2 B4/2 | r/4 | r/4 | r/4 | r/2 E6/2"
M08_CODA_FL = "r/4 | r/4 | E5/1 G5/1 B5/2 | A5/2 F#5/1 E5/1 | D#5/2 F#5/2 | G#5/4"

M08_INTRO_CH = ["Emaj7", "A/E"]
M08_A_CH = ["Emaj7", "E/G#", "Amaj7", "A6", "C#m7", "Bsus4 B", "Aadd9", "B7sus4"]
M08_A2_CH = ["Emaj7", "E/G#", "Amaj7", "F#m7", "C#m7", "G#m7", "Aadd9 B7", "E"]
M08_INT_CH = ["Cmaj7", "Amaj7", "Cmaj7", "B7sus4"]
M08_B_CH = ["C#m", "A", "E/B", "B", "C#m", "A", "F#m7", "B7sus4 B7"]
# coda bar 1 was Amaj7: under the quote's D#5 the harp's ringing E5 made a raw minor 2nd; C#m9 holds
# every note of B E D# (7 3 9) and keeps the gentle move to G#m7.
M08_CODA_CH = ["C#m9", "G#m7", "Cmaj7", "B7sus4", "Emaj9", "Emaj9"]

RIPPLE = {4: [(0, "b", 0.85), (1 / 3, "5", 0.5), (2 / 3, "8", 0.5), (1, "3+", 0.5), (4 / 3, "5+", 0.45),
	(5 / 3, "8+", 0.4), (3, "3+", 0.35, 2)],
	2: [(0, "b", 0.8), (1 / 3, "5", 0.5), (2 / 3, "8", 0.45), (1, "3+", 0.45)]}
_RDEG = ["b", "5", "8", "3+", "5+", "8", "3+", "5", "8", "3+", "5+", "8+"]
RIPPLE_FULL = {4: [(k / 3, _RDEG[k], 0.75 if k == 0 else 0.42) for k in range(12)],
	2: [(k / 3, _RDEG[k], 0.7 if k == 0 else 0.4) for k in range(6)]}


def cue_m08(rng):
	chords = M08_INTRO_CH + M08_A_CH + M08_A2_CH + M08_INT_CH + M08_B_CH + M08_A2_CH + M08_CODA_CH
	sec = {"intro": 0, "A": 2, "A2": 10, "interlude": 18, "B": 22, "A'": 30, "coda": 38, "end": 44}
	sc = Score(74, 4, 44, rng, tempo=[(0, 74), (40, 74), (42, 62), (44, 48)], tail=9.0)
	A, A2, IN, B, A3, CO = (sec[k] for k in ("A", "A2", "interlude", "B", "A'", "coda"))
	harp = I.lullaby_harp
	# --- melody --------------------------------------------------------------------------------
	line(sc, "flute", M.flute, M08_A, A, 0.62, -0.05, phrase=4, legato=0.97, arch=0.18)
	line(sc, "flute", M.flute, M08_A2, A2, 0.66, -0.05, phrase=4, legato=0.97, arch=0.18)
	line(sc, "oca", M.ocarina, M08_A2_HARM, A2, 0.5, 0.25, phrase=4, legato=0.97)
	line(sc, "bell", I.soft_bell, M08_BELLS, IN, 0.36, 0.4, phrase=4, ring=1.3)
	line(sc, "str", I.bowed, M08_B, B, 0.66, 0.05, phrase=4, legato=1.0, arch=0.2, attack=0.3, release=1.2,
		cutoff=2200)
	line(sc, "flute", M.flute, M08_B_FL, B + 4, 0.45, -0.25, phrase=4, legato=0.97)
	line(sc, "flute", M.flute, M08_A2, A3, 0.7, -0.05, phrase=4, legato=0.97, arch=0.18)
	line(sc, "str", I.bowed, M08_A2, A3, 0.42, 0.1, transpose=-12, phrase=4, legato=1.0, attack=0.35, release=1.3,
		cutoff=2000)
	line(sc, "box", M.music_box, M08_A3_BOX, A3, 0.4, 0.35)
	line(sc, "box", M.music_box, M08_CODA_BOX, CO, 0.56, 0.2, phrase=2, arch=0.1)
	line(sc, "flute", M.flute, M08_CODA_FL, CO, 0.58, -0.1, phrase=4, legato=0.98)
	# --- harp ---------------------------------------------------------------------------------
	arp(sc, "harp", harp, M08_INTRO_CH + M08_A_CH + M08_A2_CH, 0, RIPPLE, 52, 0.42, -0.25)
	blocks(sc, "harp", harp, M08_INT_CH, IN, [(0, 4, 0.8)], 52, 71, 0.34, -0.3, roll=0.2, max_voices=4)
	arp(sc, "harp", harp, M08_B_CH, B, RIPPLE_FULL, 52, 0.38, -0.25)
	arp(sc, "harp", harp, M08_A2_CH, A3, RIPPLE_FULL, 52, 0.4, -0.25)
	arp(sc, "harp", harp, M08_CODA_CH[:4], CO, RIPPLE, 52, 0.38, -0.25)
	for k, nm in enumerate(["E2", "B2", "G#3", "D#4", "F#4", "B4", "E5"]):
		sc.note("harp", harp, nm, CO + 4, 0.2 + 0.28 * k, 5.0, 0.42 - 0.02 * k, -0.35 + 0.1 * k, 0.0)
	# --- warm pad, bass, soft drums --------------------------------------------------------------
	pads(sc, "pad", I.bowed, chords, 0, 52, 68, 0.38, cutoff=1200, attack=1.0, release=2.2)
	bassline(sc, "bass", M.soft_bass, M08_A_CH + M08_A2_CH, A, {4: [(0, 3.8, "b")], 2: [(0, 1.9, "b")]}, 36, 0.55)
	bassline(sc, "bass", M.soft_bass, M08_INT_CH, IN, [(0, 3.9, "b")], 36, 0.34)
	bassline(sc, "bass", M.soft_bass, M08_B_CH + M08_A2_CH, B, {4: [(0, 1.9, "b"), (2, 1.9, "5")],
		2: [(0, 1.9, "b")]}, 36, 0.58)
	bassline(sc, "bass", M.soft_bass, M08_CODA_CH, CO, [(0, 3.9, "b")], 36, 0.5)
	perc(sc, "drum", M.tom, 55.0, range(B, CO, 2), (0.0,), 0.5, 0.0)
	perc(sc, "drum", M.tom, 82.0, range(B + 1, CO, 2), (2.5,), 0.22, 0.2)
	sc.note("swell", M.swell, 1000.0, IN + 3, 1.0, 3.0, 0.5, 0.0, 0.0)
	sc.note("swell", M.swell, 1000.0, B + 7, 1.0, 3.0, 0.6, 0.0, 0.0)
	# the interlude (one rolled chord per bar + distant bells) measured -25 LUFS between -15 / -19 LUFS
	# sections - a hole under game ambience; lifted ~3.5 dB, easing back across the swell into B
	sc.master_auto = [(0, 5.0), (A - 0.5, 3.5), (A, -1.0), (A2, 0.0), (IN, 0.5), (IN + 0.5, 4.0), (IN + 3, 3.5),
		(B, -0.5), (A3, 1.0), (CO, -0.5), (44, -2.0)]
	ir = S.hall(rng, 3.0, brightness=6500)
	levels = {"flute": (-3.5, 0.36), "oca": (-9.0, 0.4), "bell": (-2.0, 0.6), "str": (5.0, 0.4), "box": (-4.0, 0.45),
		"harp": (2.0, 0.35), "pad": (-12.0, 0.5), "bass": (-10.0, 0.1), "drum": (-9.0, 0.3), "swell": (-20.0, 0.5)}
	return sc, levels, ir, sec


# ==========================================================================================
# m09  Ripples at Mirror Pond  (Db major, 4/4, 56 bpm; sparse piano, droplets, long rests)
# ==========================================================================================

M09_A = """
Ab4/1 Eb5/1 F5/2 | r/4 | Ab4/1 Eb5/1 Ab5/1.5 Gb5/.5 | F5/3 r/1 |
Db5/1 F5/1 C6/2 | Bb5/1.5 Ab5/.5 F5/2 | Gb5/1 F5/1 Eb5/1 Db5/1 | Eb5/3 r/1
"""
M09_A_DROPS = "r/4 | r/1 C6/.5 Bb5/.5 F5/1 Db6/1 | r/4 | r/3 Ab5/.5 F5/.5 | r/4 | r/4 | r/4 | r/3 Bb5/.5 Db6/.5"
M09_B = "F5/1 Ab5/1 Bb5/1 r/1 | Db6/1.5 Bb5/.5 F5/2 | Ab5/1 F5/1 Eb5/1 Db5/1 | Eb5/3 r/1 | Gb5/1 Bb5/1 Db6/1 Eb6/1 | Db6/2 C6/2"
M09_A3 = "Ab5/1 Eb6/1 F6/2 | r/4 | Db5/1 F5/1 C6/2 | Bb5/1.5 Ab5/.5 F5/2 | Gb5/1 F5/1 Eb5/1 Db5/1 | Db5/2 r/2"
M09_A3_DROPS = "r/4 | r/1 C6/.5 Bb5/.5 F5/1 Db6/1 | r/4 | r/4 | r/4 | r/2 Ab5/.5 F5/.5 Eb5/1"
M09_CODA = "r/4 | Ab4/1 Eb5/1 F5/2 | r/4"
M09_CODA_DROPS = "r/1 C6/.5 Bb5/.5 F5/2 | r/4 | r/2 F6/1 Db6/1"

# Reviewer reharmonisation: A and A' used to be Imaj9 IVmaj7/I Imaj9 IVmaj7 vi9 IVmaj7 ii9 V7sus4 - chord
# for chord music_night's progression (Dmaj9 Gmaj7 ... Em9 A7sus4) a semitone lower, at nearly the same
# tempo. The melody is unchanged; A now walks down from the tonic (I vi IV iii | vi I6 ii V; bass Db Bb Gb F
# | Bb F Eb Ab), A' gets a Lydian IVmaj7#11 and a sighing Fm7 suspension, the coda is IV#11 - I.
M09_INTRO_CH = ["Db69", "Ebm7/Db"]
M09_A_CH = ["Db69", "Bbm9", "Gb69", "Fm7", "Bbm9", "Db6/F", "Ebm9", "Ab7sus4"]
M09_B_CH = ["Bbm", "Gbmaj7", "Db/F", "Gb6", "Ebm7", "Absus4 Ab"]
M09_A3_CH = ["Db69", "Bbm9", "Gbmaj7#11", "Fm7", "Ebm9 Ab7sus4", "Db69"]
M09_CODA_CH = ["Gbmaj7#11", "Db69", "Dbmaj9"]
DB_PENT = ["Db6", "Eb6", "F6", "Ab6", "Bb6", "Db7"]
POND_LH = {4: [(0, "b", 0.6), (0, "5", 0.45), (2, "3", 0.34), (2, "7", 0.32)],
	2: [(0, "b", 0.7), (0, "5", 0.42), (1, "3", 0.3)]}


def cue_m09(rng):
	chords = M09_INTRO_CH + M09_A_CH + M09_B_CH + M09_A3_CH + M09_CODA_CH
	sec = {"intro": 0, "A": 2, "B": 10, "A'": 16, "coda": 22, "end": 25}
	sc = Score(56, 4, 25, rng, tempo=[(0, 56), (22, 56), (24, 50), (25, 42)], tail=10.0)
	A, B, A3, CO = sec["A"], sec["B"], sec["A'"], sec["coda"]
	piano = I.felt_piano
	# --- piano: a few notes at a time, the pedal keeps the water still ---------------------------
	line(sc, "pianoR", piano, M09_A, A, 0.52, 0.08, phrase=2, legato=1.3, pedal=1.2, arch=0.2)
	arp(sc, "pianoL", piano, M09_INTRO_CH[1:] + M09_A_CH, 1, POND_LH, 49, 0.36, -0.12, hold=True, pedal=0.6)
	blocks(sc, "pianoL", piano, M09_B_CH, B, {4: [(0, 2.2, 0.8), (2, 2.2, 0.55)], 2: [(0, 2.2, 0.7)]}, 53, 70, 0.3,
		-0.1, roll=0.15, pedal=0.8)
	line(sc, "pianoR", piano, M09_A3, A3, 0.5, 0.08, phrase=2, legato=1.3, pedal=1.2, arch=0.2)
	arp(sc, "pianoL", piano, M09_A3_CH, A3, POND_LH, 49, 0.34, -0.12, hold=True, pedal=0.6)
	line(sc, "pianoR", piano, M09_CODA, CO, 0.46, 0.08, phrase=3, legato=1.4, pedal=2.0)
	for k, nm in enumerate(["Db2", "Ab2", "F3", "C4", "Eb4", "Ab4", "C5"]):
		sc.note("pianoL", piano, nm, CO + 2, 0.0 + 0.2 * k, 4.0, 0.36 - 0.015 * k, -0.15 + 0.05 * k, 0.0, pedal=3.0)
	# --- water: droplet answers in the rests, the kalimba's own tune in B ---------------------------
	line(sc, "drop", I.droplet, M09_A_DROPS, A, 0.5, 0.35, phrase=2)
	line(sc, "kal", I.kalimba, M09_B, B, 0.62, -0.2, phrase=2, arch=0.15)
	line(sc, "drop", I.droplet, M09_B, B, 0.24, 0.4, transpose=12, phrase=2)
	line(sc, "drop", I.droplet, M09_A3_DROPS, A3, 0.48, 0.35, phrase=2)
	line(sc, "drop", I.droplet, M09_CODA_DROPS, CO, 0.44, 0.3, phrase=3)
	glints(sc, "ripple", I.droplet, DB_PENT, 0, 2, 3, vel=(0.18, 0.3), chords=chords)
	glints(sc, "ripple", I.droplet, DB_PENT, A, B, 6, vel=(0.12, 0.24), chords=chords)
	glints(sc, "ripple", I.droplet, DB_PENT, B, A3, 3, vel=(0.1, 0.2), chords=chords)
	glints(sc, "ripple", I.droplet, DB_PENT, A3, CO + 2, 6, vel=(0.12, 0.24), chords=chords)
	# --- still air: a very soft pad, bowed warmth in B -----------------------------------------------
	pads(sc, "pad", M.pad, chords, 0, 53, 68, 0.36, attack=2.2, release=3.0, cutoff=900, overlap=0.4, max_voices=3)
	pads(sc, "pad2", I.bowed, M09_B_CH, B, 50, 65, 0.36, cutoff=1000, attack=1.4, release=2.5)
	bassline(sc, "bass", M.soft_bass, M09_B_CH, B, {4: [(0, 3.8, "b")], 2: [(0, 1.9, "b")]}, 37, 0.4)
	sc.master_auto = [(0, -1.5), (A, 0.0), (B, 0.5), (A3, 0.0), (CO, -0.5), (25, -1.5)]
	ir = S.hall(rng, 4.2, brightness=5500)
	levels = {"pianoR": (4.5, 0.4), "pianoL": (-3.0, 0.42), "drop": (-3.0, 0.5), "kal": (-3.0, 0.45),
		"ripple": (-9.0, 0.7), "pad": (-13.0, 0.55), "pad2": (-15.0, 0.5), "bass": (-12.0, 0.12)}
	return sc, levels, ir, sec


# ==========================================================================================
# Cue table, mastering, rendering
# ==========================================================================================

CUES = {
	"m03": dict(fn=cue_m03, file="m03_wood_wool_windows.ogg", title="Wood, Wool & Windows", bpm="96 (rit. to 66)",
		key="C major", meter="4/4", ref="music_haven", target=-17.0, dur=(110, 170),
		playlist="haven_day (rotates with M02 music_haven and M04)",
		instruments="pizzicato strings (lead), marimba (3+3+2 pulse, lead + rolls in B), nylon harp strums, "
			"celesta (windows interlude, descant), plucked upright bass, warm bowed pad, shaker, woodblock, clay pot",
		motif="New tune. Hook: a little turn E-D-E, then a leap up to the 6th (A5) that leans onto the 5th, "
			"answered a step higher (F-E-F, leap to C6); 6-bar phrases (3+3), unlike the 8-bar haven theme. B is a lyrical A-minor marimba song with rolls; C is a celesta 'windows' "
			"episode; coda reuses the hook over F / Fm6 and ends on a rolled Cadd9."),
	"m04": dict(fn=cue_m04, file="m04_berry_tea_afternoon.ogg", title="Berry Tea Afternoon",
		bpm="150 eighths (dotted quarter 50, rit.)", key="Bb major", meter="6/8", ref="music_haven", target=-17.0,
		dur=(100, 160), playlist="haven_day (crafting / gardening; rotates with M02 and M03)",
		instruments="felt piano (melody + barcarolle left hand), celesta doubling, airy woodwind-like synth lead "
			"(B, tenor counter-line in A'), soft bass, bowed pad, brush, shaker, clay pot, spoon-on-cup tinks",
		motif="New lilting 6/8 tune rising F-Bb-D-F (arpeggio) then easing down by step; B is a sustained air-synth "
			"melody through Eb-F-Dm-Gm, B' a duet with a borrowed Ebm6; coda is the opening figure over Ebmaj7 / F/Eb."),
	"m06": dict(fn=cue_m06, file="m06_firefly_wishes.ogg", title="Firefly Wishes", bpm="63 (rit. to 42)",
		key="Eb major", meter="3/4", ref="music_night", target=-18.0, dur=(100, 170),
		playlist="haven_night (rotates with M05 music_night)",
		instruments="warm harp (melody + slow arpeggios, glissando), low clarinet, bowed string lead, music box, "
			"bowed + chorused pads, soft sine bass, celesta 'fireflies'",
		motif="New lullaby: 1 - low 5 - high 3 (Eb5 Bb4 G5: a falling fourth, then a rising-sixth 'wish') that "
			"rocks down fa. re la | do-- sol (reviewer rewrite: the draft's 're. do la | sol-- mi' in 3/4 echoed "
			"the 'over the ocean' cadence of My Bonnie); A on harp, A2 on low "
			"clarinet, B a descending string sequence that climbs back to C6, A' on music box + harp, coda turns "
			"to Abm6 and ends on a slow rolled Eb(add9)."),
	"m07": dict(fn=cue_m07, file="m07_footpaths_and_ferns.ogg", title="Footpaths & Ferns", bpm="104 (rit. to 70)",
		key="A major (Lydian colour at the end)", meter="4/4", ref="music_haven", target=-17.0, dur=(100, 160),
		playlist="woods_ch1 (rotates with M08; M09 on pond entry)",
		instruments="soft bells (glockenspiel/handbell hybrid), flute, bowed string lead (B), walking plucked bass, "
			"harp off-beats and fern arpeggios, bowed pad, shaker, woodblock, clay pot",
		motif="New tune made of distinct ascending phrases - four-note climbs (A-B-C#-E, B-C#-E-G#, F#-A-C#-E, "
			"B-C#-D-F#) that each stop and rest; B is a lyrical D-major string song; a two-bar 'breather' of bells "
			"alone; coda climbs through B/A (Lydian) to a high A."),
	"m08": dict(fn=cue_m08, file="m08_the_long_way_home.ogg", title="The Long Way Home", bpm="74 (rit. to 48)",
		key="E major", meter="4/4", ref="music_haven", target=-17.0, dur=(110, 170),
		playlist="woods_ch1 (rotates with M07; returning towards the haven)",
		instruments="flute (lead), ocarina harmony, bowed strings (B lead, A' octave doubling), warm harp triplet "
			"ripples, distant soft bells, music box, bowed pad, soft bass, felt drum, air swells",
		motif="New spacious melody of long notes and wide leaps (E5 up a fifth to B5, a neighbour C#6, a fourth "
			"down to F#5; up to E6 in A2), whole-bar "
			"rests; interlude on bVI Cmaj7 with distant bells; B a low string song in C# minor. Shares motif: the "
			"coda quotes the game's own 'For Krystal' motif (5-1-7-6-5 = B4 E5 D#5 C#5 B4) on music box over "
			"C#m9 - G#m7."),
	"m09": dict(fn=cue_m09, file="m09_ripples_at_mirror_pond.ogg", title="Ripples at Mirror Pond",
		bpm="56 (rit. to 42)", key="Db major (Lydian colour)", meter="4/4", ref="music_night", target=-18.0,
		dur=(90, 140), playlist="pond / quiet glade entry (optional, not wallpaper)",
		instruments="felt piano with pedal (sparse melody, open-fifth left hand), water-like droplet plucks, "
			"kalimba (B tune), chorused pad, bowed pad, soft bass",
		motif="New sparse tune: a 5-9-3 rise (Ab4-Eb5-F5) followed by a whole bar of rest answered by droplets. "
			"A's harmony walks down from the tonic (Db6/9 Bbm9 Gb6/9 Fm7 | Bbm9 Db6/F Ebm9 Ab7sus4; re-harmonised "
			"in review - the draft was music_night's chord progression a semitone lower); B gives the kalimba its "
			"own pentatonic phrase; A' begins an octave higher over a Lydian Gbmaj7#11; coda Gbmaj7#11 - Db6/9, "
			"a rolled final Dbmaj9."),
}


# Independent review pass (note data, analysis, spectrograms - still nobody has listened).
REVIEW = {
	"m03": "B bars 8-9 rewritten: 'E5 G5 C6. B5 | A5-- F5 D5' was the opening of music_haven's B section at the "
		"same pitch and rhythm (haven has F#5); m03 rotates with music_haven. Now 'E5. B5. C6 | D6. C6. A5' on "
		"the cue's own 3+3+2 pulse.",
	"m06": "A bars 1-2 (and coda bar 1) rewritten: the draft's F5. Eb5 C5 | Bb4-- G4 in 3/4 matched the "
		"'over the ocean' cadence of My Bonnie in pitch and rhythm; now Ab5. F5 C5 | Eb5-- Bb4. Firefly glints "
		"are chosen from notes that do not rub a semitone against the chord of the moment (5 of 25 did).",
	"m08": "Interlude lifted ~3.5 dB (it measured -25 LUFS between -15 and -19 LUFS sections) with its "
		"sustained bass 2 dB lower; coda bar 1 Amaj7 -> C#m9 so the Krystal quote's D#5 no longer grinds "
		"against the harp's ringing E5.",
	"m09": "A / A' / intro / coda re-harmonised: the draft's A progression was music_night's (Dmaj9 Gmaj7 Dmaj9 "
		"Gmaj7 Bm9 Gmaj7 Em9 A7sus4) a semitone lower at 56 vs 60 bpm. Melody unchanged. Ripple glints are "
		"chord-aware.",
}


def master(x: np.ndarray, target: float, tp_ceiling: float = -1.4) -> np.ndarray:
	"""Loudness to target (BS.1770 integrated), then only as much peak limiting as needed to keep the
	true peak under the ceiling (a transparent look-ahead limiter; dynamics otherwise untouched)."""
	x = x * db(target - L.integrated_lufs(x))
	master.last_excess_db = max(0.0, L.true_peak_db(x) - tp_ceiling)   # ~ the deepest gain reduction
	for _ in range(4):
		tp = L.true_peak_db(x)
		if tp <= tp_ceiling:
			break
		x = limiter(x, tp_ceiling - 0.35 - (tp - tp_ceiling) * 0.1, 0.015)
		x = x * db(target - L.integrated_lufs(x))
	if L.true_peak_db(x) > tp_ceiling:
		x = limiter(x, tp_ceiling - 0.5, 0.015)
	return x


def write_ogg(path: str, x: np.ndarray, block: int = 8192) -> None:
	"""OGG Vorbis via soundfile. Written in blocks: libsndfile's Vorbis encoder overflows the (small,
	Windows) thread stack when handed a whole track in one call."""
	import soundfile as sf
	x = np.ascontiguousarray(x, dtype=np.float32)
	with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS") as fh:
		for i in range(0, len(x), block):
			fh.write(x[i:i + block])


def render_cue(cue_id: str, out_dir: str = OUT_DIR) -> dict:
	import soundfile as sf
	info = CUES[cue_id]
	t0 = time.time()
	rng = rng_for("hollowhaven_music2:" + cue_id)
	sc, levels, ir, sec = info["fn"](rng)
	x = sc.mix(levels, ir)
	x = master(x, info["target"])
	os.makedirs(out_dir, exist_ok=True)
	path = os.path.join(out_dir, info["file"])
	for _ in range(3):
		write_ogg(path, x)
		y, sr = sf.read(path, dtype="float64", always_2d=True)
		tp = L.true_peak_db(y)
		if tp <= -1.05:
			break
		x = x * db(-1.15 - tp)
	secs = {k: round(sc.time(v), 2) for k, v in sec.items()}
	return {"id": cue_id, "path": path, "render_s": round(time.time() - t0, 1), "notes": sc.count,
		"sections": secs, "bus_rms": sc.bus_report, "mix_len": round(len(x) / SR, 2),
		"limit_db": round(master.last_excess_db, 2)}


def render_all(out_dir: str = OUT_DIR, only=None, jobs: int = 6) -> list:
	"""Renders every cue of this group (in parallel processes) and returns per-cue render info."""
	ids = [c for c in CUES if only is None or c in only]
	if jobs <= 1 or len(ids) == 1:
		return [render_cue(c, out_dir) for c in ids]
	from concurrent.futures import ProcessPoolExecutor
	with ProcessPoolExecutor(max_workers=min(jobs, len(ids))) as ex:
		futs = [ex.submit(render_cue, c, out_dir) for c in ids]
		return [f.result() for f in futs]


# ==========================================================================================
# Verification: analysis, spectrograms, manifest
# ==========================================================================================

def _section_text(secs: dict, end_s: float) -> str:
	items = [(k, v) for k, v in secs.items() if k != "end"]
	parts = []
	for i, (k, v) in enumerate(items):
		nxt = items[i + 1][1] if i + 1 < len(items) else end_s
		parts.append("%s(%d-%ds)" % (k, round(v), round(nxt)))
	return " ".join(parts)


def spectrogram(path: str, png: str, secs: dict, title: str) -> None:
	import soundfile as sf
	from PIL import Image, ImageDraw
	from scipy import signal
	x, sr = sf.read(path, dtype="float64", always_2d=True)
	mono = x.mean(axis=1)
	width, height, strip = 1600, 440, 90
	hop = max(256, len(mono) // width)
	f, t, Z = signal.stft(mono, sr, nperseg=4096, noverlap=4096 - hop, boundary=None)
	mag = 20 * np.log10(np.abs(Z) + 1e-9)
	fl = np.geomspace(35, 16000, height)
	rows = np.array([np.interp(fl, f, mag[:, k]) for k in range(mag.shape[1])]).T
	cols = np.linspace(0, rows.shape[1] - 1, width).astype(int)
	img = rows[:, cols][::-1]
	v = np.clip((img - (np.max(img) - 85)) / 85.0, 0, 1)
	cmap = np.array([[0, 0, 4], [40, 11, 84], [101, 21, 110], [159, 42, 99], [212, 72, 66], [245, 125, 21],
		[250, 193, 39], [252, 255, 164]], dtype=float)
	vi = v * (len(cmap) - 1)
	i0 = np.clip(np.floor(vi).astype(int), 0, len(cmap) - 2)
	fr = (vi - i0)[..., None]
	rgb = (cmap[i0] * (1 - fr) + cmap[i0 + 1] * fr).astype(np.uint8)
	canvas = Image.new("RGB", (width, height + strip + 20), (18, 16, 24))
	canvas.paste(Image.fromarray(rgb), (0, strip + 20))
	d = ImageDraw.Draw(canvas)
	dur = len(mono) / sr
	st = L.short_term_curve(x, sr, 3.0, dur / width)
	for i in range(min(width, len(st))):
		h = np.clip((st[i] + 45.0) / 40.0, 0, 1) * (strip - 6)
		d.line([(i, strip - h), (i, strip)], fill=(230, 200, 120))
	for fq in (100, 1000, 10000):
		y = strip + 20 + int((1 - np.log(fq / 35) / np.log(16000 / 35)) * (height - 1))
		d.line([(0, y), (10, y)], fill=(255, 255, 255))
		d.text((12, y - 6), "%dk" % (fq // 1000) if fq >= 1000 else str(fq), fill=(255, 255, 255))
	for k, s in secs.items():
		xpix = int(s / dur * (width - 1))
		d.line([(xpix, 0), (xpix, height + strip + 20)], fill=(120, 220, 255))
		d.text((xpix + 3, strip + 4), k, fill=(120, 220, 255))
	d.text((4, 2), "%s  %.1fs   (top: short-term loudness -45..-5 LUFS; cyan: sections)" % (title, dur),
		fill=(255, 255, 255))
	os.makedirs(os.path.dirname(png), exist_ok=True)
	canvas.save(png)


def hf_share_db(y: np.ndarray, sr: int, fc: float = 8000.0) -> dict:
	"""Energy above fc relative to the whole signal (dB): over the track and in its worst 250 ms window
	(windows quieter than -40 dB under the loudest are ignored)."""
	from scipy import signal
	mono = np.mean(y, axis=1)
	hf = signal.sosfilt(signal.butter(8, fc, "hp", fs=sr, output="sos"), mono)
	w = int(0.25 * sr)
	k = len(mono) // w
	ea = np.mean(mono[:k * w].reshape(k, w) ** 2, axis=1)
	eh = np.mean(hf[:k * w].reshape(k, w) ** 2, axis=1)
	loud = ea > np.max(ea) * 1e-4
	worst = float(np.max(10 * np.log10(eh[loud] / ea[loud] + 1e-20))) if np.any(loud) else -120.0
	return {"total_db": round(float(10 * np.log10(np.sum(hf ** 2) / (np.sum(mono ** 2) + 1e-30) + 1e-20)), 1),
		"worst_250ms_db": round(worst, 1)}


def analyse(results: list) -> list:
	import soundfile as sf
	rows = []
	report = []
	for r in results:
		info = CUES[r["id"]]
		y, sr = sf.read(r["path"], dtype="float64", always_2d=True)
		dur = len(y) / sr
		lufs = L.integrated_lufs(y, sr)
		tp = L.true_peak_db(y)
		sp = L.sample_peak_db(y)
		lra = L.loudness_range(y, sr)
		st = L.short_term_curve(y, sr, 3.0, 1.0)
		end_music = r["sections"]["end"]
		gaps = [g for g in L.silence_gaps(y, sr, -50.0, 3.0) if g[1] < end_music - 0.5]
		bands = L.band_balance(y, sr)
		issues = []
		lo, hi = info["dur"]
		if not (lo <= dur <= hi):
			issues.append("duration %.1f outside %d-%d" % (dur, lo, hi))
		if tp > -1.0:
			issues.append("true peak %.2f > -1.0" % tp)
		if abs(lufs - info["target"]) > 1.0:
			issues.append("loudness %.2f off target %.1f" % (lufs, info["target"]))
		if gaps:
			issues.append("silence gaps %s" % gaps)
		if sr != 44100 or y.shape[1] != 2:
			issues.append("format %d Hz %d ch" % (sr, y.shape[1]))
		start_lv = 20 * np.log10(np.max(np.abs(y[:ns(0.002)])) + 1e-12)
		end_lv = 20 * np.log10(np.max(np.abs(y[-ns(0.01):])) + 1e-12)
		if end_lv > -60:
			issues.append("end not faded (%.0f dB)" % end_lv)
		dc = round(float(np.max(np.abs(np.mean(y, axis=0)))), 7)
		if dc > 1e-3:
			issues.append("DC offset %.1e" % dc)
		hf = hf_share_db(y, sr, 8000.0)
		if hf["total_db"] > -30.0 or hf["worst_250ms_db"] > -12.0:
			issues.append("harsh >8 kHz energy %s" % hf)
		png = os.path.join(QA_DIR, r["id"] + ".png")
		spectrogram(r["path"], png, r["sections"], info["title"])
		report.append("%s %-26s %6.1fs  I %6.2f LUFS (target %.1f, ref %s)  TP %5.2f dBTP  SP %5.2f  LRA %4.1f  "
			"st %.1f..%.1f  start %.0f dB end %.0f dB  notes %d  render %.1fs  limiter<=%.1fdB  %s" % (
			r["id"], info["file"], dur, lufs, info["target"], info["ref"], tp, sp, lra, float(np.min(st[st > -70])),
			float(np.max(st)), start_lv, end_lv, r["notes"], r["render_s"], r["limit_db"], "OK" if not issues else "!! " + "; ".join(issues)))
		report.append("     bands %s  DC %.1e  >8k %s" % ({k: float(v) for k, v in bands.items()}, dc, hf))
		report.append("     buses %s" % {k: float(v) for k, v in r["bus_rms"].items()})
		report.append("     sections %s" % r["sections"])
		rows.append({"id": r["id"], "title": info["title"], "file": info["file"],
			"res_path": "res://assets/audio/music/" + info["file"],
			"duration_s": round(dur, 2), "loop": False, "bpm": info["bpm"], "key": info["key"], "meter": info["meter"],
			"sections": _section_text(r["sections"], r["sections"]["end"]) + " + reverb tail to %ds" % round(dur),
			"instruments": info["instruments"], "motif_notes": info["motif"], "peak_dbfs": round(tp, 2),
			"sample_peak_dbfs": round(sp, 2), "loudness_lufs": round(lufs, 2), "loudness_range_lu": round(lra, 1),
			"loudness_reference": "%s (%s)" % (info["ref"], "measured with hw_loudness.integrated_lufs"),
			"location_playlist": info["playlist"], "format": "OGG Vorbis 44.1 kHz stereo",
			"generator": "tools/audio/music2/group_home_woods.py (seed 'hollowhaven_music2:%s')" % r["id"],
			"review_changes": REVIEW.get(r["id"], "none (reviewed, unchanged)"),
			"spectrogram": "qa/tmp/music2/%s.png" % r["id"], "issues": issues,
			"dc_offset": dc, "hf_above_8k_db": hf,
			"verified": "NOT VERIFIED by listening - analysis, spectrogram and note-data review only"})
	return rows, report


def reference_levels() -> list:
	import soundfile as sf
	out = []
	for name in ("music_haven", "music_night", "music_title", "music_boss", "music_ending"):
		p = os.path.join(OUT_DIR, name + ".wav")
		if os.path.exists(p):
			y, sr = sf.read(p, dtype="float64", always_2d=True)
			out.append("ref %-13s I %6.2f LUFS  TP %5.2f  LRA %.1f" % (name, L.integrated_lufs(y, sr), L.true_peak_db(y),
				L.loudness_range(y, sr)))
	return out


def main(argv=None) -> int:
	import argparse
	ap = argparse.ArgumentParser()
	ap.add_argument("--only", default="", help="comma separated cue ids (m03,m04,...)")
	ap.add_argument("--no-verify", action="store_true")
	ap.add_argument("--jobs", type=int, default=6)
	a = ap.parse_args(argv)
	only = [s.strip() for s in a.only.split(",") if s.strip()] or None
	t0 = time.time()
	res = render_all(OUT_DIR, only, a.jobs)
	print("rendered %d cues in %.1fs" % (len(res), time.time() - t0))
	if a.no_verify:
		return 0
	rows, report = analyse(res)
	print("\n".join(reference_levels()))
	print("\n".join(report))
	# merge with existing manifest rows (so --only keeps the other cues' rows)
	old = []
	if os.path.exists(MANIFEST):
		try:
			with open(MANIFEST, encoding="utf-8") as fh:
				old = json.load(fh)
		except (OSError, ValueError):
			old = []
	keep = {r["id"]: r for r in old}
	for r in rows:
		keep[r["id"]] = r
	order = list(CUES)
	merged = [keep[k] for k in order if k in keep]
	with open(MANIFEST, "w", encoding="utf-8") as fh:
		json.dump(merged, fh, indent=1, ensure_ascii=False)
		fh.write("\n")
	print("manifest: %s (%d rows); total %.1fs" % (MANIFEST, len(merged), time.time() - t0))
	return 1 if any(r["issues"] for r in rows) else 0


if __name__ == "__main__":
	sys.exit(main())
