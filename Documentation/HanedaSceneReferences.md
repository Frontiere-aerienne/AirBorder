# Haneda departure-concourse reconstruction

The current RealityKit gate-wing and café-concourse scenes use the published Terminal 3 map for gate relationships and driver poses. Their finishes and furniture are informed by the airport's own reference photographs. The scene remains an authored reconstruction: public map symbols and photographs do not establish surveyed dimensions, exact furniture spacing or access clearances.

## Sources

- [Haneda Terminal 3 floor guide](https://tokyo-haneda.com/en/floor/floor-guide.html?area=9&tab=terminal3&floor=3F).
- [Published 3F map image](https://tokyo-haneda.com/site_resource/floor/img/floor__img_floor_map_t3_3f.png). The copy checked on November 19, 2026 has SHA-256 `6ad843dacc17b9c4aa0f27a2e7f87fa8426aaf86f3b49b1eb2a79bb7289e5e4e`, matching the pin in `OfficialGateWalkPath`.
- [Haneda Airport Experience Support Book for Terminal 3](https://tokyo-haneda.com/site_resource/service/pdf/barrier-free_initiatives_hnd_airport_story_for_terminal3_en.pdf). Page 50 supplies a boarding-area photograph near Gate 112; page 91 combines a sensory map with additional concourse photographs. The downloaded document's metadata records a March 2026 modification, while the individual photograph dates are unspecified.

## What the scene implements

`HanedaReplayScenes.gateConcourse` uses lit floor, ceiling, columns, window frames and seating rather than making all architecture unlit. Text and signs remain unlit for readability. Seat banks share cloned meshes, and a reusable, procedurally drawn carpet texture conveys the blue-gray looped waiting-area finish. No generated approval image is used as an app asset or substituted for a genuine sign.

Map north is negative world X in the existing driver-to-scene transform. Consequently, the apron-facing glazing is on the left when traveling map east toward Gate 105, regardless of the generated preview's composition. Gate 105 and 108A retain their map-associated scene positions. Neither a new stair nor a lift is inserted into that same-floor route.

The driver keeps its accepted location, heading, floor and path revision independently of the rendered finishes. Gate changes, café stops, pauses and closures therefore continue to use the same state in Map and Camera. Other terminal, shuttle, rail and checkpoint scenes remain separate and have not been reconstructed from these boarding-area photographs.

## Geometry and operational limits

The existing side-passage exercise widens and stretches a short region for readability. This visual upgrade preserves that tested transform and replaces its unsupported full-height opaque divider with a low open separation. The test's detour, separation, furniture dimensions and metric scale remain authored geometry; they should not be described as a measured copy of the corresponding airport aisle or moving walkway.

Framed end panels close the visual scene beyond the reachable driver positions, preventing an unfinished background from appearing at either end. These panels define the rendered extent and do not add a walkable connection or assert an exact surveyed terminal-end layout. Apron surfaces, ground markings and fill lighting provide visual depth outside the glazing.

Closures, crowd conditions and lift availability supplied by the driver are test events. They do not establish current conditions at Haneda. The public reference map supports route relationships, but a deployed accessible route would require appropriate path, clearance and infrastructure-status evidence.
