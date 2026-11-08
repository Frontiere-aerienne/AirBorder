import XCTest

final class AirportXRCompanionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testJourneyShowsNamedExampleItineraryAndCalculationTrace() {
        launch()

        XCTAssertTrue(element("longHaulJourneyDashboard").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Example itinerary"].exists)
        XCTAssertTrue(app.staticTexts["Bangkok to Los Angeles"].exists)
        XCTAssertTrue(app.staticTexts["Thai Airways"].exists)
        XCTAssertTrue(app.staticTexts["TG 660"].exists)
        XCTAssertTrue(app.staticTexts["BKK"].exists)
        XCTAssertTrue(app.staticTexts["HND"].exists)

        let why = app.buttons["Plan details"]
        scrollToElement(why)
        XCTAssertTrue(why.exists)
        why.tap()
        XCTAssertTrue(element("calculationTraceView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your timing"].exists)
    }

    func testSafestFirstActionOpensDerivedTerminalMap() {
        launch()

        let goToGate = app.buttons["goToGateButton"]
        XCTAssertTrue(goToGate.waitForExistence(timeout: 5))
        XCTAssertTrue(goToGate.label.localizedCaseInsensitiveContains("Go to Gate"))
        goToGate.tap()

        XCTAssertTrue(element("terminalMapView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routeModePicker"].exists)
        XCTAssertTrue(app.buttons["manualCalibrationMenu"].exists)
        XCTAssertTrue(element("findNearbyCard").exists)
        XCTAssertTrue(app.buttons["findNearby_restroom"].exists)
        XCTAssertTrue(app.textFields["Search for an item"].exists)
    }

    func testFlightSearchShowsPassengerFriendlyExampleResultAndDetail() {
        launch()
        selectTab("Flights")

        XCTAssertTrue(element("itineraryEditor").waitForExistence(timeout: 5))
        app.buttons["searchFlightButton"].tap()
        XCTAssertTrue(element("flightSearchResult").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label == 'Example'")
        ).firstMatch.exists)

        app.staticTexts["AX 204"].firstMatch.tap()
        XCTAssertTrue(element("flightDetailView").waitForExistence(timeout: 5))
        let exampleDetails = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Practice flight details'")
        ).firstMatch
        scrollToElement(exampleDetails)
        XCTAssertTrue(exampleDetails.exists)
    }

    func testARGuidanceAndAccessibleMapAreAvailableForMappedGate() {
        launch()

        app.buttons["universalReturnToGateButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 8))

        app.buttons["arMapFallbackButton"].tap()
        XCTAssertTrue(element("terminalMapView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["routeModePicker"].label.localizedCaseInsensitiveContains("accessible"))
    }

    func testReturnToGateStaysAvailableAcrossTabsAndOpensDirections() {
        launch()

        for tab in ["Journey", "Flights", "AR Guide", "Map"] {
            selectTab(tab)
            XCTAssertTrue(
                app.buttons["universalReturnToGateButton"].waitForExistence(timeout: 3),
                "Return to Gate should remain available on \(tab)"
            )
        }

        app.buttons["universalReturnToGateButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["arMapFallbackButton"].exists)
    }

    func testARPreviewChangesGuidanceWithSimulatedPosition() {
        app.launchArguments = [
            "--uitesting", "--launch-mode", "demo", "--qa-simulated-walk"
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))

        app.buttons["universalReturnToGateButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 8))
        let maneuver = app.descendants(matching: .any)["arManeuverCard"].firstMatch
        XCTAssertTrue(maneuver.waitForExistence(timeout: 5))
        let stop = app.buttons["Stop"]
        if stop.exists { stop.tap() }
        let startingInstruction = maneuver.label
        app.buttons["Next point"].tap()
        // A route segment contains multiple location samples. Guidance changes
        // at the next landmark, not necessarily at its midpoint.
        for _ in 0..<6 where maneuver.label == startingInstruction {
            app.buttons["Next point"].tap()
        }
        let changedManeuver = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'arManeuverCard' AND label != %@", startingInstruction)
        ).firstMatch
        XCTAssertTrue(changedManeuver.waitForExistence(timeout: 5))
    }

    func testTerminalWalkthroughCoversCoreFeaturesAndFillsTravelerDetails() {
        app.launchArguments = [
            "--uitesting", "--launch-mode", "demo", "--qa-walkthrough"
        ]
        app.launch()
        XCTAssertTrue(element("automatedWalkthroughBanner").waitForExistence(timeout: 8))
        app.buttons["walkthroughPauseButton"].tap()

        app.buttons["walkthroughNextButton"].tap()
        XCTAssertTrue(element("layoverTransitView").waitForExistence(timeout: 5))
        app.buttons["walkthroughNextButton"].tap()
        XCTAssertTrue(element("itineraryEditor").waitForExistence(timeout: 5))
        app.buttons["walkthroughNextButton"].tap()
        XCTAssertTrue(element("terminalMapView").waitForExistence(timeout: 5))
        app.buttons["walkthroughNextButton"].tap()
        XCTAssertTrue(element("arGuideView").waitForExistence(timeout: 5))
        XCTAssertTrue(element("arManeuverCard").waitForExistence(timeout: 5))

        app.buttons["walkthroughNextButton"].tap()
        XCTAssertTrue(element("settingsView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["universalReturnToGateButton"].exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'United States'")
        ).firstMatch.exists)

        app.buttons["walkthroughNextButton"].tap()
        let accessibilityNeeds = app.textFields["Accessibility needs"]
        XCTAssertEqual(accessibilityNeeds.value as? String, "Prefer elevators and shorter walks")
    }

    func testLayoverLayersShowOfficialHanedaWorkPodAsLandsideOnly() {
        launch()

        let workPods = app.buttons["Landside work pods"]
        scrollToElement(workPods)
        XCTAssertTrue(workPods.exists)
        workPods.tap()

        XCTAssertTrue(element("layoverTransitView").waitForExistence(timeout: 5))
        scrollToElement(app.staticTexts["Terminal 3 Work Cubicles"])
        XCTAssertTrue(app.staticTexts["Terminal 3 Work Cubicles"].exists)
        let landsideLabel = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Airport Landside'")
        ).firstMatch
        scrollToElement(landsideLabel)
        XCTAssertTrue(landsideLabel.exists)
    }

    func testLayoverAffordabilityLayerShowsLocalCostsAndFreeOptions() {
        launch()
        // Costs belong to the full layover plan, not a filtered work-pod search.
        selectTab("Layover")

        XCTAssertTrue(element("layoverTransitView").waitForExistence(timeout: 5))
        let affordability = app.staticTexts["Plan your spend"]
        scrollToElement(affordability)
        XCTAssertTrue(affordability.exists)
        XCTAssertTrue(app.staticTexts["Free"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Local rail or monorail'")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Observation Deck"].exists)
    }

    func testInterAirportTransferLeadsWithPassengerFriendlyActionAndUnknownTarget() {
        launch(scenario: "interAirport")

        XCTAssertTrue(element("departureWeatherCard").waitForExistence(timeout: 5))
        XCTAssertTrue(element("transferWeatherCard").exists)
        XCTAssertTrue(element("destinationWeatherCard").exists)
        XCTAssertTrue(app.buttons["Refresh weather for HND"].exists)
        XCTAssertTrue(app.buttons["Refresh weather for NRT"].exists)
        XCTAssertTrue(app.buttons["Refresh weather for LAX"].exists)

        let journeyTransfer = app.buttons["goToGateButton"]
        XCTAssertTrue(journeyTransfer.waitForExistence(timeout: 5))
        XCTAssertTrue(journeyTransfer.label.contains("HND") && journeyTransfer.label.contains("NRT"))
        journeyTransfer.tap()

        XCTAssertTrue(element("layoverTransitView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label == 'Airport transfer'")
        ).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'HND → NRT'")
        ).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Reach your next airport before adding a stop."].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Recommended route'")
        ).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'recommended arrival time is not ready yet'")
        ).firstMatch.exists)

        let transferAction = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Start HND' AND label CONTAINS[c] 'NRT transfer'")
        ).firstMatch
        scrollToElement(transferAction)
        XCTAssertTrue(transferAction.exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Fastest' OR label BEGINSWITH[c] 'Quickest'")).count,
            0,
            "An example transfer snapshot must never be presented as fastest"
        )
    }

    func testTravelerEntryCheckAndInFlightResearchScreensOpen() {
        launch()

        let entryCheck = app.buttons["Entry check"]
        scrollToElement(entryCheck)
        XCTAssertTrue(entryCheck.exists)
        entryCheck.tap()
        XCTAssertTrue(element("entryCheckView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Personalized entry check"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        let inFlight = app.buttons["In-flight progress"]
        scrollToElement(inFlight)
        XCTAssertTrue(inFlight.exists)
        inFlight.tap()
        XCTAssertTrue(element("inFlightProgressView").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["In-flight view"].exists)
    }

    func testSettingsExposePrivacyLearningAndSecretBoundary() {
        launch()
        selectTab("Settings")

        XCTAssertTrue(element("settingsView").waitForExistence(timeout: 5))
        let appleCalendar = app.switches["appleCalendarReminderToggle"]
        scrollToElement(appleCalendar)
        XCTAssertTrue(appleCalendar.exists)
        XCTAssertFalse(appleCalendar.isEnabled, "Example itineraries must not create external calendar records")
        XCTAssertTrue(element("appleCalendarReminderStatus").exists)
        let googleTasks = element("googleTasksReminderStatus")
        scrollToElement(googleTasks)
        XCTAssertTrue(googleTasks.exists)

        let dataConnection = element("liveTravelUpdatesStatus")
        scrollToElement(dataConnection)
        XCTAssertTrue(dataConnection.exists)
        let learning = app.switches["Learn from resolved journey data"]
        scrollToElement(learning)
        XCTAssertTrue(learning.exists)
    }

    func testOfflineModeIsExplicitAndKeepsOperationalFactsStale() {
        launch()
        app.terminate()
        launch(mode: "offline")

        XCTAssertTrue(app.staticTexts["Saved trip"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Needs refresh before planning'")
        ).firstMatch.exists)
        XCTAssertTrue(element("longHaulJourneyDashboard").exists)
    }

    func testJourneyAccessibilityAtLargeTextAndReducedMotion() throws {
        app.launchArguments = [
            "--uitesting", "--launch-mode", "demo",
            "--qa-accessibility-xxxl"
        ]
        app.launchEnvironment["UIAccessibilityIsReduceMotionEnabled"] = "YES"
        app.launch()

        XCTAssertTrue(element("longHaulJourneyDashboard").waitForExistence(timeout: 8))
        let persistentGate = app.buttons["universalReturnToGateButton"]
        XCTAssertLessThan(persistentGate.frame.height, app.frame.height / 3,
                          "The fixed gate action must leave room to read and scroll the journey")
        let gateAction = app.buttons["goToGateButton"]
        scrollToElement(gateAction, attempts: 80)
        XCTAssertTrue(gateAction.isHittable)
        // Audit at the scroll boundary where the derived tab-bar clearance keeps
        // passenger content out from under iOS 26's translucent system material.
        scrollToElement(app.buttons["AR guide"], attempts: 80)
        let swipeStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: persistentGate.frame.minY - 24))
        let swipeEnd = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: app.navigationBars.firstMatch.frame.maxY + 40))
        for _ in 0..<4 { swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd) }
        // The simulator sometimes audits a lazy-grid label above the visible
        // navigation boundary. Recheck every such finding with that label in
        // view; never accept an associated contrast finding without validation.
        var deferred: [String: XCUIElement] = [:]
        var rechecked = Set<String>()
        var activeRecheck: String?
        func audit(_ types: XCUIAccessibilityAuditType) throws {
            try app.performAccessibilityAudit(for: types) { issue in
                if issue.auditType == .contrast, issue.element == nil {
                    XCTContext.runActivity(named: "Unassociated iOS simulator contrast diagnostic") { activity in
                        activity.add(XCTAttachment(string: "\(issue.compactDescription)\n\(issue.detailedDescription)\nThe audit supplied no XCUIElement; associated issues are checked."))
                    }
                    return true
                }
                if issue.auditType == .contrast, let reported = issue.element {
                    let top = self.app.navigationBars.firstMatch.frame.maxY
                    let bottom = persistentGate.frame.minY
                    let visible = CGRect(x: 0, y: top, width: self.app.frame.width, height: bottom - top)
                    if !reported.frame.intersects(visible) {
                        let key = "\(reported.elementType.rawValue):\(reported.label)"
                        // Never conflate identical labels or suppress the
                        // finding currently being checked in view.
                        let matches = self.app.descendants(matching: reported.elementType)
                            .matching(NSPredicate(format: "label == %@", reported.label))
                        guard matches.count == 1, activeRecheck != key else { return false }
                        if !rechecked.contains(key) { deferred[key] = matches.firstMatch }
                        XCTContext.runActivity(named: "Recheck offscreen contrast in view: \(reported.label)") { activity in
                            activity.add(XCTAttachment(string: "Reported frame: \(reported.frame); unobstructed content: \(visible)"))
                        }
                        return true
                    }
                }
                return false
            }
        }
        try audit([.contrast, .elementDetection, .hitRegion,
                   .sufficientElementDescription, .textClipped, .trait])
        for _ in 0..<20 {
            guard let (key, target) = deferred.first else { break }
            deferred.removeValue(forKey: key)
            scrollToElement(target, attempts: 80)
            XCTAssertTrue(target.isHittable, "A deferred contrast finding must be visible for recheck")
            activeRecheck = key
            try audit(.contrast)
            activeRecheck = nil
            rechecked.insert(key)
        }
        XCTAssertTrue(deferred.isEmpty, "Every offscreen contrast finding must be rechecked in view")
    }

    func testJourneySupportsDynamicTypeAudit() throws {
        launch()
        XCTAssertTrue(element("longHaulJourneyDashboard").waitForExistence(timeout: 8))
        try app.performAccessibilityAudit(for: .dynamicType)
    }

    private func launch(mode: String = "demo", scenario: String? = nil) {
        app.launchArguments = ["--uitesting", "--launch-mode", mode]
        if let scenario { app.launchArguments += ["--scenario", scenario] }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
    }

    private func selectTab(_ name: String) {
        let direct = app.tabBars.firstMatch.buttons[name].firstMatch
        if direct.waitForExistence(timeout: 1) {
            direct.tap()
            return
        }
        app.tabBars.firstMatch.buttons["More"].firstMatch.tap()
        let item = app.tables.staticTexts[name]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "Could not find the \(name) tab")
        item.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func scrollToElement(_ element: XCUIElement, attempts: Int = 24) {
        // XCTest can report an offscreen child as hittable even beneath the
        // persistent gate action or tab bar. Keep taps inside passenger content.
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 100
        let gate = app.buttons["universalReturnToGateButton"]
        let bottom = gate.exists ? gate.frame.minY : app.tabBars.firstMatch.frame.minY
        func safelyVisible() -> Bool {
            element.exists && element.isHittable && element.frame.midY > top + 8 && element.frame.midY < bottom - 8
        }
        for _ in 0..<attempts {
            if safelyVisible() { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: bottom - 24))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: top + 60))
            if element.exists && !element.frame.isEmpty && element.frame.minY != 0 && element.frame.midY <= top + 8 {
                end.press(forDuration: 0.05, thenDragTo: start)
            } else {
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        XCTAssertTrue(safelyVisible(), "Could not reveal \(element) above persistent controls")
    }
}
