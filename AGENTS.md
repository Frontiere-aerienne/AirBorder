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
the report consistent with code and results. Claude is the default agent for both report
reviews, and Codex is the automatic fallback.

## Review guidelines

Rubric and report-consistency review is **Claude's job**: `.github/workflows/report-pr-review.yml`
reviews report PRs, and `report-consistency-review.yml` reviews after merge. This saves Codex
capacity. Codex is the fallback.

- In a routine PR review, do **not** duplicate rubric findings on `Report/`. Review code changes as usual.
- Act as the report reviewer only when a comment explicitly asks for the fallback ("The Claude report
  review could not run"). Then check the `Report/` changes against `.github/report-review/RUBRIC.md`:
  rubric failures, regressions vs the base branch, and claims the repository contradicts are P1, and
  grammar or clarity problems are P2. Never ask for invented content.
- Do not respond to comments carrying the Claude Code attribution
  (`[Claude Code](https://claude.com/claude-code)`). Those are automated status notes, not feedback.
