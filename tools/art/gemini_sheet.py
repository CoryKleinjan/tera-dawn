#!/usr/bin/env python3
"""Generate one art sheet with Google's Gemini image model, straight from a prompt file.

This does what Cory does by hand in ChatGPT: attach the references, paste Message 0,
(optionally) paste a layout message like Message U, then paste one batch. The result is
saved next to his uploads in the project's art-sheets folder, ready to be checked and
wired in like any other sheet (art/source/ + a manifest, see art/sheets/README.md).

    python3 tools/art/gemini_sheet.py PROMPTS.md W1 --dry-run   # show prompt and refs, no call
    python3 tools/art/gemini_sheet.py PROMPTS.md W1             # one paid call, saves one PNG
    python3 tools/art/gemini_sheet.py PROMPTS.md U3 --with U --ref art-sheets/ui_u1.png
    python3 tools/art/gemini_sheet.py --list-models             # image models this key can use

PROMPTS.md is a file in art-prompts/ (a bare name like tera-dawn-chatgpt-art-prompts-8.md
is looked up there). The batch is found by its fenced block starting "Batch <ID>:".
References come from the file's own "Attach" lines (the intro's and the batch's), plus any
--ref, looked up by name in art-prompts/part-*-references/, art-sheets/ and the repo.

Every run is ONE request and never retries, because each image costs money
(about $0.10 at 2K with gemini-3.1-flash-image). Needs GEMINI_API_KEY in the environment
and generativelanguage.googleapis.com allowed by the network policy. Standard library only
(plus Pillow, which the other art tools already use).
"""
import argparse
import base64
import glob
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
PROJECT_FILES = os.environ.get("TD_PROJECT_FILES", "/mnt/project-files")
PROMPTS_DIR = os.path.join(PROJECT_FILES, "art-prompts")
OUT_DIR = os.path.join(PROJECT_FILES, "art-sheets")

API = "https://generativelanguage.googleapis.com/v1beta"
DEFAULT_MODEL = "gemini-3.1-flash-image"
# Aspect ratios the image models accept; the request uses the one closest to the batch's own reference.
ASPECTS = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]
# What the model "said" after Message 0, so the batch reads like the next turn of the chat.
READY_REPLY = "Ready. Chibi HD-2D pixel art matching the attached hero, on flat magenta #FF00FF, exact labelled grids."

FENCE = re.compile(r"^```[^\n]*\n(.*?)^```[ \t]*$", re.S | re.M)
HEADING = re.compile(r"^#{2,3} .*$", re.M)
PNG_NAME = re.compile(r"`([^`\s]+\.png)`")
SAVE_NAME = re.compile(r"(?:Save as|Name it:?\**)\s*`([^`]+\.png)`", re.I)


# --- Reading the prompt file ------------------------------------------------------------

class PromptFile:
    """A prompt part split into fenced messages, each with the plain text around it."""

    def __init__(self, path):
        self.path = path
        self.text = open(path, encoding="utf-8").read()
        self.fences = list(FENCE.finditer(self.text))
        m = re.search(r"part-?(\d+)|prompts-(\d+)", os.path.basename(path))
        self.part = (m.group(1) or m.group(2)) if m else "1"

    def message(self, letter):
        """(fenced block, attached references) for the '## Message <letter>' section."""
        head = re.search(r"^#{2,3} Message %s\b.*$" % re.escape(letter), self.text, re.M)
        if not head:
            sys.exit("No '## Message %s' section in %s" % (letter, self.path))
        fence = next((f for f in self.fences if f.start() > head.end()), None)
        if not fence:
            sys.exit("Message %s has no fenced block" % letter)
        refs = [n for l in self.text[head.end():fence.start()].splitlines()
                if "attach" in l.lower() for n in PNG_NAME.findall(l)]
        return fence.group(1).strip(), refs

    def batch(self, batch_id):
        """(prompt text, context text) for the fenced block that starts 'Batch <id>:'."""
        want = re.compile(r"^Batch %s\s*:" % re.escape(batch_id), re.I)
        for i, f in enumerate(self.fences):
            if want.match(f.group(1).lstrip()):
                return f.group(1).strip(), self._context(i)
        sys.exit("No fenced block starting 'Batch %s:' in %s" % (batch_id, self.path))

    def _context(self, i):
        # The batch's Attach/Save line sits either under its own heading (before the fence)
        # or right after the fence (the P1-P8 style, several batches under one heading).
        start = self.fences[i - 1].end() if i else 0
        before = self.text[start:self.fences[i].start()]
        heads = list(HEADING.finditer(before))
        if heads:
            return before[heads[-1].start():]
        end = self.fences[i + 1].start() if i + 1 < len(self.fences) else len(self.text)
        after = self.text[self.fences[i].end():end]
        cut = HEADING.search(after)
        return after[:cut.start()] if cut else after

    def common_refs(self):
        """References every chat attaches: the intro's Attach lines and 'every chat' lines."""
        first = HEADING.search(self.text)
        intro = self.text[:first.start()] if first else ""
        lines = [l for l in intro.splitlines() if "attach" in l.lower()]
        what = re.search(r"^## What to attach.*?(?=^## )", self.text, re.M | re.S)
        if what:
            lines += [l for l in what.group(0).splitlines() if "every chat" in l.lower()]
        names = [n for l in lines for n in PNG_NAME.findall(l)]
        # Message 0 always says the hero is attached; he is the style reference for all art.
        return names if "hero.png" in names else ["hero.png"] + names


# --- Finding reference images -----------------------------------------------------------

def find_ref(name, part):
    """Path of a reference named in a prompt file, or None."""
    if os.path.isabs(name) and os.path.exists(name):
        return name
    base = os.path.basename(name)
    stem = os.path.splitext(base)[0]
    candidates = [
        os.path.join(PROJECT_FILES, name),
        os.path.join(ROOT, name),
        os.path.join(PROMPTS_DIR, "part-%s-references" % part, base),
        *sorted(glob.glob(os.path.join(PROMPTS_DIR, "part-*-references", base)), reverse=True),
        os.path.join(OUT_DIR, base),
        os.path.join(ROOT, "art", "source", base),
        os.path.join(ROOT, "art", "reference", base),
        # A sheet this tool made earlier (e.g. B2 attaches the B1 result).
        *sorted(glob.glob(os.path.join(OUT_DIR, stem + "_gemini*.png")), reverse=True),
    ]
    return next((c for c in candidates if os.path.isfile(c)), None)


def collect_refs(prompts, context, save_name, extra):
    # The batch's own references go last: the output's aspect ratio follows the last one.
    names = prompts.common_refs() + extra + [n for n in PNG_NAME.findall(context) if n != save_name]
    paths, missing = [], []
    for n in dict.fromkeys(names):
        p = find_ref(n, prompts.part)
        if p is None:
            missing.append(n)
        elif p not in paths:
            paths.append(p)
    return paths, missing


def closest_aspect(path):
    w, h = Image.open(path).size
    return min(ASPECTS, key=lambda a: abs(int(a.split(":")[0]) / int(a.split(":")[1]) - w / h))


# --- Talking to Gemini ------------------------------------------------------------------

def api_key():
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        sys.exit("GEMINI_API_KEY is not set. Add it to the cloud environment's variables.")
    return key


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"x-goog-api-key": api_key(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        if e.code == 403 and "generativelanguage" not in detail:
            detail += "\n(A 403 with no Google error usually means the network policy blocks the host.)"
        sys.exit("Gemini API error %d:\n%s" % (e.code, detail[:2000]))


def image_part(path):
    data = open(path, "rb").read()
    return {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(data).decode()}}


def build_request(message0, layout, batch, refs, aspect, size):
    first = [image_part(p) for p in refs]
    first.append({"text": message0 + ("\n\n" + layout if layout else "")})
    return {
        "contents": [
            {"role": "user", "parts": first},
            {"role": "model", "parts": [{"text": READY_REPLY}]},
            {"role": "user", "parts": [{"text": batch}]},
        ],
        "generationConfig": {
            "responseModalities": ["TEXT", "IMAGE"],
            "imageConfig": {"aspectRatio": aspect, "imageSize": size},
        },
    }


def list_models():
    page, token = 0, ""
    while page < 10:
        resp = call("GET", "/models?pageSize=100" + ("&pageToken=" + token if token else ""))
        for m in resp.get("models", []):
            name = m["name"].split("/", 1)[-1]
            if "image" in name or "imagen" in name:
                print(name, "-", m.get("displayName", ""))
        token = resp.get("nextPageToken", "")
        page += 1
        if not token:
            break


def out_path(save_name, batch_id, part):
    stem = os.path.splitext(os.path.basename(save_name))[0] if save_name else "part%s_%s" % (part, batch_id.lower())
    path = os.path.join(OUT_DIR, stem + "_gemini.png")
    n = 2
    while os.path.exists(path):  # never overwrite an earlier try
        path = os.path.join(OUT_DIR, "%s_gemini_%d.png" % (stem, n))
        n += 1
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("prompts", nargs="?", help="prompt file (path, or a name in art-prompts/)")
    ap.add_argument("batch", nargs="?", help="batch id, e.g. W1 or U3")
    ap.add_argument("--with", dest="layout", metavar="LETTER",
                    help="also send '## Message LETTER' after Message 0 (e.g. U, P, W, M, N)")
    ap.add_argument("--ref", action="append", default=[], help="extra reference image (repeatable)")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--aspect", choices=ASPECTS, help="default: closest to the batch's own reference")
    ap.add_argument("--size", default="2K", choices=["1K", "2K", "4K"])
    ap.add_argument("--out", help="output path (default: art-sheets/<save name>_gemini.png)")
    ap.add_argument("--dry-run", action="store_true", help="print what would be sent; no API call")
    ap.add_argument("--list-models", action="store_true", help="list image models this key can use")
    args = ap.parse_args()

    if args.list_models:
        list_models()
        return
    if not (args.prompts and args.batch):
        ap.error("give a prompt file and a batch id")

    path = args.prompts if os.path.exists(args.prompts) else os.path.join(PROMPTS_DIR, args.prompts)
    prompts = PromptFile(path)
    batch, context = prompts.batch(args.batch)
    m = SAVE_NAME.search(context)
    save_name = m.group(1) if m else None
    message0, _ = prompts.message("0")
    layout, layout_refs = prompts.message(args.layout) if args.layout else (None, [])
    refs, missing = collect_refs(prompts, context, save_name, layout_refs + args.ref)
    if missing:
        sys.exit("Can't find these references: %s (pass the right file with --ref)" % ", ".join(missing))
    aspect = args.aspect or (closest_aspect(refs[-1]) if refs else "1:1")
    dest = args.out or out_path(save_name, args.batch, prompts.part)

    print("Batch %s from %s" % (args.batch, os.path.basename(path)))
    print("References:", ", ".join(os.path.basename(p) for p in refs) or "none")
    print("Model %s, %s, aspect %s -> %s" % (args.model, args.size, aspect, dest))
    if args.dry_run:
        print("\n--- Message 0 ---\n" + message0)
        if layout:
            print("\n--- Message %s ---\n%s" % (args.layout, layout))
        print("\n--- Batch ---\n" + batch)
        return

    body = build_request(message0, layout, batch, refs, aspect, args.size)
    resp = call("POST", "/models/%s:generateContent" % args.model, body)
    parts = (resp.get("candidates") or [{}])[0].get("content", {}).get("parts", [])
    for p in parts:
        if p.get("text"):
            print("Gemini says:", p["text"].strip())
    images = [p for p in parts if "inlineData" in p or "inline_data" in p]
    if not images:
        reason = (resp.get("candidates") or [{}])[0].get("finishReason") or resp.get("promptFeedback")
        sys.exit("No image came back (%s)." % reason)
    data = base64.b64decode((images[-1].get("inlineData") or images[-1]["inline_data"])["data"])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    Image.open(io.BytesIO(data)).save(dest)  # normalise to PNG whatever the API sent
    usage = resp.get("usageMetadata", {})
    print("Saved %s (%dx%d), tokens %s" % (dest, *Image.open(dest).size, usage.get("totalTokenCount", "?")))


if __name__ == "__main__":
    main()
