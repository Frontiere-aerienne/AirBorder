"""PROCEDURAL: Verify independent security queue replay observations."""

import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path


scripts = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("indoor_security_driver", scripts / "indoor-signal-emulator.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class SecurityQueueTests(unittest.TestCase):
    def make_state(self, enabled=False):
        trace = driver.load_trace(scripts / "tests" / "fixtures" / "haneda-observation-deck.json")
        return driver.SignalState(1, True, False, driver.SignalPublisher("http", "booted", False),
                                  trace=trace, security_queue=enabled)

    def assert_report(self, state, count, minutes):
        report = state.served_reading()["securityQueue"]
        self.assertEqual(report["additionalWaitMinutes"], minutes)
        self.assertEqual(len(report["pedestrians"]), count)
        self.assertEqual(len({person["id"] for person in report["pedestrians"]}), count)

    def test_queue_requires_opt_in(self):
        state = self.make_state()
        self.assertNotIn("securityQueue", state.served_reading())
        for action in ("security-queue-normal", "security-queue-long"):
            with self.subTest(action=action), self.assertRaises(ValueError):
                state.control(action)
        result = subprocess.run([sys.executable, str(scripts / "indoor-signal-emulator.py"),
                                 "--security-queue"], capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--security-queue requires --trace", result.stderr)

    def test_controls_change_only_queue_report_at_checkpoint(self):
        state = self.make_state(True)
        while state.reading()["matchedNodeID"] != "t3-return-security":
            state.control("next")
        baseline = state.reading()
        self.assert_report(state, 3, 0)
        for action, count, minutes in (("security-queue-long", 12, 12),
                                       ("security-queue-normal", 3, 0)):
            with self.subTest(action=action):
                state.control(action)
                self.assertEqual(state.reading(), baseline)
                served = state.served_reading()
                served.pop("securityQueue")
                self.assertEqual(served, baseline)
                self.assert_report(state, count, minutes)

    def test_airside_still_receives_report_and_reset_restores_normal(self):
        state = self.make_state(True)
        state.control("security-queue-long")
        while not (state.reading()["matchedNodeID"] == "t3-after-security"
                   and state.reading().get("clearanceConfirmed") is True):
            before = state.status()["sampleIndex"]
            state.control("next")
            self.assertGreater(state.status()["sampleIndex"], before, "confirmed airside observation missing")
        airside = state.reading()
        self.assert_report(state, 12, 12)
        state.control("security-queue-normal")
        self.assertEqual(state.reading(), airside)
        self.assert_report(state, 3, 0)
        state.control("security-queue-long")
        state.control("reset")
        self.assertEqual(state.status()["sampleIndex"], 0)
        self.assert_report(state, 3, 0)


if __name__ == "__main__":
    unittest.main()
