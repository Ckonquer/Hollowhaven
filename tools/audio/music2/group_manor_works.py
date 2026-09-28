"""Hollowhaven Part 2 - Moonveil Manor & Hushed Works music (cues m20-m24, m26).

Original compositions, synthesised from code with the hhsynth toolkit (tools/audio/hhsynth, used
read-only) plus the extra voices in manor_voices.py. Every melody and progression below is written
by hand for this game; nothing quotes an existing song.

    "C:/Users/Ali/Desktop/Hollowhaven/.tools/pyenv/Scripts/python.exe" tools/audio/music2/group_manor_works.py [--jobs 6] [--only m20,m23] [--no-verify]

Output (OGG Vorbis, 44.1 kHz stereo) -> game/assets/audio/music/:
  m20_the_empty_waltz.ogg          Moonveil Manor exploration  A minor 3/4 waltz, ends
  m21_a_midnight_invitation.ogg    Count Velour                E minor 3/4 waltz, LOOP, middle 'midnight' section
  m22_harvest_trouble.ogg          Chapter Two combat          C minor 4/4 galop (160), LOOP
  m23_under_the_bellhouse.ogg      Hushed Works                F minor/Phrygian bell ambience, LOOP, quiet
  m24_a_pocket_of_day.ogg          underground refuge garden   E-flat major piano/harp song, ends
  m26_borrowed_welcome_l1/l2/l3.ogg  final boss               B minor 4/4, three sample-synchronised LOOP layers
QA: spectrograms -> qa/tmp/music2/<cue>.png (m26: m26.png = all layers, m26_l1..l3.png);
manifest -> tools/audio/music2/manifest_manor_works.json. From other code: render_all(out_dir[, jobs]).
Measured (this machine, 6 processes, incl. verification): ~1.5-2 min for the whole set.

Shared motifs
  * 'Empty waltz' head (m20): the melody always enters AFTER the downbeat (rest, 5, 8 - a missing
    dance partner). Its pitches E5 A5 G#5 F5 E5 are the house 'For Krystal' shape in minor (5-1-7-b6-5,
    the same scale degrees as music_boss's A D C# Bb A) - a deliberate family link, recast as a waltz
    pickup (review note: the first manifest said it quoted nothing). m21 does not reuse it; the manor
    pieces are related by timbre (harpsichord, muted strings, celesta) and by the minor-sixth
    'invitation' leap that m21 is built on.
  * m26 borrows the house 'For Krystal' motif shape (rising fourth, then three steps down, from
    music_tracks.py) in B minor, and sets it against the motif at its ORIGINAL title pitches
    (C F E D C) a tritone away - 'familiar interval hints become unsettling counterpoint'.
Deterministic: every cue is seeded from its id (hhsynth.core.rng_for).
"""
from __future__ import annotations

import json
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
from scipy import ndimage  # noqa: E402

from hhsynth.core import SR, ns, db, rng_for, fold_loop, circular, place  # noqa: E402
from hhsynth import music as M, space as S, filters as F  # noqa: E402
from hhsynth.music import hz, midi  # noqa: E402
import manor_voices as V  # noqa: E402
import manor_meter as MM  # noqa: E402

ROOT = os.path.abspath(os.path.join(AUDIO_TOOLS, "..", ".."))
MUSIC_OUT = os.path.join(ROOT, "game", "assets", "audio", "music")
QA_OUT = os.path.join(ROOT, "qa", "tmp", "music2")
MANIFEST = os.path.join(HERE, "manifest_manor_works.json")

# Loudness references measured from the existing (liked) tracks with manor_meter.integrated_lufs:
# title -17.3, haven -17.0, night -17.6, boss -17.8, ending -16.4 LUFS. Targets stay within +-2 LU.
REF_LUFS = {"haven": -17.03, "night": -17.57, "boss": -17.76}


def _horn(f, dur, vel, rng):
	"""The existing boss-piece horn voice (music_tracks.horn), imported lazily."""
	import music_tracks as MT
	return MT.horn(f, dur, vel, rng)


# ==========================================================================================
# Harmony helpers (own chord table: adds half-diminished, diminished-seventh etc.)
# ==========================================================================================

SHAPES = dict(M.CHORD_SHAPES)
SHAPES.update({"m7b5": [0, 3, 6, 10], "dim7": [0, 3, 6, 9], "aug": [0, 4, 8], "madd9": [0, 3, 7, 14],
	"7b9": [0, 4, 7, 10, 13], "m(maj7)": [0, 3, 7, 11]})
_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pc(name: str) -> int:
	return (_PC[name[0]] + name[1:].count("#") - name[1:].count("b")) % 12


def chord(sym: str) -> dict:
	"""'F#m7b5' -> root/ivs/bass pitch classes; 'Am/G' -> bass G."""
	bass = None
	if "/" in sym:
		sym, b = sym.split("/")
		bass = pc(b)
	m = re.fullmatch(r"([A-G][#b]?)(.*)", sym)
	root = pc(m.group(1))
	return {"root": root, "ivs": SHAPES[m.group(2)], "bass": root if bass is None else bass}


def low(pcl: int, lo: int) -> int:
	"""Lowest midi note of pitch class pcl that is >= lo."""
	return lo + ((pcl - lo) % 12)


def chord_seq(prog, start_bar: int, bpb: int):
	"""prog entries: 'Am' (whole bar) or [('Am', 2), ('E7', 1)] -> (bar, beat, beats, sym)."""
	for i, entry in enumerate(prog):
		if isinstance(entry, str):
			yield start_bar + i, 0.0, float(bpb), entry
		else:
			b = 0.0
			for sym, n in entry:
				yield start_bar + i, b, float(n), sym
				b += n
	return


def tones_of(sym: str, lo: int) -> dict:
	c = chord(sym)
	r = low(c["root"], lo)
	iv = c["ivs"]
	t = {"root": r, "third": r + iv[1], "fifth": r + iv[2] if len(iv) > 2 else r + 7,
		"seventh": r + (iv[3] if len(iv) > 3 else 12), "top": r + 12, "bass": low(c["bass"], lo - 12)}
	t["fifth_lo"] = t["fifth"] - 12
	t["third_hi"] = t["third"] + 12
	t["fifth_hi"] = t["fifth"] + 12
	t["bass8"] = t["bass"] + 12
	return t


def voicing(sym: str, lo: int, hi: int, prev):
	"""Voice-led chord inside [lo, hi]. hhsynth's voice_lead falls back to the raw (sub-audio)
	pitch classes when the range is too narrow for the chord, so the range is widened instead."""
	c = chord(sym)
	tones = [c["root"] + i for i in c["ivs"]]
	for extra in range(0, 13):
		v = M.voice_lead(prev, tones, lo, hi + extra)
		if min(v) >= lo:
			return v
	raise ValueError("cannot voice %s in %d..%d" % (sym, lo, hi))


# ==========================================================================================
# Score: bar/beat sequencer with a tempo map, loop-wrapping buses and layer-aware rendering
# ==========================================================================================

class Score:
	"""Places notes on stereo buses in bar/beat time.
	loop=True : buses are exactly one loop long; anything ringing past the end wraps onto the
	            start (sample-accurate periodic loop, like hhsynth Song.mix's fold).
	loop=False: buses are the piece plus a free tail; the piece ends naturally.
	tempo = [(bar0, bar1, bpm0, bpm1)] ramps (e.g. a closing ritardando)."""

	def __init__(self, bpm: float, bpb: int, bars: int, rng: np.random.Generator, loop: bool, tempo=(),
			tail: float = 12.0):
		self.bpb = bpb
		self.bars = bars
		self.rng = rng
		self.loop = loop
		nb = bars * bpb
		spb = np.full(nb, 60.0 / bpm)
		for b0, b1, t0, t1 in tempo:
			k0, k1 = int(round(b0 * bpb)), int(round(b1 * bpb))
			for k in range(k0, min(k1, nb)):
				u = (k - k0 + 0.5) / max(k1 - k0, 1)
				spb[k] = 60.0 / (t0 + (t1 - t0) * u)
		self.spb = spb
		self.beat_t = np.concatenate([[0.0], np.cumsum(spb)])
		self.length = float(self.beat_t[-1])
		self.n = ns(self.length)
		self.buflen = self.n if loop else self.n + ns(tail)
		self.buses: dict = {}
		self.log: list = []          # (bus, hz, start_s, dur_s, vel) - for QA / note census

	def time(self, bar: float, beat: float = 0.0) -> float:
		g = bar * self.bpb + beat
		nb = len(self.spb)
		if g >= nb:
			return self.length + (g - nb) * self.spb[-1]
		if g < 0:
			return g * self.spb[0]
		k = int(np.floor(g))
		return float(self.beat_t[k] + (g - k) * self.spb[k])

	def bar_time(self, bar: float) -> float:
		return self.time(bar, 0.0)

	def bus(self, name: str) -> np.ndarray:
		if name not in self.buses:
			self.buses[name] = np.zeros((self.buflen, 2), dtype=np.float32)
		return self.buses[name]

	def add(self, bus: str, t: float, sig: np.ndarray, pan: float = 0.0, gain: float = 1.0) -> None:
		buf = self.bus(bus)
		st = S.pan(sig, pan) if sig.ndim == 1 else sig
		st = st * gain
		if not self.loop:
			place(buf, st, max(t, 0.0))
			return
		start = ns(t % self.length) % self.n
		pos = 0
		while pos < len(st):
			m = min(len(st) - pos, self.n - start)
			buf[start:start + m] += st[pos:pos + m]
			pos += m
			start = 0

	def note(self, bus: str, inst, note, bar: float, beat: float, beats: float, vel: float = 0.8, pan: float = 0.0,
			human: float = 0.006, gain: float = 1.0, cents: float = 0.0, **kw) -> None:
		f = note if isinstance(note, float) else hz(note)
		f *= 2 ** (cents / 1200.0)
		t0 = self.time(bar, beat)
		dur = max(0.02, self.time(bar, beat + beats) - t0)
		t = t0 + (self.rng.normal(0, human) if human > 0 else 0.0)
		v = float(np.clip(vel * (1.0 + (self.rng.normal(0, 0.06) if human > 0 else 0.0)), 0.03, 1.0))
		sig = inst(f, dur, v, self.rng, **kw)
		self.log.append((bus, f, t, dur, v))
		self.add(bus, t, sig, pan, gain)

	# ---------------------------------------------------------------------------------
	def render(self, levels: dict, ir: np.ndarray, hp: float = 32.0, lp: float = 14000.0, eq=None,
			bus_fx=None) -> dict:
		"""levels: bus -> (gain_db, reverb_send[, layer]); bus_fx: bus -> fn(stereo) -> stereo (per-bus EQ).
		Returns {layer: stereo float64 array}. The same reverb, filters and EQ are applied to every
		layer, so layers sum exactly to the mix."""
		layers: dict = {}
		for name, buf in self.buses.items():
			spec = levels.get(name, (0.0, 0.2))
			g, snd = spec[0], spec[1]
			lay = spec[2] if len(spec) > 2 else "main"
			if bus_fx and name in bus_fx:
				x = buf.astype(np.float64)
				buf = circular(bus_fx[name], x, ns(0.5)) if self.loop else bus_fx[name](x)
			if lay not in layers:
				layers[lay] = [np.zeros((self.buflen, 2)), np.zeros((self.buflen, 2))]
			layers[lay][0] += buf * db(g)
			layers[lay][1] += buf * (db(g) * snd)
		out = {}
		for lay, (dry, send) in layers.items():
			wet = np.stack([_oaconv(send[:, c], ir[:, c]) for c in range(2)], axis=1)
			if self.loop:
				full = dry + fold_loop(wet, self.n)
				pad = ns(1.0)
				full = circular(lambda x: F.highpass(x, hp, 2), full, pad)
				full = circular(lambda x: F.lowpass(x, lp, 1), full, pad)
				if eq:
					full = circular(eq, full, pad)
			else:
				full = np.zeros((len(wet), 2))
				full[:len(dry)] += dry
				full += wet
				full = F.highpass(full, hp, 2)
				full = F.lowpass(full, lp, 1)
				if eq:
					full = eq(full)
			out[lay] = full
		if not self.loop:
			# one common end point for all layers: where the whole mix has decayed to -70 dB
			mix = sum(out.values())
			mag = np.max(np.abs(mix), axis=1)
			thr = np.max(mag) * db(-70.0)
			above = np.nonzero(mag[self.n:] > thr)[0]
			end = self.n + (above[-1] if above.size else 0) + ns(0.25)
			end = min(end, len(mix))
			for k in out:
				y = out[k][:end].copy()
				fo = ns(1.2)
				y[-fo:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fo)))[:, None]
				fi = ns(0.004)
				y[:fi] *= np.linspace(0, 1, fi)[:, None]
				out[k] = y
		return out


class own_rng:
	"""with own_rng(score, key): notes written inside draw from their own seeded generator, so parts added
	in review do not shift the random stream (humanisation, instrument noise) of every later note."""

	def __init__(self, s: Score, key: str):
		self.s = s
		self.key = key

	def __enter__(self):
		self.saved = self.s.rng
		self.s.rng = rng_for(self.key)
		return self.s

	def __exit__(self, *exc):
		self.s.rng = self.saved
		return False


def shelf(gain_db: float, fc: float):
	"""Per-bus high-shelf (used to keep bright voices inside the house's soft palette)."""
	return lambda x: F.rbj(x, "highshelf", fc, 0.7, gain_db)


def _oaconv(x, h):
	from scipy import signal
	return signal.oaconvolve(x, h)


# ==========================================================================================
# Note-writing helpers
# ==========================================================================================

def flat(bars, bpb: int, check: bool = True) -> list:
	"""[[(note, beats), ...] per bar] -> flat list; asserts every bar is exactly full."""
	out = []
	for i, bar in enumerate(bars):
		tot = sum(b for _, b, *rest in bar)
		if check and abs(tot - bpb) > 1e-6:
			raise ValueError("bar %d sums to %s beats, expected %d: %r" % (i, tot, bpb, bar))
		out.extend(bar)
	return out


def seq(s: Score, bus: str, inst, start_bar: float, notes, vel: float = 0.8, pan: float = 0.0, transpose: int = 0,
		legato: float = 1.0, accent: float = 0.06, human: float = 0.006, cents: float = 0.0, **kw) -> float:
	"""Plays a flat list [(note | (n1, n2..) | 'r', beats[, vel])] from start_bar; notes may cross
	barlines. Returns the length in beats."""
	pos = start_bar * s.bpb
	for item in notes:
		nm, beats = item[0], item[1]
		v = item[2] if len(item) > 2 else vel
		if nm != "r":
			bar = int(pos // s.bpb)
			beat = pos - bar * s.bpb
			vv = min(1.0, v + (accent if abs(beat) < 1e-9 else 0.0))
			for one in (nm if isinstance(nm, tuple) else (nm,)):
				s.note(bus, inst, midi(one) + transpose, bar, beat, beats * legato, vv, pan, human=human, cents=cents, **kw)
		pos += beats
	return pos - start_bar * s.bpb


def pads(s: Score, bus: str, inst, prog, start_bar: int, lo: int, hi: int, vel: float, pan: float = 0.0,
		overlap: float = 0.1, tie: bool = False, **kw) -> None:
	"""Sustained voice-led chords. tie=True holds common tones across chord changes instead of
	re-attacking them (legato strings / choir)."""
	segs = list(chord_seq(prog, start_bar, s.bpb))
	prev = None
	notes = []
	active: dict = {}
	for bar, b0, nb, sym in segs:
		v = voicing(sym, lo, hi, prev)
		prev = v
		a = bar * s.bpb + b0
		if not tie:
			notes += [(n, a, a + nb) for n in v]
			continue
		for n in list(active):
			if n not in v:
				notes.append((n, active.pop(n), a))
		for n in v:
			active.setdefault(n, a)
	if tie and segs:
		bar, b0, nb, _ = segs[-1]
		end = bar * s.bpb + b0 + nb
		notes += [(n, a, end) for n, a in active.items()]
	for n, a, b in sorted(notes, key=lambda x: (x[1], x[0])):
		s.note(bus, inst, n, 0, a, b - a + overlap, vel, pan, human=0.0, **kw)


def bassline(s: Score, bus: str, inst, prog, start_bar: int, pattern, lo: int, vel: float, pan: float = 0.0,
		**kw) -> None:
	"""pattern = [(beat, beats, degree, vel_mul)] degree in tones_of() keys ('bass', 'fifth_lo', ...)."""
	for bar, b0, nb, sym in chord_seq(prog, start_bar, s.bpb):
		t = tones_of(sym, lo + 12)
		for beat, beats, deg, vm in pattern:
			if b0 <= beat < b0 + nb:
				s.note(bus, inst, t[deg], bar, beat, beats, vel * vm, pan, **kw)


def chords_on(s: Score, bus: str, inst, prog, start_bar: int, beats_at, length: float, lo: int, hi: int,
		vel: float, pan: float = 0.0, roll: float = 0.0, human: float = 0.004, **kw) -> None:
	"""Detached chords on the given beats (the 'pah-pah' of a waltz, off-beat stabs...)."""
	prev = None
	for bar, b0, nb, sym in chord_seq(prog, start_bar, s.bpb):
		v = voicing(sym, lo, hi, prev)
		prev = v
		for beat in beats_at:
			if b0 <= beat < b0 + nb:
				for k, n in enumerate(v):
					s.note(bus, inst, n, bar, beat + roll * k, length, vel, pan, human=human, **kw)


def arps(s: Score, bus: str, inst, prog, start_bar: int, pattern, lo: int, vel: float, pan: float = 0.0,
		length: float = 1.0, to_chord_end: bool = False, **kw) -> None:
	"""pattern = [(beat, degree, vel_mul)]; to_chord_end lets each note ring until the chord changes
	(a sustain pedal)."""
	for bar, b0, nb, sym in chord_seq(prog, start_bar, s.bpb):
		t = tones_of(sym, lo)
		for beat, deg, vm in pattern:
			if b0 <= beat < b0 + nb:
				L = (b0 + nb - beat) if to_chord_end else length
				s.note(bus, inst, t[deg], bar, beat, L, vel * vm, pan, **kw)


# ==========================================================================================
# Mastering
# ==========================================================================================

def _gain_env(mag: np.ndarray, ceiling_db: float, window: float, loop: bool) -> np.ndarray:
	"""Look-ahead peak-limiter gain curve (same idea as hhsynth.core.limiter) - returned as a curve so
	that it can be applied identically to several stems."""
	ceil = db(ceiling_db)
	g = np.minimum(1.0, ceil / np.maximum(mag, 1e-12))
	if np.all(g >= 1.0):
		return np.ones_like(mag)
	h = max(1, ns(window))
	mode = "wrap" if loop else "nearest"          # a loop's gain curve is periodic too
	g2 = ndimage.minimum_filter1d(g, size=2 * h + 1, mode=mode)
	g2 = ndimage.uniform_filter1d(g2, size=h, mode=mode)
	g2 = ndimage.uniform_filter1d(g2, size=h, mode=mode)
	return np.minimum(g2, 1.0)


def master(layers: dict, loop: bool, target: float, ref_keys=None, combos=None, tp_max: float = -1.35,
		window: float = 0.025) -> tuple:
	"""Gain to `target` integrated LUFS (measured on the sum of ref_keys), then a gentle shared peak
	limiter so that every combination in `combos` stays under tp_max dBTP. Returns (layers, info)."""
	keys = list(layers)
	ref_keys = ref_keys or keys
	combos = combos or [keys]
	out = {k: v.copy() for k, v in layers.items()}
	ceiling = tp_max - 0.3
	info = {}
	for it in range(6):
		ref = sum(out[k] for k in ref_keys)
		L = MM.integrated_lufs(ref)
		g = db(target - L)
		base = {k: v * g for k, v in out.items()}
		mag = np.zeros(len(ref))
		for c in combos:
			mag = np.maximum(mag, np.max(np.abs(sum(base[k] for k in c)), axis=1))
		genv = _gain_env(mag, ceiling, window, loop)
		cand = {k: v * genv[:, None] for k, v in base.items()}
		tps = [MM.true_peak_db(sum(cand[k] for k in c)) for c in combos]
		L2 = MM.integrated_lufs(sum(cand[k] for k in ref_keys))
		info = {"lufs": L2, "tp": max(tps), "limited_pct": float(np.mean(genv < 0.995) * 100.0),
			"max_gr_db": float(-20 * np.log10(np.min(genv)))}
		out = cand
		ok_tp = max(tps) <= tp_max
		ok_l = abs(L2 - target) <= 0.25
		if ok_tp and ok_l:
			break
		if not ok_tp:
			ceiling -= (max(tps) - tp_max) + 0.1
	return out, info


def write_ogg(path: str, x: np.ndarray) -> None:
	"""soundfile / libsndfile OGG Vorbis. Written in blocks: one huge write call overflows the stack
	inside libsndfile's Vorbis encoder on Windows (observed with libsndfile 1.2.2)."""
	import soundfile as sf
	x = np.ascontiguousarray(x, dtype=np.float32)
	with sf.SoundFile(path, "w", SR, x.shape[1], format="OGG", subtype="VORBIS") as fh:
		for i in range(0, len(x), 8192):
			fh.write(x[i:i + 8192])


def read_ogg(path: str) -> np.ndarray:
	import soundfile as sf
	x, sr = sf.read(path, dtype="float64", always_2d=True)
	assert sr == SR, path
	return x


# ==========================================================================================
# m20 "The Empty Waltz" - Moonveil Manor exploration (A minor, 3/4, 96 bpm, ends)
# ==========================================================================================
# Form: intro(4) A(16: a a') B(16: b b', relative major) interlude(4, 'empty ballroom')
#       A'(16, harpsichord + celesta + string counter-melody) coda(8, ritardando) - 64 bars.
# The melody always enters after the downbeat (rest - 5th - octave): the missing dance partner.

M20_INTRO = ["Am", "Dm/A", "Am", "E7/G#"]
M20_A1 = ["Am", "E7/G#", "Am/G", "Fmaj7", "Dm", "Am/E", "Bm7b5", "E7"]
M20_A2 = ["Am", "E7/G#", "Am/G", "F#m7b5", "Fmaj7", "Dm7", "E7", "Am"]
M20_B1 = ["C", "G/B", "Am", "Em/G", "F", "C/E", "Dm7", "G7"]
M20_B2 = ["C", "E7/B", "Am", "Am/G", "Dm/F", "Dm6", "E7sus4", "E7"]
M20_INTER = ["Am", "Fmaj7/A", "Am", "E7/G#"]
M20_CODA = ["Am", "Dm/F", "Am/E", "E7", "Am", "Fmaj7", "E7", "Am"]

M20_MEL_A1 = [
	[("r", 1), ("E5", 1), ("A5", 1)],
	[("G#5", 1.5), ("F5", 0.5), ("E5", 1)],
	[("r", 1), ("C5", 1), ("E5", 1)],
	[("E5", 2), ("D5", 0.5), ("C5", 0.5)],
	[("r", 1), ("F5", 1), ("A5", 1)],
	[("C6", 1.5), ("B5", 0.5), ("A5", 1)],
	[("F5", 1.5), ("E5", 0.5), ("D5", 1)],
	[("E5", 2), ("r", 1)],
]
M20_MEL_A2 = [
	[("r", 1), ("E5", 1), ("A5", 1)],
	[("G#5", 1.5), ("F5", 0.5), ("E5", 1)],
	[("r", 1), ("A5", 1), ("C6", 1)],
	[("C6", 1.5), ("B5", 0.5), ("A5", 1)],
	[("A5", 2), ("G5", 0.5), ("F5", 0.5)],
	[("F5", 1.5), ("E5", 0.5), ("D5", 1)],
	[("E5", 1), ("D5", 1), ("G#4", 1)],
	[("A4", 2), ("r", 1)],
]
M20_MEL_B1 = [
	[("C6", 2), ("B5", 0.5), ("A5", 0.5)],
	[("G5", 2), ("D5", 1)],
	[("A5", 2), ("G5", 0.5), ("F5", 0.5)],
	[("E5", 2), ("B4", 1)],
	[("F5", 1), ("A5", 1), ("C6", 1)],
	[("G5", 2), ("E5", 1)],
	[("F5", 1.5), ("E5", 0.5), ("D5", 1)],
	[("B4", 1), ("D5", 1), ("F5", 1)],
]
M20_MEL_B2 = [
	[("E5", 2), ("G5", 0.5), ("C6", 0.5)],
	[("B5", 2), ("G#5", 1)],
	[("A5", 1.5), ("B5", 0.5), ("C6", 1)],
	[("E6", 2), ("D6", 0.5), ("C6", 0.5)],
	[("A5", 2), ("F5", 1)],
	[("B5", 1), ("A5", 1), ("F5", 1)],
	[("A5", 3)],
	[("G#5", 2), ("B4", 1)],
]
M20_MEL_INTER = [
	[("r", 1), ("E6", 1), ("A6", 1)],
	[("r", 3)],
	[("r", 1), ("E6", 1), ("C6", 1)],
	[("B5", 2), ("r", 1)],
]
# muted cellos under A' (inner line, chromatic lament shape)
M20_CTR = [
	[("C4", 3)], [("D4", 3)], [("C4", 3)], [("A3", 3)], [("F3", 2), ("A3", 1)], [("C4", 3)], [("D4", 3)], [("G#3", 3)],
	[("C4", 3)], [("B3", 3)], [("C4", 3)], [("A3", 3)], [("C4", 3)], [("C4", 2), ("A3", 1)], [("G#3", 1.5), ("B3", 1.5)],
	[("A3", 3)],
]
M20_CODA_CEL = [  # celesta and harpsichord trade the head motif, lower each time
	[("r", 1), ("E5", 1), ("A5", 1)], [("r", 3)], [("r", 1), ("E5", 1), ("C5", 1)], [("r", 3)],
	[("r", 3)], [("E5", 3)], [("r", 3)], [("A5", 3)],
]
M20_CODA_HPS = [
	[("r", 3)], [("r", 1), ("F5", 1), ("A5", 1)], [("r", 3)], [("B4", 2), ("r", 1)],
	[("r", 1), ("E4", 1), ("A4", 1)], [("r", 3)], [("G#4", 2), ("B4", 1)], [("A4", 3)],
]


def m20_empty_waltz(rng):
	# 64 bars at 96 bpm, ritardando over the last four bars, the final bar held
	s = Score(96, 3, 64, rng, loop=False, tempo=[(60, 63, 92, 70), (63, 64, 60, 46)], tail=10.0)
	prog = M20_INTRO + M20_A1 + M20_A2 + M20_B1 + M20_B2 + M20_INTER + M20_A1 + M20_A2 + M20_CODA
	assert len(prog) == 64
	A, B, I, A2, C = 4, 20, 36, 40, 56

	# --- intro: harpsichord (lute stop) 'pah-pah', pizzicato 'oom', cellos breathe underneath
	chords_on(s, "hps_acc", V.harpsichord, M20_INTRO, 0, (1.0, 2.0), 0.55, 55, 67, 0.4, -0.2, buff=True)
	bassline(s, "pizz", V.pizz, M20_INTRO, 0, [(0.0, 1.0, "bass", 1.0)], 40, 0.62)
	pads(s, "cello", V.muted_strings, M20_INTRO, 0, 43, 55, 0.26, 0.0, attack=0.6, release=0.8, bright=0.7, tie=True)

	# --- A: celesta sings, harpsichord accompanies (8' stop), pizzicato bass
	# (review: the A celesta has its own bus - on the shared one it made A 7.6 LU louder than B)
	seq(s, "cel_mel", M.celesta, A, flat(M20_MEL_A1 + M20_MEL_A2, 3), 0.62, 0.18)
	chords_on(s, "hps_acc", V.harpsichord, M20_A1 + M20_A2, A, (1.0, 2.0), 0.5, 55, 67, 0.4, -0.2)
	bassline(s, "pizz", V.pizz, M20_A1 + M20_A2, A, [(0.0, 1.0, "bass", 1.0)], 40, 0.66)
	pads(s, "cello", V.muted_strings, M20_A1 + M20_A2, A, 43, 55, 0.22, 0.0, attack=0.5, release=0.8, bright=0.7, tie=True)
	pads(s, "strpad", V.muted_strings, M20_A2, A + 8, 57, 69, 0.14, 0.0, attack=0.9, release=1.2, tie=True)

	# --- B (C major): harpsichord takes a new, more flowing tune; strings play the 'pah-pah'
	seq(s, "hps", V.harpsichord, B, flat(M20_MEL_B1, 3), 0.72, -0.1)
	seq(s, "hps", V.harpsichord, B + 8, flat(M20_MEL_B2, 3), 0.78, -0.1, four=True)
	chords_on(s, "str_pah", V.muted_strings, M20_B1 + M20_B2, B, (1.0, 2.0), 0.55, 55, 67, 0.36, 0.15,
		attack=0.03, release=0.18)
	bassline(s, "pizz", V.pizz, M20_B1 + M20_B2, B, [(0.0, 1.0, "bass", 1.0)], 40, 0.7)
	pads(s, "cello", V.muted_strings, M20_B1 + M20_B2, B, 43, 55, 0.24, 0.0, attack=0.5, release=0.8, bright=0.7, tie=True)
	for bar, notes in ((B + 3, ["B5", "E6"]), (B + 7, ["D6", "F6"]), (B + 11, ["C6", "E6"]), (B + 15, ["B5", "E6"])):
		for k, nm in enumerate(notes):
			s.note("cel", M.celesta, nm, bar, 1.0 + k, 1.0, 0.34, 0.4)

	# --- interlude: the ballroom empties - a string drone, a clock, the head motif far away
	s.note("cello", V.muted_strings, "A2", I, 0.0, 12.0, 0.34, 0.0, human=0.0, attack=1.2, release=1.5, bright=0.6)
	s.note("cello", V.muted_strings, "E3", I, 0.0, 12.0, 0.22, 0.0, human=0.0, attack=1.8, release=1.5, bright=0.6)
	s.note("pizz", V.pizz, "A2", I, 0.0, 1.0, 0.55)
	seq(s, "cel", M.celesta, I, flat(M20_MEL_INTER, 3), 0.42, 0.45)
	for k in range(12):
		bar, beat = I + k // 3, float(k % 3)
		s.note("clock", V.tick, "E6" if k % 2 == 0 else "B5", bar, beat, 0.2, 0.2, -0.45, human=0.0, t60=0.25)

	# --- A': harpsichord (8'+4') melody, celesta an octave above, muted cellos' counter-line
	seq(s, "hps", V.harpsichord, A2, flat(M20_MEL_A1 + M20_MEL_A2, 3), 0.8, -0.08, four=True)
	seq(s, "cel", M.celesta, A2, flat(M20_MEL_A1, 3), 0.3, 0.35, transpose=12)
	seq(s, "cel", M.celesta, A2 + 8, flat(M20_MEL_A2[:6], 3, check=False), 0.28, 0.35, transpose=12)
	seq(s, "ctr", V.muted_strings, A2, flat(M20_CTR, 3), 0.5, 0.25, legato=1.02, attack=0.25, release=0.5, vib=9.0)
	chords_on(s, "hps_acc", V.harpsichord, M20_A1 + M20_A2, A2, (1.0, 2.0), 0.5, 52, 64, 0.38, -0.3, buff=True)
	bassline(s, "pizz", V.pizz, M20_A1 + M20_A2, A2, [(0.0, 1.0, "bass", 1.0)], 40, 0.74)
	pads(s, "strpad", V.muted_strings, M20_A1 + M20_A2, A2, 57, 69, 0.15, 0.0, attack=0.9, release=1.2, tie=True)

	# --- coda: the motif sinks and slows; last chord rolled on the harpsichord
	seq(s, "cel", M.celesta, C, flat(M20_CODA_CEL, 3), 0.44, 0.3)
	seq(s, "hps_coda", V.harpsichord, C, flat(M20_CODA_HPS, 3), 0.62, -0.1)
	pads(s, "strpad", V.muted_strings, M20_CODA[:7], C, 55, 67, 0.16, 0.0, attack=1.0, release=1.4, tie=True)
	bassline(s, "pizz", V.pizz, M20_CODA[:7], C, [(0.0, 1.0, "bass", 1.0)], 40, 0.6)
	pads(s, "cello", V.muted_strings, M20_CODA[:7], C, 43, 55, 0.2, 0.0, attack=0.6, release=1.0, bright=0.7, tie=True)
	last = C + 7
	for k, nm in enumerate(["A2", "E3", "A3", "C4", "E4"]):          # the melody's A4 tops the roll
		s.note("hps_coda", V.harpsichord, nm, last, 0.12 * k, 3.0, 0.62, -0.1 + 0.05 * k, human=0.0)
	s.note("cello", V.muted_strings, "A2", last, 0.0, 3.0, 0.3, 0.0, human=0.0, attack=0.4, release=2.0, bright=0.6)
	s.note("pizz", V.pizz, "A1", last, 0.0, 1.0, 0.6, human=0.0, ring=1.4)

	ir = S.hall(rng, 2.7, brightness=6500)
	# review (dry per-section loudness): the A celesta was 8 dB above everything else while the B / A'
	# harpsichord tune sat level with the pizzicato bass -> A -14.1, B -21.7 LUFS (LRA 9.9 LU).
	# Celesta tune -5.5 dB on its own bus, other celesta -3 dB, harpsichord tune +5 dB (coda unchanged).
	levels = {"cel_mel": (-5.5, 0.42), "cel": (-3.0, 0.42), "hps": (3.0, 0.3), "hps_coda": (-2.0, 0.3),
		"hps_acc": (-6.0, 0.28), "pizz": (-6.0, 0.18), "cello": (-7.0, 0.3), "strpad": (-9.0, 0.4),
		"str_pah": (-7.0, 0.3), "ctr": (-6.0, 0.32), "clock": (-14.0, 0.5)}
	# (review: 4-8 kHz share was ~9 dB above music_haven's - quill ticks and celesta partials; a gentle
	# whole-mix shelf keeps the harpsichord's nasal 1-4 kHz character but takes the edge off the top)
	lay = s.render(levels, ir, lp=12000.0, eq=shelf(-3.0, 5500.0), bus_fx={"cel_mel": shelf(-5.0, 4500.0),
		"cel": shelf(-4.0, 4500.0), "hps": shelf(-3.0, 4000.0), "hps_coda": shelf(-3.0, 4000.0),
		"hps_acc": shelf(-3.0, 3500.0)})
	secs = [(0, "intro"), (A, "A"), (B, "B"), (I, "interlude"), (A2, "A'"), (C, "coda")]
	return s, lay, secs


# ==========================================================================================
# m21 "A Midnight Invitation" - Count Velour (E minor, 3/4, 144 bpm, LOOP)
# ==========================================================================================
# Form: intro(4) | Waltz I A(16, E minor, 'velvet fiddle') | Waltz II(16, G major, harpsichord,
#       charming, with a sinister C minor-6 turn) | MIDNIGHT(24, G minor: hemiola 2-against-3 theme
#       in low strings, twelve bell strokes, then the fiddle and a full climax) | turn(4) |
#       Waltz I reprise(16, tutti) -> loop to intro. 80 bars = 100 s.
# The Waltz I head is a rising minor sixth that leans back down chromatically (the 'invitation').

M21_INTRO = ["Em", "C", "Am6", "B7"]
M21_A1 = ["Em", "B7", "Em", "Am6", "C", "E7", "F#m7b5", "B7"]
M21_A2 = ["Em", "B7", "E7/D", "Am/C", "D#dim7", "Em/B", "B7", "Em"]
M21_A3 = ["Em", "B7", "E7/D", "Am/C", "D#dim7", "Em/B", "C7", "B7"]
M21_W2 = ["G", "D7/F#", "G", "C", "Am7", "D7", "G", "E7", "Am", "Cm6", "G/D", "E7", "Am7", "D7", "Eb", "D7"]
M21_MB1 = ["Gm", "Gm", "Eb", "Eb", "Cm", "D7", "Gm", "D7"]
M21_MB2 = ["Gm", "Gm/F", "Eb", "Cm/Eb", "Am7b5", "D7", "Gm", "D7"]
M21_MB3 = ["Eb", "F", "Dm", "Gm", "Cm", "D7", "Eb", "D7"]
M21_TRANS = ["C", "C", "B7", "B7"]

M21_MEL_A1 = [
	[("B4", 1), ("G5", 2)], [("F#5", 1), ("E5", 1), ("D#5", 1)], [("E5", 1), ("B5", 2)], [("A5", 1), ("G5", 1), ("F#5", 1)],
	[("G5", 1), ("C6", 2)], [("B5", 1), ("A5", 1), ("G#5", 1)], [("A5", 1.5), ("G5", 0.5), ("F#5", 1)], [("D#5", 2), ("r", 1)],
]
M21_MEL_A2 = [
	[("B4", 1), ("G5", 2)], [("F#5", 1), ("E5", 1), ("D#5", 1)], [("E5", 1), ("D6", 2)], [("C6", 1), ("B5", 1), ("A5", 1)],
	[("F#5", 1), ("A5", 1), ("C6", 1)], [("B5", 2), ("G5", 1)], [("A5", 1), ("F#5", 1), ("D#5", 1)], [("E5", 2), ("r", 1)],
]
M21_MEL_A3 = M21_MEL_A1 + M21_MEL_A2[:6] + [[("E5", 1), ("G5", 1), ("Bb5", 1)], [("A5", 1), ("F#5", 1), ("D#5", 1)]]
M21_MEL_W2 = [
	[("B5", 1.5), ("A5", 0.5), ("G5", 1)], [("A5", 1), ("F#5", 1), ("D5", 1)], [("B5", 1.5), ("C6", 0.5), ("D6", 1)],
	[("E6", 2), ("C6", 1)], [("C6", 1.5), ("B5", 0.5), ("A5", 1)], [("F#5", 1), ("A5", 1), ("C6", 1)], [("B5", 2), ("G5", 1)],
	[("G#5", 1), ("B5", 1), ("D6", 1)],
	[("C6", 1.5), ("B5", 0.5), ("A5", 1)], [("Eb6", 2), ("C6", 1)], [("B5", 1.5), ("A5", 0.5), ("G5", 1)],
	[("G#5", 2), ("E5", 1)], [("A5", 1), ("C6", 1), ("E6", 1)], [("D6", 1.5), ("C6", 0.5), ("A5", 1)], [("G5", 2), ("Bb5", 1)],
	[("A5", 2), ("F#5", 1)],
]
# midnight theme: half notes against the waltz = hemiola (three 2-beat notes per two bars)
M21_MID1 = [("G4", 2), ("Bb4", 2), ("D5", 2), ("Eb5", 2), ("D5", 2), ("Bb4", 2), ("C5", 2), ("Eb5", 2), ("D5", 2),
	("Bb4", 2), ("A4", 2), ("F#4", 2)]
M21_MID2 = [("G5", 2), ("Bb5", 2), ("D6", 2), ("Eb6", 2), ("D6", 2), ("C6", 2), ("C6", 2), ("Eb6", 2), ("D6", 2),
	("Bb5", 1), ("A5", 1), ("G5", 2), ("F#5", 2)]
M21_MID2_CTR = [("Bb3", 2), ("D4", 2), ("A3", 2), ("G3", 2), ("Bb3", 2), ("G3", 2), ("A3", 2), ("C4", 2), ("A3", 2),
	("G3", 2), ("F#3", 2), ("A3", 2)]
M21_MEL_MB3 = [
	[("D5", 1), ("Bb5", 2)], [("A5", 1), ("G5", 1), ("F5", 1)], [("F5", 1), ("D6", 2)], [("D6", 1), ("C6", 1), ("Bb5", 1)],
	[("G5", 1), ("Eb6", 2)], [("D6", 1), ("C6", 1), ("A5", 1)], [("Bb5", 1.5), ("G5", 0.5), ("Eb5", 1)], [("F#5", 2), ("A5", 1)],
]
M21_MEL_TRANS = [[("E5", 1), ("G5", 1), ("C6", 1)], [("B5", 2), ("G5", 1)], [("F#5", 1), ("A5", 1), ("D#6", 1)],
	[("B5", 2), ("r", 1)]]


def m21_midnight_invitation(rng):
	s = Score(144, 3, 80, rng, loop=True)
	A, W, MID, T, R = 4, 20, 36, 60, 64
	prog = M21_INTRO + M21_A1 + M21_A2 + M21_W2 + M21_MB1 + M21_MB2 + M21_MB3 + M21_TRANS + M21_A1 + M21_A3
	assert len(prog) == 80
	oom = [(0.0, 1.0, "bass", 1.0)]

	# --- intro: the curtain - timpani, oom-pah-pah, harpsichord flourishes
	bassline(s, "pizz", V.pizz, M21_INTRO, 0, oom, 40, 0.75)
	chords_on(s, "pah", V.muted_strings, M21_INTRO, 0, (1.0, 2.0), 0.45, 52, 64, 0.42, 0.1, attack=0.02, release=0.12)
	s.note("timp", V.timpani, "E2", 0, 0.0, 1.0, 0.85, 0.0)
	s.note("timp", V.timpani, "B1", 3, 0.0, 1.0, 0.6, 0.0)
	seq(s, "hps", V.harpsichord, 1, [("E6", 0.5), ("D6", 0.5), ("C6", 0.5), ("B5", 0.5), ("A5", 0.5), ("G5", 0.5)], 0.6, -0.2,
		four=True)
	seq(s, "hps", V.harpsichord, 3, [("B3", 0.5), ("D#4", 0.5), ("F#4", 0.5), ("A4", 0.5), ("B4", 0.5), ("D#5", 0.5)], 0.6,
		-0.2, four=True)

	# --- Waltz I (E minor): velvet fiddle
	seq(s, "fid", V.fiddle, A, flat(M21_MEL_A1 + M21_MEL_A2, 3), 0.72, 0.05, legato=0.96)
	bassline(s, "pizz", V.pizz, M21_A1 + M21_A2, A, oom, 40, 0.78)
	chords_on(s, "pah", V.muted_strings, M21_A1 + M21_A2, A, (1.0, 2.0), 0.45, 52, 64, 0.42, 0.1, attack=0.02, release=0.12)
	chords_on(s, "hps_acc", V.harpsichord, M21_A1 + M21_A2, A, (1.0, 2.0), 0.4, 64, 76, 0.3, -0.35)
	for bar in (A, A + 8):
		s.note("timp", V.timpani, "E2", bar, 0.0, 1.0, 0.7, 0.0)
	s.note("timp", V.timpani, "B1", A + 7, 0.0, 1.0, 0.5, 0.0)

	# --- Waltz II (G major): harpsichord tune, lighter texture, celesta sparkles
	# (review: on the shared 'hps' bus the tune sat 5 dB under the pizzicato bass and Waltz II measured
	# -25.4 LUFS against -17.7 for Waltz I - a hole in the middle of a boss fight. Own bus + a soft
	# muted-string bed drawn from its own seed, so every other note keeps its original randomness.)
	seq(s, "hps2", V.harpsichord, W, flat(M21_MEL_W2, 3), 0.78, -0.12, four=True)
	bassline(s, "pizz", V.pizz, M21_W2, W, oom, 40, 0.72)
	chords_on(s, "pah", V.muted_strings, M21_W2, W, (1.0, 2.0), 0.4, 52, 64, 0.36, 0.15, attack=0.02, release=0.12)
	for k, (bar, nm) in enumerate([(W + 3, "G6"), (W + 7, "B6"), (W + 9, "G6"), (W + 11, "B6"), (W + 13, "F#6"),
			(W + 15, "D6")]):
		s.note("cel", M.celesta, nm, bar, 2.0, 1.0, 0.4, 0.45)
	# the minor-six shadow (bar W+9) gets a low string swell
	s.note("low", V.muted_strings, "C3", W + 9, 0.0, 3.0, 0.5, 0.0, attack=0.4, release=0.6, bright=0.8)
	s.note("low", V.muted_strings, "Eb3", W + 9, 0.0, 3.0, 0.4, 0.0, attack=0.4, release=0.6, bright=0.8)
	with own_rng(s, "music2:m21:wbed"):
		pads(s, "wbed", V.muted_strings, M21_W2, W, 55, 67, 0.2, 0.0, attack=0.35, release=0.5, bright=1.1, tie=True)
		# second half: the fiddle shadows the harpsichord an octave below (builds towards MIDNIGHT)
		seq(s, "fid2", V.fiddle, W + 8, flat(M21_MEL_W2[8:], 3), 0.5, 0.2, transpose=-12, legato=0.96)

	# --- MIDNIGHT (G minor), 24 bars. Twelve bell strokes, one every two bars.
	for k in range(12):
		s.note("bell", V.church_bell, "G3", MID + 2 * k, 0.0, 4.0, 0.62 - 0.012 * k, -0.15, human=0.0, t60=5.5)
	# B1: hemiola theme in the low strings, pizzicato on the hemiola beats, harpsichord clock
	# (review: own bus, +3 dB - B1 measured -22.9 LUFS, the phase-2 entry read as a drop-out)
	seq(s, "low1", V.muted_strings, MID, M21_MID1, 0.62, -0.1, transpose=-12, legato=0.98, attack=0.12, release=0.4,
		bright=1.2)
	for u in range(12):                      # two-bar units: accents on beats 0, 2, 4 of 6
		bar0 = MID + 2 * u
		for off in (0.0, 2.0, 4.0):
			bar = bar0 + int(off // 3)
			beat = off % 3
			sym = prog[bar]
			t = tones_of(sym, 40 + 12)
			nm = t["bass"] if off != 2.0 else t["fifth_lo"]
			s.note("pizz", V.pizz, nm, bar, beat, 1.0, 0.7 if off == 0 else 0.55, 0.0)
			if u >= 4:                            # B2 on: frame drum joins the hemiola
				s.note("drum", V.frame_drum, 70.0 if off == 0 else 95.0, bar, beat, 0.5,
					(0.55 if off == 0 else 0.35) + 0.02 * (u - 4), 0.0, human=0.002)
	for i in range(8 * 3):                   # clock: quarter notes (B1), eighths (B2)
		bar, beat = MID + i // 3, float(i % 3)
		s.note("clock", V.harpsichord, "D5" if i % 2 == 0 else "G4", bar, beat, 0.3, 0.28, 0.4, buff=True)
	for i in range(8 * 6):
		bar, beat = MID + 8 + i // 6, (i % 6) * 0.5
		s.note("clock", V.harpsichord, "D5" if i % 2 == 0 else "G4", bar, beat, 0.2, 0.24 + (0.06 if i % 6 == 0 else 0),
			0.4, buff=True)
	# B2: the fiddle takes the theme an octave up, cellos answer in contrary motion
	seq(s, "fid", V.fiddle, MID + 8, M21_MID2, 0.68, 0.05, legato=0.97, swell=0.3)
	seq(s, "low", V.muted_strings, MID + 8, M21_MID2_CTR, 0.5, -0.2, legato=0.98, attack=0.15, release=0.4)
	# B3: back to a full waltz, the climax of the middle section
	seq(s, "fid", V.fiddle, MID + 16, flat(M21_MEL_MB3, 3), 0.8, 0.05, legato=0.96)
	seq(s, "cel", M.celesta, MID + 16, flat(M21_MEL_MB3, 3), 0.3, 0.4, transpose=12)
	bassline(s, "pizz", V.pizz, M21_MB3, MID + 16, oom, 40, 0.8)
	chords_on(s, "pah", V.muted_strings, M21_MB3, MID + 16, (1.0, 2.0), 0.45, 52, 64, 0.46, 0.1, attack=0.02, release=0.12)
	pads(s, "horn", _horn, M21_MB3, MID + 16, 43, 55, 0.4, -0.1, overlap=0.0, tie=True)
	arps(s, "hps_acc", V.harpsichord, M21_MB3, MID + 16, [(0.0, "root", 0.9), (0.5, "third", 0.6), (1.0, "fifth", 0.7),
		(1.5, "top", 0.6), (2.0, "fifth", 0.65), (2.5, "third", 0.55)], 60, 0.42, -0.35, length=0.5, four=True)
	for k in range(8):
		s.note("timp", V.timpani, low(chord(prog[MID + 16 + k])["root"], 38), MID + 16 + k, 0.0, 1.0, 0.55 + 0.03 * k,
			0.0)

	# --- turn back to E minor
	seq(s, "fid", V.fiddle, T, flat(M21_MEL_TRANS, 3), 0.78, 0.05, legato=0.96)
	pads(s, "str", V.muted_strings, M21_TRANS, T, 52, 67, 0.36, 0.0, attack=0.3, release=0.5, bright=1.4)
	bassline(s, "pizz", V.pizz, M21_TRANS, T, oom, 40, 0.8)
	for i in range(12):
		bar, beat = T + 2 + i // 6, (i % 6) * 0.5
		s.note("timp", V.timpani, "B1", bar, beat, 0.5, 0.3 + 0.04 * i, 0.0, human=0.002, t60=1.2)
	s.note("swell", M.swell, 1000.0, T + 2, 0.0, 6.0, 0.8, 0.0, human=0.0)

	# --- Waltz I reprise (tutti) -> loops into the intro
	seq(s, "fid", V.fiddle, R, flat(M21_MEL_A3, 3), 0.82, 0.05, legato=0.96)
	seq(s, "cel", M.celesta, R, flat(M21_MEL_A3, 3), 0.28, 0.4, transpose=12)
	bassline(s, "pizz", V.pizz, M21_A1 + M21_A3, R, oom, 40, 0.82)
	chords_on(s, "pah", V.muted_strings, M21_A1 + M21_A3, R, (1.0, 2.0), 0.45, 52, 64, 0.46, 0.1, attack=0.02,
		release=0.12)
	arps(s, "hps_acc", V.harpsichord, M21_A1 + M21_A3, R, [(0.0, "root", 0.9), (0.5, "fifth", 0.6), (1.0, "top", 0.7),
		(1.5, "third_hi", 0.6), (2.0, "top", 0.65), (2.5, "fifth", 0.55)], 64, 0.36, -0.35, length=0.5, four=True)
	pads(s, "horn", _horn, M21_A1 + M21_A3, R, 43, 55, 0.32, -0.1, overlap=0.0, tie=True)
	for bar in (R, R + 4, R + 8, R + 12):
		s.note("timp", V.timpani, "E2", bar, 0.0, 1.0, 0.72, 0.0)

	ir = S.hall(rng, 2.3, brightness=6000)
	levels = {"fid": (-1.0, 0.3), "fid2": (-5.0, 0.32), "hps": (-2.0, 0.28), "hps2": (6.5, 0.28), "hps_acc": (-6.0, 0.25),
		"cel": (-6.0, 0.4), "pizz": (-3.0, 0.15), "pah": (-6.0, 0.22), "wbed": (-5.0, 0.35), "low": (-4.0, 0.3),
		"low1": (0.5, 0.3),
		"str": (-6.0, 0.3), "timp": (-4.0, 0.25), "bell": (-6.0, 0.5), "clock": (-8.0, 0.3), "drum": (-6.0, 0.2),
		"horn": (-9.0, 0.3), "swell": (-16.0, 0.4)}
	lay = s.render(levels, ir, bus_fx={"cel": shelf(-4.0, 4500.0), "hps": shelf(-2.0, 4000.0),
		"hps2": shelf(-3.0, 4000.0), "hps_acc": shelf(-3.0, 3500.0), "clock": shelf(-3.0, 3500.0)})
	secs = [(0, "intro"), (A, "waltz I"), (W, "waltz II"), (MID, "MIDNIGHT B1"), (MID + 8, "B2"), (MID + 16, "B3"),
		(T, "turn"), (R, "waltz I reprise")]
	return s, lay, secs


# ==========================================================================================
# m22 "Harvest Trouble" - Chapter Two combat (C minor, 4/4 galop at 160, LOOP)
# ==========================================================================================
# Review rewrite (2026-09-27). The first version was a C-minor 6/8 jig led by a bassoon-like reed over
# marimba and off-beat eighths: the same meter, a near-identical pulse (dotted quarter 112 vs 100), the
# same length (~68 s) and the same reed + marimba + pizzicato palette as m10 "Thorns in the Path",
# which the brief says m22 must be distinct from (and the reed + marimba + clacks palette of m17, the
# orchard piece this combat cue interrupts). This version is a straight-eighth 4/4 galop: spiccato
# muted strings doubled by a hard-mallet marimba carry a scampering tune, pizzicato 'oom' on 1 and 3
# against string stabs on 2 and 4, bones/clacks and a frame drum; cellos sing a lyrical E-flat B
# section. Kept from the first version: C minor, the E-flat contrast, the G-pedal call-and-response
# bridge with a D-flat (Neapolitan) build and stop-time hits.
# Form: intro(2) A(16: a a') B(16: b b') C bridge(8: call/response 4, build 2, stop-time 2)
#       A''(8, tutti, turnaround) -> loop. 50 bars at 160 = 75.0 s (1.5 s bars, 66150 frames each).

M22_INTRO = ["Cm", "G7"]
M22_A1 = ["Cm", "Ab/Bb", "Ab", "G7", "Cm", "Eb/Bb", "F7", "G7"]          # lament bass C-Bb-Ab-G
M22_A2 = ["Cm", "Ab/Bb", [("Ab", 2), ("Fm", 2)], "Db", "Cm/G", "Ab", [("Dm7b5", 2), ("G7", 2)], "Cm"]
M22_B1 = ["Eb", "Bb7/D", "Cm7", "G/B", "Ab", "Eb/G", "Fm7", "Bb7"]
M22_B2 = ["Eb", "Bb7/D", "Cm7", "G/B", "Ab", "Eb/G", [("Fm7", 2), ("Dm7b5", 2)], "G7"]
M22_C = ["Cm/G", "Dm7b5/G", "Cm7/G", "G7", "Ab", "Db", "G7", "G7"]
M22_A3 = ["Cm", "Ab/Bb", "Ab", "G7", "Cm", "Eb/Bb", [("F7", 2), ("Ab", 2)], [("Cm", 2), ("G7", 2)]]

# the scamper: a broken C-minor chord that tumbles back, a chromatic creep (Ab-B-C-D), a b9 on G7
M22_MEL_A1 = [
	[("C5", .5), ("Eb5", .5), ("G5", .5), ("Eb5", .5), ("C5", .5), ("r", .5), ("G4", 1)],
	[("Ab4", .5), ("B4", .5), ("C5", .5), ("D5", .5), ("Eb5", 1), ("D5", .5), ("r", .5)],
	[("C5", .5), ("Eb5", .5), ("Ab5", .5), ("G5", .5), ("F5", .5), ("Eb5", .5), ("C5", 1)],
	[("B4", .5), ("D5", .5), ("F5", .5), ("Ab5", .5), ("G5", 1.5), ("r", .5)],
	[("C5", .5), ("Eb5", .5), ("G5", .5), ("Eb5", .5), ("C6", .5), ("r", .5), ("G5", 1)],
	[("Bb5", .5), ("G5", .5), ("Eb5", .5), ("G5", .5), ("Bb5", 1), ("Ab5", .5), ("G5", .5)],
	[("A5", .5), ("F5", .5), ("C5", .5), ("F5", .5), ("A5", .5), ("C6", .5), ("Eb6", .5), ("D6", .5)],
	[("B5", .5), ("G5", .5), ("F5", .5), ("D5", .5), ("B4", 1), ("r", 1)],
]
M22_MEL_A2 = M22_MEL_A1[:2] + [
	[("C5", .5), ("Eb5", .5), ("Ab5", .5), ("C6", .5), ("Bb5", .5), ("Ab5", .5), ("F5", 1)],
	[("Db5", 1), ("F5", .5), ("Ab5", .5), ("Db6", 1.5), ("r", .5)],
	[("C6", .5), ("B5", .5), ("C6", .5), ("G5", .5), ("Eb5", .5), ("D5", .5), ("C5", .5), ("Eb5", .5)],
	[("Ab5", .5), ("G5", .5), ("Ab5", .5), ("Eb5", .5), ("C5", 1), ("Ab4", 1)],
	[("F5", .5), ("Ab5", .5), ("D5", .5), ("F5", .5), ("B4", .5), ("D5", .5), ("G5", .5), ("F5", .5)],
	[("Eb5", .5), ("D5", .5), ("C5", 1), ("r", 2)],
]
M22_MEL_A3 = M22_MEL_A1[:6] + [
	[("A5", .5), ("F5", .5), ("C6", .5), ("A5", .5), ("Ab5", .5), ("C6", .5), ("Eb6", .5), ("C6", .5)],
	[("C6", 1), ("G5", .5), ("Eb5", .5), ("D5", .5), ("F5", .5), ("B4", .5), ("D5", .5)],
]
# B: a broad cello song in E-flat (the one legato tune), with a G-major chord as the 'trouble' twist
M22_MEL_B1 = [
	[("Eb3", 1.5), ("F3", .5), ("G3", 1), ("Bb3", 1)],
	[("Ab3", 1.5), ("G3", .5), ("F3", 2)],
	[("G3", 1.5), ("Ab3", .5), ("Bb3", 1), ("C4", 1)],
	[("D4", 2), ("B3", 2)],
	[("C4", 1.5), ("Bb3", .5), ("Ab3", 1), ("C4", 1)],
	[("Bb3", 1.5), ("G3", .5), ("Eb3", 2)],
	[("Ab3", 1), ("G3", 1), ("F3", 1), ("Ab3", 1)],
	[("F3", 1), ("Ab3", 1), ("D3", 1), ("Bb2", 1)],
]
M22_MEL_B2 = M22_MEL_B1[:7] + [[("G3", 1), ("F3", 1), ("D3", 1), ("B2", 1)]]
# bridge: creeping strings call (beats 1-2), the marimba answers from above (beats 3-4)
M22_C_CALL = [
	[("G4", .5), ("Ab4", .5), ("G4", .5), ("F#4", .5), ("r", 2)],
	[("Ab4", .5), ("Bb4", .5), ("Ab4", .5), ("G4", .5), ("r", 2)],
	[("Bb4", .5), ("C5", .5), ("Bb4", .5), ("Ab4", .5), ("r", 2)],
	[("B4", .5), ("C5", .5), ("D5", .5), ("F5", .5), ("r", 2)],
]
M22_C_RESP = [
	[("r", 2), ("Eb6", .5), ("C6", .5), ("G5", .5), ("r", .5)],
	[("r", 2), ("F6", .5), ("D6", .5), ("Ab5", .5), ("r", .5)],
	[("r", 2), ("G6", .5), ("Eb6", .5), ("C6", .5), ("r", .5)],
	[("r", 2), ("Ab6", .5), ("F6", .5), ("D6", .5), ("B5", .5)],
]
M22_C_BUILD = [
	[("C5", .5), ("Eb5", .5), ("Ab5", .5), ("Eb5", .5), ("C5", .5), ("Eb5", .5), ("Ab5", .5), ("C6", .5)],
	[("Db5", .5), ("F5", .5), ("Ab5", .5), ("F5", .5), ("Db6", .5), ("C6", .5), ("Bb5", .5), ("Ab5", .5)],
]
M22_PICKUP = [("r", 2), ("F5", .5), ("D5", .5), ("Ab4", .5), ("B4", .5)]     # G7(b9) falling onto the leading tone
M22_GALOP = [(0.0, 1.0, "bass", 1.0), (2.0, 1.0, "fifth_lo", 0.8)]
M22_XYL_B = [(0.0, "root", 0.9), (0.5, "fifth", 0.5), (1.0, "top", 0.65), (1.5, "fifth", 0.5), (2.0, "third_hi", 0.7),
	(2.5, "top", 0.5), (3.0, "fifth", 0.6), (3.5, "third", 0.5)]


def m22_harvest_trouble(rng):
	s = Score(160, 4, 50, rng, loop=True)
	I, A, B, C, R = 0, 2, 18, 34, 42
	prog = M22_INTRO + M22_A1 + M22_A2 + M22_B1 + M22_B2 + M22_C + M22_A3
	assert len(prog) == 50
	spic = dict(attack=0.008, release=0.07, bright=2.0, vib=3.0, width=0.35)       # spiccato section
	stab = dict(attack=0.008, release=0.07, bright=1.5)

	def lead(bar, notes, vel, cellos=0.0):
		"""The A tune: spiccato strings + hard-mallet marimba in unison (+ cellos an octave down)."""
		seq(s, "lead", V.muted_strings, bar, notes, vel, -0.15, legato=0.72, **spic)
		seq(s, "xyl", V.marimba, bar, notes, vel * 0.8, 0.25, hard=0.85)
		if cellos:
			seq(s, "cel_lo", V.muted_strings, bar, notes, cellos, -0.25, transpose=-12, legato=0.72, attack=0.01,
				release=0.08, bright=1.4, vib=3.0)

	def groove(prog_part, bar, pah_vel=0.32, bass_vel=0.78):
		bassline(s, "pizz", V.pizz, prog_part, bar, M22_GALOP, 36, bass_vel)
		chords_on(s, "pah", V.muted_strings, prog_part, bar, (1.0, 3.0), 0.3, 55, 67, pah_vel, 0.1, **stab)

	# --- intro: the galop starts on its own, the marimba tumbles in
	groove(M22_INTRO, I, 0.3, 0.8)
	seq(s, "xyl", V.marimba, I + 1, M22_PICKUP, 0.55, 0.25, hard=0.85)

	# --- A (a a'): the scamper
	lead(A, flat(M22_MEL_A1 + M22_MEL_A2, 4), 0.62)
	groove(M22_A1 + M22_A2, A)
	seq(s, "xyl", V.marimba, A + 15, [("r", 2), ("Bb5", .5), ("Ab5", .5), ("G5", .5), ("F5", .5)], 0.5, 0.25, hard=0.8)
	pads(s, "str", V.muted_strings, M22_A2[4:], A + 12, 55, 67, 0.2, 0.0, attack=0.4, release=0.4)

	# --- B (b b'): the cellos sing, the marimba scampers in eighths; violins take the tune two octaves up in b'
	seq(s, "cel_lo", V.muted_strings, B, flat(M22_MEL_B1 + M22_MEL_B2, 4), 0.62, -0.2, legato=0.98, attack=0.07,
		release=0.3, bright=1.3, vib=8.0)
	seq(s, "vln", V.muted_strings, B + 8, flat(M22_MEL_B2, 4), 0.46, 0.15, transpose=24, legato=0.98, attack=0.1,
		release=0.35, bright=1.1, vib=9.0)
	arps(s, "xyl", V.marimba, M22_B1, B, M22_XYL_B, 67, 0.34, 0.3, length=0.5, hard=0.7)
	arps(s, "xyl", V.marimba, M22_B2, B + 8, M22_XYL_B, 67, 0.26, 0.3, length=0.5, hard=0.6)
	groove(M22_B1 + M22_B2, B, 0.24, 0.7)

	# --- C: bridge over a creeping G pedal, then the D-flat build and stop-time
	seq(s, "lead", V.muted_strings, C, flat(M22_C_CALL, 4), 0.66, -0.15, legato=0.72, **spic)
	seq(s, "xyl", V.marimba, C, flat(M22_C_RESP, 4), 0.6, 0.3, hard=0.9)
	for i in range(4):
		for k, nm in enumerate(["G2", "G2", "G2", "Ab2", "G2", "G2", "G2", "Ab2"]):
			s.note("pizz", V.pizz, nm, C + i, 0.5 * k, 0.45, 0.62 if k in (0, 4) else 0.4, 0.0, human=0.003)
	pads(s, "str", V.muted_strings, M22_C[:4], C, 55, 67, 0.22, 0.0, attack=0.5, release=0.5)
	s.note("bell", V.church_bell, "G3", C, 0.0, 4.0, 0.45, -0.2, human=0.0, t60=4.0, bright=0.4)
	seq(s, "lead", V.muted_strings, C + 4, flat(M22_C_BUILD, 4), 0.7, -0.15, legato=0.72, **spic)
	seq(s, "xyl", V.marimba, C + 4, flat(M22_C_BUILD, 4), 0.5, 0.25, hard=0.85)
	seq(s, "cel_lo", V.muted_strings, C + 4, [("C3", 4), ("Db3", 2), ("F3", 2)], 0.6, -0.2, legato=1.0, attack=0.15,
		release=0.3, bright=1.2)
	groove(M22_C[4:6], C + 4, 0.36, 0.82)
	for i in range(16):                                   # timpani roll on the chord roots, growing
		bar = C + 4 + i // 8
		s.note("timp", V.timpani, "Ab2" if i < 8 else "Db2", bar, 0.5 * (i % 8), 0.5, 0.25 + 0.03 * i, 0.0,
			human=0.002, t60=1.0)
	for bar, hits in ((C + 6, (0.0, 1.5)), (C + 7, (0.0,))):   # stop-time on G7(b9)
		for b in hits:
			for nm in ("G2", "G3"):
				s.note("pizz", V.pizz, nm, bar, b, 1.0, 0.7, 0.0, human=0.0)
			for nm in ("B3", "D4", "F4", "Ab4"):
				s.note("pah", V.muted_strings, nm, bar, b, 0.45, 0.46, 0.0, human=0.0, attack=0.006, release=0.1, bright=1.6)
			s.note("drum", V.frame_drum, 60.0, bar, b, 1.0, 0.7, 0.0, human=0.0)
			s.note("timp", V.timpani, "G2", bar, b, 1.0, 0.55, 0.0, human=0.0)
	for b in (2.5, 3.0, 3.5):                               # ...and in the silence, three little ticks
		s.note("perc", V.tick, "Ab5", C + 6, b, 0.2, 0.3, 0.5, human=0.0, t60=0.3)
	seq(s, "xyl", V.marimba, C + 7, M22_PICKUP, 0.6, 0.25, hard=0.9)

	# --- A'': tutti, the cellos double the scamper an octave down; turnaround back to the intro
	lead(R, flat(M22_MEL_A3, 4), 0.68, cellos=0.36)
	groove(M22_A3, R, 0.36, 0.84)
	pads(s, "str", V.muted_strings, M22_A3, R, 60, 72, 0.16, 0.0, attack=0.4, release=0.4)

	# --- percussion map
	for bar in range(50):
		if C + 6 <= bar <= C + 7:
			continue
		sect = "I" if bar < A else "A" if bar < B else "B" if bar < C else "C1" if bar < C + 4 else "C2" if bar < R else "R"
		if sect in ("I", "A", "R"):
			s.note("drum", V.frame_drum, 64.0, bar, 0.0, 1.0, 0.62 if sect != "R" else 0.7, 0.0, human=0.002)
			s.note("drum", V.frame_drum, 78.0, bar, 2.0, 1.0, 0.45, 0.1, human=0.002)
			for b in (1.0, 3.0):
				s.note("perc", V.clack, 1100.0, bar, b, 0.5, 0.4, -0.3)
			for b in (0.5, 1.5, 2.5, 3.5):
				s.note("perc", V.brush, 440.0, bar, b, 0.5, 0.2 if sect != "R" else 0.24, 0.25)
			if bar % 2 == 1:
				s.note("perc", M.woodblock, 760.0, bar, 3.5, 0.5, 0.28, 0.35)
		elif sect == "B":
			s.note("drum", V.frame_drum, 64.0, bar, 0.0, 1.0, 0.45, 0.0, human=0.002)
			for b in (1.0, 3.0):
				s.note("perc", V.clack, 1100.0, bar, b, 0.5, 0.26, -0.3)
				s.note("perc", V.brush, 440.0, bar, b, 0.5, 0.18, 0.25)
		elif sect == "C1":
			s.note("drum", V.frame_drum, 64.0, bar, 0.0, 1.0, 0.5 + 0.04 * (bar - C), 0.0, human=0.002)
			for b in (1.0, 3.0):
				s.note("perc", V.tick, "D6" if b == 1.0 else "G5", bar, b, 0.2, 0.22, 0.5 if b == 1.0 else -0.5,
					human=0.002, t60=0.3)
		else:                                               # C2: the build, a drum on every beat
			for b in (0.0, 1.0, 2.0, 3.0):
				s.note("drum", V.frame_drum, 64.0 if b % 2 == 0 else 78.0, bar, b, 1.0, 0.45 + 0.03 * (bar - C - 4) * 4 +
					0.03 * b, 0.0, human=0.002)
			for b in (0.5, 1.5, 2.5, 3.5):
				s.note("perc", V.brush, 440.0, bar, b, 0.5, 0.25, 0.25)

	ir = S.hall(rng, 1.6, brightness=7000)
	levels = {"lead": (0.0, 0.2), "xyl": (-4.0, 0.2), "cel_lo": (-2.0, 0.25), "vln": (-3.0, 0.3), "pizz": (-3.0, 0.12),
		"pah": (-2.0, 0.18), "str": (-10.0, 0.3), "perc": (-5.5, 0.18), "drum": (-4.5, 0.15), "timp": (-6.0, 0.2),
		"bell": (-8.0, 0.5)}
	lay = s.render(levels, ir, bus_fx={"xyl": shelf(-3.0, 4000.0), "perc": shelf(-5.0, 5000.0)})
	secs = [(I, "intro"), (A, "A"), (B, "B"), (C, "C bridge"), (C + 4, "C2 build+stop"), (R, "A''")]
	return s, lay, secs


# ==========================================================================================
# m23 "Under the Bellhouse" - Hushed Works (F minor / Phrygian, 4/4 at 50, LOOP, quiet)
# ==========================================================================================
# Form: A(12 bars: drone, low bell motif C-Ab-F-G with long silences between strokes)
#       B(12 bars: harmony finally moves - Bbm7, Gbmaj7, Db, C7 - and a slow glass melody,
#       sparse gear ticks) A'(8 bars: the bell motif returns, thinning into the loop).
# 32 bars = 153.6 s. Everything leaves space: no continuous rhythm, no high-mid clutter.

M23_PROG = (["Fmadd9"] * 4 + ["Dbmaj7/F"] * 4 + ["Fm"] * 2 + ["Gb/F"] * 2 +
	["Bbm7"] * 2 + ["Gbmaj7"] * 2 + ["Db"] * 2 + ["C7sus4", "C7", "Dbmaj7", "Dbmaj7", "Bbm7", "C7sus4"] +
	["Fmadd9"] * 4 + ["Gb/F"] * 2 + ["Fm"] * 2)
M23_GLASS = [
	[("F5", 2), ("Db5", 2)], [("C5", 3), ("r", 1)], [("Bb4", 2), ("Db5", 2)], [("F5", 4)],
	[("Ab5", 2), ("F5", 1), ("Eb5", 1)], [("Db5", 3), ("r", 1)], [("F5", 2), ("G5", 2)], [("E5", 4)],
	[("Ab5", 2), ("C6", 2)], [("Bb5", 1), ("Ab5", 1), ("F5", 2)], [("Db5", 4)], [("C5", 2), ("r", 2)],
]


def m23_under_the_bellhouse(rng):
	s = Score(50, 4, 32, rng, loop=True)
	A, B, R = 0, 12, 24
	assert len(M23_PROG) == 32

	# --- drones: bowed metal on the pedal note + muted low strings on the (slow) bass line
	for bar in range(0, 32, 4):
		s.note("metal", V.bowed_metal, "F2", bar, 0.0, 16.0 + 1.0, 0.55, 0.0, human=0.0, attack=5.0, release=6.0)
	for bar in range(12, 24, 4):
		s.note("metal", V.bowed_metal, "C3", bar, 2.0, 12.0, 0.25, 0.3, human=0.0, attack=4.0, release=5.0)
	prev = None
	i = 0
	while i < 32:
		sym = M23_PROG[i]
		j = i
		while j < 32 and M23_PROG[j] == sym:
			j += 1
		c = chord(sym)
		s.note("bass", V.muted_strings, low(c["bass"], 33), i, 0.0, (j - i) * 4 + 0.5, 0.4, 0.0, human=0.0, attack=3.0,
			release=4.0, bright=0.5, vib=4.0)
		v = voicing(sym, 53, 67, prev)
		prev = v
		for n in v:
			s.note("pad", V.house_pad, n, i, 0.0, (j - i) * 4 + 0.3, 0.3 if i < 12 or i >= 24 else 0.38, 0.0, human=0.0,
				attack=3.5, release=4.5, cutoff=850.0, detune=5.0)
		i = j

	# --- low bell motif (A): C Ab F G - five-three-one-two, left hanging
	bells_A = [(1, 0.0, "C4", 0.5), (1, 2.0, "Ab3", 0.42), (2, 0.0, "F3", 0.46), (2, 3.0, "G3", 0.36),
		(5, 0.0, "C4", 0.44), (5, 2.0, "Ab3", 0.38), (6, 0.0, "F3", 0.42), (6, 3.0, "Eb3", 0.34),
		(8, 0.0, "Ab3", 0.4), (8, 2.0, "G3", 0.36), (9, 0.0, "F3", 0.44), (10, 0.0, "Gb3", 0.3)]
	bells_R = [(25, 0.0, "C4", 0.42), (25, 2.0, "Ab3", 0.36), (26, 0.0, "F3", 0.4), (26, 3.0, "G3", 0.3),
		(28, 0.0, "Gb3", 0.3), (29, 2.0, "F3", 0.26), (31, 2.0, "C4", 0.22)]
	for bar, beat, nm, v in bells_A + bells_R:
		s.note("bell", V.church_bell, nm, bar, beat, 4.0, v, -0.25 + 0.5 * ((bar * 7) % 5) / 4.0, human=0.0, t60=7.5,
			bright=0.45)
	# a distant, higher bell answers the motif now and then
	for bar, beat, nm in ((3, 1.0, "C5"), (7, 2.0, "Ab4"), (27, 1.0, "C5")):
		s.note("bell_far", V.church_bell, nm, bar, beat, 4.0, 0.22, 0.6, human=0.0, t60=6.0, bright=0.3)

	# --- B: the glass melody (celesta + faint muted violins for sustain), sparse gear ticks
	seq(s, "glass", M.celesta, B, flat(M23_GLASS, 4), 0.46, 0.25, human=0.0)
	seq(s, "vln", V.muted_strings, B + 4, flat(M23_GLASS[4:], 4), 0.2, -0.2, attack=0.9, release=1.5, bright=1.3,
		vib=6.0, human=0.0)
	ticks = [(13, 1.0), (13, 3.0), (14, 2.0), (15, 1.0), (15, 1.5), (16, 3.0), (17, 1.0), (18, 2.0), (18, 2.5),
		(19, 0.0), (20, 1.0), (21, 3.0)]
	for k, (bar, beat) in enumerate(ticks):
		s.note("tick", V.tick, ["F6", "C6", "Db6", "Ab5"][k % 4], bar, beat, 0.2, 0.18, [-0.6, 0.5, -0.2, 0.7][k % 4],
			human=0.0, t60=0.5)
	# A': two glass fragments
	seq(s, "glass", M.celesta, R + 2, [("F5", 2), ("C5", 2), ("r", 4), ("Ab4", 4)], 0.36, 0.3, human=0.0)

	ir = S.cave(rng, 5.0, brightness=4500)
	levels = {"metal": (-9.0, 0.4), "bass": (-7.5, 0.3), "pad": (-9.0, 0.5), "bell": (-2.0, 0.6),
		"bell_far": (-8.0, 0.8), "glass": (-5.0, 0.6), "vln": (-8.0, 0.5), "tick": (-16.0, 0.6)}
	lay = s.render(levels, ir, hp=28.0, lp=11000.0)
	secs = [(A, "A drone+bell"), (B, "B glass melody"), (R, "A' bells return")]
	return s, lay, secs


# ==========================================================================================
# m24 "A Pocket of Day" - underground refuge garden (E-flat major, 4/4 at 76, ends)
# ==========================================================================================
# Form: intro(2) A(8, felt piano) A2(8, harp melody, celesta and bass join) B(8, flute over warm
# strings, touches of C7) A'(8, piano melody with harp, strings, ocarina counter-line) coda(4, the
# minor-iv sigh then home, ritardando). 38 bars, ~2 minutes.

M24_INTRO = ["Eb", "Ab/Eb"]
M24_A = ["Eb", "Ab/Eb", "Eb/G", "Ab", "Cm7", "Fm7", "Bb7sus4", "Bb7"]
M24_A2 = ["Eb", "Ab/Eb", "Eb/G", "Abmaj7", "Gm7", "Cm7", [("Fm7", 2), ("Bb7", 2)], "Eb"]
M24_B = ["Abmaj7", "Bb/Ab", "Gm7", "C7", "Fm7", "Bb7/D", [("Gm7", 2), ("Cm7", 2)], [("Fm7", 2), ("Bb7sus4", 2)]]
M24_A3 = ["Eb", "Ab/Eb", "Eb/G", "Ab", "Cm7", "Fm7", [("Ab", 2), ("Bb7", 2)], "Eb"]
M24_CODA = ["Ab", "Abm6", [("Eb/Bb", 2), ("Bb7", 2)], "Eb"]

M24_MEL_A = [
	[("Bb4", 0.5), ("Eb5", 0.5), ("G5", 2), ("F5", 0.5), ("Eb5", 0.5)], [("C6", 2), ("Bb5", 1), ("Ab5", 1)],
	[("G5", 1.5), ("F5", 0.5), ("Eb5", 1), ("Bb4", 1)], [("C5", 1), ("Eb5", 1), ("Ab5", 1.5), ("G5", 0.5)],
	[("Bb5", 2), ("G5", 1), ("Eb5", 1)], [("Ab5", 1.5), ("G5", 0.5), ("F5", 1), ("C5", 1)],
	[("Eb5", 2), ("F5", 1), ("Ab5", 1)], [("F5", 2), ("D5", 1), ("r", 1)],
]
M24_MEL_A2 = M24_MEL_A[:2] + [
	[("G5", 1.5), ("Ab5", 0.5), ("Bb5", 1), ("Eb6", 1)], [("Eb6", 1.5), ("C6", 0.5), ("Ab5", 1), ("G5", 1)],
	[("F5", 1), ("G5", 1), ("Bb5", 1.5), ("D6", 0.5)], [("Eb6", 2), ("D6", 0.5), ("C6", 0.5), ("Bb5", 1)],
	[("Ab5", 1), ("C6", 1), ("Bb5", 1), ("Ab5", 1)], [("G5", 3), ("r", 1)],
]
M24_MEL_B = [
	[("Eb5", 1), ("Ab5", 1), ("C6", 2)], [("Bb5", 1.5), ("Ab5", 0.5), ("F5", 2)], [("G5", 1), ("Bb5", 1), ("D6", 2)],
	[("C6", 1.5), ("Bb5", 0.5), ("G5", 1), ("E5", 1)], [("F5", 2), ("Ab5", 1), ("C6", 1)], [("Bb5", 1.5), ("Ab5", 0.5), ("F5", 2)],
	[("G5", 1), ("F5", 1), ("Eb5", 1), ("G5", 1)], [("Ab5", 2), ("F5", 1), ("Eb5", 0.5), ("F5", 0.5)],
]
M24_MEL_A3 = M24_MEL_A[:4] + [
	[("G5", 2), ("Bb5", 1), ("Eb6", 1)], [("Ab5", 1.5), ("G5", 0.5), ("F5", 1), ("Ab5", 1)],
	[("C6", 1), ("Eb6", 1), ("D6", 1), ("Ab5", 1)], [("G5", 3), ("r", 1)],
]
M24_MEL_CODA = [[("C6", 2), ("Bb5", 1), ("Ab5", 1)], [("Cb6", 2), ("Bb5", 1), ("F5", 1)], [("G5", 2), ("F5", 2)],
	[("Eb5", 4)]]
M24_OCA_A2 = [[("D5", 4)], [("C5", 2), ("Eb5", 2)], [("C5", 2), ("D5", 2)], [("Eb5", 4)]]    # over Gm7 Cm7 Fm7-Bb7 Eb
M24_OCA = [[("Eb5", 4)], [("Eb5", 4)], [("Bb4", 4)], [("C5", 4)], [("Eb5", 4)], [("C5", 4)], [("C5", 2), ("D5", 2)],
	[("Eb5", 4)]]
PIANO_LH = [(0.0, "bass", 0.9), (1.0, "fifth", 0.5), (1.5, "top", 0.48), (2.0, "third_hi", 0.55), (3.0, "fifth", 0.45)]
HARP_8THS = [(0.0, "root", 0.8), (0.5, "fifth", 0.55), (1.0, "top", 0.6), (1.5, "third_hi", 0.55), (2.0, "fifth_hi", 0.6),
	(2.5, "third_hi", 0.5), (3.0, "top", 0.55), (3.5, "fifth", 0.5)]


def m24_pocket_of_day(rng):
	s = Score(76, 4, 38, rng, loop=False, tempo=[(34, 37, 74, 58), (37, 38, 52, 44)], tail=12.0)
	I, A, A2, B, A3, C = 0, 2, 10, 18, 26, 34
	prog = M24_INTRO + M24_A + M24_A2 + M24_B + M24_A3 + M24_CODA
	assert len(prog) == 38

	# --- intro: harp rolls up, piano low chord, a celesta glint of daylight
	arps(s, "harp", M.harp, M24_INTRO, I, HARP_8THS, 50, 0.4, -0.3)
	arps(s, "pno_lh", V.piano, M24_INTRO, I, [(0.0, "bass", 0.8)], 43, 0.42, -0.1, to_chord_end=True)
	s.note("cel", M.celesta, "G6", 1, 2.0, 1.0, 0.3, 0.4)
	s.note("cel", M.celesta, "Bb6", 1, 2.5, 1.0, 0.26, 0.45)

	# --- A: felt piano alone (melody + broken-chord left hand, pedalled), a breath of pad
	seq(s, "pno", V.piano, A, flat(M24_MEL_A, 4), 0.6, 0.1, legato=1.1)
	arps(s, "pno_lh", V.piano, M24_A, A, PIANO_LH, 43, 0.4, -0.1, to_chord_end=True)
	pads(s, "pad", M.pad, M24_A, A, 55, 67, 0.22, 0.0, attack=1.5, release=2.0, cutoff=1000.0)

	# --- A2: the harp takes the tune, celesta shadows it, bass and pad
	seq(s, "harp_mel", M.harp, A2, flat(M24_MEL_A2, 4), 0.72, 0.2)
	seq(s, "cel", M.celesta, A2, flat(M24_MEL_A2, 4), 0.2, 0.4, transpose=12)
	arps(s, "pno_lh", V.piano, M24_A2, A2, PIANO_LH, 43, 0.36, -0.1, to_chord_end=True)
	bassline(s, "bass", M.soft_bass, M24_A2, A2, [(0.0, 1.8, "bass", 1.0), (2.0, 1.8, "fifth_lo", 0.7)], 36, 0.55)
	pads(s, "pad", M.pad, M24_A2, A2, 55, 67, 0.26, 0.0, attack=1.2, release=1.8, cutoff=1100.0)
	seq(s, "oca", M.ocarina, A2 + 4, flat(M24_OCA_A2, 4), 0.34, -0.25, legato=0.95)

	# --- B: flute sings over warm strings and flowing harp
	seq(s, "flute", M.flute, B, flat(M24_MEL_B, 4), 0.58, -0.1, legato=0.96)
	pads(s, "str", M.strings, M24_B, B, 55, 69, 0.4, 0.0, overlap=0.15, tie=True)
	arps(s, "harp", M.harp, M24_B, B, HARP_8THS, 50, 0.42, -0.3)
	bassline(s, "bass", M.soft_bass, M24_B, B, [(0.0, 1.8, "bass", 1.0), (2.0, 1.8, "bass", 0.7)], 36, 0.6)
	chords_on(s, "pno_lh", V.piano, M24_B, B, (0.0, 2.0), 1.9, 55, 67, 0.3, -0.1, human=0.006)

	# --- A': piano melody returns, fuller: harp, strings, ocarina counter-line, bass
	seq(s, "pno", V.piano, A3, flat(M24_MEL_A3, 4), 0.68, 0.1, legato=1.1)
	arps(s, "pno_lh", V.piano, M24_A3, A3, PIANO_LH, 43, 0.38, -0.1, to_chord_end=True)
	arps(s, "harp", M.harp, M24_A3, A3, HARP_8THS, 48, 0.36, -0.35)
	pads(s, "str", M.strings, M24_A3, A3, 55, 69, 0.34, 0.0, overlap=0.15, tie=True)
	seq(s, "oca", M.ocarina, A3, flat(M24_OCA, 4), 0.34, -0.25, legato=0.95)
	bassline(s, "bass", M.soft_bass, M24_A3, A3, [(0.0, 1.8, "bass", 1.0), (2.0, 1.8, "fifth_lo", 0.7)], 36, 0.6)
	for bar, nms in ((A3 + 3, ["Eb6", "G6"]), (A3 + 7, ["Bb6", "Eb7"])):
		for k, nm in enumerate(nms):
			s.note("cel", M.celesta, nm, bar, 3.0 + 0.5 * k, 1.0, 0.28, 0.4)

	# --- coda: the minor-iv sigh, then home; a slow harp roll and a last sparkle
	seq(s, "pno", V.piano, C, flat(M24_MEL_CODA, 4), 0.56, 0.1, legato=1.2)
	arps(s, "pno_lh", V.piano, M24_CODA, C, [(0.0, "bass", 0.85), (1.0, "fifth", 0.45), (2.0, "third_hi", 0.5)], 43, 0.34,
		-0.1, to_chord_end=True)
	pads(s, "str", M.strings, M24_CODA, C, 55, 69, 0.28, 0.0, overlap=0.4, tie=True)
	bassline(s, "bass", M.soft_bass, M24_CODA, C, [(0.0, 3.8, "bass", 1.0)], 36, 0.5)
	last = C + 3
	for k, nm in enumerate(["Eb3", "Bb3", "Eb4", "G4", "Bb4", "Eb5", "G5"]):
		s.note("harp", M.harp, nm, last, 0.25 + 0.14 * k, 3.5, 0.42, -0.3 + 0.1 * k, human=0.0, ring=3.0)
	s.note("cel", M.celesta, "Bb6", last, 1.5, 2.0, 0.24, 0.4, human=0.0)
	s.note("cel", M.celesta, "Eb7", last, 2.2, 2.0, 0.2, 0.45, human=0.0)

	ir = S.hall(rng, 2.4, brightness=7000)
	# review (dry per-section loudness): the B flute was 10 dB above the A piano (B -13.0 LUFS, A -24.8,
	# LRA 12.9 LU against 3-8 for the existing pieces). Flute -9 dB, piano +3.5 dB, strings -1 dB, harp
	# tune and ocarina counter-line a little under the melody.
	levels = {"pno": (5.0, 0.3), "pno_lh": (-2.0, 0.3), "harp": (-6.0, 0.3), "harp_mel": (-2.5, 0.3), "cel": (-9.0, 0.45),
		"pad": (-14.0, 0.45), "str": (-13.5, 0.4), "flute": (-14.5, 0.33), "oca": (-12.0, 0.4), "bass": (-12.0, 0.12)}
	lay = s.render(levels, ir, bus_fx={"cel": shelf(-3.0, 4500.0), "flute": shelf(-2.0, 3000.0)})
	secs = [(I, "intro"), (A, "A piano"), (A2, "A2 harp"), (B, "B flute"), (A3, "A'"), (C, "coda")]
	return s, lay, secs


# ==========================================================================================
# m26 "The Borrowed Welcome" - final boss (B minor, 4/4 at 108, three synchronised LOOP layers)
# ==========================================================================================
# The home motif's shape (rising fourth, three steps down) is sung in B minor (F# B A# G# F#),
# and answered by the SAME motif at its original title pitches (C F E D C) - a tritone away, over
# an F-major chord standing on a B pedal. Layers (identical length, sample-aligned):
#   l1  phase A: wordless choir, heartbeat pulse, low strings & bass, a music box 'memory'
#   l2  phase B: 3+3+2 pizzicato ostinato, frame drums, low bell tolls, metallic ticks
#   l3  phase C: horns in stretto canon, high strings, choir descant, timpani rolls, swells
# 48 bars = 106.7 s. A mid-range dip (2-4 kHz) is left open for gameplay cues.

M26_S1 = ["Bm", "Bm", "G", "G", "Em", "Em", "F#7sus4", "F#7", "Bm", "Bm", "Gmaj7", "C", "Em", "C", "F#7", "F#7"]
M26_S2 = ["G", "G", "Em/G", "Em", "C", "C", "F#7", "F#7", "Bm", "F/B", "F/B", "Bm", "Em", "C", "F#7", "F#7"]
M26_S3 = ["Bm", "Bm", "G", "G", "E", "E7", "F#7sus4", "F#7", "Bm", "G", "Em", "C", "Bm/F#", "C", "F#7", "F#7"]
MOTIF_B = [("F#4", 1), ("B4", 2), ("A#4", 1), ("G#4", 2), ("F#4", 2)]       # borrowed shape, B minor
MOTIF_HOME = [("C5", 1), ("F5", 2), ("E5", 1), ("D5", 2), ("C5", 2)]        # the title motif's own pitches
MOTIF_B_NAT = [("F#4", 1), ("B4", 2), ("A4", 1), ("G4", 2), ("F#4", 2)]    # natural-minor turn (over G / C bars)


def m26_borrowed_welcome(rng):
	s = Score(108, 4, 48, rng, loop=True)
	prog = M26_S1 + M26_S2 + M26_S3
	assert len(prog) == 48

	# ---------------- layer 1 (phase A base) ----------------
	for bar in range(48):                 # heartbeat: lub-dub, doubled in the middle section
		s.note("hb", M.heartbeat, 56.0, bar, 0.0, 0.3, 0.75, 0.0, human=0.0)
		s.note("hb", M.heartbeat, 50.0, bar, 0.5, 0.3, 0.55, 0.0, human=0.0)
		if 16 <= bar < 32 or bar >= 40:
			s.note("hb", M.heartbeat, 56.0, bar, 2.0, 0.3, 0.6, 0.0, human=0.0)
			s.note("hb", M.heartbeat, 50.0, bar, 2.5, 0.3, 0.45, 0.0, human=0.0)
	bassline(s, "bass", M.soft_bass, prog, 0, [(0.0, 1.9, "bass", 1.0), (2.0, 1.9, "bass", 0.8)], 35, 0.6)
	pads(s, "lowstr", V.muted_strings, prog, 0, 40, 52, 0.3, 0.0, attack=0.8, release=1.0, bright=0.7)
	# choir pad: one vowel colour per section, common tones held across chord changes
	for b, sec, vow, to in ((0, M26_S1, "oo", "oh"), (16, M26_S2, "oh", "ah"), (32, M26_S3, "ah", "oh")):
		pads(s, "choir", V.choir, sec, b, 52, 67, 0.5, 0.0, overlap=0.25, tie=True, vowel=vow, to=to, voices=3,
			attack=0.7, release=1.2)
	# the borrowed motif sung (soprano line), and its 'home' answer on a slightly wrong music box
	for bar in (0, 8, 32, 40):
		seq(s, "sop", V.choir, bar, MOTIF_B if bar != 40 else MOTIF_B_NAT, 0.62, 0.1, human=0.0, vowel="oo", to="ah",
			voices=3, attack=0.25, release=0.8)
	seq(s, "sop", V.choir, 24, MOTIF_B, 0.6, -0.1, human=0.0, vowel="oh", voices=3, attack=0.25, release=0.8)
	seq(s, "box", M.music_box, 25, MOTIF_HOME, 0.55, 0.35, human=0.0, cents=-22.0)
	seq(s, "box", M.music_box, 26, [("F5", 2), ("E5", 2), ("D5", 4)], 0.4, 0.35, human=0.0, cents=-30.0)
	seq(s, "box", M.music_box, 11, [("C6", 1), ("F6", 2), ("E6", 1)], 0.36, 0.4, human=0.0, cents=-18.0)

	# ---------------- layer 2 (phase B: rhythm & resonance) ----------------
	ost = [(0.0, "bass", 1.0), (0.5, "bass", 0.45), (1.0, "fifth", 0.55), (1.5, "bass", 0.9), (2.0, "bass8", 0.45),
		(2.5, "fifth", 0.5), (3.0, "bass", 0.9), (3.5, "third", 0.5)]
	for bar, b0, nb, sym in chord_seq(prog, 0, 4):
		t = tones_of(sym, 59)
		t["fifth"] = low((chord(sym)["root"] + 7) % 12, t["bass"] + 1)
		t["third"] = low((chord(sym)["root"] + chord(sym)["ivs"][1]) % 12, t["bass"] + 1)
		for beat, deg, vm in ost:
			s.note("ost", V.pizz, t[deg], bar, beat, 0.45, 0.62 * vm, 0.15 if beat % 1 else -0.15, human=0.003)
	for bar in range(48):                 # 3+3+2 frame drums
		for beat, f0, v in ((0.0, 66.0, 0.9), (1.5, 82.0, 0.6), (3.0, 74.0, 0.75)):
			s.note("drum", V.frame_drum, f0, bar, beat, 0.5, v, 0.0, human=0.002)
		s.note("drum", V.frame_drum, 104.0, bar, 3.5, 0.5, 0.3, 0.2, human=0.002)
		for beat in (1.0, 2.5):
			s.note("tick", V.tick, "F#6" if beat == 1.0 else "B5", bar, beat, 0.2, 0.2, 0.5 if beat == 1.0 else -0.5,
				human=0.002, t60=0.3)
	for bar in (0, 8, 16, 24, 32, 40):
		s.note("bell", V.church_bell, "B2", bar, 0.0, 4.0, 0.6, 0.0, human=0.0, t60=6.0, bright=0.5)
	for bar in (7, 15, 23, 31, 39):
		s.note("timp2", V.timpani, "F#2", bar, 0.0, 1.0, 0.6, 0.0)
		s.note("timp2", V.timpani, "F#2", bar, 2.0, 1.0, 0.5, 0.0)

	# ---------------- layer 3 (phase C: climax) ----------------
	# horn canon: borrowed motif, home answer two beats later (stretto), plus strings
	for bar in (8, 16, 24, 32, 36, 40, 44):
		seq(s, "horn", _horn, bar, MOTIF_B_NAT if bar in (16, 40, 44) else MOTIF_B, 0.62, -0.25, transpose=-12)
	for bar in (24, 32, 40):
		seq(s, "horn2", _horn, bar + 0.5, MOTIF_HOME, 0.52, 0.25, transpose=-12)
	for bar in (36, 44):
		seq(s, "hstr", M.strings, bar, MOTIF_B if bar == 36 else MOTIF_B_NAT, 0.5, 0.2, transpose=12, human=0.0)
	pads(s, "hstr", M.strings, prog, 0, 62, 74, 0.32, 0.0, overlap=0.1, tie=True)
	for bar, b0, nb, sym in chord_seq(M26_S3, 32, 4):        # choir descant 'ah' in the last section
		t = tones_of(sym, 71)
		s.note("desc", V.choir, t["root"] if bar % 2 == 0 else t["fifth"], bar, b0, nb, 0.5, 0.0, human=0.0, vowel="ah",
			voices=4, attack=0.6, release=1.0)
	for bar in (6, 7, 14, 15, 22, 23, 30, 31, 38, 39, 46, 47):  # timpani rolls into each section
		for k in range(8):
			s.note("timp", V.timpani, "F#2", bar, k * 0.5, 0.5, 0.25 + 0.05 * k + (0.1 if bar % 2 else 0.0), 0.0,
				human=0.002, t60=1.0)
	for bar in (15, 31, 47):
		s.note("swell", M.swell, 1000.0, bar, 0.0, 4.0, 0.8, 0.0, human=0.0)
	for bar in (0, 16, 32):
		s.note("timp", V.timpani, "B1", bar, 0.0, 1.0, 0.95, 0.0, human=0.0)

	ir = S.hall(rng, 2.6, brightness=5500)
	levels = {
		"hb": (-9.0, 0.1, "l1"), "bass": (-12.0, 0.1, "l1"), "lowstr": (-7.0, 0.25, "l1"), "choir": (-1.0, 0.4, "l1"),
		"sop": (1.0, 0.45, "l1"), "box": (-7.0, 0.5, "l1"),
		"ost": (-6.0, 0.15, "l2"), "drum": (-8.0, 0.2, "l2"), "tick": (-17.0, 0.4, "l2"), "bell": (-8.0, 0.5, "l2"),
		"timp2": (-9.0, 0.25, "l2"),
		"horn": (-11.0, 0.3, "l3"), "horn2": (-12.0, 0.3, "l3"), "hstr": (-16.5, 0.35, "l3"), "desc": (-11.5, 0.45, "l3"),
		"timp": (-13.5, 0.25, "l3"), "swell": (-23.0, 0.4, "l3")}

	def mid_dip(x):
		"""Leaves 1-4 kHz room for attack tells / companion cues; trims the low-end build-up."""
		y = F.peak_eq(F.peak_eq(x, 2800.0, -4.0, 0.7), 1400.0, -1.5, 0.8)
		return F.rbj(y, "lowshelf", 110.0, 0.7, -3.0)
	lay = s.render(levels, ir, eq=mid_dip)
	secs = [(0, "S1"), (16, "S2 (canon at the tritone)"), (32, "S3 stretto")]
	return s, lay, secs


# ==========================================================================================
# Cue table, rendering, verification, manifest
# ==========================================================================================

CUES = {
	"m20": {"title": "The Empty Waltz", "fn": m20_empty_waltz, "files": {"main": "m20_the_empty_waltz.ogg"}, "loop": False,
		"target": -17.5, "ref": "haven/night", "bpm": "96 (ritardando to 46 in the last 4 bars)", "key": "A minor",
		"meter": "3/4", "location": "Moonveil Manor exploration (hallways, ballroom)",
		"instruments": "harpsichord-like (8' + 4' and lute stop, KS quill strings), celesta, muted low strings (con sordino "
			"section + cello counter-line), pizzicato bass, soft clock ticks (interlude)",
		"motif": "Head motif: rest on the downbeat, then 5th-octave (E5 A5) falling through the leading tone G#5-F5-E5: "
			"the waltz whose melody always enters after the downbeat (a missing partner). Those five pitches are the "
			"house 'For Krystal' shape in minor (5-1-7-b6-5, the same degrees as music_boss's A D C# Bb A), used "
			"deliberately as a family link but in a new rhythm, register and timbre; the rest of the tune is new. "
			"Lament bass A-G#-G-F(#). B section is a new flowing tune in C major rising to E6. Manor timbre "
			"(harpsichord/celesta/muted strings) is shared with m21."},
	"m21": {"title": "A Midnight Invitation", "fn": m21_midnight_invitation,
		"files": {"main": "m21_a_midnight_invitation.ogg"}, "loop": True, "target": -17.6, "ref": "boss", "bpm": "144",
		"key": "E minor (Waltz II in G major, middle section in G minor)", "meter": "3/4",
		"location": "Count Velour encounter (boss); MIDNIGHT section usable as phase-2 contrast",
		"instruments": "velvet fiddle (solo bowed string), harpsichord (flourishes, Waltz II tune, running 8ths), muted "
			"string 'pah-pah', pizzicato bass, timpani, low bell (12 midnight strokes), frame drum, horn (from the existing "
			"boss piece), celesta, cymbal-air swell",
		"motif": "Waltz I 'invitation': B4 leaps a minor sixth to G5 then leans down chromatically F#-E-D#. Waltz II: "
			"charming G-major tune with a C minor-6 shadow. MIDNIGHT: G-minor half-note theme in hemiola (2 against 3) "
			"in low strings, then fiddle, with twelve bell strokes; B3 climax reuses the minor-sixth leap on Eb/Dm/Cm."},
	"m22": {"title": "Harvest Trouble", "fn": m22_harvest_trouble, "files": {"main": "m22_harvest_trouble.ogg"},
		"loop": True, "target": -17.6, "ref": "boss", "bpm": "160", "key": "C minor (B section E-flat major, bridge on "
		"a G pedal with a D-flat Neapolitan build)", "meter": "4/4 (straight-eighth galop)",
		"location": "Ordinary Chapter Two combat (orchard, commons, manor grounds)",
		"instruments": "spiccato muted strings doubled by a hard-mallet marimba (lead), cellos (B tune, A'' doubling), "
			"violins (B' tune two octaves up), pizzicato bass, muted-string stabs on 2 and 4, bones/clacks, brush, "
			"woodblock, frame drum, metal ticks, timpani and one low bell (bridge)",
		"motif": "Scamper: C5-Eb5-G5-Eb5-C5 . G4 tumbling back, then a chromatic creep Ab4-B4-C5-D5-Eb5 and a b9 "
			"(Ab over G7); the answer turns to a D-flat (Neapolitan) bar. B: a legato cello song in E-flat with a G-major "
			"'trouble' chord. Bridge: strings creep G-Ab-G-F# / Ab-Bb-Ab-G ... on a G-G-G-Ab pizzicato pedal while the "
			"marimba answers from above, a D-flat build with timpani roll, stop-time G7(b9) hits and ticks in the "
			"silence. Review rewrite: the first version (6/8 C-minor reed jig over marimba, ~68 s) shared meter, pulse, "
			"length and palette with m10 'Thorns in the Path' (6/8 E-minor oboe/bassoon over marimba, 67 s); this one "
			"is a 4/4 galop at 160 with a string/marimba lead. Distinct from the bosses: no toms or ostinato pluck, no "
			"Krystal motif, not 3/4."},
	"m23": {"title": "Under the Bellhouse", "fn": m23_under_the_bellhouse,
		"files": {"main": "m23_under_the_bellhouse.ogg"}, "loop": True, "target": -19.4, "ref": "night",
		"bpm": "50 (free-feeling, no pulse)", "key": "F minor / Phrygian (Gb over F)", "meter": "4/4 (no audible meter)",
		"location": "Hushed Works (under the bellhouse) - leaves room for environmental clues",
		"instruments": "bowed metal drone, muted low strings, dark pad, cast low bells (hum/prime/tierce partials), far "
			"bells, glass celesta, faint muted violins, sparse gear ticks; cave reverb",
		"motif": "Low bell figure C4-Ab3-F3-G3 (5-3-1-2, left hanging) with long silences between strokes; B section "
			"moves the harmony (Bbm7 Gbmaj7 Db C7sus4-C7 Dbmaj7) under a slow glass melody F5-Db5-C5 ... E5 (the one "
			"leading-tone moment), then the bells return and thin out into the loop."},
	"m24": {"title": "A Pocket of Day", "fn": m24_pocket_of_day, "files": {"main": "m24_a_pocket_of_day.ogg"},
		"loop": False, "target": -17.4, "ref": "haven/night", "bpm": "76 (ritardando to 44 in the coda)",
		"key": "E-flat major", "meter": "4/4", "location": "Underground refuge garden (safe, relief)",
		"instruments": "felt piano (inharmonic partials, pedalled left hand), harp, celesta, flute, ocarina, warm "
			"strings, pad, soft bass",
		"motif": "Piano song: Bb4-Eb5-G5 rising sixth that settles G-F-Eb, answered from C6; harp sings it again "
			"reaching Eb6; B section flute tune over Abmaj7-Bb/Ab-Gm7-C7; coda sighs through Ab minor-6 (Cb) before "
			"home. Original; no shared motif requested."},
	"m26": {"title": "The Borrowed Welcome", "fn": m26_borrowed_welcome,
		"files": {"l1": "m26_borrowed_welcome_l1.ogg", "l2": "m26_borrowed_welcome_l2.ogg",
			"l3": "m26_borrowed_welcome_l3.ogg"}, "loop": True, "target": -19.0, "ref": "boss", "bpm": "108",
		"key": "B minor (tritone from the title's F major)", "meter": "4/4", "location": "Final Choir encounter (final "
		"boss): l1 = phase A (plays alone), +l2 = phase B, +l3 = phase C",
		"instruments": "l1: wordless formant choir, music box (detuned), heartbeat, muted low strings, soft bass; "
			"l2: pizzicato 3+3+2 ostinato, frame drums, low bell, metal ticks, timpani; l3: horns (existing boss "
			"horn voice) in canon, high strings, choir descant, timpani rolls, air swells",
		"motif": "Borrows the 'For Krystal' motif SHAPE (rising 4th + three steps down) in B minor: F#4 B4 A#4 G#4 F#4 "
			"(natural-minor turn F# B A G F# over G/C bars), and sets it against the motif at its original title pitches "
			"C5 F5 E5 D5 C5 (music box ~20-30 cents flat; second horn two beats behind the first = stretto canon) a "
			"tritone apart, over F/B - familiar intervals as unsettling counterpoint. Choir is wordless (formant vowels)."},
}


def _combos(keys):
	if keys == ["l1", "l2", "l3"]:
		return [["l1"], ["l2"], ["l3"], ["l1", "l2"], ["l1", "l3"], ["l2", "l3"], ["l1", "l2", "l3"]]
	return [keys]


def render_cue(cue_id: str, out_dir: str = MUSIC_OUT) -> dict:
	"""Renders one cue to OGG (all its layers). Returns metadata for verification/manifest."""
	spec = CUES[cue_id]
	t0 = time.time()
	rng = rng_for("music2:" + cue_id)
	s, layers, secs = spec["fn"](rng)
	keys = sorted(layers)
	ref_keys = ["l1"] if cue_id == "m26" else keys
	layers, info = master(layers, spec["loop"], spec["target"], ref_keys=ref_keys, combos=_combos(keys))
	os.makedirs(out_dir, exist_ok=True)
	paths = {}
	for k in keys:
		p = os.path.join(out_dir, spec["files"][k])
		write_ogg(p, layers[k])
		paths[k] = p
	# re-check after lossy encoding; if Vorbis pushed a peak over -1 dBTP, scale everything down a bit
	for attempt in range(3):
		dec = {k: read_ogg(p) for k, p in paths.items()}
		tp = max(MM.true_peak_db(sum(dec[k] for k in c)) for c in _combos(keys))
		if tp <= -1.05:
			break
		g = db(-1.15 - tp)
		for k in keys:
			layers[k] = layers[k] * g
			write_ogg(paths[k], layers[k])
	sec_times = [(round(s.bar_time(b), 2), name) for b, name in secs]
	bpm0 = 60.0 / float(s.spb[0])
	grid = {"bpm": round(bpm0, 3), "beats_per_bar": s.bpb, "bars": s.bars, "bar_s": round(s.bpb * 60.0 / bpm0, 6),
		"section_start_bars": [b for b, _ in secs], "pass_s": round(s.length, 3),
		"tempo_changes": "none" if np.allclose(s.spb, s.spb[0]) else "ritardando in the last bars (see bpm)"}
	return {"id": cue_id, "paths": paths, "n": len(next(iter(layers.values()))), "sections": sec_times,
		"bar_times": [s.bar_time(b) for b in range(s.bars)], "grid": grid,
		"master": info, "render_s": round(time.time() - t0, 1), "loop_len_s": s.length}


def _render_job(args):
	cue_id, out_dir = args
	return render_cue(cue_id, out_dir)


def render_all(out_dir: str = MUSIC_OUT, jobs: int = 1, only=None) -> list:
	"""Renders every cue of this group into out_dir (OGG Vorbis 44.1 kHz stereo) and returns metadata
	(paths, section times, mastering info). jobs > 1 uses a process pool - only call it that way from
	a __main__-guarded script (Windows spawns workers by re-importing the caller)."""
	ids = [c for c in CUES if not only or c in only]
	if jobs and jobs > 1:
		from concurrent.futures import ProcessPoolExecutor
		with ProcessPoolExecutor(max_workers=min(jobs, len(ids))) as ex:
			return list(ex.map(_render_job, [(c, out_dir) for c in ids]))
	return [render_cue(c, out_dir) for c in ids]


# ------------------------------------------------------------------------------------------
# Verification
# ------------------------------------------------------------------------------------------

def _section_string(secs, total):
	parts = []
	for i, (t, name) in enumerate(secs):
		t1 = secs[i + 1][0] if i + 1 < len(secs) else total
		parts.append("%s(%.1f-%.1fs)" % (name, t, t1))
	return " ".join(parts)


def verify(results: list) -> list:
	"""Decodes every OGG and measures it. Returns manifest rows; prints a report."""
	rows = []
	for r in results:
		spec = CUES[r["id"]]
		dec = {k: read_ogg(p) for k, p in r["paths"].items()}
		keys = sorted(dec)
		lens = {k: len(v) for k, v in dec.items()}
		sec_marks = [(t, n) for t, n in r["sections"]]
		for k, x in dec.items():                 # qa/tmp/music2/<cue>.png (layers: <cue>_l1.png ...)
			name = r["id"] if len(dec) == 1 else "%s_%s" % (r["id"], k)
			MM.spectrogram_png(x, os.path.join(QA_OUT, name + ".png"), os.path.basename(r["paths"][k]), sec_marks)
		if len(dec) > 1:
			MM.spectrogram_png(sum(dec.values()), os.path.join(QA_OUT, r["id"] + ".png"), r["id"] + " l1+l2+l3 (all layers)",
				sec_marks)
		combos = _combos(keys)
		meas = {}
		for c in combos:
			x = sum(dec[k] for k in c)
			m = {"lufs": round(MM.integrated_lufs(x), 2), "tp": round(MM.true_peak_db(x), 2),
				"sp": round(MM.sample_peak_db(x), 2)}
			st = MM.short_term_lufs(x)
			m["st_range"] = (round(float(np.percentile(st, 5)), 1), round(float(np.percentile(st, 95)), 1))
			m["gaps"] = MM.silence_gaps(x)
			m["bands"] = MM.band_balance(x)
			m["lra"] = round(_lra(x), 1)
			m["dc"] = [round(float(v), 6) for v in np.mean(x, axis=0)]
			if spec["loop"]:
				m["seam"] = MM.seam_report(x)
				m["seam"].update(MM.seam_vs_downbeats(x, r["bar_times"]))
			meas["+".join(c)] = m
		for k in keys:
			x = dec[k]
			rows.append({"layer": k, "file": os.path.basename(r["paths"][k]), "frames": lens[k], "dur": lens[k] / SR,
				"single": meas.get(k)})
		r["measure"] = meas
		r["lens"] = lens
		total = lens[keys[0]] / SR
		marks = list(r["sections"]) + [(total, "end")]
		sec_l = {}
		for c in (combos if len(keys) == 1 else [["l1"], keys]):
			x = sum(dec[k] for k in c)
			sec_l["+".join(c)] = {"%s %.1f-%.1fs" % (n, a, b): round(MM.integrated_lufs(x[int(a * SR):int(b * SR)]), 1)
				for (a, n), (b, _) in zip(marks[:-1], marks[1:])}
		r["section_lufs"] = sec_l if len(keys) > 1 else sec_l[keys[0]]
		print("=== %s %s  render %.1fs  master %s" % (r["id"], spec["title"], r["render_s"],
			{k: round(v, 2) for k, v in r["master"].items()}))
		print("    frames %s  (%.2f s)  sections: %s" % (lens, list(lens.values())[0] / SR,
			_section_string(r["sections"], list(lens.values())[0] / SR)))
		for name, m in meas.items():
			line = "    [%s] I=%.2f LUFS  TP=%.2f dBTP  SP=%.2f  LRA=%.1f  ST5-95%%=%s  gaps>3s=%s  dc=%s" % (name, m["lufs"],
				m["tp"], m["sp"], m["lra"], m["st_range"], m["gaps"], m["dc"])
			if "seam" in m:
				sm = m["seam"]
				line += "\n        seam: jump %.5f (x%.2f of p99.9 step, slope x%.2f)  level end/start %.1f/%.1f dB " \
					"(diff %.2f; file max 50ms step %.1f)  HF at seam vs loudest other downbeat x%.2f" % (sm["jump"],
						sm["jump_ratio"], sm["seam_d2_ratio"], sm["level_end_db"], sm["level_start_db"], sm["level_diff_db"],
						sm["level_step_max_db"], sm["seam_vs_downbeat_max"])
			line += "\n        bands %s" % m["bands"]
			print(line)
		print("    section loudness %s" % r["section_lufs"])
	return results


def _seam_row(sm: dict) -> dict:
	return {"sample_jump_vs_p99_9_step": round(sm["jump_ratio"], 3), "slope_change_vs_p99_9": round(sm["seam_d2_ratio"], 3),
		"level_end_db": round(sm["level_end_db"], 1), "level_start_db": round(sm["level_start_db"], 1),
		"hf_at_seam_vs_loudest_other_downbeat": round(sm["seam_vs_downbeat_max"], 3),
		"verdict": "seamless" if sm["jump_ratio"] < 1.0 and sm["seam_d2_ratio"] < 1.5 and sm["seam_vs_downbeat_max"] <= 1.15
		else "check",
		"criteria": "sample jump and slope change across the seam below the file's own 99.9th-percentile steps (x1.0 / "
			"x1.5); 2 kHz+ transient at the seam no more than 1.15x the loudest other bar downbeat (the loop start is a "
			"written downbeat)"}


_REVIEW_COMMON = ("Independent review 2026-09-27 (note data, measurements and spectrograms only; nobody has listened): "
	"generator code read; loudness / true peak re-measured with manor_meter (calibrated: EBU 3341 1 kHz stereo sine "
	"-23.0 / -33.0 dBFS read -22.99 / -32.99 LUFS) and cross-checked with ffmpeg ebur128; DC, >8 kHz energy, silences, "
	"loop seams (sample jump, slope change, 20 ms spectral flux at the seam vs every bar line) and per-section "
	"loudness checked. ")
REVIEW = {
	"m20": _REVIEW_COMMON + "Changed: the A celesta tune was 8 dB above everything else and the B / A' harpsichord tune "
		"sat level with the pizzicato bass (sections A -14.1, B -21.7 LUFS; LRA 9.9 LU vs 3-8 for the existing pieces). "
		"Celesta tune -5.5 dB on its own bus, other celesta -3 dB, harpsichord tune +5 dB; whole-mix -3 dB shelf "
		"above 5.5 kHz and a 12 kHz low-pass (>8 kHz share now level with music_haven; 4-8 kHz stays ~8 dB above it "
		"- that is the harpsichord the brief asks for). Manifest motif note corrected: the head IS the house motif "
		"shape in minor (it had said 'no melodic quotation').",
	"m21": _REVIEW_COMMON + "Changed: Waltz II measured -25.4 LUFS against -17.7 for Waltz I (the harpsichord tune sat "
		"5 dB under the pizzicato bass) - a 20-second hole in a boss fight - and the MIDNIGHT entry was -22.9. Waltz II "
		"tune +8.5 dB on its own bus, a soft muted-string bed, and the fiddle shadowing the second half an octave "
		"below; MIDNIGHT B1 theme +4.5 dB. Both additions use their own seeds, so every other note is unchanged.",
	"m22": _REVIEW_COMMON + "Rewritten: the first version (C-minor 6/8 reed jig over marimba, dotted quarter 112, "
		"68.6 s) matched m10 'Thorns in the Path' (E-minor 6/8 oboe/bassoon over marimba, dotted quarter 100, 67.2 s) "
		"in meter, pulse, length and palette although the brief requires m22 to be distinct from m10. New: 4/4 "
		"straight-eighth galop at 160, spiccato strings + hard-mallet marimba lead, cello B tune, same key, same "
		"E-flat contrast and G-pedal bridge idea. Melody strong-beat tones checked against the chords (remaining "
		"non-chord tones are passing notes or the deliberate b9).",
	"m23": _REVIEW_COMMON + "No change: sparse, quiet (-19.4 LUFS, LRA ~4), bell/metal ambience with slow harmony; "
		"bass-heavy by design (drone below 120 Hz), almost nothing above 4 kHz, so environmental cues have room.",
	"m24": _REVIEW_COMMON + "Changed: the B flute was 10 dB above the A piano (B -13.0, A -24.8 LUFS; LRA 12.9 LU). "
		"Flute -9 dB, piano +3.5 dB, strings -1 dB, harp tune -1.5 dB, ocarina counter-line -2 dB: the piece now "
		"builds from the piano solo to the A' reprise instead of jumping at the flute.",
	"m26": _REVIEW_COMMON + "No change: layers sample-identical in length, every layer combination <= -1.5 dBTP, "
		"1-4 kHz kept low for gameplay cues (2-5 kHz share about 13 dB under music_haven). Bars 25-27 are "
		"deliberately dissonant (borrowed motif at the title pitches over F/B).",
}


def _lra(x: np.ndarray) -> float:
	"""EBU R128 loudness range (3 s windows every 0.1 s, -70 LUFS absolute and -20 LU relative gates,
	95th minus 10th percentile)."""
	st = MM.short_term_lufs(x, hop=0.1)
	st = st[st > -70.0]
	if not len(st):
		return 0.0
	st = st[st > 10.0 * np.log10(np.mean(10.0 ** (st / 10.0))) - 20.0]
	return float(np.percentile(st, 95) - np.percentile(st, 10))


def write_manifest(results: list) -> None:
	rows = []
	for r in results:
		spec = CUES[r["id"]]
		keys = sorted(r["paths"])
		dur = r["lens"][keys[0]] / SR
		base = {"title": spec["title"], "duration_s": round(dur, 2), "loop": spec["loop"], "bpm": spec["bpm"],
			"key": spec["key"], "meter": spec["meter"], "sections": _section_string(r["sections"], dur) +
			("" if spec["loop"] else " (ends; natural decay tail)"), "instruments": spec["instruments"],
			"motif_notes": spec["motif"], "location_playlist": spec["location"],
			"loudness_reference": "%s (%s)" % (spec["ref"], ", ".join("%s %.1f" % kv for kv in REF_LUFS.items())),
			"phrase_grid": r["grid"], "section_loudness_lufs": r.get("section_lufs", {}),
			"generator": "tools/audio/music2/group_manor_works.py:%s" % spec["fn"].__name__,
			"format": "OGG Vorbis 44100 Hz stereo", "verified": "analysis only - not listened",
			"review": REVIEW.get(r["id"], "")}
		if r["id"] == "m21":
			base["phase_points"] = {"midnight_start_s": r["sections"][3][0], "midnight_bars": "36-59",
				"midnight_climax_B3_s": r["sections"][5][0], "turn_back_s": r["sections"][6][0],
				"note": "single file: for a phase-2 contrast seek to midnight_start_s (bar 36, a bell stroke on a G-minor "
					"downbeat after a D7 bar) with a short crossfade; the file loops at its end into the intro"}
		if r["id"] == "m26":
			for k in keys:
				m = r["measure"][k]
				row = dict(base)
				row.update({"id": "m26_%s" % k, "file": spec["files"][k], "peak_dbfs": m["tp"], "loudness_lufs": m["lufs"],
					"loudness_range_lu": m.get("lra"), "layer": k, "frames": r["lens"][k],
					"layer_role": {"l1": "phase A base (plays alone)", "l2": "phase B: add to l1 (rhythm/resonance)",
						"l3": "phase C: add to l1+l2 (climax)"}[k],
					"combined": {n: {"loudness_lufs": v["lufs"], "true_peak_dbtp": v["tp"]} for n, v in r["measure"].items()
						if "+" in n}})
				if "seam" in m:
					row["loop_seam"] = _seam_row(m["seam"])
					if k == "l3":
						row["loop_seam"]["note"] = ("l3 on its own: the seam is the designed downbeat of bar 1 (timpani B1 + "
							"air-swell arrival), the same event as bars 17 and 33, whose 2 kHz+ peaks are within ~10 % of the "
							"seam's (noise swell varies); no sample jump or slope break")
				rows.append(row)
		else:
			m = r["measure"][keys[0]]
			row = dict(base)
			row.update({"id": r["id"], "file": spec["files"]["main"], "peak_dbfs": m["tp"], "loudness_lufs": m["lufs"],
				"loudness_range_lu": m.get("lra"), "frames": r["lens"][keys[0]]})
			if "seam" in m:
				row["loop_seam"] = _seam_row(m["seam"])
			rows.append(row)
	with open(MANIFEST, "w", encoding="utf-8") as fh:
		json.dump(rows, fh, indent=1)
	print("manifest: " + MANIFEST)


def main(argv=None) -> int:
	import argparse
	ap = argparse.ArgumentParser()
	ap.add_argument("--jobs", type=int, default=6)
	ap.add_argument("--only", default="")
	ap.add_argument("--out", default=MUSIC_OUT)
	ap.add_argument("--no-verify", action="store_true")
	a = ap.parse_args(argv)
	only = [x for x in a.only.split(",") if x]
	t0 = time.time()
	res = render_all(a.out, a.jobs, only)
	print("rendered %d cue(s) in %.1f s" % (len(res), time.time() - t0))
	if not a.no_verify:
		verify(res)
		if not only:
			write_manifest(res)
	return 0


if __name__ == "__main__":
	sys.exit(main())
