#!/usr/bin/env python3
"""Select and boot an installed iOS simulator for CI; never downloads runtimes."""
import json
import os
import re
import subprocess
import sys
import unittest
import uuid

TARGET = "iPhone 17 Pro"


def available(item):
    return item.get("isAvailable", True) is True and not item.get("availabilityError")


def runtime_version(runtime):
    version = str(runtime.get("version", ""))
    if not re.fullmatch(r"\d+(?:\.\d+)*", version):
        return ()
    return tuple(map(int, version.split(".")))


def select_simulator(runtimes, devices, device_types):
    """Return (runtime, existing device or None, device type or None, fallback)."""
    compatible = [r for r in runtimes if available(r) and
                  r.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-") and
                  runtime_version(r) and runtime_version(r) >= (26,)]
    compatible.sort(key=lambda r: (runtime_version(r), r["identifier"]), reverse=True)
    if not compatible:
        raise ValueError("No available iOS 26 or newer runtime")
    target_type = next((d for d in device_types if d.get("name") == TARGET and d.get("identifier")), None)
    if target_type:
        # Prefer the newest installed runtime, creating the requested model there if needed.
        runtime = compatible[0]
        candidates = sorted((d for d in devices.get(runtime["identifier"], [])
                             if available(d) and d.get("name") == TARGET and d.get("udid")),
                            key=lambda d: d["udid"])
        return runtime, candidates[0] if candidates else None, target_type, False
    for runtime in compatible:
        candidates = sorted((d for d in devices.get(runtime["identifier"], [])
                             if available(d) and str(d.get("name", "")).startswith("iPhone ") and d.get("udid")),
                            key=lambda d: (d["name"] != TARGET, d["name"], d["udid"]))
        if candidates:
            return runtime, candidates[0], None, True
    raise ValueError("iPhone 17 Pro device type is unavailable and no compatible iPhone simulator exists")


def command(*args, timeout=60):
    return subprocess.run(["xcrun", "simctl", *args], check=True, text=True,
                          capture_output=True, timeout=timeout).stdout


def inventory(kind):
    return json.loads(command("list", kind, "-j"))


def main():
    snapshots = {}
    try:
        for kind in ("runtimes", "devices", "devicetypes"):
            snapshots[kind] = inventory(kind)
        runtime, device, device_type, fallback = select_simulator(
            snapshots["runtimes"]["runtimes"], snapshots["devices"]["devices"],
            snapshots["devicetypes"]["devicetypes"])
        if fallback:
            print(f"iPhone 17 Pro device type unavailable; using available {device['name']} on {runtime['name']}", flush=True)
        if device is None:
            udid = command("create", "AirBorderCI", device_type["identifier"], runtime["identifier"]).strip()
            print(f"Created AirBorderCI ({TARGET}) on {runtime['name']}", flush=True)
        else:
            udid = device["udid"]
            print(f"Selected {device['name']} on {runtime['name']} ({udid})", flush=True)
        udid = str(uuid.UUID(udid)).upper()
        if not os.environ.get("GITHUB_ENV"):
            raise ValueError("GITHUB_ENV is required to export the selected simulator")
        # A booted device does not need another boot command.
        if not device or device.get("state") != "Booted":
            command("boot", udid, timeout=60)
        command("bootstatus", udid, "-b", timeout=180)
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
            output.write(f"SIMULATOR_UDID={udid}\n")
        print(f"Simulator ready: {udid}", flush=True)
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"Simulator selection failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        print("Simulator inventory collected:", file=sys.stderr)
        print(json.dumps(snapshots, indent=2, sort_keys=True), file=sys.stderr)
        return 1
    return 0


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.runtimes = [
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-25-0", "version": "25.0", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0", "version": "26.0", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2", "version": "26.2", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "version": "27.0", "isAvailable": False},
        ]
        self.types = [{"name": TARGET, "identifier": "type-17pro"}]
        self.devices = {r["identifier"]: [] for r in self.runtimes}

    def test_newest_runtime_existing_device(self):
        key = self.runtimes[2]["identifier"]
        self.devices[key] = [{"name": TARGET, "udid": "B", "isAvailable": True},
                             {"name": TARGET, "udid": "A", "isAvailable": True}]
        runtime, device, _, fallback = select_simulator(self.runtimes, self.devices, self.types)
        self.assertEqual(runtime["version"], "26.2")
        self.assertEqual(device["udid"], "A")
        self.assertFalse(fallback)

    def test_missing_target_creates_on_newest_runtime(self):
        runtime, device, kind, fallback = select_simulator(self.runtimes, self.devices, self.types)
        self.assertEqual(runtime["version"], "26.2")
        self.assertIsNone(device)
        self.assertEqual(kind["identifier"], "type-17pro")
        self.assertFalse(fallback)

    def test_fallback_requires_available_iphone(self):
        key = self.runtimes[1]["identifier"]
        self.devices[key] = [{"name": "iPhone 16", "udid": "C", "isAvailable": True}]
        runtime, device, _, fallback = select_simulator(self.runtimes, self.devices, [])
        self.assertTrue(fallback)
        self.assertEqual((runtime["version"], device["name"]), ("26.0", "iPhone 16"))
        self.devices[key][0]["isAvailable"] = False
        with self.assertRaises(ValueError):
            select_simulator(self.runtimes, self.devices, [])

    def test_old_and_unavailable_runtimes_rejected(self):
        with self.assertRaises(ValueError):
            select_simulator([self.runtimes[0], self.runtimes[3]], self.devices, self.types)


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        unittest.main(argv=[sys.argv[0]])
    else:
        sys.exit(main())
