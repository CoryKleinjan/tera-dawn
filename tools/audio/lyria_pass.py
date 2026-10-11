"""Makes the game's music with Google's Lyria models through the Gemini API.

Each entry in lyria_cues.json (a track or a jingle, several takes) becomes one file in the
output folder; files that already exist are skipped, so a run can be resumed. Every call is
paid (about $0.08 a track, $0.04 a 30 s clip) and Lyria has no batch mode: ask Cory first.
Needs GEMINI_API_KEY, and a session that isn't linked to Cory's computer (that gets 403).

  python3 tools/audio/lyria_pass.py OUT_DIR [--only ID ...] [--budget 5] [--dry-run]

Then pick a take and put it in the game with tools/audio/make_music.py.
"""
import argparse, base64, json, os, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TRACK_MODEL = "lyria-3.5"
JINGLE_MODEL = "lyria-3-clip-preview"
PRICE = {TRACK_MODEL: 0.08, JINGLE_MODEL: 0.04}
API = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"


def jobs(cfg, only):
    """(model, file name, prompt) for every take of every cue."""
    for take in cfg["takes"]:
        for key, desc in cfg["tracks"].items():
            if not only or key in only:
                yield TRACK_MODEL, f"{key}_{take}", f"{desc} {cfg['style']}"
        for key, desc in cfg["jingles"].items():
            if not only or key in only:
                yield JINGLE_MODEL, f"{key}_{take}", f"{desc} {cfg['jingle_style']}"


def generate(model, prompt):
    """The audio bytes and their file extension, or None."""
    body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}]}
    for attempt in range(3):
        req = urllib.request.Request(API % model, data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json", "x-goog-api-key": os.environ["GEMINI_API_KEY"]})
        try:
            reply = json.load(urllib.request.urlopen(req, timeout=600))
            break
        except urllib.error.HTTPError as e:
            print("  error", e.code, e.read().decode()[:300])
            time.sleep(10 * (attempt + 1))
    else:
        return None
    for c in reply.get("candidates", []):
        for p in c.get("content", {}).get("parts", []):
            if "inlineData" in p:
                ext = "wav" if "wav" in p["inlineData"]["mimeType"] else "mp3"
                return base64.b64decode(p["inlineData"]["data"]), ext
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--cues", default=os.path.join(HERE, "lyria_cues.json"))
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--budget", type=float, default=5.0)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    cfg = json.load(open(a.cues))
    os.makedirs(a.out, exist_ok=True)
    todo = [j for j in jobs(cfg, set(a.only))
            if not any(os.path.exists(os.path.join(a.out, f"{j[1]}.{e}")) for e in ("mp3", "wav"))]
    cost = sum(PRICE[m] for m, _, _ in todo)
    print(f"{len(todo)} to make, about ${cost:.2f}")
    if a.dry_run:
        return
    spent = 0.0
    for model, name, prompt in todo:
        if spent + PRICE[model] > a.budget:
            sys.exit(f"budget ${a.budget} reached")
        got = generate(model, prompt)
        spent += PRICE[model]
        if got is None:
            print("  no audio for", name)
            continue
        data, ext = got
        open(os.path.join(a.out, f"{name}.{ext}"), "wb").write(data)
        print(f"saved {name}.{ext} (about ${spent:.2f})")


if __name__ == "__main__":
    main()
