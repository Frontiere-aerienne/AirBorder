// PROCEDURAL: Verifies native interface behavior with scripted journeys.

import Foundation
import XCTest

final class AirBorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-walkingSpeed", "5.6", "-gateUpdate", "off"]
        app.launch()
    }

    func testHanedaWalkLauncherOpensTheDriverRoute() throws {
        guard let port = ProcessInfo.processInfo.environment["ADAPTIVE_WALK_PORT"] else {
            throw XCTSkip("Run with the Haneda position driver")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-open-route",
                  "--qa-indoor-feed", "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "adaptive"])
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 5))
        waitForOfficialWalkPosition("0% of route")
        XCTAssertTrue(app.buttons["mode-map"].isSelected)
    }

    /// An opt-in recording walkthrough; timing pauses let the viewer read each
    /// view while all movement between them still comes from the driver's clock.
    func testRecordHanedaContinuousWalkAndGateChange() throws {
        guard ProcessInfo.processInfo.environment["RECORD_HANEDA_WALK"] == "1",
              let port = ProcessInfo.processInfo.environment["ADAPTIVE_WALK_PORT"],
              let airportPort = ProcessInfo.processInfo.environment["AIRPORT_PROVIDER_PORT"] else {
            throw XCTSkip("Run the opt-in Haneda video capture")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        try replayControl("current-gate", port: airportPort)
        try replayControl("gate/105", port: airportPort)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-open-route",
                  "--qa-indoor-feed", "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "adaptive",
                  "--qa-airport-provider", "http://127.0.0.1:\(airportPort)/v1/assignment"])
        waitForOfficialWalkPosition("0% of route")
        print("HANEDA_RECORD_BEGIN \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 2.5)

        try replayControl("resume", port: port)
        Thread.sleep(forTimeInterval: 3)
        try replayControl("pause", port: port)
        Thread.sleep(forTimeInterval: 0.4)
        let instruction = app.staticTexts["routeInstruction"]
        let mapPose = instruction.value as? String
        app.buttons["mode-camera"].tap()
        XCTAssertEqual(instruction.value as? String, mapPose)
        snapshot("haneda-video-camera-forward")
        Thread.sleep(forTimeInterval: 2)

        try replayControl("resume", port: port)
        Thread.sleep(forTimeInterval: 2)
        try replayControl("pause", port: port)
        Thread.sleep(forTimeInterval: 0.4)
        let cameraPose = instruction.value as? String
        app.buttons["mode-map"].tap()
        XCTAssertEqual(instruction.value as? String, cameraPose)
        Thread.sleep(forTimeInterval: 2)
        app.buttons["mode-camera"].tap()
        XCTAssertEqual(instruction.value as? String, cameraPose)
        Thread.sleep(forTimeInterval: 1)

        try replayControl("gate/108A", port: airportPort)
        XCTAssertTrue(app.buttons["alertRoute"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)
        app.buttons["alertRoute"].tap()
        XCTAssertTrue(app.staticTexts["Turn back along the concourse"].waitForExistence(timeout: 4))
        XCTAssertEqual(instruction.value as? String, cameraPose)
        snapshot("haneda-video-camera-uturn")
        Thread.sleep(forTimeInterval: 2)
        try replayControl("resume", port: port)
        Thread.sleep(forTimeInterval: 2)
        app.buttons["mode-map"].tap()
        Thread.sleep(forTimeInterval: 2)
        app.buttons["mode-camera"].tap()
        try replayControl("pause", port: port)
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].exists)
        XCTAssertTrue(app.buttons["mode-camera"].isSelected)
        snapshot("haneda-video-camera-rerouted")
        Thread.sleep(forTimeInterval: 2)
        print("HANEDA_RECORD_END \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 1)
    }

    func testFourTabsShowTheirScreens() {
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Layover"].tap()
        XCTAssertTrue(app.staticTexts["Layover & transit"].waitForExistence(timeout: 2))
        app.tabBars.buttons["Route"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 2))
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Your profile"].waitForExistence(timeout: 2))
    }

    func testLayoverPlanPageShowsSelectedStopsAndBackReturnsToLayover() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-anaLounge"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["planBar"].tap()
        let first = app.buttons["plan-stop-anaLounge"]
        let second = app.buttons["plan-stop-cafe"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(first.label.contains("Arrive"))
        XCTAssertTrue(first.label.contains("Leave"))
        snapshot("critique-plan-page")
        first.tap()
        XCTAssertTrue(app.descendants(matching: .any)["leave-anaLounge"].waitForExistence(timeout: 2))
        app.buttons["back"].tap()
        XCTAssertTrue(app.staticTexts["Layover & transit"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["planBar"].label.contains("2 stops"))
    }

    func testAirportGuideSearchLeavesTheActiveFlightUnchanged() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["airportGuidesLink"].tap()
        let haneda = app.descendants(matching: .any)["airport-guide-HND"]
        let heathrow = app.descendants(matching: .any)["airport-guide-LHR"]
        XCTAssertTrue(haneda.waitForExistence(timeout: 3))
        XCTAssertTrue(haneda.label.contains("Current trip"))
        XCTAssertTrue(heathrow.exists)
        snapshot("critique-airport-guides")
        let search = app.textFields["airportGuideSearch"]
        search.tap()
        search.typeText("heathrow")
        XCTAssertTrue(heathrow.exists)
        XCTAssertTrue(haneda.waitForNonExistence(timeout: 2))
        app.buttons["back"].tap()
        app.tabBars.buttons["Flight"].tap()
        XCTAssertTrue(app.buttons["ticketGateMap"].label.contains("105"))
    }

    func testFoodFilterRanksKnownSampleWalks() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["Food & drink"].tap()
        let bento = app.buttons["add-bento"]
        let cafe = app.buttons["add-cafe"]
        XCTAssertTrue(bento.waitForExistence(timeout: 2))
        XCTAssertTrue(cafe.exists)
        XCTAssertLessThan(bento.frame.minY, cafe.frame.minY)
    }

    func testRouteShowsMapAndCameraWithoutTheSimulatorFeed() {
        app.tabBars.buttons["Route"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["mode-map"].exists)
        XCTAssertTrue(app.buttons["mode-camera"].exists)
        XCTAssertFalse(app.buttons["mode-replay"].exists)
    }

    func testTerminalReplayHoldsAtTheLastConfirmedFloorThenContinuesOnConfirmedFourFloor() throws {
        guard let port = ProcessInfo.processInfo.environment["REPLAY_PORT"], Int(port) != nil else {
            throw XCTSkip("Run through Scripts/run-terminal-replay-ui-tests.sh so the independent replay driver is available.")
        }

        app.terminate()
        app.launchArguments = [
            "-resetState", "-skipOnboarding", "-walkingSpeed", "5.6", "-gateUpdate", "off",
            "--uitesting", "--qa-indoor-feed", "http://127.0.0.1:\(port)/reading"
        ]
        app.launch()
        app.tabBars.buttons["Route"].tap()
        let camera = app.buttons["mode-camera"]
        XCTAssertTrue(camera.waitForExistence(timeout: 3))
        camera.tap()
        assertContinuousGuidance()
        XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["guidanceLocation"].label, "3F")

        try replayControl("next", port: port)
        XCTAssertTrue(app.staticTexts["Wait for floor confirmation"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["guidanceLocation"].label, "3F")
        XCTAssertFalse(app.buttons["endRoute"].exists)
        snapshot("terminal-replay-floor-hold")

        try replayControl("next", port: port)
        XCTAssertTrue(app.staticTexts["Gate 105 ahead"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["guidanceLocation"].label, "4F")
        assertContinuousGuidance()
        snapshot("terminal-replay-floor-confirmed")

        try replayControl("next", port: port)
        XCTAssertTrue(app.staticTexts["Gate 105 ahead"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["guidanceLocation"].label, "4F")
        // The second confirmed 4F reading is a distinct camera pose. Allow the 125 ms poll
        // and the 240 ms same-floor scene animation to settle before retaining its image.
        Thread.sleep(forTimeInterval: 0.5)
        snapshot("terminal-replay-four-floor-motion")

        try replayControl("previous-landmark", port: port)
        XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["guidanceLocation"].label, "3F")
        try replayControl("next-landmark", port: port)
        XCTAssertTrue(app.staticTexts["Gate 105 ahead"].waitForExistence(timeout: 3))
        try replayControl("next-landmark", port: port)
        XCTAssertTrue(app.staticTexts["Check your flight"].waitForExistence(timeout: 3))
        app.buttons["endRoute"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].waitForExistence(timeout: 3))
    }

    func testHanedaReplayShuttleDeckAndReturnSecurity() throws {
        let port = try openTerminalReplay(route: "observation-deck", portKey: "REPLAY_DECK_PORT")
        assertReplay("Go down to the buses on 1F", location: "T3 · 2F · Landside")
        try replayControl("next-landmark", port: port)
        assertReplay("Board at Stop 0", location: "T3 · 1F · Landside")
        snapshot("haneda-stop-0")
        try replayControl("next", port: port)
        Thread.sleep(forTimeInterval: 0.5)
        snapshot("haneda-stop-0-motion")

        try replayControl("next-landmark", port: port)
        assertReplay("Stay on until Terminal 2", location: "T3 → T2 · Landside")
        snapshot("haneda-shuttle-ride")
        try replayControl("next-landmark", port: port)
        assertReplay("Stay on until Terminal 2", location: "Via T1 · Landside")
        try replayControl("next-landmark", port: port)
        assertReplay("Take the lift to 5F", location: "T2 · 1F · Landside")
        try replayControl("next", port: port)
        try replayControl("next", port: port)
        assertReplay("Wait for floor confirmation", location: "T2 · 1F · Landside")
        XCTAssertFalse(app.buttons["endRoute"].exists)
        snapshot("haneda-deck-floor-hold")
        try replayControl("next", port: port)
        assertReplay("Return to Terminal 3", location: "T2 · 5F · Landside")
        snapshot("haneda-observation-deck")

        try replayControl("next-landmark", port: port)
        assertReplay("Take the lift to 1F", location: "T2 · 5F · Landside")
        snapshot("haneda-deck-return-lift")
        try replayControl("next-landmark", port: port)
        assertReplay("Board at Stop 9", location: "T2 · 1F · Landside")
        try replayControl("next-landmark", port: port)
        assertReplay("Stay on until Terminal 3", location: "T2 → T3 · Landside")
        try replayControl("next-landmark", port: port)
        assertReplay("Take the lift to 3F", location: "T3 · 1F · Landside")
        snapshot("haneda-t3-departures-lift")
        try replayControl("next-landmark", port: port)
        assertReplay("Go through security", location: "T3 · 3F · Landside")
        snapshot("haneda-return-security")
        try replayControl("next", port: port)
        try replayControl("next", port: port)
        assertReplay("Wait for security clearance", location: "T3 · 3F · Landside")
        XCTAssertFalse(app.buttons["endRoute"].exists)
        snapshot("haneda-security-hold")
        try replayControl("next", port: port)
        assertReplay("Gate 105 ahead", location: "T3 · 3F · Airside")
        snapshot("haneda-airside")
        try replayControl("next-landmark", port: port)
        assertReplay("Check your flight", location: "T3 · 3F · Airside")
        app.buttons["endRoute"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].waitForExistence(timeout: 3))
    }

    func testSecurityQueueWarnsOnlyWhileClearanceIsStillNeeded() throws {
        let port = try openTerminalReplay(route: "observation-deck", portKey: "SECURITY_QUEUE_PORT")
        for _ in 0..<9 { try replayControl("next-landmark", port: port) }
        assertReplay("Take the lift to 3F", location: "T3 · 1F · Landside")
        XCTAssertTrue(app.buttons["mode-camera"].isSelected)
        XCTAssertTrue(app.buttons["mode-camera"].isEnabled)

        try replayControl("next-landmark", port: port)
        assertReplay("Go through security", location: "T3 · 3F · Landside")
        assertCheckpointUsesMap(showsApproach: true)
        let warning = app.descendants(matching: .any)["securityQueueUpdate"].firstMatch
        XCTAssertFalse(warning.exists)
        snapshot("security-queue-normal")
        print("QUEUE_VIDEO_BEGIN \(Date().timeIntervalSince1970)")
        try replayControl("security-queue-long", port: port)
        XCTAssertTrue(warning.waitForExistence(timeout: 4))
        XCTAssertTrue(warning.label.contains("Security queue"))
        XCTAssertTrue(warning.label.contains("12"))
        assertReplay("Go through security", location: "T3 · 3F · Landside")
        snapshot("security-queue-long")
        print("QUEUE_LONG_CAPTURED \(Date().timeIntervalSince1970)")

        try replayControl("next", port: port)
        assertReplay("Go through security", location: "T3 · 3F · Landside")
        assertCheckpointUsesMap(showsApproach: false)
        XCTAssertTrue(warning.exists)
        snapshot("security-queue-inside")

        try replayControl("next", port: port)
        assertReplay("Wait for security clearance", location: "T3 · 3F · Landside")
        assertCheckpointUsesMap(showsApproach: false)
        XCTAssertTrue(warning.exists)
        XCTAssertFalse(app.buttons["endRoute"].exists)
        try replayControl("next", port: port)
        assertReplay("Gate 105 ahead", location: "T3 · 3F · Airside")
        XCTAssertFalse(warning.exists)
        XCTAssertTrue(app.buttons["mode-map"].isSelected)
        let camera = app.buttons["mode-camera"]
        XCTAssertTrue(camera.isEnabled)
        camera.tap()
        XCTAssertTrue(camera.isSelected)
        assertReplay("Gate 105 ahead", location: "T3 · 3F · Airside")
        snapshot("security-queue-after-clearance")
        print("QUEUE_VIDEO_END \(Date().timeIntervalSince1970)")
        app.buttons["mode-map"].tap()
        XCTAssertFalse(warning.exists)
    }

    func testHanedaLoungeQueueFollowsTheSelectedStop() throws {
        let port = try openTerminalReplay(route: "lounge", portKey: "LOUNGE_QUEUE_PORT")
        let warning = app.descendants(matching: .any)["facilityQueueUpdate"].firstMatch
        assertReplay("Lounge entrance on your right", location: "T3 · Airside")
        XCTAssertTrue(app.buttons["mode-camera"].isSelected)
        XCTAssertFalse(warning.exists)

        print("LOUNGE_VIDEO_BEGIN \(Date().timeIntervalSince1970)")
        snapshot("lounge-queue-normal")
        try replayControl("facility-queue-long", port: port)
        XCTAssertTrue(warning.waitForExistence(timeout: 4))
        XCTAssertTrue(warning.label.contains("Lounge queue"))
        XCTAssertTrue(warning.label.contains("8 minutes"))
        snapshot("lounge-queue-camera")

        app.buttons["mode-map"].tap()
        XCTAssertTrue(app.buttons["mode-map"].isSelected)
        assertReplay("Lounge entrance on your right", location: "T3 · Airside")
        XCTAssertTrue(warning.exists)
        XCTAssertTrue(warning.label.contains("8 minutes"))
        snapshot("lounge-queue-map")

        try replayControl("next", port: port)
        assertReplay("Check your flight", location: "T3 · 4F · Airside")
        XCTAssertFalse(warning.exists)
        XCTAssertTrue(app.buttons["endRoute"].exists)
        snapshot("lounge-queue-gate")
        print("LOUNGE_VIDEO_END \(Date().timeIntervalSince1970)")
    }

    func testHanedaArrivalsQueueHoldsCameraOffUntilClearance() throws {
        let port = try openTerminalReplay(route: "arrivals", portKey: "ARRIVALS_QUEUE_PORT", startsInCamera: false)
        let warning = app.descendants(matching: .any)["facilityQueueUpdate"].firstMatch
        let arrivals = "T3 · Arrivals"
        assertReplay("Follow signs to immigration", location: arrivals)
        assertCheckpointUsesMap(showsApproach: true)
        XCTAssertFalse(warning.exists)

        print("ARRIVALS_VIDEO_BEGIN \(Date().timeIntervalSince1970)")
        snapshot("arrivals-immigration-normal")
        try replayControl("facility-queue-long", port: port)
        XCTAssertTrue(warning.waitForExistence(timeout: 4))
        XCTAssertTrue(warning.label.contains("Immigration queue"))
        XCTAssertTrue(warning.label.contains("18 minutes"))
        snapshot("arrivals-immigration-queue")

        try replayControl("next", port: port)
        assertReplay("Follow signs to immigration", location: arrivals)
        assertCheckpointUsesMap(showsApproach: false)
        XCTAssertTrue(warning.label.contains("Immigration queue"))
        snapshot("arrivals-immigration-inside")

        try replayControl("next", port: port)
        assertReplay("Wait for immigration clearance", location: arrivals)
        assertCheckpointUsesMap(showsApproach: false)
        XCTAssertTrue(warning.label.contains("Immigration queue"))
        XCTAssertFalse(app.buttons["endRoute"].exists)
        snapshot("arrivals-immigration-hold")

        try replayControl("next", port: port)
        assertReplay("Collect your checked bags", location: arrivals)
        assertCheckpointUsesMap(showsApproach: false)
        XCTAssertFalse(warning.exists)
        snapshot("arrivals-baggage-claim")

        try replayControl("next", port: port)
        assertReplay("Follow signs to customs", location: arrivals)
        assertCheckpointUsesMap(showsApproach: true)
        XCTAssertTrue(warning.waitForExistence(timeout: 4))
        XCTAssertTrue(warning.label.contains("Customs queue"))
        XCTAssertTrue(warning.label.contains("6 minutes"))
        snapshot("arrivals-customs-queue")

        try replayControl("next", port: port)
        assertReplay("Follow signs to customs", location: arrivals)
        assertCheckpointUsesMap(showsApproach: false)
        XCTAssertTrue(warning.label.contains("Customs queue"))
        snapshot("arrivals-customs-inside")

        try replayControl("next", port: port)
        assertReplay("Wait for customs clearance", location: arrivals)
        assertCheckpointUsesMap(showsApproach: false)
        XCTAssertTrue(warning.label.contains("Customs queue"))
        XCTAssertFalse(app.buttons["endRoute"].exists)
        snapshot("arrivals-customs-hold")

        try replayControl("next", port: port)
        assertReplay("Continue to the arrivals hall", location: "T3 · 2F · Landside")
        XCTAssertTrue(app.buttons["mode-map"].isSelected)
        XCTAssertFalse(warning.exists)
        snapshot("arrivals-landside-map")

        let camera = app.buttons["mode-camera"]
        XCTAssertTrue(camera.isEnabled)
        camera.tap()
        XCTAssertTrue(camera.isSelected)
        assertReplay("Continue to the arrivals hall", location: "T3 · 2F · Landside")
        XCTAssertTrue(app.buttons["endRoute"].exists)
        snapshot("arrivals-landside-camera")
        print("ARRIVALS_VIDEO_END \(Date().timeIntervalSince1970)")
    }

    func testHanedaReplayHoldsForAFullShuttleAndAnUnavailableLift() throws {
        let port = try openTerminalReplay(route: "observation-deck", portKey: "REPLAY_DECK_PORT")
        try replayControl("next-landmark", port: port)
        assertReplay("Board at Stop 0", location: "T3 · 1F · Landside")
        try replayControl("full-shuttle", port: port)
        assertReplay("This shuttle is full. Wait for the next one.", location: "T3 · 1F · Landside")
        XCTAssertFalse(app.buttons["endRoute"].exists)
        try replayControl("next-landmark", port: port)
        assertReplay("This shuttle is full. Wait for the next one.", location: "T3 · 1F · Landside")
        snapshot("haneda-full-shuttle")
        try replayControl("shuttle-space", port: port)
        assertReplay("Board at Stop 0", location: "T3 · 1F · Landside")
        for _ in 0..<3 { try replayControl("next-landmark", port: port) }
        assertReplay("Take the lift to 5F", location: "T2 · 1F · Landside")
        try replayControl("lift-outage", port: port)
        assertReplay("Lift unavailable. Ask airport staff for a step-free route.", location: "T2 · 1F · Landside")
        XCTAssertFalse(app.buttons["endRoute"].exists)
        try replayControl("next-landmark", port: port)
        assertReplay("Lift unavailable. Ask airport staff for a step-free route.", location: "T2 · 1F · Landside")
        snapshot("haneda-lift-outage")
        try replayControl("lift-open", port: port)
        assertReplay("Take the lift to 5F", location: "T2 · 1F · Landside")
        try replayControl("next-landmark", port: port)
        assertReplay("Return to Terminal 3", location: "T2 · 5F · Landside")
    }

    func testHanedaReplayNaritaBusRemainsLandside() throws {
        let port = try openTerminalReplay(route: "narita", portKey: "REPLAY_NARITA_PORT")
        assertReplay("Go down to the buses on 1F", location: "T3 · 2F · Landside")
        XCTAssertTrue(app.staticTexts["Bus to Narita"].exists)
        try replayControl("next-landmark", port: port)
        assertReplay("Follow signs to Stop 5", location: "T3 · 1F · Landside")
        try replayControl("next-landmark", port: port)
        assertReplay("Board the Narita bus", location: "T3 · 1F · Landside")
        snapshot("haneda-narita-coach")
        app.buttons["endRoute"].tap()
        XCTAssertTrue(app.staticTexts["Route to Narita"].waitForExistence(timeout: 3))
    }

    func testHanedaReplayKeikyuPlatformMovesAndTurns() throws {
        let port = try openTerminalReplay(route: "narita-rail", portKey: "REPLAY_RAIL_PORT")
        assertReplay("Follow the Keikyu Line signs", location: "T3 · Landside")
        XCTAssertTrue(app.staticTexts["Train to Narita"].exists)
        snapshot("haneda-rail-gates")

        try replayControl("next-landmark", port: port)
        assertReplay("Take the lift down to the platform", location: "T3 · Landside")
        snapshot("haneda-rail-lift")
        try replayControl("next-landmark", port: port)
        assertReplay("Head to the platform", location: "T3 · Landside")
        snapshot("haneda-rail-approach")
        try replayControl("next-landmark", port: port)
        assertReplay("Walk to the boarding point", location: "T3 · Landside")
        for _ in 0..<3 { try replayControl("next", port: port) }
        Thread.sleep(forTimeInterval: 0.55)
        snapshot("haneda-rail-position")

        // The final sample changes heading from 13 to 51 degrees at identical coordinates.
        try replayControl("next", port: port)
        assertReplay("Check for Narita Airport", location: "T3 · Landside")
        Thread.sleep(forTimeInterval: 0.40)
        snapshot("haneda-rail-heading")
        app.buttons["endRoute"].tap()
        XCTAssertTrue(app.staticTexts["Route to Narita"].waitForExistence(timeout: 3))
    }

    private func openTerminalReplay(route: String, portKey: String, startsInCamera: Bool = true) throws -> String {
        guard let port = ProcessInfo.processInfo.environment[portKey], Int(port) != nil else {
            throw XCTSkip("Run through Scripts/run-terminal-replay-ui-tests.sh.")
        }
        try replayControl("reset", port: port)
        app.terminate()
        app.launchArguments += [
            "--uitesting", "--qa-indoor-feed", "http://127.0.0.1:\(port)/reading", "--qa-terminal-route", route
        ]
        app.launch()
        app.tabBars.buttons["Route"].tap()
        let button = app.buttons["mode-camera"]
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        if startsInCamera { button.tap() }
        assertContinuousGuidance()
        return port
    }

    private func assertCheckpointUsesMap(showsApproach: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let map = app.buttons["mode-map"]
        let camera = app.buttons["mode-camera"]
        let approach = app.descendants(matching: .any)["checkpointApproachOverview"].firstMatch
        if showsApproach {
            XCTAssertTrue(approach.waitForExistence(timeout: 4), file: file, line: line)
        } else {
            XCTAssertTrue(approach.waitForNonExistence(timeout: 4), file: file, line: line)
        }
        XCTAssertTrue(map.isSelected, file: file, line: line)
        XCTAssertTrue(camera.exists, file: file, line: line)
        XCTAssertFalse(camera.isSelected, file: file, line: line)
        XCTAssertFalse(camera.isEnabled, file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any)["cameraPrompt"].firstMatch.exists, file: file, line: line)
        XCTAssertFalse(app.buttons["routeVoiceToggle"].exists, file: file, line: line)
        for label in ["Approach overview", "Use the lane staff direct you to."] {
            XCTAssertFalse(app.staticTexts[label].exists, file: file, line: line)
        }
    }

    private func assertContinuousGuidance(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(app.buttons["mode-replay"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["replayNext"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["replayPrevious"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["nextStep"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["previousStep"].exists, file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any)["routeProgress"].firstMatch.exists, file: file, line: line)
    }

    private func assertReplay(_ instruction: String, location: String, file: StaticString = #filePath, line: UInt = #line) {
        let message = app.staticTexts["routeInstruction"]
        let badge = app.descendants(matching: .any)["guidanceLocation"]
        let reading = NSPredicate { _, _ in message.label == instruction && badge.label == location }
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reading, object: nil)], timeout: 4)
        XCTAssertEqual(outcome, .completed, "Expected \(instruction) at \(location); got \(message.label) at \(badge.label)",
                       file: file, line: line)
    }

    func testJourneyDetailsCheckpointOpensJourneySteps() {
        app.buttons["journeyDetailsLink"].tap()
        let progress = app.descendants(matching: .any)["journeyProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 2))
        XCTAssertEqual(progress.label, "Step 3 of 5, Security")
        app.buttons["checkpointLine"].tap()
        XCTAssertTrue(app.staticTexts["Journey steps"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Haneda connection, Step 3 of 5"].exists)
        app.buttons["confirm-security"].tap()
        XCTAssertTrue(app.buttons["undo-security"].exists)
        XCTAssertTrue(app.buttons["skip-passport"].exists)
        app.buttons["back"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["journeyProgress"].label, "Step 4 of 5, Passport control")
    }

    func testPlanCardAddsStopsAndEditsTimes() {
        let addStop = app.buttons["addStop"]
        XCTAssertTrue(addStop.waitForExistence(timeout: 5))
        addStop.tap()
        app.buttons["add-cafe"].tap()
        app.buttons["add-anaLounge"].tap()
        app.tabBars.buttons["Flight"].tap()
        XCTAssertTrue(app.buttons["lane-cafe"].waitForExistence(timeout: 2))
        XCTAssertFalse(addStop.exists)
        let timing = app.staticTexts["planGateTiming"]
        XCTAssertEqual(timing.label, "Estimated gate arrival 17:15")
        app.swipeUp()
        app.buttons["lane-anaLounge"].tap()
        snapshot("plan-card-open")
        let earlierLeave = app.buttons["Leave earlier"]
        if !earlierLeave.isHittable { app.swipeUp() }
        earlierLeave.tap()
        XCTAssertEqual(timing.label, "Estimated gate arrival 17:04")
        app.buttons["remove-anaLounge"].tap()
        XCTAssertTrue(app.buttons["lane-anaLounge"].waitForNonExistence(timeout: 2))
        let undo = app.buttons["toast"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertTrue(undo.label.contains("Removed ANA LOUNGE"))
        undo.tap()
        XCTAssertTrue(app.buttons["lane-anaLounge"].waitForExistence(timeout: 2))
        XCTAssertEqual(timing.label, "Estimated gate arrival 17:04", "Undo preserves the edited visit")
    }

    func testCafeWaitCanBeKeptAppliedAndUndone() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["add-anaLounge"].tap()
        app.tabBars.buttons["Flight"].tap()
        app.swipeUp()
        let suggestion = app.descendants(matching: .any)["cafeWaitSuggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 3))
        XCTAssertTrue(suggestion.label.contains("Shorten ANA LOUNGE to 18 min"))
        let timing = app.staticTexts["planGateTiming"]
        XCTAssertEqual(timing.label, "Estimated gate arrival 17:15")
        snapshot("cafe-wait-proposal")
        app.buttons["applySuggestion"].tap()
        XCTAssertEqual(timing.label, "Estimated gate arrival 17:05")
        let undo = app.buttons["toast"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.tap()
        XCTAssertTrue(suggestion.waitForExistence(timeout: 2))
        XCTAssertEqual(timing.label, "Estimated gate arrival 17:15")
        app.buttons["keepSuggestion"].tap()
        XCTAssertTrue(suggestion.waitForNonExistence(timeout: 2))
        XCTAssertEqual(timing.label, "Estimated gate arrival 17:15")
    }

    func testRouteStepsEndReturnsToFlight() {
        app.tabBars.buttons["Route"].tap()
        XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].waitForExistence(timeout: 2))
        for _ in 0 ..< 4 { app.buttons["nextStep"].tap() }
        XCTAssertTrue(app.staticTexts["Check NH 106 on the gate screen"].exists)
        app.buttons["endRoute"].tap()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 2))
    }

    func testRouteChoiceAndRouteThroughStops() {
        app.tabBars.buttons["Route"].tap()
        XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].waitForExistence(timeout: 2))
        snapshot("route-direct")
        app.buttons["routeChoice"].tap()
        XCTAssertTrue(app.buttons["use-stepFree"].waitForExistence(timeout: 2))
        snapshot("route-menu")
        app.buttons["use-stepFree"].tap()
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.staticTexts["Turn right to the lift"].waitForExistence(timeout: 2))

        app.tabBars.buttons["Layover"].tap()
        XCTAssertFalse(app.buttons["planBar"].exists, "No plan bar while the plan is empty")
        app.buttons["add-cafe"].tap()
        XCTAssertTrue(app.buttons["add-cafe"].label.contains("Remove"))
        let bar = app.buttons["planBar"]
        XCTAssertTrue(bar.waitForExistence(timeout: 2))
        XCTAssertTrue(bar.label.contains("1 stop"))
        snapshot("layover-plan")
        bar.tap()
        app.buttons["routeButton"].tap()
        XCTAssertTrue(app.staticTexts["Follow the signs to Curacion Cafe"].waitForExistence(timeout: 2))
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.staticTexts["Stop at Curacion Cafe, leave by 16:38"].exists, "Uses the leave time from the plan")
        snapshot("route-via-cafe")
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func replayControl(_ command: String, port: String) throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/control/\(command)")!)
        request.httpMethod = "POST"
        let done = expectation(description: "replay control \(command)")
        var statusCode = 0
        URLSession.shared.dataTask(with: request) { _, response, _ in
            statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 2)
        XCTAssertEqual(statusCode, 200)
    }

    private func waitForOfficialWalkPosition(_ value: String) {
        let map = app.descendants(matching: .any)["officialGateWalkMap"].firstMatch
        let predicate = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND value == %@", value), object: map
        )
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 10), .completed)
    }

    func testOfficialGateWalkFollowsConfirmedPositions() throws {
        guard let port = ProcessInfo.processInfo.environment["OFFICIAL_WALK_PORT"] else {
            throw XCTSkip("Run with the Haneda Gate 105 position driver")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "105"])
        app.tabBars.buttons["Route"].tap()
        waitForOfficialWalkPosition("0% of route")
        assertContinuousGuidance()
        snapshot("official-walk-start")
        try replayControl("next", port: port)
        waitForOfficialWalkPosition("Position unavailable")
        XCTAssertTrue(app.staticTexts["Position unavailable"].exists)
        assertContinuousGuidance()
        XCTAssertFalse(app.buttons["endRoute"].exists)
        snapshot("official-walk-floor-unconfirmed")

        try replayControl("next", port: port)
        waitForOfficialWalkPosition("14% of route")
        snapshot("official-walk-near-108A")
        try replayControl("next", port: port)
        waitForOfficialWalkPosition("28% of route")
        for _ in 0..<8 { try replayControl("next", port: port) }
        waitForOfficialWalkPosition("81% of route")
        snapshot("official-walk-near-105")
        try replayControl("next", port: port)
        try replayControl("next", port: port)
        waitForOfficialWalkPosition("100% of route")
        XCTAssertTrue(app.buttons["endRoute"].exists)
        XCTAssertTrue(app.staticTexts["Check your flight at Gate 105"].exists)
        snapshot("official-walk-at-105")
    }

    func testOfficialGate108AWalkPlaysFromDriverClock() throws {
        guard let port = ProcessInfo.processInfo.environment["OFFICIAL_WALK_108A_PORT"],
              let airportPort = ProcessInfo.processInfo.environment["AIRPORT_PROVIDER_PORT"] else {
            throw XCTSkip("Run with the Gate 108A position and airport drivers")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        try replayControl("current-gate", port: airportPort)
        try replayControl("gate/108A", port: airportPort)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "108A",
                  "--qa-airport-provider", "http://127.0.0.1:\(airportPort)/v1/assignment"])
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertRoute"].tap()
        waitForOfficialWalkPosition("0% of route")
        assertContinuousGuidance()
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts["Continue to Gate 108A"].waitForExistence(timeout: 4))
        assertContinuousGuidance()
        try replayControl("resume", port: port)
        XCTAssertTrue(app.staticTexts["Check your flight at Gate 108A"].waitForExistence(timeout: 10))
        app.buttons["mode-map"].tap()
        waitForOfficialWalkPosition("100% of route")
        snapshot("official-walk-at-108A")
    }

    func testRouteVoiceStartsFromAnAccessibleControlAndCanBeStopped() {
        if let port = ProcessInfo.processInfo.environment["ROUTE_SPEECH_PORT"] {
            relaunch(["--uitesting", "--qa-route-speech-port", port])
        }
        app.tabBars.buttons["Route"].tap()
        let talk = app.buttons["routeVoiceToggle"]
        XCTAssertTrue(talk.waitForExistence(timeout: 4))
        XCTAssertEqual(talk.label, "Talk")
        XCTAssertGreaterThanOrEqual(talk.frame.height, 44)
        talk.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            let allow = springboard.alerts.buttons["Allow"].firstMatch
            let ok = springboard.alerts.buttons["OK"].firstMatch
            if allow.waitForExistence(timeout: 0.7) { allow.tap() }
            else if ok.exists { ok.tap() }
        }
        let status = app.staticTexts["routeVoiceStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        if talk.label == "Stop" {
            // A live microphone can receive speech before the test reads the status.
            XCTAssertFalse(status.label.isEmpty)
            XCTAssertTrue(talk.isHittable)
            XCTAssertLessThanOrEqual(talk.frame.maxY, app.tabBars.firstMatch.frame.minY)
            snapshot("route-voice-active")
            talk.tap()
            XCTAssertEqual(talk.label, "Talk")
            XCTAssertFalse(status.exists)
        } else {
            XCTAssertTrue(["Voice is unavailable on this device.", "Microphone unavailable.",
                           "Allow microphone access in Settings to talk.", "Allow speech access in Settings to talk.",
                           "Couldn’t hear you. Tap Talk to try again."].contains(status.label),
                          status.label)
            XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].exists)
            let tabBar = app.tabBars.firstMatch
            if !talk.isHittable || talk.frame.maxY > tabBar.frame.minY {
                app.swipeUp()
            }
            XCTAssertTrue(talk.isHittable)
            snapshot("route-voice-unavailable")
        }
    }

    func testRouteVoiceRecognizesRecordedSpeechLocallyAndAnswers() throws {
        guard let fixture = ProcessInfo.processInfo.environment["ROUTE_SPEECH_FIXTURE"],
              let port = ProcessInfo.processInfo.environment["ROUTE_SPEECH_PORT"] else {
            throw XCTSkip("Run with the Mac dictation driver and a local ‘Which gate?’ WAV")
        }
        app.launchEnvironment["AIRBORDER_ROUTE_SPEECH_FIXTURE"] = fixture
        relaunch(["--uitesting", "--qa-route-speech-port", port])
        app.tabBars.buttons["Route"].tap()
        app.buttons["routeVoiceToggle"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 1) { allow.tap() }
        let status = app.staticTexts["routeVoiceStatus"]
        let answer = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", "Gate 105."), object: status
        )
        XCTAssertEqual(XCTWaiter.wait(for: [answer], timeout: 8), .completed,
                       status.exists ? status.label : "Voice status unavailable")
        let stop = app.buttons["routeVoiceToggle"]
        let tabBar = app.tabBars.firstMatch
        let unobscured = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            stop.exists && stop.label == "Stop" && stop.isHittable && stop.frame.maxY <= tabBar.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [unobscured], timeout: 3), .completed,
                       "Stop must be fully above the tab bar after an answer appears")
        snapshot("route-voice-answers-gate")
        stop.tap()
        XCTAssertEqual(stop.label, "Talk")
        XCTAssertFalse(status.exists)
    }

    func testAdaptiveHanedaWalkReroutesAndSharesItsPositionWithCamera() throws {
        guard let port = ProcessInfo.processInfo.environment["ADAPTIVE_WALK_PORT"],
              let airportPort = ProcessInfo.processInfo.environment["AIRPORT_PROVIDER_PORT"] else {
            throw XCTSkip("Run with the adaptive Haneda walk and airport drivers")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        try replayControl("current-gate", port: airportPort)
        try replayControl("gate/105", port: airportPort)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "adaptive",
                  "--qa-airport-provider", "http://127.0.0.1:\(airportPort)/v1/assignment"])
        app.tabBars.buttons["Route"].tap()
        waitForOfficialWalkPosition("0% of route")
        for _ in 0..<11 { try replayControl("next", port: port) }
        waitForOfficialWalkPosition("81% of route")
        snapshot("adaptive-walk-before-gate-change")
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts["Continue to Gate 105"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["3F"].exists)
        assertContinuousGuidance()
        Thread.sleep(forTimeInterval: 0.8)
        snapshot("adaptive-walk-first-person")

        try replayControl("gate/108A", port: airportPort)
        XCTAssertTrue(app.buttons["alertRoute"].waitForExistence(timeout: 6))
        app.buttons["alertRoute"].tap()
        XCTAssertTrue(app.staticTexts["Turn back along the concourse"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mode-camera"].isSelected)
        snapshot("adaptive-walk-camera-uturn")
        app.buttons["mode-map"].tap()
        waitForOfficialWalkPosition("0% of route")
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].exists)
        XCTAssertTrue(app.staticTexts["Turn back along the concourse"].exists)
        assertContinuousGuidance()
        snapshot("adaptive-walk-reassigned")
        try replayControl("stale-gate", port: airportPort)
        try replayControl("stale-reading", port: port)
        waitForOfficialWalkPosition("Position unavailable")
        XCTAssertFalse(app.buttons["endRoute"].exists)
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].exists)
        try replayControl("conflicting-gate", port: airportPort)
        try replayControl("drop-reading", port: port)
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts["Position unavailable"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Last confirmed floor 3F"].exists)
        XCTAssertFalse(app.buttons["endRoute"].exists)
        assertContinuousGuidance()
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].exists)
        try replayControl("current-gate", port: airportPort)
        try replayControl("restore-reading", port: port)
        XCTAssertTrue(app.staticTexts["Turn back along the concourse"].waitForExistence(timeout: 4))
        try replayControl("next", port: port)
        XCTAssertTrue(app.staticTexts["Continue to Gate 108A"].waitForExistence(timeout: 4))
        Thread.sleep(forTimeInterval: 0.6)
        snapshot("adaptive-walk-first-person-after-turn")
        app.buttons["mode-map"].tap()
        let map = app.descendants(matching: .any)["officialGateWalkMap"].firstMatch
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let progress = map.value as? String else { return false }
            return progress.hasSuffix("% of route") && progress != "0% of route"
        }, object: nil)
        // The first reversed leg must move the shared map point off the reroute origin.
        XCTAssertTrue(map.waitForExistence(timeout: 4))
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 3), .completed, "\(map.value ?? "")")
        for _ in 0..<14 { try replayControl("next", port: port) }
        waitForOfficialWalkPosition("100% of route")
        XCTAssertTrue(app.staticTexts["Check your flight at Gate 108A"].exists)
        snapshot("adaptive-walk-at-108a")
    }

    func testContinuousCafeWalkRecoversLandmarkAndKeepsPoseAtGateChange() throws {
        guard let port = ProcessInfo.processInfo.environment["CAFE_WALK_PORT"],
              let airportPort = ProcessInfo.processInfo.environment["AIRPORT_PROVIDER_PORT"] else {
            throw XCTSkip("Run with the café walk driver and airport provider")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        for control in ["network-on", "feed-on", "current-gate", "gate/105", "planning-clear",
                        "planning-flight-on-time", "planning-refresh"] {
            try replayControl(control, port: airportPort)
        }
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "cafe",
                  "--qa-verify-route-pose", "--qa-airport-provider",
                  "http://127.0.0.1:\(airportPort)/v1/assignment"])
        app.tabBars.buttons["Layover"].tap()
        let review = app.buttons["reviewCafeOffer"]
        XCTAssertTrue(review.waitForExistence(timeout: 6))
        review.tap()
        app.buttons["addReviewedCafe"].tap()
        XCTAssertTrue(app.buttons["planBar"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Route"].tap()
        let instruction = app.staticTexts["routeInstruction"]
        let finish = app.buttons["finishCafeStop"]
        let confirm = app.buttons["confirmCafeLandmark"]
        func pose() throws -> String { try XCTUnwrap(instruction.value as? String) }

        XCTAssertTrue(app.staticTexts["Walk to Curacion Cafe"].waitForExistence(timeout: 5))
        waitForOfficialWalkPosition("0% of route")
        let start = try pose()
        snapshot("cafe-walk-start-map")
        print("AIRBORDER_WALK_BEGIN \(Date().timeIntervalSince1970)")
        try replayControl("resume", port: port)
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        XCTAssertNotEqual(try pose(), start)
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 4))
        let cafe = try pose()
        try replayControl("misread-landmark", port: port)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(try pose(), cafe, "The wrong same-floor position cannot move Camera")
        snapshot("cafe-walk-landmark-camera")
        app.buttons["landmarkUseMap"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        XCTAssertEqual(try pose(), cafe, "Map holds at the same confirmed coordinate")
        snapshot("cafe-walk-landmark-map")
        confirm.tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertEqual(try pose(), cafe)
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 4))
        snapshot("cafe-walk-confirmed-stop")
        finish.tap()
        XCTAssertTrue(app.staticTexts["Continue to Gate 105"].waitForExistence(timeout: 4))

        // Let the clock carry the traveler beyond the concourse split without manually stepping.
        let pastSplit = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let x = (instruction.value as? String)?.split(separator: ",").first.flatMap { Double($0) }
            return (x ?? 0) >= 0.83
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [pastSplit], timeout: 40), .completed)
        try replayControl("pause", port: port)
        app.buttons["mode-map"].tap()
        let before = try pose()
        XCTAssertNotEqual(before, cafe)
        snapshot("cafe-walk-map-before-reroute")
        app.buttons["mode-camera"].tap()
        XCTAssertEqual(try pose(), before)
        snapshot("cafe-walk-camera-before-reroute")

        try replayControl("gate/108A", port: airportPort)
        let alert = app.buttons["alertRoute"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        alert.tap()
        XCTAssertTrue(app.staticTexts["Turn back along the concourse"].waitForExistence(timeout: 6))
        XCTAssertEqual(try pose(), before, "The gate revision must not move or turn Camera")
        snapshot("cafe-walk-camera-after-reroute")
        app.buttons["mode-map"].tap()
        waitForOfficialWalkPosition("0% of route")
        XCTAssertEqual(try pose(), before, "The new map route starts at the identical pose")
        snapshot("cafe-walk-map-after-reroute")
        try replayControl("resume", port: port)
        XCTAssertTrue(app.staticTexts["Check your flight at Gate 108A"].waitForExistence(timeout: 18))
        XCTAssertTrue(app.buttons["endRoute"].exists)
        snapshot("cafe-walk-at-gate-108a")
        if ProcessInfo.processInfo.environment["RECORD_CAFE_WALK"] == "1" {
            // Hold the arrival frame long enough to read before XCTest terminates the app.
            Thread.sleep(forTimeInterval: 2.5)
        }
        print("AIRBORDER_WALK_END \(Date().timeIntervalSince1970)")
    }

    func testAdaptiveHanedaCrowdExposesAQuieterConcourseOption() throws {
        guard let port = ProcessInfo.processInfo.environment["ADAPTIVE_WALK_PORT"] else {
            throw XCTSkip("Run with the adaptive Haneda walk driver")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "adaptive"])
        app.tabBars.buttons["Route"].tap()
        waitForOfficialWalkPosition("0% of route")
        app.buttons["routeChoice"].tap()
        XCTAssertFalse(app.buttons["use-lessCrowded"].exists)
        app.buttons["use-stepFree"].tap()
        waitForOfficialWalkPosition("0% of route")
        try replayControl("crowd-on", port: port)
        app.buttons["routeChoice"].tap()
        let quieter = app.buttons["use-lessCrowded"]
        XCTAssertTrue(quieter.waitForExistence(timeout: 4))
        quieter.tap()
        waitForOfficialWalkPosition("0% of route")
        XCTAssertTrue(app.buttons["routeChoice"].label.contains("Less crowded"))
        snapshot("adaptive-walk-quieter-concourse")
    }

    func testCrowdReportAffectsOnlyTheRouteThroughTheConcourseStrip() throws {
        guard let port = ProcessInfo.processInfo.environment["ADAPTIVE_WALK_PORT"] else {
            throw XCTSkip("Run with the adaptive Haneda walk driver")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "adaptive", "--qa-verify-route-pose"])
        app.tabBars.buttons["Route"].tap()
        waitForOfficialWalkPosition("0% of route")
        let update = app.descendants(matching: .any)["routeCrowdingUpdate"].firstMatch
        let instruction = app.staticTexts["routeInstruction"]
        let start = try XCTUnwrap(instruction.value as? String)
        XCTAssertFalse(update.exists)

        func waitForUpdate(_ copy: String) {
            let visible = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", copy), object: update
            )
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed, "Expected \(copy)")
        }

        try replayControl("crowd-on", port: port)
        waitForUpdate("Crowding ahead")
        XCTAssertTrue(update.label.contains("About 3 minutes longer"))
        XCTAssertEqual(instruction.value as? String, start)
        snapshot("crowd-on-direct-map")
        app.buttons["mode-camera"].tap()
        waitForUpdate("Crowding ahead")
        XCTAssertTrue(update.label.contains("About 3 minutes longer"))
        XCTAssertEqual(instruction.value as? String, start)
        snapshot("crowd-on-direct-camera")

        try replayControl("crowd-expire", port: port)
        waitForUpdate("Crowding update unavailable")
        XCTAssertFalse(update.label.contains("minutes longer"))
        XCTAssertEqual(instruction.value as? String, start)
        snapshot("crowd-expired-direct-camera")

        try replayControl("crowd-on", port: port)
        app.buttons["mode-map"].tap()
        waitForUpdate("Crowding ahead")
        app.buttons["routeChoice"].tap()
        let alternative = app.buttons["use-lessCrowded"]
        XCTAssertTrue(alternative.waitForExistence(timeout: 4))
        alternative.tap()
        XCTAssertTrue(update.waitForNonExistence(timeout: 4))
        waitForOfficialWalkPosition("0% of route")
        XCTAssertTrue(app.buttons["routeChoice"].label.contains("Less crowded"))
        let bypassPose = try XCTUnwrap(instruction.value as? String)

        try replayControl("crowd-off", port: port)
        snapshot("crowd-bypass-before")
        try replayControl("crowd-on", port: port)
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: update)
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 1.5), .timedOut)
        XCTAssertEqual(instruction.value as? String, bypassPose)
        snapshot("crowd-bypass-after")
        app.buttons["mode-camera"].tap()
        XCTAssertFalse(update.exists)
        XCTAssertEqual(instruction.value as? String, bypassPose)
        snapshot("crowd-on-bypass-camera")
    }

    func testBlockedJunctionReroutesInPlaceAndLeavesTheExistingBypassUnchanged() throws {
        guard let port = ProcessInfo.processInfo.environment["JUNCTION_WALK_PORT"] else {
            throw XCTSkip("Run with the adaptive Haneda walk starting at the junction")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "adaptive", "--qa-verify-route-pose"])
        app.tabBars.buttons["Route"].tap()
        waitForOfficialWalkPosition("0% of route")
        let update = app.descendants(matching: .any)["routeClosureUpdate"].firstMatch
        let instruction = app.staticTexts["routeInstruction"]
        let leftTurn = "Turn left onto the side passage"
        func pose() throws -> String { try XCTUnwrap(instruction.value as? String) }
        let before = try pose()
        XCTAssertEqual(instruction.label, "Continue to Gate 105")
        XCTAssertFalse(update.exists)
        snapshot("junction-direct-before")
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts["Continue to Gate 105"].waitForExistence(timeout: 4))
        XCTAssertEqual(try pose(), before)
        snapshot("junction-direct-camera-before")

        try replayControl("passage-blocked", port: port)
        XCTAssertTrue(update.waitForExistence(timeout: 5))
        XCTAssertTrue(update.label.contains("Passage blocked"))
        XCTAssertTrue(app.staticTexts[leftTurn].waitForExistence(timeout: 5))
        XCTAssertEqual(try pose(), before, "Camera keeps the same point and heading while the path changes")
        snapshot("junction-detour-camera")
        app.buttons["mode-map"].tap()
        waitForOfficialWalkPosition("0% of route")
        XCTAssertTrue(app.staticTexts[leftTurn].waitForExistence(timeout: 4))
        XCTAssertEqual(try pose(), before, "Map starts the detour at the exact same pose")
        snapshot("junction-detour-map")
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts[leftTurn].waitForExistence(timeout: 4))
        XCTAssertEqual(try pose(), before)
        try replayControl("next", port: port)
        XCTAssertTrue(app.staticTexts["Continue along the side passage"].waitForExistence(timeout: 5))
        let moved = try pose().split(separator: ",")
        let initial = before.split(separator: ",")
        XCTAssertEqual(moved[0], initial[0])
        XCTAssertLessThan(try XCTUnwrap(Double(moved[1])), try XCTUnwrap(Double(initial[1])))
        XCTAssertEqual(try XCTUnwrap(Double(moved[2])), 45, accuracy: 0.01)
        snapshot("junction-camera-turning-left")
        try replayControl("next", port: port)
        try replayControl("next", port: port)
        let inside = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = instruction.value as? String,
                  let x = value.split(separator: ",").first.flatMap({ Double($0) }) else { return false }
            return x > 0.15
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [inside], timeout: 5), .completed)
        snapshot("junction-camera-inside-side-passage")
        app.buttons["mode-map"].tap()

        try replayControl("reset", port: port)
        waitForOfficialWalkPosition("0% of route")
        try replayControl("crowd-on", port: port)
        let crowd = app.descendants(matching: .any)["routeCrowdingUpdate"].firstMatch
        XCTAssertTrue(crowd.waitForExistence(timeout: 5))
        app.buttons["routeChoice"].tap()
        app.buttons["use-lessCrowded"].tap()
        waitForOfficialWalkPosition("0% of route")
        XCTAssertTrue(app.staticTexts[leftTurn].waitForExistence(timeout: 4))
        let bypassPose = try pose()
        XCTAssertEqual(bypassPose, before)
        try replayControl("crowd-off", port: port)
        snapshot("junction-bypass-before")
        try replayControl("passage-blocked", port: port)
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: update)
        XCTAssertEqual(XCTWaiter.wait(for: [unexpected], timeout: 1.5), .timedOut)
        XCTAssertEqual(try pose(), bypassPose)
        XCTAssertEqual(instruction.label, leftTurn)
        snapshot("junction-bypass-after")
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts[leftTurn].waitForExistence(timeout: 4))
        XCTAssertFalse(update.exists)
        XCTAssertEqual(try pose(), bypassPose)
        snapshot("junction-bypass-camera")
    }

    func testPedestriansCrossWithoutChangingTheLeftTurnOrTravelerPosition() throws {
        guard let port = ProcessInfo.processInfo.environment["PEDESTRIAN_WALK_PORT"] else {
            throw XCTSkip("Run with the independent Haneda pedestrian crossing enabled")
        }
        try replayControl("pause", port: port)
        try replayControl("reset", port: port)
        try replayControl("passage-blocked", port: port)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-indoor-feed",
                  "http://127.0.0.1:\(port)/reading", "--qa-official-walk", "adaptive", "--qa-verify-route-pose"])
        app.tabBars.buttons["Route"].tap()
        waitForOfficialWalkPosition("0% of route")
        let instruction = app.staticTexts["routeInstruction"]
        let leftTurn = "Turn left onto the side passage"
        XCTAssertTrue(app.staticTexts[leftTurn].waitForExistence(timeout: 5))
        let initialPose = try XCTUnwrap(instruction.value as? String)

        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts[leftTurn].waitForExistence(timeout: 5))
        XCTAssertEqual(instruction.value as? String, initialPose)
        let crowd = app.descendants(matching: .any)["routeCrowdingUpdate"].firstMatch
        XCTAssertFalse(crowd.exists)
        snapshot("pedestrians-entrance-visible")
        print("OCCLUSION_VIDEO_BEGIN \(Date().timeIntervalSince1970)")
        try replayControl("pedestrians-cross", port: port)
        print("OCCLUSION_CROSSING_START \(Date().timeIntervalSince1970)")

        // The independent crossing lasts 4.8 seconds. Check guidance while it moves,
        // then again after it clears. The recording captures the scene between checks.
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ OR value != %@",
                                                                       leftTurn, initialPose), object: instruction)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 6), .timedOut)
        XCTAssertFalse(crowd.exists)
        snapshot("pedestrians-entrance-visible-again")
        print("OCCLUSION_VIDEO_END \(Date().timeIntervalSince1970)")
        app.buttons["mode-map"].tap()
        waitForOfficialWalkPosition("0% of route")
        XCTAssertEqual(instruction.label, leftTurn)
        XCTAssertEqual(instruction.value as? String, initialPose)
        XCTAssertFalse(crowd.exists)
    }

    func testAirportProviderGateMapHandoffAndRouteContinuity() throws {
        guard let port = ProcessInfo.processInfo.environment["AIRPORT_PROVIDER_PORT"] else {
            throw XCTSkip("Run with the airport provider driver to exercise the handoff")
        }
        try replayControl("feed-on", port: port)
        try replayControl("gate/105", port: port)
        try replayControl("map-on", port: port)
        relaunch(["-gateUpdate", "off", "--uitesting", "--qa-airport-provider",
                  "http://127.0.0.1:\(port)/v1/assignment"])

        app.tabBars.buttons["Route"].tap()
        app.buttons["routeChoice"].tap()
        app.buttons["use-stepFree"].tap()
        app.buttons["nextStep"].tap()
        let lift = app.staticTexts["Turn right to the lift"]
        XCTAssertTrue(lift.waitForExistence(timeout: 3))
        let map = app.descendants(matching: .any)["routeSummary"]
        map.tap()
        let handoff = app.buttons["Open gate map"]
        XCTAssertTrue(handoff.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Gate 105"].exists)
        snapshot("provider-route-sheet")
        handoff.tap()

        let gateMap = app.webViews.firstMatch
        XCTAssertTrue(gateMap.staticTexts["Gate 105"].waitForExistence(timeout: 10))
        if ProcessInfo.processInfo.environment["AIRPORT_PROVIDER_OFFICIAL_MAP"] == "1" {
            XCTAssertTrue(gateMap.images["Haneda Terminal 3 departure gates"].waitForExistence(timeout: 12))
        }
        XCTAssertEqual(app.state, .runningForeground)
        snapshot("provider-in-app-gate-105")
        app.buttons["Done"].tap()
        XCTAssertTrue(lift.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["routeChoice"].label.contains("Step-free"))
        snapshot("provider-route-restored")

        try replayControl("map-off", port: port)
        map.tap()
        handoff.tap()
        let unavailable = app.buttons["toast"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 3))
        XCTAssertEqual(unavailable.label, "Gate map unavailable. Continue in AirBorder.")
        XCTAssertTrue(lift.exists)
        snapshot("provider-map-unavailable")

        try replayControl("map-on", port: port)
        try replayControl("gate/108A", port: port)
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertRoute"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].waitForExistence(timeout: 3))
        map.tap()
        XCTAssertTrue(handoff.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Gate 108A"].exists)
        handoff.tap()
        XCTAssertTrue(gateMap.staticTexts["Gate 108A"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        snapshot("provider-in-app-gate-108A")

        try replayControl("gate/105", port: port)
        XCTAssertTrue(gateMap.waitForNonExistence(timeout: 3), "A new gate closes the old map")
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertRoute"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 3))
    }

    func testDriverCafeOfferRechecksTheWaitBeforeAddingAStop() throws {
        let port = try openAirportPlanning()
        app.tabBars.buttons["Layover"].tap()
        let review = app.buttons["reviewCafeOffer"]
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        snapshot("connection-stop-offer")
        review.tap()
        let add = app.buttons["addReviewedCafe"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        try replayControl("planning-busy", port: port)
        XCTAssertTrue(add.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "This stop needs")).firstMatch.exists)
        app.buttons["back"].tap()
        try replayControl("planning-clear", port: port)
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        review.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        XCTAssertTrue(app.staticTexts["Layover & transit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["planBar"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["planBar"].label.contains("1 stop"))
        XCTAssertFalse(review.exists)
    }

    func testCafeWaitExpiryPreservesThePlanAndFreshReportRestoresTiming() throws {
        let port = try openAirportPlanning()
        try replayControl("planning-cafe-wait/18", port: port)
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["add-anaLounge"].tap()
        app.buttons["planBar"].tap()

        let timing = app.staticTexts["planGateTiming"]
        let cafe = app.buttons["plan-stop-cafe"]
        let lounge = app.buttons["plan-stop-anaLounge"]
        let suggestion = app.descendants(matching: .any)["cafeWaitSuggestion"]
        func waitForLabel(_ element: XCUIElement, _ text: String) {
            let change = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [change], timeout: 6), .completed, "Expected \(text)")
        }

        waitForLabel(timing, "17:15")
        waitForLabel(suggestion, "Shorten ANA LOUNGE to 18 min")
        snapshot("cafe-wait-fresh-plan")

        try replayControl("planning-expire-cafe", port: port)
        waitForLabel(timing, "Estimated gate arrival unavailable")
        XCTAssertFalse(suggestion.exists)
        XCTAssertFalse(app.buttons["applySuggestion"].exists)
        waitForLabel(cafe, "Wait unavailable")
        waitForLabel(lounge, "28 min visit")
        XCTAssertFalse(cafe.label.contains("16:38"))
        XCTAssertFalse(lounge.label.contains("17:11"))
        XCTAssertTrue(app.staticTexts["Be at gate 17:05"].exists)
        XCTAssertTrue(app.staticTexts["Gate closes 17:25"].exists)
        XCTAssertTrue(app.buttons["routeButton"].isEnabled)
        snapshot("cafe-wait-expired-plan")
        lounge.tap()
        XCTAssertTrue(app.buttons["remove-anaLounge"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["arrive-anaLounge"].exists)
        lounge.tap()

        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetState" }
        app.launch()
        app.tabBars.buttons["Layover"].tap()
        app.buttons["planBar"].tap()
        waitForLabel(timing, "Estimated gate arrival unavailable")
        waitForLabel(cafe, "Wait unavailable")
        waitForLabel(lounge, "28 min visit")

        try replayControl("planning-cafe-wait/17", port: port)
        waitForLabel(timing, "17:14")
        waitForLabel(suggestion, "Shorten ANA LOUNGE to 19 min")
        waitForLabel(cafe, "Leave 16:37")
        waitForLabel(lounge, "Leave 17:10")
        XCTAssertLessThan(cafe.frame.minY, lounge.frame.minY)
        XCTAssertTrue(app.buttons["applySuggestion"].exists)
        snapshot("cafe-wait-recovered-plan")
        app.buttons["applySuggestion"].tap()
        waitForLabel(timing, "17:05")
    }

    func testDriverRanksLoungesAfterAGateUpdateAndCanBrowseChangi() throws {
        let port = try openAirportPlanning()
        app.tabBars.buttons["Layover"].tap()
        app.buttons["Rest"].tap()
        let nearby = app.buttons["nearbyLounges"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 4))
        nearby.tap()
        let ana = app.buttons["ranked-lounge-anaLounge"]
        let sky = app.buttons["ranked-lounge-skyLounge"]
        XCTAssertTrue(ana.waitForExistence(timeout: 3))
        XCTAssertLessThan(ana.frame.minY, sky.frame.minY)
        try replayControl("gate/108A", port: port)
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertDismiss"].tap()
        XCTAssertTrue(app.staticTexts["Near Gate 108A"].waitForExistence(timeout: 4))
        XCTAssertLessThan(sky.frame.minY, ana.frame.minY)
        XCTAssertTrue(ana.label.contains("Check at entrance"))
        snapshot("gate-108a-ranked-lounges")

        try replayControl("planning-expire-gate", port: port)
        XCTAssertTrue(app.staticTexts["Gate proximity unavailable"].waitForExistence(timeout: 4))
        XCTAssertFalse(ana.label.contains("minute walk"))
        XCTAssertTrue(ana.label.contains("Check at entrance"))
        try replayControl("planning-lounges-unavailable", port: port)
        XCTAssertTrue(app.staticTexts["Lounge details are unavailable for this terminal."].waitForExistence(timeout: 4))
        XCTAssertFalse(ana.exists)
        try replayControl("planning-lounges-restore", port: port)
        try replayControl("planning-refresh-gate", port: port)
        XCTAssertTrue(app.staticTexts["Near Gate 108A"].waitForExistence(timeout: 4))
        XCTAssertLessThan(sky.frame.minY, ana.frame.minY)

        app.buttons["back"].tap()
        app.buttons["airportGuidesLink"].tap()
        let search = app.textFields["airportGuideSearch"]
        search.tap()
        search.typeText("Singapore")
        app.buttons["airport-guide-SIN"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["airport-guide-SIN-terminal-3"].waitForExistence(timeout: 3))
        snapshot("changi-terminal-guides")
        app.buttons["back"].tap()
        app.tabBars.buttons["Flight"].tap()
        XCTAssertTrue(app.buttons["ticketGateMap"].label.contains("108A"))
    }

    func testDriverOnwardFlightReviewRetainsTheBookedTripDuringAnOutage() throws {
        let port = try openAirportPlanning(time: "17:17")
        app.buttons["travelUpdate-flight"].tap()
        app.buttons["View next flights"].tap()
        let evening = app.buttons["replacement-flight-evening"]
        XCTAssertTrue(evening.waitForExistence(timeout: 4))
        snapshot("next-flights")
        evening.tap()
        app.buttons["reviewReplacementFlight"].tap()
        let call = app.buttons["callAirlineForReplacement"]
        XCTAssertTrue(call.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Tomorrow · 17:30 JST"].exists || app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "17:30 JST")).firstMatch.exists)
        try replayControl("network-off", port: port)
        XCTAssertTrue(app.staticTexts["Flight options are unavailable. Ask ANA about your next departure."].waitForExistence(timeout: 4))
        XCTAssertTrue(call.exists)
        try replayControl("network-on", port: port)
        XCTAssertTrue(app.staticTexts["Ask ANA whether seats are available and what happens to your checked bag."]
            .waitForExistence(timeout: 4))
        try replayControl("planning-expire-flights", port: port)
        XCTAssertTrue(app.staticTexts["Flight options are unavailable. Ask ANA about your next departure."].waitForExistence(timeout: 4))
        XCTAssertTrue(call.isHittable)
        try replayControl("planning-refresh-flights", port: port)
        XCTAssertTrue(app.staticTexts["Ask ANA whether seats are available and what happens to your checked bag."]
            .waitForExistence(timeout: 4))
        app.buttons["back"].tap()
        app.buttons["back"].tap()
        XCTAssertTrue(app.buttons["ticketGateMap"].label.contains("105"))
    }

    func testAirportUpdatesDistinguishOldReportsFromConnectionLossAndRecovery() throws {
        let port = try openAirportPlanning()
        app.buttons["airportUpdatesLink"].tap()
        let rows = app.descendants(matching: .any)
        let checked = app.staticTexts["airportUpdatesChecked"]
        let security = rows["airportUpdate-security"]
        let cafe = rows["airportUpdate-cafe"]
        let gate = rows["airportUpdate-gate"]
        let flight = rows["airportUpdate-flight"]

        func waitFor(_ element: XCUIElement, toContain value: String) {
            let update = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", value), object: element
            )
            XCTAssertEqual(XCTWaiter.wait(for: [update], timeout: 5), .completed, "Expected \(value)")
        }

        waitFor(checked, toContain: "Last checked")
        waitFor(security, toContain: "9 min")
        try replayControl("planning-age-security", port: port)
        waitFor(security, toContain: "Reported")
        try replayControl("planning-expire-cafe", port: port)
        waitFor(cafe, toContain: "Current wait unknown")
        XCTAssertTrue(cafe.label.contains("Last estimate 8 min at"))
        XCTAssertTrue(flight.label.contains("On schedule"))
        snapshot("airport-updates-different-report-times")

        try replayControl("network-off", port: port)
        waitFor(checked, toContain: "Offline · Last checked")
        waitFor(gate, toContain: "Last known: 105")
        waitFor(security, toContain: "Current wait unknown")
        XCTAssertFalse(security.label.contains("9 min"))
        snapshot("airport-updates-offline")

        try replayControl("network-on", port: port)
        waitFor(security, toContain: "9 min")
        XCTAssertTrue(cafe.label.contains("Current wait unknown"), "Reconnecting does not refresh the old estimate")
        try replayControl("planning-refresh", port: port)
        waitFor(cafe, toContain: "8 min")
        XCTAssertFalse(cafe.label.contains("Current wait unknown"))
    }

    func testProviderRejectsOlderAndConflictingAssignments() throws {
        let port = try openAirportPlanning()
        let ticketGate = app.buttons["ticketGateMap"]
        XCTAssertTrue(ticketGate.waitForExistence(timeout: 4))
        try replayControl("gate/108A", port: port)
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertDismiss"].tap()
        XCTAssertTrue(ticketGate.label.contains("108A"))

        for action in ["stale-gate", "conflicting-gate", "wrong-flight-gate"] {
            try replayControl(action, port: port)
            let regressed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                alert.exists || !ticketGate.label.contains("108A")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [regressed], timeout: 1.5), .timedOut, action)
        }
        try replayControl("current-gate", port: port)
        try replayControl("gate/105", port: port)
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertDismiss"].tap()
        XCTAssertTrue(ticketGate.label.contains("105"))
    }

    func testProviderQueuesAgeIndependentlyAndRejectOldPlanningSnapshots() throws {
        let port = try openAirportPlanning()
        app.buttons["airportUpdatesLink"].tap()
        let rows = app.descendants(matching: .any)
        let security = rows["airportUpdate-security"]
        let cafe = rows["airportUpdate-cafe"]
        let flight = rows["airportUpdate-flight"]
        let crowd = rows["airportUpdate-crowd"]
        func waitFor(_ row: XCUIElement, _ value: String) {
            let update = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", value), object: row
            )
            XCTAssertEqual(XCTWaiter.wait(for: [update], timeout: 5), .completed, value)
        }
        waitFor(security, "9 min")
        try replayControl("planning-save", port: port)
        try replayControl("planning-expire-security", port: port)
        waitFor(security, "Current wait unknown")
        XCTAssertTrue(cafe.label.contains("8 min"))
        try replayControl("planning-expire-crowd", port: port)
        waitFor(crowd, "Updates unavailable")
        XCTAssertTrue(flight.label.contains("On schedule"))

        try replayControl("planning-replay-saved", port: port)
        waitFor(flight, "Updates unavailable")
        XCTAssertTrue(security.label.contains("Current wait unknown"))
        try replayControl("planning-mismatched-assignment", port: port)
        waitFor(flight, "Updates unavailable")
        try replayControl("planning-current", port: port)
        waitFor(flight, "On schedule")
        XCTAssertTrue(security.label.contains("Current wait unknown"))
        XCTAssertTrue(crowd.label.contains("Updates unavailable"))
        try replayControl("planning-refresh-security", port: port)
        waitFor(security, "9 min")
        XCTAssertTrue(crowd.label.contains("Updates unavailable"))
    }

    private func openAirportPlanning(time: String = "12:00") throws -> String {
        guard let port = ProcessInfo.processInfo.environment["AIRPORT_PROVIDER_PORT"] else {
            throw XCTSkip("Run with the airport provider driver to exercise the airport planning flow")
        }
        for action in ["network-on", "feed-on", "current-gate", "planning-current", "gate/105",
                       "planning-clear", "planning-flight-on-time", "planning-lounges-restore", "planning-refresh"] {
            try replayControl(action, port: port)
        }
        relaunch(["-gateUpdate", "off", "-now", time, "--uitesting", "--qa-airport-provider",
                  "http://127.0.0.1:\(port)/v1/assignment"])
        return port
    }

    func testRouteTabFollowsThePlanInArriveOrder() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-cafe"].tap()
        app.swipeUp()
        let sky = app.buttons["add-skyLounge"]
        XCTAssertTrue(sky.waitForExistence(timeout: 2))
        sky.tap()
        app.tabBars.buttons["Route"].tap()
        XCTAssertTrue(app.staticTexts["Follow the signs to SKY LOUNGE"].waitForExistence(timeout: 2), "SKY LOUNGE arrives first, at 15:30")
        snapshot("route-via-plan")
        var instructions: [String] = []
        while !app.buttons["endRoute"].exists {
            instructions.append(app.staticTexts["routeInstruction"].label)
            app.buttons["nextStep"].tap()
        }
        instructions.append(app.staticTexts["routeInstruction"].label)
        let order = ["Stop at SKY LOUNGE, leave by 16:38", "Follow the signs to Curacion Cafe", "Stop at Curacion Cafe, leave by 17:24",
                     "Take the stairs at the junction", "Turn left at the Gate 105 sign", "Check NH 106 on the gate screen"]
        let positions = order.compactMap { instructions.firstIndex(of: $0) }
        XCTAssertEqual(positions.count, order.count, "Missing steps in \(instructions)")
        XCTAssertEqual(positions, positions.sorted(), "Steps out of order: \(instructions)")
    }

    func testRouteMapFollowsEachRouteChoice() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["add-anaLounge"].tap()
        app.tabBars.buttons["Route"].tap()
        let map = app.descendants(matching: .any)["routeSummary"]
        XCTAssertTrue(map.waitForExistence(timeout: 2))
        XCTAssertTrue(map.label.contains("direct route via Curacion Cafe, ANA LOUNGE"))
        snapshot("map-direct")
        for (choice, title) in [("stepFree", "step-free"), ("lessCrowded", "less crowded")] {
            app.buttons["routeChoice"].tap()
            app.buttons["use-\(choice)"].tap()
            XCTAssertTrue(map.label.contains("\(title) route"))
            snapshot("map-\(choice)")
        }
    }

    func testSitDownMealWarnsWhenTheLayoverIsTight() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-cafe"].tap()
        app.swipeUp()
        app.buttons["add-skyLounge"].tap()
        app.swipeDown()
        app.buttons["Food & drink"].tap()
        XCTAssertTrue(app.staticTexts["Sit-down, ~45 min"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Quick, ~10 min"].exists)
        app.swipeUp()
        app.buttons["add-sushi"].tap()
        let alert = app.alerts["A sit-down meal may not fit"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        snapshot("sitdown-warning")
        alert.buttons["Add anyway"].tap()
        XCTAssertTrue(app.buttons["add-sushi"].label.contains("Remove"), "Add anyway still adds it")
    }

    func testAppleHealthRefinesWalkingPace() {
        app.tabBars.buttons["Profile"].tap()
        app.buttons["previousTripsRow"].tap()
        app.buttons["viewWalkingPace"].tap()
        XCTAssertTrue(app.staticTexts["4.2 km/h"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["From 3 airport walks, walking only"].exists)
        app.buttons["Connect walking data"].tap()
        app.buttons["Connect Apple Health"].tap()
        XCTAssertTrue(app.staticTexts["Walking speed and distance"].waitForExistence(timeout: 2))
        app.buttons["allowWalkingData"].tap()
        XCTAssertTrue(app.staticTexts["Speed and distance, Synced just now"].waitForExistence(timeout: 3))
        app.buttons["back"].tap()
        XCTAssertTrue(app.staticTexts["4.9 km/h"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["From 3 airport walks and Apple Health"].exists)
        let paceWords = NSPredicate(format: "label CONTAINS[c] 'slow' OR label CONTAINS[c] 'fast'")
        XCTAssertFalse(app.staticTexts.containing(paceWords).firstMatch.exists)
    }

    func testOnboardingRunsOnceThenOpensFlight() {
        app.terminate()
        app.launchArguments = ["-resetState", "-walkingSpeed", "5.6"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to\nAirBorder"].waitForExistence(timeout: 5))
        app.buttons["welcomeContinue"].tap()
        for _ in 0 ..< 3 {
            XCTAssertTrue(app.buttons["onboardingContinue"].waitForExistence(timeout: 2))
            app.buttons["onboardingContinue"].tap()
        }
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments = ["-walkingSpeed", "5.6"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 5), "Onboarding shows only once")
    }

    func testOnboardingSkipStaysDismissedOnRelaunch() {
        app.terminate()
        app.launchArguments = ["-resetState", "-gateUpdate", "off"]
        app.launch()
        let welcome = app.buttons["welcomeContinue"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))
        welcome.tap()
        let skip = app.buttons["onboardingSkip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(skip.frame.height, 44)
        skip.tap()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 4))
        app.terminate()
        app.launchArguments = ["-gateUpdate", "off"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 4))
        XCTAssertFalse(welcome.exists)
    }

    func testTutorialReplayReturnsToProfileAndPreservesThePlan() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-anaLounge"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["planBar"].tap()
        let lounge = app.buttons["plan-stop-anaLounge"]
        let cafe = app.buttons["plan-stop-cafe"]
        XCTAssertTrue(lounge.waitForExistence(timeout: 3))
        XCTAssertTrue(cafe.exists)
        let originalLabels = [lounge.label, cafe.label]
        let loungeFirst = lounge.frame.minY < cafe.frame.minY
        app.buttons["back"].tap()
        app.tabBars.buttons["Profile"].tap()
        let tutorial = app.buttons["Replay tutorial"]
        XCTAssertTrue(tutorial.waitForExistence(timeout: 3))
        tutorial.tap()
        for _ in 0..<3 {
            let next = app.buttons["onboardingContinue"]
            XCTAssertTrue(next.waitForExistence(timeout: 3))
            next.tap()
        }
        XCTAssertTrue(tutorial.waitForExistence(timeout: 4))
        XCTAssertTrue(app.tabBars.buttons["Profile"].isSelected)
        app.tabBars.buttons["Layover"].tap()
        app.buttons["planBar"].tap()
        XCTAssertTrue(lounge.waitForExistence(timeout: 3))
        XCTAssertTrue(cafe.exists)
        XCTAssertEqual([lounge.label, cafe.label], originalLabels)
        XCTAssertEqual(lounge.frame.minY < cafe.frame.minY, loungeFirst)
    }

    func testLanguageChoicesDiscloseAvailabilityAndReturnToProfile() {
        app.tabBars.buttons["Profile"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Language")).firstMatch.tap()
        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["English"].isSelected)
        for language in ["日本語", "Français"] {
            app.buttons[language].tap()
            let unavailable = app.alerts.firstMatch
            XCTAssertTrue(unavailable.waitForExistence(timeout: 3))
            XCTAssertTrue(unavailable.staticTexts["AirBorder is in English for now."].exists)
            unavailable.buttons["OK"].tap()
            XCTAssertTrue(app.buttons["English"].isSelected)
        }
        let back = app.buttons["back"]
        XCTAssertEqual(app.buttons.matching(identifier: "back").count, 1)
        XCTAssertTrue(back.isHittable)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
        back.tap()
        XCTAssertTrue(app.staticTexts["Your profile"].waitForExistence(timeout: 3))
    }

    func testBackFromBaggageReturnsToJourneyThenFlight() {
        app.buttons["journeyDetailsLink"].tap()
        let baggage = app.buttons["Baggage for this flight"]
        XCTAssertTrue(baggage.waitForExistence(timeout: 3))
        baggage.tap()
        XCTAssertTrue(app.buttons["extraBaggage"].waitForExistence(timeout: 3))
        let back = app.buttons["back"]
        XCTAssertEqual(app.buttons.matching(identifier: "back").count, 1)
        XCTAssertTrue(back.isHittable)
        XCTAssertGreaterThanOrEqual(back.frame.height, 44)
        back.tap()
        XCTAssertTrue(baggage.waitForExistence(timeout: 3))
        back.tap()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.tabBars.buttons["Flight"].isSelected)
    }

    func testRouteFinalStepCanGoBackAndEnd() {
        app.tabBars.buttons["Route"].tap()
        for _ in 0..<4 { app.buttons["nextStep"].tap() }
        let end = app.buttons["endRoute"]
        let back = app.buttons["previousStep"]
        XCTAssertTrue(end.isHittable)
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.buttons["nextStep"].isHittable)
        XCTAssertFalse(end.exists)
        app.buttons["nextStep"].tap()
        end.tap()
        XCTAssertTrue(app.buttons["toast"].waitForExistence(timeout: 3))
    }

    func testUnclearTicketPhotoCanBeRetakenReviewedCorrectedAndSaved() throws {
        guard let fixtures = ProcessInfo.processInfo.environment["TICKET_OCR_FIXTURES"] else {
            throw XCTSkip("Run with the generated ticket images")
        }
        app.launchEnvironment["AIRBORDER_TICKET_PHOTO_FIXTURES"] = fixtures
        relaunch(["--uitesting", "-gateUpdate", "off"])
        app.buttons["addFlight"].tap()
        app.buttons["importTicket"].tap()
        app.buttons["import-Camera"].tap()
        app.buttons["Continue"].tap()
        let takePhoto = app.buttons["Take photo"]
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 4))
        takePhoto.tap()
        XCTAssertTrue(app.staticTexts["Try another photo"].waitForExistence(timeout: 5))
        app.buttons["Retake photo"].tap()
        XCTAssertTrue(takePhoto.waitForExistence(timeout: 4))
        takePhoto.tap()
        XCTAssertTrue(app.staticTexts["Review your flight"].waitForExistence(timeout: 6))
        app.buttons["Review and edit details"].tap()
        let edit = app.buttons["Edit flight details"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()
        let number = app.textFields["manualNumber"]
        let date = app.textFields["manualDate"]
        XCTAssertTrue(number.waitForExistence(timeout: 3))
        XCTAssertEqual(number.value as? String, "NH 123")
        XCTAssertEqual(date.value as? String, "2027-05-20")
        number.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        number.typeText("A")
        app.buttons["reviewEntered"].tap()
        XCTAssertTrue(app.staticTexts["NH 123A"].waitForExistence(timeout: 3))
        app.buttons["saveEntered"].tap()
        let saved = app.descendants(matching: .any)["manualFlights"]
        XCTAssertTrue(saved.waitForExistence(timeout: 3))
        XCTAssertTrue(saved.label.contains("NH 123A, 20 May 2027"))
    }

    func testRouteEndShowsArrivalToast() {
        app.tabBars.buttons["Route"].tap()
        for _ in 0 ..< 4 { app.buttons["nextStep"].tap() }
        app.buttons["endRoute"].tap()
        let toast = app.buttons["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 2))
        XCTAssertTrue(toast.label.contains("Arrived, Gate 105, NH 106, boarding 17:00."))
    }

    func testManualFlightEntryValidatesAndSaves() {
        app.buttons["addFlight"].tap()
        app.buttons["importTicket"].tap()
        app.buttons["addManually"].tap()
        let number = app.textFields["manualNumber"]
        XCTAssertTrue(number.waitForExistence(timeout: 2))
        number.tap()
        number.typeText("JL")
        app.buttons["reviewEntered"].tap()
        XCTAssertTrue(app.staticTexts["Enter the airline code and number, like BA123."].exists)
        number.typeText("43")
        let date = app.textFields["manualDate"]
        date.tap()
        date.typeText("2026-10-15")
        app.buttons["reviewEntered"].tap()
        XCTAssertTrue(app.staticTexts["JL 43"].waitForExistence(timeout: 2))
        app.buttons["saveEntered"].tap()
        let saved = app.descendants(matching: .any)["manualFlights"]
        XCTAssertTrue(saved.waitForExistence(timeout: 2))
        XCTAssertTrue(saved.label.contains("JL 43, 15 Oct 2026"))
    }

    func testBaggageDeclarationAndReturnFlight() {
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["Baggage for this flight"].tap()
        XCTAssertTrue(app.staticTexts["1 × 32 kg"].waitForExistence(timeout: 2) || app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '1 × 32 kg'")).firstMatch.exists)
        app.buttons["extraBaggage"].tap()
        app.buttons["saveExtraBag"].tap()
        XCTAssertTrue(app.staticTexts["Baggage updated"].waitForExistence(timeout: 2))
        app.buttons["back"].firstMatch.tap()
        app.buttons["viewReturnFlight"].tap()
        XCTAssertTrue(app.staticTexts["RETURN FLIGHT, 21 OCT"].waitForExistence(timeout: 2))
    }

    func testEditFlightDateAndSave() {
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Saved flights"].tap()
        app.buttons["Edit this flight"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS '15 Oct 2026'")).firstMatch.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS '16 October 2026'")).firstMatch.tap()
        app.buttons["reviewCorrected"].tap()
        app.buttons["saveFlight"].tap()
        XCTAssertTrue(app.staticTexts["Flight saved"].waitForExistence(timeout: 2))
        app.buttons["View saved flights"].tap()
        XCTAssertTrue(app.staticTexts["Your flights"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any).containing(NSPredicate(format: "label CONTAINS '16 Oct'")).firstMatch.exists)
    }

    func testImportPathsAreHonestAboutWhatWorks() {
        app.buttons["addFlight"].tap()
        app.buttons["importTicket"].tap()
        app.buttons["import-Camera"].tap()
        XCTAssertTrue(app.staticTexts["Scan your ticket"].waitForExistence(timeout: 2))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["Where is your ticket?"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Camera unavailable"].exists)
        for (source, title) in [("Gmail", "Connect Gmail"), ("Google Calendar", "Connect Calendar")] {
            app.buttons["import-\(source)"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 2))
            let unavailable = app.alerts["Google sign-in isn't available yet"]
            XCTAssertFalse(unavailable.exists)
            app.buttons["Continue with Google"].tap()
            XCTAssertTrue(unavailable.waitForExistence(timeout: 2))
            unavailable.buttons["OK"].tap()
            app.buttons["back"].tap()
            XCTAssertTrue(app.staticTexts["Where is your ticket?"].waitForExistence(timeout: 2))
        }
    }

    func testWalletImportShowsPDFFallbackOnlyAfterSelection() {
        app.buttons["addFlight"].tap()
        app.buttons["importTicket"].tap()

        for provider in ["Apple Wallet", "Google Wallet"] {
            app.buttons["import-\(provider)"].tap()
            let selectPass = app.buttons["Select pass"]
            let noPass = app.alerts["No boarding pass available"]
            XCTAssertTrue(selectPass.waitForExistence(timeout: 2))
            XCTAssertTrue(app.staticTexts["Open your boarding pass in Wallet"].exists)
            XCTAssertTrue(app.staticTexts["Tap Share"].exists)
            XCTAssertFalse(app.staticTexts["Choose AirBorder"].exists)
            XCTAssertFalse(app.staticTexts["No share button? Use the airline PDF instead."].exists)
            XCTAssertFalse(app.buttons["Use a PDF instead"].exists)
            XCTAssertFalse(noPass.exists)
            let entryScreenshot = XCTAttachment(screenshot: app.screenshot())
            entryScreenshot.name = "\(provider) import on entry"
            entryScreenshot.lifetime = .keepAlways
            add(entryScreenshot)

            selectPass.tap()
            XCTAssertTrue(noPass.waitForExistence(timeout: 2))
            XCTAssertTrue(noPass.staticTexts["Wallet import is unavailable. Use the airline PDF instead."].exists)
            let fallbackScreenshot = XCTAttachment(screenshot: app.screenshot())
            fallbackScreenshot.name = "\(provider) PDF fallback after selection"
            fallbackScreenshot.lifetime = .keepAlways
            add(fallbackScreenshot)
            noPass.buttons["Cancel"].tap()
            XCTAssertTrue(noPass.waitForNonExistence(timeout: 2))
            XCTAssertTrue(selectPass.isHittable)

            selectPass.tap()
            XCTAssertTrue(noPass.waitForExistence(timeout: 2))
            noPass.buttons["Use PDF"].tap()
            XCTAssertTrue(app.staticTexts["Choose a PDF"].waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["pickPDF"].exists)

            app.buttons["back"].tap()
            XCTAssertTrue(selectPass.waitForExistence(timeout: 2))
            app.buttons["back"].tap()
            XCTAssertTrue(app.staticTexts["Where is your ticket?"].waitForExistence(timeout: 2))
        }
    }

    func testTerminalTwoVisitAddsToPlanAndShowsRoute() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["area-Landside"].tap()
        let deck = app.buttons["View route & return"]
        app.swipeUp()
        XCTAssertTrue(deck.waitForExistence(timeout: 2))
        deck.tap()
        XCTAssertTrue(app.staticTexts["T2 Observation Deck"].waitForExistence(timeout: 2))
        app.buttons["addT2Visit"].tap()
        XCTAssertTrue(app.buttons["Remove the visit"].waitForExistence(timeout: 2))
        app.buttons["View shuttle route"].tap()
        XCTAssertTrue(app.staticTexts["To Terminal 2"].waitForExistence(timeout: 2))
        app.buttons["Arrived at Terminal 2"].tap()
        XCTAssertTrue(app.staticTexts["At T2 Observation Deck"].waitForExistence(timeout: 2))
        app.buttons["View Journey"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["addedPlanCard"].waitForExistence(timeout: 2))
    }

    private func relaunch(_ extra: [String]) {
        app.terminate()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-walkingSpeed", "5.6"] + extra
        app.launch()
    }

    func testGateUpdateArrivesAsAnAlertAndChangesTheGate() {
        relaunch(["-gateUpdate", "1"])
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["NH 106 now departs from Gate 108A. It’s a 12 min walk."].exists)
        snapshot("gate-alert")
        app.buttons["alertDismiss"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["travelUpdate-flight"].label.contains("108A"))
        snapshot("gate-strip")
        app.buttons["travelUpdate-flight"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 2), "The strip shows the change again")
        app.buttons["alertRoute"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].waitForExistence(timeout: 2))
        for _ in 0 ..< 2 { app.buttons["nextStep"].tap() }
        XCTAssertTrue(app.staticTexts["Follow signs for 108–149"].waitForExistence(timeout: 2), "108A uses the same map route")
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.staticTexts["Turn left at the Gate 108A sign"].exists)
    }

    func testGateAlertKeepsTheInterruptedStopEditor() {
        relaunch(["-gateUpdate", "14"])
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-anaLounge"].tap()
        app.tabBars.buttons["Flight"].tap()
        let lane = app.buttons["lane-anaLounge"]
        if !lane.isHittable { app.swipeUp() }
        lane.tap()
        let editor = app.descendants(matching: .any)["leave-anaLounge"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 18))
        XCTAssertTrue(lane.waitForNonExistence(timeout: 2), "The modal owns the accessibility tree")
        let gates = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Gate 105 changed to 108A")).firstMatch
        XCTAssertTrue(gates.exists)
        app.buttons["alertDismiss"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))
        XCTAssertTrue(editor.waitForExistence(timeout: 3), "Dismiss returns to the open stop editor")
        XCTAssertTrue(editor.buttons["Leave earlier"].exists)
        snapshot("gate-alert-resumed-editor")
    }

    func testGateAlertActionsStayReachableWithAccessibilityText() {
        relaunch(["-gateUpdate", "1", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let route = app.buttons["alertRoute"]
        let dismiss = app.buttons["alertDismiss"]
        XCTAssertTrue(route.isHittable)
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertLessThan(route.frame.midY, dismiss.frame.midY, "The two actions stack at accessibility sizes")
        snapshot("gate-alert-accessibility-text")
        dismiss.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))
    }

    func testSavedGateAndPlanSurviveRelaunchWithFlightUpdatesOff() {
        relaunch(["-gateUpdate", "1"])
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertDismiss"].tap()
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-anaLounge"].tap()
        XCTAssertTrue(app.buttons["planBar"].waitForExistence(timeout: 2))

        app.terminate()
        app.launchArguments = ["-skipOnboarding", "-walkingSpeed", "5.6", "-gateUpdate", "off"]
        app.launch()
        let gate = app.buttons["ticketGateMap"]
        XCTAssertTrue(gate.waitForExistence(timeout: 5))
        XCTAssertTrue(gate.label.contains("108A"))
        XCTAssertTrue(app.buttons["lane-anaLounge"].exists)
        XCTAssertFalse(alert.exists)
    }

    func testTicketGateOpensMapFromFlightAndJourneyDetails() {
        let gateBadge = app.buttons["ticketGateMap"]
        XCTAssertTrue(gateBadge.waitForExistence(timeout: 3))
        XCTAssertTrue(gateBadge.label.contains("105"))
        gateBadge.tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].exists)
        app.buttons["nextStep"].tap()
        let nextInstruction = "Take the stairs at the junction"
        XCTAssertTrue(app.staticTexts[nextInstruction].waitForExistence(timeout: 3))
        app.buttons["mode-camera"].tap()
        let cameraPrompt = app.descendants(matching: .any)["cameraPrompt"]
        if cameraPrompt.waitForExistence(timeout: 2) {
            app.buttons["cameraAllow"].tap()
            let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
            if allow.waitForExistence(timeout: 3) { allow.tap() }
        }
        XCTAssertTrue(app.descendants(matching: .any)["cameraView"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Flight"].tap()
        app.buttons["journeyDetailsLink"].tap()
        XCTAssertTrue(gateBadge.waitForExistence(timeout: 3))
        gateBadge.tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].exists)
        XCTAssertTrue(app.staticTexts[nextInstruction].exists, "The shortcut retains the current route step")
    }

    func testTicketGateOpensReassignedGateAfterTheAlertIsDismissed() {
        relaunch(["-gateUpdate", "1"])
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertDismiss"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 2))
        let gateBadge = app.buttons["ticketGateMap"]
        XCTAssertTrue(gateBadge.label.contains("108A"))
        gateBadge.tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 108A"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].exists)
    }

    func testLayoverRestUsesTheDepartureTerminal() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["Rest"].tap()
        let ana = app.buttons["add-anaLounge"]
        let sky = app.buttons["add-skyLounge"]
        XCTAssertTrue(ana.waitForExistence(timeout: 3))
        XCTAssertTrue(sky.exists)
        XCTAssertLessThan(ana.frame.minY, sky.frame.minY)
        XCTAssertFalse(app.buttons["add-cafe"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["venueWalk-anaLounge"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["venueLeaveBy-anaLounge"].exists)

        relaunch(["-gateUpdate", "off", "-flight", "NH6"])
        XCTAssertFalse(app.buttons["ticketGateMap"].exists, "Narita's gate is unknown in the sample")
        app.tabBars.buttons["Layover"].tap()
        XCTAssertTrue(app.staticTexts["Layover & transit"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Food & drink"].exists)
        XCTAssertFalse(app.buttons["Rest"].exists, "The Haneda airport directory has no Narita entries")
        XCTAssertFalse(app.buttons["add-anaLounge"].exists)
        XCTAssertFalse(app.buttons["add-skyLounge"].exists)
        XCTAssertFalse(app.buttons["add-cafe"].exists)
    }

    func testLoungeCardsWithholdGateTimingAfterReassignment() {
        relaunch(["-gateUpdate", "1"])
        let alert = app.descendants(matching: .any)["gateAlert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        app.buttons["alertDismiss"].tap()
        app.tabBars.buttons["Layover"].tap()
        app.buttons["Rest"].tap()
        XCTAssertTrue(app.buttons["add-anaLounge"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["add-skyLounge"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["venueWalk-anaLounge"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["venueWalk-skyLounge"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["venueLeaveBy-anaLounge"].exists)
    }

    func testReturnNowShowsCountdownInsteadOfThePlan() {
        relaunch(["-gateUpdate", "off", "-now", "17:00"])
        XCTAssertTrue(app.staticTexts["Time to return to Gate 105"].waitForExistence(timeout: 5), "Alert opens on its own")
        app.buttons["back"].tap()
        let countdown = app.descendants(matching: .any)["scenarioCountdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 2))
        XCTAssertEqual(countdown.label, "25 min before Gate 105 closes.")
        XCTAssertFalse(app.buttons["myPlanLink"].exists)
        XCTAssertFalse(app.buttons["addStop"].exists)
    }

    func testUrgentReturnRoutesDirectlyAndRetainsTheStops() {
        app.tabBars.buttons["Layover"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["add-anaLounge"].tap()
        app.terminate()
        app.launchArguments = ["-skipOnboarding", "-gateUpdate", "off", "-now", "17:02"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Time to return to Gate 105"].waitForExistence(timeout: 5))
        app.buttons["alertRoute"].tap()
        let map = app.descendants(matching: .any)["routeSummary"]
        XCTAssertTrue(map.waitForExistence(timeout: 3))
        XCTAssertFalse(map.label.contains("Curacion Cafe"))
        XCTAssertFalse(map.label.contains("ANA LOUNGE"))
        XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].exists)
        app.terminate()
        app.launchArguments = ["-skipOnboarding", "-gateUpdate", "off"]
        app.launch()
        XCTAssertTrue(app.buttons["lane-cafe"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["lane-anaLounge"].exists)
    }

    func testArrivalAfterClosureOffersAssistance() {
        relaunch(["-gateUpdate", "off", "-now", "17:17"])
        let banner = app.buttons["travelUpdate-flight"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.label.contains("Arrival 4 min after closure"))
        XCTAssertTrue(app.buttons["travelUpdateAction-flight"].label.contains("Call ANA"))
        banner.tap()
        XCTAssertTrue(app.staticTexts["Boarding assistance"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Arriving 17:29"].exists)
    }

    func testChoosingNH6StartsTheNaritaTransfer() {
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Saved flights"].tap()
        app.buttons["Edit this flight"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'NH 106'")).firstMatch.tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'NH 6'")).firstMatch.tap()
        app.buttons["reviewCorrected"].tap()
        app.buttons["saveFlight"].tap()
        XCTAssertTrue(app.staticTexts["Flight saved"].waitForExistence(timeout: 2))
        app.buttons["View saved flights"].tap()
        app.buttons["back"].tap()
        app.tabBars.buttons["Flight"].tap()
        XCTAssertTrue(app.buttons["travelUpdate-flight"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["travelUpdate-flight"].label.contains("Change airports: Haneda → Narita"))
        XCTAssertTrue(app.descendants(matching: .any)["transferCountdown"].exists)
        app.tabBars.buttons["Route"].tap()
        XCTAssertTrue(app.staticTexts["Route to Narita"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Follow Bus signs"].exists)
    }

    func testCameraGuidanceKeepsTheStepAndFallsBackToTheMap() {
        app.terminate()
        app.resetAuthorizationStatus(for: .camera)
        app.launch()
        app.tabBars.buttons["Route"].tap()
        app.buttons["mode-camera"].tap()
        let prompt = app.descendants(matching: .any)["cameraPrompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 2), "Camera access is asked in a pop-up")
        app.buttons["cameraDismiss"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].waitForExistence(timeout: 2), "Dismiss stays on the map")
        app.buttons["nextStep"].tap()
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(prompt.waitForExistence(timeout: 2))
        app.buttons["cameraAllow"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        XCTAssertTrue(app.buttons["readSignAgain"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Take the stairs at the junction"].exists, "Camera keeps the current step")
        app.buttons["readSignAgain"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanningSign"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Can't read the sign"].waitForExistence(timeout: 15))
        app.buttons["useMap"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["routeSummary"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Take the stairs at the junction"].exists)
    }

    func testDeniedCameraReturnsToTheSameMapStep() {
        app.terminate()
        app.resetAuthorizationStatus(for: .camera)
        app.launch()
        app.tabBars.buttons["Route"].tap()
        app.buttons["nextStep"].tap()
        let step = app.staticTexts["Take the stairs at the junction"]
        XCTAssertTrue(step.exists)
        app.buttons["mode-camera"].tap()
        app.buttons["cameraAllow"].tap()
        let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(systemAlert.waitForExistence(timeout: 4))
        let options = systemAlert.buttons.allElementsBoundByIndex
        let decline = options.first { $0.label == "Don’t Allow" || $0.label == "Don't Allow" }
        XCTAssertNotNil(decline, "Expected a camera-denial choice")
        decline?.tap()
        XCTAssertTrue(step.waitForExistence(timeout: 3))
        app.buttons["mode-camera"].tap()
        XCTAssertTrue(app.staticTexts["Camera access is off. You can turn it on in Settings."].waitForExistence(timeout: 3))
        XCTAssertTrue(step.exists)
        app.buttons["mode-map"].tap()
        XCTAssertTrue(step.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["mode-map"].isSelected)
    }

    func testSignScanRetriesAndRecognizesTheGateWithoutAdvancingTheRoute() throws {
        guard let fixtures = ProcessInfo.processInfo.environment["SIGN_OCR_FIXTURES"] else {
            throw XCTSkip("Run with the generated airport sign images")
        }
        app.terminate()
        app.resetAuthorizationStatus(for: .camera)
        app.launchEnvironment["AIRBORDER_SIGN_PHOTO_FIXTURES"] = fixtures
        app.launchArguments += ["--uitesting"]
        app.launch()
        app.tabBars.buttons["Route"].tap()
        app.buttons["nextStep"].tap()
        let step = app.staticTexts["Take the stairs at the junction"]
        XCTAssertTrue(step.exists)
        app.buttons["mode-camera"].tap()
        app.buttons["cameraAllow"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 4))
        allow.tap()
        let read = app.buttons["readSignAgain"]
        XCTAssertTrue(read.waitForExistence(timeout: 4))
        read.tap()
        let unreadable = app.staticTexts["Can't read the sign"]
        XCTAssertTrue(unreadable.waitForExistence(timeout: 15))
        app.buttons["tryAgain"].tap()
        XCTAssertTrue(read.waitForExistence(timeout: 7))
        XCTAssertFalse(unreadable.exists)
        XCTAssertTrue(step.exists, "OCR confirms the sign without claiming a new position")
        app.buttons["mode-map"].tap()
        XCTAssertTrue(step.waitForExistence(timeout: 3))
    }

    func testFlightOneOpensInJourneyDetails() {
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["flightOne"].tap()
        XCTAssertTrue(app.staticTexts["05:15"].waitForExistence(timeout: 2), "Flight 1 shows as the full ticket")
        XCTAssertTrue(app.buttons["flightTwo"].exists)
        app.buttons["flightTwo"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ticket-NH106"].waitForExistence(timeout: 2))
    }

    func testTerminalTwoTooLateSendsTravellerToTheGate() {
        relaunch(["-gateUpdate", "off", "-now", "15:00"])
        app.tabBars.buttons["Layover"].tap()
        app.buttons["area-Landside"].tap()
        app.swipeUp()
        let deck = app.buttons["View route & return"]
        XCTAssertTrue(deck.waitForExistence(timeout: 2))
        deck.tap()
        XCTAssertTrue(app.staticTexts["Not enough time for Terminal 2"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["addT2Visit"].exists)
    }

    func testNH6BaggageShowsTheNaritaRecheck() {
        relaunch(["-gateUpdate", "off", "-flight", "NH6"])
        app.buttons["journeyDetailsLink"].tap()
        app.buttons["Baggage for this flight"].tap()
        XCTAssertTrue(app.staticTexts["Collect at Haneda T3 2F. Recheck at Narita T1 by 20:00."].waitForExistence(timeout: 2))
        app.buttons["extraBaggage"].tap()
        XCTAssertTrue(app.staticTexts["Up to 32 kg, NH 6"].waitForExistence(timeout: 2))
    }
}
