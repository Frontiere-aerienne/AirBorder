# Report rubric: CAP4104/CAP5178 Implementation and Evaluation Plan (Fall 2026)

Source: `HCI-ProjectImplementationEvaluation-Fall26.pdf` (deliverable due 11/16).
This file is the single source of truth for every rubric check: the deterministic checker
(`Scripts/reporting/check_rubric.py`), and Claude's reviews in Claude Code.
Note: the deliverable is an evaluation **plan**. User studies have not been run yet, so the report
must not present study results.

## Format (−5% if the correct template is not used)

- ACM full-paper template, **double column** (`acmart` with `sigconf`).
- **5–10 pages**, excluding the appendix and the references.

## Citations (project rule, set by the authors)

- The bibliography holds at most **6 authoritative peer-reviewed conference papers** (the anchor
  sources), plus the project's own materials that cannot be reproduced in full in the report:
  interview and survey records, evaluation instruments and verification records.
- Appendix-only material is not cited.
- The paper must be grounded on the anchors. Every anchor is cited in the body, and each
  claim that cites one must match what that paper shows.
- The anchors and project materials are listed in `.github/report-review/ANCHORS.json`
  and checked by `Scripts/reporting/check_citations.py` (the **Citation anchors** check).

## Required sections and grading

| ID | Criterion | Pts | What "meets expectations" requires |
|---|---|---|---|
| R-INTRO | Introduction | 10 | Problem, why it matters, who the end users are, how the system solves it. |
| R-DESIGN | Initial Design | 10 | High-fidelity prototype design, and what changed after class critiques (or why nothing changed). |
| R-SYSTEM | System | 15 | Functionality and technical details, enough for someone to **replicate** the system. |
| R-STATUS | Implementation Status | 5 | *Central* features implemented, *central* features not implemented, and an estimated % complete. |
| R-POP | Population | 5 | Who participates and how they will be recruited, in as much detail as possible. Grad groups: ≥3 evaluations per member; undergrad groups: ≥2 per member. |
| R-HYP | Hypotheses (and null) | 5 | 1–2 primary hypotheses and secondary hypotheses that explain *why*, each with an explicit **null** hypothesis. |
| R-METHOD | Method | 10 | Participant procedure from start to end, replicable without input; **within- vs between-subjects** stated; **equipment** (participant device and study equipment, e.g. camera); **location**; **time**. |
| R-METRICS | Metrics | 5 | Primary and secondary metrics and how each is measured (e.g. include the interview questions). Grad: at least one quantitative measure suitable for statistics. |
| R-STYLE | Communication style | 5 | Clear, concise, no grammar or spelling mistakes. |
| R-QUALITY | Subjective quality | 10 | Overall quality of the project. |
| — | Video | 20 | Not checked here: 4–5 min, title screen with group and member names, one users/problem screen, one evaluation screen, mostly a functionality demo. |
| — | Peer evaluation | 10 | Not checked here. |

Scoring bands: *Meets expectations* is above 75% of the points, *Needs improvement* is 50–75%, and *Unacceptable* is below 50%.
