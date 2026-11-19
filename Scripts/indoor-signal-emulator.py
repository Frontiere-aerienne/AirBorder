#!/usr/bin/env python3
# SUBSTANTIVE: Preserves the confirmed position when replaying a gate reassignment.
"""Independent localhost indoor-position signal emulator for simulator QA."""

from __future__ import annotations

import argparse
import heapq
import json
import math
import re
import subprocess
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import TCPServer


ROUTE_NODES = (
    ("t3-transfer-security", 0.10, 0.55, 3),
    ("t3-departures-center", 0.30, 0.55, 3),
    ("t3-elevator-north", 0.46, 0.72, 3),
    ("t3-gates-center", 0.65, 0.55, 4),
    ("gate-105", 0.87, 0.34, 4),
)
SAMPLES_PER_SEGMENT = 3

HND_QA_ANCHOR_LATITUDE = 35.549678
HND_QA_ANCHOR_LONGITUDE = 139.786958
HND_QA_EAST_WEST_EXTENT_METERS = 240.0
HND_QA_NORTH_SOUTH_EXTENT_METERS = 180.0
METERS_PER_LATITUDE_DEGREE = 111_320.0
HANEDA_WING_FRAME = {
    "id": "hnd-t3-3f-gate-wing",
    "sourceSizePixels": [2778, 1700],
    "cropPixels": [1740, 740, 1050, 420],
}


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def route_samples() -> list[dict[str, object]]:
    samples: list[dict[str, object]] = []
    for start, end in zip(ROUTE_NODES, ROUTE_NODES[1:]):
        start_id, start_x, start_y, start_level = start
        _, end_x, end_y, end_level = end
        heading = math.degrees(math.atan2(end_x - start_x, end_y - start_y))
        for sample_index in range(SAMPLES_PER_SEGMENT):
            progress = sample_index / SAMPLES_PER_SEGMENT
            samples.append(
                {
                    "point": {
                        "x": start_x + ((end_x - start_x) * progress),
                        "y": start_y + ((end_y - start_y) * progress),
                    },
                    "level": start_level if progress < 0.5 else end_level,
                    "floorConfirmed": start_level == end_level or progress < 0.5,
                    "matchedNodeID": start_id,
                    "headingDegrees": heading,
                    "source": "externalSignalReplay",
                }
            )
    final_id, final_x, final_y, final_level = ROUTE_NODES[-1]
    samples.append(
        {
            "point": {"x": final_x, "y": final_y},
            "level": final_level,
            "floorConfirmed": True,
            "matchedNodeID": final_id,
            "headingDegrees": samples[-1]["headingDegrees"],
            "source": "externalSignalReplay",
        }
    )
    return samples


def load_trace(path: Path) -> list[dict[str, object]]:
    trace = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(trace, dict) or type(trace.get("version")) is not int or trace["version"] != 1:
        raise ValueError("expected a version 1 indoor trace")
    samples = trace.get("samples")
    if not isinstance(samples, list) or not samples:
        raise ValueError("expected at least one position sample")
    frame = trace.get("coordinateFrame")
    if frame is not None and frame != HANEDA_WING_FRAME:
        raise ValueError("unrecognized floor-map coordinate frame")
    offsets = []
    readings = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise ValueError(f"sample {index} must be an object")
        offset, point = sample.get("offsetMs"), sample.get("point")
        level, confirmed = sample.get("level"), sample.get("floorConfirmed")
        landmark, heading = sample.get("matchedNodeID"), sample.get("headingDegrees")
        clearance = sample.get("clearanceConfirmed")
        if "checkpointEntered" in sample and type(sample["checkpointEntered"]) is not bool:
            raise ValueError(f"sample {index}: checkpoint entry must be a Boolean")
        if type(offset) is not int or (offset <= offsets[-1] if offsets else offset != 0):
            raise ValueError(f"sample {index}: offsets must start at zero and increase in integer milliseconds")
        if point is not None and (not isinstance(point, dict) or any(
            type(point.get(axis)) not in (int, float) or not 0 <= point[axis] <= 1 for axis in ("x", "y")
        )):
            raise ValueError(f"sample {index}: point must contain normalized x and y")
        if (level is not None and type(level) is not int) or type(confirmed) is not bool or (confirmed and level is None):
            raise ValueError(f"sample {index}: a confirmed floor requires an integer level")
        if landmark is not None and (not isinstance(landmark, str) or not landmark):
            raise ValueError(f"sample {index}: landmark ID must be a nonempty string or null")
        if heading is not None and (type(heading) not in (int, float) or not -360 <= heading <= 360):
            raise ValueError(f"sample {index}: heading must be between -360 and 360 degrees")
        if clearance is not None and type(clearance) is not bool:
            raise ValueError(f"sample {index}: clearance confirmation must be a Boolean")
        offsets.append(offset)
        # Emit the scripted observations and checkpoint status. Expected outcomes stay in the test.
        readings.append({"offsetMs": offset, "point": point, "level": level,
                         "floorConfirmed": confirmed, "matchedNodeID": landmark,
                         "headingDegrees": heading, "clearanceConfirmed": clearance,
                         "source": "externalSignalReplay"})
        if "checkpointEntered" in sample:
            readings[-1]["checkpointEntered"] = sample["checkpointEntered"]
        if frame is not None:
            readings[-1]["mapFrameID"] = frame["id"]
    if frame is not None:
        confirmed_reads = [reading for reading in readings if reading["floorConfirmed"] and reading["level"] == 3]
        for current, next_read in zip(confirmed_reads, confirmed_reads[1:]):
            a, b = current["point"], next_read["point"]
            if current["headingDegrees"] is None:
                current["headingDegrees"] = math.degrees(math.atan2((b["x"] - a["x"]) * 1050,
                                                                   (a["y"] - b["y"]) * 420))
        if len(confirmed_reads) > 1 and confirmed_reads[-1]["headingDegrees"] is None:
            confirmed_reads[-1]["headingDegrees"] = confirmed_reads[-2]["headingDegrees"]
    return readings


def core_location_coordinate(reading: dict[str, object]) -> tuple[float, float]:
    point = reading["point"]
    assert isinstance(point, dict)
    north_meters = (float(point["y"]) - 0.5) * HND_QA_NORTH_SOUTH_EXTENT_METERS
    east_meters = (float(point["x"]) - 0.5) * HND_QA_EAST_WEST_EXTENT_METERS
    latitude = HND_QA_ANCHOR_LATITUDE + north_meters / METERS_PER_LATITUDE_DEGREE
    longitude_scale = METERS_PER_LATITUDE_DEGREE * math.cos(math.radians(HND_QA_ANCHOR_LATITUDE))
    longitude = HND_QA_ANCHOR_LONGITUDE + east_meters / longitude_scale
    return latitude, longitude


class SignalPublisher:
    def __init__(self, transport: str, device: str, dry_run: bool) -> None:
        self.transport = transport
        self.device = device
        self.dry_run = dry_run
        self.delivery_count = 0
        self.last_error: str | None = None
        self.lock = threading.Lock()

    def publish(self, reading: dict[str, object]) -> None:
        if self.transport != "core-location":
            return
        latitude, longitude = core_location_coordinate(reading)
        command = [
            "xcrun", "simctl", "location", self.device, "set",
            f"{latitude:.8f},{longitude:.8f}",
        ]
        if self.dry_run:
            print(" ".join(command), flush=True)
            return
        try:
            subprocess.run(command, check=True, capture_output=True, text=True, timeout=5)
            with self.lock:
                self.delivery_count += 1
                self.last_error = None
        except (OSError, subprocess.SubprocessError) as error:
            with self.lock:
                self.last_error = str(error)

    def status(self) -> dict[str, object]:
        with self.lock:
            return {
                "transport": self.transport,
                "device": self.device if self.transport == "core-location" else None,
                "coreLocationDeliveries": self.delivery_count,
                "coreLocationLastError": self.last_error,
            }


class HanedaGateNetwork:
    """Connect the two published-map walks at their common main-concourse junction."""

    junction = (0.266667, 0.5)
    crowd_start = (0.12381, 0.5)
    crowd_end = (0.209524, 0.5)
    cafe_frame = "hnd-t3-3f-cafe-concourse"
    cafe_id = "t3-curacion-cafe"

    def __init__(self, walks: list[list[dict[str, object]]]) -> None:
        self.neighbours = {}
        self.gates = {}
        common = set()
        for walk in walks:
            points = [self.point(sample) for sample in walk if sample["floorConfirmed"] and sample["level"] == 3]
            if self.junction not in points:
                # The 105 trace skips over the junction. Insert it into that same straight leg.
                index = next(i for i, point in enumerate(points) if point[0] > self.junction[0])
                points.insert(index, self.junction)
            self.gates[walk[-1]["matchedNodeID"]] = points[-1]
            fork = points.index(self.junction)
            common.update(points[:fork + 1])
            self.connect(points[fork:])
        self.connect(sorted(common))
        # Use the width of the same published concourse. Occupancy in one strip
        # and the open bypass are controlled conditions, not airport reports.
        self.connect([self.crowd_start, (0.12381, 0.47), (0.12381, 0.44),
                      (0.166667, 0.44), (0.209524, 0.44), (0.209524, 0.47), self.crowd_end])
        self.frame = HANEDA_WING_FRAME["id"]
        self.pixel_scale = (1050, 420)

    def extend_to_cafe(self, first: dict[str, object]) -> list[dict[str, object]]:
        # Shop 116 is on Haneda's published 3F map. Walk positions are controlled image coordinates.
        def normalize(px: float, py: float) -> tuple[float, float]:
            return round((px - 690) / 2100, 7), round((py - 740) / 420, 7)

        def widen(point: tuple[float, float]) -> tuple[float, float]:
            return normalize(1740 + point[0] * 1050, 740 + point[1] * 420)

        edges = [(widen(a), widen(b)) for a in self.neighbours for b in self.neighbours[a] if a < b]
        self.neighbours.clear()
        self.gates = {name: widen(point) for name, point in self.gates.items()}
        self.crowd_start, self.crowd_end = widen(self.crowd_start), widen(self.crowd_end)
        self.frame = self.cafe_frame
        self.pixel_scale = (2100, 420)
        start = normalize(739, 950)
        cafe = normalize(833, 949)
        self.gates[self.cafe_id] = cafe
        main = [start, cafe, normalize(960, 939), normalize(1200, 950),
                normalize(1470, 947), normalize(1690, 949), widen(self.point(first))]
        edges.extend(zip(main, main[1:]))
        for a, b in edges:
            distance = math.hypot((b[0] - a[0]) * 2100, (b[1] - a[1]) * 420)
            count = max(1, math.ceil(distance / 18))
            # Each emitted intermediate position is a graph vertex, including reroute origins.
            points = [a]
            points.extend((round(a[0] + (b[0] - a[0]) * i / count, 7),
                           round(a[1] + (b[1] - a[1]) * i / count, 7)) for i in range(1, count))
            self.connect([*points, b])
        reading = dict(first, point={"x": start[0], "y": start[1]}, mapFrameID=self.frame)
        return self.path(reading, "t3-departure-gate-105")

    def connect(self, points: list[tuple[float, float]]) -> None:
        for a, b in zip(points, points[1:]):
            self.neighbours.setdefault(a, set()).add(b)
            self.neighbours.setdefault(b, set()).add(a)

    @staticmethod
    def point(sample: dict[str, object]) -> tuple[float, float]:
        point = sample["point"]
        return float(point["x"]), float(point["y"])

    def crosses_passage(self, a: tuple[float, float], b: tuple[float, float]) -> bool:
        low, high = sorted((a[0], b[0]))
        return a[1] == b[1] == self.crowd_start[1] and max(low, self.crowd_start[0]) < min(high, self.crowd_end[0])

    def uses_passage(self, samples: list[dict[str, object]], start: int = 0) -> bool:
        points = [self.point(sample) for sample in samples[start:] if sample["floorConfirmed"]]
        return any(self.crosses_passage(a, b) for a, b in zip(points, points[1:]))

    def path(self, current: dict[str, object], destination: str,
             avoid_crowd: bool = False, passage_blocked: bool = False) -> list[dict[str, object]] | None:
        if not current["floorConfirmed"] or current["level"] != 3:
            return None
        start = self.point(current)
        end = self.gates[destination]
        if start not in self.neighbours:
            return None
        # Compare lengths in source pixels so horizontal and vertical distances share units.
        parent = {start: None}
        cost = {start: 0.0}
        queue = [(0.0, start)]
        while queue:
            distance, node = heapq.heappop(queue)
            if distance != cost[node]:
                continue
            if node == end:
                break
            for neighbour in sorted(self.neighbours[node]):
                crosses_passage = self.crosses_passage(node, neighbour)
                if passage_blocked and crosses_passage:
                    continue
                dx = (neighbour[0] - node[0]) * self.pixel_scale[0]
                dy = (neighbour[1] - node[1]) * self.pixel_scale[1]
                candidate = distance + math.hypot(dx, dy)
                if avoid_crowd and crosses_passage:
                    candidate += 1000
                if candidate < cost.get(neighbour, math.inf):
                    cost[neighbour] = candidate
                    parent[neighbour] = node
                    heapq.heappush(queue, (candidate, neighbour))
        if end not in parent:
            return None
        route = [end]
        while parent[route[-1]] is not None:
            route.append(parent[route[-1]])
        route.reverse()
        samples = []
        offset = 0
        heading = current.get("headingDegrees") or 0
        for index, point in enumerate(route):
            if index + 1 < len(route):
                next_point = route[index + 1]
                dx = (next_point[0] - point[0]) * self.pixel_scale[0]
                dy = (next_point[1] - point[1]) * self.pixel_scale[1]
                heading = math.degrees(math.atan2(dx, -dy))
                # While crossing into the parallel aisle, look through the turn.
                # The lateral observation stays on the same graph edge.
                if (point[0] in (self.crowd_start[0], self.crowd_end[0])
                    and 0.44 < point[1] < self.crowd_start[1] and dy < 0
                    and index + 2 < len(route) and next_point[1] == 0.44):
                    along = route[index + 2][0] - point[0]
                    if along:
                        heading = math.copysign(45, along)
            if index == 0 and (self.frame == self.cafe_frame or avoid_crowd or passage_blocked) \
                    and current.get("headingDegrees") is not None:
                heading = current["headingDegrees"]
            samples.append(dict(current, point={"x": point[0], "y": point[1]}, headingDegrees=heading,
                                offsetMs=offset, matchedNodeID=destination if index == len(route) - 1
                                else "t3-departure-concourse"))
            if index + 1 < len(route):
                offset += max(100, round(math.hypot(dx, dy) * (14 if self.frame == self.cafe_frame else 10)))
        return samples


def pedestrian_poses(elapsed: float | None) -> list[dict[str, float | int]]:
    """Positions in authored gate-wing metres. These actors never enter the route graph."""
    seconds = elapsed or 0
    background = [
        {"id": 1, "x": 1.16, "z": -5.4 - 0.42 * seconds, "headingDegrees": 0,
         "stride": math.sin(7 * seconds) if elapsed is not None else 0},
        {"id": 2, "x": 2.35, "z": -9.5 + 0.31 * seconds, "headingDegrees": 180,
         "stride": math.sin(6 * seconds + 0.7) if elapsed is not None else 0},
    ]
    if elapsed is None or elapsed < 4.8:
        # At the junction the camera looks along -Z from x=0, z≈0.52. The crossing
        # at z=-0.74 sweeps across the entrance sightline near x=-0.64. It is
        # ahead of the camera but before the divider and well short of the barrier.
        background.append({"id": 0, "x": 1.32 - 0.62 * seconds, "z": -0.74, "headingDegrees": 90,
                           "stride": math.sin(8 * seconds) if elapsed is not None else 0})
    return background


def security_queue_report(long_queue: bool) -> dict[str, object]:
    # The extra wait is the driver's operational observation. Figure count is a
    # separate visual fixture, not an estimate of screening time.
    count = 12 if long_queue else 3
    people = [
        {"id": index, "x": 0.55 + 0.14 * (index % 3), "z": -10.75 + 0.80 * index,
         "headingDegrees": 0, "stride": 0}
        for index in range(count)
    ]
    return {"additionalWaitMinutes": 12 if long_queue else 0, "pedestrians": people}


def facility_queue_reports(long_queue: bool) -> list[dict[str, object]]:
    # Authored actor poses are meters in the scene, independent of the wait observation.
    reports = []
    for kind, count, wait in (("lounge", 8 if long_queue else 2, 8),
                               ("immigration", 12 if long_queue else 3, 18),
                               ("customs", 8 if long_queue else 2, 6)):
        people = []
        for index in range(count):
            if kind == "lounge":
                x, z, heading = 2.26 + 0.15 * (index % 2), -9.75 + 0.73 * index, 0
            elif kind == "immigration":
                x, z, heading = 0.85 + 1.52 * (index % 2), -12.4 + 1.17 * (index // 2), 0
            else:
                x, z, heading = 1.55 + 0.20 * (index % 2), -10.2 + 0.79 * index, 0
            people.append({"id": index, "x": x, "z": z, "headingDegrees": heading, "stride": 0})
        reports.append({"kind": kind, "additionalWaitMinutes": wait if long_queue else 0,
                        "pedestrians": people})
    return reports


class SignalState:
    def __init__(self, interval: float, paused: bool, loops: bool, publisher: SignalPublisher,
                 trace: list[dict[str, object]] | None = None,
                 network: HanedaGateNetwork | None = None, pedestrian_occlusion: bool = False,
                 security_queue: bool = False, facility_queues: bool = False) -> None:
        self.samples = trace if trace is not None else route_samples()
        self.network = network
        self.original_samples = self.samples
        self.route_revision = 0
        self.pedestrian_occlusion = pedestrian_occlusion
        self.pedestrians_started_at = None
        self.security_queue = security_queue
        self.facility_queues = facility_queues
        self.long_facility_queues = False
        self.long_security_queue = False
        self.crowd_reported_at = None
        self.passage_blocked = False
        self.closure = None
        self.prefers_quieter = False
        self.assigned_destination = self.samples[-1]["matchedNodeID"]
        self.cafe_pending = False
        self.landmark_token = None
        self.readings_available = True
        self.previous_reading = None
        self.replay_previous_reading = False
        self.full_shuttle = False
        self.lift_open = True
        self.interval = interval
        self.paused = paused
        self.loops = loops
        self.index = 0
        self.sequence = 0
        self.observed_at = iso_now()
        self.lock = threading.Condition()
        self.publisher = publisher

    def _reading(self) -> dict[str, object]:
        return dict(self.samples[self.index], observedAt=self.observed_at,
                    sequence=self.sequence, routeRevision=self.route_revision,
                    shuttleFull=self.full_shuttle, liftAvailable=self.lift_open)

    def reading(self) -> dict[str, object]:
        with self.lock:
            return self._reading()

    def served_reading(self) -> dict[str, object] | None:
        with self.lock:
            if not self.readings_available:
                return None
            if self.replay_previous_reading:
                return self.previous_reading
            if self.landmark_token is not None:
                # An erroneous match on the same floor must never advance either view.
                wrong = dict(self._reading(), point={"x": 0.76, "y": 0.54}, matchedNodeID="wrong-concourse",
                             landmarkToken=self.landmark_token)
                return wrong
            reading = self._reading()
            if self.security_queue:
                reading["securityQueue"] = security_queue_report(self.long_security_queue)
            if self.facility_queues:
                reading["facilityQueues"] = facility_queue_reports(self.long_facility_queues)
            return reading

    def status(self) -> dict[str, object]:
        with self.lock:
            status = {
                "paused": self.paused,
                "loops": self.loops,
                "sequence": self.sequence,
                "sampleIndex": self.index,
                "sampleCount": len(self.samples),
                "intervalSeconds": self.interval,
                "matchedNodeID": self.samples[self.index]["matchedNodeID"],
            }
        status.update(self.publisher.status())
        return status

    def map_path(self) -> dict[str, object] | None:
        with self.lock:
            frame = self.samples[0].get("mapFrameID")
            if frame is None:
                return None
            report = None
            junction = None
            if self.network:
                start, end = self.network.crowd_start, self.network.crowd_end
                junction = {"start": {"x": start[0], "y": start[1]}, "end": {"x": end[0], "y": end[1]}}
            if self.network and self.crowd_reported_at is not None:
                report = dict(junction, reportedAt=self.crowd_reported_at, delayMinutes=3)
            path = {
                "frameID": frame,
                "destination": self.assigned_destination,
                "revision": self.route_revision,
                "crowdReport": report,
                "junction": junction,
                "closure": self.closure,
                "prefersQuieter": self.prefers_quieter,
                "cafePending": self.cafe_pending,
                "points": [sample["point"] for sample in self.samples if sample["floorConfirmed"]
                           and sample["level"] == 3 and sample["point"] is not None],
            }

            if self.pedestrian_occlusion:
                elapsed = (None if self.pedestrians_started_at is None
                           else min(time.monotonic() - self.pedestrians_started_at, 4.8))
                path["pedestrians"] = pedestrian_poses(elapsed)
            return path

    def reassign(self, gate: str, prefers_quieter: bool, cafe_pending: bool = False) -> bool:
        with self.lock:
            destination = f"t3-departure-gate-{gate.lower()}"
            if not self.network or destination not in self.network.gates:
                return False
            if cafe_pending and self.network.frame != self.network.cafe_frame:
                return False
            # Keep the physical bypass selected while observations arrive, expire or clear.
            if (self.assigned_destination == destination and self.cafe_pending == cafe_pending
                and self.prefers_quieter == prefers_quieter):
                return True
            if not self.readings_available or self.replay_previous_reading:
                return False
            target = self.network.cafe_id if cafe_pending else destination
            current = self.samples[self.index]
            nominal = self.network.path(current, target, prefers_quieter)
            if nominal is None:
                return False
            needs_detour = self.passage_blocked and self.network.uses_passage(nominal)
            safe = self.network.path(current, target, prefers_quieter, passage_blocked=True) if needs_detour else nominal
            self.closure = ("detour" if safe else "unavailable") if needs_detour else None
            self.assigned_destination = destination
            self.cafe_pending = cafe_pending
            if not cafe_pending:
                self.landmark_token = None
            self.prefers_quieter = prefers_quieter
            self._replace_route(safe or nominal)
            return True

    def _replace_route(self, samples: list[dict[str, object]]) -> None:
        # All route changes publish a new revision while the clock holds the same position.
        self.previous_reading = self._reading()
        self.samples = samples
        self.index = 0
        self.route_revision += 1
        self.sequence += 1
        self.observed_at = iso_now()
        self.lock.notify_all()

    def _set_passage_block(self, blocked: bool) -> None:
        if blocked == self.passage_blocked:
            return
        self.passage_blocked = blocked
        if not blocked:
            self.closure = None
            self.lock.notify_all()
            return
        if not self.network.uses_passage(self.samples, self.index):
            return
        target = self.network.cafe_id if self.cafe_pending else self.assigned_destination
        safe = self.network.path(self.samples[self.index], target, self.prefers_quieter, passage_blocked=True)
        self.closure = "detour" if safe else "unavailable"
        if safe:
            self._replace_route(safe)

    def control(self, action: str) -> None:
        with self.lock:
            if action in {"facility-queue-normal", "facility-queue-long"} and self.facility_queues:
                self.long_facility_queues = action == "facility-queue-long"
                return
            if action in {"security-queue-normal", "security-queue-long"} and self.security_queue:
                self.long_security_queue = action == "security-queue-long"
                return
            if action in {"pedestrians-cross", "pedestrians-reset"} and self.pedestrian_occlusion:
                self.pedestrians_started_at = time.monotonic() if action == "pedestrians-cross" else None
                return
            if action in {"drop-reading", "stale-reading", "restore-reading"} and self.network:
                self.readings_available = action != "drop-reading"
                self.replay_previous_reading = action == "stale-reading"
                return
            if action in {"passage-blocked", "passage-open"} and self.network:
                self._set_passage_block(action == "passage-blocked")
                return
            if action in {"crowd-on", "crowd-off", "crowd-expire"} and self.network:
                if action == "crowd-expire":
                    if self.crowd_reported_at is None:
                        raise ValueError(action)
                    self.crowd_reported_at = time.time() - 6 * 60
                else:
                    self.crowd_reported_at = time.time() if action == "crowd-on" else None
                return
            self.previous_reading = self._reading()
            if action in {"full-shuttle", "shuttle-space"}:
                self.full_shuttle = action == "full-shuttle"
            elif action in {"lift-outage", "lift-open"}:
                self.lift_open = action == "lift-open"
            elif action == "pause":
                self.paused = True
            elif action == "resume":
                self.paused = False
            elif action == "reset":
                self.index = 0
                if self.samples is not self.original_samples:
                    self.samples = self.original_samples
                    self.route_revision += 1
                self.assigned_destination = self.samples[-1]["matchedNodeID"]
                self.cafe_pending = False
                self.landmark_token = None
                self.readings_available = True
                self.replay_previous_reading = False
                self.full_shuttle = False
                self.lift_open = True
                self.crowd_reported_at = None
                self.pedestrians_started_at = None
                self.long_security_queue = False
                self.long_facility_queues = False
                self.passage_blocked = False
                self.closure = None
                self.prefers_quieter = False
            elif (action == "misread-landmark" and self.network and self.cafe_pending
                  and self.samples[self.index]["matchedNodeID"] == self.network.cafe_id
                  and self.landmark_token is None):
                self.landmark_token = self.sequence + 1
            elif action == "next":
                self._move(1)
            elif action == "previous":
                self._move(-1)
            elif action in {"next-landmark", "previous-landmark"} and "offsetMs" in self.samples[self.index]:
                self._move_to_landmark(1 if action == "next-landmark" else -1)
            else:
                raise ValueError(action)
            self.sequence += 1
            self.observed_at = iso_now()
            reading = dict(self.samples[self.index])
            self.lock.notify_all()
        self.publisher.publish(reading)

    def confirm_landmark(self, token: int) -> bool:
        with self.lock:
            if token != self.landmark_token or not self.readings_available or self.replay_previous_reading:
                return False
            self.previous_reading = self._reading()
            self.landmark_token = None
            self.sequence += 1
            self.observed_at = iso_now()
            self.lock.notify_all()
            return True

    def tick(self) -> None:
        with self.lock:
            if self.paused:
                return
            self.previous_reading = self._reading()
            self._move(1)
            self.sequence += 1
            self.observed_at = iso_now()
            reading = dict(self.samples[self.index])
        self.publisher.publish(reading)

    def _can_advance(self) -> bool:
        if self.closure == "unavailable":
            return False
        landmark = self.samples[self.index]["matchedNodeID"]
        if self.full_shuttle and landmark in {"t3-shuttle-stop-0", "t2-shuttle-stop-9"}:
            return False
        return self.lift_open or landmark not in {"t3-elevator-north", "t2-public-lift",
                                                  "t2-deck-lift", "t3-departures-lift",
                                                  "t3-keikyu-platform-lift"}

    def _move(self, delta: int) -> None:
        if delta > 0 and not self._can_advance():
            return
        candidate = self.index + delta
        if self.loops:
            self.index = candidate % len(self.samples)
        else:
            self.index = max(0, min(len(self.samples) - 1, candidate))

    def _move_to_landmark(self, direction: int) -> None:
        # The route card seeks between confirmed landmarks. Raw controls and the replay
        # clock still emit every sample, including unconfirmed floors and in-between poses.
        if direction > 0 and not self._can_advance():
            return
        current = self.samples[self.index]
        limit = len(self.samples) if direction > 0 else -1
        for index in range(self.index + direction, limit, direction):
            candidate = self.samples[index]
            if (candidate["floorConfirmed"] and candidate.get("clearanceConfirmed") is not False
                and candidate["matchedNodeID"]
                and (candidate["matchedNodeID"], candidate["level"]) != (current["matchedNodeID"], current["level"])):
                self.index = index
                return


def handler_type(state: SignalState) -> type[BaseHTTPRequestHandler]:
    class SignalHandler(BaseHTTPRequestHandler):
        server_version = "AirportXRIndoorSignal/1.0"

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/reading":
                reading = state.served_reading()
                self._json(200, reading) if reading is not None else self._json(503, {"error": "no_reading"})
            elif self.path == "/map-path":
                path = state.map_path()
                self._json(200, path) if path is not None else self._json(404, {"error": "not_found"})
            elif self.path == "/status":
                self._json(200, state.status())
            else:
                self._json(404, {"error": "not_found"})

        def do_POST(self) -> None:  # noqa: N802
            prefix = "/control/"
            if not self.path.startswith(prefix):
                self._json(404, {"error": "not_found"})
                return
            action = self.path[len(prefix) :]
            gate_action = re.fullmatch(r"gate-(105|108a)(-quieter)?(-cafe)?", action)
            if gate_action is not None:
                changed = state.reassign(gate_action[1], gate_action[2] is not None, gate_action[3] is not None)
                self._json(200, state.status()) if changed else self._json(409, {"error": "route_unavailable"})
                return
            confirm = re.fullmatch(r"confirm-cafe-(\d{1,10})", action)
            if confirm is not None:
                if state.confirm_landmark(int(confirm[1])):
                    self._json(200, state.status())
                else:
                    self._json(409, {"error": "landmark_changed"})
                return
            try:
                state.control(action)
            except ValueError:
                self._json(400, {"error": "unknown_control"})
                return
            self._json(200, state.status())

        def _json(self, status: int, payload: dict[str, object]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format_string: str, *args: object) -> None:
            return

    return SignalHandler


def run_clock(state: SignalState, stop: threading.Event) -> None:
    while not stop.wait(state.interval):
        state.tick()


def run_trace_clock(state: SignalState, stop: threading.Event) -> None:
    # Manual stepping works even when paused. Resume schedules from the selected sample.
    with state.lock:
        while not stop.is_set():
            at_end = state.index == len(state.samples) - 1
            if state.paused or (at_end and not state.loops):
                state.lock.wait()
                continue
            delay = state.interval if at_end else (
                state.samples[state.index + 1]["offsetMs"] - state.samples[state.index]["offsetMs"]
            ) / 1000
            sequence = state.sequence
            changed = state.lock.wait_for(lambda: stop.is_set() or state.sequence != sequence, timeout=delay)
            if not changed:
                state.tick()


class LoopbackReplayServer(ThreadingHTTPServer):
    def server_bind(self) -> None:
        # HTTPServer normally resolves a host name during bind. The numeric
        # loopback endpoint needs no DNS, including on hosted simulator runners.
        TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Serve independent indoor QA signals through HTTP or Apple Simulator Core Location."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--interval", type=float, default=1.5)
    parser.add_argument("--paused", action="store_true")
    parser.add_argument("--no-loop", action="store_true")
    parser.add_argument("--transport", choices=("http", "core-location"), default="http")
    parser.add_argument("--device", default="booted")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--trace", type=Path, help="Replay a version 1 JSON indoor walk over HTTP")
    parser.add_argument("--haneda-gate-replanning", action="store_true",
                        help="Enable local gate reassignment across the connected Haneda walks")
    parser.add_argument("--haneda-cafe-walk", action="store_true",
                        help="Extend the Haneda walk west to the selected cafe on the same floor")
    parser.add_argument("--start-at-junction", action="store_true",
                        help="Start the adaptive Haneda gate walk facing east before the side passage")
    parser.add_argument("--pedestrian-occlusion", action="store_true",
                        help="Enable the independent three-pedestrian crossing at the Haneda junction")
    parser.add_argument("--security-queue", action="store_true",
                        help="Enable normal and long security queues on an indoor trace with a clearance checkpoint")
    parser.add_argument("--facility-queues", action="store_true",
                        help="Enable synthetic lounge, immigration, and customs queue observations")
    args = parser.parse_args()
    if args.facility_queues and not args.trace:
        parser.error("--facility-queues requires --trace")
    if args.security_queue and not args.trace:
        parser.error("--security-queue requires --trace")
    if args.pedestrian_occlusion and not args.start_at_junction:
        parser.error("--pedestrian-occlusion requires --start-at-junction")
    if args.host not in {"127.0.0.1", "localhost"}:
        parser.error("--host must remain on loopback")
    if not math.isfinite(args.interval) or args.interval <= 0:
        parser.error("--interval must be positive")
    if args.trace and (args.transport != "http" or args.dry_run):
        parser.error("--trace requires standalone HTTP replay")
    if args.start_at_junction and (not args.haneda_gate_replanning or args.haneda_cafe_walk):
        parser.error("--start-at-junction requires the adaptive gate walk")
    if args.transport == "core-location" and not (
        args.device == "booted" or re.fullmatch(r"[0-9A-Fa-f-]{36}", args.device)
    ):
        parser.error("--device must be 'booted' or a simulator UUID")

    try:
        if args.haneda_gate_replanning or args.haneda_cafe_walk:
            if args.transport != "http" or args.trace or args.dry_run:
                parser.error("Haneda gate replanning requires the HTTP driver and supplies its own traces")
            fixtures = Path(__file__).parent / "tests" / "fixtures"
            trace = load_trace(fixtures / "haneda-gate-105-walk.json")
            network = HanedaGateNetwork([trace, load_trace(fixtures / "haneda-gate-108a-walk.json")])
            if args.haneda_cafe_walk:
                trace = network.extend_to_cafe(trace[0])
            elif args.start_at_junction:
                x, y = network.crowd_start
                start = dict(trace[0], point={"x": x, "y": y}, headingDegrees=90)
                trace = network.path(start, "t3-departure-gate-105")
        else:
            trace = load_trace(args.trace) if args.trace else None
            network = None
            if args.security_queue and not (
                any(item["matchedNodeID"] == "t3-return-security" for item in trace)
                and any(item["matchedNodeID"] == "t3-after-security" and item.get("clearanceConfirmed") is True
                        for item in trace)
            ):
                raise ValueError("the security queue requires a checkpoint and a confirmed airside observation")
    except (OSError, ValueError) as error:
        parser.error(f"invalid indoor trace: {error}")
    publisher = SignalPublisher(args.transport, args.device, args.dry_run)
    state = SignalState(
        interval=args.interval,
        paused=args.paused,
        loops=not args.no_loop and not args.haneda_cafe_walk,
        publisher=publisher,
        trace=trace,
        network=network,
        pedestrian_occlusion=args.pedestrian_occlusion,
        security_queue=args.security_queue,
        facility_queues=args.facility_queues,
    )
    publisher.publish(state.reading())
    if args.dry_run:
        return
    stop = threading.Event()
    server = LoopbackReplayServer((args.host, args.port), handler_type(state))
    clock = threading.Thread(target=run_trace_clock if trace else run_clock, args=(state, stop), daemon=True)
    clock.start()
    print(f"Indoor signal emulator: http://{args.host}:{server.server_port}/reading", flush=True)
    print(f"App signal transport: {args.transport}", flush=True)
    print("Controls: POST /control/pause|resume|next|previous|reset", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        with state.lock:
            stop.set()
            state.lock.notify_all()
        server.server_close()


if __name__ == "__main__":
    main()
