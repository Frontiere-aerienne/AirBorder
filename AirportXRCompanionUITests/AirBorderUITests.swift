import XCTest

final class AirBorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-walkingSpeed", "5.6", "-gateUpdate", "off"]
        app.launch()
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
        XCTAssertFalse(app.staticTexts["4 min to gate"].exists, "Stops stay closed until tapped")
        app.buttons["lane-cafe"].tap()
        XCTAssertTrue(app.staticTexts["16:59"].waitForExistence(timeout: 2), "Leave defaults to the latest time")
        XCTAssertTrue(app.staticTexts["Overlaps with ANA LOUNGE"].exists)
        app.swipeUp()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "plan-card-open"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["Leave later"].tap()
        XCTAssertTrue(app.staticTexts["16:59"].exists, "Never past the latest leave")
        app.buttons["Leave earlier"].tap()
        XCTAssertTrue(app.staticTexts["16:45"].waitForExistence(timeout: 2))
        app.buttons["fixOverlap-cafe"].tap()
        XCTAssertTrue(app.staticTexts["16:30"].waitForExistence(timeout: 2), "Leaves when the lounge starts")
        XCTAssertFalse(app.staticTexts["Overlaps with ANA LOUNGE"].waitForExistence(timeout: 1))
        app.buttons["remove-cafe"].tap()
        XCTAssertTrue(app.buttons["lane-cafe"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.buttons["lane-anaLounge"].exists)
        let undo = app.buttons["toast"]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        XCTAssertTrue(undo.label.contains("Removed Curacion Cafe"))
        undo.tap()
        XCTAssertTrue(app.buttons["lane-cafe"].waitForExistence(timeout: 2), "Undo brings the stop back")
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
        XCTAssertTrue(app.staticTexts["Stop at Curacion Cafe, leave by 16:59"].exists, "Uses the leave time from the plan")
        snapshot("route-via-cafe")
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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
        let order = ["Stop at SKY LOUNGE, leave by 16:57", "Follow the signs to Curacion Cafe", "Stop at Curacion Cafe, leave by 16:59",
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
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 2))
        app.buttons["Other import options"].tap()
        XCTAssertTrue(app.staticTexts["Where is your ticket?"].waitForExistence(timeout: 2))
        app.buttons["import-Gmail"].tap()
        XCTAssertTrue(app.staticTexts["Connect Gmail"].waitForExistence(timeout: 2))
        app.buttons["Continue with Google"].tap()
        XCTAssertTrue(app.alerts["Google sign-in isn't available yet"].waitForExistence(timeout: 2))
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
