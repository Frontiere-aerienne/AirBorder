# AirBorder ACM report

`main.tex` is the AirBorder report in ACM `acmart` format (`sigconf,nonacm`). Its figures are in `figures/`.

## Building

- **Locally:** run `latexmk -pdf main.tex` from this folder. This needs a full TeX Live, because acmart depends on packages such as `manyfoot`.
- **CI:** the [`ACM report`](../.github/workflows/report-build.yml) workflow compiles the report on every PR that touches `Report/`, and on every such push to `main`. Each run uploads the PDF as the `AirBorder-Report` artifact. On `main`, the workflow also refreshes the `report-latest` release, which keeps one stable link to the newest PDF.

## Merge gates (block merging into `main`)

Branch protection on `main` requires these checks, enforced for admins too:

| Required check | Blocks the merge when |
|---|---|
| **Compile ACM report** | The PR's report does not compile. |
| **Citation anchors** | The bibliography holds anything besides the anchors and project materials in `.github/report-review/ANCHORS.json`, or an anchor isn't cited in the body. |
| **Rubric compliance** | Any rubric item is ❌, **or** any criterion regresses vs the PR's base branch: pass→warn, warn→fail, more missing elements, or more undefined refs/cites/TODOs (`check_rubric.py --strict --baseline-tex`). |
| Resolved conversations | Any review thread (Codex, Claude or human) is unresolved. |
| Build and test, HCI required tests, 1 approval | These were already required. |

Both report checks run on every PR. A PR that doesn't touch the report passes them immediately.

## Rubric compliance (every report edit)

The report is graded against [`.github/report-review/RUBRIC.md`](../.github/report-review/RUBRIC.md), which covers the CAP4104/CAP5178 Implementation and Evaluation Plan deliverable. Its citations are limited to the anchors in [`.github/report-review/ANCHORS.json`](../.github/report-review/ANCHORS.json). Candidate anchors are listed in [`ANCHOR-CANDIDATES.md`](ANCHOR-CANDIDATES.md).

1. **Deterministic checks (block merge).** [`check_rubric.py`](../Scripts/reporting/check_rubric.py) checks the template, the 5–10 page body (references and appendix excluded), the required sections, the evaluation-plan elements, unfilled `\TODO` placeholders and regressions against `main`. [`check_citations.py`](../Scripts/reporting/check_citations.py) checks the anchors. Results go to the job summary and to a sticky comment on the PR. To run them locally after `latexmk`, use `python3 Scripts/reporting/check_rubric.py --strict` and `python3 Scripts/reporting/check_citations.py --strict`.
2. **Claude reviews in Claude Code.** No AI runs in CI and no API keys are needed. Claude reviews report PRs in the Claude Code app when you ask, or when a report check fails on a PR its session is watching. It follows [`INSTRUCTIONS.md`](../.github/report-review/INSTRUCTIONS.md).

Codex's automatic GitHub reviews still run. `AGENTS.md` tells Codex to leave rubric and citation findings to the checks and to Claude.

## Post-merge review queue (non-blocking)

[`Report review queue`](../.github/workflows/report-review-queue.yml) runs only after changes reach `main`, so it never blocks a merge. It makes no AI calls. It collects the change context, runs both deterministic checks, and adds one request as a comment on the open issue labeled **`report-review-queue`**.

| Trigger | Mode |
|---|---|
| Push to `main` changing anything outside `Report/` (code, docs, committed results) | consistency |
| Push to `main` that only edits `Report/` | rubric (read-only) |
| `iOS CI` on `main` whose outcome differs from the previous main run (new results) | consistency |
| `repository_dispatch` `results-generated` (an external pipeline uploaded results) | consistency |
| Manual: Actions → Report review queue → Run workflow | either |

Only commits already on `main` are queued. Fork and unmerged commits are refused.

**Handling the queue:** open Claude Code in this repository and ask Claude to work through the open `report-review-queue` issue. For each request, Claude follows `INSTRUCTIONS.md`:
- **Consistency mode with report edits:** it opens a `report-sync/<sha>` PR. That PR runs the merge gates like any other.
- **Otherwise:** it replies on the issue with the grading and findings.

To skip queuing a change, put `[skip report-review]` in its commit message.

### Triggering from a results pipeline

```bash
gh api repos/MayFairMI6/AirBorder/dispatches \
  -f event_type=results-generated \
  -F 'client_payload[summary]=Simulation batch 2026-11-08: 500 scenarios, see output/…'
```
