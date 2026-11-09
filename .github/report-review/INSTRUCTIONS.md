# Report consistency review: agent instructions

You are reviewing the AirBorder ACM report (`Report/main.tex`, acmart `sigconf`) after a
change landed on `main`. This review runs **after merge**. It never blocks a pull request.
Your job is to keep the report consistent with the repository as it is now.

## Inputs

- `.report-review/context.md` describes what triggered this run: the commit range, the
  changed files, and (for CI-result triggers) the latest test outcomes.
- Use `git diff`, `git log` and `git show` on that commit range to see exactly what changed.
- The rest of the repository is the source of truth: Swift sources in `AirBorder/`, tests,
  `Backend/`, `Documentation/` (especially `Verification-*.md`), `output/`, and `README.md`.

## What to check

Read only the report sections the change touches. Check for:

1. **Functionality claims.** Features, screens, algorithms, data sources or providers the
   report describes that the change added, removed, renamed or changed in behaviour.
2. **Results and numbers.** Test counts, pass/fail status, scenario or simulation results,
   timings, and any figure or table built from data that the change regenerated.
3. **Architecture and method.** Descriptions of components, data flow, uncertainty handling,
   privacy or security behaviour that no longer match the code or docs.
4. **Figures.** Screenshots in `Report/figures/` that the change has made out of date.
   You cannot regenerate screenshots, so flag them.
5. **Internal consistency.** Abstract, introduction, evaluation and conclusion should agree
   with each other after any edit you make.

## What you may change

- Edit **only** files under `Report/`. Anything else you change is discarded.
- Make minimal, targeted edits that bring the text in line with the evidence. Keep the
  authors' voice, the acmart structure, citations (`\cite{refNN}`) and labels.
- Never invent results, participants, statistics or citations. If the report needs a number
  you cannot verify from the repository, do not edit the text. Flag it for a human.
- Do not touch the author block, affiliations, AI-use declaration or acknowledgements.
- Keep the LaTeX compilable: balanced braces and environments, no new packages.

## Required output

Write `.report-review/review.md` with exactly this structure:

```
STATUS: consistent | updated | needs-human

## Summary
<one or two sentences>

## Findings
- [updated|needs-human|ok] <report section / line> — <what was inconsistent, the evidence (file:line or commit), and what you did>
```

- `consistent`: nothing in the report is affected. You made no edits.
- `updated`: you edited `Report/`, and every finding is resolved by those edits.
- `needs-human`: at least one finding needs an author (a figure, an unverifiable number, or
  a judgment call). You may also have made safe edits for the other findings.

Be concise. A reviewer will read `review.md` as a pull-request or issue body.
