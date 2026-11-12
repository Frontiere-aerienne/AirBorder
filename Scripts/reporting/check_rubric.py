#!/usr/bin/env python3
"""Deterministic rubric compliance check for the AirBorder ACM report.

Checks Report/main.tex (and, when present, main.aux / main.log from a compile) against the
CAP4104/CAP5178 Implementation and Evaluation Plan rubric in .github/report-review/RUBRIC.md.

This only checks structure and keywords. Whether the writing is good enough (clarity,
replicability, hypothesis quality) is judged by the AI review. The script writes a Markdown
report and, unless --strict is given, always exits 0 so it never blocks a merge.

With --baseline-tex (the report from the PR's base branch, compiled alongside), it also reports
**regressions**. A regression is any criterion whose result got worse: pass→warn, warn→fail, a
warning that is missing more elements than before, or more undefined refs, cites or TODOs.
With --strict, any ❌ fail OR any regression exits 1.

Usage: check_rubric.py [--tex Report/main.tex] [--baseline-tex base/Report/main.tex]
                       [--out rubric.md] [--strict]
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

PASS, WARN, FAIL, INFO = "✅ pass", "⚠️ warn", "❌ fail", "ℹ️ info"
SEVERITY = {PASS: 0, INFO: 0, WARN: 1, FAIL: 2}


@dataclass
class Result:
    rid: str
    criterion: str
    points: str
    status: str
    evidence: str
    missing: tuple = ()
    counts: tuple = ()


def strip_comments(tex: str) -> str:
    return re.sub(r"(?<!\\)%.*", "", tex)


def heading_blocks(body: str, level: str) -> list[tuple[str, str]]:
    """Return (title, content) for each \\section or \\subsection (starred included) in body."""
    pat = re.compile(r"\\" + level + r"\*?\{((?:[^{}]|\{[^{}]*\})*)\}")
    stop = re.compile(r"\\section\*?\{" if level == "section" else r"\\(?:sub)?section\*?\{")
    out = []
    for m in pat.finditer(body):
        rest = body[m.end():]
        nxt = stop.search(rest)
        out.append((m.group(1).strip(), rest[: nxt.start()] if nxt else rest))
    return out


def find_heading(body: str, title_re: str) -> tuple[str, str, str] | None:
    """Find a section (preferred) or subsection whose title matches. Returns (level, title, text)."""
    for level in ("section", "subsection"):
        for title, text in heading_blocks(body, level):
            if re.search(title_re, title, re.I):
                return level, title, text
    return None


def has(text: str, pattern: str) -> bool:
    return re.search(pattern, text, re.I) is not None


def page_info(aux: Path, log: Path) -> dict:
    info: dict = {}
    if aux.exists():
        for m in re.finditer(
            r"\\contentsline \{section\}\{(.*?)\}\{(\d+)\}\{([^}]*)\}", aux.read_text(errors="ignore")
        ):
            title, page, anchor = m.group(1), int(m.group(2)), m.group(3)
            if "References" in title and "refs" not in info:
                info["refs"] = page
            if anchor.startswith("appendix.") and "appendix" not in info:
                info["appendix"] = page
    if log.exists():
        text = log.read_text(errors="ignore")
        m = re.search(r"Output written on .*?\((\d+) pages", text)
        if m:
            info["total"] = int(m.group(1))
        info["undef_refs"] = len(re.findall(r"Reference `[^']*' on page \d+ undefined", text))
        info["undef_cites"] = len(re.findall(r"Citation `[^']*' on page \d+ undefined", text))
        info["overfull"] = len(re.findall(r"^Overfull", text, re.M))
    return info


def check(tex_path: Path) -> list[Result]:
    raw = tex_path.read_text(errors="ignore")
    tex = strip_comments(raw)
    body = re.split(r"\\appendix\b", tex, maxsplit=1)[0]
    body = re.split(r"\\begin\{thebibliography\}|\\bibliography\{", body, maxsplit=1)[0]
    pages = page_info(tex_path.with_suffix(".aux"), tex_path.with_suffix(".log"))
    r: list[Result] = []

    # --- Format -----------------------------------------------------------------------
    m = re.search(r"\\documentclass\[([^\]]*)\]\{acmart\}", tex)
    if m and "sigconf" in m.group(1):
        r.append(Result("F-TEMPLATE", "ACM double-column template", "−5%", PASS, f"`acmart[{m.group(1)}]`"))
    elif m:
        r.append(Result("F-TEMPLATE", "ACM double-column template", "−5%", FAIL,
                        f"`acmart[{m.group(1)}]` is not `sigconf` (double column)"))
    else:
        r.append(Result("F-TEMPLATE", "ACM double-column template", "−5%", FAIL, "document class is not `acmart`"))

    if "appendix" in pages or "refs" in pages:
        # Per the course, references and the appendix are both excluded: only the body counts.
        # Body pages are those before the page where references start. A page shared by body text
        # and the start of the references is not counted against the 10-page maximum, but it does
        # count toward the 5-page minimum.
        refs = pages.get("refs", pages.get("appendix"))
        body_full = refs - 1
        ev = f"body pp. 1–{body_full} (+ shared p.{refs}); references and appendix excluded; total {pages.get('total', '?')}"
        if refs < 5:
            st = FAIL
            ev += " (under 5 pages)"
        elif body_full > 10:
            st = FAIL
            ev += f" (body exceeds 10 pages by {body_full - 10})"
        else:
            st = PASS
        r.append(Result("F-LENGTH", "5–10 body pages (excl. refs & appendix)", "—", st, ev))
    else:
        r.append(Result("F-LENGTH", "5–10 body pages (excl. refs & appendix)", "—", WARN, "no main.aux; compile first to measure pages"))

    # --- Required sections --------------------------------------------------------------
    def section_check(rid, crit, pts, title_re, content_checks):
        found = find_heading(body, title_re)
        if not found:
            r.append(Result(rid, crit, pts, FAIL, "no section with a matching title",
                            tuple(label for label, _ in content_checks) + ("section",)))
            return None
        level, title, text = found
        missing = [label for label, pat in content_checks if not has(text, pat)]
        st = PASS if level == "section" and not missing else WARN
        ev = f"{level} “{title}”"
        if level != "section":
            ev += " (subsection only; rubric expects a section)"
        if missing:
            ev += "; missing: " + ", ".join(missing)
        if level != "section":
            missing = missing + ["section heading"]
        r.append(Result(rid, crit, pts, st, ev, tuple(missing)))
        return text

    section_check("R-INTRO", "Introduction", "10", r"introduction", [
        ("problem", r"problem"),
        ("importance", r"important|matters|consequen|cost|disrupt"),
        ("end users", r"\busers?\b|passengers?|travel(l)?ers?"),
        ("solution", r"\bwe (propose|present|build|design)|airborder"),
    ])
    section_check("R-DESIGN", "Initial Design", "10", r"initial design|high[- ]fidelity|design (changes|iteration|revision)", [
        ("high-fidelity prototype", r"high[- ]fidelity|prototype"),
        ("critique/feedback", r"critique|feedback"),
        ("changes made (or why not)", r"chang|revis|iterat|kept|retain"),
    ])
    section_check("R-SYSTEM", "System", "15", r"^system\b|system (and|&) implementation|^implementation$|system design", [
        ("functionality", r"feature|functional|user can|lets? (the )?(user|passenger)"),
        ("technical details", r"swift|ios|architecture|framework|api|backend|database"),
        ("replication details", r"repositor|github|xcode|build|install|dependenc|requirement"),
    ])
    section_check("R-STATUS", "Implementation Status", "5", r"implementation status|current status|status", [
        ("implemented central features", r"\bimplemented\b|complete[d]?"),
        ("central features NOT implemented", r"not (yet )?(been )?implemented|unimplemented|remaining|missing|future work|incomplete"),
        ("% complete estimate", r"\d{1,3}\s*\\?%|percent"),
    ])

    ev_found = find_heading(body, r"evaluation plan|^evaluation|study design|user study")
    if ev_found:
        level, title, ev_text = ev_found
        st = PASS if level == "section" else WARN
        note = "" if level == "section" else " (subsection only; rubric expects a section)"
        r.append(Result("R-EVAL", "Evaluation Plan section", "—", st, f"{level} “{title}”{note}"))
        # Population/hypotheses/method/metrics may live in sibling subsections, so include the
        # whole enclosing section when the match was a subsection.
        if level == "subsection":
            ev_text = body[body.find(title):]
            nxt = re.search(r"\\section\*?\{", ev_text)
            ev_text = ev_text[: nxt.start()] if nxt else ev_text
    else:
        r.append(Result("R-EVAL", "Evaluation Plan section", "—", FAIL, "no evaluation section; scanning whole body"))
        ev_text = body

    def items(rid, crit, pts, checks):
        """The first check is the core element: if it is missing the criterion fails."""
        missing = [label for label, pat in checks if not has(ev_text, pat)]
        if not missing:
            st = PASS
        elif checks[0][0] in missing:
            st = FAIL
        else:
            st = WARN
        r.append(Result(rid, crit, pts, st, "all elements present" if not missing else "missing: " + ", ".join(missing),
                        tuple(missing)))

    items("R-POP", "Population", "5", [
        ("who participates", r"participants?|travel(l)?ers|passengers"),
        ("recruitment", r"recruit"),
        ("sample size", r"\b\d+\b\s*(participants|travel|people|users)|\b(six|eight|ten|twelve|fifteen|twenty)\b"),
    ])
    items("R-HYP", "Hypotheses (and null)", "5", [
        ("hypotheses", r"hypothes"),
        ("null hypotheses", r"null hypothes|\bH_?\{?0\}?\b|\b[HS]\d*\$?_\{?0|\$H_0\$"),
        ("primary vs secondary", r"primary"),
        ("secondary", r"secondary"),
    ])
    items("R-METHOD", "Method", "10", [
        ("participant procedure", r"procedure|participants (will )?(first|then|complete)"),
        ("within/between-subjects", r"within[- ]subjects?|between[- ]subjects?"),
        ("equipment", r"equipment|camera|screen[- ]record|recorder"),
        ("location", r"\blocation\b|\blab(oratory)?\b|\broom\b|on[- ]site|conducted (at|in)|remotely"),
        ("time / duration", r"\bminutes?\b|\bhours?\b|duration|session length"),
    ])
    items("R-METRICS", "Metrics", "5", [
        ("metrics named", r"metric|measure"),
        ("primary/secondary metrics", r"primary|secondary"),
        ("quantitative measure", r"\bSUS\b|NASA[- ]?TLX|completion time|error (rate|count)|likert|accuracy|task time|score"),
    ])

    if has(ev_text, r"\bp\s*[<=]\s*0?\.\d|statistically significant|participants (rated|preferred|were faster)"):
        r.append(Result("R-PLAN", "Plan, not results", "—", WARN,
                        "evaluation text reads like study results; the deliverable is a plan"))

    # --- Author placeholders ------------------------------------------------------------------
    placeholders = len(re.findall(r"\\TODO\{", body))
    r.append(Result("F-PLACEHOLDERS", "No unfilled author placeholders", "—", FAIL if placeholders else PASS,
                    f"{placeholders} \\TODO{{…}} placeholder(s) in the body" if placeholders else "none",
                    counts=(("author placeholders", placeholders),)))

    # --- Hygiene (feeds Communication style) ---------------------------------------------
    issues = []
    todo = re.findall(r"\b(TODO|FIXME|XXX|TBD)\b|\?\?", body)
    counts = (("undefined references", pages.get("undef_refs", 0)),
              ("undefined citations", pages.get("undef_cites", 0)),
              ("TODO/FIXME/?? markers", len(todo)))
    if pages.get("undef_refs"):
        issues.append(f"{pages['undef_refs']} undefined references")
    if pages.get("undef_cites"):
        issues.append(f"{pages['undef_cites']} undefined citations")
    if todo:
        issues.append(f"{len(todo)} TODO/FIXME/?? markers")
    if pages.get("overfull"):
        issues.append(f"{pages['overfull']} overfull boxes")
    r.append(Result("R-STYLE", "Communication style (mechanical)", "5", WARN if issues else PASS,
                    "; ".join(issues) if issues else "no undefined refs/cites or TODO markers; clarity is judged by the AI review",
                    counts=counts))
    r.append(Result("—", "Video, peer evaluation, subjective quality", "40", INFO, "not checked automatically"))
    return r


def regressions(head: list[Result], base: list[Result]) -> list[str]:
    """Criteria that got worse from base to head."""
    out = []
    by_id = {x.rid: x for x in base if x.rid != "—"}
    for h in head:
        b = by_id.get(h.rid)
        if b is None:
            continue
        if SEVERITY[h.status] > SEVERITY[b.status]:
            out.append(f"{h.rid} {h.criterion}: {b.status} → {h.status} ({h.evidence})")
            continue
        newly_missing = [m for m in h.missing if m not in b.missing]
        if newly_missing and SEVERITY[h.status] > 0:
            out.append(f"{h.rid} {h.criterion}: now also missing {', '.join(newly_missing)}")
        bc = dict(b.counts)
        for label, n in h.counts:
            if n > bc.get(label, 0):
                out.append(f"{h.rid} {h.criterion}: {label} {bc.get(label, 0)} → {n}")
    # A page-count criterion that could not be measured on either side is not compared.
    return out


def render(results: list[Result], regs: list[str] | None = None) -> str:
    fails = sum(x.status == FAIL for x in results)
    warns = sum(x.status == WARN for x in results)
    reg_note = "" if regs is None else f" · **{len(regs)} regression{'s' if len(regs) != 1 else ''} vs base**"
    lines = [
        "### Rubric compliance (Implementation & Evaluation Plan)",
        "",
        f"**{fails} fail · {warns} warn**{reg_note} · rubric: `.github/report-review/RUBRIC.md` · "
        "keyword and structure checks only; the AI review judges quality.",
        "",
        "| ID | Criterion | Pts | Result | Evidence |",
        "|---|---|---|---|---|",
    ]
    for x in results:
        lines.append(f"| {x.rid} | {x.criterion} | {x.points} | {x.status} | {x.evidence.replace('|', '/')} |")
    if regs is not None:
        lines += ["", "#### Regressions vs base branch"]
        lines += [f"- ❌ {g}" for g in regs] if regs else ["- None. No criterion got worse."]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tex", default="Report/main.tex", type=Path)
    ap.add_argument("--baseline-tex", type=Path, help="report from the base branch, to detect regressions")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--strict", action="store_true", help="exit 1 on any fail or regression")
    args = ap.parse_args()
    results = check(args.tex)
    regs = None
    if args.baseline_tex:
        if args.baseline_tex.exists():
            base = check(args.baseline_tex)
            # Only compare page length when both sides were compiled.
            if any("no main.aux" in x.evidence for x in base + results if x.rid == "F-LENGTH"):
                results_cmp = [x for x in results if x.rid != "F-LENGTH"]
                base = [x for x in base if x.rid != "F-LENGTH"]
            else:
                results_cmp = results
            regs = regressions(results_cmp, base)
        else:
            regs = []  # No report on the base branch: nothing to regress from.
    md = render(results, regs)
    if args.out:
        args.out.write_text(md)
    sys.stdout.write(md)
    failed = any(x.status == FAIL for x in results) or bool(regs)
    return 1 if args.strict and failed else 0


if __name__ == "__main__":
    sys.exit(main())
