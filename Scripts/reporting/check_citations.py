#!/usr/bin/env python3
"""Citation-anchor check for the AirBorder ACM report.

The report must be grounded on a small, fixed set of anchor sources, listed in
.github/report-review/ANCHORS.json:
  - at most `max_anchor_papers` authoritative peer-reviewed conference papers, and
  - the project's own materials (interview/survey records, evaluation instruments,
    verification records) that cannot be reproduced in full in the report.
The bibliography may hold nothing else, every \\cite must resolve to one of those keys,
and every anchor paper must be cited in the body, so the paper is grounded on it.

Writes a Markdown table. With --strict, exits 1 when any check fails.
Usage: check_citations.py [--tex Report/main.tex] [--anchors .github/report-review/ANCHORS.json]
                          [--out citations.md] [--strict]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PASS, WARN, FAIL = "✅ pass", "⚠️ warn", "❌ fail"
CONFERENCE = re.compile(
    r"\bCHI\b|\bUIST\b|\bCSCW\b|\bIUI\b|MobileHCI|UbiComp|\bDIS\b|ISMAR|Proceedings|Proc\.|Conference|10\.1145/",
)
CITE = re.compile(r"\\(?:no)?cite[a-z]*\*?(?:\[[^\]]*\])*\{([^}]+)\}")


def keys_in(text: str) -> list[str]:
    return [k.strip() for group in CITE.findall(text) for k in group.split(",") if k.strip()]


def check(tex_path: Path, anchors_path: Path) -> list[tuple[str, str, str, str]]:
    tex = re.sub(r"(?<!\\)%.*", "", tex_path.read_text(errors="ignore"))
    cfg = json.loads(anchors_path.read_text())
    cap = int(cfg.get("max_anchor_papers", 5))
    anchors = [a["key"] for a in cfg.get("anchors", [])]
    materials = [m["key"] for m in cfg.get("project_materials", [])]
    allowed = set(anchors) | set(materials)

    m = re.search(r"\\begin\{thebibliography\}.*?\\end\{thebibliography\}", tex, re.S)
    bib = m.group(0) if m else ""
    before_bib = tex[: m.start()] if m else tex.split("\\appendix", 1)[0]
    after_bib = tex[m.end():] if m else ""
    entries = dict(re.findall(r"\\bibitem(?:\[[^\]]*\])?\{([^}]+)\}((?:(?!\\bibitem).)*)", bib, re.S))
    body = before_bib.split("\\appendix", 1)[0]
    body_cites = set(keys_in(body))
    all_cites = set(keys_in(before_bib)) | set(keys_in(after_bib))

    r = []
    # C-CAP: no more than the allowed number of anchor papers.
    r.append(("C-CAP", f"At most {cap} anchor papers",
              PASS if 0 < len(anchors) <= cap else FAIL,
              f"{len(anchors)} anchor paper(s) configured" + ("" if anchors else "; none chosen yet")))

    # C-TYPE: each anchor is an authoritative conference paper present in the bibliography.
    bad_type = [k for k in anchors if k in entries and not CONFERENCE.search(" ".join(entries[k].split()))]
    missing = [k for k in anchors if k not in entries]
    st = FAIL if missing else (WARN if bad_type else PASS)
    ev = []
    if missing:
        ev.append("not in bibliography: " + ", ".join(missing))
    if bad_type:
        ev.append("not recognizably a conference paper: " + ", ".join(bad_type))
    r.append(("C-TYPE", "Anchors are conference papers in the bibliography", st, "; ".join(ev) or "all anchors present"))

    # C-BIB: the bibliography holds only anchors and project materials.
    extra = sorted(set(entries) - allowed, key=lambda k: (len(k), k))
    r.append(("C-BIB", "Bibliography holds only anchors + project materials", FAIL if extra else PASS,
              f"{len(extra)} other entr{'y' if len(extra) == 1 else 'ies'} (e.g. {', '.join(extra[:8])})" if extra
              else f"{len(entries)} entries, all allowed"))

    # C-CITES: every citation resolves to an allowed key.
    stray = sorted(all_cites - allowed, key=lambda k: (len(k), k))
    r.append(("C-CITES", "Every \\cite uses an anchor or project material", FAIL if stray else PASS,
              f"{len(stray)} other cited key(s) (e.g. {', '.join(stray[:8])})" if stray else "all citations allowed"))

    # C-GROUND: every anchor paper is cited in the body.
    ungrounded = [k for k in anchors if k not in body_cites]
    r.append(("C-GROUND", "Each anchor paper is cited in the body", FAIL if ungrounded else PASS,
              "not cited in body: " + ", ".join(ungrounded) if ungrounded else "all anchors cited in body"))

    # C-APPROVED: the authors confirmed the anchor selection.
    r.append(("C-APPROVED", "Authors approved the anchors", PASS if cfg.get("approved") else WARN,
              "approved" if cfg.get("approved") else "proposed; set \"approved\": true in ANCHORS.json after review"))
    return r


def render(rows) -> str:
    fails = sum(x[2] == FAIL for x in rows)
    lines = ["### Citation anchors", "",
             f"**{fails} fail** · anchors: `.github/report-review/ANCHORS.json` · "
             "the AI review checks that each claim citing an anchor matches the paper.", "",
             "| ID | Check | Result | Evidence |", "|---|---|---|---|"]
    lines += [f"| {a} | {b} | {c} | {d.replace('|', '/')} |" for a, b, c, d in rows]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tex", default="Report/main.tex", type=Path)
    ap.add_argument("--anchors", default=".github/report-review/ANCHORS.json", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()
    rows = check(args.tex, args.anchors)
    md = render(rows)
    if args.out:
        args.out.write_text(md)
    sys.stdout.write(md)
    return 1 if args.strict and any(x[2] == FAIL for x in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
