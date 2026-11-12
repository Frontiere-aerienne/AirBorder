# AirBorder

AirBorder is an airport travel companion for planning layovers, navigating terminals, and managing flight connections. It combines a native SwiftUI application, an iPhone 13 browser interface, and a Cloudflare API for provider access and journey progress.

The project is a programmed research prototype. Browser flight and route scenarios use synthetic data; live services require deployment and authentication. The native and browser applications have different feature coverage.

## Current status

The verified implementation at [`01785e0`](https://github.com/Frontiere-aerienne/AirBorder/commit/01785e0a1beaaea03fd066adccddb6b2e3ea8a97) passed all hosted checks and completed Codex review with no findings. Native verification ran **106 unit tests and 17 UI tests with no failures**. See the [November 8 verification record](Documentation/Verification-2026-11-08.md) for results, source revisions, and limitations. Results apply to that revision; consult the current PR checks for subsequent changes.

| Component | Implemented scope | Availability boundary |
|---|---|---|
| Browser interface | Ordered plans; gate-change and timing scenarios; route guidance; arrival, departure, and transfer checklists | Preserves the original navy/yellow design, Outfit typography, and 390 × 844 iPhone 13 composition. Operational scenarios are synthetic. |
| Native iOS app | Itineraries, terminal and inter-airport planning, map/AR flows, ticket input, sourced weather, and conservative recommendations | Physical-device AR, configured provider behavior, and complete feature acceptance require separate validation. |
| Journey progress | Authenticated per-account, trip, and leg storage; atomic revisions; idempotent updates; retry and conflict handling | Account synchronization requires a configured deployment and an authenticated host supplying real trip/leg IDs. Otherwise the browser uses session-local progress. |
| Provider API | Protected flight, facility, entry-guidance, OCR, reminder, and optional explanation routes | Provider routes require their applicable credentials, permissions, licensing, and client integrations. Route implementation does not establish live availability. |

## Run the browser application

Use Node.js 22 (the CI version) and npm. From the repository root:

```bash
npm ci --prefix Backend
npm ci --prefix Web
node Web/dev-server.mjs
```

Open <http://127.0.0.1:4173>. The local server provides the interface and bounded directory/timing APIs; it is not a production server. Add `/?presenter=1` for synthetic disruption controls. Provider secrets are not required for these scenarios.

## Build the iOS application

Use macOS, Xcode 26 or newer with a compatible iOS runtime, and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The deployment target is iOS 18; design and CI verification target **iPhone 13**. Generate the project from `project.yml`:

```bash
./Scripts/generate.sh
open AirBorder.xcodeproj
```

Select the **AirBorder** scheme and an available **iPhone 13** simulator. The helper scripts retain their legacy simulator default, so specify the intended device explicitly:

```bash
SIMULATOR_NAME='iPhone 13' ./Scripts/build.sh
SIMULATOR_NAME='iPhone 13' ./Scripts/test.sh
SIMULATOR_NAME='iPhone 13' ./Scripts/run-simulator.sh demo
```

A compatible iPhone 13 runtime must be installed. A newer runtime may omit older simulator models. CI selects the device by identifier and fails if iPhone 13 is unavailable. See [Build and Device Test](Documentation/Build-and-Device-Test.md) for physical-device signing and testing.

## Run automated checks

From the repository root, after installing the dependencies above:

```bash
npm run check --prefix Backend
npm test --prefix Backend
node --test Web/journey-engine.test.cjs Web/backend/test/*.test.mjs
python3 Scripts/select-ci-simulator.py --self-test
```

For browser tests:

```bash
cd Web
npx playwright install chromium
npm run test:ui
```

Pull requests run [iOS CI](.github/workflows/ios-ci.yml) and [HCI quality checks](.github/workflows/hci-quality.yml). Deterministic interaction, layout, and accessibility assertions complement AI code review. Screenshots and traces support inspection; there is no comprehensive approved pixel-comparison baseline. Passing tests do not establish the absence of every functional or visual defect.

## Backend configuration

The [provider API guide](Backend/README.md) documents authentication, routes, credentials, and failure behavior. The [journey integration guide](Web/docs/journey-backend-integration.md) covers the combined API deployment, durable storage, browser host configuration, and unresolved production work.

Production configuration requires Cloudflare Access issuer/audience values, the rate-limit binding, and the journey storage binding. Keep provider credentials in Worker secrets. The browser and iOS app must not contain provider keys. The checked-in placeholders and deployment dry runs do not establish a live service.

## Design and decision principles

The [AirBorder Figma reference](https://www.figma.com/design/zQaZKxZ1rrX4EMYQkY3j00/AirBorder-Travel-Companion?node-id=858-8324) defines the approved interface. The [Figma-to-code mapping](Documentation/HCI/Figma-code-mapping.md) records implementation references; automatic two-way synchronization and Code Connect are not configured.

- Missing or expired timing inputs remain unknown rather than becoming zero.
- Recommendations preserve selected stops and require explicit application and Undo.
- Security, passport-control, customs, and boarding completion require passenger confirmation.
- Provider facts retain provenance and expiry; AI explanations cannot authorize entry or change feasibility.
- Simulation results, simulator AR, and provider adapters are not evidence of real-airport accuracy.

## Documentation

Start with the [documentation index](Documentation/README.md) for architecture, local development, deployment, design acceptance, and verification records. Dated reports remain historical evidence. [Known limitations and pending work](Web/docs/journey-backend-plan.md) distinguish implemented journey infrastructure from production readiness.
