#!/usr/bin/env python3
"""Generates the two ambience loops (ticket 86): assets/audio/ambience/day.ogg (wind and soft chirps) and
drone.ogg (low detuned hum). Both are 24 s, 44.1 kHz mono, quiet, and loop seamlessly (all filtering is circular and
every tone has a whole number of cycles in the loop). Needs numpy and ffmpeg. Usage: python3 tools/make_ambience.py"""
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
SECONDS = 24
N = SR * SECONDS
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "ambience"


def filtered_noise(rng, lo, hi):
    """White noise band-limited in the frequency domain: circular, so the ends meet."""
    spec = np.fft.rfft(rng.standard_normal(N))
    f = np.fft.rfftfreq(N, 1.0 / SR)
    spec *= ((f >= lo) & (f <= hi)) / np.sqrt(np.maximum(f, 1.0))
    x = np.fft.irfft(spec, N)
    return x / np.max(np.abs(x))


def day(rng):
    t = np.arange(N) / SR
    wind = filtered_noise(rng, 80, 900)
    # slow gusts: a few whole cycles per loop
    gust = 0.65 + 0.35 * np.sin(2 * np.pi * 3 * t / SECONDS + 1.0) * np.sin(2 * np.pi * 5 * t / SECONDS)
    out = 0.5 * wind * gust
    for _ in range(14):  # soft chirps, wrapping round the loop end
        start = rng.integers(0, N)
        dur = int(rng.uniform(0.12, 0.3) * SR)
        base = rng.uniform(2200, 4200)
        tt = np.arange(dur) / SR
        freq = base * (1 + 0.25 * np.sin(2 * np.pi * rng.uniform(8, 18) * tt))
        chirp = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.sin(np.pi * tt / tt[-1]) ** 2
        idx = (start + np.arange(dur)) % N
        out[idx] += 0.07 * chirp
    return out


def drone(rng):
    t = np.arange(N) / SR
    out = np.zeros(N)
    for cycles_per_s, amp in ((55, 0.5), (55.5, 0.4), (82.5, 0.2), (110.5, 0.12)):
        # whole cycles in the loop: cycles_per_s * SECONDS is an integer for every entry
        out += amp * np.sin(2 * np.pi * cycles_per_s * t + rng.uniform(0, 6.28))
    out *= 0.75 + 0.25 * np.sin(2 * np.pi * 2 * t / SECONDS)  # slow swell, 2 cycles per loop
    out += 0.05 * filtered_noise(rng, 40, 300)
    return out


def write_ogg(name, x, peak):
    x = x / np.max(np.abs(x)) * peak
    pcm = (x * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / (name + ".wav")
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        OUT.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "2",
                        str(OUT / (name + ".ogg"))], check=True)


def main():
    write_ogg("day", day(np.random.default_rng(86)), 0.5)
    write_ogg("drone", drone(np.random.default_rng(87)), 0.5)
    return 0


if __name__ == "__main__":
    sys.exit(main())
