# AirBorder ACM report

`main.tex` is the AirBorder report in ACM `acmart` format (`sigconf,nonacm`). Its figures are in `figures/`.

## Building

- **Locally:** run `latexmk -pdf main.tex` from this folder. This needs a full TeX Live, because acmart depends on packages such as `manyfoot`.
- **CI:** the [`ACM report`](../.github/workflows/report-build.yml) workflow compiles the report on every PR or push that touches `Report/`. Each run uploads the PDF as the `AirBorder-Report` artifact. On `main`, the workflow also refreshes the `report-latest` release, which keeps one stable link to the newest PDF.

## Rubric compliance (every report edit)

The report is graded against [`.github/report-review/RUBRIC.md`](../.github/report-review/RUBRIC.md), which covers the CAP4104/CAP5178 Implementation and Evaluation Plan deliverable. Every edit to the report is checked three ways:

1. **Deterministic check.** [`Scripts/reporting/check_rubric.py`](../Scripts/reporting/check_rubric.py) checks the template, the 5–10 page body, the required sections, and the evaluation-plan elements: population, null hypotheses, within/between-subjects, equipment, location, time and metrics. It runs on every report build. Results go to the job summary and to a sticky comment on the PR. To run it locally, use `python3 Scripts/reporting/check_rubric.py` after `latexmk`.
2. **Codex PR review.** The `## Review guidelines` section in `AGENTS.md` tells Codex to check every report edit against the rubric.
3. **Post-merge AI rubric review.** Every push to `main` that edits only `Report/` triggers a read-only AI grading. It updates one rolling `report-rubric` issue per agent.

None of these block merging.

## Automatic consistency review (post-merge, non-blocking)

[`Report consistency review`](../.github/workflows/report-consistency-review.yml) runs only after changes reach `main`. It is not a pull-request check, so it never blocks a merge.

| Trigger | When |
|---|---|
| Push to `main` | Any change outside `Report/`: code, docs, or committed results in `output/` or `Documentation/` (consistency mode). A push that edits only `Report/` gets read-only rubric mode. |
| `iOS CI` completes on `main` | Only when the outcome differs from the previous run, meaning the results changed |
| `repository_dispatch` `results-generated` | An external pipeline uploaded new results (see below) |
| Manual | Actions → Report consistency review → Run workflow |

An AI agent reads the diff and the trigger context, then checks the report for stale claims (features, numbers, test results, architecture, and figures) and re-grades it against the rubric. Its instructions are in [`.github/report-review/INSTRUCTIONS.md`](../.github/report-review/INSTRUCTIONS.md). The agent may edit only `Report/`. The workflow discards any other edit.

- If the agent edits the report, the workflow opens a **`report-sync` PR**. The edited LaTeX is compile-checked first.
- If something needs an author, such as a stale screenshot or an unverifiable number, the workflow opens a **`report-review` issue**.
- If the report is still consistent, the run ends with only a job summary.

The review is intentionally non-deterministic. Treat its output as a suggestion and merge or close it yourself. To skip a run, put `[skip report-review]` in the commit message.

### One-time setup

| Setting (Settings → Secrets and variables → Actions) | Purpose |
|---|---|
| Secret `ANTHROPIC_API_KEY` *or* `CLAUDE_CODE_OAUTH_TOKEN` | Needed when the agent is `claude` |
| Secret `OPENAI_API_KEY` | Needed when the agent is `codex` |
| Variable `REPORT_REVIEW_AGENT` | `claude` (default), `codex`, or `both` |
| Variable `REPORT_REVIEW_CLAUDE_MODEL` / `REPORT_REVIEW_CODEX_MODEL` | Optional model overrides |
| Secret `REPORT_SYNC_TOKEN` (optional) | A fine-grained PAT with contents and pull-request write access. When set, the `ACM report` build also runs on report-sync PRs, because PRs opened with the default token do not trigger workflows. |

Also enable **Settings → Actions → General → Workflow permissions → "Allow GitHub Actions to create and approve pull requests"**.

### Triggering from a results pipeline

```bash
gh api repos/MayFairMI6/AirBorder/dispatches \
  -f event_type=results-generated \
  -F 'client_payload[summary]=Simulation batch 2026-11-08: 500 scenarios, see output/…' \
  -F 'client_payload[agent]=both'
```
