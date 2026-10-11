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

For anything more than a one-off test, add the sheet to tools/art/gemini_pass.json and make it
with tools/art/gemini_pass.py, which uses Gemini's batch mode at half the price. Every run of
this script is ONE request and never retries, because each image costs money
(about $0.10 at 2K with gemini-3.1-flash-image). Needs GEMINI_API_KEY in the environment
and generativelanguage.googleapis.com allowed by the network policy. Standard library only
(plus Pillow, which the other art tools already use).
"""
import argparse
import base64
import glob
import http.client as http_client
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


LIST_ITEM = re.compile(r"^\s*(?:\d+\.|-)\s+(.+)$")


def pick_item(batch, item):
    """The batch with only `item`'s line left in its list of items."""
    want = re.sub(r"^\d+\.\s*", "", item).upper()
    kept = []
    for line in batch.splitlines():
        m = LIST_ITEM.match(line)
        if m and m.group(1).split(":")[0].strip().upper() != want:
            continue
        kept.append(line)
    text = re.sub(r"\s*Start with [^.]*? after\.", "", "\n".join(kept))  # H1: "I'll ask for the next after"
    return text + "\n\nDraw ONLY %s in this image, nothing else from my list." % want


class GeminiError(Exception):
    """A request that could not be made or came back without an image."""


# --- Reading the prompt file ------------------------------------------------------------

class PromptFile:
    """A prompt part split into fenced messages, each with the plain text around it."""

    def __init__(self, path):
        self.path = path
        with open(path, encoding="utf-8") as f:
            self.text = f.read()
        self.fences = list(FENCE.finditer(self.text))
        m = re.search(r"part-?(\d+)|prompts-(\d+)", os.path.basename(path))
        self.part = (m.group(1) or m.group(2)) if m else "1"

    def message(self, letter):
        """(fenced block, attached references) for the '## Message <letter>' section."""
        head = re.search(r"^#{2,3} Message %s\b.*$" % re.escape(letter), self.text, re.M)
        if not head:
            raise GeminiError("No '## Message %s' section in %s" % (letter, self.path))
        fence = next((f for f in self.fences if f.start() > head.end()), None)
        if not fence:
            raise GeminiError("Message %s has no fenced block" % letter)
        refs = [n for l in self.text[head.end():fence.start()].splitlines()
                if "attach" in l.lower() for n in PNG_NAME.findall(l)]
        return fence.group(1).strip(), refs

    def batch(self, batch_id):
        """(prompt text, context text) for the fenced block that starts 'Batch <id>:'."""
        want = re.compile(r"^Batch %s\s*:" % re.escape(batch_id), re.I)
        for i, f in enumerate(self.fences):
            if want.match(f.group(1).lstrip()):
                return f.group(1).strip(), self._context(i)
        # Part 9 style: the fence starts "R1. Room:", or follows a "### B1. ..." heading.
        own = re.compile(r"^%s[.:]\s" % re.escape(batch_id))
        for i, f in enumerate(self.fences):
            if own.match(f.group(1).lstrip()):
                return f.group(1).strip(), self._context(i)
        head = re.search(r"^#{2,3} %s[.:]\s.*$" % re.escape(batch_id), self.text, re.M)
        if head:
            for i, f in enumerate(self.fences):
                if f.start() > head.end():
                    return f.group(1).strip(), self._context(i)
        raise GeminiError("No fenced block starting 'Batch %s:' in %s" % (batch_id, self.path))

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

# Old names the early prompt parts use for files that are now called something else.
REF_ALIASES = {"hero_spritesheet.png": "hero_main.png", "environment-tileset.png": "meadow_tileset.png"}


def find_ref(name, part):
    """Path of a reference named in a prompt file, or None."""
    if os.path.isabs(name) and os.path.exists(name):
        return name
    base = REF_ALIASES.get(os.path.basename(name), os.path.basename(name))
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
        *sorted(glob.glob(os.path.join(OUT_DIR, "gemini-pass-*", base)), reverse=True),
    ]
    return next((c for c in candidates if os.path.isfile(c)), None)


def collect_refs(prompts, context, save_name, extra, outputs=(), later=()):
    """(paths, missing). outputs are file names this request makes (never references); later
    are files another request will make, which are left out quietly when they don't exist yet."""
    # The batch's own references go last: the output's aspect ratio follows the last one.
    # Names on "Save as" lines and templates like mon_<name>.png are outputs, not references.
    outputs = set(outputs) | {save_name} | {n for line in context.splitlines()
                                             if line.startswith("#") or re.search(r"save|name it", line, re.I)
                                             for n in PNG_NAME.findall(line)}
    names = prompts.common_refs() + list(extra) + [n for n in PNG_NAME.findall(context)
                                                   if n not in outputs and "<" not in n]
    paths, missing = [], []
    for n in dict.fromkeys(names):
        p = find_ref(n, prompts.part)
        if p is None:
            if os.path.basename(n) not in later:
                missing.append(n)
        elif p not in paths:
            paths.append(p)
    return paths, missing


def closest_aspect(path):
    with Image.open(path) as im:
        return closest_aspect_of(*im.size)


def closest_aspect_of(w, h):
    """The aspect ratio Gemini offers that is closest to w x h."""
    return min(ASPECTS, key=lambda a: abs(int(a.split(":")[0]) / int(a.split(":")[1]) - w / h))


# --- Talking to Gemini ------------------------------------------------------------------

def api_key():
    key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if not key:
        raise GeminiError("GEMINI_API_KEY is not set. Add it to the cloud environment's variables.")
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
        raise GeminiError("Gemini API error %d:\n%s" % (e.code, detail[:2000]))


def http(url, data=None, headers=None, method=None):
    """A raw request to the API host (file uploads and downloads); returns (body, headers)."""
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"x-goog-api-key": api_key(), **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.read(), r.headers
    except urllib.error.HTTPError as e:
        raise GeminiError("Gemini API error %d:\n%s" % (e.code, e.read().decode(errors="replace")[:2000]))


def upload_file(data, mime, display_name):
    """Upload bytes with the Files API (kept 48 hours); returns the file resource."""
    base = API.replace("/v1beta", "/upload/v1beta") + "/files"
    _, h = http(base, json.dumps({"file": {"display_name": display_name}}).encode(), {
        "X-Goog-Upload-Protocol": "resumable", "X-Goog-Upload-Command": "start",
        "X-Goog-Upload-Header-Content-Length": str(len(data)),
        "X-Goog-Upload-Header-Content-Type": mime, "Content-Type": "application/json"}, "POST")
    body, _ = http(h["X-Goog-Upload-URL"], data, {
        "X-Goog-Upload-Command": "upload, finalize", "X-Goog-Upload-Offset": "0",
        "Content-Length": str(len(data))}, "POST")
    return json.loads(body)["file"]


def download_file(name, attempts=3):
    """The bytes of a Files API file, e.g. a batch job's results (files/...). Downloads are free,
    so a cut-off transfer is tried again."""
    url = API.replace("/v1beta", "/download/v1beta") + "/%s:download?alt=media" % name
    for attempt in range(attempts):
        try:
            return http(url)[0]
        except http_client.IncompleteRead:
            if attempt == attempts - 1:
                raise GeminiError("The download of %s kept getting cut off." % name)


def image_part(path):
    with open(path, "rb") as f:
        data = f.read()
    return {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(data).decode()}}


def build_request(message0, layout, batch, refs, aspect, size, image=image_part):
    first = [image(p) for p in refs]
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


def generate(prompts_file, batch_id, layout=None, extra_refs=(), model=DEFAULT_MODEL, size="2K",
             aspect=None, out=None, extra_text=None, pick=None, later=(), dry_run=False, log=print,
             prepare=None):
    """Make one sheet: ONE request, never retried. Returns {"path", "refs", "aspect", "usage"}.

    prepare, if given, is a function that turns a reference path into a request part (e.g. an
    uploaded file); the request is then built and returned as "body" instead of being sent, for
    Gemini's batch mode.

    extra_text is appended to the batch (e.g. the full pass's consistency rules). pick names one
    item of a batch that lists several to draw one per image (H1's styles, T1's tops): the other
    items' lines are dropped and the request says to draw only that one. later names files other
    requests make (e.g. this batch attaches a sheet the pass hasn't made yet): if one doesn't exist
    yet it is left out instead of stopping the request."""
    path = prompts_file if os.path.exists(prompts_file) else os.path.join(PROMPTS_DIR, prompts_file)
    prompts = PromptFile(path)
    batch, context = prompts.batch(batch_id)
    if pick:
        batch = pick_item(batch, pick)
    if extra_text:
        batch += "\n\n" + extra_text
    m = SAVE_NAME.search(context)
    save_name = m.group(1) if m else None
    message0, _ = prompts.message("0")
    layout_text, layout_refs = prompts.message(layout) if layout else (None, [])
    outputs = {os.path.basename(out)} if out else set()
    refs, missing = collect_refs(prompts, context, save_name, layout_refs + list(extra_refs), outputs, later)
    if missing:
        raise GeminiError("Can't find these references: %s (pass the right file with --ref)" % ", ".join(missing))
    aspect = aspect or (closest_aspect(refs[-1]) if refs else "1:1")
    dest = out or out_path(save_name, batch_id, prompts.part)

    log("Batch %s from %s" % (batch_id, os.path.basename(path)))
    log("References: " + (", ".join(os.path.basename(p) for p in refs) or "none"))
    log("Model %s, %s, aspect %s -> %s" % (model, size, aspect, dest))
    result = {"path": None, "refs": refs, "aspect": aspect, "usage": {}}
    if dry_run:
        log("\n--- Message 0 ---\n" + message0)
        if layout_text:
            log("\n--- Message %s ---\n%s" % (layout, layout_text))
        log("\n--- Batch ---\n" + batch)
        return result

    if prepare:
        result["body"] = build_request(message0, layout_text, batch, refs, aspect, size, prepare)
        result["dest"] = dest
        return result
    body = build_request(message0, layout_text, batch, refs, aspect, size)
    resp = call("POST", "/models/%s:generateContent" % model, body)
    result["usage"] = resp.get("usageMetadata", {})
    result["path"] = save_image(resp, dest, log)
    return result


def save_image(resp, dest, log=print):
    """Save the image in a generateContent response as a PNG at dest; returns dest."""
    parts = (resp.get("candidates") or [{}])[0].get("content", {}).get("parts", [])
    for p in parts:
        if p.get("text"):
            log("Gemini says: " + p["text"].strip())
    images = [p for p in parts if "inlineData" in p or "inline_data" in p]
    if not images:
        reason = (resp.get("candidates") or [{}])[0].get("finishReason") or resp.get("promptFeedback")
        raise GeminiError("No image came back (%s)." % reason)
    data = base64.b64decode((images[-1].get("inlineData") or images[-1]["inline_data"])["data"])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    Image.open(io.BytesIO(data)).save(dest)  # normalise to PNG whatever the API sent
    log("Saved %s (%dx%d), tokens %s" % (dest, *Image.open(dest).size,
                                          resp.get("usageMetadata", {}).get("totalTokenCount", "?")))
    return dest


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

    if not (args.list_models or (args.prompts and args.batch)):
        ap.error("give a prompt file and a batch id")
    try:
        if args.list_models:
            list_models()
            return
        generate(args.prompts, args.batch, args.layout, args.ref, args.model, args.size,
                 args.aspect, args.out, dry_run=args.dry_run)
    except GeminiError as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main()
