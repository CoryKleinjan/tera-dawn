#!/usr/bin/env python3
"""Run the whole Gemini art pass: every sheet in tools/art/gemini_pass.json, once each.

    python3 tools/art/gemini_pass.py --dry-run          # check every entry's batch and refs, free
    python3 tools/art/gemini_pass.py --limit 3          # make the next 3 sheets (paid)
    python3 tools/art/gemini_pass.py                    # make everything still missing (paid)
    python3 tools/art/gemini_pass.py --report           # rebuild report.md and the contact sheet

Results go to art-sheets/gemini-pass-1/ in the project files, never into the game. Each sheet
is ONE request: a sheet that already has a result, or whose request failed, is skipped on
later runs, so running again only makes what is missing. Redoing a sheet is deliberate:
pass --redo ID (Cory decides which sheets get redone).

The run stops before it would go over the budget (the list's "budget", or --budget). Sheets
whose "anchor" is another entry wait for that entry and attach its result, so a family of
sheets matches one model. Every request gets CONSISTENCY added to its batch text, which keeps
the prompt files themselves usable in ChatGPT. Each result is checked by sheet_check.py.
"""
import argparse
import json
import os
import sys
import threading
import time
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
WORKERS = 4

CONSISTENCY = """Consistency rules for this sheet (follow them strictly):
- Every cell shows the SAME character or object as the other cells and as any attached sheet of it: the same height, head size, proportions, outline thickness and exact colours. Only the pose or the item changes from cell to cell.
- If a sheet with the same grid is attached, trace its poses, cell positions and sprite sizes exactly.
- Same pixel size, the same crisp dark plum-brown outline, the same light from the upper left and the same warm-gold rim light in every cell.
- Characters and creatures stand on one shared baseline: the feet sit the same distance above the bottom edge of every cell.
- Flat pure magenta #FF00FF background with no shadows or gradients, and no magenta or pink-purple inside any sprite."""
GRID_RULE = "- Draw exactly {rows} rows x {cols} columns = {n} equal cells, every cell filled in the order given."


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

    def spent(self):
        return sum(v.get("cost", 0) for v in self.state.values())

    def save(self):
        os.makedirs(OUT, exist_ok=True)
        tmp = STATE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.state, f, indent=1)
        os.replace(tmp, STATE)

    def done(self, sid):
        return sid in self.state

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

    def run_one(self, sheet):
        refs = list(sheet.get("refs", []))
        anchor = self.anchor_result(sheet)
        if anchor:
            refs.append(anchor)
        out = os.path.join(OUT, sheet["save"] if sheet.get("save") else sheet["id"] + ".png")
        n = 2
        while os.path.exists(out):  # a redo keeps the earlier result
            out = os.path.join(OUT, "%s_%d.png" % (os.path.splitext(sheet.get("save") or sheet["id"])[0], n))
            n += 1
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
                anchor or self.replaced(sheet), sheet.get("must_have"))
        return entry

    def replaced(self, sheet):
        r = sheet.get("replaces")
        path = os.path.join(gemini_sheet.ROOT, r) if r else None
        return path if path and os.path.exists(path) else None

    # --- the whole pass -----------------------------------------------------------------

    def run(self, limit=None, only=None):
        todo = [s for s in self.sheets if s.get("batch") and not self.done(s["id"])
                and (not only or s["id"] in only)]
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
        sheet.save(os.path.join(OUT, "contact_sheet.png"))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dry-run", action="store_true", help="check every entry's batch and references; no calls")
    ap.add_argument("--limit", type=int, help="make at most this many sheets")
    ap.add_argument("--only", help="comma-separated ids to make")
    ap.add_argument("--redo", action="append", default=[], help="forget this id's result so it is made again")
    ap.add_argument("--budget", type=float, help="dollar cap for the whole pass (default: the list's)")
    ap.add_argument("--report", action="store_true", help="only rebuild report.md and contact_sheet.png")
    args = ap.parse_args()

    spec = load_list()
    p = Pass(spec, args.budget or spec.get("budget", 25.0), args.dry_run)
    for sid in args.redo:
        if p.state.pop(sid, None) is not None:
            # The old result stays on disk; only its record goes. Its cost stays counted.
            p.state.setdefault("_redone", {"cost": 0})["cost"] += p.price
    if args.redo:
        p.save()
    if args.report:
        p.report()
        return
    p.run(args.limit, set(args.only.split(",")) if args.only else None)


if __name__ == "__main__":
    main()
