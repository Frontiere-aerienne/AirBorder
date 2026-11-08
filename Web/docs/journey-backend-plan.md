# Journey backend implementation status

The journey overlay, authenticated progress API, and browser sync adapter are implemented. This document separates that repository implementation from production activation and future work. See [Journey Integration](journey-backend-integration.md) for the API and host contract and the [verification snapshot](../../Documentation/Verification-2026-11-08.md) for recorded evidence.

| Area | Status | Scope |
|---|---|---|
| Account, trip, and flight-leg isolation | Implemented and tested | Verified Access subject selects a private Durable Object; updates validate the expected owner. |
| Atomic revisions and idempotency | Implemented and tested | Concurrent/stale writes conflict; identical event retries retain acknowledgement semantics. |
| Explicit journey confirmations | Implemented and tested | Phase, step and value are validated; provider updates do not complete airport procedures. |
| Browser outbox and recovery | Implemented and tested | Session-scoped retry, ordered pending state, conflict recovery, unavailable-storage fallback and same-account reauthentication. |
| Account changes and logout | Implemented and tested | Account-bound UI clears on ownership mismatch and logout, including when storage cleanup fails. |
| Contextual preparation advice | Implemented with bounded sources | Active airport/phase/step guidance links to official sources; it does not determine entry eligibility. |
| Production storage and identity-host activation | Pending | Real Access configuration, deployment and authenticated dated trip/leg IDs are required. |
| Fully derived journey applicability | Pending | Broader domestic/international, baggage, terminal and separate-ticket rules need verified inputs and explicit reconciliation. The checklist is not a complete airport-procedure rule engine. |
| Durable offline client queue | Pending | Current queue is session-scoped, with memory fallback when storage fails; it cannot guarantee survival after a closed session or process loss. |
| Automated retention and deletion | Pending | The current store is capped at 1,000 accepted events per trip/leg; lifecycle administration remains to be implemented. |
| Itinerary-change reconciliation | Pending | A changed dated itinerary must not inherit unrelated confirmations; existing trip/leg separation does not implement a full migration policy. |

Production acceptance requires configured authenticated end-to-end operation and observed offline recovery against the deployed service. Synthetic scenarios, mocked HTTP responses, SQLite emulator tests and deployment dry runs establish their stated bounded behavior, not a deployed account service.
