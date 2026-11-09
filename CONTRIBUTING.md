# Contributing to AirBorder

Create a branch or fork, implement a focused change, and open a pull request against `main`. Use the PR template to identify affected passenger flows and the requirement IDs in [the acceptance contract](Documentation/HCI/Acceptance-and-review.md). Keep credentials and personal travel, health, participant, and peer-feedback records out of commits.

Automatic Codex review is enabled for all AirBorder pull requests on every push through the repository's connected ChatGPT plan. A manual `@codex review` comment can request another pass. Reviews consume the plan's allowance; they can be unavailable at a limit. Extra-credit spending is not enabled by this setup. A missing review is not a clean review.

Every PR runs native iOS build/unit/UI tests and the HCI engine, backend, HTTP integration, browser, and selected design/accessibility checks. The `HCI required tests` aggregate rejects failed, skipped, and cancelled suites. Main requires this check and `Build and test` from GitHub Actions, with the branch up to date. One independent approving review after the latest push and resolved review discussions are also required. New commits dismiss stale approvals. Force pushes and deletion of main are disabled, and these protections apply to administrators.

The author cannot satisfy the independent-approval requirement by approving their own PR. A collaborator must review it. Do not disable protection to work around a failing test, missing review, or lack of a reviewer. Review settings and required checks live in GitHub/Codex account configuration; this document describes the verified setup rather than configuring it by itself.

Before approving, check the exact current commit and all required jobs, examine relevant screenshots and traces, and resolve substantive Codex findings with evidence. Codex's review comments are not an automatic human approval. Review changes to tests, workflow files, expected screenshots, and acceptance rules especially carefully: explain why each change preserves the requirement instead of merely accommodating a regression.

Tests cover defined cases, not every possible visual or functional defect. The acceptance contract lists unimplemented or unverified conditions, including physical-device AR, live-provider behavior, localization, health consent/history, and full Figma fidelity. A new feature needs observable interaction tests and evidence appropriate to its risk. Approved design changes should update their reference and tests together; a baseline update alone is not design approval.

For local commands, see [README](README.md). Browser screenshots and traces are uploaded in the `browser-results` CI artifact; iOS results are in `xcresult`. Public contributors should use synthetic data and secret-free tests. Never execute untrusted pull-request code with repository secrets or add a privileged `pull_request_target` checkout/test workflow.
