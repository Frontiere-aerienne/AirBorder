# PROCEDURAL: Black-box checks of the standalone QA input source, without the app.
import json
import os
import pathlib
import random
import sys
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from indoor_replay_process import running_driver


class DriverTests(unittest.TestCase):
    def setUp(self):
        driver = running_driver()
        self.base = driver.__enter__()
        self.addCleanup(driver.__exit__, None, None, None)

    def request(self, path, method="GET"):
        with urlopen(Request(self.base + path, method=method), timeout=3) as response:
            return json.load(response)

    def step(self, action):
        return self.request("/control/" + action, "POST")

    def test_scripted_labels_and_replay(self):
        start = self.request("/reading")
        self.assertEqual((start["matchedNodeID"], start["level"]), ("t3-transfer-security", 3))
        self.assertEqual(start["source"], "externalSignalReplay")
        self.assertRegex(start["observedAt"], r"^\d{4}-\d\d-\d\dT.*Z$")
        self.assertEqual(start["point"], {"x": 0.1, "y": 0.55})
        self.assertEqual(self.step("previous")["sampleIndex"], 0)
        self.assertEqual(self.request("/status")["sampleCount"], 13)
        for _ in range(9):
            self.step("next")
        upper = self.request("/reading")
        self.assertEqual((upper["matchedNodeID"], upper["level"]), ("t3-gates-center", 4))
        for _ in range(4):
            self.step("next")
        end = self.request("/reading")
        self.assertEqual((end["matchedNodeID"], end["level"]), ("gate-105", 4))
        self.assertEqual(self.request("/status")["sampleIndex"], 12)
        self.assertEqual(self.step("reset")["sampleIndex"], 0)
        self.assertTrue(self.request("/status")["paused"])
        reset = self.request("/reading")
        self.assertEqual({k: v for k, v in reset.items() if k != "observedAt"},
                         {k: v for k, v in start.items() if k != "observedAt"})

    def test_invalid_requests_leave_replay_unchanged(self):
        before = self.request("/status")
        for path, method, code in [("/missing", "GET", 404), ("/control/invalid", "POST", 400)]:
            with self.assertRaises(HTTPError) as error:
                self.request(path, method)
            self.assertEqual(error.exception.code, code)
            error.exception.close()
        self.assertEqual(self.request("/status"), before)

    def test_randomized_paused_replay_controls(self):
        seed_text = os.environ.get("AIRBORDER_DRIVER_TEST_SEED")
        seed = int(seed_text) if seed_text is not None else random.SystemRandom().getrandbits(64)
        rng = random.Random(seed)
        print(f"AIRBORDER_DRIVER_TEST_SEED={seed}", flush=True)

        # Input delivery stays paused so the random control sequence is the only clock.
        # Include boundary bursts on every run and vary the actions between them.
        actions = ["previous"] * 2
        actions += rng.choices(["next", "previous", "reset", "pause", "invalid"], k=48)
        actions += ["next"] * 15 + ["reset"]
        index = sequence = 0
        for step, action in enumerate(actions):
            with self.subTest(seed=seed, step=step, action=action):
                if action == "invalid":
                    with self.assertRaises(HTTPError) as error:
                        self.step(action)
                    self.assertEqual(error.exception.code, 400)
                    error.exception.close()
                    status = self.request("/status")
                else:
                    sequence += 1
                    index = {"next": min(index + 1, 12), "previous": max(index - 1, 0),
                             "reset": 0, "pause": index}[action]
                    status = self.step(action)
                self.assertEqual(status["sampleIndex"], index)
                self.assertEqual(status["sequence"], sequence)
                self.assertTrue(status["paused"])
                reading = self.request("/reading")
                self.assertEqual(reading["matchedNodeID"], status["matchedNodeID"])
                self.assertIn(reading["level"], (3, 4))
                self.assertTrue(all(0 <= reading["point"][axis] <= 1 for axis in ("x", "y")))


if __name__ == "__main__":
    unittest.main()
