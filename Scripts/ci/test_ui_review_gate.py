import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ui_review_gate as g  # noqa: E402

DIFF = """diff --git a/AirBorder/Views/Settings/SettingsView.swift b/AirBorder/Views/Settings/SettingsView.swift
--- a/AirBorder/Views/Settings/SettingsView.swift
+++ b/AirBorder/Views/Settings/SettingsView.swift
@@ -10,2 +10,5 @@
 unchanged
+            Text("Confirm passport control, if required")
+            // "Optional" in a comment is fine
+            let value: Optional<Int> = nil
+            Label("Optional · disconnect anytime", systemImage: "heart")
"""


class PolicyTests(unittest.TestCase):
    def test_flags_tags_in_added_string_literals_only(self):
        findings = g.banned_copy(DIFF)
        self.assertEqual(len(findings), 2)
        self.assertIn("SettingsView.swift:11", findings[0])
        self.assertIn("if required", findings[0])
        self.assertIn("SettingsView.swift:14", findings[1])

    def test_ignores_tests_and_non_swift_files(self):
        diff = DIFF.replace("AirBorder/Views/Settings/SettingsView.swift", "AirportXRCompanionUITests/X.swift")
        self.assertEqual(g.banned_copy(diff), [])

    def test_frozen_web_needs_label(self):
        self.assertTrue(g.policy(["Web/app.js"], set(), ""))
        self.assertEqual(g.policy(["Web/app.js"], {"web-change-approved"}, ""), [])

    def test_clean_change_passes(self):
        self.assertEqual(g.policy(["AirBorder/Models/X.swift"], set(), ""), [])


class GateTests(unittest.TestCase):
    BODY_OK = "Preview (approved): https://example.com/preview.png\nScreenshots: ![after](https://example.com/a.png)\n"

    def test_non_ui_change_is_not_gated(self):
        self.assertEqual(g.gate(["Backend/x.ts"], set(), ""), (False, []))

    def test_ui_change_needs_preview_and_screenshots(self):
        ui, problems = g.gate(["AirBorder/Views/Journey/JourneyDashboardView.swift"], set(), "")
        self.assertTrue(ui)
        self.assertEqual(len(problems), 3)

    def test_ui_change_with_evidence_passes(self):
        self.assertEqual(g.gate(["AirBorder/Components/InterfaceComponents.swift"], set(), self.BODY_OK), (True, []))

    def test_template_placeholder_without_link_fails(self):
        _, problems = g.gate(["AirBorder/Views/A.swift"], set(), "Preview (approved):\nScreenshots:\n")
        self.assertEqual(len(problems), 3)

    def test_no_visual_change_label_skips(self):
        self.assertEqual(g.gate(["AirBorder/Views/A.swift"], {"no-visual-change"}, ""), (True, []))


if __name__ == "__main__":
    unittest.main()
