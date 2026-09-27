"""16-bit PCM WAV I/O with an optional 'smpl' loop chunk (Godot reads it: loop mode 'Detect')."""
from __future__ import annotations

import struct
import zlib

import numpy as np

from .core import SR


def write_wav(path: str, x: np.ndarray, loop: bool = False, sr: int = SR) -> int:
	"""Writes float audio (-1..1) as 16-bit PCM with TPDF dither (deterministic per path).
	For loops, one extra frame equal to the first frame is appended and the loop end is set to
	the original length: Godot's loop end is exclusive, so playback covers frames [0, n) and the
	resampler's look-ahead sees the true continuation at the seam. Returns the frame count."""
	x = np.asarray(x, dtype=np.float64)
	ch = 1 if x.ndim == 1 else x.shape[1]
	n_loop = len(x)
	if loop:
		x = np.concatenate([x, x[:1]], axis=0)
	rng = np.random.default_rng(zlib.crc32(path.replace("\\", "/").split("/")[-1].encode()))
	lsb = 1.0 / 32768.0
	d = (rng.uniform(-0.5, 0.5, x.shape) + rng.uniform(-0.5, 0.5, x.shape)) * lsb
	if loop:
		d[-1] = d[0]
	q = np.clip(np.round((x + d) * 32767.0), -32768, 32767).astype("<i2")
	data = q.tobytes()
	fmt = struct.pack("<HHIIHH", 1, ch, sr, sr * 2 * ch, 2 * ch, 16)
	chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
	chunks += b"data" + struct.pack("<I", len(data)) + data
	if loop:
		smpl = struct.pack("<9I", 0, 0, int(1e9 / sr), 60, 0, 0, 0, 1, 0)
		smpl += struct.pack("<6I", 0, 0, 0, n_loop, 0, 0)
		chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
	with open(path, "wb") as fh:
		fh.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
	return len(q)


def read_wav(path: str):
	"""Returns (float samples (n,) or (n, ch), sample_rate, loop (start, end) or None)."""
	with open(path, "rb") as fh:
		raw = fh.read()
	if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
		raise ValueError("not a WAV file: " + path)
	pos = 12
	ch = sr = bits = 0
	data = None
	loop = None
	while pos + 8 <= len(raw):
		cid = raw[pos:pos + 4]
		size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
		body = raw[pos + 8:pos + 8 + size]
		if cid == b"fmt ":
			_, ch, sr, _, _, bits = struct.unpack("<HHIIHH", body[:16])
		elif cid == b"data":
			data = body
		elif cid == b"smpl" and size >= 36 + 24:
			count = struct.unpack("<I", body[28:32])[0]
			if count > 0:
				_, _, start, end, _, _ = struct.unpack("<6I", body[36:60])
				loop = (start, end)
		pos += 8 + size + (size & 1)
	if data is None or bits != 16:
		raise ValueError("unsupported WAV: " + path)
	x = np.frombuffer(data, dtype="<i2").astype(np.float64) / 32768.0
	if ch > 1:
		x = x.reshape(-1, ch)
	return x, sr, loop
