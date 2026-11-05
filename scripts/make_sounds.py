#!/usr/bin/env python3
"""Makes the rest-countdown sounds for the app (specs/lift-feedback.llm.md, AC-9).

Writes into ios/MuscleMap/Resources/Sounds/:
- beep_short.caf: one short beep (a tick in the last 10 s, played by the app while open)
- beep_long.caf: the long beep at 0
- countdown_1.caf ... countdown_10.caf: n short beeps 1 s apart, then the long beep 1 s
  after the last one. Notifications play these when the app is closed or locked.

Each file is under 30 s, as iOS requires for notification sounds. The sounds are our own
sine tones, so there is no license question. Needs macOS (`afconvert`).

Run: python3 scripts/make_sounds.py
"""

import math
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

RATE = 22_050
OUT = Path(__file__).resolve().parent.parent / "ios" / "MuscleMap" / "Resources" / "Sounds"

SHORT = (880.0, 0.12)   # Hz, seconds
LONG = (1320.0, 0.7)
VOLUME = 0.8
FADE_S = 0.005          # short fade in and out, so the beeps don't click


def tone(freq: float, seconds: float) -> list[float]:
    count = int(RATE * seconds)
    fade = int(RATE * FADE_S)
    samples = []
    for i in range(count):
        gain = min(1.0, i / fade, (count - 1 - i) / fade) if fade else 1.0
        samples.append(VOLUME * gain * math.sin(2 * math.pi * freq * i / RATE))
    return samples


def silence(seconds: float) -> list[float]:
    return [0.0] * int(RATE * seconds)


def countdown(n: int) -> list[float]:
    """n short beeps at 0, 1, ... n-1 s, then the long beep at n s."""
    samples: list[float] = []
    beep = tone(*SHORT)
    for _ in range(n):
        samples += beep + silence(1.0 - SHORT[1])
    return samples + tone(*LONG)


def write_caf(name: str, samples: list[float]) -> None:
    seconds = len(samples) / RATE
    assert seconds < 30, f"{name} is {seconds:.1f} s; notification sounds must be under 30 s"
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = Path(tmp) / f"{name}.wav"
        with wave.open(str(wav_path), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
        out = OUT / f"{name}.caf"
        # IMA4 (IMA/ADPCM) in a CAF file: small, and a format notifications can play.
        subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", str(wav_path), str(out)], check=True)
    print(f"{out.relative_to(OUT.parent.parent.parent.parent)}  {seconds:.2f} s")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write_caf("beep_short", tone(*SHORT))
    write_caf("beep_long", tone(*LONG))
    for n in range(1, 11):
        write_caf(f"countdown_{n}", countdown(n))


if __name__ == "__main__":
    main()
