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

## Handoff and continuity

At the start of implementation or after a handoff/context compaction, read the current checkpoint in `.codex/project-context.md` and the relevant acceptance criteria in `Documentation/HCI/Acceptance-and-review.md`. Treat older ledger sections as dated evidence, not current completion claims. Verify the current branch, changes, PR head, checks and unresolved reviews before resuming. Update the checkpoint after material verified progress; preserve decisions, scope, remaining defects and exact evidence. Do not create a second competing `compaction.md` or change compaction configuration merely to store project status. During code review, use the acceptance contract and applicable Code Review Rules; a ledger's statement that tests passed never substitutes for current CI.

## Code Review Rules

### Passenger decisions and state

- Recommendations may change only selected, incomplete, optional stops, and only after explicit Apply. Preserve order, required stops, and user changes across flight/weather updates. Reject stale recommendations after any relevant plan, observation, or clock change; support Undo. Missing, stale, or invalid timing inputs are unknown, never zero or confident permission to proceed. A departure delay must not silently move the boarding deadline.
- Gate updates are notifications, not passenger-selected flight statuses. Keep the complete gate identifier (including `108A`) consistent across ticket, alert, map, and guidance. Back returns to the originating page; camera always has a direct exit; map/camera preserve route progress; the final route step has an End action. Onboarding runs once with an explicit replay option.

### Design and evidence

- Preserve the approved AirBorder navy/blue/yellow semantic palette, Outfit typography, and genuine Haneda image provenance. Do not replace airport images with unrelated stock imagery, clip gate suffixes, invent live AR/location accuracy, or expose internal implementation language in passenger UI. Check narrow screens, visible focus, labeled controls, adequate touch targets, and readable contrast. See `Documentation/HCI/` for acceptance criteria and coverage limitations.
- Do not call a feature complete solely because a mock or fixture passes. Keep synthetic and live sources visibly distinct. Health-derived walking estimates require consent and revocation fallback; airport-specific history and average estimates must retain provenance. LLM text cannot override deterministic timing, eligibility, or provider evidence.

### Merge evidence and boundaries

- Preserve native iOS build/unit/UI tests, backend contract/authentication tests, and browser integration/design checks. Never skip, delete, loosen assertions, blindly regenerate screenshots, or remove required checks to turn a failed PR green. Changes to workflows, tests, baselines, or these rules need explicit rationale and independent reviewer scrutiny.
- Review the affected completed flows as well as the diff. Report uncovered requirements and residual risks honestly. Do not claim a clean review guarantees a bug-free app. Provider secrets remain server-side, protected endpoints retain authentication, and public endpoints accept only bounded non-sensitive inputs.
