import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared layout for the ticket camera screens (Figma 997:31885–31910)

private struct InfoStepScreen<Extra: View>: View {
    let title: String
    let message: String
    var primary: (String, () -> Void)?
    var secondary: [(String, () -> Void)] = []
    @ViewBuilder var extra: Extra
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 20, top: 48) {
            BackButton { dismiss() }
            Text(title).outfitText(28, .bold).accessibilityAddTraits(.isHeader)
            InfoCard { Text(message).outfitText(16, .regular) }
            extra
            if let primary {
                CTAButton(title: primary.0, action: primary.1).accessibilityIdentifier(primary.0)
            }
            ForEach(Array(secondary.enumerated()), id: \.offset) { _, item in
                Button(action: item.1) {
                    Text(item.0).outfitText(13, .regular)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(AB.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(item.0)
            }
        }
    }
}

extension InfoStepScreen where Extra == EmptyView {
    init(title: String, message: String, primary: (String, () -> Void)? = nil, secondary: [(String, () -> Void)] = []) {
        self.init(title: title, message: message, primary: primary, secondary: secondary) { EmptyView() }
    }
}

/// Figma "Camera permission" (997:31885).
struct CameraPermissionView: View {
    @Environment(\.openDestination) private var open

    var body: some View {
        InfoStepScreen(
            title: "Scan your ticket",
            message: "Use your camera to capture your ticket. Review the flight details before saving.",
            primary: ("Continue", {
                Task { @MainActor in
                    let granted = await AVCaptureDevice.requestAccess(for: .video)
                    let hasCamera = AVCaptureDevice.default(for: .video) != nil
                    open(granted && hasCamera ? .ticketCamera : .cameraUnavailable)
                }
            }),
            secondary: [("Not now", { open(.cameraUnavailable) })]
        )
    }
}

/// Figma "Camera unavailable" (997:31895).
struct CameraUnavailableView: View {
    @Environment(\.popTo) private var popTo
    @Environment(\.openURL) private var openURL

    var body: some View {
        InfoStepScreen(
            title: "Camera unavailable",
            message: "Allow camera access in your device settings, or choose another way to add your flight.",
            primary: ("Try again", {
                if AVCaptureDevice.authorizationStatus(for: .video) == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                } else {
                    popTo(.cameraPermission)
                }
            }),
            secondary: [("Other import options", { popTo(.importFlight) })]
        )
    }
}

/// Figma "Ticket camera" (997:31890): live camera inside the ticket frame.
struct TicketCameraView: View {
    @Environment(\.openDestination) private var open
    @StateObject private var camera = TicketCamera()
    @State private var reading = false

    var body: some View {
        InfoStepScreen(
            title: "Capture your ticket",
            message: "Place the whole ticket inside the frame. Keep the flight number and date readable.",
            primary: (reading ? "Reading your ticket…" : "Take photo", takePhoto)
        ) {
            ZStack {
                AB.card
                if camera.isRunning {
                    TicketCameraPreview(session: camera.session)
                } else {
                    Text("Ticket within frame").outfitText(18, .regular)
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(AB.primary, lineWidth: 1))
            .accessibilityLabel("Ticket within frame")
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func takePhoto() {
        guard !reading else { return }
        reading = true
        Task { @MainActor in
            defer { reading = false }
            guard let photo = await camera.capture() else { return open(.cameraUnavailable) }
            if let ticket = await TicketReader.read(photo: photo), ticket.date != nil {
                open(.capturedReview(ticket))
            } else {
                open(.unreadableTicket)
            }
        }
    }
}

/// Figma "Unreadable ticket" (997:31900).
struct UnreadableTicketView: View {
    @Environment(\.openDestination) private var open
    @Environment(\.popTo) private var popTo

    var body: some View {
        InfoStepScreen(
            title: "Try another photo",
            message: "We could not read the flight number or date. Flatten the ticket and avoid glare.",
            primary: ("Retake photo", { popTo(.ticketCamera) }),
            secondary: [("Add manually", { open(.manualEntry) })]
        )
    }
}

/// Figma "Captured review" (997:31905).
struct CapturedReviewView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.popTo) private var popTo
    let ticket: ParsedTicket

    var body: some View {
        let line = [ticket.number.replacingOccurrences(of: " ", with: ""), ticket.route].compactMap { $0 }.joined(separator: " · ")
        InfoStepScreen(
            title: "Review your flight",
            message: "From your ticket\n\(line)\nCheck the flight date, time and gate before saving.",
            primary: ("Review and edit details", { open(.reviewImported(ticket)) }),
            secondary: [
                ("Save flight", { save() }),
                ("Retake", { popTo(.ticketCamera) }),
            ]
        )
    }

    private func save() {
        if let date = ticket.date { store.addManualFlight(ManualFlight(number: ticket.number, date: date)) }
        open(.ticketSaved)
    }
}

/// Figma "Ticket saved" (997:31910).
struct TicketSavedView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.popToRoot) private var popToRoot

    var body: some View {
        InfoStepScreen(
            title: "Flight added",
            message: "Your flight is ready. Open the journey to review its gate and travel plan.",
            primary: ("Open flight", {
                popToRoot()
                store.tab = .flight
            })
        )
    }
}

// MARK: - PDF, Wallet and Google (Figma 858:11697–858:11831)

/// Figma "Choose a PDF" (858:11697). Reads the PDF's text on this iPhone.
struct ChoosePDFView: View {
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var picked: (name: String, ticket: ParsedTicket?)?

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Choose a PDF") { dismiss() }
            Button { importing = true } label: {
                HStack(spacing: 14) {
                    Image("tileInfo").resizable().frame(width: 18, height: 18)
                        .frame(width: 36, height: 36)
                        .background(AB.sky.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(picked?.name ?? "Choose from Files").outfitText(16, .semibold).lineLimit(1)
                        Text(summary).outfitText(13, .regular, picked != nil && picked?.ticket == nil ? AB.removeRed : AB.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("PDF").outfitText(12, .semibold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(AB.sky.opacity(0.25), in: Capsule())
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pickPDF")
            if let ticket = picked?.ticket {
                CenteredButton(title: "Use this PDF") { open(.reviewImported(ticket)) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            guard case let .success(url) = result else { return }
            picked = (url.lastPathComponent, TicketReader.read(pdf: url))
        }
    }

    private var summary: String {
        guard let picked else { return "Ticket or itinerary" }
        guard let ticket = picked.ticket else { return "No flight number found in this PDF" }
        return [ticket.number, ticket.route, ticket.date.map { TripDate.format($0, "d MMM") }].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Figma "Import from Wallet" (858:11712).
struct ImportWalletView: View {
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss
    @State private var noPass = false

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Import from Wallet") { dismiss() }
            VStack(alignment: .leading, spacing: 0) {
                step(1, "Open your boarding pass in Wallet", line: true)
                step(2, "Tap Share", line: true)
                step(3, "Choose AirBorder", line: false)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
            Text("No share button? Use the airline PDF instead.").outfitText(13, .regular, AB.muted)
            CenteredButton(title: "Choose shared pass") { noPass = true }
            CenteredButton(title: "Use a PDF instead", filled: false) { open(.choosePDF) }
        }
        .alert("No boarding pass shared yet", isPresented: $noPass) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("AirBorder can't receive Wallet passes yet. Use the airline PDF instead.")
        }
    }

    private func step(_ number: Int, _ text: String, line: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(number)").outfitText(13, .bold)
                    .frame(width: 26, height: 26)
                    .background(AB.sky.opacity(0.35), in: Circle())
                if line { Rectangle().fill(AB.primary.opacity(0.25)).frame(width: 2, height: 12) }
            }
            Text(text).outfitText(15, .semibold).padding(.top, 3)
        }
    }
}

/// Figma "Connect Gmail" (858:11768) and "Connect Calendar" (858:11808).
struct ConnectGoogleView: View {
    @Environment(\.dismiss) private var dismiss
    let calendar: Bool
    @State private var unavailable = false

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: calendar ? "Connect Calendar" : "Connect Gmail") { dismiss() }
            GroupedList {
                row("tileShield", calendar ? "Reads flight events only" : "Reads booking emails only")
                RowDivider()
                row("icCheckList", calendar ? "Your calendar stays unchanged" : "You choose what to add")
                RowDivider()
                row("tileInfo", "Disconnect any time", detail: "In Profile")
            }
            Button { unavailable = true } label: {
                HStack(spacing: 9) {
                    Text("G").outfitText(14, .bold, AB.primary)
                        .frame(width: 21, height: 21)
                        .background(.white, in: Circle())
                    Text("Continue with Google").outfitText(15, .semibold, .white)
                }
                .padding(.horizontal, 17)
                .frame(minHeight: 52)
                .background(AB.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue with Google")
            .frame(maxWidth: .infinity)
        }
        .alert("Google sign-in isn't available yet", isPresented: $unavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add your flight with a PDF, your camera or Add manually.")
        }
    }

    private func row(_ icon: String, _ title: String, detail: String? = nil) -> some View {
        HStack(spacing: 14) {
            Image(icon).resizable().frame(width: 18, height: 18)
                .frame(width: 36, height: 36)
                .background(AB.sky.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).outfitText(16, .semibold)
                if let detail { Text(detail).outfitText(13, .regular, AB.muted) }
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

// MARK: - Review imported flight (858:11849), Flight updated (858:11884), Review flight (858:10603)

struct ReviewImportedView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss
    let ticket: ParsedTicket

    var body: some View {
        let isTrip = ticket.number == store.tripFlight.number
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Check flight details") { dismiss() }
            if isTrip {
                HStack(spacing: 6) {
                    Image("icCheckList").resizable().frame(width: 14, height: 14)
                    Text("Already saved").outfitText(12, .semibold)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(AB.card, in: Capsule())
                TicketSummary(number: ticket.number, pill: durationText(SampleJourney.outbound.durationMinutes ?? 0),
                              from: "HND", to: "LAX", departs: "18:00", arrives: "11:45")
            } else {
                TicketSummary(number: ticket.number, from: ticket.from ?? "–", to: ticket.to ?? "–",
                              pills: ticket.date.map { [TripDate.format($0, "d MMM yyyy")] } ?? [])
            }
            HStack(spacing: 14) {
                Image("tileInfo").resizable().frame(width: 18, height: 18)
                    .frame(width: 36, height: 36)
                    .background(AB.sky.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ticket.source).outfitText(16, .semibold).lineLimit(1)
                    Text(ticket.route == nil ? "Flight number and date" : "Flight number, route and date").outfitText(13, .regular, AB.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(AB.card, in: RoundedRectangle(cornerRadius: 18))
            if isTrip {
                CenteredButton(title: "Update existing flight") {
                    if let date = ticket.date {
                        store.flightDraft = store.tripFlight
                        store.flightDraft.date = date
                        store.saveFlightDraft()
                    }
                    open(.flightUpdated)
                }
                CenteredButton(title: "Review saved flight details", filled: false) { open(.reviewFlight) }
            } else if let date = ticket.date {
                CenteredButton(title: "Save flight") {
                    store.addManualFlight(ManualFlight(number: ticket.number, date: date))
                    open(.ticketSaved)
                }
            }
            CenteredButton(title: "Edit flight details", filled: false) {
                if isTrip {
                    store.beginEditingFlight()
                    open(.editFlight)
                } else {
                    open(.manualEntry)
                }
            }
        }
    }
}

struct FlightUpdatedView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.popTo) private var popTo
    @Environment(\.popToRoot) private var popToRoot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubScreen(spacing: 16, top: 52) {
            StackedHeader(title: "Flight updated") { dismiss() }
            TicketSummary(number: store.tripFlight.number, pill: "Updated", from: "HND", to: "LAX", departs: "18:00", arrives: "11:45")
            Text("Your gate alerts and ticket details are unchanged.").outfitText(13, .regular, AB.muted)
            CenteredButton(title: "View Journey") {
                popToRoot()
                store.tab = .flight
            }
            CenteredButton(title: "Import another flight", filled: false) { popTo(.importFlight) }
        }
    }
}

struct ReviewFlightView: View {
    @EnvironmentObject private var store: JourneyStore
    @Environment(\.openDestination) private var open
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let flight = SampleJourney.outbound
        FlightStack {
            LargeTitleHeader(title: "Review flight") { dismiss() }
            VStack(alignment: .leading, spacing: 14) {
                TicketSummary(number: store.tripFlight.number, pill: flight.cabin, from: "HND", to: "LAX", departs: "18:00", arrives: "11:45")
                HStack(spacing: 6) {
                    TerminalSign(terminal: flight.departureTerminal)
                    GateSign(gate: flight.departureGate)
                    Text("closes").outfitText(14, .regular, AB.ice.opacity(0.75))
                    TimeChip(text: flight.gateCloses?.description ?? "–")
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
            .background(AB.ticket, in: RoundedRectangle(cornerRadius: 20))
            AllowanceCard(checked: store.extraBagDeclared ? "2 × 32 kg" : "1 × 32 kg")
            CenteredButton(title: "Save flight to Journey") {
                store.flightDraft = store.tripFlight
                store.saveFlightDraft()
                open(.flightSaved)
            }
            CenteredButton(title: "Edit flight", filled: false) {
                store.beginEditingFlight()
                open(.editFlight)
            }
        }
    }
}

// MARK: - Camera capture

@MainActor
final class TicketCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    @Published private(set) var isRunning = false

    func start() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.inputs.isEmpty, session.canAddInput(input) { session.addInput(input) }
        if session.outputs.isEmpty, session.canAddOutput(output) { session.addOutput(output) }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        isRunning = true
    }

    func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
        isRunning = false
    }

    func capture() async -> UIImage? {
        guard isRunning else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            continuation?.resume(returning: image)
            continuation = nil
        }
    }
}

private struct TicketCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let layer = view.layer as! AVCaptureVideoPreviewLayer
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
