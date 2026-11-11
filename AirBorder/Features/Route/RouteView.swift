import AVFoundation
import SwiftUI

/// Figma "Route" (858:10477) with Map and Camera views sharing the route step (862:16974).
struct RouteView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @State private var mode: Mode = .map
    @State private var showsMapInfo = false

    enum Mode { case map, camera }

    static let steps = ["Follow the Gates 105–109 sign", "Gate 105 ahead", "Check your flight"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Route to Gate \(SampleJourney.outbound.departureGate)").outfitText(30, .bold).tracking(-1.1)
                    .accessibilityAddTraits(.isHeader)
                modeSwitch
                if mode == .map {
                    summary
                    concourse
                } else {
                    CameraPanel().frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                RouteStepCard(step: $store.routeStep, texts: Self.steps) {
                    store.routeStep = 1
                    mode = .map
                    store.tab = .flight
                    let flight = SampleJourney.outbound
                    store.showToast(ToastMessage(text: "Arrived, Gate \(flight.departureGate), \(flight.number), boarding \(SampleJourney.boarding)."))
                }
                HStack {
                    Spacer()
                    TextLink(title: "See route options") { open(.routeOptions) }
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 54)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(AB.screen.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            segment("Map", .map)
            segment("Camera", .camera)
        }
        .padding(4)
        .background(.white.opacity(0.7), in: Capsule())
    }

    private func segment(_ title: String, _ value: Mode) -> some View {
        let selected = mode == value
        return Button { mode = value } label: {
            Text(title).outfitText(14, .semibold, selected ? .white : AB.primary)
                .frame(maxWidth: .infinity, minHeight: 47)
                .background(selected ? AB.primary : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mode-\(title.lowercased())")
    }

    private var summary: some View {
        HStack(spacing: 8) {
            Image("icWalkNavy").resizable().frame(width: 22, height: 22)
            ZStack {
                Image("routeDots").resizable().frame(height: 2)
                TimeChip(text: "\(store.gateWalkMinutes) min")
            }
            .frame(maxWidth: .infinity)
            GateSign(gate: SampleJourney.outbound.departureGate)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.gateWalkMinutes) minute walk to Gate \(SampleJourney.outbound.departureGate)")
        .accessibilityIdentifier("routeSummary")
    }

    private var concourse: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("T3, 3F").outfitText(12, .medium, AB.ticket)
            ZStack(alignment: .topLeading) {
                Image("concourseFrame").resizable().frame(width: 342, height: 48)
                Text(SampleJourney.outbound.departureGate).outfitText(12, .bold, AB.ticket).offset(x: 150, y: -12)
                Image("concourseCurrent").resizable().frame(width: 18, height: 18)
                    .offset(markerOffset)
                    .animation(.easeInOut, value: store.routeStep)
                    .accessibilityLabel("You are at step \(store.routeStep)")
            }
            .frame(width: 342, height: 48, alignment: .topLeading)
            HStack {
                Text("105–109").outfitText(12, .bold, AB.ticket)
                Spacer()
                Text("108–149").outfitText(12, .bold, AB.ticket)
            }
            .frame(width: 342)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 106)
        .background(AB.card, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { showsMapInfo = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("About this map")
        .sheet(isPresented: $showsMapInfo) { Sheets.aboutMap(walk: store.gateWalkMinutes) }
    }

    private var markerOffset: CGSize {
        switch store.routeStep {
        case 1: return CGSize(width: 9, height: 27)
        case 2: return CGSize(width: 80, height: 27)
        default: return CGSize(width: 141, height: 27)
        }
    }
}

/// Figma "Integrated route step": progress, instruction, Previous / Next step / End.
struct RouteStepCard: View {
    @Binding var step: Int
    let texts: [String]
    let end: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 0) {
                ForEach(1 ... texts.count, id: \.self) { index in
                    Text("\(index)")
                        .outfitText(13, .bold, index <= step ? AB.gateText : AB.ice.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(index == step ? AB.gateYellow : (index < step ? AB.sky.opacity(0.9) : AB.ice.opacity(0.12)), in: Circle())
                    Rectangle().fill(index < step ? AB.sky.opacity(0.9) : AB.ice.opacity(0.18)).frame(height: 2)
                }
                Image("icGateStep").resizable().frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
                    .background(AB.ice.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step) of \(texts.count)")
            Text(texts[step - 1]).outfitText(22, .bold, AB.gateYellow)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                .accessibilityIdentifier("routeInstruction")
            HStack(spacing: step == texts.count ? 18 : 8) {
                if step > 1 {
                    CTAButton(title: "Previous", style: .translucent) { step -= 1 }
                        .accessibilityIdentifier("previousStep")
                }
                if step < texts.count {
                    Button { step += 1 } label: {
                        HStack(spacing: 9) {
                            Text("Next step").outfitText(14, .semibold)
                            Image("icArrowRightNavy").resizable().frame(width: 21, height: 21)
                        }
                        .frame(maxWidth: .infinity, minHeight: 47)
                        .background(AB.ice, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nextStep")
                } else {
                    CTAButton(title: "End", action: end).accessibilityIdentifier("endRoute")
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// Live camera behind the route step. Frames stay on the device.
struct CameraPanel: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        ZStack {
            AB.ticket
            switch status {
            case .authorized where AVCaptureDevice.default(for: .video) != nil:
                CameraPreview()
            case .notDetermined:
                message("Turn on the camera to see directions in front of you.", button: "Allow camera") {
                    Task {
                        _ = await AVCaptureDevice.requestAccess(for: .video)
                        status = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            case .authorized:
                message("No camera on this device. Use Map for directions.")
            default:
                message("Camera access is off. You can turn it on in Settings.", button: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .accessibilityIdentifier("cameraPanel")
    }

    private func message(_ text: String, button: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 16) {
            Text(text).outfitText(15, .regular, AB.ice).multilineTextAlignment(.center)
            if let button, let action {
                CTAButton(title: button, style: .light, fullWidth: false, action: action)
            }
        }
        .padding(24)
    }
}

private struct CameraPreview: UIViewRepresentable {
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        let session = AVCaptureSession()
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = view.session
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           view.session.canAddInput(input) {
            view.session.addInput(input)
            let session = view.session
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
        let session = uiView.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }
}

/// Figma "Choose a route" (997:31030).
struct RouteOptionsView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openDestination) private var open

    var body: some View {
        SubScreen {
            HeaderWithBack(title: "Choose a route") { dismiss() }
            GateChip()
            Text("your gate · Terminal \(SampleJourney.outbound.departureTerminal)").outfitText(15, .regular, AB.secondary)
            ForEach(RouteChoice.allCases, id: \.self) { choice in
                InfoCard(padding: 16, radius: 16) {
                    Text("\(choice.title) · \(store.gateWalkMinutes(for: choice)) min").outfitText(18, .bold)
                    Text(choice.detail).outfitText(15, .regular, AB.secondary)
                }
                CTAButton(title: "Use \(choice.title.lowercased()) route", style: store.routeChoice == choice ? .filled : .outline) {
                    if choice == .direct {
                        store.routeChoice = choice
                        store.routeStep = 1
                        dismiss()
                    } else {
                        open(.routeDetail(choice))
                    }
                }
                .accessibilityIdentifier("use-\(choice.rawValue)")
            }
            CTAButton(title: "Other map apps", style: .outline) { open(.openAnotherMap) }
        }
    }
}
