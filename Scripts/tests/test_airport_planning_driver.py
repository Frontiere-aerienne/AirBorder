"""PROCEDURAL: Exercise the airport driver's HTTP contract with a fixed clock."""

import importlib.util
import json
import threading
import unittest
from http.server import HTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


spec = importlib.util.spec_from_file_location(
    "airport_provider", Path(__file__).resolve().parents[1] / "airport-provider-driver.py"
)
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class AirportPlanningDriverTests(unittest.TestCase):
    def setUp(self):
        self.clock = 1_800_000_000
        self.server = HTTPServer(("127.0.0.1", 0), driver.make_handler(clock=lambda: self.clock))
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.01})
        self.thread.start()
        self.addCleanup(self.stop_server)

    def stop_server(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()

    def request(self, path, method="GET"):
        url = f"http://127.0.0.1:{self.server.server_port}{path}"
        with urlopen(Request(url, method=method), timeout=2) as response:
            return json.load(response)

    def test_gate_change_rescopes_lounge_walks_without_refreshing_cafe(self):
        before = self.request("/v1/planning")
        self.clock += 120
        self.assertEqual(self.request("/v1/planning"), before)
        assignment = self.request("/control/gate/108A", "POST")
        after = self.request("/v1/planning")

        self.assertEqual((after["gate"], after["assignmentRevision"]), ("108A", assignment["revision"]))
        self.assertEqual(after["gateCheckedAt"], self.clock)
        self.assertEqual(after["cafe"], before["cafe"])
        self.assertEqual(after["crowd"], before["crowd"])
        self.assertEqual(min(after["lounges"], key=lambda lounge: lounge["walkMinutes"])["place"], "skyLounge")

    def test_independent_expiry_and_reconnection(self):
        self.request("/control/planning-busy", "POST")
        busy = self.request("/v1/planning")
        self.assertEqual((busy["security"]["minutes"], busy["cafe"]["minutes"], busy["crowd"]["level"]), (22, 28, "busy"))
        self.request("/control/planning-expire-cafe", "POST")
        expired = self.request("/v1/planning")
        self.assertLess(expired["cafe"]["observedAt"], self.clock - 15 * 60)
        self.assertEqual(expired["security"], busy["security"])
        self.request("/control/feed-off", "POST")
        with self.assertRaises(HTTPError) as unavailable:
            self.request("/v1/planning")
        self.assertEqual(unavailable.exception.code, 503)
        self.request("/control/feed-on", "POST")
        self.assertEqual(self.request("/v1/planning"), expired)
        self.request("/control/planning-refresh", "POST")
        refreshed = self.request("/v1/planning")
        self.assertEqual(refreshed["cafe"]["observedAt"], self.clock)
        self.assertGreater(refreshed["revision"], expired["revision"])

    def test_fresh_cafe_wait_changes_only_that_observation(self):
        before = self.request("/v1/planning")
        self.clock += 90
        self.request("/control/planning-cafe-wait/17", "POST")
        changed = self.request("/v1/planning")
        self.assertEqual(changed.pop("cafe"), {"minutes": 17, "observedAt": self.clock})
        before.pop("cafe")
        self.assertGreater(changed.pop("revision"), before.pop("revision"))
        self.assertEqual(changed, before)

        current = self.request("/v1/planning")
        for invalid in ("-1", "181", "17.5"):
            with self.subTest(invalid=invalid):
                with self.assertRaises(HTTPError) as response:
                    self.request(f"/control/planning-cafe-wait/{invalid}", "POST")
                self.assertEqual(response.exception.code, 400)
                self.assertEqual(self.request("/v1/planning"), current)

    def test_delay_does_not_refresh_gate_or_replacement_options(self):
        before = self.request("/v1/planning")
        self.clock += 90
        self.request("/control/planning-flight-delayed", "POST")
        delayed = self.request("/v1/planning")
        self.assertEqual(delayed["status"], {"value": "delayed", "observedAt": self.clock})
        self.assertEqual(delayed["gateCheckedAt"], before["gateCheckedAt"])
        self.assertEqual(delayed["flightsCheckedAt"], before["flightsCheckedAt"])

    def test_each_observation_ages_and_recovers_independently_across_outages(self):
        fields = {"gate": ("gateCheckedAt",), "security": ("security", "observedAt"),
                  "cafe": ("cafe", "observedAt"), "crowd": ("crowd", "observedAt"),
                  "status": ("status", "observedAt"), "flights": ("flightsCheckedAt",)}
        def timestamp(snapshot, path):
            for part in path:
                snapshot = snapshot[part]
            return snapshot
        for feed, path in fields.items():
            with self.subTest(feed=feed):
                self.clock += 10
                before = self.request("/v1/planning")
                self.request(f"/control/planning-expire-{feed}", "POST")
                expired = self.request("/v1/planning")
                self.assertEqual(timestamp(expired, path), self.clock - 31 * 60)
                for other, other_path in fields.items():
                    if other != feed:
                        self.assertEqual(timestamp(expired, other_path), timestamp(before, other_path))
                for outage in ("feed", "network"):
                    self.request(f"/control/{outage}-off", "POST")
                    with self.assertRaises(HTTPError) as unavailable:
                        self.request("/v1/planning")
                    self.assertEqual(unavailable.exception.code, 503)
                    self.request(f"/control/{outage}-on", "POST")
                    self.assertEqual(self.request("/v1/planning"), expired)
                self.clock += 10
                self.request(f"/control/planning-refresh-{feed}", "POST")
                refreshed = self.request("/v1/planning")
                self.assertEqual(timestamp(refreshed, path), self.clock)
                for other, other_path in fields.items():
                    if other != feed:
                        self.assertEqual(timestamp(refreshed, other_path), timestamp(expired, other_path))
                self.assertEqual(refreshed["lounges"], expired["lounges"])
                self.assertEqual(refreshed["flights"], expired["flights"])

    def test_older_and_mismatched_snapshots_do_not_mutate_current_state(self):
        initial = self.request("/v1/planning")
        self.request("/control/planning-save", "POST")
        self.clock += 60
        self.request("/control/gate/108A", "POST")
        self.request("/control/planning-flight-delayed", "POST")
        current_assignment = self.request("/v1/assignment")
        current = self.request("/v1/planning")
        self.assertGreater(current["revision"], initial["revision"])
        self.request("/control/planning-replay-saved", "POST")
        self.assertEqual(self.request("/v1/planning"), initial)
        self.assertEqual(self.request("/v1/assignment"), current_assignment)
        self.request("/control/planning-mismatched-assignment", "POST")
        mismatch = self.request("/v1/planning")
        self.assertNotEqual(mismatch["assignmentRevision"], current_assignment["revision"])
        self.assertEqual(mismatch["status"], current["status"])
        self.request("/control/planning-current", "POST")
        self.assertEqual(self.request("/v1/planning"), current)
        self.request("/control/stale-gate", "POST")
        stale = self.request("/v1/assignment")
        self.assertLess(stale["revision"], current_assignment["revision"])
        self.assertEqual(self.request("/v1/planning"), current)
        self.request("/control/conflicting-gate", "POST")
        conflict = self.request("/v1/assignment")
        self.assertEqual(conflict["revision"], current_assignment["revision"])
        self.assertNotEqual(conflict["gate"], current_assignment["gate"])
        self.request("/control/current-gate", "POST")
        self.assertEqual(self.request("/v1/assignment"), current_assignment)

    def test_lounge_availability_changes_without_refreshing_observations(self):
        before = self.request("/v1/planning")
        self.clock += 30
        self.request("/control/planning-lounges-unavailable", "POST")
        unavailable = self.request("/v1/planning")
        self.assertEqual(unavailable["lounges"], [])
        for key in ("gateCheckedAt", "security", "cafe", "crowd", "status", "flightsCheckedAt"):
            self.assertEqual(unavailable[key], before[key])
        self.assertGreater(unavailable["revision"], before["revision"])
        self.clock += 30
        self.request("/control/planning-lounges-restore", "POST")
        restored = self.request("/v1/planning")
        self.assertEqual(restored["lounges"], before["lounges"])
        self.assertGreater(restored["revision"], unavailable["revision"])
        for key in ("gateCheckedAt", "security", "cafe", "crowd", "status", "flightsCheckedAt"):
            self.assertEqual(restored[key], before[key])

    def test_wrong_flight_gate_is_newer_but_does_not_mutate_current_assignment(self):
        current = self.request("/v1/assignment")
        planning = self.request("/v1/planning")
        self.request("/control/wrong-flight-gate", "POST")
        wrong = self.request("/v1/assignment")
        self.assertGreater(wrong["revision"], current["revision"])
        self.assertNotEqual(wrong["flight"], current["flight"])
        self.assertNotEqual(wrong["gate"], current["gate"])
        self.assertEqual(self.request("/v1/planning"), planning)
        self.request("/control/current-gate", "POST")
        self.assertEqual(self.request("/v1/assignment"), current)

    def test_network_outage_differs_from_provider_outage(self):
        original = self.request("/v1/planning")
        self.request("/control/network-off", "POST")
        for path in ("/v1/assignment", "/v1/planning"):
            with self.assertRaises(HTTPError) as offline:
                self.request(path)
            with offline.exception as response:
                self.assertEqual(json.load(response), {"error": "network_unavailable"})
        self.request("/control/network-on", "POST")
        self.assertEqual(self.request("/v1/planning"), original)


if __name__ == "__main__":
    unittest.main()
