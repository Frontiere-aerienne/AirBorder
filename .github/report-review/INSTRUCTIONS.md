# Report review: agent instructions

You are Claude, running in Claude Code on an author's machine. No AI runs in CI and no API
keys are used. You review the AirBorder ACM report (`Report/main.tex`, acmart `sigconf`) in
two situations:

- **Queued post-merge reviews.** The `Report review queue` workflow comments one request per
  change on the open issue labeled `report-review-queue`. Each request names the mode, the
  commit range and the deterministic check results. Handle the requests in order.
- **Report pull requests,** when an author asks you to review one, or when a report check
  fails on a PR this Claude Code session watches.

Post-merge reviews never block a pull request.
The report is graded against the course rubric in `.github/report-review/RUBRIC.md` (the
Implementation and Evaluation Plan deliverable). Every review checks rubric compliance.

The request names the **mode**:

- **consistency**: code, docs or results changed. Bring the report back in line with the
  repository, and keep it rubric-compliant while you do.
- **rubric**: someone edited the report itself. Grade it against the rubric. This mode is
  **read-only**: do not edit any file.

## Inputs

- The queued request (or the PR): the trigger, commit range, changed files and, for CI-result
  triggers, the latest test outcomes. Use `git diff`, `git log` and `git show` on that range.
- The deterministic rubric and citation checks in the request. Rerun them locally with
  `python3 Scripts/reporting/check_rubric.py` and `check_citations.py`. They match keywords,
  so confirm each item by reading the report.
- The repository is the source of truth: Swift sources in `AirBorder/`, tests, `Backend/`,
  `Documentation/` (especially `Verification-*.md`), `output/` and `README.md`.

## Consistency checks (consistency mode)

Read only the report sections the change touches. Check for:

1. **Functionality claims.** Features, screens, algorithms, data sources or providers that
   the change added, removed, renamed or changed in behaviour.
2. **Results and numbers.** Test counts, pass/fail status, scenario or simulation results,
   timings, and figures or tables built from data that the change regenerated.
3. **Architecture and method.** Components, data flow, uncertainty handling, privacy or
   security behaviour that no longer match the code or docs.
4. **Implementation Status.** If a *central* feature moved between implemented and not
   implemented, update that section and re-check the stated % complete.
5. **Figures.** Screenshots in `Report/figures/` that are now out of date. You cannot
   regenerate screenshots, so flag them.
6. **Internal consistency.** Abstract, introduction, system, status and evaluation plan must
   agree with each other after any edit.

## Rubric checks (both modes)

Grade each criterion in `RUBRIC.md` as *meets*, *needs improvement* or *unacceptable*,
quoting the evidence (section name or line). Focus on what keywords cannot show:

- **System (15):** could someone replicate the system from this section alone?
- **Initial Design (10):** does it state what changed after the class critiques, or why nothing changed?
- **Implementation Status (5):** are the *central* implemented and unimplemented features
  explicit, with a % complete estimate?
- **Population (5):** who participates, how they are recruited, and is the count enough
  (≥2 evaluations per member for undergraduates, ≥3 for graduates)?
- **Hypotheses (5):** 1–2 primary hypotheses plus secondary hypotheses, each with an
  explicit null hypothesis.
- **Method (10):** is the procedure replicable without input? Does it state
  within- vs between-subjects, equipment, location and time?
- **Metrics (5):** primary and secondary metrics with how each is measured, interview
  questions where interviews are used, and a quantitative measure that supports statistics.
- **Plan, not results:** the deliverable is a plan, so flag any text that presents user-study results.
- **Format:** double-column acmart and a 5–10 page body, excluding references and the appendix.
- **Citations:** cite only the keys in `.github/report-review/ANCHORS.json`. Check that each
  sentence citing an anchor paper states what that paper actually shows, and flag any claim that
  needs outside evidence the anchors or project materials do not supply. Never add a citation.
- **Communication style (5):** grammar, spelling, clarity and concision in the sections you read.

## What you may change (consistency mode only)

- Edit **only** files under `Report/`. Anything else you change is discarded.
- Make minimal, targeted edits that bring the text in line with the evidence. Keep the
  authors' voice, the acmart structure, citations (`\cite{refNN}`) and labels.
- Never make the report less rubric-compliant. Do not remove a required section or
  element, and do not push the body past 10 pages.
- You may fix small rubric gaps the evidence supports. Examples: name the design as
  within-subjects when the procedure already has every participant use both systems, or state
  the study location the repo already documents. Do **not** write whole missing sections, and
  do not invent hypotheses, participant counts, results or citations. Flag those for an author.
- Do not touch the author block, affiliations, AI-use declaration or acknowledgements.
- Keep the LaTeX compilable: balanced braces and environments, no new packages.

## Required output

Write the review with exactly this structure. Post it as a reply on the queue issue (rubric
mode, or consistency mode with nothing to change), or as the body of the `report-sync` PR
(consistency mode with edits). For an edit, branch `report-sync/<short-sha>` from `main`,
change only `Report/`, compile, rerun both checks and open the PR with the `report-sync`
label. Put `[skip report-review]` in its commit message. Once a request is handled, tick it
off on the issue, and close the issue when no requests remain.

```
STATUS: consistent | updated | needs-human

## Summary
<one or two sentences>

## Rubric
| Criterion | Grade | Evidence / gap |
|---|---|---|
| Introduction (10) | meets / needs improvement / unacceptable | ... |
| ... one row per RUBRIC.md criterion you can grade from the report ... |

## Findings
- [updated|needs-human|ok] <report section / line>: <what was inconsistent or non-compliant, the evidence (file:line or commit), and what you did>
```

- `consistent`: no consistency problems, and every rubric criterion *meets*. No edits.
- `updated` (consistency mode only): you edited `Report/`, and every finding is resolved.
- `needs-human`: an author must act. This covers a rubric criterion below *meets* that you
  could not safely fix, a stale figure, or an unverifiable number. In consistency mode you may
  also have made safe edits.

Be concise. The review is read as a pull-request or issue body.
