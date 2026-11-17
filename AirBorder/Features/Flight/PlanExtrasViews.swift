import SwiftUI

/// Flight tab plan card once stops are added (Figma "Flight (Plan: …)", 858:8502).
struct AddedPlanCard: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open

    var body: some View {
        if let schedule = store.schedule, let target = store.gateArrivalTarget {
            addedPlan(schedule, target: target)
        }
    }

    private func addedPlan(_ schedule: Schedule, target: ClockTime) -> some View {
        let stops = schedule.stops
        let leave = stops.isEmpty ? TerminalTwo.leaveBy(gateWalk: store.gateWalkMinutes) : schedule.leave
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if stops.count == 1, stops[0].stop.id == .anaLounge {
                    AirlineBadge(airline: .ana)
                    Text("LOUNGE").outfitText(17, .semibold)
                } else {
                    Text(stops.isEmpty ? "T2 Observation Deck" : stops.map(\.stop.name).joined(separator: ", "))
                        .outfitText(17, .semibold).lineLimit(2)
                }
                Spacer()
                circle(image: "icClosePlan", label: "Remove plan") {
                    for item in stops { store.remove(item.stop.id) }
                    store.t2VisitPlanned = false
                }
            }
            timeline(leave: leave, arrive: stops.isEmpty ? target : schedule.arriveAtGate, closes: schedule.gateCloses)
        }
        .padding(24)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(AB.border, lineWidth: 1))
        .accessibilityIdentifier("addedPlanCard")
    }

    private func circle(image: String?, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(image).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(AB.ticket)
                }
            }
            .frame(width: 36, height: 36)
            .background(AB.chip, in: Circle())
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func timeline(leave: ClockTime, arrive: ClockTime, closes: ClockTime?) -> some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 320
            ZStack(alignment: .topLeading) {
                Rectangle().fill(AB.primary).frame(width: 180 * scale, height: 3).offset(y: 3)
                Rectangle().fill(AB.primary.opacity(0.3)).frame(width: 116 * scale, height: 3).offset(x: 180 * scale, y: 3)
                point("Now", store.now, x: 0, filled: true)
                point("Leave", leave, x: 175 * scale, filled: true)
                point("At gate", arrive, x: 233 * scale, filled: false)
                Image("icGate").resizable().frame(width: 24, height: 24).offset(x: 300 * scale, y: -4)
                if let closes { Text(closes.description).outfitText(13, .semibold).offset(x: 296 * scale, y: 18) }
            }
        }
        .frame(height: 48)
    }

    private func point(_ label: String, _ time: ClockTime, x: CGFloat, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Circle().fill(filled ? AB.primary : .white).overlay(Circle().strokeBorder(AB.primary, lineWidth: 1.5)).frame(width: 10, height: 10)
            VStack(spacing: 0) {
                Text(time.description).outfitText(13, .semibold)
                Text(label).outfitText(11, .regular, AB.muted)
            }
            .offset(x: x == 0 ? 0 : -11)
        }
        .offset(x: x)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(time)")
    }
}
