#!/usr/bin/env python3
# PROCEDURAL: Starts the existing local drivers and simulator with simple walk controls.

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.example.AirportXRCompanion"


def request(base, path, *, post=False):
    req = urllib.request.Request(base + path, method="POST" if post else "GET")
    with urllib.request.urlopen(req, timeout=3) as response:
        return json.load(response)


class WalkSession:
    """Own only the two child processes created for this walk, on unused ports."""

    def __init__(self, logs):
        self.logs = Path(logs)
        self.logs.mkdir(parents=True, exist_ok=True)
        self.processes = []
        self.handles = []
        self.indoor = None
        self.airport = None

    def __enter__(self):
        try:
            self.indoor = self._start("indoor", "indoor-signal-emulator.py",
                                      ["--haneda-gate-replanning", "--paused", "--no-loop"],
                                      r"Indoor signal emulator: (http://127\.0\.0\.1:\d+)/reading", "/status")
            self.airport = self._start("airport", "airport-provider-driver.py", [],
                                       r"Airport provider replay: (http://127\.0\.0\.1:\d+)/v1/assignment",
                                       "/v1/assignment")
            return self
        except BaseException:
            self.close()
            raise

    def _start(self, name, script, arguments, pattern, health):
        path = self.logs / (name + ".log")
        handle = path.open("w")
        self.handles.append(handle)
        child = subprocess.Popen([sys.executable, str(ROOT / "Scripts" / script),
                                  *arguments, "--port", "0"], stdout=handle, stderr=subprocess.STDOUT)
        self.processes.append(child)
        # Cold Python imports on a hosted Mac can exceed a few seconds. Poll
        # readiness, with a bound, instead of assuming a local startup speed.
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline:
            if child.poll() is not None:
                raise RuntimeError(f"{name.title()} driver stopped. Details: {path}")
            match = re.search(pattern, path.read_text())
            if match:
                request(match[1], health)
                return match[1]
            time.sleep(0.05)
        tail = path.read_text()[-2000:]
        raise RuntimeError(f"{name.title()} driver did not become ready. Details: {path}\n{tail}")

    def close(self):
        for child in self.processes:
            if child.poll() is None:
                child.terminate()
        for child in self.processes:
            try:
                child.wait(timeout=4)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=4)
        for handle in self.handles:
            handle.close()

    def __exit__(self, *_):
        self.close()

    def move(self, action):
        if action not in {"resume", "pause", "next", "passage-blocked", "passage-open"}:
            raise ValueError("Unknown walk action")
        return request(self.indoor, "/control/" + action, post=True)

    def gate(self, value):
        if value not in {"105", "108A"}:
            raise ValueError("This walk covers Gates 105 and 108A")
        return request(self.airport, "/control/gate/" + value, post=True)

    def restart(self):
        self.move("pause")
        self.gate("105")
        return request(self.indoor, "/control/reset", post=True)

    def status(self):
        walking = request(self.indoor, "/status")
        gate = request(self.airport, "/v1/assignment")["gate"]
        progress = round(100 * walking["sampleIndex"] / max(walking["sampleCount"] - 1, 1))
        return f"Gate {gate} · {progress}% of current route · {'Paused' if walking['paused'] else 'Walking'}"


def run(command, log=None):
    if log:
        with Path(log).open("w") as output:
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f"Setup did not finish. Details: {log}")
    else:
        subprocess.run(command, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)


def choose_device(requested=None):
    result = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True)
    devices = [d for group in json.loads(result)["devices"].values() for d in group]
    if requested:
        matches = [d for d in devices if requested in {d["udid"], d["name"]}]
        if not matches:
            raise RuntimeError("The requested simulator is unavailable. Check its name in Xcode.")
        return matches[0]
    # A dedicated simulator keeps the walk's reset separate from other simulator data.
    matches = [d for d in devices if d["name"] == "AirBorder Haneda Walk"]
    if matches:
        return matches[0]
    runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"], text=True))
    device_type = "com.apple.CoreSimulator.SimDeviceType.iPhone-13"
    # A newer installed runtime can support a different device family only.
    # Select the newest runtime that actually supports this walk's iPhone.
    ios = [r for r in runtimes["runtimes"] if r.get("isAvailable")
           and r.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
           and any(d.get("identifier") == device_type for d in r.get("supportedDeviceTypes", []))]
    if not ios:
        raise RuntimeError("Install an iPhone 13-compatible iOS simulator runtime in Xcode, then start the walk again.")
    runtime = max(ios, key=lambda r: tuple(int(x) for x in r["version"].split(".")))
    device_id = subprocess.check_output(["xcrun", "simctl", "create", "AirBorder Haneda Walk",
                                         device_type, runtime["identifier"]], text=True).strip()
    return {"udid": device_id, "name": "AirBorder Haneda Walk", "state": "Shutdown"}


def launch_app(session, args):
    device = choose_device(args.device)
    if device["state"] != "Booted":
        print("Starting the iPhone simulator…", flush=True)
        run(["xcrun", "simctl", "boot", device["udid"]])
    run(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], session.logs / "simulator.log")
    build = Path(args.derived_data).expanduser().resolve() if args.derived_data else ROOT / "build/HanedaWalk"
    if not args.skip_build:
        print("Building AirBorder. The first build takes longer…", flush=True)
        run(["xcodebuild", "build", "-project", "AirBorder.xcodeproj", "-scheme", "AirBorder",
             "-configuration", "Debug", "-destination", "platform=iOS Simulator,id=" + device["udid"],
             "-derivedDataPath", str(build), "CODE_SIGNING_ALLOWED=NO"], session.logs / "build.log")
    app = build / "Build/Products/Debug-iphonesimulator/AirBorder.app"
    if not app.is_dir():
        raise RuntimeError("The built app is missing. Start again without --skip-build.")
    run(["xcrun", "simctl", "install", device["udid"], str(app)])
    subprocess.run(["xcrun", "simctl", "terminate", device["udid"], BUNDLE_ID], capture_output=True)
    run(["xcrun", "simctl", "launch", device["udid"], BUNDLE_ID, "-resetState", "-skipOnboarding",
         "-walkingSpeed", "5.6", "-gateUpdate", "off", "--uitesting", "--qa-open-route",
         "--qa-indoor-feed", session.indoor + "/reading", "--qa-official-walk", "adaptive",
         "--qa-airport-provider", session.airport + "/v1/assignment"])
    # Resolve from the selected Xcode instead of relying on Launch Services to
    # have indexed an app named Simulator (fresh Xcode installs may not have).
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    simulator = developer / "Applications/Simulator.app"
    if simulator.is_dir():
        run(["open", "-a", str(simulator), "--args", "-CurrentDeviceUDID", device["udid"]])
    else:
        print("AirBorder is running, but this Xcode installation has no Simulator desktop app.\n"
              "Install the full Xcode app to interact with its iPhone window. The walk controls still work.", flush=True)
    return device["udid"]


def check_drivers(session):
    before = request(session.indoor, "/reading")["point"]
    session.move("resume")
    session.move("pause")
    session.move("next")
    # The trace deliberately includes an unconfirmed-floor observation. Reassign
    # only once it reaches a confirmed position, as the app's route layer does.
    if not request(session.indoor, "/reading")["floorConfirmed"]:
        session.move("next")
    session.gate("108A")
    assert request(session.airport, "/v1/assignment")["gate"] == "108A"
    # Exercise the same route request the app makes, retaining the current pose.
    point = request(session.indoor, "/reading")["point"]
    request(session.indoor, "/control/gate-108a", post=True)
    assert request(session.indoor, "/reading")["point"] == point
    session.restart()
    assert request(session.indoor, "/reading")["point"] == before
    assert "Gate 105" in session.status()
    print("Driver startup, motion, pause, gate reassignment and reset passed.")


def main():
    parser = argparse.ArgumentParser(description="Open AirBorder's Haneda walk with simple local driver controls.")
    parser.add_argument("--device", help="Simulator name or UUID; otherwise use a dedicated iPhone 13")
    parser.add_argument("--derived-data", help="Existing or new Xcode build directory")
    parser.add_argument("--skip-build", action="store_true", help="Use an already built app")
    parser.add_argument("--drivers-only", action="store_true", help="Run controls without launching Simulator")
    parser.add_argument("--check-drivers", action="store_true", help="Exercise the two real drivers and exit")
    args = parser.parse_args()
    logs = Path.home() / "Library/Logs/AirBorder Walk" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    try:
        with WalkSession(logs) as session:
            if args.check_drivers:
                check_drivers(session)
                return
            if not args.drivers_only:
                launch_app(session, args)
            print("\nAirBorder Haneda walk controls are ready.\nIn the Simulator window, use Map and Camera to switch views.")
            print("The map image loads from Haneda; no API key or AI service is used.")
            print("\n1 Walk   2 Pause   3 Next position   4 Gate 108A   5 Gate 105")
            print("6 Close passage   7 Reopen passage   8 Restart walk   9 Status   Q Quit")
            actions = {"1": "resume", "2": "pause", "3": "next", "6": "passage-blocked", "7": "passage-open"}
            while True:
                try:
                    choice = input("\nChoose a control: ").strip().lower()
                except EOFError:
                    return
                if choice in {"q", "quit"}:
                    return
                try:
                    if choice in actions:
                        session.move(actions[choice])
                    elif choice in {"4", "5"}:
                        session.gate("108A" if choice == "4" else "105")
                    elif choice == "8":
                        session.restart()
                    elif choice != "9":
                        print("Choose 1–9 or Q.")
                        continue
                    print(session.status())
                except (OSError, ValueError) as exc:
                    print(f"That control did not finish: {exc}. Logs: {logs}")
    except KeyboardInterrupt:
        print("\nWalk stopped.")
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"\n{exc}\nLogs: {logs}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
