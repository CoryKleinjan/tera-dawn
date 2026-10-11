"""Puts a sound effect in the game as assets/audio/sfx/<id>.ogg.

Several sources become variants (<id>_1.ogg, <id>_2.ogg ...), one picked at random each time
it plays. Each is cut free of silence at both ends, made mono, and set to the same loudness so
no sound jumps out. Needs ffmpeg.

  python3 tools/audio/make_sfx.py ID SOURCE [SOURCE ...] [--gain DB]
"""
import argparse, glob, os, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")
## Loudness every effect is set to (peak, dBFS); --gain moves one sound up or down from it.
PEAK_DB = -3.0
SILENCE_DB = -50
OGG_QUALITY = "4"


def peak(path):
    log = subprocess.run(["ffmpeg", "-v", "info", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    for line in log.splitlines():
        if "max_volume:" in line:
            return float(line.split("max_volume:")[1].split()[0])
    return 0.0


def convert(src, dst, gain):
    trim = (f"silenceremove=start_periods=1:start_threshold={SILENCE_DB}dB,areverse,"
            f"silenceremove=start_periods=1:start_threshold={SILENCE_DB}dB,areverse")
    boost = PEAK_DB + gain - peak(src)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-ac", "1", "-af", f"{trim},volume={boost:.2f}dB",
                    "-c:a", "libvorbis", "-q:a", OGG_QUALITY, dst], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("id")
    ap.add_argument("sources", nargs="+")
    ap.add_argument("--gain", type=float, default=0.0)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, f"{a.id}.ogg")) + glob.glob(os.path.join(OUT, f"{a.id}_[0-9]*.ogg")):
        os.remove(old)
    names = [f"{a.id}.ogg"] if len(a.sources) == 1 else [f"{a.id}_{i + 1}.ogg" for i in range(len(a.sources))]
    for src, name in zip(a.sources, names):
        convert(src, os.path.join(OUT, name), a.gain)
        print(f"assets/audio/sfx/{name}")


if __name__ == "__main__":
    main()
