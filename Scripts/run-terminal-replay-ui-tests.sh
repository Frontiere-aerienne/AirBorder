#!/bin/zsh
# PROCEDURAL: Runs the simulator-only terminal replay UI regression against the independent loopback driver.

set -euo pipefail

script_dir=${0:A:h}
root_dir=${script_dir:h}
driver_logs=$(mktemp -d -t airborder-terminal-replay-drivers.XXXXXX)
driver_pids=()

cleanup() {
  for driver_pid in "${driver_pids[@]}"; do kill "$driver_pid" 2>/dev/null || true; done
  rm -r "$driver_logs"
}
trap cleanup EXIT INT TERM

start_driver() {
  local variable="$1" port="" log_file="$driver_logs/$2.log"
  shift 2
  # Create the log before the first readiness poll; background redirection can
  # otherwise race sed under set -e on a fast or busy hosted runner.
  : >"$log_file"
  python3 "$root_dir/Scripts/indoor-signal-emulator.py" "$@" \
    --paused --no-loop --port 0 >"$log_file" 2>&1 &
  driver_pids+=("$!")
  for _ in {1..900}; do
    port=$(sed -n 's/^Indoor signal emulator: http:\/\/127\.0\.0\.1:\([0-9][0-9]*\)\/reading$/\1/p' "$log_file" | head -n 1)
    if [[ -n "$port" ]] && curl -fsS "http://127.0.0.1:$port/status" >/dev/null; then
      export "$variable=$port"
      return
    fi
    sleep 0.05
  done
  cat "$log_file" >&2
  return 1
}

fixtures="$root_dir/Scripts/tests/fixtures"
start_driver TEST_RUNNER_REPLAY_PORT wrong-floor-lift --trace "$fixtures/wrong-floor-lift.json"
start_driver TEST_RUNNER_PEDESTRIAN_WALK_PORT haneda-pedestrians --haneda-gate-replanning --start-at-junction --pedestrian-occlusion
start_driver TEST_RUNNER_LOUNGE_QUEUE_PORT haneda-lounge-queue --trace "$fixtures/haneda-lounge-queue.json" --facility-queues
start_driver TEST_RUNNER_ARRIVALS_QUEUE_PORT haneda-arrivals-queues --trace "$fixtures/haneda-arrivals-queues.json" --facility-queues
start_driver TEST_RUNNER_SECURITY_QUEUE_PORT haneda-security-queue --trace "$fixtures/haneda-observation-deck.json" --security-queue
start_driver TEST_RUNNER_REPLAY_DECK_PORT haneda-deck --trace "$fixtures/haneda-observation-deck.json"
start_driver TEST_RUNNER_REPLAY_NARITA_PORT haneda-bus --trace "$fixtures/haneda-narita-bus.json"
start_driver TEST_RUNNER_REPLAY_RAIL_PORT haneda-rail --trace "$fixtures/haneda-narita-rail.json"
start_driver TEST_RUNNER_ADAPTIVE_WALK_PORT adaptive-haneda --haneda-gate-replanning
start_driver TEST_RUNNER_JUNCTION_WALK_PORT haneda-junction --haneda-gate-replanning --start-at-junction
start_driver TEST_RUNNER_CAFE_WALK_PORT haneda-cafe --haneda-cafe-walk
start_driver TEST_RUNNER_OFFICIAL_WALK_PORT haneda-105 --trace "$fixtures/haneda-gate-105-walk.json"
start_driver TEST_RUNNER_OFFICIAL_WALK_108A_PORT haneda-108a --trace "$fixtures/haneda-gate-108a-walk.json"

airport_log="$driver_logs/airport-provider.log"
: >"$airport_log"
python3 "$root_dir/Scripts/airport-provider-driver.py" --offline-map --port 0 >"$airport_log" 2>&1 &
driver_pids+=("$!")
airport_port=""
for _ in {1..900}; do
  airport_port=$(sed -n 's|^Airport provider replay: http://127.0.0.1:\([0-9][0-9]*\)/v1/assignment$|\1|p' "$airport_log" | head -n 1)
  if [[ -n "$airport_port" ]] && curl -fsS "http://127.0.0.1:$airport_port/v1/assignment" >/dev/null; then
    export TEST_RUNNER_AIRPORT_PROVIDER_PORT="$airport_port"
    break
  fi
  sleep 0.05
done
: "${TEST_RUNNER_AIRPORT_PROVIDER_PORT:?Airport provider failed to start}"

ocr_fixtures="$driver_logs/ocr"
swift "$root_dir/Scripts/generate-ticket-ocr-fixtures.swift" "$ocr_fixtures"
export TEST_RUNNER_TICKET_OCR_FIXTURES="$ocr_fixtures/unreadable.png"$'\n'"$ocr_fixtures/readable.png"
export TEST_RUNNER_SIGN_OCR_FIXTURES="$ocr_fixtures/sign-nonmatch.png"$'\n'"$ocr_fixtures/sign-gates.png"

speech_tests=()
if [[ -n "${AIRBORDER_LOCAL_SPEECH_HELPER:-}" && -n "${AIRBORDER_LOCAL_SPEECH_FIXTURE:-}" ]]; then
  speech_log="$driver_logs/local-speech.log"
  python3 "$root_dir/Scripts/local-route-speech.py" --helper "$AIRBORDER_LOCAL_SPEECH_HELPER" --port 0 >"$speech_log" 2>&1 &
  driver_pids+=("$!")
  for _ in {1..60}; do
    speech_port=$(sed -n 's/^Local route speech: \([0-9][0-9]*\)$/\1/p' "$speech_log" | head -n 1)
    if [[ -n "$speech_port" ]]; then
      export TEST_RUNNER_ROUTE_SPEECH_PORT="$speech_port"
      export TEST_RUNNER_ROUTE_SPEECH_FIXTURE="$AIRBORDER_LOCAL_SPEECH_FIXTURE"
      break
    fi
    sleep 0.05
  done
  : "${TEST_RUNNER_ROUTE_SPEECH_PORT:?Local speech driver failed to start}"
  speech_tests=(-only-testing:AirportXRCompanionUITests/AirBorderUITests/testRouteVoiceRecognizesRecordedSpeechLocallyAndAnswers)
fi

ui_target=AirportXRCompanionUITests/AirBorderUITests
if (( $# == 0 )); then
  set -- -only-testing:AirportXRCompanionTests
  for test_name in \
    testHanedaWalkLauncherOpensTheDriverRoute \
    testTerminalReplayHoldsAtTheLastConfirmedFloorThenContinuesOnConfirmedFourFloor \
    testPedestriansCrossWithoutChangingTheLeftTurnOrTravelerPosition \
    testHanedaLoungeQueueFollowsTheSelectedStop \
    testHanedaArrivalsQueueHoldsCameraOffUntilClearance \
    testSecurityQueueWarnsOnlyWhileClearanceIsStillNeeded \
    testHanedaReplayShuttleDeckAndReturnSecurity \
    testHanedaReplayNaritaBusRemainsLandside \
    testHanedaReplayKeikyuPlatformMovesAndTurns \
    testAdaptiveHanedaCrowdExposesAQuieterConcourseOption \
    testAdaptiveHanedaWalkReroutesAndSharesItsPositionWithCamera \
    testHanedaReplayHoldsForAFullShuttleAndAnUnavailableLift \
    testOfficialGateWalkFollowsConfirmedPositions \
    testOfficialGate108AWalkPlaysFromDriverClock \
    testBlockedJunctionReroutesInPlaceAndLeavesTheExistingBypassUnchanged \
    testContinuousCafeWalkRecoversLandmarkAndKeepsPoseAtGateChange \
    testCrowdReportAffectsOnlyTheRouteThroughTheConcourseStrip \
    testAirportProviderGateMapHandoffAndRouteContinuity \
    testProviderRejectsOlderAndConflictingAssignments \
    testProviderQueuesAgeIndependentlyAndRejectOldPlanningSnapshots \
    testAirportUpdatesDistinguishOldReportsFromConnectionLossAndRecovery \
    testDriverCafeOfferRechecksTheWaitBeforeAddingAStop \
    testCafeWaitExpiryPreservesThePlanAndFreshReportRestoresTiming \
    testDriverRanksLoungesAfterAGateUpdateAndCanBrowseChangi \
    testDriverOnwardFlightReviewRetainsTheBookedTripDuringAnOutage \
    testOnboardingRunsOnceThenOpensFlight \
    testOnboardingSkipStaysDismissedOnRelaunch \
    testTutorialReplayReturnsToProfileAndPreservesThePlan \
    testLanguageChoicesDiscloseAvailabilityAndReturnToProfile \
    testBackFromBaggageReturnsToJourneyThenFlight \
    testRouteFinalStepCanGoBackAndEnd \
    testLayoverPlanPageShowsSelectedStopsAndBackReturnsToLayover \
    testDeniedCameraReturnsToTheSameMapStep \
    testCameraGuidanceKeepsTheStepAndFallsBackToTheMap \
    testUnclearTicketPhotoCanBeRetakenReviewedCorrectedAndSaved \
    testSignScanRetriesAndRecognizesTheGateWithoutAdvancingTheRoute \
    testRouteVoiceStartsFromAnAccessibleControlAndCanBeStopped \
    testGateAlertActionsStayReachableWithAccessibilityText; do
    set -- "$@" "-only-testing:$ui_target/$test_name"
  done
  set -- "$@" "${speech_tests[@]}"
fi

cd "$root_dir"
xcodebuild test \
  -project AirBorder.xcodeproj \
  -scheme AirBorder \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${SIMULATOR_UDID:?Set SIMULATOR_UDID to an available iPhone simulator}" \
  -derivedDataPath "${DERIVED_DATA:-$root_dir/build/DerivedData}" \
  -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO \
  "$@"
