#!/usr/bin/env python3
"""Generate looping 8-bit chiptune tracks (mono 16-bit WAV) for the prototype.

No external deps — pure stdlib synthesis, same spirit as gen_sfx.py. Each track
is a short seamless loop built from real diatonic harmony so nothing drifts
off-key:

  * a square-wave melody locked to the current chord's tones (+ passing tones),
    cycling through several distinct phrases so the tune actually develops,
  * an arpeggiated square "pad" spelling out each chord,
  * a soft triangle bass on the chord root,
  * a noise channel for kick / snare / hi-hat (the classic NES 4th channel),
    driven by a per-track 16-step drum grid.

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
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")

# Semitone -> frequency (A4 = 440). Note 0 = A4.
def _freq(semi: int) -> float:
    return 440.0 * (2.0 ** (semi / 12.0))

# One-octave diatonic scales (7 degrees, semitone offsets from the root).
MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]      # natural minor
PHRYGIAN = [0, 1, 3, 5, 7, 8, 10]   # darkest mode — flat 2nd; tense/ominous


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


def _noise(dur: float, vol: float, decay: float) -> list:
    """Decaying white-noise burst — the raw material for snare and hi-hat."""
    n = int(RATE * dur)
    return [(random.random() * 2.0 - 1.0) * vol * math.exp(-decay * (i / RATE))
            for i in range(n)]


def _kick(vol: float = 0.55, dur: float = 0.13) -> list:
    """Sine with a fast downward pitch sweep — a punchy chip kick."""
    n = int(RATE * dur)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 45.0 + 115.0 * math.exp(-18.0 * t)   # 160 Hz -> 45 Hz thump
        phase += f / RATE
        out[i] = math.sin(2.0 * math.pi * phase) * vol * math.exp(-20.0 * t)
    return out


def _drum_kit():
    return {"K": _kick(), "S": _noise(0.13, 0.34, 32.0), "H": _noise(0.035, 0.16, 90.0)}


def _seamless(samples: list, fade_ms: float = 45.0) -> list:
    """Crossfade the loop's tail into its head so the wrap is click-free.

    The last `w` samples are equal-power blended over the first `w` and then
    dropped. That leaves result[0] == old[-w] and result[-1] == old[-w-1] —
    adjacent samples in the original, so the loop point is continuous, and the
    blend smooths the phase/amplitude jump between busy end and busy start.
    """
    w = int(RATE * fade_ms / 1000.0)
    if w < 1 or 2 * w >= len(samples):
        return samples
    tail = samples[-w:]
    out = samples[:-w]
    for i in range(w):
        a = (i + 0.5) / w
        out[i] = out[i] * math.sin(a * math.pi / 2.0) + tail[i] * math.cos(a * math.pi / 2.0)
    return out


def _build(progression, scale, root_semi, bpm, melody_phrases, drums=None,
           drum_gain=1.0, mel_oct=12, bass_oct=-24, arp_oct=0, arp_div=2,
           duty=0.5, mel_vol=0.26, arp_vol=0.13):
    """progression: list of chord root *scale degrees* (0=I, 3=IV, 4=V, 5=vi).
    melody_phrases: list of phrases; bar i plays phrase i % len, so the melody
        develops instead of repeating. Each phrase is a list of (chord-tone slot
        or None, beats) summing to 4 beats.
    drums: optional {"K"/"S"/"H": 16-char grid} ('x' = hit) over the bar."""
    beat = 60.0 / bpm
    kit = _drum_kit()
    samples = []
    for bar_idx, root_deg in enumerate(progression):
        phrase = melody_phrases[bar_idx % len(melody_phrases)]
        # Melody — chord-locked lead with a touch of vibrato.
        mel = []
        for slot, beats in phrase:
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
        # Mix the pitched voices into a fixed-length bar buffer.
        n = max(len(mel), len(bass), len(arp))
        bar = [0.0] * n
        for buf in (mel, bass, arp):
            for i, v in enumerate(buf):
                bar[i] += v
        # Drums — drop each one-shot at its 16th-note slot.
        if drums:
            step = int((beat / 4.0) * RATE)
            for lane, grid in drums.items():
                hit = kit[lane]
                for s, ch in enumerate(grid):
                    if ch != "." and ch != " ":
                        off = s * step
                        for j, hv in enumerate(hit):
                            if off + j < n:
                                bar[off + j] += hv * drum_gain
        samples += bar
    samples = _lowpass(samples)
    # Remove DC offset (asymmetric duty cycles bias the mean) so it doesn't eat
    # headroom.
    mean = sum(samples) / len(samples)
    samples = [s - mean for s in samples]
    # Soft-clip (tanh) glues the mix and tames drum transients so peak-normalising
    # doesn't duck the sustained music — keeps it loud and punchy without clipping.
    samples = [math.tanh(1.6 * s) for s in samples]
    # Seamless loop, then normalise (after the crossfade, so its overlap can't clip).
    samples = _seamless(samples)
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


# ===========================================================================
# Dark cinematic / ambient engine — NOT chiptune. Detuned sine pads, deep sub
# drones, filtered-noise wind beds, low booms, and a Schroeder reverb for space.
# Still pure-stdlib synthesis (the committed-tooling constraint), but the timbre
# is pads/drones, not square/triangle.
# ===========================================================================

def _env(n: int, atk: float, rel: float) -> list:
    """Slow attack/release amplitude envelope (seconds)."""
    a = max(1, int(RATE * atk))
    r = max(1, int(RATE * rel))
    e = [1.0] * n
    for i in range(min(a, n)):
        e[i] = i / a
    for i in range(min(r, n)):
        e[n - 1 - i] *= i / r
    return e


def _pad(root_semi: int, voices: list, dur: float, vol: float, detune: float = 0.005) -> list:
    """A lush chord pad: detuned sine layers per voice, slow swell in/out."""
    n = int(RATE * dur)
    out = [0.0] * n
    env = _env(n, dur * 0.34, dur * 0.5)
    for v in voices:
        f = _freq(root_semi + v)
        for mult in (1.0 - detune, 1.0 + detune):
            ph = 0.0
            inc = f * mult / RATE
            for i in range(n):
                ph += inc
                out[i] += math.sin(2.0 * math.pi * ph) * env[i]
    k = vol / (len(voices) * 2)
    return [s * k for s in out]


def _drone(semi: int, dur: float, vol: float) -> list:
    """Deep sustained sine + octave, with a slow amplitude swell."""
    n = int(RATE * dur)
    out = [0.0] * n
    f = _freq(semi)
    ph = 0.0
    ph2 = 0.0
    for i in range(n):
        t = i / RATE
        swell = 0.82 + 0.18 * math.sin(2.0 * math.pi * 0.06 * t)
        ph += f / RATE
        ph2 += 2.0 * f / RATE
        out[i] = (math.sin(2.0 * math.pi * ph) * 0.82 + math.sin(2.0 * math.pi * ph2) * 0.18) * vol * swell
    return out


def _wind(dur: float, vol: float) -> list:
    """A desolate wind bed: heavily low-passed noise with a slow swell."""
    n = int(RATE * dur)
    raw = [random.random() * 2.0 - 1.0 for _ in range(n)]
    lp = _lowpass(_lowpass(raw, 0.04), 0.04)
    out = [0.0] * n
    for i in range(n):
        t = i / RATE
        swell = 0.45 + 0.45 * math.sin(2.0 * math.pi * 0.045 * t - 1.0)
        out[i] = lp[i] * vol * swell
    return out


def _boom(semi: int, dur: float, vol: float) -> list:
    """A low tension hit: sine with a downward pitch drop and long decay."""
    n = int(RATE * dur)
    out = [0.0] * n
    base = _freq(semi)
    ph = 0.0
    for i in range(n):
        t = i / RATE
        f = base * (1.0 + 1.4 * math.exp(-7.0 * t))
        ph += f / RATE
        out[i] = math.sin(2.0 * math.pi * ph) * vol * math.exp(-2.2 * t)
    return out


def _comb(samples: list, delay: int, fb: float) -> list:
    out = [0.0] * len(samples)
    buf = [0.0] * delay
    p = 0
    for i, x in enumerate(samples):
        y = buf[p]
        buf[p] = x + y * fb
        out[i] = y
        p += 1
        if p >= delay:
            p = 0
    return out


def _allpass(samples: list, delay: int, g: float) -> list:
    out = [0.0] * len(samples)
    buf = [0.0] * delay
    p = 0
    for i, x in enumerate(samples):
        bo = buf[p]
        y = -g * x + bo
        buf[p] = x + g * bo
        out[i] = y
        p += 1
        if p >= delay:
            p = 0
    return out


def _reverb(samples: list, mix: float = 0.32) -> list:
    """Schroeder reverb (parallel combs -> series allpass) for cavernous space."""
    combs = [_comb(samples, int(RATE * d), f)
             for d, f in [(0.0297, 0.80), (0.0371, 0.76), (0.0411, 0.72), (0.0437, 0.70)]]
    wet = [(combs[0][i] + combs[1][i] + combs[2][i] + combs[3][i]) * 0.25
           for i in range(len(samples))]
    wet = _allpass(wet, int(RATE * 0.0050), 0.7)
    wet = _allpass(wet, int(RATE * 0.0017), 0.7)
    return [(1.0 - mix) * samples[i] + mix * wet[i] for i in range(len(samples))]


def _mix(length: int, layers: list) -> list:
    """Sum (samples, start_sample) layers into a single buffer of `length`."""
    out = [0.0] * length
    for samples, off in layers:
        for i, s in enumerate(samples):
            j = off + i
            if 0 <= j < length:
                out[j] += s
    return out


def _finish(samples: list, lp: float = 0.6, rev: float = 0.32) -> list:
    samples = [math.tanh(1.4 * s) for s in samples]
    samples = _lowpass(samples, lp)            # warmth — roll off harshness
    samples = _reverb(samples, rev)            # space
    samples = _seamless(samples, 90.0)
    peak = max(0.001, max(abs(s) for s in samples))
    return [s * (0.80 / peak) for s in samples]


# Minor-triad pad voicing in Phrygian (root, b3, 5, octave).
_TRIAD = [0, 3, 7, 12]


def main() -> None:
    random.seed(0xC0FFEE)

    # Setting: post-apocalyptic, dark and tense. Cinematic ambient — sine pads,
    # deep drones, wind, and reverb. No 8-bit/chiptune voices.

    # Title — ominous, evolving pad chords over a deep drone + faint wind.
    title_chords = [(0, 4.0), (1, 4.0), (0, 4.0), (8, 4.0),
                    (0, 4.0), (1, 4.0), (10, 4.0), (0, 4.0)]   # i bII i bVI i bII bVII i
    base = -14
    total = int(RATE * sum(d for _, d in title_chords))
    layers = []
    off = 0
    for root, d in title_chords:
        layers.append((_pad(base + root, _TRIAD, d, 0.55), off))
        off += int(RATE * d)
    layers.append((_drone(base - 12, total / RATE, 0.34), 0))
    layers.append((_wind(total / RATE, 0.16), 0))
    _write("title", _finish(_mix(total, layers)))

    # Map — desolate wasteland. Deep drone + prominent wind + sparse lonely pads.
    map_secs = 36.0
    total = int(RATE * map_secs)
    layers = [
        (_drone(-26, map_secs, 0.36), 0),
        (_drone(-14, map_secs, 0.12), 0),
        (_wind(map_secs, 0.26), 0),
    ]
    # A few sparse, far-apart single-note pads (root / b6 / b3) — lonely.
    for root, t in [(0, 2.0), (8, 11.0), (3, 20.0), (1, 28.0)]:
        layers.append((_pad(-2 + root, [0, 12], 5.0, 0.30), int(RATE * t)))
    _write("map", _finish(_mix(total, layers), lp=0.5))

    # Battle — tense and driving. A pulsing low boom on every beat + dark pad
    # stabs + reverb. No melody lead, just relentless pressure.
    bpm = 120
    beat = 60.0 / bpm
    beats = 32                       # ~16s loop
    total = int(RATE * beat * beats)
    layers = [(_drone(-26, beat * beats, 0.30), 0)]
    for b in range(beats):
        off = int(RATE * beat * b)
        # Pounding pulse every beat; accent the downbeat of each bar (4 beats).
        vol = 0.62 if (b % 4 == 0) else 0.40
        layers.append((_boom(-26, beat * 0.95, vol), off))
    # Dark pad stabs every two bars, moving i -> bII for tension.
    pad_roots = [0, 1, 0, 8]
    for k, root in enumerate(pad_roots):
        off = int(RATE * beat * (k * 8))
        layers.append((_pad(-12 + root, _TRIAD, beat * 8, 0.34), off))
    _write("battle", _finish(_mix(total, layers), lp=0.7, rev=0.26))


if __name__ == "__main__":
    main()
