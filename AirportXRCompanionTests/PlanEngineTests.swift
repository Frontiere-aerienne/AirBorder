// PROCEDURAL: Verifies timing and journey state with controlled inputs.

@testable import AirBorder
import RealityKit
import XCTest

final class TerminalReplayStateTests: XCTestCase {
    private func reading(point: TerminalReading.Point? = .init(x: 0.46, y: 0.72), level: Int? = 3,
                         confirmed: Bool = true, node: String? = "t3-elevator-north",
                         source: String = "externalSignalReplay") -> TerminalReading {
        TerminalReading(point: point, level: level, floorConfirmed: confirmed, matchedNodeID: node, source: source)
    }

    func testUnconfirmedFloorRetainsTheLastConfirmedThreeFloorPositionAndHoldsControls() {
        var state = TerminalReplayState()
        let threeFloor = reading()
        state.receive(threeFloor)
        state.receive(reading(point: .init(x: 0.65, y: 0.55), level: 4, confirmed: false,
                              node: "t3-gates-center"))

        XCTAssertEqual(state.confirmed, threeFloor)
        XCTAssertTrue(state.awaitingFloor)
        XCTAssertTrue(state.hasConnection)
    }

    func testConfirmedFourFloorReadingsAdvanceTheVisiblePoseWithoutChangingTheRouteStep() {
        var state = TerminalReplayState()
        let firstFourFloor = reading(point: .init(x: 0.65, y: 0.55), level: 4, node: "t3-gates-center")
        let secondFourFloor = reading(point: .init(x: 0.74, y: 0.48), level: 4, node: "t3-gates-center")

        state.receive(firstFourFloor)
        state.receive(secondFourFloor)

        XCTAssertEqual(state.confirmed, secondFourFloor)
        XCTAssertFalse(state.awaitingFloor)
        XCTAssertTrue(state.hasConnection)
    }

    func testUnsupportedOrWrongSourceReadingsCannotReplaceConfirmedPosition() {
        var state = TerminalReplayState()
        let accepted = reading()
        state.receive(accepted)
        state.receive(reading(node: "gate-105", source: "untrusted"))
        state.receive(reading(level: 4, node: "not-a-route-node"))

        XCTAssertEqual(state.confirmed, accepted)
        XCTAssertFalse(state.awaitingFloor)
    }

    func testDeckReplayRequiresClearanceEvenWhenFloorAndCoordinatesMatch() {
        var state = TerminalReplayState(route: .observationDeck)
        let checkpoint = reading(level: 3, node: "t3-return-security")
        var airside = reading(level: 3, node: "t3-after-security")
        state.receive(checkpoint)
        state.receive(airside)
        XCTAssertEqual(state.confirmed, checkpoint)
        XCTAssertTrue(state.awaitingCheckpoint)
        airside.clearanceConfirmed = true
        state.receive(airside)
        XCTAssertEqual(state.confirmed, airside)
        XCTAssertFalse(state.awaitingCheckpoint)
        state.receive(checkpoint)
        XCTAssertEqual(state.confirmed?.landmark?.location, "T3 · 3F · Landside")
    }

    func testQueueWaitIsIndependentOfPedestriansAndEndsAfterClearance() {
        var state = TerminalReplayState(route: .observationDeck)
        var checkpoint = reading(level: 3, node: "t3-return-security")
        let walker = DriverPedestrian(id: 0, x: 0.6, z: -4, headingDegrees: 0, stride: 0)
        checkpoint.securityQueue = .init(additionalWaitMinutes: 0, pedestrians: [walker])
        state.receive(checkpoint)
        let position = state.confirmed
        XCTAssertEqual(state.securityQueue?.additionalWaitMinutes, 0)
        XCTAssertEqual(state.securityQueue?.scenePedestrians.count, 1)

        checkpoint.securityQueue = .init(additionalWaitMinutes: 12, pedestrians: [])
        state.receive(checkpoint)
        XCTAssertEqual(state.securityQueue?.additionalWaitMinutes, 12, "The wait comes from the report")
        XCTAssertEqual(state.confirmed, position)
        XCTAssertEqual(state.guidance.instruction, "Go through security")

        var airside = reading(level: 3, node: "t3-after-security")
        airside.securityQueue = checkpoint.securityQueue
        state.receive(airside)
        XCTAssertEqual(state.securityQueue?.additionalWaitMinutes, 12)
        XCTAssertTrue(state.awaitingCheckpoint)
        airside.clearanceConfirmed = true
        state.receive(airside)
        XCTAssertNil(state.securityQueue, "A live report remains irrelevant once screening is complete")
        XCTAssertEqual(state.guidance.instruction, "Gate 105 ahead")

        var direct = TerminalReplayState()
        var gateReading = reading()
        gateReading.securityQueue = checkpoint.securityQueue
        direct.receive(gateReading)
        XCTAssertNil(direct.securityQueue)
    }

    func testFacilityQueuesFollowTheirRouteAndConfirmedCheckpoint() {
        let reports = [
            DriverFacilityQueue(kind: .lounge, additionalWaitMinutes: 8, pedestrians: []),
            DriverFacilityQueue(kind: .immigration, additionalWaitMinutes: 18, pedestrians: []),
            DriverFacilityQueue(kind: .customs, additionalWaitMinutes: 6, pedestrians: [])
        ]
        func observation(_ node: String, level: Int, clearance: Bool? = nil) -> TerminalReading {
            var result = reading(level: level, node: node)
            result.clearanceConfirmed = clearance
            result.facilityQueues = reports
            return result
        }

        var lounge = TerminalReplayState(route: .lounge)
        lounge.receive(observation("t3-lounge-entrance", level: 4))
        XCTAssertEqual(lounge.facilityQueue?.kind, .lounge)
        XCTAssertEqual(lounge.facilityQueue?.additionalWaitMinutes, 8)
        XCTAssertFalse(lounge.cameraRestricted)
        lounge.receive(observation("gate-105", level: 4))
        XCTAssertNil(lounge.facilityQueue)
        XCTAssertFalse(lounge.cameraRestricted)

        var unrelated = TerminalReplayState(route: .gate)
        unrelated.receive(observation("t3-lounge-entrance", level: 4))
        XCTAssertNil(unrelated.facilityQueue)
        unrelated.receive(observation("gate-105", level: 4))
        XCTAssertNil(unrelated.facilityQueue)

        var arrivals = TerminalReplayState(route: .arrivals)
        arrivals.receive(observation("t3-arrivals-immigration", level: 2))
        XCTAssertTrue(arrivals.cameraRestricted)
        XCTAssertEqual(arrivals.facilityQueue?.kind, .immigration)
        XCTAssertEqual(arrivals.facilityQueue?.additionalWaitMinutes, 18)
        arrivals.receive(observation("t3-arrivals-baggage", level: 2, clearance: false))
        XCTAssertTrue(arrivals.awaitingCheckpoint)
        XCTAssertTrue(arrivals.cameraRestricted)
        XCTAssertEqual(arrivals.confirmed?.landmark, .immigration)
        XCTAssertEqual(arrivals.facilityQueue?.additionalWaitMinutes, 18)
        arrivals.receive(observation("t3-arrivals-baggage", level: 2, clearance: true))
        XCTAssertFalse(arrivals.awaitingCheckpoint)
        XCTAssertTrue(arrivals.cameraRestricted)
        XCTAssertNil(arrivals.facilityQueue)
        arrivals.receive(observation("t3-arrivals-customs", level: 2))
        XCTAssertTrue(arrivals.cameraRestricted)
        XCTAssertEqual(arrivals.facilityQueue?.kind, .customs)
        XCTAssertEqual(arrivals.facilityQueue?.additionalWaitMinutes, 6)
        arrivals.receive(observation("t3-arrivals-exit", level: 2, clearance: false))
        XCTAssertTrue(arrivals.awaitingCheckpoint)
        XCTAssertTrue(arrivals.cameraRestricted)
        XCTAssertEqual(arrivals.confirmed?.landmark, .customs)
        XCTAssertEqual(arrivals.facilityQueue?.additionalWaitMinutes, 6)
        arrivals.receive(observation("t3-arrivals-exit", level: 2, clearance: true))
        XCTAssertFalse(arrivals.awaitingCheckpoint)
        XCTAssertFalse(arrivals.cameraRestricted)
        XCTAssertNil(arrivals.facilityQueue)
    }

    func testCameraRestrictionEndsOnlyAfterSecurityClearance() {
        var state = TerminalReplayState(route: .observationDeck)
        state.receive(reading(level: 3, node: "t3-return-security"))
        XCTAssertTrue(state.cameraRestricted)
        var airside = reading(level: 3, node: "t3-after-security")
        airside.clearanceConfirmed = false
        state.receive(airside)
        XCTAssertTrue(state.awaitingCheckpoint)
        XCTAssertTrue(state.cameraRestricted)
        airside.clearanceConfirmed = true
        state.receive(airside)
        XCTAssertFalse(state.awaitingCheckpoint)
        XCTAssertFalse(state.cameraRestricted)
    }

    func testFacilityQueueRejectsInvalidOrAmbiguousReports() {
        var state = TerminalReplayState(route: .lounge)
        var entrance = reading(level: 4, node: "t3-lounge-entrance")
        entrance.facilityQueues = [.init(kind: .lounge, additionalWaitMinutes: -1, pedestrians: [])]
        state.receive(entrance)
        XCTAssertNil(state.facilityQueue)
        entrance.facilityQueues = [.init(kind: .lounge, additionalWaitMinutes: 8, pedestrians: []),
                                   .init(kind: .lounge, additionalWaitMinutes: 9, pedestrians: [])]
        state.receive(entrance)
        XCTAssertNil(state.facilityQueue)
    }

    func testFullShuttleOnlyHoldsThatBoardingStep() {
        var deck = TerminalReplayState(route: .observationDeck)
        var atStop = reading(level: 1, node: "t3-shuttle-stop-0")
        atStop.shuttleFull = true
        deck.receive(atStop)
        XCTAssertTrue(deck.awaitingShuttle)
        var boarding = reading(level: 1, node: "shuttle-to-t2")
        boarding.shuttleFull = true
        deck.receive(boarding)
        XCTAssertEqual(deck.confirmed, atStop)
        boarding.shuttleFull = false
        deck.receive(boarding)
        XCTAssertEqual(deck.confirmed, boarding)
        XCTAssertFalse(deck.awaitingShuttle)

        var gateRoute = TerminalReplayState()
        var gateReading = reading()
        gateReading.shuttleFull = true
        gateRoute.receive(gateReading)
        XCTAssertEqual(gateRoute.confirmed, gateReading)
        XCTAssertFalse(gateRoute.awaitingShuttle)
    }

    func testLiftOutageKeepsTheLastConfirmedPosition() {
        var state = TerminalReplayState()
        var lift = reading()
        lift.liftAvailable = false
        state.receive(lift)
        XCTAssertTrue(state.awaitingLift)
        var upper = reading(level: 4, node: "t3-gates-center")
        upper.liftAvailable = false
        state.receive(upper)
        XCTAssertEqual(state.confirmed, lift)
        upper.liftAvailable = true
        state.receive(upper)
        XCTAssertEqual(state.confirmed, upper)
        XCTAssertFalse(state.awaitingLift)
    }

    func testOfficialWalkRejectsOldAndConflictingReadingsAndKeepsItsPosition() {
        let frame = "hnd-t3-3f-gate-wing"
        let start = TerminalReading.Point(x: 0.2, y: 0.5)
        let end = TerminalReading.Point(x: 0.3, y: 0.5)
        let path = OfficialGateWalkPath(frameID: frame, destination: "t3-departure-gate-108a",
                                        points: [start, end], revision: 1)
        var walk = OfficialGateWalkState(path: path)
        var first = reading(point: start)
        first.mapFrameID = frame
        first.sequence = 4
        first.routeRevision = 1
        walk.receive(first)
        XCTAssertEqual(walk.index, 0)
        XCTAssertTrue(walk.positionAvailable)
        var conflict = TerminalReading(point: end, level: 3, floorConfirmed: true, matchedNodeID: nil,
                                   source: "externalSignalReplay", mapFrameID: frame, sequence: 4, routeRevision: 1)
        walk.receive(conflict)
        XCTAssertFalse(walk.positionAvailable)
        XCTAssertEqual(walk.confirmed, first)
        conflict.sequence = 5
        walk.receive(conflict)
        XCTAssertTrue(walk.atGate)
        walk.receive(first)
        XCTAssertFalse(walk.positionAvailable)
        XCTAssertEqual(walk.confirmed, conflict)
        XCTAssertFalse(walk.atGate)
    }

    func testCafeLandmarkIssueHoldsAtTheLastPositionAndAcceptsTheNextConfirmedReading() {
        let frame = OfficialGateWalkPath.cafeConcourse
        let start = TerminalReading.Point(x: 0.03, y: 0.5)
        let cafe = TerminalReading.Point(x: 0.07, y: 0.5)
        let path = OfficialGateWalkPath(frameID: frame, destination: "t3-departure-gate-105",
                                        points: [start, cafe], revision: 1, cafePending: true)
        var walk = OfficialGateWalkState(path: path)
        var entrance = reading(point: cafe)
        entrance.mapFrameID = frame
        entrance.sequence = 8
        entrance.routeRevision = 1
        walk.receive(entrance)
        XCTAssertTrue(walk.atCafe)
        XCTAssertFalse(walk.atGate)

        let wrong = TerminalReading(point: start, level: 3, floorConfirmed: true, matchedNodeID: "wrong-concourse",
                                    source: "externalSignalReplay", mapFrameID: frame, sequence: 9,
                                    routeRevision: 1, landmarkToken: 9)
        walk.receive(wrong)
        XCTAssertEqual(walk.confirmed?.point, cafe)
        XCTAssertEqual(walk.landmarkToken, 9)
        XCTAssertFalse(walk.atCafe)

        entrance.sequence = 10
        walk.receive(entrance)
        XCTAssertTrue(walk.atCafe)
        XCTAssertNil(walk.landmarkToken)
    }

    func testCafeConcourseRerouteKeepsTheLastConfirmedCoordinateAndHeading() {
        let frame = OfficialGateWalkPath.cafeConcourse
        let point = TerminalReading.Point(x: 0.78, y: 0.5)
        let path105 = OfficialGateWalkPath(frameID: frame, destination: "t3-departure-gate-105",
                                           points: [point, .init(x: 0.95, y: 0.5)], revision: 1)
        var original = OfficialGateWalkState(path: path105)
        var pose = reading(point: point)
        pose.mapFrameID = frame
        pose.sequence = 20
        pose.routeRevision = 1
        pose.headingDegrees = 90
        original.receive(pose)
        let path108A = OfficialGateWalkPath(frameID: frame, destination: "t3-departure-gate-108a",
                                            points: [point, .init(x: 0.64, y: 0.5)], revision: 2)
        var updated = OfficialGateWalkState(path: path108A, retaining: original)
        XCTAssertEqual(updated.guidance(gate: "108A").position, pose)
        pose.sequence = 21
        pose.routeRevision = 2
        updated.receive(pose)
        XCTAssertEqual(updated.guidance(gate: "108A").position?.point, original.confirmed?.point)
        XCTAssertEqual(updated.guidance(gate: "108A").position?.headingDegrees, original.confirmed?.headingDegrees)
        XCTAssertTrue(updated.shouldTurnBack)
    }

    func testCrowdDelayUsesOnlyTheRemainingOverlapWithTheReportedStrip() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let stripStart = TerminalReading.Point(x: 0.2, y: 0.5)
        let stripEnd = TerminalReading.Point(x: 0.4, y: 0.5)
        let report = OfficialGateWalkPath.CrowdReport(start: stripStart, end: stripEnd,
                                                     reportedAt: now.timeIntervalSince1970, delayMinutes: 3)
        let direct: [TerminalReading.Point] = [.init(x: 0.1, y: 0.5), .init(x: 0.3, y: 0.5),
                                               .init(x: 0.5, y: 0.5), .init(x: 0.7, y: 0.5)]
        let overlap = try XCTUnwrap(WalkCrowdImpact(report: report, remaining: direct[...], now: now))
        XCTAssertEqual(overlap.delayMinutes, 3, "The estimate applies once across the whole strip")
        XCTAssertEqual(overlap.segments.first?.start, stripStart)
        XCTAssertEqual(overlap.segments.last?.end, stripEnd)
        XCTAssertEqual(WalkCrowdImpact(report: report, remaining: direct[1...], now: now)?.segments.first?.start, direct[1])
        XCTAssertNil(WalkCrowdImpact(report: report, remaining: direct[2...], now: now))

        let bypass: [TerminalReading.Point] = [direct[0], stripStart, .init(x: 0.2, y: 0.44),
                                               .init(x: 0.4, y: 0.44), stripEnd, direct[3]]
        XCTAssertNil(WalkCrowdImpact(report: report, remaining: bypass[...], now: now))
        let expired = try XCTUnwrap(WalkCrowdImpact(report: report, remaining: direct[...], now: now + 300))
        XCTAssertNil(expired.delayMinutes)
        XCTAssertNil(WalkCrowdImpact(report: report, remaining: bypass[...], now: now + 300))
    }

    func testBlockedJunctionUsesFacingDirectionAndRetainsTheAcceptedPose() {
        let frame = OfficialGateWalkPath.gateWing
        let west = TerminalReading.Point(x: 0.2, y: 0.5)
        let east = TerminalReading.Point(x: 0.4, y: 0.5)
        let north = TerminalReading.Point(x: 0.2, y: 0.44)
        let junction = OfficialGateWalkPath.Junction(start: west, end: east)
        let direct = OfficialGateWalkPath(frameID: frame, destination: "t3-departure-gate-105",
                                         points: [west, east], revision: 1, junction: junction)
        var before = OfficialGateWalkState(path: direct)
        var pose = reading(point: west)
        pose.mapFrameID = frame
        pose.sequence = 4
        pose.routeRevision = 1
        pose.headingDegrees = 90
        before.receive(pose)

        let blocked = OfficialGateWalkPath(frameID: frame, destination: direct.destination,
                                          points: [west, north, east], revision: 2, junction: junction, closure: .detour)
        var after = OfficialGateWalkState(path: blocked, retaining: before)
        pose.routeRevision = 2
        pose.sequence = 5
        after.receive(pose)
        XCTAssertTrue(after.showsClosure)
        XCTAssertEqual(after.guidance(gate: "105").turn, .left)
        XCTAssertEqual(after.guidance(gate: "105").instruction, "Turn left onto the side passage")
        XCTAssertEqual(after.confirmed?.point, before.confirmed?.point)
        XCTAssertEqual(after.confirmed?.headingDegrees, before.confirmed?.headingDegrees)

        pose.headingDegrees = -90
        pose.sequence = 6
        after.receive(pose)
        XCTAssertEqual(after.guidance(gate: "105").turn, .right)
    }

    func testSidePassageRenderKeepsTheEntryThenSeparatesTheTwoAisles() {
        let west = GateWingSidePassage.west
        let east = GateWingSidePassage.east
        let middle = (west + east) / 2
        let entry = HanedaReplayScene.gateWing.cameraPose(.init(x: west, y: 0.5), headingDegrees: 90)
        let turning = HanedaReplayScene.gateWing.cameraPose(.init(x: west, y: 0.47), headingDegrees: 45)
        let side = HanedaReplayScene.gateWing.cameraPose(.init(x: middle, y: 0.44), headingDegrees: 90)
        let main = HanedaReplayScene.gateWing.cameraPose(.init(x: middle, y: 0.5), headingDegrees: 90)
        XCTAssertEqual(entry.translation.x, 0, accuracy: 0.001)
        XCTAssertEqual(entry.translation.z, turning.translation.z, accuracy: 0.001)
        XCTAssertNotEqual(entry.rotation.vector, turning.rotation.vector)
        XCTAssertGreaterThan(main.translation.x - GateWingSidePassage.dividerX, 0.5)
        XCTAssertGreaterThan(GateWingSidePassage.dividerX - side.translation.x, 1)
        XCTAssertLessThan(side.translation.z, entry.translation.z)
        XCTAssertEqual(GateWingSidePassage.depth(0.85), 3 - 0.85 * 20, accuracy: 0.001)
    }

    func testVoiceFollowUpReadsTheNewGateAndPreservesAnUncertainPosition() {
        var voice = RouteVoiceConversation()
        let initial = RouteVoiceConversation.Guidance(gate: "105", instruction: "Follow the concourse")
        let change = RouteVoiceConversation.Guidance(gate: "108A", instruction: "Position unavailable")
        XCTAssertEqual(voice.answer("Which gate?", using: initial), "Gate 105.")
        XCTAssertEqual(voice.answer("What about now?", using: change), "Gate 108A.")
        XCTAssertEqual(voice.answer("What's next?", using: change), "Position unavailable")
        XCTAssertEqual(voice.answer("Repeat that", using: change), "Position unavailable")
        XCTAssertEqual(voice.answer("When is dinner?", using: change), "You can ask which gate, or what’s next.")
    }

    func testNewReplayUsesHeadingAndBothPositionAxes() {
        let scene = HanedaReplayScene.deck
        let first = scene.cameraPose(.init(x: 0.1, y: 0.4), headingDegrees: 0)
        let second = scene.cameraPose(.init(x: 0.4, y: 0.6), headingDegrees: 35)
        XCTAssertLessThan(second.translation.z, first.translation.z)
        XCTAssertGreaterThan(second.translation.x, first.translation.x)
        XCTAssertNotEqual(first.rotation.vector, second.rotation.vector)
    }

    @MainActor
    func testHanedaReplayLoadsTheBoxedAssetsWithExpectedAxes() throws {
        for name in ["ReplayShuttle", "ReplayCoach", "ReplayHanedaT2", "ReplayHanedaT3"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "usdz"))
            let model = try Entity.load(contentsOf: url)
            let size = model.visualBounds(relativeTo: nil).extents
            XCTAssertTrue(size.x > 0 && size.y > 0 && size.z > 0, name)
            if name == "ReplayShuttle" || name == "ReplayCoach" {
                // A bus stands on Y, with length along X and a smaller width along Z.
                XCTAssertTrue(size.x > size.y && size.y > size.z, name)
            }
        }
        _ = try XCTUnwrap(Bundle.main.url(forResource: "ReplayTerrazzo", withExtension: "jpg"))
    }

    @MainActor
    func testRailReplayLoadsTrainAndTrackAndTurnsInPlace() throws {
        for (name, length) in [("ReplayRailCar", Float(20.5)), ("ReplayRailTrack", Float(6))] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "usdz"))
            let model = try Entity.load(contentsOf: url)
            XCTAssertEqual(model.visualBounds(relativeTo: nil).extents.z, length, accuracy: 0.1)
        }
        let point = TerminalReading.Point(x: 0.82, y: 0.63)
        let walking = HanedaReplayScene.railPlatform.cameraPose(point, headingDegrees: 13)
        let turned = HanedaReplayScene.railPlatform.cameraPose(point, headingDegrees: 51)
        XCTAssertEqual(walking.translation, turned.translation)
        XCTAssertNotEqual(walking.rotation.vector, turned.rotation.vector)
        XCTAssertTrue(TerminalReplayRoute.naritaRail.includes(.railDestination))
        XCTAssertFalse(TerminalReplayRoute.narita.includes(.railDestination))
        XCTAssertFalse(TerminalReplayRoute.observationDeck.includes(.railDestination))
    }
}

final class LoungeDirectoryTests: XCTestCase {
    func testHanedaTerminalThreeLoungesUseKnownGateWalks() {
        let options = LoungeDirectory.options(for: SampleJourney.outbound, gate: "105", pace: .average)
        XCTAssertEqual(options.map(\.id), [.anaLounge, .skyLounge])
        XCTAssertEqual(options.map(\.walkToGate), [4, 8])
    }

    func testUnknownGateKeepsSameTerminalListingsWithoutInventingADistance() {
        let options = LoungeDirectory.options(for: SampleJourney.outbound, gate: "108A", pace: .average)
        XCTAssertEqual(options.map(\.id), [.anaLounge, .skyLounge])
        XCTAssertTrue(options.allSatisfy { $0.walkToGate == nil })
    }

    func testHanedaLoungesAreExcludedForNaritaDeparture() {
        XCTAssertTrue(LoungeDirectory.options(for: SampleJourney.naritaOutbound, gate: "", pace: .average).isEmpty)
    }
}

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
        XCTAssertEqual(PlanText.timing(schedule.stops[0]), "16:00–16:28, 8 min wait + 20 min visit")
        XCTAssertEqual(PlanText.timing(schedule.stops[1]), "16:33–17:01, 28 min visit")
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
        XCTAssertEqual(PlanText.timing(applied.stops[0]), "16:00–16:38, 18 min for the queue + 20 min visit")
        XCTAssertEqual(PlanText.timing(applied.stops[1]), "16:43–17:01, 18 min visit")
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

    func testDriverCafeOffersOnlyAPreservedPlanWithAnUpToDateWait() throws {
        let store = makeStore()
        XCTAssertNil(store.fittingCafe(waitMinutes: 8))
        store.receiveDriverCafeWait(8)
        let offer = try XCTUnwrap(store.fittingCafe(waitMinutes: 8))
        XCTAssertEqual(offer.arrival.description, "16:36")
        XCTAssertTrue(store.plan.stops.isEmpty)

        store.receiveDriverCafeWait(nil)
        XCTAssertNil(store.fittingCafe(waitMinutes: 8))

        store.receiveDriverCafeWait(28)
        store.add(.anaLounge)
        XCTAssertNil(store.fittingCafe(waitMinutes: 8))
        XCTAssertNil(store.fittingCafe(waitMinutes: 28), "Adding the café would extend the earlier commitment")
        XCTAssertEqual(store.plan.stops.map(\.id), [.anaLounge])
    }

    func testDriverCafeUsesTheSameWaitInTheOfferedAndSavedPlan() throws {
        let store = makeStore()
        store.receiveDriverCafeWait(8)
        let offer = try XCTUnwrap(store.fittingCafe(waitMinutes: 8))
        store.add(offer.stop)
        XCTAssertEqual(store.schedule.arriveAtGate, offer.arrival)
        XCTAssertNil(store.fittingCafe(waitMinutes: 8))
        store.receiveDriverCafeWait(28)
        XCTAssertEqual(store.schedule.stops.first?.stop.waitMinutes, 28)
        store.receiveDriverCafeWait(nil)
        XCTAssertEqual(store.schedule.stops.first?.stop.waitMinutes, 28)
        XCTAssertNil(store.suggestion)
    }

    func testExpiredCafeWaitCannotShortenAnExistingPlanAndFreshWaitRestoresOffer() throws {
        let store = makeStore()
        store.add(.cafe)
        store.add(.anaLounge)
        let originalPlan = store.plan

        store.receiveDriverCafeWait(18)
        XCTAssertEqual(try XCTUnwrap(store.suggestion).extraMinutes, 10)

        store.receiveDriverCafeWait(nil)
        XCTAssertTrue(store.planTimingUnavailable)
        XCTAssertNil(store.suggestion)
        XCTAssertNil(store.times(.cafe))
        XCTAssertNil(store.times(.anaLounge))
        XCTAssertEqual(store.conditionInputs.leaveBy, SampleJourney.gateArrivalTarget - store.gateWalkMinutes)
        store.applySuggestion()
        store.setTimes(.anaLounge, leave: ClockTime(16, 59))
        XCTAssertEqual(store.plan, originalPlan)

        store.receiveDriverCafeWait(17)
        XCTAssertFalse(store.planTimingUnavailable)
        XCTAssertEqual(try XCTUnwrap(store.suggestion).extraMinutes, 9)
        XCTAssertEqual(store.times(.cafe)?.leave, ClockTime(16, 37))
        XCTAssertEqual(store.plan, originalPlan)
    }

    func testUnavailableFirstCafeReportAffectsOnlyPlansThatIncludeTheCafe() {
        let store = makeStore()
        store.add(.anaLounge)
        store.receiveDriverCafeWait(nil)
        XCTAssertFalse(store.planTimingUnavailable)
        XCTAssertNotNil(store.times(.anaLounge))

        store.add(.cafe)
        XCTAssertTrue(store.planTimingUnavailable)
        XCTAssertNil(store.times(.anaLounge))
        XCTAssertNil(store.suggestion)

        store.remove(.cafe)
        XCTAssertFalse(store.planTimingUnavailable)
        XCTAssertNotNil(store.times(.anaLounge))
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

    func testStopsMoveTheLeaveTimeForReturnNow() {
        let store = makeStore()
        store.setNow(ClockTime(16, 40))
        XCTAssertNil(store.primaryCondition)
        store.add(.cafe)
        XCTAssertEqual(store.conditionInputs.leaveBy, SampleJourney.gateArrivalTarget - store.schedule.walkToGate)
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

    func testRejectsSignTextEmbeddedInOtherGateCodesAndWords() {
        XCTAssertFalse(SignMatcher.matches(["Gates 105–109A"], .gates105to109))
        XCTAssertFalse(SignMatcher.matches(["Gates 1105–109"], .gates105to109))
        XCTAssertFalse(SignMatcher.matches(["Business center"], .bus))
        XCTAssertFalse(SignMatcher.matches(["Loungewear"], .lounges))
        XCTAssertTrue(SignMatcher.matches(["Shuttle bus →"], .bus))
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
        XCTAssertNil(StopTimes.earlierArrive(ClockTime(15, 0)), "Plan starts at 15:00")
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
        XCTAssertEqual(store.schedule.arriveAtGate, ClockTime(17, 15))
        store.setTimes(.anaLounge, leave: ClockTime(17, 1))
        XCTAssertEqual(store.schedule.arriveAtGate, ClockTime(17, 5))
        XCTAssertEqual(store.minutesToSpare, 0)
        XCTAssertTrue(RouteSteps.steps(for: .direct, store: store).contains {
            $0.text == "Stop at ANA LOUNGE, leave by 17:01"
        })
        store.setTimes(.anaLounge, arrive: ClockTime(16, 45))
        XCTAssertEqual(store.times(.anaLounge)?.leave, ClockTime(17, 3))
        XCTAssertEqual(store.schedule.arriveAtGate, ClockTime(17, 7))
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
        let bento = store.schedule.stops.first { $0.stop.id == .bento }
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
