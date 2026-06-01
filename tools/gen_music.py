#!/usr/bin/env python3
"""Generate looping 8-bit chiptune tracks (mono 16-bit WAV) for the prototype.

No external deps — pure stdlib synthesis, same spirit as gen_sfx.py. Each track
is a short seamless loop: a square-wave melody over a pulse-wave bass, following
a simple chord progression. Output: assets/music/<name>.wav.

The Music autoload (src/music.gd) loads these and sets loop_mode at runtime.

Run:  python3 tools/gen_music.py   then  godot --headless --import
"""
import math
import os
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")

# Semitone -> frequency (A4 = 440). Note 0 = A4.
def _freq(semi: int) -> float:
    return 440.0 * (2.0 ** (semi / 12.0))

# Named scale degrees relative to a root, in semitones (minor / major pentatonic-ish).
MINOR = [0, 2, 3, 5, 7, 8, 10, 12]
MAJOR = [0, 2, 4, 5, 7, 9, 11, 12]


def _square(phase: float, duty: float = 0.5) -> float:
    return 1.0 if (phase % 1.0) < duty else -1.0


def _triangle(phase: float) -> float:
    p = phase % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def _note(freq: float, dur: float, vol: float, duty: float, kind: str = "square") -> list:
    n = int(RATE * dur)
    out = [0.0] * n
    if freq <= 0.0:
        return out  # rest
    for i in range(n):
        t = i / RATE
        phase = freq * t
        s = _triangle(phase) if kind == "tri" else _square(phase, duty)
        # Short attack + gentle decay so notes don't click and have a chip "pluck".
        a = min(1.0, (i / RATE) / 0.006)
        rel = n - i
        r = min(1.0, rel / (0.02 * RATE))
        decay = 0.65 + 0.35 * math.exp(-3.0 * t / max(0.05, dur))
        out[i] = s * vol * a * r * decay
    return out


def _build(progression, scale, root_semi, bpm, melody_pattern, bass_octave=-24, duty=0.5):
    """progression: list of chord-root offsets (semitones from root) per bar.
    melody_pattern: list of (degree_index_or_None, beats) within each bar."""
    beat = 60.0 / bpm
    samples = []
    for bar_root in progression:
        # Melody for this bar
        bar_mel = []
        for deg, beats in melody_pattern:
            dur = beat * beats
            if deg is None:
                bar_mel += _note(0.0, dur, 0.0, duty)
            else:
                semi = root_semi + bar_root + scale[deg % len(scale)] + (12 if deg >= len(scale) else 0)
                bar_mel += _note(_freq(semi), dur, 0.32, duty, "square")
        # Bass: root note, four beats
        bar_bass = []
        for _b in range(4):
            semi = root_semi + bar_root + bass_octave
            bar_bass += _note(_freq(semi), beat, 0.30, 0.5, "tri")
        # Mix (pad to equal length)
        n = max(len(bar_mel), len(bar_bass))
        bar_mel += [0.0] * (n - len(bar_mel))
        bar_bass += [0.0] * (n - len(bar_bass))
        for i in range(n):
            samples.append(bar_mel[i] + bar_bass[i])
    # Normalise to avoid clipping
    peak = max(0.001, max(abs(s) for s in samples))
    g = 0.85 / peak
    return [s * g for s in samples]


def _write(name: str, samples: list) -> None:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))
    print("wrote", os.path.relpath(path), "(%.1fs)" % (len(samples) / RATE))


def main() -> None:
    # Title — stately major, slow, hopeful.
    _write("title", _build(
        progression=[0, 5, -4, -2, 0, 5, 7, 0],   # I IV vi V ...
        scale=MAJOR, root_semi=-9, bpm=96, duty=0.5,
        melody_pattern=[(4, 1), (3, 1), (2, 1), (4, 1)]))
    # Map — calm, sparse, minor-ish wander.
    _write("map", _build(
        progression=[0, -2, 3, -4, 0, -2, 5, 3],
        scale=MINOR, root_semi=-9, bpm=84, duty=0.375,
        melody_pattern=[(0, 2), (2, 1), (4, 1)]))
    # Battle — driving, fast, minor, busier melody.
    _write("battle", _build(
        progression=[0, 0, 5, 5, -2, -2, 3, 7],
        scale=MINOR, root_semi=-12, bpm=140, duty=0.25,
        melody_pattern=[(4, 0.5), (5, 0.5), (6, 1), (4, 0.5), (2, 0.5), (4, 1)]))


if __name__ == "__main__":
    main()
