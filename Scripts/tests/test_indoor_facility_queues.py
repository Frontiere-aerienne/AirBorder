"""PROCEDURAL: Verify independently controlled facility queue replay inputs."""
import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path

scripts = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("facility_driver", scripts / "indoor-signal-emulator.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class FacilityQueueTests(unittest.TestCase):
    def state(self, fixture, enabled=True, security=False):
        trace = driver.load_trace(scripts / "tests" / "fixtures" / fixture)
        return driver.SignalState(1, True, False, driver.SignalPublisher("http", "booted", False),
                                  trace=trace, facility_queues=enabled, security_queue=security)

    def reports(self, state, long):
        reports = state.served_reading()["facilityQueues"]
        self.assertEqual([r["kind"] for r in reports], ["lounge", "immigration", "customs"])
        self.assertEqual([r["additionalWaitMinutes"] for r in reports], [8, 18, 6] if long else [0, 0, 0])
        self.assertEqual([len(r["pedestrians"]) for r in reports], [8, 12, 8] if long else [2, 3, 2])
        for report in reports:
            people = report["pedestrians"]
            self.assertEqual([p["id"] for p in people], list(range(len(people))))
            for person in people:
                self.assertTrue(-4 <= person["x"] <= 4 and -19 <= person["z"] <= 3)
                self.assertEqual(set(person), {"id", "x", "z", "headingDegrees", "stride"})
        self.assertEqual(len({p["x"] for p in reports[1]["pedestrians"]}), 2)
        self.assertTrue(all(1.3 <= p["x"] <= 2.1 for p in reports[2]["pedestrians"]))
        return reports

    def test_opt_in_and_trace_requirement(self):
        state = self.state("haneda-lounge-queue.json", enabled=False)
        self.assertNotIn("facilityQueues", state.served_reading())
        for action in ("facility-queue-normal", "facility-queue-long"):
            with self.assertRaises(ValueError):
                state.control(action)
        result = subprocess.run([sys.executable, str(scripts / "indoor-signal-emulator.py"),
                                 "--facility-queues"], capture_output=True, text=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--facility-queues requires --trace", result.stderr)

    def test_controls_preserve_observation_and_security_independently(self):
        state = self.state("haneda-lounge-queue.json", security=True)
        before = state.reading()
        self.reports(state, False)
        state.control("security-queue-long")
        state.control("facility-queue-long")
        self.assertEqual(state.reading(), before)
        self.assertEqual(state.served_reading()["securityQueue"]["additionalWaitMinutes"], 12)
        self.reports(state, True)
        state.control("facility-queue-normal")
        self.assertEqual(state.reading(), before)
        self.assertEqual(state.served_reading()["securityQueue"]["additionalWaitMinutes"], 12)
        self.reports(state, False)

    def test_reports_persist_across_checkpoints_and_reset(self):
        for fixture, expected, level in (
            ("haneda-lounge-queue.json", [("t3-lounge-entrance", None), ("gate-105", None)], 4),
            ("haneda-arrivals-queues.json", [("t3-arrivals-immigration", None), ("t3-arrivals-immigration", None),
             ("t3-arrivals-baggage", False), ("t3-arrivals-baggage", True),
             ("t3-arrivals-customs", None), ("t3-arrivals-customs", None), ("t3-arrivals-exit", False),
             ("t3-arrivals-exit", True)], 2),
        ):
            with self.subTest(fixture=fixture):
                state = self.state(fixture)
                state.control("facility-queue-long")
                for index, (node, clearance) in enumerate(expected):
                    reading = state.reading()
                    self.assertEqual((reading["matchedNodeID"], reading["clearanceConfirmed"], reading["level"]),
                                     (node, clearance, level))
                    self.reports(state, True)
                    if index < len(expected) - 1:
                        state.control("next")
                state.control("reset")
                self.assertEqual(state.status()["sampleIndex"], 0)
                self.reports(state, False)


if __name__ == "__main__":
    unittest.main()
