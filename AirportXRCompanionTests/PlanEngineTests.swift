// PROCEDURAL: Verifies timing and journey state with controlled inputs.

@testable import AirBorder
import XCTest

final class PlanEngineTests: XCTestCase {
    private let both = Plan(stops: [.cafe, .anaLounge])

    func testNoStopsLeavesInTimeToArriveAtTarget() throws {
        let schedule = try XCTUnwrap(PlanEngine.schedule(Plan(), pace: .average, context: SampleJourney.planning))
        XCTAssertEqual(schedule.leave.description, "16:53")
        XCTAssertEqual(schedule.arriveAtGate.description, "17:05")
        XCTAssertEqual(durationText(schedule.leave - SampleJourney.now), "4h 53m")
    }

    func testCafeThenLoungeMatchesMyPlan() throws {
        let schedule = try XCTUnwrap(PlanEngine.schedule(both, pace: .average, context: SampleJourney.planning))
        XCTAssertEqual(PlanText.timing(schedule.stops[0]), "16:00–16:28, 8 min wait + 20 min visit")
        XCTAssertEqual(PlanText.timing(schedule.stops[1]), "16:33–17:01, 28 min visit")
        XCTAssertEqual(PlanText.walk(schedule.stops[1]), "5 min walk from the café")
        XCTAssertEqual(PlanText.arrivalTitle(schedule), "Arrive at your gate by 17:05")
        XCTAssertEqual(PlanText.arrivalDetail(schedule), "Leave ANA LOUNGE at 17:01. Gate closes at 17:25.")
    }

    func testShorterCafeAndReorderRecompute() throws {
        var shorter = both
        shorter.stops[0].visitMinutes = 15
        let first = try XCTUnwrap(PlanEngine.schedule(shorter, pace: .average, context: SampleJourney.planning))
        XCTAssertEqual(first.stops[1].start.description, "16:28")
        XCTAssertEqual(first.arriveAtGate.description, "17:00")

        let reordered = Plan(stops: [.anaLounge, .cafe])
        let second = try XCTUnwrap(PlanEngine.schedule(reordered, pace: .average, context: SampleJourney.planning))
        XCTAssertEqual(second.stops[0].start.description, "16:05")
        XCTAssertEqual(second.stops[1].end.description, "17:06")
        XCTAssertEqual(second.arriveAtGate.description, "17:14")
    }

    func testQueueUpdateSuggestsShorteningTheLaterSelectedStop() throws {
        let update = QueueUpdate(stopID: .cafe, waitMinutes: 18)
        let suggestion = try XCTUnwrap(PlanEngine.suggestion(for: both, update: update, pace: .average, context: SampleJourney.planning))
        XCTAssertEqual(suggestion.title, "Allow 10 more minutes for the café queue")
        XCTAssertEqual(suggestion.detail, "Shorten ANA LOUNGE to 18 min to still arrive by 17:05.")
        let applied = try XCTUnwrap(PlanEngine.schedule(suggestion.proposed, pace: .average, context: SampleJourney.planning))
        XCTAssertEqual(PlanText.timing(applied.stops[0]), "16:00–16:38, 18 min for the queue + 20 min visit")
        XCTAssertEqual(PlanText.timing(applied.stops[1]), "16:43–17:01, 18 min visit")
        XCTAssertEqual(applied.arriveAtGate.description, "17:05")
        // The proposal never touches stops that were not in the selected plan.
        XCTAssertEqual(suggestion.proposed.stops.map(\.id), both.stops.map(\.id))
    }

    func testNoSuggestionWhenNothingLaterCanAbsorbTheDelay() {
        let cafeLast = Plan(stops: [.anaLounge, .cafe])
        XCTAssertNil(PlanEngine.suggestion(for: cafeLast, update: QueueUpdate(stopID: .cafe, waitMinutes: 18), pace: .average, context: SampleJourney.planning))
        XCTAssertNil(PlanEngine.suggestion(for: Plan(stops: [.cafe]), update: QueueUpdate(stopID: .cafe, waitMinutes: 18), pace: .average, context: SampleJourney.planning))
    }

    func testDifferentAirportRouteUsesSuppliedNodesTimesAndDeadline() throws {
        let food = PlanStop(id: PlaceID(rawValue: "atl-B-food"), name: "Concourse B deli",
                            shortName: "deli", waitMinutes: 5, visitMinutes: 10)
        let lounge = PlanStop(id: PlaceID(rawValue: "atl-B-lounge"), name: "Concourse B lounge",
                              shortName: "lounge", waitMinutes: 0, visitMinutes: 20)
        let context = PlanningContext(planStart: ClockTime(8, 0), gateArrivalTarget: ClockTime(8, 55), gateCloses: ClockTime(9, 5)) { from, to in
            switch (from, to) {
            case (.start, food.id): return 4
            case (food.id, lounge.id): return 6
            case (lounge.id, .gate): return 7
            default: return nil
            }
        }
        let plan = Plan(stops: [food, lounge])
        let schedule = try XCTUnwrap(PlanEngine.schedule(plan, pace: .average, context: context))
        XCTAssertEqual(schedule.stops.map(\.walkFromPrevious), [4, 6])
        XCTAssertEqual(schedule.arriveAtGate, ClockTime(8, 52))
        XCTAssertEqual(schedule.gateCloses, ClockTime(9, 5))
        let update = QueueUpdate(stopID: food.id, waitMinutes: 12)
        let suggestion = try XCTUnwrap(PlanEngine.suggestion(for: plan, update: update, pace: .average, context: context))
        XCTAssertEqual(suggestion.shortenedStop.visitMinutes, 16)
        XCTAssertTrue(suggestion.detail.contains("08:55"))
        XCTAssertNil(PlanEngine.schedule(Plan(stops: [lounge, food]), pace: .average, context: context),
                     "An unmodeled direction must not inherit a fixture walking time")
        XCTAssertNil(PlanEngine.schedule(Plan(), pace: .average, context: context),
                     "A missing direct walk must not be guessed")
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

    private func flight(id: String, from: Airport, to: Airport, departureGate: String,
                        departs: ClockTime, arrives: ClockTime) -> FlightLeg {
        FlightLeg(id: id, airline: Airline(code: "AS", name: "Alaska Airlines"), number: id, from: from, to: to, departs: departs, arrives: arrives,
                  arrivalDayOffset: nil, status: "Scheduled", departureTerminal: "B", departureGate: departureGate,
                  gateCloses: nil, arrivalTerminal: "B", arrivalGate: "B2", baggageBelt: nil, date: "2026-11-17")
    }

    func testSuppliedJourneyDoesNotInheritFixtureData() async {
        let lax = Airport(code: "LAX", city: "Los Angeles")
        let atl = Airport(code: "ATL", city: "Atlanta")
        let bos = Airport(code: "BOS", city: "Boston")
        let connection = JourneyDefinition(
            inbound: flight(id: "EX 12", from: lax, to: atl, departureGate: "A2", departs: ClockTime(8, 0), arrives: ClockTime(12, 0)),
            outbound: flight(id: "EX 18", from: atl, to: bos, departureGate: "B9", departs: ClockTime(13, 0), arrives: ClockTime(15, 0)),
            planning: PlanningContext(planStart: ClockTime(12, 0), gateArrivalTarget: ClockTime(12, 40), gateCloses: nil) {
                $0 == .start && $1 == .gate ? 17 : nil
            },
            boarding: nil, now: ClockTime(12, 5)
        )
        let defaults = UserDefaults(suiteName: "SuppliedJourneyTests-\(UUID().uuidString)")!
        let sample = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
        sample.add(.cafe)
        sample.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(12, 0)))
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults, journey: connection)
        XCTAssertEqual(store.inbound.to.code, "ATL")
        XCTAssertEqual(store.outbound.to.code, "BOS")
        XCTAssertEqual(store.outbound.airline.code, "AS")
        XCTAssertNil(store.outbound.airline.logoAsset)
        XCTAssertNil(store.baggagePreference)
        XCTAssertNil(store.layoverMinutes, "Do not subtract local clocks across airports")
        XCTAssertFalse(store.isAirportTransfer)
        XCTAssertFalse(store.hasConcourseCoverage)
        XCTAssertNil(store.transferDetails)
        XCTAssertTrue(store.plan.stops.isEmpty)
        XCTAssertNil(store.feed)
        XCTAssertEqual(store.pace, .average)
        XCTAssertEqual(store.knownGateWalkMinutes(for: .direct), 17)
        XCTAssertNil(store.knownGateWalkMinutes(for: .stepFree))
        XCTAssertEqual(store.schedule?.leave, ClockTime(12, 23))
        XCTAssertTrue(RouteSteps.steps(for: .direct, store: store).isEmpty, "No fixture map without its coverage")
        store.startSampleFeed(after: .zero)
        await Task.yield()
        XCTAssertEqual(store.gate, "B9")
        store.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(12, 15), flightID: "NH106"))
        XCTAssertEqual(store.gate, "B9")
        store.receive(FlightFeed(gate: "B11", receivedAt: ClockTime(12, 15), flightID: connection.outbound.id))
        XCTAssertEqual(store.gate, "B11")
        XCTAssertNil(store.schedule, "A different gate needs its own timing input")

        var withDirections = connection
        withDirections.gateDirections = GateDirections(gate: "B9", instructions: ["Follow the Concourse B signs", "Check the gate display"])
        let routed = JourneyStore(walkingData: FixedWalkingData(kmh: nil),
                                  defaults: UserDefaults(suiteName: "DirectDirections-\(UUID().uuidString)")!, journey: withDirections)
        XCTAssertEqual(RouteSteps.steps(for: .direct, store: routed).map(\.text), ["Follow the Concourse B signs", "Check the gate display"])
        XCTAssertFalse(routed.hasConcourseCoverage, "Text instructions are not a map or AR coverage")
        routed.receive(FlightFeed(gate: "B11", receivedAt: ClockTime(12, 15), flightID: withDirections.outbound.id))
        XCTAssertTrue(RouteSteps.steps(for: .direct, store: routed).isEmpty, "Do not reuse the old gate's directions")
    }

    func testSuppliedAirportChangeDoesNotInheritNaritaInstructions() {
        let jfk = Airport(code: "JFK", city: "New York")
        let lga = Airport(code: "LGA", city: "New York")
        let bos = Airport(code: "BOS", city: "Boston")
        let definition = JourneyDefinition(
            inbound: flight(id: "EX 12", from: bos, to: jfk, departureGate: "B3", departs: ClockTime(8, 0), arrives: ClockTime(9, 0)),
            outbound: flight(id: "EX 18", from: lga, to: bos, departureGate: "B9", departs: ClockTime(13, 0), arrives: ClockTime(15, 0)),
            planning: nil, boarding: nil, now: ClockTime(10, 0)
        )
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil),
                                 defaults: UserDefaults(suiteName: "TransferCoverage-\(UUID().uuidString)")!, journey: definition)
        XCTAssertTrue(store.isAirportTransfer)
        XCTAssertEqual(store.outbound.from.code, "LGA")
        XCTAssertEqual(store.primaryCondition, .airportTransfer)
        XCTAssertNil(store.transferDetails)
        XCTAssertFalse(store.hasConcourseCoverage)
        XCTAssertNil(store.schedule)
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
        XCTAssertEqual(store.schedule?.arriveAtGate.description, "17:15")
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

/// Situations come only from their conditions (Figma scenarios: gate change, return, at risk, assistance, transfer).
final class JourneyConditionTests: XCTestCase {
    private func inputs(now: ClockTime, feedGate: String? = nil, closes: ClockTime? = ClockTime(17, 25), atGate: Bool = false, transfer: Bool = false) -> ConditionInputs {
        ConditionInputs(
            now: now,
            ticketGate: "105",
            feed: feedGate.map { FlightFeed(gate: $0, receivedAt: ClockTime(12, 0)) },
            gateCloses: closes,
            walkToGate: 12,
            leaveBy: ClockTime(16, 53),
            atGate: atGate,
            departsFromAnotherAirport: transfer
        )
    }

    func testNothingToReportAtNoon() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(12, 0))), [])
    }

    func testGateChangeComesFromTheFeed() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(12, 0), feedGate: "108A")), [.gateChanged(from: "105", to: "108A")])
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(12, 0), feedGate: "105")), [], "Same gate is not a change")
    }

    func testReturnNowAtFigmaTime() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 0))), [.returnNow(closesIn: 25, walk: 12)])
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(16, 52))), [], "Not before the leave time")
    }

    func testBoardingAtRiskAtFigmaTime() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 10))), [.boardingAtRisk(closesIn: 15, walk: 12)])
    }

    func testArrivalAfterClosureAtFigmaTime() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 17))), [.arrivesAfterClosure(arrival: ClockTime(17, 29), minutesLate: 4)])
    }

    func testMostUrgentFirstWhenSeveralHold() {
        let found = JourneyConditions.evaluate(inputs(now: ClockTime(17, 10), feedGate: "108A"))
        XCTAssertEqual(found, [.boardingAtRisk(closesIn: 15, walk: 12), .gateChanged(from: "105", to: "108A")])
    }

    func testNoTimingSituationOnceAtTheGateOrWhenClosingTimeIsUnknown() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 17), atGate: true)), [])
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 17), closes: nil)), [], "Unknown closing time is never treated as late or fine")
    }

    func testTransferReplacesHanedaSituations() {
        XCTAssertEqual(JourneyConditions.evaluate(inputs(now: ClockTime(17, 10), feedGate: "108A", transfer: true)), [.airportTransfer])
    }

    func testReminderOnlyWhenSeenAndNotActedOn() {
        let seen = Date(timeIntervalSince1970: 0)
        var record = AlertRecord(issuedAt: ClockTime(12, 0), firstSeen: seen)
        XCTAssertFalse(record.isReminder(at: seen.addingTimeInterval(60)))
        XCTAssertTrue(record.isReminder(at: seen.addingTimeInterval(AlertRecord.reminderInterval)))
        record.acknowledged = true
        XCTAssertFalse(record.isReminder(at: seen.addingTimeInterval(3600)))
        XCTAssertFalse(AlertRecord(issuedAt: ClockTime(12, 0)).isReminder(at: seen), "Never shown, so no reminder")
    }
}

@MainActor
final class JourneySituationStoreTests: XCTestCase {
    private func makeStore() -> JourneyStore {
        let defaults = UserDefaults(suiteName: "JourneySituationStoreTests-\(UUID().uuidString)")!
        return JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
    }

    func testGateUpdateRaisesOneAlertAndChangesTheGateEverywhere() {
        let store = makeStore()
        XCTAssertEqual(store.gate, "105")
        store.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(12, 0)))
        XCTAssertEqual(store.gate, "108A")
        XCTAssertEqual(store.alertToPresent, .gateChange)
        XCTAssertEqual(store.alerts[.gateChange]?.issuedAt, ClockTime(12, 0))
        store.alertToPresent = nil
        store.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(12, 5)))
        XCTAssertNil(store.alertToPresent, "The same update does not alert twice")
        store.acknowledge(.gateChange)
        XCTAssertEqual(store.alerts[.gateChange]?.acknowledged, true)
    }

    func testGateChangeReopensConfirmedArrivalEvenWhenReturningToOriginalGate() {
        let store = makeStore()
        store.confirmStep("security")
        store.skipStep("passport")
        let firstAssignment = store.gateAssignmentRevision
        store.confirmStep("gate", assignmentRevision: firstAssignment)
        store.setNow(ClockTime(17, 8))
        XCTAssertTrue(store.conditionInputs.atGate)
        store.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(17, 8)))
        XCTAssertEqual(store.checklist.current?.id, "gate")
        XCTAssertEqual(store.checklist.steps.first { $0.id == "security" }?.state, .confirmed)
        XCTAssertTrue(store.conditions.contains(.boardingAtRisk(closesIn: 17, walk: 12)))
        store.confirmStep("gate", assignmentRevision: store.gateAssignmentRevision)
        store.receive(FlightFeed(gate: "105", receivedAt: ClockTime(17, 9)))
        store.confirmStep("gate", assignmentRevision: firstAssignment)
        XCTAssertEqual(store.checklist.current?.id, "gate")
        XCTAssertTrue(store.conditions.contains(.gateChanged(from: "108A", to: "105")))
        XCTAssertEqual(store.alertToPresent, .gateChange)
    }

    func testUrgentRouteBypassesOptionalStopsWithoutChangingPlan() {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        let saved = store.plan
        store.openRoute()
        XCTAssertEqual(RouteSteps.stopsInOrder(store).map(\.id), [.cafe, .anaLounge])
        store.setNow(ClockTime(17, 2))
        XCTAssertTrue(store.hasTimingSituation)
        store.openRoute(directToGate: true)
        let steps = RouteSteps.steps(for: .direct, store: store)
        XCTAssertEqual(steps.first?.remaining, "12 min")
        XCTAssertFalse(steps.contains { $0.turn == .stop })
        XCTAssertEqual(store.plan, saved)
        store.setNow(ClockTime(17, 17))
        store.receive(FlightFeed(gate: "108A", receivedAt: ClockTime(17, 17)))
        store.openRoute()
        XCTAssertEqual(store.timingCondition, .arrivesAfterClosure(arrival: ClockTime(17, 29), minutesLate: 4))
        XCTAssertTrue(RouteSteps.stopsInOrder(store).isEmpty, "A simultaneous gate change does not hide an urgent return")
        store.setNow(ClockTime(12, 0))
        store.openRoute()
        XCTAssertEqual(RouteSteps.stopsInOrder(store).map(\.id), [.cafe, .anaLounge])
    }

    func testCameraArrowMatchesTheInstructionOrIsOmitted() {
        XCTAssertEqual(RouteStep.Turn.straight.cameraArrow, "camArrowForward")
        XCTAssertEqual(RouteStep.Turn.right.cameraArrow, "camArrowRight")
        XCTAssertEqual(RouteStep.Turn.left.cameraArrow, "camArrowRight")
        XCTAssertFalse(RouteStep.Turn.right.mirrorsCameraArrow)
        XCTAssertTrue(RouteStep.Turn.left.mirrorsCameraArrow)
        for turn in [RouteStep.Turn.stairs, .lift, .stop, .gate] { XCTAssertNil(turn.cameraArrow) }
    }

    func testStopsMoveTheLeaveTimeForReturnNow() throws {
        let store = makeStore()
        store.setNow(ClockTime(16, 40))
        XCTAssertNil(store.primaryCondition)
        store.add(.cafe)
        let schedule = try XCTUnwrap(store.schedule)
        XCTAssertEqual(store.conditionInputs.leaveBy, SampleJourney.gateArrivalTarget - schedule.walkToGate)
    }

    func testChoosingNH6StartsTheNaritaTransfer() {
        let store = makeStore()
        store.beginEditingFlight()
        store.flightDraft.number = "NH 6"
        store.saveFlightDraft()
        XCTAssertTrue(store.isAirportTransfer)
        XCTAssertEqual(store.primaryCondition, .airportTransfer)
        XCTAssertEqual(store.checklist.steps.map(\.id), ["arrival", "passport", "bags", "customs", "narita"])
        XCTAssertEqual(store.layoverMinutes, 9 * 60 + 45)
        store.beginEditingFlight()
        store.flightDraft.number = "NH 106"
        store.saveFlightDraft()
        XCTAssertEqual(store.checklist, .haneda)
    }
}

final class SignMatcherTests: XCTestCase {
    func testReadsHanedaGateSignsWhateverTheDash() {
        XCTAssertTrue(SignMatcher.matches(["← 110", "↑ 105-109"], .gates105to109))
        XCTAssertTrue(SignMatcher.matches(["搭乗口 Gates 105–109"], .gates105to109))
        XCTAssertTrue(SignMatcher.matches(["105 - 109"], .gates105to109))
        XCTAssertFalse(SignMatcher.matches(["← 110", "108-149"], .gates105to109))
        XCTAssertTrue(SignMatcher.matches(["Gates 108–149"], .gates108to149))
    }

    func testReadsBusAndLoungeSignsInEnglishOrJapanese() {
        XCTAssertTrue(SignMatcher.matches(["バス乗り場"], .bus))
        XCTAssertTrue(SignMatcher.matches(["Bus"], .bus))
        XCTAssertTrue(SignMatcher.matches(["航空会社ラウンジ"], .lounges))
        XCTAssertTrue(SignMatcher.matches(["Airline Lounges"], .lounges))
        XCTAssertFalse(SignMatcher.matches(["Restrooms"], .lounges))
    }
}

final class TerminalTwoTimingTests: XCTestCase {
    func testVisitFitsOnlyUntilTheLatestStart() {
        // Leave T2 by 15:53 with a 12 min gate walk; 30 min to get there and a 30 min visit.
        XCTAssertEqual(TerminalTwo.leaveBy(gateWalk: 12), ClockTime(15, 53))
        XCTAssertTrue(TerminalTwo.hasTime(now: ClockTime(12, 0), gateWalk: 12))
        XCTAssertTrue(TerminalTwo.hasTime(now: ClockTime(14, 53), gateWalk: 12))
        XCTAssertFalse(TerminalTwo.hasTime(now: ClockTime(14, 54), gateWalk: 12))
    }

    func testStopTimesStepByFifteenMinutesWithinLimits() {
        let latest = ClockTime(16, 59)
        XCTAssertEqual(StopTimes.earlierLeave(latest, earliestAllowed: ClockTime(16, 28))?.description, "16:45")
        XCTAssertEqual(StopTimes.laterLeave(ClockTime(16, 45), latest: latest)?.description, "16:59")
        XCTAssertNil(StopTimes.laterLeave(latest, latest: latest), "Never past the latest leave")
        XCTAssertNil(StopTimes.earlierArrive(ClockTime(15, 0), earliestAllowed: SampleJourney.planning.timelineStart), "Plan starts at 15:00")
        XCTAssertNil(StopTimes.laterArrive(ClockTime(16, 30), latestAllowed: ClockTime(16, 44)), "Keeps at least 15 min")
        XCTAssertEqual(StopTimes.laterArrive(ClockTime(16, 0), latestAllowed: ClockTime(16, 44))?.description, "16:15")
    }

    @MainActor
    func testRouteStepsFollowTheMap() {
        let defaults = UserDefaults(suiteName: "routeSteps")!
        defaults.removePersistentDomain(forName: "routeSteps")
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
        XCTAssertEqual(RouteSteps.steps(for: .direct, store: store).map(\.text), [
            "Follow the Gates 105–109 sign", "Take the stairs at the junction", "Go straight past Gate 104",
            "Turn left at the Gate 105 sign", "Check NH 106 on the gate screen",
        ], "No stops: the Figma direct route")
        XCTAssertEqual(RouteSteps.steps(for: .direct, store: store).first?.remaining, "12 min")
        store.add(.cafe)
        store.add(.anaLounge)
        for choice in RouteChoice.allCases {
            let steps = RouteSteps.steps(for: choice, store: store)
            print("ROUTE \(choice):", steps.map { "[\($0.distance)] \($0.text) (\($0.remaining))" }.joined(separator: " | "))
            XCTAssertEqual(steps.filter { $0.turn == .stop }.map(\.text), [
                "Stop at Curacion Cafe, leave by 16:38", "Stop at ANA LOUNGE, leave by 17:11",
            ])
        }
    }

    @MainActor
    func testStopEditsChangeArrivalAndRouteTogether() {
        let defaults = UserDefaults(suiteName: "planTimes")!
        defaults.removePersistentDomain(forName: "planTimes")
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
        store.setNow(ClockTime(16, 50))
        XCTAssertEqual(store.minutesToSpare, 3, "Slack includes the twelve-minute walk and the planning target")
        store.setNow(ClockTime(12, 0))
        store.add(.cafe)
        store.add(.anaLounge)
        XCTAssertEqual(store.schedule?.arriveAtGate, ClockTime(17, 15))
        store.setTimes(.anaLounge, leave: ClockTime(17, 1))
        XCTAssertEqual(store.schedule?.arriveAtGate, ClockTime(17, 5))
        XCTAssertEqual(store.minutesToSpare, 0)
        XCTAssertTrue(RouteSteps.steps(for: .direct, store: store).contains {
            $0.text == "Stop at ANA LOUNGE, leave by 17:01"
        })
        store.setTimes(.anaLounge, arrive: ClockTime(16, 45))
        XCTAssertEqual(store.times(.anaLounge)?.leave, ClockTime(17, 3))
        XCTAssertEqual(store.schedule?.arriveAtGate, ClockTime(17, 7))
    }

    @MainActor
    func testFirstArrivalEditIncludesTheWalkAndHonorsCurrentTime() {
        let defaults = UserDefaults(suiteName: "firstStopWalk")!
        defaults.removePersistentDomain(forName: "firstStopWalk")
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
        store.add(.anaLounge)
        XCTAssertEqual(store.times(.anaLounge)?.arrive, ClockTime(16, 5))
        store.setTimes(.anaLounge, arrive: ClockTime(16, 0))
        XCTAssertEqual(store.times(.anaLounge)?.arrive, ClockTime(16, 0))
        store.setNow(ClockTime(15, 58))
        XCTAssertEqual(store.times(.anaLounge)?.arrive, ClockTime(16, 3), "Cannot start the walk in the past")
        XCTAssertEqual(store.earliestArrival(for: .anaLounge), ClockTime(16, 3))
        XCTAssertNil(StopTimes.earlierArrive(ClockTime(16, 3), earliestAllowed: ClockTime(16, 3)))
    }

    @MainActor
    func testEarlierLeaveControlIncludesUpdatedWaitAndMinimumVisit() {
        let defaults = UserDefaults(suiteName: "cafeLeaveBounds")!
        defaults.removePersistentDomain(forName: "cafeLeaveBounds")
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
        store.add(.cafe)
        XCTAssertEqual(store.earliestLeave(for: .cafe), ClockTime(16, 28))
        XCTAssertEqual(StopTimes.earlierLeave(ClockTime(16, 38), earliestAllowed: ClockTime(16, 28)), ClockTime(16, 30))
        store.setTimes(.cafe, leave: ClockTime(16, 30))
        XCTAssertEqual(store.times(.cafe)?.leave, ClockTime(16, 30))
        XCTAssertNil(StopTimes.earlierLeave(ClockTime(16, 30), earliestAllowed: ClockTime(16, 28)))
    }

    @MainActor
    func testSkyLoungeGuidanceUsesFourthFloorAndLiftBothWays() {
        let defaults = UserDefaults(suiteName: "skyLoungeRoute")!
        defaults.removePersistentDomain(forName: "skyLoungeRoute")
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
        store.add(.skyLounge)
        XCTAssertEqual(PlaceID.skyLounge.floor, "4F")
        let steps = RouteSteps.steps(for: .direct, store: store)
        XCTAssertTrue(steps.contains { $0.text == "Take the lift to SKY LOUNGE, 4F" && $0.turn == .lift })
        XCTAssertTrue(steps.contains { $0.text == "Take the lift down to 3F" && $0.turn == .lift })
    }

    @MainActor
    func testSitDownAndBusyPlansWarnBeforeAdding() {
        let defaults = UserDefaults(suiteName: "fitWarning")!
        defaults.removePersistentDomain(forName: "fitWarning")
        let store = JourneyStore(walkingData: FixedWalkingData(kmh: nil), defaults: defaults)
        XCTAssertNil(store.fitWarning(for: .sushi), "An empty afternoon fits a sit-down meal")
        store.add(.cafe)
        store.add(.skyLounge)
        XCTAssertEqual(store.fitWarning(for: .sushi)?.title, "A sit-down meal may not fit")
        XCTAssertNil(store.fitWarning(for: .bento), "A quick bite still fits")
        store.add(.bento)
        XCTAssertEqual(store.fitWarning(for: .udon)?.title, "That's a lot to fit in")
        let bento = store.schedule?.stops.first { $0.stop.id == .bento }
        XCTAssertNotNil(bento)
        if let bento { XCTAssertEqual(bento.end - bento.start, 10) }
        store.remove(.bento)
        store.remove(.skyLounge)
        store.add(.sushi)
        let texts = RouteSteps.steps(for: .direct, store: store).map(\.text)
        XCTAssertTrue(texts.contains("Take the lift to Sushi Restaurant, 4F"), "\(texts)")
        XCTAssertTrue(texts.contains("Take the lift down to 3F"), "\(texts)")
    }
}
