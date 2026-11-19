# PROCEDURAL: Regression coverage for launcher compatibility and process ownership.
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("haneda_walk", Path(__file__).resolve().parents[1] / "haneda-walk.py")
walk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(walk)


class LauncherTests(unittest.TestCase):
    def test_ignores_newer_runtime_that_cannot_run_iphone_13(self):
        supported = {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-13"}
        runtimes = {"runtimes": [
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "isAvailable": True,
             "version": "27.0", "supportedDeviceTypes": [supported]},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1", "isAvailable": True,
             "version": "27.1", "supportedDeviceTypes": [{"identifier": "other-device"}]},
        ]}
        with patch.object(walk.subprocess, "check_output", side_effect=[json.dumps({"devices": {}}), json.dumps(runtimes), "new-uuid\n"]) as output:
            self.assertEqual(walk.choose_device()["udid"], "new-uuid")
            self.assertEqual(output.call_args.args[0][-1], "com.apple.CoreSimulator.SimRuntime.iOS-27-0")

    def test_real_driver_controls_and_cleanup_after_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            session = walk.WalkSession(directory)
            with self.assertRaisesRegex(RuntimeError, "deliberate exit"):
                with session:
                    walk.check_drivers(session)
                    with self.assertRaises(ValueError):
                        session.move("unsupported")
                    self.assertIn("Gate 105", session.status())
                    raise RuntimeError("deliberate exit")
            self.assertEqual(len(session.processes), 2)
            self.assertTrue(all(p.poll() is not None for p in session.processes))
            self.assertTrue(all(h.closed for h in session.handles))


if __name__ == "__main__":
    unittest.main()
