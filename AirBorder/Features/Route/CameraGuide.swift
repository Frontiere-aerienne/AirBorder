import AVFoundation
import SwiftUI
import Vision

/// A sign the camera looks for while guiding the traveller (Figma "Camera navigation").
struct SignTarget: Equatable {
    /// "gate", "bus" or "lounge sign": used in "We couldn't read the gate sign."
    let kind: String
    /// Header while scanning, e.g. "Scan the gate sign".
    let scanTitle: String
    /// What the sign says, as printed at Haneda: "搭乗口 / Gates 105–109".
    let label: String
    /// Text that identifies the sign once read.
    let tokens: [String]

    static let gates105to109 = SignTarget(kind: "gate", scanTitle: "Scan the gate sign", label: "搭乗口 / Gates 105–109", tokens: ["105-109"])
    static let gates108to149 = SignTarget(kind: "gate", scanTitle: "Scan the gate sign", label: "搭乗口 / Gates 108–149", tokens: ["108-149"])
    static let bus = SignTarget(kind: "bus", scanTitle: "Reading the bus sign", label: "Bus, 2F access hall", tokens: ["BUS", "バス"])
    static let lounges = SignTarget(kind: "lounge", scanTitle: "Scan the lounge sign", label: "航空会社ラウンジ / Airline lounges", tokens: ["LOUNGE", "ラウンジ"])
}

enum SignMatcher {
    /// True when any recognised line contains one of the sign's tokens. Dashes and spaces are ignored.
    static func matches(_ lines: [String], _ target: SignTarget) -> Bool {
        let text = lines.map(normalise).joined(separator: "\n")
        return target.tokens.map(normalise).contains { text.contains($0) }
    }

    private static func normalise(_ value: String) -> String {
        value.uppercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "〜", with: "-")
            .replacingOccurrences(of: " ", with: "")
    }
}

/// Live back-camera preview that can read signs on this iPhone with Vision. Nothing leaves the device.
@MainActor
final class SignCamera: NSObject, ObservableObject {
    enum ScanResult { case found, notFound }

    let session = AVCaptureSession()
    @Published private(set) var hasCamera = false
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "airborder.sign-camera")
    private var target: SignTarget?
    private var completion: ((ScanResult) -> Void)?
    private var deadline: Date?
    private var lastRead = Date.distantPast
    private var configured = false

    /// How long to look for a sign before saying it could not be read.
    static let scanTimeout: TimeInterval = 10

    func start() {
        configureIfNeeded()
        guard hasCamera else { return }
        let session = session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
        cancelScan()
    }

    /// Looks for the sign in the camera feed; reports `.notFound` after `scanTimeout`.
    func scan(for target: SignTarget, completion: @escaping (ScanResult) -> Void) {
        self.target = target
        self.completion = completion
        deadline = Date().addingTimeInterval(Self.scanTimeout)
        if !hasCamera {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.scanTimeout))
                self.finish(.notFound)
            }
        }
    }

    func cancelScan() {
        target = nil
        completion = nil
        deadline = nil
    }

    private func finish(_ result: ScanResult) {
        guard let completion else { return }
        cancelScan()
        completion(result)
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: queue)
        }
        session.commitConfiguration()
        hasCamera = true
    }

    fileprivate func read(_ lines: [String]) {
        guard let target else { return }
        if SignMatcher.matches(lines, target) {
            finish(.found)
        } else if let deadline, Date() > deadline {
            finish(.notFound)
        }
    }

    fileprivate var isScanning: Bool { target != nil }
}

extension SignCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in
            guard self.isScanning, Date().timeIntervalSince(self.lastRead) > 0.5 else { return }
            self.lastRead = Date()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.recognitionLanguages = ["en-US", "ja-JP"]
            let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .right)
            let lines: [String] = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    try? handler.perform([request])
                    continuation.resume(returning: (request.results ?? []).compactMap { $0.topCandidates(1).first?.string })
                }
            }
            self.read(lines)
        }
    }
}

/// Camera preview inside the rounded Figma "Camera corridor background" frame.
struct SignCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Figma camera guidance: live view with the step's arrow, the step card, Read sign again and Exit camera
/// (858:10985, 858:11007, 858:11029), scanning (858:11061, 858:11487) and Can't read the sign (858:11050).
struct CameraGuide<StepCard: View>: View {
    enum Phase { case guide, scanning, failed }

    let sign: SignTarget
    var arrow = "camArrowForward"
    var readAgainTitle = "Read sign again"
    var readAgainFullWidth = false
    let exit: () -> Void
    /// True while Camera guidance or Can't read the sign fills the screen (the route title and switch hide).
    @Binding var covers: Bool
    @ViewBuilder let stepCard: StepCard

    @StateObject private var camera = SignCamera()
    @State private var phase: Phase = .guide
    @State private var status = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch (status, phase) {
            case (.notDetermined, _): access
            case (_, .failed): failed
            default: guidance
            }
        }
        .onAppear {
            if status == .authorized { camera.start() }
            updateCovers()
        }
        .onDisappear {
            camera.stop()
            covers = false
        }
        .onChange(of: phase) { updateCovers() }
        .onChange(of: status) { updateCovers() }
    }

    // MARK: Camera guidance (access, 858:10975)

    private var access: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Camera guidance").outfitText(30, .bold).tracking(-1.1).accessibilityAddTraits(.isHeader)
            navyCard(title: "Find the next sign", detail: "Point your camera at the overhead \(sign.label.components(separatedBy: " / ").last ?? sign.label) sign.", titleSize: 20)
            centered("Allow camera", filled: true, id: "allowCamera") {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: .video)
                    status = AVCaptureDevice.authorizationStatus(for: .video)
                    if status == .authorized { camera.start() }
                }
            }
            centered("Use map instead", filled: false, id: "useMapInstead", action: exit)
        }
    }

    // MARK: Guidance and scanning

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            if phase == .scanning {
                navyCard(title: sign.scanTitle, detail: sign.label, titleSize: 17)
                    .accessibilityIdentifier("scanningSign")
            }
            ZStack {
                AB.ticket
                if camera.hasCamera {
                    SignCameraPreview(session: camera.session)
                } else {
                    Text(status == .authorized ? "No camera on this device. Use Map for directions." : "Camera access is off. You can turn it on in Settings.")
                        .outfitText(15, .regular, AB.ice).multilineTextAlignment(.center).padding(24)
                }
                if phase == .scanning {
                    Image("camScanTarget").resizable().frame(width: 200, height: 90)
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 20)
                        .accessibilityHidden(true)
                } else if camera.hasCamera {
                    Image(arrow).resizable().frame(width: 160, height: 60)
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 18)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .accessibilityIdentifier("cameraView")
            if phase == .guide {
                stepCard
                if readAgainFullWidth {
                    CTAButton(title: readAgainTitle, style: .light, height: 48, action: scan)
                        .accessibilityIdentifier("readSignAgain")
                } else {
                    centered(readAgainTitle, filled: false, id: "readSignAgain", action: scan)
                }
            }
            if status != .authorized {
                CTAButton(title: "Open Settings", style: .outline, height: 47) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            exitButton
        }
    }

    // MARK: Can't read the sign (858:11050)

    private var failed: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Can't read the sign").outfitText(30, .bold).tracking(-1.1).accessibilityAddTraits(.isHeader)
            navyCard(title: "We couldn't read the \(sign.kind) sign.", detail: "Use the saved route, or scan the sign again.", titleSize: 20)
            centered("Use map", filled: true, id: "useMap", action: exit)
            centered("Try again", filled: false, id: "tryAgain", action: scan)
        }
    }

    private func updateCovers() {
        covers = status == .notDetermined || phase == .failed
    }

    private func scan() {
        phase = .scanning
        camera.scan(for: sign) { result in
            phase = result == .found ? .guide : .failed
        }
    }

    private var exitButton: some View {
        Button {
            camera.cancelScan()
            phase = .guide
            exit()
        } label: {
            Text("Exit camera").outfitText(14, .semibold, .white)
                .frame(width: 158, height: 47)
                .background(AB.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exitCamera")
    }

    private func navyCard(title: String, detail: String, titleSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: titleSize > 17 ? 14 : 6) {
            Text(title).outfitText(titleSize, .bold, AB.gateYellow)
            Text(detail).outfitText(titleSize > 17 ? 16 : 13, .regular, AB.ice.opacity(0.85))
        }
        .padding(titleSize > 17 ? 20 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AB.ticket, in: RoundedRectangle(cornerRadius: titleSize > 17 ? 20 : 16))
        .accessibilityElement(children: .combine)
    }

    private func centered(_ title: String, filled: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).outfitText(15, .semibold, filled ? .white : AB.navy)
                .frame(width: 200, height: 52)
                .background(filled ? AB.primary : .white, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(id)
    }
}
