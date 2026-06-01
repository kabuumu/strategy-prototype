#!/usr/bin/env python3
"""Generate small retro sound effects (mono 16-bit WAV) for the prototype.

No external deps — pure stdlib synthesis. Output: assets/sfx/<name>.wav.
Style: short chiptune-ish blips that match the pixel-art look.
"""
import math
import os
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def _write(name, samples):
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
    print("wrote", os.path.relpath(path))


def _env(i, n, attack=0.01, release=0.3):
    """Simple attack/release amplitude envelope (0..1) over n samples."""
    t = i / RATE
    dur = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (dur - t) / release) if release > 0 else 1.0
    return max(0.0, a * r)


def tone(freq, dur, vol=0.5, attack=0.005, release=0.08, kind="square"):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        if kind == "square":
            v = 1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0
        elif kind == "saw":
            v = 2.0 * ((freq * t) % 1.0) - 1.0
        else:  # sine
            v = math.sin(2 * math.pi * freq * t)
        out.append(v * vol * _env(i, n, attack, release))
    return out


def sweep(f0, f1, dur, vol=0.5, kind="square", attack=0.005, release=0.1):
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        phase += 2 * math.pi * f / RATE
        if kind == "square":
            v = 1.0 if math.sin(phase) >= 0 else -1.0
        else:
            v = math.sin(phase)
        out.append(v * vol * _env(i, n, attack, release))
    return out


def noise(dur, vol=0.5, release=0.12):
    # Deterministic LCG noise (no Math.random/Date dependency concerns)
    n = int(RATE * dur)
    out = []
    seed = 1234567
    for i in range(n):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        v = (seed / 0x3FFFFFFF) - 1.0
        out.append(v * vol * _env(i, n, 0.001, release))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def seq(*tracks):
    out = []
    for t in tracks:
        out += t
    return out


def main():
    os.makedirs(OUT, exist_ok=True)

    # Melee/attack — short noisy thwack
    _write("attack", mix(noise(0.12, 0.4), sweep(420, 160, 0.12, 0.3)))
    # Hit/damage — gritty low blip
    _write("hit", mix(tone(180, 0.10, 0.45, kind="square"), noise(0.06, 0.25)))
    # Death — descending tone
    _write("death", sweep(300, 70, 0.45, 0.45, kind="square", release=0.3))
    # Heal — rising bright chime
    _write("heal", seq(tone(523, 0.09, 0.35, kind="sine"),
                       tone(659, 0.09, 0.35, kind="sine"),
                       tone(784, 0.14, 0.35, kind="sine", release=0.12)))
    # Ability — zappy up-sweep
    _write("ability", sweep(300, 900, 0.22, 0.4, kind="saw" if False else "square"))
    # Objective capture — two-note fanfare
    _write("capture", seq(tone(659, 0.10, 0.4), tone(988, 0.18, 0.4, release=0.14)))
    # Gold/buy — coin blip
    _write("gold", seq(tone(880, 0.06, 0.4), tone(1175, 0.10, 0.4, release=0.08)))
    # Stun — wobble
    _write("stun", mix(sweep(500, 350, 0.25, 0.35), sweep(380, 520, 0.25, 0.25)))
    # Victory — ascending triad
    _write("win", seq(tone(523, 0.12, 0.4), tone(659, 0.12, 0.4),
                      tone(784, 0.12, 0.4), tone(1047, 0.28, 0.45, release=0.22)))
    # Defeat — descending sad
    _write("lose", seq(tone(440, 0.16, 0.4, kind="square"),
                       tone(349, 0.16, 0.4, kind="square"),
                       tone(262, 0.34, 0.4, kind="square", release=0.26)))
    # Footstep — soft low thump for overworld walking (quiet; plays often)
    _write("step", mix(tone(150, 0.05, 0.22, kind="sine", release=0.04),
                       noise(0.03, 0.07)))
    # Select — short high tick for choosing a fork on the overworld
    _write("select", tone(720, 0.04, 0.30, kind="square", release=0.03))


if __name__ == "__main__":
    main()
