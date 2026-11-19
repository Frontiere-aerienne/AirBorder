"""PROCEDURAL: Check the driver's continuous Haneda walk, recovery, and reroute."""

import importlib.util
import random
import unittest
from pathlib import Path
from unittest.mock import patch


scripts = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("indoor_driver", scripts / "indoor-signal-emulator.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class CafeWalkTests(unittest.TestCase):
    def setUp(self):
        fixtures = scripts / "tests" / "fixtures"
        walk105 = driver.load_trace(fixtures / "haneda-gate-105-walk.json")
        walk108a = driver.load_trace(fixtures / "haneda-gate-108a-walk.json")
        network = driver.HanedaGateNetwork([walk105, walk108a])
        trace = network.extend_to_cafe(walk105[0])
        self.state = driver.SignalState(1, True, False, driver.SignalPublisher("http", "booted", False),
                                        trace=trace, network=network)

    def reach_cafe(self):
        self.assertTrue(self.state.reassign("105", False, cafe_pending=True))
        for _ in range(self.state.status()["sampleCount"]):
            self.state.control("next")
        self.assertEqual(self.state.reading()["matchedNodeID"], "t3-curacion-cafe")

    def test_cafe_leg_emits_multiple_positions_and_holds_at_entrance(self):
        self.assertTrue(self.state.reassign("105", False, cafe_pending=True))
        path = self.state.map_path()
        self.assertEqual(path["destination"], "t3-departure-gate-105")
        self.assertGreater(len(path["points"]), 5)
        self.assertEqual(len(path["points"]), len({tuple(point.values()) for point in path["points"]}))
        previous = self.state.reading()["point"]
        self.state.control("next")
        self.assertNotEqual(self.state.reading()["point"], previous)
        self.reach_cafe()
        reached = self.state.reading()["point"]
        self.state.control("next")
        self.assertEqual(self.state.reading()["point"], reached)

    def test_wrong_same_floor_match_recovers_only_with_matching_token(self):
        self.reach_cafe()
        confirmed = self.state.reading()["point"]
        self.state.control("misread-landmark")
        wrong = self.state.served_reading()
        self.assertNotEqual(wrong["point"], confirmed)
        self.assertEqual(wrong["level"], 3)
        self.assertFalse(self.state.confirm_landmark(wrong["landmarkToken"] - 1))
        self.assertTrue(self.state.confirm_landmark(wrong["landmarkToken"]))
        self.assertEqual(self.state.served_reading()["point"], confirmed)

    def test_cafe_departure_and_gate_change_start_at_current_coordinate(self):
        self.reach_cafe()
        checkpoint = self.state.reading()["point"]
        self.assertTrue(self.state.reassign("105", False))
        self.assertEqual(self.state.map_path()["points"][0], checkpoint)
        for _ in range(80):
            self.state.control("next")
        before = self.state.reading()
        self.assertTrue(self.state.reassign("108a", False))
        after = self.state.reading()
        self.assertEqual(before["point"], after["point"])
        self.assertEqual(before["headingDegrees"], after["headingDegrees"])
        self.assertNotEqual(before["routeRevision"], after["routeRevision"])
        self.assertEqual(self.state.map_path()["points"][0], before["point"])
        self.assertEqual(self.state.map_path()["destination"], "t3-departure-gate-108a")
        self.state.control("next")
        self.assertNotEqual(self.state.reading()["point"], before["point"])

    def test_gate_change_preserves_pose_at_seeded_positions_along_the_walk(self):
        self.reach_cafe()
        self.assertTrue(self.state.reassign("105", False))
        # Vary the event's position while keeping the walk on the existing route graph.
        seed = 108105
        positions = random.Random(seed).sample(range(1, self.state.status()["sampleCount"] - 1), 12)
        for position in positions:
            with self.subTest(seed=seed, position=position):
                self.state.control("reset")
                self.reach_cafe()
                self.assertTrue(self.state.reassign("105", False))
                for _ in range(position):
                    self.state.control("next")
                before = self.state.reading()
                self.assertEqual(self.state.status()["sampleIndex"], position)

                self.assertTrue(self.state.reassign("108a", False))
                after = self.state.reading()
                self.assertEqual(after["point"], before["point"])
                self.assertEqual(after["headingDegrees"], before["headingDegrees"])
                self.assertGreater(after["routeRevision"], before["routeRevision"])
                route = self.state.map_path()
                self.assertEqual(route["points"][0], before["point"])
                self.assertEqual(route["destination"], "t3-departure-gate-108a")
                self.state.control("next")
                self.assertNotEqual(self.state.reading()["point"], before["point"])

    def test_crowd_observation_does_not_restart_or_change_either_walk(self):
        for prefers_quieter in (False, True):
            with self.subTest(prefers_quieter=prefers_quieter):
                self.state.control("reset")
                self.assertTrue(self.state.reassign("108a", prefers_quieter))
                position = self.state.reading()
                route = self.state.map_path()
                self.assertIsNone(route["crowdReport"])
                self.state.control("crowd-on")
                self.assertTrue(self.state.reassign("108a", prefers_quieter))
                updated = self.state.map_path()
                self.assertEqual(self.state.reading(), position)
                for key in ("points", "revision", "destination"):
                    self.assertEqual(route[key], updated[key])

                report = updated["crowdReport"]
                self.assertEqual(report["delayMinutes"], 3)
                strip = report["start"]["y"]
                low, high = report["start"]["x"], report["end"]["x"]
                edges = zip(updated["points"], updated["points"][1:])
                crosses = any(
                    a["y"] == b["y"] == strip and max(min(a["x"], b["x"]), low) < min(max(a["x"], b["x"]), high)
                    for a, b in edges
                )
                self.assertEqual(crosses, not prefers_quieter)
                self.state.control("crowd-expire")
                self.assertLess(self.state.map_path()["crowdReport"]["reportedAt"], report["reportedAt"] - 300)
                self.state.control("crowd-off")
                self.assertEqual(self.state.map_path(), route)

    def test_pedestrians_cross_sightline_without_changing_position_route_or_alerts(self):
        network = self.state.network
        x, y = network.crowd_start
        start = dict(self.state.reading(), point={"x": x, "y": y}, headingDegrees=90)
        trace = network.path(start, "t3-departure-gate-105")
        state = driver.SignalState(1, True, False, self.state.publisher, trace=trace, network=network,
                                   pedestrian_occlusion=True)
        self.assertNotIn("pedestrians", self.state.map_path())
        with self.assertRaises(ValueError):
            self.state.control("pedestrians-cross")
        state.control("passage-blocked")  # Existing closure makes the left turn necessary.
        position = state.reading()
        route = state.map_path()
        starting_poses = {pose["id"]: pose for pose in route.pop("pedestrians")}
        self.assertEqual(route["closure"], "detour")
        self.assertEqual(len(starting_poses), 3)
        self.assertGreater(starting_poses[0]["x"], 1)

        with patch.object(driver.time, "monotonic", return_value=100):
            state.control("pedestrians-cross")
        with patch.object(driver.time, "monotonic", return_value=103.15):
            during = state.map_path()
        during_poses = {pose["id"]: pose for pose in during.pop("pedestrians")}
        self.assertAlmostEqual(during_poses[0]["x"], -0.64, delta=0.04)
        self.assertLess(during_poses[1]["z"], starting_poses[1]["z"])
        self.assertGreater(during_poses[2]["z"], starting_poses[2]["z"])
        self.assertEqual(during, route)
        self.assertEqual(state.reading(), position)

        with patch.object(driver.time, "monotonic", return_value=105):
            after = state.map_path()
        self.assertEqual({pose["id"] for pose in after.pop("pedestrians")}, {1, 2})
        self.assertEqual(after, route)
        self.assertEqual(state.reading(), position)
        self.assertIsNone(after["crowdReport"])

    def test_blocked_passage_reroutes_from_the_same_facing_point_and_leaves_bypass_intact(self):
        network = self.state.network
        x, y = network.crowd_start
        start = dict(self.state.reading(), point={"x": x, "y": y}, headingDegrees=90)
        trace = network.path(start, "t3-departure-gate-105")
        state = driver.SignalState(1, True, False, self.state.publisher, trace=trace, network=network)
        was = state.reading()
        self.assertTrue(network.uses_passage(trace))
        state.control("passage-blocked")
        now = state.reading()
        self.assertEqual((was["point"], was["headingDegrees"]), (now["point"], now["headingDegrees"]))
        self.assertNotEqual(was["routeRevision"], now["routeRevision"])
        self.assertEqual(state.map_path()["closure"], "detour")
        self.assertFalse(network.uses_passage(state.samples))
        self.assertEqual(state.map_path()["points"][1]["x"], x)
        self.assertLess(state.map_path()["points"][1]["y"], y)
        state.control("next")
        self.assertLess(state.reading()["point"]["y"], y)
        self.assertEqual(state.reading()["headingDegrees"], 45)

        state.control("reset")
        self.assertTrue(state.reassign("105", True))
        bypass = state.map_path()
        position = state.reading()
        state.control("passage-blocked")
        self.assertEqual(state.map_path(), bypass)
        self.assertEqual(state.reading(), position)

    def test_passage_block_without_an_exit_holds_current_position(self):
        network = self.state.network
        low, high = network.crowd_start[0], network.crowd_end[0]
        x, y = next((x, y) for x, y in network.neighbours if low < x < high and y == network.crowd_start[1])
        start = dict(self.state.reading(), point={"x": x, "y": y}, headingDegrees=90)
        trace = network.path(start, "t3-departure-gate-105")
        state = driver.SignalState(1, True, False, self.state.publisher, trace=trace, network=network)
        state.control("passage-blocked")
        self.assertEqual(state.map_path()["closure"], "unavailable")
        state.control("next")
        self.assertEqual(state.reading()["point"], start["point"])
        state.control("passage-open")
        state.control("next")
        self.assertNotEqual(state.reading()["point"], start["point"])


if __name__ == "__main__":
    unittest.main()
