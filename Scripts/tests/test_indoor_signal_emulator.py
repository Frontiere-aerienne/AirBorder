# PROCEDURAL: Black-box checks of the standalone QA input source, without the app.
import json
import pathlib
import re
import subprocess
import sys
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen


DRIVER = pathlib.Path(__file__).resolve().parents[1] / "indoor-signal-emulator.py"


class DriverTests(unittest.TestCase):
    def setUp(self):
        self.process = subprocess.Popen(
            [sys.executable, str(DRIVER), "--port", "0", "--paused", "--no-loop"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        self.addCleanup(self.stop_driver)
        # Bound startup too: an emulator that never publishes a URL must fail CI.
        import select
        self.assertTrue(select.select([self.process.stdout], [], [], 5)[0], "Driver did not become ready")
        line = self.process.stdout.readline()
        match = re.fullmatch(r"Indoor signal emulator: (http://127\.0\.0\.1:\d+)/reading\n", line)
        self.assertIsNotNone(match, line)
        self.base = match.group(1)

    def stop_driver(self):
        if self.process.poll() is None:
            self.process.terminate()
        try:
            self.process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.communicate()

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


if __name__ == "__main__":
    unittest.main()
