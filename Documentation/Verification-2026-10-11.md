# Verification snapshot — October 11, 2026

This note records observed evidence for code commit [620a00e2d4baefcc04f0845a01ab1f46d25a92db](https://github.com/MayFairMI6/AirBorder/commit/620a00e2d4baefcc04f0845a01ab1f46d25a92db). The documentation addition does not change application or Worker behavior.

| Check | Evidence | Outcome |
|---|---|---|
| Fresh local Worker suite | Original package lock; Node 25.8.1 on macOS arm64 | 37 passed; zero failed/skipped |
| Hosted build | [Run 36787086841](https://github.com/MayFairMI6/AirBorder/actions/runs/36787086841) | Passed |
| Hosted unit suite | Same run's original job log | 106 tests passed |
| Hosted UI suite | Same run's original job log | 17 tests executed; 10 failures |
| Overall hosted run | GitHub run/jobs API | Failed at UI-test step |

## Reproduce the Worker check

From an isolated checkout of the inspected code commit:

```sh
cd Backend
npm ci --ignore-scripts
npm test
```

The install uses the committed lockfile. Disabling dependency install scripts is sufficient for this Worker test command; deployment is a separate workflow. The original CI workflow remains the reference for iOS build and simulator testing.

## Decision-model interpretation

The [recommendation engine](../AirBorder/Services/LongHaul/MonteCarloLayoverRecommendationEngine.swift) uses a replayable seed, triangular segment-time distributions, explicit calculation traces and unresolved-input handling. [SafetyPolicy](../AirBorder/Services/LongHaul/SafetyPolicy.swift) supplies the policy boundary.

A Wilson interval around a simulated success fraction describes sampling uncertainty conditional on the selected modeled inputs. It does not independently validate those inputs or calibrate a real traveler's probability of making an onward flight. Provider freshness and provenance checks likewise do not establish that a credential-backed provider has been configured and validated in a particular deployment.

## Next validation work

- Reproduce and resolve the UI failures, then rerun the affected scenarios and full suite.
- Validate physical-device AR and configured provider behavior with the corresponding acceptance evidence.
- Keep questionnaire/software cases distinct from recruited participants, consent records and completed study analysis.
- Assess field calibration against observed outcomes before strengthening real-airport performance claims.

No new participant responses, sensor recordings, full iOS/device test run or provider-contract validation were produced for this documentation update. Existing implementation and historical test records are preserved.
