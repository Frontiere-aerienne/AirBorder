import SwiftUI

/// Figma "Welcome" (858:8326) and "Onboarding 1–3" (858:8332, 858:8356, 858:8401).
/// Runs once on first launch; Profile › Replay tutorial starts again at Onboarding 1.
struct OnboardingFlow: View {
    @EnvironmentObject private var store: JourneyStore
    @State var page: Int
    let finish: () -> Void

    init(startAt page: Int = 0, finish: @escaping () -> Void) {
        _page = State(initialValue: page)
        self.finish = finish
    }

    var body: some View {
        ZStack {
            switch page {
            case 0: WelcomeView { advance() }
            default: OnboardingPage(page: page, next: advance, skip: done)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func advance() {
        if page >= 3 { done() } else { page += 1 }
    }

    private func done() {
        store.onboardingSeen = true
        store.tab = .flight
        finish()
    }
}

private struct WelcomeView: View {
    let next: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("obLogo").resizable().frame(width: 96, height: 96).accessibilityHidden(true)
            Text("Welcome to\nAirBorder").outfitText(32, .bold)
                .multilineTextAlignment(.center)
                .padding(.top, 58)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: next) {
                VStack(spacing: 8) {
                    Image("obChevron").resizable().frame(width: 16, height: 8)
                    Text("Swipe up to continue").outfitText(14, .medium, AB.muted)
                }
                .frame(minWidth: 160, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcomeContinue")
        }
        .frame(maxWidth: .infinity)
        .background(AB.screen.ignoresSafeArea())
        .gesture(DragGesture(minimumDistance: 30).onEnded { if $0.translation.height < -30 { next() } })
    }
}

private struct OnboardingPage: View {
    @EnvironmentObject private var store: JourneyStore
    let page: Int
    let next: () -> Void
    let skip: () -> Void

    private var headline: String {
        ["", "Your layover,\nplanned to\nthe minute.", "Always know\nyour time.", "Get there at\nyour own pace."][page]
    }

    private var bodyText: String {
        ["", "See how long you have, how to reach your gate, and what fits in between!",
         "Your gate, the time until it closes, and your departure. One look.",
         "See how long each walk takes."][page]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if page < 3 {
                    Button(action: skip) {
                        Text("Skip").outfitText(15, .medium, AB.ice).frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboardingSkip")
                }
            }
            .frame(height: 44)
            .padding(.top, 27)
            VStack(alignment: .leading, spacing: 12) {
                Text(headline).outfitText(page == 1 ? 38 : 34, .bold, AB.ice).accessibilityAddTraits(.isHeader)
                Text(bodyText).outfitText(16, .regular, AB.ice.opacity(0.78))
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)
            graphic
            Spacer(minLength: 16)
            Image("obProgress\(page)").resizable().scaledToFit().frame(height: 26)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Page \(page) of 3")
            CTAButton(title: page == 3 ? "Get started" : "Continue", style: .light, height: 52, action: next)
                .padding(.horizontal, 30)
                .padding(.top, 16)
                .accessibilityIdentifier("onboardingContinue")
        }
        .background(AB.primary.ignoresSafeArea())
        .gesture(DragGesture(minimumDistance: 30).onEnded { if $0.translation.width < -30 { next() } })
    }

    @ViewBuilder
    private var graphic: some View {
        switch page {
        case 1:
            ZStack(alignment: .topLeading) {
                Image("obGraphic1").resizable().frame(width: 390, height: 260)
                HStack {
                    Text("Departure").outfitText(16, .semibold, AB.ice.opacity(0.75))
                    Spacer()
                    Text("Layover").outfitText(16, .semibold, AB.ice)
                    Spacer()
                    Text("Destination").outfitText(16, .semibold, AB.ice.opacity(0.75))
                }
                .frame(width: 371)
                .offset(x: 9, y: 148)
            }
            .frame(width: 390, height: 260)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Departure, layover, destination")
        case 2:
            VStack(alignment: .leading, spacing: 14) {
                TicketCard(flight: SampleJourney.outbound, previous: SampleJourney.inbound)
                    .frame(width: 370)
                    .scaleEffect(310 / 370, anchor: .topLeading)
                    .frame(width: 310, height: 288, alignment: .topLeading)
                    .allowsHitTesting(false)
                HStack(spacing: 5) {
                    TimeChip(text: durationText((SampleJourney.outbound.gateCloses ?? SampleJourney.gateArrivalTarget) - SampleJourney.now))
                        .fixedSize()
                    Text("before").outfitText(17, .regular, AB.muted).fixedSize()
                    GateSign(gate: SampleJourney.outbound.departureGate, size: 15).fixedSize()
                    Text("closes.").outfitText(17, .regular, AB.muted).fixedSize()
                }
                .scaleEffect(0.95, anchor: .leading)
            }
            .padding(16)
            .background(Color(hex: 0xF3F6F9), in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 30)
            .padding(.top, 33)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your ticket, with the time before your gate closes")
        default:
            ZStack(alignment: .topLeading) {
                Image("obGraphic3").resizable().frame(width: 342, height: 150)
                Text("You").outfitText(14, .semibold, AB.ice.opacity(0.8)).offset(x: 17, y: 94)
                Text("Your gate").outfitText(14, .semibold, AB.ice.opacity(0.8))
                    .frame(width: 106, alignment: .trailing).offset(x: 224, y: 94)
                Text("At your pace").outfitText(12, .semibold, AB.ice)
                    .frame(width: 91, height: 27).offset(x: 123, y: 46.5)
            }
            .frame(width: 342, height: 150)
            .padding(.horizontal, 30)
            .padding(.top, 133)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("From you to your gate, at your pace")
        }
    }
}
