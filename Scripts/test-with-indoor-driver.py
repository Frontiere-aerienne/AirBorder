#!/usr/bin/env python3
# PROCEDURAL: Owns the replay subprocess for a simulator test invocation.
import os
import pathlib
import re
import select
import subprocess
import sys


def main():
    if len(sys.argv) < 2:
        raise SystemExit("Usage: python3 Scripts/test-with-indoor-driver.py xcodebuild [arguments...]")

    driver = pathlib.Path(__file__).with_name("indoor-signal-emulator.py")
    with subprocess.Popen(
        [sys.executable, str(driver), "--port", "0", "--paused", "--no-loop"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    ) as process:
        try:
            line = process.stdout.readline() if select.select([process.stdout], [], [], 5)[0] else ""
            match = re.fullmatch(r"Indoor signal emulator: (http://127\.0\.0\.1:\d+)/reading\n", line)
            if match is None:
                raise SystemExit(f"Indoor replay driver did not start: {line.strip()}")
            env = os.environ.copy()
            env["TEST_RUNNER_AIRBORDER_QA_REPLAY_URL"] = match.group(1)
            return subprocess.call(sys.argv[1:], env=env)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    sys.exit(main())
