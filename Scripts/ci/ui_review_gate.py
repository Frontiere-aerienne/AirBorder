#!/usr/bin/env python3
"""UI review checks for AirBorder pull requests.

Two subcommands, both run by .github/workflows/ui-review.yml:

  policy  Fails when the pull request adds passenger-facing iOS copy containing the
          tags "Optional", "if needed" or "if required", or changes the frozen browser
          app under Web/ without the "web-change-approved" label.
  gate    For pull requests that change iOS screens, components, assets or styles,
          requires an approved preview link and screenshots in the PR description,
          unless the "no-visual-change" label is set. Prints "ui=true|false".

Inputs are files written by the workflow, so untrusted PR text never reaches a shell.
Standard library only.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

UI_PREFIXES = (
    "AirBorder/Views/",
    "AirBorder/Components/",
    "AirBorder/Assets.xcassets/",
    "AirBorder/AR/",
    "AirBorder/App/RootTabView.swift",
)
APP_SOURCE_PREFIX = "AirBorder/"
FROZEN_PREFIX = "Web/"
NO_VISUAL_LABEL = "no-visual-change"
WEB_LABEL = "web-change-approved"

BANNED = re.compile(r"\b(optional|if needed|if required)\b", re.IGNORECASE)
SWIFT_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
URL = re.compile(r"https?://\S+")
PREVIEW_LINE = re.compile(r"^\s*[-*]?\s*Preview \(approved\):(.*)$", re.IGNORECASE | re.MULTILINE)
SCREENSHOT_LINE = re.compile(r"^\s*[-*]?\s*Screenshots:(.*)$", re.IGNORECASE | re.MULTILINE)


def read_lines(path: str | None) -> list[str]:
    if not path:
        return []
    return [line.strip() for line in Path(path).read_text(encoding="utf-8").splitlines() if line.strip()]


def is_ui_path(path: str) -> bool:
    return any(path == p or path.startswith(p) for p in UI_PREFIXES)


def added_swift_lines(diff_text: str) -> list[tuple[str, int, str]]:
    """Return (file, new-line-number, text) for every added line in app Swift sources."""
    results: list[tuple[str, int, str]] = []
    current: str | None = None
    line_no = 0
    for raw in diff_text.splitlines():
        if raw.startswith("+++ "):
            name = raw[4:].strip()
            name = name[2:] if name.startswith("b/") else name
            current = name if name.startswith(APP_SOURCE_PREFIX) and name.endswith(".swift") else None
            continue
        if raw.startswith("@@"):
            match = re.search(r"\+(\d+)", raw)
            line_no = int(match.group(1)) if match else 0
            continue
        if current is None:
            continue
        if raw.startswith("+") and not raw.startswith("+++"):
            results.append((current, line_no, raw[1:]))
            line_no += 1
        elif raw.startswith(" "):
            line_no += 1
    return results


def banned_copy(diff_text: str) -> list[str]:
    findings = []
    for name, line_no, text in added_swift_lines(diff_text):
        stripped = text.lstrip()
        if stripped.startswith("//") or stripped.startswith("///"):
            continue
        for literal in SWIFT_STRING.findall(text):
            hit = BANNED.search(literal)
            if hit:
                findings.append(f"{name}:{line_no}: {literal} contains “{hit.group(1)}”")
    return findings


def policy(files: list[str], labels: set[str], diff_text: str) -> list[str]:
    problems = [f"Passenger copy tag: {f}" for f in banned_copy(diff_text)]
    web = [f for f in files if f.startswith(FROZEN_PREFIX)]
    if web and WEB_LABEL not in labels:
        problems.append(
            "The browser app under Web/ is frozen. Changed: " + ", ".join(web[:10])
            + (" …" if len(web) > 10 else "")
            + f". Revert these files, or add the “{WEB_LABEL}” label if the owner approved the change."
        )
    return problems


def has_link(section: str) -> bool:
    return bool(URL.search(section)) or "![" in section


def gate(files: list[str], labels: set[str], body: str) -> tuple[bool, list[str]]:
    ui_files = [f for f in files if is_ui_path(f)]
    if not ui_files or NO_VISUAL_LABEL in labels:
        return bool(ui_files), []
    problems = []
    preview = PREVIEW_LINE.search(body)
    if not preview or not has_link(preview.group(1)):
        problems.append(
            "Add “Preview (approved): <link>” to the PR description, linking the preview image "
            "(imagegen or another current image tool) that the user approved before implementation."
        )
    shots = SCREENSHOT_LINE.search(body)
    if not shots or not has_link(shots.group(1)):
        problems.append("Add “Screenshots: <links or images>” showing the affected screens after the change.")
    if problems:
        problems.append(
            "UI files changed: " + ", ".join(ui_files[:10]) + (" …" if len(ui_files) > 10 else "")
            + f". If nothing visible changes, add the “{NO_VISUAL_LABEL}” label instead."
        )
    return True, problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["policy", "gate"])
    parser.add_argument("--files", required=True, help="file listing changed paths, one per line")
    parser.add_argument("--labels", help="file listing PR labels, one per line")
    parser.add_argument("--diff", help="unified diff of the PR (policy)")
    parser.add_argument("--body", help="PR description (gate)")
    args = parser.parse_args(argv)

    files = read_lines(args.files)
    labels = set(read_lines(args.labels))
    if args.command == "policy":
        diff_text = Path(args.diff).read_text(encoding="utf-8") if args.diff else ""
        problems = policy(files, labels, diff_text)
    else:
        body = Path(args.body).read_text(encoding="utf-8") if args.body else ""
        ui, problems = gate(files, labels, body)
        print(f"ui={'true' if ui else 'false'}")
    for problem in problems:
        print(f"::error::{problem}")
    if not problems:
        print(f"{args.command}: passed")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
