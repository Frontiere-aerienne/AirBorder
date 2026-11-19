#!/usr/bin/env python3
# PROCEDURAL: Supplies local macOS dictation to the iPhone Simulator.
"""Run on loopback, discard each WAV after use, and return only the transcript."""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


def handler_for(helper):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/transcribe":
                self.send_error(404)
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.send_error(400)
                return
            if self.headers.get_content_type() != "audio/wav" or not 44 <= length <= 450_000:
                self.send_error(400)
                return
            self.connection.settimeout(7)
            try:
                audio = self.rfile.read(length)
                if not audio.startswith(b"RIFF") or audio[8:12] != b"WAVE" or len(audio) != length:
                    self.send_error(400)
                    return
                with TemporaryDirectory(prefix="airborder-route-voice-") as folder:
                    file = Path(folder) / "input.wav"
                    file.write_bytes(audio)
                    result = subprocess.run([helper, str(file)], capture_output=True, check=True, timeout=8)
            except (OSError, subprocess.SubprocessError):
                self.send_error(503)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(result.stdout)))
            self.end_headers()
            self.wfile.write(result.stdout)

        def log_message(self, *args):
            pass

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper", required=True, type=Path)
    parser.add_argument("--port", default=18974, type=int)
    args = parser.parse_args()
    with HTTPServer(("127.0.0.1", args.port), handler_for(str(args.helper.resolve()))) as server:
        print(f"Local route speech: {server.server_port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
