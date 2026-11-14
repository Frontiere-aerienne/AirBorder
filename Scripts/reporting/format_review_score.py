#!/usr/bin/env python3
"""PROCEDURAL: Validate advisory model grades and total them against the course rubric."""

import argparse
import json
import re
from pathlib import Path


RUBRIC = Path(__file__).resolve().parents[2] / ".github/report-review/RUBRIC.md"


def render_review(rows, rubric_text):
    criteria = re.findall(
        r"^\|\s*(R-[A-Z]+)\s*\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|",
        rubric_text,
        re.MULTILINE,
    )
    if not criteria or len({row[0] for row in criteria}) != len(criteria):
        raise ValueError("Rubric has missing or duplicate scored criteria")
    if not isinstance(rows, list):
        raise ValueError("Expected a JSON array of criterion reviews")
    indexed = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            raise ValueError("Each review row must be an object with a criterion ID")
        if row["id"] in indexed:
            raise ValueError(f"Duplicate criterion: {row['id']}")
        indexed[row["id"]] = row
    if indexed.keys() != {row[0] for row in criteria}:
        raise ValueError("Supply exactly one review row for every scored rubric ID")

    def field(row, key, required=True):
        value = row.get(key, "")
        if not isinstance(value, str) or (required and not value.strip()):
            raise ValueError(f"{row['id']}: {key} must provide specific text")
        return " ".join(value.split()).replace("|", "&#124;")

    earned = assessed = 0
    total = sum(int(points) for _, _, points in criteria)
    lines = []
    for criterion_id, name, max_points in criteria:
        limit = int(max_points)
        row = indexed[criterion_id]
        if "points" not in row:
            raise ValueError(f"{criterion_id}: supply points or explicit null")
        points = row["points"]
        if points is not None and (type(points) is not int or not 0 <= points <= limit):
            raise ValueError(f"{criterion_id}: points must be an integer from 0 to {limit}, or null")
        evidence = field(row, "evidence")
        gap = field(row, "gap", required=points != limit)
        revision = field(row, "revision", required=points != limit)
        if points is None:
            score, band = f"— / {limit}", "Not assessed"
        else:
            score = f"{points} / {limit}"
            band = ("Meets" if points * 4 > limit * 3 else
                    "Needs improvement" if points * 2 >= limit else "Unacceptable")
            earned += points
            assessed += limit
        lines.append(f"| {criterion_id}: {name} | {score} | {band} | {evidence} | {gap or '—'} | {revision or '—'} |")

    if assessed == total:
        summary = f"**Advisory report estimate: {earned}/{total}.**"
    elif assessed:
        summary = f"**Partial advisory estimate: {earned}/{assessed} assessed points; {total - assessed} points not assessed.**"
    else:
        summary = f"**No estimate: all {total} points were unassessed.**"
    return "\n".join([
        summary, "", "Video, peer evaluation, and format penalties are excluded.", "",
        "| Criterion | Points | Rubric band | Evidence | Gap or reason for deduction | Specific revision |",
        "|---|---:|---|---|---|---|", *lines,
    ])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("review", type=Path, help="JSON array of evidence-backed rubric grades")
    args = parser.parse_args()
    try:
        print(render_review(json.loads(args.review.read_text()), RUBRIC.read_text()))
    except (ValueError, OSError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
