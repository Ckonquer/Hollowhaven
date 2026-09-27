"""hhsynth - a small, readable synthesis toolkit for Hollowhaven's original audio.

Everything is plain numpy/scipy. Signals are float64 arrays at 44.1 kHz:
mono = shape (n,), stereo = shape (n, 2). Every generator takes an explicit
numpy Generator (see core.rng_for) so builds are reproducible.

Modules
  core      sample-rate helpers, envelopes, mixing, fades, normalisation, loops, limiter
  osc       phase-accumulating oscillators (sine, band-limited saw/pulse, triangle), glides
  noise     white / pink / brown / blue noise (FFT-shaped, loop friendly)
  filters   Butterworth + RBJ biquads, time-varying (swept) filters, formant banks
  physical  modal resonators, Karplus-Strong plucks, creaks, granular crunches, bubbles
  fm        FM operators, bells, glass chimes, woodwind-like voices
  space     panning, synthetic room/cave impulse responses, convolution reverb, echoes
  music     note names, chords, instruments and a tiny sequencer
  wavio     16-bit WAV writer (with an optional 'smpl' loop chunk) and reader
"""
