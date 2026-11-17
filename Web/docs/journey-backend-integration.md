# Journey progress API and browser integration

The browser overlay connects to authenticated GET/POST `/v1/journeys/{trip}/{leg}`. The Cloudflare Worker verifies the existing Access JWT and rate limit, hashes its authenticated subject, and selects a Durable Object from subject + trip + leg. Caller-supplied ownership cannot select another passenger's storage. Each accepted update atomically saves a snapshot, increasing revision and idempotency record. Reusing an event ID with a changed payload fails. Conditional not-needed values and all step IDs are validated; confirmations never change route timing, entry eligibility or selected stops.

## Deployment boundary

Deploy the combined API with `npx --prefix Backend wrangler deploy --config Web/wrangler.toml` after setting real Cloudflare Access issuer/audience, explicit allowed origin, and account bindings. The SQLite Durable Object migration is included. The deploy dry run is verified; the service has not been deployed by this change. Do not deploy the placeholder Access settings. Prefer a same-origin authenticated proxy for the browser: no JWT or provider secret belongs in JavaScript. The existing remote API deployment does not acquire these capabilities until updated.

## Authenticated browser host

Before loading app.js, the authenticated host supplies `window.AIRBORDER_JOURNEY = {trip: 'opaque-trip-id', leg: 'opaque-flight-leg-id'}` and, if needed, `window.AIRBORDER_API_BASE`. IDs must refer to the actual dated itinerary; never use a shared constant for all trips. The fixture app intentionally retains session-local saving until this binding exists. Browser sync uses same-origin credentials. Cross-origin account sign-in is not implemented by the public directory preview.

## Persistence and recovery

Account-bound editing waits for an authenticated record. The client restores saved progress with pending changes, stores an owner/URL-scoped outbox in sessionStorage, retries identical events on reconnect, and pauses on revision conflict. Older replay acknowledgements cannot roll the known revision backward. Storage failure retains a memory-only queue; expired authentication preserves queued updates for the same account. The checklist offers Use saved progress for an explicit conflict resolution; this discards queued local changes. Dispatch `airborder:logout` when the host signs out to clear progress and its active outbox. Ownership mismatch also clears the displayed checklist. An in-flight response cannot restore logged-out progress, and failed storage cleanup cannot prevent the UI reset. A closed browser session does not retain the outbox; acknowledged server progress persists. Durable records currently accept at most 1,000 events and then return an explicit error. Automated retention/deletion, persistent offline outboxes, itinerary reconciliation and production identity-host integration remain pending; do not claim these are deployed or fully supported.

## Verification

Verification combines authenticated API/storage tests, client offline/conflict/logout tests and a browser test through the overlay's HTTP contract. Source guidance remains in journey-advice-sources.md. No live entry rules, queues or location are inferred from this service.


## Request contract

`GET /v1/journeys/{trip}/{leg}` returns `owner`, `revision`, `phase` and phase-indexed `status`. Trip and leg IDs accept 1–80 ASCII letters, digits, underscores or hyphens. New records begin at revision zero with no confirmed steps.

`POST` accepts only these fields:

| Field | Requirement |
|---|---|
| `eventId` | UUID retained unchanged for a retry. |
| `expectedOwner` | Opaque 64-character owner hash from the authenticated GET response. |
| `expectedRevision` | Nonnegative safe integer for optimistic concurrency. |
| `phase` | `arrival`, `departure` or `transfer`. |
| `step` | An allowed step ID for that phase, or null for a phase-only change. |
| `value` | `done`, `pending` (Undo), or `not-needed` for an optional step. Phase-only changes require null. |

Requests are limited to 2,048 bytes and validated before mutation. An owner mismatch returns `403`; revision or event-ID reuse conflicts return `409`. Repeating an identical event returns its original acknowledgement; clients must retain any newer fetched revision. These endpoints do not accept passport numbers, health records, provider credentials or arbitrary plan content.

The [backend implementation status](journey-backend-plan.md) lists remaining production work. The [November verification record](../../Documentation/Verification-2026-11-08.md) identifies tested revisions and coverage limits.

### Airport-neutral browser itinerary input

The static browser app still opens with the explicit Tokyo fixture in
`demo-journey.js` when the host has not provided an itinerary. Before
`app.js` runs, a host can set `window.AIRBORDER_ITINERARY` to a two-leg
connection. It takes `id`, `date`, and `inbound` and `onward` records with
`id` (flight identifier), `airline`, `from` and `to` airport records,
`departure` and `arrival` in local `HH:mm`, `terminal`, `gate`, and a
published `target` in local `HH:mm` when available. Airport records can
contain `code` (three-letter IATA), `name`, `city`, `country` (two-letter
ISO), `zone` (display abbreviation), and `timeZone` (IANA zone).
An incomplete supplied itinerary stays incomplete; it does not borrow
fields or facility links from Tokyo. A different arrival and departure
airport produces a transfer checklist, not estimated transport or border
clearance.

The public facility lookup requires an explicit airport parameter. A host
that expects official links can provide the exact permitted HTTPS hostnames
in `officialDirectoryHosts`; the browser also rejects a mismatched airport
in the service response. The directory displays unavailable for unsupported
airports. The presence of a published directory entry does not provide
route geometry, live queues or permission to enter.

For a same-airport trip with a sourced point-to-gate estimate, the host may
provide a `timing` object with matching `airportCode`, `flightId`, and
`gate`, integer `walkMinutes` (0–1440), and offset-qualified ISO date-times
`observedAt`, `expiresAt`, and `arrivalTargetAt`. The browser limits the
validity and target horizon to 24 hours from observation, rejects future or
expired observations for numeric guidance, and uses the departure airport’s
IANA zone. This enables local timing estimates, not turn-by-turn navigation,
a claim of live airport coverage, or an eligibility determination. A new or
updated source must supply a fresh itinerary; the browser does not fetch a
live walk estimate itself. It does not submit host timing to the public
calculation API. Unbound supplied-trip checklist progress stays in the
current page and is isolated from the demo session; authenticated binding
still uses `AIRBORDER_JOURNEY` and its existing account controls.
