#!/usr/bin/env python3
"""Mely's own sounds (task 7.4), synthesized: soft bells, plucks and pops, 16-bit mono WAV.
Run: python3 scripts/make-sounds.py  →  Resources/Sounds/*.wav"""
import math, os, random, struct, wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "Sounds")

def bell(freq, dur, start=0.0, amp=0.5, decay=6.0, partials=((1, 1.0), (2.01, 0.35), (3.02, 0.12))):
    """A struck bell: a few partials, quick attack, exponential decay."""
    out = []
    for i in range(int(dur * RATE)):
        t = i / RATE
        env = min(1.0, t / 0.004) * math.exp(-decay * t)
        v = sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in partials)
        out.append(amp * env * v)
    return start, out

def pluck(freq, dur, start=0.0, amp=0.5):
    return bell(freq, dur, start, amp, decay=14.0, partials=((1, 1.0), (2, 0.25)))

def pop(start=0.0, amp=0.6, f0=900, f1=260, dur=0.07):
    """A bubble pop: a fast falling sine."""
    out = []
    for i in range(int(dur * RATE)):
        t = i / RATE
        f = f1 + (f0 - f1) * math.exp(-t * 60)
        env = math.sin(math.pi * min(1, t / dur)) ** 0.6
        out.append(amp * env * math.sin(2 * math.pi * f * t))
    return start, out

def noise_tick(start=0.0, amp=0.25, dur=0.012):
    random.seed(7)
    return start, [amp * (random.random() * 2 - 1) * (1 - i / (dur * RATE)) for i in range(int(dur * RATE))]

def mix(name, parts, tail=0.05):
    length = max(s + len(o) / RATE for s, o in parts) + tail
    buf = [0.0] * int(length * RATE)
    for s, o in parts:
        off = int(s * RATE)
        for i, v in enumerate(o):
            buf[off + i] += v
    peak = max(1e-6, max(abs(v) for v in buf))
    gain = min(1.0, 0.9 / peak)
    with wave.open(os.path.join(OUT, name + ".wav"), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * gain)) * 32767)) for v in buf))

# Note frequencies (A4 = 440).
def n(semitones_from_a4): return 440 * 2 ** (semitones_from_a4 / 12)
C5, D5, E5, G5, A5, C6, E6, G6 = n(3), n(5), n(7), n(10), n(12), n(15), n(19), n(22)
A4, F4, E4, D4 = n(0), n(-4), n(-5), n(-7)

os.makedirs(OUT, exist_ok=True)
# Hello at launch: three rising bells.
mix("greet", [bell(C5, 0.9, 0.0, 0.45), bell(E5, 0.9, 0.11, 0.42), bell(G5, 1.1, 0.22, 0.45)])
# Claude finished: a bright major third up.
mix("finish", [bell(E5, 0.8, 0.0, 0.45), bell(C6, 1.0, 0.12, 0.45)])
# An approval waits: two same bells, asking.
mix("approval", [bell(A5, 0.6, 0.0, 0.45, decay=8), bell(A5, 0.8, 0.18, 0.4, decay=8)])
# A question: up a fourth, like an intonation.
mix("question", [bell(D5, 0.5, 0.0, 0.42, decay=9), bell(G5, 0.8, 0.14, 0.45, decay=7)])
# Error: two low notes down.
mix("error", [pluck(E4, 0.5, 0.0, 0.5), pluck(D4 * 0.94, 0.6, 0.14, 0.5)])
# Limit reached: a soft low falling bell.
mix("limit", [bell(A4, 1.0, 0.0, 0.4, decay=4), bell(F4, 1.2, 0.2, 0.35, decay=4)])
# A file dropped on the notch: a gulp.
mix("drop", [pop(0.0, 0.6, 500, 160, 0.09), pop(0.08, 0.35, 700, 300, 0.06)])
# Mely lands on the desktop / a window is attached.
mix("pop", [pop(0.0, 0.6)])
# A poke.
mix("poke", [pop(0.0, 0.45, 1300, 600, 0.05)])
# Back home in the notch.
mix("home", [pluck(G5, 0.3, 0.0, 0.4), pluck(C5, 0.4, 0.08, 0.4)])
# Island opens / closes: tiny ticks.
mix("open", [noise_tick(0.0, 0.2), pluck(C6, 0.12, 0.0, 0.18)])
mix("close", [noise_tick(0.0, 0.2), pluck(G5, 0.12, 0.0, 0.15)])
# A sent chat message.
mix("send", [pop(0.0, 0.4, 600, 1200, 0.06)])
# A focus session starts: one soft low bell, settling in.
mix("focusStart", [bell(G5 / 2, 1.2, 0.0, 0.4, decay=3.5), bell(D5, 1.0, 0.09, 0.22, decay=4)])
# A focus session is over: a calm descending chime, not as bright as Claude's finish.
mix("focusEnd", [bell(G5, 1.0, 0.0, 0.4, decay=4), bell(E5, 1.0, 0.16, 0.38, decay=4), bell(C5, 1.4, 0.32, 0.42, decay=3)])
print("ok")
