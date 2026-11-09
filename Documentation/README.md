# AirBorder documentation

Use the repository README for a quick start. These documents describe implementation boundaries, verification, and deployment requirements; dated results apply only to their recorded revisions.

| Topic | Reference |
|---|---|
| Build, simulator, and physical-device testing | [Build and Device Test](Build-and-Device-Test.md) |
| Native domain model and decision services | [Architecture](Architecture.md), [Developer Guide](DeveloperGuide.md) |
| Provider authentication, routes, and secrets | [Backend API](../Backend/README.md) |
| Browser progress API and host integration | [Journey Integration](../Web/docs/journey-backend-integration.md) |
| Journey implementation status and remaining work | [Journey Backend Status](../Web/docs/journey-backend-plan.md) |
| Current verified implementation snapshot | [November 8, 2026 verification](Verification-2026-11-08.md) |
| Product acceptance and coverage limitations | [Acceptance and Review](HCI/Acceptance-and-review.md) |
| Design references and code locations | [Figma Mapping](HCI/Figma-code-mapping.md) |
| HCI implementation and evaluation scope | [Implementation and Evaluation Plan](HCI/Implementation-and-evaluation-plan.md) |
| Data use, security, and bounded AI | [Data Sources](DataSources.md), [Privacy and Security](PrivacyAndSecurity.md), [AI Integrations](AIIntegrations.md) |

The native source directory is `AirBorder/`. Test targets and some identifiers retain the historical `AirportXRCompanion` name. The browser application lives in `Web/`, and the canonical provider Worker lives in `Backend/`.

## Reading historical material

The [October verification](Verification-2026-10-11.md), [July report](Reports/2026-07-14-airportxr-long-haul-layover.md), generated report exports, and submission artifacts record their original scope and results. They do not override newer verification or certify the current branch. Research roadmaps and architectural proposals describe intended capabilities unless implementation and evidence are explicitly identified.

For an exact current status, inspect the commit being reviewed, its GitHub checks, and the applicable acceptance criteria. Runtime deployment, external credentials, device validation, and participant evaluation remain separate from repository test results.
