#!/usr/bin/env python3
# PROCEDURAL: Serves independent synthetic airport assignments to the simulator.

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit


GATES = ("105", "108A")
HANEDA_FLOOR_IMAGE = "https://tokyo-haneda.com/site_resource/floor/img/floor__img_floor_map_t3_3f.png"
HANEDA_FLOOR_SIZE = (2778, 1700)
# Pixel centers of the printed gate circles on Haneda's published 3F image.
HANEDA_GATE_PIXELS = {"105": (2751, 870), "108A": (2004, 791)}
# The gate wing in source pixels. The right margin leaves room for the ring around Gate 105.
GATE_WING = (1740, 740, 1050, 420)


def map_document(heading, illustration=""):
    return f"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{heading} — Terminal map</title>
<style>
  body {{ margin: 0; background: #f3f8fa; color: #17364a; font: 1.08rem system-ui, sans-serif; }}
  main {{ max-width: 28rem; margin: auto; padding: 3rem 1.5rem; }}
  h1 {{ font-size: clamp(2rem, 10vw, 3rem); margin: .65rem 0 .35rem; }}
  p {{ color: #485e6e; }}
  .floor-map {{
      position: relative; margin: 1.5rem 0 0; overflow: hidden; background: white;
      border: 1px solid #cddfe6; border-radius: .65rem;
  }}
  .floor-map img {{ position: absolute; max-width: none; height: auto; }}
  .gate-ring {{
      position: absolute; width: 6%; aspect-ratio: 1;
      border: 3px solid #e4ac00; box-sizing: border-box; border-radius: 50%;
      transform: translate(-50%, -50%); pointer-events: none;
  }}
  .gates {{ display: flex; justify-content: space-between; padding: 0 1rem; margin-top: 4rem; }}
  .gate {{ font-weight: 700; background: #dbe3e7; padding: .55rem .9rem; border-radius: .65rem; }}
  .gate[aria-current="true"] {{ background: #ffd044; color: #142b38; }}
  .corridor {{ margin-top: 1rem; padding: 1rem; border-radius: .7rem; background: #cddfe6;
               display: grid; grid-template-columns: repeat(3, 1fr); gap: .55rem; }}
  .room {{ height: 2.3rem; background: #f3f8fa; }}
</style>
<main>
  <p>Terminal map</p>
  <h1>{heading}</h1>
  <p>Haneda · Terminal 3, 3F</p>
  {illustration}
</main>
</html>"""


def official_floor_map(gate):
    left, top, width, height = GATE_WING
    image_width, image_height = HANEDA_FLOOR_SIZE
    x, y = HANEDA_GATE_PIXELS[gate]
    # Crop in CSS and place the ring in the same coordinate system as the source image.
    return f"""<figure class="floor-map" style="aspect-ratio:{width}/{height}">
<img src="{HANEDA_FLOOR_IMAGE}" alt="Haneda Terminal 3 departure gates"
 data-gate-map width="{image_width}" height="{image_height}"
 style="width:{100 * image_width / width:.5f}%;left:{-100 * left / width:.5f}%;top:{-100 * top / height:.5f}%">
<span class="gate-ring" aria-hidden="true"
 style="left:{100 * (x - left) / width:.5f}%;top:{100 * (y - top) / height:.5f}%"></span>
</figure>"""


def gate_illustration(selected):
    badges = "".join(
        f'<span class="gate" aria-current="{str(gate == selected).lower()}">{gate}</span>'
        for gate in reversed(GATES)
    )
    return f"""<div class="gates" aria-label="Gate markers">{badges}</div>
<div class="corridor" aria-hidden="true"><i class="room"></i><i class="room"></i><i class="room"></i></div>"""


def make_handler(offline_map=False, clock=time.time):
    # HTTPServer serializes requests so a control update publishes one coherent snapshot.
    assignment = {
        "source": "syntheticAirportProvider",
        "flight": "NH 106",
        "date": "2026-10-15",
        "airport": "HND",
        "terminal": "3",
        "gate": "105",
        "revision": 0,
        "mapAvailable": True,
    }
    available = True
    network_available = True
    replayed_assignment = None
    previous_assignment = None
    saved_planning = None
    replayed_planning = None
    planning_revision = 0
    lounges_available = True
    security_minutes = 9
    cafe_minutes = 8
    crowd_level = "moderate"
    flight_status = "onSchedule"
    gate_checked_at = security_checked_at = cafe_checked_at = crowd_checked_at = flights_checked_at = clock()
    status_checked_at = gate_checked_at

    def planning_snapshot():
        gate = assignment["gate"]
        lounge_walks = {"105": (4, 8), "108A": (8, 5)}
        ana_walk, sky_walk = lounge_walks[gate]
        return {
            "source": assignment["source"],
            "flight": assignment["flight"],
            "date": assignment["date"],
            "airport": assignment["airport"],
            "terminal": assignment["terminal"],
            "gate": gate,
            "assignmentRevision": assignment["revision"],
            "revision": planning_revision,
            "gateCheckedAt": gate_checked_at,
            "security": {"minutes": security_minutes, "observedAt": security_checked_at},
            "cafe": {"minutes": cafe_minutes, "observedAt": cafe_checked_at},
            "crowd": {"level": crowd_level, "observedAt": crowd_checked_at},
            "status": {"value": flight_status, "observedAt": status_checked_at},
            "flightsCheckedAt": flights_checked_at,
            "flights": [
                {"id": "morning", "from": "HND", "to": "LAX", "dayOffset": 1, "departureMinute": 710},
                {"id": "evening", "from": "HND", "to": "LAX", "dayOffset": 1, "departureMinute": 1050},
            ],
            "lounges": ([
                {"place": "anaLounge", "walkMinutes": ana_walk, "access": "businessClass"},
                {"place": "skyLounge", "walkMinutes": sky_walk, "access": "paidEntry"},
            ] if lounges_available else []),
            "airports": [
                {"code": "SIN", "name": "Singapore Changi", "city": "Singapore", "terminals": ["1", "2", "3", "4"]},
            ],
        }

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if not network_available:
                self.send_json(503, {"error": "network_unavailable"})
                return
            if self.path == "/v1/assignment":
                if available:
                    self.send_json(200, replayed_assignment or assignment)
                else:
                    self.send_json(503, {"error": "provider_unavailable"})
                return
            if self.path == "/v1/planning":
                if available:
                    self.send_json(200, replayed_planning if replayed_planning is not None else planning_snapshot())
                else:
                    self.send_json(503, {"error": "provider_unavailable"})
                return
            target = urlsplit(self.path)
            for gate in GATES:
                if target.path != f"/map/HND/3/{gate}":
                    continue
                if not available or not assignment["mapAvailable"]:
                    self.send_html(503, map_document("Gate map unavailable"))
                elif gate != assignment["gate"] or parse_qs(target.query) != {"rev": [str(assignment["revision"])]}:
                    self.send_html(409, map_document("Gate assignment changed"))
                else:
                    map_content = gate_illustration(gate) if offline_map else official_floor_map(gate)
                    self.send_html(200, map_document(f"Gate {gate}", map_content))
                return
            self.send_json(404, {"error": "not_found"})

        def do_POST(self):
            nonlocal available, network_available, previous_assignment, replayed_assignment
            nonlocal saved_planning, replayed_planning
            nonlocal planning_revision, security_minutes, cafe_minutes, crowd_level, lounges_available
            nonlocal flight_status, status_checked_at
            nonlocal gate_checked_at, security_checked_at, cafe_checked_at, crowd_checked_at, flights_checked_at
            actions = {
                "/control/map-on": ("mapAvailable", True),
                "/control/map-off": ("mapAvailable", False),
            }
            actions.update({f"/control/gate/{gate}": ("gate", gate) for gate in GATES})
            if self.path in actions:
                field, value = actions[self.path]
                if assignment[field] != value:
                    previous_assignment = assignment.copy()
                    assignment[field] = value
                    assignment["revision"] += 1
                    planning_revision += 1
                    if field == "gate":
                        gate_checked_at = clock()
            elif self.path == "/control/stale-gate" and previous_assignment is not None:
                replayed_assignment = previous_assignment
            elif self.path == "/control/conflicting-gate":
                other_gate = next(gate for gate in GATES if gate != assignment["gate"])
                replayed_assignment = dict(assignment, gate=other_gate)
            elif self.path == "/control/wrong-flight-gate":
                other_gate = next(gate for gate in GATES if gate != assignment["gate"])
                replayed_assignment = dict(assignment, flight="NH 999", gate=other_gate,
                                           revision=assignment["revision"] + 1)
            elif self.path == "/control/current-gate":
                replayed_assignment = None
            elif self.path == "/control/feed-off":
                available = False
            elif self.path == "/control/feed-on":
                available = True
            elif self.path == "/control/network-off":
                network_available = False
            elif self.path == "/control/network-on":
                network_available = True
            elif self.path in ("/control/planning-lounges-unavailable", "/control/planning-lounges-restore"):
                lounges_available = self.path.endswith("restore")
                planning_revision += 1
            elif self.path == "/control/planning-save":
                # The saved snapshot is immutable while current observations continue advancing.
                saved_planning = planning_snapshot()
            elif self.path == "/control/planning-replay-saved" and saved_planning is not None:
                replayed_planning = saved_planning
            elif self.path == "/control/planning-mismatched-assignment":
                replayed_planning = dict(planning_snapshot(), assignmentRevision=assignment["revision"] + 1)
            elif self.path == "/control/planning-current":
                replayed_planning = None
            elif self.path in {f"/control/planning-{action}-{feed}"
                               for action in ("expire", "refresh")
                               for feed in ("gate", "security", "cafe", "crowd", "status", "flights")}:
                action, feed = self.path.rsplit("/", 1)[1].removeprefix("planning-").split("-", 1)
                observed = clock() - 31 * 60 if action == "expire" else clock()
                if feed == "gate":
                    gate_checked_at = observed
                elif feed == "security":
                    security_checked_at = observed
                elif feed == "cafe":
                    cafe_checked_at = observed
                elif feed == "crowd":
                    crowd_checked_at = observed
                elif feed == "status":
                    status_checked_at = observed
                else:
                    flights_checked_at = observed
                planning_revision += 1
            elif self.path == "/control/planning-refresh":
                gate_checked_at = security_checked_at = cafe_checked_at = crowd_checked_at = flights_checked_at = clock()
                status_checked_at = gate_checked_at
                planning_revision += 1
            elif self.path in ("/control/planning-flight-delayed", "/control/planning-flight-on-time"):
                flight_status = "delayed" if self.path.endswith("delayed") else "onSchedule"
                status_checked_at = clock()
                planning_revision += 1
            elif self.path == "/control/planning-age-security":
                security_checked_at = clock() - 4 * 60
                planning_revision += 1
            elif self.path.startswith("/control/planning-cafe-wait/"):
                value = self.path.rsplit("/", 1)[1]
                if not (value.isascii() and value.isdecimal() and len(value) <= 3 and int(value) <= 180):
                    self.send_json(400, {"error": "invalid_cafe_wait"})
                    return
                cafe_minutes = int(value)
                cafe_checked_at = clock()
                planning_revision += 1
            elif self.path == "/control/planning-busy":
                cafe_minutes = 28
                security_minutes = 22
                crowd_level = "busy"
                security_checked_at = cafe_checked_at = crowd_checked_at = clock()
                planning_revision += 1
            elif self.path == "/control/planning-clear":
                cafe_minutes = 8
                security_minutes = 9
                crowd_level = "moderate"
                security_checked_at = cafe_checked_at = crowd_checked_at = clock()
                planning_revision += 1
            else:
                self.send_json(404, {"error": "not_found"})
                return
            self.send_json(200, assignment)

        def send_json(self, status, payload):
            self.send_content(status, "application/json", json.dumps(payload, separators=(",", ":")))

        def send_html(self, status, body):
            self.send_content(status, "text/html; charset=utf-8", body)

        def send_content(self, status, content_type, text):
            body = text.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--offline-map", action="store_true", help="Use the local diagram for tests without internet.")
    args = parser.parse_args()
    with HTTPServer(("127.0.0.1", args.port), make_handler(offline_map=args.offline_map)) as server:
        print(f"Airport provider replay: http://127.0.0.1:{server.server_port}/v1/assignment", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
