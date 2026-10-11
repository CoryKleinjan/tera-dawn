"""Synthesizes the soft magical sounds the free sound packs don't have: chimes, sparkles,
whooshes and swirls, as .wav files to feed to make_sfx.py. Needs numpy.

  python3 tools/audio/synth_sfx.py OUT_DIR

Every sound is made from a fixed random seed, so a run always gives the same files.
"""
import os, sys, wave
import numpy as np

RATE = 44100


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def env(n, attack, decay):
    """An envelope: rises over `attack` seconds, then decays with time constant `decay`."""
    x = np.arange(n) / RATE
    rise = np.clip(x / max(attack, 1e-4), 0, 1)
    return rise * np.exp(-np.maximum(x - attack, 0) / decay)


def bell(freq, seconds, decay=0.35, attack=0.002):
    """A glockenspiel-like tone: a few inharmonic partials that fade at different speeds."""
    x = t(seconds)
    out = np.zeros_like(x)
    for ratio, amp, d in ((1.0, 1.0, 1.0), (2.76, 0.45, 0.5), (5.4, 0.2, 0.25), (8.93, 0.08, 0.15)):
        out += amp * np.sin(2 * np.pi * freq * ratio * x) * env(len(x), attack, decay * d)
    return out


def noise(seconds, rng):
    return rng.standard_normal(int(RATE * seconds))


def sweep_filter(signal, lo, hi, q=6.0):
    """Band-pass filters `signal` with a centre frequency gliding from lo to hi (a state-variable filter)."""
    out = np.zeros_like(signal)
    low = band = 0.0
    centres = np.geomspace(lo, hi, len(signal))
    for i, s in enumerate(signal):
        f = 2 * np.sin(np.pi * centres[i] / RATE)
        low += f * band
        high = s - low - band / q
        band += f * high
        out[i] = band
    return out


def place(dst, src, at):
    """Mixes `src` into `dst` starting `at` seconds in."""
    i = int(at * RATE)
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += src[:n]


def reverb(x, rng, seconds=0.6, mix=0.25):
    """A cheap room: the sound convolved with decaying noise."""
    tail = noise(seconds, rng) * env(int(RATE * seconds), 0.001, seconds / 5)
    wet = np.convolve(x, tail)
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    wet *= np.max(np.abs(dry)) / (np.max(np.abs(wet)) + 1e-9)
    return dry * (1 - mix) + wet * mix


NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def note(name, octave):
    return NOTE[name] * 2 ** (octave - 4)


def sparkle(rng):
    """A quick rising arpeggio of bells, then a shimmer."""
    out = np.zeros(int(RATE * 1.4))
    for i, (n, o) in enumerate((("C", 6), ("E", 6), ("G", 6), ("C", 7), ("E", 7))):
        place(out, bell(note(n, o), 1.0, 0.3) * (0.8 - i * 0.08), i * 0.055)
    for i in range(10):
        place(out, bell(rng.uniform(3000, 6000), 0.3, 0.08) * 0.12, 0.25 + rng.uniform(0, 0.6))
    return reverb(out, rng)


def heal(rng):
    """A soft, warm rising chord with a breathy swell."""
    out = np.zeros(int(RATE * 1.3))
    for i, (n, o) in enumerate((("F", 5), ("A", 5), ("C", 6), ("F", 6))):
        place(out, bell(note(n, o), 1.1, 0.45, attack=0.04) * 0.5, i * 0.09)
    air = sweep_filter(noise(1.0, rng), 800, 3000, 3) * env(int(RATE * 1.0), 0.35, 0.2) * 0.25
    place(out, air, 0)
    return reverb(out, rng, mix=0.35)


def buff(rng):
    """An upward whoosh capped with a bright chime."""
    out = np.zeros(int(RATE * 1.0))
    whoosh = sweep_filter(noise(0.45, rng), 300, 4000, 4) * env(int(RATE * 0.45), 0.3, 0.08) * 0.6
    place(out, whoosh, 0)
    place(out, bell(note("A", 6), 0.6, 0.25) * 0.5, 0.3)
    place(out, bell(note("E", 7), 0.6, 0.2) * 0.3, 0.33)
    return reverb(out, rng)


def portal(rng):
    """A swirling, rising whoosh over a low wobbling hum."""
    n = int(RATE * 0.9)
    x = t(0.9)
    swirl = sweep_filter(noise(0.9, rng) * (1 + 0.6 * np.sin(2 * np.pi * 9 * x)), 250, 2500, 5)
    hum = np.sin(2 * np.pi * (110 + 80 * x) * x + 2 * np.sin(2 * np.pi * 5 * x)) * 0.3
    out = (swirl * 0.8 + hum) * env(n, 0.25, 0.25)
    return reverb(out, rng, mix=0.3)


def cast(rng):
    """A short airy magical whoosh with a glint."""
    out = np.zeros(int(RATE * 0.6))
    place(out, sweep_filter(noise(0.3, rng), 1500, 5000, 3) * env(int(RATE * 0.3), 0.05, 0.08) * 0.6, 0)
    place(out, bell(note("D", 7), 0.4, 0.12) * 0.35, 0.04)
    return reverb(out, rng, 0.4)


def magic_hit(rng):
    """A bright crackling burst."""
    out = np.zeros(int(RATE * 0.5))
    crack = noise(0.25, rng) * env(int(RATE * 0.25), 0.001, 0.04)
    place(out, sweep_filter(crack, 4000, 1200, 2) * 0.9, 0)
    place(out, bell(note("G", 6), 0.4, 0.1) * 0.4, 0)
    place(out, bell(note("C#", 7), 0.4, 0.08) * 0.25, 0.01)
    return reverb(out, rng, 0.3, 0.2)


def jump(rng):
    """A soft, short upward swish."""
    sw = sweep_filter(noise(0.18, rng), 500, 2200, 3) * env(int(RATE * 0.18), 0.03, 0.05)
    return sw


SOUNDS = {"sparkle": sparkle, "heal": heal, "buff": buff, "portal": portal, "cast": cast,
          "magic_hit": magic_hit, "jump": jump}


def save(path, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for i, (name, make) in enumerate(SOUNDS.items()):
        save(os.path.join(out, f"{name}.wav"), make(np.random.default_rng(1000 + i)))
        print(name)


if __name__ == "__main__":
    main()
