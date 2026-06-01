#!/usr/bin/env python3
"""Generate looping 8-bit chiptune tracks (mono 16-bit WAV) for the prototype.

No external deps — pure stdlib synthesis, same spirit as gen_sfx.py. Each track
is a short seamless loop built from real diatonic harmony so nothing drifts
off-key:

  * a square-wave melody locked to the current chord's tones (+ passing tones),
  * an arpeggiated square "pad" spelling out each chord,
  * a soft triangle bass on the chord root.

Everything is voiced from the key's scale via diatonic chord degrees, so the
melody never clashes with the bass (the old generator shifted the whole melody
by raw semitone chord offsets, which fell outside the scale). A gentle one-pole
low-pass tames the square harshness and the progressions end on V so the loop
seam resolves V->I.

Output: assets/music/<name>.wav. The Music autoload (src/music.gd) loads these
and sets loop_mode at runtime.

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

# One-octave diatonic scales (7 degrees, semitone offsets from the root).
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]  # natural minor


def _scale_note(scale: list, degree: int) -> int:
    """Diatonic note for any degree index, wrapping the octave as needed."""
    octave, idx = divmod(degree, len(scale))
    return scale[idx] + 12 * octave


def _chord_tone(scale: list, root_deg: int, slot: int) -> int:
    """Note (semitones from key root) for a voice 'slot' over the chord whose
    root is scale-degree `root_deg`. Slots stay inside the chord/scale so every
    voice is consonant:
        0 root · 1 third · 2 fifth · 3 octave · 4 passing 2nd · 5 sixth · 6 leading
    """
    table = {0: 0, 1: 2, 2: 4, 3: 7, 4: 1, 5: 5, 6: -1}
    return _scale_note(scale, root_deg + table[slot])


def _square(phase: float, duty: float = 0.5) -> float:
    return 1.0 if (phase % 1.0) < duty else -1.0


def _triangle(phase: float) -> float:
    p = phase % 1.0
    return 4.0 * abs(p - 0.5) - 1.0


def _note(freq: float, dur: float, vol: float, duty: float,
          kind: str = "square", vibrato: float = 0.0) -> list:
    n = int(RATE * dur)
    out = [0.0] * n
    if freq <= 0.0:
        return out  # rest
    phase = 0.0
    for i in range(n):
        t = i / RATE
        # Slow vibrato (~5 Hz) eases in after the attack so leads sing a little.
        f = freq
        if vibrato > 0.0 and t > 0.08:
            f = freq * (1.0 + vibrato * math.sin(2.0 * math.pi * 5.0 * t))
        phase += f / RATE
        s = _triangle(phase) if kind == "tri" else _square(phase, duty)
        # Soft attack + longer release so notes neither click nor sound harsh.
        a = min(1.0, t / 0.008)
        r = min(1.0, (n - i) / (0.04 * RATE))
        decay = 0.70 + 0.30 * math.exp(-2.5 * t / max(0.05, dur))
        out[i] = s * vol * a * r * decay
    return out


def _lowpass(samples: list, alpha: float = 0.30) -> list:
    """One-pole low-pass — rounds off the brightest square harmonics."""
    y = 0.0
    out = [0.0] * len(samples)
    for i, x in enumerate(samples):
        y += alpha * (x - y)
        out[i] = y
    return out


def _build(progression, scale, root_semi, bpm, melody_pattern,
           mel_oct=12, bass_oct=-24, arp_oct=0, arp_div=2,
           duty=0.5, mel_vol=0.26, arp_vol=0.13):
    """progression: list of chord root *scale degrees* (0=I, 3=IV, 4=V, 5=vi).
    melody_pattern: list of (chord-tone slot or None, beats) summing to 4 beats."""
    beat = 60.0 / bpm
    samples = []
    for root_deg in progression:
        # Melody — chord-locked lead with a touch of vibrato.
        mel = []
        for slot, beats in melody_pattern:
            dur = beat * beats
            if slot is None:
                mel += _note(0.0, dur, 0.0, duty)
            else:
                semi = root_semi + mel_oct + _chord_tone(scale, root_deg, slot)
                mel += _note(_freq(semi), dur, mel_vol, duty, "square", vibrato=0.006)
        # Bass — chord root, one note per beat, soft triangle.
        bass = []
        for _b in range(4):
            semi = root_semi + bass_oct + _scale_note(scale, root_deg)
            bass += _note(_freq(semi), beat, 0.26, 0.5, "tri")
        # Arp pad — cycle root/third/fifth/octave to spell out the chord.
        arp = []
        slots = [0, 1, 2, 3]
        steps = 4 * arp_div
        sdur = beat / arp_div
        for s in range(steps):
            semi = root_semi + arp_oct + _chord_tone(scale, root_deg, slots[s % len(slots)])
            arp += _note(_freq(semi), sdur, arp_vol, 0.35, "square")
        # Mix the three voices (pad to equal length).
        n = max(len(mel), len(bass), len(arp))
        mel += [0.0] * (n - len(mel))
        bass += [0.0] * (n - len(bass))
        arp += [0.0] * (n - len(arp))
        for i in range(n):
            samples.append(mel[i] + bass[i] + arp[i])
    samples = _lowpass(samples)
    # Remove DC offset (asymmetric duty cycles bias the mean) so it doesn't eat
    # headroom, then normalise to avoid clipping.
    mean = sum(samples) / len(samples)
    samples = [s - mean for s in samples]
    peak = max(0.001, max(abs(s) for s in samples))
    g = 0.80 / peak
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
    # Title — stately major, hopeful. I V vi IV ... resolving V -> I at the loop.
    _write("title", _build(
        progression=[0, 4, 5, 3, 0, 3, 5, 4],
        scale=MAJOR, root_semi=-9, bpm=92, arp_div=2, duty=0.5,
        melody_pattern=[(0, 1), (2, 1), (1, 1), (3, 1)]))
    # Map — calm minor wander, sparse melody, prominent pad.
    _write("map", _build(
        progression=[0, 5, 3, 4, 0, 5, 6, 4],
        scale=MINOR, root_semi=-9, bpm=80, arp_div=1, duty=0.375,
        melody_pattern=[(0, 2), (2, 1), (1, 1)],
        mel_vol=0.22, arp_vol=0.15))
    # Battle — driving minor, busy arp + lead with a passing tone.
    _write("battle", _build(
        progression=[0, 0, 5, 3, 4, 4, 3, 4],
        scale=MINOR, root_semi=-12, bpm=140, arp_div=2, duty=0.5,
        melody_pattern=[(0, 0.5), (1, 0.5), (2, 1), (3, 0.5), (4, 0.5), (2, 1)],
        mel_vol=0.27))


if __name__ == "__main__":
    main()
