import XCTest

final class AirBorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState", "-skipOnboarding", "-walkingSpeed", "5.6"]
        app.launch()
    }

    func testFourTabsShowTheirScreens() {
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 5))
        app.buttons["tab-layover"].tap()
        XCTAssertTrue(app.staticTexts["Layover & transit"].waitForExistence(timeout: 2))
        app.buttons["tab-route"].tap()
        XCTAssertTrue(app.staticTexts["Route to Gate 105"].waitForExistence(timeout: 2))
        app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.staticTexts["Your profile"].waitForExistence(timeout: 2))
    }

    func testJourneyDetailsCheckpointOpensJourneySteps() {
        app.buttons["journeyDetailsLink"].tap()
        let line = app.buttons["checkpointLine"]
        XCTAssertTrue(line.waitForExistence(timeout: 2))
        XCTAssertTrue(line.label.contains("Security"))
        line.tap()
        XCTAssertTrue(app.staticTexts["Journey steps"].waitForExistence(timeout: 2))
        app.buttons["confirm-security"].tap()
        XCTAssertTrue(app.buttons["undo-security"].exists)
        XCTAssertTrue(app.buttons["skip-passport"].exists)
        app.buttons["back"].tap()
        XCTAssertTrue(app.buttons["checkpointLine"].label.contains("Passport control"))
    }

    func testAddStopsApplySuggestionAndUndo() {
        app.buttons["tab-layover"].tap()
        app.buttons["add-cafe"].tap()
        app.buttons["add-anaLounge"].tap()
        app.buttons["tab-flight"].tap()
        app.buttons["myPlanLink"].tap()
        let suggestion = app.descendants(matching: .any)["suggestion"]
        XCTAssertTrue(suggestion.waitForExistence(timeout: 2))
        XCTAssertTrue(suggestion.label.contains("Allow 10 more minutes for the café queue"))
        XCTAssertTrue(app.buttons["stop-anaLounge"].label.contains("28 min visit"), "Nothing changes before Apply")
        app.buttons["applySuggestion"].tap()
        XCTAssertTrue(app.buttons["undoToast"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["stop-anaLounge"].label.contains("16:43–17:01 · 18 min visit"))
        app.buttons["undoToast"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["suggestion"].waitForExistence(timeout: 2))
    }

    func testRouteStepsEndReturnsToFlight() {
        app.buttons["tab-route"].tap()
        XCTAssertTrue(app.staticTexts["Follow the Gates 105–109 sign"].waitForExistence(timeout: 2))
        app.buttons["nextStep"].tap()
        app.buttons["nextStep"].tap()
        XCTAssertTrue(app.staticTexts["Check your flight"].exists)
        app.buttons["endRoute"].tap()
        XCTAssertTrue(app.staticTexts["Your flight"].waitForExistence(timeout: 2))
    }

    func testWalkingPaceComesFromAppleHealth() {
        app.buttons["tab-profile"].tap()
        app.buttons["previousTripsRow"].tap()
        app.buttons["viewWalkingPace"].tap()
        XCTAssertTrue(app.staticTexts["No personal walking data"].waitForExistence(timeout: 2))
        app.buttons["Connect walking data"].tap()
        app.buttons["Connect Apple Health"].tap()
        XCTAssertTrue(app.staticTexts["Speed and distance · Synced just now"].waitForExistence(timeout: 3))
        app.buttons["back"].tap()
        XCTAssertTrue(app.staticTexts["5.6 km/h"].waitForExistence(timeout: 2))
        let paceWords = NSPredicate(format: "label CONTAINS[c] 'slow' OR label CONTAINS[c] 'fast'")
        XCTAssertFalse(app.staticTexts.containing(paceWords).firstMatch.exists)
    }
}
