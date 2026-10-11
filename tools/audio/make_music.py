"""Puts a piece of music in the game as assets/audio/music/<id>.ogg.

A track (the default) loops: Lyria tracks fade out at the end, so the faded tail is cut and
the end is crossfaded into the start, giving a seamless loop. A jingle (--jingle) plays once:
it's cut where it first falls silent (Lyria clips are 30 s with silence after the jingle).
Needs ffmpeg.

  python3 tools/audio/make_music.py SOURCE ID [--jingle]
"""
import argparse, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio", "music")
## Seconds cut from a track's end (its fade-out), and how long its end crossfades into its start.
TAIL = 4.0
CROSSFADE = 3.0
## A jingle ends at the first silence (quieter than SILENCE_DB for SILENCE_S seconds) after
## JINGLE_MIN seconds, and is never longer than JINGLE_MAX; it fades out over JINGLE_FADE.
SILENCE_DB = -40
SILENCE_S = 0.6
JINGLE_MIN = 1.5
JINGLE_MAX = 10.0
JINGLE_FADE = 0.4
OGG_QUALITY = "5"


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out)


def make_loop(src, dst):
    end = duration(src) - TAIL
    with tempfile.TemporaryDirectory() as tmp:
        body, head = os.path.join(tmp, "body.wav"), os.path.join(tmp, "head.wav")
        # body starts CROSSFADE in; the head (the first CROSSFADE seconds) blends into its end,
        # so the loop's last sample leads straight back into its first
        ffmpeg("-ss", str(CROSSFADE), "-to", f"{end:.3f}", "-i", src, body)
        ffmpeg("-t", str(CROSSFADE), "-i", src, head)
        ffmpeg("-i", body, "-i", head, "-filter_complex", f"[0][1]acrossfade=d={CROSSFADE}:c1=tri:c2=tri",
               "-c:a", "libvorbis", "-q:a", OGG_QUALITY, dst)


def jingle_end(src):
    log = subprocess.run(["ffmpeg", "-v", "info", "-i", src, "-af", f"silencedetect=n={SILENCE_DB}dB:d={SILENCE_S}",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    for start in re.findall(r"silence_start: ([\d.]+)", log):
        if float(start) >= JINGLE_MIN:
            return min(float(start) + 0.2, JINGLE_MAX)
    return min(duration(src), JINGLE_MAX)


def make_jingle(src, dst):
    end = jingle_end(src)
    ffmpeg("-t", f"{end:.3f}", "-i", src, "-af", f"afade=t=out:st={max(0.0, end - JINGLE_FADE):.3f}:d={JINGLE_FADE}",
           "-c:a", "libvorbis", "-q:a", OGG_QUALITY, dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("id")
    ap.add_argument("--jingle", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"{a.id}.ogg")
    (make_jingle if a.jingle else make_loop)(a.source, dst)
    print(f"{os.path.relpath(dst, ROOT)}: {duration(dst):.1f} s")


if __name__ == "__main__":
    sys.exit(main())
