#!/usr/bin/env python3
"""Run the whole Gemini art pass: every sheet in tools/art/gemini_pass.json, once each.

    python3 tools/art/gemini_pass.py --dry-run          # the waves batch mode would send and their cost, free
    python3 tools/art/gemini_pass.py --wait             # make everything still missing, batch mode (paid)
    python3 tools/art/gemini_pass.py --redo ID --wait   # make one sheet again (ask Cory first unless it came back broken)
    python3 tools/art/gemini_pass.py --report           # rebuild report.md and the contact sheet
    python3 tools/art/gemini_pass.py --now --dry-run    # check every entry's batch and refs, free
    python3 tools/art/gemini_pass.py --now --limit 3    # one by one at full price, no waiting

Results go to art-sheets/gemini-pass-1/ in the project files, never into the game. Each sheet
is ONE request: a sheet that already has a result, or whose request failed, is skipped on
later runs, so running again only makes what is missing. Redoing a sheet is deliberate:
pass --redo ID (Cory decides which sheets get redone).

The run stops before it would go over the budget (the list's "budget", or --budget). Sheets
whose "anchor" is another entry wait for that entry and attach its result, so a family of
sheets matches one model. Every request gets CONSISTENCY added to its batch text, which keeps
the prompt files themselves usable in ChatGPT. Each result is checked by sheet_check.py.

Batch mode is the default (Cory: all art goes through it to keep costs down). It costs half
as much and takes longer (Google promises results within a day; usually
far sooner). Sheets go up in waves: every sheet whose anchor is made goes in the next wave, so a
family's anchor comes back before the sheets that attach it. --batch does one step (collect a
finished wave, then submit the next) and exits; --wait keeps stepping until everything is made.
--limit and --only apply to --now runs.
References are uploaded once with the Files API, which keeps them for 48 hours.
"""
import argparse
import hashlib
import json
import os
import sys
import threading
import time
import urllib.parse
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gemini_sheet  # noqa: E402
import sheet_check  # noqa: E402

LIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gemini_pass.json")
OUT = os.path.join(gemini_sheet.OUT_DIR, "gemini-pass-1")
STATE = os.path.join(OUT, "state.json")
# Estimated dollars per image at 2K: Google's list price ($0.134 for Pro) plus the attached references.
PRICE = {"gemini-3-pro-image": 0.136, "gemini-3-pro-image-preview": 0.136,
         "gemini-3.1-flash-image": 0.11, "gemini-3.1-flash-image-preview": 0.11}
BATCH_DISCOUNT = 0.5  # batch mode bills half the standard price
SIZE_PRICE = {"1K": 1.0, "2K": 1.0, "4K": 1.8}  # 4K output costs about 1.8x the 2K price
WORKERS = 4
MAGENTA = (255, 0, 255)
FILE_LIFETIME = 40 * 3600  # re-upload references older than this (Gemini keeps files 48 hours)

CONSISTENCY = """Consistency rules for this sheet (follow them strictly):
- Every cell shows the SAME character or object as the other cells and as any attached sheet of it: the same height, head size, proportions, outline thickness and exact colours. Only the pose or the item changes from cell to cell.
- If a sheet with the same grid is attached, trace its poses, cell positions and sprite sizes exactly.
- The same soft painted style (smooth painted shading, no visible pixels), the same thin dark plum-brown outline, the same light from the upper left and the same warm-gold rim light in every cell.
- Characters and creatures stand on one shared baseline: the feet sit the same distance above the bottom edge of every cell.
- The background of the WHOLE image, inside every cell too, is one flat pure magenta #FF00FF (RGB 255, 0, 255): not grey, white, pink, lilac or a darker purple, with no shadows, gradients or coloured panels. No magenta or pink-purple inside any sprite."""
GRID_RULE = "- Draw exactly {rows} rows x {cols} columns = {n} equal cells, every cell filled in the order given."
# Sheets with an "edit" entry send ONE image (its "base") and a short instruction instead of the
# prompt-file chat (plus any "refs" after it). Gemini keeps an edited image's layout far better
# than it traces an attached one, and a result can be edited again to fix only its bad cells.
EDIT_RULES = """This is an edit of the attached image, not a new drawing. Keep the image's size, grid, cell borders and labels, and every figure's position, size and pose, exactly as they are; change only what is asked above. Any added art matches the style asked for above, with the same dark plum-brown outline. The background stays one flat pure magenta #FF00FF (RGB 255, 0, 255) everywhere: never grey, pink or lilac. Answer with the edited image."""
# Edits with "new_view": true redraw the base from another viewpoint (a 3/4 building as a flat
# side-on front), so they get these rules instead: EDIT_RULES would keep the old angle.
VIEW_RULES = """This is a redraw of the attached image from a new viewpoint, not a copy: the new view asked above is the whole point, and an answer that keeps the old angle is wrong. Keep the image's size, keep the subject centred at about the same height, and keep its design, colours and style. Any art matches the style asked for above, with the same dark plum-brown outline. The background stays one flat pure magenta #FF00FF (RGB 255, 0, 255) everywhere: never grey, pink or lilac. Answer with the redrawn image."""


def find_key(obj, key):
    """The first value of `key` anywhere in a nested JSON object."""
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        obj = list(obj.values())
    if isinstance(obj, list):
        for v in obj:
            found = find_key(v, key)
            if found:
                return found
    return None


def load_list():
    with open(LIST, encoding="utf-8") as f:
        return json.load(f)


def load_state():
    if os.path.exists(STATE):
        with open(STATE, encoding="utf-8") as f:
            return json.load(f)
    return {}


class Pass:
    def __init__(self, spec, budget, dry_run=False):
        self.spec = spec
        self.sheets = spec["sheets"]
        self.by_id = {s["id"]: s for s in self.sheets}
        self.saves = {s["save"] for s in self.sheets if s.get("save")}
        self.model = spec.get("model", gemini_sheet.DEFAULT_MODEL)
        self.size = spec.get("size", "2K")
        self.price = PRICE.get(self.model, 0.25)
        self.budget = budget
        self.dry_run = dry_run
        self.state = load_state()
        self.lock = threading.Lock()

    # --- bookkeeping --------------------------------------------------------------------

    def price_for(self, sheet):
        """Full price of one try at `sheet`, at its own output size if it sets one."""
        return self.price * SIZE_PRICE.get(sheet.get("size", self.size), 1.0)

    def spent(self):
        """Dollars spent, plus what batch jobs still running will cost."""
        done = sum(v.get("cost", 0) for k, v in self.state.items() if not k.startswith("_"))
        jobs = self.state.get("_jobs", [])
        return done + self.state.get("_redone", {}).get("cost", 0) + \
            sum(self.price_for(self.by_id.get(i, {})) * BATCH_DISCOUNT
                for j in jobs if not j.get("collected") for i in j["ids"])

    def save(self):
        os.makedirs(OUT, exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.state, f, indent=1)
        os.replace(tmp, STATE)

    def done(self, sid):
        return sid in self.state

    def queued(self):
        return {i for j in self.state.get("_jobs", []) if not j.get("collected") for i in j["ids"]}

    def anchor_result(self, sheet):
        a = sheet.get("anchor")
        return self.state.get(a, {}).get("path") if a else None

    # --- one sheet ----------------------------------------------------------------------

    def request_text(self, sheet):
        text = CONSISTENCY
        if sheet.get("cells"):
            rows, cols = sheet["cells"]
            text += "\n" + GRID_RULE.format(rows=rows, cols=cols, n=rows * cols)
        if sheet.get("extra"):
            text += "\n" + sheet["extra"]
        return text

    @staticmethod
    def pick(sheet):
        """The one item to draw, for batches that list several (fill keys item, style, top)."""
        fill = sheet.get("fill") or {}
        return next((fill[k] for k in ("item", "style", "top") if k in fill), None)

    def refs_for(self, sheet):
        refs = list(sheet.get("refs", []))
        anchor = self.anchor_result(sheet)
        if anchor:
            refs.append(anchor)
        return refs

    @staticmethod
    def out_for(sheet):
        stem = os.path.splitext(sheet.get("save") or sheet["id"] + ".png")[0]
        out, n = os.path.join(OUT, stem + ".png"), 2
        while os.path.exists(out):  # a redo keeps the earlier result
            out = os.path.join(OUT, "%s_%d.png" % (stem, n))
            n += 1
        return out

    def run_one(self, sheet):
        refs = self.refs_for(sheet)
        anchor = self.anchor_result(sheet)
        out = self.out_for(sheet)
        lines = []
        started = time.time()
        try:
            res = gemini_sheet.generate(
                sheet["prompts"], sheet["batch"], sheet.get("with"), refs, self.model, self.size,
                sheet.get("aspect"), out, self.request_text(sheet), self.pick(sheet),
                later=self.saves - {sheet.get("save")}, dry_run=self.dry_run, log=lines.append)
        except (gemini_sheet.GeminiError, OSError) as e:
            # Gemini bills an answer that came back without an image, not a refused request.
            billed = not self.dry_run and "No image came back" in str(e)
            return {"error": str(e).splitlines()[0][:300], "cost": self.price if billed else 0, "log": lines}
        entry = {"path": res["path"], "cost": 0 if self.dry_run else self.price,
                 "seconds": round(time.time() - started), "refs": [os.path.basename(r) for r in res["refs"]],
                 "aspect": res["aspect"], "log": lines[-2:]}
        if res["path"]:
            entry["check"] = sheet_check.check(
                res["path"], sheet.get("cells"), sheet.get("kind", "still"),
                self.replaced(sheet) or anchor, sheet.get("must_have"))
        return entry

    def recheck(self):
        """Run sheet_check again on every result (free), e.g. after the checker changed."""
        for s in self.sheets:
            e = self.state.get(s["id"])
            if e and e.get("path") and os.path.exists(e["path"]):
                e["check"] = sheet_check.check(e["path"], s.get("cells"), s.get("kind", "still"),
                                               self.replaced(s) or self.anchor_result(s), s.get("must_have"))
        self.save()
        self.report()

    def replaced(self, sheet):
        r = sheet.get("replaces")
        path = os.path.join(gemini_sheet.ROOT, r) if r else None
        return path if path and os.path.exists(path) else None

    # --- the whole pass -----------------------------------------------------------------

    def run(self, limit=None, only=None):
        todo = [s for s in self.sheets if s.get("batch") and not self.done(s["id"])
                and (not only or s["id"] in only) and not s.get("edit")]  # edits run in batch mode
        if limit:
            todo = todo[:limit]
        print("%d sheets to make; spent so far $%.2f of $%.2f" % (len(todo), self.spent(), self.budget))
        pending = list(todo)
        running = {}
        with ThreadPoolExecutor(WORKERS) as pool:
            while pending or running:
                for sheet in list(pending):
                    if len(running) >= WORKERS:
                        break
                    a = sheet.get("anchor")
                    waiting = a and a in self.by_id and not self.done(a) and \
                        (any(s["id"] == a for s in pending) or a in running.values())
                    if waiting:
                        continue
                    if not self.dry_run and self.spent() + (len(running) + 1) * self.price > self.budget:
                        print("Stopping: the next sheet would go over the $%.2f budget." % self.budget)
                        pending = []
                        break
                    pending.remove(sheet)
                    running[pool.submit(self.run_one, sheet)] = sheet["id"]
                if not running:
                    break
                finished, _ = wait(list(running), return_when=FIRST_COMPLETED)
                for fut in finished:
                    sid = running.pop(fut)
                    entry = fut.result()
                    with self.lock:
                        if self.dry_run:
                            status = "error: " + entry["error"] if "error" in entry else "ok"
                            print("%-28s %s" % (sid, status))
                            continue
                        self.state[sid] = entry
                        self.save()
                    status = entry.get("error") or entry.get("check", {}).get("status", "?")
                    print("%-28s %-6s $%.2f total" % (sid, status, self.spent()))
        if not self.dry_run:
            self.report()

    # --- batch mode ---------------------------------------------------------------------

    def next_wave(self):
        """Sheets that can go now: not made, not queued, and their anchor (if it runs) is made."""
        queued = self.queued()
        wave = []
        for s in self.sheets:
            if not s.get("batch") or self.done(s["id"]) or s["id"] in queued:
                continue
            a = s.get("anchor")
            if a and self.by_id.get(a, {}).get("batch") and not self.done(a):
                continue
            wave.append(s)
        return wave

    def edit_base(self, sheet):
        """The edit's base image padded with its background colour to the closest aspect Gemini
        offers, so the answer can be scaled back and cropped to the base exactly."""
        base = os.path.join(gemini_sheet.ROOT, sheet["edit"]["base"])
        im = Image.open(base)
        # "base_crop": [x0, y0, x1, y1] of the base to send on its own (one piece of a sheet)
        crop = sheet["edit"].get("base_crop")
        if im.mode in ("RGBA", "LA", "P"):
            # a cut sprite: set it on magenta, the background every sheet is drawn on
            im = im.convert("RGBA")
            flat = Image.new("RGBA", im.size, MAGENTA + (255,))
            flat.alpha_composite(im)
            im, background = flat.convert("RGB"), MAGENTA
        else:
            im = im.convert("RGB")
            background = tuple(int(c) for c in sheet_check.background_color(sheet_check.load_rgb(base)))
        if crop:
            im = im.crop(tuple(crop))
        # "base_scale": enlarge the base (nearest neighbour) so the answer has room for finer pixels
        k = sheet["edit"].get("base_scale", 1.0)
        if k != 1.0:
            im = im.resize((round(im.width * k), round(im.height * k)), Image.NEAREST)
        # "base_margin": add this share of the base's size as background on every side, so a
        # redraw has room to finish a subject that runs off the edge (roof ends, chimney tops)
        m = sheet["edit"].get("base_margin", 0.0)
        if m:
            mx, my = round(im.width * m), round(im.height * m)
            framed = Image.new("RGB", (im.width + 2 * mx, im.height + 2 * my), background)
            framed.paste(im, (mx, my))
            im = framed
        w, h = im.size
        aspect = gemini_sheet.closest_aspect_of(w, h)
        a, b = map(int, aspect.split(":"))
        pw, ph = max(w, round(h * a / b)), max(h, round(w * b / a))
        padded = Image.new("RGB", (pw, ph), background)
        padded.paste(im, (0, 0))
        path = os.path.join(OUT, "_bases", sheet["id"] + ".png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        padded.save(path)
        return path, aspect, [pw, ph, w, h]

    def edit_request(self, sheet, prepare):
        base, aspect, unpad = self.edit_base(sheet)
        rules = VIEW_RULES if sheet["edit"].get("new_view") else EDIT_RULES
        body = {"contents": [{"role": "user", "parts": [
                    prepare(base)] + [prepare(os.path.join(gemini_sheet.ROOT, r)) for r in sheet["edit"].get("refs", [])] + [
                    {"text": sheet["edit"]["text"] + "\n\n" + rules}]}],
                "generationConfig": {"responseModalities": ["TEXT", "IMAGE"],
                                     "imageConfig": {"aspectRatio": aspect, "imageSize": sheet.get("size", self.size)}}}
        return body, aspect, unpad

    @staticmethod
    def unpad(path, unpad):
        """Scale an edit's answer to the padded base's size and crop the padding off."""
        pw, ph, w, h = unpad
        Image.open(path).convert("RGB").resize((pw, ph), Image.LANCZOS).crop((0, 0, w, h)).save(path)

    def file_part(self, path):
        files = self.state.setdefault("_files", {})
        with open(path, "rb") as f:
            data = f.read()
        # keyed by content too: a redo's edit base is written to the same _bases path, and the
        # old upload of that path must not be sent again (wg_hats_1_only's redo once was)
        key = "%s#%s" % (path, hashlib.sha1(data).hexdigest()[:12])
        f = files.get(key)
        if not f or time.time() - f["at"] > FILE_LIFETIME:
            res = gemini_sheet.upload_file(data, "image/png", os.path.basename(path))
            f = files[key] = {"uri": res["uri"], "at": time.time()}
        return {"file_data": {"mime_type": "image/png", "file_uri": f["uri"]}}

    def submit(self, wave):
        left, room = self.budget - self.spent(), 0
        while room < len(wave) and left >= self.price_for(wave[room]) * BATCH_DISCOUNT:
            left -= self.price_for(wave[room]) * BATCH_DISCOUNT
            room += 1
        if room < len(wave):
            print("Budget allows %d of the %d sheets in this wave." % (room, len(wave)))
            wave = wave[:room]
        if not wave:
            return False
        lines, dests, errors = [], {}, {}
        for s in wave:
            if s.get("edit"):
                body, aspect, unpad = self.edit_request(s, self.file_part)
                lines.append(json.dumps({"key": s["id"], "request": body}))
                dests[s["id"]] = {"path": self.out_for(s), "refs": [s["edit"]["base"]],
                                  "aspect": aspect, "unpad": unpad}
                continue
            log = []
            try:
                res = gemini_sheet.generate(
                    s["prompts"], s["batch"], s.get("with"), self.refs_for(s), self.model, self.size,
                    s.get("aspect"), self.out_for(s), self.request_text(s), self.pick(s),
                    later=self.saves - {s.get("save")}, log=log.append, prepare=self.file_part)
            except (gemini_sheet.GeminiError, OSError) as e:
                errors[s["id"]] = {"error": str(e).splitlines()[0][:300], "cost": 0}
                continue
            lines.append(json.dumps({"key": s["id"], "request": res["body"]}))
            dests[s["id"]] = {"path": res["dest"], "refs": [os.path.basename(r) for r in res["refs"]],
                              "aspect": res["aspect"]}
        self.state.update(errors)
        if not lines:
            self.save()
            return bool(errors)
        n = len(self.state.get("_jobs", [])) + 1
        upload = gemini_sheet.upload_file(("\n".join(lines) + "\n").encode(), "jsonl",
                                          "gemini-pass-1-wave-%d" % n)
        job = gemini_sheet.call("POST", "/models/%s:batchGenerateContent" % self.model, {
            "batch": {"display_name": "gemini-pass-1-wave-%d" % n, "input_config": {"file_name": upload["name"]}}})
        self.state.setdefault("_jobs", []).append(
            {"name": job["name"], "wave": n, "ids": list(dests), "sheets": dests, "at": time.time()})
        self.save()
        print("Submitted wave %d: %d sheets (%s)" % (n, len(dests), job["name"]))
        return True

    def collect(self):
        """Save the results of finished batch jobs. Returns how many jobs are still running."""
        running = 0
        for job in self.state.get("_jobs", []):
            if job.get("collected"):
                continue
            info = gemini_sheet.call("GET", "/" + urllib.parse.quote(job["name"]))
            meta = info.get("metadata", {})
            state = meta.get("state") or info.get("state", "")
            if not info.get("done") and not any(w in state for w in ("SUCCEEDED", "FAILED", "CANCELLED", "EXPIRED")):
                running += 1
                print("Wave %d: %s" % (job["wave"], state or "running"))
                continue
            results = find_key(info, "responsesFile")
            by_key = {}
            if results:
                for line in gemini_sheet.download_file(results).decode().splitlines():
                    if line.strip():
                        row = json.loads(line)
                        by_key[row.get("key")] = row
            for sid, meta_s in job["sheets"].items():
                each = self.price_for(self.by_id.get(sid, {})) * BATCH_DISCOUNT
                row = by_key.get(sid)
                entry = dict(meta_s)
                try:
                    if not row:
                        raise gemini_sheet.GeminiError("No result for this sheet (job %s)." % state)
                    if "error" in row:
                        raise gemini_sheet.GeminiError(json.dumps(row["error"])[:300])
                    gemini_sheet.save_image(row["response"], meta_s["path"], log=lambda *_: None)
                    if meta_s.get("unpad"):
                        self.unpad(meta_s["path"], meta_s["unpad"])
                    entry["cost"] = each
                    s = self.by_id[sid]
                    entry["check"] = sheet_check.check(meta_s["path"], s.get("cells"), s.get("kind", "still"),
                                                       self.replaced(s) or self.anchor_result(s), s.get("must_have"))
                except gemini_sheet.GeminiError as e:
                    entry = {"error": str(e).splitlines()[0][:300],
                             "cost": each if row and "response" in row else 0}
                self.state[sid] = entry
            job["collected"] = True
            self.save()
            print("Wave %d collected (%s)." % (job["wave"], state))
        return running

    def run_batch(self, wait=False):
        while True:
            running = self.collect()
            if not running:
                wave = self.next_wave()
                if not wave:
                    print("Nothing left to make. Spent about $%.2f." % self.spent())
                    self.report()
                    return
                if not self.submit(wave):
                    print("Stopping: no budget left for the next wave.")
                    self.report()
                    return
            if not wait:
                return
            time.sleep(60)

    def plan_batch(self):
        """Free: the waves batch mode would send, assuming every sheet comes back."""
        made, n = set(self.state), 0
        while True:
            wave = [s["id"] for s in self.sheets if s.get("batch") and s["id"] not in made and
                    not (s.get("anchor") and self.by_id.get(s["anchor"], {}).get("batch") and s["anchor"] not in made)]
            if not wave:
                break
            n += 1
            made |= set(wave)
            cost = sum(self.price_for(self.by_id[i]) for i in wave) * BATCH_DISCOUNT
            print("Wave %d: %d sheets, about $%.2f" % (n, len(wave), cost))

    # --- report -------------------------------------------------------------------------

    def report(self):
        rows = ["# Gemini pass 1", "",
                "Model %s at %s. Spent about $%.2f. Nothing here is in the game yet." % (self.model, self.size, self.spent()),
                "", "| Sheet | Result | What the checker found |", "| --- | --- | --- |"]
        counts = {}
        for s in self.sheets:
            e = self.state.get(s["id"])
            if not e:
                status, detail = ("not made", "") if s.get("batch") else ("no prompt", s.get("note", ""))
            elif "error" in e:
                status, detail = "error", e["error"]
            else:
                c = e.get("check", {})
                status = c.get("status", "?")
                detail = "; ".join("%s: %s" % (r["check"], r["detail"]) for r in c.get("checks", [])
                                   if r["status"] != "pass")
            counts[status] = counts.get(status, 0) + 1
            name = "[%s](%s)" % (s["id"], os.path.basename(e["path"])) if e and e.get("path") else s["id"]
            rows.append("| %s | %s | %s |" % (name, status, detail.replace("|", "/")))
        rows[2] += " " + ", ".join("%d %s" % (n, k) for k, n in sorted(counts.items())) + "."
        with open(os.path.join(OUT, "report.md"), "w", encoding="utf-8") as f:
            f.write("\n".join(rows) + "\n")
        self.contact_sheet()
        print("Report: %s" % os.path.join(OUT, "report.md"))

    def contact_sheet(self, thumb=360, per_row=6):
        made = [(s["id"], self.state[s["id"]]) for s in self.sheets
                if self.state.get(s["id"], {}).get("path") and os.path.exists(self.state[s["id"]]["path"])]
        if not made:
            return
        th = thumb * 9 // 16 + 22
        rows = (len(made) + per_row - 1) // per_row
        sheet = Image.new("RGB", (per_row * thumb, rows * th), (32, 28, 36))
        draw = ImageDraw.Draw(sheet)
        colour = {"pass": (90, 200, 120), "warn": (230, 190, 80), "fail": (230, 80, 80)}
        for i, (sid, e) in enumerate(made):
            x, y = (i % per_row) * thumb, (i // per_row) * th
            im = Image.open(e["path"]).convert("RGB")
            im.thumbnail((thumb - 8, th - 30))
            sheet.paste(im, (x + 4, y + 4))
            status = e.get("check", {}).get("status", "?")
            draw.rectangle([x + 2, y + 2, x + thumb - 3, y + th - 3], outline=colour.get(status, (150, 150, 150)), width=2)
            draw.text((x + 6, y + th - 18), "%s (%s)" % (sid, status), fill=(240, 240, 240))
        sheet.save(os.path.join(OUT, "contact_sheet.jpg"), quality=88)  # a PNG of ~180 sheets is too big to preview


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dry-run", action="store_true", help="check every entry's batch and references; no calls")
    ap.add_argument("--limit", type=int, help="make at most this many sheets")
    ap.add_argument("--only", help="comma-separated ids to make")
    ap.add_argument("--redo", action="append", default=[], help="forget this id's result so it is made again")
    ap.add_argument("--budget", type=float, help="dollar cap for the whole pass (default: the list's)")
    ap.add_argument("--report", action="store_true", help="only rebuild report.md and contact_sheet.jpg")
    ap.add_argument("--recheck", action="store_true", help="check every result again, then rebuild the report")
    ap.add_argument("--now", action="store_true",
                    help="send requests one by one at full price instead of batch mode (Cory: use batch for all art)")
    ap.add_argument("--batch", action="store_true", help="batch mode, the default (kept for old commands)")
    ap.add_argument("--wait", action="store_true", help="with --batch: keep going until every wave is in")
    args = ap.parse_args()

    spec = load_list()
    p = Pass(spec, args.budget or spec.get("budget", 25.0), args.dry_run)
    for sid in args.redo:
        old = p.state.pop(sid, None)
        if old is not None:
            # The old result stays on disk; only its record goes. Its cost stays counted.
            p.state.setdefault("_redone", {"cost": 0})["cost"] += old.get("cost", 0)
    if args.redo:
        p.save()
    if args.report or args.recheck:
        p.recheck() if args.recheck else p.report()
        return
    if not args.now:
        if args.dry_run:
            p.plan_batch()
        else:
            p.run_batch(args.wait)
        return
    p.run(args.limit, set(args.only.split(",")) if args.only else None)


if __name__ == "__main__":
    main()
