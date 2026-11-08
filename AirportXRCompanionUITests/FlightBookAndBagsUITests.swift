import XCTest

final class FlightBookAndBagsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testExampleBKKHNDLAXShowsThroughCheckedFactAndExternalFareComparison() {
        launchDemo()
        selectFlightsAndBookBags()

        let state = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Through-checked'")
        ).firstMatch
        scrollToElement(state)
        XCTAssertTrue(state.exists)
        XCTAssertTrue(state.label.localizedCaseInsensitiveContains("Through-checked"))
        let bagDestination = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'LAX'")
        ).firstMatch
        scrollToElement(bagDestination)
        XCTAssertTrue(bagDestination.exists)
        let demoNotice = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Trip details'")
        ).firstMatch
        scrollToElement(demoNotice)
        XCTAssertTrue(demoNotice.exists)

        let search = app.buttons["Compare fares"]
        scrollToElement(search)
        XCTAssertTrue(search.isHittable)
        search.tap()

        let handoff = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Open Google Flights'")
        ).firstMatch
        scrollToElement(handoff)
        XCTAssertTrue(handoff.isHittable)
        XCTAssertTrue(element("googleFlightsHandoffLink").exists)
    }

    func testExampleHNDNRTShowsReclaimSequenceInterAirportStepAndBagDropCutoff() {
        launchDemo(scenario: "interAirport")
        selectFlightsAndBookBags()

        let state = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Reclaim' AND label CONTAINS[c] 'recheck'")
        ).firstMatch
        scrollToElement(state)
        XCTAssertTrue(state.exists)
        XCTAssertTrue(state.label.localizedCaseInsensitiveContains("Reclaim"))

        let interAirport = app.staticTexts["Inter-airport travel"]
        scrollToElement(interAirport)
        XCTAssertTrue(interAirport.exists)
        XCTAssertTrue(app.staticTexts["Baggage reclaim wait"].exists)
        XCTAssertTrue(app.staticTexts["Immigration / border processing"].exists)
        XCTAssertTrue(app.staticTexts["Customs processing"].exists)
        XCTAssertTrue(app.staticTexts["Bag drop and check-in"].exists)
        XCTAssertTrue(app.staticTexts["Security screening"].exists)
        XCTAssertTrue(app.staticTexts["Bag-drop/check-in cutoff"].exists)
    }

    private func launchDemo(scenario: String? = nil) {
        app.launchArguments = ["--uitesting", "--launch-mode", "demo"]
        if let scenario { app.launchArguments += ["--scenario", scenario] }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Preparing your journey"].waitForNonExistence(timeout: 60),
                      "Journey preparation must finish before navigation")
    }

    private func selectFlightsAndBookBags() {
        let flights = app.tabBars.firstMatch.buttons["Flights"].firstMatch
        if flights.waitForExistence(timeout: 1) {
            flights.tap()
        } else {
            app.tabBars.firstMatch.buttons["More"].firstMatch.tap()
            let item = app.tables.staticTexts["Flights"]
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            item.tap()
        }
        XCTAssertTrue(element("itineraryEditor").waitForExistence(timeout: 5))
        let mode = app.segmentedControls.buttons["Book & bags"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        XCTAssertTrue(element("bookAndBagsPanel").waitForExistence(timeout: 5))
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
