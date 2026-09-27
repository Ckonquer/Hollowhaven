"""Music helpers: note names, instruments and a tiny bar/beat sequencer with buses + reverb.

Instruments are functions (freq, dur, vel, rng) -> mono (or stereo) arrays that may ring past
`dur` (release/decay tails). The Song class places notes on named buses, then mixes them with
per-bus gain and reverb sends into a seamless loop (tails are folded back onto the start)."""
from __future__ import annotations

import re

import numpy as np

from .core import SR, ns, env_perc, env_adsr, env_points, fold_loop, circular, limiter, normalize_rms, place, db
from . import osc
from . import filters as F
from . import fm as FM
from . import physical as P
from . import space as S
from . import noise as N

_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name) -> int:
	"""'C4' -> 60, 'F#5', 'Bb3', 'Db6'. Integers pass through."""
	if isinstance(name, (int, np.integer)):
		return int(name)
	m = re.fullmatch(r"([A-G])([#b]*)(-?\d)", name.strip())
	if not m:
		raise ValueError("bad note name: %r" % name)
	n = _NOTE[m.group(1)] + m.group(2).count("#") - m.group(2).count("b")
	return 12 * (int(m.group(3)) + 1) + n


def hz(note) -> float:
	return 440.0 * 2.0 ** ((midi(note) - 69) / 12.0)


def transpose(note, semis: int) -> int:
	return midi(note) + semis


# ---------------------------------------------------------------------------------------------
# Instruments (mono unless noted)
# ---------------------------------------------------------------------------------------------

def music_box(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Comb-tine music box: pure fundamental, quick metallic 'ting' partials, soft tick."""
	t60 = float(np.clip(2.6 * (523.25 / f) ** 0.5, 0.9, 3.6))
	length = t60 * 0.85
	n = ns(length)
	t = np.arange(n) / SR
	b = 0.6 + 0.4 * vel
	parts = [(1.0, 1.0, t60), (2.0, 0.10 * b, t60 * 0.35), (3.0, 0.035 * b, t60 * 0.2),
		(4.2, 0.045 * b, 0.22), (6.27, 0.06 * b, 0.1)]
	y = np.zeros(n)
	for r, a, d in parts:
		if f * r > 12000:
			continue
		y += a * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6.28)) * np.exp(-6.9 * t / d)
	# second, very slightly detuned tine (gentle shimmer)
	y += 0.12 * np.sin(2 * np.pi * (f + 0.6) * t) * np.exp(-6.9 * t / (t60 * 0.8))
	tick = F.bandpass(rng.standard_normal(ns(0.004)), 2500, 7500, 1) * np.hanning(ns(0.004))
	y[:len(tick)] += tick * 0.05 * b
	m = ns(0.0008)
	y[:m] *= np.linspace(0, 1, m)
	fo = ns(0.08)
	y[-fo:] *= np.linspace(1, 0, fo)
	return y * vel


def celesta(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	t60 = float(np.clip(2.0 * (523.25 / f) ** 0.4, 0.8, 3.0))
	y = FM.glass(f, t60 * 0.9, t60, sparkle=0.55 + 0.3 * vel)
	fo = ns(0.06)
	y[-fo:] *= np.linspace(1, 0, fo)
	return y * vel * 0.8


def harp(f: float, dur: float, vel: float, rng: np.random.Generator, ring: float = 1.6) -> np.ndarray:
	"""Soft nylon/harp pluck (Karplus-Strong) that rings a little past the note."""
	t60 = float(np.clip(2.8 * (196.0 / f) ** 0.45, 0.7, 4.0))
	length = min(t60, dur + ring)
	y = P.ks_pluck(f, length, rng, t60=t60, bright=0.25 + 0.3 * vel, pos=rng.uniform(0.12, 0.22), soft=0.4)
	y = F.lowpass(y, 5200, 1)
	fo = ns(min(0.25, length * 0.3))
	y[-fo:] *= np.linspace(1, 0, fo) ** 2
	return y * vel


def pad(f: float, dur: float, vel: float, rng: np.random.Generator, attack: float = 0.9, release: float = 1.4,
		cutoff: float = 1300.0, detune: float = 7.0) -> np.ndarray:
	"""Warm chorused pad (stereo): three detuned saw/triangle voices, gently filtered."""
	total = dur + release
	env = env_adsr(total, attack, 0.5, 1.0, release, gate=dur)
	voices = []
	for i, (c, p) in enumerate(((-detune, -0.6), (0.0, 0.0), (detune, 0.6))):
		fr = f * 2 ** (c / 1200.0)
		fr = osc.vibrato(fr, total, rate=rng.uniform(0.15, 0.35), cents=3.0, phase0=rng.uniform(0, 1))
		v = 0.55 * osc.saw(fr, total, rng.uniform(0, 1)) + 0.45 * osc.triangle(fr, total, rng.uniform(0, 1))
		voices.append(S.pan(v, p))
	y = sum(voices) / 3.0
	fc = min(cutoff, f * 5.0)
	y = F.lowpass(y, fc, 2)
	y = F.highpass(y, 60, 1)
	return y * env[:, None] * vel


def strings(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Brighter ensemble pad with vibrato and slow bow-like attack (stereo)."""
	total = dur + 1.2
	env = env_adsr(total, 0.7, 0.8, 0.9, 1.2, gate=dur)
	y = np.zeros((ns(total), 2))
	for c, p in ((-9.0, -0.8), (-3.0, -0.3), (4.0, 0.3), (10.0, 0.8)):
		fr = osc.vibrato(f * 2 ** (c / 1200.0), total, rate=rng.uniform(4.6, 5.6), cents=9.0, delay=0.3, rise=0.6,
			phase0=rng.uniform(0, 1))
		y += S.pan(osc.saw(fr, total, rng.uniform(0, 1)), p)
	y = F.lowpass(y, min(2600.0, f * 6.0), 2)
	y = F.peak_eq(y, 1800, -3.0, 0.8)
	return y * env[:, None] * vel * 0.3


def flute(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	return FM.woodwind(f, dur, rng, "flute", vel)


def clarinet(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	return FM.woodwind(f, dur, rng, "clarinet", vel, attack=0.05, vib_cents=8.0)


def ocarina(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	return FM.woodwind(f, dur, rng, "ocarina", vel, attack=0.09, vib_cents=10.0)


def soft_bass(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Round sine bass with a touch of 2nd harmonic; plucky onset, short release."""
	total = dur + 0.25
	t = np.arange(ns(total)) / SR
	env = env_adsr(total, 0.012, 0.6, 0.55, 0.25, gate=dur)
	y = np.sin(2 * np.pi * f * t) + 0.22 * np.sin(4 * np.pi * f * t + 0.3) + 0.06 * np.sin(6 * np.pi * f * t)
	y = F.lowpass(y, 900, 2)
	return y * env * vel


def pluck_bass(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Upright-ish plucked bass (KS), damped at note end."""
	length = dur + 0.35
	y = P.ks_pluck(f, length, rng, t60=2.2, bright=0.2, pos=0.25, soft=0.9)
	y += 0.5 * np.sin(2 * np.pi * f * np.arange(len(y)) / SR) * env_perc(length, 0.004, 1.2)
	damp = env_adsr(length, 0.001, 0.1, 1.0, 0.3, gate=dur)
	return F.lowpass(y * damp, 1400, 2) * vel


def ostinato_pluck(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Tense, muted plucked-synth note for the boss ostinato (short, dark, round)."""
	length = max(dur, 0.12) + 0.2
	t = np.arange(ns(length)) / SR
	env = env_perc(length, 0.003, 0.45)
	y = 0.6 * osc.saw(f, length) + 0.4 * osc.pulse(f * 1.002, length, 0.3)
	fc = 300 + 1600 * vel * np.exp(-t / 0.07)
	y = F.sweep(y, "lowpass", fc, 0.9)
	return y * env * vel * 0.8


def tom(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Soft low drum (felt mallet): pitch-dropping body + muffled skin noise."""
	length = 0.9
	fr = osc.glide(f * 1.7, f, 0.07, "exp", total=length)
	body = np.sin(2 * np.pi * osc.phase(fr, length)) * env_perc(length, 0.002, 0.55)
	body += 0.3 * np.sin(2 * np.pi * osc.phase(fr * 1.52, length)) * env_perc(length, 0.002, 0.2)
	skin = F.lowpass(rng.standard_normal(ns(length)), 1200, 2) * env_perc(length, 0.001, 0.05)
	return F.lowpass(body + 0.35 * skin, 2500, 1) * vel


def heartbeat(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Very low soft thump (sub-ish, felt more than heard)."""
	length = 0.6
	fr = osc.glide(f * 2.0, f, 0.05, "exp", total=length)
	y = np.sin(2 * np.pi * osc.phase(fr, length)) * env_perc(length, 0.003, 0.3)
	return F.lowpass(y, 400, 2) * vel


def shaker(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	length = 0.14
	y = F.bandpass(rng.standard_normal(ns(length)), 4000, 9000, 2)
	env = env_points([(0, 0), (0.018, 1), (0.05, 0.35), (length, 0)], length)
	return y * env * vel * 0.5


def woodblock(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	y = P.modal([f, f * 2.41, f * 3.9], [1.0, 0.35, 0.12], [0.09, 0.04, 0.02], 0.2, rng)
	return F.lowpass(y, 5000, 1) * vel


def swell(f: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
	"""Soft cymbal-like air swell (reverse-shaped), for phrase transitions."""
	length = dur + 0.6
	y = F.bandpass(rng.standard_normal(ns(length)), 2500, 11000, 1)
	env = env_points([(0, 0), (dur, 1.0), (length, 0)], length, "cos") ** 2
	return y * env * vel * 0.25


# ---------------------------------------------------------------------------------------------
# Chords
# ---------------------------------------------------------------------------------------------

CHORD_SHAPES = {
	"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10],
	"sus2": [0, 2, 7], "sus4": [0, 5, 7], "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14], "6": [0, 4, 7, 9],
	"m6": [0, 3, 7, 9], "dim": [0, 3, 6], "maj9": [0, 4, 7, 11, 14], "m9": [0, 3, 7, 10, 14], "7sus4": [0, 5, 7, 10],
	"5": [0, 7], "m(b6)": [0, 3, 8],
}


def chord(root: str, quality: str = "", octave: int = 3) -> list:
	"""Chord tones as midi numbers, root in the given octave: chord('F', 'maj7', 3)."""
	r = midi(root + str(octave))
	return [r + i for i in CHORD_SHAPES[quality]]


def parse_chord(sym: str, octave: int = 3):
	"""'F', 'Am', 'Gm7', 'C/E', 'Bbmaj7' -> (tones, bass_midi)."""
	bass = None
	if "/" in sym:
		sym, b = sym.split("/")
		bass = midi(b + str(octave - 1))
	m = re.fullmatch(r"([A-G][#b]?)(.*)", sym)
	root, q = m.group(1), m.group(2)
	tones = chord(root, q, octave)
	if bass is None:
		bass = tones[0] - 12
	return tones, bass


def voice_lead(prev: list | None, tones: list, lo: int = 53, hi: int = 72) -> list:
	"""Chooses inversions of `tones` inside [lo, hi] closest to the previous voicing."""
	pcs = sorted(set(t % 12 for t in tones))
	candidates = []
	for base in range(lo, hi + 1):
		if base % 12 not in pcs:
			continue
		v = [base]
		for pc in sorted(pcs, key=lambda p: (p - base) % 12):
			if pc == base % 12:
				continue
			nxt = v[-1] + 1
			while nxt % 12 != pc:
				nxt += 1
			v.append(nxt)
		v = sorted(v)
		if v[-1] <= hi + 2:
			candidates.append(v)
	if not candidates:
		return sorted(tones)
	if prev is None:
		return min(candidates, key=lambda v: abs(np.mean(v) - (lo + hi) / 2))
	return min(candidates, key=lambda v: sum(min(abs(a - b) for b in prev) for a in v) + 0.1 * abs(len(v) - len(prev)))


# ---------------------------------------------------------------------------------------------
# Sequencer
# ---------------------------------------------------------------------------------------------

class Song:
	"""Places notes on stereo buses in bar/beat time and mixes a seamless loop.

	song = Song(bpm=76, beats_per_bar=3, bars=32, seed="music_title")
	song.note("box", music_box, "C5", bar=0, beat=0, beats=1, vel=0.8, pan=0.2)
	mix = song.mix({"box": (0.0, 0.25)}, ir)          # bus: (gain_db, reverb_send)
	"""

	def __init__(self, bpm: float, beats_per_bar: int, bars: int, rng: np.random.Generator, tail: float = 8.0,
			swing: float = 0.0):
		self.bpm = bpm
		self.bpb = beats_per_bar
		self.bars = bars
		self.spb = 60.0 / bpm
		self.length = bars * beats_per_bar * self.spb
		self.n = ns(self.length)
		self.rng = rng
		self.tail = tail
		self.swing = swing
		self.buses: dict[str, np.ndarray] = {}

	def time(self, bar: float, beat: float = 0.0) -> float:
		b = beat
		if self.swing > 0:
			frac = b - np.floor(b)
			if abs(frac - 0.5) < 1e-6:
				b = np.floor(b) + 0.5 + self.swing * 0.5
		return (bar * self.bpb + b) * self.spb

	def bus(self, name: str) -> np.ndarray:
		if name not in self.buses:
			self.buses[name] = np.zeros((self.n + ns(self.tail), 2))
		return self.buses[name]

	def add(self, bus: str, t: float, sig: np.ndarray, pan: float = 0.0, gain: float = 1.0) -> None:
		buf = self.bus(bus)
		st = S.pan(sig, pan) if sig.ndim == 1 else sig
		# wrap notes that start before 0 (humanised pickups) to the loop end
		t = t % self.length
		place(buf, st, t, gain)

	def note(self, bus: str, inst, note, bar: float, beat: float, beats: float, vel: float = 0.8, pan: float = 0.0,
			human: float = 0.006, gain: float = 1.0, **kw) -> None:
		f = hz(note) if not isinstance(note, float) else note
		t = self.time(bar, beat) + (self.rng.normal(0, human) if human > 0 else 0.0)
		dur = beats * self.spb
		v = float(np.clip(vel * (1.0 + (self.rng.normal(0, 0.06) if human > 0 else 0.0)), 0.05, 1.0))
		sig = inst(f, dur, v, self.rng, **kw)
		self.add(bus, t, sig, pan, gain)

	def mix(self, levels: dict, ir: np.ndarray, rms_db: float = -20.0, ceiling_db: float = -1.5,
			hp: float = 35.0, master_lp: float = 14000.0) -> np.ndarray:
		"""levels: bus -> (gain_db, reverb_send). Returns an exactly periodic stereo loop."""
		total = self.n + ns(self.tail)
		dry = np.zeros((total, 2))
		send = np.zeros((total, 2))
		self.bus_report = {}
		for name, buf in self.buses.items():
			g, s = levels.get(name, (0.0, 0.2))
			dry += buf * db(g)
			send += buf * db(g) * s
			active = buf[np.max(np.abs(buf), axis=1) > 1e-4]
			self.bus_report[name] = 20 * np.log10(np.sqrt(np.mean(np.square(active))) * db(g) + 1e-12) if len(active) else -120.0
		Song.last_report = self.bus_report      # for tools/audio/mix_report.py
		wet = S.reverb(send, ir, wet=1.0, dry=0.0)
		full = np.zeros((len(wet), 2))
		full[:total] += dry
		full += wet
		loop = fold_loop(full, self.n)
		pad = ns(1.0)
		loop = circular(lambda x: F.highpass(x, hp, 2), loop, pad)
		loop = circular(lambda x: F.lowpass(x, master_lp, 1), loop, pad)
		loop = normalize_rms(loop, rms_db)
		loop = circular(lambda x: limiter(x, ceiling_db, 0.02), loop, pad)
		return loop
