"""PROCEDURAL: Verify checkpoint entry phases in trace and HTTP replay."""
import importlib.util
import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import Request, urlopen

scripts = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("checkpoint_driver", scripts / "indoor-signal-emulator.py")
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


class CheckpointEntryTests(unittest.TestCase):
    def test_trace_rejects_non_boolean_values_but_allows_omission(self):
        fixture = scripts / "tests" / "fixtures" / "haneda-lounge-queue.json"
        original = json.loads(fixture.read_text())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.json"
            for value in (None, 0, 1, "true", [], {}):
                with self.subTest(value=value):
                    data = json.loads(json.dumps(original))
                    data["samples"][0]["checkpointEntered"] = value
                    path.write_text(json.dumps(data))
                    with self.assertRaisesRegex(ValueError, "checkpoint entry must be a Boolean"):
                        driver.load_trace(path)
            path.write_text(json.dumps(original))
            self.assertNotIn("checkpointEntered", driver.load_trace(path)[0])

    def test_http_readings_publish_each_entry_phase_and_keep_queue_reports(self):
        fixtures = scripts / "tests" / "fixtures"
        for filename, nodes, queue_option, key in (
            ("haneda-observation-deck.json", ["t3-return-security"], "security_queue", "securityQueue"),
            ("haneda-arrivals-queues.json", ["t3-arrivals-immigration", "t3-arrivals-customs"],
             "facility_queues", "facilityQueues"),
        ):
            with self.subTest(fixture=filename):
                trace = driver.load_trace(fixtures / filename)
                state = driver.SignalState(1, True, False, driver.SignalPublisher("http", "booted", False),
                                           trace=trace, **{queue_option: True})
                server = driver.LoopbackReplayServer(("127.0.0.1", 0), driver.handler_type(state))
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                base = f"http://127.0.0.1:{server.server_port}"
                try:
                    observed = {node: [] for node in nodes}
                    for index in range(len(trace)):
                        with urlopen(base + "/reading", timeout=5) as response:
                            reading = json.load(response)
                        self.assertIn(key, reading)
                        if reading["matchedNodeID"] in observed:
                            observed[reading["matchedNodeID"]].append(reading["checkpointEntered"])
                        elif "checkpointEntered" not in trace[index]:
                            self.assertNotIn("checkpointEntered", reading)
                        if index + 1 < len(trace):
                            with urlopen(Request(base + "/control/next", method="POST"), timeout=5):
                                pass
                    self.assertEqual(observed, {node: [False, True] for node in nodes})
                finally:
                    server.shutdown()
                    thread.join(timeout=5)
                    server.server_close()


if __name__ == "__main__":
    unittest.main()
