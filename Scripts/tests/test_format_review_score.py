# PROCEDURAL: Verify totals, partial assessments and score validation without an LLM.
import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "reporting/format_review_score.py"
SPEC = importlib.util.spec_from_file_location("format_review_score", SCRIPT)
FORMAT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FORMAT)
RUBRIC = "| R-INTRO | Introduction | 10 | Description |\n| R-METHOD | Method | 10 | Procedure |"


class ReviewScoreTests(unittest.TestCase):
    def setUp(self):
        self.rows = [
            {"id": "R-INTRO", "points": 10, "evidence": "Introduction names the intended traveler."},
            {"id": "R-METHOD", "points": 7, "evidence": "Method describes both tasks.",
             "gap": "Task order is unspecified.", "revision": "State how task order is assigned."},
        ]

    def test_totals_and_bands(self):
        review = FORMAT.render_review(self.rows, RUBRIC)
        self.assertIn("17/20", review)
        self.assertIn("7 / 10 | Needs improvement", review)
        self.assertIn("State how task order is assigned.", review)

    def test_unassessed_is_not_zero(self):
        self.rows[1].update(points=None, evidence="Method appendix unavailable.")
        review = FORMAT.render_review(self.rows, RUBRIC)
        self.assertIn("10/10 assessed points; 10 points not assessed", review)
        self.assertIn("Not assessed", review)

    def test_invalid_point_values_are_rejected(self):
        for points in (-1, 11, True, 7.5):
            with self.subTest(points=points), self.assertRaises(ValueError):
                FORMAT.render_review([self.rows[0], dict(self.rows[1], points=points)], RUBRIC)

    def test_missing_and_duplicate_criteria_are_rejected(self):
        for rows in (self.rows[:1], self.rows + self.rows[:1]):
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                FORMAT.render_review(rows, RUBRIC)

    def test_deduction_requires_actionable_feedback_fields(self):
        for key in ("evidence", "gap", "revision"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                FORMAT.render_review([self.rows[0], dict(self.rows[1], **{key: " "})], RUBRIC)


if __name__ == "__main__":
    unittest.main()
