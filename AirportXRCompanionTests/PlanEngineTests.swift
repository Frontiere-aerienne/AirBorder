@testable import AirBorder
import XCTest

final class PlanEngineTests: XCTestCase {
    private let both = Plan(stops: [.cafe, .anaLounge])

    func testNoStopsLeavesInTimeToArriveAtTarget() {
        let schedule = PlanEngine.schedule(Plan(), pace: .average)
        XCTAssertEqual(schedule.leave.description, "16:53")
        XCTAssertEqual(schedule.arriveAtGate.description, "17:05")
        XCTAssertEqual(durationText(schedule.leave - SampleJourney.now), "4h 53m")
    }

    func testCafeThenLoungeMatchesMyPlan() {
        let schedule = PlanEngine.schedule(both, pace: .average)
        XCTAssertEqual(PlanText.timing(schedule.stops[0]), "16:00–16:28 · 8 min wait + 20 min visit")
        XCTAssertEqual(PlanText.timing(schedule.stops[1]), "16:33–17:01 · 28 min visit")
        XCTAssertEqual(PlanText.walk(schedule.stops[1]), "5 min walk from the café")
        XCTAssertEqual(PlanText.arrivalTitle(schedule), "Arrive at your gate by 17:05")
        XCTAssertEqual(PlanText.arrivalDetail(schedule), "Leave ANA LOUNGE at 17:01. Gate closes at 17:25.")
    }

    func testShorterCafeAndReorderRecompute() {
        var shorter = both
        shorter.stops[0].visitMinutes = 15
        let first = PlanEngine.schedule(shorter, pace: .average)
        XCTAssertEqual(first.stops[1].start.description, "16:28")
        XCTAssertEqual(first.arriveAtGate.description, "17:00")

        let reordered = Plan(stops: [.anaLounge, .cafe])
        let second = PlanEngine.schedule(reordered, pace: .average)
        XCTAssertEqual(second.stops[0].start.description, "16:05")
        XCTAssertEqual(second.stops[1].end.description, "17:06")
        XCTAssertEqual(second.arriveAtGate.description, "17:14")
    }

    func testQueueUpdateSuggestsShorteningTheLaterSelectedStop() throws {
        let update = QueueUpdate(stopID: .cafe, waitMinutes: 18)
        let suggestion = try XCTUnwrap(PlanEngine.suggestion(for: both, update: update, pace: .average))
        XCTAssertEqual(suggestion.title, "Allow 10 more minutes for the café queue")
        XCTAssertEqual(suggestion.detail, "Shorten ANA LOUNGE to 18 min to still arrive by 17:05.")
        let applied = PlanEngine.schedule(suggestion.proposed, pace: .average)
        XCTAssertEqual(PlanText.timing(applied.stops[0]), "16:00–16:38 · 18 min for the queue + 20 min visit")
        XCTAssertEqual(PlanText.timing(applied.stops[1]), "16:43–17:01 · 18 min visit")
        XCTAssertEqual(applied.arriveAtGate.description, "17:05")
        // The proposal never touches stops that were not in the selected plan.
        XCTAssertEqual(suggestion.proposed.stops.map(\.id), both.stops.map(\.id))
    }

    func testNoSuggestionWhenNothingLaterCanAbsorbTheDelay() {
        let cafeLast = Plan(stops: [.anaLounge, .cafe])
        XCTAssertNil(PlanEngine.suggestion(for: cafeLast, update: QueueUpdate(stopID: .cafe, waitMinutes: 18), pace: .average))
        XCTAssertNil(PlanEngine.suggestion(for: Plan(stops: [.cafe]), update: QueueUpdate(stopID: .cafe, waitMinutes: 18), pace: .average))
    }

    func testPersonalPaceScalesWalkingTimes() {
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .average), 12)
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 4.2)), 12)
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 5.6)), 9)
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 3.0)), 17)
        // Implausible readings fall back to average times.
        XCTAssertEqual(WalkingTimes.minutes(average: 12, pace: .personal(kmh: 0.2)), 12)
        XCTAssertEqual(PaceText.kmh(4.64), "4.6 km/h")
    }

    func testEstimatesStartFromAirportWalksAndAppleHealthRefinesThem() {
        let walks = SampleJourney.airportWalks
        XCTAssertEqual(WalkingEstimate.kmh(walks: walks), 4.2)
        XCTAssertEqual(WalkingEstimate.pace(walks: walks, healthKmh: nil), .personal(kmh: 4.2))
        guard case let .personal(blended) = WalkingEstimate.pace(walks: walks, healthKmh: 5.6) else { return XCTFail("Expected a personal pace") }
        XCTAssertEqual(PaceText.kmh(blended), "4.9 km/h")
        XCTAssertEqual(WalkingEstimate.pace(walks: [], healthKmh: nil), .average)
        XCTAssertEqual(WalkingEstimate.pace(walks: [], healthKmh: 5.0), .personal(kmh: 5.0))
    }
}

final class JourneyChecklistTests: XCTestCase {
    func testNowIsFirstUnconfirmedStep() {
        let checklist = JourneyChecklist.haneda
        XCTAssertEqual(checklist.current?.title, "Security")
        XCTAssertEqual(checklist.next?.title, "Passport control")
        XCTAssertEqual(checklist.status(of: checklist.steps[2]), "Now")
        XCTAssertEqual(checklist.status(of: checklist.steps[3]), "Next")
    }

    func testConfirmSkipAndUndo() {
        var checklist = JourneyChecklist.haneda
        XCTAssertFalse(checklist.canConfirm("passport"), "Only the current step can be confirmed")
        checklist.skip("passport")
        XCTAssertEqual(checklist.next?.title, "Gate and boarding")
        checklist.undo()
        XCTAssertEqual(checklist.next?.title, "Passport control")
        checklist.confirm("security")
        XCTAssertEqual(checklist.current?.title, "Passport control")
        XCTAssertTrue(checklist.canUndo("security"))
        checklist.undo()
        XCTAssertEqual(checklist.current?.title, "Security")
        XCTAssertFalse(checklist.canSkip("security"))
    }

    func testCompletes() {
        var checklist = JourneyChecklist.haneda
        checklist.confirm("security")
        checklist.skip("passport")
        checklist.confirm("gate")
        XCTAssertTrue(checklist.isComplete)
        XCTAssertNil(checklist.current)
    }
}

@MainActor
final class JourneyStoreTests: XCTestCase {
    private func makeStore(kmh: Double? = nil) -> JourneyStore {
        let defaults = UserDefaults(suiteName: "JourneyStoreTests-\(UUID().uuidString)")!
        return JourneyStore(walkingData: FixedWalkingData(kmh: kmh), defaults: defaults)
    }

    func testSuggestionAppliesOnlyAfterApplyAndCanBeUndone() {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        XCTAssertNotNil(store.suggestion)
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 28, "Nothing changes before Apply")
        store.applySuggestion()
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 18)
        XCTAssertNil(store.suggestion)
        store.undoSuggestion()
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 28)
        XCTAssertNotNil(store.suggestion)
    }

    func testKeepPlanKeepsStopsButCountsTheQueue() {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        store.keepPlan()
        XCTAssertEqual(store.plan.stops[1].visitMinutes, 28)
        XCTAssertEqual(store.plan.stops[0].waitMinutes, 18)
        XCTAssertEqual(store.schedule.arriveAtGate.description, "17:15")
    }

    func testPlanChangeDropsStaleSuggestion() {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        store.remove(.anaLounge)
        XCTAssertNil(store.suggestion)
    }

    func testAppleHealthRefinesAirportWalkEstimate() async {
        let store = makeStore(kmh: 5.6)
        XCTAssertEqual(store.pace, .personal(kmh: 4.2), "Airport walks come first")
        XCTAssertEqual(store.gateWalkMinutes, 12)
        await store.connectHealth()
        XCTAssertEqual(store.gateWalkMinutes, 11, "Apple Health refines the estimate")
        store.removeHealth()
        XCTAssertEqual(store.health, .removed)
        XCTAssertEqual(store.pace, .personal(kmh: 4.2))
    }

    func testStepFreePreferenceSelectsStepFreeRoute() {
        let store = makeStore()
        store.stepFreeRoutes = true
        XCTAssertEqual(store.routeChoice, .stepFree)
        XCTAssertEqual(store.gateWalkMinutes, 16)
    }
}

final class TicketReaderTests: XCTestCase {
    func testReadsFlightDateAndRouteFromItineraryText() {
        let text = """
        ANA itinerary
        Flight NH 106  HND → LAX
        Departure 15 Oct 2026 18:00 Terminal 3
        """
        let ticket = TicketReader.parse(text, source: "ANA-itinerary.pdf")
        XCTAssertEqual(ticket?.number, "NH 106")
        XCTAssertEqual(ticket?.date, "2026-10-15")
        XCTAssertEqual(ticket?.route, "HND → LAX")
    }

    func testReadsBoardingPassStyleText() {
        let ticket = TicketReader.parse("BOARDING PASS JL043 21OCT LAX TO HND SEAT 3A", source: "Your ticket photo", defaultYear: 2026)
        XCTAssertEqual(ticket?.number, "JL 43")
        XCTAssertEqual(ticket?.date, "2026-10-21")
        XCTAssertEqual(ticket?.from, "LAX")
    }

    func testNoFlightNumberMeansUnreadable() {
        XCTAssertNil(TicketReader.parse("Thank you for shopping with us", source: "receipt.pdf"))
    }

    func testRejectsImpossibleDates() {
        XCTAssertNil(TicketReader.date(in: "2026-02-31", defaultYear: 2026))
        XCTAssertNil(TicketReader.date(in: "45 OCT 2026", defaultYear: 2026))
    }
}
