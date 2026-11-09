# AirportXRCompanion agent routing

Use the project-scoped custom agents in `.codex/agents/` whenever work is delegated.
Name the role explicitly; do not spawn an unnamed generic agent when one of these roles fits.

Choose the parent by task risk before delegation:

- `parent_deep`: ambiguous, safety-critical, architecture, immigration, privacy/security, licensing, learning, probability, and cross-system decisions.
- `parent_balanced`: normal implementation, UI, backend, and multi-file maintenance with policy already decided.
- `parent_fast`: mechanical searches, builds, tests, logs, formatting, and evidence-only documentation.

When the current root session is already the parent, it follows the same classification. A
fast or balanced parent must escalate when deeper judgment appears; it must not silently keep
the cheaper profile. Use `scripts/run-codex-parent.sh` to pin a new root invocation via CLI
overrides, which have higher precedence than the project default.

- `architect`: architecture, advanced algorithms, migrations, provider/licensing policy, and ambiguous cross-feature decisions.
- `safety_reviewer`: immigration/entry guidance, privacy/security, cache authority, probabilistic safety, and learning-policy review.
- `worker`: bounded implementation after the decision is made.
- `explorer`: read-only repository or log exploration.
- `ui_researcher`: UX research, passenger-flow critique, wireframes, and accessibility rationale.
- `test_runner`: builds, tests, simulator logs, fuzz/replay evidence, and reproducibility checks.
- `docs_reporter`: guides, reports, references, and evidence synchronization.

Deep roles use `gpt-5.6` with `xhigh` reasoning. Routine bounded roles use
`gpt-5.6-terra` with low or medium reasoning. The root session integrates results using
the project default (`gpt-5.6`, high), unless its launch command pins a task parent profile.
Do not let a lower-cost role decide or weaken a safety boundary. A task parent may delegate
one level to a specialist; that specialist must not delegate again. Keep at most four concurrent
threads.

Runtime model, permission, or administrator policy can override repository defaults. If a
pinned model is unavailable, report the failure; do not silently substitute a different model.

## Report and rubric rules

`Report/main.tex` is the course deliverable (ACM `acmart` `sigconf`). It is graded against
`.github/report-review/RUBRIC.md` (CAP4104/CAP5178 Implementation and Evaluation Plan).
Any task that edits `Report/` must keep the report rubric-compliant:

- Keep the required sections: Introduction, Initial Design, System, Implementation Status,
  and Evaluation Plan with Population, Hypotheses with nulls, Method and Metrics.
- Keep the body at 5–10 pages excluding the appendix, in the double-column template.
- It is a **plan**: never present user-study results, and never invent participants,
  hypotheses, numbers or citations.
- Run `python3 Scripts/reporting/check_rubric.py` after compiling (`latexmk -pdf` in `Report/`).
- Route report edits to `docs_reporter`. A change to evaluation method or hypotheses goes
  to a deep parent.

Merge gates: `.github/workflows/report-build.yml` adds two required checks on `main`.
**Compile ACM report** fails if the report doesn't compile. **Rubric compliance** fails on any
rubric ❌ or any regression vs the base branch (`check_rubric.py --strict --baseline-tex`). Unresolved review threads also block merging.
`.github/workflows/report-consistency-review.yml` is advisory: it runs after merge and keeps
the report consistent with code and results.

## Review guidelines

When reviewing a pull request that touches `Report/`, `.github/report-review/` or anything the
report describes:

- Check every report edit against `.github/report-review/RUBRIC.md`, and flag anything that makes
  a criterion worse than on the base branch (a rubric regression), even when it still passes. Flag a removed or weakened
  required section, a missing null hypothesis, a missing within/between-subjects statement,
  equipment, location or time, a missing % complete estimate, a body over 10 pages, or
  study results presented in a plan. Treat these as P1.
- Flag report claims (features, test counts, results, architecture) that the PR's code or
  results contradict. Treat these as P1.
- Treat grammar, spelling and clarity problems in edited report text as P2.
- Do not ask for report changes on PRs that do not affect anything the report describes.
