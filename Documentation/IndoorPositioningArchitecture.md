# Indoor positioning and AR test architecture

Updated: 2026-11-16

## Exact-gate handoff in the iPhone simulator

AirBorder's native Map and Camera provide the route guidance. The gate-map handoff addresses a separate peer request. It displays a focused view of Haneda's published terminal map in an in-app browser, with a ring around the assigned gate. Done returns to the selected route and step. The simulator supplies the NH 106 gate assignment through a loopback driver. The original floor image loads directly from Haneda, and the ring uses the location of the printed gate circle in the published image. The map request carries no flight or passenger details to Haneda. This reference shows where the gate is on the map. Live flight assignments and surveyed indoor routes need separate data sources.

Run `python3 Scripts/airport-provider-driver.py --port 0` and note the port printed at startup. Launch the Debug iPhone simulator build with `--uitesting --qa-airport-provider http://127.0.0.1:<port>/v1/assignment -resetState -skipOnboarding -gateUpdate off`. In Route, tap the schematic, then open the gate map from the sheet. A standard launch uses the existing terminal floor guide. With the test provider, POST to `/control/gate/108A` to send a new assignment or `/control/map-off` to test the fallback. Use the driver flag `--offline-map` for an isolated UI test with the local diagram. If the official image fails to load or its dimensions change, the map closes and native guidance remains available.

The focused UI case is `AirportXRCompanionUITests/AirBorderUITests/testAirportProviderGateMapHandoffAndRouteContinuity`. Set `TEST_RUNNER_AIRPORT_PROVIDER_PORT` to the port when running it through `xcodebuild test`. Set `TEST_RUNNER_AIRPORT_PROVIDER_OFFICIAL_MAP=1` when checking the online view. The case verifies exact gate labels in the in-app browser, the same Step-free route step on return, the native fallback when the map is unavailable, and the new destination after a gate change. Check the overlaid gate rings visually when the source map changes, including updates that preserve the image dimensions.

### Published airport facts and dynamic inputs

The [official Terminal 3 3F map](https://tokyo-haneda.com/text/floor/terminal3/3rd_floor.html) and its [airport-hosted image](https://tokyo-haneda.com/site_resource/floor/img/floor__img_floor_map_t3_3f.png) show the actual 105 and 108A gate markers on the same concourse, with 108A between the 109 and 107 gate areas and 105 at the end of that wing. They also show terminal lift and moving-walkway locations. Map positions describe landmarks. Door permissions, walking durations, and live elevator availability need additional evidence.

The [airport's shuttle guide](https://tokyo-haneda.com/en/access/travel_between_terminals/index.html) confirms the 1F shuttle Stops 0 at T3 and 9 at T2. The [T2 observation deck](https://tokyo-haneda.com/en/service/facilities/observation_deck.html?tab=terminal2) is on 5F with published outdoor hours of 06:30--22:00 and possible weather or security closures. The [airport coach guide](https://tokyo-haneda.com/en/access/bus/index.html?tab=terminal3) lists the Narita coach at T3 Stop 5 and an approximate journey time of 75 minutes. [Curacion Cafe](https://tokyo-haneda.com/en/shop_and_dine/detail/tenant_00006.html) is on T3 3F after security. The simulator supplies the individual flight assignment, queue observations, missed or full vehicles, gate changes, and passenger location. The test clock and route estimates are controlled inputs.

### Walking the published gate concourse

The native Route card can display the same published image during a controlled direct walk toward 105 or 108A. The driver offers a planned path at `/map-path` and a position at `/reading`. The paths trace the visible airside concourse, and the timed coordinates are synthetic. Positions are normalized within the map crop, whose origin is (1740, 740) with width 1050 and height 420 in the 2778-by-1700 source image. The app checks the exact image revision before drawing the route. An invalid floor or missing reading holds the last accepted marker and prevents advancing. The traveled line is solid, the remaining line is dotted, and the gate keeps a yellow ring. Next and Back move the driver by one reading. Automatic playback uses the trace's clock.

For the Gate 105 walk, start the driver, then run the app with the displayed port. Open Route and resume the driver clock. Use the loopback controls to inspect individual readings during testing.

```bash
python3 Scripts/indoor-signal-emulator.py --trace Scripts/tests/fixtures/haneda-gate-105-walk.json --paused --no-loop
xcrun simctl launch --terminate-running-process booted com.example.AirportXRCompanion \
  --uitesting --qa-indoor-feed http://127.0.0.1:8765/reading --qa-official-walk 105 \
  -resetState -skipOnboarding -gateUpdate off
curl -fsS -X POST http://127.0.0.1:8765/control/resume
```

For 108A, use `haneda-gate-108a-walk.json` and `--qa-official-walk 108A`. Supply Gate 108A from the airport driver using `--qa-airport-provider`. The official walk is available for the matching gate, direct route and itinerary. Alternate routes use the existing renderer. These traces support checking the interaction in the simulator. They supply neither a surveyed route graph nor a live position, distance or ETA.

## Driver-led Map and Camera guidance

With an explicit loopback position feed in a Debug Simulator launch, Camera renders the RealityKit scene and Map presents guidance from the same accepted reading. The original Gate 105 trace renders an illustrative 3F lift landing and 4F corridor. In the gate wing, Map also moves the position marker along the airport floor plan. Both views show the current instruction. Unconfirmed readings preserve the last accepted floor and pose. The two Haneda traces below add terminal transfers and accept a heading with each position.

```bash
# Terminal 1: load the file and wait at the first reading
python3 Scripts/indoor-signal-emulator.py --trace Scripts/tests/fixtures/wrong-floor-lift.json --paused --no-loop

# Terminal 2: launch the simulator, then choose Route → Camera
SIMULATOR_NAME='AirBorder flight timeline' ./Scripts/run-simulator.sh ar-external

# Start timed playback once Camera is open
curl -X POST http://127.0.0.1:8765/control/resume
```

The file's millisecond offsets determine timed playback. The loopback controls seek between confirmed landmarks or expose each recorded observation, including the premature 4F reading. The traveler interface advances as validated observations arrive. Run `SIMULATOR_UDID=<installed-simulator-id> ./Scripts/run-terminal-replay-ui-tests.sh` for the driver-backed UI regression. Real venue alignment and live floor accuracy require independent field data.

### Simulator input and operator regression suite

The simulator suite starts independent drivers for the gate map, airport updates and indoor routes. The airport provider can replay an older assignment, a conflicting assignment and an update for the wrong flight. It can vary each observation's age, remove lounge availability, expire the flight list and simulate provider or network outages. The exact-gate handoff uses a loopback map so the test can exercise unavailable and changed-assignment responses. The airport floor-map walkthrough still uses the published map.

The runner renders test ticket and sign images locally. Debug simulator capture substitutes those images for sensor frames and passes them to Vision, then uses the normal app review and retry paths. A supplied local speech helper and WAV enable the route voice test through macOS dictation. Set `AIRBORDER_LOCAL_SPEECH_HELPER` and `AIRBORDER_LOCAL_SPEECH_FIXTURE` to their absolute paths before starting the runner. Camera sensor operation, microphone acoustics, physical indoor accuracy and spoken VoiceOver interaction require device evidence.

### Haneda Terminal 3 and Terminal 2

The observation-deck trace starts in T3 public arrivals, goes to shuttle Stop 0, passes T1 aboard the bus, and takes the T2 lift from 1F to the public 5F deck. The return takes the T2 lift back down to Stop 9, then uses the T3 lift from 1F to the 3F security checkpoint before reaching Gate 105. The Narita trace starts in the same public arrivals scene after arrival formalities and follows the exit to the fixture's Stop 5. It ends at the landside coach curb. The two traces are separate itineraries.

Start the relevant driver in one terminal. Launch the existing Debug Simulator app in another, then choose **Route → Camera**. The deck option sets `TERMINAL_REPLAY_ROUTE=observation-deck`; the airport change uses `TERMINAL_REPLAY_ROUTE=narita` and opens the NH 6 itinerary.

```bash
# Driver for the deck detour. Use haneda-narita-bus.json for the Narita trace.
python3 Scripts/indoor-signal-emulator.py --trace Scripts/tests/fixtures/haneda-observation-deck.json --paused --no-loop

# Use the name of an installed simulator.
SIMULATOR_NAME='AirBorder flight timeline' TERMINAL_REPLAY_ROUTE=observation-deck ./Scripts/run-simulator.sh ar-external

# After opening Camera, play the timed samples through the scene.
curl -fsS -X POST http://127.0.0.1:8765/control/resume
```

The route maps normalized position and heading to a local camera transform and interpolates within a scene. During a shuttle segment, the cabin moves with the camera and the road and terminal exteriors remain fixed. The alert and badge hold the last accepted scene when a floor is unconfirmed. The requested secure scene stays blocked until a separate clearance observation is confirmed. The test harness can seek per landmark with the loopback commands. The trace demonstrates the interaction and uses compressed route geometry and time.

### Haneda to Narita by rail

The optional rail replay opens the same NH 6 airport-change trip and shows the route from T3 public arrivals to the Keikyu ticket-gate approach and platform. The platform, train, and destination display stay fixed as the driver supplies walking positions. The final sample changes heading at the same position to reveal the destination display. The trace stops at the platform with the traveler on the landside of the airport. It models the approach and train identification. The coach replay remains available separately as `narita`, and the ordinary transfer itinerary continues to show the existing coach plan.

```bash
python3 Scripts/indoor-signal-emulator.py --trace Scripts/tests/fixtures/haneda-narita-rail.json --paused --no-loop
SIMULATOR_NAME='AirBorder flight timeline' TERMINAL_REPLAY_ROUTE=narita-rail ./Scripts/run-simulator.sh ar-external
# Open Route → Camera before resuming the driver.
curl -fsS -X POST http://127.0.0.1:8765/control/resume
```

The rail scene follows [Keikyu's terminal-to-station directions](https://www.haneda-tokyo-access.com/en/haneda-airport/to-stationl.html) and uses [photos of the T3 platform](https://commons.wikimedia.org/wiki/Category:Platforms_of_Haneda_Airport_Terminal_3_Station_%28Keiky%C5%AB%29) as references. The platform geometry and bilingual train display are illustrative. The display conveys the scripted destination and the trace does not represent a current departure, platform assignment, or ride to Narita.

The bundled replay assets are documented here for reuse and attribution:

- `ReplayHanedaT2.usdz` and `ReplayHanedaT3.usdz` contain adapted building geometry from [Project PLATEAU, MLIT Japan / Ōta Ward, 2025 LOD2](https://api.plateauview.mlit.go.jp/datacatalog/3dtiles/13111-bldg-lod2-latest/tileset.json). The terminal-area features are `bldg_85660669-ad73-413e-b750-b1c28309955a` and `bldg_96c5aebd-2cb5-40e5-8cb3-55fcc563a6ed`, respectively. Their geometry was extracted, re-centered, compressed for the staged ride, and recolored. See [MLIT's open-data terms](https://www.mlit.go.jp/plateau/faq/).
- `ReplayShuttle.usdz` and `ReplayCoach.usdz` adapt the [CC0 bus mesh by ajanhallinta](https://opengameart.org/content/3d-bus). Their dimensions, materials and visible silhouettes differ. Neither is a fleet-specific vehicle scan.
- `ReplayTerrazzo.jpg` is a downsampled and color-adjusted [Poly Haven terrazzo tiles texture](https://polyhaven.com/a/terrazzo_tiles), distributed under CC0.
- `ReplayRailCar.usdz` and `ReplayRailTrack.usdz` adapt the [commuter driving car](https://3dassets.dev/assets/modern-rail-and-metro-network-commuter-emu-driving-car-8934b654) and [6 m slab track](https://3dassets.dev/assets/modern-rail-and-metro-network-slab-track-straight-6m-0b78f8fd) from 3DAssets.dev, both CC0. The GLB meshes were converted to USDZ and the car's colors were adapted. Platform barriers, tactile strip, station columns and wayfinding display use original meshes and the existing terrazzo material.
- Walkable interiors use original geometry grounded in the [T3 floor guide](https://tokyo-haneda.com/text/floor/terminal3/3rd_floor.html), [T2 floor guide](https://tokyo-haneda.com/site_resource/floor/pdf/floor__pdf_floor_map_t2_en.pdf), and [shuttle guide](https://tokyo-haneda.com/en/access/travel_between_terminals/index.html). Published stop identifiers give the replay its geography. Route distances, driver signals and checkpoint state come from the scripted scenario.

## Shared Haneda gate walk and local voice

Launch the iPhone simulator with the existing airport assignment driver and the indoor driver in `--haneda-gate-replanning` mode. Use `--qa-official-walk adaptive` with the indoor feed. The Haneda floor image is the verified published revision. The graph uses two traced routes joined at their shared concourse. The driver emits a new route revision from the last confirmed point following a gate change. Map and Camera use the same accepted position, heading and current instruction. Camera renders the moving 3D view for this driver. The 3D hall illustrates the position with authored geometry.

Driver controls include `/control/crowd-on`, `/control/stale-reading`, and `/control/drop-reading` on the adaptive indoor feed. A scripted crowd report exposes a quieter strip of the concourse. The same-floor Direct and Step-free choices share the route when the graph supplies only one suitable path. On the separate terminal transfer trace, `/control/full-shuttle` and `/control/lift-outage` hold the relevant boarding or lift step. `shuttle-space` and `lift-open` restore it. These controlled conditions establish the app response to interruptions. Terminal geometry, capacity and live accessibility still require operator validation.

The crowd report contains a strip on the same floor, its observation time and a three-minute estimate. Map and Camera show the estimate if a remaining walking edge overlaps the strip. The map highlights the overlap. After the traveler clears the strip, the route has no remaining crowd delay. After five minutes, a report still on the route shows the current delay as unknown. `POST /control/crowd-expire` generates that state and `POST /control/crowd-off` clears it. The selected bypass keeps the same path and position when the report changes. The estimate describes the controlled concourse event.

### Blocked passage at the junction

Start the adaptive driver with `--haneda-gate-replanning --start-at-junction --paused --no-loop`. The first observation places the traveler at the west junction facing east. `POST /control/passage-blocked` excludes the closed horizontal edges from the route calculation and starts the replacement path at the current coordinate and heading. Map draws the detour around a closure marker and Camera shows the same turn from the shared heading and next edge. The already-selected bypass keeps its route revision, position and instruction. If no route is available, the driver holds the traveler at the last location and the app directs them to airport staff. `POST /control/passage-open` clears the closure. This exercise uses controlled route geometry and spacing from the published map image.

The gate-wing Camera scene places an open aisle beside the main concourse, with gaps at both ends of the divider and a barrier for the affected route. The scene projection widens and lengthens that short section so the split is visible from eye level. Map retains the original coordinates. Intermediate heading and position readings carry the viewpoint through the turn and then along the aisle.

### Facility queues and checkpoint guidance

The simulator uses authored lounge, departure security and international arrivals traces. Controls switch between normal and long queues. The driver supplies an additional wait separately from the number and positions of rendered people. Route guidance shows a report only for the current facility or the upcoming security checkpoint. Advancing past the facility removes its warning even if the report remains available.

The lounge scene shows its entrance, a waiting line on one side and a clear walking aisle. Security, immigration and staffed customs use a distant view in Map on approach. The operating system's camera does not supply these views. On entry, Map shows the procedure steps and the model holds the current step until the driver confirms clearance. The customs overview depicts separate electronic and staffed lanes. The itinerary controls the reported wait, and the app does not determine a traveler's eligibility for a lane. After clearance, Camera is available again by selection.

`Scripts/run-terminal-replay-ui-tests.sh` starts the loopback drivers and runs the phone tests. `--security-queue` enables the departure report with `security-queue-normal` and `security-queue-long` controls. `--facility-queues` enables lounge, immigration and customs reports with `facility-queue-normal` and `facility-queue-long`. The trace's `checkpointEntered` observation ends the distant view.

### Continuous walk through Curacion Cafe

Start the local indoor driver with `--haneda-cafe-walk --paused` and launch the Debug Simulator app with the airport provider enabled and `--qa-official-walk cafe`. Add Curacion Cafe as the route's only selected stop, open Route, and resume the driver. The panning map and first-person scene use the same accepted coordinates. The driver sends intermediate positions along the corridor and holds at the café entrance. Finish and Skip both let the current walk continue from there. The saved plan retains the visit.

The wider map uses the same hash-checked Haneda image. The café checkpoint is at shop 116, listed in the [airport directory](https://tokyo-haneda.com/en/shop_and_dine/detail/tenant_00006.html) and [Terminal 3 floor guide](https://tokyo-haneda.com/site_resource/floor/pdf/floor__pdf_floor_map_t3_en.pdf). The driver interpolates a controlled walk through that image and the 3D scene uses authored geometry. Other stops and multi-stop walks use the established route flow.

At the café, `POST /control/misread-landmark` injects a conflicting position on 3F. The app holds the last confirmed position and offers confirmation of the café entrance in either view. The driver accepts confirmation only for the current challenge and the app waits for its next valid reading. Later, a gate reassignment starts a new route from the same coordinate and heading. Local validation can pause the clock at that instant to compare both modes before the traveler follows the new direction.

On an iPhone with local English speech recognition, **Talk** uses Apple Speech for transcription and on-device speech synthesis for replies. AirBorder answers from the current journey and keeps the controls read-only. The supported questions are the current gate and the next instruction, including short follow-ups such as “What about now?” and “Repeat that”. Apple Voice Control is available independently for tapping and navigating named controls.

The simulator runtime could not load its own local speech recognizer. For the simulator, run this bridge on the same Mac using macOS 26 or later and its installed English dictation model:

```bash
helper="$(mktemp -d -t airborder-voice)/dictation"
xcrun swiftc -O -parse-as-library Scripts/local-route-speech.swift -o "$helper"
"$helper" --prepare
python3 Scripts/local-route-speech.py --helper "$helper" --port 18974
```

Launch the installed Debug simulator app with `--uitesting --qa-route-speech-port 18974`, open **Route**, and tap **Talk**. The first macOS setup can fetch Apple's speech assets. During use, microphone audio from Simulator is processed on the same Mac over loopback, and the recorder removes its temporary audio after each turn. Simulator support is excluded from device and Release builds.

## Earlier indoor prototypes

The `ar-preview` and `walkthrough` terminal modes use `TerminalRouteLocationEmulator` inside the app process. It generates a sequence of local `(x, y, level)` readings along the selected terminal graph, matches each reading to a named landmark, and feeds those readings into the same maneuver builder used by AR Guide. This is controlled indoor route replay, not GPS and not a claim that the simulator knows where a traveler is.

The independent option is `Scripts/indoor-signal-emulator.py`. It runs as a separate process and advances or pauses its own clock. In `http` transport, `ar-external` polls its loopback reading. In `core-location` transport, the process calls `simctl location set`; Apple Simulator then delivers the coordinate to the app through `CLLocationManager`, while loopback HTTP is used only for pause, resume, step, reset, and status controls. Both paths require an explicit UI-test launch.

```bash
python3 Scripts/indoor-signal-emulator.py
./Scripts/run-simulator.sh ar-external
```

To test Apple location delivery instead of app polling, boot the target simulator and run:

```bash
# Terminal 1
python3 Scripts/indoor-signal-emulator.py --transport core-location --device booted

# Terminal 2
./Scripts/run-simulator.sh ar-corelocation
```

`HNDCoreLocationQAFixture` projects the named test graph onto a small, versioned WGS84 footprint around the HND reference coordinate. The app reverses that projection and snaps only within the fixture's named distance limit. The floor comes from the matched test-graph node because Simulator latitude/longitude does not provide a reliable indoor `CLFloor`. These coordinates must not be treated as surveyed terminal geometry.

On a physical iPhone, ARKit supplies camera-relative motion and surface tracking. The current arrow remains camera-relative until a venue-quality position and coordinate transform are available. Apple documents that ARKit is unavailable in iOS Simulator, so simulator validation covers route progression and interface behavior, not camera tracking.

## Researched options

| Method | What it can test or provide | Airport limitation | Recommended role |
|---|---|---|---|
| Graph-route emulator | Repeatable `(x, y, level, heading)` readings, elevators, route changes, replay seeds, UI automation; may run in-app or as an independent localhost process | Synthetic unless backed by surveyed venue data | Required CI, simulator walkthrough, and parallel signal testing |
| `simctl location`, Xcode GPX, or `XCUILocation` | Latitude/longitude replay through Apple's Core Location delivery | Coordinates alone do not resolve a concourse, floor, or corridor | Test outdoor airport movement directly; test indoor UI only with an explicit synthetic or surveyed venue transform |
| IMDF plus venue indoor positioning | Venue-owned floors, units, openings, POIs, and a coordinate system suitable for indoor maps | Requires airport/property-owner data and deployment participation | Preferred production map/location foundation |
| iBeacon | Coarse proximity to deployed Bluetooth beacons | Apple says beacon ranging is proximity, not precise distance; RF attenuation and venue calibration matter | Landmark confirmation and zone/floor hints |
| UWB / Nearby Interaction | Precise relative distance and direction to a partnered device/accessory | Requires compatible hardware, permission, deployed accessories, and foreground sessions | High-precision confirmation near gates or decision points |
| Visual relocalization / saved `ARWorldMap` | Reconcile AR anchors with a previously scanned physical environment | Requires on-site surveying, stable visual features, device testing, and map lifecycle management | Partner pilot for a bounded terminal area |
| `ARGeoAnchor` | Outdoor geographic anchors where Apple geotracking is available | Not a general indoor-airport locator; availability is geographic and device-only | Outdoor terminal approaches and inter-airport wayfinding |

## Production fusion boundary

A production provider should emit the same `IndoorLocationReading` shape now produced by the emulator:

- local map point and floor;
- matched graph node or corridor;
- heading when available;
- observation time and source;
- accuracy/confidence supplied by the positioning system.

The route layer can then consume manual landmark confirmation, IMDF venue positioning, beacon proximity, UWB, or surveyed visual anchors without changing the passenger-facing maneuver model. Readings that cannot identify a floor or corridor must not silently snap across walls or levels.

## Sources

- [Apple: Simulating location in tests](https://developer.apple.com/documentation/xcode/simulating-location-in-tests)
- [Apple: XCUILocation](https://developer.apple.com/documentation/xcuiautomation/xcuilocation)
- [Apple: CLLocation floor](https://developer.apple.com/documentation/corelocation/cllocation/floor)
- [Apple: Core Location](https://developer.apple.com/documentation/corelocation)
- [Apple: Displaying an Indoor Map with IMDF](https://developer.apple.com/documentation/mapkit/displaying-an-indoor-map)
- [Apple: IMDF community standard](https://developer.apple.com/news/?id=8lmz909p)
- [Apple: Determining proximity to an iBeacon](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device)
- [Apple: Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction)
- [Apple: Tracking geographic locations in AR](https://developer.apple.com/documentation/arkit/tracking-geographic-locations-in-ar)
- [Apple: AR world-map anchors](https://developer.apple.com/documentation/arkit/arworldmap/anchors)
